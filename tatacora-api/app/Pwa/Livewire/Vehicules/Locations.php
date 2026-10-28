<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Vehicules;

use App\Domain\Crm\Models\Client;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Exports\LocationsExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * M8 — Véhicules & Locations, en ÉCRITURE.
 *
 * Maître : `prototype_v2/pages/m8-locations.html` et `m8-locations.js`.
 *
 * ## Ce que ce composant NE fait pas, et pourquoi c'est le point important
 *
 * Il ne porte AUCUNE règle métier. RG-08 (double location) et RG-09 (pièces
 * justificatives) vivent dans `ContratLocationService`, qui écrit sous verrou
 * pessimiste ; l'entretien passe par `ParcVehiculeService` ; la dispense de
 * permis se lit sur `Vehicule::exigePermis()`, seul endroit qui connaisse
 * `CATEGORIES_SANS_PERMIS`. Recopier l'une de ces règles ici en ferait deux
 * versions, et la version recopiée serait celle qui décide au comptoir.
 *
 * ## Aucune suppression — le maître ARCHIVE, il n'efface pas
 *
 * `prototype_v2/assets/js/crud-engine.js` l.523-551 pose trois états
 * (bloqué / partiel / nominal), et `BasePolicy::delete()` rend `false` pour
 * les 20 policies. Le lot précédent appelait pourtant une SUPPRESSION PHYSIQUE
 * sur le véhicule et sur l'entretien : les clés étrangères portant
 * `restrictOnDelete()`, un véhicule sous contrat aurait renvoyé un `SQLSTATE`
 * brut à l'écran.
 *
 * Ici, archiver un véhicule le passe `hors_service` — la valeur existe déjà à
 * l'énumération de `vehicules.statut` — et l'opération est REFUSÉE tant qu'un
 * contrat actif court dessus. Annuler un contrat le passe `annule`. Une
 * immobilisation, elle, ne s'archive pas du tout : voir
 * `vehicules.pwa.refus_lever_immobilisation`, rendu à l'écran.
 *
 * ## Le RBAC est exigé à l'ouverture ET à l'enregistrement
 *
 * `FormulaireModal` porte les deux (lire son PHPDoc). L'ouverture évite de
 * faire saisir un formulaire que l'on refusera ; l'enregistrement est le seul
 * contrôle qui protège réellement, l'état de la modale étant une propriété
 * Livewire modifiable depuis le navigateur.
 *
 * ## Exporter est une LECTURE, et c'est traité comme tel
 *
 * `genererExport()` et `fermerModales()` n'exigent AUCUN droit
 * d'écriture : un export ne produit rien de neuf, il rend sur un autre
 * papier des données déjà à l'écran, et le droit de les lire est porté par
 * le middleware `module:M#,L` de la route. Les deux méthodes sont inscrites
 * dans `METHODES_DE_LECTURE` de `PwaEcritureAutoriseeTest` — inscrites,
 * donc RELUES : le corps de chacune reste balayé, et l'une d'elles qui se
 * mettrait un jour à persister serait signalée.
 *
 * @see EF-M8-01 Référentiel véhicules
 * @see EF-M8-02 Disponibilité et planning
 * @see EF-M8-03 Contrat de location
 * @see EF-M8-05 Suivi des entretiens et carburations
 * @see RG-08 Prévention des doubles locations
 * @see RG-09 Pièces justificatives conditionnelles
 * @see RG-18 Fiche client unique — `client_id` est une clé étrangère, jamais un nom libre
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4, 7
 */
#[Layout('layouts.pwa')]
#[Title('Véhicules & Locations — LogiReStock — TATACORA AFRIQUE')]
class Locations extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M8"` au maître. */
    public const MODULE = 'M8';

    public const ONGLETS = ['parc', 'contrats', 'planning', 'immo'];

    public const JOURS_PAR_DEFAUT = 14;

    /**
     * Le préfixe des numéros de contrat, alloués par `SequenceDocumentService`.
     *
     * Jamais `substr($uuid, 0, 6)` : quatre ou six caractères d'un UUID ne
     * sont ni séquentiels ni uniques, et le numéro ne dit rien de l'ordre des
     * contrats.
     */
    public const PREFIXE_CONTRAT = 'LOC';

    /**
     * Les motifs d'immobilisation RÉELS — l'énumération de la colonne
     * `entretiens_vehicule.type`, pas les trois motifs du maître.
     *
     * Le maître propose « Entretien programmé », « Panne / immobilisation » et
     * « Réservé à la direction » ; aucune de ces valeurs n'entrerait dans
     * l'énumération. Offrir un choix que la base rejette ferait tomber le
     * refus à l'enregistrement, sur un formulaire déjà rempli.
     */
    public const MOTIFS_IMMOBILISATION = [
        EntretienVehicule::TYPE_ENTRETIEN => 'motif_entretien',
        EntretienVehicule::TYPE_CARBURATION => 'motif_carburation',
    ];

    /** Les états archivables, jeu fermé : un type hors liste est un bug d'appel. */
    private const TYPES_ARCHIVABLES = ['vehicule', 'contrat'];

    // ---------------------------------------------------------------- filtres

    #[Url(as: 'onglet')]
    public string $onglet = 'parc';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'categorie')]
    public string $categorie = '';

    #[Url(as: 'statut')]
    public string $statut = 'actif';

    #[Url(as: 'debut')]
    public string $debut = '';

    #[Url(as: 'fin')]
    public string $fin = '';

    // ------------------------------------------------- formulaire « véhicule »

    public ?string $vehiculeIdEdite = null;

    public string $immatriculationSaisie = '';

    public string $categorieSaisie = '';

    public ?int $capaciteSaisie = null;

    public ?int $anneeSaisie = null;

    public string $transmissionSaisie = '';

    public string $tarifJourSaisi = '';

    // -------------------------------------------------- formulaire « contrat »

    public ?string $vehiculeIdContrat = null;

    public ?string $clientIdContrat = null;

    public string $pieceIdentiteSaisie = '';

    public string $numeroPermisSaisi = '';

    public string $dateDebutContrat = '';

    public string $dateFinContrat = '';

    public string $remiseSaisie = '0';

    public string $acompteSaisi = '0';

    // ------------------------------------------- formulaire « immobilisation »

    public ?string $vehiculeIdImmo = null;

    public string $motifImmo = EntretienVehicule::TYPE_ENTRETIEN;

    public string $dateImmo = '';

    public string $coutImmo = '0';

    // ---------------------------------------------------------- archivage

    public ?string $typeElementSupprime = null;

    public ?string $idElementSupprime = null;

    public ?string $libelleElementSupprime = null;

    /** @var list<string> */
    public array $verrousArchivage = [];

    public bool $archivageBloque = false;

    // ------------------------------------------------------------- export

    public string $formatExport = 'pdf';

    public function mount(): void
    {
        $aujourdhui = CarbonImmutable::today();

        if ($this->debut === '') {
            $this->debut = $aujourdhui->format('Y-m-d');
        }

        if ($this->fin === '') {
            $this->fin = $aujourdhui->addDays(self::JOURS_PAR_DEFAUT)->format('Y-m-d');
        }
    }

    /**
     * Le registre FERMÉ des formulaires, avec les propriétés à remettre à zéro.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'vehicule' => [
                'vehiculeIdEdite', 'immatriculationSaisie', 'categorieSaisie',
                'capaciteSaisie', 'anneeSaisie', 'transmissionSaisie', 'tarifJourSaisi',
            ],
            'contrat' => [
                'vehiculeIdContrat', 'clientIdContrat', 'pieceIdentiteSaisie',
                'numeroPermisSaisi', 'dateDebutContrat', 'dateFinContrat',
                'remiseSaisie', 'acompteSaisi',
            ],
            'immobilisation' => ['vehiculeIdImmo', 'motifImmo', 'dateImmo', 'coutImmo'],
            'archivage' => [
                'typeElementSupprime', 'idElementSupprime', 'libelleElementSupprime',
                'verrousArchivage', 'archivageBloque',
            ],
            'export' => ['formatExport'],
        ];
    }

    // =====================================================================
    // Écritures — référentiel du parc
    // =====================================================================

    /**
     * Ouvre le formulaire de véhicule, en création ou en édition.
     *
     * ⚠ Écart au maître, assumé : le maître pose le parc « en lecture seule »
     * parce que « le modifier suppose une table `vehicules` au backend ». Elle
     * existe ici. Le refus du maître a donc cessé d'être vrai, et le porter
     * quand même laisserait un parc que rien ne peuple hors seeder de
     * démonstration (plan PA-159, « Impossible aujourd'hui »).
     *
     * ⚠ Cette écriture devrait vivre dans `ParcVehiculeService`, dont le
     * PHPDoc la réserve explicitement. Ce lot ne modifie pas `app/Domain`
     * (périmètre) : elle est portée ici, sans règle métier, et devra y
     * migrer. Signalé le 31/08/2026.
     */
    public function ouvrirFormulaireVehicule(?string $vehiculeId = null): void
    {
        $this->ouvrirFormulaire('vehicule');

        $vehicule = $vehiculeId === null ? null : Vehicule::find($vehiculeId);

        if ($vehicule === null) {
            // La première valeur de l'énumération, jamais une catégorie écrite
            // ici : une liste locale divergerait du schéma au premier ajout.
            $this->categorieSaisie = $this->categoriesDuParc()[0] ?? '';

            return;
        }

        $this->vehiculeIdEdite = $vehicule->id;
        $this->immatriculationSaisie = $vehicule->immatriculation;
        $this->categorieSaisie = $vehicule->categorie;
        $this->capaciteSaisie = $vehicule->capacite;
        $this->anneeSaisie = $vehicule->annee;
        $this->transmissionSaisie = (string) $vehicule->transmission;
        $this->tarifJourSaisi = (string) $vehicule->tarif_jour;
    }

    public function enregistrerVehicule(): void
    {
        $donnees = $this->validerEcriture([
            'immatriculationSaisie' => [
                'required', 'string', 'max:255',
                'unique:vehicules,immatriculation'.($this->vehiculeIdEdite === null ? '' : ','.$this->vehiculeIdEdite),
            ],
            'categorieSaisie' => ['required', 'string', 'in:'.implode(',', $this->categoriesDuParc())],
            'anneeSaisie' => ['required', 'integer', 'min:1950', 'max:'.(int) date('Y') + 1],
            'capaciteSaisie' => ['required', 'integer', 'min:1', 'max:99'],
            'transmissionSaisie' => ['nullable', 'string', 'max:255'],
            'tarifJourSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        $attributs = [
            'immatriculation' => $donnees['immatriculationSaisie'],
            'categorie' => $donnees['categorieSaisie'],
            'annee' => $donnees['anneeSaisie'],
            'capacite' => $donnees['capaciteSaisie'],
            'transmission' => $donnees['transmissionSaisie'],
            'tarif_jour' => $donnees['tarifJourSaisi'],
        ];

        if ($this->vehiculeIdEdite === null) {
            // `statut` n'est PAS saisi : un véhicule entre au parc disponible,
            // et le statut se pilote par l'archivage et la remise en service.
            $attributs['statut'] = 'disponible';
            Vehicule::create($attributs);
        } else {
            Vehicule::findOrFail($this->vehiculeIdEdite)->update($attributs);
        }

        $this->terminerFormulaire(__('vehicules.pwa.vehicule_enregistre', [
            'immatriculation' => $donnees['immatriculationSaisie'],
        ]));
    }

    /**
     * Remet au parc un véhicule archivé ou immobilisé.
     *
     * C'est la moitié qui manquait au geste d'archivage : le maître promet
     * « rien n'est effacé, l'élément reste restaurable », et une promesse sans
     * chemin de retour est le défaut PA-59/60/61 sous une autre forme.
     */
    public function remettreEnService(string $vehiculeId): void
    {
        $this->exigerEcriture(self::MODULE);

        $vehicule = Vehicule::findOrFail($vehiculeId);

        // Même chemin que l'onglet « Restaurer » d'Import & Export
        // (`ParcVehiculeService`, 02/09/2026) — jamais deux écrivains.
        app(ParcVehiculeService::class)->remettreEnService($vehicule);

        session()->flash('pwa-succes', __('vehicules.pwa.remise_en_service_faite', [
            'immatriculation' => $vehicule->immatriculation,
        ]));
    }

    // =====================================================================
    // Écritures — contrat de location
    // =====================================================================

    public function ouvrirFormulaireContrat(?string $vehiculeId = null): void
    {
        $this->ouvrirFormulaire('contrat');

        [$debut, $fin] = $this->fenetre();

        $this->vehiculeIdContrat = $vehiculeId ?? Vehicule::query()
            ->whereIn('statut', Vehicule::STATUTS_LOUABLES)
            ->orderBy('immatriculation')
            ->value('id');

        $this->clientIdContrat = Client::query()->orderBy('nom')->value('id');
        $this->dateDebutContrat = $debut->format('Y-m-d');
        $this->dateFinContrat = $fin->format('Y-m-d');
        $this->remiseSaisie = '0';
        $this->acompteSaisi = '0';
    }

    /**
     * Établit le contrat — RG-08 et RG-09 sont tenues par le SERVICE.
     *
     * Le service lève : `ChevauchementDetecteException` si le véhicule est
     * déjà engagé sur la plage, `RuntimeException` si une pièce manque ou si
     * le véhicule n'est pas louable. Les deux messages sont affichés tels
     * quels sur le champ concerné — jamais avalés : un `catch` qui rendrait
     * « contrat créé » sur un refus est le défaut que le lot précédent portait.
     */
    public function enregistrerContrat(): void
    {
        $donnees = $this->validerEcriture([
            'vehiculeIdContrat' => ['required', 'string', 'exists:vehicules,id'],
            'clientIdContrat' => ['required', 'string', 'exists:clients,id'],
            'pieceIdentiteSaisie' => ['required', 'string', 'max:255'],
            'numeroPermisSaisi' => ['nullable', 'string', 'max:255'],
            'dateDebutContrat' => ['required', 'date'],
            'dateFinContrat' => ['required', 'date', 'after:dateDebutContrat'],
            'remiseSaisie' => ['required', 'numeric', 'min:0'],
            'acompteSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        $vehicule = Vehicule::findOrFail($donnees['vehiculeIdContrat']);

        // RG-09 — la question est posée AU MODÈLE, seul endroit qui connaisse
        // `CATEGORIES_SANS_PERMIS`. Le service refusera de toute façon ; le
        // faire ici accroche le message au champ où on le corrige, au lieu
        // d'une bannière générique.
        if ($vehicule->exigePermis() && $donnees['numeroPermisSaisi'] === '') {
            $this->addError('numeroPermisSaisi', __('vehicules.permis_requis', [
                'categorie' => $vehicule->categorie,
            ]));

            return;
        }

        $debut = CarbonImmutable::parse($donnees['dateDebutContrat']);
        $fin = CarbonImmutable::parse($donnees['dateFinContrat']);
        $jours = (int) $debut->diffInDays($fin);

        $montantBrut = bcmul((string) $vehicule->tarif_jour, (string) $jours, 2);
        $remise = bcadd((string) $donnees['remiseSaisie'], '0', 2);
        $acompte = bcadd((string) $donnees['acompteSaisi'], '0', 2);

        // Une remise supérieure au brut produirait un montant négatif, donc un
        // « reste dû » négatif présenté comme une créance du client sur le gîte.
        if (bccomp($remise, $montantBrut, 2) > 0) {
            $this->addError('remiseSaisie', __('validation.lte.numeric', [
                'attribute' => __('vehicules.pwa.champ_remise'),
                'value' => $montantBrut,
            ]));

            return;
        }

        $montantNet = bcsub($montantBrut, $remise, 2);

        if (bccomp($acompte, $montantNet, 2) > 0) {
            $this->addError('acompteSaisi', __('validation.lte.numeric', [
                'attribute' => __('vehicules.pwa.champ_acompte'),
                'value' => $montantNet,
            ]));

            return;
        }

        $reste = bcsub($montantNet, $acompte, 2);

        try {
            $numero = DB::transaction(function () use (
                $vehicule,
                $donnees,
                $debut,
                $fin,
                $montantNet,
                $acompte,
                $reste
            ): string {
                $contrat = app(ContratLocationService::class)->creer([
                    'vehicule_id' => $vehicule->id,
                    'client_id' => $donnees['clientIdContrat'],
                    'date_debut' => $debut->format('Y-m-d'),
                    'date_fin' => $fin->format('Y-m-d'),
                    'piece_identite' => $donnees['pieceIdentiteSaisie'],
                    'permis_conduire' => $donnees['numeroPermisSaisi'] === '' ? null : $donnees['numeroPermisSaisi'],
                ]);

                $numero = app(SequenceDocumentService::class)
                    ->suivant('contrats_location', self::PREFIXE_CONTRAT);

                // `forceFill` et non `update` : les six colonnes ajoutées par
                // `2026_08_28_200000_add_missing_pwa_columns.php` existent en
                // base mais ne figurent pas au `$fillable` du modèle de
                // domaine, que ce lot n'a pas le droit de modifier. Une
                // affectation de masse les jetterait EN SILENCE — le montant
                // serait resté à zéro sur l'écran où l'on réclame le solde.
                // `client_nom` reste délibérément vide : RG-18 interdit de
                // dupliquer un nom de client hors de sa fiche.
                $contrat->forceFill([
                    'numero' => $numero,
                    'statut' => 'actif',
                    'montant' => $montantNet,
                    'acompte' => $acompte,
                    'reste_a_payer' => $reste,
                ])->save();

                return $numero;
            });
        } catch (ChevauchementDetecteException $e) {
            $this->addError('vehiculeIdContrat', $e->getMessage());

            return;
        } catch (RuntimeException $e) {
            // Le service refuse : véhicule non louable (RG-08 côté statut) ou
            // pièce manquante (RG-09). Son message est affiché TEL QUEL —
            // rendre « contrat créé » sur un refus est le défaut que portait
            // le lot précédent.
            $this->addError('vehiculeIdContrat', $e->getMessage());

            return;
        }

        $this->terminerFormulaire(__('vehicules.pwa.contrat_etabli', [
            'numero' => $numero,
            'montant' => $montantNet,
            'jours' => $jours,
        ]));
    }

    // =====================================================================
    // Écritures — immobilisation
    // =====================================================================

    public function ouvrirFormulaireImmobilisation(?string $vehiculeId = null): void
    {
        $this->ouvrirFormulaire('immobilisation');

        [$debut] = $this->fenetre();

        $this->vehiculeIdImmo = $vehiculeId ?? Vehicule::query()->orderBy('immatriculation')->value('id');
        $this->motifImmo = EntretienVehicule::TYPE_ENTRETIEN;
        $this->dateImmo = $debut->format('Y-m-d');
        $this->coutImmo = '0';
    }

    /**
     * Enregistre l'entretien par le service de domaine — EF-M8-05.
     *
     * `vehicules.statut` n'est PAS touché : le statut n'est pas la
     * disponibilité (même distinction qu'en M1, RG-02), et une immobilisation
     * datée ne doit pas poser un drapeau permanent que rien ne lèverait. Le
     * lot précédent écrivait `statut = 'entretien'` ici, sans aucun chemin de
     * retour.
     */
    public function enregistrerImmobilisation(): void
    {
        $donnees = $this->validerEcriture([
            'vehiculeIdImmo' => ['required', 'string', 'exists:vehicules,id'],
            'motifImmo' => ['required', 'string', 'in:'.implode(',', array_keys(self::MOTIFS_IMMOBILISATION))],
            'dateImmo' => ['required', 'date'],
            'coutImmo' => ['required', 'numeric', 'min:0'],
        ]);

        $vehicule = Vehicule::findOrFail($donnees['vehiculeIdImmo']);

        app(ParcVehiculeService::class)->enregistrerEntretien([
            'vehicule_id' => $vehicule->id,
            'type' => $donnees['motifImmo'],
            'date' => $donnees['dateImmo'],
            'cout' => $donnees['coutImmo'],
        ]);

        $this->terminerFormulaire(__('vehicules.pwa.immobilisation_enregistree', [
            'immatriculation' => $vehicule->immatriculation,
            'date' => CarbonImmutable::parse($donnees['dateImmo'])->format('d/m/Y'),
        ]));
    }

    // =====================================================================
    // Archivage — trois états, aucune suppression
    // =====================================================================

    /**
     * Prépare la confirmation d'archivage et CALCULE ses verrous en base.
     *
     * L'état bloqué se décide AVANT le clic : le maître masque alors le bouton
     * de confirmation (`crud-engine.js` l.535). Laisser un bouton visible et
     * inerte laisserait croire à une panne.
     */
    public function confirmerArchivage(string $type, string $id): void
    {
        $this->ouvrirFormulaire('archivage');

        if (! in_array($type, self::TYPES_ARCHIVABLES, true)) {
            abort(404);
        }

        $this->typeElementSupprime = $type;
        $this->idElementSupprime = $id;

        if ($type === 'vehicule') {
            $vehicule = Vehicule::findOrFail($id);
            $this->libelleElementSupprime = $vehicule->immatriculation;
            $this->verrousArchivage = $this->verrousDuVehicule($vehicule);
        } else {
            $contrat = ContratLocation::with('vehicule')->findOrFail($id);
            $this->libelleElementSupprime = (string) ($contrat->numero ?? $contrat->id);
            $this->verrousArchivage = $contrat->statut === 'annule'
                ? [__('vehicules.pwa.verrou_contrat_annule')]
                : [];
        }

        $this->archivageBloque = $this->verrousArchivage !== [];
    }

    /**
     * Exécute l'archivage — ASCII pur dans le nom, le dispatch Livewire ne
     * survit pas à un accent (V8, vague précédente).
     *
     * Aucun `delete()` : un véhicule passe `hors_service`, un contrat passe
     * `annule`. Les deux restent lisibles, et les lignes qui les référencent
     * aussi.
     */
    public function executerSuppression(): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->idElementSupprime === null || $this->archivageBloque) {
            // Le bouton n'est pas rendu dans cet état : y arriver signifie que
            // la propriété a été forcée depuis le navigateur.
            abort(403);
        }

        if ($this->typeElementSupprime === 'vehicule') {
            $vehicule = Vehicule::findOrFail($this->idElementSupprime);

            // Le verrou est RECALCULÉ par le service au moment d'agir (ceux
            // affichés datent de l'ouverture de la modale, un contrat a pu
            // naître depuis) — `ParcVehiculeService::archiver()`, extrait de
            // cet écran le 02/09/2026 pour que l'onglet « Restaurer »
            // d'Import & Export emprunte le MÊME chemin.
            try {
                app(ParcVehiculeService::class)->archiver($vehicule);
            } catch (RuntimeException $refus) {
                // Le refus est NOMMÉ avec le mot du service, et la modale se
                // rouvre sur les verrous recalculés — jamais un échec avalé.
                // ⚠ ORDRE : `confirmerArchivage()` passe par `ouvrirFormulaire()`
                // qui appelle `resetValidation()` — l'erreur se pose APRÈS.
                $this->confirmerArchivage('vehicule', $vehicule->id);
                $this->addError('idElementSupprime', $refus->getMessage());

                return;
            }
            $message = __('vehicules.pwa.archivage_vehicule_fait', [
                'immatriculation' => $vehicule->immatriculation,
            ]);
        } elseif ($this->typeElementSupprime === 'contrat') {
            $contrat = ContratLocation::findOrFail($this->idElementSupprime);
            // Le SERVICE annule (26/10/2026) : le même chemin que la
            // synchronisation d'un poste, la même phrase de refus.
            app(ContratLocationService::class)->annuler($contrat);
            $message = __('vehicules.pwa.archivage_contrat_fait', [
                'numero' => (string) ($contrat->numero ?? $contrat->id),
            ]);
        } else {
            abort(404);
        }

        $this->terminerFormulaire($message);
    }

    // =====================================================================
    // Export — PA-119 : il porte sur CE QUI EST AFFICHÉ, et il DIT son filtre
    // =====================================================================

    /**
     * @return StreamedResponse|\Symfony\Component\HttpFoundation\BinaryFileResponse|null
     */
    public function genererExport()
    {
        $onglet = $this->ongletValide();
        $lignes = $this->lignesExportables($onglet);

        if ($lignes === []) {
            // PA-119 : une liste vide se REFUSE, elle ne produit pas une page
            // blanche que l'on croirait complète.
            $this->addError('formatExport', __('vehicules.pwa.contrats_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new LocationsExport($onglet, $lignes, $this->descriptionDuFiltre()),
                'vehicules_locations_'.$onglet.'_'.now()->format('Ymd_His').'.xlsx',
            );
        }

        $pdf = Pdf::loadView('pdf.locations', $this->donneesDuDocument($onglet, $lignes))
            ->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'vehicules_locations_'.$onglet.'_'.now()->format('Ymd_His').'.pdf',
        );
    }

    /**
     * Le REÇU de location (PDF A4) d'UN contrat — la même pièce que le poste
     * (`impression/recu_location.dart`).
     *
     * ## C'est une LECTURE
     *
     * Rien n'est écrit et aucun numéro n'est alloué : le N° est celui que le
     * contrat porte déjà (`LOC-…`), un contrat qui n'en a pas rend le tiret.
     * Comme `genererExport()`, elle n'exige pas le droit d'écriture : elle ne
     * rend que ce que l'écran affiche déjà. Inscrite dans
     * `METHODES_DE_LECTURE` de `PwaEcritureAutoriseeTest`, donc relue.
     *
     * ## Ce que le document dit, et ne dit pas
     *
     * - il ne vaut PAS facture (mention au corps) : la facture normalisée est
     *   émise à l'encaissement ;
     * - un contrat ANNULÉ porte le bandeau « ANNULÉ » et AUCUN montant : ni
     *   total, ni acompte, ni reste dû (rien n'est dû au titre d'un contrat
     *   annulé) ;
     * - le tarif journalier n'est écrit que s'il EXPLIQUE le montant figé
     *   (tarif du véhicule × jours = montant) ; sinon le tiret — le montant
     *   est figé à la signature, le tarif du véhicule peut avoir changé.
     */
    public function imprimerRecu(string $contrat): StreamedResponse
    {
        $piece = ContratLocation::with(['vehicule', 'client'])->findOrFail($contrat);

        $pdf = Pdf::loadView('pdf.location-recu', [
            'contrat' => $piece,
            ...app(ContratLocationService::class)->donneesRecu($piece),
            'entete' => $this->enTeteRapport(
                __('vehicules.pwa.recu_titre'),
                __('rapports.periode.du_au', [
                    'debut' => $piece->date_debut->format('d/m/Y'),
                    'fin' => $piece->date_fin->format('d/m/Y'),
                ]),
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            __('vehicules.pwa.recu_fichier').'_'.($piece->numero ?? substr((string) $piece->id, 0, 8)).'.pdf',
        );
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    public function render(): View
    {
        [$debut, $fin] = $this->fenetre();
        $jours = max(1, (int) $debut->diffInDays($fin));

        $parc = $this->parcFiltre();
        $contrats = $this->contratsFiltres();
        $immobilisations = $this->immobilisations();

        // La formule des quatre agrégats vit dans `ParcVehiculeService`
        // depuis le 02/09/2026 : la carte « Location de véhicules » de
        // l'accueil lit la même — deux formules divergeraient (PA-121).
        $agregats = ParcVehiculeService::agregerContratsActifs($contrats->collect());

        $capaciteJours = $parc->count() * $jours;

        return view('pwa.vehicules.locations', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'parc' => $parc,
            'contrats' => $contrats,
            'immobilisations' => $immobilisations,
            'disponibilites' => $this->disponibilites($parc, $debut, $fin),
            'categories' => $this->categoriesDuParc(),
            'clients' => Client::query()->orderBy('nom')->get(['id', 'nom', 'prenom', 'telephone']),
            'parcComplet' => Vehicule::query()->orderBy('immatriculation')->get(),
            'joursFenetre' => $jours,
            'fenetreDebut' => $debut,
            'fenetreFin' => $fin,
            'parcCount' => $parc->count(),
            'immobilisesCount' => $parc->whereIn('statut', Vehicule::STATUTS_IMMOBILISES)->count(),
            'contratsActifsCount' => $agregats['contrats_actifs'],
            'contratsAnnulesCount' => $contrats->count() - $agregats['contrats_actifs'],
            'chiffreAffaires' => $agregats['chiffre_affaires'],
            'resteAEncaisser' => $agregats['reste_a_encaisser'],
            'joursLoues' => $agregats['jours_loues'],
            'tauxOccupation' => $capaciteJours > 0
                ? round(($agregats['jours_loues'] / $capaciteJours) * 100, 1)
                : null,
            'peutEcrire' => $this->peutEcrire(),
        ]));
    }

    // ---------------------------------------------------------------- privé

    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur instanceof User
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    private function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'parc';
    }

    /**
     * @return array{0: CarbonImmutable, 1: CarbonImmutable}
     */
    private function fenetre(): array
    {
        $aujourdhui = CarbonImmutable::today();

        $debut = $this->dateOuNull($this->debut) ?? $aujourdhui;
        $fin = $this->dateOuNull($this->fin) ?? $debut->addDays(self::JOURS_PAR_DEFAUT);

        if ($fin->lessThanOrEqualTo($debut)) {
            $fin = $debut->addDays(self::JOURS_PAR_DEFAUT);
        }

        return [$debut, $fin];
    }

    private function dateOuNull(string $valeur): ?CarbonImmutable
    {
        if ($valeur === '' || preg_match('/^\d{4}-\d{2}-\d{2}$/', $valeur) !== 1) {
            return null;
        }

        // Une date hors calendrier (« 2026-02-31 ») vient d'une URL, donc de
        // l'extérieur : elle est ignorée, jamais devinée.
        [$a, $m, $j] = array_map('intval', explode('-', $valeur));

        return checkdate($m, $j, $a) ? CarbonImmutable::create($a, $m, $j)->startOfDay() : null;
    }

    /**
     * Les catégories offertes — l'ÉNUMÉRATION de la colonne, lue en base.
     *
     * Une liste écrite dans le composant divergerait de l'énumération au
     * premier ajout, et le refus ne tomberait qu'à l'enregistrement.
     *
     * @return list<string>
     */
    private function categoriesDuParc(): array
    {
        $type = DB::selectOne(
            'SELECT COLUMN_TYPE AS type FROM information_schema.COLUMNS '
            .'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            ['vehicules', 'categorie'],
        );

        if ($type === null || preg_match_all("/'([^']+)'/", (string) $type->type, $trouves) === 0) {
            // La colonne est introuvable : refuser plutôt que d'offrir une
            // liste devinée que la base rejetterait.
            return [];
        }

        return $trouves[1];
    }

    /**
     * @return \Illuminate\Database\Eloquent\Collection<int, Vehicule>
     */
    private function parcFiltre(): \Illuminate\Database\Eloquent\Collection
    {
        $terme = trim($this->recherche);

        return Vehicule::query()
            ->when($this->categorie !== '', fn ($q) => $q->where('categorie', $this->categorie))
            ->when($terme !== '', fn ($q) => $q->where('immatriculation', 'like', '%'.$terme.'%'))
            ->orderBy('immatriculation')
            ->get();
    }

    /**
     * @return \Illuminate\Database\Eloquent\Collection<int, ContratLocation>
     */
    private function contratsFiltres(): \Illuminate\Database\Eloquent\Collection
    {
        $terme = trim($this->recherche);
        [$debut, $fin] = $this->fenetre();

        // Le prédicat de fenêtre vient du Service (02/09/2026) — la carte
        // d'accueil lit la même population, jamais une seconde requête.
        return app(ParcVehiculeService::class)->contratsSurFenetre($debut, $fin)
            // `with()` : sans lui, chaque ligne rouvrirait deux requêtes pour
            // son véhicule et son client.
            ->with(['vehicule', 'client'])
            ->when($this->statut === 'actif', fn ($q) => $q->where('statut', '!=', 'annule'))
            ->when($this->statut === 'annule', fn ($q) => $q->where('statut', 'annule'))
            ->when($terme !== '', function ($q) use ($terme) {
                $q->where(function ($sous) use ($terme) {
                    $sous->where('numero', 'like', '%'.$terme.'%')
                        ->orWhereHas('vehicule', fn ($v) => $v->where('immatriculation', 'like', '%'.$terme.'%'))
                        ->orWhereHas('client', fn ($c) => $c->where('nom', 'like', '%'.$terme.'%'));
                });
            })
            ->orderByDesc('date_debut')
            ->get();
    }

    /**
     * Les immobilisations, avec le LOGIN de qui les a enregistrées.
     *
     * `utilisateur_creation_id` vient de `Auditable` (migration
     * `2026_08_28_000001_ajouter_audit_referentiels`) ; `chauffeur_id`, lui,
     * désigne le chauffeur affecté, jamais l'auteur de la saisie.
     *
     * @return list<array{id: string, vehicule: string, motif: string, date: \Illuminate\Support\Carbon, cout: string, auteur: string|null}>
     */
    private function immobilisations(): array
    {
        $entretiens = EntretienVehicule::query()
            ->with('vehicule')
            ->orderByDesc('date')
            ->get();

        // Une seule requête pour tous les auteurs, jamais une par ligne.
        $logins = User::query()
            ->whereIn('id', $entretiens->pluck('utilisateur_creation_id')->filter()->unique())
            ->pluck('login', 'id');

        return $entretiens->map(static function (EntretienVehicule $e) use ($logins): array {
            $auteur = $logins->get((string) $e->utilisateur_creation_id);

            return [
                'id' => $e->id,
                'vehicule' => $e->vehicule->immatriculation,
                'motif' => $e->type,
                'date' => $e->date,
                'cout' => (string) $e->cout,
                // Une ligne anterieure a l'audit des referentiels n'a pas
                // d'auteur : l'ecran rend « — », il n'en invente pas un.
                'auteur' => is_string($auteur) ? $auteur : null,
            ];
        })->values()->all();
    }

    /**
     * La disponibilité vient du SERVICE — RG-08, jamais un `whereBetween`
     * recopié : un véhicule annoncé libre alors qu'il est loué est exactement
     * le défaut que M8 existe pour empêcher.
     *
     * @param  \Illuminate\Database\Eloquent\Collection<int, Vehicule>  $parc
     * @return array<string, bool>
     */
    private function disponibilites(
        \Illuminate\Database\Eloquent\Collection $parc,
        CarbonImmutable $debut,
        CarbonImmutable $fin,
    ): array {
        $service = app(ContratLocationService::class);
        $etat = [];

        foreach ($parc as $vehicule) {
            $etat[$vehicule->id] = $vehicule->estLouable() && $service->estDisponible(
                $vehicule->id,
                $debut->format('Y-m-d'),
                $fin->format('Y-m-d'),
            );
        }

        return $etat;
    }

    /**
     * Les verrous d'archivage d'un véhicule, LUS EN BASE.
     *
     * Un véhicule engagé sur un contrat non annulé dont la restitution n'est
     * pas passée ne s'archive pas : la ligne de contrat deviendrait illisible.
     *
     * @return list<string>
     */
    private function verrousDuVehicule(Vehicule $vehicule): array
    {
        // Le PRÉDICAT d'engagement vit dans `ParcVehiculeService::
        // contratsEngages()` (02/09/2026) — cet écran ne fait plus que le
        // mettre en phrases pour la modale d'archivage.
        $contrats = app(ParcVehiculeService::class)->contratsEngages($vehicule);

        if ($contrats->isEmpty()) {
            return [];
        }

        $apercu = $contrats->take(3)->map(static fn (ContratLocation $c): string => __(
            'vehicules.pwa.verrou_contrat',
            [
                'numero' => (string) ($c->numero ?? $c->id),
                'debut' => $c->date_debut->format('d/m/Y'),
                'fin' => $c->date_fin->format('d/m/Y'),
            ],
        ))->implode(' · ');

        return [__('vehicules.pwa.verrou', [
            'nombre' => $contrats->count(),
            'apercu' => $apercu.($contrats->count() > 3 ? ' …' : ''),
        ])];
    }

    /**
     * Les lignes RÉELLEMENT AFFICHÉES de l'onglet — PA-119.
     *
     * @return list<array<int, string>>
     */
    private function lignesExportables(string $onglet): array
    {
        if ($onglet === 'parc' || $onglet === 'planning') {
            [$debut, $fin] = $this->fenetre();
            $parc = $this->parcFiltre();
            $dispo = $this->disponibilites($parc, $debut, $fin);
            $jours = max(1, (int) $debut->diffInDays($fin));

            return $parc->map(fn (Vehicule $v): array => [
                $v->immatriculation,
                $v->categorie,
                (string) $v->capacite,
                $v->exigePermis() ? __('vehicules.pwa.permis_exige') : __('vehicules.pwa.permis_dispense'),
                (string) $v->tarif_jour,
                bcmul((string) $v->tarif_jour, (string) $jours, 2),
                ($dispo[$v->id] ?? false)
                    ? __('vehicules.pwa.disponible')
                    : __('vehicules.pwa.engage'),
            ])->values()->all();
        }

        if ($onglet === 'immo') {
            return array_map(fn (array $i): array => [
                $i['vehicule'],
                __('vehicules.pwa.'.self::MOTIFS_IMMOBILISATION[$i['motif']]),
                $i['date']->format('d/m/Y'),
                $i['cout'],
                $i['auteur'] ?? MontantFcfa::TIRET,
            ], $this->immobilisations());
        }

        return $this->contratsFiltres()->map(fn (ContratLocation $c): array => [
            (string) ($c->numero ?? MontantFcfa::TIRET),
            $c->vehicule->immatriculation,
            $c->client->nom,
            $c->date_debut->format('d/m/Y'),
            $c->date_fin->format('d/m/Y'),
            (string) $c->nombreJours(),
            (string) ($c->montant ?? '0'),
            (string) ($c->acompte ?? '0'),
            (string) ($c->reste_a_payer ?? '0'),
            $c->statut === 'annule'
                ? __('vehicules.pwa.contrat_annule')
                : __('vehicules.pwa.contrat_actif'),
        ])->values()->all();
    }

    /**
     * Le filtre, écrit en toutes lettres sur le document — PA-119.
     */
    private function descriptionDuFiltre(): string
    {
        [$debut, $fin] = $this->fenetre();

        $morceaux = [
            __('vehicules.pwa.du').' '.$debut->format('d/m/Y').' '
                .__('vehicules.pwa.au').' '.$fin->format('d/m/Y'),
        ];

        if ($this->categorie !== '') {
            $morceaux[] = __('vehicules.pwa.col_categorie').' : '.$this->categorie;
        }

        if (trim($this->recherche) !== '') {
            $morceaux[] = __('vehicules.pwa.recherche').' '.trim($this->recherche);
        }

        return implode(' · ', $morceaux);
    }

    /**
     * @param  list<array<int, string>>  $lignes
     * @return array<string, mixed>
     */
    private function donneesDuDocument(string $onglet, array $lignes): array
    {
        $utilisateur = auth()->user();
        $titre = match ($onglet) {
            'parc', 'planning' => __('vehicules.pwa.onglet_parc'),
            'immo' => __('vehicules.pwa.onglet_immo'),
            default => __('vehicules.pwa.onglet_contrats'),
        };

        return [
            'entete' => $this->enTeteRapport($titre, $this->descriptionDuFiltre()),
            'titreDocument' => $titre,
            'lignes' => $lignes,
            'entetes' => LocationsExport::entetesDe($onglet),
            'filtre' => $this->descriptionDuFiltre(),
            // `login` : `utilisateurs` n'a aucune colonne `name`, et
            // `Auth::user()->name` rendait null sur tous les documents.
            'auteur' => $utilisateur instanceof User ? $utilisateur->login : null,
        ];
    }
}
