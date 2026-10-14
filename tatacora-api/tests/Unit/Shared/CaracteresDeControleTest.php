<?php

declare(strict_types=1);

namespace Tests\Unit\Shared;

use FilesystemIterator;
use PHPUnit\Framework\Attributes\Test;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use SplFileInfo;
use Tests\TestCase;

/**
 * PA-105 — aucun caractere de controle invisible dans le code source.
 *
 * ## Le defaut, rencontre DEUX fois
 *
 * Un script de generation ecrivant `\b` dans une expression reguliere a
 * produit l'octet **0x08** — le retour arriere — au lieu des deux caracteres
 * `\` et `b`. Le motif devenu `/<retour arriere>mot/` ne correspond **jamais
 * a rien**.
 *
 * C'est arrive ici, dans `PwaLectureSeuleTest` : son balayage des cles de role
 * portait 0x08 et 0x01 la ou `\b` et `\1` etaient attendus, et il passait donc
 * **a vide** — le depouillement des balises `<script>` n'avait jamais lieu.
 * C'est arrive une seconde fois le 24/08/2026 dans `prototype_v2`, sur la
 * garde du bouton « Facture A4 » : le mutant qui emettait une deuxieme facture
 * passait au vert.
 *
 * La forme est celle que ce depot connait bien — **un controle qui affiche
 * « tout va bien » pendant qu'il ne verifie rien**. Ce qui la rend
 * particuliere, c'est qu'elle est **invisible a la relecture** : aucune revue
 * humaine ne distingue `\b` d'un octet 0x08 a l'ecran. Seule une machine le
 * peut, d'ou ce test.
 *
 * ## Le second symptome : NUL rend un fichier binaire pour grep
 *
 * Un octet NUL dans un fichier source le fait classer **binaire** par grep,
 * qui le saute alors **sans un mot**. Un balayage du depot passe a cote sans
 * que rien ne le signale — meme famille, autre mecanisme.
 *
 * ## Ce qui est exclu, et pourquoi
 *
 * Tout repertoire nomme `vendor` : ces fichiers sont minifies par un tiers,
 * ne sont pas relus ligne a ligne, et un caractere de controle y serait le
 * choix de leur auteur, pas une erreur de ce depot.
 *
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-105
 */
final class CaracteresDeControleTest extends TestCase
{
    /**
     * Les racines relues. Chacune contient du code ou des donnees ecrites a la
     * main dans ce depot ; `vendor/`, `node_modules/` et `storage/` en sont
     * absents parce qu'aucun n'est ecrit ici.
     */
    private const RACINES = ['app', 'tests', 'routes', 'config', 'database', 'lang', 'resources', 'public'];

    private const EXTENSIONS = ['php', 'js', 'css', 'json', 'md', 'yml', 'yaml', 'blade', 'env', 'xml'];

    /**
     * Seuls trois caracteres de controle sont legitimes dans un fichier
     * source : le saut de ligne, le retour chariot et la tabulation.
     */
    private const AUTORISES = [0x0A, 0x0D, 0x09];

    private const NOMS = [
        0x00 => 'NUL — rend le fichier BINAIRE pour grep, qui le saute sans un mot',
        0x01 => 'SOH — un \1 de groupe de capture qui a perdu son antislash',
        0x07 => 'BEL',
        0x08 => 'RETOUR ARRIERE — un \b de motif qui a perdu son antislash',
        0x0B => 'TABULATION VERTICALE',
        0x0C => 'SAUT DE PAGE',
        0x1A => 'SUBSTITUTE — fin de fichier DOS',
        0x1B => 'ECHAPPEMENT',
    ];

    /**
     * Plancher de fichiers relus.
     *
     * **Sans lui, ce test se trompe exactement comme ceux qu'il protege.** Une
     * racine renommee, un `base_path()` qui ne resout plus, et l'iterateur ne
     * rend aucun fichier : zero fichier lu, zero anomalie trouvee, test VERT.
     * Le depot comptait 279 fichiers relus le 24/08/2026 ; la borne est posee
     * bas pour ne pas rougir a chaque suppression, mais assez haut pour qu'un
     * balayage vide ou reduit a une seule racine ne passe pas.
     */
    private const PLANCHER_FICHIERS = 200;

    #[Test]
    public function aucun_fichier_source_ne_porte_de_caractere_de_controle_invisible(): void
    {
        $anomalies = [];
        $nbFichiers = 0;

        foreach ($this->fichiers() as $chemin) {
            $nbFichiers++;
            $contenu = file_get_contents($chemin);

            if ($contenu === false || $contenu === '') {
                continue;
            }

            $ligne = 1;
            $longueur = strlen($contenu);

            for ($i = 0; $i < $longueur; $i++) {
                $octet = ord($contenu[$i]);

                if ($octet === 0x0A) {
                    $ligne++;

                    continue;
                }

                if ($octet >= 0x20 || in_array($octet, self::AUTORISES, true)) {
                    continue;
                }

                $anomalies[] = sprintf(
                    '%s:%d — U+%04X %s',
                    $this->relatif($chemin),
                    $ligne,
                    $octet,
                    self::NOMS[$octet] ?? 'caractere de controle',
                );
            }
        }

        // La garde de la garde : un balayage vide ne doit JAMAIS passer pour
        // un balayage propre.
        $this->assertGreaterThanOrEqual(
            self::PLANCHER_FICHIERS,
            $nbFichiers,
            "Seuls {$nbFichiers} fichiers ont ete relus, sous le plancher de "
            .self::PLANCHER_FICHIERS.". Le balayage ne couvre plus le depot : "
            .'une racine a ete renommee ou deplacee, et ce test passerait a vide.',
        );

        $this->assertSame(
            [],
            $anomalies,
            "Caractere(s) de controle invisible(s) dans le code source.\n"
            ."Un \b ou un \1 a perdu son antislash a l'ecriture : le motif qui "
            ."le porte ne correspond plus a rien, et la garde qu'il sert passe a "
            ."vide sans rougir.\n\n"
            .implode("\n", array_slice($anomalies, 0, 20))
            .(count($anomalies) > 20 ? sprintf("\n… et %d autre(s)", count($anomalies) - 20) : ''),
        );
    }

    /**
     * @return list<string>
     */
    private function fichiers(): array
    {
        $trouves = [];

        foreach (self::RACINES as $racine) {
            $chemin = base_path($racine);

            if (! is_dir($chemin)) {
                continue;
            }

            $iterateur = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($chemin, FilesystemIterator::SKIP_DOTS),
            );

            /** @var SplFileInfo $fichier */
            foreach ($iterateur as $fichier) {
                if (! $fichier->isFile()) {
                    continue;
                }

                // `vendor` a n'importe quelle profondeur — voir l'en-tete.
                $normalise = str_replace('\\', '/', $fichier->getPathname());
                if (str_contains($normalise, '/vendor/') || str_contains($normalise, '/node_modules/')) {
                    continue;
                }

                if (! in_array(strtolower($fichier->getExtension()), self::EXTENSIONS, true)) {
                    continue;
                }

                $trouves[] = $fichier->getPathname();
            }
        }

        return $trouves;
    }

    private function relatif(string $chemin): string
    {
        $base = str_replace('\\', '/', base_path()).'/';

        return str_replace($base, '', str_replace('\\', '/', $chemin));
    }
}
