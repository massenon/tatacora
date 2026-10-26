<?php

declare(strict_types=1);

namespace Tests\Feature\Internationalisation;

use FilesystemIterator;
use PhpToken;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;

/**
 * Aucune note de conception ne s'affiche à l'écran (décision du Product Owner).
 *
 * Les pages web ne portent que du texte métier utile à l'utilisateur final :
 * libellés, aides de saisie, messages d'erreur métier, messages de succès,
 * états vides légitimes. Les phrases d'équipe — « Sur ce poste : … »,
 * mentions d'écart avec la maquette, codes internes (PA-xx, RG-xx, EF-Mx-xx,
 * D2xx), « ce que cet écran ne fait pas », noms de fichiers, de classes, de
 * tables ou de colonnes, notes d'avancement — n'ont pas leur place à l'écran.
 *
 * ## Ce que la garde parcourt
 *
 *  - toutes les chaînes de `lang/fr/*.php` (valeurs rendues, pas les clés ni
 *    les commentaires) ;
 *  - les gabarits Blade `resources/views/**`, une fois retirés les commentaires
 *    (commentaires Blade, HTML, PHP et JavaScript, scripts et feuilles de style) ;
 *  - les littéraux de chaîne de `app/Pwa/**` (hors le registre documentaire
 *    `Support/DerogationsMaquette.php`, qui n'est jamais rendu).
 *
 * Les commentaires de code documentent : ils ne sont PAS à l'écran et restent
 * libres de citer les codes internes.
 *
 * ## Preuve que la garde mord
 *
 * `la_garde_detecte_une_note_de_conception_injectee` applique les MÊMES
 * fonctions d'analyse à des échantillons mutés : une note dans une valeur de
 * langue, dans un gabarit, dans un littéral PHP, doit être signalée ; la même
 * note dans un commentaire ne doit pas l'être. Un plancher de fichiers non
 * vide empêche la garde de passer au vert en ne parcourant rien.
 */
final class AucuneNoteDeConceptionALEcranTest extends TestCase
{
    /**
     * Motifs interdits à l'écran (insensibles à la casse sauf mention).
     *
     * @var array<string, string>
     */
    private const MOTIFS = [
        'code PA-xx' => '/\bPA-\d+/u',
        'code RG-xx' => '/\bRG-\d+/u',
        'code EF-Mx-xx' => '/\bEF-M\d+/u',
        'ticket Dxxx' => '/\bD\d{3}\b/u',
        'document interne' => '/\bPLAN_ACTION\w*|\bLARAVEL_PWA\b|\bDIRECTIVE_\w+/u',
        'Sur ce poste' => '/sur ce poste/iu',
        'le maître' => '/\bmaître\b/iu',
        'prototype' => '/\bprototype\b/iu',
        'maquette' => '/\bmaquette\b/iu',
        'schéma' => '/\bsch[ée]ma\b/iu',
        'non porté' => '/non porté/iu',
        'non calculé' => '/non calculé/iu',
        'donnée sans source' => '/donnée sans source/iu',
        'jeu d\'essai' => '/jeu d.essai/iu',
        'refus déclaré' => '/refus déclaré/iu',
        'ce que cet écran ne fait pas' => '/ce que cet écran ne fait pas/iu',
        'ce dépôt' => '/ce dépôt|du dépôt/iu',
        'Article 7 / 8' => '/\bArticle [78]\b/u',
        'Directive' => '/\bDirective\b/u',
        'côté serveur' => '/côté serveur/iu',
        'fichier .env' => '/\.env\b/u',
        'identifiant technique entre accents graves' => '/`[^`]+`/u',
        'nom de fichier PHP' => '/\w+\.php\b/u',
        'Flutter' => '/\bFlutter\b/u',
        'gabarit' => '/écart de gabarit/iu',
        'arbitrage de conception' => '/non arbitré|à arbitrer|arbitrage en attente/iu',
        'dérogation' => '/\bDérogation/iu',
        'chapitre du cahier des charges' => '/chap\. ?\d+(\.\d+)*/u',
    ];

    /** Fichiers jamais rendus : registre documentaire de conformité. */
    private const FICHIERS_PWA_EXCLUS = ['app/Pwa/Support/DerogationsMaquette.php'];

    private static function racine(): string
    {
        return dirname(__DIR__, 3);
    }

    /**
     * @return list<string> motifs enfreints par le texte
     */
    private static function motifsEnfreints(string $texte): array
    {
        $enfreints = [];
        foreach (self::MOTIFS as $nom => $motif) {
            if (preg_match($motif, $texte) === 1) {
                $enfreints[] = $nom;
            }
        }

        return $enfreints;
    }

    /**
     * @return iterable<string, string> clé pointée => valeur
     */
    private static function aplatir(array $tableau, string $prefixe = ''): iterable
    {
        foreach ($tableau as $cle => $valeur) {
            if (is_array($valeur)) {
                yield from self::aplatir($valeur, $prefixe . $cle . '.');
            } else {
                yield $prefixe . $cle => (string) $valeur;
            }
        }
    }

    /** Retire d'un gabarit Blade tout ce qui n'est pas rendu à l'écran. */
    private static function blade_rendu(string $source): string
    {
        $source = preg_replace('/\{\{--.*?--\}\}/s', '', $source) ?? $source;
        $source = preg_replace('/<!--.*?-->/s', '', $source) ?? $source;
        $source = preg_replace_callback('/@php\b.*?@endphp/s', static function (array $m): string {
            $code = '';
            foreach (PhpToken::tokenize('<?php ' . substr($m[0], 4, -7)) as $jeton) {
                if (! in_array($jeton->id, [T_COMMENT, T_DOC_COMMENT], true)) {
                    $code .= $jeton->text;
                }
            }

            return $code;
        }, $source) ?? $source;
        $source = preg_replace('#<script\b[^>]*>.*?</script>#s', '', $source) ?? $source;
        $source = preg_replace('#<style\b[^>]*>.*?</style>#s', '', $source) ?? $source;
        $source = preg_replace('#^\s*//.*$#m', '', $source) ?? $source;
        $source = preg_replace('#/\*.*?\*/#s', '', $source) ?? $source;

        return $source;
    }

    /** Littéraux de chaîne d'un fichier PHP (commentaires exclus par le tokenizer). */
    private static function litteraux_php(string $source): array
    {
        $litteraux = [];
        foreach (PhpToken::tokenize($source) as $jeton) {
            if (in_array($jeton->id, [T_CONSTANT_ENCAPSED_STRING, T_ENCAPSED_AND_WHITESPACE], true)) {
                $litteraux[] = $jeton->text;
            }
        }

        return $litteraux;
    }

    /**
     * @return list<string> chemins relatifs
     */
    private static function fichiers(string $dossier, string $suffixe): array
    {
        $racine = self::racine();
        $trouves = [];
        $iterateur = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($racine . '/' . $dossier, FilesystemIterator::SKIP_DOTS),
        );
        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && str_ends_with($fichier->getPathname(), $suffixe)) {
                $trouves[] = ltrim(substr($fichier->getPathname(), strlen($racine)), '/');
            }
        }
        sort($trouves);

        return $trouves;
    }

    #[Test]
    public function le_plancher_de_fichiers_parcourus_n_est_pas_vide(): void
    {
        self::assertGreaterThanOrEqual(30, count(self::fichiers('lang/fr', '.php')), 'Fichiers de langue');
        self::assertGreaterThanOrEqual(80, count(self::fichiers('resources/views', '.blade.php')), 'Gabarits Blade');
        self::assertGreaterThanOrEqual(30, count(self::fichiers('app/Pwa', '.php')), 'Classes de l\'interface web');
    }

    #[Test]
    public function les_fichiers_de_langue_ne_portent_aucune_note_de_conception(): void
    {
        $trouvailles = [];
        foreach (self::fichiers('lang/fr', '.php') as $fichier) {
            $tableau = require self::racine() . '/' . $fichier;
            foreach (self::aplatir($tableau) as $cle => $valeur) {
                foreach (self::motifsEnfreints($valeur) as $motif) {
                    $trouvailles[] = "$fichier [$cle] ($motif) : " . mb_substr($valeur, 0, 110);
                }
            }
        }

        self::assertSame([], $trouvailles, "Notes de conception à l'écran (lang/fr) :\n" . implode("\n", $trouvailles));
    }

    #[Test]
    public function les_gabarits_rendus_ne_portent_aucune_note_de_conception(): void
    {
        $trouvailles = [];
        foreach (self::fichiers('resources/views', '.blade.php') as $fichier) {
            $rendu = self::blade_rendu((string) file_get_contents(self::racine() . '/' . $fichier));
            foreach (explode("\n", $rendu) as $ligne) {
                foreach (self::motifsEnfreints($ligne) as $motif) {
                    $trouvailles[] = "$fichier ($motif) : " . mb_substr(trim($ligne), 0, 110);
                }
            }
        }

        self::assertSame([], $trouvailles, "Notes de conception à l'écran (Blade) :\n" . implode("\n", $trouvailles));
    }

    #[Test]
    public function les_chaines_passees_aux_vues_ne_portent_aucune_note_de_conception(): void
    {
        $trouvailles = [];
        foreach (self::fichiers('app/Pwa', '.php') as $fichier) {
            if (in_array($fichier, self::FICHIERS_PWA_EXCLUS, true)) {
                continue;
            }
            foreach (self::litteraux_php((string) file_get_contents(self::racine() . '/' . $fichier)) as $litteral) {
                foreach (self::motifsEnfreints($litteral) as $motif) {
                    $trouvailles[] = "$fichier ($motif) : " . mb_substr(trim($litteral), 0, 110);
                }
            }
        }

        self::assertSame([], $trouvailles, "Notes de conception à l'écran (app/Pwa) :\n" . implode("\n", $trouvailles));
    }

    #[Test]
    public function la_garde_detecte_une_note_de_conception_injectee(): void
    {
        // Mutation 1 : une valeur de langue.
        self::assertNotSame([], self::motifsEnfreints('Sur ce poste : le panier reste ouvert.'));
        self::assertNotSame([], self::motifsEnfreints('Fiche technique absente (EF-M4-02).'));
        self::assertNotSame([], self::motifsEnfreints('Le maître propose ici un texte libre (PA-23).'));
        self::assertNotSame([], self::motifsEnfreints('Colonne `plats.menu_id` obligatoire.'));
        self::assertNotSame([], self::motifsEnfreints('Ce que cet écran ne fait pas, et pourquoi'));
        self::assertNotSame([], self::motifsEnfreints('Aucune colonne du schéma ne porte cette information.'));

        // Mutation 2 : un gabarit — la note rendue est signalée, la même en commentaire non.
        $note = "<p class=\"text-xs\">Non porté par le schéma (RG-02).</p>";
        self::assertNotSame([], self::motifsEnfreints(self::blade_rendu($note)));
        self::assertSame([], self::motifsEnfreints(self::blade_rendu("{{-- Non porté par le schéma (RG-02). --}}")));
        self::assertSame([], self::motifsEnfreints(self::blade_rendu("<!-- PA-12 -->\n// maître l.12\n/* D385 */")));
        self::assertNotSame([], self::motifsEnfreints(self::blade_rendu("@php \$a = 'Sur ce poste : note'; @endphp")));

        // Mutation 3 : un littéral PHP — le commentaire n'est pas un littéral.
        $source = "<?php\n// PA-12 maître\n\$m = 'Voir PA-12 dans le dépôt';\n";
        $litteraux = self::litteraux_php($source);
        self::assertCount(1, $litteraux);
        self::assertNotSame([], self::motifsEnfreints($litteraux[0]));

        // Texte métier légitime : jamais signalé.
        self::assertSame([], self::motifsEnfreints('Réservation enregistrée. Le client sera prévenu par e-mail.'));
        self::assertSame([], self::motifsEnfreints('Caisse clôturée — écart de 1 500 FCFA.'));
    }
}
