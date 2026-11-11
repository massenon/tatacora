<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Tourisme;

use App\Domain\Crm\Models\Client;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Exports\TourismeExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\MontantFcfa;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as CollectionEloquent;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;

/**
 * M9 — Tourisme, en ÉCRITURE.
 *
 * Maître : `prototype_v2/pages/m9-tourisme-departs.html` et
 * `m9-tourisme-departs.js`.
 *
 * ## Un DÉPART est dérivé, il n'est pas stocké — et c'est le point central
 *
 * Il n'existe AUCUNE table `departs` au schéma. Un départ, c'est le couple
 * (`circuit_id`, `date_circuit`) porté par les lignes de `reservations_tour`,
 * plus le guide que ces lignes désignent. Le lot précédent le rangeait dans
 * la SESSION HTTP, sous la clé `tourisme_departs_assignments` : la
 * table affichait le nouveau guide pendant que la base gardait l'ancien,
 * l'écran disait Paul et le départ partait avec Jean, et la décision
 * disparaissait à la déconnexion. La réaffectation passe désormais par
 * `ReservationTourService::affecterGuide()`, donc par la base.
 *
 * ## La capacité n'est PAS recalculée ici
 *
 * `ReservationTourService` porte le contrôle **cumulé sur le départ**, sous
 * verrou pessimiste (EF-M9-04, PA-51). Le lot précédent posait
 * `capaciteRestanteResa = 99` en édition — une valeur d'échappement qui est
 * une sur-réservation en puissance. L'écran affiche ce que le service
 * calcule (`placesRestantes()`), et c'est le service qui refuse.
 *
 * ## Ce que ce composant refuse, et qui est NOMMÉ à l'écran
 *
 * « Planifier un départ », la colonne « Véhicule », les numéros, l'acompte,
 * les excursions, l'indicatif en euros, le motif de réaffectation et la
 * suppression d'une prestation : voir les clés `tourisme.pwa.refus_*`, toutes
 * rendues en bas d'écran avec la date à laquelle leur raison a été vérifiée.
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
 * @see EF-M9-01 Catalogue de circuits
 * @see EF-M9-03 Réservation avec affectation de guide
 * @see EF-M9-04 Capacité maximale par circuit
 * @see UC-39 Réaffecter un guide
 * @see RG-18 Fiche client unique
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4, 7
 */
#[Layout('layouts.pwa')]
#[Title('Tourisme — LogiReStock — TATACORA AFRIQUE')]
class Departs extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M9"` au maître. */
    public const MODULE = 'M9';

    public const ONGLETS = ['departs', 'reservations', 'catalogue'];

    public const JOURS_PAR_DEFAUT = 30;

    /** Les états archivables, jeu fermé. */
    private const TYPES_ARCHIVABLES = ['reservation', 'depart'];

    // ---------------------------------------------------------------- filtres

    #[Url(as: 'onglet')]
    public string $onglet = 'departs';

    #[Url(as: 'q')]
    public string $recherche = '';

    /**
     * Le select « Circuits et excursions » du maître (`m9-tourisme-departs.html`
     * l.60-64, `#f-type`) — filtre par PRESTATION, pas par type (01/09/2026).
     *
     * ## Pourquoi ce n'est plus le filtre du maître, à la lettre
     *
     * `circuits` ne porte AUCUNE colonne distinguant un circuit d'une
     * excursion — vérifié sur le schéma, pas supposé. Le rendre fidèlement
     * (options « Circuits » / « Excursions ») afficherait une commande qui ne
     * filtrerait jamais rien : le défaut exact qu'Article 3.3 interdit
     * (aucune entrée inerte). Une version antérieure a donc OMIS le contrôle
     * — jeton `maitre-refuse:m9-tourisme-departs.html#page` retiré ici, le
     * contrôle étant désormais réel.
     *
     * Le select reprend la MÊME position et le MÊME libellé par défaut
     * (« Circuits et excursions ») que le maître, mais ses options sont la
     * liste RÉELLE des circuits du catalogue : un « départ » comme une
     * « réservation » se rattachent tous deux à UN circuit précis
     * (`circuit_id`, NOT NULL), qui est la seule granularité que le schéma
     * garantit. Filtrer « par prestation » est donc un filtre qui existe
     * vraiment, là où filtrer « par type » ne le pourrait pas.
     */
    #[Url(as: 'prestation')]
    public string $prestationId = '';

    #[Url(as: 'remplissage')]
    public string $remplissage = '';

    #[Url(as: 'statut')]
    public string $statut = 'planifie';

    #[Url(as: 'debut')]
    public string $debut = '';

    #[Url(as: 'fin')]
    public string $fin = '';

    // --------------------------------------------- formulaire « réservation »

    public ?string $circuitIdResa = null;

    public string $dateDepartResa = '';

    public ?string $guideIdResa = null;

    public ?string $clientIdResa = null;

    public ?int $nbPersonnesSaisi = 1;

    /** Départ verrouillé quand la réservation est ouverte depuis une ligne. */
    public bool $departImpose = false;

    // ---------------------------------------- modale « Ajouter un guide »
    //
    // Posée PAR-DESSUS « Réserver des places » : ce n'est pas un formulaire du
    // registre (`etatFormulaire` n'en porte qu'un à la fois, et ouvrir celui-ci
    // effacerait la réservation en cours de saisie).

    public bool $ajoutGuideOuvert = false;

    public string $guideNomSaisi = '';

    public string $guideCertificationSaisie = '';

    public string $guideZoneSaisie = '';

    public string $guideTarifSaisi = '';

    // ------------------------------------------------ formulaire « réaffecter »

    public ?string $circuitIdGuide = null;

    public string $dateDepartGuide = '';

    public ?string $nouveauGuideId = null;

    // ------------------------------------------------- formulaire « prestation »

    public ?string $circuitIdEdite = null;

    public string $circuitNomSaisi = '';

    public string $circuitThemeSaisi = '';

    public string $circuitZoneSaisie = '';

    public string $circuitDureeSaisie = '';

    public string $circuitPrixSaisi = '';

    public ?int $circuitCapaciteSaisie = null;

    // ---------------------------------------------------------- archivage

    public ?string $typeElementSupprime = null;

    public ?string $idElementSupprime = null;

    public ?string $dateElementSupprime = null;

    public ?string $libelleElementSupprime = null;

    /** @var list<string> */
    public array $verrousArchivage = [];

    public bool $archivageBloque = false;

    public int $placesConcernees = 0;

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
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'reservation' => [
                'circuitIdResa', 'dateDepartResa', 'guideIdResa',
                'clientIdResa', 'nbPersonnesSaisi', 'departImpose', 'ajoutGuideOuvert',
            ],
            'guide' => ['circuitIdGuide', 'dateDepartGuide', 'nouveauGuideId'],
            'prestation' => [
                'circuitIdEdite', 'circuitNomSaisi', 'circuitThemeSaisi', 'circuitZoneSaisie',
                'circuitDureeSaisie', 'circuitPrixSaisi', 'circuitCapaciteSaisie',
            ],
            'archivage' => [
                'typeElementSupprime', 'idElementSupprime', 'dateElementSupprime',
                'libelleElementSupprime', 'verrousArchivage', 'archivageBloque', 'placesConcernees',
            ],
            'export' => ['formatExport'],
        ];
    }

    // =====================================================================
    // Écritures — réservation d'un départ
    // =====================================================================

    /**
     * Ouvre « Réserver des places ».
     *
     * Sans argument, c'est aussi le geste qui CRÉE un départ : le premier
     * enregistrement sur un couple (circuit, date) le fait exister. Avec
     * argument, le départ est imposé et ses trois clés sont verrouillées.
     */
    public function ouvrirFormulaireReservation(
        ?string $circuitId = null,
        ?string $dateDepart = null,
        ?string $guideId = null,
    ): void {
        $this->ouvrirFormulaire('reservation');

        [$debutFenetre] = $this->fenetre();

        $this->circuitIdResa = $circuitId ?? Circuit::query()->orderBy('nom')->value('id');
        $this->dateDepartResa = $dateDepart ?? $debutFenetre->format('Y-m-d');
        $this->guideIdResa = $guideId ?? Guide::query()->orderBy('nom')->value('id');
        $this->clientIdResa = Client::query()->orderBy('nom')->value('id');
        $this->nbPersonnesSaisi = 1;
        $this->departImpose = $circuitId !== null && $dateDepart !== null;

        // Le depart peut deja exister sans qu'on soit parti de sa ligne — par
        // « Planifier » au catalogue, ou en choisissant une date deja servie.
        $this->alignerGuideSurLeDepart();
    }

    /**
     * Un DEPART A UN GUIDE : changer de circuit ou de date realigne le champ.
     *
     * Sans cela, l'ecran proposerait une liste libre et le service refuserait
     * a l'enregistrement (`tourisme.guide_du_depart_impose`), sur un
     * formulaire deja rempli. Le guide du depart se lit AVANT la saisie, il ne
     * se decouvre pas au refus.
     *
     * Prefixe `updated` : c'est un point d'entree du cadre Livewire, pas une
     * action d'ecriture — il ne persiste rien.
     */
    public function updatedCircuitIdResa(): void
    {
        $this->alignerGuideSurLeDepart();
    }

    public function updatedDateDepartResa(): void
    {
        $this->alignerGuideSurLeDepart();
    }

    /**
     * Enregistre la réservation par le SERVICE de domaine.
     *
     * Le service refuse dans trois cas : capacité cumulée dépassée (EF-M9-04),
     * guide déjà engagé sur un AUTRE circuit ce jour-là, ou guide différent de
     * celui qui conduit déjà le départ. Son message est affiché tel quel —
     * réécrire ici une seconde règle de capacité serait la duplication que ce
     * dépôt interdit.
     *
     * Le troisième cas ne devrait pas se produire depuis l'écran : le champ
     * « Guide » s'aligne sur le départ dès qu'il en a un
     * (`alignerGuideSurLeDepart()`). Le contrôle du service reste le seul qui
     * protège — l'alignement est un confort de saisie, pas une garantie.
     */
    public function enregistrerReservation(): void
    {
        $donnees = $this->validerEcriture([
            'circuitIdResa' => ['required', 'string', 'exists:circuits,id'],
            'dateDepartResa' => ['required', 'date'],
            'guideIdResa' => ['required', 'string', 'exists:guides,id'],
            'clientIdResa' => ['required', 'string', 'exists:clients,id'],
            'nbPersonnesSaisi' => ['required', 'integer', 'min:1'],
        ]);

        try {
            app(ReservationTourService::class)->reserver([
                'circuit_id' => $donnees['circuitIdResa'],
                'client_id' => $donnees['clientIdResa'],
                'guide_id' => $donnees['guideIdResa'],
                'date_circuit' => $donnees['dateDepartResa'],
                'nb_participants' => (int) $donnees['nbPersonnesSaisi'],
            ]);
        } catch (RuntimeException $e) {
            $this->addError('nbPersonnesSaisi', $e->getMessage());

            return;
        }

        // `exists:clients,id` vient de passer : la fiche existe.
        $client = Client::findOrFail($donnees['clientIdResa']);

        $this->terminerFormulaire(__('tourisme.pwa.reservation_faite', [
            'personnes' => (int) $donnees['nbPersonnesSaisi'],
            'client' => $client->nom,
        ]));
    }

    /**
     * Ouvre « Ajouter un guide touristique » au-dessus de la réservation.
     */
    public function ouvrirAjoutGuide(): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->etatFormulaire !== 'reservation') {
            abort(404);
        }

        $this->reset(['guideNomSaisi', 'guideCertificationSaisie', 'guideZoneSaisie', 'guideTarifSaisi']);
        $this->resetValidation();
        $this->ajoutGuideOuvert = true;
    }

    public function fermerAjoutGuide(): void
    {
        $this->ajoutGuideOuvert = false;
        $this->resetValidation();
    }

    /**
     * Écrit le guide par le service, puis le SÉLECTIONNE dans la réservation.
     */
    public function enregistrerGuide(): void
    {
        $donnees = $this->validerEcriture([
            'guideNomSaisi' => ['required', 'string', 'max:255'],
            'guideCertificationSaisie' => ['nullable', 'string', 'max:255'],
            'guideZoneSaisie' => ['nullable', 'string', 'max:255'],
            'guideTarifSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        try {
            $guide = app(ReservationTourService::class)->creerGuide([
                'nom' => $donnees['guideNomSaisi'],
                'certification' => ($donnees['guideCertificationSaisie'] ?? '') === '' ? null : $donnees['guideCertificationSaisie'],
                'zone_competence' => ($donnees['guideZoneSaisie'] ?? '') === '' ? null : $donnees['guideZoneSaisie'],
                'tarif_jour' => $donnees['guideTarifSaisi'],
            ]);
        } catch (\RuntimeException $e) {
            $this->addError('guideNomSaisi', $e->getMessage());

            return;
        }

        // Le guide d'un départ existant est IMPOSÉ : on ne le remplace pas.
        if ($this->guideDuDepart($this->circuitIdResa, $this->dateDepartResa) === null) {
            $this->guideIdResa = $guide->id;
        }

        $this->ajoutGuideOuvert = false;
        session()->flash('pwa-succes', __('tourisme.pwa.guide_cree', ['nom' => $guide->nom]));
    }

    // =====================================================================
    // Écritures — réaffectation du guide (UC-39)
    // =====================================================================

    public function ouvrirFormulaireGuide(string $circuitId, string $dateDepart): void
    {
        $this->ouvrirFormulaire('guide');

        $this->circuitIdGuide = $circuitId;
        $this->dateDepartGuide = $dateDepart;
        $this->nouveauGuideId = Guide::query()->orderBy('nom')->value('id');
    }

    /**
     * Réaffecte le guide de TOUTES les réservations du départ — en base.
     *
     * ⚠ `reservations_tour.guide_id` est NOT NULL (PA-51) : une prestation ne
     * peut pas exister sans guide, donc UC-39 est une RÉaffectation et le
     * champ ne peut jamais être vidé. Le service refuse une prestation annulée
     * ou clôturée, et vérifie que le remplaçant est libre ce jour-là.
     */
    public function enregistrerReaffectationGuide(): void
    {
        $donnees = $this->validerEcriture([
            'circuitIdGuide' => ['required', 'string', 'exists:circuits,id'],
            'dateDepartGuide' => ['required', 'date'],
            'nouveauGuideId' => ['required', 'string', 'exists:guides,id'],
        ]);

        $service = app(ReservationTourService::class);

        $reservations = ReservationTour::query()
            ->where('circuit_id', $donnees['circuitIdGuide'])
            ->whereDate('date_circuit', $donnees['dateDepartGuide'])
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->get();

        if ($reservations->isEmpty()) {
            $this->addError('nouveauGuideId', __('tourisme.pwa.depart_sans_reservation'));

            return;
        }

        try {
            DB::transaction(function () use ($reservations, $service, $donnees): void {
                foreach ($reservations as $reservation) {
                    $service->affecterGuide($reservation, $donnees['nouveauGuideId']);
                }
            });
        } catch (RuntimeException $e) {
            $this->addError('nouveauGuideId', $e->getMessage());

            return;
        }

        $this->terminerFormulaire(__('tourisme.pwa.guide_reaffecte', [
            'nombre' => $reservations->count(),
        ]));
    }

    // =====================================================================
    // Écritures — catalogue des prestations
    // =====================================================================

    public function ouvrirFormulairePrestation(?string $circuitId = null): void
    {
        $this->ouvrirFormulaire('prestation');

        $circuit = $circuitId === null ? null : Circuit::find($circuitId);

        if ($circuit === null) {
            $this->circuitThemeSaisi = $this->themesDuCatalogue()[0] ?? '';

            return;
        }

        $this->circuitIdEdite = $circuit->id;
        $this->circuitNomSaisi = $circuit->nom;
        $this->circuitThemeSaisi = $circuit->theme;
        $this->circuitZoneSaisie = $circuit->zone;
        $this->circuitDureeSaisie = $circuit->duree;
        $this->circuitPrixSaisi = (string) $circuit->prix;
        $this->circuitCapaciteSaisie = $circuit->capacite_max;
    }

    public function enregistrerPrestation(): void
    {
        $donnees = $this->validerEcriture([
            'circuitNomSaisi' => ['required', 'string', 'max:255'],
            // Le thème est une ÉNUMÉRATION en base : offrir un texte libre
            // ferait tomber le refus à l'enregistrement, sur un formulaire
            // déjà rempli.
            'circuitThemeSaisi' => ['required', 'string', 'in:'.implode(',', $this->themesDuCatalogue())],
            'circuitZoneSaisie' => ['required', 'string', 'max:255'],
            'circuitDureeSaisie' => ['required', 'string', 'max:255'],
            'circuitPrixSaisi' => ['required', 'numeric', 'min:0'],
            'circuitCapaciteSaisie' => ['required', 'integer', 'min:1', 'max:999'],
        ]);

        $attributs = [
            'nom' => $donnees['circuitNomSaisi'],
            'theme' => $donnees['circuitThemeSaisi'],
            'zone' => $donnees['circuitZoneSaisie'],
            'duree' => $donnees['circuitDureeSaisie'],
            'prix' => $donnees['circuitPrixSaisi'],
            'capacite_max' => $donnees['circuitCapaciteSaisie'],
        ];

        if ($this->circuitIdEdite === null) {
            Circuit::create($attributs);
        } else {
            Circuit::findOrFail($this->circuitIdEdite)->update($attributs);
        }

        $this->terminerFormulaire(__('tourisme.pwa.circuit_enregistre', [
            'nom' => $donnees['circuitNomSaisi'],
        ]));
    }

    // =====================================================================
    // Archivage — trois états, aucune suppression
    // =====================================================================

    public function confirmerArchivage(string $type, string $id, ?string $dateDepart = null): void
    {
        $this->ouvrirFormulaire('archivage');

        if (! in_array($type, self::TYPES_ARCHIVABLES, true)) {
            abort(404);
        }

        $this->typeElementSupprime = $type;
        $this->idElementSupprime = $id;
        $this->dateElementSupprime = $dateDepart;

        if ($type === 'reservation') {
            $reservation = ReservationTour::with(['client', 'circuit'])->findOrFail($id);
            $this->libelleElementSupprime = __('tourisme.pwa.verrou_reservation', [
                'client' => $reservation->client->nom,
                'personnes' => $reservation->nb_participants,
                'date' => $reservation->date_circuit->format('d/m/Y'),
            ]);
            $this->placesConcernees = $reservation->nb_participants;
            // Une prestation clôturée ne s'annule plus : le service le refuse,
            // et le bouton est masqué plutôt que laissé inerte.
            $this->verrousArchivage = $reservation->estTerminee()
                ? [__('tourisme.annulation_apres_cloture')]
                : [];
        } else {
            $circuit = Circuit::findOrFail($id);
            $reservations = $this->reservationsDuDepart($id, (string) $dateDepart);
            $this->libelleElementSupprime = $circuit->nom
                .' — '.CarbonImmutable::parse((string) $dateDepart)->format('d/m/Y');
            $this->placesConcernees = (int) $reservations->sum('nb_participants');
            $this->verrousArchivage = $reservations->isEmpty()
                ? [__('tourisme.pwa.depart_sans_reservation')]
                : [];
        }

        $this->archivageBloque = $this->verrousArchivage !== [];
    }

    /**
     * Exécute l'annulation — ASCII pur dans le nom, le dispatch Livewire ne
     * survit pas à un accent (V8, vague précédente).
     *
     * Aucun `delete()` : `ReservationTourService::annuler()` passe le statut à
     * `annulee`, ce qui libère aussitôt la place au départ (RG-02 en M1).
     */
    public function executerSuppression(): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->idElementSupprime === null || $this->archivageBloque) {
            abort(403);
        }

        $service = app(ReservationTourService::class);

        try {
            if ($this->typeElementSupprime === 'reservation') {
                $service->annuler(ReservationTour::findOrFail($this->idElementSupprime));
                $message = __('tourisme.pwa.reservation_annulee_faite');
            } elseif ($this->typeElementSupprime === 'depart') {
                $reservations = $this->reservationsDuDepart(
                    $this->idElementSupprime,
                    (string) $this->dateElementSupprime,
                );

                DB::transaction(function () use ($reservations, $service): void {
                    foreach ($reservations as $reservation) {
                        $service->annuler($reservation);
                    }
                });

                $message = __('tourisme.pwa.depart_annule_faite', ['nombre' => $reservations->count()]);
            } else {
                abort(404);
            }
        } catch (RuntimeException $e) {
            $this->addError('idElementSupprime', $e->getMessage());

            return;
        }

        $this->terminerFormulaire($message);
    }

    // =====================================================================
    // Export — PA-119
    // =====================================================================

    /**
     * @return \Symfony\Component\HttpFoundation\StreamedResponse|\Symfony\Component\HttpFoundation\BinaryFileResponse|null
     */
    public function genererExport()
    {
        $onglet = $this->ongletValide();
        $lignes = $this->lignesExportables($onglet);

        if ($lignes === []) {
            $this->addError('formatExport', __('tourisme.pwa.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new TourismeExport($onglet, $lignes, $this->descriptionDuFiltre()),
                'tourisme_'.$onglet.'_'.now()->format('Ymd_His').'.xlsx',
            );
        }

        $utilisateur = auth()->user();

        $titre = match ($onglet) {
            'reservations' => __('tourisme.pwa.onglet_reservations'),
            'catalogue' => __('tourisme.pwa.onglet_catalogue'),
            default => __('tourisme.pwa.onglet_departs'),
        };

        $pdf = Pdf::loadView('pdf.tourisme', [
            'entete' => $this->enTeteRapport($titre, $this->descriptionDuFiltre()),
            'titreDocument' => $titre,
            'entetes' => TourismeExport::entetesDe($onglet),
            'lignes' => $lignes,
            'filtre' => $this->descriptionDuFiltre(),
            'auteur' => $utilisateur instanceof User ? $utilisateur->login : null,
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'tourisme_'.$onglet.'_'.now()->format('Ymd_His').'.pdf',
        );
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->ajoutGuideOuvert = false;
        $this->resetValidation();
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    public function render(): View
    {
        [$debut, $fin] = $this->fenetre();

        $catalogue = $this->catalogueFiltre();
        $reservations = $this->reservationsDeLaFenetre();
        $departs = $this->departsDerives($reservations);
        $departsAffiches = $this->departsFiltres($departs);
        $reservationsAffichees = $this->reservationsAffichees($reservations);

        // La formule des agrégats vit dans `ReservationTourService` depuis le
        // 02/09/2026 : la carte « Tourisme & circuits » de l'accueil lit la
        // même — deux formules divergeraient (PA-121).
        $agregats = ReservationTourService::agregerDeparts($departsAffiches);

        return view('pwa.tourisme.departs', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'departs' => $departsAffiches,
            'reservations' => $reservationsAffichees,
            'catalogue' => $catalogue,
            'catalogueComplet' => Circuit::query()->orderBy('nom')->get(),
            'departsParCircuit' => $this->departsParCircuit($reservations),
            'guides' => Guide::query()->orderBy('nom')->get(),
            'clients' => Client::query()->orderBy('nom')->get(['id', 'nom', 'prenom', 'telephone']),
            'themes' => $this->themesDuCatalogue(),
            'placesRestantesResa' => $this->placesRestantesDuFormulaire(),
            'capaciteResa' => $this->capaciteDuFormulaire(),
            'guideActuel' => $this->guideActuelDuDepart(),
            'guideImpose' => $this->guideDuDepart($this->circuitIdResa, $this->dateDepartResa),
            'totalDeparts' => $agregats['departs'],
            'completsCount' => $agregats['complets'],
            'totalPlacesVendues' => $agregats['places_vendues'],
            'totalCapaciteOfferte' => $agregats['capacite_offerte'],
            'tauxRemplissage' => $agregats['taux_remplissage'],
            'chiffreAffairesTotal' => $agregats['chiffre_affaires'],
            'dureeIndetermineeCount' => $catalogue->filter(
                fn (Circuit $c): bool => $this->dureeIndeterminee($c->duree),
            )->count(),
            'fenetreDebut' => $debut,
            'fenetreFin' => $fin,
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
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'departs';
    }

    /**
     * @return array{0: CarbonImmutable, 1: CarbonImmutable}
     */
    private function fenetre(): array
    {
        $aujourdhui = CarbonImmutable::today();

        $debut = $this->dateOuNull($this->debut) ?? $aujourdhui;
        $fin = $this->dateOuNull($this->fin) ?? $debut->addDays(self::JOURS_PAR_DEFAUT);

        if ($fin->lessThan($debut)) {
            $fin = $debut->addDays(self::JOURS_PAR_DEFAUT);
        }

        return [$debut, $fin];
    }

    private function dateOuNull(string $valeur): ?CarbonImmutable
    {
        if ($valeur === '' || preg_match('/^\d{4}-\d{2}-\d{2}$/', $valeur) !== 1) {
            return null;
        }

        [$a, $m, $j] = array_map('intval', explode('-', $valeur));

        return checkdate($m, $j, $a) ? CarbonImmutable::create($a, $m, $j)->startOfDay() : null;
    }

    /**
     * Les thèmes offerts — l'ÉNUMÉRATION de `circuits.theme`, lue en base.
     *
     * @return list<string>
     */
    private function themesDuCatalogue(): array
    {
        $type = DB::selectOne(
            'SELECT COLUMN_TYPE AS type FROM information_schema.COLUMNS '
            .'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            ['circuits', 'theme'],
        );

        if ($type === null || preg_match_all("/'([^']+)'/", (string) $type->type, $trouves) === 0) {
            return [];
        }

        return $trouves[1];
    }

    /**
     * @return CollectionEloquent<int, Circuit>
     */
    private function catalogueFiltre(): CollectionEloquent
    {
        $terme = trim($this->recherche);

        return Circuit::query()
            ->when($terme !== '', function ($q) use ($terme) {
                $q->where(function ($sous) use ($terme) {
                    $sous->where('nom', 'like', '%'.$terme.'%')
                        ->orWhere('zone', 'like', '%'.$terme.'%');
                });
            })
            ->orderBy('nom')
            ->get();
    }

    /**
     * Les réservations de la fenêtre — `with()` pour qu'aucune ligne ne
     * rouvre une requête par relation.
     *
     * @return CollectionEloquent<int, ReservationTour>
     */
    private function reservationsDeLaFenetre(): CollectionEloquent
    {
        [$debut, $fin] = $this->fenetre();

        // La requête vit dans le Service depuis le 02/09/2026 : la carte
        // « Tourisme & circuits » de l'accueil lit la même population.
        return app(ReservationTourService::class)->reservationsSurFenetre($debut, $fin);
    }

    /**
     * Les départs, DÉRIVÉS des réservations : (circuit, date) + guide.
     *
     * @param  CollectionEloquent<int, ReservationTour>  $reservations
     * @return list<array<string, mixed>>
     */
    private function departsDerives(CollectionEloquent $reservations): array
    {
        // La dérivation vit dans `ReservationTourService` depuis le
        // 02/09/2026 : la carte « Tourisme & circuits » de l'accueil dérive
        // les mêmes départs — deux dérivations divergeraient (PA-121).
        return app(ReservationTourService::class)->departsDerives($reservations);
    }

    /**
     * @param  list<array<string, mixed>>  $departs
     * @return list<array<string, mixed>>
     */
    private function departsFiltres(array $departs): array
    {
        $terme = mb_strtolower(trim($this->recherche));

        return array_values(array_filter($departs, function (array $depart) use ($terme): bool {
            if ($this->prestationId !== '' && $depart['circuit_id'] !== $this->prestationId) {
                return false;
            }

            if ($this->statut === 'planifie' && $depart['annule']) {
                return false;
            }

            if ($this->statut === 'annule' && ! $depart['annule']) {
                return false;
            }

            if ($this->remplissage === 'complet' && $depart['places_restantes'] > 0) {
                return false;
            }

            if ($this->remplissage === 'disponible' && $depart['places_restantes'] <= 0) {
                return false;
            }

            if ($this->remplissage === 'vide' && $depart['places_vendues'] > 0) {
                return false;
            }

            if ($terme !== '' && ! str_contains(
                mb_strtolower($depart['circuit_nom'].' '.(string) $depart['guide']),
                $terme,
            )) {
                return false;
            }

            return true;
        }));
    }

    /**
     * @param  CollectionEloquent<int, ReservationTour>  $reservations
     * @return Collection<int, ReservationTour>
     */
    private function reservationsAffichees(CollectionEloquent $reservations): Collection
    {
        $terme = mb_strtolower(trim($this->recherche));

        return $reservations
            ->filter(function (ReservationTour $r): bool {
                if ($this->prestationId !== '' && $r->circuit_id !== $this->prestationId) {
                    return false;
                }

                if ($this->statut === 'planifie') {
                    return ! $r->estAnnulee();
                }

                if ($this->statut === 'annule') {
                    return $r->estAnnulee();
                }

                return true;
            })
            ->when($terme !== '', fn (Collection $c) => $c->filter(
                static fn (ReservationTour $r): bool => str_contains(
                    mb_strtolower($r->client->nom.' '.$r->circuit->nom),
                    $terme,
                ),
            ))
            ->values();
    }

    /**
     * Le nombre de départs planifiés par circuit — colonne du maître.
     *
     * @param  CollectionEloquent<int, ReservationTour>  $reservations
     * @return array<string, int>
     */
    private function departsParCircuit(CollectionEloquent $reservations): array
    {
        $compte = [];

        foreach ($reservations as $reservation) {
            if ($reservation->estAnnulee()) {
                continue;
            }

            $compte[$reservation->circuit_id][$reservation->date_circuit->format('Y-m-d')] = true;
        }

        return array_map('count', $compte);
    }

    /**
     * `circuits.duree` est un `varchar` libre : « Plusieurs jours » n'est pas
     * une durée exploitable (PA-51). On ne DEVINE pas une durée, on signale.
     */
    private function dureeIndeterminee(?string $duree): bool
    {
        // La règle vit dans le Service depuis le 02/09/2026 (PA-121).
        return app(ReservationTourService::class)->dureeIndeterminee($duree);
    }

    /**
     * @return CollectionEloquent<int, ReservationTour>
     */
    private function reservationsDuDepart(string $circuitId, string $date): CollectionEloquent
    {
        return ReservationTour::query()
            ->where('circuit_id', $circuitId)
            ->whereDate('date_circuit', $date)
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->get();
    }

    /**
     * Les places restantes du départ visé par le formulaire — CALCULÉES PAR
     * LE SERVICE, jamais une valeur d'échappement (le lot précédent posait 99).
     */
    private function placesRestantesDuFormulaire(): ?int
    {
        if ($this->circuitIdResa === null || $this->dateDepartResa === '') {
            return null;
        }

        $circuit = Circuit::find($this->circuitIdResa);

        if ($circuit === null) {
            return null;
        }

        return app(ReservationTourService::class)->placesRestantes($circuit, $this->dateDepartResa);
    }

    private function capaciteDuFormulaire(): ?int
    {
        if ($this->circuitIdResa === null) {
            return null;
        }

        return Circuit::find($this->circuitIdResa)?->capacite_max;
    }

    /**
     * Le guide DEJA EN PLACE sur un depart, ou `null` si le depart n'existe
     * pas encore.
     *
     * Une seule implementation, partagee par la modale de reservation et
     * celle de reaffectation : deux lectures de la meme regle finiraient par
     * diverger, et c'est la copie affichee qui tromperait l'operateur.
     */
    private function guideDuDepart(?string $circuitId, ?string $date): ?Guide
    {
        if ($circuitId === null || $date === null || $date === '') {
            return null;
        }

        return $this->reservationsDuDepart($circuitId, $date)->first()?->guide;
    }

    /**
     * Aligne le guide saisi sur celui du depart vise, quand il en a un.
     */
    private function alignerGuideSurLeDepart(): void
    {
        $enPlace = $this->guideDuDepart($this->circuitIdResa, $this->dateDepartResa);

        if ($enPlace !== null) {
            $this->guideIdResa = $enPlace->id;
        }
    }

    private function guideActuelDuDepart(): ?string
    {
        return $this->guideDuDepart($this->circuitIdGuide, $this->dateDepartGuide)?->nom;
    }

    /**
     * Les lignes RÉELLEMENT AFFICHÉES de l'onglet — PA-119.
     *
     * @return list<array<int, string>>
     */
    private function lignesExportables(string $onglet): array
    {
        if ($onglet === 'catalogue') {
            $reservations = $this->reservationsDeLaFenetre();
            $departs = $this->departsParCircuit($reservations);

            return $this->catalogueFiltre()->map(fn (Circuit $c): array => [
                $c->nom,
                __('tourisme.pwa.type_valeur_circuit'),
                $c->duree,
                $c->zone.' · '.$c->theme,
                (string) $c->prix,
                // « Indicatif € » : aucune colonne au schéma (refus_indicatif_eur).
                MontantFcfa::TIRET,
                (string) ($departs[$c->id] ?? 0),
            ])->values()->all();
        }

        if ($onglet === 'reservations') {
            return $this->reservationsAffichees($this->reservationsDeLaFenetre())
                ->map(fn (ReservationTour $r): array => [
                    // « N° » : aucune colonne `numero` (refus_numero).
                    MontantFcfa::TIRET,
                    $r->client->nom,
                    $r->circuit->nom,
                    $r->date_circuit->format('d/m/Y'),
                    (string) $r->nb_participants,
                    (string) $r->circuit->prix,
                    $r->montant(),
                    // « Acompte » et « Reste dû » : aucune colonne (refus_acompte).
                    MontantFcfa::TIRET,
                    MontantFcfa::TIRET,
                ])->values()->all();
        }

        $departs = $this->departsFiltres($this->departsDerives($this->reservationsDeLaFenetre()));

        return array_map(static fn (array $d): array => [
            MontantFcfa::TIRET,
            $d['circuit_nom'],
            CarbonImmutable::parse($d['date'])->format('d/m/Y'),
            (string) ($d['guide'] ?? MontantFcfa::TIRET),
            // « Véhicule » : aucune colonne (refus_vehicule).
            MontantFcfa::TIRET,
            $d['places_vendues'].'/'.$d['capacite'],
            $d['prix_unitaire'],
            $d['chiffre_affaires'],
            $d['annule'] ? __('tourisme.pwa.depart_annule') : __('tourisme.pwa.statut_planifie'),
        ], $departs);
    }

    private function descriptionDuFiltre(): string
    {
        [$debut, $fin] = $this->fenetre();

        $morceaux = [
            __('tourisme.pwa.du').' '.$debut->format('d/m/Y').' '
                .__('tourisme.pwa.au').' '.$fin->format('d/m/Y'),
        ];

        if ($this->statut !== '') {
            $morceaux[] = $this->statut === 'annule'
                ? __('tourisme.pwa.statut_annule')
                : __('tourisme.pwa.statut_planifie');
        }

        if (trim($this->recherche) !== '') {
            $morceaux[] = __('tourisme.pwa.recherche').' '.trim($this->recherche);
        }

        return implode(' · ', $morceaux);
    }
}
