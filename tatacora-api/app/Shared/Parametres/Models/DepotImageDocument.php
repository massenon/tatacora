<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * La trace d'un dépôt ou d'un retrait de la signature / du cachet fait depuis un poste — voir
 * `GestionnaireImagesDocument`. Identifiant : l'UUID du poste. Aucun octet d'image ici : le
 * fichier est rangé par `ApparenceEtablissementService`, comme au web.
 *
 * @property string $id
 * @property string $nature
 * @property string $action
 * @property string|null $type_mime
 * @property string|null $empreinte
 * @property string $poste_id
 */
class DepotImageDocument extends Model
{
    use HasUuids;

    public const ACTION_DEPOSER = 'deposer';

    public const ACTION_RETIRER = 'retirer';

    protected $table = 'depots_images_document';

    protected $fillable = ['id', 'nature', 'action', 'type_mime', 'empreinte', 'poste_id', 'auteur_id'];
}
