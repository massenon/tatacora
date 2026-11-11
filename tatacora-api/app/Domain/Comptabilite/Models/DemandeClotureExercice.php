<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Une demande de clôture (ou de réouverture) d'exercice reçue d'un poste et
 * EXÉCUTÉE par le serveur — voir `GestionnaireDemandesCloture`. Identifiant :
 * l'UUID du poste.
 *
 * @property string $id
 * @property string $exercice_id
 * @property int $annee
 * @property string $action
 * @property string|null $motif
 * @property string $issue
 * @property string $statut_exercice
 * @property string|null $piece_cloture
 * @property string|null $piece_a_nouveaux
 * @property string|null $resultat
 * @property string|null $archive_empreinte
 */
class DemandeClotureExercice extends Model
{
    use HasUuids;

    public const ISSUE_EXECUTEE = 'executee';

    public const ISSUE_DEJA_DANS_CET_ETAT = 'deja_dans_cet_etat';

    protected $table = 'demandes_cloture_exercice';

    protected $fillable = [
        'id', 'exercice_id', 'annee', 'action', 'motif', 'issue', 'statut_exercice', 'piece_cloture',
        'piece_a_nouveaux', 'resultat', 'archive_empreinte', 'poste_id', 'demandeur_id', 'demandee_le',
    ];

    protected function casts(): array
    {
        return [
            'annee' => 'integer',
            'demandee_le' => 'datetime',
        ];
    }
}
