<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\ReadModels\EtapeCloture;
use App\Domain\Comptabilite\ReadModels\EtatCloture;
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

    /**
     * Cf. `MODULE_COMPTABILITE_COMPLET_PART4.md` §2.2 — bénéfice / perte : les
     * rôles `RESULTAT_BENEFICE` et `RESULTAT_PERTE` de la correspondance des
     * comptes (modifiable depuis le 26/10/2026), lus au moment de l'état.
     */
    public const BLOCAGE_JOURNAL_AN_ABSENT = 'journal_a_nouveaux_absent';

    public const BLOCAGE_COMPTES_RESULTAT_ABSENTS = 'comptes_de_resultat_absents';

    public const BLOCAGE_CENTRE_STRUCTURE_ABSENT = 'centre_de_cloture_absent';

    /** Le centre qui porte les ecritures de cloture — PART4 §2.2. */
    private const CENTRE_DE_CLOTURE = 'Structure';

    /**
     * Les limites NON VÉRIFIABLES À L'EXÉCUTION, littérales — nommées comme
     * telles plutôt que déguisées en contrôle. Il y en avait deux jusqu'au
     * 20/10/2026 : `report_a_nouveau_absent` (aucun mécanisme de report) et
     * `perimetre_cloture_non_arbitre` (PA-28). Le lot 2 les a levées toutes
     * deux — clôture ANNUELLE arbitrée par le PO, report au journal AN par
     * `ClotureExerciceService` — et la liste est vide. Elle reste pour la
     * prochaine limite qui ne se constaterait dans aucune table.
     *
     * @var list<string>
     */
    public const LIMITES_NON_VERIFIABLES = [];

    public const BLOCAGE_ECRITURES_BROUILLON = 'ecritures_en_brouillon';

    public const BLOCAGE_BALANCE_DESEQUILIBREE = 'balance_desequilibree';

    public const BLOCAGE_BILAN_DESEQUILIBRE = 'bilan_desequilibre';

    public const AVERTISSEMENT_IMPOT = 'impot_non_comptabilise';

    public const AVERTISSEMENT_RAPPROCHEMENT = 'releves_bancaires_non_rapproches';

    public const MOTIF_INVENTAIRE_HORS_DOMAINE = 'inventaire_physique_hors_domaine_m10';

    public const MOTIF_DEPEND_ETAPE_PRECEDENTE = 'depend_d_une_etape_non_atteinte';

    /** Lot 2 (20/10/2026) : l'étape attend le geste de l'onglet Clôtures. */
    public const MOTIF_CLOTURE_NON_DEMARREE = 'cloture_non_demarree';

    public const MOTIF_CLOTURE_NON_PASSEE = 'cloture_non_passee';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly BilanService $bilan,
        private readonly TafireService $tafire,
        private readonly CorrespondanceComptesService $comptes,
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
        $journalAnexiste = JournalComptable::query()->whereIn('code', ['AN', 'CL'])->count() === 2;

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

        $compteBenefice = $this->comptes->compte('RESULTAT_BENEFICE');
        $comptePerte = $this->comptes->compte('RESULTAT_PERTE');

        $comptesDeResultatPresents = CompteComptable::query()->where('numero_compte', $compteBenefice)->exists()
            && CompteComptable::query()->where('numero_compte', $comptePerte)->exists();

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

        // Lot 2 (20/10/2026) : les étapes 2 à 5 se lisent sur la clôture
        // RÉELLE — le statut de l'exercice et la clôture active
        // (`ClotureExerciceService`), plus sur une déclaration.
        $clotureActive = ClotureExercice::query()
            ->where('exercice_id', $exercice->id)
            ->whereNull('rouverte_le')
            ->latest('cloturee_le')
            ->first();
        $gestionSoldee = $clotureActive !== null && $this->comptesDeGestionSoldes($exercice->id);

        $etapes = $this->etapes($balance->equilibree, $balance->totalDebit, $brouillons, $nonRapproches, $bilan->equilibre, $bilan->resultatExercice, $tafire->coherent, $exercice->statut, $clotureActive, $gestionSoldee);

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
            // Lot 2 (20/10/2026) : la clôture est exposée — onglet « Clôtures »
            // du hub (`Hub::cloturerExercice`, `ClotureExerciceService`).
            actionExposee: true,
            resultatAReporter: $bilan->resultatExercice,
            compteDeDestination: bccomp($bilan->resultatExercice, '0.00', self::PRECISION) >= 0
                ? $compteBenefice
                : $comptePerte,
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
        string $statut,
        ?ClotureExercice $cloture,
        bool $gestionSoldee,
    ): array {
        $demarree = in_array($statut, ['en_cloture', 'cloture'], true);
        $attente = $demarree ? self::MOTIF_CLOTURE_NON_PASSEE : self::MOTIF_CLOTURE_NON_DEMARREE;

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
                $demarree ? EtatCloture::ETAT_CONFORME : EtatCloture::ETAT_NON_ATTEINT,
                motif: $demarree ? null : self::MOTIF_CLOTURE_NON_DEMARREE,
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
                $cloture !== null ? EtatCloture::ETAT_CONFORME : EtatCloture::ETAT_NON_ATTEINT,
                valeur: $cloture?->piece_cloture,
                motif: $cloture !== null ? null : $attente,
            ),
            new EtapeCloture(
                3,
                $g3,
                'Report à nouveau des comptes de bilan (journal AN, 1er janvier suivant)',
                $cloture !== null ? EtatCloture::ETAT_CONFORME : EtatCloture::ETAT_NON_ATTEINT,
                valeur: $cloture?->piece_a_nouveaux,
                motif: $cloture !== null ? null : $attente,
            ),

            new EtapeCloture(
                4,
                $g4,
                'Comptes de classes 6/7 à solde zéro',
                match (true) {
                    $cloture === null => EtatCloture::ETAT_NON_ATTEINT,
                    $gestionSoldee => EtatCloture::ETAT_CONFORME,
                    default => EtatCloture::ETAT_BLOQUE,
                },
                motif: $cloture !== null ? null : self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),
            new EtapeCloture(
                4,
                $g4,
                'Compte 131/139 = résultat net calculé',
                match (true) {
                    $cloture === null => EtatCloture::ETAT_NON_ATTEINT,
                    bccomp((string) $cloture->resultat, $resultat, self::PRECISION) === 0 => EtatCloture::ETAT_CONFORME,
                    default => EtatCloture::ETAT_BLOQUE,
                },
                valeur: $cloture === null ? null : (string) $cloture->resultat,
                motif: $cloture !== null ? null : self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),

            new EtapeCloture(
                5,
                $g5,
                'Verrou définitif RG-11bis',
                $statut === 'cloture' ? EtatCloture::ETAT_CONFORME : EtatCloture::ETAT_NON_ATTEINT,
                motif: $statut === 'cloture' ? null : self::MOTIF_DEPEND_ETAPE_PRECEDENTE,
            ),

            new EtapeCloture(6, $g6, 'Bilan équilibré', $bilanEquilibre
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE),
            new EtapeCloture(6, $g6, 'TAFIRE cohérent (variation calculée = réelle)', $tafireCoherent
                ? EtatCloture::ETAT_CONFORME
                : EtatCloture::ETAT_BLOQUE),
        ];
    }

    /**
     * Après la pièce de clôture, les classes 6 à 8 sont-elles toutes à solde
     * nul ? Lu sur la balance APRÈS clôture (journal CL compris).
     */
    private function comptesDeGestionSoldes(string $exerciceId): bool
    {
        $apres = $this->balance->genererPourExercice($exerciceId, ['validee'], apresCloture: true);

        foreach ($apres->lignes as $ligne) {
            if (in_array(substr($ligne->numeroCompte, 0, 1), ['6', '7', '8'], true)
                && bccomp($ligne->soldeDebiteur, $ligne->soldeCrediteur, self::PRECISION) !== 0) {
                return false;
            }
        }

        return true;
    }
}
