<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Trace d'un message effectivement parti — M12, onglet Journal du maitre.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html`, onglet Journal.
 *
 * ## Ce modele est en LECTURE SEULE, et ce n'est pas une precaution
 *
 * Aucun service de ce depot n'ecrit dans `notifications_envoyees`, et aucun
 * n'en ecrira tant que RG-20 ne sera pas levee : l'API WhatsApp Business
 * n'est pas contractee, aucun relais SMTP n'est configure, et l'application
 * Flutter qui porterait le canal Android n'expose aucun appareil enregistre
 * (verifie le 31/08/2026 — `grep` a zero sur `NotificationEnvoyee::create`
 * hors tests).
 *
 * Ecrire ici sans qu'un message parte reellement produirait exactement le
 * defaut que le maitre nomme en tete de sa page : « un message marque
 * "envoye" alors que rien n'est parti serait pire que pas de module du
 * tout : le Gerant croirait son client prevenu ».
 *
 * Le journal est donc rendu VIDE, et il dit pourquoi. Un journal vide lu sur
 * une table reelle n'affirme rien de faux ; c'est un compteur de diffusion
 * pose a cote de la table qui mentirait.
 *
 * @property string $id
 * @property string $modele_id
 * @property string $destinataire
 * @property \Illuminate\Support\Carbon $date_envoi
 * @property string $statut_remise
 * @property-read ModeleNotification $modele
 */
class NotificationEnvoyee extends Model
{
    use HasUuids;

    protected $table = 'notifications_envoyees';

    protected $fillable = ['id', 'modele_id', 'destinataire', 'date_envoi', 'statut_remise'];

    protected function casts(): array
    {
        return ['date_envoi' => 'datetime'];
    }

    /**
     * @return BelongsTo<ModeleNotification, $this>
     */
    public function modele(): BelongsTo
    {
        return $this->belongsTo(ModeleNotification::class, 'modele_id');
    }
}
