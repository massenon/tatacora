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
