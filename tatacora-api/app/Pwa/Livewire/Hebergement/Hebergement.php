<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Http\Requests\EnregistrerCategorieHebergementRequest;
use App\Domain\Hebergement\Http\Requests\EnregistrerUniteHebergementRequest;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Hebergement\Services\SejourService;
use App\Exports\HebergementExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\ReglesDeLApi;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Collection;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Plan d'Hébergement, Réservations en cours et Calendrier d'Occupation (M1).
 *
 * Maître : `prototype_v2/pages/m1-hebergement.html` — trois onglets, un rendu
 * en cartes, le cycle opérationnel de l'unité sur le bouton de chaque carte.
 *
 * ## LES DEUX SOURCES, ET LA QUESTION A LAQUELLE CHACUNE REPOND
 *
 * L'arbitrage fait foi en tête de `SejourService` ; cet écran s'y conforme, et
 * la confusion qu'il interdit est exactement celle que RG-02 condamne :
 *
 * | Ce que l'écran affiche | D'où il le tire |
 * |---|---|
 * | la PASTILLE d'une carte (Libre / Réservée / Occupée / Nettoyage / Hors service) | les réservations actives du jour + le séjour en cours + `statut` pour les seuls états d'exploitation (nettoyage, hors service) |
 * | le BOUTON d'action | le même état dérivé — jamais un statut lu seul |
 * | le calendrier d'occupation | les réservations actives, bornes semi-ouvertes |
 *
 * `unites_hebergement.statut` n'est JAMAIS lu pour répondre à « cette chambre
 * est-elle libre ? » : il ne connaît ni date ni période, et une réservation
 * future le laisserait à `libre` (PA-118, PA-126). Il n'est lu que pour les
 * deux états qu'il est seul à porter — `nettoyage` et `hors_service` —, et il
 * n'est écrit que par `SejourService` (check-in, check-out, ménage) et par
 * l'archivage du parc ci-dessous.
 *
 * ## RG-01 N'EST PAS RÉÉCRITE ICI, ELLE EST APPELÉE
 *
 * La réservation rapide passe par `ReservationService`, donc par
 * `VerificationChevauchementService` : verrou pessimiste sur l'unité,
 * transaction, bornes semi-ouvertes. La version précédente refaisait le test
 * en Eloquent, hors transaction et sans `lockForUpdate()`, avec un
 * `whereBetween` — deux réceptionnistes passaient tous deux le contrôle, et
 * une arrivée le jour même d'un départ était refusée, ce qui bloquait une
 * nuit à chaque rotation.
 *
 * @see EF-M1-01 Consultation des disponibilités
 * @see EF-M1-02 Création de réservation
 * @see EF-M1-03 Check-in / EF-M1-04 Check-out
 * @see EF-M1-07 Planning d'occupation
 * @see RG-01 Prévention des doubles réservations
 * @see RG-02 Disponibilité toujours calculée
 */
#[Layout('layouts.pwa')]
#[Title('Hébergement & Réservations — TATACORA AFRIQUE')]
final class Hebergement extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — jamais un littéral dans les appels. */
    public const MODULE = 'M1';

    public const ONGLETS = ['plan', 'reservations', 'calendrier', 'disponibilites'];

    /**
     * Les cinq états du jour d'une unité, avec les couleurs du maître
     * (`m1-hebergement.html` l.157-163). Ce ne sont PAS les valeurs de
     * `unites_hebergement.statut` : ce sont les états DÉRIVÉS que l'écran
     * affiche, dont deux seulement coïncident avec la colonne.
     *
     * @var array<string, array{bg: string, txt: string}>
     */
    public const COULEURS_STATUT = [
        'libre' => ['bg' => '#E8F5E9', 'txt' => '#2E7D32'],
        'occupee' => ['bg' => '#FDECEC', 'txt' => '#C62828'],
        'reservee' => ['bg' => '#FDF3E0', 'txt' => '#B8891E'],
        'nettoyage' => ['bg' => '#E8EEFD', 'txt' => '#1D4ED8'],
        'hors_service' => ['bg' => '#F3F4F6', 'txt' => '#6B7280'],
    ];

    #[Url(as: 'onglet')]
    public string $onglet = 'plan';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'categorie')]
    public string $categorie = '';

    /**
     * 10 lignes par page pour l'onglet « Réservations en cours » — la valeur
     * du moteur du maître (`crud-engine.js` l.21).
     */
    public const PAR_PAGE_RESERVATIONS = 10;

    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /** Créer la CATÉGORIE depuis la modale d'unité — le modèle du Product
     * Owner (01/09/2026) : « chaque hébergement a sa catégorie et libellé »,
     * et les catégories sans tarif au catalogue (Chambre simple, Suite…) ne
     * se seedent pas : elles naissent ici, avec le tarif réel saisi. */
    public bool $uniteNouvelleCategorie = false;

    public string $categorieLibelle = '';

    public string $categorieTarif = '';

    public string $categorieCapacite = '';

    /**
     * La pagination de la grille du parc — maître, `crud-engine.js`
     * l.21/151-154 (10 lignes par page).
     *
     * Non liée à l'URL, comme au maître : `pageActuelle` y est une variable
     * JS en mémoire, remise à 1 à chaque chargement de page.
     *
     * ⚠ Elle n'est PAS remise à 1 par un crochet `updatedRecherche()` /
     * `updatedCategorie()` comme le fait le maître (l.90, l.106) : sous ce
     * lot, ajouter un crochet Livewire est une méthode PUBLIQUE de plus, donc
     * une entrée de plus dans la liste fermée de `PwaActionsReluesTest` —
     * hors périmètre de cette campagne, qui ne touche aucun fichier de test.
     * `render()` CLAMPE `$page` à la dernière page valide à chaque affichage
     * ({@see parcPagine()}) : un filtre qui réduit le résultat sous la page
     * courante ne peut donc jamais rendre une grille vide sans raison — la
     * différence avec le maître est un unique clic de « Précédent » en moins
     * d'automatisme, jamais une page blanche.
     */
    public int $page = 1;

    /** Lignes par page — maître, `crud-engine.js` l.21 (`lignesParPage = 10`). */
    private const PAR_PAGE = 10;

    // ---- Onglet « Disponibilités » (PO 08/10/2026) -----------------------
    // Lecture seule : deux dates, aucune ecriture. Le calcul est celui de
    // `DisponibiliteService` (RG-02) - jamais `unites_hebergement.statut`.
    #[Url(as: 'du')]
    public string $dispoArrivee = '';

    #[Url(as: 'au')]
    public string $dispoDepart = '';

    // ---- Formulaire « Réservation rapide » -----------------------------
    public ?string $rrUniteId = null;

    public ?string $rrClientId = null;

    public string $rrDateArrivee = '';

    public string $rrDateDepart = '';

    // ---- Formulaire « Ajouter / Modifier un hébergement » ---------------
    public ?string $uniteId = null;

    public string $uniteNumero = '';

    public ?string $uniteCategorieId = null;

    // ---- Archivage -----------------------------------------------------
    public ?string $uniteAArchiver = null;

    // ---- Export --------------------------------------------------------
    public string $formatExport = 'pdf';

    /**
     * Le registre FERMÉ des formulaires de l'écran (motif `FormulaireModal`).
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'reservation-rapide' => ['rrUniteId', 'rrClientId', 'rrDateArrivee', 'rrDateDepart'],
            'unite' => [
                'uniteId', 'uniteNumero', 'uniteCategorieId',
                'uniteNouvelleCategorie', 'categorieLibelle', 'categorieTarif', 'categorieCapacite',
            ],
            'archivage' => ['uniteAArchiver'],
        ];
    }

    // =====================================================================
    // Cycle opérationnel — les trois gestes du maître, tous délégués au
    // Service de domaine qui en est l'unique point d'entrée.
    // =====================================================================

    /**
     * EF-M1-03 — l'arrivée réelle du client.
     *
     * La réservation est celle qui couvre AUJOURD'HUI : faire entrer un client
     * trois jours avant son arrivée marquerait occupée une chambre encore
     * vendable (maître, l.228-229).
     */
    public function effectuerCheckIn(string $uniteId, SejourService $sejours): void
    {
        $this->exigerEcriture(self::MODULE);

        $unite = UniteHebergement::findOrFail($uniteId);
        $reservation = $this->reservationDuJour($uniteId);

        if ($reservation === null) {
            $this->addError('cycle', __('hebergement_pwa.hebergement.checkin_impossible', [
                'numero' => $unite->numero,
            ]));

            return;
        }

        try {
            $sejours->checkin($reservation);
        } catch (RuntimeException $refus) {
            $this->addError('cycle', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('hebergement_pwa.hebergement.checkin_fait', [
            'client' => $reservation->client->nomComplet(),
            'numero' => $unite->numero,
        ]));
    }

    /**
     * EF-M1-04 — le départ réel. L'unité passe en nettoyage, jamais en libre :
     * elle n'est pas prête à recevoir tant que le ménage n'est pas fait.
     */
    public function effectuerCheckOut(string $uniteId, SejourService $sejours): void
    {
        $this->exigerEcriture(self::MODULE);

        $unite = UniteHebergement::findOrFail($uniteId);
        $sejour = $sejours->sejourEnCours($unite);

        if ($sejour === null) {
            $this->addError('cycle', __('hebergement_pwa.hebergement.checkout_impossible', [
                'numero' => $unite->numero,
            ]));

            return;
        }

        try {
            $sejours->checkout($sejour);
        } catch (RuntimeException $refus) {
            $this->addError('cycle', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('hebergement_pwa.hebergement.checkout_fait', [
            'numero' => $unite->numero,
        ]));
    }

    /**
     * Troisième geste du cycle — sans lui, toute unité libérée resterait en
     * nettoyage indéfiniment, et le cycle s'arrêterait à son avant-dernier
     * état.
     */
    public function marquerNettoye(string $uniteId, SejourService $sejours): void
    {
        $this->exigerEcriture(self::MODULE);

        $unite = UniteHebergement::findOrFail($uniteId);

        try {
            $sejours->marquerNettoyee($unite);
        } catch (RuntimeException $refus) {
            $this->addError('cycle', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('hebergement_pwa.hebergement.nettoyee', [
            'numero' => $unite->numero,
        ]));
    }

    // =====================================================================
    // Réservation rapide — le comptoir, l'unité sous les yeux
    // =====================================================================

    public function ouvrirReservationRapide(string $uniteId, ?string $arrivee = null, ?string $depart = null): void
    {
        // `ouvrirFormulaire` exige le droit AVANT toute lecture : rien n'est
        // affecté si le rôle est refusé.
        $this->ouvrirFormulaire('reservation-rapide');

        $aujourdhui = CarbonImmutable::today();

        $this->rrUniteId = UniteHebergement::findOrFail($uniteId)->id;
        $this->rrDateArrivee = $aujourdhui->toDateString();
        $this->rrDateDepart = $aujourdhui->addDay()->toDateString();

        // Depuis l'onglet « Disponibilites » : la periode CHERCHEE devient la
        // periode reservee. La valeur est reverifiee a l'enregistrement
        // (`date`, `after`) puis par RG-01 : une date forgee ne contourne rien.
        if ($arrivee !== null && $depart !== null
            && strtotime($arrivee) !== false && strtotime($depart) !== false
            && $depart > $arrivee) {
            $this->rrDateArrivee = CarbonImmutable::parse($arrivee)->toDateString();
            $this->rrDateDepart = CarbonImmutable::parse($depart)->toDateString();
        }
    }

    /**
     * RG-01 — la garantie est celle du Service, sous verrou pessimiste.
     *
     * Le client est une VRAIE clé étrangère choisie dans le référentiel : ni
     * nom tapé au clavier, ni téléphone fabriqué. La version précédente
     * inscrivait `'0100000000'` sur une fiche client réelle — le numéro qu'on
     * appellerait pour confirmer — et rapprochait deux homonymes sur le seul
     * nom, fusionnant deux personnes en une fiche et un solde.
     */
    public function enregistrerReservationRapide(ReservationService $reservations): void
    {
        $donnees = $this->validerEcriture([
            'rrUniteId' => ['required', 'uuid', 'exists:unites_hebergement,id'],
            'rrClientId' => ['required', 'uuid', 'exists:clients,id'],
            'rrDateArrivee' => ['required', 'date'],
            'rrDateDepart' => ['required', 'date', 'after:rrDateArrivee'],
        ]);

        try {
            $reservation = $reservations->creer([
                'client_id' => $donnees['rrClientId'],
                'unite_id' => $donnees['rrUniteId'],
                'date_arrivee' => $donnees['rrDateArrivee'],
                'date_depart' => $donnees['rrDateDepart'],
            ]);
        } catch (ChevauchementDetecteException $conflit) {
            // La modale RESTE ouverte : fermer sur un refus ferait perdre la
            // saisie et retaper les dates.
            $this->addError('rrUniteId', $conflit->getMessage());

            return;
        }

        $this->terminerFormulaire(__('hebergement_pwa.hebergement.reservation_creee', [
            'client' => $reservation->client?->nomComplet() ?? '',
            'nuits' => $reservation->nombreNuitees(),
            'numero' => $reservation->unite->numero,
        ]));
    }

    // =====================================================================
    // Le parc — ajout, modification, archivage
    // =====================================================================

    public function ouvrirFormulaireUnite(?string $uniteId = null): void
    {
        $this->ouvrirFormulaire('unite');

        if ($uniteId === null) {
            return;
        }

        $unite = UniteHebergement::findOrFail($uniteId);

        $this->uniteId = $unite->id;
        $this->uniteNumero = $unite->numero;
        $this->uniteCategorieId = $unite->categorie_id;
    }

    /**
     * ⚠ `statut` n'est PAS saisi : le cycle opérationnel appartient à
     * `SejourService`, et une unité créée entre au parc `libre` — c'est aussi
     * le défaut du schéma. Le laisser choisir ferait dire à l'écran qu'une
     * chambre est occupée sans que personne y dorme.
     */
    public function enregistrerUnite(): void
    {
        // Les règles sont celles des requêtes du domaine depuis le 15/10/2026
        // (lot S2 : la synchronisation crée aussi catégories et unités) —
        // une seule liste, lue ici par `ReglesDeLApi`.
        $regleUnite = ReglesDeLApi::pourCreation(EnregistrerUniteHebergementRequest::class, [
            'numero' => 'uniteNumero',
            'categorie_id' => 'uniteCategorieId',
        ]);

        // La catégorie naît AVEC son tarif réel et sa capacité — jamais un
        // zéro d'attente qui se lirait comme une nuit gratuite.
        $reglesCategorie = $this->uniteNouvelleCategorie
            ? ReglesDeLApi::pourCreation(EnregistrerCategorieHebergementRequest::class, [
                'libelle' => 'categorieLibelle',
                'tarif_base' => 'categorieTarif',
                'capacite_max' => 'categorieCapacite',
            ])
            : ['categorieLibelle' => ['nullable'], 'categorieTarif' => ['nullable'], 'categorieCapacite' => ['nullable']];

        $donnees = $this->validerEcriture([
            'uniteNumero' => $regleUnite['uniteNumero'],
            'uniteCategorieId' => $this->uniteNouvelleCategorie ? ['nullable'] : $regleUnite['uniteCategorieId'],
            ...$reglesCategorie,
        ]);

        $parc = app(ParcHebergementService::class);

        if ($this->uniteNouvelleCategorie) {
            $donnees['uniteCategorieId'] = $parc->creerCategorie([
                'libelle' => (string) $donnees['categorieLibelle'],
                'tarif_base' => (string) $donnees['categorieTarif'],
                'capacite_max' => (int) $donnees['categorieCapacite'],
            ])->id;
        }

        if ($this->uniteId !== null) {
            $parc->modifierUnite(UniteHebergement::findOrFail($this->uniteId), [
                'numero' => $donnees['uniteNumero'],
                'categorie_id' => $donnees['uniteCategorieId'],
            ]);
        } else {
            $parc->creerUnite([
                'numero' => $donnees['uniteNumero'],
                'categorie_id' => $donnees['uniteCategorieId'],
            ]);
        }

        $this->terminerFormulaire(__('hebergement_pwa.hebergement.unite_enregistree', [
            'numero' => $donnees['uniteNumero'],
        ]));
    }

    public function confirmerArchivageUnite(string $uniteId): void
    {
        // Bascule « Suppression d'un enregistrement » (écran Paramètres,
        // 02/09/2026 — `OptionsSystemeService`, fermée par défaut comme au
        // maître) : l'archivage est LE geste « supprimer = archiver » de la
        // PWA, et le maître le retire de l'écran tant qu'un Administrateur ne
        // l'a pas ouvert. Le bouton n'est pas rendu quand elle est fermée
        // (retiré, pas grisé — Article 3.3) ; ce recontrôle ferme le chemin
        // du bouton falsifié, et celui d'une bascule refermée entre le rendu
        // et le clic.
        $this->exigerSuppressionOuverte();

        $this->ouvrirFormulaire('archivage');

        $this->uniteAArchiver = UniteHebergement::findOrFail($uniteId)->id;
    }

    /**
     * ARCHIVER, JAMAIS SUPPRIMER — et le mot compte autant que le geste.
     *
     * `BasePolicy::delete()` rend `false` pour les 20 policies : la version
     * précédente appelait pourtant `$u->delete()` sur une unité d'hébergement,
     * ce qui aurait rendu illisibles toutes les réservations qui la citent.
     *
     * ## Pourquoi `hors_service` EST l'archive de ce schéma
     *
     * Aucune table d'archives n'existe côté serveur pour le parc, et aucune
     * migration n'est ouverte ici. `hors_service` est le seul état qui retire
     * l'unité de ce qui est vendable — `UniteHebergement::estCommercialisable()`
     * rend `false` — sans rien effacer, et il est réversible : c'est exactement
     * ce que la modale du maître promet (« reste restaurable — rien n'est
     * effacé »).
     *
     * ## Et pourquoi ce n'est pas un second écrivain du cycle opérationnel
     *
     * `SejourService` se déclare l'unique point d'entrée du CYCLE
     * `libre → occupee → nettoyage` et EXCLUT `hors_service` de ses trois
     * gestes : « une unité hors service n'est jamais touchée, la maintenance
     * prime sur l'exploitation ». Entrer et sortir de `hors_service` est une
     * décision de parc, pas un mouvement du cycle — et c'est ici, avec
     * `restaurerUnite()`, son seul chemin (31/08/2026).
     */
    public function archiverUnite(): void
    {
        $this->exigerEcriture(self::MODULE);

        // Même bascule qu'à l'ouverture — l'ouverture ne protège rien
        // (`FormulaireModal`), l'enregistrement revérifie.
        $this->exigerSuppressionOuverte();

        if ($this->uniteAArchiver === null) {
            return;
        }

        $unite = UniteHebergement::findOrFail($this->uniteAArchiver);

        // Le VERROU du maître (un élément engagé ailleurs ne s'archive pas)
        // vit dans `ParcHebergementService::archiver()` depuis le 02/09/2026 —
        // extrait de cet écran pour que l'onglet « Restaurer » d'Import &
        // Export emprunte le MÊME chemin. Le service recontrôle au moment
        // d'agir, pas seulement à l'affichage.
        try {
            app(ParcHebergementService::class)->archiver($unite);
        } catch (\RuntimeException $refus) {
            $this->addError('archivage', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('hebergement_pwa.hebergement.archivee', [
            'numero' => $unite->numero,
        ]));
    }

    /**
     * Le pendant de l'archivage — sans lui, « reste restaurable » serait une
     * promesse que rien ne tient (PA-59/60/61).
     */
    /**
     * La bascule d'activation de la suppression, ou 403.
     *
     * ⚠ `restaurerUnite()` n'est PAS derrière cette garde, délibérément :
     * restaurer n'est pas supprimer — fermer la bascule pendant qu'une unité
     * est aux archives ne doit jamais l'y enfermer (« reste restaurable »
     * serait sinon une promesse que rien ne tient, PA-59/60/61).
     */
    private function exigerSuppressionOuverte(): void
    {
        if (! app(\App\Shared\Parametres\Services\OptionsSystemeService::class)->suppressionActive()) {
            abort(403);
        }
    }

    public function restaurerUnite(string $uniteId): void
    {
        $this->exigerEcriture(self::MODULE);

        $unite = UniteHebergement::findOrFail($uniteId);

        if ($unite->statut !== 'hors_service') {
            return;
        }

        // Même chemin que l'onglet « Restaurer » d'Import & Export
        // (`ParcHebergementService`, 02/09/2026) — jamais deux écrivains.
        app(ParcHebergementService::class)->restaurer($unite);

        session()->flash('pwa-succes', __('hebergement_pwa.hebergement.restauree', [
            'numero' => $unite->numero,
        ]));
    }

    // =====================================================================
    // Export — PA-119 : il porte sur CE QUI EST AFFICHÉ, et il DIT son filtre
    // =====================================================================

    /**
     * L'export est une LECTURE, et il est ouvert à qui peut lire l'écran.
     *
     * Générer ce document n'écrit rien — ni `etats_generes`, ni aucune table :
     * il met en page les lignes déjà affichées. Exiger `M1 = C` priverait un
     * `comptable`, qui consulte légitimement ce parc, du fichier correspondant
     * à l'écran qu'il a sous les yeux. `genererExport` est inscrit dans les
     * méthodes de lecture de `PwaEcritureAutoriseeTest` (31/08/2026) — et
     * l'inscription ne dispense de rien : le corps reste relu, donc un export
     * qui persisterait un jour serait signalé.
     *
     * ⚠ Ce qui protège cet appel n'est PAS le middleware `module:M1,L` :
     * `ForcerLectureSeule` et les middlewares de module gardent les routes
     * `/pwa`, donc le GET initial, tandis qu'une action Livewire transite par
     * la route dédiée du paquet, hors du groupe (PA-67). Ce qui tient
     * réellement, c'est qu'appeler l'action exige un instantané de composant
     * valide — obtenu en servant la page, qui, elle, est gardée.
     */
    public function genererExport(): BinaryFileResponse|Response|StreamedResponse
    {

        $parc = $this->parcFiltre();

        // Une liste vide se REFUSE : elle ne produit pas une page blanche que
        // le lecteur prendrait pour un parc vide (PA-119).
        if ($parc->isEmpty()) {
            $this->addError('export', __('hebergement_pwa.hebergement.export_vide'));

            return new Response('', 204);
        }

        $filtre = $this->libelleDuFiltre();
        $this->etatFormulaire = null;
        $horodatage = CarbonImmutable::now()->format('Y_m_d_His');

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new HebergementExport($parc->pluck('id')->all(), $filtre, 'parc'),
                'hebergement_parc_'.$horodatage.'.xlsx',
            );
        }

        $etats = $this->etatsDuJour();

        $pdf = Pdf::loadView('pdf.hebergement', [
            'document' => 'parc',
            'parc' => $parc,
            'etats' => $etats,
            // En-tête RG-19 (PA-192) : le filtre RÉELLEMENT appliqué est la
            // période du bloc titre (PA-119).
            'entete' => $this->enTeteRapport(
                __('pwa.hebergement.onglet_plan'),
                __('hebergement_pwa.hebergement.export_filtre', ['filtre' => $filtre]),
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'hebergement_parc_'.$horodatage.'.pdf',
        );
    }

    /**
     * Ferme la modale ouverte — elle ne touche aucune table.
     *
     * ⚠ Elle n'existe QUE parce que `pwa/partials/modale-export.blade.php`
     * câble ce nom en dur sur ses deux boutons : partout ailleurs, cet écran
     * ferme par `$set('etatFormulaire', null)`, qui n'ajoute aucune action à
     * la surface publique. Elle est inscrite dans les méthodes de lecture de
     * `PwaEcritureAutoriseeTest` (31/08/2026) : exiger un droit d'écriture
     * pour REFERMER une modale d'export enfermerait un rôle en lecture dans
     * un panneau qu'il vient d'ouvrir légitimement.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
    }

    // =====================================================================
    // Rendu
    // =====================================================================

    public function render(): View
    {
        $parc = $this->parcFiltre();
        $etats = $this->etatsDuJour();
        $pagination = $this->parcPagine($parc);

        // Les compteurs portent sur TOUT le parc, jamais sur la liste filtrée :
        // « 3 libres » sous un filtre « Bungalow » se lirait comme le parc
        // entier.
        $repartition = array_count_values(array_map(
            static fn (array $etat): string => $etat['cle'],
            $etats,
        ));

        return view('pwa.hebergement.hebergement', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            // La GRILLE affiche la PAGE courante ; les contrôles ci-dessous
            // (état vide, décompte, pagination) portent sur le FILTRE entier.
            'parc' => $pagination['page'],
            'parcEstVide' => $parc->isEmpty(),
            'parcTotalFiltre' => $pagination['total'],
            'parcTotalPages' => $pagination['totalPages'],
            'etats' => $etats,
            'categories' => CategorieHebergement::orderBy('libelle')->get(),
            'clients' => Client::orderBy('nom')->orderBy('prenom')->get(),
            'totalParc' => count($etats),
            'libresCount' => $repartition['libre'] ?? 0,
            'occupeesCount' => $repartition['occupee'] ?? 0,
            'reserveesCount' => $repartition['reservee'] ?? 0,
            'nettoyageCount' => $repartition['nettoyage'] ?? 0,
            'reservationsEnCours' => $this->reservationsAvecHebergement(),
            'joursOccupation' => $this->occupationDuMois(),
            'aujourdHui' => CarbonImmutable::today(),
            'disponibilites' => $this->disponibilitesDeLaPeriode(),
            'rrNuits' => $this->nuitsSaisies(),
            'rrTarif' => $this->tarifDeLUniteSaisie(),
            // L'unité visée par la réservation rapide est résolue ICI : une vue
            // qui interroge la base est un N+1 qu'aucun test de rendu ne voit.
            'rrUnite' => $this->rrUniteId === null
                ? null
                : UniteHebergement::with('categorie')->find($this->rrUniteId),
            'verrouArchivage' => $this->uniteAArchiver === null
                ? []
                : $this->engagementsDe($this->uniteAArchiver)->all(),
            'uniteArchivee' => $this->uniteAArchiver === null
                ? null
                : UniteHebergement::find($this->uniteAArchiver),
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            'title' => 'Hébergement & Réservations — TATACORA AFRIQUE',
        ]);
    }

    // =====================================================================
    // Auxiliaires — tous `protected`/`private` : une méthode publique de plus
    // serait une action Livewire de plus, donc une surface à garder (PA-67).
    // =====================================================================

    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'plan';
    }

    /**
     * Le parc tel qu'il est AFFICHÉ — c'est lui, et lui seul, que l'export
     * emporte (PA-119).
     *
     * @return EloquentCollection<int, UniteHebergement>
     */
    private function parcFiltre(): EloquentCollection
    {
        return UniteHebergement::query()
            ->with('categorie')
            ->when(
                $this->categorie !== '',
                fn ($requete) => $requete->where('categorie_id', $this->categorie),
            )
            ->when(
                $this->recherche !== '',
                fn ($requete) => $requete->where('numero', 'like', '%'.$this->recherche.'%'),
            )
            ->orderBy('numero')
            ->get();
    }

    /**
     * La page courante de `$parc`, et le nombre total de pages.
     *
     * Découpage EN MÉMOIRE sur la collection déjà chargée — le parc d'un
     * gîte se compte en dizaines d'unités, jamais en milliers : une requête
     * paginée à la base ajouterait un aller-retour pour un gain nul ici, là
     * où `crud-engine.js` (l.154, `donneesFiltrees.slice(...)`) fait de même
     * côté client.
     *
     * `$this->page` est CLAMPÉE ici, pas ailleurs : c'est ce qui remplace le
     * `pageActuelle = 1` que le maître pose à chaque changement de filtre
     * (voir le docblock de {@see $page}).
     *
     * @param  EloquentCollection<int, UniteHebergement>  $parc
     * @return array{page: EloquentCollection<int, UniteHebergement>, total: int, totalPages: int}
     */
    private function parcPagine(EloquentCollection $parc): array
    {
        $total = $parc->count();
        $totalPages = max(1, (int) ceil($total / self::PAR_PAGE));

        if ($this->page > $totalPages) {
            $this->page = $totalPages;
        }

        if ($this->page < 1) {
            $this->page = 1;
        }

        return [
            'page' => $parc->slice(($this->page - 1) * self::PAR_PAGE, self::PAR_PAGE)->values(),
            'total' => $total,
            'totalPages' => $totalPages,
        ];
    }

    private function libelleDuFiltre(): string
    {
        $morceaux = [];

        if ($this->categorie !== '') {
            $morceaux[] = (string) CategorieHebergement::find($this->categorie)?->libelle;
        }

        if ($this->recherche !== '') {
            $morceaux[] = $this->recherche;
        }

        return $morceaux === []
            ? __('hebergement_pwa.hebergement.export_sans_filtre')
            : implode(' · ', array_filter($morceaux));
    }

    /**
     * L'ÉTAT DU JOUR de chaque unité du parc — le cœur de cet écran.
     *
     * Trois lectures, jamais une par unité : le N+1 est certain sur un écran
     * qui affiche tout le parc.
     *
     * L'ordre des tests est la règle métier, et il n'est pas interchangeable :
     * la maintenance prime sur tout (une chambre condamnée ne se vend pas),
     * puis le ménage, puis qui dort là ce soir, puis qui est attendu.
     *
     * @return array<string, array{cle: string, libelle: string, bg: string, txt: string, reservation: Reservation|null}>
     */
    private function etatsDuJour(): array
    {
        $aujourdhui = CarbonImmutable::today()->toDateString();

        /** @var EloquentCollection<int, UniteHebergement> $unites */
        $unites = UniteHebergement::query()->orderBy('numero')->get();

        // Qui dort ici ce soir : `sejours`, jamais `unites_hebergement.statut`
        // — le statut dit qu'une chambre est occupée, pas PAR QUI.
        $sejoursEnCours = Sejour::query()
            ->whereNotNull('date_checkin_reel')
            ->whereNull('date_checkout_reel')
            ->with('reservation')
            ->get()
            ->keyBy(static fn (Sejour $sejour): string => (string) $sejour->reservation?->unite_id);

        $reservationsDuJour = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<=', $aujourdhui)
            ->where('date_depart', '>', $aujourdhui)
            ->with('client')
            ->get()
            ->keyBy('unite_id');

        // Une réservation dont le séjour a déjà eu lieu ne rouvre pas un
        // check-in : sans ce filtre, un départ anticipé ferait réapparaître
        // « Effectuer Check-In Client » sur une chambre déjà rendue, et le
        // Service refuserait par « l'arrivée a déjà été enregistrée ».
        $reservationsDejaArrivees = Sejour::query()->pluck('reservation_id')->all();

        $etats = [];

        foreach ($unites as $unite) {
            $sejour = $sejoursEnCours->get($unite->id);
            $reservation = $reservationsDuJour->get($unite->id);

            $cle = match (true) {
                $unite->statut === 'hors_service' => 'hors_service',
                $unite->statut === 'nettoyage' => 'nettoyage',
                $sejour !== null => 'occupee',
                $reservation !== null
                    && ! in_array($reservation->id, $reservationsDejaArrivees, true) => 'reservee',
                default => 'libre',
            };

            $etats[$unite->id] = [
                'cle' => $cle,
                'libelle' => $this->libelleEtat($cle),
                'bg' => self::COULEURS_STATUT[$cle]['bg'],
                'txt' => self::COULEURS_STATUT[$cle]['txt'],
                'reservation' => $cle === 'reservee' ? $reservation : null,
            ];
        }

        return $etats;
    }

    private function libelleEtat(string $cle): string
    {
        return match ($cle) {
            'libre' => __('pwa.hebergement.pastille_libre'),
            'reservee' => __('pwa.hebergement.pastille_reservee'),
            'occupee' => __('hebergement_pwa.hebergement.pastille_occupee'),
            'nettoyage' => __('hebergement_pwa.hebergement.pastille_nettoyage'),
            default => __('pwa.hebergement.pastille_hors_service'),
        };
    }

    private function reservationDuJour(string $uniteId): ?Reservation
    {
        $aujourdhui = CarbonImmutable::today()->toDateString();

        return Reservation::query()
            ->where('unite_id', $uniteId)
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<=', $aujourdhui)
            ->where('date_depart', '>', $aujourdhui)
            ->with('client')
            ->orderBy('date_arrivee')
            ->first();
    }

    /**
     * Onglet « Réservations en cours » — le maître y montre toute réservation
     * portant de l'hébergement, passées comprises, avec son état DÉRIVÉ.
     *
     * PAGINÉ à 10 lignes, la valeur du moteur du maître (`crud-engine.js`
     * l.21) — même mécanisme que `Achats` : propriété `#[Url]` passée en
     * quatrième argument, jamais `WithPagination` (PA-67).
     *
     * @return \Illuminate\Contracts\Pagination\LengthAwarePaginator<int, Reservation>
     */
    private function reservationsAvecHebergement(): \Illuminate\Contracts\Pagination\LengthAwarePaginator
    {
        return Reservation::query()
            ->with(['client', 'unite.categorie'])
            ->orderBy('date_arrivee', 'desc')
            ->paginate(self::PAR_PAGE_RESERVATIONS, ['*'], 'page', max(1, $this->pageCourante));
    }

    /**
     * Le calendrier du mois — bornes SEMI-OUVERTES, comme le maître (l.550) :
     * le jour du départ, la chambre se reloue. Se tromper d'un jour par séjour
     * gonfle le taux d'un tiers sur un mois plein.
     *
     * Une seule requête pour le mois entier : la version précédente en lançait
     * une par jour, soit trente et une.
     *
     * @return array<string, int>
     */
    private function occupationDuMois(): array
    {
        $premier = CarbonImmutable::today()->startOfMonth();
        $suivant = $premier->addMonth();

        $reservations = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<', $suivant->toDateString())
            ->where('date_depart', '>', $premier->toDateString())
            ->get(['date_arrivee', 'date_depart']);

        $jours = [];

        for ($jour = $premier; $jour->lessThan($suivant); $jour = $jour->addDay()) {
            $date = $jour->toDateString();

            $jours[$date] = $reservations
                ->filter(static fn (Reservation $reservation): bool => $reservation->date_arrivee->toDateString() <= $date
                    && $reservation->date_depart->toDateString() > $date)
                ->count();
        }

        return $jours;
    }

    /**
     * Le PRÉDICAT d'engagement vit dans `ParcHebergementService::engagements()`
     * (02/09/2026) — cet écran ne fait plus que le mettre en phrases pour la
     * modale d'archivage. Deux requêtes d'engagement écrites à deux endroits
     * auraient divergé au premier statut ajouté.
     *
     * @return Collection<int, string>
     */
    private function engagementsDe(string $uniteId): Collection
    {
        return app(ParcHebergementService::class)
            ->engagements(UniteHebergement::findOrFail($uniteId))
            ->map(static fn (Reservation $reservation): string => __(
                'hebergement_pwa.hebergement.archivage_detail_reservation',
                [
                    'arrivee' => $reservation->date_arrivee->format('d/m/Y'),
                    'depart' => $reservation->date_depart->format('d/m/Y'),
                ],
            ))
            ->values();
    }

    /** Nuits CALCULÉES, jamais saisies — un total modifiable finit par contredire les dates. */
    /**
     * Les disponibilites de la periode choisie - TOUTES les unites, libres ou
     * non, chacune avec son motif : une liste reduite aux libres empeche de
     * repondre a « et la Pendjari, elle est prise ? » devant le client.
     *
     * La disponibilite vient de `DisponibiliteService` (RG-02), les motifs des
     * reservations actives qui chevauchent (bornes semi-ouvertes). `statut`
     * n'est lu que pour les deux etats qu'il est seul a porter.
     *
     * @return array{valide: bool, nuits: int, libres: int, lignes: list<array<string, mixed>>}
     */
    private function disponibilitesDeLaPeriode(): array
    {
        $vide = ['valide' => false, 'nuits' => 0, 'libres' => 0, 'lignes' => []];

        if ($this->dispoArrivee === '' || $this->dispoDepart === ''
            || strtotime($this->dispoArrivee) === false || strtotime($this->dispoDepart) === false) {
            return $vide;
        }

        $arrivee = CarbonImmutable::parse($this->dispoArrivee);
        $depart = CarbonImmutable::parse($this->dispoDepart);

        if (! $depart->greaterThan($arrivee)) {
            return $vide;
        }

        $nuits = (int) $arrivee->diffInDays($depart);
        $libresIds = app(\App\Domain\Hebergement\Services\DisponibiliteService::class)
            ->unitesDisponibles($arrivee->toDateString(), $depart->toDateString())
            ->pluck('id')
            ->all();

        $reservations = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->where('date_arrivee', '<', $depart->toDateString())
            ->where('date_depart', '>', $arrivee->toDateString())
            ->orderBy('date_arrivee')
            ->get()
            ->groupBy('unite_id');

        $lignes = [];

        foreach (UniteHebergement::query()->with('categorie')->orderBy('numero')->get() as $unite) {
            $libre = in_array($unite->id, $libresIds, true);
            $tarif = (string) ($unite->categorie?->tarif_base ?? '0.00');

            $motif = null;

            if (! $libre) {
                $reservation = $reservations->get($unite->id)?->first();
                $motif = match (true) {
                    $unite->statut === 'hors_service' => __('pwa.hebergement.dispo_motif_hors_service'),
                    $unite->statut === 'nettoyage' => __('pwa.hebergement.dispo_motif_nettoyage'),
                    $reservation !== null => __('pwa.hebergement.dispo_motif_reservation', [
                        'du' => CarbonImmutable::parse($reservation->date_arrivee)->format('d/m/Y'),
                        'au' => CarbonImmutable::parse($reservation->date_depart)->format('d/m/Y'),
                    ]),
                    default => __('pwa.hebergement.dispo_indisponible'),
                };
            }

            $lignes[] = [
                'id' => $unite->id,
                'numero' => $unite->numero,
                'categorie' => $unite->categorie?->libelle,
                'capacite' => $unite->categorie?->capacite_max,
                'libre' => $libre,
                'motif' => $motif,
                // Le montant se CALCULE (tarif de la categorie x nuits) :
                // lecture seule, jamais un champ.
                'montant' => $unite->categorie === null ? null : bcmul($tarif, (string) $nuits, 2),
            ];
        }

        return [
            'valide' => true,
            'nuits' => $nuits,
            'libres' => count(array_filter($lignes, static fn (array $l): bool => $l['libre'])),
            'lignes' => $lignes,
        ];
    }

    private function nuitsSaisies(): int
    {
        if ($this->rrDateArrivee === '' || $this->rrDateDepart === '') {
            return 0;
        }

        $arrivee = CarbonImmutable::parse($this->rrDateArrivee);
        $depart = CarbonImmutable::parse($this->rrDateDepart);

        return $depart->greaterThan($arrivee) ? (int) $arrivee->diffInDays($depart) : 0;
    }

    /**
     * Le tarif est celui de la CATÉGORIE — seule colonne de tarif du schéma.
     * Aucun repli chiffré : une unité sans catégorie rend « 0 », jamais un
     * `?? 20000` qui afficherait un prix que personne n'a fixé.
     */
    private function tarifDeLUniteSaisie(): string
    {
        if ($this->rrUniteId === null) {
            return '0.00';
        }

        return (string) (UniteHebergement::with('categorie')
            ->find($this->rrUniteId)?->categorie->tarif_base ?? '0.00');
    }
}
