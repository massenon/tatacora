<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Models\User;
use App\Pwa\Livewire\Accueil;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Support\MenuLateral;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les DOUZE pages M10 de la PWA — le hub
 * `resources/views/pwa/comptabilite/hub.blade.php` et les onze pages qui en
 * descendent.
 *
 * Ce qui est verifie ici, et qui ne l'est nulle part ailleurs :
 *
 *  1. Les douze pages sont REELLEMENT SERVIES — pas seulement routees. Le
 *     precedent est ecrit dans `CLAUDE.md` : « une page HTML livree vide que
 *     seule une execution reelle a revelee ».
 *  2. Le RBAC de 2e niveau : un role a `'-'` sur M10 est refuse SUR LA ROUTE,
 *     pas seulement prive d'entree de menu.
 *  3. L'Article 7 : « — » quand la donnee n'existe pas, « 0 » quand elle vaut
 *     zero — sur un ETAT FINANCIER, ou la confusion coute le plus cher.
 *  4. Les refus de l'Article 8 sont NOMMES a l'ecran, jamais tus.
 *  5. Aucune ressource distante : la PWA doit rester servable sans Internet.
 *
 * @see LARAVEL_PWA.md §1, §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 1, 3, 6, 7, 8
 */
final class ComptabilitePwaTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $exercice;

    private CompteComptable $banque;

    private CentreCout $structure;

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

        $vte = JournalComptable::create(['code' => 'VTE', 'libelle' => 'Ventes']);
        $this->structure = CentreCout::create(['libelle' => 'Structure', 'type' => 'support']);

        $this->banque = $this->compte('521000', 'Banque — compte principal', '5', 'actif');
        $ventes = $this->compte('706100', "Prestations d'hébergement", '7', 'produit');

        // Un compte SANS nature : c'est lui qui eprouve l'Article 7 sur la
        // colonne « Nature » du plan comptable.
        $this->compte('231000', 'Bâtiments', '2', null);

        // Une pièce écrite par le SEUL chemin qui garantit son équilibre
        // (PA-52) : `enregistrerPiece()`.
        $service = app(EcritureComptableService::class);
        $piece = $service->enregistrerPiece([
            'exercice_id' => $this->exercice->id,
            'journal_id' => $vte->id,
            'date_ecriture' => '2026-07-10',
            'libelle' => 'Hébergement — Agence Bénin Tour',
        ], [
            ['compte_id' => $this->banque->id, 'centre_id' => $this->structure->id, 'debit' => '184000.00', 'credit' => '0.00'],
            ['compte_id' => $ventes->id, 'centre_id' => $this->structure->id, 'debit' => '0.00', 'credit' => '184000.00'],
        ]);
        $service->valider($piece);
    }

    /**
     * Les douze pages du lot, avec les parametres qu'elles attendent.
     *
     * ⚠ Ecrite a la main plutot que derivee des routes, et c'est voulu : une
     * page ajoutee a `routes/web.php` sans etre inscrite ici ferait rougir le
     * cas de couverture ci-dessous. On ne peut pas livrer une page sans dire
     * qu'on l'a eprouvee.
     *
     * @return array<string, string>
     */
    private function pages(): array
    {
        $exercice = ['exercice' => $this->exercice->id];

        return [
            'hub' => route('pwa.comptabilite.hub', $exercice),
            'plan-comptable' => route('pwa.comptabilite.plan-comptable'),
            'journal' => route('pwa.comptabilite.journal', $exercice),
            'grand-livre' => route('pwa.comptabilite.grand-livre', $exercice),
            'balance' => route('pwa.comptabilite.balance', $exercice),
            'compte-resultat' => route('pwa.comptabilite.compte-resultat', $exercice),
            'bilan' => route('pwa.comptabilite.bilan', $exercice),
            'flux-tresorerie' => route('pwa.comptabilite.flux-tresorerie', $exercice),
            'notes-annexes' => route('pwa.comptabilite.notes-annexes', $exercice),
            'etats-financiers' => route('pwa.comptabilite.etats-financiers', $exercice),
            'analytique' => route('pwa.comptabilite.analytique', $exercice),
            'cloture' => route('pwa.comptabilite.cloture', $exercice),
        ];
    }

    /**
     * Les douze pages sont servies, avec leur titre, sur des donnees reelles.
     *
     * Un `assertOk` seul ne dirait rien : une vue Blade dont le corps aurait
     * disparu rend 200. Le `<h1>` du maitre est donc verifie sur chacune.
     */
    #[Test]
    public function les_douze_pages_m10_sont_reellement_servies_avec_le_titre_du_maitre(): void
    {
        $titres = [
            'hub' => 'Comptabilité — SYSCOHADA révisé',
            'plan-comptable' => 'Plan Comptable',
            'journal' => 'Journal Comptable',
            'grand-livre' => 'Grand Livre',
            'balance' => 'Balance Générale',
            'compte-resultat' => 'Compte de Résultat',
            'bilan' => "Bilan de l'Entreprise",
            'flux-tresorerie' => 'Tableau des Flux de Trésorerie',
            'notes-annexes' => 'Notes Annexes',
            'etats-financiers' => 'États Financiers',
            'analytique' => 'Comptabilité Analytique',
            'cloture' => 'Clôture Périodique',
        ];

        $pages = $this->pages();

        // Plancher : douze pages, ni onze ni treize. Sans lui, retirer une
        // entree de la liste rendrait ce cas vert sur ce qui reste.
        $this->assertCount(12, $pages);
        $this->assertSame(array_keys($pages), array_keys($titres));

        foreach ($pages as $nom => $url) {
            $reponse = $this->get($url);

            $reponse->assertOk();
            // `assertSee` sans `escape: false` : Blade echappe l'apostrophe
            // en `&#039;`, et « Bilan de l'Entreprise » ne se retrouverait pas
            // dans le HTML brut. C'est l'echappement qui doit etre compare, pas
            // contourne.
            $reponse->assertSee($titres[$nom]);

            // Et le corps existe : la coquille seule rendrait 200 sur une vue
            // dont le `<main>` serait vide.
            $reponse->assertSee('</main>', escape: false);
        }
    }

    // ⚠ CAS RETIRE LE 10/09/2026 (PA-183) — « les colonnes des tableaux sont
    // celles du maitre dans son ordre ». Il relevait les `<thead>` de cinq
    // pages `prototype_v2/pages/m10-*.html` et exigeait de la PWA les memes
    // colonnes, dans le meme ordre. La vue Blade etant desormais le maitre et
    // `prototype_v2/` une ancienne version, le re-cibler sur la vue la
    // comparerait a elle-meme. La conformite du client Flutter a ces colonnes
    // est mesuree par `tatacora_flutter/tool/conformite_blade/`.

    /**
     * RBAC de 2e NIVEAU : la route refuse, pas seulement le menu.
     *
     * `barman` a `M10 = '-'` dans la matrice. Le masquage d'interface ne
     * protege rien a lui seul — une URL tapee a la main doit etre refusee ici.
     */
    #[Test]
    public function un_role_sans_droit_sur_m10_est_refuse_sur_les_douze_routes(): void
    {
        $barman = $this->utilisateur('barman');
        $this->assertSame('-', $barman->niveauSurModule('M10'), 'La matrice a change : ce cas ne verifie plus rien.');

        $this->actingAs($barman);

        foreach ($this->pages() as $nom => $url) {
            $this->get($url)->assertForbidden();
        }
    }

    /** Et il ne voit pas non plus l'entree de menu, ni la carte d'accueil. */
    #[Test]
    public function un_role_sans_droit_sur_m10_ne_voit_ni_l_entree_de_menu_ni_la_carte(): void
    {
        $this->actingAs($this->utilisateur('barman'));
        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        $this->assertStringNotContainsString('SYSCOHADA', $html);
        $this->assertStringNotContainsString(route('pwa.comptabilite.hub'), $html);
    }

    /**
     * Article 3.3 — l'entree « Comptabilité » NAVIGUE vers l'ecran reel.
     *
     * `DIRECTIVE_CONFORMITE_100.md` renverse ici une decision anterieure : une
     * entree de menu inerte n'est plus acceptable des lors que l'ecran existe.
     */
    #[Test]
    public function l_entree_de_menu_comptabilite_conduit_au_hub(): void
    {
        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        $this->assertStringContainsString(
            'href="' . route('pwa.comptabilite.hub') . '"',
            $html,
            "L'entree « Comptabilité » du menu ne navigue pas vers le hub M10.",
        );

        // ⚠ Et « Dépense courante », l'AUTRE entree M10, ne mene PAS au hub :
        // elle releve de `depenses.html`, un ecran de saisie de tresorerie qui
        // n'a rien a voir avec lui. La detourner donnerait un lien qui navigue
        // vers autre chose que ce qu'il annonce.
        //
        // ## Ce cas mesurait la mauvaise chose, corrige le 31/08/2026
        //
        // Il lisait `isset($item['route'])`, c'est-a-dire « cette entree a-t-elle
        // une route ? », et attendait `false` sur « Dépense courante ». Le
        // commentaire disait « reste inerte » — vrai a l'ecriture, quand
        // l'ecran n'existait pas.
        //
        // L'ecran existe depuis, l'entree a donc une route, et le cas est
        // devenu rouge alors que le depot venait de s'ameliorer. Pire : la
        // prémisse était devenue contraire a la doctrine, l'Article 3.3 de
        // `DIRECTIVE_CONFORMITE_100.md` interdisant desormais une entree de
        // menu inerte. Un cas vert n'aurait plus voulu dire que l'entree est
        // bien cablee, mais qu'elle ne mene nulle part.
        //
        // L'INTENTION, elle, reste entiere : une seule des deux entrees M10
        // conduit au hub. On mesure donc cela, et rien d'autre.
        $hub = route('pwa.comptabilite.hub');

        $entreesM10 = [];
        foreach (MenuLateral::NAVIGATION as $entree) {
            foreach ($entree['items'] ?? [$entree] as $item) {
                if ($item['module'] !== 'M10') {
                    continue;
                }

                // ⚠ PAS de `?? null` ICI, et c'est PHPStan qui a tranché
                // (31/08/2026) : toutes les entrées M10 de `MenuLateral::NAVIGATION`
                // portent une `route`, et le repli décrivait un cas que le type
                // rend impossible. Un repli inatteignable est du code que rien
                // n'exerce — le défaut PA-150. Si une entrée M10 sans route
                // apparaît demain, PHPStan signalera l'offset manquant sur
                // cette ligne : la garde se déplace, elle ne disparaît pas.
                $entreesM10[(string) $item['nom']] = route($item['route']) === $hub;
            }
        }

        $this->assertSame(
            ['Dépense courante' => false, 'Comptabilité' => true],
            $entreesM10,
            'Le cablage des entrees M10 a change : une seule doit mener au hub.',
        );

        // Et l'entree qui ne mene pas au hub mene quand meme QUELQUE PART :
        // sans ce controle, supprimer sa route ferait reverdir le cas
        // ci-dessus en la rendant inerte, ce que l'Article 3.3 refuse.
        foreach (MenuLateral::NAVIGATION as $entree) {
            foreach ($entree['items'] ?? [$entree] as $item) {
                if ($item['module'] === 'M10') {
                    $this->assertArrayHasKey(
                        'route',
                        $item,
                        "L'entree M10 « {$item['nom']} » est inerte (Article 3.3).",
                    );
                }
            }
        }
    }

    /**
     * Article 7, sur la donnee ou la confusion coute le plus cher.
     *
     * « — » quand la donnee n'existe pas, « 0 » quand elle vaut zero. Le compte
     * 231000 est cree SANS nature : sa cellule doit porter un tiret. Le plan
     * comptable, lui, compte reellement ses comptes — un total ecrit en dur
     * serait le deuxieme interdit de l'Article 6.
     */
    #[Test]
    public function article7_une_nature_absente_rend_un_tiret_jamais_un_zero(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.plan-comptable', ['classe' => '2']))
            ->assertOk()->getContent();

        $this->assertStringContainsString('Bâtiments', $html);

        // La ligne du compte sans nature porte le tiret, pas un badge.
        $this->assertMatchesRegularExpression(
            '#Bâtiments.*?<span class="text-slate-300">—</span>#s',
            $html,
            'Une nature absente doit rendre « — », jamais une case vide ni un zero.',
        );

        // Et le decompte du sous-titre est le vrai : trois comptes crees.
        $this->assertSame(3, CompteComptable::query()->count());
        $this->assertStringContainsString('</span> comptes', $html);
    }

    /**
     * Article 7 encore : un ZERO reel s'affiche, il ne devient pas un tiret.
     *
     * C'est le CONTRASTE qui protege la regle, pas la regle seule. Sans ce
     * cas, remplacer tous les montants par « — » passerait au vert.
     */
    #[Test]
    public function article7_un_zero_reel_s_affiche_bien_zero(): void
    {
        // Aucune immobilisation n'est mouvementee : le poste « Actif
        // immobilisé » du bilan vaut zero, et c'est un zero CALCULE.
        $html = (string) $this->get(route('pwa.comptabilite.bilan', ['exercice' => $this->exercice->id]))
            ->assertOk()->getContent();

        $this->assertStringContainsString('Total actif immobilisé (net)', $html);
        $this->assertMatchesRegularExpression(
            '#Total actif immobilisé \(net\).*?0 F#s',
            $html,
            "Un poste calcule a zero doit afficher « 0 F », jamais « — » : ce n'est pas une donnee absente.",
        );
    }

    /**
     * PLUS AUCUNE SECTION DE REFUS N'EST RENDUE — directive du Product Owner
     * du 31/08/2026.
     *
     * Le hub affichait un panneau « Ce que cet écran ne fait pas, et pourquoi »
     * et deux onglets — « Passer écriture », « Immobilisations » — dont le seul
     * contenu était la raison de leur absence. Les deux formes sont supprimées :
     * ce qui ne peut pas être réel est OMIS, et déclaré en jeton code.
     *
     * ⚠ CE CAS EST UNE MOITIÉ, ET IL SERAIT DANGEREUX SEUL : « rien ne
     * s'affiche » est aussi ce que rendrait un écran cassé. Sa seconde moitié
     * est l'assertion des HUIT onglets réellement servis, chacun rendu — et
     * `les_douze_pages_m10_sont_reellement_servies_avec_le_titre_du_maitre`,
     * qui charge les douze écrans en 200.
     *
     * ⚠ MUTATION ÉPROUVÉE (31/08/2026) : réintroduire `@include(
     * 'pwa.comptabilite.partials.refus', …)` dans `hub.blade.php` fait échouer
     * la première assertion ; remettre `'immo'` dans `Hub::ONGLETS` fait
     * échouer le décompte. Ce cas mord dans les deux sens.
     */
    #[Test]
    public function le_hub_ne_rend_plus_aucune_section_de_refus(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.hub', ['exercice' => $this->exercice->id]))
            ->assertOk()->getContent();

        $this->assertStringNotContainsString(
            e(__('pwa.comptabilite.refus_titre')),
            $html,
            'Le hub rend encore un panneau « Ce que cet écran ne fait pas ».',
        );

        // Les HUIT onglets servis sont rendus, dans l'ordre du maitre. Aucun
        // n'est inerte : chacun a son gabarit sous `pwa/comptabilite/onglets/`.
        // 10 depuis la vague E (01/09/2026) : « Passer écriture » et
        // « Immobilisations » — les deux onglets que l'audit navigateur
        // signalait MANQUANTS — sont livrés, chacun avec son gabarit.
        $this->assertCount(10, Hub::ONGLETS);
        // Les deux clés dont l'ABSENCE se vérifiait sont devenues les deux
        // livraisons : leur PRÉSENCE est le nouveau contrat.
        $this->assertArrayHasKey('saisie', Hub::ONGLETS);
        $this->assertArrayHasKey('immo', Hub::ONGLETS);

        $position = 0;
        foreach (Hub::ONGLETS as $cle => $libelle) {
            $trouve = strpos($html, e($libelle), $position);
            $this->assertNotFalse($trouve, "L'onglet « {$libelle} » ({$cle}) n'est pas rendu, ou pas dans l'ordre du maitre.");
            $position = $trouve;

            $this->assertFileExists(
                resource_path('views/pwa/comptabilite/onglets/'.$cle.'.blade.php'),
                "L'onglet « {$libelle} » est rendu sans gabarit : il serait inerte.",
            );
        }
    }

    /**
     * L'onglet de SAISIE est OMIS, et un `?onglet=saisie` retombe sur le
     * defaut au lieu de rendre une page vide.
     *
     * `$onglet` est une propriete `#[Url]` : la valeur vient du navigateur.
     * Sans le repli de `render()`, l'URL heritee d'un favori ou d'un lien
     * envoye avant le 31/08/2026 afficherait la coquille sans contenu — ce qui
     * se lit comme un ecran casse.
     */
    #[Test]
    public function un_onglet_omis_demande_par_l_url_retombe_sur_le_defaut(): void
    {
        foreach (['saisie', 'immo', 'nimporte-quoi'] as $inconnu) {
            $html = (string) $this->get(route('pwa.comptabilite.hub', [
                'exercice' => $this->exercice->id,
                'onglet' => $inconnu,
            ]))->assertOk()->getContent();

            // Le contenu servi est celui de l'onglet par defaut — le Journal.
            $this->assertStringContainsString(
                e(Hub::ONGLETS[Hub::ONGLET_DEFAUT]),
                $html,
                "L'onglet « {$inconnu} » ne retombe pas sur le defaut.",
            );

            // Et aucun champ de saisie de piece n'apparait : le formulaire du
            // maitre n'est ni rendu, ni simule.
            $this->assertStringNotContainsString('name="debit"', $html);
            $this->assertStringNotContainsString('name="credit"', $html);
            $this->assertStringNotContainsString('Enregistrer et valider', $html);
            $this->assertStringNotContainsString('Enregistrer en brouillon', $html);
        }
    }

    /**
     * Les ONZE tuiles de navigation du hub (la page d'atterrissage M10, que
     * l'ancienne maquette posait en `m10-comptabilite.html`) sont rendues, et
     * chacune NAVIGUE reellement.
     *
     * C'est ce qui rend la page d'atterrissage servie plutot que refusee :
     * jusqu'au 31/08/2026, onze ecrans M10 routes et servis
     * n'etaient atteignables qu'en tapant leur URL — `MenuLateral` n'a qu'une
     * entree M10. Un lien mort serait pire que pas de lien (Article 3.3) : le
     * cas suit donc chaque `href` jusqu'a un HTTP 200.
     */
    #[Test]
    public function les_onze_tuiles_de_la_page_d_atterrissage_naviguent_reellement(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.hub', ['exercice' => $this->exercice->id]))
            ->assertOk()->getContent();

        $this->assertCount(11, Hub::TUILES);

        foreach (Hub::TUILES as [$titre, $description, $nomDeRoute]) {
            $this->assertStringContainsString(e($titre), $html, "La tuile « {$titre} » n'est pas rendue.");
            $this->assertStringContainsString(e($description), $html, "La description de « {$titre} » n'est pas celle du maitre.");

            $url = route($nomDeRoute, ['exercice' => $this->exercice->id]);
            $this->assertStringContainsString(
                e(route($nomDeRoute, ['exercice' => $this->exercice->id, 'statut' => 'toutes'])),
                $html,
                "La tuile « {$titre} » ne porte pas de lien vers {$nomDeRoute}.",
            );

            $this->get($url)->assertOk();
        }
    }

    /**
     * La page de cloture montre un ETAT et ne declenche rien — c'est le point
     * sensible du lot.
     */
    #[Test]
    public function la_page_de_cloture_montre_un_etat_et_ne_declenche_rien(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.cloture', ['exercice' => $this->exercice->id]))
            ->assertOk()->getContent();

        // Les six groupes d'etapes du maitre sont rendus.
        foreach ([
            'Vérification pré-clôture',
            "Passage en statut 'en_cloture'",
            'Écritures de clôture',
            'Contrôle post-clôture',
            "Passage en statut 'cloture' (verrou définitif)",
            'Bilan actuel (pour référence, hors séquence de clôture)',
        ] as $groupe) {
            $this->assertStringContainsString(e($groupe), $html, "Le groupe d'étapes « {$groupe} » manque.");
        }

        // Et AUCUNE section de refus n'est rendue (directive du 31/08/2026) :
        // les actions de cloture sont omises, leur motif vit en jeton code.
        $this->assertStringNotContainsString(e(__('pwa.comptabilite.refus_titre')), $html);
        $this->assertStringNotContainsString(e(__('pwa.comptabilite.refus_actions_cloture')), $html);

        // ⚠ CE QUI RESTE A L'ECRAN EST D'UNE AUTRE NATURE, et doit y rester :
        // « Ce que ce contrôle ne peut pas vérifier » est un ETAT calcule par
        // `EtatClotureService` (`limitesNonVerifiables`), pas une declaration
        // de portage. Le confondre avec un refus le ferait disparaitre, et
        // l'ecran affirmerait alors une conformite qu'il n'a pas verifiee.
        if ($this->exercice->annee > 0) {
            $this->assertStringContainsString(e(__('pwa.comptabilite.limites_titre')), $html);
        }

        // ⚠ UN piege d'assertion, rencontre en ecrivant ce cas :
        //    on ne peut pas chercher `wire:click` sur la PAGE ENTIERE — la
        //    coquille en porte deux, les boutons de deconnexion de la barre
        //    superieure et du menu lateral. Ils sont legitimes et relus
        //    (`FermeSession`).
        //
        // Ce qui doit etre absent, c'est un CONTROLE dans le CORPS de l'ecran.
        $corps = $this->corpsDeLaPage($html);

        $this->assertStringNotContainsString('wire:click', $corps, 'Le corps de la page de cloture porte une action Livewire.');
        $this->assertStringNotContainsString('<form', $corps, 'Le corps de la page de cloture porte un formulaire.');
        $this->assertStringNotContainsString('<button', $corps, 'Le corps de la page de cloture porte un bouton.');
        $this->assertStringNotContainsString('Clôturer définitivement', $html);
    }

    /**
     * Aucune page M10 ne charge de ressource distante : la PWA doit rester
     * servable sans Internet.
     */
    #[Test]
    public function aucune_page_m10_ne_charge_de_ressource_distante(): void
    {
        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000', 'www.w3.org'];

        foreach ($this->pages() as $nom => $url) {
            $html = (string) $this->get($url)->assertOk()->getContent();

            preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

            foreach (array_unique($hotes[1]) as $hote) {
                $this->assertContains(
                    $hote,
                    $autorises,
                    "La page M10 « {$nom} » charge une ressource distante : {$hote}.",
                );
            }
        }
    }

    /**
     * Un etat DIT son filtre (PA-119), et le filtre de statut est un registre
     * FERME : une valeur venue de l'URL ne vide pas l'etat en silence.
     */
    #[Test]
    public function un_filtre_de_statut_inconnu_retombe_sur_le_registre_au_lieu_de_vider_l_etat(): void
    {
        $attendu = MontantFcfa::format('184000.00');

        $htmlValide = (string) $this->get(route('pwa.comptabilite.balance', [
            'exercice' => $this->exercice->id,
        ]))->assertOk()->getContent();

        $this->assertStringContainsString($attendu, $htmlValide);

        // Une valeur fantaisiste produirait `whereIn('statut', ['n-importe-quoi'])`,
        // donc une balance VIDE sous un bandeau qui affirme le contraire.
        $htmlBidon = (string) $this->get(route('pwa.comptabilite.balance', [
            'exercice' => $this->exercice->id,
            'statut' => 'n-importe-quoi',
        ]))->assertOk()->getContent();

        $this->assertStringContainsString(
            $attendu,
            $htmlBidon,
            "Un filtre de statut inconnu a vide l'etat au lieu de retomber sur le registre.",
        );
    }

    /**
     * Un exercice inconnu — venu de l'URL, donc de l'exterieur — ne leve pas :
     * l'ecran retombe sur son etat « aucun exercice choisi », qui DIT quoi
     * faire (Article 7).
     */
    #[Test]
    public function un_exercice_inconnu_rend_l_etat_vide_explicite_au_lieu_de_lever(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.balance', [
            'exercice' => '00000000-0000-4000-8000-000000000000',
        ]))->assertOk()->getContent();

        $this->assertStringContainsString(e(__('pwa.comptabilite.aucun_exercice_titre')), $html);
        $this->assertStringContainsString(e(__('pwa.comptabilite.aucun_exercice_detail')), $html);
    }

    /**
     * `Accueil::ECRANS_AUTORISES` contient M10, et sa carte OUVRE l'ecran.
     *
     * La liste est fermee : la mutation « retirer M10 » doit faire rougir ce
     * cas, sans quoi l'extension de perimetre ne serait tenue par rien.
     */
    #[Test]
    public function m10_figure_a_la_liste_fermee_des_ecrans_et_sa_carte_ouvre_le_hub(): void
    {
        $this->assertContains('M10', Accueil::ECRANS_AUTORISES);

        $html = (string) $this->get('/pwa')->assertOk()->getContent();

        $this->assertStringContainsString(e(__('pwa.ecrans.M10.libelle')), $html);
        $this->assertStringContainsString(e(__('pwa.ecrans.M10.description')), $html);
        $this->assertStringContainsString(e(__('pwa.accueil.ouvrir_ecran')), $html);
    }

    /**
     * Les montants sont mis en forme SANS FLOTTANT, et le separateur est
     * U+00A0 — PLUS la fine U+202F mesuree sur `Intl.NumberFormat('fr-FR')`
     * (02/09/2026) : le meme formateur alimente les PDF Helvetica, dont
     * l'encodage WinAnsi n'a pas de glyphe pour la fine — « 1?500 » sur la
     * fiche des prix remise, constate par le Product Owner. La raison
     * complete vit sur `MontantFcfa::SEPARATEUR`.
     */
    #[Test]
    public function les_montants_sont_groupes_comme_au_maitre_sans_passer_par_un_flottant(): void
    {
        $this->assertSame("1\u{00A0}234\u{00A0}567 FCFA", MontantFcfa::format('1234567.00'));
        $this->assertSame("1\u{00A0}234\u{00A0}568 FCFA", MontantFcfa::format('1234567.50'));
        $this->assertSame('0 FCFA', MontantFcfa::format('0.00'));

        // Le tiret des colonnes a double sens, et la cellule vide : TROIS
        // rendus DIFFERENTS pour un meme zero, chacun avec son sens.
        //
        // ⚠ Une quatrieme methode, `formatOuInconnu(?string)`, a existe
        // quelques heures le 27/08/2026 et a ete SUPPRIMEE : une mutation a
        // revele qu'elle n'avait aucun appelant hors de ce test. C'est la
        // forme exacte de PA-63 — du code appele uniquement par ses propres
        // assertions, qui passe pour vivant. Le seul « — » d'Article 7 de ce
        // lot est le solde d'ouverture du Grand Livre, et le maitre n'y pose
        // aucune cellule : il est rendu par une phrase, pas par un tiret.
        $this->assertSame('—', MontantFcfa::formatOuTiret('0.00'));
        $this->assertSame('', MontantFcfa::formatOuVide('0.00'));
        $this->assertSame('0 FCFA', MontantFcfa::format('0.00'));

        // Un montant a quinze chiffres : c'est la ou un `(float)` se trompe.
        $this->assertSame("999\u{00A0}999\u{00A0}999\u{00A0}999 FCFA", MontantFcfa::format('999999999999.00'));

        // -0,40 ne devient jamais « -0 F ».
        $this->assertSame('0 FCFA', MontantFcfa::format('-0.40'));
        $this->assertTrue(MontantFcfa::estNegatif('-0.01'));
        $this->assertFalse(MontantFcfa::estNegatif('0.00'));
    }

    /**
     * Le Journal du hub compte des LIGNES, jamais des « pièces ».
     *
     * PA-52 : le schema ne porte aucun identifiant de piece. Ecrire « 2 pièces »
     * sur deux lignes annoncerait deux documents la ou il y en a un.
     */
    #[Test]
    public function le_hub_compte_des_lignes_et_non_des_pieces(): void
    {
        $this->assertSame(2, EcritureComptable::query()->count());

        $html = (string) $this->get(route('pwa.comptabilite.hub', [
            'exercice' => $this->exercice->id,
            'onglet' => 'journal',
        ]))->assertOk()->getContent();

        $this->assertStringContainsString('2 ligne(s)', $html);
        $this->assertStringNotContainsString('2 pièce(s)', $html);
    }

    /**
     * Le CORPS de la page — ce que `<main>` contient, coquille exclue.
     *
     * La barre superieure et le menu lateral portent des controles legitimes
     * (deconnexion, ouverture du menu) sur TOUTES les pages. Les compter
     * ferait echouer n'importe quelle assertion d'absence de bouton, y compris
     * sur un ecran parfaitement en lecture seule.
     */
    private function corpsDeLaPage(string $html): string
    {
        $trouve = preg_match('#<main\b[^>]*>(.*)</main>#s', $html, $capture);

        // Sans ce plancher, une coquille renommee rendrait une chaine vide,
        // dans laquelle rien ne se trouve — donc toutes les assertions
        // d'absence passeraient au vert sans rien examiner.
        $this->assertSame(1, $trouve, "Aucun <main> dans la page : le decoupage ne mesure plus rien.");
        $this->assertGreaterThan(500, strlen($capture[1]), 'Le corps de la page est quasi vide.');

        return $capture[1];
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

    private function comptable(): User
    {
        return $this->comptable ??= $this->utilisateur('comptable');
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.test',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
