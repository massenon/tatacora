<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Centre de cout (M10) — Hebergement, Restauration, Bar, Tourisme, Vehicules,
 * RH, Structure.
 *
 * @see RG-12 Centre de cout obligatoire sur toute ecriture — `centre_id` est
 *      NOT NULL au schema, la regle est donc portee par la base et pas
 *      seulement par du code.
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §2 compte le centre de cout parmi les
 * colonnes du Journal General. `m10-journal.html` ne l'affiche pas : le maitre
 * fait foi sur ce qui se voit, la documentation sur ce qui se calcule, et une
 * ligne de journal sans son centre serait inexploitable pour la comptabilite
 * analytique (EF-M10-03). Il descend donc dans la ressource, imputation reelle
 * de l'ecriture — jamais deduite du numero de compte, contrairement au
 * `CENTRES_COUT_PAR_COMPTE` de demonstration du maitre
 * (`m10-comptabilite-data.js` l.64-81), qui note lui-meme que ce raccourci ne
 * vaut pas en production.
 *
 * @property string $id
 * @property string $libelle
 * @property string|null $type
 */
class CentreCout extends Model
{
    use HasUuids;

    protected $table = 'centres_cout';

    protected $fillable = ['id', 'libelle', 'type'];
}
