<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Une chaîne de langue qui porte du HTML doit être RENDUE comme du HTML —
 * 03/09/2026, né d'un défaut constaté par le Product Owner : la modale
 * « Annuler cette réservation » affichait littéralement
 * « La réservation est <strong>conservée</strong> », balises comprises,
 * parce que la clé était rendue par `{{ }}` (échappement Blade) alors que
 * ses vingt-cinq sœurs passent par `{!! !!}`.
 *
 * ⚠ Aucun test fonctionnel ne pouvait le voir : `assertSee()` cherche le
 * texte, et le texte EST présent — c'est sa mise en forme qui est cassée.
 * Seul un balayage croisé langue × vues le révèle.
 *
 * La règle tient dans les deux sens :
 *  - une clé AVEC HTML rendue par `{{ }}` affiche ses balises ;
 *  - une clé rendue par `{!! !!}` ne doit contenir que du HTML écrit par
 *    nous, jamais une donnée d'utilisateur — c'est pourquoi la liste des
 *    clés à HTML est petite, fermée et relue.
 */
final class HtmlDesLibellesTest extends TestCase
{
    /** Les balises admises dans un fichier de langue. */
    private const BALISES = 'strong|em|b|br|span|a';

    #[Test]
    public function aucune_chaine_de_langue_avec_du_html_n_est_rendue_echappee(): void
    {
        $avecHtml = $this->clesAvecHtml();

        // Plancher : un remaniement des fichiers de langue qui viderait ce
        // relevé rendrait la boucle vide, donc verte.
        $this->assertGreaterThanOrEqual(20, count($avecHtml), 'Le relevé des clés à HTML est vide ou cassé.');

        $fautives = [];
        $rendues = 0;

        foreach ($this->vues() as $chemin => $source) {
            foreach (array_keys($avecHtml) as $cle) {
                $offset = 0;

                while (($p = strpos($source, "'".$cle."'", $offset)) !== false) {
                    $offset = $p + 1;
                    $debut = strrpos(substr($source, 0, $p), "\n");
                    $ligne = substr($source, $debut === false ? 0 : $debut, $p - ($debut === false ? 0 : $debut) + 200);

                    if (str_contains($ligne, '{!!')) {
                        $rendues++;

                        continue;
                    }

                    if (str_contains($ligne, '{{')) {
                        $fautives[] = basename($chemin).' :: '.$cle;
                    }
                }
            }
        }

        $this->assertSame(
            [],
            array_values(array_unique($fautives)),
            'Ces clés portent du HTML et sont rendues par `{{ }}` : leurs balises '
                .'s\'affichent littéralement à l\'écran. Rendre par `{!! !!}` (la chaîne '
                .'ne doit alors porter aucune donnée utilisateur), ou retirer le HTML.',
        );

        $this->assertGreaterThanOrEqual(15, $rendues, 'Trop peu de rendus confrontés : le balayage est cassé.');
    }

    /**
     * Les clés de `lang/fr` dont la valeur porte une balise HTML.
     *
     * @return array<string, string>
     */
    private function clesAvecHtml(): array
    {
        $cles = [];

        foreach ((array) glob(lang_path('fr').DIRECTORY_SEPARATOR.'*.php') as $fichier) {
            $domaine = basename((string) $fichier, '.php');

            foreach ($this->aplatir((array) require $fichier) as $cle => $valeur) {
                if (preg_match('#</?('.self::BALISES.')\b#i', $valeur) === 1) {
                    $cles[$domaine.'.'.$cle] = $valeur;
                }
            }
        }

        return $cles;
    }

    /**
     * @param  array<array-key, mixed>  $tableau
     * @return array<string, string>
     */
    private function aplatir(array $tableau, string $prefixe = ''): array
    {
        $plat = [];

        foreach ($tableau as $cle => $valeur) {
            $chemin = $prefixe === '' ? (string) $cle : $prefixe.'.'.$cle;

            if (is_array($valeur)) {
                $plat += $this->aplatir($valeur, $chemin);
            } elseif (is_string($valeur)) {
                $plat[$chemin] = $valeur;
            }
        }

        return $plat;
    }

    /** @return array<string, string> chemin => source */
    private function vues(): array
    {
        $vues = [];
        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator(resource_path('views'), \FilesystemIterator::SKIP_DOTS),
        );

        /** @var \SplFileInfo $fichier */
        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && str_ends_with($fichier->getFilename(), '.blade.php')) {
                $chemin = (string) $fichier->getRealPath();
                $vues[$chemin] = (string) file_get_contents($chemin);
            }
        }

        return $vues;
    }
}
