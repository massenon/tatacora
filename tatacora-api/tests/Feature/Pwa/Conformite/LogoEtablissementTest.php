<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\ReportEngine\Data\EtatResultat;
use App\Shared\ReportEngine\Renderers\RenduPdf;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le logo de l'établissement est le PNG fourni par le Product Owner —
 * décision du 14/10/2026 (dans le chat au lead), ticket D392, PA-210.
 *
 * Fichier source du PO : PNG 19 431 octets, 735 × 403, fond blanc opaque
 * (« Tatacora », le « o » orange portant la carte de l'Afrique, toit de case
 * tata somba, « AFRIQUE VOYAGE » en vert). Il remplace `logo.jpg` (rond,
 * carré) PARTOUT où le logo s'affiche : barre supérieure, connexion,
 * démarrage, hors connexion, 404, aide, aperçus de Paramètres, favicon de
 * repli, service worker, en-tête des états PDF, icônes du manifeste.
 *
 * Trois gardes :
 *  1. aucune surface affichée ne référence plus l'ancien logo (code RENDU :
 *     commentaires Blade, PHP et JS retirés avant la recherche) ;
 *  2. le fichier livré EST celui du PO (empreinte SHA-256) ;
 *  3. le logo n'est jamais déformé ni rogné — `object-contain` dans les cadres
 *     carrés de la vue, hauteur automatique dans l'en-tête dompdf, et l'image
 *     entre réellement dans un état PDF généré, à ses dimensions natives.
 */
final class LogoEtablissementTest extends TestCase
{
    use RefreshDatabase;

    /** Empreinte du fichier du PO (`C:\Projects\tatacora_flutter\logo.png`, 14/10/2026). */
    private const SHA256_LOGO_PO = '706c80a0fe2dda4de046b2bb2a22fe35d01d5816a4e22218b097f7ccf7adceb7';

    private const ANCIEN_LOGO = '/logo\.jpe?g/i';

    /** Plancher mesuré le 14/10/2026 : plus de 300 fichiers relus. */
    private const PLANCHER_FICHIERS = 200;

    /**
     * Images du logo dans les vues, mesuré le 14/10/2026 : barre supérieure,
     * connexion ×2, démarrage, hors connexion, 404, aide, Paramètres ×2 (9).
     * Refonte du 29/10/2026 puis décision du PO du même jour (deux panneaux) :
     * la connexion rend de nouveau DEUX images — le logo du panneau gauche (dès
     * `lg`) et celui du haut de la carte (sous `lg`) : 9.
     */
    private const PLANCHER_IMAGES_LOGO = 9;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // Rien de téléversé : c'est l'actif LIVRÉ qui est éprouvé.
        Storage::fake(ApparenceEtablissementService::DISQUE);
    }

    #[Test]
    public function aucune_surface_affichee_ne_reference_plus_l_ancien_logo(): void
    {
        $fautifs = [];
        $relus = 0;

        foreach ($this->fichiers(resource_path('views'), '.blade.php') as $fichier) {
            $relus++;
            if (preg_match(self::ANCIEN_LOGO, $this->sansCommentairesBlade((string) file_get_contents($fichier))) === 1) {
                $fautifs[] = $fichier;
            }
        }

        foreach ($this->fichiers(app_path(), '.php') as $fichier) {
            $relus++;
            if (preg_match(self::ANCIEN_LOGO, $this->sansCommentairesPhp((string) file_get_contents($fichier))) === 1) {
                $fautifs[] = $fichier;
            }
        }

        foreach ([public_path('sw.js'), public_path('manifest.json')] as $fichier) {
            $relus++;
            $source = (string) preg_replace(['#/\*.*?\*/#s', '#//[^\n]*#'], '', (string) file_get_contents($fichier));
            // `//` des URL absolues n'existe pas dans ces deux fichiers (chemins
            // relatifs) : retirer les commentaires de ligne ne masque rien.
            if (preg_match(self::ANCIEN_LOGO, $source) === 1) {
                $fautifs[] = $fichier;
            }
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_FICHIERS, $relus, 'Balayage vide : le dossier a-t-il été renommé ?');
        $this->assertSame([], $fautifs, "Ces fichiers affichent encore l'ancien logo :\n  ".implode("\n  ", $fautifs));
    }

    #[Test]
    public function l_actif_livre_est_le_png_paysage_du_product_owner(): void
    {
        $chemin = public_path(ApparenceEtablissementService::ACTIF_LIVRE);

        $this->assertSame('assets/img/logo.png', ApparenceEtablissementService::ACTIF_LIVRE);
        $this->assertFileExists($chemin);
        $this->assertSame("\x89PNG\r\n\x1a\n", substr((string) file_get_contents($chemin), 0, 8), 'Le logo livré n\'est pas un PNG.');
        $this->assertSame(self::SHA256_LOGO_PO, hash_file('sha256', $chemin), 'Le logo livré n\'est pas le fichier du PO.');

        $dimensions = getimagesize($chemin);
        $this->assertIsArray($dimensions);
        $this->assertSame([735, 403], [$dimensions[0], $dimensions[1]]);
    }

    #[Test]
    public function le_repli_de_la_barre_du_favicon_et_de_la_route_d_apparence_est_le_png(): void
    {
        $apparence = app(ApparenceEtablissementService::class);

        $this->assertSame(asset('assets/img/logo.png'), $apparence->urlLogo());
        $this->assertSame(asset('assets/img/logo.png'), $apparence->urlFavicon());

        $this->get(route('pwa.apparence', ['type' => 'logo']))->assertRedirect(asset('assets/img/logo.png'));
        $this->get(route('pwa.apparence', ['type' => 'favicon']))->assertRedirect(asset('assets/img/logo.png'));
    }

    #[Test]
    public function les_pages_servies_rendent_le_png_et_jamais_le_jpeg(): void
    {
        foreach (['/pwa/demarrage', '/pwa/connexion', '/pwa/hors-connexion'] as $page) {
            $html = (string) $this->get($page)->assertOk()->getContent();

            $this->assertStringContainsString('assets/img/logo.png', $html, "{$page} ne rend pas le nouveau logo.");
            $this->assertDoesNotMatchRegularExpression(self::ANCIEN_LOGO, $html, "{$page} rend encore l'ancien logo.");
        }
    }

    /**
     * Le logo est PAYSAGE ; les cadres de la vue sont CARRÉS. `object-cover`
     * le rognait au centre (« taco »), une taille forcée l'étirerait : chaque
     * image du logo garde le cadre et passe en `object-contain`.
     */
    #[Test]
    public function chaque_image_du_logo_est_contenue_dans_son_cadre_jamais_rognee(): void
    {
        $images = [];

        foreach ($this->fichiers(resource_path('views'), '.blade.php') as $fichier) {
            $source = $this->sansCommentairesBlade((string) file_get_contents($fichier));
            // Attributs entre guillemets lus d'un bloc : la barre supérieure
            // écrit `->urlLogo()` dans son `src`, et un `[^>]*` naïf coupait
            // la balise sur le `>` de la flèche (constaté le 14/10/2026).
            preg_match_all('/<img\b(?:[^>"]|"[^"]*")*>/s', $source, $balises);

            foreach ($balises[0] as $balise) {
                if (preg_match('/src="[^"]*(logo\.png|urlLogo|urlFavicon)[^"]*"/', $balise) !== 1) {
                    continue;
                }
                $images[] = basename($fichier);
                $this->assertStringContainsString('object-contain', $balise, basename($fichier).' : logo sans object-contain.');
                $this->assertStringNotContainsString('object-cover', $balise, basename($fichier).' : logo rogné par object-cover.');
            }
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_IMAGES_LOGO, count($images), 'Moins d\'images du logo que mesuré : '.implode(', ', $images));
    }

    /**
     * PA-210 tranchée par le PO le 14/10/2026, option (c) : le cadre de la
     * BARRE SUPÉRIEURE est paysage au ratio du logo (735/403 × 40 px ≈ 73 px),
     * hauteur 40 px gardée pour ne pas faire grandir la barre.
     */
    #[Test]
    public function le_cadre_du_logo_de_la_barre_est_paysage_au_ratio_du_logo(): void
    {
        $source = $this->sansCommentairesBlade((string) file_get_contents(resource_path('views/pwa/partials/barre-superieure.blade.php')));
        preg_match_all('/<img\b(?:[^>"]|"[^"]*")*>/s', $source, $balises);
        $logo = array_values(array_filter($balises[0], static fn (string $b): bool => str_contains($b, 'urlLogo')));

        $this->assertCount(1, $logo, 'Image du logo introuvable dans la barre supérieure.');
        $this->assertStringContainsString('w-[73px] h-10', $logo[0]);
        $this->assertStringNotContainsString('w-10 h-10', $logo[0], 'Le cadre carré de la barre est revenu.');
        $this->assertSame(73, (int) round(735 / 403 * 40));
    }

    /**
     * dompdf n'applique pas `object-fit` : une largeur ET une hauteur fixes
     * étirent le paysage en carré. La hauteur est automatique.
     */
    #[Test]
    public function l_en_tete_des_etats_ne_deforme_pas_le_logo(): void
    {
        $styles = (string) file_get_contents(resource_path('views/pdf/partials/entete-rapport-styles.blade.php'));

        $this->assertMatchesRegularExpression('/\.er-logo\s*\{\s*width:\s*48px;\s*height:\s*auto;\s*\}/', $styles);
    }

    #[Test]
    public function un_etat_pdf_genere_porte_reellement_le_logo_png(): void
    {
        $entete = app(ReportHeaderService::class)->genererEnTete('Essai du logo', 'Octobre 2026', null);

        $this->assertSame(public_path('assets/img/logo.png'), $entete->logo);

        $pdf = (new RenduPdf())->rendre($entete, new EtatResultat(
            kpis: [],
            entetes: ['Libellé'],
            lignes: [['Ligne d\'essai']],
        ));

        $this->assertStringStartsWith('%PDF', $pdf);
        // Le dictionnaire d'une image est écrit en clair par dompdf (seul le
        // flux est compressé) : le logo y figure à ses dimensions NATIVES.
        $this->assertMatchesRegularExpression('#/Subtype\s*/Image#', $pdf, 'Aucune image dans l\'état généré.');
        $this->assertMatchesRegularExpression('#/Width\s+735\b#', $pdf, 'Le logo du PO n\'est pas dans l\'état.');
        $this->assertMatchesRegularExpression('#/Height\s+403\b#', $pdf);
    }

    #[Test]
    public function les_icones_du_manifeste_sont_tirees_du_nouveau_logo(): void
    {
        $manifeste = json_decode((string) file_get_contents(public_path('manifest.json')), true, flags: JSON_THROW_ON_ERROR);
        $this->assertIsArray($manifeste);

        $icones = $manifeste['icons'] ?? [];
        $this->assertIsArray($icones);
        $this->assertCount(2, $icones);

        foreach ($icones as $icone) {
            $this->assertIsArray($icone);
            $this->assertMatchesRegularExpression('#^/icones/icone-logo-(192|512)\.png$#', (string) $icone['src']);
            $chemin = public_path(ltrim((string) $icone['src'], '/'));
            $this->assertFileExists($chemin);

            $dimensions = getimagesize($chemin);
            $this->assertIsArray($dimensions);
            $this->assertSame((string) $icone['sizes'], $dimensions[0].'x'.$dimensions[1]);
            $this->assertSame(IMAGETYPE_PNG, $dimensions[2]);
        }
    }

    /**
     * @return list<string>
     */
    private function fichiers(string $racine, string $suffixe): array
    {
        $trouves = [];
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS));

        foreach ($iterateur as $fichier) {
            if ($fichier instanceof \SplFileInfo && str_ends_with($fichier->getFilename(), $suffixe)) {
                $trouves[] = $fichier->getPathname();
            }
        }
        sort($trouves);

        return $trouves;
    }

    private function sansCommentairesBlade(string $source): string
    {
        return (string) preg_replace('/\{\{--.*?--\}\}/s', '', $source);
    }

    private function sansCommentairesPhp(string $source): string
    {
        $code = '';
        foreach (token_get_all($source) as $jeton) {
            if (is_array($jeton)) {
                if ($jeton[0] === T_COMMENT || $jeton[0] === T_DOC_COMMENT) {
                    continue;
                }
                $code .= $jeton[1];
            } else {
                $code .= $jeton;
            }
        }

        return $code;
    }
}
