<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Pwa\Support\MenuLateral;
use Illuminate\Contracts\View\View;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Livewire\Component;

/**
 * Recherche globale instantanée de la barre supérieure — AJOUT à la
 * maquette, demandé par l'audit du Product Owner du 01/09/2026 (« Intégrer
 * un champ de recherche transversale dans la barre supérieure »). Le maître
 * n'en porte pas : l'écart est un ajout décidé, daté, jamais un oubli.
 *
 * ## Ce qu'elle cherche, et où elle mène
 *
 * Deux familles de résultats :
 *
 * 1. **Les pages** — les entrées du menu latéral dont le nom correspond,
 *    mêmes libellés et même filtre RBAC que le menu (`MenuLateral::pour`).
 * 2. **Les données** — clients, articles, plats, carte du bar, factures,
 *    fournisseurs, véhicules, circuits. Chaque résultat mène à l'ÉCRAN du
 *    module avec le terme dans `?q=` : les écrans portent déjà leur
 *    recherche en propriété `#[Url(as: 'q')]`, le lien profond retombe sur
 *    le filtre natif de l'écran — jamais un écran de résultats parallèle,
 *    qui dupliquerait chaque liste.
 *
 * Chaque source n'est interrogée que si l'utilisateur a accès à son module
 * (`MenuLateral::moduleAccessible` — la même source RBAC que le menu). Cinq
 * résultats par famille : la recherche invite, l'écran détaille.
 *
 * ## Lecture seule
 *
 * Aucune méthode n'écrit : `render()` et le crochet `updated*` du cadre.
 */
class RechercheGlobale extends Component
{
    /** Le terme saisi — propriété Livewire, jamais une méthode (PA-67). */
    public string $terme = '';

    public const PLAFOND_PAR_FAMILLE = 5;

    /**
     * Les sources de données : module RBAC, table, colonnes cherchées,
     * colonnes affichées, route cible (le terme part en `?q=`).
     *
     * @var array<string, array{module: string, table: string, colonnes: list<string>, libelle: list<string>, route: string}>
     */
    public const SOURCES = [
        'clients' => ['module' => 'M3', 'table' => 'clients', 'colonnes' => ['nom', 'prenom', 'telephone'], 'libelle' => ['prenom', 'nom'], 'route' => 'pwa.clients'],
        'articles' => ['module' => 'M6', 'table' => 'articles', 'colonnes' => ['libelle'], 'libelle' => ['libelle'], 'route' => 'pwa.stocks.liste'],
        'plats' => ['module' => 'M4', 'table' => 'plats', 'colonnes' => ['libelle'], 'libelle' => ['libelle'], 'route' => 'pwa.restaurant.plats'],
        'carte_bar' => ['module' => 'M5', 'table' => 'cartes_boisson', 'colonnes' => ['libelle'], 'libelle' => ['libelle'], 'route' => 'pwa.bar.carte'],
        'factures' => ['module' => 'M2', 'table' => 'factures', 'colonnes' => ['numero_mecef'], 'libelle' => ['numero_mecef'], 'route' => 'pwa.facturation'],
        'fournisseurs' => ['module' => 'M7', 'table' => 'fournisseurs', 'colonnes' => ['raison_sociale'], 'libelle' => ['raison_sociale'], 'route' => 'pwa.achats.liste'],
        'vehicules' => ['module' => 'M8', 'table' => 'vehicules', 'colonnes' => ['immatriculation'], 'libelle' => ['immatriculation'], 'route' => 'pwa.vehicules'],
        'circuits' => ['module' => 'M9', 'table' => 'circuits', 'colonnes' => ['nom'], 'libelle' => ['nom'], 'route' => 'pwa.tourisme'],
    ];

    public function render(): View
    {
        return view('pwa.transverse.recherche-globale', [
            'resultats' => $this->resultats(),
        ]);
    }

    /**
     * @return array{pages: list<array{libelle: string, url: string}>, donnees: array<string, list<array{libelle: string, url: string}>>}
     */
    private function resultats(): array
    {
        $terme = trim($this->terme);

        if (mb_strlen($terme) < 2) {
            return ['pages' => [], 'donnees' => []];
        }

        $utilisateur = auth()->user();

        // 1. Les pages du menu — mêmes libellés, même RBAC.
        $pages = [];
        foreach (MenuLateral::pour($utilisateur) as $section) {
            foreach ($section['items'] as $item) {
                if (mb_stripos($item['nom'], $terme) === false) {
                    continue;
                }

                $pages[] = ['libelle' => $item['nom'], 'url' => $item['url']];
            }
        }

        // 2. Les données, source par source, sous le RBAC du module.
        $donnees = [];

        foreach (self::SOURCES as $famille => $source) {
            if (! MenuLateral::moduleAccessible($utilisateur, $source['module'])) {
                continue;
            }

            if (! Route::has($source['route'])) {
                continue;
            }

            $requete = DB::table($source['table']);

            $requete->where(function ($sous) use ($source, $terme): void {
                foreach ($source['colonnes'] as $colonne) {
                    $sous->orWhere($colonne, 'like', '%' . $terme . '%');
                }
            });

            $lignes = $requete
                ->orderBy($source['libelle'][count($source['libelle']) - 1])
                ->limit(self::PLAFOND_PAR_FAMILLE)
                ->get($source['libelle']);

            if ($lignes->isEmpty()) {
                continue;
            }

            $donnees[$famille] = $lignes->map(static function (object $ligne) use ($source, $terme): array {
                $morceaux = [];
                foreach ($source['libelle'] as $colonne) {
                    $morceaux[] = (string) ($ligne->{$colonne} ?? '');
                }

                return [
                    'libelle' => trim(implode(' ', $morceaux)),
                    // Le lien profond retombe sur le filtre natif de l'écran.
                    'url' => route($source['route'], ['q' => $terme]),
                ];
            })->values()->all();
        }

        return ['pages' => array_slice($pages, 0, self::PLAFOND_PAR_FAMILLE), 'donnees' => $donnees];
    }
}
