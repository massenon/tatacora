<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Hebergement\Models\CanalReservation;
use RuntimeException;

/**
 * Gestion du référentiel des canaux de réservation — PA-163 (01/09/2026) en a
 * fait une table réelle ; ce service en ouvre la gestion, jusque-là refusée
 * par l'écran Paramètres faute de référentiel à modifier.
 *
 * ## Trois gestes fermés, jamais une suppression
 *
 * Le maître l'écrit lui-même (`canaux-engine.js`) : « un canal utilisé ne se
 * supprime pas, il se désactive » — l'effacer laisserait des réservations
 * pointant un canal inexistant, et la FK `restrictOnDelete` de
 * `reservations.canal_id` le rend mécanique. Ce service ne porte donc que
 * `ajouter()`, `renommer()` et `basculer()` ; aucune méthode `supprimer()`
 * n'existe, délibérément.
 *
 * ## Refus nommés, jamais un `ValidationException` générique
 *
 * `RuntimeException` avec message traduit, exactement le contrat de
 * `EnregistrerParametreService` : le composant Livewire appelant l'attrape et
 * l'affiche sous le champ, comme pour l'édition d'un paramètre. Deux services
 * d'écriture de l'écran, une seule forme de refus.
 *
 * @see RG-10 paramétrage sans déploiement
 */
class CanalReservationService
{
    public function ajouter(string $nom): CanalReservation
    {
        $nom = $this->normaliser($nom);
        $this->refuserSiDoublon($nom);

        return CanalReservation::create([
            'nom' => $nom,
            'actif' => true,
        ]);
    }

    public function renommer(string $id, string $nom): CanalReservation
    {
        $canal = CanalReservation::find($id);

        if ($canal === null) {
            throw new RuntimeException(__('parametres.canal_introuvable'));
        }

        $nom = $this->normaliser($nom);
        $this->refuserSiDoublon($nom, $canal->id);

        // Les réservations déjà saisies conservent l'ancien libellé, comme au
        // maître (`canaux-engine.js` : « renommer ne réécrit pas le passé ») —
        // aucune colonne dénormalisée ne le porte, il n'y a rien à réécrire.
        $canal->nom = $nom;
        $canal->save();

        return $canal;
    }

    public function basculer(string $id): CanalReservation
    {
        $canal = CanalReservation::find($id);

        if ($canal === null) {
            throw new RuntimeException(__('parametres.canal_introuvable'));
        }

        $canal->actif = ! $canal->actif;
        $canal->save();

        return $canal;
    }

    private function normaliser(string $nom): string
    {
        $nom = trim($nom);

        if ($nom === '') {
            throw new RuntimeException(__('parametres.canal_nom_requis'));
        }

        return $nom;
    }

    /**
     * Une contrainte `unique` existe déjà au schéma (PA-163) : ce contrôle
     * anticipé transforme l'exception SQL, illisible pour un Administrateur,
     * en un refus de formulaire nommé — le même contrat que
     * `EnregistrerParametreService::verifierCoherence()`.
     */
    private function refuserSiDoublon(string $nom, ?string $idExclu = null): void
    {
        $existe = CanalReservation::query()
            ->whereRaw('LOWER(nom) = ?', [mb_strtolower($nom)])
            ->when($idExclu !== null, fn ($requete) => $requete->where('id', '!=', $idExclu))
            ->exists();

        if ($existe) {
            throw new RuntimeException(__('parametres.canal_nom_deja_utilise', ['nom' => $nom]));
        }
    }
}
