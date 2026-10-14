<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * G4 — « Le châssis de modale est partagé, pas recopié. »
 *
 * ## Les quatre défauts mesurés le 31/08/2026
 *
 * 1. **41 conteneurs de modale écrits à la main** dans `resources/views/pwa/`,
 *    chacun redéclarant son voile, son ombre et son rayon. Une charte se tient
 *    à un endroit ou ne se tient nulle part.
 *
 * 2. **Aucun de ces conteneurs ne borne sa hauteur** : ils portent
 *    `overflow-hidden` sans `max-height`. Une modale plus haute que la fenêtre
 *    est donc **tronquée et non défilable** — le bouton « Enregistrer » devient
 *    inatteignable, et l'utilisateur conclut que le formulaire ne marche pas.
 *    La maquette d'alors écrivait `max-height: 90vh; overflow-y: auto` sur
 *    `.boite-modale`.
 *
 * 3. **La modale d'export est recopiée dans 11 vues sous 10 titres
 *    différents.** Onze endroits à corriger le jour où l'on ajoute un format,
 *    et dix libellés qui ont déjà divergé.
 *
 * 4. **Le voile et le rayon n'étaient pas ceux de la maquette d'alors** :
 *    `bg-black/45` là où elle posait `rgba(0,0,0,.5)` avec
 *    `backdrop-filter: blur(2px)`, et `rounded-xl` (12 px) ou `rounded-lg`
 *    (8 px) là où elle fixait 12 px. C'est la leçon de PA-139 et PA-145 :
 *    l'échelle nommée de Tailwind n'est pas la valeur qu'elle approche.
 *
 * ## Les règles sont LUES dans la feuille SERVIE (PA-183, 10/09/2026)
 *
 * Jusqu'au 10/09/2026, `.overlay-modale` et `.boite-modale` étaient extraits
 * de `prototype_v2/assets/css/app.css` et confrontés à la feuille servie. La
 * vue Blade et sa feuille étant désormais le maître, et `prototype_v2/` une
 * ancienne version, cette confrontation ne prouverait plus rien. Les règles
 * sont lues dans `public/assets/css/app.css` — la feuille que le navigateur
 * télécharge — et jugées sur ce qui rend une modale UTILISABLE : un voile,
 * un rayon, une hauteur bornée, un défilement.
 *
 * ## Trois mutations exécutées le 31/08/2026, toutes rejouées et annulées
 *
 * 1. `class="boite-modale relative"` → `class="bg-white rounded-lg relative
 *    overflow-hidden"` dans le châssis. **Elle n'a pas mordu au premier
 *    essai** : la recherche portait sur le fichier entier, et l'en-tête
 *    documentaire du châssis NOMME `boite-modale` trois fois. Le contrôle
 *    porte donc désormais sur un attribut `class=`, commentaires Blade
 *    retirés. C'est exactement le piège du contrat « rendu OU mentionné » que
 *    `t-trois-sources.js` documente — ici, il a été fermé.
 * 2. `max-height: 90vh; overflow-y: auto` retiré de `public/assets/css/app.css`
 *    (la feuille SERVIE) : le cas a rougi en nommant les
 *    deux déclarations. C'est la garde contre PA-139.
 * 3. Le chemin du châssis pointé sur un fichier inexistant : le premier cas a
 *    rougi en le nommant.
 *
 * Les deux autres cas sont rouges sur des défauts reproduits — 39 conteneurs
 * écrits à la main, aucun ne bornant sa hauteur, et 12 fichiers portant la
 * modale d'export.
 *
 * @see public/assets/css/app.css (.overlay-modale, .boite-modale)
 * @see docs/DIRECTIVE_CONFORMITE_100.md Article 4.6 (les modales)
 */
final class ChassisModalePwaTest extends TestCase
{
    /**
     * Le châssis générique attendu — livré par la vague CRUD en cours. Trois
     * fichiers, trois rôles distincts, nommés ici parce que c'est le contrat
     * que ce test vérifie, pas une liste de pages susceptible de vieillir.
     */
    private const CHASSIS = 'views/components/pwa/modale.blade.php';

    private const CHASSIS_ARCHIVAGE = 'views/components/pwa/modale-archivage.blade.php';

    private const CHASSIS_EXPORT = 'views/pwa/partials/modale-export.blade.php';

    /**
     * Les voiles plein écran qui ne sont PAS des modales — chacun avec sa
     * raison, datée.
     *
     * Les compter comme modales ferait rougir la garde sur du code conforme, et
     * un développeur qui rencontre un faux positif désarme la garde entière.
     * Mais une exemption sans raison est une porte ouverte : chaque entrée dit
     * ce qu'est réellement l'élément, et pourquoi la borne de hauteur du
     * châssis ne s'y applique pas.
     *
     * ⚠ Ce sont tous des PANNEAUX : ils occupent toute la hauteur de la fenêtre
     * (`inset-y-0` ou `h-full`) et font défiler leur corps eux-mêmes. Le défaut
     * que `max-height:90vh` corrige — une boîte centrée plus haute que la
     * fenêtre, tronquée et non défilable — ne peut pas les atteindre.
     *
     * @var array<string, string>
     */
    private const VOILES_HORS_MODALE = [
        // Voile du menu latéral escamotable sur mobile (`#overlay-sidebar-mobile`,
        // transcrit de `shell.js`).
        'views/pwa/partials/menu-lateral.blade.php' => 'Voile du menu latéral mobile (shell.js) — 31/08/2026.',

        // Voile du panneau d'accès rapide (Alt+A), tiroir latéral droit.
        'views/pwa/partials/acces-rapide.blade.php' => 'Voile du tiroir d\'accès rapide (Alt+A) — 31/08/2026.',

        // Panneau latéral « Historique des réservations » du maître
        // (`reservations.html` l.60-105) : `inset-y-0 right-0`, pleine hauteur,
        // corps défilant. Ce n'est pas une boîte centrée.
        'views/pwa/hebergement/reservations.blade.php' => 'Panneau latéral « Historique » (maître l.60-105), pleine hauteur — 31/08/2026.',
    ];

    /**
     * Les marqueurs de la modale d'export de la PWA — DEUX formes, et il en
     * faut deux.
     *
     * Ce ne sont pas des libellés du maître : ce sont les signatures qui
     * permettent de compter les copies. La première est la phrase que les
     * douze copies avaient en dur. La seconde est la clé de traduction qui
     * l'a remplacée quand le partial partagé est passé en i18n.
     *
     * ## Pourquoi la première ne suffisait plus (31/08/2026)
     *
     * Ce cas cherchait le seul littéral. Le partial partagé ayant été
     * traduit, le compte est tombé à ZÉRO et le cas est passé rouge — alors
     * que le dépôt venait de s'améliorer sur les deux tableaux : la modale
     * n'existe plus qu'une fois, et elle est traduite.
     *
     * C'est le défaut de garde le plus insidieux : elle mesurait la forme du
     * code plutôt que la propriété voulue. Un rouge injustifié se paie plus
     * cher qu'un vert manquant — c'est lui qui fait désactiver le contrôle.
     *
     * On garde le littéral : une copie non migrée le porte encore, et c'est
     * précisément celle qu'il faut attraper.
     *
     * @var list<string>
     */
    private const MARQUEURS_EXPORT = [
        'PDF Officiel A4 Imprimable',
        'pwa.export.pdf_titre',
    ];

    #[Test]
    public function le_chassis_de_modale_partage_existe(): void
    {
        $manquants = [];

        foreach ([self::CHASSIS, self::CHASSIS_ARCHIVAGE, self::CHASSIS_EXPORT] as $relatif) {
            if (! is_file(resource_path($relatif))) {
                $manquants[] = 'resources/'.$relatif;
            }
        }

        $this->assertSame(
            [],
            $manquants,
            "Le chassis de modale partage n existe pas. Sans lui, chaque ecran continue\n"
            ."de redeclarer son voile, son rayon et son ombre a la main :\n  "
            .implode("\n  ", $manquants),
        );
    }

    /**
     * Le châssis porte les classes `overlay-modale` et `boite-modale`, et la
     * feuille SERVIE définit réellement les règles qui rendent la modale
     * utilisable — voile, flou, rayon, hauteur bornée, défilement vertical.
     *
     * ⚠ Jusqu'au 10/09/2026, les valeurs attendues étaient lues dans
     * `prototype_v2/assets/css/app.css` et confrontées à la feuille servie.
     * La vue et sa feuille étant désormais le maître (PA-183), les confronter
     * l'une à l'autre ne prouverait plus rien. Reste l'invariant FONCTIONNEL,
     * qui ne demande aucune référence : une boîte plus haute que la fenêtre
     * doit être bornée (`max-height` en `vh`, au plus 100) et défilable
     * (`overflow-y: auto|scroll`), sans quoi le bouton « Enregistrer » devient
     * inatteignable sur un portable 1366×768.
     */
    #[Test]
    public function le_chassis_s_appuie_sur_les_regles_de_la_feuille_servie(): void
    {
        $servi = $this->cssServiParLaPwa();

        $voile = $this->declarations($servi, 'overlay-modale');
        $boite = $this->declarations($servi, 'boite-modale');

        // Plancher : sans lui, une regle renommee rendrait ce cas vert en ne
        // lisant plus rien.
        $this->assertGreaterThanOrEqual(
            4,
            count($voile),
            'Moins de 4 declarations lues sur .overlay-modale dans la feuille servie : '
            .'la lecture ne mesure plus rien.',
        );
        $this->assertGreaterThanOrEqual(
            4,
            count($boite),
            'Moins de 4 declarations lues sur .boite-modale dans la feuille servie.',
        );

        $chemin = resource_path(self::CHASSIS);
        $this->assertFileExists(
            $chemin,
            'Le chassis resources/'.self::CHASSIS.' n existe pas : impossible de verifier '
            .'qu il s appuie sur la feuille servie.',
        );

        // ⚠ Les commentaires Blade sont RETIRES avant toute recherche. Sans
        // cela, un chassis qui ne fait que NOMMER `boite-modale` dans son
        // entete documentaire satisfaisait le controle : la mutation
        // « remplacer class="boite-modale" par class="bg-white rounded-lg" »
        // n a pas mordu au premier essai, et c est ainsi qu on l a su.
        $source = (string) preg_replace('#\{\{--.*?--\}\}#s', '', (string) file_get_contents($chemin));

        // Le chassis doit PORTER les deux classes du maitre. Exiger les
        // declarations en style inline serait exiger une duplication de la
        // feuille de style : les valeurs vivent dans app.css, le gabarit s'y
        // rattache. C'est le sens de la non-conformite n° 1 de
        // `RESPECT_TABLEAU_RAPPORT.md` §4 — ne jamais recopier ce qui existe.
        $absentes = [];

        foreach (['overlay-modale', 'boite-modale'] as $classe) {
            $porte = preg_match(
                '#class\s*=\s*"[^"]*\b'.preg_quote($classe, '#').'\b#',
                $source,
            ) === 1;

            if (! $porte) {
                $absentes[] = "le chassis ne porte pas la classe `{$classe}` du maitre "
                    .'sur un attribut class= (une mention en commentaire ne compte pas)';
            }
        }

        // ⚠ Et la feuille SERVIE doit reellement porter les regles. PA-139 :
        // la feuille servie par la PWA a ete une copie amputee de 105 lignes.
        // Se fier a la classe sans verifier la regle laisserait passer
        // exactement ce defaut-la — une modale qui porte le bon nom de classe
        // et aucune des proprietes qui la rendent utilisable.
        foreach ([
            ['.overlay-modale', 'background', $voile],
            ['.overlay-modale', 'backdrop-filter', $voile],
            ['.boite-modale', 'border-radius', $boite],
        ] as [$regle, $propriete, $declarations]) {
            if (($declarations[$propriete] ?? '') === '') {
                $absentes[] = "{$regle} → {$propriete} absente de la feuille servie";
            }
        }

        // La boite est BORNEE a la hauteur de la fenetre…
        $hauteur = $boite['max-height'] ?? '';
        if (preg_match('#^(\d+(?:\.\d+)?)vh$#', $this->sansEspaces($hauteur), $vh) !== 1 || (float) $vh[1] > 100.0) {
            $absentes[] = ".boite-modale → max-height « {$hauteur} » : la boite n est pas bornee "
                .'a la hauteur de la fenetre (attendu : une valeur en vh, au plus 100vh)';
        }

        // … et DEFILE quand son contenu la depasse.
        $defilement = $boite['overflow-y'] ?? '';
        if (! in_array($this->sansEspaces($defilement), ['auto', 'scroll'], true)) {
            $absentes[] = ".boite-modale → overflow-y « {$defilement} » : la boite ne defile pas";
        }

        $this->assertSame(
            [],
            $absentes,
            "Le chassis de modale ne s appuie pas sur des regles utilisables.\n"
            ."Sans `max-height` ni `overflow-y`, une modale plus haute que la fenetre est\n"
            ."tronquee et non defilable : le bouton « Enregistrer » devient inatteignable.\n  "
            .implode("\n  ", $absentes),
        );
    }

    /**
     * ⚠ DEUX CORRECTIONS DE MESURE, LE 31/08/2026 — dans les deux sens.
     *
     * 1. **Les commentaires Blade sont retirés avant le balayage.** Ce cas
     *    accusait `reservations.blade.php:174`, une ligne qui dit
     *    littéralement « Son voile ne peut pas s'écrire `bg-black/40` : la
     *    garde de châssis refuse tout voile posé à la main ». La garde
     *    reprochait à un développeur d'avoir EXPLIQUÉ pourquoi il s'y
     *    conformait. C'est le même piège que le cas
     *    `le_chassis_reprend_le_voile_et_la_boite_du_maitre` a fermé pour
     *    lui-même — la correction n'y avait pas été propagée.
     *
     * 2. **Le voile en style INLINE est désormais détecté.** Ne chercher que
     *    `bg-black/` laissait une porte ouverte, et elle a été empruntée :
     *    `style="background:rgba(0,0,0,.4)"` posait le même voile sans
     *    déclencher la garde. Une garde qu'on contourne en changeant de
     *    notation ne mesure pas la propriété, elle mesure une orthographe.
     *
     * Les deux corrections ont été éprouvées par mutation :
     *   - re-poser `class="fixed inset-0 bg-black/40"` dans une vue de la PWA
     *     hors registre → ROUGE, la ligne nommée ;
     *   - poser `style="background:rgba(0,0,0,.5)"` sur un `fixed inset-0`
     *     dans la même vue → ROUGE aussi, alors que l'ancienne version
     *     restait verte ;
     *   - vider `VOILES_HORS_MODALE` → ROUGE sur les trois panneaux, ce qui
     *     prouve que le registre porte bien quelque chose.
     */
    #[Test]
    public function aucune_vue_ne_redeclare_un_conteneur_de_modale_a_la_main(): void
    {
        $fautifs = [];
        $relus = 0;
        $sansHauteur = 0;

        foreach ($this->vuesPwa() as $relatif => $chemin) {
            if (array_key_exists($relatif, self::VOILES_HORS_MODALE)) {
                continue;
            }

            $relus++;

            // Les commentaires Blade sont RETIRES : une ligne qui NOMME
            // `bg-black/` pour expliquer qu'elle ne l'emploie pas n'est pas un
            // voile. Le retrait preserve les sauts de ligne pour que le numero
            // rapporte reste celui du fichier source.
            $source = (string) preg_replace_callback(
                '#\{\{--.*?--\}\}#s',
                static fn (array $bloc): string => str_repeat("\n", substr_count($bloc[0], "\n")),
                (string) file_get_contents($chemin),
            );

            $lignes = explode("\n", $source);

            foreach ($lignes as $index => $ligne) {
                // Un voile, c'est une couleur noire semi-transparente posee en
                // plein ecran — que la notation soit une classe Tailwind ou un
                // style inline.
                $voile = str_contains($ligne, 'bg-black/')
                    || preg_match('#rgba\(\s*0\s*,\s*0\s*,\s*0\s*,#', $ligne) === 1;

                if (! $voile) {
                    continue;
                }

                $fautifs[] = 'resources/'.$relatif.':'.($index + 1);

                // La boite suit le voile : on regarde les trois lignes qui
                // viennent pour savoir si elle borne sa hauteur.
                $suite = implode(' ', array_slice($lignes, $index + 1, 3));
                if (! str_contains($suite, 'max-h-[90vh]') && ! str_contains($suite, 'max-height:90vh')) {
                    $sansHauteur++;
                }
            }
        }

        // Plancher mesure le 31/08/2026 : 61 vues Blade sous resources/views/pwa.
        $this->assertGreaterThanOrEqual(
            45,
            $relus,
            "Seules {$relus} vues ont ete relues (plancher 45, mesure 61 le 31/08/2026) : "
            .'le balayage est en train de se vider.',
        );

        $this->assertSame(
            [],
            $fautifs,
            "Des vues redeclarent un conteneur de modale a la main au lieu de passer par\n"
            ."le chassis <x-pwa.modale>. Sur ".count($fautifs)." conteneurs, {$sansHauteur} ne bornent\n"
            ."pas leur hauteur : la modale est tronquee et non defilable des qu elle depasse\n"
            ."la fenetre.\n  ".implode("\n  ", $fautifs),
        );
    }

    #[Test]
    public function la_modale_d_export_n_est_declaree_qu_une_fois(): void
    {
        $porteurs = [];

        foreach ($this->vuesPwa(tout: true) as $relatif => $chemin) {
            $source = (string) file_get_contents($chemin);

            foreach (self::MARQUEURS_EXPORT as $marqueur) {
                if (str_contains($source, $marqueur)) {
                    $porteurs[] = 'resources/'.$relatif;
                    break;
                }
            }
        }

        sort($porteurs);

        $this->assertCount(
            1,
            $porteurs,
            'La modale d export est declaree dans '.count($porteurs)." fichiers. Elle doit vivre\n"
            ."a UN seul endroit (resources/".self::CHASSIS_EXPORT.") : autrement, ajouter un\n"
            ."format se fait en ".count($porteurs)." endroits, et les titres divergent — ils ont deja diverge.\n  "
            .implode("\n  ", $porteurs),
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * La feuille de style REELLEMENT servie par la PWA — celle que le
     * navigateur télécharge. Depuis PA-183 (10/09/2026), c'est aussi la
     * référence : il n'y a plus de feuille « du maître » à côté.
     */
    private function cssServiParLaPwa(): string
    {
        $chemin = public_path('assets/css/app.css');

        $this->assertFileExists(
            $chemin,
            'La PWA ne sert aucune feuille de style : public/assets/css/app.css est absente.',
        );

        return (string) file_get_contents($chemin);
    }

    /**
     * Les déclarations d'une règle CSS du maître, propriété => valeur.
     *
     * @return array<string, string>
     */
    private function declarations(string $css, string $classe): array
    {
        // ⚠ L'ancrage en debut de ligne est la substance de ce motif : sans
        // lui, `.boite-modale` tombait d'abord sur le selecteur descendant
        // `.overlay-modale[style*="display:flex"] .boite-modale` et ne lisait
        // que 2 declarations sur 7. Le plancher de l'appelant l'a revele.
        $motif = '#(?:^|\n)[ \t]*\.'.preg_quote($classe, '#').'\s*\{([^}]*)\}#';

        if (preg_match($motif, $css, $trouve) !== 1) {
            return [];
        }

        $declarations = [];

        foreach (explode(';', $trouve[1]) as $morceau) {
            if (! str_contains($morceau, ':')) {
                continue;
            }

            [$propriete, $valeur] = explode(':', $morceau, 2);
            $declarations[trim($propriete)] = trim($valeur);
        }

        return $declarations;
    }

    /**
     * Les vues Blade de la PWA.
     *
     * @return array<string, string> chemin relatif à `resources/` => chemin absolu
     */
    /**
     * L'action de FERMETURE de chaque modale existe reellement sur le
     * composant qui la rend — 03/09/2026, ne d'un defaut constate par le
     * Product Owner : la modale « Modifier le prix » de la carte du bar
     * n'avait pas declare `fermer`, le chassis retombait sur son defaut
     * `fermerModales`, absent des ecrans de carte, et la CROIX plantait en
     * 500 (MethodNotFoundException).
     *
     * ⚠ Aucun test ne pouvait le voir : les cas fonctionnels appellent les
     * actions par leur nom, jamais la croix. La garde relie donc chaque
     * COMPOSANT a ses vues (racine + @include resolus) et confronte l'action
     * de fermeture a ses methodes publiques. Une action commencant par `$`
     * (`$set(...)`) est une expression Livewire, pas une methode.
     */
    #[Test]
    public function chaque_modale_ferme_par_une_action_qui_existe_vraiment(): void
    {
        $verifiees = 0;
        $composants = $this->composantsPwa();

        $this->assertGreaterThanOrEqual(30, count($composants), 'La resolution composant/vue est cassee.');

        foreach ($composants as $classe => $vueRacine) {
            $publiques = get_class_methods($classe);

            foreach ($this->vuesAtteintes($vueRacine) as $chemin) {
                $source = (string) file_get_contents($chemin);

                if (! str_contains($source, '<x-pwa.modale')) {
                    continue;
                }

                foreach ($this->attributsDesModales($source) as $attributs) {
                    $action = preg_match('#fermer="([^"]+)"#', $attributs, $trouve) === 1
                        ? $trouve[1]
                        : 'fermerModales';

                    $verifiees++;

                    if (str_starts_with($action, '$')) {
                        continue;
                    }

                    $nom = (string) preg_replace('#\(.*$#', '', $action);

                    $this->assertContains(
                        $nom,
                        $publiques,
                        'La modale de '.basename($chemin).' ferme par « '.$nom.'() », methode '
                            .'absente de '.$classe.' : la croix de fermeture leve une '
                            .'MethodNotFoundException (500) au premier clic.',
                    );
                }
            }
        }

        // Plancher : une resolution cassee rendrait la boucle vide, donc
        // verte — le defaut meme que ce cas surveille.
        $this->assertGreaterThanOrEqual(20, $verifiees, 'Trop peu de modales confrontees ('.$verifiees.').');
    }

    /**
     * Les attributs de chaque balise `<x-pwa.modale …>` d'une vue.
     *
     * ⚠ PAS de regex `<x-pwa\.modale(.*?)>` : les attributs contiennent des
     * `=>` et des `->` (`['article' => $article->libelle]`), et la capture
     * non gourmande s'arretait au premier `>` VENU D'UNE CHAINE — la garde
     * lisait alors une balise tronquee, ne voyait pas son `fermer` et
     * accusait a tort une modale correcte. Le balayage suit donc les
     * guillemets : seul un `>` HORS chaine ferme la balise.
     *
     * @return list<string>
     */
    private function attributsDesModales(string $source): array
    {
        // Les COMMENTAIRES Blade sont retires d'abord : plusieurs vues citent
        // `<x-pwa.modale>` dans leur entete pour expliquer le chassis, et une
        // mention n'est pas une balise — la lire comme telle accusait une vue
        // parfaitement correcte (constate en posant cette garde).
        $source = (string) preg_replace('#\{\{--.*?--\}\}#s', '', $source);

        $attributs = [];
        $position = 0;

        while (($debut = strpos($source, '<x-pwa.modale', $position)) !== false) {
            $i = $debut + strlen('<x-pwa.modale');
            $guillemet = null;

            while ($i < strlen($source)) {
                $c = $source[$i];

                if ($guillemet !== null) {
                    if ($c === $guillemet) {
                        $guillemet = null;
                    }
                } elseif ($c === '"' || $c === "'") {
                    $guillemet = $c;
                } elseif ($c === '>') {
                    break;
                }

                $i++;
            }

            $attributs[] = substr($source, $debut, $i - $debut);
            $position = $i;
        }

        return $attributs;
    }

    /**
     * Les composants Livewire de la PWA, avec la vue qu'ils rendent.
     *
     * @return array<class-string, string> classe => chemin absolu de la vue
     */
    private function composantsPwa(): array
    {
        $composants = [];
        $racine = app_path('Pwa'.DIRECTORY_SEPARATOR.'Livewire');
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS));

        /** @var \SplFileInfo $fichier */
        foreach ($iterateur as $fichier) {
            if (! $fichier->isFile() || ! str_ends_with($fichier->getFilename(), '.php')) {
                continue;
            }

            $source = (string) file_get_contents((string) $fichier->getRealPath());

            if (preg_match('#namespace\s+([^;]+);#', $source, $ns) !== 1) {
                continue;
            }

            $classe = trim($ns[1]).'\\'.$fichier->getBasename('.php');

            if (! class_exists($classe) || ! is_subclass_of($classe, \Livewire\Component::class)) {
                continue;
            }

            // La vue rendue : `view('pwa.…')` dans le source du composant.
            if (preg_match('#view[(].(pwa[.][a-z0-9_.-]+).#i', $source, $v) !== 1) {
                continue;
            }

            $chemin = resource_path('views'.DIRECTORY_SEPARATOR.str_replace('.', DIRECTORY_SEPARATOR, $v[1]).'.blade.php');

            if (is_file($chemin)) {
                $composants[$classe] = $chemin;
            }
        }

        return $composants;
    }

    /**
     * Une vue et toutes celles qu'elle inclut, transitivement.
     *
     * @param  list<string>  $vues
     * @return list<string> chemins absolus
     */
    private function vuesAtteintes(string $racine, array $vues = []): array
    {
        if (in_array($racine, $vues, true) || ! is_file($racine)) {
            return $vues;
        }

        $vues[] = $racine;
        $source = (string) file_get_contents($racine);

        preg_match_all("#@include\('([a-z0-9_.\-]+)'#i", $source, $inclusions);

        foreach ($inclusions[1] as $nom) {
            $chemin = resource_path('views'.DIRECTORY_SEPARATOR.str_replace('.', DIRECTORY_SEPARATOR, $nom).'.blade.php');
            $vues = $this->vuesAtteintes($chemin, $vues);
        }

        return $vues;
    }

    /** @return array<string, string> */
    private function vuesPwa(bool $tout = false): array
    {
        $racine = resource_path('views'.($tout ? '' : DIRECTORY_SEPARATOR.'pwa'));

        $vues = [];
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS));

        /** @var \SplFileInfo $fichier */
        foreach ($iterateur as $fichier) {
            if (! $fichier->isFile() || ! str_ends_with($fichier->getFilename(), '.blade.php')) {
                continue;
            }

            $absolu = (string) $fichier->getRealPath();
            $relatif = str_replace(
                [resource_path().DIRECTORY_SEPARATOR, DIRECTORY_SEPARATOR],
                ['', '/'],
                $absolu,
            );

            $vues[$relatif] = $absolu;
        }

        ksort($vues);

        return $vues;
    }

    private function sansEspaces(string $valeur): string
    {
        return (string) preg_replace('#\s+#', '', $valeur);
    }
}
