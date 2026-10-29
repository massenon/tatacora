<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Support\MenuLateral;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Conformité de la COQUILLE et des pages hors session de la PWA —
 * BRIEFS_AGENTS.md §B1.
 *
 * La vue Blade est le maître depuis le 10/09/2026 (PA-182, PA-183) :
 * `prototype_v2/`, qui a servi de maquette jusque-là, est une ancienne version
 * et n'est plus lu ici. Ces vérifications figent les traits de mise en page
 * qu'un remaniement futur ferait disparaître sans que personne ne s'en
 * aperçoive ; la conformité visuelle, elle, se juge à l'œil.
 *
 * Ce qui EST vérifiable automatiquement, et l'est ici :
 *  - les deux colonnes de l'écran de connexion ;
 *  - la coquille — barre supérieure, menu latéral rendu dans l'ordre de
 *    `MenuLateral::NAVIGATION` avec les icônes de `MenuLateral::ICONES`, voile
 *    mobile, menu de compte ;
 *  - l'écran de démarrage, sans la session fabriquée que l'ancienne maquette
 *    y posait (SECURITY_STRICT.md §12bis) ;
 *  - l'absence totale de ressource distante, sur toutes les pages servies ;
 *  - la feuille servie porte les règles dont la coquille dépend.
 *
 * ## Ce qui a été RETIRÉ le 10/09/2026, et pourquoi
 *
 * Quatre cas confrontaient la vue à `prototype_v2/assets/js/shell.js` sans
 * qu'aucun invariant n'en subsiste une fois la maquette retirée : les classes
 * de la barre latérale, les classes de tout le châssis (35 éléments), les
 * tracés SVG de la barre supérieure et les libellés du châssis. La vue étant
 * désormais la référence, les re-cibler sur elle-même ne prouverait rien. La
 * conformité du client Flutter à cette vue est mesurée par
 * `tatacora_flutter/tool/conformite_blade/`.
 *
 * Cinq cas ont été CONVERTIS en invariants qui ne demandent aucune référence
 * extérieure : l'ordre du menu rendu, les icônes rendues depuis leur registre,
 * l'ordre horizontal de la barre supérieure, la structure du menu de compte,
 * la cohérence du panneau latéral et de son voile — plus la feuille servie,
 * qui n'est plus comparée à celle de la maquette mais doit porter les règles
 * de la coquille.
 */
final class ConformiteMaquettePwaTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // ------------------------------------------------------- Écran de connexion

    /**
     * Refonte du 29/10/2026 (PO, docs/HANDOFF_ECRAN_CONNEXION_LOGIRESTOCK.md) :
     * l'écran de connexion est une CARTE UNIQUE centrée, dans l'ordre du
     * handoff : marque, slogan, bandeau de sept pictogrammes, accueil, deux
     * champs, « Se souvenir de moi » / « Mot de passe oublié ? », bouton. Le
     * panneau image à deux colonnes de l'ancienne maquette n'existe plus.
     */
    #[Test]
    public function l_ecran_de_connexion_est_une_carte_unique_dans_l_ordre_du_handoff(): void
    {
        $html = (string) $this->get('/pwa/connexion')->getContent();

        // Plus de panneau image.
        $this->assertStringNotContainsString('hidden lg:block lg:w-1/2', $html);
        $this->assertStringNotContainsString('gite-cover.jpg', $html);
        $this->assertStringContainsString('max-w-[560px]', $html);

        // Les libellés, dans l'ordre exact du document (apostrophes décodées).
        $texte = html_entity_decode($html, ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $ordre = [
            'Logi', 'ReStock', 'TATACORA AFRIQUE',
            'VOTRE LOGICIEL DE GESTION INTÉGRÉE',
            'Restauration', 'Hébergement', 'Éco-tourisme', 'Stock', 'Location', 'Caisse', 'Comptabilité',
            'Bienvenue !',
            'Connectez-vous à votre espace d\'administration LogiReStock.',
            'NOM D\'UTILISATEUR OU E-MAIL',
            'MOT DE PASSE',
            'Se souvenir de moi',
            'Mot de passe oublié ?',
            'SE CONNECTER',
        ];
        $position = 0;
        foreach ($ordre as $libelle) {
            $trouve = strpos($texte, $libelle, $position);
            $this->assertNotFalse($trouve, "« {$libelle} » absent ou hors d'ordre.");
            $position = $trouve + strlen($libelle);
        }

        // Sept pictogrammes de module, tous décoratifs, plus la marque.
        $this->assertSame(7, substr_count($html, '<li title="'));
        $this->assertStringNotContainsString('<img', $html);

        // Accessibilité : labels explicites, autocomplete, œil nommé et pressé.
        $this->assertStringContainsString('<label for="champ-identifiant"', $html);
        $this->assertStringContainsString('<label for="champ-motdepasse"', $html);
        $this->assertStringContainsString('autocomplete="username"', $html);
        $this->assertStringContainsString('autocomplete="current-password"', $html);
        $this->assertStringContainsString('aria-label="Afficher le mot de passe"', $html);
        $this->assertStringContainsString('aria-pressed', $html);

        // L'ordre de tabulation est celui du document : identifiant, mot de
        // passe, œil, case, lien, bouton (aucun tabindex positif).
        $this->assertDoesNotMatchRegularExpression('#tabindex="[1-9]#', $html);
        $suite = ['id="champ-identifiant"', 'id="champ-motdepasse"', 'aria-pressed', 'type="checkbox"', 'aria-controls="aide-mot-de-passe-oublie"', 'type="submit"'];
        $position = 0;
        foreach ($suite as $element) {
            $trouve = strpos($html, $element, $position);
            $this->assertNotFalse($trouve, "{$element} hors de l'ordre de tabulation.");
            $position = $trouve + strlen($element);
        }

        // « Se souvenir » ne mémorise jamais le mot de passe.
        $this->assertSame(1, substr_count($html, 'setItem(this'));
        $this->assertSame(1, substr_count($html, 'localStorage.setItem(this.cle, this.$refs.identifiant.value)'));

        // Titre d'onglet : le <h1> « Connexion » suivi de la marque.
        $this->assertStringContainsString('<title>Connexion — LogiReStock</title>', $html);
    }

    /**
     * Decision du PO du 29/10/2026 : le logo TELEVERSE coiffe la carte de
     * connexion (hauteur 64, proportions gardees, alt = nom de la marque) ;
     * absent, le pictogramme de marque prend sa place. « LogiReStock » reste.
     */
    #[Test]
    public function le_logo_televerse_coiffe_la_carte_et_son_absence_laisse_le_pictogramme(): void
    {
        \Illuminate\Support\Facades\Storage::fake(\App\Shared\Parametres\Services\ApparenceEtablissementService::DISQUE);

        $sans = (string) $this->get('/pwa/connexion')->getContent();
        $this->assertStringNotContainsString('<img', $sans);
        $this->assertStringContainsString('M12 22V12', $sans, 'Repli : le pictogramme de marque.');

        \Illuminate\Support\Facades\Storage::disk(\App\Shared\Parametres\Services\ApparenceEtablissementService::DISQUE)
            ->put(\App\Shared\Parametres\Services\ApparenceEtablissementService::REPERTOIRE.'/logo.png', 'x');

        $avec = (string) $this->get('/pwa/connexion')->getContent();
        $this->assertMatchesRegularExpression('#<img src="[^"]*/pwa/apparence/logo[^"]*" alt="Logo TATACORA AFRIQUE" class="[^"]*h-16[^"]*object-contain#', $avec);
        $this->assertStringNotContainsString('M12 22V12', $avec, 'Le pictogramme cede la place au logo.');
        $this->assertStringContainsString('>Logi<', $avec);
        $this->assertStringContainsString('>ReStock<', $avec);
    }

    /**
     * `SECURITY_STRICT.md` §12 : la grille de 11 comptes de demonstration
     * cliquables (connexion instantanee sans mot de passe) de l'ancienne
     * maquette n'existe dans AUCUN environnement, et le texte qui l'annonce
     * (« […] cliquez pour vous connecter instantanement […] ») ne survit pas
     * seul — mecanisme decrit en tete de `pwa.livewire.connexion`.
     *
     * Mutation jouee le 01/09/2026 : reintroduire la chaine recyclee
     * (« cliquez pour vous connecter instantanement ») dans la vue fait
     * echouer ce test (rouge), la retirer le fait repasser au vert.
     */
    #[Test]
    public function la_grille_de_comptes_demo_n_est_jamais_rendue_a_l_ecran_de_connexion(): void
    {
        $html = (string) $this->get('/pwa/connexion')->getContent();

        $this->assertStringNotContainsString('grille-comptes-demo', $html);
        $this->assertStringNotContainsString('bouton-compte-demo', $html);
        $this->assertStringNotContainsString('Comptes de démonstration', $html);
        $this->assertStringNotContainsString('cliquez pour vous connecter', $html);
    }

    /**
     * Le bandeau rouge d'echec (`#erreur-identifiants`) n'apparait QUE sur un
     * refus reel — l'ancienne maquette le laissait dans le DOM avec la classe
     * `hidden` et le revelait en JavaScript.
     */
    #[Test]
    public function le_bandeau_d_echec_n_apparait_qu_en_cas_de_refus(): void
    {
        $this->assertStringNotContainsString(
            'erreur-identifiants',
            (string) $this->get('/pwa/connexion')->getContent(),
        );

        \Livewire\Livewire::test(\App\Pwa\Livewire\Connexion::class)
            ->set('login', 'inconnu')
            ->set('motDePasse', 'mauvais')
            ->call('seConnecter')
            ->assertSee('erreur-identifiants', escape: false);
    }

    // ------------------------------------------------------- Écran de démarrage

    #[Test]
    public function la_racine_conduit_a_l_ecran_de_demarrage(): void
    {
        $this->get('/')->assertRedirect('/pwa/demarrage');
    }

    #[Test]
    public function l_ecran_de_demarrage_reprend_la_maquette_sans_session_fabriquee(): void
    {
        $html = (string) $this->get('/pwa/demarrage')->assertOk()->getContent();

        // Composition et animations decalees de l ecran de demarrage.
        $this->assertStringContainsString('fond-splash', $html);
        $this->assertStringContainsString('anim-1', $html);
        $this->assertStringContainsString('anim-4', $html);
        $this->assertStringContainsString('barre-progression', $html);
        $this->assertStringContainsString('GÎTE CHEZ NOËL — AGENCE DE VOYAGES &amp; HÉBERGEMENT', $html);
        $this->assertStringContainsString('PAEB', $html);
        $this->assertStringContainsString('FAGUEZ SARL', $html);

        // Les etapes de chargement, dans l'ordre.
        foreach (['Initialisation du système', 'Chargement de la charte graphique', 'Prêt.'] as $etape) {
            $this->assertStringContainsString($etape, $html);
        }

        // SECURITY_STRICT.md §12bis : l'ancienne maquette ecrivait une session
        // Administrateur dans `localStorage` quand aucune n'existait — un
        // contournement complet de l'ecran de connexion. Rien de tel ici : la
        // page ne connait aucun compte et ne touche a aucun stockage.
        $this->assertStringNotContainsString('localStorage', $html);
        $this->assertStringNotContainsString('COMPTES_DEMO', $html);
        $this->assertStringNotContainsString('admin', $html);

        // Et la redirection finale passe par une route protegee, pas par une
        // page d'accueil choisie cote client.
        $this->assertStringContainsString(route('pwa.accueil'), $html);

        // Le trajet reel : un invite qui suit cette redirection tombe sur le
        // formulaire de connexion, jamais sur une page de donnees.
        $this->get(route('pwa.accueil'))->assertRedirect('/pwa/connexion');
    }

    // ---------------------------------------------------------------- Coquille

    #[Test]
    public function la_coquille_reprend_la_barre_superieure_le_menu_et_le_voile_mobile(): void
    {
        // Administrateur et plus gerant depuis le 03/09/2026 : le PO masque
        // au gerant plusieurs groupes du menu (ROUTES_MASQUEES_PAR_ROLE) —
        // ce cas verifie la coquille COMPLETE, il lui faut un role complet.
        $this->actingAs($this->creerUtilisateur('administrateur'));

        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        // Les quatre blocs de la coquille, dans l'ordre du gabarit.
        foreach (['shell-topbar', 'shell-banniere', 'shell-sidebar', '<main'] as $bloc) {
            $this->assertStringContainsString($bloc, $html);
        }

        $positions = array_map(
            static fn (string $bloc): int => (int) strpos($html, $bloc),
            ['shell-topbar', 'shell-banniere', 'shell-sidebar'],
        );
        $ordonnees = $positions;
        sort($ordonnees);
        $this->assertSame($ordonnees, $positions, 'L\'ordre des blocs de la coquille a change.');

        // Barre superieure : hauteur, fond, bouton de menu mobile, cloche,
        // menu de profil.
        $this->assertStringContainsString('h-16 bg-[var(--navy)] flex items-center px-4 sm:px-6 shrink-0 z-30', $html);
        $this->assertStringContainsString('bouton-menu-mobile', $html);
        $this->assertStringContainsString('bouton-cloche-notifications', $html);
        $this->assertStringContainsString('bouton-menu-profil', $html);

        // Menu lateral : largeur, comportement escamotable, voile.
        $this->assertStringContainsString('w-[264px] bg-[var(--navy)]', $html);
        $this->assertStringContainsString('-translate-x-full lg:translate-x-0 transition-transform duration-200', $html);
        $this->assertStringContainsString('overlay-sidebar-mobile', $html);

        // Groupes et entrees, DERIVES du registre plutot que recopies. La
        // chaine de verite est unique : MenuLateral::NAVIGATION -> HTML servi.
        // Ce cas tient la PRESENCE ; l'ORDRE est tenu par
        // `le_menu_est_rendu_dans_l_ordre_de_son_registre()`.
        //
        // Le `&` est echappe par Blade : c'est `&amp;` qui figure dans le HTML.
        $echapper = static fn (string $t): string => htmlspecialchars($t, ENT_QUOTES);

        $groupes = 0;
        $entrees = 0;
        foreach (MenuLateral::NAVIGATION as $entree) {
            if (isset($entree['groupe'])) {
                $this->assertStringContainsString(
                    $echapper(mb_strtoupper((string) $entree['groupe'])),
                    $html,
                    'Groupe absent du menu servi : ' . $entree['groupe'],
                );
                $groupes++;
            }

            foreach ($entree['items'] ?? [$entree] as $item) {
                $this->assertStringContainsString(
                    $echapper((string) $item['nom']),
                    $html,
                    'Entree absente du menu servi : ' . $item['nom'],
                );
                $entrees++;
            }
        }

        // Plancher : un registre vide rendrait la boucle vide, donc verte.
        $this->assertGreaterThanOrEqual(8, $groupes);
        $this->assertGreaterThanOrEqual(24, $entrees);

        // Badges du registre.
        $this->assertStringContainsString('MECeF', $html);
        $this->assertStringContainsString('SYSCOHADA', $html);

        // Pied du menu.
        $this->assertStringContainsString('TATACORA AFRIQUE — PAEB / FAGUEZ SARL', $html);
    }

    /**
     * Le filtrage RBAC du menu : un module a `'-'` n'est pas grise, il est
     * ABSENT. Verifie sur le rendu reel de la page, pas sur la valeur de
     * retour de la methode : un menu correctement calcule mais mal affiche
     * resterait une fuite.
     */
    #[Test]
    public function le_menu_lateral_masque_les_modules_sans_droit(): void
    {
        $this->actingAs($this->creerUtilisateur('guide'));

        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        // Le guide a M9 = 'C' et M8 = 'L' : ces deux entrees sont visibles.
        // Les libelles viennent du registre, jamais recopies (voir plus haut).
        $this->assertStringContainsString(
            htmlspecialchars(self::libelleDuModule('M9'), ENT_QUOTES),
            $html,
        );
        $this->assertStringContainsString(
            htmlspecialchars(self::libelleDuModule('M8'), ENT_QUOTES),
            $html,
        );

        // M11, M6, M2, M13, M10 valent '-' : leurs entrees sont absentes, et
        // les groupes devenus vides disparaissent avec elles.
        foreach (['Tableau de bord', 'Stocks', 'Facturation', 'Personnel &amp; Paie', 'Comptabilité'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $html);
        }
        foreach (['APPROVISIONNEMENT', 'FINANCE', 'RESSOURCES HUMAINES'] as $groupeVide) {
            $this->assertStringNotContainsString($groupeVide, $html);
        }

        // Contre-epreuve : ces memes entrees existent pour un role qui y a droit.
        // Sans elle, un menu vide par erreur ferait passer le test ci-dessus.
        // ⚠ ADMINISTRATEUR et plus gerant depuis le 03/09/2026 : la
        // directive PO masque au gerant Facturation, Personnel & Paie et
        // Comptabilite (MenuLateral::ROUTES_MASQUEES_PAR_ROLE, tenu par
        // MenuLateralParRoleTest) — la contre-epreuve « un role plein voit
        // tout » a besoin d'un role qui voit reellement tout.
        $this->actingAs($this->creerUtilisateur('administrateur', 'actif', 'autre.compte'));
        $htmlComplet = (string) $this->get('/pwa')->assertOk()->getContent();
        foreach (['Tableau de bord', 'Stocks', 'Facturation', 'Personnel &amp; Paie', 'Comptabilité'] as $attendu) {
            $this->assertStringContainsString($attendu, $htmlComplet);
        }
    }

    /**
     * Le menu est RENDU dans l'ordre de son registre — groupes et entrées.
     *
     * Jusqu'au 10/09/2026, ce cas comparait `MenuLateral::NAVIGATION` à la
     * constante `NAVIGATION` de `prototype_v2/assets/js/shell.js`. La vue
     * étant le maître (PA-183), le registre EST la référence ; ce qui reste à
     * prouver, c'est que la page servie le rend fidèlement — même contenu et
     * MÊME ORDRE. Le cas précédent tient la présence ; seul celui-ci tient
     * l'ordre : une boucle de vue réordonnée, un tri ajouté, et le menu
     * changerait sans qu'aucun autre test ne bouge.
     */
    #[Test]
    public function le_menu_est_rendu_dans_l_ordre_de_son_registre(): void
    {
        $this->actingAs($this->creerUtilisateur('administrateur'));
        $menu = $this->extraireBloc(
            (string) $this->get('/pwa')->assertOk()->getContent(),
            '<aside id="sidebar"',
            'overlay-sidebar-mobile',
        );

        $curseur = 0;
        $groupes = 0;
        $entrees = 0;

        foreach (MenuLateral::NAVIGATION as $entree) {
            if (isset($entree['groupe'])) {
                $curseur = $this->positionApres(
                    $menu,
                    htmlspecialchars(mb_strtoupper((string) $entree['groupe']), ENT_QUOTES),
                    $curseur,
                    'Le groupe « '.$entree['groupe'].' »',
                );
                $groupes++;
            }

            foreach ($entree['items'] ?? [$entree] as $item) {
                $curseur = $this->positionApres(
                    $menu,
                    htmlspecialchars((string) $item['nom'], ENT_QUOTES),
                    $curseur,
                    'L entree « '.$item['nom'].' »',
                );
                $entrees++;
            }
        }

        // Plancher : un registre vide rendrait la boucle vide, donc verte.
        $this->assertGreaterThanOrEqual(8, $groupes);
        $this->assertGreaterThanOrEqual(24, $entrees);
    }

    /**
     * La position du texte `$libelle` rendu comme CONTENU d'une balise
     * (`>Libelle<`, espaces tolerees), cherchee APRES `$depuis` — ou un echec
     * qui dit que l'element manque ou n'est plus a sa place.
     */
    private function positionApres(string $html, string $libelle, int $depuis, string $quoi): int
    {
        $trouve = preg_match(
            '#>\s*'.preg_quote($libelle, '#').'\s*<#u',
            $html,
            $capture,
            PREG_OFFSET_CAPTURE,
            $depuis,
        );

        $this->assertSame(
            1,
            $trouve,
            "{$quoi} n est pas rendu APRES l element qui le precede au registre : "
                .'il manque, ou le menu n est plus dans l ordre de MenuLateral::NAVIGATION.',
        );

        return (int) $capture[0][1] + 1;
    }

    /**
     * Le libelle que le registre donne au premier ecran d'un module.
     *
     * Derive, jamais recopie : c'est ce qui fait qu'un renommage au registre
     * se propage jusqu'ici au lieu de laisser ce test vert sur un mot disparu.
     */
    private static function libelleDuModule(string $module): string
    {
        foreach (MenuLateral::NAVIGATION as $entree) {
            foreach ($entree['items'] ?? [$entree] as $item) {
                if ($item['module'] === $module) {
                    return (string) $item['nom'];
                }
            }
        }

        throw new \RuntimeException('Aucune entree de menu pour ' . $module);
    }

    // ⚠ CAS RETIRE LE 10/09/2026 (PA-183) —
    // « les classes de la barre laterale sont celles du prototype ». Il
    // confrontait les classes de l'entree de menu et de l'intitule de groupe
    // a `prototype_v2/assets/js/shell.js` (PA-139 : `py-[7px]` remplace par
    // `py-2.5`). La vue etant desormais le maitre, il n'a plus de reference.

    /**
     * La barre laterale porte `sidebar-nav`, sans quoi deux regles d'`app.css`
     * ne s'appliquent a rien.
     *
     * `.sidebar-nav .epingle + .epingle` et `.sidebar-nav .epingle:last-of-type`
     * posent le liseré sous la DERNIERE epinglee. Elles supposent donc des
     * `.epingle` FRERES — un conteneur unique pour les cinq rendrait la
     * premiere inapplicable et poserait le trait au mauvais endroit.
     */
    #[Test]
    public function les_entrees_epinglees_sont_des_freres_sous_sidebar_nav(): void
    {
        $this->actingAs($this->creerUtilisateur('administrateur'));
        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        $this->assertStringContainsString('sidebar-nav', $html);

        // Autant de conteneurs `.epingle` que d'entrees epinglees au registre.
        $epinglees = count(array_filter(
            MenuLateral::NAVIGATION,
            static fn (array $entree): bool => ($entree['epingle'] ?? false) === true,
        ));
        $this->assertGreaterThanOrEqual(5, $epinglees, 'Plancher : cinq entrees epinglees au registre.');

        $this->assertSame(
            $epinglees,
            substr_count($html, 'class="epingle"'),
            'Les entrees epinglees doivent etre des freres, un conteneur chacune.',
        );
    }

    /**
     * @return list<string>
     */
    private function classes(string $brut): array
    {
        $classes = preg_split('/\s+/', trim($brut)) ?: [];
        $classes = array_values(array_filter($classes, static fn (string $c): bool => $c !== ''));
        sort($classes);

        return $classes;
    }

    /**
     * Chaque icône du menu est dessinée depuis `MenuLateral::ICONES`, et
     * chaque icône que le registre de navigation nomme y existe.
     *
     * Jusqu'au 10/09/2026, les tracés du registre étaient comparés à
     * `ICONES_MODULES` de `prototype_v2/assets/js/shell.js` (PA-143 : un point
     * de trop dans l'icône `reservation`). Le registre est désormais la
     * référence (PA-183) ; ce qui reste vérifiable sans maître extérieur, c'est
     * la chaîne registre → page servie — et c'est précisément là que le défaut
     * du 31/08/2026 avait vécu : la vue relisait le tracé comme une CLÉ, le
     * repli `??` s'appliquait partout, et les vingt-quatre lignes du menu
     * dessinaient l'engrenage des « Paramètres » pendant que la garde,
     * comparant le registre au maître, restait verte.
     */
    #[Test]
    public function les_icones_du_menu_sont_dessinees_depuis_leur_registre(): void
    {
        $this->assertGreaterThanOrEqual(18, count(MenuLateral::ICONES), 'Un registre vide rendrait la boucle vide.');

        $nommees = [];
        foreach (MenuLateral::NAVIGATION as $entree) {
            foreach ($entree['items'] ?? [$entree] as $item) {
                $nommees[(string) $item['icone']] = true;
            }
        }

        $this->actingAs($this->creerUtilisateur('administrateur'));
        $menu = $this->extraireBloc(
            (string) $this->get('/pwa')->assertOk()->getContent(),
            '<aside id="sidebar"',
            'overlay-sidebar-mobile',
        );

        foreach (array_keys($nommees) as $nom) {
            $this->assertArrayHasKey(
                $nom,
                MenuLateral::ICONES,
                "Le menu nomme l'icone « {$nom} », absente de MenuLateral::ICONES : "
                    .'l entree dessinerait un vide.',
            );

            $this->assertStringContainsString(
                MenuLateral::ICONES[$nom],
                $menu,
                "Le trace de l'icone « {$nom} » n'est pas rendu dans le menu servi : "
                    .'l entree dessine autre chose que son registre.',
            );
        }

        // Plancher : au moins quinze icones distinctes nommees par le registre.
        $this->assertGreaterThanOrEqual(15, count($nommees));

        // Et deux entrees d'icones differentes ne dessinent pas la meme chose :
        // le defaut du 31/08/2026 rendait l'engrenage partout.
        $this->assertSame(
            count(MenuLateral::ICONES),
            count(array_unique(MenuLateral::ICONES)),
            'Deux icones du registre portent le meme trace.',
        );
    }

    // ------------------------------------------------- Aucune ressource distante

    /**
     * La PWA doit rester servable sans Internet (BRIEFS_AGENTS.md §B1,
     * contrainte 2). L'ancienne maquette chargeait Tailwind, Chart.js et les
     * polices par CDN : reprises telles quelles, ces balises produisaient une
     * page qui s'affiche parfaitement au bureau du developpeur et sans aucune
     * mise en forme au Gite.
     *
     * Le controle porte sur le HTML REELLEMENT SERVI, pas sur les fichiers
     * source : une URL distante peut arriver par un partial, un helper ou une
     * feuille de style importee.
     */
    #[Test]
    public function aucune_page_de_la_pwa_ne_charge_de_ressource_distante(): void
    {
        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000', 'www.w3.org'];

        $verifier = function (string $page) use ($autorises): void {
            $html = (string) $this->get($page)->assertOk()->getContent();

            preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

            foreach (array_unique($hotes[1]) as $hote) {
                $this->assertContains(
                    $hote,
                    $autorises,
                    "La page {$page} charge une ressource distante : {$hote}. "
                    . 'La PWA doit rester servable sans Internet.',
                );
            }
        };

        // Pages sans session d'abord : `/pwa/connexion` porte le middleware
        // `guest` et redirigerait un utilisateur deja authentifie.
        foreach (['/pwa/demarrage', '/pwa/connexion', '/pwa/hors-connexion'] as $page) {
            $verifier($page);
        }

        $this->actingAs($this->creerUtilisateur('administrateur'));
        $verifier('/pwa');

        // ⚠ CE BALAYAGE NE COUVRAIT QUE LA COQUILLE, ET C'ETAIT UN TROU.
        //
        // Jusqu'au 27/08/2026 il verifiait quatre pages : le demarrage, la
        // connexion, le repli hors connexion et l'accueil. Les VINGT-NEUF
        // pages de donnees livrees depuis lui echappaient entierement — une
        // balise vers une police distante posee sur l'une d'elles n'aurait
        // fait rougir personne, et la page fonctionnerait parfaitement au
        // bureau du developpeur. C'est exactement la forme du trou de
        // `PwaActionsReluesTest` (PA-152) : une garde qui dit « tout va bien »
        // sans avoir regarde.
        //
        // Une page par module livre — celles qui portent leur propre gabarit,
        // au-dela des partials de coquille deja couverts par `/pwa`.
        foreach ([
            '/pwa/reservations',
            '/pwa/hebergement',
            '/pwa/clients',
            '/pwa/bar/carte',
            '/pwa/stocks',
            '/pwa/achats',
            '/pwa/facturation',
            '/pwa/comptabilite',
            '/pwa/restaurant/carte',
            '/pwa/restaurant/plats',
            '/pwa/vehicules',
            '/pwa/tourisme',
            '/pwa/etats',
            '/pwa/etats/bibliotheque',
            '/pwa/parametres',
            '/pwa/journal-audit',
        ] as $page) {
            $verifier($page);
        }
    }

    /**
     * Meme controle sur les feuilles de style embarquees : c'est par un
     * `@import` vers Google Fonts que la dependance reseau revient le plus
     * discretement — la page reste fonctionnelle, seule la typographie change,
     * et avec elle l'interligne et la largeur des colonnes.
     */
    #[Test]
    public function les_feuilles_de_style_embarquees_ne_pointent_vers_aucun_hote_distant(): void
    {
        foreach (['assets/css/app.css', 'assets/css/vendor/fonts.css'] as $feuille) {
            $chemin = public_path($feuille);
            $this->assertFileExists($chemin);

            $contenu = (string) file_get_contents($chemin);
            $sansCommentaires = (string) preg_replace('#/\*.*?\*/#s', ' ', $contenu);

            $this->assertDoesNotMatchRegularExpression(
                '#url\(\s*[\'"]?https?://#i',
                $sansCommentaires,
                "La feuille {$feuille} charge une ressource distante.",
            );
        }

        // Et les polices referencees existent reellement : un chemin relatif
        // faux ne provoque aucune erreur, la page retombe simplement sur la
        // police systeme.
        $fonts = (string) file_get_contents(public_path('assets/css/vendor/fonts.css'));
        preg_match_all('#url\([\'"]?([^\'")]+)[\'"]?\)#', $fonts, $sources);

        $this->assertNotEmpty($sources[1]);

        foreach (array_unique($sources[1]) as $source) {
            $this->assertFileExists(
                public_path('assets/css/vendor/' . $source),
                "Police referencee mais absente : {$source}",
            );
        }
    }

    // ============================================================ ARTICLE 3
    //
    // Le chassis — barre laterale (3.1), barre superieure (3.2), menu de
    // compte (3.3), panneau lateral (3.4).
    //
    // `DIRECTIVE_CONFORMITE_100.md` Article 3 : « Le chassis se voit sur TOUS
    // les ecrans. Une erreur ici se repete partout — c'est le point le plus
    // rentable a verrouiller en premier. »
    //
    // Jusqu'au 10/09/2026, les gardes ci-dessous relisaient `shell.js` a
    // chaque execution. Depuis PA-183 la vue Blade est le maitre : elles
    // portent des INVARIANTS du chassis servi, et chacune garde un PLANCHER
    // pour ne jamais passer a vide.

    /**
     * Le HTML reellement servi a un Administrateur — tout le chassis y est.
     */
    private function chassisServi(): string
    {
        $this->actingAs($this->creerUtilisateur('administrateur'));

        return (string) $this->get('/pwa')->assertOk()->getContent();
    }

    /**
     * Une chaine de classes isolee par un motif, rendue en ENSEMBLE trie.
     *
     * @return list<string>
     */
    private function classesIsolees(string $motif, string $sujet, string $ou): array
    {
        $this->assertSame(
            1,
            preg_match($motif, $sujet, $trouve),
            "Le motif ne trouve plus la chaine de classes dans {$ou} : sans "
                . 'elle, la verification porterait sur un ensemble vide.',
        );

        return $this->classes($trouve[1]);
    }

    // ⚠ CAS RETIRE LE 10/09/2026 (PA-183) — « les classes du chassis sont
    // celles du prototype ». Il confrontait a l'egalite stricte 35 chaines de
    // classes de la barre superieure, du menu de compte et du panneau lateral
    // a leurs homologues de `prototype_v2/assets/js/shell.js`. La vue etant
    // desormais le maitre, il n'a plus de reference.

    /**
     * ARTICLE 3.2 — l'ORDRE HORIZONTAL des widgets de la barre supérieure.
     *
     * Jusqu'au 10/09/2026, l'ordre attendu était d'abord relevé dans le
     * `<header>` de `prototype_v2/assets/js/shell.js`. La vue étant le maître
     * (PA-183), l'ordre ci-dessous EST la spécification : il fige la barre
     * telle que le Product Owner l'a validée (bascule plein écran, recherche
     * globale et bouton « Vente » compris). Un widget déplacé, ou qui
     * disparaît, fait échouer ce cas.
     */
    #[Test]
    public function l_ordre_horizontal_de_la_barre_superieure_est_fige(): void
    {
        $barre = $this->extraireBloc($this->chassisServi(), 'id="shell-topbar"', '</header>');

        /**
         * Ordre horizontal, de gauche a droite : pour chaque widget, le
         * marqueur qui l'identifie dans le HTML servi.
         *
         * @var array<string, string>
         */
        $widgets = [
            'bouton de menu mobile' => 'id="bouton-menu-mobile"',
            'bascule plein ecran' => 'id="bouton-plein-ecran"',
            'logo et marque' => 'ring-2 ring-[var(--gold)]',
            'espaceur' => '<div class="flex-1"></div>',
            'recherche globale' => 'wire:model.live.debounce.250ms="terme"',
            'badge reseau' => 'bg-[var(--succes)]/15',
            'indicateur de caisse' => 'id="indicateur-caisse"',
            'bouton Vente' => 'bg-[var(--gold)] text-white hover:brightness-110',
            'cloche de notifications' => 'id="bouton-cloche-notifications"',
            'pastille de comptage' => 'id="badge-notifications-non-lues"',
            'bloc de compte' => 'class="relative ml-2 pl-3 border-l border-white/10"',
        ];

        $this->assertGreaterThanOrEqual(11, count($widgets));

        $precedent = -1;
        foreach ($widgets as $quoi => $marqueur) {
            $position = strpos($barre, $marqueur);
            $this->assertIsInt($position, "Le widget « {$quoi} » n'est plus rendu dans la barre superieure.");
            $this->assertGreaterThan(
                $precedent,
                $position,
                "L'ordre horizontal de la barre superieure a change : « {$quoi} » "
                    . "n'est plus a sa place.",
            );
            $precedent = $position;
        }
    }

    /**
     * ARTICLE 3.3 — la STRUCTURE du menu de compte : entrées, séparateurs,
     * ordre, et traitement distinctif de la déconnexion.
     *
     * PA-143 avait rétabli cinq entrées et deux séparateurs manquants : le
     * menu servi était retombé à deux lignes sur sept une première fois.
     * Jusqu'au 10/09/2026, la séquence servie était comparée à celle du
     * `<header>` de `prototype_v2/assets/js/shell.js`. Depuis PA-183 elle est
     * jugée sur ses INVARIANTS : assez d'entrées pour ne pas être retombée,
     * deux séparateurs, aucune entrée en double, la déconnexion en DERNIER, et
     * « Journal d'Audit » juste après « Import & Export » (directive PO du
     * 02/09/2026).
     */
    #[Test]
    public function le_menu_de_compte_garde_sa_structure(): void
    {
        // ⚠ Les cinq entrees du menu de compte naviguent vraiment : le chassis
        // est rendu pour un Administrateur, qui a droit aux six modules
        // concernes ; un profil sans droit verrait un `<span aria-disabled>` a
        // la place — c'est
        // `les_entrees_de_chassis_sans_droit_restent_inertes_et_le_disent()`
        // qui le tient.
        $servi = $this->sequenceDuMenuDeCompte(
            $this->extraireBloc($this->chassisServi(), 'id="menu-profil"', '</header>'),
            ['<a href=', '<button type="button" wire:click="seDeconnecter"'],
        );

        // Plancher : sept elements tant que le menu portait la sequence
        // d'origine, huit depuis que Journal d'Audit y est entre.
        $this->assertGreaterThanOrEqual(8, count($servi), 'Le menu de compte est retombe sous huit elements.');

        $this->assertSame(2, count(array_keys($servi, 'separateur', true)), 'Le menu de compte ne porte plus deux separateurs.');

        $entrees = array_values(array_filter($servi, static fn (string $e): bool => $e !== 'separateur'));
        $this->assertSame($entrees, array_values(array_unique($entrees)), 'Une entree du menu de compte est rendue deux fois.');

        $this->assertStringStartsWith('deconnexion:', $servi[count($servi) - 1], 'La deconnexion n est plus la derniere entree.');

        $entreeJournal = 'entree:'.__('pwa.coquille.journal_audit');
        $positionJournal = array_search($entreeJournal, $servi, true);
        $this->assertIsInt(
            $positionJournal,
            'Journal d Audit n est plus au menu de compte : la directive PO '
                . 'du 02/09/2026 le place la, et il n est plus dans la barre.',
        );
        $this->assertSame(
            'entree:'.__('pwa.coquille.import_export'),
            $servi[$positionJournal - 1],
            'Journal d Audit doit suivre Import & Export au menu de compte.',
        );
    }

    /**
     * Le fragment compris entre deux marqueurs, ou un echec net.
     */
    private function extraireBloc(string $sujet, string $depuis, string $jusqu): string
    {
        $debut = strpos($sujet, $depuis);
        $this->assertIsInt($debut, "Marqueur d'ouverture introuvable : {$depuis}");

        $fin = strpos($sujet, $jusqu, $debut);
        $this->assertIsInt($fin, "Marqueur de fermeture introuvable : {$jusqu}");

        return substr($sujet, $debut, $fin - $debut);
    }

    /**
     * La sequence d'un menu de compte : `entree:<libelle>`, `separateur`,
     * `deconnexion:<libelle>`, dans l'ordre du document.
     *
     * @param  array{0: string, 1: string}  $ouvertures  [entree, deconnexion]
     * @return list<string>
     */
    private function sequenceDuMenuDeCompte(string $bloc, array $ouvertures): array
    {
        // ⚠ Les MARQUEURS DE BLOC DE LIVEWIRE sont retires avant l'analyse.
        //
        // Livewire encadre chaque `@if` rendu de `<!--[if BLOCK]><![endif]-->`
        // et `<!--[if ENDBLOCK]><![endif]-->`. Depuis que les entrees du menu
        // de compte passent par le partial `lien-chassis`, ces commentaires se
        // collent en tete des lignes servies : `<!--[if BLOCK]><![endif]--><a
        // href=...` ne commence plus par `<a href=`, et la sequence sortait
        // VIDE. Le plancher de l'appelant garantit que ce nettoyage n'a pas
        // tout efface.
        $bloc = (string) preg_replace('/<!--\[if (?:BLOCK|ENDBLOCK)\]><!\[endif\]-->/', '', $bloc);

        $sequence = [];
        $enCours = null;

        foreach (explode("\n", $bloc) as $ligne) {
            $nue = trim($ligne);

            if ($nue === '') {
                continue;
            }

            if (str_contains($nue, 'class="my-1 border-t')) {
                $sequence[] = 'separateur';

                continue;
            }

            if (str_starts_with($nue, $ouvertures[1])) {
                $enCours = 'deconnexion';

                continue;
            }

            if (str_starts_with($nue, $ouvertures[0])) {
                $enCours = 'entree';

                continue;
            }

            // Le libelle est la seule ligne d'un item qui ne porte aucune
            // balise. Les valeurs interpolees (`{{ … }}`) sont ignorees : elles
            // nomment une source, pas un libelle fige.
            if ($enCours !== null && ! str_contains($nue, '<') && ! str_contains($nue, '>')) {
                $sequence[] = $enCours . ':' . html_entity_decode($nue, ENT_QUOTES, 'UTF-8');
                $enCours = null;
            }
        }

        return $sequence;
    }

    /**
     * ARTICLE 3.4 — le panneau latéral et son voile sont COHÉRENTS entre eux.
     *
     * Jusqu'au 10/09/2026, côté, largeur, durée, plans et opacité étaient
     * comparés, valeur par valeur, à `construireSidebar()` de
     * `prototype_v2/assets/js/shell.js`. La vue étant désormais le maître
     * (PA-183), recopier ces valeurs ici ne prouverait rien. Restent les
     * invariants qui font fonctionner le tiroir, quelles que soient les
     * valeurs choisies :
     *
     *  - le voile DISPARAÎT au point de rupture même où le panneau devient
     *    statique — sinon un voile noir couvrirait l'écran de bureau, ou un
     *    tiroir mobile s'ouvrirait sans voile ;
     *  - le panneau passe AU-DESSUS de son voile — sinon le voile capte les
     *    clics destinés au menu ;
     *  - fermé, le panneau est hors écran (`-translate-x-full`) et il est remis
     *    en place au même point de rupture ;
     *  - l'animation porte sur la transformation, avec une durée.
     */
    #[Test]
    public function le_panneau_lateral_et_son_voile_sont_coherents(): void
    {
        $vue = (string) file_get_contents(base_path('resources/views/pwa/partials/menu-lateral.blade.php'));

        $panneau = $this->classesIsolees('/<aside id="sidebar" class="([^"]+)"/', $vue, 'le panneau lateral');
        $voile = $this->classesIsolees('/id="overlay-sidebar-mobile" class="([^"]+)"/', $vue, 'le voile mobile');

        $rupturePanneau = $this->valeurUnique('/^([a-z0-9]+):static$/', $panneau, 'le panneau lateral');
        $ruptureVoile = $this->valeurUnique('/^([a-z0-9]+):hidden$/', $voile, 'le voile mobile');
        $this->assertSame(
            $rupturePanneau,
            $ruptureVoile,
            'Le voile ne disparait pas au point de rupture ou le panneau devient statique.',
        );

        $this->assertGreaterThan(
            (int) $this->valeurUnique('/^z-(\d+)$/', $voile, 'le voile mobile'),
            (int) $this->valeurUnique('/^z-(\d+)$/', $panneau, 'le panneau lateral'),
            'Le panneau lateral ne passe pas au-dessus de son voile : le voile capterait les clics du menu.',
        );

        $this->assertContains('-translate-x-full', $panneau, 'Ferme, le panneau n est plus hors ecran.');
        $this->assertContains(
            $rupturePanneau.':translate-x-0',
            $panneau,
            'Le panneau n est pas remis en place au point de rupture ou il devient statique.',
        );

        $this->assertContains('transition-transform', $panneau, 'L animation du tiroir ne porte plus sur la transformation.');
        $this->valeurUnique('/^duration-(\d+)$/', $panneau, 'le panneau lateral');
    }

    /**
     * L'unique valeur capturee par `$motif` dans une liste de classes.
     *
     * @param  list<string>  $classes
     */
    private function valeurUnique(string $motif, array $classes, string $ou): string
    {
        $trouvees = [];

        foreach ($classes as $classe) {
            if (preg_match($motif, $classe, $capture) === 1) {
                $trouvees[] = $capture[1];
            }
        }

        $this->assertCount(
            1,
            $trouvees,
            "Le motif {$motif} ne capture pas exactement une classe dans {$ou} : "
                . 'sans capture, la verification serait vide, donc verte.',
        );

        return $trouvees[0];
    }

    /**
     * ARTICLE 3.1 — l'ÉTAT ACTIF, le survol et l'échelle du menu latéral ne
     * vivent pas dans une classe utilitaire : ils vivent dans la feuille
     * SERVIE, `public/assets/css/app.css`.
     *
     * Jusqu'au 10/09/2026, ce cas exigeait que cette feuille soit la
     * transcription, au caractère près, de `prototype_v2/assets/css/app.css`.
     * Depuis PA-183 la feuille servie EST la référence : la comparaison est
     * retirée. Reste l'invariant qui ne dépend d'aucun maître — ces règles-là
     * ne sont portées par AUCUNE classe Tailwind ; une feuille amputée les
     * perdrait sans qu'aucune classe ne le trahisse. C'est arrivé : PA-139,
     * 114 lignes au lieu de 219, verte six jours durant.
     */
    #[Test]
    public function la_feuille_de_style_servie_porte_les_regles_de_la_coquille(): void
    {
        $chemin = public_path('assets/css/app.css');
        $this->assertFileExists($chemin, 'La PWA ne sert plus de feuille de style.');

        $servie = (string) file_get_contents($chemin);

        foreach ([
            '--gold-actif: #CA971E',
            '.lien-sidebar.actif',
            '.lien-sidebar.actif svg',
            '.lien-sidebar.actif:hover',
            '.sidebar-nav .epingle:last-of-type',
            '#shell-sidebar .lien-sidebar { font-size: 14px; }',
            '.overlay-modale',
            '.boite-modale',
        ] as $selecteur) {
            $this->assertStringContainsString($selecteur, $servie, "Regle absente de la feuille servie : {$selecteur}");
        }

        // Et la classe qui donne leur portee a deux de ces regles est bien
        // posee : retablir la feuille sans elle ne retablirait rien.
        $this->assertStringContainsString(
            'sidebar-nav',
            (string) file_get_contents(base_path('resources/views/pwa/partials/menu-lateral.blade.php')),
        );
    }

    // ⚠ CAS RETIRES LE 10/09/2026 (PA-183) — « les traces de la barre
    // superieure sont ceux du prototype » (quatorze traces SVG, dont celui
    // en trop que PA-143 avait trouve) et « les libelles du chassis sont ceux
    // du prototype » (barre superieure et panneau lateral, mot pour mot).
    // Tous deux relisaient `prototype_v2/assets/js/shell.js` ; la vue etant
    // desormais le maitre, ils n'ont plus de reference. Les libelles du chassis
    // de la PWA sont ceux que le client Flutter doit reproduire : c'est
    // `tatacora_flutter/tool/conformite_blade/` qui les confronte.

    private function creerUtilisateur(string $role, string $statut = 'actif', string $login = 'compte.test'): User
    {
        return User::create([
            'login' => $login,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => $statut,
        ]);
    }
}
