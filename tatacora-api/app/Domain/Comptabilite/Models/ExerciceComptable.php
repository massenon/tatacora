<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Exercice comptable (M10) — le cadre de TOUT etat de ce module.
 *
 * @see EF-M10-07 Cloture comptable periodique
 * @see RG-11 L'exercice porte un verrou AU-DESSUS du verrou par ecriture
 *
 * ## Pourquoi ce modele existait pas, et pourquoi il est indispensable ici
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §1 : « **Tout ecran de M10 (Journal, Grand
 * Livre, Balance, Etats financiers) filtre systematiquement par
 * `exercice_id`** — jamais un etat "toutes annees confondues" par defaut, qui
 * n'aurait pas de sens comptable. »
 *
 * C'est une regle de calcul, et l'Article 0 de `DIRECTIVE_CONFORMITE_100.md`
 * donne la documentation pour autorite sur les regles de calcul. Les quatre
 * pages du maitre n'affichent pourtant aucun selecteur d'exercice : leur jeu de
 * demonstration n'en contient qu'un seul, implicite. L'API, elle, doit le
 * demander — et donc pouvoir le faire choisir, sans quoi le client n'aurait
 * aucun moyen de connaitre un seul identifiant d'exercice. C'est la forme exacte
 * de PA-128 : une donnee absente de l'API est une donnee absente du client.
 *
 * ## Le cycle de vie est un registre FERME
 *
 * `ouvert` -> `en_cloture` -> `cloture`, avec retour possible de `en_cloture`
 * vers `ouvert` si une anomalie est detectee. Aucune valeur n'est admise hors
 * de cette liste : l'`enum` du schema la tient deja, la constante la nomme pour
 * que le code n'ait pas a la deviner.
 *
 * @property string $id
 * @property int $annee
 * @property \Illuminate\Support\Carbon $date_debut
 * @property \Illuminate\Support\Carbon $date_fin
 * @property string $statut
 * @property \Illuminate\Support\Carbon|null $date_cloture
 * @property string|null $evenements_posterieurs
 * @property string|null $utilisateur_cloture_id
 */
class ExerciceComptable extends Model
{
    use HasUuids;

    /** Registre ferme des statuts — `MODULE_COMPTABILITE_COMPLET.md` §1. */
    public const STATUTS = ['ouvert', 'en_cloture', 'cloture'];

    protected $table = 'exercices_comptables';

    protected $fillable = [
        'id', 'annee', 'date_debut', 'date_fin', 'statut',
        'date_cloture', 'evenements_posterieurs', 'utilisateur_cloture_id',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'annee' => 'integer',
            'date_debut' => 'date',
            'date_fin' => 'date',
            'date_cloture' => 'datetime',
        ];
    }

    /**
     * @return HasMany<EcritureComptable, $this>
     */
    public function ecritures(): HasMany
    {
        return $this->hasMany(EcritureComptable::class, 'exercice_id');
    }

    /**
     * La saisie est-elle encore possible sur cet exercice ?
     *
     * ⚠ **Cette methode est un RENSEIGNEMENT, pas une garde.** La garde reelle
     * est `EcritureComptableObserver`, seul chemin qui couvre la synchronisation
     * differee, les jobs et les commandes artisan (RG-11). Un predicat qui
     * dirait ici l'inverse de ce que l'Observer applique serait exactement le
     * defaut de PA-61 : un indicateur qui affirme un etat qu'il n'a pas
     * verifie.
     *
     * Elle rend donc ce que l'Observer REFUSE REELLEMENT aujourd'hui, pas ce que
     * la documentation prescrit — et l'ecart entre les deux est ouvert en
     * question dans le rapport de ce lot : `MODULE_COMPTABILITE_COMPLET.md` §1
     * annonce la saisie bloquee des `en_cloture`, l'Observer ne ferme que
     * `cloture`.
     */
    public function saisieRefuseeParObserver(): bool
    {
        return $this->statut === 'cloture';
    }
}
