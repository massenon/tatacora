<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Architecture;

use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Finder\Finder;
use Tests\TestCase;

/**
 * Les clés du socle sont RÉSERVÉES — aucun composant ne les redéclare.
 *
 * ## Le 500 que cette garde épingle (31/08/2026)
 *
 * `PageMetier::socle()` fournit à la coquille `utilisateur`, `menu`,
 * `banniere` et `caisse`. Le composant Dépenses passait de son côté
 * `'caisse' => <montant décaissé>` à sa vue : la CHAÎNE masquait le TABLEAU
 * du socle, et `barre-superieure.blade.php` levait « Cannot access offset of
 * type string on string » — `/pwa/depenses` en 500.
 *
 * Le défaut est de la même famille que le `<title>` : deux moitiés justes
 * chacune de son côté, et le raccord qui casse. Il est invisible tant que la
 * coquille ne lit pas la clé sur CETTE page — puis un widget de coquille
 * s'ajoute (l'indicateur de caisse), et l'écran tombe.
 *
 * ## Ce qu'elle balaye
 *
 * Toute clé littérale `'<réservée>' =>` dans un fichier de composant, HORS
 * du corps de `socle()` lui-même. Les constantes de registre (un libellé
 * `'caisse' => 'Caisse'` dans TRESORERIES) sont des faux positifs connus :
 * la garde ne regarde que les tableaux passés à `view(...)` — repérés par la
 * présence de `array_merge($this->socle()` dans la même méthode, le motif
 * unique du dépôt pour rendre une page.
 */
final class ClesDuSocleReserveesTest extends TestCase
{
    /** Ce que `PageMetier::socle()` fournit — relu contre la source. */
    private const CLES_RESERVEES = ['utilisateur', 'menu', 'banniere', 'caisse'];

    private const PLANCHER_COMPOSANTS = 30;

    #[Test]
    public function aucun_composant_ne_masque_une_cle_du_socle(): void
    {
        // La liste ci-dessus doit être celle du socle RÉEL : si `socle()`
        // gagne une clé demain, cette garde doit l'apprendre — sinon elle
        // protège la liste d'hier.
        $socle = (string) file_get_contents(app_path('Pwa/Livewire/PageMetier.php'));

        foreach (self::CLES_RESERVEES as $cle) {
            $this->assertStringContainsString(
                "'{$cle}' =>",
                $socle,
                "« {$cle} » n'est plus fournie par socle() : retirer la clé d'ici aussi.",
            );
        }

        $finder = (new Finder())->files()->in(app_path('Pwa/Livewire'))->name('*.php');

        $defauts = [];
        $relus = 0;

        foreach ($finder as $fichier) {
            if ($fichier->getFilename() === 'PageMetier.php') {
                continue;
            }

            $source = $fichier->getContents();
            $relus++;

            // Seuls les rendus de page sont concernés : le masquage n'existe
            // que dans le tableau fusionné au socle.
            if (! str_contains($source, 'array_merge($this->socle()')) {
                continue;
            }

            foreach (self::CLES_RESERVEES as $cle) {
                // Le motif vise une clé de tableau de vue, pas un littéral
                // quelconque : `'caisse' => $` (une valeur calculée), jamais
                // `'caisse' => 'Caisse'` (un libellé de registre).
                if (preg_match("/'{$cle}' => \\\$/", $source) === 1) {
                    $defauts[] = $fichier->getFilename()." redéclare « {$cle} »";
                }
            }
        }

        $this->assertSame(
            [],
            $defauts,
            "Des composants masquent une clé du socle — la coquille recevra leur valeur\n"
            ."à la place de la sienne, et l'écran tombera au premier widget qui la lit :\n  "
            .implode("\n  ", $defauts),
        );

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_COMPOSANTS,
            $relus,
            "Seuls {$relus} composants relus : le balayage est devenu creux.",
        );
    }
}
