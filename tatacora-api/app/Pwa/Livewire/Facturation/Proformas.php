<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Facturation;

use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\DocumentProforma;
use App\Domain\Facturation\Services\PrefillProforma;
use App\Domain\Facturation\Services\ProformaService;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Facture PROFORMA (M2) — écran « Proformas » de Facturation (PO, 07/11/2026). docs/SPEC_FACTURE_PROFORMA.md.
 *
 * Document NON FISCAL : aucun geste de cet écran ne parle de MECeF. Création depuis l'écran (« Nouvelle facture
 * proforma », saisie libre) ET depuis un module (`?flux=location|tourisme|hebergement|evenement&source=<id>`),
 * qui prérempli le client, l'objet et les lignes (`PrefillProforma`) ; les lignes restent modifiables.
 * Droits : module M2, comme les factures. Toute règle vit dans `ProformaService` ; cet écran ne fait que l'appeler.
 */
#[Title('Factures proforma — LogiReStock — TATACORA AFRIQUE')]
class Proformas extends PageMetier
{
    use FormulaireModal;

    public const MODULE = 'M2';

    #[Url(as: 'flux')]
    public string $flux = '';

    #[Url(as: 'source')]
    public string $source = '';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'statut')]
    public string $statut = '';

    /** Proformas par page : la liste PAGINE, elle ne tronque pas (un plafond silencieux masquerait des pièces). */
    public const PAR_PAGE = 10;

    /** La page courante — propriété `#[Url]` passée à `paginate()`, comme le registre des factures. */
    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /** Un filtre qui change remet la liste à sa première page. */
    public function updated(string $propriete): void
    {
        if (in_array($propriete, ['recherche', 'statut'], true)) {
            $this->pageCourante = 1;
        }
    }

    public string $proformaId = '';

    public string $clientId = '';

    public string $clientNom = '';

    public string $clientTelephone = '';

    public string $clientIfu = '';

    public string $objet = '';

    public string $sourceModule = 'libre';

    public string $sourceId = '';

    /** @var list<array{designation: string, quantite: string, prix_unitaire: string}> */
    public array $lignes = [];

    public string $cibleId = '';

    public string $motifAnnulation = '';

    /** @return array<string, list<string>> */
    protected function formulaires(): array
    {
        return [
            'proforma' => ['proformaId', 'clientId', 'clientNom', 'clientTelephone', 'clientIfu', 'objet', 'sourceModule', 'sourceId', 'lignes'],
            'annulation' => ['cibleId', 'motifAnnulation'],
            'conversion' => ['cibleId'],
        ];
    }

    /** Arrivée depuis un module : la saisie s'ouvre prérempli — jamais pour qui ne peut pas écrire. */
    public function mount(PrefillProforma $prefill): void
    {
        if ($this->flux === '' || ! $this->peutEcrire()) {
            return;
        }

        $donnees = $prefill->depuis($this->flux, $this->source === '' ? null : $this->source);

        if ($donnees === null) {
            return;
        }

        $this->ouvrirFormulaire('proforma');
        $this->clientId = (string) $donnees['client_id'];
        $this->clientNom = $donnees['client_nom'];
        $this->clientTelephone = $donnees['client_telephone'];
        $this->clientIfu = $donnees['client_ifu'];
        $this->objet = $donnees['objet'];
        $this->sourceModule = $donnees['source_module'];
        $this->sourceId = (string) $donnees['source_id'];
        $this->lignes = array_map(static fn (array $l): array => [
            'designation' => $l['designation'], 'quantite' => (string) $l['quantite'], 'prix_unitaire' => (string) $l['prix_unitaire'],
        ], $donnees['lignes']);

        if ($this->lignes === []) {
            $this->lignes = [$this->ligneVide()];
        }
    }

    public function ouvrirCreation(): void
    {
        $this->ouvrirFormulaire('proforma');
        $this->lignes = [$this->ligneVide()];
    }

    public function ouvrirModification(string $proforma): void
    {
        $this->ouvrirFormulaire('proforma');
        $piece = Proforma::query()->with('lignes')->find($proforma);

        if ($piece === null || ! $piece->estModifiable()) {
            $this->etatFormulaire = null;

            return;
        }

        $this->proformaId = (string) $piece->id;
        $this->clientId = (string) $piece->client_id;
        $this->clientNom = $piece->client_nom;
        $this->clientTelephone = (string) $piece->client_telephone;
        $this->clientIfu = (string) $piece->client_ifu;
        $this->objet = (string) $piece->objet;
        $this->sourceModule = $piece->source_module;
        $this->lignes = $piece->lignes->map(static fn ($l): array => [
            'designation' => $l->designation, 'quantite' => (string) $l->quantite, 'prix_unitaire' => (string) $l->prix_unitaire,
        ])->all();
    }

    public function ajouterLigne(): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->lignes[] = $this->ligneVide();
    }

    public function retirerLigne(int $index): void
    {
        $this->exigerEcriture(self::MODULE);
        unset($this->lignes[$index]);
        $this->lignes = array_values($this->lignes);
    }

    /** Enregistre le brouillon ; `$emettre` : l'émet aussitôt (numéro attribué). */
    public function enregistrer(ProformaService $service, bool $emettre = false): void
    {
        $this->validerEcriture([
            'clientNom' => ['required', 'string', 'max:150'],
            'clientTelephone' => ['nullable', 'string', 'max:40'],
            'clientIfu' => ['nullable', 'string', 'max:30'],
            'objet' => ['nullable', 'string', 'max:255'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.designation' => ['required', 'string', 'max:255'],
            'lignes.*.quantite' => ['required', 'integer', 'min:1'],
            'lignes.*.prix_unitaire' => ['required', 'integer', 'min:0'],
        ]);

        $donnees = [
            'client_id' => $this->clientId === '' ? null : $this->clientId,
            'client_nom' => $this->clientNom, 'client_telephone' => $this->clientTelephone, 'client_ifu' => $this->clientIfu,
            'objet' => $this->objet, 'lignes' => $this->lignes,
        ];

        try {
            if ($this->proformaId === '') {
                $piece = $service->creer($donnees + ['source_module' => $this->sourceModule, 'source_id' => $this->sourceId === '' ? null : $this->sourceId]);
            } else {
                $piece = $service->modifier(Proforma::query()->findOrFail($this->proformaId), $donnees);
            }

            if ($emettre) {
                $piece = $service->emettre($piece);
            }
        } catch (RuntimeException $refus) {
            $this->addError('clientNom', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire($emettre
            ? __('proforma.ui.emise', ['numero' => $piece->numero])
            : __('proforma.ui.enregistree'));
    }

    public function emettre(string $proforma, ProformaService $service): void
    {
        $this->exigerEcriture(self::MODULE);
        $piece = Proforma::query()->find($proforma);

        if ($piece === null) {
            return;
        }

        try {
            $piece = $service->emettre($piece);
        } catch (RuntimeException $refus) {
            session()->flash('pwa-erreur', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('proforma.ui.emise', ['numero' => $piece->numero]));
    }

    public function ouvrirAnnulation(string $proforma): void
    {
        $this->ouvrirFormulaire('annulation');
        $this->cibleId = $proforma;
    }

    public function confirmerAnnulation(ProformaService $service): void
    {
        $this->validerEcriture(['motifAnnulation' => ['required', 'string', 'max:500']]);

        try {
            $service->annuler(Proforma::query()->findOrFail($this->cibleId), $this->motifAnnulation);
        } catch (RuntimeException $refus) {
            $this->addError('motifAnnulation', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('proforma.ui.annulee'));
    }

    /** La conversion se CONFIRME toujours (une expirée surtout) : une fois faite, elle est définitive. */
    public function ouvrirConversion(string $proforma): void
    {
        $this->ouvrirFormulaire('conversion');
        $this->cibleId = $proforma;
    }

    public function confirmerConversion(ProformaService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        try {
            $facture = $service->convertir(Proforma::query()->findOrFail($this->cibleId));
        } catch (RuntimeException $refus) {
            $this->etatFormulaire = null;
            session()->flash('pwa-erreur', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('proforma.ui.convertie', ['numero' => $facture->numero]));
    }

    public function imprimer(string $proforma, DocumentProforma $document): ?Response
    {
        $this->exigerEcriture(self::MODULE);
        $piece = Proforma::query()->find($proforma);

        if ($piece === null) {
            return null;
        }

        return response()->streamDownload(static function () use ($document, $piece): void {
            echo $document->pdf($piece);
        }, $document->nomFichier($piece));
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    public function render(): View
    {
        $terme = trim($this->recherche);
        $requete = Proforma::query()->withCount('lignes')->orderByDesc('created_at');

        if ($terme !== '') {
            $requete->where(static fn ($q) => $q->where('numero', 'like', '%'.$terme.'%')->orWhere('client_nom', 'like', '%'.$terme.'%')->orWhere('objet', 'like', '%'.$terme.'%'));
        }
        if (in_array($this->statut, Proforma::STATUTS, true)) {
            $requete->where('statut', $this->statut);
        }

        return view('pwa.facturation.proformas', array_merge($this->socle(), [
            'proformas' => $requete->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante)),
            'filtreApplique' => $terme !== '' || in_array($this->statut, Proforma::STATUTS, true),
            'peutEcrire' => $this->peutEcrire(),
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    /** @return array{designation: string, quantite: string, prix_unitaire: string} */
    private function ligneVide(): array
    {
        return ['designation' => '', 'quantite' => '1', 'prix_unitaire' => ''];
    }

    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur !== null && $utilisateur->estActif() && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }
}
