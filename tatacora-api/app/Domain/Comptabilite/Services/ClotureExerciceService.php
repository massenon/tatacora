<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * La CLÔTURE SYSCOHADA ANNUELLE — lot 2 (décisions du Product Owner du
 * 20/10/2026 : clôture annuelle seulement, réouverture par LE COMPTABLE).
 *
 * ## Le cycle d'un exercice
 *
 *     ouvert ──démarrer──▶ en_cloture ──clôturer──▶ cloture
 *       ▲                     │   ▲                     │
 *       └──reprendre saisie───┘   └───────rouvrir───────┘ (comptable, motif)
 *
 *  - **en_cloture** : les modules ne passent plus de pièce dans N (vente,
 *    dépense… : `PasserEcritureService` n'admet que `ouvert`) ; seules les
 *    écritures d'inventaire et de régularisation du comptable y entrent
 *    (`statuts_exercice_admis`). L'exercice N+1 est ouvert pour le
 *    quotidien — deux exercices vivent en même temps.
 *  - **clôturer** : la liste de contrôle d'`EtatClotureService` doit être
 *    réunie (balance et bilan équilibrés, aucun brouillon, journal AN,
 *    comptes 131/139, centre « Structure »), et N-1 déjà clôturé (les
 *    exercices se clôturent DANS L'ORDRE). Dans UNE transaction :
 *      1. pièce de clôture au 31/12/N (journal CL, de clôture) : chaque compte de
 *         gestion (classes 6, 7, 8) est soldé CENTRE PAR CENTRE — l'analytique
 *         de chaque centre retombe à zéro —, la contrepartie va en 131
 *         (bénéfice) ou 139 (perte), centre « Structure » ;
 *      2. pièce d'à-nouveaux au 01/01/N+1 (journal AN) : les soldes des
 *         comptes de bilan (classes 1 à 5, résultat compris) ;
 *      3. statut `cloture` (verrou définitif RG-11bis) ; trace au journal
 *         d'audit et dans `clotures_exercices`.
 *  - **rouvrir** (LE COMPTABLE seul, motif obligatoire) : les deux pièces
 *    sont CONTRE-PASSÉES à leur propre date (rien ne s'efface, RG-11) et
 *    l'exercice repasse `en_cloture` ; refusé si N+1 est déjà clôturé.
 *
 * Les à-nouveaux PROVISOIRES de N+1, tant que N n'est pas clôturé, ne
 * s'écrivent pas (une écriture ne se supprime jamais) : ils se CALCULENT
 * dans la balance de N+1 (`BalanceGeneraleService`), donc dans le bilan.
 *
 * @see EF-M10-07 Clôture d'exercice
 * @see RG-11 immutabilité des écritures validées
 */
class ClotureExerciceService
{
    /**
     * Un journal À PART pour le solde des comptes de gestion : les états
     * financiers d'un exercice clôturé (compte de résultat, bilan) se
     * calculent sans lui — ceux d'avant la clôture, comme il se doit.
     */
    public const JOURNAL_CLOTURE = 'CL';

    public const JOURNAL_A_NOUVEAUX = 'AN';

    /**
     * Les journaux que seule la clôture écrit : une saisie manuelle y est
     * refusée (une pièce passée à la main au journal CL disparaîtrait des
     * états, qui l'excluent).
     *
     * @var list<string>
     */
    public const JOURNAUX_RESERVES = [self::JOURNAL_CLOTURE, self::JOURNAL_A_NOUVEAUX];

    public const CENTRE_DE_CLOTURE = 'Structure';

    /** Décision du PO du 20/10/2026 : « Qui a le droit de rouvrir ? LE COMPTABLE ». */
    public const ROLE_REOUVERTURE = 'comptable';

    public const MOTIF_LONGUEUR_MIN = 10;

    /** Les classes de GESTION soldées à la clôture. */
    public const CLASSES_GESTION = ['6', '7', '8'];

    /** Les classes de BILAN reportées à nouveau. */
    public const CLASSES_BILAN = ['1', '2', '3', '4', '5'];

    private const PRECISION = 2;

    public function __construct(
        private readonly ExerciceComptableService $exercices,
        private readonly EtatClotureService $etat,
        private readonly PasserEcritureService $passer,
        private readonly BalanceGeneraleService $balance,
        private readonly CorrespondanceComptesService $comptes,
    ) {
    }

    /** ouvert → en_cloture ; ouvre N+1 s'il manque. */
    public function demarrer(ExerciceComptable $exercice, User $auteur): ExerciceComptable
    {
        if ($exercice->statut !== 'ouvert') {
            throw new RuntimeException(__('comptabilite.cloture_demarrage_impossible', [
                'annee' => (string) $exercice->annee,
                'statut' => $exercice->statut,
            ]));
        }

        return DB::transaction(function () use ($exercice, $auteur): ExerciceComptable {
            $this->exercices->assurer($exercice->annee + 1, 'demarrage_cloture');
            $exercice->update(['statut' => 'en_cloture']);
            $this->tracer('cloture_demarree', $exercice, $auteur, []);

            return $exercice->refresh();
        });
    }

    /** en_cloture → ouvert, tant que la clôture n'est pas passée. */
    public function reprendreSaisie(ExerciceComptable $exercice, User $auteur): ExerciceComptable
    {
        if ($exercice->statut !== 'en_cloture') {
            throw new RuntimeException(__('comptabilite.cloture_reprise_impossible', [
                'annee' => (string) $exercice->annee,
                'statut' => $exercice->statut,
            ]));
        }

        return DB::transaction(function () use ($exercice, $auteur): ExerciceComptable {
            $exercice->update(['statut' => 'ouvert']);
            $this->tracer('cloture_reprise_saisie', $exercice, $auteur, []);

            return $exercice->refresh();
        });
    }

    /**
     * La clôture DÉFINITIVE — voir l'entête.
     *
     * @throws RuntimeException statut, ordre des exercices, liste de contrôle
     */
    public function cloturer(ExerciceComptable $exercice, User $auteur): ClotureExercice
    {
        if ($exercice->statut !== 'en_cloture') {
            throw new RuntimeException(__('comptabilite.cloture_exige_en_cloture', ['annee' => (string) $exercice->annee]));
        }

        $precedent = ExerciceComptable::query()->where('annee', $exercice->annee - 1)->first();

        if ($precedent !== null && $precedent->statut !== 'cloture') {
            throw new RuntimeException(__('comptabilite.cloture_ordre', [
                'annee' => (string) $exercice->annee,
                'precedent' => (string) $precedent->annee,
            ]));
        }

        $etat = $this->etat->genererPourExercice($exercice, ['validee', 'brouillon']);

        if (! $etat->conditionsVerifiablesReunies) {
            throw new RuntimeException(__('comptabilite.cloture_conditions_non_reunies', [
                'annee' => (string) $exercice->annee,
                'blocages' => implode(', ', array_map(
                    static fn (string $b): string => (string) __('pwa.comptabilite.motifs.' . $b),
                    [...$etat->blocagesStructurels, ...$etat->blocagesDeDonnees],
                )),
            ]));
        }

        return DB::transaction(function () use ($exercice, $auteur): ClotureExercice {
            $suivant = $this->exercices->assurer($exercice->annee + 1, 'cloture');

            if ($suivant->statut === 'cloture') {
                throw new RuntimeException(__('comptabilite.cloture_suivant_clos', ['annee' => (string) $suivant->annee]));
            }

            $structure = (string) CentreCout::query()->where('libelle', self::CENTRE_DE_CLOTURE)->value('id');

            // 1. Le solde des comptes de gestion, centre par centre.
            [$lignesCloture, $resultat] = $this->lignesDeCloture($exercice->id, $structure);
            $pieceCloture = null;

            if ($lignesCloture !== []) {
                $pieceCloture = (string) $this->passer->passerEtValider([
                    'journal' => self::JOURNAL_CLOTURE,
                    'date' => sprintf('%d-12-31', $exercice->annee),
                    'libelle' => (string) __('comptabilite.libelle_piece_cloture', ['annee' => (string) $exercice->annee]),
                    'lignes' => $lignesCloture,
                    'statuts_exercice_admis' => ['en_cloture'],
                ])->first()->numero_piece;
            }

            // 2. Les à-nouveaux : les soldes de bilan APRÈS la clôture.
            $lignesAn = $this->lignesANouveaux($exercice->id, $structure);
            $pieceAn = null;

            if ($lignesAn !== []) {
                $pieceAn = (string) $this->passer->passerEtValider([
                    'journal' => self::JOURNAL_A_NOUVEAUX,
                    'date' => sprintf('%d-01-01', $exercice->annee + 1),
                    'libelle' => (string) __('comptabilite.libelle_piece_a_nouveaux', ['annee' => (string) $exercice->annee]),
                    'lignes' => $lignesAn,
                    'statuts_exercice_admis' => ['ouvert', 'en_cloture'],
                ])->first()->numero_piece;
            }

            // 3. Le verrou définitif.
            $exercice->update([
                'statut' => 'cloture',
                'date_cloture' => now(),
                'utilisateur_cloture_id' => $auteur->id,
            ]);

            $cloture = ClotureExercice::create([
                'exercice_id' => $exercice->id,
                'piece_cloture' => $pieceCloture,
                'piece_a_nouveaux' => $pieceAn,
                'resultat' => $resultat,
                'cloturee_par' => $auteur->id,
                'cloturee_le' => now(),
            ]);

            $this->tracer('exercice_cloture', $exercice, $auteur, [
                'resultat' => $resultat,
                'piece_cloture' => $pieceCloture,
                'piece_a_nouveaux' => $pieceAn,
            ]);

            return $cloture;
        });
    }

    /**
     * La RÉOUVERTURE contrôlée — le comptable seul, motif obligatoire.
     *
     * @throws RuntimeException rôle, statut, motif, N+1 clôturé
     */
    public function rouvrir(ExerciceComptable $exercice, User $auteur, string $motif): ExerciceComptable
    {
        if ($auteur->role?->libelle !== self::ROLE_REOUVERTURE) {
            throw new RuntimeException(__('comptabilite.reouverture_reservee'));
        }

        if ($exercice->statut !== 'cloture') {
            throw new RuntimeException(__('comptabilite.reouverture_non_cloture', ['annee' => (string) $exercice->annee]));
        }

        $motif = trim($motif);

        if (mb_strlen($motif) < self::MOTIF_LONGUEUR_MIN) {
            throw new RuntimeException(__('comptabilite.reouverture_motif', ['min' => self::MOTIF_LONGUEUR_MIN]));
        }

        $suivant = ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();

        if ($suivant !== null && $suivant->statut === 'cloture') {
            throw new RuntimeException(__('comptabilite.reouverture_suivant_clos', [
                'annee' => (string) $exercice->annee,
                'suivant' => (string) $suivant->annee,
            ]));
        }

        return DB::transaction(function () use ($exercice, $auteur, $motif, $suivant): ExerciceComptable {
            // D'abord le statut : une contre-passation ne s'écrit pas dans un
            // exercice clôturé (RG-11bis).
            $exercice->update(['statut' => 'en_cloture', 'date_cloture' => null, 'utilisateur_cloture_id' => null]);

            $cloture = ClotureExercice::query()
                ->where('exercice_id', $exercice->id)
                ->whereNull('rouverte_le')
                ->latest('cloturee_le')
                ->first();

            $libelle = (string) __('comptabilite.libelle_reouverture', ['annee' => (string) $exercice->annee, 'motif' => $motif]);

            if ($cloture !== null) {
                $this->contrePasser($exercice->id, $cloture->piece_cloture, $libelle);

                if ($suivant !== null) {
                    $this->contrePasser($suivant->id, $cloture->piece_a_nouveaux, $libelle);
                }

                $cloture->update([
                    'rouverte_par' => $auteur->id,
                    'rouverte_le' => now(),
                    'motif_reouverture' => $motif,
                ]);
            }

            $this->tracer('exercice_rouvert', $exercice, $auteur, ['motif' => $motif]);

            return $exercice->refresh();
        });
    }

    /** La clôture ACTIVE de l'exercice, ou `null`. */
    public function clotureActive(string $exerciceId): ?ClotureExercice
    {
        return ClotureExercice::query()
            ->where('exercice_id', $exerciceId)
            ->whereNull('rouverte_le')
            ->latest('cloturee_le')
            ->first();
    }

    /**
     * Les lignes qui soldent les comptes de gestion, centre par centre, et la
     * contrepartie en 131 (bénéfice) ou 139 (perte).
     *
     * @return array{0: list<array<string, string>>, 1: string} lignes, résultat (signé)
     */
    private function lignesDeCloture(string $exerciceId, string $structure): array
    {
        $soldes = DB::table('ecritures_comptables as e')
            ->join('plan_comptable as p', 'e.compte_id', '=', 'p.id')
            ->where('e.exercice_id', $exerciceId)
            ->where('e.statut', 'validee')
            ->whereIn('p.classe', self::CLASSES_GESTION)
            ->groupBy('p.numero_compte', 'e.centre_id')
            ->orderBy('p.numero_compte')
            ->selectRaw('p.numero_compte AS numero, e.centre_id AS centre, SUM(e.debit) AS d, SUM(e.credit) AS c')
            ->get();

        $lignes = [];
        $debits = '0.00';
        $credits = '0.00';

        foreach ($soldes as $solde) {
            $net = bcsub((string) $solde->d, (string) $solde->c, self::PRECISION);
            $signe = bccomp($net, '0.00', self::PRECISION);

            if ($signe === 0) {
                continue;
            }

            // Le solde est INVERSÉ : un compte débiteur (charge) est crédité.
            $montant = $signe > 0 ? $net : bcsub('0.00', $net, self::PRECISION);
            $lignes[] = [
                'compte' => (string) $solde->numero,
                'centre_id' => (string) $solde->centre,
                'debit' => $signe < 0 ? $montant : '0.00',
                'credit' => $signe > 0 ? $montant : '0.00',
            ];
            $debits = bcadd($debits, $signe < 0 ? $montant : '0.00', self::PRECISION);
            $credits = bcadd($credits, $signe > 0 ? $montant : '0.00', self::PRECISION);
        }

        // Débits (produits soldés) − crédits (charges soldées) = le résultat.
        $resultat = bcsub($debits, $credits, self::PRECISION);
        $signe = bccomp($resultat, '0.00', self::PRECISION);

        if ($signe > 0) {
            $lignes[] = ['compte' => $this->comptes->compte('RESULTAT_BENEFICE'), 'centre_id' => $structure, 'debit' => '0.00', 'credit' => $resultat];
        } elseif ($signe < 0) {
            $lignes[] = ['compte' => $this->comptes->compte('RESULTAT_PERTE'), 'centre_id' => $structure, 'debit' => bcsub('0.00', $resultat, self::PRECISION), 'credit' => '0.00'];
        }

        return [$lignes, $resultat];
    }

    /**
     * Les soldes des comptes de BILAN de l'exercice (classes 1 à 5), à-nouveaux
     * provisoires de l'exercice précédent compris — ceux que la balance
     * calcule tant que ce dernier n'a pas de clôture active.
     *
     * @return list<array<string, string>>
     */
    private function lignesANouveaux(string $exerciceId, string $structure): array
    {
        $balance = $this->balance->genererPourExercice($exerciceId, ['validee'], apresCloture: true);
        $lignes = [];

        foreach ($balance->lignes as $ligne) {
            if (! in_array($ligne->classe, self::CLASSES_BILAN, true)) {
                continue;
            }

            $net = bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION);
            $signe = bccomp($net, '0.00', self::PRECISION);

            if ($signe === 0) {
                continue;
            }

            $montant = $signe > 0 ? $net : bcsub('0.00', $net, self::PRECISION);
            $lignes[] = [
                'compte' => $ligne->numeroCompte,
                'centre_id' => $structure,
                'debit' => $signe > 0 ? $montant : '0.00',
                'credit' => $signe < 0 ? $montant : '0.00',
            ];
        }

        return $lignes;
    }

    /**
     * Contre-passe une pièce à SA date, dans SON exercice : chaque ligne
     * inversée, liée à l'origine (`ecriture_contrepassee_id`), validée.
     */
    private function contrePasser(string $exerciceId, ?string $numeroPiece, string $libelle): void
    {
        if ($numeroPiece === null) {
            return;
        }

        $lignes = EcritureComptable::query()
            ->where('exercice_id', $exerciceId)
            ->where('numero_piece', $numeroPiece)
            ->whereNull('ecriture_contrepassee_id')
            ->get();

        foreach ($lignes as $ligne) {
            if (EcritureComptable::query()->where('ecriture_contrepassee_id', $ligne->id)->exists()) {
                continue;
            }

            EcritureComptable::create([
                'exercice_id' => $ligne->exercice_id,
                'journal_id' => $ligne->journal_id,
                'compte_id' => $ligne->compte_id,
                'centre_id' => $ligne->centre_id,
                'date_ecriture' => $ligne->date_ecriture->toDateString(),
                'libelle' => $libelle,
                'debit' => $ligne->credit,
                'credit' => $ligne->debit,
                'ecriture_contrepassee_id' => $ligne->id,
                'statut' => 'validee',
            ]);
        }
    }

    /** @param array<string, mixed> $details */
    private function tracer(string $action, ExerciceComptable $exercice, User $auteur, array $details): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $auteur->id,
            'action' => $action,
            'entite_concernee' => 'exercices_comptables',
            'entite_id' => $exercice->id,
            'valeur_avant' => null,
            'valeur_apres' => ['annee' => $exercice->annee, 'statut' => $exercice->statut, ...$details],
            'adresse_poste' => request()->ip(),
        ]);
    }
}
