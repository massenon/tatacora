<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use Illuminate\Support\Facades\Blade;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * TOUTES les vues de la PWA compilent en PHP valide.
 *
 * ## Pourquoi ce controle existe — un defaut rencontre, pas imagine
 *
 * Le 27/08/2026, deux vues de ce lot compilaient en
 * « syntax error, unexpected token "endforeach" ». La cause n'est visible dans
 * AUCUNE relecture : Blade extrait les blocs PHP bruts AVANT tout le reste, et
 * il apparie la PREMIERE ouverture rencontree a la PREMIERE fermeture. Une
 * forme BLOC placee apres une forme EN LIGNE referme donc cette derniere, et
 * tout ce qui les separe — quarante lignes de gabarit, boucles comprises —
 * devient du PHP brut.
 *
 * Deux consequences que ce cas verrouille :
 *
 *  1. La vue est parfaitement lisible et parfaitement fausse. Aucun
 *     `php -l`, aucun `pint`, aucun `phpstan` ne regarde un fichier Blade :
 *     ils n'analysent que du PHP, et une vue n'en est pas un tant qu'elle
 *     n'est pas compilee.
 *  2. Le defaut n'apparait qu'a l'EXECUTION de la page concernee. Un test qui
 *     n'ouvrirait pas cette page precise resterait vert — c'est la forme
 *     exacte du precedent de `CLAUDE.md` : « une page HTML livree vide que
 *     seule une execution reelle a revelee ».
 *
 * Le meme piege guette un commentaire Blade : les mots-cles y sont vus par
 * l'extraction des blocs bruts, qui passe AVANT le retrait des commentaires.
 * C'est ce qui a produit le second echec de la meme journee.
 *
 * ## Ce cas balaie, il ne recite pas une liste
 *
 * Une liste de vues ecrite a la main aurait vieilli au premier fichier ajoute
 * — et un balayage qui ne couvre pas la vue ajoutee est vert a vide, le defaut
 * meme que PA-152 a trouve dans la garde de lecture seule. Le balayage est
 * donc recursif, et il porte un PLANCHER : sans lui, un dossier renomme
 * rendrait la liste vide, donc verte.
 *
 * @see DIRECTIVE_CONFORMITE_100.md Article 9 (la conformite se prouve)
 */
final class VuesPwaCompilentTest extends TestCase
{
    /**
     * Plancher de vues relues. Il ne doit que monter.
     *
     * Au 27/08/2026 : les 12 vues M10 et leurs 11 partials, les 7 transverses
     * et leur partial, les 4 metier, la coquille et ses partials, la connexion,
     * le demarrage et la page de repli.
     */
    private const PLANCHER = 40;

    #[Test]
    public function toutes_les_vues_de_la_pwa_compilent_en_php_valide(): void
    {
        $vues = $this->vuesPwa();

        $this->assertGreaterThanOrEqual(
            self::PLANCHER,
            count($vues),
            'Moins de vues PWA que prevu : le balayage a perdu un dossier, et un balayage vide est vert.',
        );

        $fichierTemporaire = tempnam(sys_get_temp_dir(), 'blade_pwa_') . '.php';

        try {
            foreach ($vues as $vue) {
                $compilee = Blade::compileString((string) file_get_contents($vue));

                file_put_contents($fichierTemporaire, $compilee);

                $sortie = [];
                $code = 0;
                exec('php -l ' . escapeshellarg($fichierTemporaire) . ' 2>&1', $sortie, $code);

                $this->assertSame(
                    0,
                    $code,
                    "La vue {$vue} ne compile pas en PHP valide : " . implode(' ', $sortie),
                );
            }
        } finally {
            @unlink($fichierTemporaire);
        }
    }

    /**
     * Les vues de la PWA : le dossier `pwa/`, la coquille qui les enveloppe,
     * et les COMPOSANTS Blade anonymes de `components/pwa/`.
     *
     * ⚠ Les composants ont ete ajoutes au balayage le 31/08/2026, et ils n'y
     * etaient pas. C'est exactement le dossier ou ce controle est le plus
     * utile : un chassis de modale casse ne se voit sur aucune page en
     * particulier — il casse les dix-neuf qui l'incluent d'un coup, et il
     * n'appartient a l'ecran de personne.
     *
     * @return list<string>
     */
    private function vuesPwa(): array
    {
        $racines = [
            resource_path('views/pwa'),
            resource_path('views/layouts'),
            resource_path('views/components/pwa'),
        ];
        $fichiers = [];

        foreach ($racines as $racine) {
            $iterateur = new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
            );

            foreach ($iterateur as $fichier) {
                if ($fichier instanceof \SplFileInfo && str_ends_with($fichier->getPathname(), '.blade.php')) {
                    $fichiers[] = $fichier->getPathname();
                }
            }
        }

        sort($fichiers);

        return $fichiers;
    }
}
