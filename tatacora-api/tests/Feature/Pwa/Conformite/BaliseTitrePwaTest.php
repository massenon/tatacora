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
 * G3 — « La balise `<title>` dit de quelle page il s'agit. »
 *
 * ## Le défaut, et pourquoi il est exemplaire
 *
 * Mesuré le 31/08/2026 : **toutes** les pages de la PWA rendent
 * `<title>TATACORA AFRIQUE</title>`, alors que les composants portent partout
 * un `#[Title(...)]` ou passent `'title' => '…'` au layout. La cause est d'une
 * ligne : `resources/views/pwa/partials/tete.blade.php` lit `$titre`, et le
 * `render()` des composants transmet `title`. La variable attendue n'arrive
 * jamais, le `??` fait son office, et chaque onglet du navigateur affiche la
 * même chose — quinze onglets ouverts sur le même mot.
 *
 * **C'est la raison d'être de cette garde : elle lit le HTML RENDU.** Un test
 * qui aurait relu l'attribut `#[Title]` du composant, ou la chaîne `'title'`
 * du `render()`, aurait été vert sur les 44 écrans. Le code affirmait un état
 * qu'il n'avait pas vérifié — la famille PA-59/60/61, ici sur un titre.
 *
 * ## Ce qui est exigé
 *
 * 1. Le `<title>` rendu **diffère d'une page à l'autre** : deux écrans ne
 *    peuvent pas porter le même.
 * 2. Il porte la marque, et il porte autre chose que la marque : la forme
 *    `<Nom de l'écran> — TATACORA AFRIQUE`.
 * 3. Le nom de l'écran est celui du `<h1>` que la page REND — la même phrase
 *    dans l'onglet et dans le corps. Jusqu'au 10/09/2026, la référence était
 *    le `<h1>` d'une page de `prototype_v2/` ; la vue Blade étant désormais
 *    le maître (PA-183), c'est celui de la page elle-même. L'invariant ne
 *    demande aucune référence extérieure : deux vocabulaires pour la même page
 *    divergeraient dès la première reformulation.
 *
 * ## Preuve que ces cas peuvent échouer
 *
 * Les trois cas étaient ROUGES au 31/08/2026 sur le défaut reproduit ci-dessus :
 * 19 écrans partageaient le titre « TATACORA AFRIQUE ». Un test rouge sur un
 * défaut reproduit, dont le message nomme les URL une par une, prouve qu'il
 * peut échouer.
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md
 */
final class BaliseTitrePwaTest extends TestCase
{
    use InventaireDesEcransPwa;
    use RefreshDatabase;
    use SertLesEcransPwa;

    /**
     * La marque, telle que `lang/fr/pwa.php` la porte. Lue, jamais recopiée :
     * une marque changée ici et là-bas divergerait sans que rien ne le dise.
     */
    private function marque(): string
    {
        return trim((string) __('pwa.marque'));
    }

    /** Plancher mesuré le 31/08/2026 : 42 écrans servis en HTTP 200 sur 44. */
    private const PLANCHER_ECRANS_RELUS = 35;

    /**
     * Plancher de comparaisons titre / `<h1>` : 28 écrans ancrés étaient
     * comparés au 31/08/2026 sur l'ancienne référence ; l'invariant porte
     * désormais sur tout écran à `<h1>` unique, donc au moins autant.
     */
    private const PLANCHER_COMPARAISONS = 28;

    /**
     * Les écrans dont le `<title>` nomme DÉLIBÉRÉMENT autre chose que le
     * `<h1>`, chacun avec sa raison et sa source. Liste FERMÉE, relevée le
     * 10/09/2026 (PA-183) : un écran qui y figure et dont les deux noms se
     * sont rejoints fait échouer le cas, pour qu'aucune raison périmée ne
     * reste écrite.
     *
     * @var array<string, string>
     */
    private const TITRE_DISTINCT_DU_H1 = [
        '/pwa/demarrage' => 'Ecran de demarrage : son <h1> est la MARQUE, pas un titre de page ; l onglet '
            .'nomme l ecran d abord (« Demarrage — … »). Ecart delibere documente dans '
            .'`lang/fr/coquille_pwa.php` (cle demarrage_titre_page).',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function deux_ecrans_ne_portent_jamais_le_meme_titre_de_navigateur(): void
    {
        $parTitre = [];

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $titre = $this->baliseTitre($html);
            if ($titre === null) {
                continue;
            }

            $parTitre[$titre][] = (string) $ecran['url'];
        }

        $relus = array_sum(array_map('count', $parTitre));
        $this->assertGreaterThanOrEqual(
            self::PLANCHER_ECRANS_RELUS,
            $relus,
            "Seuls {$relus} titres ont ete lus (plancher ".self::PLANCHER_ECRANS_RELUS.'). '
            .'Le motif de lecture de <title> ne mord plus.',
        );

        $doublons = [];
        foreach ($parTitre as $titre => $urls) {
            if (count($urls) > 1) {
                $doublons[] = '« '.$titre.' » sur '.count($urls).' ecrans : '.implode(', ', $urls);
            }
        }

        $this->assertSame(
            [],
            $doublons,
            "Des ecrans partagent la meme balise <title>. Le navigateur affiche alors le\n"
            ."meme mot sur tous les onglets, et l historique devient illisible.\n"
            ."Cause connue (31/08/2026) : `pwa/partials/tete.blade.php` lit \$titre quand\n"
            ."les composants transmettent 'title' — le ?? renvoie la marque a chaque page.\n  "
            .implode("\n  ", $doublons),
        );
    }

    #[Test]
    public function chaque_titre_nomme_l_ecran_puis_la_marque(): void
    {
        $marque = $this->marque();
        $fautifs = [];
        $relus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            $titre = $this->baliseTitre($html);
            if ($titre === null) {
                $fautifs[] = "{$ecran['url']} n a aucune balise <title>";

                continue;
            }

            $relus++;

            $suffixe = ' — '.$marque;

            if (! str_ends_with($titre, $suffixe) || $titre === $suffixe) {
                $fautifs[] = "{$ecran['url']} → « {$titre} » (attendu « <Nom de l ecran>{$suffixe} »)";
            }
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_ECRANS_RELUS, $relus + count($fautifs), 'Balayage vide.');

        $this->assertSame(
            [],
            $fautifs,
            "Des balises <title> ne suivent pas la forme « <Nom de l ecran> — ".$marque." » :\n  "
            .implode("\n  ", $fautifs),
        );
    }

    /**
     * Le nom porté par le `<title>` est celui du `<h1>` que la page rend.
     *
     * Les écrans qui ne portent pas exactement UN `<h1>` sont laissés à
     * `TitreDePageH1PwaTest` : c'est lui qui dit s'ils en ont un, et un seul.
     */
    #[Test]
    public function le_nom_porte_par_le_titre_est_le_h1_de_la_page(): void
    {
        $marque = $this->marque();
        $ecarts = [];
        $perimes = [];
        $compares = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran);
            if ($html === null) {
                continue;
            }

            if (preg_match_all('#<h1\b[^>]*>(.*?)</h1>#si', $html, $trouves) !== 1) {
                continue;   // zero ou plusieurs <h1> : l affaire de G2.
            }

            $h1 = $this->texteVisible($trouves[1][0]);
            $titre = $this->baliseTitre($html);
            if ($h1 === '' || $titre === null) {
                continue;
            }

            $compares++;
            $accorde = $titre === $h1.' — '.$marque;
            $declare = array_key_exists($ecran['url'], self::TITRE_DISTINCT_DU_H1);

            if (! $accorde && ! $declare) {
                $ecarts[] = "{$ecran['url']} → « {$titre} » (le <h1> de la page est « {$h1} »)";
            }

            if ($accorde && $declare) {
                $perimes[] = $ecran['url'];
            }
        }

        $this->assertSame(
            [],
            $perimes,
            'Des ecrans declares dans TITRE_DISTINCT_DU_H1 ont desormais un titre accorde a leur '
            ."<h1> : leur raison est perimee, la retirer.\n  ".implode("\n  ", $perimes),
        );

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_COMPARAISONS,
            $compares + count($ecarts),
            'Trop peu d ecrans compares : le motif de lecture du <h1> ne mord plus.',
        );

        $this->assertSame(
            [],
            $ecarts,
            "Le nom porte par la balise <title> n est pas celui du <h1> de la page — deux\n"
            ."vocabulaires pour le meme ecran :\n  "
            .implode("\n  ", $ecarts),
        );
    }

    // ------------------------------------------------------------------ outils

    private function baliseTitre(string $html): ?string
    {
        if (preg_match('#<title\b[^>]*>(.*?)</title>#si', $html, $trouve) !== 1) {
            return null;
        }

        $texte = $this->texteVisible($trouve[1]);

        return $texte === '' ? null : $texte;
    }
}
