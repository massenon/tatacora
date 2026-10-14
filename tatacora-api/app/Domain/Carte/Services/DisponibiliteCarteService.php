<?php

declare(strict_types=1);

namespace App\Domain\Carte\Services;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Restaurant\Models\Plat;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Poser et lever l'indisponibilité d'un article de carte — M4 et M5.
 *
 * **Unique point d'entrée d'écriture sur `indisponibilites_carte`.**
 *
 * ## Ce que ce service remplace
 *
 * `CarteBar::enregistrerDispo()` et `CarteRestaurant::enregistrerDispo()`
 * écrivaient dans `Session::put('bar_boissons_indisponibles', …)`. Un plat
 * retiré revenait tout seul à l'expiration de la session, aucun autre poste ne
 * le voyait retiré, et la décision n'était imputable à personne. Trois défauts
 * pour un seul stockage.
 *
 * ## Lever, c'est écrire — jamais supprimer
 *
 * `lever()` renseigne `date_retour_disponibilite` sur la ligne en cours.
 * Effacer la ligne effacerait l'historique des ruptures, qui est précisément
 * ce sur quoi se décide un réapprovisionnement. Le « D » de CRUD n'existe
 * nulle part dans ce dépôt.
 *
 * ## Une seule indisponibilité en cours à la fois
 *
 * MySQL n'a pas d'index unique partiel (même limite que Q2 de
 * `PROPOSITION_MODELE_PANIER_POS.md`) : la règle est tenue par le service, sous
 * verrou pessimiste, jamais par une simple lecture avant écriture. Sans le
 * verrou, deux postes retirant le même plat à la même seconde créeraient deux
 * lignes ouvertes, et lever l'une laisserait l'article indisponible sans
 * raison visible.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see RG-15 Journalisation — `utilisateur_id` est NOT NULL
 */
class DisponibiliteCarteService
{
    /**
     * Retire un article de la carte du jour.
     *
     * @param  string  $motif  une clé de `IndisponibiliteCarte::MOTIFS`
     *
     * @throws RuntimeException motif hors registre, article déjà indisponible,
     *                          ou décision non imputable
     */
    public function rendreIndisponible(
        CarteBoisson|Plat $article,
        string $motif,
        ?string $commentaire = null,
        ?string $utilisateurId = null,
    ): IndisponibiliteCarte {
        if (! array_key_exists($motif, IndisponibiliteCarte::MOTIFS)) {
            // Registre fermé : un motif inconnu serait accepté par la colonne
            // `enum` sous forme de chaîne vide sur MySQL non strict, et
            // `estTemporaire()` échouerait ensuite sur une clé absente.
            throw new RuntimeException(__('carte.motif_inconnu', ['motif' => $motif]));
        }

        $auteur = $this->auteur($utilisateurId);
        $colonne = $this->colonneCible($article);

        return DB::transaction(function () use ($article, $colonne, $motif, $commentaire, $auteur): IndisponibiliteCarte {
            $enCours = IndisponibiliteCarte::query()
                ->where($colonne, $article->getKey())
                ->enCours()
                ->lockForUpdate()
                ->first();

            if ($enCours !== null) {
                throw new RuntimeException(__('carte.deja_indisponible', [
                    'article' => $article->libelle,
                    'motif' => $enCours->libelleMotif(),
                ]));
            }

            return IndisponibiliteCarte::create([
                $colonne => $article->getKey(),
                'motif' => $motif,
                // Un commentaire vide n'est pas un commentaire : le stocker
                // ferait apparaître une ligne de précision vide à l'écran.
                'commentaire' => $this->commentaireOuNull($commentaire),
                'date_indisponibilite' => now(),
                'utilisateur_id' => $auteur,
            ]);
        });
    }

    /**
     * Remet l'article à la carte. Rend l'indisponibilité levée.
     *
     * @throws RuntimeException si l'article n'était pas indisponible
     */
    public function rendreDisponible(
        CarteBoisson|Plat $article,
        ?string $utilisateurId = null,
    ): IndisponibiliteCarte {
        $auteur = $this->auteur($utilisateurId);
        $colonne = $this->colonneCible($article);

        return DB::transaction(function () use ($article, $colonne, $auteur): IndisponibiliteCarte {
            $enCours = IndisponibiliteCarte::query()
                ->where($colonne, $article->getKey())
                ->enCours()
                ->lockForUpdate()
                ->first();

            if ($enCours === null) {
                // Silence impossible : « remis à la carte » sur un article qui
                // y était déjà laisserait croire qu'une action a eu lieu.
                throw new RuntimeException(__('carte.pas_indisponible', [
                    'article' => $article->libelle,
                ]));
            }

            $enCours->update([
                'date_retour_disponibilite' => now(),
                'utilisateur_retour_id' => $auteur,
            ]);

            return $enCours->refresh();
        });
    }

    /**
     * L'indisponibilité en cours d'un article, ou `null` s'il est à la carte.
     */
    public function indisponibilite(CarteBoisson|Plat $article): ?IndisponibiliteCarte
    {
        return IndisponibiliteCarte::query()
            ->where($this->colonneCible($article), $article->getKey())
            ->enCours()
            ->first();
    }

    public function estDisponible(CarteBoisson|Plat $article): bool
    {
        return $this->indisponibilite($article) === null;
    }

    /**
     * Indisponibilités en cours du rayon, indexées par identifiant d'article.
     *
     * UNE requête pour tout l'écran : appeler `indisponibilite()` par ligne
     * ferait N+1 sur une carte de cinquante articles.
     *
     * @param  string  $rayon `boisson` ou `plat` — registre fermé, contrôlé
     *                        au moment de l'appel plutôt que promis par une annotation
     * @return Collection<string, IndisponibiliteCarte>
     */
    public function indisponibilitesEnCours(string $rayon): Collection
    {
        $colonne = match ($rayon) {
            'boisson' => 'boisson_id',
            'plat' => 'plat_id',
            default => throw new RuntimeException(__('carte.rayon_inconnu', ['rayon' => $rayon])),
        };

        return IndisponibiliteCarte::query()
            ->enCours()
            ->whereNotNull($colonne)
            ->get()
            ->keyBy($colonne);
    }

    /**
     * Les deux cibles vivent dans deux tables distinctes, donc deux colonnes
     * distinctes : c'est ce qui permet à chacune d'être une vraie clé
     * étrangère (voir la migration `create_indisponibilites_carte`).
     */
    private function colonneCible(CarteBoisson|Plat $article): string
    {
        return $article instanceof CarteBoisson ? 'boisson_id' : 'plat_id';
    }

    /**
     * Retirer un article de la carte est une décision de gestion : elle doit
     * être imputable. `utilisateurs.id` étant NOT NULL sur cette table, un
     * appel hors session est refusé plutôt qu'attribué à personne.
     */
    private function auteur(?string $utilisateurId): string
    {
        $auteur = $utilisateurId ?? auth()->id();

        if ($auteur === null) {
            throw new RuntimeException(__('carte.decision_non_imputable'));
        }

        return (string) $auteur;
    }

    private function commentaireOuNull(?string $commentaire): ?string
    {
        $propre = trim((string) $commentaire);

        return $propre === '' ? null : $propre;
    }
}
