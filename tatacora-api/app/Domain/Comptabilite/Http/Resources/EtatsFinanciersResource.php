<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\EtatsFinanciers;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Etats Financiers » — quatre onglets, une seule lecture.
 *
 * Les cles sont celles des onglets du maitre (`m10-etats-financiers.html`
 * l.84-146), dans son ordre : `bilan`, `resultat`, `flux`, `notes`.
 *
 * ⚠ ECART DELIBERE — `m10-etats-financiers.html` l.37-40 et l.163-169
 * Le maitre : un bouton « Exporter les 4 documents (PDF) » dont le
 * gestionnaire n'appelle rien et affiche « Export PDF consolide — non
 * implemente dans ce demonstrateur statique ».
 * Ici : aucune route d'export.
 * Raison : Article 6 — un bouton qui confirme sans rien produire ne se porte
 * jamais. Le maitre le dit lui-meme. L'export reel passera par
 * `GenerateurEtatService` (RG-19), qui est le point unique de tout PDF/CSV du
 * depot ; aucun controleur ne genere de PDF. Cette route livre les DONNEES des
 * quatre documents, qui sont ce qu'il manquait a l'etat pour exister.
 *
 * @property-read EtatsFinanciers $resource
 */
class EtatsFinanciersResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'bilan' => (new BilanResource($this->resource->bilan))->resolve($request),
            'resultat' => (new CompteResultatResource($this->resource->compteResultat))->resolve($request),
            'flux' => (new TafireResource($this->resource->tafire))->resolve($request),
            'notes' => (new NotesAnnexesResource($this->resource->notesAnnexes))->resolve($request),
        ];
    }
}
