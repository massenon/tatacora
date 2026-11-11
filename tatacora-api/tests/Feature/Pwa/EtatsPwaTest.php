<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Models\EtatGenere;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * M14 en CONSULTATION — `m14-etats-studio.html` et `m14-etats.html`, livrees
 * le 27/08/2026.
 *
 * ## CE FICHIER TIENT LA DECISION DU LOT, ET ELLE SE PROUVE
 *
 * `LARAVEL_PWA.md` §2 fait du Hub M14 « la SEULE exception a la lecture
 * stricte », au motif que « generer/exporter un etat est une operation de
 * lecture agregee, pas une ecriture transactionnelle ». Verifie contre le
 * code : `GenerateurEtatService::generer()` l.78-92 execute
 * `DB::transaction(fn (): EtatGenere => EtatGenere::create([...]))` —
 * l'archivage horodate d'EF-M14-06. **Generer ECRIT.**
 *
 * La coupure retenue passe donc a l'INTERIEUR du moteur, la ou l'architecture
 * l'a deja tracee : `CatalogueEtatsService` et `EtatInterface::calculer()`
 * d'un cote — ce dernier etant STRUCTURELLEMENT prive de l'archivage par son
 * propre contrat — et `GenerateurEtatService::generer()` de l'autre.
 *
 * L'apercu est donc REELLEMENT rendu ; les exports sont refuses et nommes. Et
 * le cas `aucune_consultation_n_archive_d_etat` compte les lignes de
 * `etats_generes` AVANT et APRES avoir parcouru les deux pages : c'est la
 * seule facon de savoir que cette decision est tenue par le code et pas
 * seulement par un commentaire.
 *
 * @see LARAVEL_PWA.md §1, §2, §3
 * @see DIRECTIVE_CONFORMITE_100.md Articles 4.3, 6, 7, 8
 * @see EF-M14-02, EF-M14-06
 */
final class EtatsPwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    /**
     * @var array<string, array{url: string, titre: string}>
     */
    private const PAGES = [
        'm14-etats-studio' => ['url' => '/pwa/etats', 'titre' => 'États &amp; Rapports'],
        'm14-etats' => ['url' => '/pwa/etats/bibliotheque', 'titre' => 'États, Rapports &amp; Exports'],
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /* ------------------------------------------------------------ socle */

    #[Test]
    public function les_deux_pages_sont_reellement_servies(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            $this->assertStringContainsString($page['titre'], $html, "La page {$nom} ne rend pas le titre du maitre.");
            $this->assertGreaterThan(6000, strlen($html), "La page {$nom} est anormalement courte.");
            $this->assertStringContainsString('<body data-module="M14"', $html);
        }
    }

    #[Test]
    public function un_profil_sans_droit_sur_m14_est_refuse(): void
    {
        // ⚠ `guide` est le SEUL role a `M14 = '-'` dans toute la matrice —
        // verifie contre `RolePermissionSeeder::MATRICE` le 27/08/2026. Les dix
        // autres ont au moins `L` : le Hub des etats est un ecran de
        // consultation transverse, et c'est coherent.
        $guide = $this->utilisateur('guide');
        $this->assertSame('-', $guide->niveauSurModule('M14'), 'La matrice a change : ce cas ne verifie plus rien.');

        $this->actingAs($guide);

        foreach (self::PAGES as $page) {
            $this->get($page['url'])->assertForbidden();
        }
    }

    #[Test]
    public function un_invite_est_redirige_vers_le_formulaire_de_connexion(): void
    {
        foreach (self::PAGES as $page) {
            $this->get($page['url'])->assertRedirect(route('pwa.connexion'));
        }
    }

    /* --------------------------- LA DECISION DU LOT, MESUREE --------------- */

    /**
     * ⚠ LE CAS CENTRAL DE CE FICHIER.
     *
     * Parcourir les deux pages, catalogue, apercu d'un etat reel et
     * historique compris, ne cree AUCUNE ligne dans `etats_generes`.
     *
     * Sans ce cas, la decision « l'apercu oui, l'export non » ne serait qu'un
     * commentaire. Le jour ou quelqu'un remplacerait `calculer()` par
     * `generer()` — ce qui est tentant, `generer()` rendant en plus l'en-tete
     * normalisee — la PWA archiverait une edition a chaque affichage, et le
     * journal d'audit se remplirait de documents que personne n'a demandes.
     */
    #[Test]
    public function aucune_consultation_n_archive_d_etat(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $avant = EtatGenere::query()->count();

        $this->get('/pwa/etats')->assertOk();
        $this->get('/pwa/etats?etat=stocks')->assertOk();
        $this->get('/pwa/etats?etat=parc-vehicules')->assertOk();
        $this->get('/pwa/etats?module=M6')->assertOk();
        $this->get('/pwa/etats/bibliotheque')->assertOk();

        $this->assertSame(
            $avant,
            EtatGenere::query()->count(),
            'Une consultation a ARCHIVE un etat. `GenerateurEtatService::generer()` insere dans '
            . '`etats_generes` (EF-M14-06) : il n a aucun chemin depuis la PWA, qui est en lecture '
            . 'seule stricte.',
        );
    }

    /**
     * L'apercu est REELLEMENT calcule : ce n'est ni une coquille vide, ni une
     * reprise des valeurs de demonstration du maitre.
     *
     * Le jeu de donnees pose 10 sacs de riz au magasin, dont 3 sortis : l'etat
     * des stocks doit en montrer la trace.
     */
    #[Test]
    public function l_apercu_rend_le_calcul_reel_de_l_etat(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/etats?etat=stocks')->assertOk()->getContent();
        $corps = $this->corpsPrincipalPwa($html, 'm14-etats-studio');

        // Le libelle et la periode viennent de l'etat lui-meme.
        $this->assertStringContainsString('Riz local', $corps, "L'apercu ne rend pas les lignes calculees.");
        // Et la bande de KPI de l'etat est rendue.
        $this->assertStringContainsString('ligne(s)', $corps);
    }

    /**
     * État « Locations » : la case « Inclure les contrats annulés » n'existe
     * que sur lui, décochée par défaut ; cochée, la colonne « Statut » apparaît
     * et l'annulé est listé sans entrer dans les totaux.
     */
    #[Test]
    public function la_case_des_contrats_annules_ne_concerne_que_l_etat_locations(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $vehicule = \App\Domain\Vehicules\Models\Vehicule::create([
            'categorie' => 'voiture', 'immatriculation' => 'AB 1', 'annee' => 2020,
            'tarif_jour' => '10000.00', 'statut' => 'disponible',
        ]);
        $client = \App\Domain\Crm\Models\Client::factory()->create();
        foreach ([['2026-10-01', '2026-10-03', 'actif'], ['2026-10-10', '2026-10-12', 'annule']] as [$debut, $fin, $statut]) {
            \App\Domain\Vehicules\Models\ContratLocation::create([
                'vehicule_id' => $vehicule->id, 'client_id' => $client->id, 'date_debut' => $debut, 'date_fin' => $fin,
            ])->forceFill(['statut' => $statut])->save();
        }

        $stocks = $this->corpsPrincipalPwa((string) $this->get('/pwa/etats?etat=stocks')->assertOk()->getContent(), 'm14-etats-studio');
        $this->assertStringNotContainsString('Inclure les contrats annulés', $stocks);

        $decoche = $this->corpsPrincipalPwa((string) $this->get('/pwa/etats?etat=locations-vehicules')->assertOk()->getContent(), 'm14-etats-studio');
        $this->assertStringContainsString('Inclure les contrats annulés', $decoche);
        $this->assertStringContainsString('contrats annulés exclus', $decoche);
        $this->assertStringNotContainsString('>Statut<', $decoche);

        $coche = $this->corpsPrincipalPwa((string) $this->get('/pwa/etats?etat=locations-vehicules&annules=1')->assertOk()->getContent(), 'm14-etats-studio');
        $this->assertStringContainsString('contrats annulés inclus', $coche);
        $this->assertStringContainsString('Statut', $coche);
    }

    /**
     * Un code d'etat tape dans l'URL ne contourne PAS le filtrage RBAC du
     * catalogue.
     *
     * C'est le 2e niveau, sur la donnee et non sur l'affichage : masquer une
     * entree du catalogue ne protege rien a lui seul.
     */
    #[Test]
    public function un_code_d_etat_hors_droits_ne_rend_aucun_apercu(): void
    {
        $this->jeuDeDonnees();

        // ⚠ Le role doit avoir M14 (il ouvre l'ecran) SANS avoir M6. Le
        // comptable ne convient pas : il a `M6 = 'L'`. `vehicules` a
        // `M14 = 'L'` et `M6 = '-'` — verifie contre
        // `RolePermissionSeeder::MATRICE` le 27/08/2026. C'est exactement le
        // cas que le maitre decrit a l'ecran : « un magasinier ne lit pas le
        // livre de paie parce qu'il a acces aux "Etats" ».
        $responsable = $this->utilisateur('vehicules');
        $this->assertNotSame('-', $responsable->niveauSurModule('M14'));
        $this->assertSame('-', $responsable->niveauSurModule('M6'), 'La matrice a change : ce cas ne verifie plus rien.');

        $this->actingAs($responsable);

        $html = (string) $this->get('/pwa/etats?etat=stocks')->assertOk()->getContent();
        $corps = $this->corpsPrincipalPwa($html, 'm14-etats-studio');

        $this->assertStringNotContainsString(
            'Riz local',
            $corps,
            'Un code tape dans l URL a contourne le filtrage RBAC du catalogue.',
        );
        $this->assertStringContainsString('Choisissez un état dans le catalogue', $corps);
    }

    /**
     * Un code inconnu ne fait pas LEVER `CatalogueEtatsService::resoudre()`,
     * qui refuse explicitement un code hors registre.
     */
    #[Test]
    public function un_code_d_etat_inconnu_retombe_sur_l_ecran_d_accueil(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/etats?etat=n-importe-quoi')->assertOk()->getContent();

        $this->assertStringContainsString('Choisissez un état dans le catalogue', $html);
    }

    /* ------------------------------------------------------ lecture seule */

    #[Test]
    public function aucune_des_deux_pages_ne_porte_de_champ_d_ecriture(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // La barre d'outils du maître (vague F, 01/09/2026) ajoute des
        // FILTRES de lecture : période du/au, exercice, module, recherche —
        // aucun n'écrit, tous bornent ce que l'écran AFFICHE (PA-119).
        $filtres = [
            'm14-etats-studio' => ['recherche', 'moduleFiltre'],
            'm14-etats' => ['recherche', 'moduleFiltre'],
        ];

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            $this->assertAucunChampDEcriture($html, $nom, $filtres[$nom]);
        }
    }

    #[Test]
    public function aucune_action_livewire_d_ecriture_n_est_cablee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();
            $corps = $this->corpsPrincipalPwa($html, $nom);

            preg_match_all('/wire:click="([^"]+)"/', $corps, $appels);

            foreach ($appels[1] as $appel) {
                $this->assertStringStartsWith(
                    '$set(',
                    $appel,
                    "La page {$nom} cable une action Livewire de composant : {$appel}.",
                );
            }
        }
    }

    /* ------------------------------------------------ Article 6, 7 et 8 */

    /**
     * La grille rend le catalogue REEL, jamais les huit cartes ecrites en dur
     * dans le HTML du maitre (Article 6).
     */
    #[Test]
    public function la_grille_rend_le_catalogue_du_serveur_et_non_les_cartes_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/etats/bibliotheque')->assertOk()->getContent();
        $corps = $this->corpsPrincipalPwa($html, 'm14-etats');

        // Les cinq etats du maitre qui n'existent pas au registre serveur
        // n'apparaissent nulle part comme carte.
        foreach (["Planning d'occupation", 'Journal de caisse', 'Liste des soldes clients', 'État de présence'] as $absent) {
            $this->assertStringNotContainsString(
                $absent,
                $corps,
                "La carte « {$absent} » est rendue alors qu'aucun etat du registre ne la produit.",
            );
        }

        // ⚠ ET L'ECART EST NOMME — DANS LE CODE, PLUS A L'ECRAN (31/08/2026).
        //
        // Ce cas exigeait la phrase « écrites en dur » dans le corps de page :
        // elle venait du panneau de refus, que le Product Owner a retire. Un
        // ecart tu resterait un defaut, alors le controle suit la declaration
        // la ou elle vit desormais, et verifie du meme geste qu'elle n'est
        // plus affichee.
        $this->assertStringNotContainsString(e((string) __('pwa.etats_legacy.ecart_catalogue')), $corps);

        $this->assertStringContainsString(
            'ECRITS EN DUR',
            (string) file_get_contents(app_path('Pwa/Livewire/Etats/Etats.php')),
            'L ecart entre les huit cartes du maitre et le registre serveur '
                .'n est plus nomme nulle part : il redevient un oubli.',
        );
    }

    /**
     * L'historique lit `etats_generes` — la vraie table, pas les trois lignes
     * de demonstration du maitre.
     *
     * ⚠ ET UN CONSTAT DE SCHEMA, MESURE PLUTOT QUE SUPPOSE.
     *
     * Cette page a d'abord ete ecrite avec un repli « — » sur l'emetteur, au
     * motif qu'une edition planifiee n'aurait pas d'auteur humain. C'est FAUX :
     * `etats_generes.utilisateur_id` est `constrained()` SANS `nullable()`
     * (`2026_08_01_001300_create_etats.php` l.20). Le repli etait donc du code
     * que rien ne pouvait exercer, et le commentaire qui le justifiait
     * affirmait un `nullable` inexistant. Les deux sont retires.
     *
     * Consequence signalee au rapport, hors perimetre : `GenerateurEtatService`
     * l.85 ecrit `$auteur?->id` dans cette colonne NOT NULL. Le `?->` y est
     * inatteignable, mais il DECRIT un chemin que le schema refuserait —
     * celui d'EF-M14-05, les etats recurrents planifies.
     */
    #[Test]
    public function l_historique_lit_la_vraie_table_et_distingue_l_emetteur_absent(): void
    {
        $this->jeuDeDonnees();
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        EtatGenere::create([
            'module' => 'M6',
            'nom_etat' => 'État des stocks — édition humaine',
            'filtres_appliques' => [],
            'utilisateur_id' => $auteur->id,
            'date_edition' => now(),
            'format' => 'pdf',
            'chemin_fichier_archive' => null,
        ]);

        EtatGenere::create([
            'module' => 'M11',
            'nom_etat' => 'Tableau de bord — seconde édition',
            'filtres_appliques' => [],
            'utilisateur_id' => $auteur->id,
            'date_edition' => now()->subDay(),
            'format' => 'excel',
            'chemin_fichier_archive' => null,
        ]);

        $html = (string) $this->get('/pwa/etats/bibliotheque')->assertOk()->getContent();
        $corps = $this->corpsPrincipalPwa($html, 'm14-etats');

        $this->assertStringContainsString('État des stocks — édition humaine', $corps);
        $this->assertStringContainsString('compte.administrateur', $corps);
        $this->assertStringContainsString('Tableau de bord — seconde édition', $corps);

        // La colonne « Format » rend l'enum REEL — `pdf|excel` — en capitales.
        $this->assertStringContainsString('>PDF</td>', $corps);
        $this->assertStringContainsString('>EXCEL</td>', $corps);

        // La contrainte qui rend le repli inatteignable est verifiee ICI, pas
        // supposee : sans ce cas, le repli reviendrait a la premiere relecture.
        $colonne = DB::selectOne("SHOW COLUMNS FROM etats_generes LIKE 'utilisateur_id'");
        $this->assertSame(
            'NO',
            $colonne->Null ?? null,
            '`utilisateur_id` est devenue nullable : le repli « — » redevient necessaire.',
        );

        // Les trois lignes de demonstration du maitre n'apparaissent pas.
        $this->assertStringNotContainsString('NABOGOU', $corps);
    }

    /**
     * Les refus sont DECLARES DANS LE CODE, et l'ecran n'en dit plus rien.
     *
     * ## Ce que ce cas mesurait avant, et pourquoi il a change
     *
     * Il exigeait que chaque refus soit « nomme a l'ecran avec les mots du
     * maitre » : « Imprimer », « Excel », « PDF », « Generer »,
     * « Reteledecharger »… Les deux ecrans portaient donc un panneau qui
     * enumerait ce qu'ils ne font pas — le Studio le rendait meme DEUX fois.
     * Le Product Owner l'a retire le 31/08/2026 : un ecran ne catalogue pas
     * ses absences pour l'utilisateur.
     *
     * ⚠ Le controle n'est pas supprime, il CHANGE DE CIBLE. Sans lui, une
     * fonction pourrait disparaitre sans que personne l'ait decide, ce qui
     * est exactement ce que la directive ne dit pas. Deux moities :
     *
     *  1. les mots du maitre ne sont plus a l'ecran — ni rendus, ni grises ;
     *  2. le refus est declare sous le jeton `maitre-refuse:` que
     *     `t-trois-sources.js` relit a chaque execution.
     */
    #[Test]
    public function les_refus_sont_declares_dans_le_code_et_absents_de_l_ecran(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // 1. L'ecran ne porte plus les PHRASES de refus.
        $studio = (string) $this->get('/pwa/etats')->assertOk()->getContent();

        foreach (['refus_periode', 'refus_exports', 'refus_decompte', 'refus_impression', 'refus_alignement'] as $cle) {
            $this->assertStringNotContainsString(
                e((string) __('pwa.etats.'.$cle)),
                $studio,
                "La phrase de refus « {$cle} » est encore rendue par le Studio.",
            );
        }

        // Et le titre du panneau retire ne revient nulle part.
        $this->assertStringNotContainsString(e((string) __('pwa.refus_titre')), $studio);

        $bibliotheque = (string) $this->get('/pwa/etats/bibliotheque')->assertOk()->getContent();

        foreach (['refus_generer', 'refus_modale', 'refus_retelecharger', 'refus_periode', 'ecart_catalogue'] as $cle) {
            $this->assertStringNotContainsString(
                e((string) __('pwa.etats_legacy.'.$cle)),
                $bibliotheque,
                "La phrase de refus « {$cle} » est encore rendue par la bibliotheque.",
            );
        }

        $this->assertStringNotContainsString(e((string) __('pwa.refus_titre')), $bibliotheque);

        // 2. Les refus sont declares la ou la conformite les mesure.
        $studioSource = (string) file_get_contents(app_path('Pwa/Livewire/Etats/EtatsStudio.php'));

        foreach (['periode', 'exports', 'decompte', 'impression'] as $bloc) {
            $this->assertStringContainsString(
                'maitre-refuse:m14-etats-studio.html#'.$bloc,
                $studioSource,
                "Le refus « {$bloc} » du Studio n'est declare nulle part.",
            );
        }

        $legacySource = (string) file_get_contents(app_path('Pwa/Livewire/Etats/Etats.php'));

        foreach (['modale-generer-etat', 'periode', 'generer', 'retelecharger'] as $bloc) {
            $this->assertStringContainsString(
                'maitre-refuse:m14-etats.html#'.$bloc,
                $legacySource,
                "Le refus « {$bloc} » de la bibliotheque n'est declare nulle part.",
            );
        }
    }

    /**
     * L'ancienne bibliotheque d'etats ne porte aucun bandeau de conception :
     * « Ecran remplace… maquette validee par le client » est une note d'equipe,
     * pas un texte pour l'utilisateur final (decision du Product Owner).
     */
    #[Test]
    public function la_bibliotheque_ne_porte_aucun_bandeau_ecran_remplace(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/etats/bibliotheque')->assertOk()->getContent();

        $this->assertStringNotContainsString('Écran remplacé.', $html);
        $this->assertStringNotContainsString('maquette validée par le client', $html);
    }

    /* ------------------------------------------------------------ outils */

    private function jeuDeDonnees(): void
    {
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $riz = Article::create([
            'libelle' => 'Riz local (sac 50 kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '12.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($riz->id, $magasin->id, '10.00', 'Réception SODIS Bénin', '1000.00');
        $mouvements->sortie($riz->id, $magasin->id, '3.00', 'Consommation cuisine');
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.' . $role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.' . $role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
