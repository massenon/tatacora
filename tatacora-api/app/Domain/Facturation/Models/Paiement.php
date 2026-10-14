<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Encaissement d'une facture — la moitié restante de PA-21, fermée le
 * 01/09/2026 (PA-165).
 *
 * ## La table existait depuis l'origine, sans AUCUN writer
 *
 * `create_facturation.php` l.67 crée `paiements` ; jusqu'à ce lot, rien dans
 * tout `app/` n'y écrivait — c'est ce qui faisait du solde client de M3 un
 * MAXIMUM (PA-21), aucun encaissement ne pouvant réduire une créance.
 *
 * ## Le schéma dit deux choses, et elles sont volontaires
 *
 * `facture_id` NOT NULL : un encaissement règle une FACTURE — la pièce
 * opposable — jamais un « client » en général. `session_id` NOT NULL : il se
 * produit dans une session de caisse OUVERTE, celle du tiroir qui reçoit
 * l'argent (RG-15 : on sait qui a encaissé, où, quand).
 *
 * ## Aucune annulation n'existe, et c'est nommé
 *
 * Le schéma ne porte pas de colonne de statut : un paiement erroné n'a pas de
 * geste d'annulation propre (même lacune assumée que `contrats_location`,
 * PA-50). La correction comptable passe par la contre-passation de la pièce ;
 * le geste métier complet (marquer le paiement annulé) attend une colonne,
 * décision d'Architecte — ne pas la contourner par une suppression, que
 * `PaiementPolicy::delete()` refuse.
 *
 * @see EF-M2-03 Encaissement des factures
 * @see RG-15 Journalisation (trait Auditable)
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-21, PA-165
 *
 * @property string $id
 * @property string $facture_id
 * @property string $session_id
 * @property string $mode_paiement
 * @property string $montant
 * @property \Illuminate\Support\Carbon $date_paiement
 * @property string $statut
 * @property string|null $motif_annulation
 * @property string|null $annule_par_id
 * @property \Illuminate\Support\Carbon|null $date_annulation
 */
class Paiement extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'paiements';

    /**
     * Le registre FERMÉ du schéma (`enum` MySQL) — le relire d'ici, jamais le
     * recopier dans un écran.
     *
     * @var list<string>
     */
    public const MODES = ['especes', 'mobile_money', 'carte', 'virement'];

    protected $fillable = [
        'id',
        'facture_id',
        'session_id',
        'mode_paiement',
        'montant',
        'date_paiement',
        // Annulation (PA-168) — écrites EXCLUSIVEMENT par
        // EncaissementFactureService::annuler(), jamais par un formulaire.
        'statut',
        'motif_annulation',
        'annule_par_id',
        'date_annulation',
    ];

    protected function casts(): array
    {
        return [
            'montant' => 'decimal:2',
            'date_paiement' => 'datetime',
            'date_annulation' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Facture, $this>
     */
    public function facture(): BelongsTo
    {
        return $this->belongsTo(Facture::class, 'facture_id');
    }

    /**
     * @return BelongsTo<SessionCaisse, $this>
     */
    public function session(): BelongsTo
    {
        return $this->belongsTo(SessionCaisse::class, 'session_id');
    }

    /**
     * L'opérateur qui a encaissé — colonne d'audit du trait `Auditable`
     * (PA-165) : la « colonne Par » du relevé de recouvrements (M3) et de
     * l'onglet Dettes fournisseurs (M7) la lit par cette relation, jamais un
     * second `utilisateur_id` dédié.
     *
     * @return BelongsTo<User, $this>
     */
    public function utilisateurCreation(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_creation_id');
    }
}
