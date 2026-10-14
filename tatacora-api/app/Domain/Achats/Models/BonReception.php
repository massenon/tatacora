<?php

declare(strict_types=1);

namespace App\Domain\Achats\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Bon de reception (M7, EF-M7-03).
 *
 * **Limite structurelle connue — PA-39 :** cette table n'a AUCUNE table de
 * lignes. Elle enregistre un en-tete et un drapeau `conformite`, mais aucune
 * quantite recue par article. Les quantites reellement receptionnees ne sont
 * donc tracees que par les `mouvements_stock` d'entree generes a la reception.
 *
 * @property string $id
 * @property string $commande_id
 * @property \Illuminate\Support\Carbon $date_reception
 * @property string $utilisateur_id
 * @property string $conformite
 */
class BonReception extends Model
{
    use HasUuids;

    /**
     * Registre FERMÉ du verdict RG-10, tel que l'enum du schéma le porte.
     *
     * L'écran du prototype ne connaît que « Conformes » / « Avec écart » ;
     * regrouper `partielle` et `non_conforme` ici perdrait l'information qui
     * compte — recevoir moins que commandé ouvre une créance sur le
     * fournisseur, recevoir un article hors commande est une anomalie d'une
     * tout autre nature.
     *
     * @var list<string>
     */
    public const CONFORMITES = ['totale', 'partielle', 'non_conforme'];

    protected $table = 'bons_reception';

    protected $fillable = ['id', 'commande_id', 'date_reception', 'utilisateur_id', 'conformite'];

    protected function casts(): array
    {
        return ['date_reception' => 'date'];
    }

    /**
     * @return BelongsTo<CommandeAchat, $this>
     */
    public function commande(): BelongsTo
    {
        return $this->belongsTo(CommandeAchat::class, 'commande_id');
    }
}
