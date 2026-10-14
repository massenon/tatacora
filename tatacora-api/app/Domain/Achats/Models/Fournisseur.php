<?php

declare(strict_types=1);

namespace App\Domain\Achats\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Référentiel fournisseurs (M7).
 *
 * Référencé en clé étrangère par `commandes_achat.fournisseur_id` — jamais un
 * champ texte libre. L'anti-pattern « Fournisseur en texte libre » a été trouvé
 * dans le prototype et ne doit pas être reproduit : il casse silencieusement le
 * rapprochement à trois voies (EF-M7-04), qui suppose une relation exacte.
 *
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $raison_sociale
 * @property string|null $contact
 * @property string|null $categorie
 * @property string|null $conditions_paiement
 * @property string|null $evaluation
 * @property bool $actif l'ARCHIVE du referentiel (03/09/2026) — hors `$fillable` : seul `ReferentielFournisseurService` la bascule
 */
class Fournisseur extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Registre FERMÉ de l'évaluation qualitative — EF-M7-05.
     *
     * Ce sont les valeurs de l'`enum` MySQL, pas les libellés affichés par le
     * prototype (« Excellent », « À revoir »). La traduction est l'affaire du
     * client ; accepter les libellés ici ferait rejeter l'écriture par la base
     * avec un message SQL illisible.
     *
     * @var list<string>
     */
    public const EVALUATIONS = ['excellent', 'bon', 'moyen', 'a_revoir'];

    /**
     * Pagination du référentiel. Contrairement aux points de stockage
     * (`/stocks/points`, rendus ENTIERS parce qu'aucune recherche ne les
     * atteint), le sélecteur de fournisseur du prototype est un champ de
     * recherche : un fournisseur absent de la première page reste joignable en
     * tapant son nom. La pagination n'y cache donc rien.
     *
     * Aucun total n'est calculé sur l'ensemble filtré et rendu au-dessus d'une
     * page de lignes : c'est l'autre danger, celui qui afficherait deux
     * vérités sur le même écran.
     */
    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'fournisseurs';

    protected $fillable = [
        'id',
        'raison_sociale',
        'contact',
        'categorie',
        'conditions_paiement',
        'evaluation',
    ];

    protected function casts(): array
    {
        return [
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
            // L'ARCHIVE du référentiel (03/09/2026). Absente de `$fillable`
            // volontairement : `ReferentielFournisseurService` est le seul
            // chemin qui la bascule, et il porte le verrou d'engagement.
            'actif' => 'boolean',
        ];
    }
}
