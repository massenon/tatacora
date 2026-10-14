<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Modele de message d'un evenement et d'un canal — M12.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html`, onglet Modeles.
 *
 * ## Un modele est une CONFIGURATION, jamais une promesse d'envoi
 *
 * `actif` dit que le modele « sera pris en compte a la prochaine detection »
 * (mot du maitre) — il ne dit pas qu'un message part. Aucun canal n'est
 * branche : l'API WhatsApp Business n'est pas contractee, aucun relais SMTP
 * n'est configure, et RG-20 (diffusion automatique) reste la seule des vingt
 * regles de gestion non implementee (verifie le 31/08/2026).
 *
 * C'est la raison pour laquelle ce modele n'expose AUCUNE methode d'envoi et
 * aucun compteur de diffusion : un `envoyer()` qui ne partirait pas, ou un
 * `dernier_envoi` que rien n'ecrirait, serait la forme la plus directe de
 * PA-59/60/61 — un indicateur qui affirme un etat que rien n'a verifie.
 *
 * ## `evenement` porte le CODE du declencheur, pas une phrase
 *
 * La migration d'origine l'ecrit elle-meme (`create_notifications.php` l.16 :
 * « 'reservation_creee', 'seuil_stock_atteint'… »). Le libelle lisible vit
 * dans `RegistreDeclencheurs`, registre FERME : deux listes de libelles, une
 * en base et une au code, finiraient par diverger — c'est le defaut que ce
 * depot a rencontre cinq fois sur ses seeders (PA-161).
 *
 * @property string $id
 * @property string $evenement
 * @property string $canal
 * @property string|null $objet
 * @property string $contenu_template
 * @property bool $actif
 */
class ModeleNotification extends Model
{
    use HasUuids;

    protected $table = 'modeles_notification';

    protected $fillable = ['id', 'evenement', 'canal', 'objet', 'contenu_template', 'actif'];

    protected function casts(): array
    {
        return ['actif' => 'boolean'];
    }

    /**
     * Les variables `{nom}` encore presentes dans le modele.
     *
     * @return list<string>
     */
    public function variablesCitees(): array
    {
        $texte = $this->contenu_template.' '.(string) $this->objet;

        if (preg_match_all('/\{([a-z_]+)\}/', $texte, $trouves) === 0) {
            return [];
        }

        return array_values(array_unique($trouves[1]));
    }

    /**
     * @return HasMany<NotificationEnvoyee, $this>
     */
    public function envois(): HasMany
    {
        return $this->hasMany(NotificationEnvoyee::class, 'modele_id');
    }
}
