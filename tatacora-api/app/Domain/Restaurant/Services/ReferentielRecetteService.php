<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Models\Recette;

/**
 * Référentiel des fiches techniques — création (M4, EF-M4-02).
 *
 * Extrait de `RecetteController` (PA-159, lot 0b) : `LARAVEL_PWA.md` §3
 * impose qu'un composant Livewire appelle un Service de domaine — ce service
 * est le point d'entrée commun de l'API et de la PWA.
 *
 * ## Créer une recette n'écrit PAS sa composition
 *
 * La fiche naît vide : la composition (les vraies clés étrangères vers
 * `articles`, avec leurs quantités) passe exclusivement par
 * `CompositionRecetteService::remplacerComposition()`, seul chemin qui écrit
 * aussi `recettes.cout_matiere_calcule`. Dupliquer cette écriture ici
 * produirait deux coûts matière calculés par deux codes — PA-23.
 *
 * ⚠ « Aucune modification de l'entête de recette n'est exposée » A CESSÉ
 * D'ÊTRE VRAI le 04/09/2026, et le motif d'origine — « le contrôleur n'en
 * offrait pas, et en ajouter une ici élargirait le contrat HTTP hors de ce
 * lot » — ne portait que sur le PÉRIMÈTRE d'un lot, jamais sur une règle.
 * Datez la raison d'un refus et vérifiez-la avant de vous y fier (PA-144).
 *
 * `modifier()` n'ajoute AUCUNE route : son unique appelant est l'écran PWA
 * « Fiches techniques », qui compose les fiches existantes. Sans lui, ouvrir
 * une fiche pour la composer aurait affiché un libellé qu'aucun geste ne peut
 * corriger — un champ inerte au milieu d'un formulaire d'écriture.
 *
 * @see EF-M4-02 Gestion des fiches techniques
 * @see RG-15 Journalisation (trait Auditable sur Recette)
 */
class ReferentielRecetteService
{
    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerRecetteRequest` ou les règles qui en dérivent
     */
    public function creer(array $donnees): Recette
    {
        return Recette::create($donnees);
    }

    /**
     * Met à jour l'ENTÊTE d'une fiche — jamais sa composition.
     *
     * La séparation est la même qu'à la création, et pour la même raison :
     * `recettes.cout_matiere_calcule` n'a qu'un auteur,
     * `CompositionRecetteService::recalculer()`. Laisser passer cette colonne
     * ici produirait un coût matière écrit par deux codes, dont l'un ne
     * connaîtrait pas les lignes — PA-23, puis PA-126.
     *
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(Recette $recette, array $donnees): Recette
    {
        unset($donnees['cout_matiere_calcule']);

        $recette->update($donnees);

        return $recette->refresh();
    }
}
