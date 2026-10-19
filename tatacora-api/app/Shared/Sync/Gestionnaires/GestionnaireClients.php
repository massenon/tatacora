<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Crm\Http\Requests\EnregistrerClientRequest;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;

/**
 * Fiches clients saisies hors connexion (M3) — par `EnregistrementClientService`.
 *
 * ## Ce qui a changé le 15/10/2026, et ce qui n'a pas changé
 *
 * Jusque-là, `clients` était déclarée « écriture directe » : le moteur
 * insérait ou mettait à jour le payload BRUT. Trois conséquences, aucune
 * voulue : aucune validation (un `type_client` hors liste remontait en erreur
 * SQL), aucun avertissement RG-18 à la création, et toute colonne du payload
 * était écrite — `actif` compris, ce qui archivait une fiche en contournant
 * le verrou d'engagement de `ReferentielClientService`.
 *
 * Désormais :
 * - **Création** : règles d'`EnregistrerClientRequest` (celles de
 *   `POST /crm/clients`), puis `EnregistrementClientService::creer()` sous
 *   l'UUID du poste — le service l'accepte (`id` est remplissable). La règle
 *   RG-18 reste AVERTISSANTE : l'avertissement de doublon est rendu dans le
 *   résultat (`avertissement_doublon`), jamais un rejet. Aucune fusion sur
 *   clé naturelle : deux personnes peuvent porter le même nom et le même
 *   téléphone familial, et fusionner deux clients fondrait deux historiques
 *   de séjours et de créances — irréversible. La décision PO de fusion vise
 *   le CATALOGUE (fournisseurs, articles), pas les tiers clients.
 * - **Modification** : PARTIELLE, comme le moteur l'acceptait (le poste
 *   envoie les champs changés). Chaque champ présent est validé par la règle
 *   de l'API ; les champs hors règles (`actif`, `solde` calculé à terme,
 *   colonnes d'audit) sont IGNORÉS comme `validated()` les ignore sur la
 *   route — `actif` n'est plus jamais écrit par ce chemin.
 *   Le conflit de versions (RG-17, last-write-wins par horodatage de saisie)
 *   reste arbitré par le moteur, inchangé ; seule l'écriture finale passe
 *   désormais par le service (Eloquent : audit RG-15 et `date_modification`
 *   tenus par `Auditable`, ce que l'`UPDATE` brut devait simuler).
 */
final class GestionnaireClients extends GestionnaireAbstrait
{
    public function __construct(
        private readonly EnregistrementClientService $enregistrement,
    ) {
    }

    public function table(): string
    {
        return 'clients';
    }

    public function module(): string
    {
        return 'M3';
    }

    public function serviceDomaine(): string
    {
        return EnregistrementClientService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        unset($payload['id']);

        $donnees = $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerClientRequest::class),
            EnregistrerClientRequest::class,
        );

        $resultat = $this->enregistrement->creer([...$donnees, 'id' => $entiteId]);

        return new EcritureSynchronisee(
            $entiteId,
            complements: array_filter(
                ['avertissement_doublon' => $resultat['avertissement_doublon']],
                static fn (?string $valeur): bool => $valeur !== null,
            ),
        );
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $client = Client::query()->findOrFail($entiteId);

        $regles = $this->reglesDeLApi(EnregistrerClientRequest::class, 'client', $client);
        // L'identifiant ne se modifie pas ; et seules les règles des champs
        // PRÉSENTS s'appliquent — une modification partielle n'est pas une
        // fiche incomplète.
        unset($regles['id'], $payload['id']);
        $regles = array_intersect_key($regles, $payload);

        $donnees = $this->valider($payload, $regles, EnregistrerClientRequest::class);

        $this->enregistrement->modifier($client, $donnees);

        return new EcritureSynchronisee($entiteId);
    }
}
