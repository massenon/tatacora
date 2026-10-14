<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Crm;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Crm\Services\ReferentielClientService;
use App\Domain\Crm\Services\RelanceClientService;
use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Services\EncaissementFactureService;
use App\Domain\Hebergement\Models\Reservation;
use App\Exports\ClientsCreancesExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\AutoriseArchivage;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Clients & Créances — maitre : `prototype_v2/pages/m3-clients-creances.html`.
 *
 * ## PA-165 (02/09/2026) — LES QUATRE ONGLETS SONT PORTÉS, ET C'EST UN
 *   RENVERSEMENT ASSUMÉ DE CE QUE CE FICHIER DISAIT JUSQU'ICI
 *
 * Cette classe refusait trois onglets sur quatre, le recouvrement, la
 * relance et la création de client, tous pour la MÊME raison de fond : le
 * modèle `Paiement` n'existait pas et rien n'écrivait `paiements` (PA-21).
 * `EncaissementFactureService` (premier writer de `paiements`),
 * `RelanceClientService` (writer de `relances_clients`) et
 * `ReglementFournisseurService` livrent la moitié qui manquait. La prémisse
 * de chaque refus ci-dessous est donc tombée le même jour — daté, pas
 * supposé : PA-21 reste néanmoins ouvert pour tout écran qui n'a pas encore
 * été porté au même titre.
 *
 * Deux refus SURVIVENT, et pour une raison différente de PA-21 :
 *
 *   - la « Ancienneté » de la colonne clients et le filtre par tranche
 *     restaient une extension hors des 61 EF (PA-20) — mais l'onglet
 *     « Suivi des dettes » lui-même EST désormais porté : PA-20 empêchait
 *     d'inventer une DATE D'ÉCHÉANCE dans le contexte d'un client isolé,
 *     jamais de grouper les factures déjà impayées par ancienneté RÉELLE
 *     (`factures.date_emission`, un fait, pas une convention).
 *   - le référentiel de modes de règlement du maître (5 valeurs :
 *     Espèces/Mobile Money/Virement/Chèque/Compensation) n'est PAS celui du
 *     schéma. `EncaissementFactureService::TRESORERIE_PAR_MODE` — donc
 *     `Paiement::MODES` — n'en connaît que quatre, et remplace « Chèque » /
 *     « Compensation » par « Carte » : le schéma fait foi sur la donnée, le
 *     maître sur le mot affiché (Article 0), et inventer un mode que le
 *     Service refuserait romprait le contrat à l'enregistrement.
 *   - le champ « Ville » de la modale « Nouveau client » n'a AUCUNE colonne
 *     au schéma (`clients` n'en porte pas) : l'ajouter écrirait dans le
 *     vide, ou pire, silencieusement nulle part.
 *
 * ## LE SOLDE VIENT DU SERVICE, ET IL N'Y A QU'UNE FORMULE
 *
 * `SoldeClientService` reste le SEUL chemin vers le solde AFFICHÉ dans la
 * bande et la liste (LARAVEL_PWA.md §3) — cette classe ne le réécrit jamais,
 * elle réutilise sa formule PUBLIQUE (`appliquerPredicatImpayee()`,
 * `SQL_RESTE_DU`) pour les vues supplémentaires (balance âgée, solde d'un
 * client isolé, factures impayées d'un client) qu'il n'expose pas
 * lui-même : reprendre `Facture::SQL_RESTE_DU` littéralement, jamais une
 * seconde formule PHP qui diverge au premier terme ajouté (PA-121).
 *
 * ## Ce qui reste calculé, jamais lu d'une colonne
 *
 * `clients.solde` n'est LU NULLE PART, ici comme ailleurs (PA-126).
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHÉE (directive du 31/08/2026)
 *
 * Un refus se déclare sous le jeton `maitre-refuse:<page>#<bloc>`, en
 * commentaire, jamais à l'écran.
 *
 * Aucun refus de BLOC n'est déclaré : le champ « Ville » de la modale
 * « Nouveau client » est le seul écart (voir plus haut), et il est trop
 * étroit pour justifier de soustraire toute la modale à la comparaison des
 * trois sources — cela masquerait la fidélité du reste de son contenu.
 *
 * @see EF-M3-01 Fiche client unique
 * @see EF-M3-03 Relances clients
 * @see EF-M3-04 Suivi des soldes et créances
 * @see RG-18 Détection de doublon — avertir, jamais bloquer
 * @see LARAVEL_PWA.md §1, §3
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-20, PA-21, PA-65, PA-121, PA-126, PA-165
 */
#[Title('Clients & Créances — TATACORA AFRIQUE')]
class ClientsCreances extends PageMetier
{
    use AutoriseArchivage;
    use FormulaireModal;

    /** Le module dont cet écran dépend — `data-module="M3"` du maître (l.14). */
    public const MODULE = 'M3';

    /**
     * Le recouvrement encaisse une FACTURE : une écriture M2, en plus de M3
     * (PA-65 — droit par opération, même motif que les gestes rapides du
     * tableau de bord).
     */
    public const MODULE_FACTURATION = 'M2';

    /** Les QUATRE onglets du maître (l.44-47) — tous portés depuis PA-165. */
    public const ONGLETS = ['clients', 'dettes', 'relances', 'avances'];

    /**
     * `clients.type_client` → libellé affiché.
     *
     * ⚠ DEUX registres cohabitent (PA-116) : le schéma stocke
     * `particulier|groupe|agence|structure`, le maître affiche
     * « Particulier / Groupe / Agence partenaire / Entreprise ». Le schéma
     * fait foi sur la donnée, le maître sur le mot affiché (Article 0).
     *
     * @var array<string, string>
     */
    public const TYPES_CLIENT = [
        'particulier' => 'Particulier',
        'groupe' => 'Groupe',
        'agence' => 'Agence partenaire',
        'structure' => 'Entreprise',
    ];

    /** Les DEUX états du filtre — « À relancer » du maître reste hors registre : voir `clientsARelancer()`. */
    public const ETATS = ['debiteur', 'solde'];

    /**
     * Les tranches d'ancienneté de la balance âgée — mêmes clés, mêmes
     * bornes que `prototype_v2/assets/js/creances-engine.js` (`TRANCHES`,
     * l.43-48) : c'est le référentiel du maître, jamais réinventé.
     *
     * @var array<string, array{min: int, max: int|null}>
     */
    public const TRANCHES = [
        '0_30' => ['min' => 0, 'max' => 30],
        '31_60' => ['min' => 31, 'max' => 60],
        '61_90' => ['min' => 61, 'max' => 90],
        'plus_90' => ['min' => 91, 'max' => null],
    ];

    /** Plafond des journaux (relances, avances, recouvrements) — même arbitrage qu'en `Approvisionnement`. */
    public const PLAFOND = 200;

    /** Un client n'est plus « à relancer » avant ce délai depuis sa dernière relance (maître, KPI 5). */
    public const JOURS_AVANT_RELANCE = 30;

    #[Url(as: 'onglet')]
    public string $onglet = 'clients';

    /** Recherche libre — PROPRIÉTÉ Livewire, jamais une méthode (PA-67). */
    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'etat')]
    public string $etat = '';

    // ---- Formulaire « Nouveau client » (EF-M3-01) ------------------------

    public string $clientNom = '';

    public string $clientTelephone = '';

    public string $clientType = 'particulier';

    // ---- Formulaire « Ajouter un recouvrement » (EF-M2-03 depuis M3) -----

    public ?string $recouvrementClientId = null;

    /** Nom affiché dans l'en-tête de la modale — figé à l'ouverture, jamais recalculé au clavier. */
    public string $recouvrementClientNom = '';

    /**
     * Les factures impayées du client, pour le `<select>` — reconstruites à
     * chaque ouverture, jamais mises à jour au clavier.
     *
     * @var list<array{id: string, libelle: string, reste: string}>
     */
    public array $recouvrementFactures = [];

    public ?string $recouvrementFactureId = null;

    public string $recouvrementMontant = '';

    public string $recouvrementMode = 'especes';

    public string $recouvrementReference = '';

    public string $recouvrementCommentaire = '';

    // ---- Formulaire « Tracer une relance » (EF-M3-03) ---------------------

    public ?string $relanceClientId = null;

    public string $relanceClientNom = '';

    public string $relanceCanal = 'telephone';

    public string $relanceMontant = '';

    public string $relancePromesse = '';

    public string $relanceCommentaire = '';

    // ---- Modale « Historique » (lecture seule) -----------------------------

    public ?string $historiqueClientId = null;

    // ---- Modale d'export partagée (`pwa/partials/modale-export`) -----------

    /** Le format choisi dans la modale — `pdf` (défaut) ou `excel`. */
    public string $formatExport = 'pdf';

    // --- Archivage du référentiel (directive PO du 03/09/2026) ------------
    //
    // « Supprimer = archiver » : le geste passe `clients.actif` à `false` par
    // `ReferentielClientService::archiver()` — jamais un `delete()` : six
    // tables citent `clients.id` en `restrictOnDelete`, et RG-18 pose une
    // fiche client UNIQUE qui doit survivre à la fin de la relation.

    /** @var list<string> Les identifiants cochés dans le tableau des clients. */
    public array $selection = [];

    /** La case « tout sélectionner » de l'entête. */
    public bool $toutSelectionne = false;

    /** @var list<string> Les clients retenus par la modale de confirmation. */
    public array $clientsAArchiver = [];

    /** @var list<string> Les motifs de blocage affichés dans la modale. */
    public array $verrousArchivage = [];

    /** Vrai quand TOUT le lot est engagé : le bouton de confirmation disparaît. */
    public bool $archivageBloque = false;

    /** Nombre d'éléments qui resteront (état PARTIEL du maître). */
    public int $conservesArchivage = 0;

    /** Le nom de l'élément visé quand le lot n'en compte qu'un. */
    public string $libelleArchivage = '';

    /**
     * Le registre FERMÉ des formulaires de l'écran.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'client' => ['clientNom', 'clientTelephone', 'clientType'],
            'archivage' => [
                'clientsAArchiver', 'verrousArchivage', 'archivageBloque',
                'conservesArchivage', 'libelleArchivage',
            ],
            'recouvrement' => [
                'recouvrementClientId', 'recouvrementClientNom', 'recouvrementFactures',
                'recouvrementFactureId', 'recouvrementMontant', 'recouvrementMode',
                'recouvrementReference', 'recouvrementCommentaire',
            ],
            'relance' => [
                'relanceClientId', 'relanceClientNom', 'relanceCanal',
                'relanceMontant', 'relancePromesse', 'relanceCommentaire',
            ],
        ];
    }

    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'clients';
    }

    protected function etatValide(): ?string
    {
        return in_array($this->etat, self::ETATS, true) ? $this->etat : null;
    }

    // =====================================================================
    // « + Nouveau client » (l.35) — écriture M3, `EnregistrementClientService`
    // =====================================================================

    public function ouvrirFormulaireClient(): void
    {
        $this->ouvrirFormulaire('client');
    }

    /**
     * RG-18 — la détection de doublon est AVERTISSANTE, jamais bloquante :
     * elle vit dans `EnregistrementClientService`, jamais réécrite ici (même
     * motif que la modale « Client rapide » du tableau de bord).
     */
    public function enregistrerClient(EnregistrementClientService $clients): void
    {
        $donnees = $this->validerEcriture([
            'clientNom' => ['required', 'string', 'max:255'],
            'clientTelephone' => ['required', 'string', 'max:255'],
            'clientType' => ['required', 'in:'.implode(',', array_keys(self::TYPES_CLIENT))],
        ]);

        $resultat = $clients->creer([
            'nom' => $donnees['clientNom'],
            'telephone' => $donnees['clientTelephone'],
            'type_client' => $donnees['clientType'],
        ]);

        $this->terminerFormulaire(
            $resultat['avertissement_doublon']
                ?? __('pwa.clients.modale_client.succes', ['nom' => $donnees['clientNom']]),
        );
    }

    // =====================================================================
    // « Recouvrement » (l.150) — écriture M2, `EncaissementFactureService`
    // =====================================================================

    public function ouvrirRecouvrement(string $clientId): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de l'ÉCRAN
        // (`self::MODULE`, M3) est exigé par `ouvrirFormulaire()` ; il est
        // écrit ici EN TOUTES LETTRES pour que la garde statique voie les
        // deux modules sur la même méthode. Celui du module RÉELLEMENT
        // écrit (M2, un encaissement de facture) vient ensuite.
        $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_FACTURATION);

        $client = Client::findOrFail($clientId);
        $factures = $this->facturesImpayeesDuClient($client->id);

        if ($factures === []) {
            $this->addError('recouvrementClientId', __('pwa.clients.recouvrement_aucune_creance'));

            return;
        }

        $this->ouvrirFormulaire('recouvrement');

        $this->recouvrementClientId = $client->id;
        $this->recouvrementClientNom = $client->nomComplet();
        $this->recouvrementFactures = $factures;
        $this->recouvrementFactureId = $factures[0]['id'];
        $this->recouvrementMontant = $factures[0]['reste'];
        $this->recouvrementMode = 'especes';
    }

    public function updatedRecouvrementFactureId(string $factureId): void
    {
        foreach ($this->recouvrementFactures as $facture) {
            if ($facture['id'] === $factureId) {
                $this->recouvrementMontant = $facture['reste'];

                return;
            }
        }
    }

    /**
     * ⚠ Le refus du Service est AFFICHÉ tel quel, jamais avalé : un
     * sur-encaissement REFUSÉ doit rester lisible, modale ouverte — le
     * masquer ferait croire à un encaissement qui n'a pas eu lieu
     * (PA-59/60/61).
     */
    public function enregistrerRecouvrement(EncaissementFactureService $encaissements): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->exigerEcriture(self::MODULE_FACTURATION);

        $donnees = $this->validerEcriture([
            'recouvrementFactureId' => ['required', 'uuid', 'exists:factures,id'],
            'recouvrementMontant' => ['required', 'numeric', 'gt:0'],
            'recouvrementMode' => ['required', 'in:'.implode(',', array_keys(EncaissementFactureService::TRESORERIE_PAR_MODE))],
        ]);

        $facture = Facture::findOrFail((string) $donnees['recouvrementFactureId']);

        try {
            $paiement = $encaissements->encaisser(
                $facture,
                (string) $donnees['recouvrementMontant'],
                (string) $donnees['recouvrementMode'],
            );
        } catch (RuntimeException $refus) {
            // Le message du Service est écrit pour l'opérateur (lang/fr/facturation.php).
            $this->addError('recouvrementMontant', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('pwa.clients.recouvrement_succes', [
            // PA-186 : mis en forme par l'auteur unique des montants — le
            // décimal brut (« 6000.00 F ») ne s'affiche plus dans le message.
            'montant' => \App\Pwa\Support\MontantFcfa::format((string) $paiement->montant),
            'client' => $this->recouvrementClientNom,
        ]));
    }

    // =====================================================================
    // « Relancer » (l.216) — écriture M3, `RelanceClientService`
    // =====================================================================

    public function ouvrirRelance(string $clientId): void
    {
        $this->ouvrirFormulaire('relance');

        $client = Client::findOrFail($clientId);

        $this->relanceClientId = $client->id;
        $this->relanceClientNom = $client->nomComplet();
        $this->relanceCanal = 'telephone';
        $this->relanceMontant = $this->soldeDuClient($client->id);
        $this->relancePromesse = '';
        $this->relanceCommentaire = '';
    }

    public function enregistrerRelance(RelanceClientService $relances): void
    {
        $donnees = $this->validerEcriture([
            'relanceClientId' => ['required', 'uuid', 'exists:clients,id'],
            'relanceCanal' => ['required', 'in:'.implode(',', RelanceClient::CANAUX)],
            'relanceMontant' => ['required', 'numeric', 'min:0'],
            'relancePromesse' => ['nullable', 'date'],
        ]);

        try {
            $relances->enregistrer([
                'client_id' => (string) $donnees['relanceClientId'],
                'canal' => (string) $donnees['relanceCanal'],
                'montant_reclame' => (string) $donnees['relanceMontant'],
                'promesse' => ($donnees['relancePromesse'] ?? '') === '' ? null : (string) $donnees['relancePromesse'],
                'commentaire' => $this->relanceCommentaire === '' ? null : $this->relanceCommentaire,
            ]);
        } catch (RuntimeException $refus) {
            $this->addError('relanceMontant', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('pwa.clients.relance_succes', ['client' => $this->relanceClientNom]));
    }

    // =====================================================================
    // « Historique » / « Détail » (l.149, l.173) — LECTURE, aucune écriture
    // =====================================================================

    /**
     * Ouvre le relevé d'un client. Aucun droit d'écriture n'est exigé :
     * consulter un historique que la page affiche déjà n'écrit rien — même
     * famille que `ouvrirExport()` (voir `PwaEcritureAutoriseeTest::
     * METHODES_DE_LECTURE`).
     */
    public function ouvrirHistoriqueClient(string $clientId): void
    {
        $this->historiqueClientId = Client::findOrFail($clientId)->id;
        $this->etatFormulaire = 'historique';
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Archivage du référentiel — « supprimer = archiver » (PO, 03/09/2026)
    // =====================================================================

    /**
     * La case « tout sélectionner » de l'entête (`crud-ui.js` l.66).
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur ? $this->identifiantsAffiches() : [];
    }

    /**
     * Ouvre la confirmation d'archivage — une ligne, ou la sélection entière.
     *
     * Le droit d'ARCHIVER est exigé DÈS l'ouverture : sans lui, un `reception`
     * bascule fermée ouvrirait une modale que l'exécution refuserait en 403.
     */
    public function confirmerArchivageClient(?string $client = null): void
    {
        $this->exigerArchivage();

        // La sélection porte sur CE QUI EST AFFICHÉ (même règle que l'export,
        // PA-119) : cocher tout le référentiel puis changer de filtre ne doit
        // pas archiver des clients que l'écran ne montre plus.
        $ids = $client !== null
            ? [$client]
            : array_values(array_intersect($this->selection, $this->identifiantsAffiches()));

        if ($ids === []) {
            return;
        }

        $this->ouvrirFormulaire('archivage');

        $referentiel = app(ReferentielClientService::class);
        $lot = $this->composerLotArchivage(
            Client::query()->whereIn('id', $ids)->where('actif', true)->orderBy('nom')->get(),
            static fn (Client $c): array => $referentiel->verrous($c),
            static fn (Client $c): string => $c->nomComplet(),
        );

        $this->clientsAArchiver = $lot['ids'];
        $this->verrousArchivage = $lot['motifs'];
        $this->archivageBloque = $lot['bloque'];
        $this->conservesArchivage = $lot['conserves'];
        $this->libelleArchivage = $lot['libelle'];
    }

    /**
     * Archive le lot confirmé — par le SERVICE, jamais un `update()` écrit ici.
     *
     * Un refus du service (une réservation ou une facture née entre
     * l'ouverture et le clic) s'affiche et n'empêche PAS les autres archivages
     * du lot.
     */
    public function archiverClients(ReferentielClientService $referentiel): void
    {
        $this->exigerArchivage();

        if ($this->clientsAArchiver === []) {
            return;
        }

        $archives = 0;

        foreach (Client::query()->whereIn('id', $this->clientsAArchiver)->get() as $client) {
            try {
                $referentiel->archiver($client);
                $archives++;
            } catch (RuntimeException $refus) {
                $this->addError('archivage', $refus->getMessage());
            }
        }

        $this->clientsAArchiver = [];
        $this->selection = [];
        $this->toutSelectionne = false;
        $this->etatFormulaire = null;

        if ($archives > 0) {
            session()->flash('pwa-succes', trans_choice('crm.archivage.succes', $archives, [
                'nombre' => $archives,
            ]));
        }
    }

    /**
     * Le pendant de l'archivage.
     *
     * ⚠ Il n'est PAS derrière `exigerArchivage()`, délibérément : restaurer
     * n'est pas supprimer — fermer la bascule pendant qu'un client est aux
     * archives ne doit jamais l'y enfermer (PA-59/60/61).
     */
    public function restaurerClient(string $client, ReferentielClientService $referentiel): void
    {
        $this->exigerEcriture(self::MODULE);

        $modele = Client::findOrFail($client);
        $referentiel->restaurer($modele);

        session()->flash('pwa-succes', __('crm.archivage.restaure', [
            'nom' => $modele->nomComplet(),
        ]));
    }

    /**
     * Les identifiants du registre AFFICHÉ — filtre et état compris.
     *
     * Il passe par `SoldeClientService::registre()`, la même source que la
     * liste : reconstruire la requête ici en ferait un second auteur du
     * périmètre, et « tout sélectionner » finirait par désigner autre chose
     * que ce que l'écran montre.
     *
     * @return list<string>
     */
    private function identifiantsAffiches(): array
    {
        $terme = trim($this->recherche);

        /** @var list<string> $ids */
        $ids = array_map(
            static fn (object $ligne): string => (string) $ligne->id,
            app(SoldeClientService::class)->registre(
                $terme === '' ? null : $terme,
                $this->etatValide(),
            ),
        );

        return $ids;
    }

    /**
     * « Imprimer PDF » de la modale Historique (maître, l.580) — LECTURE : le
     * document rend, sur un autre papier, un relevé déjà sous les yeux de
     * l'utilisateur (même famille que `genererExport()`, PA-119).
     */
    public function imprimerReleveClient(): ?Response
    {
        if ($this->historiqueClientId === null) {
            return null;
        }

        $client = Client::findOrFail($this->historiqueClientId);
        $historique = $this->historiqueClient($client->id);

        $utilisateur = Auth::user();

        $pdf = Pdf::loadView('pdf.releve-client', [
            'entete' => $this->enTeteRapport(__('pwa.clients.releve_document'), $client->nomComplet()),
            'client' => $client,
            'relances' => $historique['relances'],
            'paiements' => $historique['paiements'],
            'auteur' => $utilisateur === null ? '' : (string) $utilisateur->login,
        ])->setPaper('a4', 'portrait');

        $nom = 'releve_client_'.now()->format('Ymd_His');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    // =====================================================================
    // Export — PA-119 : ce qui est AFFICHÉ, et le document DIT son filtre
    // =====================================================================

    /**
     * Ouvre la modale d'export partagée — LECTURE (`METHODES_DE_LECTURE`).
     *
     * ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026 : le maître pose
     * DEUX boutons (« Excel » / « PDF », `m3-clients-creances.html` l.64-65) ;
     * la PWA n'en pose qu'UN, « Exporter », et le format se choisit dans la
     * modale. Voir `DerogationsMaquette` (export_bouton_unique). Jusqu'au
     * 02/09/2026 cet écran ne portait qu'`exporterExcel()`, sans modale ni
     * PDF — le PDF ajouté est un état RÉEL (dompdf, mêmes lignes que
     * l'écran), jamais une page vide.
     *
     * L'onglet est contrôlé À L'OUVERTURE : ouvrir une modale qui refusera
     * toujours de générer laisserait l'utilisateur deviner pourquoi.
     */
    public function ouvrirExport(): void
    {
        if ($this->ongletValide() !== 'clients') {
            $this->addError('export', __('pwa.clients.export_onglet_refuse'));

            return;
        }

        $this->resetValidation();
        $this->etatFormulaire = 'export';
    }

    /**
     * Produit le document choisi (PDF A4 / Excel) sur la liste FILTRÉE —
     * LECTURE : un export ne produit rien de neuf (PA-119). Une liste vide
     * se REFUSE : une page blanche ne dirait pas si le filtre est trop
     * étroit ou si la donnée n'existe pas.
     */
    public function genererExport(SoldeClientService $soldes, ReportHeaderService $entetes): mixed
    {
        if ($this->ongletValide() !== 'clients') {
            $this->etatFormulaire = null;
            $this->addError('export', __('pwa.clients.export_onglet_refuse'));

            return null;
        }

        $terme = trim($this->recherche);
        $lignes = $soldes->registre($terme === '' ? null : $terme, $this->etatValide());

        if ($lignes === []) {
            $this->etatFormulaire = null;
            $this->addError('export', __('pwa.clients.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $nom = 'clients_creances_'.now()->format('Ymd_His');

        if ($this->formatExport === 'excel') {
            return Excel::download(new ClientsCreancesExport($lignes), $nom.'.xlsx');
        }

        $total = '0.00';

        foreach ($lignes as $ligne) {
            $total = bcadd($total, (string) $ligne->solde, 2);
        }

        $pdf = Pdf::loadView('pdf.clients-creances', [
            'lignes' => $lignes,
            'total' => $total,
            'filtre' => $this->descriptionDuFiltre(),
            // En-tête établissement — source unique RG-19, jamais recopiée
            // en dur (même chemin que `Facturation::imprimerFacture()`).
            'entete' => $entetes->genererEnTete(
                typeRapport: __('pwa.clients.export_document'),
                periode: '',
                auteur: Auth::user(),
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    /**
     * La phrase « Périmètre » du document — PA-119 : l'export DIT son filtre,
     * et « Aucun filtre » se dit aussi, jamais rien.
     */
    private function descriptionDuFiltre(): string
    {
        $parts = [];
        $terme = trim($this->recherche);

        if ($terme !== '') {
            $parts[] = __('pwa.clients.export_filtre_recherche', ['terme' => $terme]);
        }

        $etat = $this->etatValide();

        if ($etat !== null) {
            $parts[] = __('pwa.clients.export_filtre_etat', [
                'valeur' => __($etat === 'debiteur' ? 'pwa.clients.etat_debiteur' : 'pwa.clients.etat_solde'),
            ]);
        }

        return $parts === [] ? __('pwa.clients.export_filtre_aucun') : implode(' · ', $parts);
    }

    // =====================================================================

    public function render(SoldeClientService $soldes): View
    {
        $onglet = $this->ongletValide();
        $etat = $this->etatValide();
        $terme = trim($this->recherche);

        // La balance âgée COMPLÈTE (aucun filtre) sert deux fins : le corps
        // de l'onglet Dettes (filtré si une recherche est active) ET les
        // deux cartes KPI qui en dérivent — une seule requête, jamais deux
        // (même souci qu'`Approvisionnement::etat()`, mémoïsé pour le rendu).
        $detteGlobale = $this->detteAgeeParClient(null);
        $detteAgee = ($onglet === 'dettes' && $terme !== '')
            ? $this->detteAgeeParClient($terme)
            : $detteGlobale;

        $aRelancer = $this->clientsARelancer();

        return view('pwa.crm.clients-creances', array_merge($this->socle(), [
            'onglet' => $onglet,
            'lignes' => $onglet === 'clients'
                ? $soldes->registre($terme === '' ? null : $terme, $etat)
                : [],
            'detteAgee' => $onglet === 'dettes' ? $detteAgee : [],
            'aRelancer' => $aRelancer,
            'historiqueRelances' => $onglet === 'relances' ? $this->historiqueRelances() : collect(),
            'avances' => $onglet === 'avances' ? $this->avances() : collect(),
            'recouvrements' => $onglet === 'avances' ? $this->recouvrementsEncaisses() : collect(),
            // Les totaux portent sur le registre ENTIER, comme le maître.
            'totaux' => $soldes->totaux(),
            'kpiDettesDouteuses' => $this->kpiParTranche($detteGlobale, 'plus_90'),
            'kpiRecent' => $this->kpiParTranche($detteGlobale, '0_30'),
            'kpiEncaisse30j' => $this->encaisseSur30Jours(),
            'kpiARelancer' => count($aRelancer),
            'etatApplique' => $etat,
            // Le recouvrement exige les DEUX droits (M3 l'écran, M2
            // l'écriture réelle, PA-65) : le bouton ne s'offre que si les
            // deux sont réunis, comme `Accueil::peutEcrire()`.
            'peutEncaisser' => $this->peutEcrire(self::MODULE_FACTURATION),
            'peutEcrireClient' => $this->peutEcrire(self::MODULE),
            // La vue ne rejoue JAMAIS la règle d'archivage : elle la reçoit
            // (voir `AutoriseArchivage` — un seul auteur, deux lecteurs).
            'peutArchiver' => $this->peutArchiver(),
            'clientHistorique' => $this->historiqueClientId === null ? null : Client::find($this->historiqueClientId),
            'historique' => $this->historiqueClientId === null ? [] : $this->historiqueClient($this->historiqueClientId),
            // PA-119 — le sous-titre de la modale d'export DIT le filtre.
            'filtreExport' => $this->descriptionDuFiltre(),
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // =====================================================================
    // Lectures — chacune réutilise la formule PUBLIQUE de `SoldeClientService`
    // =====================================================================

    /**
     * Les factures impayées d'UN client, formule identique à `registre()`
     * mais groupée par PIÈCE plutôt que par client — ce que la modale de
     * recouvrement exige (choisir LA pièce réglée).
     *
     * @return list<array{id: string, libelle: string, reste: string}>
     */
    private function facturesImpayeesDuClient(string $clientId): array
    {
        $lignes = SoldeClientService::appliquerPredicatImpayee(
            DB::table('factures')->where('factures.client_id', $clientId),
        )
            ->selectRaw('factures.id, factures.numero_mecef, factures.date_emission, '.SoldeClientService::SQL_RESTE_DU.' AS reste')
            ->orderBy('factures.date_emission')
            ->get();

        return $lignes->map(static fn (object $l): array => [
            'id' => (string) $l->id,
            'libelle' => (string) ($l->numero_mecef ?? $l->id),
            'reste' => bcadd((string) $l->reste, '0', 2),
        ])->all();
    }

    /** Le solde d'UN client — même prédicat que `SoldeClientService::totaux()`, restreint à un client. */
    private function soldeDuClient(string $clientId): string
    {
        $total = SoldeClientService::appliquerPredicatImpayee(
            DB::table('factures')->where('factures.client_id', $clientId),
        )->selectRaw('SUM'.SoldeClientService::SQL_RESTE_DU.' AS total')->value('total');

        return bcadd((string) ($total ?? '0'), '0', 2);
    }

    /**
     * Balance âgée PAR CLIENT — l'onglet « Suivi des dettes » du maître
     * (`m3-clients-creances.js` `vueDettes()`, l.160-195). Ancienneté depuis
     * `factures.date_emission`, jamais une colonne de statut : c'est un fait,
     * pas une convention (PA-20 ne portait que sur une date d'ÉCHÉANCE, que
     * personne n'a décidée — celle-ci est réelle).
     *
     * @return list<array{client_id: string, nom: string, tranches: array<string, string>, total: string}>
     */
    private function detteAgeeParClient(?string $terme): array
    {
        $requete = SoldeClientService::appliquerPredicatImpayee(
            DB::table('factures')->join('clients', 'clients.id', '=', 'factures.client_id'),
        );

        if ($terme !== null) {
            $requete->where(function ($sous) use ($terme): void {
                $sous->where('clients.nom', 'like', '%'.$terme.'%')
                    ->orWhere('clients.prenom', 'like', '%'.$terme.'%');
            });
        }

        $factures = $requete
            ->selectRaw('factures.client_id, clients.nom, clients.prenom, factures.date_emission, '.SoldeClientService::SQL_RESTE_DU.' AS reste')
            ->get();

        $aujourdhui = Carbon::today();
        /** @var array<string, array{client_id: string, nom: string, tranches: array<string, string>, total: string}> $parClient */
        $parClient = [];

        foreach ($factures as $f) {
            $jours = (int) Carbon::parse((string) $f->date_emission)->diffInDays($aujourdhui);
            $tranche = $this->trancheDe($jours);
            $reste = bcadd((string) $f->reste, '0', 2);

            $parClient[$f->client_id] ??= [
                'client_id' => (string) $f->client_id,
                'nom' => trim($f->nom.' '.($f->prenom ?? '')),
                'tranches' => array_fill_keys(array_keys(self::TRANCHES), '0.00'),
                'total' => '0.00',
            ];

            $parClient[$f->client_id]['tranches'][$tranche] = bcadd($parClient[$f->client_id]['tranches'][$tranche], $reste, 2);
            $parClient[$f->client_id]['total'] = bcadd($parClient[$f->client_id]['total'], $reste, 2);
        }

        $lignes = array_values($parClient);
        usort($lignes, static fn (array $a, array $b): int => bccomp($b['total'], $a['total'], 2) ?: strcmp($a['nom'], $b['nom']));

        return $lignes;
    }

    private function trancheDe(int $jours): string
    {
        foreach (self::TRANCHES as $cle => $bornes) {
            if ($jours >= $bornes['min'] && ($bornes['max'] === null || $jours <= $bornes['max'])) {
                return $cle;
            }
        }

        return 'plus_90';
    }

    /**
     * Une carte KPI (« Dont + de 90 jours », « 0 à 30 jours ») — dérivée de
     * la MÊME balance âgée que l'onglet Dettes, jamais une seconde requête.
     *
     * @param  list<array{client_id: string, nom: string, tranches: array<string, string>, total: string}>  $detteGlobale
     */
    private function kpiParTranche(array $detteGlobale, string $tranche): string
    {
        $total = '0.00';
        foreach ($detteGlobale as $ligne) {
            $total = bcadd($total, $ligne['tranches'][$tranche], 2);
        }

        return $total;
    }

    /**
     * KPI « Encaissé sur 30 j » — somme réelle des `paiements` récents
     * (PA-21 levée). La formule vit dans `SoldeClientService` depuis le
     * 02/09/2026 : la carte « Clients & créances » de l'accueil lit la même
     * (PA-121) — et le Service filtre `statut = 'actif'`, ce que cette
     * version omettait : un paiement ANNULÉ était compté comme encaissé.
     */
    private function encaisseSur30Jours(): string
    {
        return app(SoldeClientService::class)->encaisseDepuis(now()->subDays(30));
    }

    /**
     * Les débiteurs sans relance récente — KPI « Clients à relancer » et
     * bloc « Clients à relancer » de l'onglet Relances (maître, footer
     * « Plus de 30 j sans relance récente »).
     *
     * Chaque ligne porte aussi les deux colonnes du maître (`vueRelances()`,
     * m3-clients-creances.js l.207-219), rendues depuis le 01/09/2026 :
     *
     *   - `anciennete_max` — jours depuis la PLUS ANCIENNE facture impayée
     *     du client (`MIN(date_emission)`), le même prédicat que le solde
     *     (`SoldeClientService::appliquerPredicatImpayee()`), jamais une
     *     seconde formule. C'est une ancienneté RÉELLE, pas une échéance
     *     inventée : PA-20 n'interdisait que la seconde (même arbitrage que
     *     `detteAgeeParClient()`).
     *   - `derniere_relance` — `MAX(date_relance)`, ou `null` : l'écran
     *     affiche « Jamais relancé », comme le maître (l.213).
     *
     * @return list<array{id: string, nom: string, solde: string, anciennete_max: int, derniere_relance: string|null}>
     */
    private function clientsARelancer(): array
    {
        $debiteurs = app(SoldeClientService::class)->registre(null, 'debiteur');

        $dernieres = RelanceClient::query()
            ->select('client_id')
            ->selectRaw('MAX(date_relance) AS derniere')
            ->groupBy('client_id')
            ->pluck('derniere', 'client_id');

        $plusAnciennes = SoldeClientService::appliquerPredicatImpayee(DB::table('factures'))
            ->selectRaw('factures.client_id, MIN(factures.date_emission) AS plus_ancienne')
            ->groupBy('factures.client_id')
            ->pluck('plus_ancienne', 'client_id');

        $seuil = now()->subDays(self::JOURS_AVANT_RELANCE)->toDateString();
        $aujourdhui = Carbon::today();

        $aRelancer = [];

        foreach ($debiteurs as $ligne) {
            $derniere = $dernieres[$ligne->id] ?? null;

            if ($derniere !== null && $derniere >= $seuil) {
                continue;
            }

            $plusAncienne = $plusAnciennes[$ligne->id] ?? null;

            $aRelancer[] = [
                'id' => (string) $ligne->id,
                'nom' => trim($ligne->nom.' '.($ligne->prenom ?? '')),
                'solde' => $ligne->solde,
                'anciennete_max' => $plusAncienne === null
                    ? 0
                    : (int) Carbon::parse((string) $plusAncienne)->diffInDays($aujourdhui),
                'derniere_relance' => $derniere === null ? null : (string) $derniere,
            ];
        }

        return $aRelancer;
    }

    /**
     * @return \Illuminate\Support\Collection<int, RelanceClient>
     */
    private function historiqueRelances(): \Illuminate\Support\Collection
    {
        return RelanceClient::query()
            ->with(['client', 'utilisateurCreation'])
            ->orderByDesc('date_relance')
            ->limit(self::PLAFOND)
            ->get();
    }

    /**
     * « Avances et acomptes » — réservations à acompte > 0, jamais annulées.
     * Origine : le canal SAISI ou un tiret (PA-163, les fiches d'avant n'en
     * ont pas). Reste dû : `Reservation::resteAPayer()`, la MÊME formule
     * que l'écran Réservations (PA-111) — jamais recalculée ici.
     *
     * @return \Illuminate\Support\Collection<int, Reservation>
     */
    private function avances(): \Illuminate\Support\Collection
    {
        return Reservation::query()
            ->with(['client', 'canal'])
            ->where('acompte', '>', '0.00')
            ->whereNot('statut', 'annulee')
            ->orderByDesc('date_arrivee')
            ->limit(self::PLAFOND)
            ->get();
    }

    /**
     * @return \Illuminate\Support\Collection<int, Paiement>
     */
    private function recouvrementsEncaisses(): \Illuminate\Support\Collection
    {
        return Paiement::query()
            ->with(['facture.client', 'utilisateurCreation'])
            ->orderByDesc('date_paiement')
            ->limit(self::PLAFOND)
            ->get();
    }

    /**
     * @return array{relances: \Illuminate\Support\Collection<int, RelanceClient>, paiements: \Illuminate\Support\Collection<int, Paiement>}
     */
    private function historiqueClient(string $clientId): array
    {
        return [
            'relances' => RelanceClient::query()
                ->where('client_id', $clientId)
                ->orderByDesc('date_relance')
                ->get(),
            'paiements' => Paiement::query()
                ->whereHas('facture', static fn ($q) => $q->where('client_id', $clientId))
                ->with('facture')
                ->orderByDesc('date_paiement')
                ->get(),
        ];
    }

    /**
     * Le niveau réel sur un module, ET sur l'écran — même source que
     * `Accueil::peutEcrire()`. Un module écrit DEPUIS cet écran (ici, M2)
     * exige les deux droits, jamais l'un pour l'autre (PA-65).
     */
    private function peutEcrire(string $module): bool
    {
        /** @var \App\Models\User|null $utilisateur */
        $utilisateur = auth()->user();

        return $utilisateur !== null
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule($module) === 'C'
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }
}
