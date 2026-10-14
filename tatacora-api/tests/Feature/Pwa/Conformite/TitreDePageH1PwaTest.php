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
 * G2 — « Une page, un seul `<h1>`, et il porte son titre. »
 *
 * ## Les deux défauts mesurés le 31/08/2026
 *
 * 1. **Le double `<h1>`.** Sept vues ouvraient par un en-tête institutionnel
 *    d'impression (`hidden print:block`) contenant
 *    `<h1>TATACORA AFRIQUE — GÎTE CHEZ NOËL</h1>` **avant** le titre de page.
 *    Deux `<h1>` par page, dont le premier n'est pas le titre : c'est aussi ce
 *    qu'un lecteur d'écran annonce en premier. **La correction attendue est de
 *    passer le bloc d'impression en `<h2>`/`<p>`**, pas de supprimer
 *    l'en-tête : le papier a besoin de porter le nom de l'établissement,
 *    l'écran a besoin d'un seul titre.
 *
 * 2. **Le titre reformulé** par rapport à la maquette d'alors (« Fournisseurs
 *    & Commandes d'achat » contre « Fournisseurs & Achats »…).
 *
 * ## Ce qui a changé le 10/09/2026 (PA-183)
 *
 * Le titre rendu était comparé au `<h1>` d'une page de `prototype_v2/`, que le
 * trait de localisation du maître désignait. Depuis la décision du Product
 * Owner du 10/09/2026, la VUE BLADE est le maître et `prototype_v2/` une
 * ancienne version : re-cibler la comparaison sur la vue la comparerait à
 * elle-même. Elle est remplacée par l'invariant qui ne demande aucune
 * référence extérieure — **chaque écran porte UN titre `<h1>`**, sauf ceux
 * d'une liste FERMÉE qui dit pourquoi. L'accord de ce titre avec la balise
 * `<title>` est tenu par `BaliseTitrePwaTest`. Le cas « écrans sans page
 * maître » a disparu avec le rattachement lui-même.
 *
 * Le `<h1>` est lu dans le HTML **rendu** (jamais le source Blade : une clé
 * de traduction ne se compare pas à une phrase), entités décodées et espaces
 * normalisés.
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md
 */
final class TitreDePageH1PwaTest extends TestCase
{
    use InventaireDesEcransPwa;
    use RefreshDatabase;
    use SertLesEcransPwa;

    /**
     * Plancher mesuré le 31/08/2026 : 42 écrans servis en HTTP 200 sur 44
     * routes. Il est posé sous la valeur mesurée — un écran s'ajoute, aucun ne
     * disparaît en silence.
     */
    private const PLANCHER_ECRANS_RELUS = 35;

    /**
     * Les écrans servis SANS `<h1>`, chacun avec sa raison. Liste FERMÉE,
     * mesurée le 10/09/2026 (PA-183) : un écran qui perd son titre sans y
     * figurer fait échouer le cas — et un écran qui y figure alors qu'il a
     * retrouvé un titre aussi, pour qu'aucune raison périmée ne reste écrite.
     *
     * @var array<string, string>
     */
    private const ECRANS_SANS_H1 = [
        '/pwa/pos/comptant' => 'Ecran de caisse : la salle et le panier occupent toute la page, aucun titre '
            .'de page n y est pose — l ancienne maquette (`pos.html`) n en portait pas non plus. L ecran '
            .'se nomme par l entree « Point de vente » active du menu et par sa balise <title>.',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function chaque_ecran_ne_porte_qu_un_seul_h1(): void
    {
        $fautifs = [];
        $relus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;   // l ecran ne se charge pas : c est l affaire de G1.
            }

            $relus++;
            $titres = $this->titresH1($html);

            if (count($titres) > 1) {
                $fautifs[] = "{$ecran['url']} porte ".count($titres).' <h1> : « '
                    .implode(' » puis « ', $titres).' »';
            }
        }

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_ECRANS_RELUS,
            $relus,
            "Seuls {$relus} ecrans ont ete relus (plancher ".self::PLANCHER_ECRANS_RELUS.'). '
            .'Un balayage vide serait vert.',
        );

        $this->assertSame(
            [],
            $fautifs,
            "Des ecrans portent plusieurs <h1>. L en-tete institutionnel d impression\n"
            ."(« TATACORA AFRIQUE — GITE CHEZ NOEL ») doit passer en <h2>/<p> : le papier\n"
            ."garde le nom de l etablissement, l ecran garde un seul titre.\n  "
            .implode("\n  ", $fautifs),
        );
    }

    /**
     * L'en-tête d'impression est nommé séparément parce que sa correction est
     * connue et tient en une balise. Le laisser noyé dans le cas précédent
     * ferait chercher la cause à chaque relecture.
     */
    #[Test]
    public function l_en_tete_d_impression_n_est_jamais_un_h1(): void
    {
        $fautifs = [];
        $relus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $relus++;

            foreach ($this->titresH1($html) as $titre) {
                if (str_contains($titre, 'TATACORA AFRIQUE') && str_contains($titre, 'CHEZ NO')) {
                    $fautifs[] = "{$ecran['url']} → <h1>{$titre}</h1>";
                }
            }
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_ECRANS_RELUS, $relus, 'Balayage vide.');

        $this->assertSame(
            [],
            $fautifs,
            "L en-tete institutionnel d impression est rendu en <h1>, devant le titre\n"
            ."de la page. Il doit etre un <h2> (nom de l etablissement) suivi d un <p>.\n  "
            .implode("\n  ", $fautifs),
        );
    }

    /**
     * Chaque écran porte un titre `<h1>` non vide — l'invariant qui remplace,
     * depuis PA-183, la comparaison au `<h1>` d'une page de `prototype_v2/`.
     */
    #[Test]
    public function chaque_ecran_porte_un_titre_h1(): void
    {
        $sansTitre = [];
        $perimes = [];
        $relus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $relus++;
            $aUnTitre = $this->titresH1($html) !== [];
            $declare = array_key_exists($ecran['url'], self::ECRANS_SANS_H1);

            if (! $aUnTitre && ! $declare) {
                $sansTitre[] = $ecran['url'];
            }

            if ($aUnTitre && $declare) {
                $perimes[] = $ecran['url'];
            }
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_ECRANS_RELUS, $relus, 'Balayage vide.');

        $this->assertSame(
            [],
            $sansTitre,
            "Des ecrans ne portent aucun <h1>. Le titre est la premiere chose qui se voit,\n"
            ."et la premiere qu un lecteur d ecran annonce. Si l absence est voulue,\n"
            ."l inscrire dans ECRANS_SANS_H1 avec sa raison.\n  "
            .implode("\n  ", $sansTitre),
        );

        $this->assertSame(
            [],
            $perimes,
            "Des ecrans declares SANS <h1> en portent un : leur raison est perimee,\n"
            ."la retirer de ECRANS_SANS_H1.\n  ".implode("\n  ", $perimes),
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * @return list<string>
     */
    private function titresH1(string $html): array
    {
        if (preg_match_all('#<h1\b[^>]*>(.*?)</h1>#si', $html, $trouves) < 1) {
            return [];
        }

        $titres = [];

        foreach ($trouves[1] as $brut) {
            $texte = $this->texteVisible($brut);
            if ($texte !== '') {
                $titres[] = $texte;
            }
        }

        return $titres;
    }
}
