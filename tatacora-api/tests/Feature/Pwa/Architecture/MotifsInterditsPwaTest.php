<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Architecture;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * G8 — les six motifs que le Product Owner interdit dans la PWA.
 *
 * ## Pourquoi des motifs ÉTROITS et NOMMÉS, jamais une expression vague
 *
 * Une garde large produit des faux positifs ; le premier développeur qui en
 * rencontre un désarme la garde entière — et elle cesse alors de protéger les
 * vrais cas aussi. Chacun des six motifs ci-dessous est donc défini par ce
 * qu'il attrape ET par ce qu'il laisse passer, et le second est écrit.
 *
 * ## Les six motifs, et le défaut réel derrière chacun
 *
 * **M1 — le `catch` qui avale.** Défaut n° 1 du dépôt. `app/Pwa/Livewire/`
 * comptait 44 blocs `catch` le 31/08/2026, dont une quinzaine dont le corps
 * entier est `// Ignorer`. Cinq autres rendent une valeur de repli inventée :
 * `$caPaye = 200000` sur le tableau de bord — un chiffre d'affaires FAUX,
 * affiché comme un fait, quand la requête échoue. Un échec qui n'est pas
 * nommé n'est pas un échec : c'est un chiffre.
 * *Ce qui passe :* un `catch` qui journalise, notifie, relance ou renvoie une
 * erreur à l'écran.
 *
 * **M2 — le `class_exists()` qui garde un appel de service.** C'est le motif
 * exact qui a fait qu'aucune dépense n'a jamais produit d'écriture comptable :
 * `if (class_exists(PasserEcritureService::class))`. La classe existe ou
 * n'existe pas — c'est décidé à la compilation, pas au comptoir. Si elle
 * manque, l'application est cassée et doit le dire ; si elle est là, le test
 * ne sert à rien. Entre les deux, il produit un silence.
 * *Ce qui passe :* `class_exists()` sur une dépendance de PAQUET réellement
 * optionnelle (dompdf, Laravel Excel), qui peut manquer sur cPanel mutualisé.
 *
 * **M3 — `->delete()` / `forceDelete()` depuis `app/Pwa/`.** Le « D » de CRUD
 * n'existe nulle part dans ce dépôt : `BasePolicy::delete()` rend `false` pour
 * les 20 policies, et la correction passe par le geste métier — annuler,
 * contre-passer, faire un avoir, poser le mouvement inverse.
 *
 * **M4 — `wire:confirm`.** C'est la boîte de dialogue native du navigateur :
 * police système, boutons en anglais selon la locale, hors charte, et
 * impossible à styler. Le maître a une modale de confirmation
 * (`crud-ui.js`, `modale-suppression`).
 *
 * **M5 — une valeur monétaire, un compte comptable ou un téléphone en dur.**
 * Précédents réels : `?? 20000` comme tarif de repli dans `PosHeberges`, le
 * compte `'601'` écrit deux fois dans `Depenses`, `'0100000000'` comme
 * téléphone dans `Hebergement` et `Departs`. Un montant en dur devient la
 * règle de production et personne ne le rouvre — la leçon de PA-53.
 *
 * **M6 — comparer des montants par `==` / `===`.** Règle du dépôt sans
 * exception : `bccomp()`. Une égalité flottante sur `DECIMAL(15,2)` échoue de
 * façon intermittente et jamais reproductible. **Aucune occurrence
 * aujourd'hui** : ce cas est PRÉVENTIF, et son plancher de lecture est ce qui
 * l'empêche d'être vert à vide.
 *
 * ## Preuve que chaque cas peut échouer
 *
 * **M1 à M5 sont ROUGES au 31/08/2026** sur des occurrences reproduites,
 * chacune nommée fichier et ligne : 25 `catch` avaleurs, un
 * `class_exists(PasserEcritureService::class)`, sept `->delete()`, deux
 * `wire:confirm`, et une série de montants, de comptes et de téléphones en
 * dur. Un test rouge qui désigne un fichier et une ligne prouve qu'il peut
 * échouer ; aucune mutation n'était nécessaire.
 *
 * **M6 est VERT — il a donc été muté.** Le 31/08/2026, une méthode témoin
 * `mutationTemoin(float $montantTotal): bool { return $montantTotal == 0; }` a
 * été ajoutée à `app/Pwa/Support/MontantFcfa.php` : le cas a rougi en citant
 * la ligne, puis le fichier a été restauré (empreinte MD5 vérifiée). C'est la
 * seule preuve possible pour une garde préventive — et sans elle, sa ligne
 * verte ne voudrait rien dire.
 *
 * Le motif de M2 a également été vérifié dans les deux sens :
 * `class_exists(PasserEcritureService::class)` est relevé,
 * `class_exists(Pdf::class)` ne l'est pas.
 *
 * @see CLAUDE.md §« Les 6 règles qui ne souffrent aucune exception »
 * @see docs/06_DEVELOPMENT_STANDARDS.md §5
 */
final class MotifsInterditsPwaTest extends TestCase
{
    /** Plancher mesuré le 31/08/2026 : 45 fichiers PHP sous `app/Pwa/`. */
    private const PLANCHER_FICHIERS_PHP = 35;

    /** Plancher mesuré le 31/08/2026 : 61 vues Blade sous `resources/views/pwa/`. */
    private const PLANCHER_VUES = 45;

    /**
     * M2 — les paquets réellement optionnels sur cPanel mutualisé. Un
     * `class_exists()` sur eux est légitime : le binaire peut manquer.
     * Tout le reste est un service de ce dépôt, qui existe ou n'existe pas.
     *
     * @var list<string>
     */
    private const DEPENDANCES_OPTIONNELLES = ['Pdf', 'Excel', 'Dompdf'];

    // ------------------------------------------------------------ M1 : le catch

    #[Test]
    public function aucun_catch_n_avale_son_echec(): void
    {
        $fichiers = $this->fichiersPhpDeLaPwa();
        $this->planchePhp($fichiers);

        $blocsLus = 0;
        $avaleurs = [];

        foreach ($fichiers as $relatif => $chemin) {
            foreach ($this->blocsCatch((string) file_get_contents($chemin)) as [$ligne, $corps]) {
                $blocsLus++;

                $motif = $this->diagnosticCatch($corps);
                if ($motif !== null) {
                    $avaleurs[] = "{$relatif}:{$ligne} → {$motif}";
                }
            }
        }

        $this->assertGreaterThanOrEqual(
            20,
            $blocsLus,
            "Seuls {$blocsLus} blocs catch ont ete lus (plancher 20, mesure 44 le 31/08/2026) : "
            .'l analyse par jetons ne mord plus.',
        );

        $this->assertSame(
            [],
            $avaleurs,
            "Des blocs `catch` avalent leur echec. Un echec qui n est pas nomme n est pas\n"
            ."un echec : c est un chiffre. Journaliser, notifier a l ecran, ou relancer.\n  "
            .implode("\n  ", $avaleurs),
        );
    }

    // ------------------------------------------------------ M2 : class_exists()

    #[Test]
    public function aucun_class_exists_ne_garde_un_appel_de_service(): void
    {
        $fichiers = $this->fichiersPhpDeLaPwa();
        $this->planchePhp($fichiers);

        $gardes = [];

        foreach ($fichiers as $relatif => $chemin) {
            $lignes = $this->lignesDeCode($chemin);

            foreach ($lignes as $index => $ligne) {
                if (preg_match_all('#class_exists\s*\(\s*([A-Za-z_\\\\]+)::class#', $ligne, $trouves) < 1) {
                    continue;
                }

                foreach ($trouves[1] as $classe) {
                    $court = ltrim((string) strrchr('\\'.$classe, '\\'), '\\');

                    if (in_array($court, self::DEPENDANCES_OPTIONNELLES, true)) {
                        continue;
                    }

                    if (! str_ends_with($court, 'Service')) {
                        continue;   // motif ETROIT : seuls les services de domaine.
                    }

                    $gardes[] = "{$relatif}:".($index + 1)." → class_exists({$court}::class)";
                }
            }
        }

        // ⚠ LE PLANCHER EXIGEAIT LE DEFAUT (corrige le 31/08/2026).
        //
        // Il valait `$lus >= 10` : au moins dix appels a `class_exists()`
        // devaient EXISTER dans le code balaye, sans quoi le cas echouait en
        // annoncant « le motif ne mord plus ». Or `$lus` compte les
        // occurrences du motif SURVEILLE. La vague CRUD ayant retire ces
        // gardes — c'est exactement ce que ce cas demande —, il n'en restait
        // qu'une, et le cas est passe ROUGE pour cause de succes.
        //
        // Un plancher doit mesurer que le BALAYAGE a eu lieu, jamais que le
        // defaut subsiste. Sinon il devient un quota de defauts, et le seul
        // moyen de le satisfaire est d'en reintroduire.
        //
        // Que le balayage ait eu lieu est deja garanti par `planchePhp()`
        // ci-dessus. Ce qui restait a prouver, c'est que le MOTIF mord encore :
        // il est donc eprouve sur un echantillon ecrit ICI, sans rien exiger
        // du code de production.
        $echantillon = 'if (class_exists(FauxDomaineService::class)) { }';
        $this->assertSame(
            1,
            preg_match('#class_exists\s*\(\s*([A-Za-z_\\\\]+)::class#', $echantillon),
            'Le motif de detection de `class_exists()` ne mord plus sur un echantillon '
            .'connu : le balayage ci-dessus ne prouve plus rien.',
        );


        $this->assertSame(
            [],
            $gardes,
            "Un `class_exists()` garde un appel de service de domaine. C est le motif exact\n"
            ."qui a fait qu aucune depense n a jamais produit d ecriture comptable : la classe\n"
            ."manquait, la garde etait fausse, et rien ne le disait.\n  "
            .implode("\n  ", $gardes),
        );
    }

    // ------------------------------------------------------- M3 : la suppression

    #[Test]
    public function aucune_suppression_n_est_declenchee_depuis_la_pwa(): void
    {
        $fichiers = $this->fichiersPhpDeLaPwa();
        $this->planchePhp($fichiers);

        $suppressions = [];

        foreach ($fichiers as $relatif => $chemin) {
            $lignes = $this->lignesDeCode($chemin);

            foreach ($lignes as $index => $ligne) {
                if (preg_match('#->\s*(forceDelete|delete)\s*\(\s*\)#', $ligne, $trouve) === 1) {
                    $suppressions[] = "{$relatif}:".($index + 1).' → '.trim($ligne);
                }
            }
        }

        $this->assertSame(
            [],
            $suppressions,
            "Le « D » de CRUD n existe nulle part dans ce depot : `BasePolicy::delete()` rend\n"
            ."`false` pour les 20 policies, et deux Observer levent a `deleting()`. La\n"
            ."correction passe par le geste metier — annuler, contre-passer, faire un avoir,\n"
            ."poser le mouvement inverse.\n  "
            .implode("\n  ", $suppressions),
        );
    }

    // ------------------------------------------------------- M4 : wire:confirm

    #[Test]
    public function aucune_vue_n_utilise_la_boite_native_du_navigateur(): void
    {
        $vues = $this->vuesDeLaPwa();

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_VUES,
            count($vues),
            'Seules '.count($vues).' vues relues (plancher '.self::PLANCHER_VUES.').',
        );

        $natives = [];

        foreach ($vues as $relatif => $chemin) {
            $lignes = $this->lignesDeVue($chemin);

            foreach ($lignes as $index => $ligne) {
                if (preg_match('#wire:confirm\s*=#', $ligne) === 1) {
                    $natives[] = "{$relatif}:".($index + 1);
                }
            }
        }

        $this->assertSame(
            [],
            $natives,
            "`wire:confirm` ouvre la boite de dialogue NATIVE du navigateur : police systeme,\n"
            ."boutons dans la langue du navigateur, hors charte, impossible a styler. Le\n"
            ."maitre a une modale de confirmation (crud-ui.js, `modale-suppression`).\n  "
            .implode("\n  ", $natives),
        );
    }

    // ------------------------------------- M5 : montants, comptes et telephones

    #[Test]
    public function aucune_valeur_monetaire_ni_reglementaire_n_est_ecrite_en_dur(): void
    {
        $fichiers = $this->fichiersPhpDeLaPwa();
        $this->planchePhp($fichiers);

        /**
         * Quatre motifs ETROITS, chacun nomme. Aucun ne porte sur « un nombre
         * dans le code » : les plafonds de pagination, les codes HTTP et les
         * durees resteraient pris, et la garde serait desarmee la semaine
         * suivante.
         */
        $motifs = [
            'repli monetaire' => '#\?\?\s*([0-9]{4,}(?:\.[0-9]+)?)\b#',
            'montant nomme en dur' => '#\$?[A-Za-z_]*(?:tarif|prix|montant|total|acompte|solde|caPaye|budget)'
                .'[A-Za-z_]*\s*=\s*([0-9]{3,}(?:\.[0-9]+)?)\s*;#i',
            'compte comptable en dur' => '#[\'"]compte[a-z_]*[\'"]\s*=>\s*[\'"]([0-9]{3,8})[\'"]#i',
            'telephone en dur' => '#[\'"](0[0-9]{8,9})[\'"]#',
        ];

        $enDur = [];
        $lignesLues = 0;

        foreach ($fichiers as $relatif => $chemin) {
            $lignes = $this->lignesDeCode($chemin);
            $lignesLues += count($lignes);

            foreach ($lignes as $index => $ligne) {
                foreach ($motifs as $nom => $motif) {
                    if (preg_match($motif, $ligne, $trouve) === 1) {
                        $enDur[] = "{$relatif}:".($index + 1)." → {$nom} « {$trouve[1]} »";
                    }
                }
            }
        }

        $this->assertGreaterThanOrEqual(
            3000,
            $lignesLues,
            "Seules {$lignesLues} lignes relues : le balayage se vide.",
        );

        $this->assertSame(
            [],
            $enDur,
            "Des valeurs monetaires, comptables ou de contact sont ecrites en dur dans un\n"
            ."composant. Un montant en dur devient la regle de production et personne ne le\n"
            ."rouvre (PA-53). Elles vont en base, en parametre, ou le refus est explicite.\n  "
            .implode("\n  ", $enDur),
        );
    }

    // ------------------------------------------- M6 : la comparaison de montants

    #[Test]
    public function aucun_montant_n_est_compare_par_egalite(): void
    {
        $fichiers = $this->fichiersPhpDeLaPwa();
        $this->planchePhp($fichiers);

        // Motif ETROIT : une variable ou propriete dont le NOM designe un
        // montant, comparee par == ou ===. Comparer « toute egalite » prendrait
        // les statuts, les identifiants et les chaines — et serait desarme.
        $motif = '#\$[A-Za-z_>\x2D\[\]\'"()>-]*'
            .'(?:montant|total|solde|prix|tarif|acompte|reste|debit|credit)'
            .'[A-Za-z_>\x2D\[\]\'"()>-]*\s*[=!]==?[^=]#i';

        $egalites = [];
        $lignesLues = 0;

        foreach ($fichiers as $relatif => $chemin) {
            $lignes = $this->lignesDeCode($chemin);
            $lignesLues += count($lignes);

            foreach ($lignes as $index => $ligne) {
                // Une AFFECTATION (`$montant = …`) n est pas une comparaison.
                $sansAffectation = (string) preg_replace('#(?<![=!<>])=(?!=)#', "\x01", $ligne);

                // ⚠ COMPARER A `null` OU A `[]` N'EST PAS COMPARER UN MONTANT
                // (corrige le 31/08/2026).
                //
                // La regle du depot porte sur l'egalite de deux VALEURS
                // monetaires, ou la representation flottante d'un
                // `DECIMAL(15,2)` rend le resultat intermittent. `$solde ===
                // null` et `$tarifes === []` sont des controles de PRESENCE :
                // ils demandent si la donnee existe, pas si deux montants sont
                // egaux, et `bccomp()` n'a rien a y faire — il leverait sur
                // `null`.
                //
                // La garde relevait trois de ces controles dans
                // `EcranDeCarte.php`, tous corrects. Un faux positif sur du
                // code juste fait desarmer la garde entiere, et celle-ci
                // protege une regle qui ne souffre aucune exception.
                // ⚠ Le `\b` porte sur les MOTS seulement. Ecrit en fin de
                // groupe (`(?:null|\[\s*\]|true|false)\b`), il ne pouvait pas
                // suivre un `]` : entre `]` et `)` il n'y a aucune limite de
                // mot, et l'alternative `[]` ne mordait jamais.
                $sansPresence = (string) preg_replace(
                    '#[=!]==?\s*(?:null\b|true\b|false\b|\[\s*\])#i',
                    "\x02",
                    $sansAffectation,
                );

                if (preg_match($motif, $sansPresence) === 1) {
                    $egalites[] = "{$relatif}:".($index + 1).' → '.trim($ligne);
                }
            }
        }

        $this->assertGreaterThanOrEqual(
            3000,
            $lignesLues,
            "Seules {$lignesLues} lignes relues : ce cas preventif serait vert a vide.",
        );

        $this->assertSame(
            [],
            $egalites,
            "Un montant est compare par egalite. La regle du depot est `bccomp()`, sans\n"
            ."exception : une egalite flottante sur DECIMAL(15,2) echoue de facon\n"
            ."intermittente et jamais reproductible.\n  "
            .implode("\n  ", $egalites),
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * Le CODE d'un fichier PHP, ses commentaires effacés — sauts de ligne
     * conservés pour que le numéro rapporté reste celui du fichier source.
     *
     * ## Pourquoi (31/08/2026) : quatre cas rouges, aucun défaut réel
     *
     * Ces gardes lisaient le fichier ligne par ligne, commentaires compris.
     * Elles accusaient donc les docblocks qui **expliquent le défaut retiré** :
     *
     *   - « La version précédente appelait pourtant `$u->delete()` sur une
     *     unité d'hébergement » → compté comme une suppression ;
     *   - « ⚠ AUCUN TÉLÉPHONE FABRIQUÉ. Le motif `'0100000000'` a été retiré
     *     de M1 le 31/08/2026 » → compté comme un téléphone en dur ;
     *   - « Aucun repli chiffré […] jamais un `?? 20000` » → compté comme un
     *     repli monétaire.
     *
     * Les trois phrases disent exactement l'inverse de ce qu'on leur
     * reprochait. C'est le pire signal qu'une garde puisse produire : elle
     * punit la documentation d'un correctif, et la réaction naturelle est de
     * retirer le commentaire — donc l'explication — pour faire taire le rouge.
     *
     * Le même piège avait déjà été fermé dans `ChassisModalePwaTest` pour un
     * seul de ses cas ; la correction n'avait pas été propagée. Elle l'est ici
     * pour les quatre.
     *
     * L'effacement passe par `token_get_all()`, jamais par une expression
     * régulière : un `//` dans une chaîne (`'https://…'`) n'ouvre pas un
     * commentaire, et un analyseur textuel tronquerait la ligne.
     */
    private function codeSansCommentaires(string $source): string
    {
        $sortie = '';

        foreach (token_get_all($source) as $jeton) {
            if (! is_array($jeton)) {
                $sortie .= $jeton;

                continue;
            }

            if (in_array($jeton[0], [T_COMMENT, T_DOC_COMMENT], true)) {
                // On garde les sauts de ligne : les numeros de ligne rapportes
                // doivent rester ceux du fichier reel.
                $sortie .= str_repeat("\n", substr_count($jeton[1], "\n"));

                continue;
            }

            $sortie .= $jeton[1];
        }

        return $sortie;
    }

    /**
     * Les lignes d'un fichier PHP, commentaires effacés.
     *
     * @return list<string>
     */
    private function lignesDeCode(string $chemin): array
    {
        return explode("\n", $this->codeSansCommentaires((string) file_get_contents($chemin)));
    }

    /**
     * Les lignes d'une vue Blade, commentaires `{{-- --}}` effacés.
     *
     * Blade n'est pas du PHP : `token_get_all()` ne connaît pas `{{-- --}}`.
     * Le retrait est donc textuel, et il préserve lui aussi les sauts de ligne.
     *
     * @return list<string>
     */
    private function lignesDeVue(string $chemin): array
    {
        $source = (string) preg_replace_callback(
            '#\{\{--.*?--\}\}#s',
            static fn (array $bloc): string => str_repeat("\n", substr_count($bloc[0], "\n")),
            (string) file_get_contents($chemin),
        );

        return explode("\n", $source);
    }

    /**
     * Les blocs `catch` d'un fichier, repérés par analyse de jetons — un
     * découpage par accolades sur du texte confondrait une accolade dans une
     * chaîne avec une fin de bloc.
     *
     * @return list<array{0: int, 1: string}> [ligne, corps du bloc]
     */
    private function blocsCatch(string $source): array
    {
        $jetons = token_get_all($source);
        $blocs = [];
        $n = count($jetons);

        for ($i = 0; $i < $n; $i++) {
            $jeton = $jetons[$i];

            if (! is_array($jeton) || $jeton[0] !== T_CATCH) {
                continue;
            }

            $ligne = (int) $jeton[2];

            // Aller a l accolade ouvrante qui suit la parenthese du catch.
            $j = $i;
            while ($j < $n && $jetons[$j] !== '{') {
                $j++;
            }

            if ($j >= $n) {
                break;
            }

            $profondeur = 0;
            $corps = '';

            for ($k = $j; $k < $n; $k++) {
                $texte = is_array($jetons[$k]) ? $jetons[$k][1] : $jetons[$k];

                if ($texte === '{') {
                    $profondeur++;
                    if ($profondeur === 1) {
                        continue;
                    }
                } elseif ($texte === '}') {
                    $profondeur--;
                    if ($profondeur === 0) {
                        break;
                    }
                }

                // Les commentaires ne comptent PAS comme un traitement : c est
                // tout l objet de ce controle (« // Ignorer »).
                if (is_array($jetons[$k]) && in_array($jetons[$k][0], [T_COMMENT, T_DOC_COMMENT], true)) {
                    continue;
                }

                $corps .= $texte;
            }

            $blocs[] = [$ligne, $corps];
            $i = $j;
        }

        return $blocs;
    }

    /**
     * `null` si le bloc traite son échec ; sinon la raison du refus.
     */
    private function diagnosticCatch(string $corps): ?string
    {
        $utile = trim($corps);

        if ($utile === '') {
            return 'bloc VIDE — l echec disparait sans laisser de trace';
        }

        $nommages = [
            'throw', 'Log::', 'report(', 'notifier(', 'addError(', 'abort(',
            'dispatch(', 'flash(', 'getMessage(', 'erreur', 'Erreur',
        ];

        foreach ($nommages as $marqueur) {
            if (str_contains($utile, $marqueur)) {
                return null;
            }
        }

        // Repli silencieux : une valeur par defaut posee sans un mot.
        $repli = '#(?:=|return)\s*(?:collect\(\)|\[\]|null|true|false|-?[0-9]+(?:\.[0-9]+)?)\s*;#';

        if (preg_match($repli, $utile) === 1) {
            return 'repli SILENCIEUX — une valeur par defaut est posee sans nommer l echec';
        }

        return 'echec non nomme — ni journalisation, ni message, ni relance';
    }

    /**
     * @param  array<string, string>  $fichiers
     */
    private function planchePhp(array $fichiers): void
    {
        $this->assertGreaterThanOrEqual(
            self::PLANCHER_FICHIERS_PHP,
            count($fichiers),
            'Seuls '.count($fichiers).' fichiers PHP relus sous app/Pwa (plancher '
            .self::PLANCHER_FICHIERS_PHP.') : le balayage se vide, et un balayage vide est vert.',
        );
    }

    /**
     * @return array<string, string>
     */
    private function fichiersPhpDeLaPwa(): array
    {
        return $this->fichiersSous(app_path('Pwa'), 'app/Pwa', '.php');
    }

    /**
     * @return array<string, string>
     */
    private function vuesDeLaPwa(): array
    {
        return $this->fichiersSous(
            resource_path('views'.DIRECTORY_SEPARATOR.'pwa'),
            'resources/views/pwa',
            '.blade.php',
        );
    }

    /**
     * @return array<string, string>
     */
    private function fichiersSous(string $racine, string $prefixe, string $extension): array
    {
        $fichiers = [];
        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
        );

        /** @var \SplFileInfo $fichier */
        foreach ($iterateur as $fichier) {
            if (! $fichier->isFile() || ! str_ends_with($fichier->getFilename(), $extension)) {
                continue;
            }

            $absolu = (string) $fichier->getRealPath();
            $relatif = $prefixe.'/'.str_replace(
                [$racine.DIRECTORY_SEPARATOR, DIRECTORY_SEPARATOR],
                ['', '/'],
                $absolu,
            );

            $fichiers[$relatif] = $absolu;
        }

        ksort($fichiers);

        return $fichiers;
    }
}
