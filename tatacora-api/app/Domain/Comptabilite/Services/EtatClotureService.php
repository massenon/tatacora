<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\ReadModels\EtapeCloture;
use App\Domain\Comptabilite\ReadModels\EtatCloture;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use Illuminate\Support\Facades\DB;

/**
 * L'ETAT de la procedure de cloture — jamais la cloture elle-meme.
 *
 * @see EF-M10-07 Cloture comptable periodique avec verrouillage
 *
 * Transcription de la checklist de `m10-cloture.html`, qui suit la sequence
 * obligatoire de `MODULE_COMPTABILITE_COMPLET_PART4.md` §2.1. Ce service LIT :
 * il n'ecrit rien, ne change aucun statut d'exercice, et ne solde aucun compte.
 * Voir l'entete de `EtatCloture` pour les trois raisons structurelles.
 *
 * ## L'IS est un AVERTISSEMENT, et la contradiction du maitre est signalee
 *
 * `m10-cloture.html` l.100 marque l'etape 3c « BLOQUÉ par PA-19 ».
 * `comptabilite-engine.js` l.911-917 — le moteur du hub, que le maitre lui-meme
 * designe comme la version fonctionnelle — en fait un avertissement NON
 * bloquant. Les deux pages du maitre se contredisent.
 *
 * L'avertissement est retenu, pour deux raisons : le hub fait foi sur ce point
 * (`m10-comptabilite.html` l.20-24 renvoie explicitement vers lui), et surtout
 * la cloture est de toute facon impossible ici pour des raisons structurelles
 * qui, elles, ne sont contestees par aucune des deux pages. Le choix n'a donc
 * aucun effet operationnel aujourd'hui. La contradiction est portee au rapport
 * de lot plutot que tranchee seule (Article 8).
 */
class EtatClotureService
{
    private const PRECISION = 2;

    /** Cf. `MODULE_COMPTABILITE_COMPLET_PART4.md` §2.2 — benefice / perte. */
    private const COMPTE_BENEFICE = ComptesSyscohada::RESULTAT_BENEFICE;

    private const COMPTE_PERTE = ComptesSyscohada::RESULTAT_PERTE;

    public const BLOCAGE_JOURNAL_AN_ABSENT = 'journal_a_nouveaux_absent';

    public const BLOCAGE_COMPTES_RESULTAT_ABSENTS = 'comptes_de_resultat_absents';

    public const BLOCAGE_CENTRE_STRUCTURE_ABSENT = 'centre_de_cloture_absent';

    /** Le centre qui porte les ecritures de cloture — PART4 §2.2. */
    private const CENTRE_DE_CLOTURE = 'Structure';

    /**
     * Les deux limites qui NE SONT PAS VERIFIABLES A L'EXECUTION, et qui sont
     * donc litterales — nommees comme telles plutot que deguisees en controle.
     *
     * - `report_a_nouveau_absent` : c'est un fait de CODE, pas de donnees. La
     *   Partie 4 §2.1 etape 6 decrit le report a nouveau ; aucun service ne
     *   l'implemente. Aucune requete ne peut constater l'absence d'un
     *   mecanisme — au mieux constaterait-elle qu'aucune ecriture de report
     *   n'existe, ce qui est vrai aussi d'un exercice inaugural parfaitement
     *   sain. Confondre les deux ferait accuser les donnees d'un manque qui est
     *   celui du logiciel.
     * - `perimetre_cloture_non_arbitre` : c'est un fait d'ARBITRAGE (PA-28).
     *   « Cloture Periodique » (mensuelle) et « Cloture d'Exercice » (annuelle)
     *   restent deux concepts distincts non tranches — le maitre l'ecrit en
     *   tete de sa page. Aucune donnee ne peut trancher une question qui n'a
     *   pas ete posee.
     *
     * Elles sont rendues a part de `blocagesStructurels`, qui ne contient que
     * du verifie. Les melanger aurait fait passer pour un constat ce qui est
     * une declaration, et fige `conditionsVerifiablesReunies` a `false` pour
     * toujours.
     *
     * @var list<string>
     */
    public const LIMITES_NON_VERIFIABLES = [
        'report_a_nouveau_absent',
        'perimetre_cloture_non_arbitre',
    ];

    public const BLOCAGE_ECRITURES_BROUILLON = 'ecritures_en_brouillon';

    public const BLOCAGE_BALANCE_DESEQUILIBREE = 'balance_desequilibree';

    public const BLOCAGE_BILAN_DESEQUILIBRE = 'bilan_desequilibre';

    public const AVERTISSEMENT_IMPOT = 'impot_non_comptabilise';

    public const AVERTISSEMENT_RAPPROCHEMENT = 'releves_bancaires_non_rapproches';

    public const MOTIF_INVENTAIRE_HORS_DOMAINE = 'inventaire_physique_hors_domaine_m10';

    public const MOTIF_ACTION_SERVEUR_NON_EXPOSEE = 'action_de_cloture_non_exposee';

    public const MOTIF_DEPEND_ETAPE_PRECEDENTE = 'depend_d_une_etape_non_atteinte';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly BilanService $bilan,
        private readonly TafireService $tafire,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        ExerciceComptable $exercice,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): EtatCloture {
        $balance = $this->balance->genererPourExercice($exercice->id, $statuts, $filtreStatut);
        $bilan = $this->bilan->genererPourExercice($exercice->id, $statuts, $filtreStatut);
        $tafire = $this->tafire->genererPourExercice($exercice->id, $statuts, $filtreStatut);

        $brouillons = $balance->statuts->brouillon;

        // Le journal d'a-nouveaux : la Partie 4 §2.1 etape 6 y date les
        // ecritures de report. `journaux_comptables` ne porte que VTE, ACH, BQ,
        // CAI et OD — on le VERIFIE en base plutot que de l'affirmer, parce
        // qu'un journal AN ajoute demain doit lever ce blocage tout seul.
        $journalAnexiste = JournalComptable::query()->where('code', 'AN')->exists();

        // `releves_bancaires` appartient a M10 (meme migration). Lecture par
        // requete directe plutot que par un modele : c'est un decompte, et
        // introduire un modele Eloquent pour lui ouvrirait une surface
        // d'ecriture sur une table que ce lot ne doit pas toucher.
        $nonRapproches = (int) DB::table('releves_bancaires')
            ->where('statut_rapprochement', 'non_rapproche')
            ->count();

        // --- Les blocages REELLEMENT VERIFIES a l'execution ---
        //
        // `MODULE_COMPTABILITE_COMPLET_PART4.md` §2.2 nomme les trois elements
        // de referentiel sans lesquels la cloture leve : le journal ou dater
        // les ecritures, les deux comptes de resultat qui recoivent le solde,
        // et le centre de cout qui porte ces ecritures. Les VERIFIER plutot que
        // les supposer est ce qui rend cette liste utile : le jour ou l'un
        // d'eux sera cree, il disparaitra de la liste tout seul.
        $blocagesStructurels = [];

        if (! $journalAnexiste) {
            $blocagesStructurels[] = self::BLOCAGE_JOURNAL_AN_ABSENT;
        }

        $comptesDeResultatPresents = CompteComptable::query()
            ->whereIn('numero_compte', [self::COMPTE_BENEFICE, self::COMPTE_PERTE])
            ->count() === 2;

        if (! $comptesDeResultatPresents) {
            $blocagesStructurels[] = self::BLOCAGE_COMPTES_RESULTAT_ABSENTS;
        }

        if (! CentreCout::query()->where('libelle', self::CENTRE_DE_CLOTURE)->exists()) {
            $blocagesStructurels[] = self::BLOCAGE_CENTRE_STRUCTURE_ABSENT;
        }

        $blocagesDeDonnees = [];

        if ($brouillons > 0) {
            $blocagesDeDonnees[] = self::BLOCAGE_ECRITURES_BROUILLON;
        }

        if (! $balance->equilibree) {
            $blocagesDeDonnees[] = self::BLOCAGE_BALANCE_DESEQUILIBREE;
        }

        if (! $bilan->equilibre) {
            $blocagesDeDonnees[] = self::BLOCAGE_BILAN_DESEQUILIBRE;
        }

        $avertissements = [];

        if ($bilan->impotNonComptabilise) {
            $avertissements[] = self::AVERTISSEMENT_IMPOT;
        }

        if ($nonRapproches > 0) {
            $avertissements[] = self::AVERTISSEMENT_RAPPROCHEMENT;
        }

        $etapes = $this->etapes($balance->equilibree, $balance->totalDebit, $brouillons, $nonRapproches, $bilan->equilibre, $bilan->resultatExercice, $tafire->coherent);

        return new EtatCloture(
            exerciceId: $exercice->id,
            annee: $exercice->annee,
            statutExercice: $exercice->statut,
            etapes: $etapes,
            blocagesStructurels: $blocagesStructurels,
            blocagesDeDonnees: $blocagesDeDonnees,
            limitesNonVerifiables: self::LIMITES_NON_VERIFIABLES,
            avertissements: $avertissements,
            // Il porte SEULEMENT ce qui a ete reellement verifie ici — le
            // referentiel de cloture et l'etat des ecritures. Il peut donc
            // valoir `true`, et le dire aurait un sens.
            //
            // Y melanger `LIMITES_NON_VERIFIABLES` le figerait a `false` par
            // construction : le champ n'apprendrait plus rien, et affirmerait
            // un etat qu'aucun controle n'aurait produit — la forme meme de
            // PA-59/60/61. Ce sont deux questions differentes, rendues
            // separement : « les conditions constatables sont-elles reunies ? »
            // d'un cote, « la cloture est-elle implementable ? » de l'autre,
            // cette seconde etant portee par `actionExposee`.
            conditionsVerifiablesReunies: $blocagesStructurels === [] && $blocagesDeDonnees === [],
            // Toujours `false`, et assume comme tel : ce n'est pas le resultat
            // d'un calcul mais la transcription du maitre, qui ne porte aucun
            // bouton sur cette page. `LIMITES_NON_VERIFIABLES` en donne les
            // raisons.
            actionExposee: false,
            resultatAReporter: $bilan->resultatExercice,
            compteDeDestination: bccomp($bilan->resultatExercice, '0.00', self::PRECISION) >= 0
                ? self::COMPTE_BENEFICE
                : self::COMPTE_PERTE,
            impotNonComptabilise: $bilan->impotNonComptabilise,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * Les six blocs de `m10-cloture.html`, dans son ordre.
     *
     * @return list<EtapeCloture>
     */
    private function etapes(
        bool $balanceEquilibree,
        string $totalDebit,
        int $brouillons,
        int $nonRapproches,
        bool $bilanEquilibre,
        string $resultat,
        bool $tafireCoherent,
    ): array {
        $g1 = 'Vérification pré-clôture';
        $g2 = "Passage en statut 'en_cloture'";
        $g3 = 'Écritures de clôture';
        $g4 = 'Contrôle post-clôture';
        $g5 = "Passage en statut 'cloture' (verrou définitif)";
        $g6 = 'Bilan actuel (pour référence, hors séquence de clôture)';

        return [
            new EtapeCloture(1, $g1, 'Balance Générale équilibrée', $balanceEquilibree
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE, valeur: $totalDebit),
            new EtapeCloture(1, $g1, 'Aucune écriture en brouillon', $brouillons === 0
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE, valeur: (string) $brouillons),
            new EtapeCloture(
                1,
                $g1,
                'Inventaire physique réconcilié avec le stock théorique (M6)',
                EtatCloture::ETAT_NON_VERIFIABLE,
                motif: self::MOTIF_INVENTAIRE_HORS_DOMAINE,
            ),
            new EtapeCloture(1, $g1, 'Rapprochement bancaire à jour', $nonRapproches === 0
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE, valeur: (string) $nonRapproches),

            new EtapeCloture(
                2,
                $g2,
                'Bloque toute nouvelle saisie sur l\'exercice',
                EtatCloture::ETAT_NON_ATTEINT,
                motif: self::MOTIF_ACTION_SERVEUR_NON_EXPOSEE,
            ),

            new EtapeCloture(
                3,
                $g3,
                'Dotations aux amortissements de l\'exercice',
                EtatCloture::ETAT_NON_VERIFIABLE,
                motif: self::MOTIF_INVENTAIRE_HORS_DOMAINE,
            ),
            new EtapeCloture(
                3,
                $g3,
                'Calcul du résultat net',
                EtatCloture::ETAT_CONFORME,
                valeur: $resultat,
            ),
            new EtapeCloture(
                3,
                $g3,
                'Solde des comptes de gestion (classes 6/7 → 131/139)',
                EtatCloture::ETAT_BLOQUE,
                motif: self::LIMITES_NON_VERIFIABLES[0],
            ),

            new EtapeCloture(
                4,
                $g4,
                'Comptes de classes 6/7 à solde zéro',
                EtatCloture::ETAT_NON_ATTEINT,
                motif: self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),
            new EtapeCloture(
                4,
                $g4,
                'Compte 131/139 = résultat net calculé',
                EtatCloture::ETAT_NON_ATTEINT,
                motif: self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),

            new EtapeCloture(
                5,
                $g5,
                'Verrou définitif RG-11bis',
                EtatCloture::ETAT_NON_ATTEINT,
                motif: self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),

            new EtapeCloture(6, $g6, 'Bilan équilibré', $bilanEquilibre
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE),
            new EtapeCloture(6, $g6, 'TAFIRE cohérent (variation calculée = réelle)', $tafireCoherent
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE),
        ];
    }
}
