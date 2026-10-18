<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Un écart SIGNALÉ par la synchronisation d'un document — jamais corrigé en
 * silence, jamais transformé en refus (décisions PO du 15/10/2026, voir la
 * migration `create_anomalies_synchronisation`).
 *
 * Écrite UNIQUEMENT par `SignalementAnomalies`.
 *
 * @property string $id
 * @property string $poste_id
 * @property string|null $utilisateur_id
 * @property string $table_concernee
 * @property string $entite_id
 * @property string $type
 * @property string $reference
 * @property string|null $valeur_poste
 * @property string|null $valeur_serveur
 * @property array<string, mixed>|null $details
 * @property string $statut
 */
class AnomalieSynchronisation extends Model
{
    use HasUuids;

    public const ECART_PRIX = 'ecart_prix';

    public const VENTE_EN_RUPTURE = 'vente_en_rupture';

    public const VENTE_SESSION_INCONNUE = 'vente_session_inconnue';

    public const VENTE_SESSION_CLOTUREE = 'vente_session_cloturee';

    public const ECART_THEORIQUE_CAISSE = 'ecart_theorique_caisse';

    public const ECART_CONFORMITE_RECEPTION = 'ecart_conformite_reception';

    /**
     * Décision du PO du 15/10/2026 : un plat vendu hors connexion sans
     * composition (fiche vide, aucun lien direct) ne fait pas rejeter la
     * vente — la ligne n'a rien sorti du stock, et c'est signalé ici, une
     * anomalie par plat (`reference` = id du plat).
     */
    public const PLAT_SANS_COMPOSITION = 'plat_sans_composition';

    /**
     * Décision du PO du 15/10/2026 : une clôture de caisse n'est JAMAIS
     * bloquée. Celle d'une session que le serveur ne connaît pas (ouverture
     * refusée — une caisse était déjà ouverte sur ce point — ou jamais
     * reçue) est acceptée sans rien écrire d'autre que cette anomalie, qui
     * porte les chiffres du poste (fond, théorique, constaté, dates).
     */
    public const CLOTURE_SESSION_INCONNUE = 'cloture_session_inconnue';

    /**
     * Lot F4 (17/10/2026) : un guide créé sur un poste n'a pas de tarif
     * journalier (le poste ne le saisit pas). Il est enregistré à 0 — jamais
     * refusé, jamais un tarif deviné — et c'est signalé ici, à compléter.
     */
    public const GUIDE_SANS_TARIF = 'guide_sans_tarif';

    /**
     * Audit de couverture (18/10/2026) : un véhicule créé sur un poste n'a ni
     * année ni capacité (le poste ne les saisit pas) ; rangé avec l'année 0,
     * et SIGNALÉ — jamais une année devinée.
     */
    public const VEHICULE_SANS_ANNEE = 'vehicule_sans_annee';

    /**
     * Audit de couverture (18/10/2026) : le bulletin établi au serveur (son
     * barème, ses paramètres) n'a pas le net à payer que le poste avait
     * calculé. Le serveur fait foi ; l'écart est signalé, jamais aplani.
     */
    public const BULLETIN_ECART_NET = 'bulletin_ecart_net';

    /**
     * Lot F5d (17/10/2026) : un poste a encaissé une facture que le serveur
     * n'a pas certifiée (la certification n'est pas lancée, PA-17). L'argent
     * est réel : le paiement est enregistré, et c'est signalé ici.
     */
    public const PAIEMENT_FACTURE_NON_CERTIFIEE = 'paiement_facture_non_certifiee';

    /**
     * Lot F5d : la caisse du poste qui a reçu l'argent n'est pas connue du
     * serveur ; le paiement est rattaché à la caisse ouverte du serveur.
     */
    public const PAIEMENT_SESSION_INCONNUE = 'paiement_session_inconnue';

    protected $table = 'anomalies_synchronisation';

    protected $fillable = [
        'id', 'poste_id', 'utilisateur_id', 'table_concernee', 'entite_id', 'type',
        'reference', 'valeur_poste', 'valeur_serveur', 'details', 'statut',
    ];

    protected function casts(): array
    {
        return [
            'valeur_poste' => 'decimal:2',
            'valeur_serveur' => 'decimal:2',
            'details' => 'array',
        ];
    }
}
