<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Correspondance UUID du poste → UUID du serveur, née d'une FUSION sur clé
 * naturelle (décision PO du 15/10/2026, référentiels créés hors connexion).
 *
 * Écrite UNIQUEMENT par `ResolveurCorrespondances` ; lue par chaque
 * gestionnaire qui traduit un identifiant cité dans un document.
 *
 * @property string $id
 * @property string $poste_id
 * @property string $table_concernee
 * @property string $id_poste
 * @property string $id_serveur
 * @property \Illuminate\Support\Carbon $created_at
 */
class CorrespondanceSynchronisation extends Model
{
    use HasUuids;

    public const UPDATED_AT = null;

    protected $table = 'correspondances_synchronisation';

    protected $fillable = ['id', 'poste_id', 'table_concernee', 'id_poste', 'id_serveur'];
}
