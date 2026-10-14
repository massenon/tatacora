<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Parametre metier modifiable par l'Administrateur sans deploiement (RG-10).
 *
 * **Jamais un secret technique.** Cette table est lisible par tout profil ayant
 * acces a l'ecran Parametres : y stocker une cle API MECeF ou WhatsApp la
 * rendrait consultable par un Administrateur, alors qu'elle engage
 * juridiquement l'entreprise vis-a-vis de la DGI ou de Meta. Les secrets vont
 * en `.env`, sans exception (MECEF_INTEGRATION_SPEC.md §7.1).
 *
 * ## Le journal d'audit porte l'ANCIENNE valeur
 *
 * Le trait `Auditable` ecrit un avant/apres dans `journal_audit` a chaque
 * modification (RG-15). Sur cette table, c'est l'ancienne valeur qui compte :
 * apres une erreur de saisie sur un taux, la question n'est jamais « qui ? »
 * mais « on revient a quoi ? ». Sans elle, l'erreur n'est pas corrigeable.
 *
 * @property string $id
 * @property string $cle
 * @property string|null $valeur
 * @property string|null $description
 */
class ParametreSysteme extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'parametres_systeme';

    protected $fillable = ['id', 'cle', 'valeur', 'description', 'utilisateur_modification_id'];
}
