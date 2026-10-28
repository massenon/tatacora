<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Depenses;

use App\Domain\Depenses\Exceptions\RefusRecuDepense;
use App\Domain\Depenses\Services\RecuDepenseService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le reçu d'une dépense : une image trop lourde est RÉDUITE, jamais refusée pour
 * son poids (PO, 28/10/2026) — sur l'écran web comme sur le poste.
 *
 * La RÈGLE (constantes, ordre, résultat) est celle de `reduction_recu.dart`,
 * confrontée par `depenses_recu_contre_serveur_test.dart`. Ce qui reste refusé :
 * un fichier vide, qui n'est pas une image, ou qu'on ne sait pas lire. La porte
 * de DÉPÔT par synchronisation (`controler`) garde sa borne de 400 Ko.
 */
final class RecuDepenseReductionTest extends TestCase
{
    use RefreshDatabase;

    /** Une image BRUITÉE (incompressible), donc lourde en PNG comme en JPEG. */
    private function imageLourde(int $largeur, int $hauteur, string $format = 'png'): string
    {
        $image = imagecreatetruecolor($largeur, $hauteur);
        mt_srand(42);
        for ($x = 0; $x < $largeur; $x++) {
            for ($y = 0; $y < $hauteur; $y++) {
                imagesetpixel($image, $x, $y, (mt_rand(0, 255) << 16) | (mt_rand(0, 255) << 8) | mt_rand(0, 255));
            }
        }

        ob_start();
        $format === 'jpeg' ? imagejpeg($image, null, 100) : imagepng($image, null, 0);

        return (string) ob_get_clean();
    }

    #[Test]
    public function une_image_de_plus_de_400_ko_est_reduite_en_jpeg_qui_tient_dans_la_limite(): void
    {
        $lourde = $this->imageLourde(1500, 1000);
        $this->assertGreaterThan(400 * 1024, strlen($lourde));

        $service = new RecuDepenseService();
        $prepare = $service->preparer($lourde);

        $this->assertTrue($prepare['reduit']);
        $this->assertLessThanOrEqual(400 * 1024, strlen($prepare['octets']));
        $this->assertSame('image/jpeg', $prepare['type']);
        $this->assertSame('jpg', $prepare['extension']);
        $this->assertSame(hash('sha256', $prepare['octets']), $prepare['sha256']);
        $this->assertSame(strlen($lourde), $prepare['taille_origine']);

        // Le résultat passe la porte de dépôt de la synchronisation.
        $this->assertSame('image/jpeg', $service->controler($prepare['octets'])['type']);

        // Les proportions sont gardées (1500x1000 → ratio 1,5 à un pixel près).
        [$l, $h] = getimagesizefromstring($prepare['octets']);
        $this->assertLessThanOrEqual(RecuDepenseService::COTE_MAX_PX, max($l, $h));
        $this->assertEqualsWithDelta(1.5, $l / $h, 0.01);
    }

    #[Test]
    public function une_grande_image_est_ramenee_a_2048_pixels_sur_son_grand_cote(): void
    {
        $prepare = (new RecuDepenseService())->preparer($this->imageLourde(3000, 1000, 'jpeg'));

        [$l, $h] = getimagesizefromstring($prepare['octets']);
        $this->assertLessThanOrEqual(2048, max($l, $h));
        $this->assertLessThanOrEqual(400 * 1024, strlen($prepare['octets']));
    }

    #[Test]
    public function une_image_de_400_ko_ou_moins_est_gardee_telle_quelle(): void
    {
        $service = new RecuDepenseService();
        $png = $this->imageLourde(40, 40);
        $this->assertLessThanOrEqual(400 * 1024, strlen($png));

        $prepare = $service->preparer($png);

        $this->assertFalse($prepare['reduit']);
        $this->assertSame($png, $prepare['octets']);
        $this->assertSame('image/png', $prepare['type']);
    }

    #[Test]
    public function une_image_transparente_est_posee_sur_fond_blanc(): void
    {
        $image = imagecreatetruecolor(1400, 1400);
        imagesavealpha($image, true);
        imagealphablending($image, false);
        imagefill($image, 0, 0, (int) imagecolorallocatealpha($image, 0, 0, 0, 127));
        // Du bruit opaque dans un coin pour peser lourd ; le reste reste transparent.
        mt_srand(7);
        for ($x = 0; $x < 700; $x++) {
            for ($y = 0; $y < 1400; $y++) {
                imagesetpixel($image, $x, $y, (int) imagecolorallocatealpha($image, mt_rand(0, 255), mt_rand(0, 255), mt_rand(0, 255), 0));
            }
        }
        ob_start();
        imagepng($image, null, 0);
        $png = (string) ob_get_clean();

        $prepare = (new RecuDepenseService())->preparer($png);

        $reduit = imagecreatefromstring($prepare['octets']);
        $rgb = imagecolorat($reduit, (int) (imagesx($reduit) * 0.9), (int) (imagesy($reduit) / 2));
        $this->assertGreaterThan(240, ($rgb >> 16) & 255, 'La zone transparente doit être blanche, pas noire.');
        $this->assertGreaterThan(240, $rgb & 255);
    }

    #[Test]
    public function l_orientation_exif_est_appliquee_une_photo_couchee_ressort_debout(): void
    {
        $jpeg = $this->imageLourde(1200, 800, 'jpeg');
        $this->assertGreaterThan(400 * 1024, strlen($jpeg));

        // Un segment APP1/EXIF minimal (IFD0 à une entrée : Orientation = 6),
        // inséré juste après le SOI — comme un téléphone tenu en portrait.
        $tiff = "II*\x00\x08\x00\x00\x00"          // en-tête little-endian, IFD0 à l'offset 8
            ."\x01\x00"                              // une entrée
            ."\x12\x01\x03\x00\x01\x00\x00\x00\x06\x00\x00\x00" // 0x0112 SHORT x1 = 6
            ."\x00\x00\x00\x00";                   // pas d'IFD suivant
        $exif = "Exif\x00\x00".$tiff;
        $segment = "\xFF\xE1".pack('n', strlen($exif) + 2).$exif;
        $couche = substr($jpeg, 0, 2).$segment.substr($jpeg, 2);

        $prepare = (new RecuDepenseService())->preparer($couche);

        [$l, $h] = getimagesizefromstring($prepare['octets']);
        $this->assertGreaterThan($l, $h, 'La photo doit être remise debout (portrait).');
    }

    #[Test]
    public function le_refus_reste_pour_un_fichier_vide_non_image_ou_illisible(): void
    {
        $service = new RecuDepenseService();

        $refus = static function (string $octets) use ($service): RefusRecuDepense {
            try {
                $service->preparer($octets);
            } catch (RefusRecuDepense $e) {
                return $e;
            }
            throw new \LogicException('Aucun refus.');
        };

        $this->assertSame('recu_invalide', $refus('')->codeMotif);

        // Un texte lourd n'est pas une image : la phrase du validateur, pas un refus de poids.
        $texte = $refus(str_repeat('abc ', 200_000));
        $this->assertSame('Le champ photo recu doit être une image.', $texte->getMessage());

        // Une image lourde dont le corps est corrompu : illisible.
        $png = $this->imageLourde(1200, 900);
        $illisible = $refus(substr($png, 0, 100).str_repeat("\x00", 450 * 1024));
        $this->assertSame('recu_illisible', $illisible->codeMotif);
        $this->assertSame("Ce fichier n'a pas pu être lu comme une image : choisissez-en un autre.", $illisible->getMessage());
    }

    #[Test]
    public function la_porte_de_depot_garde_sa_borne_de_400_ko(): void
    {
        $this->expectException(RefusRecuDepense::class);
        $this->expectExceptionMessage('ne peut pas peser plus de 400 kilo-octets');

        (new RecuDepenseService())->controler($this->imageLourde(1500, 1000));
    }
}
