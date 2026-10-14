<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Models;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Ventes\Observers\PanierObserver;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Le panier en cours de composition — UNE table pour les deux points de vente.
 *
 * ## Ce que ce modele remplace (PA-161)
 *
 * Jusqu'au 31/08/2026, le panier des clients heberges vivait dans la SESSION
 * HTTP et celui du comptoir dans une propriete de composant Livewire. Les deux
 * ont la meme faiblesse, et elle est concrete au Gite : une session expire au
 * bout de 120 minutes, est propre a un navigateur et disparait a la
 * deconnexion — le serveur qui prend la releve au comptoir voisin ne voyait
 * rien, et le client avait consomme sans que rien ne le porte. Le panier vit
 * desormais en base : il survit au changement d'equipe et de navigateur.
 *
 * ⚠ **Il ne part PAS au serveur d'un autre poste.** `paniers` n'est pas au
 * registre `TABLES_SYNCHRONISABLES` : une operation de synchronisation y
 * serait rejetee a chaque tentative. L'ecran dit « enregistre sur ce poste »,
 * jamais « en attente de synchronisation » — annoncer un depart qui n'aura pas
 * lieu serait PA-59/60/61.
 *
 * ## Le total est CALCULE, jamais stocke
 *
 * Aucune colonne `montant_total` : elle deviendrait fausse au premier article
 * ajoute par un autre poste, et c'est exactement le defaut que PA-126 nomme
 * (une colonne que rien n'alimente, rendue comme un fait). Le total vient des
 * lignes, par `bcadd`/`bcmul`, jamais par une egalite flottante.
 *
 * ## R-a — un seul panier ouvert par sejour, tenu en SERVICE
 *
 * La regle n'est pas dans le schema, et ce n'est pas un oubli : MySQL n'a pas
 * d'index partiel, et un index unique sur `(reservation_id, statut)`
 * interdirait un second panier CLOTURE sur le meme sejour. Elle vit dans
 * {@see \App\Domain\Ventes\Services\PanierService}, sous `lockForUpdate()`.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 R-a a R-d, §8 Q2 (option A)
 * @see RG-02 Aucune suppression — un panier se cloture, il ne disparait pas
 *
 * @property string $id
 * @property string|null $reservation_id
 * @property string $type_vente
 * @property string $point_vente
 * @property string|null $table_id
 * @property string|null $session_id
 * @property string $statut
 * @property string $remise_type
 * @property string $remise_valeur
 * @property string|null $vente_id
 * @property \Illuminate\Support\Carbon|null $cloture_at
 * @property-read \Illuminate\Database\Eloquent\Collection<int, LignePanier> $lignes
 */
#[ObservedBy(PanierObserver::class)]
class Panier extends Model
{
    use Auditable;
    use HasUuids;

    /** Precision de tout calcul monetaire — DECIMAL(15,2), jamais un flottant. */
    public const PRECISION = 2;

    /** Registre FERME des statuts — un panier est ouvert, ou cloture. */
    public const STATUT_OUVERT = 'ouvert';

    public const STATUT_CLOTURE = 'cloture';

    /**
     * Registre FERME des types de vente.
     *
     * C'est la SEULE difference de structure entre les deux points de vente,
     * avec `reservation_id` : « le POS n'est pas une structure, c'est un
     * ecran » (PA-98).
     */
    public const TYPE_COMPTANT = 'comptant';

    public const TYPE_SEJOUR = 'sejour';

    /**
     * Registre FERME des types de remise — le motif de `reservations`
     * (`remise_type`/`remise_valeur`, jamais un montant pré-calculé), porté au
     * panier par la directive Product Owner du 02/09/2026.
     */
    public const REMISE_AUCUNE = 'aucune';

    public const REMISE_POURCENTAGE = 'pourcentage';

    public const REMISE_MONTANT = 'montant';

    /** @var list<string> */
    public const TYPES_REMISE = [
        self::REMISE_AUCUNE,
        self::REMISE_POURCENTAGE,
        self::REMISE_MONTANT,
    ];

    protected $table = 'paniers';

    protected $fillable = [
        'id',
        'reservation_id',
        'type_vente',
        'point_vente',
        'table_id',
        'session_id',
        'statut',
        'remise_type',
        'remise_valeur',
        'vente_id',
        'cloture_at',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'remise_valeur' => 'decimal:2',
            'cloture_at' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * Les lignes, dans l'ordre ou elles ont ete portees au panier.
     *
     * L'ordre est explicite : sans lui, MySQL rend les lignes dans l'ordre
     * qu'il veut, et le ticket relu deux fois n'aurait pas la meme tete.
     *
     * @return HasMany<LignePanier, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LignePanier::class, 'panier_id')->orderBy('date_creation')->orderBy('id');
    }

    /**
     * @return BelongsTo<Reservation, $this>
     */
    public function reservation(): BelongsTo
    {
        return $this->belongsTo(Reservation::class, 'reservation_id');
    }

    /**
     * @return BelongsTo<SessionCaisse, $this>
     */
    public function session(): BelongsTo
    {
        return $this->belongsTo(SessionCaisse::class, 'session_id');
    }

    /**
     * @return BelongsTo<Vente, $this>
     */
    public function vente(): BelongsTo
    {
        return $this->belongsTo(Vente::class, 'vente_id');
    }

    public function estOuvert(): bool
    {
        return $this->statut === self::STATUT_OUVERT;
    }

    public function estCloture(): bool
    {
        return $this->statut === self::STATUT_CLOTURE;
    }

    /**
     * Vrai quand le panier a ete clos SANS qu'aucune vente n'en soit issue.
     *
     * Ce n'est pas une deduction hasardeuse : `vente_id` est pose dans la meme
     * transaction que la cloture sur vente, et la contrainte
     * `chk_paniers_cloture_coherente` interdit a un panier ouvert d'en porter
     * une. Un panier cloture sans vente a donc ete abandonne, et l'etat se lit
     * de la donnee au lieu d'exiger une colonne de plus.
     */
    public function estAbandonne(): bool
    {
        return $this->estCloture() && $this->vente_id === null;
    }

    /**
     * Le total BRUT des lignes du panier, en bcmath — jamais en flottant.
     */
    public function total(): string
    {
        $total = '0.00';

        foreach ($this->lignes as $ligne) {
            $total = bcadd($total, $ligne->montant(), self::PRECISION);
        }

        return $total;
    }

    /**
     * Le montant de la remise, DÉRIVÉ du type et de la valeur — directive
     * Product Owner du 02/09/2026 (remise en % ou en FCFA sur les deux POS).
     *
     * @throws \RuntimeException remise hors bornes (voir {@see remiseSur()})
     */
    public function montantRemise(): string
    {
        return self::remiseSur($this->total(), (string) $this->remise_type, (string) $this->remise_valeur);
    }

    /**
     * Le TOTAL NET du panier : total des lignes − remise.
     *
     * C'est L'UNIQUE formule du net — l'encaissement (`VenteService`), la
     * facture du séjour et la pièce comptable passent tous par elle (via
     * {@see remiseSur()} pour le service, qui ne reçoit pas le modèle) :
     * deux arithmétiques du même panier divergeraient au premier changement
     * de règle, et l'écart ne se verrait qu'au comptage de caisse.
     */
    public function totalNet(): string
    {
        return bcsub($this->total(), $this->montantRemise(), self::PRECISION);
    }

    /**
     * Le montant de la remise pour L'AFFICHAGE : `0.00` quand la remise
     * stockée est devenue hors bornes — une ligne retirée après coup peut
     * faire dépasser au montant fixe le total restant. L'écran rend alors le
     * BRUT plutôt que de tomber en erreur ; l'ENCAISSEMENT, lui, passe par
     * {@see remiseSur()} et refuse en nommant la cause — la tolérance est
     * ici, jamais sur le chemin de l'argent.
     */
    public function remisePourAffichage(): string
    {
        try {
            return $this->montantRemise();
        } catch (\RuntimeException) {
            return '0.00';
        }
    }

    /** Le net pour l'affichage — même tolérance que {@see remisePourAffichage()}. */
    public function totalNetPourAffichage(): string
    {
        return bcsub($this->total(), $this->remisePourAffichage(), self::PRECISION);
    }

    /**
     * Le montant de remise sur un total donné — AUTEUR UNIQUE de la règle.
     *
     * Bornes (directive PO 02/09/2026) : un pourcentage vit entre 0 et 100,
     * un montant entre 0 et le total — un net NÉGATIF ne doit jamais exister,
     * ni à l'écran ni sur la pièce comptable. Le refus est levé ICI, pas
     * seulement à la saisie : une remise en francs devenue supérieure au
     * total (ligne retirée après coup) doit faire refuser l'encaissement,
     * jamais produire un encaissement négatif plausible.
     *
     * `bccomp`/`bcdiv`/`bcmul`, jamais une arithmétique flottante : ce sont
     * des montants. L'arrondi du pourcentage est celui de la fiche de
     * réservation (échelle 4 puis division par 100 à l'échelle 2) — même
     * règle, même centime.
     *
     * @throws \RuntimeException type inconnu, valeur négative, pourcentage
     *                           au-delà de 100 ou montant au-delà du total
     */
    public static function remiseSur(string $total, string $type, string $valeur): string
    {
        if ($type === self::REMISE_AUCUNE || $type === '') {
            return '0.00';
        }

        if (! in_array($type, self::TYPES_REMISE, true)) {
            throw new \RuntimeException(__('ventes.remise_type_inconnu'));
        }

        if (! is_numeric($valeur) || bccomp($valeur, '0.00', self::PRECISION) < 0) {
            throw new \RuntimeException(__('ventes.remise_valeur_invalide'));
        }

        if ($type === self::REMISE_POURCENTAGE) {
            if (bccomp($valeur, '100.00', self::PRECISION) > 0) {
                throw new \RuntimeException(__('ventes.remise_pourcentage_hors_bornes'));
            }

            return bcdiv(bcmul($total, $valeur, 4), '100', self::PRECISION);
        }

        if (bccomp($valeur, $total, self::PRECISION) > 0) {
            throw new \RuntimeException(__('ventes.remise_superieure_au_total'));
        }

        return bcadd($valeur, '0', self::PRECISION);
    }

    /**
     * Les modules presents au panier — ce qui commande les droits a exiger.
     *
     * Un ticket qui mele le bar et le restaurant est une ecriture sur DEUX
     * modules : n'en verifier qu'un donnerait par le navigateur ce que l'API
     * refuse (PA-65).
     *
     * @return list<string>
     */
    public function modules(): array
    {
        $modules = [];

        foreach ($this->lignes as $ligne) {
            $modules[$ligne->module] = true;
        }

        return array_keys($modules);
    }

    /**
     * La ventilation du panier par module, pour l'affichage.
     *
     * @return array<string, string>
     */
    public function ventilationParModule(): array
    {
        $ventilation = [];

        foreach ($this->lignes as $ligne) {
            $ventilation[$ligne->module] = bcadd(
                $ventilation[$ligne->module] ?? '0.00',
                $ligne->montant(),
                self::PRECISION,
            );
        }

        return $ventilation;
    }
}
