<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Models\LigneDepense;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Dépenses courantes : saisie, ventilation SYSCOHADA et comptabilisation (M10).
 *
 * **Unique point d'entrée d'écriture sur `depenses` et `lignes_depense`.**
 *
 * ## Le défaut corrigé (PA-159, lot 0b, T4)
 *
 * Ce service importait `App\Domain\Comptabilite\Services\PasserEcritureService`
 * — une classe qui **n'existait nulle part**. L'appel était gardé par un
 * `if ($this->ecritureService !== null)` et enveloppé dans un
 * `catch (\Throwable)` qui rangeait le message dans une colonne que personne ne
 * lisait. Le composant PWA faisait la même chose derrière un `class_exists()`
 * qui rendait `false` pour toujours. Résultat mesuré : cinq dépenses en base,
 * zéro écriture comptable, un bandeau vert à chaque saisie, et un grand livre
 * qui ne voyait jamais l'argent sortir.
 *
 * Deux choses ont changé, et la seconde compte autant que la première :
 * `PasserEcritureService` existe, **et l'écriture n'est plus facultative**.
 *
 * ## Une dépense sans écriture n'est plus enregistrée du tout
 *
 * L'écriture est passée dans la MÊME transaction que la dépense. Si elle
 * échoue, rien n'est écrit et l'opérateur voit pourquoi.
 *
 * C'est le raisonnement de `CalculTvaService` (PA-62), pas celui de MECeF : les
 * quatre causes d'échec — compte inconnu, journal inconnu, exercice absent ou
 * clos, centre de coût introuvable — sont toutes **locales et corrigibles**,
 * jamais la panne d'un service tiers. Enregistrer quand même, en rangeant le
 * refus dans une colonne, reproduirait le défaut sous une forme plus douce :
 * un toast vert, une caisse qui se vide, une comptabilité qui l'ignore.
 *
 * `ecriture_refus` subsiste pour une raison précise et une seule : les dépenses
 * antérieures à ce lot n'ont pas d'écriture, et `comptabiliser()` y consigne
 * la raison d'un échec de rattrapage — sur un enregistrement qui existe déjà.
 *
 * @see EF-M10-02 Saisie des écritures comptables
 * @see RG-11 Immutabilité — la correction passe par contre-passation
 * @see RG-12 Centre de coût obligatoire
 */
class DepenseService
{
    private const PRECISION = 2;

    private const PREFIXE_NUMERO = 'DEP';

    /**
     * Registre FERMÉ des trésoreries : compte de contrepartie et journal.
     *
     * Les numéros sont ceux de `ComptesSyscohada` (plan du PO, 10/10/2026) :
     * 5711 « Caisse en monnaie nationale », 5211 « Banque X », 552 « MONNAIE
     * ELECTRONIQUE- TELEPHONE PORTABLE ». Un ancien code portait `5711`, `521` et `5311` :
     * trois numéros qui n'existent dans aucun plan comptable du dépôt, donc
     * trois pièces qui auraient été refusées si l'écriture avait été tentée.
     *
     * Les codes de journal sont ceux de `MODULE_COMPTABILITE_COMPLET.md` §2
     * (VTE, ACH, BQ, CAI, OD). Le rattachement du Mobile Money au journal BQ
     * est un **choix d'organisation signalé au Comptable**, pas une donnée
     * réglementaire : un compte de trésorerie non-espèces se tient au journal
     * de banque. Il se change ici, à un seul endroit.
     *
     * ## Les numéros sont les DÉFAUTS (26/10/2026)
     *
     * Le compte qu'une pièce utilise est celui de la correspondance
     * ({@see CorrespondanceComptesService::compteDeTresorerie()}), modifiable
     * par l'administrateur ; le journal, lui, reste ici.
     *
     * @var array<string, array{compte: string, journal: string}>
     */
    public const TRESORERIES = [
        'caisse' => ['compte' => ComptesSyscohada::CAISSE, 'journal' => 'CAI'],
        'momo' => ['compte' => ComptesSyscohada::MOBILE_MONEY, 'journal' => 'BQ'],
        'banque' => ['compte' => ComptesSyscohada::BANQUE, 'journal' => 'BQ'],
    ];

    public function __construct(
        private readonly PasserEcritureService $ecritures,
        private readonly SequenceDocumentService $sequences,
        private readonly CorrespondanceComptesService $comptes,
    ) {
    }

    /**
     * Enregistre une dépense multi-lignes ET sa pièce comptable.
     *
     * ## L'identifiant du client et l'année du numéro (15/10/2026, lot S3)
     *
     * Pour la synchronisation des postes hors connexion (décision du Product
     * Owner du 15/10/2026), deux ajouts OPTIONNELS, sans effet sur les
     * appelants en ligne :
     *
     * - `$donnees['id']` — l'UUID posé par le poste. Une dépense qui existe
     *   déjà sous cet identifiant est RENDUE telle quelle, sans seconde pièce
     *   ni second numéro : un rejeu (coupure réseau, mémoire d'idempotence
     *   purgée) ne décaisse pas deux fois. Vérifié avant ET sous verrou dans
     *   la transaction — même raisonnement que `VenteService::enregistrer()`.
     * - `$anneeNumero` — l'année de la séquence `DEP-AAAA-…`. En ligne, la
     *   dépense est saisie le jour même et l'année du jour convient (défaut,
     *   inchangé). Une dépense du 31/12 synchronisée le 02/01 doit porter un
     *   numéro de SON exercice : la synchronisation passe l'année de
     *   `date_transaction`.
     *
     * @param  array{id?: string, date_transaction?: string, tresorerie?: string, centre_id?: string|null, libelle?: string, recu_path?: string|null, recu_sha256?: string|null, recu_taille?: int|null, recu_type?: string|null, lignes?: list<array{compte_charge: string, montant: string|float, libelle?: string|null, nature?: string, famille?: string, centre_id?: string}>}  $donnees
     *
     * @throws RuntimeException trésorerie inconnue, aucune ligne, montant nul,
     *                          ou pièce comptable refusée (compte, journal, exercice, centre)
     */
    public function enregistrer(array $donnees, ?User $utilisateur = null, ?int $anneeNumero = null): Depense
    {
        $identifiant = isset($donnees['id']) ? (string) $donnees['id'] : null;

        if ($identifiant !== null && ($existante = Depense::find($identifiant)) !== null) {
            return $existante;
        }

        $lignes = $donnees['lignes'] ?? [];

        if ($lignes === []) {
            throw new RuntimeException(__('depenses.sans_ligne'));
        }

        $tresorerieCode = (string) ($donnees['tresorerie'] ?? 'caisse');

        if (! array_key_exists($tresorerieCode, self::TRESORERIES)) {
            throw new RuntimeException(__('depenses.tresorerie_inconnue', ['code' => $tresorerieCode]));
        }

        // Le compte de la trésorerie est celui de la CORRESPONDANCE au moment de
        // passer la pièce (26/10/2026) ; `TRESORERIES` n'en porte que le défaut.
        $tresorerie = self::TRESORERIES[$tresorerieCode];
        $tresorerie['compte'] = $this->comptes->compteDeTresorerie($tresorerieCode);
        $date = (string) ($donnees['date_transaction'] ?? now()->toDateString());
        $libelle = (string) ($donnees['libelle'] ?? __('depenses.libelle_par_defaut'));

        $montantTotal = $this->totaliser($lignes);

        if (bccomp($montantTotal, '0.00', self::PRECISION) <= 0) {
            // Une dépense à zéro est comptablement vide : la pièce serait
            // refusée plus loin par `EcritureComptableService`, autant le dire
            // ici où le message a un sens pour l'opérateur.
            throw new RuntimeException(__('depenses.montant_nul'));
        }

        return DB::transaction(function () use (
            $donnees,
            $lignes,
            $tresorerieCode,
            $tresorerie,
            $date,
            $libelle,
            $montantTotal,
            $utilisateur,
            $identifiant,
            $anneeNumero
        ): Depense {
            if ($identifiant !== null
                && ($concurrente = Depense::query()->whereKey($identifiant)->lockForUpdate()->first()) !== null) {
                return $concurrente;
            }

            // La pièce est passée D'ABORD : si elle est refusée, la dépense
            // n'est jamais écrite, et l'opérateur reçoit la raison comptable
            // plutôt qu'un enregistrement muet.
            $piece = $this->ecritures->passerEtValider([
                'journal' => $tresorerie['journal'],
                'date' => $date,
                'libelle' => __('depenses.libelle_ecriture', ['libelle' => $libelle]),
                'lignes' => $this->lignesDeLaPiece($lignes, $tresorerie['compte'], $libelle, $montantTotal, isset($donnees['centre_id']) ? (string) $donnees['centre_id'] : null, CorrespondanceComptesService::roleDeTresorerie($tresorerieCode)),
            ]);

            $depense = Depense::create([
                ...($identifiant !== null ? ['id' => $identifiant] : []),
                'numero' => $this->sequences->suivant('depenses', self::PREFIXE_NUMERO, $anneeNumero),
                'date_transaction' => $date,
                'tresorerie' => $tresorerieCode,
                'compte_tresorerie' => $tresorerie['compte'],
                'montant_total' => $montantTotal,
                'libelle' => $libelle,
                'recu_path' => $donnees['recu_path'] ?? null,
                // L'empreinte du reçu (lot L4) : posée avec le fichier, jamais
                // devinée — et seulement quand il y en a une (une dépense sans
                // reçu n'écrit rien de plus qu'avant).
                ...array_filter([
                    'recu_sha256' => $donnees['recu_sha256'] ?? null,
                    'recu_taille' => $donnees['recu_taille'] ?? null,
                    'recu_type' => $donnees['recu_type'] ?? null,
                ], static fn ($valeur): bool => $valeur !== null),
                'ecriture_id' => $this->ligneDeTresorerie($piece, $tresorerie['compte']),
                'ecriture_refus' => null,
                'utilisateur_id' => $utilisateur !== null ? $utilisateur->id : auth()->id(),
                'lignes_json' => $lignes,
            ]);

            foreach ($lignes as $ligne) {
                LigneDepense::create([
                    'depense_id' => $depense->id,
                    'libelle' => $this->libelleLigne($ligne, $libelle),
                    'compte_charge' => (string) $ligne['compte_charge'],
                    'nature' => (string) ($ligne['nature'] ?? __('depenses.nature_par_defaut')),
                    'famille' => (string) ($ligne['famille'] ?? __('depenses.famille_par_defaut')),
                    'montant' => $this->montant($ligne['montant']),
                ]);
            }

            return $depense->refresh();
        });
    }

    /**
     * Rattrapage : passe la pièce d'une dépense qui n'en a pas.
     *
     * Sert les dépenses écrites avant ce lot, quand aucune écriture n'était
     * produite. Une dépense déjà comptabilisée est rendue telle quelle — la
     * repasser créerait une seconde pièce pour le même argent.
     *
     * En cas d'échec, la raison est PERSISTÉE sur la dépense (hors
     * transaction, pour survivre au rejet) puis relancée : l'écran voit
     * l'erreur, et la liste des dépenses garde la trace de ce qui bloque.
     *
     * Le CENTRE DE COÛT est un paramètre OBLIGATOIRE du geste : aucun compte
     * de charge du plan du PO n'a de centre par défaut, et la dépense n'en
     * mémorise pas. Passé à la pièce sur les charges ET sur la trésorerie, comme
     * `enregistrer()`. Vide, il est refusé par RG-12 (`depenses.centre_absent`).
     *
     * @throws Throwable la cause réelle du refus, jamais avalée
     */
    public function comptabiliser(Depense $depense, string $centreId): Depense
    {
        if ($depense->estComptabilisee()) {
            return $depense;
        }

        $tresorerie = self::TRESORERIES[$depense->tresorerie] ?? null;

        if ($tresorerie === null) {
            $this->consignerRefus($depense, __('depenses.tresorerie_inconnue', ['code' => $depense->tresorerie]));

            throw new RuntimeException(__('depenses.tresorerie_inconnue', ['code' => $depense->tresorerie]));
        }

        $tresorerie['compte'] = $this->comptes->compteDeTresorerie($depense->tresorerie);

        $lignes = $depense->lignes()->get()
            ->map(fn (LigneDepense $ligne): array => [
                'compte_charge' => $ligne->compte_charge,
                'libelle' => $ligne->libelle,
                'montant' => (string) $ligne->montant,
            ])
            ->all();

        if ($lignes === []) {
            $this->consignerRefus($depense, __('depenses.sans_ligne'));

            throw new RuntimeException(__('depenses.sans_ligne'));
        }

        try {
            $depense = DB::transaction(function () use ($depense, $tresorerie, $lignes, $centreId): Depense {
                $piece = $this->ecritures->passerEtValider([
                    'journal' => $tresorerie['journal'],
                    'date' => $depense->date_transaction->toDateString(),
                    'libelle' => __('depenses.libelle_ecriture', ['libelle' => $depense->libelle]),
                    'lignes' => $this->lignesDeLaPiece(
                        $lignes,
                        $tresorerie['compte'],
                        $depense->libelle,
                        (string) $depense->montant_total,
                        $centreId,
                        CorrespondanceComptesService::roleDeTresorerie($depense->tresorerie),
                    ),
                ]);

                $depense->update([
                    'ecriture_id' => $this->ligneDeTresorerie($piece, $tresorerie['compte']),
                    'ecriture_refus' => null,
                ]);

                return $depense->refresh();
            });
        } catch (Throwable $erreur) {
            // Pas un `catch` avalant : la raison est écrite sur la dépense
            // POUR ÊTRE VUE, et l'exception repart telle quelle.
            $this->consignerRefus($depense, $erreur->getMessage());

            throw $erreur;
        }

        return $depense;
    }

    /**
     * Construction de requête filtrée.
     *
     * `with('lignes')` est là pour une raison mesurable : l'écran affiche la
     * ventilation de chaque dépense, et sans lui chaque ligne de la liste
     * déclencherait sa propre requête (N+1).
     *
     * @param  array<string, mixed>  $filtres
     * @return Builder<Depense>
     */
    public function filtrer(array $filtres = []): Builder
    {
        $query = Depense::query()->with('lignes')->orderByDesc('date_transaction');

        if (! empty($filtres['recherche'])) {
            $terme = mb_strtolower(trim((string) $filtres['recherche']));
            $query->where(function (Builder $sous) use ($terme): void {
                $sous->whereRaw('LOWER(libelle) LIKE ?', ['%'.$terme.'%'])
                    ->orWhereRaw('LOWER(numero) LIKE ?', ['%'.$terme.'%']);
            });
        }

        if (! empty($filtres['du'])) {
            $query->where('date_transaction', '>=', $filtres['du']);
        }

        if (! empty($filtres['au'])) {
            $query->where('date_transaction', '<=', $filtres['au']);
        }

        if (! empty($filtres['tresorerie'])) {
            $query->where('tresorerie', $filtres['tresorerie']);
        }

        if (($filtres['non_comptabilisees'] ?? false) === true) {
            // Un état NOMMÉ plutôt que déduit d'un total qui ne tombe pas
            // juste : ce filtre est ce qui rend visibles les dépenses
            // antérieures à ce lot, celles que `comptabiliser()` doit reprendre.
            $query->whereNull('ecriture_id');
        }

        return $query;
    }

    /**
     * Les lignes de la pièce : les charges au débit, la trésorerie au crédit.
     *
     * La contrepartie de trésorerie est ajoutée ICI et pas par l'appelant :
     * une pièce à sens unique serait refusée par `EcritureComptableService`,
     * et c'est précisément ce que faisait le composant PWA — il n'envoyait que
     * les débits.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<array<string, mixed>>
     */
    private function lignesDeLaPiece(
        array $lignes,
        string $compteTresorerie,
        string $libelle,
        string $montantTotal,
        ?string $centreId = null,
        ?string $roleTresorerie = null,
    ): array {
        $piece = [];

        foreach ($lignes as $ligne) {
            $piece[] = [
                'compte' => (string) $ligne['compte_charge'],
                'libelle' => $this->libelleLigne($ligne, $libelle),
                'debit' => $this->montant($ligne['montant']),
                'credit' => '0.00',
                // Centre EXPLICITE (ligne, sinon dépense), sinon défaut du compte,
                // sinon refus RG-12 par `PasserEcritureService`.
                'centre_id' => ($ligne['centre_id'] ?? $centreId) ?: null,
            ];
        }

        $piece[] = [
            'compte' => $compteTresorerie,
            'role' => $roleTresorerie,
            'libelle' => $libelle,
            'debit' => '0.00',
            'credit' => $montantTotal,
            'centre_id' => $centreId ?: null,
        ];

        return $piece;
    }

    /**
     * L'identifiant de la ligne de trésorerie de la pièce.
     *
     * Voir la note de `Depense` : cette ligne est la seule dont il existe
     * exactement une par dépense. Elle est reconnue à son SENS — dans une
     * dépense, les charges sont au débit et la trésorerie seule au crédit —
     * plutôt qu'à sa position, qui n'est pas une garantie, ou à son compte,
     * qui coûterait une requête par ligne.
     *
     * @param  \Illuminate\Database\Eloquent\Collection<int, EcritureComptable>  $piece
     */
    private function ligneDeTresorerie(EloquentCollection $piece, string $compteTresorerie): string
    {
        foreach ($piece as $ecriture) {
            if (bccomp((string) $ecriture->credit, '0.00', self::PRECISION) > 0) {
                return $ecriture->id;
            }
        }

        // Inatteignable tant que `lignesDeLaPiece()` ajoute la contrepartie :
        // si ce refus tombe un jour, c'est que la pièce a changé de forme, et
        // le dire vaut mieux que de rattacher la dépense à une ligne de charge.
        throw new RuntimeException(__('depenses.ligne_tresorerie_absente', [
            'compte' => $compteTresorerie,
        ]));
    }

    private function consignerRefus(Depense $depense, string $raison): void
    {
        $depense->forceFill(['ecriture_refus' => $raison])->save();
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     */
    private function totaliser(array $lignes): string
    {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            // `bcadd`, jamais `array_sum` sur des flottants : deux lignes à
            // 0,1 et 0,2 ne font pas 0,3 en virgule flottante.
            $total = bcadd($total, $this->montant($ligne['montant']), self::PRECISION);
        }

        return $total;
    }

    /**
     * @param  array<string, mixed>  $ligne
     */
    private function libelleLigne(array $ligne, string $defaut): string
    {
        $propre = trim((string) ($ligne['libelle'] ?? ''));

        return $propre === '' ? $defaut : $propre;
    }

    private function montant(mixed $valeur): string
    {
        return bcadd((string) $valeur, '0', self::PRECISION);
    }

    /**
     * Le total décaissé d'un lot de dépenses — `bcadd` sur les chaînes
     * rendues par PDO, jamais `sum()` sur des flottants.
     *
     * Remonté de l'écran Dépenses (`Pwa\Livewire\Depenses\Depenses`) le
     * 02/09/2026 : la carte « Dépense courante » de l'accueil lit la même
     * formule que l'écran — deux formules divergeraient (PA-121).
     *
     * @param  EloquentCollection<int, Depense>  $depenses
     */
    public static function totalDecaisse(EloquentCollection $depenses): string
    {
        $total = '0.00';

        foreach ($depenses as $depense) {
            $total = bcadd($total, (string) $depense->montant_total, 2);
        }

        return $total;
    }

    /**
     * Le total des LIGNES d'une famille (« Marché », « Services ») — les
     * familles sont celles de `lignes_depense.famille`, PAS des centres de
     * coût (`depenses` ne porte aucun `centre_id` : le centre vit sur la
     * pièce comptable, RG-12). Même provenance et même date que
     * `totalDecaisse()` (PA-121).
     *
     * @param  EloquentCollection<int, Depense>  $depenses
     */
    public static function totalParFamille(EloquentCollection $depenses, string $famille): string
    {
        $total = '0.00';

        foreach ($depenses as $depense) {
            foreach ($depense->lignes as $ligne) {
                if ($ligne->famille === $famille) {
                    $total = bcadd($total, (string) $ligne->montant, 2);
                }
            }
        }

        return $total;
    }
}
