<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\LigneReservation;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Exports\HebergementExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Http\Response;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use InvalidArgumentException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Réservations — créer, modifier, annuler, et l'historique (M1/EF-M1-02).
 *
 * Maître : `prototype_v2/pages/reservations.html`, et son panneau
 * `prototype_v2/assets/js/historique-reservations.js` pour les colonnes et les
 * indicateurs.
 *
 * ## L'ÉTAT D'UN SÉJOUR SE DÉDUIT — il ne se lit pas de `statut` (PA-111)
 *
 * Quatre états au maître : à venir, en cours, terminée, annulée. Un seul est
 * une DONNÉE — l'annulation. Les trois autres se lisent des dates, à la date
 * du jour. Les stocker exigerait de les faire vieillir chaque nuit, et rien
 * dans ce dépôt n'écrit `en_cours` ni `terminee` sur une réservation créée par
 * l'API : une réservation restée `confirmee` s'afficherait « à venir » un mois
 * après le départ du client. L'état AFFICHÉ et l'état FILTRÉ viennent donc de
 * la même dérivation, jamais de deux.
 *
 * ## LES MONTANTS : DEUX LIGNES, ET AUCUNE INVENTÉE (PA-112, PA-55)
 *
 * Le maître affiche « Total » et « Reste dû ». Ce serveur ne stocke aucun
 * montant de séjour : le recalculer depuis la grille tarifaire courante
 * réécrirait le prix d'un séjour déjà vendu. Ces colonnes rendent donc « — »,
 * et le refus est nommé à l'écran. Les « Consommations » se lisent d'un
 * panier, et aucune table `paniers` n'existe ici (vérifié contre la base le
 * 31/08/2026, pas contre un document).
 *
 * ## RG-01 ET RG-02 SONT APPELÉES, JAMAIS RÉÉCRITES
 *
 * `ReservationService` est l'unique point d'entrée d'écriture sur
 * `reservations` : il porte le verrou pessimiste, la transaction et
 * l'auto-exclusion en modification (PA-115). Un `Reservation::create()` posé
 * ici contournerait le verrou sans lever la moindre erreur.
 *
 * @see EF-M1-02 Création, modification et annulation de réservation
 * @see RG-01 Prévention des doubles réservations
 * @see RG-02 Libération automatique après annulation
 * @see RG-18 Fiche client unique — détection de doublon avertissante
 */
#[Layout('layouts.pwa')]
#[Title('Réservations — LogiReStock — TATACORA AFRIQUE')]
final class Reservations extends PageMetier
{
    use FormulaireModal;

    public const MODULE = 'M1';

    /**
     * Créer une fiche client est une écriture M3, pas M1 (PA-116) — la
     * synchronisation vérifie les droits PAR OPÉRATION, et un client refusé
     * ferait rejeter la réservation sur sa clé étrangère.
     */
    public const MODULE_CLIENT = 'M3';

    /**
     * Droit transverse d'ANNULATION AVEC COMMISSION ET REMBOURSEMENT
     * (EF-M1-06) — distinct de `M1`, suivant le seul précédent du dépôt pour
     * un droit qui n'est pas un module métier (`ROLES`, `PARAM`). Voir
     * `RolePermissionSeeder::MATRICE` pour la raison de la distinction :
     * avant cette colonne, tout rôle avec `M1 = C` pouvait décider seul d'un
     * remboursement en numéraire sorti de caisse.
     */
    public const MODULE_ANNULATION = 'ANNULATIONS';

    public const PLAFOND_HISTORIQUE = 200;

    /**
     * Les quatre types de client du maître (`reservations.html` l.259) et la
     * valeur que le SCHÉMA stocke.
     *
     * ⚠ Deux registres cohabitent, et les confondre casse la synchronisation :
     * la fiche du maître dit « Entreprise » côté réservation et « Structure »
     * côté client ; `clients.type_client` n'accepte que
     * `particulier|groupe|agence|structure`.
     *
     * @var array<string, string>
     */
    public const TYPES_CLIENT = [
        'particulier' => 'hebergement_pwa.reservations.type_particulier',
        'groupe' => 'hebergement_pwa.reservations.type_groupe',
        'agence' => 'hebergement_pwa.reservations.type_agence',
        'structure' => 'hebergement_pwa.reservations.type_structure',
    ];

    /** Les quatre états dérivés du maître (`historique-reservations.js` l.24-29). */
    public const ETATS = ['a_venir', 'en_cours', 'termine', 'annulee'];

    /**
     * Les QUATRE modes du maitre (`reservations.html`, select `mode_paiement`) :
     * Mobile Money, Virement, Cheque, Credit — pas d'« Especes » chez lui, et
     * on ne complete pas un registre du maitre sans decision (PA-53 : un
     * choix plausible pose ici deviendrait la regle sans que personne ne le
     * rouvre).
     *
     * @var array<string, string>
     */
    public const MODES_PAIEMENT = [
        // « Espèces » AJOUTÉ au registre du maître (01/09/2026, écart
        // déclaré) : sa fiche ne l'a pas, mais son POS l'a — et le comptoir
        // du Gîte encaisse des acomptes en liquide. Sans cette entrée, un
        // acompte espèces n'aurait AUCUN mode, donc aucune pièce comptable
        // possible (ReservationService::TRESORERIE_ACOMPTE_PAR_MODE), alors
        // que l'annulation, elle, rembourse réellement (PA-166).
        'especes' => 'pwa.reservations.mode_especes',
        'mobile_money' => 'pwa.reservations.mode_mobile_money',
        'virement' => 'pwa.reservations.mode_virement',
        'cheque' => 'pwa.reservations.mode_cheque',
        'credit' => 'pwa.reservations.mode_credit',
    ];

    /**
     * Etiquettes de quantite par service — celles du maitre
     * (`reservations-services.js`, `labelQte`).
     *
     * @var array<string, string>
     */
    public const LIBELLES_QUANTITE = [
        'restauration' => 'pwa.reservations.qte_personnes',
        'bar' => 'pwa.reservations.qte_quantite',
        'tourisme' => 'pwa.reservations.qte_participants',
        'vehicule' => 'pwa.reservations.qte_jours',
    ];

    #[Url(as: 'vue')]
    public string $vue = '';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'hist_terme')]
    public string $histTerme = '';

    #[Url(as: 'hist_etat')]
    public string $histEtat = '';

    #[Url(as: 'hist_service')]
    public string $histService = '';

    #[Url(as: 'hist_debut')]
    public string $histDebut = '';

    #[Url(as: 'hist_fin')]
    public string $histFin = '';

    // ---- Fiche de réservation : les CINQ colonnes métier du schéma --------
    public ?string $reservationId = null;

    public ?string $rClientId = null;

    public ?string $rUniteId = null;

    public string $rDateArrivee = '';

    public string $rDateDepart = '';

    public string $rAcompte = '';

    // ---- La fiche du maître (PA-163) -------------------------------------
    public ?string $rCanalId = null;

    public string $rRemiseType = 'aucune';

    public string $rRemiseValeur = '';

    public string $rModePaiement = '';

    /**
     * Les services cochés dans la grille du maître (`grille-services`) —
     * hors hébergement, porté par l'unité de la fiche.
     *
     * @var list<string>
     */
    public array $rServices = [];

    /**
     * Les lignes saisies : service, élément du catalogue, quantité.
     *
     * @var list<array{service: string, source_id: string, quantite: string}>
     */
    public array $rLignes = [];

    // ---- Fiche client (écriture M3) --------------------------------------
    public string $clientNom = '';

    public string $clientPrenom = '';

    public string $clientTelephone = '';

    public string $clientType = 'particulier';

    // ---- Annulation, détail, confirmation, export ------------------------
    public ?string $reservationAAnnuler = null;

    /**
     * Nouvel onglet dédié aux annulations (instruction du Product Owner,
     * 01/09/2026) — `'actives'` (la grille existante, défaut) ou
     * `'annulations'`. Propriété distincte de `$vue`, qui gouverne le
     * panneau Historique (concept différent, non touché).
     */
    #[Url(as: 'onglet')]
    public string $ongletActif = 'actives';

    /**
     * Recherche + filtre de l'onglet Annulations (en-tête navy + barre de
     * recherche par table, décision du Product Owner du 01/09/2026) — mêmes
     * principes que `$histTerme`/`$histService` : filtrage SERVEUR réel,
     * jamais du JS client.
     */
    #[Url(as: 'annul_terme')]
    public string $annulRecherche = '';

    #[Url(as: 'annul_canal')]
    public string $annulCanal = '';

    // ---- Formulaire d'annulation (EF-M1-06) -------------------------------
    /** Pré-rempli depuis `AnnulationReservationService::tauxParDefaut()`, éditable. */
    public string $aTaux = '';

    /** `'pourcentage'` (fraction de l'ACOMPTE) ou `'montant'` (FCFA direct). */
    public string $aModeRemboursement = 'pourcentage';

    public string $aRembourseValeur = '';

    /**
     * Informatif uniquement — voir `AnnulationReservationService` sur
     * pourquoi le délai n'automatise PAS le taux.
     */
    public ?float $aDelaiHeures = null;

    public bool $aSousLeSeuil = false;

    public ?string $reservationConfirmee = null;

    /** Le détail est une LECTURE : ouvert par `$set`, sans action publique. */
    public ?string $detailId = null;

    public string $formatExport = 'pdf';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'reservation' => [
                'reservationId', 'rClientId', 'rUniteId',
                'rDateArrivee', 'rDateDepart', 'rAcompte',
                'rCanalId', 'rRemiseType', 'rRemiseValeur', 'rModePaiement',
                'rServices', 'rLignes',
            ],
            'client' => ['clientNom', 'clientPrenom', 'clientTelephone', 'clientType'],
            'annulation' => [
                'reservationAAnnuler', 'aTaux', 'aModeRemboursement', 'aRembourseValeur',
                'aDelaiHeures', 'aSousLeSeuil',
            ],
        ];
    }

    // =====================================================================
    // Créer / modifier — EF-M1-02
    // =====================================================================

    public function ouvrirCreationReservation(): void
    {
        $this->ouvrirFormulaire('reservation');

        $aujourdhui = CarbonImmutable::today();
        $this->rDateArrivee = $aujourdhui->toDateString();
        $this->rDateDepart = $aujourdhui->addDay()->toDateString();
    }

    /**
     * Coche ou décoche un service de la grille du maître (`grille-services`).
     * Décocher RETIRE ses lignes : les garder hors écran les enverrait à
     * l'enregistrement — une fiche facturerait des services invisibles.
     */
    public function basculerServiceFiche(string $service): void
    {
        $this->exigerEcriture(self::MODULE);

        if (! in_array($service, LigneReservation::SERVICES, true)) {
            return;
        }

        if (in_array($service, $this->rServices, true)) {
            $this->rServices = array_values(array_diff($this->rServices, [$service]));
            $this->rLignes = array_values(array_filter(
                $this->rLignes,
                static fn (array $ligne): bool => $ligne['service'] !== $service,
            ));

            return;
        }

        $this->rServices[] = $service;
        $this->ajouterLigneFiche($service);
    }

    /**
     * Une ligne vierge pour un service coché — le geste « + Ajouter une
     * chambre/un plat/… » du maître (`reservations-services.js`,
     * `ajouterLigne`).
     */
    public function ajouterLigneFiche(string $service): void
    {
        $this->exigerEcriture(self::MODULE);

        if (! in_array($service, LigneReservation::SERVICES, true)) {
            return;
        }

        $this->rLignes[] = ['service' => $service, 'source_id' => '', 'quantite' => '1'];
    }

    public function retirerLigneFiche(int $index): void
    {
        $this->exigerEcriture(self::MODULE);

        unset($this->rLignes[$index]);
        $this->rLignes = array_values($this->rLignes);
    }

    /**
     * PA-115 — une réservation ANNULÉE ne se rouvre pas : l'enregistrer la
     * ferait revivre sans que son statut change.
     */
    public function ouvrirModificationReservation(string $reservationId): void
    {
        $this->ouvrirFormulaire('reservation');

        $reservation = Reservation::findOrFail($reservationId);

        abort_if($reservation->statut === 'annulee', 422, __('hebergement.annulee_non_modifiable'));

        $this->reservationId = $reservation->id;
        $this->rClientId = $reservation->client_id;
        $this->rUniteId = $reservation->unite_id;
        $this->rDateArrivee = $reservation->date_arrivee->toDateString();
        $this->rDateDepart = $reservation->date_depart->toDateString();
        $this->rAcompte = (string) $reservation->acompte;

        // La fiche (PA-163) : rouvrir montre CE QUI EST ENREGISTRÉ, lignes
        // comprises — un formulaire rouvert vide effacerait la fiche au
        // premier enregistrement.
        $this->rCanalId = $reservation->canal_id;
        $this->rRemiseType = $reservation->remise_type;
        $this->rRemiseValeur = $reservation->remise_type === 'aucune' ? '' : (string) $reservation->remise_valeur;
        $this->rModePaiement = (string) ($reservation->mode_paiement ?? '');
        $this->rLignes = $reservation->lignes()->get()
            ->map(static fn (LigneReservation $ligne): array => [
                'service' => $ligne->service,
                'source_id' => $ligne->source_id,
                'quantite' => (string) $ligne->quantite,
            ])
            ->all();
        $this->rServices = array_values(array_unique(array_column($this->rLignes, 'service')));
    }

    /**
     * RG-01 : la garantie appartient au Service, sous verrou pessimiste.
     *
     * Le conflit arrive comme une erreur de VALIDATION lisible — le même
     * message de langue que l'API — et la modale reste ouverte : fermer sur un
     * refus ferait perdre la fiche et retaper les dates.
     */
    public function enregistrerReservation(ReservationService $service): void
    {
        $donnees = $this->validerEcriture([
            'rClientId' => ['required', 'uuid', 'exists:clients,id'],
            'rUniteId' => ['required', 'uuid', 'exists:unites_hebergement,id'],
            'rDateArrivee' => ['required', 'date'],
            'rDateDepart' => ['required', 'date', 'after:rDateArrivee'],
            // Vide n'est pas zéro à la saisie, mais l'est au schéma : `nullable`
            // puis normalisé ci-dessous, jamais une chaîne vide envoyée à un
            // DECIMAL(15,2).
            'rAcompte' => ['nullable', 'numeric', 'min:0'],
            // La fiche du maître (PA-163). Le canal est facultatif sur le
            // formulaire complet — le maître ne le marque requis QUE sur la
            // réservation rapide — mais un canal fourni doit exister.
            'rCanalId' => ['nullable', 'uuid', 'exists:canaux_reservation,id'],
            'rRemiseType' => ['required', 'in:aucune,pourcentage,montant'],
            'rRemiseValeur' => ['nullable', 'numeric', 'min:0'],
            'rModePaiement' => ['nullable', 'in:'.implode(',', array_keys(self::MODES_PAIEMENT))],
            'rLignes' => ['array'],
            'rLignes.*.service' => ['required', 'in:'.implode(',', LigneReservation::SERVICES)],
            'rLignes.*.source_id' => ['required', 'uuid'],
            'rLignes.*.quantite' => ['required', 'numeric', 'gt:0'],
        ]);

        $remiseType = (string) $donnees['rRemiseType'];

        $charge = [
            'client_id' => $donnees['rClientId'],
            'unite_id' => $donnees['rUniteId'],
            'date_arrivee' => $donnees['rDateArrivee'],
            'date_depart' => $donnees['rDateDepart'],
            'acompte' => ($donnees['rAcompte'] ?? '') === '' ? '0' : (string) $donnees['rAcompte'],
            'canal_id' => $donnees['rCanalId'] ?? null,
            'remise_type' => $remiseType,
            // La contrainte CHECK du schéma exige valeur = 0 quand le type est
            // « aucune » : la normalisation vit ici, pas dans la tête de
            // l'utilisateur.
            'remise_valeur' => $remiseType === 'aucune' || ($donnees['rRemiseValeur'] ?? '') === ''
                ? '0'
                : (string) $donnees['rRemiseValeur'],
            'mode_paiement' => ($donnees['rModePaiement'] ?? '') === '' ? null : (string) $donnees['rModePaiement'],
            // Le tarif est FIGÉ à l'enregistrement, depuis le parc (PA-55) :
            // un changement de grille ne réécrit jamais une fiche convenue.
            'tarif_nuit' => (string) UniteHebergement::with('categorie')
                ->findOrFail((string) $donnees['rUniteId'])
                ->categorie?->tarif_base,
        ];

        $lignes = array_map(static fn (array $ligne): array => [
            'service' => (string) $ligne['service'],
            'source_id' => (string) $ligne['source_id'],
            'quantite' => (string) $ligne['quantite'],
        ], $donnees['rLignes'] ?? []);

        try {
            // Fiche ET lignes dans la même transaction : une source de
            // catalogue disparue entre l'écran et l'enregistrement refuse le
            // tout — jamais une réservation enregistrée à moitié.
            $reservation = DB::transaction(function () use ($service, $charge, $lignes): Reservation {
                $reservation = $this->reservationId === null
                    ? $service->creer($charge)
                    : $service->modifier(Reservation::findOrFail($this->reservationId), $charge);

                return $service->remplacerLignes($reservation, $lignes);
            });
        } catch (ChevauchementDetecteException $conflit) {
            $this->addError('rUniteId', $conflit->getMessage());

            return;
        } catch (\InvalidArgumentException $refus) {
            // Le refus d'une ligne (source disparue, quantité) est une erreur
            // de SAISIE : la modale reste ouverte, le message dit quoi rouvrir.
            $this->addError('rLignes', $refus->getMessage());

            return;
        }

        $creation = $this->reservationId === null;

        $this->terminerFormulaire($creation
            ? __('pwa.reservations.enregistree')
            : __('pwa.reservations.modifiee'));

        // Le maître propose l'impression juste après la création (l.193-210) —
        // jamais après une modification, où il n'y a rien de neuf à remettre.
        if ($creation) {
            $this->reservationConfirmee = $reservation->id;
        }
    }

    // =====================================================================
    // Annuler — RG-02, et JAMAIS une suppression
    // =====================================================================

    /**
     * Ouvre le formulaire d'annulation (EF-M1-06) — taux et remboursement
     * pré-remplis, MODIFIABLES ligne par ligne (instruction du Product
     * Owner, 01/09/2026). LES DEUX droits sont exigés ici, comme
     * `ouvrirCreationClient` : présenter un formulaire à quelqu'un qui ne
     * pourra pas le soumettre lui fait perdre sa saisie sans rien lui
     * apprendre.
     */
    public function confirmerAnnulation(string $reservationId, AnnulationReservationService $annulations): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_ANNULATION);

        $reservation = Reservation::findOrFail($reservationId);
        abort_if($reservation->statut === 'annulee', 422, __('hebergement_pwa.reservations.annulation_impossible'));

        // Article 9 du dépôt (refuser plutôt qu'inventer) : sans montant
        // total fiable, aucun calcul de commission n'a de sens — la modale
        // ne s'ouvre pas, le motif se lit dans le bandeau d'erreur déjà
        // rendu en tête de page (`@error('annulation')`).
        if ($reservation->montantTotal() === null) {
            $this->addError('annulation', __('hebergement.annulation_montant_total_inconnu'));

            return;
        }

        $this->ouvrirFormulaire('annulation');

        $this->reservationAAnnuler = $reservation->id;
        $this->aTaux = $annulations->tauxParDefaut();
        $this->aModeRemboursement = 'pourcentage';
        $this->aDelaiHeures = $annulations->delaiHeuresAvantArrivee($reservation);
        $this->aSousLeSeuil = $annulations->estSousLeSeuil($reservation);
        $this->aRembourseValeur = $this->pourcentageRembourseSuggere($reservation, $this->aTaux);
    }

    /**
     * L'unité est libérée par le seul passage du statut à `annulee` : la
     * disponibilité étant calculée à la demande, aucune propagation n'est
     * nécessaire — et aucune ligne n'est effacée (RG-02).
     *
     * Commission, remboursement, écriture comptable éventuelle et audit
     * (auteur + date/heure) sont tenus par `AnnulationReservationService`,
     * jamais recomposés ici (EF-M1-06).
     */
    public function annulerReservation(string $reservationId, AnnulationReservationService $annulations): void
    {
        $auteur = $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_ANNULATION);

        $reservation = Reservation::findOrFail($reservationId);

        if ($reservation->statut === 'annulee') {
            $this->addError('annulation', __('hebergement_pwa.reservations.annulation_impossible'));

            return;
        }

        $donnees = $this->validerEcriture([
            'aTaux' => ['required', 'numeric', 'min:0', 'max:100'],
            'aModeRemboursement' => ['required', 'in:pourcentage,montant'],
            'aRembourseValeur' => ['required', 'numeric', 'min:0'],
        ]);

        try {
            $annulations->annuler($reservation, [
                'taux' => (string) $donnees['aTaux'],
                'mode_remboursement' => (string) $donnees['aModeRemboursement'],
                'valeur_remboursement' => (string) $donnees['aRembourseValeur'],
            ], $auteur);
        } catch (InvalidArgumentException $refus) {
            // Erreur de SAISIE (taux hors bornes, remboursement supérieur à
            // l'acompte) : la modale reste ouverte, comme le conflit RG-01
            // sur `enregistrerReservation`.
            $this->addError('aRembourseValeur', $refus->getMessage());

            return;
        } catch (RuntimeException $refus) {
            // Refus STRUCTUREL (montant total inconnu, réservation déjà
            // annulée entre-temps) : même traitement, message différent.
            $this->addError('annulation', $refus->getMessage());

            return;
        }

        $this->etatFormulaire = null;
        $this->reservationAAnnuler = null;
        session()->flash('pwa-succes', __('pwa.reservations.annulee_flash'));
    }

    /**
     * Le pourcentage de l'ACOMPTE proposé par défaut dans le formulaire :
     * ce qu'il resterait de l'acompte après la commission théorique
     * (taux × montant total), jamais négatif. Un simple point de départ —
     * `annulerReservation()` ne relit jamais cette suggestion, seule la
     * valeur effectivement soumise compte.
     */
    private function pourcentageRembourseSuggere(Reservation $reservation, string $taux): string
    {
        $acompte = (string) $reservation->acompte;

        if (bccomp($acompte, '0.00', 2) <= 0) {
            return '0';
        }

        $montantTotal = $reservation->montantTotal();

        if ($montantTotal === null) {
            return '0';
        }

        $commission = bcdiv(bcmul($montantTotal, $taux, 4), '100', 2);
        $suggere = bcsub($acompte, $commission, 2);

        if (bccomp($suggere, '0.00', 2) < 0) {
            return '0';
        }

        return bcdiv(bcmul($suggere, '100', 4), $acompte, 2);
    }

    // =====================================================================
    // Ajouter un client — une écriture M3 exigée EN PLUS du droit M1
    // =====================================================================

    public function ouvrirCreationClient(): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance : l'écran est M1, le
        // geste est M3. La synchronisation vérifie les droits par opération
        // (PA-65) — un compte qui pousserait un client sans droit M3 verrait
        // sa réservation rejetée sur la clé étrangère, et ne saurait pas
        // pourquoi.
        $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_CLIENT);

        $this->ouvrirFormulaire('client');
    }

    /**
     * RG-18 — la détection de doublon est AVERTISSANTE, jamais bloquante, et
     * elle vit dans `EnregistrementClientService`, pas ici : bloquer pousserait
     * à déformer l'orthographe, recréant le doublon que la règle évite.
     */
    public function enregistrerClient(EnregistrementClientService $service): void
    {
        // Le droit M1 est déjà exigé par `validerEcriture()` ; il est écrit ici
        // en toutes lettres pour que la garde statique voie les DEUX modules
        // sur la même méthode — un droit implicite ne se relit pas.
        $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_CLIENT);

        $donnees = $this->validerEcriture([
            'clientNom' => ['required', 'string', 'max:255'],
            'clientPrenom' => ['nullable', 'string', 'max:255'],
            'clientTelephone' => ['required', 'string', 'max:255'],
            'clientType' => ['required', 'in:'.implode(',', array_keys(self::TYPES_CLIENT))],
        ]);

        $resultat = $service->creer([
            'nom' => $donnees['clientNom'],
            'prenom' => $donnees['clientPrenom'] === '' ? null : $donnees['clientPrenom'],
            'telephone' => $donnees['clientTelephone'],
            'type_client' => $donnees['clientType'],
        ]);

        $nom = $donnees['clientNom'];

        // La fiche créée est sélectionnée : c'est pour la réservation en cours
        // qu'on vient de la créer.
        $this->rClientId = $resultat['client']->id;

        $this->terminerFormulaire(
            $resultat['avertissement_doublon'] === null
                ? __('hebergement_pwa.reservations.client_cree', ['nom' => $nom])
                : __('hebergement_pwa.reservations.doublon_avertissement', [
                    'message' => $resultat['avertissement_doublon'],
                ]),
        );

        // La fiche de réservation reprend la main : le client vient d'y être
        // choisi, et refermer tout obligerait à tout ressaisir.
        $this->etatFormulaire = 'reservation';
    }

    // =====================================================================
    // Le papier remis — PA-113 : ce N'EST PAS une facture
    // =====================================================================

    /**
     * « CONFIRMATION DE RÉSERVATION », et le titre n'est pas négociable.
     *
     * Le maître titre son document « Facture », mais il n'a ni numéro, ni IFU,
     * ni cachet. Au Bénin une facture est normalisée MECeF : imprimer
     * « FACTURE » sur ce papier et le remettre à un client produirait un FAUX
     * DOCUMENT FISCAL. La mention « ne vaut pas facture » est au CORPS, pas en
     * pied de page. La modale, elle, garde les mots du maître.
     *
     * ⚠ AUCUN numéro n'est alloué : `numeroSuivant()` alloue et persiste, ce
     * n'est jamais une lecture (PA-101). Ce document ne touche pas la
     * séquence.
     */
    public function imprimerConfirmation(string $reservationId): StreamedResponse
    {
        $auteur = $this->exigerEcriture(self::MODULE);

        $reservation = Reservation::with(['client', 'unite.categorie'])->findOrFail($reservationId);

        $this->reservationConfirmee = null;

        $pdf = Pdf::loadView('pdf.hebergement', [
            'document' => 'confirmation',
            'reservation' => $reservation,
            'etat' => $this->etatDerive($reservation),
            // En-tête RG-19 (PA-192) — la « période » d'une confirmation est
            // le séjour lui-même.
            'entete' => $this->enTeteRapport(
                __('hebergement_pwa.reservations.confirmation_titre'),
                __('rapports.periode.du_au', [
                    'debut' => $reservation->date_arrivee->format('d/m/Y'),
                    'fin' => $reservation->date_depart->format('d/m/Y'),
                ]),
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'confirmation_reservation_'.substr($reservation->id, 0, 8).'.pdf',
        );
    }

    // =====================================================================
    // Export de l'historique — PA-119 : ce qui est AFFICHÉ, et il dit son filtre
    // =====================================================================

    /**
     * L'export de l'historique est une LECTURE — voir la note jumelle sur
     * `Hebergement::genererExport()`.
     *
     * Il met en page les lignes déjà affichées et n'écrit aucune table. Le
     * priver d'un `comptable` serait d'autant plus absurde ici que
     * l'historique des réservations est précisément la pièce qu'il consulte.
     * Inscrit dans les méthodes de lecture de `PwaEcritureAutoriseeTest`
     * (31/08/2026), corps toujours relu.
     */
    public function genererExport(): BinaryFileResponse|Response|StreamedResponse
    {

        $lignes = $this->historique();

        // PA-119 : une liste vide se REFUSE — elle ne produit pas une page
        // blanche que le comptable prendrait pour un registre vide.
        if ($lignes->isEmpty()) {
            $this->addError('export', __('hebergement_pwa.reservations.export_vide'));

            return new Response('', 204);
        }

        $filtre = $this->libelleDuFiltre();
        $this->etatFormulaire = null;
        $horodatage = CarbonImmutable::now()->format('Y_m_d_His');

        /** @var array<string, array{cle: string, libelle: string, classe: string}> $etats */
        $etats = $lignes->mapWithKeys(
            fn (Reservation $r): array => [$r->id => $this->etatDerive($r)],
        )->all();

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new HebergementExport(
                    $lignes->pluck('id')->all(),
                    $filtre,
                    'reservations',
                    array_map(static fn (array $etat): string => $etat['libelle'], $etats),
                ),
                'reservations_historique_'.$horodatage.'.xlsx',
            );
        }

        $pdf = Pdf::loadView('pdf.hebergement', [
            'document' => 'historique',
            'lignes' => $lignes,
            'etats' => $etats,
            'nuitees' => $this->nuitees($lignes),
            // En-tête RG-19 (PA-192) : le filtre RÉELLEMENT appliqué est la
            // période du bloc titre (PA-119).
            'entete' => $this->enTeteRapport(
                __('pwa.reservations.hist_titre'),
                __('hebergement_pwa.reservations.export_filtre', ['filtre' => $filtre]),
            ),
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'reservations_historique_'.$horodatage.'.pdf',
        );
    }

    /**
     * Ferme la modale ouverte — voir la note jumelle sur `Hebergement` : cette
     * action n'existe que parce que le partiel d'export partagé câble ce nom
     * en dur, elle ne touche aucune table, et elle est inscrite dans les
     * méthodes de lecture. Partout ailleurs, cet écran ferme par
     * `$set('etatFormulaire', null)`.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->reservationConfirmee = null;
        $this->detailId = null;
    }

    // =====================================================================
    // Rendu
    // =====================================================================

    public function render(): View
    {
        $historique = $this->historique();

        // Calculé une seule fois : deux appels nullsafe sur le même
        // utilisateur dans une expression `&&` font croire à PHPStan (à
        // raison, par analyse de flux) que le second ne peut jamais être
        // null — extraire la variable évite l'ambiguïté à la lecture.
        $utilisateurCourant = Auth::user();
        $peutAnnuler = $utilisateurCourant !== null
            && $utilisateurCourant->niveauSurModule(self::MODULE) === 'C'
            && $utilisateurCourant->niveauSurModule(self::MODULE_ANNULATION) === 'C';

        $grille = Reservation::query()
            // 'canal' et 'lignes' : la carte du maître affiche « Type de
            // client • Canal • dates » et des badges de service DÉRIVÉS des
            // lignes (`rendreCarteReservation()`) — les charger ici évite un
            // N+1 par carte, jamais une requête posée dans la vue.
            ->with(['client', 'unite.categorie', 'canal', 'lignes'])
            ->whereNot('statut', 'annulee')
            ->when(
                $this->recherche !== '',
                fn ($requete) => $requete->whereHas(
                    'client',
                    fn ($c) => $c->where('nom', 'like', '%'.$this->recherche.'%')
                        ->orWhere('prenom', 'like', '%'.$this->recherche.'%'),
                ),
            )
            ->orderBy('date_arrivee', 'desc')
            ->get();

        $etats = $grille->merge($historique)
            ->mapWithKeys(fn (Reservation $r): array => [$r->id => $this->etatDerive($r)])
            ->all();

        return view('pwa.hebergement.reservations', array_merge($this->socle(), [
            'grille' => $grille,
            'historique' => $historique,
            'etats' => $etats,
            'historiqueOuvert' => $this->vue === 'historique',
            'nuitees' => $this->nuitees($historique),
            'repartition' => array_count_values(array_map(
                static fn (array $etat): string => $etat['cle'],
                $historique->mapWithKeys(
                    fn (Reservation $r): array => [$r->id => $this->etatDerive($r)],
                )->all(),
            )),
            'clients' => Client::orderBy('nom')->orderBy('prenom')->get(),
            'unites' => UniteHebergement::with('categorie')->orderBy('numero')->get(),
            // Le canal retenu par la fiche rouverte reste proposable même
            // désactivé — règle du maître (`canaux-engine.js`).
            'canaux' => CanalReservation::proposables($this->rCanalId),
            'cataloguesFiche' => $this->etatFormulaire === 'reservation' ? $this->cataloguesFiche() : [],
            'recapFiche' => $this->etatFormulaire === 'reservation' ? $this->recapFiche() : null,
            'detail' => $this->detailId === null
                ? null
                : Reservation::with(['client', 'unite.categorie'])->find($this->detailId),
            'confirmee' => $this->reservationConfirmee === null
                ? null
                : Reservation::with('client')->find($this->reservationConfirmee),
            'aAnnuler' => $this->reservationAAnnuler === null
                ? null
                : Reservation::with('client')->find($this->reservationAAnnuler),
            'peutEcrireClient' => Auth::user()?->niveauSurModule(self::MODULE_CLIENT) === 'C',
            // Nouvel onglet Annulations (instruction du Product Owner,
            // 01/09/2026) : LES DEUX droits sont exigés pour exécuter une
            // annulation, mais `M1 = C` ne suffit plus seul — voir
            // `RolePermissionSeeder::MATRICE` pour la raison.
            'peutAnnuler' => $peutAnnuler,
            'annulations' => $this->ongletActif === 'annulations' ? $this->annulations() : new EloquentCollection(),
            // Registre fermé pour le filtre de l'onglet Annulations — TOUS
            // les canaux, actifs ou non : une annulation ancienne peut viser
            // un canal désactivé depuis, et le masquer le rendrait
            // introuvable au filtre.
            'canauxAnnulations' => $this->ongletActif === 'annulations'
                ? CanalReservation::orderBy('nom')->get()
                : new EloquentCollection(),
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            'title' => 'Réservations — LogiReStock — TATACORA AFRIQUE',
        ]);
    }

    // =====================================================================
    // Auxiliaires
    // =====================================================================

    /**
     * Les réservations annulées AVEC leurs conditions financières — le
     * contenu du nouvel onglet Annulations. Plafonnée comme l'historique
     * (`PLAFOND_HISTORIQUE`) : une liste non bornée sur un registre qui ne
     * fait que grandir finirait par charger des années d'annulations à
     * chaque ouverture d'onglet.
     *
     * @return EloquentCollection<int, Reservation>
     */
    private function annulations(): EloquentCollection
    {
        return Reservation::query()
            ->with(['client', 'unite.categorie', 'utilisateurAnnulation', 'canal'])
            ->where('statut', 'annulee')
            ->when(
                $this->annulRecherche !== '',
                fn ($q) => $q->whereHas(
                    'client',
                    fn ($c) => $c->where('nom', 'like', '%'.$this->annulRecherche.'%')
                        ->orWhere('prenom', 'like', '%'.$this->annulRecherche.'%'),
                ),
            )
            ->when($this->annulCanal !== '', fn ($q) => $q->where('canal_id', $this->annulCanal))
            ->orderByDesc('date_annulation')
            ->limit(self::PLAFOND_HISTORIQUE)
            ->get();
    }

    /**
     * L'historique filtré — c'est lui que l'écran montre ET que l'export
     * emporte : une seule liste, jamais deux requêtes qui divergeraient.
     *
     * @return EloquentCollection<int, Reservation>
     */
    private function historique(): EloquentCollection
    {
        $requete = Reservation::query()
            ->with(['client', 'unite.categorie'])
            ->when(
                $this->histTerme !== '',
                fn ($q) => $q->whereHas(
                    'client',
                    fn ($c) => $c->where('nom', 'like', '%'.$this->histTerme.'%')
                        ->orWhere('prenom', 'like', '%'.$this->histTerme.'%'),
                ),
            )
            ->when($this->histDebut !== '', fn ($q) => $q->where('date_depart', '>=', $this->histDebut))
            ->when($this->histFin !== '', fn ($q) => $q->where('date_arrivee', '<=', $this->histFin));

        // Le seul service que ce serveur porte est l'hébergement : les quatre
        // autres vivent sur le poste de saisie (PA-110). Un filtre sur l'un
        // d'eux ne peut donc rien rendre, et le dire vaut mieux que de rendre
        // la liste entière comme si le filtre n'existait pas.
        if ($this->histService !== '' && $this->histService !== 'hebergement') {
            return new EloquentCollection();
        }

        $lignes = $requete->orderBy('date_arrivee', 'desc')->limit(self::PLAFOND_HISTORIQUE)->get();

        if (! in_array($this->histEtat, self::ETATS, true)) {
            return $lignes;
        }

        // L'état FILTRÉ vient de la même dérivation que l'état AFFICHÉ : deux
        // calculs finiraient par se contredire sur le même écran (PA-121).
        return $lignes->filter(
            fn (Reservation $r): bool => $this->etatDerive($r)['cle'] === $this->histEtat,
        )->values();
    }

    /**
     * Les quatre états du maître — un seul est stocké, les trois autres se
     * déduisent des dates à la date du jour (PA-111).
     *
     * @return array{cle: string, libelle: string, classe: string}
     */
    private function etatDerive(Reservation $reservation): array
    {
        // La dérivation vit sur le MODÈLE depuis le 02/09/2026 : la carte
        // « Réservations & hébergement » de l'accueil lit la même formule —
        // deux calculs finiraient par se contredire (PA-121).
        $cle = $reservation->etatDerive(CarbonImmutable::today());

        return [
            'cle' => $cle,
            'libelle' => match ($cle) {
                'a_venir' => __('hebergement_pwa.reservations.etat_a_venir'),
                'en_cours' => __('hebergement_pwa.reservations.etat_en_cours'),
                'termine' => __('hebergement_pwa.reservations.etat_terminee'),
                default => __('hebergement_pwa.reservations.etat_annulee'),
            },
            'classe' => match ($cle) {
                'a_venir' => 'bg-blue-50 text-blue-700',
                'en_cours' => 'bg-emerald-50 text-emerald-700',
                'termine' => 'bg-slate-100 text-slate-600',
                default => 'bg-red-50 text-red-700',
            },
        ];
    }

    /**
     * @param  Collection<int, Reservation>|EloquentCollection<int, Reservation>  $lignes
     */
    private function nuitees(Collection|EloquentCollection $lignes): int
    {
        return (int) $lignes->sum(
            static fn (Reservation $reservation): int => $reservation->nombreNuitees(),
        );
    }

    /** PA-119 — l'export DIT son filtre, sans quoi on croit avoir vérifié le registre entier. */
    private function libelleDuFiltre(): string
    {
        $morceaux = array_filter([
            $this->histTerme,
            $this->histEtat === '' ? '' : ($this->etatLibelleSeul($this->histEtat)),
            $this->histService,
            ($this->histDebut !== '' || $this->histFin !== '')
                ? __('hebergement_pwa.reservations.export_periode', [
                    'debut' => $this->histDebut === '' ? '…' : $this->histDebut,
                    'fin' => $this->histFin === '' ? '…' : $this->histFin,
                ])
                : '',
        ]);

        return $morceaux === []
            ? __('hebergement_pwa.reservations.export_sans_filtre')
            : implode(' · ', $morceaux);
    }

    private function etatLibelleSeul(string $cle): string
    {
        return match ($cle) {
            'a_venir' => __('hebergement_pwa.reservations.etat_a_venir'),
            'en_cours' => __('hebergement_pwa.reservations.etat_en_cours'),
            'termine' => __('hebergement_pwa.reservations.etat_terminee'),
            'annulee' => __('hebergement_pwa.reservations.etat_annulee'),
            default => '',
        };
    }

    // =====================================================================
    // La fiche du maître — catalogues et récapitulatif (PA-163)
    // =====================================================================

    /**
     * Les quatre catalogues proposables, lus par le MÊME registre que le
     * service d'écriture (`ReservationService::CATALOGUES`) : deux listes
     * écrites à deux endroits finiraient par proposer ce que l'écriture
     * refuse.
     *
     * @return array<string, list<array{id: string, libelle: string, prix: string}>>
     */
    private function cataloguesFiche(): array
    {
        $catalogues = [];

        foreach (ReservationService::CATALOGUES as $service => $definition) {
            $catalogues[$service] = DB::table($definition['table'])
                ->orderBy($definition['libelle'][0])
                ->get()
                ->map(static fn (object $element): array => [
                    'id' => (string) $element->id,
                    'libelle' => implode(' · ', array_map(
                        static fn (string $colonne): string => (string) $element->{$colonne},
                        $definition['libelle'],
                    )),
                    'prix' => (string) $element->{$definition['prix']},
                ])
                ->all();
        }

        return $catalogues;
    }

    /**
     * Le récapitulatif du maître — Sous-total, Remise, Total, Acompte, Reste
     * à payer — calculé en `bcmath` sur ce que le formulaire porte À CET
     * INSTANT, et rendu en lecture seule : une valeur calculable n'est jamais
     * un champ soumis (règle n° 3 du dépôt).
     *
     * `null` tant que l'unité ou les dates manquent : un récapitulatif à zéro
     * sur une fiche incomplète se lirait comme un séjour gratuit.
     *
     * @return array{sous_total: string, remise: string, total: string, acompte: string, reste: string}|null
     */
    private function recapFiche(): ?array
    {
        if ($this->rUniteId === null || $this->rDateArrivee === '' || $this->rDateDepart === '') {
            return null;
        }

        $unite = UniteHebergement::with('categorie')->find($this->rUniteId);
        $tarif = $unite?->categorie?->tarif_base;

        if ($tarif === null) {
            return null;
        }

        try {
            $arrivee = CarbonImmutable::parse($this->rDateArrivee);
            $depart = CarbonImmutable::parse($this->rDateDepart);
        } catch (\Throwable $echec) {
            // Aucune formule n'est changée : la même valeur (`null`, un
            // récapitulatif refusé) est rendue avant comme après. Seule
            // l'observabilité change — l'échec est nommé, pas avalé, comme
            // partout ailleurs dans ce dépôt (MotifsInterditsPwaTest).
            report($echec);

            return null;
        }

        $nuits = (int) $arrivee->diffInDays($depart);

        if ($nuits <= 0) {
            return null;
        }

        $sousTotal = bcmul((string) $tarif, (string) $nuits, 2);

        // Les lignes valides comptent, les lignes en cours de saisie (source
        // pas encore choisie, quantité non numérique) sont ignorées SANS
        // refus : le récapitulatif suit la frappe, l'enregistrement refuse.
        $catalogues = $this->cataloguesFiche();

        foreach ($this->rLignes as $ligne) {
            $prix = null;

            foreach ($catalogues[$ligne['service']] ?? [] as $element) {
                if ($element['id'] === $ligne['source_id']) {
                    $prix = $element['prix'];
                    break;
                }
            }

            if ($prix === null || ! is_numeric($ligne['quantite'])) {
                continue;
            }

            $sousTotal = bcadd($sousTotal, bcmul($prix, (string) $ligne['quantite'], 2), 2);
        }

        $remise = '0.00';

        if (is_numeric($this->rRemiseValeur)) {
            $remise = match ($this->rRemiseType) {
                'pourcentage' => bcdiv(bcmul($sousTotal, $this->rRemiseValeur, 4), '100', 2),
                'montant' => bcadd($this->rRemiseValeur, '0', 2),
                default => '0.00',
            };
        }

        $total = bcsub($sousTotal, $remise, 2);
        $acompte = is_numeric($this->rAcompte) ? bcadd($this->rAcompte, '0', 2) : '0.00';

        return [
            'sous_total' => $sousTotal,
            'remise' => $remise,
            'total' => $total,
            'acompte' => $acompte,
            'reste' => bcsub($total, $acompte, 2),
        ];
    }
}
