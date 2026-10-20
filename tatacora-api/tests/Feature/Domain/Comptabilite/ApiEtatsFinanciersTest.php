<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\ReadModels\Analytique;
use App\Domain\Comptabilite\ReadModels\CompteResultat;
use App\Domain\Comptabilite\ReadModels\NotesAnnexes;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\NotesAnnexesService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M10 — les états financiers DÉRIVÉS de la Balance : Bilan, Compte de
 * Résultat, TAFIRE, Notes Annexes, Analytique, état de clôture, indicateurs.
 *
 * @see EF-M10-03 Comptabilité analytique par centre de coût
 * @see EF-M10-06 Édition des états réglementaires SYSCOHADA
 * @see EF-M10-07 Clôture comptable périodique
 * @see RG-11 Immutabilité et contre-passation
 * @see RG-12 Centre de coût obligatoire
 * @see RG-16 RBAC à trois niveaux
 *
 * ## Ce que cette suite existe pour empêcher
 *
 * 1. **Qu'un taux d'impôt sur les sociétés entre dans un calcul** (PA-19). La
 *    charge d'impôt est LUE de la classe 89 ; deux cas éprouvent les DEUX
 *    branches — rien comptabilisé, et une écriture d'impôt réelle. La seconde
 *    est la leçon PA-61 : une branche jamais exécutée est une branche fausse.
 * 2. **Qu'un résultat avant impôt se fasse passer pour un résultat net.** Le
 *    drapeau `impot_non_comptabilise` remonte jusqu'au bilan, au TAFIRE et au
 *    bandeau d'indicateurs — un cas le vérifie sur les quatre à la fois.
 * 3. **Qu'un compte disparaisse en silence.** La répartition par préfixe n'est
 *    pas exhaustive par construction : un cas ouvre un compte hors nomenclature
 *    et vérifie que le bilan le NOMME au lieu de se contenter d'être faux.
 * 4. **Que le TAFIRE mente sur sa propre cohérence.** L'égalité se démontre par
 *    la partie double ; un cas la vérifie sur un grand livre complet, arrhes
 *    clients comprises — c'est ce compte que la Partie 3 §2.3 classe du mauvais
 *    côté.
 * 5. **Qu'une route perde sa garde RBAC** (PA-65), ou qu'une écriture
 *    apparaisse là où le maître n'a aucun bouton (Article 6).
 */
final class ApiEtatsFinanciersTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $exercice;

    private JournalComptable $od;

    private CentreCout $structure;

    private CentreCout $hebergement;

    /** @var array<string, CompteComptable> */
    private array $comptes = [];

    private ?User $comptable = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->comptable());

        $this->exercice = ExerciceComptable::create([
            'annee' => 2026,
            'date_debut' => '2026-01-01',
            'date_fin' => '2026-12-31',
            'statut' => 'ouvert',
        ]);

        $this->od = JournalComptable::create(['code' => 'OD', 'libelle' => 'Opérations diverses']);

        $this->structure = CentreCout::create(['libelle' => 'Structure', 'type' => 'support']);
        $this->hebergement = CentreCout::create(['libelle' => 'Hébergement', 'type' => 'activite']);

        // Le référentiel réel d'`ATELIER_PLAN_COMPTABLE.md` §2 à §4.
        $this->compte('101000', 'Capital social', '1');
        $this->compte('131', 'Résultat net : bénéfice', '1');
        $this->compte('139', 'Résultat net : perte', '1');
        $this->compte('231000', 'Bâtiments', '2');
        $this->compte('281000', 'Amortissements des bâtiments', '2');
        $this->compte('4011', 'Fournisseurs', '4');
        $this->compte('4111', 'Clients', '4');
        $this->compte('4191', 'Clients — avances et acomptes reçus', '4');
        $this->compte('431000', 'CNSS', '4');
        $this->compte('447000', 'État — impôts retenus à la source', '4');
        $this->compte('521000', 'Banque — compte principal', '5');
        $this->compte('601100', 'Achats denrées alimentaires', '6');
        $this->compte('661000', 'Rémunérations directes du personnel', '6');
        $this->compte('681000', 'Dotations aux amortissements', '6');
        $this->compte('706100', "Prestations d'hébergement", '7');
        $this->compte('891000', 'Impôts sur le résultat', '8');

        $this->grandLivreDeReference();
    }

    /**
     * Un exercice COMPLET, dont tous les chiffres sont vérifiés à la main.
     *
     * Il n'est pas décoratif : il traverse chacune des rubriques que les cinq
     * états savent lire — capital, immobilisation, amortissement, dette
     * fournisseur, DETTE SOCIALE, créance client, ARRHES CLIENTS, produit,
     * charge de personnel, charge d'exploitation, dotation.
     * Un grand livre plus pauvre laisserait la moitié des rubriques à zéro, et
     * un zéro passe tous les tests d'équilibre sans rien prouver.
     *
     * Bilan attendu : 1 044 000 F à l'actif comme au passif.
     */
    private function grandLivreDeReference(): void
    {
        $this->piece('2026-01-02', 'Apport en capital', [
            ['521000', '500000.00', null],
            ['101000', null, '500000.00'],
        ]);

        $this->piece('2026-02-15', 'Acquisition bâtiment — bungalows', [
            ['231000', '300000.00', null],
            ['4011', null, '300000.00'],
        ]);

        $this->piece('2026-07-10', 'Hébergement — Agence Bénin Tour', [
            ['521000', '184000.00', null],
            ['706100', null, '184000.00'],
        ], centre: $this->hebergement);

        $this->piece('2026-07-12', 'Réapprovisionnement denrées cuisine', [
            ['601100', '132000.00', null],
            ['4011', null, '132000.00'],
        ]);

        // Les ARRHES : le compte que `MODULE_COMPTABILITE_COMPLET_PART3.md`
        // §2.3 range parmi les créances et que la Partie 2 §2.2 range au passif
        // circulant. Sans lui dans les fixtures, la contradiction ne serait
        // éprouvée par rien.
        $this->piece('2026-08-05', 'Arrhes de réservation — Jean KORA', [
            ['521000', '50000.00', null],
            ['4191', null, '50000.00'],
        ], centre: $this->hebergement);

        $this->piece('2026-08-20', 'Hébergement à crédit — Société ABC', [
            ['4111', '30000.00', null],
            ['706100', null, '30000.00'],
        ], centre: $this->hebergement);

        // Une DETTE SOCIALE (431 CNSS). Elle est ici pour une raison precise :
        // `MODULE_COMPTABILITE_COMPLET_PART3.md` §2.3 ne compte au BFR que les
        // dettes FOURNISSEURS (401), en omettant 421, 431 et 447. Sans une
        // dette sociale au grand livre, cette omission ne serait eprouvee par
        // rien — la mutation accuserait le cas, pas le code (INSTRUCTIONS §7).
        $this->piece('2026-11-30', 'Salaires de novembre — part CNSS due', [
            ['661000', '40000.00', null],
            ['431000', null, '40000.00'],
        ]);

        $this->piece('2026-12-31', "Dotation aux amortissements de l'exercice", [
            ['681000', '20000.00', null],
            ['281000', null, '20000.00'],
        ]);
    }

    // ------------------------------------------------------------------- RBAC

    /**
     * RG-16 — un rôle sans aucun accès à M10 est refusé sur les neuf routes.
     * Le rôle est DÉRIVÉ de la matrice : l'écrire en dur ferait passer la suite
     * au vert le jour où elle changerait.
     */
    #[Test]
    public function rg16_un_role_sans_acces_a_m10_est_refuse_sur_les_neuf_etats(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM10('-')));

        foreach ($this->neufRoutes() as $url) {
            $this->getJson($url)->assertForbidden();
        }
    }

    #[Test]
    public function rg16_un_role_en_lecture_seule_consulte_les_neuf_etats(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM10('L')));

        foreach ($this->neufRoutes() as $url) {
            $this->getJson($url)->assertOk();
        }
    }

    /**
     * Article 6 / RG-11 — aucune de ces routes n'écrit, et le maître n'a aucun
     * bouton pour le demander. Le verbe NON ROUTÉ (405) est la preuve la plus
     * solide qu'il n'existe pas : un contrôleur pourrait toujours refuser, une
     * route absente ne peut rien faire du tout.
     */
    #[Test]
    public function article6_aucune_ecriture_n_est_exposee_sur_les_etats_financiers(): void
    {
        foreach (['/api/v1/comptabilite/cloture', '/api/v1/comptabilite/bilan', '/api/v1/comptabilite/compte-resultat'] as $url) {
            $this->postJson($url, [])->assertStatus(405);
            $this->putJson($url, [])->assertStatus(405);
            $this->deleteJson($url)->assertStatus(405);
        }
    }

    // ------------------------------------------------------------------ PA-19

    /**
     * PA-19 — AUCUN taux d'impôt sur les sociétés n'entre dans le calcul.
     *
     * Rien n'est comptabilisé en classe 89 : la charge d'impôt vaut `0.00` — un
     * zéro CALCULÉ sur une classe réellement balayée — et le résultat net égale
     * le résultat avant impôt. Le drapeau `impot_non_comptabilise` et son motif
     * disent que ce n'est pas un résultat net au sens fiscal.
     *
     * ⚠ Ce cas est la garde anti-mutation de PA-19 : faire dériver l'impôt d'un
     * taux, quel qu'il soit, le fait rougir immédiatement.
     */
    #[Test]
    public function pa19_l_impot_est_lu_de_la_classe_89_jamais_derive_d_un_taux(): void
    {
        $etat = $this->getJson('/api/v1/comptabilite/compte-resultat?'.$this->portee())
            ->assertOk()
            ->json('data');

        $this->assertSame('22000.00', $etat['resultat_avant_impot']);
        $this->assertSame('0.00', $etat['impot_comptabilise']);
        $this->assertSame('22000.00', $etat['resultat_net']);
        $this->assertTrue($etat['impot_non_comptabilise']);
        $this->assertSame(
            CompteResultat::MOTIF_IMPOT_NON_COMPTABILISE,
            $etat['motif_resultat_avant_impot'],
        );

        // La ligne RS est RENDUE, jamais omise : un client qui ne la recevrait
        // pas ne pourrait pas distinguer « pas d'impôt » de « pas d'info ».
        $lignes = $this->indexerParCode($etat['lignes']);
        $this->assertArrayHasKey('RS', $lignes);
        $this->assertSame('0.00', $lignes['RS']['montant']);
        $this->assertSame('Impôts sur le résultat', $lignes['RS']['libelle']);
    }

    /**
     * PA-61 — la branche « un impôt EST comptabilisé » est réellement exécutée.
     *
     * C'est la leçon des trois défauts PA-59/60/61 : une branche que rien n'a
     * jamais empruntée est une branche fausse. Le jour où le Comptable, muni du
     * taux officiel de la DGI, passera son écriture d'impôt, le résultat net
     * doit cesser d'égaler le résultat avant impôt et le drapeau doit tomber —
     * sans une ligne de code de plus.
     *
     * ⚠ Les 15 000 F ci-dessous sont un montant de TEST, pas un taux : aucune
     * donnée réglementaire n'est fixée ici, on écrit une pièce comme le ferait
     * un comptable.
     */
    #[Test]
    public function pa61_un_impot_reellement_comptabilise_produit_un_vrai_resultat_net(): void
    {
        $this->piece('2026-12-31', "Impôt sur le résultat de l'exercice", [
            ['891000', '15000.00', null],
            ['447000', null, '15000.00'],
        ]);

        $etat = $this->getJson('/api/v1/comptabilite/compte-resultat?'.$this->portee())
            ->assertOk()
            ->json('data');

        $this->assertSame('22000.00', $etat['resultat_avant_impot']);
        $this->assertSame('-15000.00', $etat['impot_comptabilise']);
        $this->assertSame('7000.00', $etat['resultat_net']);
        $this->assertFalse($etat['impot_non_comptabilise']);
        $this->assertNull($etat['motif_resultat_avant_impot']);

        // Et le bilan reste équilibré : la charge d'impôt entre au résultat, la
        // dette d'impôt au passif circulant, et les deux se compensent. C'est
        // ce qui prouve que le bilan n'a jamais eu besoin du taux.
        $bilan = $this->getJson('/api/v1/comptabilite/bilan?'.$this->portee())->assertOk()->json('data');

        $this->assertTrue($bilan['equilibre']);
        $this->assertSame('1044000.00', $bilan['totaux']['actif']);
        $this->assertSame('1044000.00', $bilan['totaux']['passif']);
        $this->assertSame('7000.00', $bilan['resultat_exercice']);
    }

    /**
     * Le drapeau PA-19 se propage aux QUATRE états qui portent un résultat.
     *
     * Un bilan qui afficherait « Résultat net » sans ce drapeau serait la
     * non-conformité PA-49 : un intitulé qui ne dit pas ce qui est calculé.
     */
    #[Test]
    public function pa49_le_drapeau_avant_impot_se_propage_a_tous_les_etats_porteurs(): void
    {
        foreach (['bilan', 'tafire', 'indicateurs', 'compte-resultat'] as $etat) {
            $reponse = $this->getJson("/api/v1/comptabilite/{$etat}?".$this->portee())
                ->assertOk()
                ->json('data');

            $this->assertTrue(
                $reponse['impot_non_comptabilise'],
                "L'état « {$etat} » n'annonce pas que son résultat est un résultat avant impôt.",
            );
            $this->assertSame(
                CompteResultat::MOTIF_IMPOT_NON_COMPTABILISE,
                $reponse['motif_resultat_avant_impot'],
            );
        }
    }

    // ------------------------------------------------------------------ BILAN

    /**
     * Le contrôle fondamental — Actif = Passif, en `bccomp`.
     *
     * L'égalité n'est pas empirique : elle découle de la partie double, le poste
     * de résultat du passif étant mathématiquement la grandeur qui équilibre.
     */
    #[Test]
    public function ef_m10_06_le_bilan_s_equilibre_et_le_resultat_entre_au_passif(): void
    {
        $bilan = $this->getJson('/api/v1/comptabilite/bilan?'.$this->portee())->assertOk()->json('data');

        $this->assertTrue($bilan['equilibre']);
        $this->assertSame('0.00', $bilan['ecart']);
        $this->assertSame('1044000.00', $bilan['totaux']['actif']);
        $this->assertSame('1044000.00', $bilan['totaux']['passif']);

        $actif = $this->indexerParCode($bilan['actif']);
        $this->assertSame('300000.00', $actif['actif_immobilise']['brut']);
        $this->assertSame('20000.00', $actif['actif_immobilise']['amortissement']);
        $this->assertSame('280000.00', $actif['actif_immobilise']['net']);
        $this->assertSame('30000.00', $actif['actif_circulant']['net']);
        $this->assertSame('734000.00', $actif['tresorerie_actif']['net']);

        $passif = $this->indexerParCode($bilan['passif']);
        $this->assertSame('522000.00', $passif['capitaux_propres']['net']);
        // 4011 (432 000) + 4191 (50 000) + 431000 (40 000) — les arrhes
        // sont une DETTE, et la dette sociale en est une aussi.
        $this->assertSame('522000.00', $passif['passif_circulant']['net']);

        // Trésorerie-Passif : rubrique à `0.00`, jamais supprimée du modèle
        // (`MODULE_COMPTABILITE_COMPLET_PART2.md` §2.3).
        $this->assertSame('0.00', $passif['tresorerie_passif']['net']);
    }

    /**
     * Article 7 — un compte qu'aucune rubrique ne capte est NOMMÉ, pas avalé.
     *
     * La répartition par préfixe n'est pas exhaustive par construction. Sans
     * cette garde, ouvrir un compte hors nomenclature ne produirait qu'un
     * déséquilibre inexplicable, et l'erreur serait cherchée dans les écritures.
     */
    #[Test]
    public function article7_un_compte_hors_rubrique_est_nomme_jamais_avale(): void
    {
        $vierge = $this->getJson('/api/v1/comptabilite/bilan?'.$this->portee())->assertOk()->json('data');
        $this->assertSame([], $vierge['comptes_hors_rubrique']);

        // 471 « Compte d'attente » ne relève d'aucune rubrique du bilan ni du
        // compte de résultat — cas réel d'un plan comptable qu'on étend.
        $this->compte('471000', "Compte d'attente", '4');
        $this->piece('2026-09-01', 'Encaissement non identifié', [
            ['471000', '7500.00', null],
            ['706100', null, '7500.00'],
        ]);

        $bilan = $this->getJson('/api/v1/comptabilite/bilan?'.$this->portee())->assertOk()->json('data');

        $this->assertFalse($bilan['equilibre']);
        $this->assertCount(1, $bilan['comptes_hors_rubrique']);
        $this->assertSame('471000', $bilan['comptes_hors_rubrique'][0]['numero_compte']);
        $this->assertSame('7500.00', $bilan['comptes_hors_rubrique'][0]['solde']);
    }

    // ----------------------------------------------------------------- TAFIRE

    /**
     * Le contrôle de cohérence du TAFIRE — `MODULE_COMPTABILITE_COMPLET_PART3.md`
     * §2.2 : « écart = signal d'erreur de calcul, PAS une différence normale ».
     *
     * ⚠ C'est le cas qui DÉPARTAGE la contradiction du document sur le compte
     * 4191. Les arrhes clients figurent au grand livre de référence ; les
     * classer parmi les créances (Partie 3 §2.3) au lieu des dettes (Partie 2
     * §2.2) rend cet écart non nul, et le tableau accuserait alors les écritures
     * d'une erreur qui serait la sienne.
     */
    #[Test]
    public function ef_m10_06_le_tafire_recoupe_la_variation_reelle_de_tresorerie(): void
    {
        $tafire = $this->getJson('/api/v1/comptabilite/tafire?'.$this->portee())->assertOk()->json('data');

        // Le RECOUPEMENT d'abord : c'est lui qui valide le tableau, et le
        // placer en tete garantit qu'une erreur de methode le fasse tomber
        // AVANT les assertions de detail. Une mutation arretee par une ligne
        // de rubrique n'aurait rien prouve sur la cohérence elle-meme.
        $this->assertSame('734000.00', $tafire['tresorerie']['variation_calculee']);
        $this->assertSame('734000.00', $tafire['tresorerie']['variation_reelle']);
        $this->assertSame('0.00', $tafire['tresorerie']['ecart']);
        $this->assertTrue($tafire['coherent']);

        $this->assertSame('22000.00', $tafire['ressources']['resultat_exercice']);
        $this->assertSame('20000.00', $tafire['ressources']['dotations_amortissements']);
        $this->assertSame('42000.00', $tafire['ressources']['capacite_autofinancement_globale']);
        $this->assertSame('500000.00', $tafire['ressources']['augmentation_capital']);
        $this->assertSame('542000.00', $tafire['ressources']['total']);

        $this->assertSame('300000.00', $tafire['emplois']['total']);

        $this->assertSame('30000.00', $tafire['besoin_fonds_roulement']['variation_creances']);
        // 401 + 4191 + 431 : les TROIS. PART3 §2.3 ne compte que 401.
        $this->assertSame('522000.00', $tafire['besoin_fonds_roulement']['variation_dettes']);
        $this->assertSame('-492000.00', $tafire['besoin_fonds_roulement']['total']);
    }

    // ------------------------------------------------------------- ANALYTIQUE

    /**
     * EF-M10-03 — des marges SUR COÛTS DIRECTS, et un taux qui vaut `null`
     * plutôt que zéro quand le centre n'a aucun produit (Article 7).
     */
    #[Test]
    public function ef_m10_03_l_analytique_ventile_par_centre_et_refuse_un_taux_sans_produit(): void
    {
        $analytique = $this->getJson('/api/v1/comptabilite/analytique?'.$this->portee())
            ->assertOk()
            ->json('data');

        $this->assertFalse($analytique['repartition_structure_effectuee']);
        $this->assertSame(Analytique::MOTIF_SANS_REPARTITION, $analytique['motif_nature_des_marges']);
        $this->assertTrue($analytique['ventilation_garantie_par_schema']);

        $centres = $this->indexerPar($analytique['centres'], 'libelle');

        // Hébergement : 214 000 F de produits, aucune charge directe.
        $this->assertSame('214000.00', $centres['Hébergement']['produits']);
        $this->assertSame('0.00', $centres['Hébergement']['charges']);
        $this->assertSame('214000.00', $centres['Hébergement']['resultat']);
        $this->assertSame('100.0', $centres['Hébergement']['taux_marge']);

        // Structure : aucun produit — le taux est ABSENT, pas nul.
        $this->assertSame('0.00', $centres['Structure']['produits']);
        $this->assertSame('192000.00', $centres['Structure']['charges']);
        $this->assertNull($centres['Structure']['taux_marge']);
    }

    // ---------------------------------------------------------------- CLÔTURE

    /**
     * EF-M10-07 — l'état de clôture distingue ce qui est VÉRIFIÉ de ce qui
     * est DÉCLARÉ.
     *
     * `blocages_structurels` est recalculé à chaque appel contre le
     * référentiel. Depuis le lot 2 (20/10/2026), la clôture est EXPOSÉE
     * (onglet « Clôtures » du hub) et `limites_non_verifiables` est vide : le
     * report à nouveau existe (journal AN) et le périmètre est arbitré
     * (annuel). Les étapes 2 à 5 se lisent sur la clôture réelle.
     */
    #[Test]
    public function ef_m10_07_la_cloture_expose_son_etat_et_son_action(): void
    {
        $cloture = $this->getJson('/api/v1/comptabilite/cloture?'.$this->portee())->assertOk()->json('data');

        $this->assertTrue($cloture['action_exposee']);
        $this->assertSame([], $cloture['limites_non_verifiables']);

        // Les journaux CL et AN (migration du lot 2), les comptes 131/139 et le
        // centre « Structure » existent : aucun blocage structurel.
        $this->assertSame([], $cloture['blocages_structurels']);

        // Exercice ouvert : la clôture n'est pas démarrée, rien n'est passé.
        $etapes = collect($cloture['etapes'])->keyBy('libelle');
        $this->assertSame('non_atteint', $etapes["Bloque toute nouvelle saisie sur l'exercice"]['etat']);
        $this->assertSame(EtatClotureService::MOTIF_CLOTURE_NON_DEMARREE, $etapes["Bloque toute nouvelle saisie sur l'exercice"]['motif']);
        $this->assertSame('non_atteint', $etapes['Verrou définitif RG-11bis']['etat']);

        $this->assertContains(EtatClotureService::AVERTISSEMENT_IMPOT, $cloture['avertissements']);
        $this->assertSame('22000.00', $cloture['resultat_a_reporter']);
        $this->assertSame('131', $cloture['compte_de_destination']);
    }

    /**
     * Le blocage structurel APPARAÎT quand son élément disparaît du référentiel.
     *
     * Sans ce cas, la liste pourrait être écrite en dur sans que rien ne le
     * montre — c'est exactement le défaut que le coordinateur a relevé sur la
     * première version de ce service.
     */
    #[Test]
    public function ef_m10_07_un_blocage_structurel_est_constate_et_non_affirme(): void
    {
        CompteComptable::query()->whereIn('numero_compte', ['131', '139'])->delete();
        CentreCout::query()->where('libelle', 'Structure')->update(['libelle' => 'Siège']);

        \App\Domain\Comptabilite\Models\JournalComptable::query()->where('code', 'AN')->update(['code' => 'ANX']);

        $cloture = $this->getJson('/api/v1/comptabilite/cloture?'.$this->portee())->assertOk()->json('data');

        $this->assertContains(
            EtatClotureService::BLOCAGE_JOURNAL_AN_ABSENT,
            $cloture['blocages_structurels'],
        );
        $this->assertContains(
            EtatClotureService::BLOCAGE_COMPTES_RESULTAT_ABSENTS,
            $cloture['blocages_structurels'],
        );
        $this->assertContains(
            EtatClotureService::BLOCAGE_CENTRE_STRUCTURE_ABSENT,
            $cloture['blocages_structurels'],
        );
        $this->assertFalse($cloture['conditions_verifiables_reunies']);
    }

    // ------------------------------------------------------------ INDICATEURS

    /**
     * Les six indicateurs du bandeau sont LUS des états, jamais recalculés à
     * côté (PA-121) — un cas les confronte aux soldes de la cascade.
     */
    #[Test]
    public function ef_m10_06_les_indicateurs_reprennent_les_soldes_de_la_cascade(): void
    {
        $resultat = $this->getJson('/api/v1/comptabilite/compte-resultat?'.$this->portee())->assertOk()->json('data');
        $lignes = $this->indexerParCode($resultat['lignes']);

        $kpi = $this->getJson('/api/v1/comptabilite/indicateurs?'.$this->portee())->assertOk()->json('data');

        $this->assertSame($lignes['XB']['montant'], $kpi['chiffre_affaires']);
        $this->assertSame($lignes['XC']['montant'], $kpi['valeur_ajoutee']);
        $this->assertSame($lignes['XD']['montant'], $kpi['excedent_brut']);
        $this->assertSame($resultat['resultat_net'], $kpi['resultat_net']);

        $this->assertSame('214000.00', $kpi['chiffre_affaires']);
        $this->assertSame('82000.00', $kpi['valeur_ajoutee']);
        $this->assertSame('42000.00', $kpi['excedent_brut']);
        $this->assertSame('734000.00', $kpi['tresorerie']);
        $this->assertSame('1044000.00', $kpi['total_bilan']);
        $this->assertTrue($kpi['equilibre']);
        $this->assertSame(2026, $kpi['annee']);
    }

    // --------------------------------------------------------- NOTES ANNEXES

    /**
     * Les SEPT notes descendent toujours, avec leur état — « indisponible »
     * n'est pas « vide », et une note omise se lirait comme une note sans objet
     * alors qu'elle est obligatoire au sens SYSCOHADA (Partie 4 §1).
     */
    #[Test]
    public function ef_m10_06_les_sept_notes_annexes_descendent_avec_leur_etat(): void
    {
        $notes = $this->getJson('/api/v1/comptabilite/notes-annexes?'.$this->portee())
            ->assertOk()
            ->json('data.notes');

        $this->assertCount(7, $notes);

        $parNumero = $this->indexerPar($notes, 'numero');
        $note1 = $this->note($parNumero, '1');
        $note2 = $this->note($parNumero, '2');
        $note6 = $this->note($parNumero, '6');
        $note7 = $this->note($parNumero, '7');

        // Note 6 — effectif : INDISPONIBLE, et ses postes sont VIDES. Un
        // tableau de zéros se lirait « aucun employé ».
        $this->assertSame(NotesAnnexes::ETAT_INDISPONIBLE, $note6['etat']);
        $this->assertSame(NotesAnnexesService::MOTIF_DOMAINE_RH, $note6['motif']);
        $this->assertSame([], $note6['postes']);

        // Note 7 — événements postérieurs : NON SAISIE, pas « aucun événement ».
        $this->assertSame(NotesAnnexes::ETAT_NON_SAISIE, $note7['etat']);
        $this->assertNull($note7['texte']);

        // Note 2 — immobilisations : disponible, plus bornée par l'absence de
        // report à nouveau (lot 2, 20/10/2026) : l'ouverture et la variation
        // sont rendues (exercice inaugural : ouverture 0).
        $this->assertSame(NotesAnnexes::ETAT_DISPONIBLE, $note2['etat']);
        $this->assertNull($note2['motif']);
        $this->assertSame('300000.00', $note2['postes'][0]['montant']);
        $this->assertSame('0.00', $note2['postes'][0]['ouverture']);
        $this->assertSame('300000.00', $note2['postes'][0]['variation']);

        // Note 1 — texte traduit, jamais une chaîne en dur dans le service.
        $this->assertSame(__('comptabilite.notes.regles_et_methodes'), $note1['texte']);
    }

    // ------------------------------------------------------- ÉTATS FINANCIERS

    /**
     * Les quatre documents proviennent de la MÊME lecture, et disent la même
     * chose que les routes individuelles — le maître l'exige explicitement
     * (`m10-etats-financiers.html` l.42 : « aucun recalcul indépendant »).
     */
    #[Test]
    public function ef_m10_06_les_etats_financiers_consolident_sans_recalculer(): void
    {
        $consolide = $this->getJson('/api/v1/comptabilite/etats-financiers?'.$this->portee())
            ->assertOk()
            ->json('data');

        $bilan = $this->getJson('/api/v1/comptabilite/bilan?'.$this->portee())->assertOk()->json('data');
        $resultat = $this->getJson('/api/v1/comptabilite/compte-resultat?'.$this->portee())->assertOk()->json('data');
        $tafire = $this->getJson('/api/v1/comptabilite/tafire?'.$this->portee())->assertOk()->json('data');

        $this->assertSame($bilan, $consolide['bilan']);
        $this->assertSame($resultat, $consolide['resultat']);
        $this->assertSame($tafire, $consolide['flux']);
        $this->assertCount(7, $consolide['notes']['notes']);
    }

    // ------------------------------------------------------------- PORTÉE

    /**
     * `MODULE_COMPTABILITE_COMPLET.md` §1 — aucun état « toutes années
     * confondues ». L'exercice est une portée obligatoire, pas un filtre.
     */
    #[Test]
    public function ef_m10_06_aucun_etat_financier_ne_se_produit_sans_exercice(): void
    {
        foreach (['bilan', 'compte-resultat', 'tafire', 'analytique', 'notes-annexes', 'cloture', 'indicateurs', 'etats-financiers'] as $etat) {
            $this->getJson("/api/v1/comptabilite/{$etat}")
                ->assertStatus(422)
                ->assertJsonValidationErrors('exercice_id');
        }
    }

    // ---------------------------------------------------------------- Fixtures

    /**
     * @param  list<array{0: string, 1: string|null, 2: string|null}>  $lignes
     */
    private function piece(string $date, string $libelle, array $lignes, ?CentreCout $centre = null): void
    {
        $centre ??= $this->structure;

        app(EcritureComptableService::class)->valider(
            app(EcritureComptableService::class)->enregistrerPiece([
                'exercice_id' => $this->exercice->id,
                'journal_id' => $this->od->id,
                'date_ecriture' => $date,
                'libelle' => $libelle,
            ], array_map(fn (array $ligne): array => [
                'compte_id' => $this->comptes[$ligne[0]]->id,
                'centre_id' => $centre->id,
                'debit' => $ligne[1] ?? '0.00',
                'credit' => $ligne[2] ?? '0.00',
            ], $lignes)),
        );
    }

    private function compte(string $numero, string $libelle, string $classe): CompteComptable
    {
        return $this->comptes[$numero] = CompteComptable::create([
            'numero_compte' => $numero,
            'libelle' => $libelle,
            'classe' => $classe,
            'nature' => null,
        ]);
    }

    private function portee(): string
    {
        return 'exercice_id='.$this->exercice->id;
    }

    /**
     * @return list<string>
     */
    private function neufRoutes(): array
    {
        $portee = $this->portee();

        return [
            '/api/v1/comptabilite/compte-resultat?'.$portee,
            '/api/v1/comptabilite/bilan?'.$portee,
            '/api/v1/comptabilite/tafire?'.$portee,
            '/api/v1/comptabilite/notes-annexes?'.$portee,
            '/api/v1/comptabilite/etats-financiers?'.$portee,
            '/api/v1/comptabilite/analytique?'.$portee,
            '/api/v1/comptabilite/indicateurs?'.$portee,
            '/api/v1/comptabilite/cloture?'.$portee,
            '/api/v1/comptabilite/centres-cout',
        ];
    }

    /**
     * Une note, avec un message utile quand elle manque.
     *
     * Le detour par un helper n'est pas cosmetique : `$index['6']` sur un
     * tableau indexe par chaine ne dit rien a l'analyse statique, et une note
     * disparue produirait une erreur PHP au lieu d'un echec d'assertion lisible.
     *
     * @param  array<string, array<string, mixed>>  $index
     * @return array<string, mixed>
     */
    private function note(array $index, string $numero): array
    {
        $this->assertArrayHasKey($numero, $index, "La note {$numero} n'est pas rendue.");

        return $index[$numero];
    }

    /**
     * @return array<string, array<string, mixed>>
     */
    private function indexerParCode(mixed $lignes): array
    {
        return $this->indexerPar($lignes, 'code');
    }

    /**
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

    /** Les fixtures ecrivent des pieces : leur auteur doit pouvoir ECRIRE M10. */
    private function comptable(): User
    {
        return $this->comptable ??= $this->utilisateur($this->roleAvecNiveauM10('C'));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(8),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
