<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Policies\CompteComptablePolicy;
use App\Domain\Comptabilite\Policies\EcritureComptablePolicy;
use App\Domain\Comptabilite\Policies\ExerciceComptablePolicy;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\GrandLivreService;
use App\Domain\Comptabilite\Services\JournalGeneralService;
use App\Domain\Comptabilite\Services\PorteeEcrituresService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route as RouteFacade;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M10 — Comptabilité SYSCOHADA révisé. Les quatre pages fondatrices :
 * `m10-plan-comptable.html`, `m10-journal.html`, `m10-grand-livre.html`,
 * `m10-balance.html`.
 *
 * @see EF-M10-01 Plan comptable conforme SYSCOHADA révisé
 * @see EF-M10-06 Édition des états réglementaires SYSCOHADA
 * @see RG-11 Immutabilité et contre-passation
 * @see RG-12 Centre de coût obligatoire
 * @see RG-16 RBAC de 2ᵉ niveau
 *
 * ## Ce que cette suite existe pour empêcher
 *
 * 1. **Qu'un solde inconnu se rende en `0`.** Le report à nouveau n'existe
 *    nulle part dans ce dépôt : le solde d'ouverture d'un compte est INCONNU.
 *    Rendre zéro affirmerait que le compte partait de rien au premier jour de
 *    l'exercice, sur l'écran même où un comptable lit un solde (PA-126,
 *    Article 7 de la directive de conformité).
 * 2. **Qu'un état prétende plus qu'il ne sait.** `equilibre` porte sur
 *    l'ensemble affiché, jamais sur chaque pièce : `ecritures_comptables` n'a
 *    aucun identifiant de pièce (PA-52). Un cas le prouve en insérant une ligne
 *    hors du service — ce que ferait un import — et en vérifiant que l'API
 *    l'avoue.
 * 3. **Qu'un état perde sa portée d'exercice.** Aucune route ne sait produire
 *    un état « toutes années confondues » : le paramètre est obligatoire, et un
 *    cas vérifie qu'un exercice ne fuit pas dans l'autre.
 * 4. **Qu'une route perde sa garde RBAC** (PA-65). Les rôles sont dérivés de
 *    `RolePermissionSeeder::MATRICE`, jamais écrits en dur.
 * 5. **Qu'une suppression apparaisse.** RG-11 refuse toute suppression, même en
 *    brouillon. Le verbe non routé (405) est la seule preuve solide.
 * 6. **Qu'un total soit sommé en flottant.** Un cas construit exactement le
 *    piège d'arrondi que `bccomp` évite et que `==` ne verrait pas.
 */
final class ApiComptabiliteTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $exercice2026;

    /** Un exercice CLOS : ses états restent consultables, c'est leur raison d'être. */
    private ExerciceComptable $exercice2025;

    private JournalComptable $vte;

    private JournalComptable $ach;

    private JournalComptable $od;

    private CentreCout $structure;

    private CompteComptable $banque;

    private CompteComptable $ventesHebergement;

    private CompteComptable $achatsDenrees;

    private CompteComptable $clients;

    /** Jamais mouvementé : il ne doit apparaître ni au sélecteur, ni à la balance. */
    private CompteComptable $capitalJamaisMouvemente;

    /** `nature` NULLE : le référentiel est incomplet, et cela se compte. */
    private CompteComptable $sansNature;

    /** Classe 8 (HAO) : le schéma l'admet, l'écran n'a aucun bouton pour l'atteindre. */
    private CompteComptable $horsEcran;

    /** Mémoïsé : les fixtures en ont besoin avant que le test ne s'authentifie. */
    private ?User $comptable = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->comptable());

        $this->exercice2026 = $this->exercice(2026, 'ouvert');
        $this->exercice2025 = $this->exercice(2025, 'cloture');

        $this->vte = JournalComptable::create(['code' => 'VTE', 'libelle' => 'Ventes']);
        $this->ach = JournalComptable::create(['code' => 'ACH', 'libelle' => 'Achats']);
        $this->od = JournalComptable::create(['code' => 'OD', 'libelle' => 'Opérations diverses']);

        $this->structure = CentreCout::create(['libelle' => 'Structure', 'type' => 'support']);

        $this->banque = $this->compte('521000', 'Banque — compte principal', '5', 'actif');
        $this->ventesHebergement = $this->compte('706100', "Prestations d'hébergement", '7', 'produit');
        $this->achatsDenrees = $this->compte('601100', 'Achats denrées alimentaires', '6', 'charge');
        $this->clients = $this->compte('4111', 'Clients', '4', 'actif');
        $this->capitalJamaisMouvemente = $this->compte('101000', 'Capital social', '1', 'passif');
        $this->sansNature = $this->compte('231000', 'Bâtiments', '2', null);
        $this->horsEcran = $this->compte('831000', 'Charges hors activités ordinaires', '8', 'charge');

        // --- Le grand livre de démonstration -------------------------------
        //
        // Trois pièces, toutes écrites par `enregistrerPiece()` : c'est le seul
        // chemin qui garantit l'équilibre (PA-52), et le faire emprunter par les
        // fixtures vérifie au passage qu'il fonctionne encore.

        // 1. Vente encaissée en banque — VALIDÉE.
        $this->piece($this->vte, '2026-07-10', 'Hébergement — Agence Bénin Tour', [
            ['compte' => $this->banque, 'debit' => '184000.00'],
            ['compte' => $this->ventesHebergement, 'credit' => '184000.00'],
        ], validee: true);

        // 2. Achat réglé en banque — VALIDÉE. Antérieure à la vente : elle
        //    permet au solde progressif du compte 521000 de passer par une
        //    valeur NÉGATIVE, seul moyen d'éprouver le sens créditeur.
        $this->piece($this->ach, '2026-07-08', 'Réapprovisionnement denrées cuisine', [
            ['compte' => $this->achatsDenrees, 'debit' => '132000.00'],
            ['compte' => $this->banque, 'credit' => '132000.00'],
        ], validee: true);

        // 3. Vente à crédit — laissée en BROUILLON, pour que le filtre de
        //    statut ait quelque chose à exclure et que le décompte le dise.
        $this->piece($this->od, '2026-08-01', 'Solde à recevoir — Jean KORA', [
            ['compte' => $this->clients, 'debit' => '30000.00'],
            ['compte' => $this->ventesHebergement, 'credit' => '30000.00'],
        ], validee: false);

        // Un exercice VOISIN, mouvementé lui aussi : sans lui, aucun cas ne
        // prouverait que la portée d'exercice tient réellement.
        $this->piece($this->vte, '2025-05-12', 'Vente exercice précédent', [
            ['compte' => $this->banque, 'debit' => '999000.00'],
            ['compte' => $this->ventesHebergement, 'credit' => '999000.00'],
        ], validee: true, exercice: $this->exercice2025);
    }

    // ------------------------------------------------------- Authentification

    /**
     * Aucune des sept routes n'est publique. La liste est explicite : une route
     * ajoutée au groupe sans jeton passerait sinon inaperçue.
     */
    #[Test]
    public function aucune_route_de_comptabilite_n_est_accessible_sans_jeton(): void
    {
        // Les fixtures ont eu besoin d'un utilisateur authentifié — une écriture
        // porte obligatoirement son auteur (trait `Auditable`). Sans cette
        // ligne, ce test partirait AUTHENTIFIÉ et vérifierait donc l'inverse
        // exact de ce qu'il annonce. Même piège que PA-146 sur M4.
        $this->app['auth']->forgetGuards();

        $this->getJson('/api/v1/comptabilite/exercices')->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/journaux')->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/plan-comptable')->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/journal?' . $this->portee())->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/comptes-mouvementes?' . $this->portee())->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->banque))->assertUnauthorized();
        $this->getJson('/api/v1/comptabilite/balance?' . $this->portee())->assertUnauthorized();
    }

    // -------------------------------------------------------------------- RBAC

    /**
     * RG-16 — un rôle sans aucun accès à M10 est refusé sur les sept routes.
     * Le rôle est DÉRIVÉ de la matrice : l'écrire en dur ferait passer la suite
     * au vert le jour où elle changerait.
     */
    #[Test]
    public function rg16_un_role_sans_acces_a_m10_est_refuse_partout(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM10('-')));

        foreach ($this->septRoutes() as $url) {
            $this->getJson($url)->assertForbidden();
        }
    }

    /**
     * RG-16 — le rôle en LECTURE seule consulte les sept états.
     *
     * M10 n'a AUCUNE route d'écriture dans ce lot : le contraste habituel
     * « lit tout, n'écrit rien » ne peut pas être posé ici, et c'est le constat
     * lui-même qui est vérifié plus bas (`aucune_ecriture_n_est_exposee`).
     */
    #[Test]
    public function rg16_un_role_en_lecture_seule_consulte_les_sept_etats(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM10('L')));

        foreach ($this->septRoutes() as $url) {
            $this->getJson($url)->assertOk();
        }
    }

    /**
     * Le refus RBAC est traduit, jamais écrit en dur dans le middleware.
     */
    #[Test]
    public function rg16_le_refus_est_un_message_traduit(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM10('-')));

        $this->getJson('/api/v1/comptabilite/balance?' . $this->portee())
            ->assertForbidden()
            ->assertJsonPath('message', __('auth.module_refuse'));
    }

    /**
     * Garde STRUCTURELLE à liste fermée — chaque route du groupe `comptabilite`
     * déclare le niveau RBAC qu'elle exige, et la suite échoue tant qu'une route
     * nouvelle n'y est pas inscrite.
     *
     * ## Pourquoi un test de structure en plus des tests de comportement
     *
     * Sur un groupe entièrement en lecture, retirer `module:M10,L` d'une route
     * ne fait rougir AUCUN test de comportement autre que celui-ci : la route
     * resterait derrière `auth:sanctum`, donc accessible à tout utilisateur
     * authentifié — y compris un `barman`, pour qui M10 vaut `'-'`. Le trou
     * serait invisible. C'est exactement la forme de PA-65, et aucune de ces
     * sept routes n'a de `FormRequest` capable de rattraper le coup, les quatre
     * qui en ont un ne validant que des paramètres.
     */
    #[Test]
    public function rg16_chaque_route_du_groupe_comptabilite_porte_sa_garde_rbac(): void
    {
        $attendu = [
            // --- Socle (PA-148) ---
            'GET|HEAD api/v1/comptabilite/balance' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/comptes-mouvementes' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/exercices' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/grand-livre' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/journal' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/journaux' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/plan-comptable' => 'M10,L',

            // --- Etats derives de la Balance ---
            //
            // Toutes en LECTURE, comme le socle. Ce n'est pas un raccourci :
            // de ces sept ecrans du maitre, un seul porte un bouton et son
            // gestionnaire n'ecrit rien. `cloture` en particulier rend la
            // CHECKLIST de `m10-cloture.html`, page qui ne contient pas un
            // seul `addEventListener` — l'action de cloture n'est pas exposee,
            // et `aucune_ecriture_n_est_exposee` le prouve par le verbe.
            'GET|HEAD api/v1/comptabilite/analytique' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/bilan' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/centres-cout' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/cloture' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/compte-resultat' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/etats-financiers' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/indicateurs' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/notes-annexes' => 'M10,L',
            'GET|HEAD api/v1/comptabilite/tafire' => 'M10,L',
        ];

        $constate = [];

        foreach (RouteFacade::getRoutes()->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/v1/comptabilite/')) {
                continue;
            }

            $middlewares = $route->gatherMiddleware();

            $gardes = array_values(array_filter(
                $middlewares,
                fn (mixed $m): bool => is_string($m) && str_starts_with($m, 'module:'),
            ));

            $cle = implode('|', array_diff($route->methods(), ['HEAD'])) . ' ' . $route->uri();
            $cle = str_contains($cle, 'GET ') ? str_replace('GET ', 'GET|HEAD ', $cle) : $cle;

            $constate[$cle] = $gardes === []
                ? 'AUCUNE GARDE'
                : str_replace('module:', '', $gardes[0]);

            $this->assertContains(
                'auth:sanctum',
                $middlewares,
                "La route {$cle} est accessible sans authentification.",
            );
        }

        ksort($attendu);
        ksort($constate);

        $this->assertSame(
            $attendu,
            $constate,
            'Une route du groupe `comptabilite` a perdu sa garde RBAC, ou une route nouvelle n\'y est pas inscrite.',
        );
    }

    // ------------------------------------------------- RG-11 : aucune écriture

    /**
     * RG-11 — aucune suppression, aucune écriture. Le verbe non routé (405) est
     * la seule preuve solide qu'ils n'existent pas.
     *
     * M10 est le cas le plus strict du dépôt : une écriture ne se supprime
     * jamais, même en BROUILLON — un trou dans la séquence est précisément ce
     * qu'un contrôle fiscal recherche.
     */
    #[Test]
    public function rg11_aucune_ecriture_ni_suppression_n_est_exposee(): void
    {
        Sanctum::actingAs($this->comptable());

        foreach (['/journal', '/balance', '/grand-livre', '/plan-comptable', '/exercices', '/journaux'] as $chemin) {
            $url = '/api/v1/comptabilite' . $chemin;

            $this->postJson($url, [])->assertStatus(405);
            $this->putJson($url, [])->assertStatus(405);
            $this->patchJson($url, [])->assertStatus(405);
            $this->deleteJson($url)->assertStatus(405);
        }
    }

    /**
     * RG-11 — la garde réelle est l'`Observer`, et elle refuse la suppression
     * d'une écriture EN BROUILLON.
     *
     * Ce cas ne passe par aucune route : il vérifie que le verrou tient sur le
     * chemin qu'une future route, un job ou un import emprunteraient. Un
     * contrôle placé dans un service ne protégerait que les appelants qui
     * pensent à passer par lui (PA-100).
     */
    #[Test]
    public function rg11_une_ecriture_en_brouillon_ne_se_supprime_pas(): void
    {
        $brouillon = EcritureComptable::query()->where('statut', 'brouillon')->firstOrFail();

        $this->expectExceptionMessage(__('comptabilite.ecriture_suppression_interdite'));

        $brouillon->delete();
    }

    /**
     * Les trois `Policy` de M10 sont réellement DÉCOUVERTES malgré
     * l'arborescence DDD — vérifié, pas supposé.
     *
     * Elles sont délibérément REDONDANTES avec le middleware sur ces sept
     * routes de lecture : le verrou appliqué est celui de la route. Elles
     * existent pour tout appelant qui n'est pas une route — et c'est
     * précisément pour cela qu'un test doit prouver qu'elles se résolvent.
     */
    #[Test]
    public function rg16_les_policies_de_m10_sont_decouvertes_et_refusent_la_suppression(): void
    {
        $this->assertInstanceOf(EcritureComptablePolicy::class, Gate::getPolicyFor(EcritureComptable::class));
        $this->assertInstanceOf(CompteComptablePolicy::class, Gate::getPolicyFor(CompteComptable::class));
        $this->assertInstanceOf(ExerciceComptablePolicy::class, Gate::getPolicyFor(ExerciceComptable::class));

        $comptable = $this->comptable();
        $policy = new EcritureComptablePolicy();

        // Le comptable a 'C' sur M10 et pourtant : aucune modification, aucune
        // suppression. RG-11 ne se négocie pas avec le niveau d'accès.
        $this->assertSame('C', $comptable->niveauSurModule('M10'));
        $this->assertTrue($policy->viewAny($comptable));
        $this->assertFalse($policy->update($comptable));
        $this->assertFalse($policy->delete($comptable));
    }

    // --------------------------------------------------------- Plan comptable

    /**
     * EF-M10-01 — le plan comptable entier, avec les décomptes du sous-titre et
     * des boutons de filtre.
     */
    #[Test]
    public function ef_m10_01_le_plan_comptable_rend_ses_lignes_et_ses_decomptes(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/plan-comptable')->assertOk();

        // Les sept comptes du référentiel, hors-écran compris : c'est le
        // « <N> comptes » du sous-titre du maître.
        $reponse->assertJsonPath('data.total', 7);
        $reponse->assertJsonCount(7, 'data.lignes');

        // Ordre : par numéro de compte, comme le maître (`localeCompare`).
        $this->assertSame(
            ['101000', '231000', '4111', '521000', '601100', '706100', '831000'],
            array_column($reponse->json('data.lignes'), 'numero_compte'),
        );

        // Les SEPT classes de l'écran, zéros compris. Une classe absente de la
        // réponse serait indiscernable d'une classe vide (Article 7).
        $reponse->assertJsonPath('data.classes.1', 1);
        $reponse->assertJsonPath('data.classes.2', 1);
        $reponse->assertJsonPath('data.classes.3', 0);
        $reponse->assertJsonPath('data.classes.4', 1);
        $reponse->assertJsonPath('data.classes.5', 1);
        $reponse->assertJsonPath('data.classes.6', 1);
        $reponse->assertJsonPath('data.classes.7', 1);
        $this->assertCount(7, (array) $reponse->json('data.classes'));
    }

    /**
     * Un compte de classe 8 est INATTEIGNABLE depuis l'écran, et l'API le dit.
     *
     * Le schéma admet les classes 1 à 9, l'écran n'a de boutons que pour 1 à 7.
     * Sans ce décompte, des comptes réels seraient invisibles sous un plan qui
     * aurait l'air complet — « un plan SYSCOHADA incomplet se signale, il ne
     * s'invente pas ».
     */
    #[Test]
    public function ef_m10_01_une_classe_hors_ecran_est_signalee_jamais_tue(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/plan-comptable')
            ->assertOk()
            ->assertJsonPath('data.classes_hors_ecran.8', 1)
            // Elle n'est pas comptée parmi les classes de l'écran…
            ->assertJsonMissingPath('data.classes.8')
            // … mais elle EST comptée au total : le référentiel en contient sept.
            ->assertJsonPath('data.total', 7);

        // Et elle reste atteignable par le filtre : refuser une valeur dont on
        // vient de signaler l'existence serait une impasse.
        $this->getJson('/api/v1/comptabilite/plan-comptable?classe=8')
            ->assertOk()
            ->assertJsonCount(1, 'data.lignes')
            ->assertJsonPath('data.lignes.0.numero_compte', $this->horsEcran->numero_compte);
    }

    /**
     * Une `nature` absente descend NULLE et se compte — elle ne se devine pas.
     *
     * Le maître indexe un badge de couleur dessus : une nature absente n'y
     * produit rien du tout. La déduire de la classe serait inventer une donnée
     * de référentiel comptable.
     */
    #[Test]
    public function ef_m10_01_une_nature_absente_descend_nulle_et_se_compte(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/plan-comptable')->assertOk();

        $reponse->assertJsonPath('data.sans_nature', 1);

        $lignes = $this->indexerPar($reponse->json('data.lignes'), 'numero_compte');
        $this->assertNull($lignes[$this->sansNature->numero_compte]['nature']);
        $this->assertSame('actif', $this->ligne($lignes, '521000')['nature']);
    }

    /**
     * Le filtre de classe s'applique aux LIGNES, jamais aux décomptes — et il
     * DIT qu'il a été appliqué (PA-119).
     */
    #[Test]
    public function ef_m10_01_le_filtre_de_classe_ne_touche_pas_les_decomptes(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/plan-comptable?classe=7')
            ->assertOk()
            ->assertJsonCount(1, 'data.lignes')
            ->assertJsonPath('data.lignes.0.numero_compte', '706100')
            // Le sous-titre du maître annonce l'effectif du PLAN, pas celui du
            // filtre : « 1 compte » sur un plan qui en compte sept serait faux.
            ->assertJsonPath('data.total', 7)
            ->assertJsonPath('data.classes.5', 1)
            ->assertJsonPath('data.filtres_appliques.classe', '7');
    }

    /**
     * Le registre des classes est FERMÉ, et le refus est traduit.
     */
    #[Test]
    public function ef_m10_01_une_classe_inconnue_est_refusee(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/plan-comptable?classe=0')
            ->assertStatus(422)
            ->assertJsonPath('errors.classe.0', __('comptabilite.validation.classe_inconnue', [
                'valeurs' => implode(', ', CompteComptable::CLASSES_SYSCOHADA),
            ]));
    }

    // ------------------------------------------------------------ Référentiels

    /**
     * Le sélecteur d'exercice — sans lui, aucun client ne connaîtrait un seul
     * identifiant d'exercice et les trois états seraient inatteignables
     * (PA-128).
     */
    #[Test]
    public function le_selecteur_d_exercice_sert_aussi_les_exercices_clos(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/exercices')->assertOk();

        // Du plus récent au plus ancien, et l'exercice CLOS y figure : ses états
        // restent consultables, c'est même leur raison d'être.
        $this->assertSame([2026, 2025], array_column($reponse->json('data'), 'annee'));

        $exercices = $this->indexerPar($reponse->json('data'), 'annee');
        $this->assertSame('ouvert', $this->ligne($exercices, '2026')['statut']);
        $this->assertFalse($this->ligne($exercices, '2026')['saisie_refusee']);
        $this->assertSame('cloture', $this->ligne($exercices, '2025')['statut']);
        $this->assertTrue($this->ligne($exercices, '2025')['saisie_refusee']);
    }

    /**
     * Le référentiel des journaux vient du SERVEUR, pas d'une liste recopiée.
     *
     * `m10-journal.html` l.73 écrit ses trois codes en dur. Deux listes
     * décrivant la même chose divergent ; ce n'est qu'une question de temps.
     */
    #[Test]
    public function le_referentiel_des_journaux_est_servi_par_le_serveur(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/journaux')->assertOk();

        // AN et CL : les journaux de clôture, posés par la migration du lot 2
        // (20/10/2026) — servis comme les autres, dans l'ordre des codes.
        $this->assertSame(['ACH', 'AN', 'CL', 'OD', 'VTE'], array_column($reponse->json('data'), 'code'));
    }

    /**
     * Le sélecteur du Grand Livre ne liste que les comptes RÉELLEMENT
     * mouvementés — `MODULE_COMPTABILITE_COMPLET.md` §3.
     */
    #[Test]
    public function ef_m10_06_le_selecteur_du_grand_livre_ignore_les_comptes_sans_mouvement(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/comptes-mouvementes?' . $this->portee())->assertOk();

        $numeros = array_column($reponse->json('data'), 'numero_compte');

        $this->assertSame(['4111', '521000', '601100', '706100'], $numeros);
        $this->assertNotContains(
            $this->capitalJamaisMouvemente->numero_compte,
            $numeros,
            'Un compte jamais mouvementé ouvrirait un écran vide : le Grand Livre restitue '
            . "l'activité réelle, pas le référentiel complet.",
        );
    }

    /**
     * Le filtre de statut s'applique AUSSI au sélecteur.
     *
     * Consulter le Grand Livre des seules écritures validées et se voir proposer
     * un compte qui n'a que des brouillons ouvrirait un écran vide sans
     * explication.
     */
    #[Test]
    public function ef_m10_06_le_selecteur_suit_le_filtre_de_statut(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/comptes-mouvementes?' . $this->portee() . '&statut=validee')
            ->assertOk();

        $numeros = array_column($reponse->json('data'), 'numero_compte');

        // 4111 n'est mouvementé que par la pièce en brouillon.
        $this->assertSame(['521000', '601100', '706100'], $numeros);
    }

    // ------------------------------------------------------- Journal Général

    /**
     * EF-M10-06 — le Journal Général, ses totaux et son bandeau d'équilibre,
     * d'un seul parcours.
     */
    #[Test]
    public function ef_m10_06_le_journal_rend_ses_lignes_ses_totaux_et_son_equilibre(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/journal?' . $this->portee())->assertOk();

        // Six lignes : trois pièces de deux lignes. L'exercice 2025 n'y est pas.
        $reponse->assertJsonCount(6, 'data.lignes');

        // Ordre chronologique — `MODULE_COMPTABILITE_COMPLET.md` §2.
        $this->assertSame(
            ['2026-07-08', '2026-07-08', '2026-07-10', '2026-07-10', '2026-08-01', '2026-08-01'],
            array_column($reponse->json('data.lignes'), 'date_ecriture'),
        );

        // 184 000 + 132 000 + 30 000 des deux côtés.
        $reponse->assertJsonPath('data.totaux.debit', '346000.00');
        $reponse->assertJsonPath('data.totaux.credit', '346000.00');
        $reponse->assertJsonPath('data.equilibre', true);

        // Les montants sont des CHAÎNES : un flottant réintroduirait l'erreur
        // d'arrondi que tout le schéma évite.
        $this->assertIsString($reponse->json('data.totaux.debit'));
        $this->assertIsString($reponse->json('data.lignes.0.debit'));
    }

    /**
     * RG-12 — chaque ligne porte son centre de coût, et le journal qui l'a
     * produite.
     *
     * `MODULE_COMPTABILITE_COMPLET.md` §2 compte le centre parmi les colonnes du
     * Journal. Le maître ne l'affiche pas ; une ligne sans son centre serait
     * pourtant inexploitable par la comptabilité analytique (EF-M10-03).
     */
    #[Test]
    public function rg12_chaque_ligne_de_journal_porte_son_centre_et_son_journal(): void
    {
        Sanctum::actingAs($this->comptable());

        $ligne = $this->getJson('/api/v1/comptabilite/journal?' . $this->portee())
            ->assertOk()
            ->json('data.lignes.0');

        $this->assertSame('ACH', $ligne['journal']['code']);
        $this->assertSame('601100', $ligne['compte']['numero_compte']);
        $this->assertSame('Structure', $ligne['centre']['libelle']);
        $this->assertNotNull($ligne['centre']['id'], 'RG-12 : `centre_id` est NOT NULL au schéma.');
        $this->assertNull($ligne['contrepassation_de']);
    }

    /**
     * Le filtre de journal restreint les lignes ET les totaux — et il DIT qu'il
     * a été appliqué (PA-119).
     */
    #[Test]
    public function ef_m10_06_le_filtre_de_journal_restreint_lignes_et_totaux(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/journal?' . $this->portee() . '&journal_id=' . $this->vte->id)
            ->assertOk()
            ->assertJsonCount(2, 'data.lignes')
            ->assertJsonPath('data.totaux.debit', '184000.00')
            ->assertJsonPath('data.totaux.credit', '184000.00')
            ->assertJsonPath('data.equilibre', true)
            ->assertJsonPath('data.filtres_appliques.journal_id', $this->vte->id);
    }

    /**
     * **PA-52 en un cas.** L'équilibre est une garantie de FLUX, pas d'ÉTAT :
     * il tient tant que tout passe par `enregistrerPiece()`, et il tombe au
     * premier import.
     *
     * La ligne ci-dessous est écrite hors du service — exactement ce que ferait
     * une reprise de données ou un SQL direct. L'API ne prétend pas que c'est
     * impossible : elle l'AVOUE. Un `equilibre` toujours vrai serait la version
     * comptable de PA-61.
     */
    #[Test]
    public function pa52_une_ecriture_ecrite_hors_du_service_desequilibre_le_journal(): void
    {
        Sanctum::actingAs($this->comptable());

        // Une seule ligne, sans contrepartie : impossible par le service,
        // triviale par un import.
        EcritureComptable::create([
            'exercice_id' => $this->exercice2026->id,
            'journal_id' => $this->od->id,
            'compte_id' => $this->banque->id,
            'centre_id' => $this->structure->id,
            'date_ecriture' => '2026-08-15',
            'libelle' => 'Reprise de données — ligne orpheline',
            'debit' => '7500.00',
            'credit' => '0.00',
            'statut' => 'validee',
        ]);

        $this->getJson('/api/v1/comptabilite/journal?' . $this->portee())
            ->assertOk()
            ->assertJsonPath('data.totaux.debit', '353500.00')
            ->assertJsonPath('data.totaux.credit', '346000.00')
            ->assertJsonPath('data.equilibre', false);
    }

    /**
     * Les totaux se somment en `bccomp`/`bcadd`, jamais en flottant.
     *
     * Le cas est construit pour que la somme flottante ÉCHOUE :
     * `0.1 + 0.2 !== 0.3` en IEEE 754. Un contrôle d'équilibre écrit en `==`
     * annoncerait « Journal déséquilibré — anomalie à investiguer avant
     * clôture » sur une pièce parfaitement équilibrée, et enverrait un comptable
     * chercher une anomalie qui n'existe pas.
     */
    #[Test]
    public function ef_m10_06_l_equilibre_se_compare_en_bccomp_jamais_en_flottant(): void
    {
        $exercice = $this->exercice(2024, 'ouvert');

        $this->piece($this->od, '2024-03-01', 'Le piège d\'arrondi', [
            ['compte' => $this->banque, 'debit' => '0.10'],
            ['compte' => $this->clients, 'debit' => '0.20'],
            ['compte' => $this->ventesHebergement, 'credit' => '0.30'],
        ], validee: true, exercice: $exercice);

        // La preuve que le piège est réel, et pas une hypothèse d'école.
        $this->assertNotSame(0.3, 0.1 + 0.2);

        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/journal?exercice_id=' . $exercice->id)
            ->assertOk()
            ->assertJsonPath('data.totaux.debit', '0.30')
            ->assertJsonPath('data.totaux.credit', '0.30')
            ->assertJsonPath('data.equilibre', true);
    }

    // ---------------------------------------------------------- Grand Livre

    /**
     * EF-M10-06 — le solde progressif, cumulé ligne à ligne, avec son SENS.
     */
    #[Test]
    public function ef_m10_06_le_grand_livre_cumule_un_solde_progressif_signe(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->banque))
            ->assertOk();

        $reponse->assertJsonPath('data.compte.numero_compte', '521000');
        $reponse->assertJsonCount(2, 'data.lignes');

        // 08/07 : crédit 132 000 -> le compte est CRÉDITEUR à cette ligne.
        $reponse->assertJsonPath('data.lignes.0.date_ecriture', '2026-07-08');
        $reponse->assertJsonPath('data.lignes.0.solde_progressif', '-132000.00');
        $reponse->assertJsonPath('data.lignes.0.sens', 'crediteur');

        // 10/07 : débit 184 000 -> il repasse DÉBITEUR.
        $reponse->assertJsonPath('data.lignes.1.date_ecriture', '2026-07-10');
        $reponse->assertJsonPath('data.lignes.1.solde_progressif', '52000.00');
        $reponse->assertJsonPath('data.lignes.1.sens', 'debiteur');

        // Le cumul de l'exercice, nommé pour ce qu'il est.
        $reponse->assertJsonPath('data.solde_mouvements', '52000.00');
        $reponse->assertJsonPath('data.sans_mouvement', false);
    }

    /**
     * **Le solde d'OUVERTURE est INCONNU, et il ne vaut pas zéro.**
     *
     * Le report à nouveau n'existe nulle part dans ce dépôt : aucun service,
     * aucun job, aucune migration ne le génère. Rendre `0` affirmerait que le
     * compte partait de rien au premier jour de l'exercice — sur l'écran même où
     * un comptable lit le solde d'un compte. Article 7 : « — » quand la donnée
     * n'existe pas, « 0 » quand elle vaut zéro.
     *
     * Conséquence en chaîne : une ouverture inconnue rend la CLÔTURE inconnue.
     */
    #[Test]
    public function article7_le_solde_d_ouverture_est_inconnu_jamais_zero(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->banque))
            ->assertOk();

        $this->assertNull($reponse->json('data.solde_ouverture'));
        $this->assertNull($reponse->json('data.solde_cloture'));
        $reponse->assertJsonPath('data.motif_soldes_indisponibles', 'report_a_nouveau_absent');

        // Et le seul montant réellement calculé n'est PAS nommé « clôture ».
        $this->assertSame('52000.00', $reponse->json('data.solde_mouvements'));
    }

    /**
     * Un compte sans mouvement rend 200 avec une liste vide, jamais 404.
     *
     * Le compte existe, c'est son activité qui est nulle — et les deux ne se
     * disent pas de la même façon. Le maître a un message pour exactement ce cas
     * (l.29 : « Ce compte n'a aucun mouvement sur l'exercice. »).
     */
    #[Test]
    public function ef_m10_06_un_compte_sans_mouvement_rend_une_liste_vide_pas_une_erreur(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->capitalJamaisMouvemente))
            ->assertOk()
            ->assertJsonCount(0, 'data.lignes')
            ->assertJsonPath('data.sans_mouvement', true)
            ->assertJsonPath('data.solde_mouvements', '0.00')
            ->assertJsonPath('data.compte.numero_compte', '101000');
    }

    // -------------------------------------------------------------- Balance

    /**
     * EF-M10-06 — les quatre colonnes de montants, les quatre totaux et le
     * double contrôle d'équilibre.
     */
    #[Test]
    public function ef_m10_06_la_balance_rend_quatre_colonnes_et_deux_egalites(): void
    {
        Sanctum::actingAs($this->comptable());

        $reponse = $this->getJson('/api/v1/comptabilite/balance?' . $this->portee())->assertOk();

        // Un compte par compte MOUVEMENTÉ, ordonné par numéro. 101000, 231000 et
        // 831000 n'y sont pas : ils n'ont aucun mouvement.
        $this->assertSame(
            ['4111', '521000', '601100', '706100'],
            array_column($reponse->json('data.lignes'), 'numero_compte'),
        );

        $lignes = $this->indexerPar($reponse->json('data.lignes'), 'numero_compte');

        // La banque : 184 000 au débit, 132 000 au crédit, solde débiteur 52 000.
        $this->assertSame('184000.00', $this->ligne($lignes, '521000')['total_debit']);
        $this->assertSame('132000.00', $this->ligne($lignes, '521000')['total_credit']);
        $this->assertSame('52000.00', $this->ligne($lignes, '521000')['solde_debiteur']);
        $this->assertSame('0.00', $this->ligne($lignes, '521000')['solde_crediteur']);

        // Les ventes : 214 000 au crédit, solde CRÉDITEUR.
        $this->assertSame('0.00', $this->ligne($lignes, '706100')['total_debit']);
        $this->assertSame('214000.00', $this->ligne($lignes, '706100')['total_credit']);
        $this->assertSame('0.00', $this->ligne($lignes, '706100')['solde_debiteur']);
        $this->assertSame('214000.00', $this->ligne($lignes, '706100')['solde_crediteur']);

        $reponse->assertJsonPath('data.totaux.debit', '346000.00');
        $reponse->assertJsonPath('data.totaux.credit', '346000.00');
        $reponse->assertJsonPath('data.totaux.solde_debiteur', '214000.00');
        $reponse->assertJsonPath('data.totaux.solde_crediteur', '214000.00');
        $reponse->assertJsonPath('data.equilibree', true);
    }

    /**
     * La portée d'exercice TIENT : les 999 000 F de 2025 n'apparaissent nulle
     * part dans les états de 2026.
     *
     * `MODULE_COMPTABILITE_COMPLET.md` §1 : « jamais un état "toutes années
     * confondues" par défaut, qui n'aurait pas de sens comptable ».
     */
    #[Test]
    public function ef_m10_06_un_exercice_ne_fuit_jamais_dans_l_autre(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/balance?' . $this->portee())
            ->assertOk()
            ->assertJsonPath('data.totaux.debit', '346000.00');

        $this->getJson('/api/v1/comptabilite/balance?exercice_id=' . $this->exercice2025->id)
            ->assertOk()
            ->assertJsonCount(2, 'data.lignes')
            ->assertJsonPath('data.totaux.debit', '999000.00')
            ->assertJsonPath('data.equilibree', true);
    }

    /**
     * Le filtre de statut change les chiffres — et l'état COMPTE ce qu'il a
     * laissé de côté.
     *
     * Sans `repartition_statuts`, une balance amputée de ses brouillons aurait
     * exactement l'air d'une balance complète.
     */
    #[Test]
    public function le_filtre_de_statut_change_les_chiffres_et_compte_les_exclus(): void
    {
        Sanctum::actingAs($this->comptable());

        $toutes = $this->getJson('/api/v1/comptabilite/balance?' . $this->portee())->assertOk();
        $toutes->assertJsonPath('data.totaux.debit', '346000.00');
        $toutes->assertJsonPath('data.repartition_statuts.brouillon', 2);
        $toutes->assertJsonPath('data.repartition_statuts.validee', 4);
        $toutes->assertJsonPath('data.repartition_statuts.comporte_des_exclusions', false);
        $toutes->assertJsonPath('data.filtres_appliques.statut', 'toutes');

        $validees = $this->getJson('/api/v1/comptabilite/balance?' . $this->portee() . '&statut=validee')->assertOk();
        // 30 000 F de moins : la pièce en brouillon est écartée.
        $validees->assertJsonPath('data.totaux.debit', '316000.00');
        $validees->assertJsonCount(3, 'data.lignes');
        // Les décomptes portent sur la portée SANS le filtre : ils disent ce qui
        // existe, pas ce qui a été retenu.
        $validees->assertJsonPath('data.repartition_statuts.brouillon', 2);
        $validees->assertJsonPath('data.repartition_statuts.comporte_des_exclusions', true);
        $validees->assertJsonPath('data.filtres_appliques.statut', 'validee');
    }

    // ------------------------------------------------------------ Validation

    /**
     * `exercice_id` est OBLIGATOIRE sur les quatre routes qui produisent un
     * état — et le refus est traduit.
     *
     * Retomber sur l'exercice ouvert en son absence afficherait un exercice que
     * l'utilisateur n'a pas choisi ; le jour d'une bascule, deux postes ouverts
     * sur la même page rendraient deux années différentes sans que rien ne le
     * dise.
     */
    #[Test]
    public function l_exercice_est_obligatoire_sur_tout_etat_de_m10(): void
    {
        Sanctum::actingAs($this->comptable());

        foreach (['/journal', '/balance', '/comptes-mouvementes'] as $chemin) {
            $this->getJson('/api/v1/comptabilite' . $chemin)
                ->assertStatus(422)
                ->assertJsonPath('errors.exercice_id.0', __('comptabilite.validation.exercice_requis'));
        }

        $this->getJson('/api/v1/comptabilite/grand-livre?compte_id=' . $this->banque->id)
            ->assertStatus(422)
            ->assertJsonPath('errors.exercice_id.0', __('comptabilite.validation.exercice_requis'));
    }

    /**
     * Le registre des statuts est FERMÉ : une valeur inconnue est refusée,
     * jamais interprétée « au mieux ».
     */
    #[Test]
    public function le_registre_des_statuts_est_ferme(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/balance?' . $this->portee() . '&statut=annulee')
            ->assertStatus(422)
            ->assertJsonPath('errors.statut.0', __('comptabilite.validation.statut_inconnu', [
                'valeurs' => implode(', ', EcritureComptable::FILTRES_STATUT),
            ]));
    }

    /**
     * Un exercice inexistant est refusé avec un message traduit, jamais une
     * exception technique.
     */
    #[Test]
    public function un_exercice_inexistant_est_refuse_proprement(): void
    {
        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/balance?exercice_id=' . Str::uuid()->toString())
            ->assertStatus(422)
            ->assertJsonPath('errors.exercice_id.0', __('comptabilite.validation.exercice_inexistant'));
    }

    // ----------------------------------------------------- Refus de volume

    /**
     * Au-delà du plafond, l'état REFUSE et nomme le geste qui débloque — il ne
     * tronque pas.
     *
     * Tronquer rendrait des totaux faux sous un bandeau annonçant « Journal
     * déséquilibré — anomalie à investiguer avant clôture », et enverrait un
     * comptable chercher une anomalie technique grave qui n'existe pas. Paginer
     * poserait un total juste au-dessus de lignes qui ne le font pas (PA-121).
     */
    #[Test]
    public function un_etat_trop_volumineux_refuse_avec_son_decompte(): void
    {
        $this->app->bind(
            JournalGeneralService::class,
            fn ($app): JournalGeneralService => new JournalGeneralService(
                $app->make(PorteeEcrituresService::class),
                2,
            ),
        );

        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/journal?' . $this->portee())
            ->assertStatus(422)
            ->assertJsonPath('lignes', 6)
            ->assertJsonPath('maximum', 2)
            ->assertJsonPath('message', __('comptabilite.etat_trop_volumineux', [
                'lignes' => 6,
                'maximum' => 2,
            ]));

        // Le filtre nommé par le message débloque réellement : deux lignes pour
        // le journal des ventes, sous le plafond.
        $this->getJson('/api/v1/comptabilite/journal?' . $this->portee() . '&journal_id=' . $this->vte->id)
            ->assertOk()
            ->assertJsonCount(2, 'data.lignes');
    }

    /**
     * Le Grand Livre porte le même plafond, pour la même raison : sa colonne
     * « solde progressif » n'a de sens que cumulée depuis la première ligne.
     */
    #[Test]
    public function le_grand_livre_porte_le_meme_plafond(): void
    {
        $this->app->bind(
            GrandLivreService::class,
            fn ($app): GrandLivreService => new GrandLivreService(
                $app->make(PorteeEcrituresService::class),
                1,
            ),
        );

        Sanctum::actingAs($this->comptable());

        $this->getJson('/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->banque))
            ->assertStatus(422)
            ->assertJsonPath('lignes', 2)
            ->assertJsonPath('maximum', 1);
    }

    // ------------------------------------------------------------- Fixtures

    private function portee(): string
    {
        return 'exercice_id=' . $this->exercice2026->id;
    }

    private function porteeCompte(CompteComptable $compte): string
    {
        return $this->portee() . '&compte_id=' . $compte->id;
    }

    /**
     * @return list<string>
     */
    private function septRoutes(): array
    {
        return [
            '/api/v1/comptabilite/exercices',
            '/api/v1/comptabilite/journaux',
            '/api/v1/comptabilite/plan-comptable',
            '/api/v1/comptabilite/journal?' . $this->portee(),
            '/api/v1/comptabilite/comptes-mouvementes?' . $this->portee(),
            '/api/v1/comptabilite/grand-livre?' . $this->porteeCompte($this->banque),
            '/api/v1/comptabilite/balance?' . $this->portee(),
        ];
    }

    private function exercice(int $annee, string $statut): ExerciceComptable
    {
        return ExerciceComptable::create([
            'annee' => $annee,
            'date_debut' => $annee . '-01-01',
            'date_fin' => $annee . '-12-31',
            'statut' => $statut,
        ]);
    }

    private function compte(string $numero, string $libelle, string $classe, ?string $nature): CompteComptable
    {
        return CompteComptable::create([
            'numero_compte' => $numero,
            'libelle' => $libelle,
            'classe' => $classe,
            'nature' => $nature,
        ]);
    }

    /**
     * Écrit une pièce par le SEUL chemin qui garantit son équilibre.
     *
     * ⚠ L'exercice CLOS est renseigné après coup : `EcritureComptableObserver`
     * refuse toute création sur un exercice `cloture`, et c'est bien le
     * comportement attendu. La pièce est donc écrite sur un exercice ouvert,
     * puis l'exercice est fermé — ce qui reproduit l'ordre réel des choses.
     *
     * @param  list<array{compte: CompteComptable, debit?: string, credit?: string}>  $lignes
     */
    private function piece(
        JournalComptable $journal,
        string $date,
        string $libelle,
        array $lignes,
        bool $validee,
        ?ExerciceComptable $exercice = null,
    ): void {
        $exercice ??= $this->exercice2026;
        $statutInitial = $exercice->statut;

        if ($statutInitial !== 'ouvert') {
            $exercice->update(['statut' => 'ouvert']);
        }

        $service = app(EcritureComptableService::class);

        $piece = $service->enregistrerPiece([
            'exercice_id' => $exercice->id,
            'journal_id' => $journal->id,
            'date_ecriture' => $date,
            'libelle' => $libelle,
        ], array_map(fn (array $ligne): array => [
            'compte_id' => $ligne['compte']->id,
            'centre_id' => $this->structure->id,
            'debit' => $ligne['debit'] ?? '0.00',
            'credit' => $ligne['credit'] ?? '0.00',
        ], $lignes));

        if ($validee) {
            $service->valider($piece);
        }

        if ($statutInitial !== 'ouvert') {
            $exercice->update(['statut' => $statutInitial]);
        }
    }

    /**
     * Une ligne indexee, avec un echec NOMME si elle manque.
     *
     * Passer par une cle variable plutot qu'un litteral n'est pas un detour de
     * confort : PHPStan niveau 6 refuse l'acces litteral sur un tableau dont il
     * ne connait pas les cles, et l'assertion rend l'absence lisible au lieu
     * d'un « undefined index » a la ligne suivante.
     *
     * @param  array<string, array<string, mixed>>  $index
     * @return array<string, mixed>
     */
    private function ligne(array $index, string $cle): array
    {
        $this->assertArrayHasKey($cle, $index, "La cle « {$cle} » n'apparait pas dans cet etat.");

        return $index[$cle];
    }

    /**
     * Indexe une liste de lignes JSON par la valeur d'une de leurs colonnes.
     *
     * @return array<string, array<string, mixed>>
     */
    private function indexerPar(mixed $lignes, string $colonne): array
    {
        $this->assertIsArray($lignes);

        $index = [];

        foreach ($lignes as $ligne) {
            $this->assertIsArray($ligne);
            $index[(string) $ligne[$colonne]] = $ligne;
        }

        return $index;
    }

    /**
     * Le rôle est DÉRIVÉ de la matrice, jamais écrit en dur : le jour où elle
     * change, la suite suit — ou échoue en le disant.
     */
    private function roleAvecNiveauM10(string $niveau): string
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            if ($droits['M10'] === $niveau) {
                return $role;
            }
        }

        $this->fail("Aucun rôle de la matrice ne porte M10 = '{$niveau}'.");
    }

    private function comptable(): User
    {
        return $this->comptable ??= $this->utilisateur($this->roleAvecNiveauM10('C'));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(8),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
