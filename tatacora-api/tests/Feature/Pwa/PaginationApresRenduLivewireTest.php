<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Pagination\Paginator;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Finder\Finder;
use Tests\TestCase;

/**
 * « Suivant » MÈNE À LA PAGE SUIVANTE, pas au point d'entrée de Livewire.
 *
 * ## Le défaut, signalé par le Product Owner le 04/09/2026
 *
 * > `MethodNotAllowedHttpException` — The GET method is not supported for
 * > route `livewire-5f1c3da4/update`. Supported methods: POST.
 * > Referer : `/pwa/restaurant/plats`.
 *
 * ## Sa racine, et pourquoi elle est plus ancienne que l'écran qui l'a révélé
 *
 * Ce dépôt pagine SANS le trait `WithPagination` (PA-67) : la page courante est
 * une propriété `#[Url]` passée en quatrième argument de `paginate()`, et la
 * vue rend de VRAIS liens `<a href>` (`vendor/pagination/tatacora`). L'URL de
 * ces liens vient de `Paginator::resolveCurrentPath()`, dont le résolveur par
 * défaut de Laravel est `url()->current()`.
 *
 * Or **la « page courante » d'un rendu Livewire n'est pas la page** : c'est
 * `POST /livewire/update`. Tant qu'un écran est rendu par le GET initial, les
 * liens sont justes ; dès qu'un rendu passe par Livewire — un filtre tapé, un
 * onglet cliqué, une modale fermée — la pagination se réécrit en
 * `href="/livewire-xxxx/update?page=2"`, et le clic suivant part en **GET sur
 * une route qui n'accepte que POST**.
 *
 * Le défaut est donc GÉNÉRAL : il touche les six écrans qui rendent `->links()`
 * (Achats ×2, Facturation, Hébergement, Carte, Restauration). Personne ne
 * l'avait vu parce qu'il faut DEUX gestes pour l'atteindre — d'abord provoquer
 * un rendu Livewire, ensuite seulement cliquer « Suivant ». Les onglets livrés
 * le 04/09/2026 mettent ces deux gestes l'un derrière l'autre, ce qui l'a rendu
 * immédiat sur `/pwa/restaurant/plats`.
 *
 * ## Le correctif a UN SEUL AUTEUR
 *
 * `AppServiceProvider::boot()` remplace le résolveur de chemin par
 * `Livewire::originalUrl()`, qui rend l'URL RÉELLE de la page pendant un rendu
 * Livewire et retombe sur `url()->current()` partout ailleurs — donc sur le
 * comportement de Laravel hors Livewire. Le corriger vue par vue avec un
 * `->withPath(...)` aurait produit six écritures qui auraient fini par diverger,
 * et le septième écran paginé serait né cassé.
 *
 * ## Mutation RÉELLEMENT exécutée puis annulée (04/09/2026)
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `Paginator::currentPathResolver(…)` retiré d'`AppServiceProvider::boot()` | `la_pagination_rendue_par_livewire_pointe_sur_la_page` | 1 failed — attendu `…/pwa/restaurant/plats?page=2`, rendu `http://localhost/livewire-5f1c3da4/update?page=2` |
 *
 * ⚠ La première écriture de ce cas envoyait un appel `$set` dans la charge
 * Livewire, et **le composant ne changeait pas d'onglet** : la réponse ne
 * portait alors aucune barre de pagination, donc aucun lien à vérifier. Le cas
 * échouait, mais pas sur ce qu'il croyait mesurer. La charge envoie désormais
 * `updates`, la forme qu'un `wire:model.live` produit réellement — et
 * `hrefsDePagination()` **échoue explicitement si aucune barre n'est rendue**,
 * pour qu'un cas vidé de sa substance ne puisse plus passer au vert.
 *
 * @see PA-67 La pagination de la PWA n'utilise pas `WithPagination`
 */
final class PaginationApresRenduLivewireTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Plancher du balayage : six rendus de pagination mesurés le 04/09/2026.
     * Sans lui, un renommage de répertoire viderait la boucle, qui passerait au
     * vert sans avoir rien mesuré.
     */
    private const PLANCHER_VUES_PAGINEES = 5;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /**
     * LE CAS QUI TIENT LE CORRECTIF, rejoué comme le navigateur le fait.
     *
     * ⚠ `Livewire::test()` NE REPRODUIT PAS ce défaut, et c'est instructif :
     * son harnais monte le composant sur son propre point d'entrée
     * (`livewire-unit-test-endpoint/…`), donc le mémo de l'instantané ne porte
     * jamais l'URL de la page. Un cas écrit avec lui aurait été vert des deux
     * côtés du correctif — il aurait « prouvé » un comportement qu'il ne
     * traverse pas. Le parcours réel est donc rejoué en entier : GET de la
     * page, extraction de l'instantané rendu, POST sur la route de mise à jour
     * de Livewire, puis lecture des liens de la réponse.
     */
    #[Test]
    public function la_pagination_rendue_par_livewire_pointe_sur_la_page(): void
    {
        $this->actingAs($this->administrateur());
        $this->fiches(12);

        $html = $this->apresUneMiseAJourLivewire('/pwa/restaurant/plats', 'onglet', 'fiches');

        $this->assertStringContainsString(
            'href="'.url('/pwa/restaurant/plats').'?page=2"',
            $html,
            'La pagination ne pointe pas sur la page servie.',
        );

        $this->assertStringNotContainsString(
            'livewire',
            $this->hrefsDePagination($html),
            'Un lien de pagination pointe sur le point d\'entrée de Livewire : le clic partira en '
            .'GET sur une route qui n\'accepte que POST (405).',
        );
    }

    /**
     * Le résolveur est POSÉ, et il retombe sur le comportement de Laravel hors
     * Livewire.
     *
     * Sans cette seconde moitié, un résolveur qui renverrait toujours la même
     * URL passerait le cas précédent en cassant toutes les autres pages.
     */
    #[Test]
    public function hors_livewire_le_resolveur_rend_l_url_courante(): void
    {
        $this->actingAs($this->administrateur());
        $this->fiches(12);

        $html = (string) $this->get('/pwa/restaurant/plats?onglet=fiches')->assertOk()->getContent();

        $this->assertStringContainsString('href="'.url('/pwa/restaurant/plats').'?page=2"', $html);
        $this->assertStringNotContainsString('livewire', $this->hrefsDePagination($html));
    }

    /**
     * Le défaut était GÉNÉRAL : ce balayage nomme les vues concernées.
     *
     * Il ne rend aucune de ces pages — le correctif est global, une seule
     * preuve de comportement suffit. Ce qu'il tient, c'est que la correction
     * reste PERTINENTE : le jour où plus aucune vue ne rend `->links()`, ce
     * fichier doit être relu plutôt que de rester vert sur rien.
     */
    #[Test]
    public function les_vues_paginees_sont_bien_celles_qui_rendent_de_vrais_liens(): void
    {
        $vues = [];

        foreach ((new Finder())->files()->in(resource_path('views/pwa'))->name('*.blade.php') as $fichier) {
            if (str_contains((string) file_get_contents($fichier->getRealPath()), '->links(')) {
                $vues[] = $fichier->getRelativePathname();
            }
        }

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_VUES_PAGINEES,
            count($vues),
            'Le balayage des vues paginées est vide ou cassé.',
        );

        // Le résolveur vit à UN SEUL endroit, et ce cas le nomme : un
        // `->withPath(` ajouté dans une vue serait un second auteur.
        $provider = (string) file_get_contents(app_path('Providers/AppServiceProvider.php'));

        $this->assertStringContainsString(
            'currentPathResolver',
            $provider,
            'Le résolveur de chemin de pagination a disparu du seul endroit qui le pose : les '
            .'liens « Suivant » repartiront vers /livewire/update dès le premier rendu Livewire.',
        );
    }

    // =====================================================================
    // Décor
    // =====================================================================

    /**
     * Le parcours RÉEL du navigateur : la page est servie, puis une action
     * Livewire la re-rend — et c'est ce second rendu qui portait des liens
     * cassés.
     *
     * L'instantané est repris TEL QUEL du HTML servi : c'est lui qui porte
     * `memo.path`, donc l'URL que le résolveur doit retrouver. Le fabriquer à
     * la main reviendrait à écrire la réponse qu'on attend.
     */
    private function apresUneMiseAJourLivewire(string $chemin, string $propriete, string $valeur): string
    {
        $page = (string) $this->get($chemin)->assertOk()->getContent();

        $this->assertSame(
            1,
            preg_match('/wire:snapshot="([^"]*)"/', $page, $capture),
            'Aucun instantané Livewire dans la page : le parcours ne peut pas être rejoué.',
        );

        $reponse = $this->withHeaders(['X-Livewire' => '1'])->postJson('/'.Livewire::getUpdateUri(), [
            'components' => [[
                'snapshot' => html_entity_decode($capture[1], ENT_QUOTES),
                // `updates`, et non un appel a `$set` : c'est la forme qu'un
                // `wire:model.live` envoie reellement, donc celle que le
                // navigateur a produite quand le defaut est apparu.
                'updates' => [$propriete => $valeur],
                'calls' => [],
            ]],
        ])->assertOk();

        return (string) data_get($reponse->json(), 'components.0.effects.html');
    }

    /** Les seuls `href` qui nous intéressent : ceux de la barre de pagination. */
    private function hrefsDePagination(string $html): string
    {
        $debut = strpos($html, '<nav role="navigation"');

        $this->assertNotFalse($debut, 'Aucune barre de pagination rendue : le cas ne prouve rien.');

        $fin = strpos($html, '</nav>', $debut);

        return substr($html, $debut, ($fin === false ? strlen($html) : $fin) - $debut);
    }

    /** Assez de fiches pour dépasser une page (`Restauration::PAR_PAGE` = 10). */
    private function fiches(int $nombre): void
    {
        $article = Article::create([
            'libelle' => 'Riz local (kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '20.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $compositions = app(CompositionRecetteService::class);

        for ($i = 1; $i <= $nombre; $i++) {
            $compositions->remplacerComposition(
                Recette::create(['libelle' => 'Fiche '.str_pad((string) $i, 2, '0', STR_PAD_LEFT)]),
                [['article_id' => $article->id, 'quantite_unitaire' => '0.100']],
            );
        }
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'compte.administrateur',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    protected function tearDown(): void
    {
        // Le résolveur est un état STATIQUE du framework : le laisser derrière
        // soi ferait dépendre les cas suivants de l'ordre d'exécution.
        Paginator::currentPathResolver(static fn (): string => url()->current());

        parent::tearDown();
    }
}
