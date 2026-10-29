<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Architecture;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * G7 — « Aucune donnée métier ne vit dans la session HTTP. »
 *
 * ## Les quatre défauts sont FERMÉS — la garde est devenue préventive
 *
 * Relevé le 31/08/2026 dans `app/Pwa/Livewire/`, et corrigé depuis :
 *
 * | Clé | Ce qu'elle portait | Fermée par |
 * |---|---|---|
 * | `panier_sejour_{id}` | le panier d'un client hébergé | table `paniers` (PA-161) |
 * | `tourisme_departs_assignments` | la réaffectation de guide (M9, UC-39) | table de domaine |
 * | `bar_boissons_indisponibles` | l'indisponibilité d'une boisson à la carte | `indisponibilites_carte` |
 * | `restaurant_plats_indisponibles` | l'indisponibilité d'un plat | `indisponibilites_carte` |
 *
 * La dernière — le panier de séjour — était **accordée par exception datée**,
 * en attente de l'arbitrage Q2 de `PROPOSITION_MODELE_PANIER_POS.md`. Cet
 * arbitrage est rendu (PA-161, option A : verrou pessimiste en service, MySQL
 * n'ayant pas d'index partiel), la table existe, et l'exception a été retirée
 * le 31/08/2026 avec la dernière écriture qu'elle couvrait. Une exception qui
 * survit à sa raison est un oubli déguisé en décision (PA-107, PA-120,
 * PA-144).
 *
 * ## Pourquoi c'est une faute, et pas un raccourci
 *
 * Une session HTTP **expire**, est **propre à un navigateur**, et **disparaît
 * à la déconnexion**. Trois conséquences concrètes au Gîte :
 *
 * - Le serveur qui prend la relève au comptoir voisin ne voit ni le panier ni
 *   l'indisponibilité — il vend un plat que son collègue a retiré de la carte.
 * - Une session expirée efface un panier ouvert : le client a consommé, rien
 *   ne le porte plus, et RG-15 (une vente porte le nom de qui l'a encaissée)
 *   n'a plus d'objet.
 * - Rien n'est audité : `HasAuditColumns` ne s'applique qu'à une table.
 *
 * C'est aussi, de près, la famille PA-59/60/61 : un état affiché — « ce plat
 * est indisponible » — que rien de durable n'a enregistré.
 *
 * ## La liste des exceptions est FERMÉE, et chacune porte sa raison
 *
 * L'état d'un onglet ou un filtre d'affichage sont légitimes en session : ils
 * ne décrivent rien du monde, seulement ce que cet écran-ci montre à cette
 * personne-ci. Un panier, une affectation de guide, une indisponibilité de
 * carte décrivent le monde — ils vont en base.
 *
 * ⚠ **Une clé calculée est refusée par principe** (`Session::put($cle, …)`) :
 * personne ne peut relire ce qu'elle contient, donc personne ne peut décider
 * qu'elle est légitime. C'est précisément la forme du panier de séjour.
 *
 * ## Preuve que ce cas peut encore échouer, maintenant qu'il est vert
 *
 * Il était ROUGE au 31/08/2026 sur sept écritures reproduites, chacune nommée
 * fichier et ligne. Il n'en reste **aucune** : le balayage ne détecte plus rien
 * du tout, et un balayage qui ne détecte rien est vert **quelle que soit** la
 * raison — y compris parce que son motif a cessé de mordre. C'est le défaut
 * que ce dépôt a payé trois fois (un `\b` de regex devenu l'octet 0x08).
 *
 * Deux protections le tiennent, et la seconde est nouvelle :
 *
 * 1. `PLANCHER_FICHIERS` — le balayage doit lire les fichiers qu'il prétend
 *    lire. Un répertoire renommé le fait échouer.
 * 2. Le cas `le_motif_de_detection_mord_encore_sur_un_echantillon_fabrique`
 *    — les trois motifs sont éprouvés sur des lignes FABRIQUÉES, littérale et
 *    calculée. Il remplace le plancher d'écritures, qui ne pouvait plus rien
 *    tenir une fois tombé à zéro : sans lui, casser la détection rendrait
 *    cette garde verte et muette.
 *
 * @see docs/03_DATABASE_ENGINEERING.md §15
 * @see CLAUDE.md (PA-59/60/61 — l'indicateur qui affirme un état non vérifié)
 */
final class SessionSansDonneeMetierTest extends TestCase
{
    /**
     * Les seules clés de session autorisées, chacune avec sa raison.
     *
     * Elle est VIDE aujourd'hui, et ce n'est pas un oubli : aucune des quatre
     * clés écrites par la PWA ne porte de l'affichage. Une clé n'y entre
     * qu'accompagnée de la phrase qui explique pourquoi sa perte n'a aucune
     * conséquence pour l'établissement.
     *
     * Elle est rendue par une MÉTHODE plutôt que par une constante : une
     * constante littéralement vide est un type `array{}` pour l'analyse
     * statique, qui déclare alors que la recherche « sera toujours fausse » et
     * bloque le niveau 6. La liste doit pouvoir être vide sans que la garde
     * cesse de compiler.
     *
     * @return array<string, string> clé => raison
     */
    private function clesAutorisees(): array
    {
        return [
            // Exemple de ce qui serait recevable, si le besoin se presentait :
            // 'affichage_onglet_comptabilite' => "etat d'onglet : sa perte ne
            //     coute qu'un clic, et il ne decrit rien du monde reel",

            // Le drapeau des modales d'ouverture (02/09/2026) — la famille
            // meme que l'exemple ci-dessus : un etat d'AFFICHAGE par
            // connexion (« les alertes de cette connexion n'ont pas encore
            // ete montrees »), pose par `Connexion::seConnecter()` et
            // consomme par `AlertesOuvertureModales`. Sa perte ne coute que
            // le reaffichage — ou l'absence — des modales de CETTE session ;
            // il ne decrit rien du monde reel, et les gestes qu'elles
            // portent (check-out, relance) ecrivent, eux, dans de vraies
            // tables sous RBAC.
            'alertes_ouverture_en_attente' => 'drapeau d affichage des modales '
                . 'd ouverture, une fois par connexion — aucune donnee metier',

            // L'empreinte (HMAC) du mot de passe de chaque compte vu par cette
            // session (29/10/2026, mot de passe perdu SANS e-mail) : un etat de
            // SECURITE de la session, pose par `EmpreinteMotDePasseEnSession`.
            // Il sert a fermer la session d'un compte dont un administrateur a
            // reinitialise le mot de passe. Sa perte ne coute rien : la session
            // le repose a sa requete suivante ; il ne decrit rien du monde reel.
            'empreintes_mots_de_passe' => 'empreinte (HMAC) du mot de passe, pour '
                . 'fermer les sessions d un compte reinitialise — aucune donnee metier',
        ];
    }

    /**
     * Plancher mesuré le 31/08/2026 : 45 fichiers PHP sous `app/Pwa/Livewire/`.
     * Sans lui, un dossier renommé rendrait le balayage vide, donc vert — le
     * défaut même que cette garde protège (PA-131).
     */
    private const PLANCHER_FICHIERS = 35;

    /**
     * ⚠ RAMENÉ À 0 **VOLONTAIREMENT** le 31/08/2026, et la garde est devenue
     * PRÉVENTIVE — c'est très exactement le geste que la version précédente de
     * ce commentaire annonçait, et sous la condition qu'elle posait : « le jour
     * où il n'y en aura plus une seule ».
     *
     * Il valait 7 à l'écriture, puis 1 quand la seule écriture restante était
     * celle du panier de séjour, accordée par exception. Cette écriture a
     * disparu avec la table `paniers` (PA-161). Il n'y a plus rien à compter.
     *
     * Un plancher à zéro ne tient plus rien : c'est pourquoi le contrôle du
     * MOTIF est passé dans son propre cas, sur des lignes fabriquées. Sans ce
     * relais, la garde serait verte le jour où sa détection cesserait de
     * mordre — le défaut même qu'elle protège.
     */
    private const PLANCHER_ECRITURES = 0;

    /**
     * Les écritures de session ACCORDÉES — VIDE depuis le 31/08/2026.
     *
     * ## Ce qu'elle portait, et pourquoi elle est vide
     *
     * Une seule entrée : `PosHeberges.php`, expression `$this->clePanier(
     * $reservationId)`, accordée en attente de l'arbitrage Q2 de
     * `PROPOSITION_MODELE_PANIER_POS.md` — « un seul panier ouvert par séjour »
     * ne s'exprimant pas en contrainte sur MySQL, qui n'a pas d'index partiel.
     *
     * L'arbitrage est rendu (PA-161, option A), la table `paniers` existe, et
     * l'écriture de session a disparu avec elle. **L'exception a été retirée le
     * jour même** : une exception qui survit à sa raison transforme une
     * décision en oubli (PA-107, PA-120, PA-144), et personne ne rouvre la
     * question puisque la liste dit que le cas est réglé.
     *
     * ## Pourquoi une exception plutôt qu'un rouge permanent — la règle reste
     *
     * Une garde qui reste rouge sur un cas connu et accepté ne dit plus rien :
     * on apprend à ignorer sa ligne, et le jour où elle attrape un VRAI défaut,
     * personne ne regarde. Le nommer la remet en état de marche — et rend la
     * décision visible, ce qu'un rouge chronique ne fait pas. Une future entrée
     * porte donc SA DATE et SON EXPRESSION, jamais un nom de fichier seul :
     * l'exception dispense d'une ligne, pas d'un fichier.
     *
     * (Méthode et non constante, comme `clesAutorisees()` : PHPStan fige le
     * type d'une constante vide en `array{}` et déclare alors que toute
     * recherche dedans « sera toujours fausse », ce qui bloque le niveau 6. La
     * liste doit pouvoir être vide sans que la garde cesse de compiler.)
     *
     * @return array<string, array{expression: string, raison: string}>
     */
    private function exceptionsDatees(): array
    {
        return [];
    }

    #[Test]
    public function aucun_composant_pwa_n_ecrit_de_donnee_metier_en_session(): void
    {
        $fichiers = $this->fichiersDesComposants();

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_FICHIERS,
            count($fichiers),
            'Seuls '.count($fichiers).' fichiers relus (plancher '.self::PLANCHER_FICHIERS.
            ') : le balayage se vide, et un balayage vide est vert.',
        );

        $ecritures = 0;
        $fautives = [];

        foreach ($fichiers as $relatif => $chemin) {
            $lignes = $this->lignesDeCode($chemin);

            foreach ($lignes as $index => $ligne) {
                foreach ($this->clesEcrites($ligne) as $cle) {
                    $ecritures++;

                    if ($cle !== null && array_key_exists($cle, $this->clesAutorisees())) {
                        continue;
                    }

                    // Une ecriture EXPLICITEMENT accordee, en attente d'un
                    // arbitrage nomme et date (voir `exceptionsDatees()`).
                    $accordee = $this->exceptionsDatees()[$relatif] ?? null;

                    if ($accordee !== null && str_contains($ligne, $accordee['expression'])) {
                        continue;
                    }

                    $fautives[] = $relatif.':'.($index + 1).' → '
                        .($cle === null
                            ? 'cle CALCULEE (illisible, donc non relue — refusee par principe)'
                            : "cle « {$cle} »");
                }
            }
        }

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_ECRITURES,
            $ecritures,
            'Aucune ecriture de session detectee : le motif de detection ne mord plus. '
            .'Verifier `Session::put`, `session()->put` et `session([...])`.',
        );

        // Une exception qui a cesse d'etre necessaire est un oubli deguise en
        // decision (PA-107, PA-120, PA-144). Chacune doit donc porter sa date,
        // et designer une expression que le fichier contient REELLEMENT — sans
        // quoi elle dispenserait un code qui a change sous elle.
        foreach ($this->exceptionsDatees() as $relatif => $exception) {
            $this->assertMatchesRegularExpression(
                '#\b\d{2}/\d{2}/\d{4}\b#',
                $exception['raison'],
                "L exception accordee a {$relatif} n est pas datee : elle deviendra un oubli.",
            );

            $this->assertArrayHasKey(
                $relatif,
                $fichiers,
                "L exception accordee a {$relatif} designe un fichier qui n existe plus.",
            );

            $this->assertStringContainsString(
                $exception['expression'],
                (string) file_get_contents($fichiers[$relatif]),
                "L exception accordee a {$relatif} porte sur l expression « {$exception['expression']} », "
                .'que le fichier ne contient plus : la retirer, elle dispense desormais du vide.',
            );
        }

        $this->assertSame(
            [],
            $fautives,
            "Des composants de la PWA ecrivent une donnee metier dans la session HTTP.\n"
            ."Une session expire, est propre a un navigateur et disparait a la deconnexion :\n"
            ."le serveur du comptoir voisin ne voit rien, et rien n est audite.\n"
            ."La correction est une table, pas une cle plus longue.\n  "
            .implode("\n  ", $fautives),
        );
    }

    /**
     * Le motif de détection MORD encore — le relais du plancher tombé à zéro.
     *
     * Sans ce cas, la garde serait verte de deux façons indiscernables :
     * « aucun composant n'écrit en session » et « le motif ne reconnaît plus
     * une écriture de session ». Le dépôt a déjà payé trois fois la seconde.
     *
     * Les échantillons sont FABRIQUÉS ici, jamais lus du code : un échantillon
     * pris dans un fichier disparaîtrait avec lui, et le contrôle s'éteindrait
     * sans un mot. Les trois formes d'écriture sont couvertes, plus la
     * distinction qui fait tout le contrat — une clé littérale se relit, une
     * clé calculée ne se relit pas.
     */
    #[Test]
    public function le_motif_de_detection_mord_encore_sur_un_echantillon_fabrique(): void
    {
        $this->assertSame(
            ['panier_du_jour'],
            $this->clesEcrites('Session::put(\'panier_du_jour\', $panier);'),
        );
        $this->assertSame(
            ['panier_du_jour'],
            $this->clesEcrites('session()->put("panier_du_jour", $panier);'),
        );
        $this->assertSame(
            ['panier_du_jour'],
            $this->clesEcrites('session([\'panier_du_jour\' => $panier]);'),
        );

        // Une cle CALCULEE est refusee par principe : personne ne peut relire
        // ce qu'elle contient, donc personne ne peut decider qu'elle est
        // legitime. C'est la forme qu'avait le panier de sejour.
        $this->assertSame(
            [null],
            $this->clesEcrites('Session::put($this->clePanier($id), $panier);'),
        );

        // Et il ne mord pas sur une LECTURE : un motif qui refuserait tout
        // serait aussi inutile qu un motif qui n accepte rien.
        $this->assertSame([], $this->clesEcrites('$panier = Session::get(\'panier_du_jour\', []);'));
    }

    // ------------------------------------------------------------------ outils

    /**
     * Les lignes de CODE d'un fichier, commentaires effacés — sauts de ligne
     * conservés pour que le numéro rapporté reste celui du fichier.
     *
     * ⚠ Sans ce retrait, cette garde accusait `EcranDeCarte.php:376`, dont le
     * docblock explique que `CarteBar::enregistrerDispo()` **faisait**
     * `Session::put(...)` et ne le fait plus. Elle reprochait à un correctif
     * d'être documenté — et la seule façon de la faire taire aurait été de
     * supprimer l'explication. Même piège que dans `ChassisModalePwaTest` et
     * `MotifsInterditsPwaTest`, fermé le 31/08/2026 pour les trois.
     *
     * @return list<string>
     */
    private function lignesDeCode(string $chemin): array
    {
        $sortie = '';

        foreach (token_get_all((string) file_get_contents($chemin)) as $jeton) {
            if (! is_array($jeton)) {
                $sortie .= $jeton;

                continue;
            }

            if (in_array($jeton[0], [T_COMMENT, T_DOC_COMMENT], true)) {
                $sortie .= str_repeat("\n", substr_count($jeton[1], "\n"));

                continue;
            }

            $sortie .= $jeton[1];
        }

        return explode("\n", $sortie);
    }

    /**
     * Les clés écrites en session sur une ligne. `null` marque une clé
     * calculée, qu'aucune relecture ne peut approuver.
     *
     * @return list<string|null>
     */
    private function clesEcrites(string $ligne): array
    {
        $motifs = [
            '#Session::put\s*\(\s*([^,)]+)#',
            '#session\(\)\s*->\s*put\s*\(\s*([^,)]+)#',
            '#session\(\s*\[\s*([\'"][^\'"]+[\'"])#',
        ];

        $cles = [];

        foreach ($motifs as $motif) {
            if (preg_match_all($motif, $ligne, $trouves) < 1) {
                continue;
            }

            foreach ($trouves[1] as $argument) {
                $argument = trim($argument);

                if (preg_match('#^[\'"]([^\'"]*)[\'"]$#', $argument, $litteral) === 1) {
                    $cles[] = $litteral[1];
                } else {
                    $cles[] = null;
                }
            }
        }

        return $cles;
    }

    /**
     * @return array<string, string> chemin relatif => chemin absolu
     */
    private function fichiersDesComposants(): array
    {
        $racine = app_path('Pwa');

        $fichiers = [];
        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
        );

        /** @var \SplFileInfo $fichier */
        foreach ($iterateur as $fichier) {
            if (! $fichier->isFile() || $fichier->getExtension() !== 'php') {
                continue;
            }

            $absolu = (string) $fichier->getRealPath();
            $relatif = 'app/'.str_replace(
                [app_path().DIRECTORY_SEPARATOR, DIRECTORY_SEPARATOR],
                ['', '/'],
                $absolu,
            );

            $fichiers[$relatif] = $absolu;
        }

        ksort($fichiers);

        return $fichiers;
    }
}
