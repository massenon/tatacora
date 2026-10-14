<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use Database\Seeders\DemonstrationSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\InventaireDesEcransPwa;
use Tests\Feature\Pwa\Concerns\SertLesEcransPwa;
use Tests\TestCase;

/**
 * G5 — « Un entête de colonne n'est jamais écrit en majuscules en dur. »
 *
 * ## Ce que ce fichier vérifiait jusqu'au 10/09/2026, et pourquoi c'est retiré
 *
 * Deux cas confrontaient les entêtes RENDUES par chaque écran aux tableaux
 * d'une page de `prototype_v2/` (`<thead>`, `entetes: [...]`,
 * `colonnes: [{ libelle }]`, `tableau([...])`) : « aucune colonne du maître ne
 * disparaît de la PWA » et « aucune colonne n'est inventée par la PWA ». Ils
 * avaient trouvé onze colonnes perdues le 31/08/2026, dont `Reste dû` sur la
 * grille des réservations.
 *
 * Depuis la décision du Product Owner du 10/09/2026 (PA-182, PA-183), la VUE
 * BLADE est le maître et `prototype_v2/` une ancienne version. Re-cibler ces
 * deux cas sur la vue reviendrait à la comparer à elle-même : ils sont
 * retirés. La conformité du client Flutter aux colonnes de la vue est mesurée
 * par `tatacora_flutter/tool/conformite_blade/`.
 *
 * ## Ce qui reste, et ne demande aucun maître
 *
 * Un entête écrit `VÉHICULE` dans le HTML, là où la classe `uppercase` ferait
 * le rendu, n'est pas un détail typographique : `uppercase` est une règle
 * CSS. Elle ne s'applique ni dans un export CSV, ni dans un PDF généré côté
 * serveur — la majuscule ressort telle quelle sur le document remis au
 * comptable. L'invariant vaut pour toute la PWA.
 *
 * Jusqu'au 10/09/2026, un entête que le maître écrivait lui-même en capitales
 * était toléré. Cette tolérance est désormais portée par une liste FERMÉE de
 * sigles (`SIGLES`), relevée le jour de la conversion : un sigle s'écrit en
 * capitales partout, écran comme papier, et l'y inscrire est une décision.
 *
 * ## La donnée de démonstration est semée, et c'est la substance de la garde
 *
 * Sans elle, chaque écran rend son état vide et le `<thead>` de son tableau,
 * placé derrière `@if ($lignes->isEmpty()) … @else`, n'existe pas dans le
 * HTML (mesuré le 31/08/2026 : une garde qui ne lisait plus aucun entête).
 * `DemonstrationSeeder` est le jeu d'`AmorcageDemonstrationTest` — celui qui passe
 * par les vrais services.
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md Article 4
 */
final class ColonnesDesTableauxPwaTest extends TestCase
{
    use InventaireDesEcransPwa;
    use RefreshDatabase;
    use SertLesEcransPwa;

    /**
     * Les entêtes écrits en capitales, ÉCRAN PAR ÉCRAN. Liste FERMÉE relevée
     * le 10/09/2026 (PA-183) : jusqu'à cette date, l'ancien contrôle les
     * tolérait parce que l'ancienne maquette les écrivait elle-même ainsi —
     * vérifié ce jour-là, chacun y figure en capitales, casse comprise. La
     * liste reconduit donc EXACTEMENT la tolérance d'avant, sans l'élargir,
     * et chaque entrée est scopée à son écran : un « DATE » en capitales
     * ailleurs reste refusé.
     *
     * Deux familles, et elles ne se valent pas :
     *  - des SIGLES et conventions (CNSS, ITS, VPS, CMP, CA, VNC, ACTIF /
     *    PASSIF du bilan SYSCOHADA), qui s'écrivent en capitales partout,
     *    écran comme papier ;
     *  - des MOTS ORDINAIRES reconduits en capitales depuis la maquette
     *    (`/pwa/import-export`, `/pwa/mon-profil`). Ils tombent sous la règle
     *    CSV/PDF de ce cas : ils sont DÉCLARÉS plutôt que tolérés en silence,
     *    et restent une dette à corriger dans la vue.
     *
     * Un entête déclaré qu'aucun écran ne rend plus fait échouer la
     * contre-épreuve.
     *
     * @var array<string, list<string>>
     */
    private const CAPITALES_DECLAREES = [
        // Conventions du bilan SYSCOHADA et sigle comptable.
        '/pwa/comptabilite' => ['ACTIF', 'PASSIF', 'VNC'],
        // DETTE — mots ordinaires en capitales dans le HTML.
        '/pwa/import-export' => [
            'COLONNE', 'OBLIGATOIRE', 'VALEURS ATTENDUES', 'FICHIER', 'DATE', 'TABLE',
            'ACTION', 'ÉLÉMENT', 'MODULE', 'ARCHIVÉ LE', 'PAR',
        ],
        // DETTE — mots ordinaires en capitales, et un sigle (IP).
        '/pwa/mon-profil' => ['DATE / HEURE', 'ACTION', 'MODULE', 'IP'],
        // Sigles sociaux et fiscaux.
        '/pwa/paie' => ['N° CNSS', 'CNSS 3,6 %', 'ITS', 'VPS 4 %'],
        // Cout moyen pondere.
        '/pwa/stocks' => ['CMP'],
        // Chiffre d'affaires.
        '/pwa/tourisme' => ['CA'],
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(DemonstrationSeeder::class);
    }

    #[Test]
    public function les_entetes_ne_sont_pas_ecrits_en_majuscules_en_dur(): void
    {
        $criards = [];
        $declaresRendus = [];
        $relus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $fautifs = [];

            foreach (array_unique($this->entetesRendues($html)) as $entete) {
                $relus++;

                // Un entete est « criard » s il contient au moins deux lettres
                // et aucune minuscule. Le seuil de deux ecarte « N° », « % »
                // et les sigles d une lettre.
                $lettres = (string) preg_replace('#[^\p{L}]#u', '', $entete);
                if (mb_strlen($lettres) < 2) {
                    continue;
                }

                if ($lettres !== mb_strtoupper($lettres, 'UTF-8')) {
                    continue;
                }

                if (in_array($entete, self::CAPITALES_DECLAREES[$ecran['url']] ?? [], true)) {
                    $declaresRendus[$ecran['url'].' → '.$entete] = true;

                    continue;
                }

                $fautifs[] = "« {$entete} »";
            }

            if ($fautifs !== []) {
                $criards[] = "{$ecran['url']} : ".implode(', ', $fautifs);
            }
        }

        $this->assertGreaterThanOrEqual(
            60,
            $relus,
            "Seules {$relus} entetes ont ete relues (plancher 60) : le motif d extraction "
            .'des <th> ne mord plus, ou la donnee de demonstration n est plus semee.',
        );

        $this->assertSame(
            [],
            $criards,
            "Des entetes de colonne sont ecrits en majuscules DANS LE HTML. Les ecrire en\n"
            ."casse normale et laisser la classe `uppercase` faire le rendu — une regle CSS\n"
            ."qui ne s applique ni au CSV ni au PDF. Un vrai sigle s inscrit, ecran par\n"
            ."ecran, dans CAPITALES_DECLAREES.\n  "
            .implode("\n  ", $criards),
        );

        // Contre-epreuve : un entete declare qu aucun ecran ne rend plus est une
        // tolerance perimee — elle couvrirait demain un entete qui n en est pas un.
        $declares = [];
        foreach (self::CAPITALES_DECLAREES as $url => $entetes) {
            foreach ($entetes as $entete) {
                $declares[] = $url.' → '.$entete;
            }
        }

        $this->assertSame(
            [],
            array_values(array_diff($declares, array_keys($declaresRendus))),
            'Des entetes declares dans CAPITALES_DECLAREES ne sont plus rendus en capitales par '
            .'leur ecran : les retirer de la liste.',
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * Les entêtes de colonne rendues par un écran.
     *
     * @return list<string>
     */
    private function entetesRendues(string $html): array
    {
        $entetes = [];

        if (preg_match_all('#<thead\b[^>]*>(.*?)</thead>#si', $html, $theads) < 1) {
            return [];
        }

        foreach ($theads[1] as $thead) {
            foreach ($this->cellulesEntete($thead) as $libelle) {
                $entetes[] = $libelle;
            }
        }

        return $entetes;
    }

    /**
     * @return list<string>
     */
    private function cellulesEntete(string $thead): array
    {
        if (preg_match_all('#<th\b[^>]*>(.*?)</th>#si', $thead, $trouves) < 1) {
            return [];
        }

        $libelles = [];

        foreach ($trouves[1] as $cellule) {
            $texte = $this->texteVisible($cellule);

            // Une cellule vide est la colonne de case a cocher ou d icone :
            // elle n a pas de libelle a juger.
            if ($texte === '') {
                continue;
            }

            $libelles[] = $texte;
        }

        return $libelles;
    }
}
