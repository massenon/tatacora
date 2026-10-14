<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Rapprochement commande / réception / facture — EF-M7-04.
 *
 * ## `facture_verifiable` sort toujours à `false`, et c'est le livrable
 *
 * `ControleTroisVoiesService::rapprocher()` accepte un tableau de montants
 * facturés. Il ne s'en sert **pour aucune comparaison** : il le teste contre
 * `null`, bascule `facture_verifiable` à `true` et retire l'avertissement qui
 * disait que la troisième voie n'avait pas été vérifiée. Exposer ce paramètre
 * dans l'API donnerait donc à un écran le moyen d'annoncer un rapprochement à
 * trois voies conforme sans qu'aucun montant n'ait jamais été confronté — un
 * indicateur qui affirme un état qu'il n'a pas vérifié, la forme exacte de
 * PA-59, PA-60 et PA-61.
 *
 * La route n'accepte donc aucun montant facturé. La raison de fond est en
 * amont : **aucune table ne porte de facture fournisseur** — `factures` est la
 * facturation CLIENT (M2), de nature opposée. Tant que le schéma n'en a pas,
 * le contrôle porte réellement sur deux voies, et il le dit.
 *
 * ## Les avertissements ne sont pas décoratifs
 *
 * Ils descendent tels quels et doivent être affichés : un rapprochement
 * présenté comme complet alors qu'il ne porte que sur deux voies est pire que
 * pas de rapprochement du tout — il donne une assurance qu'il n'a pas. C'est
 * ce qui autorise, ou non, le paiement d'une facture fournisseur.
 *
 * @property-read array{
 *     commande_id: string,
 *     lignes: list<array{article_id: string, commandee: string, recue: string, ecart: string, concordance: string}>,
 *     concordance_globale: string,
 *     facture_verifiable: bool,
 *     avertissements: list<string>
 * } $resource
 */
class RapprochementResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'commande_id' => $this->resource['commande_id'],
            'concordance_globale' => $this->resource['concordance_globale'],
            'facture_verifiable' => $this->resource['facture_verifiable'],
            'voies_verifiees' => ['commande', 'reception'],
            'avertissements' => $this->resource['avertissements'],
            'lignes' => $this->resource['lignes'],
        ];
    }
}
