<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Crm\Models\Client;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Les contrats de location (M8) saisis sur un poste — audit de couverture du
 * 18/10/2026.
 *
 * Par `ContratLocationService::creer`, et lui seul : RG-08 (aucun
 * chevauchement sur le même véhicule, sous verrou — deux postes ne louent
 * jamais le même véhicule sur la même période) et RG-09 (pièces). Puis, comme
 * la PWA : le numéro `LOC-` de la séquence, statut `actif`, montant = tarif
 * du jour × jours − remise, acompte, reste dû = montant − acompte (voir
 * « Remise et acompte » ci-dessous). Les numéros de pièce et de permis viennent de la saisie du poste
 * (la charge de la file), jamais d'un fichier.
 *
 * ## Remise et acompte (lot L3-S, 27/10/2026)
 *
 * Décision du PO : le contrat du poste porte remise et acompte « comme le web ».
 * `remise` et `acompte` (FCFA, nombres >= 0, absents = 0 pour un poste d'avant
 * la v41) se jugent comme `Locations::enregistrerContrat`, AVANT le service :
 * une remise supérieure au montant brut (tarif du jour × jours), puis un
 * acompte supérieur au montant net, sont refusés avec la phrase `lte` de la vue
 * (champ « Remise (FCFA) » / « Acompte reçu (FCFA) », borne rendue). Le montant
 * net, l'acompte et le reste dû sont rangés comme la PWA ; la remise elle-même
 * n'est rangée nulle part (la PWA ne la garde pas non plus : elle n'est que dans
 * le montant net). Le poste reçoit `numero` (séquence `LOC-`) et `montant` à
 * l'accusé.
 *
 * ## L'annulation (26/10/2026) — la seule modification admise
 *
 * Un poste annule un contrat comme la PWA (« Voulez-vous annuler le contrat »)
 * : `statut = annule`, par `ContratLocationService::annuler`, le chemin que
 * l'écran partage. Rien d'autre ne se modifie (ni dates, ni véhicule : un
 * contrat qui change de plage est un autre contrat, soumis à RG-08). Un contrat
 * déjà annulé — par un autre poste, par la PWA — est un REJEU : accepté, rien
 * n'est réécrit (l'intention du poste est déjà celle du serveur).
 */
final class GestionnaireContratsLocation extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ContratLocationService $contrats,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'contrats_location';
    }

    public function module(): string
    {
        return 'M8';
    }

    public function serviceDomaine(): string
    {
        return ContratLocationService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $contrat = ContratLocation::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: array_filter([
            'numero' => $contrat->getAttribute('numero'),
            'montant' => (string) $contrat->getAttribute('montant'),
        ], static fn (?string $v): bool => $v !== null));
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'vehicule_id' => ['required', 'string'],
            'client_id' => ['required', 'string'],
            'guide_id' => ['nullable', 'string'],
            'date_debut' => ['required', 'date_format:Y-m-d'],
            'date_fin' => ['required', 'date_format:Y-m-d', 'after:date_debut'],
            'piece_identite' => ['required', 'string', 'max:255'],
            'permis_conduire' => ['nullable', 'string', 'max:255'],
            'remise' => ['nullable', 'numeric', 'min:0'],
            'acompte' => ['nullable', 'numeric', 'min:0'],
        ], [], [
            // Les libellés de la vue, comme pour les deux refus `lte` ci-dessous.
            'remise' => __('vehicules.pwa.champ_remise'),
            'acompte' => __('vehicules.pwa.champ_acompte'),
        ]);

        $vehicule = Vehicule::find($this->resoudre('vehicules', $donnees['vehicule_id']));

        if ($vehicule === null) {
            throw new RuntimeException(__('sync.vehicules.inconnu'));
        }

        $client = Client::find($this->resoudre('clients', $donnees['client_id']));

        if ($client === null) {
            throw new RuntimeException(__('sync.vehicules.client_inconnu'));
        }

        // Remise puis acompte, AVANT le service et dans l'ordre de la PWA
        // (`Locations::enregistrerContrat`) : un refus ne laisse rien d'écrit.
        $jours = (int) CarbonImmutable::parse($donnees['date_debut'])->diffInDays(CarbonImmutable::parse($donnees['date_fin']));
        $brut = bcmul((string) $vehicule->tarif_jour, (string) $jours, 2);
        $remise = bcadd((string) ($donnees['remise'] ?? '0'), '0', 2);
        $acompte = bcadd((string) ($donnees['acompte'] ?? '0'), '0', 2);

        if (bccomp($remise, $brut, 2) > 0) {
            throw new RuntimeException(__('validation.lte.numeric', [
                'attribute' => __('vehicules.pwa.champ_remise'),
                'value' => $brut,
            ]));
        }

        $net = bcsub($brut, $remise, 2);

        if (bccomp($acompte, $net, 2) > 0) {
            throw new RuntimeException(__('validation.lte.numeric', [
                'attribute' => __('vehicules.pwa.champ_acompte'),
                'value' => $net,
            ]));
        }

        DB::transaction(function () use ($entiteId, $donnees, $vehicule, $client, $net, $acompte): void {
            $contrat = $this->contrats->creer([
                'id' => $entiteId,
                'vehicule_id' => $vehicule->id,
                'client_id' => $client->id,
                'guide_id' => empty($donnees['guide_id']) ? null : $this->resoudre('guides', $donnees['guide_id']),
                'date_debut' => $donnees['date_debut'],
                'date_fin' => $donnees['date_fin'],
                'piece_identite' => $donnees['piece_identite'],
                'permis_conduire' => $donnees['permis_conduire'] ?? null,
            ]);
            $contrat->forceFill([
                'numero' => app(SequenceDocumentService::class)->suivant('contrats_location', Locations::PREFIXE_CONTRAT),
                'statut' => 'actif',
                'montant' => $net,
                'acompte' => $acompte,
                'reste_a_payer' => bcsub($net, $acompte, 2),
            ])->save();
        });

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), ['statut']);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.vehicules.contrat_champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        if (! array_key_exists('statut', $payload) || $payload['statut'] !== ContratLocationService::STATUT_ANNULE) {
            throw new RuntimeException(__('sync.vehicules.contrat_statut_refuse', [
                'statut' => is_scalar($payload['statut'] ?? null) ? (string) $payload['statut'] : '—',
            ]));
        }

        $contrat = ContratLocation::query()->findOrFail($entiteId);

        // Rejeu : déjà annulé, au même sens.
        if ($contrat->getAttribute('statut') === ContratLocationService::STATUT_ANNULE) {
            return $this->resultat($entiteId);
        }

        $this->contrats->annuler($contrat);

        return $this->resultat($entiteId);
    }
}
