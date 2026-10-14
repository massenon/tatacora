<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Passage d'une pièce comptable depuis des CODES MÉTIER — M10.
 *
 * ## Pourquoi ce service existe alors que `EcritureComptableService` existe
 *
 * `EcritureComptableService` travaille en identifiants : `exercice_id`,
 * `journal_id`, `compte_id`, `centre_id`, tous des UUID. C'est le bon niveau
 * pour lui — il porte l'équilibre débit/crédit, la validation et la
 * contre-passation, et il ne doit rien savoir des référentiels.
 *
 * Les modules métier, eux, ne connaissent que des codes : le journal « CA »,
 * le compte « 6011 », une date. Personne au comptoir ne saisit un UUID. La
 * traduction code → identifiant était le chaînon manquant, et son absence a
 * produit exactement le défaut que le lot 0b corrige : `DepenseService`
 * importait `PasserEcritureService`, une classe **qui n'existait nulle part**,
 * derrière un `class_exists()` qui rendait `false` pour toujours. Aucune
 * dépense n'a jamais atteint le grand livre, sans erreur, sans journal, sans
 * un mot à l'écran.
 *
 * Ce service ne réécrit AUCUNE règle comptable : il résout, puis délègue.
 *
 * ## Quatre refus, aucun repli
 *
 * Journal inconnu, compte inconnu, exercice absent ou clos, centre de coût
 * introuvable : chacun lève. Aucun n'est remplacé par une valeur plausible.
 * Un compte « 601 » (division) substitué au « 6011 » attendu imputerait une charge au
 * mauvais poste sur une pièce validée, donc immuable (RG-11) — la correction
 * demanderait ensuite une contre-passation.
 *
 * ## Le centre de coût vient du PLAN, jamais du numéro de compte
 *
 * RG-12 rend `centre_id` NOT NULL. Le maître de démonstration déduit le centre
 * d'un préfixe de compte (`CENTRES_COUT_PAR_COMPTE`, `m10-comptabilite-data.js`
 * l.64-81) — et note lui-même que ce raccourci ne vaut pas en production.
 * L'ordre retenu est : centre passé explicitement, sinon
 * `plan_comptable.centre_cout_defaut_id` (la colonne existe précisément pour
 * cela), sinon refus. Jamais un centre « par défaut » global : imputer les
 * achats du bar à la Structure fausserait toute la comptabilité analytique
 * (EF-M10-03) sans qu'aucun total ne bouge.
 *
 * @see EF-M10-02 Saisie des écritures comptables
 * @see EF-M10-07 Clôture comptable périodique — un exercice clos refuse
 * @see RG-11 Immutabilité — portée par `EcritureComptableObserver`
 * @see RG-12 Centre de coût obligatoire
 */
class PasserEcritureService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly EcritureComptableService $ecritures,
        private readonly SequenceDocumentService $sequences,
    ) {
    }

    /**
     * Écrit une pièce en BROUILLON, à partir de codes métier.
     *
     * @param  array{journal: string, date: string, libelle: string, lignes: list<array<string, mixed>>}  $donnees
     *                                                                                                              Chaque ligne : `compte` (numéro), `debit` et/ou `credit`,
     *                                                                                                              `libelle` (optionnel), `centre_id` (optionnel — voir la note de classe).
     * @return Collection<int, EcritureComptable>
     *
     * @throws RuntimeException journal, compte, exercice ou centre introuvable
     */
    public function passer(array $donnees): Collection
    {
        $journal = $this->journal((string) $donnees['journal']);
        $date = (string) $donnees['date'];
        $exercice = $this->exerciceOuvert($date);
        $libelle = (string) $donnees['libelle'];

        $lignes = [];

        foreach ($donnees['lignes'] as $ligne) {
            $compte = $this->compte((string) $ligne['compte']);

            $lignes[] = [
                'compte_id' => $compte->id,
                'centre_id' => $this->centre($ligne, $compte),
                'debit' => $this->montant($ligne['debit'] ?? '0'),
                'credit' => $this->montant($ligne['credit'] ?? '0'),
                'libelle' => (string) ($ligne['libelle'] ?? $libelle),
            ];
        }

        // SEULE modification chirurgicale de ce service pour la Vague E
        // (01/09/2026) — PA-52, partiellement refermée. L'allocation du
        // numéro DOIT être posée dans la même transaction que l'écriture :
        // `SequenceDocumentService::suivant()` pose un verrou `FOR UPDATE`
        // qui n'a d'effet sérialisant que dans la transaction appelante —
        // hors d'elle, il est relâché avant même que la pièce ne soit écrite,
        // et deux saisies concurrentes sur le même journal pourraient
        // recevoir le même numéro.
        return DB::transaction(function () use ($journal, $exercice, $date, $libelle, $lignes): Collection {
            $numeroPiece = $this->sequences->suivant(
                'ecritures_comptables',
                $journal->code,
                (int) substr($date, 0, 4),
                'numero_piece',
            );

            return $this->ecritures->enregistrerPiece([
                'exercice_id' => $exercice->id,
                'journal_id' => $journal->id,
                'date_ecriture' => $date,
                'libelle' => $libelle,
                'numero_piece' => $numeroPiece,
            ], $lignes);
        });
    }

    /**
     * Écrit une pièce ET la valide, en une transaction.
     *
     * ## Pourquoi la validation immédiate est le bon choix ICI
     *
     * Toutes les lectures comptables du dépôt filtrent `statut = 'validee'` —
     * `EcritureComptableService::soldeCompte()`, les états financiers, et
     * `TableauDeBordService::depensesCumulees()` (l.234). Une pièce laissée en
     * brouillon reste donc invisible partout : le grand livre, la balance, le
     * compte de résultat et la trésorerie continueraient de ne pas voir
     * l'argent sortir — exactement le défaut que ce service corrige, sous une
     * forme plus douce.
     *
     * Le geste métier est déjà irréversible quand on arrive ici : l'argent est
     * sorti du tiroir. La pièce qui le constate n'a pas de raison d'attendre.
     * RG-11 s'applique alors pleinement, et une erreur se corrige par
     * contre-passation — la seule correction admise.
     *
     * `passer()` reste offert pour les saisies qui doivent être relues avant
     * d'être opposables. Le choix se fait à l'appel, en un mot, pas en
     * dupliquant la mécanique.
     *
     * @param  array{journal: string, date: string, libelle: string, lignes: list<array<string, mixed>>}  $donnees
     * @return Collection<int, EcritureComptable>
     */
    public function passerEtValider(array $donnees): Collection
    {
        return DB::transaction(function () use ($donnees): Collection {
            return $this->ecritures->valider($this->passer($donnees));
        });
    }

    /**
     * Contre-passe TOUTES les lignes d'une piece deja validee.
     *
     * ## Pourquoi la piece entiere, jamais une seule ligne
     *
     * `EcritureComptableService::contrepasser()` inverse UNE ecriture. Appele
     * sur la seule ligne de contrepartie d'une vente, il rendrait la tresorerie
     * juste et laisserait le compte de produits credite : le grand livre
     * serait desequilibre de tout le montant annule, et le compte de resultat
     * afficherait un chiffre d'affaires que plus rien ne justifie. Une piece
     * s'annule entiere ou pas du tout.
     *
     * Le motif est repete a l'identique sur chaque ligne : c'est ce qui rend
     * les inverses reconnaissables comme un seul geste au journal.
     *
     * @param  Collection<int, EcritureComptable>  $piece
     * @return Collection<int, EcritureComptable>
     *
     * @throws \App\Domain\Comptabilite\Exceptions\EcritureImmuableException piece en brouillon, ou deja contre-passee
     */
    public function contrepasserPiece(Collection $piece, ?string $motif = null): Collection
    {
        if ($piece->isEmpty()) {
            // Une contre-passation qui ne trouve rien a inverser ne doit pas
            // se taire : elle laisserait croire que l'annulation a atteint la
            // comptabilite alors qu'elle n'a touche personne.
            throw new RuntimeException(__('comptabilite.piece_vide'));
        }

        return DB::transaction(function () use ($piece, $motif): Collection {
            $inverses = new Collection();

            foreach ($piece as $ecriture) {
                $inverses->push($this->ecritures->contrepasser($ecriture, $motif));
            }

            return $inverses;
        });
    }

    private function journal(string $code): JournalComptable
    {
        $journal = JournalComptable::where('code', $code)->first();

        if ($journal === null) {
            throw new RuntimeException(__('depenses.journal_inconnu', ['code' => $code]));
        }

        return $journal;
    }

    private function compte(string $numero): CompteComptable
    {
        $compte = CompteComptable::where('numero_compte', $numero)->first();

        if ($compte === null) {
            throw new RuntimeException(__('depenses.compte_inconnu', ['numero' => $numero]));
        }

        // Un compte de DIVISION (le plan en porte des sous-comptes) ne reçoit
        // aucun mouvement : seuls les comptes de détail s'imputent. En pratique
        // les comptes à 4 chiffres ; les comptes plus courts SANS sous-compte
        // au plan (552, 131, 139…) sont des feuilles et restent imputables.
        if (strlen($numero) < 4
            && CompteComptable::where('numero_compte', 'like', $numero.'%')->where('numero_compte', '!=', $numero)->exists()) {
            throw new RuntimeException(__('comptabilite.compte_division', ['numero' => $numero]));
        }

        return $compte;
    }

    /**
     * L'exercice qui COUVRE la date et qui est encore ouvert.
     *
     * Deux refus distincts, et l'écart compte : « aucun exercice » se corrige
     * en créant l'exercice, « exercice clos » se corrige en rouvrant ou en
     * datant la pièce autrement. Un message unique enverrait chercher au
     * mauvais endroit.
     */
    private function exerciceOuvert(string $date): ExerciceComptable
    {
        $exercice = ExerciceComptable::query()
            ->whereDate('date_debut', '<=', $date)
            ->whereDate('date_fin', '>=', $date)
            ->first();

        if ($exercice === null) {
            throw new RuntimeException(__('depenses.exercice_absent', ['date' => $date]));
        }

        if ($exercice->statut !== 'ouvert') {
            throw new RuntimeException(__('depenses.exercice_clos', [
                'annee' => (string) $exercice->annee,
                'statut' => $exercice->statut,
            ]));
        }

        return $exercice;
    }

    /**
     * @param  array<string, mixed>  $ligne
     */
    private function centre(array $ligne, CompteComptable $compte): string
    {
        $centre = $ligne['centre_id'] ?? $compte->centre_cout_defaut_id;

        if ($centre === null || $centre === '') {
            throw new RuntimeException(__('depenses.centre_absent', [
                'numero' => $compte->numero_compte,
            ]));
        }

        return (string) $centre;
    }

    /**
     * Montant normalisé en chaîne à deux décimales — jamais un flottant
     * transmis tel quel à une colonne DECIMAL.
     */
    private function montant(mixed $valeur): string
    {
        return bcadd((string) $valeur, '0', self::PRECISION);
    }
}
