<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\InventaireDesEcransPwa;
use Tests\Feature\Pwa\Concerns\SertLesEcransPwa;
use Tests\TestCase;

/**
 * G6 — les trois éléments du TABLEAU GÉNÉRIQUE : un état vide, une case à
 * cocher de sélection en entête, une pagination.
 *
 * ## D'où vient ce contrôle
 *
 * L'ancienne maquette (`prototype_v2/assets/js/crud-ui.js`) construisait le
 * même tableau pour toutes les pages qui l'utilisaient, et y posait ces trois
 * choses. Mesuré le 31/08/2026 : la PWA les avait perdues en réécrivant chaque
 * tableau à la main — `grep "Aucun résultat"` ne rendait aucune occurrence
 * rendue. Un tableau sans lignes et sans message ne dit pas si le filtre est
 * trop étroit, si la donnée n'existe pas, ou si l'écran est cassé.
 *
 * ## Ce qui a changé le 10/09/2026 (PA-183)
 *
 * La vue Blade est désormais le maître et `prototype_v2/` une ancienne
 * version. Deux choses étaient LUES dans la maquette, elles ne le sont plus :
 *
 * 1. **Les écrans concernés** étaient dérivés des pages de la maquette portant
 *    le conteneur `crud-table-zone`. Ils sont désormais écrits dans
 *    `ECRANS` — la liste que cette dérivation rendait le jour de la
 *    conversion —, et un écran qui y figure sans être servi fait échouer le
 *    balayage.
 * 2. **Les phrases de l'état vide** étaient lues dans `crud-ui.js`. Elles le
 *    sont désormais dans les libellés de la PWA (`pwa.achats.vide_titre`,
 *    `pwa.achats.vide_detail`) : ce sont les mots que la vue affiche.
 *
 * Le « conseil d'export » (« Astuce : utilisez la case à cocher… ») que la
 * maquette posait dans sa modale d'export n'existe dans AUCUN libellé ni
 * aucune vue de la PWA (relevé le 10/09/2026) : sa moitié du contrôle est
 * retirée, la case à cocher reste exigée pour elle-même.
 *
 * ## Une limite écrite : la pagination est vérifiée par PROCURATION
 *
 * « Rendue dès que le jeu dépasse une page » ne se constate qu'avec un jeu qui
 * dépasse une page. Le contrôle porte donc sur le MÉCANISME : le composant
 * pagine (`paginate(`) et la vue rend les liens (`->links(`).
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md (« zéro écran vide »)
 */
final class TableauGeneriquePwaTest extends TestCase
{
    use InventaireDesEcransPwa;
    use RefreshDatabase;
    use SertLesEcransPwa;

    /**
     * Les écrans qui rendent le tableau générique. Liste FERMÉE, relevée le
     * 10/09/2026 : c'est celle que la dérivation par la maquette rendait.
     *
     * @var list<string>
     */
    private const ECRANS = [
        '/pwa/achats',
        '/pwa/facturation',
        '/pwa/hebergement',
        '/pwa/restaurant/plats',
    ];

    /**
     * Les écrans du tableau générique rendus en CARTES : pas d'entête, donc pas
     * de case à cocher à y chercher. Chacun avec sa raison.
     *
     * @var array<string, string>
     */
    private const EN_CARTES = [
        '/pwa/hebergement' => 'Le moteur generique y est configure en mode cartes depuis la maquette '
            .'d origine (`m1-hebergement.html`, `modeAffichage: \'cartes\'`) : aucune ligne '
            .'d entete ou poser une case de selection.',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function chaque_tableau_generique_a_un_etat_vide(): void
    {
        [$titre, $invite] = $this->phrasesEtatVide();

        $sans = [];

        foreach ($this->ecransDuTableauGenerique() as $ecran) {
            $html = $this->htmlDe($ecran, $code);
            if ($html === null) {
                $sans[] = "{$ecran['url']} → HTTP {$code}";

                continue;
            }

            $absentes = [];

            foreach ([$titre, $invite] as $phrase) {
                if (! str_contains($this->texteVisible($html), $phrase)) {
                    $absentes[] = $phrase;
                }
            }

            if ($absentes !== []) {
                $sans[] = "{$ecran['url']} : « ".implode(' » et « ', $absentes).' » absentes';
            }
        }

        $this->assertSame(
            [],
            $sans,
            "Le tableau generique affiche un etat vide ; ces ecrans n en ont pas.\n"
            ."La base de test est vide : ces tableaux sont donc rendus SANS AUCUNE ligne\n"
            ."et sans un mot d explication — l ecran vide que la Directive interdit.\n  "
            .implode("\n  ", $sans),
        );
    }

    #[Test]
    public function chaque_tableau_generique_pose_une_case_de_selection(): void
    {
        $sansCase = [];
        $perimes = [];

        foreach ($this->ecransDuTableauGenerique() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $enCartes = array_key_exists($ecran['url'], self::EN_CARTES);
            $porteUneCase = $this->uneCaseDeSelectionExiste($html);

            if (! $porteUneCase && ! $enCartes) {
                $sansCase[] = "{$ecran['url']} : aucune case a cocher de selection en entete de tableau";
            }

            // Contre-epreuve : un ecran declare « en cartes » qui pose desormais
            // une case a une raison perimee.
            if ($porteUneCase && $enCartes) {
                $perimes[] = $ecran['url'];
            }
        }

        $this->assertSame(
            [],
            $sansCase,
            "Le tableau generique pose une case a cocher de selection en entete ; ces ecrans\n"
            ."n en ont pas.\n  ".implode("\n  ", $sansCase),
        );

        $this->assertSame([], $perimes, 'Ecran declare en cartes qui pose une case : retirer sa raison de EN_CARTES.');
    }

    #[Test]
    public function chaque_tableau_generique_pagine(): void
    {
        $sans = [];

        foreach ($this->ecransDuTableauGenerique() as $ecran) {
            $composant = $ecran['fichierComposant'] ?? null;
            $vue = $ecran['fichierVue'] ?? null;

            if (! is_string($composant) || ! is_file($composant) || ! is_string($vue) || ! is_file($vue)) {
                $sans[] = "{$ecran['url']} : composant ou vue introuvable, pagination invérifiable";

                continue;
            }

            $sourceComposant = (string) file_get_contents($composant);
            $sourceVue = (string) file_get_contents($vue);

            $pagine = str_contains($sourceComposant, 'paginate(')
                || str_contains($sourceComposant, 'simplePaginate(');
            $rendLesLiens = str_contains($sourceVue, '->links(');

            if (! $pagine || ! $rendLesLiens) {
                $sans[] = "{$ecran['url']} : "
                    .(! $pagine ? 'le composant ne pagine pas' : '')
                    .(! $pagine && ! $rendLesLiens ? ' et ' : '')
                    .(! $rendLesLiens ? 'la vue ne rend pas les liens de pagination' : '');
            }
        }

        $this->assertSame(
            [],
            $sans,
            "Le tableau generique pose une pagination sous chaque jeu de resultats.\n"
            ."(Controle par procuration : le composant pagine ET la vue rend les liens.)\n  "
            .implode("\n  ", $sans),
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * Les écrans de `ECRANS`, tels que la PWA les sert. Un écran listé que la
     * PWA ne sert plus fait ÉCHOUER : une liste qui se viderait en silence
     * rendrait les trois cas verts sans rien avoir regardé.
     *
     * @return list<array<string, mixed>>
     */
    private function ecransDuTableauGenerique(): array
    {
        $servis = [];
        foreach ($this->ecransPwa() as $ecran) {
            $servis[$ecran['url']] = $ecran;
        }

        $retenus = [];
        foreach (self::ECRANS as $url) {
            $this->assertArrayHasKey(
                $url,
                $servis,
                "L ecran {$url} figure dans ECRANS mais la PWA ne le sert plus : la liste est perimee.",
            );
            $retenus[] = $servis[$url];
        }

        $this->assertCount(4, $retenus, 'Plancher : quatre ecrans du tableau generique.');

        return $retenus;
    }

    /**
     * Les deux phrases de l'état vide, LUES dans les libellés de la PWA.
     *
     * @return array{0: string, 1: string}
     */
    private function phrasesEtatVide(): array
    {
        $titre = (string) __('pwa.achats.vide_titre');
        $invite = (string) __('pwa.achats.vide_detail');

        // Une cle introuvable se rend telle quelle : le cas comparerait alors
        // la page a un nom de cle, et accuserait tous les ecrans a tort.
        $this->assertNotSame('pwa.achats.vide_titre', $titre, 'Le libelle de l etat vide a disparu de lang/fr/pwa.php.');
        $this->assertNotSame('pwa.achats.vide_detail', $invite, 'Le libelle de l etat vide a disparu de lang/fr/pwa.php.');

        return [trim($titre), trim($invite)];
    }

    /**
     * Une case à cocher de sélection dans l'entête d'un tableau rendu.
     */
    private function uneCaseDeSelectionExiste(string $html): bool
    {
        if (preg_match_all('#<thead\b[^>]*>(.*?)</thead>#si', $html, $theads) < 1) {
            return false;
        }

        foreach ($theads[1] as $thead) {
            if (preg_match('#<input[^>]+type="checkbox"#i', $thead) === 1) {
                return true;
            }
        }

        return false;
    }
}
