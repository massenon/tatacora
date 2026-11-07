<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\ProformaService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Factures PROFORMA émises sur un poste (M2) — décisions du PO du 07/11/2026, point 8.
 *
 * Un DOCUMENT SOURCE né au poste : l'identifiant est celui du poste (le rejeu d'une création ne double rien :
 * `reprendreExistant`). Le poste crée (brouillon ou émise, hors ligne), modifie, annule, ou range sa conversion ;
 * `ProformaService` reste l'unique auteur des règles.
 *
 * ## Le numéro
 * Le poste émet un numéro PROVISOIRE (`PROV-FP-AAAA-NNNNN`) ; à l'émission le SERVEUR attribue le numéro définitif
 * `N°0045 FP-GCN/2026` (séquence continue par année, sous verrou) et le RENDS (`numero`, `rang`, `annee`) : le poste
 * remplace son provisoire à l'accusé.
 *
 * ## La validité
 * Décidée au poste à l'émission (réglage descendu) et fournie (`valide_jusqu_au`, y compris null) : le serveur la range
 * telle quelle, il ne la recalcule pas avec son réglage du moment.
 *
 * ## La conversion
 * Faite au poste, la facture locale monte par `factures` (son numéro est régularisé comme toute facture) ; ici
 * `statut: convertie` + `facture_id` LIE les deux, sans créer de seconde facture. La facture est poussée AVANT
 * (ordre du registre) ; une facture inconnue est un rejet explicite, jamais une facture inventée.
 */
final class GestionnaireProformas extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ProformaService $proformas,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'proformas';
    }

    public function module(): string
    {
        return 'M2';
    }

    public function serviceDomaine(): string
    {
        return ProformaService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function champDateDocument(): ?string
    {
        return 'date_emission';
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $p = Proforma::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: array_filter([
            'numero' => $p->numero,
            'annee' => $p->annee === null ? null : (string) $p->annee,
            'rang' => $p->rang === null ? null : (string) $p->rang,
            'statut_proforma' => $p->statut,
            'valide_jusqu_au' => $p->valide_jusqu_au?->toDateString(),
            'total' => (string) $p->total,
        ], static fn (?string $v): bool => $v !== null));
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'client_id' => ['nullable', 'string'],
            'client_nom' => ['required', 'string', 'max:150'],
            'client_telephone' => ['nullable', 'string', 'max:40'],
            'client_ifu' => ['nullable', 'string', 'regex:/^[0-9]{13}$/'],
            'objet' => ['nullable', 'string', 'max:255'],
            'source_module' => ['nullable', 'in:'.implode(',', array_keys(ProformaService::MODULE_LIGNE))],
            'source_id' => ['nullable', 'string'],
            'date_emission' => ['nullable', 'date_format:Y-m-d'],
            'emettre' => ['nullable', 'boolean'],
            'valide_jusqu_au' => ['nullable', 'date_format:Y-m-d'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.designation' => ['required', 'string', 'max:255'],
            'lignes.*.quantite' => ['required', 'integer', 'min:1'],
            'lignes.*.prix_unitaire' => ['required', 'integer', 'min:0'],
        ], ['client_ifu.regex' => __('proforma.ifu_invalide')]);

        $clientId = empty($donnees['client_id']) ? null : $this->resoudre('clients', $donnees['client_id']);

        $proforma = $this->proformas->creer([
            ...$donnees,
            'client_id' => is_string($clientId) ? $clientId : null,
            'source_id' => null,
        ], $entiteId);

        if ((bool) ($donnees['emettre'] ?? false)) {
            $this->proformas->emettre(
                $proforma,
                $donnees['date_emission'] ?? null,
                array_key_exists('valide_jusqu_au', $payload) ? ['valide_jusqu_au' => $donnees['valide_jusqu_au'] ?? null] : null,
            );
        }

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $proforma = Proforma::query()->findOrFail($entiteId);
        $statut = $payload['statut'] ?? null;

        $edition = array_intersect_key($payload, array_flip(['client_nom', 'client_telephone', 'client_ifu', 'objet', 'lignes']));
        $inconnus = array_diff(array_keys($payload), [...array_keys($edition), 'statut', 'motif', 'facture_id', 'date_emission', 'valide_jusqu_au']);

        if ($inconnus !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        if ($edition !== []) {
            if (isset($edition['client_ifu']) && $edition['client_ifu'] !== '' && preg_match('/^[0-9]{13}$/', (string) $edition['client_ifu']) !== 1) {
                throw new RuntimeException(__('proforma.ifu_invalide'));
            }
            $proforma = $this->proformas->modifier($proforma, $edition);
        }

        if ($statut === 'emise') {
            $this->proformas->emettre(
                $proforma,
                isset($payload['date_emission']) ? (string) $payload['date_emission'] : null,
                array_key_exists('valide_jusqu_au', $payload) ? ['valide_jusqu_au' => $payload['valide_jusqu_au'] === null ? null : (string) $payload['valide_jusqu_au']] : null,
            );
        } elseif ($statut === 'annulee') {
            $this->proformas->annuler($proforma, (string) ($payload['motif'] ?? ''));
        } elseif ($statut === 'convertie') {
            $factureId = $this->resoudre('factures', $payload['facture_id'] ?? null);
            $facture = is_string($factureId) ? Facture::query()->find($factureId) : null;

            if ($facture === null) {
                throw new RuntimeException(__('sync.factures.facture_inconnue'));
            }
            $this->proformas->lier($proforma, $facture);
        } elseif ($statut !== null) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        return $this->resultat($entiteId);
    }
}
