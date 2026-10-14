<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use App\Domain\Crm\Models\Client;

/**
 * Enregistrement du référentiel client — création et modification (M3).
 *
 * Extrait de `ClientController` (PA-159, lot 0b) : `LARAVEL_PWA.md` §3 impose
 * qu'un composant Livewire appelle un Service de domaine, jamais un Eloquent
 * nu — ce service est le point d'entrée commun de l'API et de la PWA.
 *
 * ## RG-18 vit ICI, pas dans le canal
 *
 * La création rend l'avertissement de doublon AVEC la fiche créée : la règle
 * est **avertissante, jamais bloquante** (deux personnes peuvent porter le
 * même nom, et un blocage pousserait à ressaisir une orthographe approchante —
 * créant exactement le doublon redouté). Si l'avertissement restait dans le
 * contrôleur d'API, la PWA créerait des doublons en silence — que rien ne
 * peut supprimer, aucune route de suppression n'existant sur `clients`.
 *
 * La recherche précède la création : lancée après, la fiche qu'on vient
 * d'écrire serait son propre doublon et l'avertissement sonnerait toujours.
 *
 * @see EF-M3-01 Fiche client unique
 * @see RG-18 Détection de doublons — avertissante, jamais bloquante
 * @see RG-15 Journalisation (trait Auditable sur Client)
 */
class EnregistrementClientService
{
    public function __construct(
        private readonly DetectionDoublonService $doublons,
    ) {
    }

    /**
     * Crée la fiche et rend l'avertissement RG-18 qui l'accompagne.
     *
     * @param  array<string, mixed>  $donnees données déjà validées par
     *                                        `EnregistrerClientRequest` (API) ou par les règles
     *                                        qui en dérivent via `ReglesDeLApi` (PWA)
     * @return array{client: Client, avertissement_doublon: string|null}
     */
    public function creer(array $donnees): array
    {
        $doublons = $this->doublons->rechercherDoublons(
            (string) $donnees['nom'],
            (string) $donnees['telephone'],
        );

        $client = Client::create($donnees);

        return [
            'client' => $client,
            'avertissement_doublon' => $this->doublons->messageAvertissement($doublons),
        ];
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(Client $client, array $donnees): Client
    {
        $client->update($donnees);

        return $client->refresh();
    }
}
