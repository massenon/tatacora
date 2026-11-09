<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * L'AFFECTATION DU RÉSULTAT d'un exercice CLÔTURÉ (SYSCOHADA révisé) — demande
 * du Product Owner du 09/11/2026 : « ajoute l'affectation du résultat ».
 *
 * ## Pourquoi cette fonction manquait
 *
 * La clôture de N-1 laisse le résultat en 131 (bénéfice) ou 139 (perte), puis
 * l'à-nouveau le reporte dans N. Faute d'affectation, il y reste et se cumule
 * avec le résultat de N. L'assemblée qui approuve les comptes décide de son
 * sort : réserves, dividendes, report à nouveau. Cette décision est une PIÈCE
 * comptable DATÉE DANS N (date d'approbation des comptes), jamais dans N-1 (déjà
 * clôturé, immuable).
 *
 * ## La pièce
 *
 * Journal OD (aucun journal propre : une affectation est une opération diverse),
 * passée et validée par `PasserEcritureService` — le service d'écriture UNIQUE,
 * jamais un INSERT direct —, donc immuable (RG-11) : on la corrige par
 * contre-passation ({@see self::contrepasser()}).
 *
 *  - bénéfice : DÉBIT 131 du résultat ; CRÉDIT réserve légale (111), autres
 *    réserves (118x), dividendes à payer (465), report à nouveau créditeur (121) ;
 *  - perte : CRÉDIT 139 du résultat ; DÉBIT report à nouveau débiteur (129x),
 *    ou imputation sur les autres réserves (118x) / le report à nouveau
 *    créditeur (121).
 *
 * Les numéros de compte viennent de la correspondance PARAMÉTRABLE
 * (`CorrespondanceComptesService`), jamais en dur. Le centre de coût est celui
 * de la clôture (« Structure »).
 *
 * ## Les règles de contrôle (phrases dans `lang/fr/comptabilite.php`)
 *
 *  1. le comptable seul (même droit que la réouverture) ;
 *  2. l'exercice N-1 est CLÔTURÉ, avec une clôture active : le montant est lu
 *     sur `clotures_exercices.resultat`, jamais recalculé ; un résultat nul ne
 *     s'affecte pas ;
 *  3. UNE seule affectation ACTIVE par exercice (une contre-passée peut être
 *     refaite) — la ligne d'exercice est verrouillée pendant le contrôle ;
 *  4. la date est celle de l'approbation : dans l'exercice N (celui qui suit),
 *     OUVERT ;
 *  5. aucun montant négatif ; la SOMME des ventilations égale EXACTEMENT le
 *     résultat ; pas de dividende ni de réserve légale sur une perte ;
 *     l'imputation d'une perte sur des réserves ne dépasse pas leur solde.
 *
 * ## La réserve légale est une PROPOSITION
 *
 * 10 % du bénéfice tant que la réserve légale n'atteint pas 20 % du capital
 * (101x au plan). Modifiable, jamais bloquante ; si le capital n'est pas
 * déterminable (aucun solde créditeur en 101), rien n'est proposé.
 *
 * ## Interaction avec la clôture de N
 *
 * L'affectation solde 131/139 dans N : la clôture de N reporte alors les
 * classes 1 à 5 sans résultat reporté (`Bilan::resultatReporte` = 0), le bilan
 * reste équilibré. La RÉOUVERTURE de N-1 est refusée tant qu'une affectation
 * est active ({@see ClotureExerciceService::rouvrir()}) : son à-nouveau ne
 * peut pas être contre-passé sous une affectation qui le solde.
 *
 * @see EF-M10-07 Clôture d'exercice
 * @see RG-11 immutabilité des écritures validées
 */
class AffectationResultatService
{
    /** Même droit que la réouverture d'un exercice. */
    public const ROLE = ClotureExerciceService::ROLE_REOUVERTURE;

    /** Une affectation est une opération diverse : aucun journal propre. */
    public const JOURNAL = 'OD';

    public const MOTIF_LONGUEUR_MIN = 10;

    /** Les postes de ventilation d'un bénéfice. */
    public const POSTES_BENEFICE = ['reserve_legale', 'autres_reserves', 'dividendes', 'report_a_nouveau'];

    /** Les postes de ventilation d'une perte. */
    public const POSTES_PERTE = ['autres_reserves', 'imputation_report_crediteur', 'report_a_nouveau'];

    /** Tous les postes, dans l'ordre de l'écran. */
    public const POSTES = ['reserve_legale', 'autres_reserves', 'dividendes', 'report_a_nouveau', 'imputation_report_crediteur'];

    /** Taux de la réserve légale proposée (10 % du bénéfice) et plafond (20 % du capital). */
    public const TAUX_RESERVE_LEGALE = '0.10';

    public const PLAFOND_RESERVE_LEGALE = '0.20';

    private const PRECISION = 2;

    public function __construct(
        private readonly ClotureExerciceService $clotures,
        private readonly PasserEcritureService $passer,
        private readonly CorrespondanceComptesService $comptes,
        private readonly EcritureComptableService $ecritures,
    ) {
    }

    /** L'affectation ACTIVE de l'exercice (N-1), ou `null`. */
    public function active(string $exerciceId): ?AffectationResultat
    {
        return AffectationResultat::query()
            ->where('exercice_id', $exerciceId)
            ->whereNull('contrepassee_le')
            ->latest('affectee_le')
            ->first();
    }

    /**
     * Ce que la carte « Affectation du résultat » affiche pour l'exercice
     * [$exercice] (N-1) — `null` tant qu'il n'est pas clôturé avec une clôture
     * active (rien à affecter, la carte n'existe pas).
     *
     * @return array{
     *     annee: int, anneeAffectation: int, resultat: string, estBenefice: bool, compteResultat: string,
     *     exerciceAffectation: ?ExerciceComptable, affectable: bool, active: ?AffectationResultat,
     *     dateParDefaut: string, proposition: array<string, string>, reserveLegalePropose: bool,
     *     plafondReserveLegaleAtteint: bool, peutAffecter: bool
     * }|null
     */
    public function etat(ExerciceComptable $exercice, ?User $utilisateur = null): ?array
    {
        if ($exercice->statut !== 'cloture') {
            return null;
        }

        $cloture = $this->clotures->clotureActive($exercice->id);

        if ($cloture === null) {
            return null;
        }

        $resultat = (string) $cloture->resultat;
        $estBenefice = bccomp($resultat, '0.00', self::PRECISION) >= 0;
        $suivant = ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();
        $active = $this->active($exercice->id);
        $proposition = $this->proposer($exercice, $resultat, $suivant);

        return [
            'annee' => $exercice->annee,
            'anneeAffectation' => $exercice->annee + 1,
            'resultat' => $resultat,
            'estBenefice' => $estBenefice,
            'compteResultat' => $this->comptes->compte($estBenefice ? 'RESULTAT_BENEFICE' : 'RESULTAT_PERTE'),
            'exerciceAffectation' => $suivant,
            'affectable' => $active === null && $suivant !== null && $suivant->statut === 'ouvert'
                && bccomp($resultat, '0.00', self::PRECISION) !== 0,
            'active' => $active,
            'dateParDefaut' => $this->dateParDefaut($exercice->annee + 1),
            'proposition' => $proposition['ventilation'],
            'reserveLegalePropose' => $proposition['reserveLegalePropose'],
            'plafondReserveLegaleAtteint' => $proposition['plafondAtteint'],
            'peutAffecter' => $utilisateur !== null && $utilisateur->role?->libelle === self::ROLE,
        ];
    }

    /**
     * La ventilation PROPOSÉE : bénéfice → réserve légale à 10 % tant que la
     * réserve légale n'atteint pas 20 % du capital, le reste en report à
     * nouveau ; perte → tout en report à nouveau débiteur.
     *
     * @return array{ventilation: array<string, string>, reserveLegalePropose: bool, plafondAtteint: bool}
     */
    public function proposer(ExerciceComptable $exercice, string $resultat, ?ExerciceComptable $suivant = null): array
    {
        $ventilation = array_fill_keys(self::POSTES, '0.00');

        if (bccomp($resultat, '0.00', self::PRECISION) <= 0) {
            $ventilation['report_a_nouveau'] = bcsub('0.00', $resultat, self::PRECISION);

            return ['ventilation' => $ventilation, 'reserveLegalePropose' => false, 'plafondAtteint' => false];
        }

        $reserve = '0.00';
        $propose = false;
        $plafondAtteint = false;
        $suivant ??= ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();
        $capital = $suivant === null ? '0.00' : $this->soldeCrediteurParPrefixes($suivant->id, RubriquesSyscohada::CAPITAL);

        // Capital non déterminable : aucune proposition, jamais un taux deviné.
        if (bccomp($capital, '0.00', self::PRECISION) > 0) {
            $propose = true;
            $existante = $this->soldeCrediteur($suivant->id, $this->comptes->compte('RESERVE_LEGALE'));
            $plafond = bcmul($capital, self::PLAFOND_RESERVE_LEGALE, self::PRECISION);
            $place = bcsub($plafond, $existante, self::PRECISION);

            if (bccomp($place, '0.00', self::PRECISION) <= 0) {
                $plafondAtteint = true;
            } else {
                $dix = bcmul($resultat, self::TAUX_RESERVE_LEGALE, self::PRECISION);
                $reserve = bccomp($dix, $place, self::PRECISION) <= 0 ? $dix : $place;
            }
        }

        $ventilation['reserve_legale'] = $reserve;
        $ventilation['report_a_nouveau'] = bcsub($resultat, $reserve, self::PRECISION);

        return ['ventilation' => $ventilation, 'reserveLegalePropose' => $propose, 'plafondAtteint' => $plafondAtteint];
    }

    /**
     * Passe l'affectation du résultat de [$exercice] (N-1) par une pièce OD
     * datée de [$date] dans N.
     *
     * @param  array<string, string|int|float|null>  $ventilation  postes de {@see self::POSTES}, montants positifs
     * @param  string|null  $pieceOrigineId  identifiant de la pièce d'un poste (rejeu idempotent)
     * @param  list<array{compte: string, debit: string, credit: string}>|null  $lignesDuPoste
     *                                                                                          les lignes que le poste a passées de son côté : le serveur les confronte aux siennes
     *
     * @throws RuntimeException chacun des refus de l'en-tête, avec sa phrase
     */
    public function affecter(
        ExerciceComptable $exercice,
        array $ventilation,
        string $date,
        User $auteur,
        ?string $motif = null,
        ?string $pieceOrigineId = null,
        ?array $lignesDuPoste = null,
    ): AffectationResultat {
        if ($auteur->role?->libelle !== self::ROLE) {
            throw new RuntimeException(__('comptabilite.affectation_reservee'));
        }

        return DB::transaction(function () use ($exercice, $ventilation, $date, $auteur, $motif, $pieceOrigineId, $lignesDuPoste): AffectationResultat {
            // Le verrou sérialise deux affectations simultanées du même exercice.
            $exercice = ExerciceComptable::query()->whereKey($exercice->id)->lockForUpdate()->firstOrFail();

            if ($exercice->statut !== 'cloture') {
                throw new RuntimeException(__('comptabilite.affectation_exige_cloture', ['annee' => (string) $exercice->annee]));
            }

            $cloture = $this->clotures->clotureActive($exercice->id);

            if ($cloture === null) {
                throw new RuntimeException(__('comptabilite.affectation_exige_cloture', ['annee' => (string) $exercice->annee]));
            }

            $resultat = (string) $cloture->resultat;

            if (bccomp($resultat, '0.00', self::PRECISION) === 0) {
                throw new RuntimeException(__('comptabilite.affectation_resultat_nul', ['annee' => (string) $exercice->annee]));
            }

            $existante = $this->active($exercice->id);

            if ($existante !== null) {
                throw new RuntimeException(__('comptabilite.affectation_deja_passee', [
                    'annee' => (string) $exercice->annee,
                    'piece' => $existante->piece_affectation,
                ]));
            }

            $suivant = $this->exerciceDeLaDate($exercice, $date);
            $montants = $this->controlerVentilation($ventilation, $resultat, $suivant);
            $lignes = $this->lignes($resultat, $montants);

            if ($lignesDuPoste !== null && ! $this->memesLignes($lignes, $lignesDuPoste)) {
                throw new RuntimeException(__('comptabilite.affectation_piece_divergente'));
            }

            // Pièce brouillon d'abord : l'identifiant du poste se pose AVANT la
            // validation (une pièce validée est immuable).
            $piece = $this->passer->passer([
                'journal' => self::JOURNAL,
                'date' => $date,
                'libelle' => (string) __('comptabilite.libelle_affectation_resultat', ['annee' => (string) $exercice->annee]),
                'lignes' => $lignes,
                'statuts_exercice_admis' => ['ouvert'],
            ]);

            if ($pieceOrigineId !== null) {
                DB::table('ecritures_comptables')
                    ->whereIn('id', $piece->pluck('id')->all())
                    ->update(['piece_origine_id' => $pieceOrigineId]);
            }

            $this->ecritures->valider($piece);
            $numero = (string) $piece->first()->numero_piece;
            $beneficiaire = bccomp($resultat, '0.00', self::PRECISION) > 0;

            $affectation = AffectationResultat::query()->create([
                'exercice_id' => $exercice->id,
                'cloture_id' => $cloture->id,
                'resultat' => $resultat,
                'date_approbation' => $date,
                'reserve_legale' => $montants['reserve_legale'],
                'autres_reserves' => $montants['autres_reserves'],
                'dividendes' => $montants['dividendes'],
                'report_a_nouveau_crediteur' => $beneficiaire ? $montants['report_a_nouveau'] : $montants['imputation_report_crediteur'],
                'report_a_nouveau_debiteur' => $beneficiaire ? '0.00' : $montants['report_a_nouveau'],
                'piece_affectation' => $numero,
                'piece_origine_id' => $pieceOrigineId,
                'motif' => $motif === null || trim($motif) === '' ? null : trim($motif),
                'affectee_par' => $auteur->id,
                'affectee_le' => now(),
            ]);

            $this->tracer('affectation_resultat', $exercice, $auteur, [
                'resultat' => $resultat,
                'date_approbation' => $date,
                'piece' => $numero,
                'ventilation' => $montants,
                'motif' => $affectation->motif,
            ]);

            return $affectation;
        });
    }

    /**
     * La CONTRE-PASSATION de l'affectation active de [$exercice] (N-1) : le
     * comptable seul, motif de dix caractères au moins. La pièce d'affectation
     * est inversée ligne à ligne (rien ne s'efface, RG-11) ; l'exercice peut
     * ensuite être affecté de nouveau.
     *
     * @throws RuntimeException rôle, motif, aucune affectation, exercice N clôturé
     */
    public function contrepasser(ExerciceComptable $exercice, User $auteur, string $motif): AffectationResultat
    {
        if ($auteur->role?->libelle !== self::ROLE) {
            throw new RuntimeException(__('comptabilite.affectation_reservee'));
        }

        $motif = trim($motif);

        if (mb_strlen($motif) < self::MOTIF_LONGUEUR_MIN) {
            throw new RuntimeException(__('comptabilite.affectation_motif', ['min' => self::MOTIF_LONGUEUR_MIN]));
        }

        return DB::transaction(function () use ($exercice, $auteur, $motif): AffectationResultat {
            $exercice = ExerciceComptable::query()->whereKey($exercice->id)->lockForUpdate()->firstOrFail();
            $affectation = $this->active($exercice->id);

            if ($affectation === null) {
                throw new RuntimeException(__('comptabilite.affectation_aucune', ['annee' => (string) $exercice->annee]));
            }

            $suivant = ExerciceComptable::query()->where('annee', $exercice->annee + 1)->firstOrFail();

            if ($suivant->statut === 'cloture') {
                throw new RuntimeException(__('comptabilite.affectation_contrepassation_exercice_clos', [
                    'annee' => (string) $exercice->annee,
                    'suivant' => (string) $suivant->annee,
                ]));
            }

            $libelle = (string) __('comptabilite.libelle_contrepassation_affectation', [
                'annee' => (string) $exercice->annee,
                'motif' => $motif,
            ]);
            $lignes = EcritureComptable::query()
                ->where('exercice_id', $suivant->id)
                ->where('numero_piece', $affectation->piece_affectation)
                ->whereNull('ecriture_contrepassee_id')
                ->get();

            $this->passer->contrepasserPiece($lignes, $libelle);

            $affectation->update([
                'contrepassee_par' => $auteur->id,
                'contrepassee_le' => now(),
                'motif_contrepassation' => $motif,
            ]);

            $this->tracer('affectation_resultat_contrepassee', $exercice, $auteur, [
                'resultat' => (string) $affectation->resultat,
                'piece' => $affectation->piece_affectation,
                'motif' => $motif,
            ]);

            return $affectation->refresh();
        });
    }

    /**
     * Les lignes de la pièce : bénéfice → 131 débité, postes crédités ; perte →
     * 139 crédité, postes débités.
     *
     * @param  array<string, string>  $montants
     * @return list<array<string, string>>
     */
    public function lignes(string $resultat, array $montants): array
    {
        $structure = (string) CentreCout::query()->where('libelle', ClotureExerciceService::CENTRE_DE_CLOTURE)->value('id');

        if ($structure === '') {
            throw new RuntimeException(__('comptabilite.affectation_centre_absent', ['centre' => ClotureExerciceService::CENTRE_DE_CLOTURE]));
        }

        $beneficiaire = bccomp($resultat, '0.00', self::PRECISION) > 0;
        $absolu = $beneficiaire ? $resultat : bcsub('0.00', $resultat, self::PRECISION);
        $lignes = [];

        // Le compte du résultat : débité (bénéfice) ou crédité (perte), en tête.
        $lignes[] = [
            'compte' => $this->comptes->compte($beneficiaire ? 'RESULTAT_BENEFICE' : 'RESULTAT_PERTE'),
            'centre_id' => $structure,
            'debit' => $beneficiaire ? $absolu : '0.00',
            'credit' => $beneficiaire ? '0.00' : $absolu,
        ];

        // poste => rôle du compte (même ordre que l'écran).
        $roles = $beneficiaire
            ? ['reserve_legale' => 'RESERVE_LEGALE', 'autres_reserves' => 'AUTRES_RESERVES', 'dividendes' => 'DIVIDENDES_A_PAYER', 'report_a_nouveau' => 'REPORT_A_NOUVEAU_CREDITEUR']
            : ['autres_reserves' => 'AUTRES_RESERVES', 'imputation_report_crediteur' => 'REPORT_A_NOUVEAU_CREDITEUR', 'report_a_nouveau' => 'REPORT_A_NOUVEAU_DEBITEUR'];

        foreach ($roles as $poste => $role) {
            $montant = $montants[$poste] ?? '0.00';

            if (bccomp($montant, '0.00', self::PRECISION) <= 0) {
                continue;
            }

            $lignes[] = [
                'compte' => $this->comptes->compte($role),
                'centre_id' => $structure,
                'debit' => $beneficiaire ? '0.00' : $montant,
                'credit' => $beneficiaire ? $montant : '0.00',
            ];
        }

        return $lignes;
    }

    /**
     * Les lignes du poste sont-elles celles que le serveur passerait ? Comparaison
     * en multiensemble (compte, débit, crédit), sans tenir compte de l'ordre.
     *
     * @param  list<array<string, string>>  $serveur
     * @param  list<array{compte: string, debit: string, credit: string}>  $poste
     */
    private function memesLignes(array $serveur, array $poste): bool
    {
        $cle = static fn (array $l): string => $l['compte'] . '|' . bcadd((string) $l['debit'], '0', self::PRECISION)
            . '|' . bcadd((string) $l['credit'], '0', self::PRECISION);
        $a = array_map($cle, $serveur);
        $b = array_map($cle, $poste);
        sort($a);
        sort($b);

        return $a === $b;
    }

    /**
     * Les contrôles de la ventilation, dans l'ordre : montant lisible et non
     * négatif, postes admis (dividende / réserve légale refusés sur une perte),
     * somme EXACTE, imputation dans la limite du solde.
     *
     * @param  array<string, string|int|float|null>  $ventilation
     * @return array<string, string> montants à deux décimales, tous les postes présents
     */
    private function controlerVentilation(array $ventilation, string $resultat, ExerciceComptable $suivant): array
    {
        $beneficiaire = bccomp($resultat, '0.00', self::PRECISION) > 0;
        $absolu = $beneficiaire ? $resultat : bcsub('0.00', $resultat, self::PRECISION);
        $montants = array_fill_keys(self::POSTES, '0.00');

        foreach (self::POSTES as $poste) {
            $brut = $ventilation[$poste] ?? null;
            $brut = $brut === null || $brut === '' ? '0' : (string) $brut;

            if (! preg_match('/^-?\d+(\.\d{1,2})?$/', $brut)) {
                throw new RuntimeException(__('comptabilite.affectation_montant_illisible', [
                    'poste' => (string) __('comptabilite.affectation_poste_' . $poste),
                    'valeur' => $brut,
                ]));
            }

            $montant = bcadd($brut, '0', self::PRECISION);

            if (bccomp($montant, '0.00', self::PRECISION) < 0) {
                throw new RuntimeException(__('comptabilite.affectation_montant_negatif', [
                    'poste' => (string) __('comptabilite.affectation_poste_' . $poste),
                ]));
            }

            $montants[$poste] = $montant;
        }

        if (! $beneficiaire) {
            if (bccomp($montants['dividendes'], '0.00', self::PRECISION) > 0) {
                throw new RuntimeException(__('comptabilite.affectation_dividende_sur_perte'));
            }

            if (bccomp($montants['reserve_legale'], '0.00', self::PRECISION) > 0) {
                throw new RuntimeException(__('comptabilite.affectation_reserve_legale_sur_perte'));
            }
        } elseif (bccomp($montants['imputation_report_crediteur'], '0.00', self::PRECISION) > 0) {
            throw new RuntimeException(__('comptabilite.affectation_imputation_sur_benefice'));
        }

        $somme = '0.00';

        foreach ($montants as $montant) {
            $somme = bcadd($somme, $montant, self::PRECISION);
        }

        if (bccomp($somme, $absolu, self::PRECISION) !== 0) {
            throw new RuntimeException(__('comptabilite.affectation_somme_differente', [
                'somme' => $somme,
                'resultat' => $absolu,
                'ecart' => bcsub($absolu, $somme, self::PRECISION),
            ]));
        }

        if (! $beneficiaire) {
            foreach (['autres_reserves' => 'AUTRES_RESERVES', 'imputation_report_crediteur' => 'REPORT_A_NOUVEAU_CREDITEUR'] as $poste => $role) {
                $solde = $this->soldeCrediteur($suivant->id, $this->comptes->compte($role));

                if (bccomp($montants[$poste], $solde, self::PRECISION) > 0) {
                    throw new RuntimeException(__('comptabilite.affectation_imputation_excessive', [
                        'poste' => (string) __('comptabilite.affectation_poste_' . $poste),
                        'montant' => $montants[$poste],
                        'solde' => bccomp($solde, '0.00', self::PRECISION) > 0 ? $solde : '0.00',
                    ]));
                }
            }
        }

        return $montants;
    }

    /**
     * L'exercice N qui reçoit la pièce : celui qui suit [$exercice], OUVERT, et
     * qui couvre la date d'approbation.
     */
    private function exerciceDeLaDate(ExerciceComptable $exercice, string $date): ExerciceComptable
    {
        $jour = \DateTimeImmutable::createFromFormat('!Y-m-d', $date);

        if ($jour === false || $jour->format('Y-m-d') !== $date) {
            throw new RuntimeException(__('comptabilite.affectation_date_invalide', ['date' => $date]));
        }

        $suivant = ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();

        if ($suivant === null || (int) $jour->format('Y') !== $suivant->annee) {
            throw new RuntimeException(__('comptabilite.affectation_date_hors_exercice', [
                'date' => $date,
                'annee' => (string) ($exercice->annee + 1),
            ]));
        }

        if ($suivant->statut !== 'ouvert') {
            throw new RuntimeException(__('comptabilite.affectation_exercice_non_ouvert', [
                'annee' => (string) $suivant->annee,
                'statut' => $suivant->statut,
            ]));
        }

        return $suivant;
    }

    /** Aujourd'hui s'il est dans N, sinon la borne de N la plus proche. */
    private function dateParDefaut(int $annee): string
    {
        $aujourdhui = now();

        if ($aujourdhui->year === $annee) {
            return $aujourdhui->toDateString();
        }

        return $aujourdhui->year > $annee ? sprintf('%d-12-31', $annee) : sprintf('%d-01-01', $annee);
    }

    /** Solde créditeur d'un compte dans l'exercice (écritures validées), contre-passations comprises. */
    private function soldeCrediteur(string $exerciceId, string $numero): string
    {
        return $this->soldeCrediteurParPrefixes($exerciceId, [$numero], exact: true);
    }

    /**
     * @param  list<string>  $prefixes
     */
    private function soldeCrediteurParPrefixes(string $exerciceId, array $prefixes, bool $exact = false): string
    {
        $solde = DB::table('ecritures_comptables as e')
            ->join('plan_comptable as p', 'e.compte_id', '=', 'p.id')
            ->where('e.exercice_id', $exerciceId)
            ->where('e.statut', 'validee')
            ->where(function ($q) use ($prefixes, $exact): void {
                foreach ($prefixes as $prefixe) {
                    $exact ? $q->orWhere('p.numero_compte', $prefixe) : $q->orWhere('p.numero_compte', 'like', $prefixe . '%');
                }
            })
            ->selectRaw('COALESCE(SUM(e.credit) - SUM(e.debit), 0) AS solde')
            ->value('solde');

        return bcadd((string) ($solde ?? '0'), '0', self::PRECISION);
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
            'valeur_apres' => ['annee' => $exercice->annee, ...$details],
            'adresse_poste' => request()->ip(),
        ]);
    }
}
