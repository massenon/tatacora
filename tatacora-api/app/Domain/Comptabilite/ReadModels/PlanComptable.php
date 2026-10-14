<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\CompteComptable;
use Illuminate\Support\Collection;

/**
 * Le plan comptable et ses decomptes — `m10-plan-comptable.html`.
 *
 * @see EF-M10-01 Plan comptable conforme SYSCOHADA revise
 *
 * ## Trois decomptes, et chacun empeche un mensonge different
 *
 * **`total`** alimente le sous-titre du maitre (l.29 : « <N> comptes ») et
 * compte TOUT le referentiel, classes hors ecran comprises. Le faire porter sur
 * la seule classe filtree ferait afficher « 8 comptes » sur un plan qui en
 * compte 52.
 *
 * **`comptesParClasse`** couvre les **sept** classes de l'ecran, y compris
 * celles a zero. Une classe absente de la reponse serait indiscernable d'une
 * classe vide : Article 7, « — » et « 0 » ne disent pas la meme chose. Un
 * bouton « Classe 3 — Stocks » qui n'ouvre sur rien indique un plan a
 * completer, ce qui est une information ; son absence n'en est pas une.
 *
 * **`comptesParClasseHorsEcran`** est le decompte qui existe pour SIGNALER un
 * trou. Le schema admet les classes 8 (HAO) et 9 (analytique) ; l'ecran n'a
 * aucun bouton pour les atteindre. Sans ce champ, des comptes reels seraient
 * invisibles et le plan aurait l'air complet — « un plan SYSCOHADA incomplet se
 * signale, il ne s'invente pas ».
 *
 * **`sansNature`** compte les comptes dont `plan_comptable.nature` est nulle.
 * Le maitre indexe un badge de couleur sur cette valeur (l.80) : une nature
 * absente n'y produit aucun badge, donc rien du tout. Comptee, elle devient un
 * defaut de referentiel visible plutot qu'une case vide.
 */
final readonly class PlanComptable
{
    /**
     * @param  Collection<int, CompteComptable>  $comptes  Les lignes du tableau, filtre applique.
     * @param  array<array-key, int>  $comptesParClasse  Les sept classes de l'ecran, zeros compris.
     * @param  array<array-key, int>  $comptesParClasseHorsEcran  Classes 8 et 9 reellement peuplees.
     *
     * ⚠ `array-key` et non `string` : PHP contraint toute cle de tableau
     * numerique en entier, si bien que la classe « 1 » devient la cle `1`. Le
     * cast en objet de la ressource les rend en chaines dans le JSON, ce que
     * le client attend — mais le type PHP, lui, ne peut pas mentir.
     * @param  array{classe: string|null}  $filtresAppliques
     */
    public function __construct(
        public Collection $comptes,
        public int $total,
        public array $comptesParClasse,
        public array $comptesParClasseHorsEcran,
        public int $sansNature,
        public array $filtresAppliques,
    ) {
    }
}
