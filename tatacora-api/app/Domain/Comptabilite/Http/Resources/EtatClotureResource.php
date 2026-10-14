<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\EtatCloture;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Cloture Periodique » — EF-M10-07, en LECTURE SEULE.
 *
 * ## `action_exposee` vaut `false`, et c'est le livrable
 *
 * Le maitre n'a AUCUN bouton sur cette page : pas un `addEventListener` dans
 * tout le fichier. Cette API en est la transcription fidele, et non une
 * livraison partielle.
 *
 * `limites_non_verifiables` dit pourquoi l'action ne pourrait pas etre offerte
 * meme si le maitre la demandait — report a nouveau inexistant (un fait de
 * code) et perimetre non arbitre (PA-28, un fait d'arbitrage). Ces deux-la sont
 * LITTERALES et le disent : aucune requete ne peut constater l'absence d'un
 * mecanisme ni trancher une question qui n'a pas ete posee. Une cloture est
 * IRREVERSIBLE : un bouton qui confirmerait sans ecrire est interdit par
 * l'Article 6, et un bouton qui ecrirait sans report a nouveau produirait un
 * exercice suivant faux, sans retour possible.
 *
 * `blocages_structurels` est, lui, REELLEMENT VERIFIE a chaque appel : les
 * comptes 131/139, le journal et le centre de cloture existent-ils au
 * referentiel ? `blocages_de_donnees` porte ce qui se corrige en SAISISSANT.
 * Les trois listes restent separees parce qu'elles n'appellent pas la meme
 * personne : le comptable pour la troisieme, le parametrage pour la seconde, un
 * developpeur et le Product Owner pour la premiere.
 *
 * `conditions_verifiables_reunies` ne porte que les deux listes constatees — y
 * verser les limites litterales l'aurait fige a `false` pour toujours, et un
 * indicateur qui ne peut pas changer n'informe personne (PA-59/60/61).
 *
 * @property-read EtatCloture $resource
 */
class EtatClotureResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'annee' => $this->resource->annee,
            'statut_exercice' => $this->resource->statutExercice,
            'conditions_verifiables_reunies' => $this->resource->conditionsVerifiablesReunies,
            'action_exposee' => $this->resource->actionExposee,
            'blocages_structurels' => $this->resource->blocagesStructurels,
            'blocages_de_donnees' => $this->resource->blocagesDeDonnees,
            'limites_non_verifiables' => $this->resource->limitesNonVerifiables,
            'avertissements' => $this->resource->avertissements,
            'resultat_a_reporter' => $this->resource->resultatAReporter,
            'compte_de_destination' => $this->resource->compteDeDestination,
            'impot_non_comptabilise' => $this->resource->impotNonComptabilise,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'etapes' => EtapeClotureResource::collection($this->resource->etapes)->resolve($request),
        ];
    }
}
