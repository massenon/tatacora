<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Support\FormeJuridique;
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
 *    réserves (118x), dividendes à payer (465), report à nouveau créditeur (121),
 *    compte de l'exploitant (104x, entreprise individuelle) ;
 *  - perte : CRÉDIT 139 du résultat ; DÉBIT report à nouveau débiteur (129x),
 *    ou imputation sur les autres réserves (118x) / le report à nouveau
 *    créditeur (121), ou compte de l'exploitant (104x, entreprise individuelle).
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
 *     l'imputation d'une perte sur des réserves ne dépasse pas leur solde ;
 *  6. les règles de la FORME JURIDIQUE (ci-dessous) : postes offerts, réserve légale
 *     obligatoire, plancher des capitaux propres sous les dividendes.
 *
 * ## Interaction avec la clôture de N
 *
 * L'affectation solde 131/139 dans N : la clôture de N reporte alors les
 * classes 1 à 5 sans résultat reporté (`Bilan::resultatReporte` = 0), le bilan
 * reste équilibré. La RÉOUVERTURE de N-1 est refusée tant qu'une affectation
 * est active ({@see ClotureExerciceService::rouvrir()}) : son à-nouveau ne
 * peut pas être contre-passé sous une affectation qui le solde.
 *
 * ## Les règles PAR FORME JURIDIQUE (décision du PO du 09/11/2026 : « le Gîte est
 * ## une entreprise individuelle », avis de l'expert-comptable SYSCOHADA révisé)
 *
 * {@see FormeJuridique} (paramètre `forme_juridique`, défaut ENTREPRISE INDIVIDUELLE) :
 *
 *  - ENTREPRISE INDIVIDUELLE : pas de réserve légale, pas de dividendes (ni la
 *    ligne ni le compte 465 : un montant sur ces postes est REFUSÉ, y compris dans
 *    la pièce d'un poste), pas de procès-verbal d'assemblée — « date de la
 *    décision de l'exploitant ». Un bénéfice (131) se ventile librement entre le
 *    COMPTE DE L'EXPLOITANT (rôle `COMPTE_EXPLOITANT`, 1041 par défaut : 104 est
 *    une division du plan), le report à nouveau créditeur (121) et les autres
 *    réserves (1181) ; le RESTE va par défaut au compte de l'exploitant. Une perte
 *    (139) se débite au compte de l'exploitant (défaut), au report à nouveau
 *    débiteur (1291), ou s'impute sur 121 / 1181 dans la limite de leur solde ;
 *  - SARL / SA : RÉSERVE LÉGALE OBLIGATOIRE — au moins 10 % de (bénéfice − pertes
 *    antérieures, soit le report à nouveau débiteur) tant que la réserve légale est
 *    sous 20 % du capital (101x) : refus bloquant sinon ; capital non déterminable :
 *    pas de blocage, un AVERTISSEMENT. Dividendes REFUSÉS si la distribution ferait
 *    passer les capitaux propres sous le capital augmenté des réserves non
 *    distribuables. ALERTE non bloquante (carte et journal d'audit) quand, après une
 *    perte, les capitaux propres tombent sous la moitié du capital (art. 664 de
 *    l'Acte uniforme : décision de l'assemblée dans les quatre mois, à faire
 *    confirmer par le comptable) ;
 *  - ORDRE D'IMPUTATION D'UNE PERTE (toutes formes, proposition modifiable) : report
 *    à nouveau créditeur (121), puis réserves facultatives (1181), puis le reste en
 *    report à nouveau débiteur (1291) ; l'entreprise individuelle propose le compte
 *    de l'exploitant. Jamais la réserve légale : une perte ne s'y affecte pas.
 *
 * ## La contre-passation
 *
 * Datée du JOUR de la correction, dans l'exercice N OUVERT, jamais avant la pièce
 * d'origine ; référence de la décision facultative, tracée à l'audit ; REFUSÉE si un
 * dividende de l'affectation est déjà réglé en tout ou partie (« annulez d'abord le
 * règlement »).
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

    /** Les postes de ventilation d'un bénéfice (SARL / SA). */
    public const POSTES_BENEFICE = ['reserve_legale', 'autres_reserves', 'dividendes', 'report_a_nouveau'];

    /** Les postes de ventilation d'une perte (SARL / SA). */
    public const POSTES_PERTE = ['autres_reserves', 'imputation_report_crediteur', 'report_a_nouveau'];

    /** Les postes d'un bénéfice d'une entreprise individuelle : ni réserve légale ni dividendes. */
    public const POSTES_BENEFICE_EI = ['compte_exploitant', 'autres_reserves', 'report_a_nouveau'];

    /** Les postes d'une perte d'une entreprise individuelle. */
    public const POSTES_PERTE_EI = ['compte_exploitant', 'autres_reserves', 'imputation_report_crediteur', 'report_a_nouveau'];

    /** Tous les postes, dans l'ordre de l'écran. */
    public const POSTES = ['reserve_legale', 'autres_reserves', 'dividendes', 'report_a_nouveau', 'imputation_report_crediteur', 'compte_exploitant'];

    /**
     * Le capital SOCIAL se lit au 101 seul (101x au plan) : le groupe 104 est le
     * compte de l'exploitant, jamais un capital sur lequel calculer une réserve légale.
     *
     * @var list<string>
     */
    public const PREFIXES_CAPITAL_SOCIAL = ['101'];

    /**
     * Les capitaux propres : le capital (groupe 10, écrit compte par compte — le plan n'a
     * pas de compte `10` : 101 capital, 102 dotation, 103 personnel, 104 exploitant,
     * 105 primes, 106 écarts, 109 non appelé), les réserves (11), le report à nouveau
     * (12), le résultat (13), les subventions (14) et les provisions réglementées (15).
     *
     * @var list<string>
     */
    public const PREFIXES_CAPITAUX_PROPRES = ['101', '102', '103', '104', '105', '106', '109', '11', '12', '13', '14', '15'];

    /** Les pertes antérieures non apurées : le report à nouveau débiteur (129x). */
    public const PREFIXES_PERTES_ANTERIEURES = ['129'];

    /** Réserves que la loi ne permet pas de distribuer, en plus de la réserve légale : statutaires (112), réglementées (113). */
    public const PREFIXES_RESERVES_NON_DISTRIBUABLES = ['112', '113'];

    /** Longueur maximale de la référence de la décision (colonne `string(255)`). */
    public const REFERENCE_LONGUEUR_MAX = 255;

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
     * `postes` : les postes de ventilation OFFERTS pour la forme juridique et le
     * sens du résultat (une entreprise individuelle n'offre ni réserve légale ni
     * dividendes) ; `posteDuReste` : celui qui reçoit le reste ; `alertes` et
     * `avertissements` : non bloquants, à lire sur la carte.
     *
     * @return array{
     *     annee: int, anneeAffectation: int, resultat: string, estBenefice: bool, compteResultat: string,
     *     exerciceAffectation: ?ExerciceComptable, affectable: bool, active: ?AffectationResultat,
     *     dateParDefaut: string, proposition: array<string, string>, reserveLegalePropose: bool,
     *     plafondReserveLegaleAtteint: bool, peutAffecter: bool, forme: string, estSociete: bool,
     *     postes: list<string>, posteDuReste: string, alertes: list<string>, avertissements: list<string>
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

        $forme = FormeJuridique::courante();
        $resultat = (string) $cloture->resultat;
        $estBenefice = bccomp($resultat, '0.00', self::PRECISION) >= 0;
        $suivant = ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();
        $active = $this->active($exercice->id);
        $proposition = $this->proposer($exercice, $resultat, $suivant, $forme);
        $alertes = [];
        $avertissements = [];

        if ($suivant !== null && $forme->estSociete()) {
            $situation = $this->situation($suivant);
            $alerte = $this->alerteMoitieCapital($situation, $resultat);

            if ($alerte !== null) {
                $alertes[] = $alerte;
            }

            if ($estBenefice && bccomp($situation['capital'], '0.00', self::PRECISION) <= 0) {
                $avertissements[] = (string) __('comptabilite.affectation_avertissement_capital_indetermine');
            }
        }

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
            'peutAffecter' => $utilisateur !== null && $utilisateur->estComptableOuGerant(),
            'forme' => $forme->value,
            'estSociete' => $forme->estSociete(),
            'postes' => self::postes($forme, $estBenefice),
            'posteDuReste' => self::posteDuReste($forme),
            'alertes' => $alertes,
            'avertissements' => $avertissements,
        ];
    }

    /**
     * Les postes de ventilation OFFERTS pour [$forme] et le sens du résultat.
     *
     * @return list<string>
     */
    public static function postes(FormeJuridique $forme, bool $benefice): array
    {
        if ($forme->estSociete()) {
            return $benefice ? self::POSTES_BENEFICE : self::POSTES_PERTE;
        }

        return $benefice ? self::POSTES_BENEFICE_EI : self::POSTES_PERTE_EI;
    }

    /** Le poste qui reçoit LE RESTE : le compte de l'exploitant (EI), le report à nouveau (société). */
    public static function posteDuReste(FormeJuridique $forme): string
    {
        return $forme->estSociete() ? 'report_a_nouveau' : 'compte_exploitant';
    }

    /**
     * La ventilation PROPOSÉE.
     *
     *  - entreprise individuelle : tout au compte de l'exploitant (bénéfice comme perte) ;
     *  - société, bénéfice : réserve légale obligatoire (10 % du bénéfice net des pertes
     *    antérieures tant qu'elle n'atteint pas 20 % du capital), le reste en report à
     *    nouveau ; capital non déterminable : aucune réserve légale proposée ;
     *  - société, perte : report à nouveau créditeur (121) d'abord, puis réserves
     *    facultatives (1181), puis le reste en report à nouveau débiteur (1291) — jamais
     *    au-delà du solde, jamais la réserve légale.
     *
     * @return array{ventilation: array<string, string>, reserveLegalePropose: bool, plafondAtteint: bool}
     */
    public function proposer(ExerciceComptable $exercice, string $resultat, ?ExerciceComptable $suivant = null, ?FormeJuridique $forme = null): array
    {
        $forme ??= FormeJuridique::courante();
        $ventilation = array_fill_keys(self::POSTES, '0.00');
        $beneficiaire = bccomp($resultat, '0.00', self::PRECISION) > 0;
        $absolu = $beneficiaire ? $resultat : bcsub('0.00', $resultat, self::PRECISION);

        if (! $forme->estSociete()) {
            $ventilation['compte_exploitant'] = $absolu;

            return ['ventilation' => $ventilation, 'reserveLegalePropose' => false, 'plafondAtteint' => false];
        }

        $suivant ??= ExerciceComptable::query()->where('annee', $exercice->annee + 1)->first();

        if (bccomp($resultat, '0.00', self::PRECISION) <= 0) {
            $reste = $absolu;

            foreach (['imputation_report_crediteur' => 'REPORT_A_NOUVEAU_CREDITEUR', 'autres_reserves' => 'AUTRES_RESERVES'] as $poste => $role) {
                $solde = $suivant === null ? '0.00' : $this->soldeCrediteur($suivant->id, $this->comptes->compte($role));
                $impute = bccomp($solde, '0.00', self::PRECISION) <= 0 ? '0.00' : (bccomp($reste, $solde, self::PRECISION) <= 0 ? $reste : $solde);
                $ventilation[$poste] = $impute;
                $reste = bcsub($reste, $impute, self::PRECISION);
            }

            $ventilation['report_a_nouveau'] = $reste;

            return ['ventilation' => $ventilation, 'reserveLegalePropose' => false, 'plafondAtteint' => false];
        }

        $reserve = '0.00';
        $propose = false;
        $plafondAtteint = false;
        $situation = $suivant === null ? null : $this->situation($suivant);

        // Capital non déterminable : aucune proposition, jamais un taux deviné.
        if ($situation !== null && bccomp($situation['capital'], '0.00', self::PRECISION) > 0) {
            $propose = true;
            $minimum = $this->reserveLegaleMinimum($situation, $resultat);

            if ($minimum === null) {
                $plafondAtteint = true;
            } else {
                $reserve = $minimum;
            }
        }

        $ventilation['reserve_legale'] = $reserve;
        $ventilation['report_a_nouveau'] = bcsub($resultat, $reserve, self::PRECISION);

        return ['ventilation' => $ventilation, 'reserveLegalePropose' => $propose, 'plafondAtteint' => $plafondAtteint];
    }

    /**
     * La SITUATION de N lue sur ses écritures validées (à-nouveaux écrits compris) :
     * capital social (101x), réserve légale, réserves non distribuables, pertes
     * antérieures (report à nouveau débiteur, positif) et capitaux propres.
     *
     * @return array{capital: string, reserveLegale: string, reservesNonDistribuables: string, pertesAnterieures: string, capitauxPropres: string}
     */
    private function situation(ExerciceComptable $suivant): array
    {
        $debitNet = $this->soldeCrediteurParPrefixes($suivant->id, self::PREFIXES_PERTES_ANTERIEURES);

        return [
            'capital' => $this->soldeCrediteurParPrefixes($suivant->id, self::PREFIXES_CAPITAL_SOCIAL),
            'reserveLegale' => $this->soldeCrediteur($suivant->id, $this->comptes->compte('RESERVE_LEGALE')),
            'reservesNonDistribuables' => $this->soldeCrediteurParPrefixes($suivant->id, self::PREFIXES_RESERVES_NON_DISTRIBUABLES),
            'pertesAnterieures' => bccomp($debitNet, '0.00', self::PRECISION) < 0 ? bcsub('0.00', $debitNet, self::PRECISION) : '0.00',
            'capitauxPropres' => $this->soldeCrediteurParPrefixes($suivant->id, self::PREFIXES_CAPITAUX_PROPRES),
        ];
    }

    /**
     * La réserve légale OBLIGATOIRE d'un bénéfice de société : 10 % de (bénéfice −
     * pertes antérieures), plafonnée à ce qui reste avant 20 % du capital. `null` quand
     * le plafond est atteint (rien n'est dû). Le capital doit être déterminable.
     *
     * @param  array{capital: string, reserveLegale: string, pertesAnterieures: string}  $situation
     */
    private function reserveLegaleMinimum(array $situation, string $resultat): ?string
    {
        $plafond = bcmul($situation['capital'], self::PLAFOND_RESERVE_LEGALE, self::PRECISION);
        $place = bcsub($plafond, $situation['reserveLegale'], self::PRECISION);

        if (bccomp($place, '0.00', self::PRECISION) <= 0) {
            return null;
        }

        $base = bcsub($resultat, $situation['pertesAnterieures'], self::PRECISION);

        if (bccomp($base, '0.00', self::PRECISION) <= 0) {
            return '0.00';
        }

        $dix = bcmul($base, self::TAUX_RESERVE_LEGALE, self::PRECISION);

        return bccomp($dix, $place, self::PRECISION) <= 0 ? $dix : $place;
    }

    /**
     * L'ALERTE de l'article 664 : une PERTE de société dont les capitaux propres
     * tombent sous la moitié du capital. Non bloquante ; à faire confirmer par le
     * comptable. `null` sinon (bénéfice, capital non déterminable, capitaux propres
     * suffisants). L'affectation d'une perte ne change pas les capitaux propres :
     * la perte (139) est déjà dans les capitaux propres que l'à-nouveau a reportés.
     *
     * @param  array{capital: string, capitauxPropres: string}  $situation
     */
    private function alerteMoitieCapital(array $situation, string $resultat): ?string
    {
        if (bccomp($resultat, '0.00', self::PRECISION) >= 0 || bccomp($situation['capital'], '0.00', self::PRECISION) <= 0) {
            return null;
        }

        $moitie = bcdiv($situation['capital'], '2', self::PRECISION);

        if (bccomp($situation['capitauxPropres'], $moitie, self::PRECISION) >= 0) {
            return null;
        }

        return (string) __('comptabilite.affectation_alerte_moitie_capital', [
            'propres' => $situation['capitauxPropres'],
            'capital' => $situation['capital'],
        ]);
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
        if (! $auteur->estComptableOuGerant()) {
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

            $forme = FormeJuridique::courante();
            $suivant = $this->exerciceDeLaDate($exercice, $date);
            $controle = $this->controlerVentilation($ventilation, $resultat, $suivant, $forme);
            $montants = $controle['montants'];
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

            // L'ALERTE de l'article 664 se lit APRÈS la pièce (les capitaux propres
            // d'après) : non bloquante, elle va à l'audit et à la carte.
            $alertes = [];

            if ($forme->estSociete()) {
                $alerte = $this->alerteMoitieCapital($this->situation($suivant), $resultat);

                if ($alerte !== null) {
                    $alertes[] = $alerte;
                }
            }

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
                'compte_exploitant' => $montants['compte_exploitant'],
                'forme_juridique' => $forme->value,
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
                'forme_juridique' => $forme->value,
                'ventilation' => $montants,
                'motif' => $affectation->motif,
                'avertissements' => $controle['avertissements'],
                'alertes' => $alertes,
            ]);

            return $affectation;
        });
    }

    /**
     * La CONTRE-PASSATION de l'affectation active de [$exercice] (N-1) : le
     * comptable seul, motif de dix caractères au moins, référence de la décision
     * (PV d'assemblée / décision de l'exploitant) FACULTATIVE et tracée à l'audit.
     *
     * La pièce d'affectation est inversée ligne à ligne (rien ne s'efface, RG-11) :
     *  - à la date du JOUR de la correction, qui doit tomber dans l'exercice N, OUVERT,
     *    et n'est jamais antérieure à la pièce d'origine ;
     *  - REFUSÉE si un dividende de l'affectation est déjà réglé en tout ou partie (le
     *    compte des dividendes à payer n'est plus au montant affecté) : « annulez
     *    d'abord le règlement ».
     *
     * L'exercice peut ensuite être affecté de nouveau.
     *
     * @throws RuntimeException rôle, motif, référence, aucune affectation, exercice N non ouvert, date, dividende réglé
     */
    public function contrepasser(ExerciceComptable $exercice, User $auteur, string $motif, ?string $reference = null): AffectationResultat
    {
        if (! $auteur->estComptableOuGerant()) {
            throw new RuntimeException(__('comptabilite.affectation_reservee'));
        }

        $motif = trim($motif);

        if (mb_strlen($motif) < self::MOTIF_LONGUEUR_MIN) {
            throw new RuntimeException(__('comptabilite.affectation_motif', ['min' => self::MOTIF_LONGUEUR_MIN]));
        }

        $reference = $reference === null || trim($reference) === '' ? null : trim($reference);

        if ($reference !== null && mb_strlen($reference) > self::REFERENCE_LONGUEUR_MAX) {
            throw new RuntimeException(__('comptabilite.affectation_reference_trop_longue', ['max' => self::REFERENCE_LONGUEUR_MAX]));
        }

        return DB::transaction(function () use ($exercice, $auteur, $motif, $reference): AffectationResultat {
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

            if ($suivant->statut !== 'ouvert') {
                throw new RuntimeException(__('comptabilite.affectation_contrepassation_exercice_non_ouvert', [
                    'annee' => (string) $exercice->annee,
                    'suivant' => (string) $suivant->annee,
                    'statut' => $suivant->statut,
                ]));
            }

            // La date de la correction : AUJOURD'HUI, dans N, jamais avant la pièce d'origine.
            $jour = now()->toDateString();

            if ((int) now()->format('Y') !== $suivant->annee) {
                throw new RuntimeException(__('comptabilite.affectation_contrepassation_date_hors_exercice', [
                    'date' => $jour,
                    'suivant' => (string) $suivant->annee,
                ]));
            }

            $origine = $affectation->date_approbation->toDateString();

            if ($jour < $origine) {
                throw new RuntimeException(__('comptabilite.affectation_contrepassation_anterieure', [
                    'date' => $jour,
                    'origine' => $origine,
                ]));
            }

            // Un dividende réglé (le compte des dividendes à payer a été débité) : on annule d'abord le règlement.
            if (bccomp((string) $affectation->dividendes, '0.00', self::PRECISION) > 0) {
                $reste = $this->soldeCrediteur($suivant->id, $this->comptes->compte('DIVIDENDES_A_PAYER'));
                $regle = bcsub((string) $affectation->dividendes, $reste, self::PRECISION);

                if (bccomp($regle, '0.00', self::PRECISION) > 0) {
                    throw new RuntimeException(__('comptabilite.affectation_dividende_regle', [
                        'annee' => (string) $exercice->annee,
                        'regle' => $regle,
                        'dividendes' => (string) $affectation->dividendes,
                    ]));
                }
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

            $this->passer->contrepasserPiece($lignes, $libelle, $jour);

            $affectation->update([
                'contrepassee_par' => $auteur->id,
                'contrepassee_le' => now(),
                'motif_contrepassation' => $motif,
                'reference_decision_contrepassation' => $reference,
            ]);

            $this->tracer('affectation_resultat_contrepassee', $exercice, $auteur, [
                'resultat' => (string) $affectation->resultat,
                'piece' => $affectation->piece_affectation,
                'motif' => $motif,
                'reference_decision' => $reference,
                'date_contrepassation' => $jour,
            ]);

            return $affectation->refresh();
        });
    }

    /**
     * Les lignes de la pièce : bénéfice → 131 débité, postes crédités ; perte →
     * 139 crédité, postes débités (le compte de l'exploitant comme les autres).
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
            ? ['reserve_legale' => 'RESERVE_LEGALE', 'autres_reserves' => 'AUTRES_RESERVES', 'dividendes' => 'DIVIDENDES_A_PAYER', 'report_a_nouveau' => 'REPORT_A_NOUVEAU_CREDITEUR', 'compte_exploitant' => 'COMPTE_EXPLOITANT']
            : ['autres_reserves' => 'AUTRES_RESERVES', 'imputation_report_crediteur' => 'REPORT_A_NOUVEAU_CREDITEUR', 'report_a_nouveau' => 'REPORT_A_NOUVEAU_DEBITEUR', 'compte_exploitant' => 'COMPTE_EXPLOITANT'];

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
     * négatif, postes admis POUR LA FORME JURIDIQUE (ni réserve légale ni dividende
     * pour une entreprise individuelle, pas de compte de l'exploitant pour une
     * société ; ni dividende ni réserve légale sur une perte), somme EXACTE,
     * imputation dans la limite du solde, puis — société, bénéfice — la RÉSERVE
     * LÉGALE OBLIGATOIRE et le plancher des capitaux propres sous les dividendes.
     *
     * @param  array<string, string|int|float|null>  $ventilation
     * @return array{montants: array<string, string>, avertissements: list<string>} montants à deux décimales, tous les postes présents
     */
    private function controlerVentilation(array $ventilation, string $resultat, ExerciceComptable $suivant, FormeJuridique $forme): array
    {
        $beneficiaire = bccomp($resultat, '0.00', self::PRECISION) > 0;
        $absolu = $beneficiaire ? $resultat : bcsub('0.00', $resultat, self::PRECISION);
        $montants = array_fill_keys(self::POSTES, '0.00');
        $avertissements = [];

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

        // La forme juridique : une entreprise individuelle n'a ni réserve légale ni dividende
        // (le compte 465 n'est pas offert, une pièce de poste qui en porte est refusée) ; une
        // société n'a pas de compte de l'exploitant.
        if (! $forme->estSociete()) {
            if (bccomp($montants['reserve_legale'], '0.00', self::PRECISION) > 0) {
                throw new RuntimeException(__('comptabilite.affectation_ei_reserve_legale'));
            }

            if (bccomp($montants['dividendes'], '0.00', self::PRECISION) > 0) {
                throw new RuntimeException(__('comptabilite.affectation_ei_dividende'));
            }
        } elseif (bccomp($montants['compte_exploitant'], '0.00', self::PRECISION) > 0) {
            throw new RuntimeException(__('comptabilite.affectation_societe_compte_exploitant', ['forme' => $forme->libelle()]));
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

        if ($forme->estSociete() && $beneficiaire) {
            $situation = $this->situation($suivant);

            // La réserve légale est OBLIGATOIRE tant qu'elle n'atteint pas 20 % du capital.
            if (bccomp($situation['capital'], '0.00', self::PRECISION) <= 0) {
                $avertissements[] = (string) __('comptabilite.affectation_avertissement_capital_indetermine');
            } else {
                $minimum = $this->reserveLegaleMinimum($situation, $resultat);

                if ($minimum !== null && bccomp($montants['reserve_legale'], $minimum, self::PRECISION) < 0) {
                    throw new RuntimeException(__('comptabilite.affectation_reserve_legale_insuffisante', [
                        'minimum' => $minimum,
                        'base' => bcsub($resultat, $situation['pertesAnterieures'], self::PRECISION),
                        'pertes' => $situation['pertesAnterieures'],
                        'capital' => $situation['capital'],
                        'saisi' => $montants['reserve_legale'],
                    ]));
                }
            }

            // Un dividende ne peut pas entamer le capital ni les réserves non distribuables.
            if (bccomp($montants['dividendes'], '0.00', self::PRECISION) > 0) {
                $apres = bcsub($situation['capitauxPropres'], $montants['dividendes'], self::PRECISION);
                $plancher = bcadd(
                    bcadd($situation['capital'], bcadd($situation['reserveLegale'], $montants['reserve_legale'], self::PRECISION), self::PRECISION),
                    $situation['reservesNonDistribuables'],
                    self::PRECISION,
                );

                if (bccomp($apres, $plancher, self::PRECISION) < 0) {
                    throw new RuntimeException(__('comptabilite.affectation_dividende_capitaux_propres', [
                        'dividendes' => $montants['dividendes'],
                        'apres' => $apres,
                        'plancher' => $plancher,
                    ]));
                }
            }
        }

        return ['montants' => $montants, 'avertissements' => $avertissements];
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
