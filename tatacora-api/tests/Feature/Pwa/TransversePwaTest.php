<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service;
use App\Models\User;
use App\Pwa\Livewire\Transverse\AideAPropos;
use App\Pwa\Livewire\Transverse\JournalAudit as ComposantJournalAudit;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Pwa\Livewire\Transverse\RolesPermissions;
use App\Pwa\Support\MenuLateral;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * Les SEPT pages TRANSVERSES de la PWA — celles du maitre qui ne relevent
 * d'aucun module metier.
 *
 * Ce qui est verifie ici, et qui ne l'est nulle part ailleurs :
 *
 *  1. Les sept pages sont REELLEMENT SERVIES, pas seulement routees. Le
 *     precedent est ecrit dans `CLAUDE.md` : « une page HTML livree vide que
 *     seule une execution reelle a revelee ».
 *  2. Le RBAC de 2e niveau, PAGE PAR PAGE, avec le module que le `data-module`
 *     du maitre designe — et l'ABSENCE de module sur les trois pages qui n'en
 *     portent pas. Une garde trop large est aussi un defaut : elle fermerait
 *     l'aide a un profil qui doit apprendre a se servir de son outil.
 *  3. AUCUNE ECRITURE. C'est le risque propre a ce lot : quatre des douze
 *     pages transverses du maitre sont des ecrans de SAISIE. Le cas
 *     `aucun_champ_de_saisie_n_est_rendu_…` relit le HTML servi et refuse tout
 *     `<form>`, `<input>` d'ecriture, `<textarea>` ou bouton de soumission.
 *  4. Les refus de l'Article 8 sont NOMMES a l'ecran, jamais tus, et avec LES
 *     MOTS DU MAITRE (PA-144).
 *  5. Article 7 : « — » quand la donnee n'existe pas.
 *  6. Aucun secret n'est rendu.
 *
 * @see LARAVEL_PWA.md §1, §3, §5, §6
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.3, 4.5, 6, 7, 8
 */
final class TransversePwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    /**
     * Les sept pages livrees, avec le module que le maitre leur donne
     * (`data-module` sur son `<body>`) et le titre exact de son `<h1>`.
     *
     * ⚠ La colonne « module » est le miroir de `routes/web.php`. Un module
     * ajoute ou retire ici sans l'etre la-bas fait rougir ce cas — c'est le
     * seul endroit ou les deux se confrontent.
     *
     * @var array<string, array{url: string, module: string|null, titre: string}>
     */
    private const PAGES = [
        'aide-a-propos' => ['url' => '/pwa/aide-a-propos', 'module' => null, 'titre' => 'Aide &amp; À propos'],
        'contact-editeur' => ['url' => '/pwa/contact-editeur', 'module' => null, 'titre' => 'Contactez l&#039;éditeur'],
        'mon-profil' => ['url' => '/pwa/mon-profil', 'module' => null, 'titre' => 'Mon profil'],
        'journal-audit' => ['url' => '/pwa/journal-audit', 'module' => 'M14', 'titre' => 'Journal d&#039;Audit'],
        'roles-permissions' => ['url' => '/pwa/roles-permissions', 'module' => 'ROLES', 'titre' => 'Rôles &amp; Permissions'],
        'parametres' => ['url' => '/pwa/parametres', 'module' => 'PARAM', 'titre' => 'Paramètres'],
        'import-export' => ['url' => '/pwa/import-export', 'module' => 'PARAM', 'titre' => 'Import &amp; Export'],
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /**
     * Les sept pages sont servies, et leur `<h1>` est celui du maitre.
     *
     * Le titre est compare a la chaine ECHAPPEE que Blade produit : c'est ce
     * qu'un navigateur recoit. Comparer la chaine brute laisserait passer une
     * page qui rend `Aide & À propos` sans echappement.
     */
    #[Test]
    public function les_sept_pages_transverses_sont_reellement_servies(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            $this->assertStringContainsString(
                '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">'.$page['titre'].'</h1>',
                $html,
                "La page {$nom} ne rend pas le titre du maitre.",
            );

            // Plancher : une page qui rendrait la coquille et rien d'autre
            // passerait le controle de titre. Le `<main>` doit porter du
            // contenu — c'est le defaut « page livree vide » de `CLAUDE.md`.
            $this->assertGreaterThan(
                6000,
                strlen($html),
                "La page {$nom} est anormalement courte : la coquille sans contenu ?",
            );
        }
    }

    /**
     * Le RBAC de 2e niveau, page par page — et l'ABSENCE de garde la ou le
     * maitre n'en pose pas.
     *
     * Le `guide` est choisi a dessein : `ROLES` et `PARAM` a `'-'`, `M14` a
     * `'-'` aussi. Il est donc refuse sur les QUATRE pages a module, et admis
     * sur les TROIS qui n'en portent pas. Un seul role eprouve ainsi les deux
     * sens du controle.
     */
    #[Test]
    public function le_rbac_de_route_suit_le_module_que_le_maitre_donne_a_chaque_page(): void
    {
        $this->actingAs($this->utilisateur('guide'));

        foreach (self::PAGES as $nom => $page) {
            $reponse = $this->get($page['url']);

            if ($page['module'] === null) {
                $reponse->assertOk();

                continue;
            }

            $reponse->assertForbidden();
            $this->assertNotEquals(200, $reponse->getStatusCode(), $nom);
        }
    }

    /**
     * Un `barman` a `M14 = 'L'` : il consulte le journal d'audit, et reste
     * refuse sur les trois pages d'administration.
     *
     * Ce cas existe pour que le precedent ne puisse pas passer en refusant
     * TOUT : un controle qui rend 403 partout serait vert sur la moitie des
     * assertions du cas ci-dessus.
     */
    #[Test]
    public function un_droit_de_lecture_sur_le_module_suffit_a_ouvrir_la_page(): void
    {
        $this->actingAs($this->utilisateur('barman'));

        $this->get('/pwa/journal-audit')->assertOk();
        $this->get('/pwa/roles-permissions')->assertForbidden();
        $this->get('/pwa/parametres')->assertForbidden();
        $this->get('/pwa/import-export')->assertForbidden();
    }

    /**
     * AUCUN CHAMP DE SAISIE SUR LES SEPT PAGES — c'est le risque propre a ce
     * lot.
     *
     * Quatre pages transverses du maitre sont des ecrans d'ECRITURE : les deux
     * formulaires de « Contactez l'editeur », les deux de « Mon profil », le
     * formulaire de « Parametres » et les quatre onglets d'« Import & Export ».
     * Elles deviennent des consultations, et « consultation » se verifie : un
     * `<form>` reintroduit un jour par commodite passerait toutes les autres
     * gardes de ce fichier.
     *
     * ⚠ La recherche est TOLEREE, et nommement : `<input type="text">` lie par
     * `wire:model` filtre l'affichage et n'ecrit rien. C'est la seule
     * exception, et elle est bornee aux deux ecrans qui en portent une.
     */
    #[Test]
    public function aucun_champ_de_saisie_n_est_rendu_sur_les_pages_transverses(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // Les pages a porter un champ, et la propriete qu'il lie.
        // Liste FERMEE : un filtre ajoute ailleurs fait rougir ce cas.
        // `import-export` ajoute le 02/09/2026 : la recherche dans les
        // archives de l'onglet Restaurer (maquette l.229-230) est un FILTRE,
        // comme celle du journal d'audit. Le champ de depot de fichier de
        // l'onglet Importer, lui, n'est PAS rendu au premier GET (il attend
        // le choix d'un module) — la doctrine RefuseLaSaisie reste entiere.
        $filtresRelus = [
            'aide-a-propos' => ['recherche'],
            'journal-audit' => ['recherche'],
            'import-export' => ['rechercheArchives'],
            // 28/10/2026 (décision du PO) : l'e-mail facultatif du compte COURANT est le seul champ
            // d'« Informations personnelles » que le compte porte (`utilisateurs.email`). Comme au
            // maître, il vit dans la carte, avec « Enregistrer les informations » : ce n'est pas un
            // filtre mais une écriture sans module RBAC, inscrite à ce titre dans
            // `PwaEcritureAutoriseeTest::ECRITURES_HORS_MODULE`. Le champ de mot de passe, lui, reste
            // derrière sa modale.
            'mon-profil' => ['emailSaisi'],
        ];

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            // ⚠ Le controle lui-meme vit dans `RefuseLaSaisie`, partage avec
            // les pages METIER (27/08/2026). Il y avait ici une seconde
            // implementation en puissance : deux definitions de « champ
            // tolere » auraient fini par diverger, et c'est celle qu'on relit
            // le moins qui aurait laisse passer (Article 10).
            $this->assertAucunChampDEcriture($html, $nom, $filtresRelus[$nom] ?? []);
        }
    }

    /**
     * Toute methode non-GET sur ces sept routes est refusee par le middleware
     * du groupe — 405, pas 404.
     *
     * ⚠ Cela ne dit RIEN des actions Livewire, qui transitent hors du groupe
     * (PA-67). C'est `PwaActionsReluesTest` qui tient ce chemin, et lui seul.
     */
    #[Test]
    public function aucune_ecriture_http_n_atteint_les_pages_transverses(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            foreach (['post', 'put', 'patch', 'delete'] as $methode) {
                $this->{$methode}($page['url'])->assertStatus(405);
            }
        }
    }

    /**
     * Aucune des sept pages ne charge de ressource distante.
     *
     * `ConformiteMaquettePwaTest` tient le meme controle sur la coquille ; il
     * est repete ici parce que sa liste de pages est FERMEE et n'aurait pas vu
     * ces sept-la. Un balayage qui ne couvre pas la page ajoutee est vert a
     * vide — le defaut que PA-152 a trouve dans la garde de lecture seule.
     */
    #[Test]
    public function aucune_page_transverse_ne_charge_de_ressource_distante(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000', 'www.w3.org'];

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

            foreach (array_unique($hotes[1]) as $hote) {
                $this->assertContains($hote, $autorises, "La page {$nom} charge une ressource distante : {$hote}.");
            }
        }
    }

    /* ------------------------------------------------------ Aide & À propos */

    /**
     * La grille de modules lit le RBAC REEL, et un module sans acces est
     * GRISE — pas retire.
     *
     * C'est le comportement du maitre (`aide-a-propos.html` l.276), et il
     * differe de celui du menu lateral, ou `'-'` retire l'entree. Les deux
     * divergent AU MAITRE, et l'ecart est reporte tel quel.
     */
    #[Test]
    public function la_grille_de_modules_de_l_aide_grise_les_modules_sans_acces(): void
    {
        $guide = $this->utilisateur('guide');
        $this->actingAs($guide);

        $html = (string) $this->get('/pwa/aide-a-propos')->assertOk()->getContent();

        // Les SEIZE cartes sont la, quel que soit le droit.
        foreach (AideAPropos::MODULES as $module) {
            $this->assertStringContainsString(
                e((string) __('pwa.aide.modules.'.$module['code'].'.nom')),
                $html,
                "Le module {$module['code']} a disparu de la grille.",
            );
        }

        // Le `guide` n'a AUCUN droit sur M11 : la carte porte le badge.
        $this->assertSame('-', $guide->niveauSurModule('M11'));
        $this->assertStringContainsString(e((string) __('pwa.aide.badge_sans_acces')), $html);

        // Et le decompte est REEL, pas seize.
        $ouverts = 0;
        foreach (AideAPropos::MODULES as $module) {
            if ($guide->niveauSurModule($module['code']) !== '-') {
                $ouverts++;
            }
        }

        $this->assertLessThan(count(AideAPropos::MODULES), $ouverts);
        $this->assertStringContainsString(
            e((string) __('pwa.aide.modules_compteur', ['accessibles' => $ouverts, 'total' => count(AideAPropos::MODULES)])),
            $html,
        );
    }

    /**
     * Le bouton « Revoir mes alertes » du maitre n'est pas rendu, et son
     * absence est DECLAREE DANS LE CODE.
     *
     * ⚠ La seconde moitie a change de place le 31/08/2026, elle n'a pas
     * disparu. Ce cas exigeait la raison A L'ECRAN ; le Product Owner a
     * retire les sections de refus, et la declaration vit desormais sous le
     * jeton `maitre-refuse:` que `t-trois-sources.js` relit. Les deux moities
     * comptent toujours : un bouton retire en silence empeche de savoir si la
     * fonction manque ou si l'ecran est casse.
     */
    #[Test]
    public function le_bouton_d_alertes_de_l_aide_est_absent_et_son_refus_declare(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/aide-a-propos')->assertOk()->getContent();

        $this->assertStringNotContainsString('bouton-rejouer-alertes', $html);
        $this->assertStringNotContainsString(e((string) __('pwa.aide.refus_alertes')), $html);
        $this->assertStringNotContainsString(e((string) __('pwa.refus_titre')), $html);

        $this->assertStringContainsString(
            'maitre-refuse:aide-a-propos.html#alertes',
            (string) file_get_contents(app_path('Pwa/Livewire/Transverse/AideAPropos.php')),
        );
    }

    /* --------------------------------------------------------- Journal d'audit */

    /**
     * Le journal rend les entrees REELLES, avec les six colonnes du maitre, et
     * « — » la ou la donnee n'existe pas.
     *
     * L'entree de test est ecrite SANS utilisateur ni poste : c'est le cas
     * d'un job planifie ou d'une commande console, et c'est celui ou l'Article
     * 7 se joue. Un compte invente y serait indetectable.
     */
    #[Test]
    public function le_journal_d_audit_rend_les_entrees_reelles_et_un_tiret_pour_l_absent(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => null,
            'action' => 'creation',
            'entite_concernee' => 'reservations',
            'entite_id' => 'res-de-test-0001',
            'adresse_poste' => null,
        ]);

        $html = (string) $this->get('/pwa/journal-audit')->assertOk()->getContent();

        foreach (['col_utilisateur', 'col_action', 'col_detail', 'col_date', 'col_heure', 'col_poste'] as $colonne) {
            $this->assertStringContainsString(e((string) __('pwa.journal_audit.'.$colonne)), $html);
        }

        // Le libellé FRANÇAIS de la table (corrigé le 02/09/2026 : la
        // colonne « Détail » ne rend plus le nom de table brut), et
        // l'identifiant qui reste en second faute d'un enregistrement
        // « reservations » portant réellement cet id.
        $this->assertStringContainsString(__('pwa.journal_audit.tables.reservations'), $html);
        $this->assertStringNotContainsString('>reservations<', $html);
        $this->assertStringContainsString('res-de-test-0001', $html);
        $this->assertStringContainsString(ComposantJournalAudit::ACTIONS['creation']['libelle'], $html);

        // Deux « — » : l'utilisateur et le poste, tous deux absents.
        $corps = $this->corpsPrincipal($html, 'journal-audit');
        $lignes = $this->extraireLigneDuJournal($corps, 'res-de-test-0001');
        $this->assertSame(
            2,
            substr_count($lignes, '—'),
            'La ligne doit porter DEUX tirets — utilisateur et poste absents — '
                .'et pas un de plus : un tiret de trop masquerait une donnee reelle.',
        );
    }

    /**
     * LE LIBELLÉ RÉEL DE L'ENREGISTREMENT EST RÉSOLU QUAND IL EXISTE ENCORE
     * — défaut relevé par l'audit navigateur du Product Owner (01/09/2026) :
     * la colonne « Détail » ne rendait qu'un nom de table brut et un UUID.
     *
     * Deux entrées : l'une pointe un client RÉEL (son nom doit apparaître),
     * l'autre une facture dont l'identifiant ne correspond à AUCUNE ligne
     * (l'identifiant doit rester, en second — jamais un libellé inventé).
     */
    #[Test]
    public function le_detail_resout_le_libelle_reel_de_l_enregistrement_encore_lisible(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $client = \App\Domain\Crm\Models\Client::create([
            'id' => (string) Str::uuid(),
            'nom' => 'HOUNKPATIN',
            'prenom' => 'Estelle',
            'telephone' => '+229 01 00 11 22 33',
            'type_client' => 'particulier',
        ]);

        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => null,
            'action' => 'creation',
            'entite_concernee' => 'clients',
            'entite_id' => $client->id,
            'adresse_poste' => null,
        ]);

        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => null,
            'action' => 'suppression',
            'entite_concernee' => 'factures',
            'entite_id' => 'facture-disparue-0001',
            'adresse_poste' => null,
        ]);

        $html = (string) $this->get('/pwa/journal-audit')->assertOk()->getContent();

        // Le client réel : son nom, pas seulement son identifiant.
        $this->assertStringContainsString(__('pwa.journal_audit.tables.clients'), $html);
        $this->assertStringContainsString('HOUNKPATIN Estelle', $html);

        // La facture disparue : le libellé de la table, et l'identifiant en
        // second — jamais un numéro de facture inventé.
        $this->assertStringContainsString(__('pwa.journal_audit.tables.factures'), $html);
        $this->assertStringContainsString('facture-disparue-0001', $html);
    }

    /**
     * Le bouton « Réinitialiser les données de démo » du maitre n'existe pas,
     * et la mention de lecture seule du maitre est conservee.
     */
    #[Test]
    public function le_journal_d_audit_ne_porte_aucun_outil_de_demonstration(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/journal-audit')->assertOk()->getContent();

        $this->assertStringNotContainsString('bouton-vider-journal', $html);
        $this->assertStringNotContainsString('Réinitialiser les données de démo</button>', $html);

        // ⚠ LE REFUS A CHANGE DE PLACE, PAS DISPARU (31/08/2026). La phrase
        // qui l'expliquait a l'ecran est retiree ; le jeton la remplace, et
        // c'est lui que la conformite mesure.
        $this->assertStringNotContainsString(e((string) __('pwa.journal_audit.refus_reinitialiser')), $html);
        $this->assertStringContainsString(
            'maitre-refuse:journal-audit.html#reinitialiser',
            (string) file_get_contents(app_path('Pwa/Livewire/Transverse/JournalAudit.php')),
        );

        // La mention du MAITRE, elle, reste : elle dit ce que le journal EST
        // (inalterable), pas ce que l'ecran ne fait pas.
        $this->assertStringContainsString(e((string) __('pwa.journal_audit.mention_lecture_seule')), $html);
    }

    /**
     * Le filtre d'action est un registre derive du REGISTRE REEL : il ne
     * propose que les actions presentes, et une valeur inconnue venue de l'URL
     * retombe sur « toutes » au lieu de rendre une liste vide.
     */
    #[Test]
    public function le_filtre_du_journal_ne_propose_que_les_actions_presentes(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => null,
            'action' => 'creation',
            'entite_concernee' => 'factures',
            'entite_id' => 'fac-0001',
            'adresse_poste' => null,
        ]);

        $html = (string) $this->get('/pwa/journal-audit')->assertOk()->getContent();
        $this->assertStringContainsString('<option value="creation">', $html);
        $this->assertStringNotContainsString('<option value="suppression">', $html);

        // Une action inconnue venue de l'URL ne vide pas l'ecran.
        $htmlInconnu = (string) $this->get('/pwa/journal-audit?action=nimporte-quoi')->assertOk()->getContent();
        $this->assertStringContainsString('fac-0001', $htmlInconnu);
    }

    /* ------------------------------------------------------------ Mon profil */

    /**
     * Le profil rend le nom et la fonction de la FICHE EMPLOYE quand il y en a
     * une, et « — » quand il n'y en a pas.
     */
    #[Test]
    public function mon_profil_lit_la_fiche_employe_et_rend_un_tiret_sans_elle(): void
    {
        $service = Service::create(['id' => (string) Str::uuid(), 'libelle' => 'Réception']);
        $employe = Employe::create([
            'id' => (string) Str::uuid(),
            'nom' => 'HOUNSOU',
            'prenom' => 'Marceline',
            'poste' => 'Réceptionniste',
            'service_id' => $service->id,
            'date_embauche' => '2026-01-05',
            'salaire_base' => '150000.00',
            'statut' => 'actif',
        ]);

        $avecFiche = $this->utilisateur('receptionniste');
        $avecFiche->forceFill(['employe_id' => $employe->id])->save();

        $html = (string) $this->actingAs($avecFiche)->get('/pwa/mon-profil')->assertOk()->getContent();
        $this->assertStringContainsString('Marceline HOUNSOU', $html);
        $this->assertStringContainsString('Réceptionniste', $html);

        // Un compte technique n'a pas de fiche : « — », jamais un nom fabrique.
        $sansFiche = $this->utilisateur('comptable');
        $htmlSansFiche = (string) $this->actingAs($sansFiche)->get('/pwa/mon-profil')->assertOk()->getContent();
        $this->assertStringContainsString(e((string) __('pwa.profil.sans_fiche_rh')), $htmlSansFiche);
        $this->assertStringNotContainsString('Marceline HOUNSOU', $htmlSansFiche);
    }

    /**
     * Le statut affiche est le statut REEL, pas « Actif » ecrit en dur.
     *
     * ⚠ Un compte suspendu n'atteint pas cet ecran — `estActif()` le refuse en
     * amont. Ce que ce cas prouve, c'est que la valeur vient de la colonne :
     * elle est confrontee au registre, pas a une chaine du gabarit.
     */
    #[Test]
    public function mon_profil_affiche_le_statut_reel_du_compte(): void
    {
        $utilisateur = $this->utilisateur('administrateur');
        $this->actingAs($utilisateur);

        $html = (string) $this->get('/pwa/mon-profil')->assertOk()->getContent();

        $this->assertSame('actif', $utilisateur->statut);
        $this->assertStringContainsString(
            'style="color:var(--succes)">'.\App\Pwa\Livewire\Transverse\MonProfil::STATUTS['actif']['libelle'],
            $html,
        );
    }

    /**
     * Aucun champ de mot de passe, aucune coquille de section a la place, et
     * le refus DECLARE dans le code.
     *
     * ⚠ RENOMMÉ le 01/09/2026 : il s'appelait « mon profil n'offre aucun
     * changement de mot de passe » — prémisse RENVERSÉE par la directive du
     * Product Owner (vague F). Ce qui RESTE vrai et mesuré ici : au premier
     * GET, le seul champ de mot de passe servi est celui du verrou de session
     * (la modale de changement ne se rend qu'à l'ouverture, doctrine
     * `RefuseLaSaisie`) — le cas suivant vérifie l'offre réelle.
     *
     * ## Ce que ce cas mesurait avant
     *
     * Il exigeait que les quatre intitules du maitre — « Ancien mot de
     * passe », « Nouveau mot de passe »… — restent NOMMES a l'ecran, dans un
     * encadre expliquant leur absence. La directive du 31/08/2026 retire ces
     * sections, et l'Article 3.3 interdit de laisser a leur place une section
     * qui n'aurait plus qu'un titre : la section entiere est donc omise.
     *
     * Le controle porte donc sur TROIS choses — pas de champ, pas de coquille
     * vide, et un refus declare la ou la conformite le relit.
     */
    #[Test]
    public function au_premier_get_seul_le_verrou_porte_un_champ_de_mot_de_passe(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/mon-profil')->assertOk()->getContent();

        // ⚠ Le VERROU DE SESSION (monté par le layout sur TOUTES les pages
        // depuis le 01/09/2026) porte légitimement UN champ
        // `autocomplete="current-password"` — le sien, pas un changement de
        // mot de passe offert par Mon profil. Le contrôle devient donc un
        // comptage : exactement l'occurrence du verrou, jamais une seconde.
        // La contre-épreuve vérifie que le porteur autorisé est bien la vue
        // du verrou — sans elle, retirer le verrou ET ajouter un champ au
        // profil laisserait le compte à un.
        $this->assertSame(
            1,
            substr_count($html, 'autocomplete="current-password"'),
            'Un champ de mot de passe HORS verrou de session est rendu sur Mon profil.',
        );
        $this->assertStringContainsString(
            'autocomplete="current-password"',
            (string) file_get_contents(resource_path('views/pwa/livewire/verrou-session.blade.php')),
            'Le porteur attendu de l\'unique champ est le verrou de session.',
        );

        $this->assertStringNotContainsString('autocomplete="new-password"', $html);

        // Les phrases de l'ancien refus ne reviennent jamais.
        $this->assertStringNotContainsString(e((string) __('pwa.profil.refus_mot_de_passe')), $html);
        $this->assertStringNotContainsString(e((string) __('pwa.profil.refus_titre')), $html);

        $source = (string) file_get_contents(app_path('Pwa/Livewire/Transverse/MonProfil.php'));

        // Le jeton `mot-de-passe` a quitté la liste avec la directive du
        // Product Owner (vague F) : le changement de mot de passe est OFFERT,
        // le déclarer refusé serait la phrase périmée de PA-144.
        foreach (['enregistrer-infos', 'email-telephone', 'module'] as $bloc) {
            $this->assertStringContainsString(
                'maitre-refuse:mon-profil.html#'.$bloc,
                $source,
                "Le refus « {$bloc} » n'est declare nulle part.",
            );
        }
    }

    /**
     * ⚠ GARDE INVERSÉE le 01/09/2026 — directive du Product Owner (vague F) :
     * Mon profil OFFRE le changement de mot de passe. L'ancien cas assertait
     * son absence ; celui-ci exige sa présence RÉELLE : l'action publique
     * existe, la modale porte les trois champs aux bons `autocomplete`, et
     * l'ancien mot de passe est vérifié par `Auth::validate` — jamais un
     * changement sans preuve de possession.
     */
    #[Test]
    public function mon_profil_offre_le_changement_de_mot_de_passe_reel(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/mon-profil')->assertOk()->getContent();

        $this->assertStringContainsString(e((string) __('pwa.profil.mdp_titre')), $html);

        $source = (string) file_get_contents(app_path('Pwa/Livewire/Transverse/MonProfil.php'));
        $this->assertStringContainsString('Auth::validate', $source, 'L\'ancien mot de passe doit être vérifié.');

        $vue = (string) file_get_contents(resource_path('views/pwa/transverse/mon-profil.blade.php'));
        $this->assertStringContainsString('autocomplete="current-password"', $vue);
        $this->assertSame(2, substr_count($vue, 'autocomplete="new-password"'), 'Nouveau + confirmation.');
    }

    /* --------------------------------------------------- Rôles & Permissions */

    /**
     * Chaque case de la matrice vaut EXACTEMENT ce que le serveur applique.
     *
     * C'est le point de cet ecran : `LARAVEL_PWA.md` §5 impose la meme source
     * que le controle qui refuse vraiment l'acces. La verification est faite
     * ROLE PAR ROLE et MODULE PAR MODULE contre `Role::niveauSurModule()` — pas
     * contre une matrice recopiee ici, qui ne verifierait qu'elle-meme.
     */
    #[Test]
    public function la_matrice_des_roles_vaut_ce_que_le_serveur_applique(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/roles-permissions')->assertOk()->getContent();

        $roles = Role::query()->with('permissions')->orderBy('libelle')->get();
        $this->assertGreaterThanOrEqual(11, $roles->count(), 'Le referentiel de roles est vide : le cas serait vert a vide.');

        $verifiees = 0;

        foreach ($roles as $role) {
            foreach (array_keys(RolesPermissions::MODULES) as $module) {
                $niveau = $role->niveauSurModule($module);
                $verifiees++;

                $this->assertStringContainsString(
                    '>'.$niveau.'</span>',
                    $html,
                    "Le niveau {$niveau} n'apparait nulle part pour {$role->libelle}/{$module}.",
                );
            }
        }

        $this->assertGreaterThanOrEqual(11 * 16, $verifiees);

        // Les seize libelles de module du maitre, avec SES abreviations.
        foreach (RolesPermissions::MODULES as $libelle) {
            $this->assertStringContainsString(e($libelle), $html);
        }
    }

    /**
     * Aucune action d'ecriture sur la matrice, et le badge d'etat du maitre
     * n'est pas affiche — le serveur ne conserve aucune trace du socle.
     */
    /**
     * ⚠ GARDE INVERSÉE le 01/09/2026 (vague F, directive PO) : la page des
     * rôles ÉDITE réellement — « + Nouveau rôle », « Rétablir le socle »,
     * « Modifier les droits ». Ce qui se mesure désormais : les boutons
     * existent pour un rôle autorisé, N'EXISTENT PAS pour un rôle en
     * lecture, et le badge « Conforme au socle » est DÉRIVÉ (rendu réel).
     */
    #[Test]
    public function la_page_des_roles_offre_l_edition_aux_seuls_roles_autorises(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/roles-permissions')->assertOk()->getContent();

        $this->assertStringContainsString(e((string) __('pwa.roles.bouton_nouveau_role')), $html);
        $this->assertStringContainsString(e((string) __('pwa.roles.bouton_retablir_socle')), $html);
        $this->assertStringContainsString(e((string) __('pwa.roles.badge_conforme')), $html);

        // Un rôle SANS droit sur ROLES est déjà refusé à la route (403,
        // cas RBAC plus haut) : la contre-épreuve du masquage niveau 1 se
        // joue donc sur l'existence même des boutons pour l'autorisé —
        // vérifiée ci-dessus — et le refus de route pour les autres.
    }

    /* ------------------------------------------------------------ Paramètres */

    /**
     * Les SEPT onglets de `Parametres::ONGLETS` sont RENDUS dans l'ordre du
     * registre, le premier actif par defaut (Article 4.5).
     *
     * ⚠ Jusqu'au 10/09/2026, ce cas relevait les onglets dans
     * `prototype_v2/pages/parametres.html` : comparer le HTML servi a la seule
     * constante avait ete juge tautologique — permuter deux onglets dans la
     * constante ne faisait rougir aucune assertion, le rendu suivant la
     * constante mutee. Depuis PA-183 la vue Blade EST le maitre, et la
     * constante qu'elle rend en est le registre : il n'existe plus de reference
     * exterieure a laquelle confronter l'ORDRE du registre lui-meme. Ce que ce
     * cas prouve desormais, c'est que la page SERVIE rend le registre
     * fidelement — memes onglets, meme ordre, meme onglet actif — et qu'il en
     * compte sept. Une permutation VOULUE du registre se relit donc a la revue,
     * pas ici : c'est ecrit plutot que suppose.
     */
    #[Test]
    public function les_sept_onglets_de_parametres_sont_rendus_dans_l_ordre_du_registre(): void
    {
        // Plancher : un registre vide rendrait la boucle vide, donc verte.
        $this->assertCount(7, Parametres::ONGLETS, 'Le registre ne porte plus sept onglets : confronter avant de corriger.');

        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/parametres')->assertOk()->getContent();

        $positionPrecedente = -1;
        $index = 0;

        foreach (Parametres::ONGLETS as $libelle) {
            $position = strpos($html, '>'.e($libelle).'</a>');
            $this->assertIsInt($position, "L'onglet « {$libelle} » n'est pas rendu.");
            $this->assertGreaterThan(
                $positionPrecedente,
                $position,
                "L'onglet « {$libelle} » ne vient pas dans l'ordre du registre.",
            );
            $positionPrecedente = $position;

            // Le PREMIER onglet du registre est celui qui s'ouvre par defaut
            // (Article 4.5 : « meme onglet actif par defaut »). L'etat actif
            // se lit du REGISTRE UNIQUE des classes d'onglets (directive PO
            // du 01/09/2026) — la chaine litterale d'avant a vieilli le jour
            // ou `shadow-sm` s'y est ajoute.
            if ($index === 0) {
                $this->assertStringContainsString(
                    \App\Pwa\Support\Onglets::ACTIF.'">'.e($libelle),
                    $html,
                );
            }

            $index++;
        }
    }

    /**
     * Les QUATRE groupes du registre serveur sont rendus, y compris les DEUX
     * que le maitre n'a aucun onglet pour montrer — mais chacun sous SON
     * onglet, jamais tous a la fois (corrige le 01/09/2026 : l'audit
     * navigateur du Product Owner a releve que les sept onglets rendaient un
     * contenu identique, le clic ne changeant que la mise en surbrillance).
     *
     * C'est la decision n° 2 de `DIRECTIVE_CONFORMITE_100.md` : aucun groupe
     * reel ne disparait derriere aucun onglet. Sans ce cas, les neuf
     * parametres sociaux et d'exploitation pourraient redevenir invisibles
     * sans qu'une seule assertion bouge.
     */
    #[Test]
    public function aucun_groupe_du_registre_serveur_ne_disparait_derriere_un_onglet(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $groupesVus = [];

        foreach (RegistreParametres::definitions() as $definition) {
            // La correspondance des comptes (26/10/2026) a son propre ecran ;
            // `la_correspondance_des_comptes_ne_se_montre_pas_dans_parametres`
            // prouve qu'elle n'est rendue sous aucun onglet.
            if ($definition->groupe === RegistreParametres::GROUPE_COMPTES) {
                continue;
            }

            $onglet = Parametres::ongletDe($definition);
            $groupesVus[$definition->groupe] = true;

            $html = (string) $this->get('/pwa/parametres?onglet=' . $onglet)->assertOk()->getContent();

            $this->assertStringContainsString(
                e($definition->libelle),
                $html,
                "Le parametre « {$definition->libelle} » ({$definition->groupe}) n'est pas rendu sous l'onglet « {$onglet} ».",
            );
        }

        // Plancher : un registre vide rendrait la boucle verte a vide.
        $this->assertGreaterThanOrEqual(4, count($groupesVus));
        $this->assertSame(
            Parametres::GROUPES_IDENTITE,
            array_keys($groupesVus),
            'Un groupe du registre serveur n\'est rendu sous aucun onglet.',
        );
    }

    #[Test]
    public function la_correspondance_des_comptes_ne_se_montre_pas_dans_parametres(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $declarees = array_filter(
            RegistreParametres::definitions(),
            static fn ($d): bool => $d->groupe === RegistreParametres::GROUPE_COMPTES,
        );
        // Plancher : un registre sans ces cles rendrait le balayage vert a vide.
        $this->assertGreaterThanOrEqual(15, count($declarees));

        foreach (array_keys(Parametres::ONGLETS) as $onglet) {
            $html = (string) $this->get('/pwa/parametres?onglet=' . $onglet)->assertOk()->getContent();

            foreach ($declarees as $definition) {
                $this->assertStringNotContainsString(e($definition->libelle), $html);
                $this->assertStringNotContainsString($definition->cle, $html);
            }
        }
    }

    /**
     * CHAQUE ONGLET SERT SES GROUPES, ET EUX SEULS.
     *
     * C'est le defaut precis releve par l'audit navigateur : les sept onglets
     * de Parametres rendaient tous le MEME contenu, le parametre `onglet`
     * n'etant jamais exploite par la vue. Un parametre du groupe `entreprise`
     * (rendu sous « Identite & Legal ») ne doit pas apparaitre sous
     * « Activation & Securite », qui sert `social` et `exploitation`.
     */
    #[Test]
    public function un_onglet_ne_sert_pas_les_groupes_d_un_autre_onglet(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $htmlIdentite = (string) $this->get('/pwa/parametres?onglet=identite')->assertOk()->getContent();
        $htmlActivation = (string) $this->get('/pwa/parametres?onglet=activation')->assertOk()->getContent();

        $cleEntreprise = \App\Shared\ReportEngine\Services\ReportHeaderService::CLE_RAISON_SOCIALE;
        $definitionEntreprise = RegistreParametres::definition($cleEntreprise);
        $this->assertNotNull($definitionEntreprise);

        $cleSocial = \App\Domain\Rh\Services\CalculPaieService::CLE_VPS;
        $definitionSocial = RegistreParametres::definition($cleSocial);
        $this->assertNotNull($definitionSocial);

        // Le groupe entreprise est servi par « identite », pas par « activation ».
        $this->assertStringContainsString(e($definitionEntreprise->libelle), $htmlIdentite);
        $this->assertStringNotContainsString(e($definitionEntreprise->libelle), $htmlActivation);

        // Le groupe social est servi par « activation », pas par « identite ».
        $this->assertStringContainsString(e($definitionSocial->libelle), $htmlActivation);
        $this->assertStringNotContainsString(e($definitionSocial->libelle), $htmlIdentite);
    }

    /**
     * Article 7 sur un taux REGLEMENTAIRE : une cle non renseignee rend « — »,
     * une cle a zero rend « 0 ».
     *
     * C'est le cas de `taux_cnss_risques_professionnels` (PA-53) : un taux
     * absent fait publier une fourchette, un taux a 0 % serait une charge
     * patronale nulle. Les confondre a l'ecran ferait croire l'arbitrage rendu.
     * La cle vit dans le groupe `social`, servi par l'onglet « activation ».
     */
    #[Test]
    public function un_parametre_non_renseigne_rend_un_tiret_et_un_zero_reste_zero(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/parametres?onglet=activation')->assertOk()->getContent();
        $this->assertStringContainsString('bg-slate-100 text-slate-600">—</p>', $html);

        ParametreSysteme::create([
            'id' => (string) Str::uuid(),
            'cle' => \App\Domain\Rh\Services\CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS,
            'valeur' => '0',
        ]);

        $htmlZero = (string) $this->get('/pwa/parametres?onglet=activation')->assertOk()->getContent();
        $this->assertStringContainsString('bg-slate-100 text-slate-600">0</p>', $htmlZero);
    }

    /**
     * L'ONGLET « CANAUX DE RESERVATION » N'EST PLUS VIDE.
     *
     * `canaux_reservation` est un referentiel reel depuis PA-163
     * (01/09/2026) : l'ecran lit desormais les canaux existants au lieu de ne
     * rien montrer sous cet onglet.
     */
    #[Test]
    public function l_onglet_canaux_rend_les_canaux_de_reservation_reels(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        \App\Domain\Hebergement\Models\CanalReservation::query()->delete();
        \App\Domain\Hebergement\Models\CanalReservation::create([
            'id' => (string) Str::uuid(),
            'nom' => 'Canal de test PWA',
            'actif' => true,
        ]);
        \App\Domain\Hebergement\Models\CanalReservation::create([
            'id' => (string) Str::uuid(),
            'nom' => 'Canal desactive de test',
            'actif' => false,
        ]);

        $html = (string) $this->get('/pwa/parametres?onglet=canaux')->assertOk()->getContent();

        $this->assertStringContainsString('Canal de test PWA', $html);
        $this->assertStringContainsString('Canal desactive de test', $html);
        $this->assertStringContainsString(__('pwa.parametres.canaux_etat_actif'), $html);
        $this->assertStringContainsString(__('pwa.parametres.canaux_etat_desactive'), $html);
    }

    /**
     * AUCUN SECRET N'ATTEINT L'ECRAN.
     *
     * Deux moities : le registre lui-meme ne peut pas porter de cle secrete
     * (`MOTIFS_SECRET`), et l'ecran n'affiche QUE le registre. La seconde est
     * ce qui rend la premiere suffisante — sans elle, une valeur posee dans
     * `parametres_systeme` par un autre chemin pourrait remonter.
     */
    #[Test]
    public function aucun_secret_n_est_rendu_par_l_ecran_parametres(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // Une valeur secrete posee DIRECTEMENT en base, hors registre.
        ParametreSysteme::create([
            'id' => (string) Str::uuid(),
            'cle' => 'whatsapp_api_key',
            'valeur' => 'SECRET-QUI-NE-DOIT-PAS-SORTIR',
        ]);

        $html = (string) $this->get('/pwa/parametres')->assertOk()->getContent();

        $this->assertStringNotContainsString('SECRET-QUI-NE-DOIT-PAS-SORTIR', $html);
        $this->assertStringNotContainsString('whatsapp_api_key', $html);

        foreach (RegistreParametres::MOTIFS_SECRET as $motif) {
            foreach (RegistreParametres::definitions() as $definition) {
                $this->assertStringNotContainsString(
                    $motif,
                    $definition->cle,
                    'Une cle du registre porte un motif de secret.',
                );
            }
        }
    }

    /* -------------------------------------------------------- Import & Export */

    /**
     * ⚠ GARDE INVERSÉE le 01/09/2026 (vague F) : Import & Export AGIT —
     * sauvegarde réelle, restauration honnête, réinitialisation DOUBLEMENT
     * confirmée et REFUSÉE en production. Ce qui se mesure : le bouton de
     * sauvegarde présent pour un rôle autorisé, et AUCUNE phrase de
     * l'ancien refus (les clés retirées ne doivent pas revenir).
     */
    #[Test]
    public function import_export_agit_reellement_et_l_ancien_refus_ne_revient_pas(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        // L'onglet Sauvegardes porte le bouton — le défaut est « Importer ».
        $html = (string) $this->get('/pwa/import-export?onglet=sauvegardes')->assertOk()->getContent();

        foreach (['refus_importer', 'refus_sauvegardes', 'refus_restaurer', 'refus_seeders', 'refus_modales'] as $cle) {
            $traduction = (string) __('pwa.import_export.'.$cle);

            if ($traduction !== 'pwa.import_export.'.$cle) {
                $this->assertStringNotContainsString(e($traduction), $html);
            }
        }

        $this->assertStringContainsString(e((string) __('pwa.import_export.sauvegardes_generer')), $html);
    }

    /**
     * Le rythme de sauvegarde affiche est celui de la PLANIFICATION REELLE,
     * pas le « Hebdomadaire » du maitre — et la date de derniere sauvegarde
     * vient d'un fichier VERIFIE, jamais d'une supposition.
     *
     * PA-60 : un fichier de 802 octets au nom conforme avait ete pris pour
     * une sauvegarde. CONTRAT REVISE le 02/09/2026 (directive PO, les 4 KPI
     * du maitre) : la date EST desormais affichee — elle est mesuree sur le
     * fichier reel le plus recent, et les dumps incomplets sont retires par
     * le Job avant d'etre listes (c'est ce qui rend l'affichage honnete la ou
     * il ne l'aurait pas ete en 08/2026). Sans aucun fichier, le KPI rend
     * « — », jamais une date.
     */
    #[Test]
    public function import_export_ne_promet_aucune_sauvegarde_qu_il_n_a_pas_verifiee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/import-export?onglet=sauvegardes')->assertOk()->getContent();

        // Clé renommée `sauvegardes_rythme` par la vague F (01/09/2026) —
        // le fait énoncé reste le même : la planification RÉELLE (chaque
        // nuit à 02h00), jamais le « Hebdomadaire » du maître.
        $this->assertStringContainsString(e((string) __('pwa.import_export.sauvegardes_rythme')), $html);
        $this->assertStringNotContainsString('Hebdomadaire<', $html);
        $this->assertStringContainsString('chaque nuit', (string) __('pwa.import_export.sauvegardes_rythme'));

        // Les 4 KPI du maître sont rendus, dont « Dernière sauvegarde ».
        $this->assertStringContainsString(e((string) __('pwa.import_export.kpi_derniere')), $html);
        $this->assertStringContainsString(e((string) __('pwa.import_export.kpi_rythme_valeur')), $html);
    }

    /* ------------------------------------------------------------- Le châssis */

    /**
     * ARTICLE 3.3 — les entrees du menu de compte NAVIGUENT vers l'ecran reel
     * quand le profil y a droit, et restent inertes AVEC LA BONNE RAISON
     * sinon.
     *
     * TROIS raisons cohabitent, et les confondre coute cher : « a venir » fait
     * attendre une livraison, « hors perimetre » ferme la question, « sans
     * droit » designe un ecran qui EXISTE et un acces a demander. Ce cas
     * eprouve les deux etats de la meme entree.
     */
    #[Test]
    public function les_entrees_du_menu_de_compte_naviguent_ou_disent_pourquoi_pas(): void
    {
        $administrateur = $this->utilisateur('administrateur');
        $liens = MenuLateral::liensChassis($administrateur);

        foreach (['journal_audit', 'mon_profil', 'parametres_compte', 'aide_a_propos', 'contact_editeur', 'import_export'] as $cle) {
            $this->assertNotNull($liens[$cle]['url'], "L'entree {$cle} ne navigue pas pour un administrateur.");
        }

        $html = (string) $this->actingAs($administrateur)->get('/pwa')->assertOk()->getContent();
        $this->assertStringContainsString('href="'.route('pwa.mon-profil').'"', $html);
        $this->assertStringContainsString('href="'.route('pwa.aide-a-propos').'"', $html);

        // Un `guide` n'a ni PARAM ni M14 : trois entrees redeviennent inertes,
        // et le titre dit « sans droit », pas « a venir ».
        $guide = $this->utilisateur('guide');
        $liensGuide = MenuLateral::liensChassis($guide);

        $this->assertNull($liensGuide['parametres_compte']['url']);
        $this->assertNull($liensGuide['journal_audit']['url']);
        $this->assertSame('pwa.coquille.sans_droit', $liensGuide['parametres_compte']['raison']);
        $this->assertNotNull($liensGuide['mon_profil']['url'], 'Mon profil ne depend d\'aucun module.');

        $htmlGuide = (string) $this->actingAs($guide)->get('/pwa')->assertOk()->getContent();
        $this->assertStringContainsString(e((string) __('pwa.coquille.sans_droit')), $htmlGuide);
    }

    /**
     * Le `<main>` de la page, sans la coquille.
     *
     * La barre superieure et le menu lateral portent des boutons qui ne sont
     * pas l'objet des cas de saisie : les inclure ferait rougir un controle
     * pourtant exact, et la reaction serait de l'assouplir.
     */
    private function corpsPrincipal(string $html, string $page): string
    {
        $debut = strpos($html, '<main class="flex-1 overflow-y-auto">');
        $this->assertIsInt($debut, "Le <main> de la page {$page} est introuvable.");

        $fin = strpos($html, '</main>', $debut);
        $this->assertIsInt($fin, "La fermeture du <main> de la page {$page} est introuvable.");

        return substr($html, $debut, $fin - $debut);
    }

    /**
     * La ligne `<tr>` du journal qui porte un identifiant donne.
     *
     * Compter les tirets sur la page entiere ne dirait rien : le bloc de
     * refus en contient, et le decompte resterait vert quoi qu'il arrive.
     */
    private function extraireLigneDuJournal(string $corps, string $identifiant): string
    {
        $position = strpos($corps, $identifiant);
        $this->assertIsInt($position, "L'entree {$identifiant} n'est pas rendue.");

        $debut = strrpos(substr($corps, 0, $position), '<tr');
        $this->assertIsInt($debut, 'La ligne de tableau est introuvable.');

        $fin = strpos($corps, '</tr>', $debut);
        $this->assertIsInt($fin, 'La fermeture de la ligne est introuvable.');

        return substr($corps, $debut, $fin - $debut);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.transverse',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
