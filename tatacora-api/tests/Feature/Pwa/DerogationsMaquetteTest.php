<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Pwa\Support\DerogationsMaquette;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le registre des dérogations à la maquette est RELU, pas seulement écrit.
 *
 * ## Pourquoi ce fichier existe
 *
 * Un registre qu'aucun code ne lit est une note de bas de page : il vieillit
 * sans que rien ne le signale, et c'est exactement le défaut que le dépôt a
 * rencontré trois fois (PA-107, PA-120, PA-144). Ce cas lui donne un lecteur.
 *
 * Ce qu'il vérifie tient en une phrase : **une dérogation sans raison ni date
 * n'est pas une décision, c'est un oubli**. Il refuse donc une entrée
 * incomplète, une date mal formée, et — le point qui compte — un jeton
 * `maitre-refuse:` annoncé par le registre mais absent du code, car un jeton
 * qui n'existe que dans sa propre description ne déclare rien à la garde qui
 * le cherche.
 *
 * ⚠ Ce qu'il NE vérifie PAS, et qui est assumé : que la dérogation soit
 * toujours JUSTIFIÉE. Aucun test ne peut lire une raison. C'est à la relecture
 * de comparer la date à l'état du jour.
 */
final class DerogationsMaquetteTest extends TestCase
{
    /**
     * Plancher : sans lui, un registre vidé passerait au vert à vide — le
     * défaut même que ce fichier protège.
     */
    private const PLANCHER = 3;

    #[Test]
    public function chaque_derogation_porte_sa_raison_son_auteur_et_sa_date(): void
    {
        $registre = DerogationsMaquette::DEROGATIONS;

        $this->assertGreaterThanOrEqual(
            self::PLANCHER,
            count($registre),
            'Le registre des dérogations a perdu des entrées : un écart accordé qui '
            . 'disparaît du registre redevient un écart inexpliqué.',
        );

        foreach ($registre as $cle => $derogation) {
            foreach (['element', 'maitre', 'pwa', 'raison', 'decideur', 'portee_du_jeton'] as $champ) {
                $this->assertArrayHasKey($champ, $derogation, "Dérogation « {$cle} » : champ « {$champ} » absent.");
                $this->assertNotSame('', trim((string) $derogation[$champ]), "Dérogation « {$cle} » : « {$champ} » est vide.");
            }

            // La DATE est le champ dont l'absence coûte le plus cher : sans
            // elle, personne ne sait si le motif est encore vrai.
            $this->assertMatchesRegularExpression(
                '#^\d{2}/\d{2}/\d{4}$#',
                (string) $derogation['date'],
                "Dérogation « {$cle} » : la date doit être écrite jj/mm/aaaa.",
            );
        }
    }

    /**
     * Un jeton annoncé par le registre existe RÉELLEMENT dans le code.
     *
     * C'est le seul point qui ne se relit pas : le registre peut affirmer
     * qu'un refus est déclaré pendant que le jeton a été effacé du fichier qui
     * le portait. La garde `t-trois-sources.js` recommencerait alors à
     * signaler l'écart, et le rapport dirait le contraire du registre.
     */
    #[Test]
    public function tout_jeton_annonce_par_le_registre_existe_dans_le_code(): void
    {
        $jetons = array_filter(array_column(DerogationsMaquette::DEROGATIONS, 'jeton'));

        $this->assertNotEmpty($jetons, 'Aucun jeton déclaré : le cas ne vérifierait plus rien.');

        $source = $this->sourcePwa();

        foreach ($jetons as $jeton) {
            $this->assertStringContainsString(
                (string) $jeton,
                $source,
                "Le registre annonce le refus « {$jeton} », qui n'est écrit nulle part sous "
                . '`app/Pwa`, `resources/views` ni `lang/fr` — les trois répertoires que '
                . '`t-trois-sources.js` relit. La déclaration ne parvient donc pas à la garde.',
            );
        }
    }

    /**
     * Le registre ne peut ÉMETTRE un jeton que par son champ `jeton` — jamais
     * en le citant dans sa prose.
     *
     * ## Le défaut, trouvé le 31/08/2026, et pourquoi il était invisible
     *
     * `DerogationsMaquette::DEROGATIONS['bandeau_kpi']['portee_du_jeton']`
     * contenait la chaîne complète `maitre-refuse:tableau-de-bord.html#page`,
     * écrite d'un seul tenant — pour EXPLIQUER qu'il ne faut surtout pas
     * l'écrire, parce qu'elle masquerait onze libellés d'un coup.
     *
     * Or `t-trois-sources.js` (l.652, 758) cherche le jeton par un simple
     * `includes()` sur le code : **il ne distingue pas une déclaration d'une
     * citation**, et son propre en-tête le documente comme le prix assumé du
     * contrat. Le jeton était donc réellement émis, et il avalait les libellés
     * de la page — l'effet exact que le paragraphe décrivait comme à éviter.
     *
     * Sans conséquence le jour de la découverte : la page M11 est portée pour
     * de vrai, tous ses libellés se retrouvent. Mais un jeton émis par accident
     * ne se manifeste jamais tant que tout va bien — il ne fait que **taire la
     * prochaine régression**, définitivement et sans bruit. C'est la forme
     * PA-59/60/61 appliquée à une garde : un contrôle qui dit « conforme »
     * parce qu'on lui a demandé de ne pas regarder.
     *
     * ## Ce que ce cas impose
     *
     * Dans le fichier du registre, toute occurrence d'un jeton doit être la
     * valeur d'un champ `jeton`. Une citation en prose ou en commentaire
     * s'épelle (« un jeton “maitre-refuse” portant sur telle page »), ce qui
     * se lit aussi bien et n'émet rien.
     *
     * Prouvé par mutation le 31/08/2026 : réécrire la chaîne d'un tenant dans
     * `portee_du_jeton` rend ce cas ROUGE en nommant le champ.
     */
    #[Test]
    public function le_registre_n_emet_aucun_jeton_hors_de_son_champ_jeton(): void
    {
        $chemin = (new \ReflectionClass(DerogationsMaquette::class))->getFileName();
        $this->assertIsString($chemin);

        $source = (string) file_get_contents($chemin);

        // Les jetons LEGITIMES : ceux que le registre declare par son champ.
        $declares = array_values(array_filter(array_column(DerogationsMaquette::DEROGATIONS, 'jeton')));

        // Toutes les occurrences ecrites dans le fichier, quelles qu'elles
        // soient — prose, commentaire, valeur.
        $trouvees = [];
        // ⚠ Delimiteur `~` et non `#` : le jeton CONTIENT un `#`, et un motif
        // delimite par `#` se terminait au milieu de la classe de caracteres
        // (« Unknown modifier '-' »). Le choix du delimiteur est ici une part
        // du contrat, pas un detail de style.
        preg_match_all('~maitre-refuse:[A-Za-z0-9._#-]+~', $source, $brut);
        foreach ($brut[0] as $occurrence) {
            $trouvees[$occurrence] = ($trouvees[$occurrence] ?? 0) + 1;
        }

        // Plancher : sans jeton declare, ce cas ne comparerait rien.
        $this->assertNotEmpty(
            $declares,
            'Aucun jeton declare par le registre : le controle ci-dessous ne mesurerait rien.',
        );

        $parasites = [];

        foreach ($trouvees as $occurrence => $nombre) {
            $attendu = count(array_keys($declares, $occurrence, true));

            if ($nombre > $attendu) {
                $parasites[] = sprintf(
                    '« %s » apparait %d fois pour %d declaration(s) par le champ `jeton`',
                    $occurrence,
                    $nombre,
                    $attendu,
                );
            }
        }

        $this->assertSame(
            [],
            $parasites,
            "Le registre EMET un jeton hors de son champ `jeton`.\n"
            ."`t-trois-sources.js` cherche le jeton par `includes()` : il ne distingue pas une\n"
            ."declaration d'une citation. Un jeton cite en prose est donc un jeton emis — il\n"
            ."avale les libelles du bloc vise et fait taire la prochaine regression, en\n"
            ."silence. Epelez-le (« un jeton “maitre-refuse” portant sur ... ») au lieu de\n"
            ."l'ecrire d'un tenant.\n  "
            .implode("\n  ", $parasites),
        );
    }

    /**
     * Les trois répertoires que `t-trois-sources.js` relit pour la PWA.
     */
    private function sourcePwa(): string
    {
        $racines = [app_path('Pwa'), resource_path('views'), lang_path('fr')];
        $source = '';

        foreach ($racines as $racine) {
            $iterateur = new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
            );

            foreach ($iterateur as $fichier) {
                if ($fichier instanceof \SplFileInfo && $fichier->getExtension() === 'php') {
                    $source .= (string) file_get_contents($fichier->getPathname());
                }
            }
        }

        // Plancher : deux répertoires vides rendraient toute recherche
        // « introuvable », donc ce cas rouge sans rapport avec son sujet.
        $this->assertGreaterThan(100000, strlen($source), 'Le balayage des sources PWA est vide.');

        return $source;
    }
}
