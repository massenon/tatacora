<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use RuntimeException;
use Throwable;

/**
 * Décisions de PARC sur une unité d'hébergement : archiver (`hors_service`),
 * restaurer, purger — extraites de l'écran `Hebergement` le 02/09/2026 pour
 * que l'onglet « Restaurer » d'Import & Export emprunte le MÊME chemin
 * (« un composant Livewire appelle le Service de domaine, jamais une logique
 * métier réécrite » — LARAVEL_PWA.md §3 ; deux écrivains du même statut
 * auraient divergé au premier verrou oublié).
 *
 * ## Pourquoi ce n'est pas dans `SejourService`
 *
 * `SejourService` se déclare l'unique point d'entrée du CYCLE
 * `libre → occupee → nettoyage` et EXCLUT `hors_service` de ses trois gestes :
 * « une unité hors service n'est jamais touchée, la maintenance prime sur
 * l'exploitation ». Entrer et sortir de `hors_service` est une décision de
 * parc, pas un mouvement du cycle — elle vit ici.
 *
 * ## `hors_service` EST l'archive de ce schéma
 *
 * Aucune table d'archives n'existe : `hors_service` est le seul état qui
 * retire l'unité de ce qui est vendable (`estCommercialisable()` rend
 * `false`) sans rien effacer, et il est réversible — exactement ce que le
 * maître promet (« reste restaurable — rien n'est effacé »).
 *
 * @see EF-M1-01 Gestion du parc
 * @see RG-02 (le statut n'est jamais la disponibilité)
 */
class ParcHebergementService
{
    /**
     * Crée une catégorie — avec son tarif réel et sa capacité.
     *
     * Extrait de l'écran `Hebergement` le 15/10/2026 : la synchronisation
     * (lot S2, décision du Product Owner du 15/10/2026) crée désormais aussi
     * des catégories, et deux écrivains auraient divergé au premier contrôle
     * ajouté d'un seul côté.
     *
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerCategorieHebergementRequest`
     */
    public function creerCategorie(array $donnees): CategorieHebergement
    {
        return CategorieHebergement::create([
            ...$donnees,
            'tarif_base' => (string) $donnees['tarif_base'],
            'capacite_max' => (int) $donnees['capacite_max'],
        ]);
    }

    /**
     * Crée une unité au parc — TOUJOURS `libre`.
     *
     * Le statut n'est pas une donnée de création : le cycle opérationnel
     * appartient à `SejourService`, et une unité qui naîtrait `occupee`
     * ferait dire à l'écran qu'une chambre est occupée sans que personne y
     * dorme. Un `statut` reçu est donc écrasé ici, pas seulement ignoré par
     * l'appelant.
     *
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerUniteHebergementRequest`
     */
    public function creerUnite(array $donnees): UniteHebergement
    {
        return UniteHebergement::create([...$donnees, 'statut' => SejourService::STATUT_LIBRE]);
    }

    /**
     * Modifie une catégorie — libellé, tarif, capacité (champs présents).
     *
     * Né de la décision du Product Owner du 15/10/2026 (« offline-first
     * total ») : la synchronisation applique les modifications de catalogue
     * faites hors connexion, par le service, jamais en écriture brute.
     *
     * @param  array<string, mixed>  $donnees  champs validés par
     *                                         `EnregistrerCategorieHebergementRequest`
     */
    public function modifierCategorie(CategorieHebergement $categorie, array $donnees): CategorieHebergement
    {
        unset($donnees['id']);

        if (array_key_exists('tarif_base', $donnees)) {
            $donnees['tarif_base'] = (string) $donnees['tarif_base'];
        }

        if (array_key_exists('capacite_max', $donnees)) {
            $donnees['capacite_max'] = (int) $donnees['capacite_max'];
        }

        $categorie->update($donnees);

        return $categorie->refresh();
    }

    /**
     * Modifie une unité — numéro, catégorie. JAMAIS le statut : le cycle
     * appartient à `SejourService`, l'archive à `archiver()`/`restaurer()`.
     *
     * Le chemin de l'écran `Hebergement` ET de la synchronisation (décision
     * PO du 15/10/2026) : deux écrivains auraient divergé au premier contrôle
     * ajouté d'un seul côté.
     *
     * @param  array<string, mixed>  $donnees  champs validés par
     *                                         `EnregistrerUniteHebergementRequest`
     */
    public function modifierUnite(UniteHebergement $unite, array $donnees): UniteHebergement
    {
        unset($donnees['id'], $donnees['statut']);

        $unite->update($donnees);

        return $unite->refresh();
    }

    /**
     * Les réservations qui ENGAGENT l'unité — le verrou du maître : un
     * élément engagé ailleurs ne s'archive pas et ne se purge pas.
     *
     * @return Collection<int, Reservation>
     */
    public function engagements(UniteHebergement $unite): Collection
    {
        return Reservation::query()
            ->where('unite_id', $unite->id)
            ->whereNot('statut', 'annulee')
            ->where('date_depart', '>=', CarbonImmutable::today()->toDateString())
            ->orderBy('date_arrivee')
            ->get();
    }

    /**
     * Archive l'unité — `hors_service`, jamais un `delete()`.
     *
     * @throws RuntimeException l'unité est engagée dans une réservation
     */
    public function archiver(UniteHebergement $unite): void
    {
        // Recontrôlé au moment d'AGIR, pas seulement à l'affichage — entre
        // l'ouverture d'une modale et le clic, une réservation a pu naître.
        // Preuve par mutation (02/09/2026) : ce bloc retiré, le cas
        // `une_unite_engagee_ne_s_archive_pas…` d'`ImportExportActionsTest`
        // passe au ROUGE — la garde mord.
        $engagements = $this->engagements($unite);

        if ($engagements->isNotEmpty()) {
            throw new RuntimeException(__('hebergement_pwa.hebergement.archivage_verrou', [
                'nombre' => $engagements->count(),
                'details' => $this->detailsEngagements($engagements),
            ]));
        }

        $unite->update(['statut' => 'hors_service']);
    }

    /**
     * Le pendant de l'archivage — sans lui, « reste restaurable » serait une
     * promesse que rien ne tient (PA-59/60/61).
     */
    public function restaurer(UniteHebergement $unite): void
    {
        if ($unite->statut !== 'hors_service') {
            return;
        }

        $unite->update(['statut' => SejourService::STATUT_LIBRE]);
    }

    /**
     * Purge DÉFINITIVE — le seul endroit de l'application où une unité
     * disparaît vraiment (maître, encadré de l'onglet Restaurer). Réservée à
     * une unité déjà ARCHIVÉE ; l'écran ajoute sa propre garde de rôle.
     *
     * @throws RuntimeException unité non archivée, engagée, ou encore
     *                          référencée (les FK `restrictOnDelete` du schéma ont le dernier mot)
     */
    public function purger(UniteHebergement $unite): void
    {
        if ($unite->statut !== 'hors_service') {
            throw new RuntimeException(__('pwa.import_export.purge_refusee_non_archive'));
        }

        $engagements = $this->engagements($unite);

        if ($engagements->isNotEmpty()) {
            throw new RuntimeException(__('hebergement_pwa.hebergement.archivage_verrou', [
                'nombre' => $engagements->count(),
                'details' => $this->detailsEngagements($engagements),
            ]));
        }

        // Une réservation PASSÉE (hors du verrou d'engagement) la référence
        // encore : refus AVANT le `delete()` — c'est le même verdict que
        // `restrictOnDelete` rendrait, mais nommé, et sans compter sur une
        // exception SQL pour le porter. Effacer l'unité rendrait cet
        // historique illisible.
        if (Reservation::query()->where('unite_id', $unite->id)->exists()) {
            throw new RuntimeException(__('pwa.import_export.purge_refusee_referencee'));
        }

        try {
            $unite->delete();
        } catch (Throwable) {
            // Le filet des références que ce service ne connaît pas : une FK
            // ajoutée demain (`restrictOnDelete` partout au schéma) doit
            // rendre le même refus nommé, jamais une page d'erreur.
            throw new RuntimeException(__('pwa.import_export.purge_refusee_referencee'));
        }
    }

    /**
     * @param  Collection<int, Reservation>  $engagements
     */
    private function detailsEngagements(Collection $engagements): string
    {
        return $engagements
            ->map(static fn (Reservation $reservation): string => __(
                'hebergement_pwa.hebergement.archivage_detail_reservation',
                [
                    'arrivee' => $reservation->date_arrivee->format('d/m/Y'),
                    'depart' => $reservation->date_depart->format('d/m/Y'),
                ],
            ))
            ->implode(', ');
    }
}
