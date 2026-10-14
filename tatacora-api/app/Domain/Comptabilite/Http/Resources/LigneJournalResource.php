<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne du Journal General — les six colonnes de `m10-journal.html`
 * (l.37-38), plus le centre de cout que `MODULE_COMPTABILITE_COMPLET.md` §2
 * compte parmi les colonnes du Journal.
 *
 * ## Les montants descendent en CHAINE
 *
 * `DECIMAL(15,2)` caste en `decimal:2` par Eloquent. Les convertir en `float`
 * pour le JSON reintroduirait l'erreur d'arrondi que tout le schema evite, et
 * c'est la colonne la plus lue du module. Meme conduite que `tarif_nuit` sur
 * `GET /hebergement/parc`.
 *
 * ## `contrepassation_de` descend, parce que RG-11 se LIT au grand livre
 *
 * Une correction n'efface rien : elle ajoute une ecriture inverse liee a
 * l'originale. Sans ce champ, deux lignes en sens contraire seraient
 * indiscernables d'une double saisie — et c'est precisement ce qu'un audit
 * cherche a distinguer.
 *
 * @property-read EcritureComptable $resource
 */
class LigneJournalResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $journal = $this->resource->journal;
        $compte = $this->resource->compte;
        $centre = $this->resource->centre;

        return [
            'id' => $this->resource->id,
            'date_ecriture' => $this->resource->date_ecriture->toDateString(),
            'libelle' => $this->resource->libelle,
            'debit' => (string) $this->resource->debit,
            'credit' => (string) $this->resource->credit,
            'statut' => $this->resource->statut,

            'journal' => $journal instanceof JournalComptable ? [
                'id' => $journal->id,
                'code' => $journal->code,
                'libelle' => $journal->libelle,
            ] : null,

            'compte' => $compte instanceof CompteComptable ? [
                'id' => $compte->id,
                'numero_compte' => $compte->numero_compte,
                'libelle' => $compte->libelle,
            ] : null,

            // RG-12 : NOT NULL au schema. Le `null` de secours ne couvre que
            // l'absence de chargement, jamais une ecriture sans centre.
            'centre' => $centre instanceof CentreCout ? [
                'id' => $centre->id,
                'libelle' => $centre->libelle,
            ] : null,

            'contrepassation_de' => $this->resource->ecriture_contrepassee_id,
        ];
    }
}
