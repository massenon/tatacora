<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Ventes\Services\VenteService;
use App\Exports\FacturationExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\MontantFcfa;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use Symfony\Component\HttpFoundation\Response;

/**
 * Facturation & Caisse MECeF — maitre :
 * `prototype_v2/pages/m2-facturation.html`.
 *
 * En-tete (l.22-27), puis le « Registre des factures émises » (l.29, rendu par
 * `rendreRegistre()` l.75-140) : son en-tete, sa barre de recherche et ses deux
 * filtres, sa bande de compteurs et son tableau a sept colonnes (l.124-132).
 *
 * ## LE BLOC « JEU DE DEMONSTRATION » EST REFUSE — c'est le point du lot
 *
 * ECART DELIBERE — `m2-facturation.html` l.33-39
 * Le maitre : sous le registre reel, un second tableau titre « Jeu de
 * démonstration », avec ce sous-titre — « Les lignes ci-dessous sont des
 * factures de démonstration livrées avec le prototype. Elles ne proviennent pas
 * des points de vente — le registre réel est au-dessus. » — puis les zones du
 * moteur CRUD et ses cinq modales.
 * Ici : rien de tout cela n'est rendu ; le bloc est nomme au bloc de refus.
 * Raison : DEUX raisons, et chacune suffirait.
 *  1. Article 6, litteralement : « Ne se portent jamais tels quels : les
 *     OUTILS DE DEMONSTRATION de la maquette : sélecteur de rôle de test,
 *     bouton "forcer l'affichage", JEUX DE DONNEES FIGES. » Le maitre le dit
 *     de lui-meme en sous-titre.
 *  2. Ce que ce CRUD ecrit, ce sont des FACTURES. Poser de fausses pieces dans
 *     un registre fiscal est la version tableau de PA-113 — le papier qui
 *     s'intitulait « Facture » sans numero ni cachet. Au Benin une facture est
 *     normalisee MECeF ; un enregistrement fabrique dans `factures` prend un
 *     numero de la sequence unique et decale toute la suite.
 * PA-144 avait deja nomme ce refus, mais mal : il est repris ici avec LES MOTS
 * DU MAITRE, pour que qui compare les deux ecrans retrouve SA formulation.
 *
 * Refus declares :
 *   maitre-refuse:m2-facturation.html#modale-formulaire
 *   maitre-refuse:m2-facturation.html#modale-detail
 *   maitre-refuse:m2-facturation.html#modale-suppression
 *   maitre-refuse:m2-facturation.html#modale-export
 *   maitre-refuse:m2-facturation.html#modale-import
 *
 * ## LA MENTION DE CERTIFICATION EST DERIVEE DES PIECES, JAMAIS FIGEE (PA-119)
 *
 * Le maitre l'ecrit en dur — « MECeF — non certifiées, démonstration » (l.107)
 * — avec ce commentaire : « Jamais "certifiées : N". MECeF est factice ici, et
 * l'ecrire autrement serait affirmer une certification qui n'a pas eu lieu. »
 *
 * L'INTENTION est gardee, le MECANISME change : le compte vient de
 * `Facture::estCertifiee()`, qui se derive du NUMERO et non du statut. Une
 * constante resterait vraie aujourd'hui et deviendrait fausse le jour de
 * l'inscription DGI — c'est-a-dire le jour ou elle compterait vraiment (PA-61,
 * PA-100). Aujourd'hui elle rend exactement la phrase du maitre, parce que
 * c'est la verite : `MecefClientFake` produit des numeros `MECEF-DEMO-`.
 *
 * ⚠ `estCertifiee()` et `estFigee()` sont DEUX predicats de sens oppose.
 * Celui qui compte des certifications appelle le premier ; le second porte
 * l'etat du cycle de vie et rendrait `true` sur une piece de demonstration.
 *
 * ## Ce qui n'est PAS porte — Article 8, chaque motif verifie le 27/08/2026
 *
 * ECART DELIBERE — `m2-facturation.html` l.98-101 (filtre « Toutes les
 * origines »), l.128 (colonne « Origine »)
 * Le maitre : trois origines — « POS au comptant », « Séjour client hébergé »,
 * « Facture directe » (`facture-engine.js` l.40-44).
 * Ici : le filtre n'est pas offert, la colonne rend « — ».
 * Raison : `factures` ne porte AUCUNE colonne d'origine — verifie contre
 * `2026_08_01_000200_create_facturation.php` l.16-31 (numero_mecef, client_id,
 * date_emission, montant_ht, montant_tva, montant_ttc, statut, qr_code_fiscal)
 * et contre `Facture::$fillable`. L'origine ne se deduit pas non plus des
 * lignes : `lignes_facture.source_module` dit l'ACTIVITE vendue, pas le canal
 * de vente — un sejour et un comptoir peuvent porter les memes lignes de bar.
 * Deviner l'un a partir de l'autre inventerait une classification sur l'ecran
 * meme ou l'on rapproche la caisse.
 *
 * ECART DELIBERE — `m2-facturation.html` l.146-149 (les valeurs de la colonne
 * « Statut » : « émise », « annulée », « avoir de N° »)
 * Le maitre : deux statuts de piece et un marquage d'avoir.
 * Ici : les quatre valeurs REELLES de `factures.statut` — « brouillon »,
 * « en attente de certification », « certifiée », « échec de certification » —
 * et le nombre d'avoirs rattaches, en plus.
 * Raison : c'est le meme arbitrage que PA-49, deja rendu sur M11 — « les
 * intitules affiches disent ce qui est reellement calcule ; ne pas les
 * "corriger" vers le libelle du prototype ». `factures.statut` est le CYCLE
 * MECeF, pas un etat d'emission : ecrire « émise » sur une facture en echec de
 * certification masquerait exactement ce qu'il faut voir. Et un avoir n'est pas
 * une facture negative ici — c'est une ligne de la table `avoirs`, rattachee a
 * sa facture, qui reste intacte (RG-03 : aucune suppression, la correction
 * passe par l'avoir). Le TITRE de la colonne, lui, ne bouge pas.
 *
 * « Export Excel » (`m2-facturation.html` l.102-103) — ETAIT refuse,
 * NE L'EST PLUS (01/09/2026)
 *
 * Le motif ecrit ici jusqu'au 01/09/2026 disait : identique aux quatre pages
 * M6/M7 de ce lot, « le moteur d'etats existe (RG-19), mais
 * `LARAVEL_PWA.md` §2 reserve l'exception a la lecture seule au seul Hub
 * Etats & Rapports. L'etendre est une divergence documentaire, donc pas une
 * decision d'agent (§9). » — et posait la question au rapport suivant.
 *
 * ⚠ CE MOTIF ETAIT DEJA FAUX AU 31/08/2026. RG-19 gouverne le CATALOGUE
 * d'etats de M14, pas les exports d'ecran : `Stocks`, `Achats`, `Depenses`,
 * `Locations` appellent tous `Excel::download()` DIRECTEMENT, sans passer
 * par `GenerateurEtatService`. `PwaEcritureAutoriseeTest::METHODES_DE_LECTURE`
 * inscrit `exporterExcel`/`genererExport` comme des LECTURES depuis cette
 * date-la, PARTOUT. La decision que ce bloc disait attendre a ete rendue le
 * 01/09/2026 (audit navigateur, Product Owner) : l'export sur les pieces
 * AFFICHEES (PA-119).
 *
 * ⚠ DEROGATION PO du 01/09/2026, rappelee le 02/09/2026 — EXPORT UNIFIE.
 * Le « Export Excel » direct est remplace par UN bouton « Exporter » qui
 * ouvre la modale d'export partagee (`ouvrirExport()`/`genererExport()`),
 * ou le format PDF A4 / Excel se choisit. Le PDF de l'ECRAN est le REGISTRE
 * affiche, en A4 dompdf (`pdf.facturation-registre`) — il ne remplace PAS
 * les factures individuelles, qui gardent leur bouton « Facture A4 » par
 * ligne (`imprimerFacture()`, document MECeF). Voir `DerogationsMaquette`
 * (export_bouton_unique). L'ancienne mention « Export PDF reste NON PORTE :
 * hors du perimetre demande » a cesse d'etre vraie ce jour-la.
 *
 * ## LES DEUX GESTES D'ECRITURE DE CET ECRAN (lot PA-159)
 *
 * Jusqu'a ce lot, ce composant n'avait qu'une methode publique : `render()`.
 * Le module etait presente comme livre et ne permettait rien.
 *
 * **1. L'AVOIR — et c'est le seul geste de correction admis.** Le maitre pose
 * « Modifier » et « Supprimer definitivement » dans son jeu de demonstration.
 * Ni l'un ni l'autre n'existe ici : RG-03 rend une facture figee immuable,
 * `BasePolicy::delete()` rend `false` sur les vingt policies, et
 * `FactureObserver` refuse a `updating()`. PA-159 nomme lui-meme le geste
 * metier qui remplace le « D » de CRUD sur ce module : l'avoir.
 * `EmissionFactureService::emettreAvoir()` existe et porte la regle (plafond
 * au TTC de la facture) ; ce composant ne la reecrit pas, il l'appelle.
 *
 * **2. LE DOCUMENT A4 — et il porte le filigrane.** Aucun etat de facture
 * n'etait genere cote serveur : le filigrane « DOCUMENT DE DEMONSTRATION »,
 * troisieme obligation ouverte de PA-124, n'avait nulle part ou s'imprimer.
 * Il en a un desormais, et sa condition est `Facture::estCertifiee()` — le
 * predicat qui se derive du NUMERO, jamais du statut (PA-100). Fonder le
 * filigrane sur `estFigee()` le ferait disparaitre de toute facture
 * `MECEF-DEMO-` certifiee : exactement le document qu'il doit marquer.
 *
 * ⚠ **DEPUIS le 01/09/2026, l'en-tete vient de `ReportHeaderService`**,
 * jamais recopiee en dur : c'est la meme source que le catalogue d'etats M14
 * (RG-19), et c'est elle qui affiche desormais IFU/RCCM lorsqu'ils sont
 * renseignes — ce document ne les affichait jamais, meme renseignes, avant ce
 * lot.
 *
 * ⚠ **Encaissements et reste du (PA-165)** : `Facture::paiements` et
 * `Facture::resteDu()` sont lus tels quels, jamais recalcules ici — deux
 * formules du meme montant auraient fini par diverger.
 *
 * ⚠ **Aucune EMISSION n'est offerte ici, et ce n'est pas un oubli.** Le
 * registre reel du maitre n'a aucun bouton de creation, et son etat vide dit
 * ou les factures naissent : « Encaissez au point de vente ou cloturez un
 * sejour » (l.127-128). C'est le cas dans le code —
 * `EmissionFactureService::emettrePourReservation()` est appele par
 * `PosHeberges`, et le service n'expose aucune emission directe. En ajouter
 * une ici demanderait d'ecrire dans `app/Domain/**`, hors du perimetre de ce
 * lot, et surtout : le formulaire du maitre saisit un « Montant TTC » a la
 * main, alors que `recalculerTotaux()` interdit precisement qu'un total ne
 * corresponde pas a ses lignes.
 *
 * @see EF-M2-01 Emission de facture normalisee
 * @see EF-M2-02 Consolidation multi-activites
 * @see RG-03 Immuabilite de la facture certifiee — l'avoir, seule correction
 * @see LARAVEL_PWA.md §1, §3
 * @see DIRECTIVE_CONFORMITE_100.md Articles 4, 6, 7, 8
 */
#[Title('Facturation & Caisse MECeF — TATACORA AFRIQUE')]
class Facturation extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'ecran — `data-module="M2"` du maitre (l.16). */
    public const MODULE = 'M2';

    /**
     * 10 lignes par page — la valeur du moteur du maitre (`crud-engine.js`
     * l.21, `lignesParPage = 10`). Remplace l'ancien plafond de 200 lignes
     * tronquees : le maitre PAGINE, il ne tronque pas.
     */
    public const PAR_PAGE = 10;

    /**
     * Les cinq activites du maitre (l.90), avec SES libelles, indexees par la
     * valeur reelle de `lignes_facture.source_module`.
     *
     * ⚠ CETTE VALEUR REELLE EST LE CODE DE MODULE (`M1`, `M4`...), PAS LE NOM
     * DE DOMAINE — corrige le 02/09/2026, trouve par le passage navigateur :
     * la colonne « Activites » affichait « M1 » en clair, et le filtre
     * d'activite ne pouvait JAMAIS correspondre. La premisse d'origine (« le
     * schema stocke le nom du domaine ») venait du commentaire de la
     * migration, dementie par TOUS les ecrivains reels :
     * `EmissionFactureService` ecrit `M1`, `VenteService::MODULES` indexe les
     * paniers par `M1/M4/M5/M8/M9`, `Facture::SQL_ACOMPTES_LIES` filtre sur
     * `M1`, et la ventilation M11 (`noms-activites` de l'accueil) mappe les
     * memes codes. Le maitre lui-meme indexe par code (`facture-engine.js`).
     * Une valeur hors registre reste rendue EN CLAIR : une valeur inattendue
     * doit se voir — c'est exactement ainsi que ce defaut s'est montre.
     *
     * @var array<string, string>
     */
    public const ACTIVITES = [
        'M1' => 'Hébergement',
        'M4' => 'Restaurant',
        'M5' => 'Bar',
        'M8' => 'Véhicules',
        'M9' => 'Tourisme',
    ];

    /**
     * Les quatre statuts REELS de `factures.statut`, avec les couleurs du
     * maitre reparties selon ce qu'elles disent : vert pour l'aboutissement,
     * rouge pour l'echec, gris pour le provisoire.
     *
     * @var array<string, array{libelle: string, fond: string, texte: string}>
     */
    public const STATUTS = [
        'brouillon' => ['libelle' => 'brouillon', 'fond' => '#F3F4F6', 'texte' => '#6B7280'],
        'en_attente_certification' => ['libelle' => 'en attente de certification', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
        'certifiee' => ['libelle' => 'certifiée', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'],
        'echec_certification' => ['libelle' => 'échec de certification', 'fond' => '#FDECEC', 'texte' => '#C62828'],
    ];

    /** Recherche libre — PROPRIETE Livewire, jamais une methode (PA-67). */
    #[Url(as: 'q')]
    public string $recherche = '';

    /** Filtre d'activite : une valeur de `lignes_facture.source_module`. */
    #[Url(as: 'activite')]
    public string $activite = '';

    /**
     * La page courante — meme mecanisme que `Achats` : propriete `#[Url]`
     * passee EXPLICITEMENT en quatrieme argument de `paginate()`, jamais le
     * trait `WithPagination` (sept actions Livewire de plus sur le chemin que
     * `ForcerLectureSeule` ne couvre pas, PA-67).
     */
    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /**
     * La SELECTION du tableau — identifiants coches. Elle n'ecrit rien :
     * c'est le perimetre que l'export reprend, exactement ce que le conseil
     * de la modale d'export du maitre designe (« utilisez la case a cocher du
     * tableau pour n'exporter qu'une selection », `crud-ui.js` l.160).
     *
     * @var list<string>
     */
    public array $selection = [];

    /** La case d'entete du maitre (`crud-ui.js` l.66, `#crud-case-tout`). */
    public bool $toutSelectionne = false;

    /**
     * Le format choisi dans la modale d'export partagee — `pdf` (defaut) ou
     * `excel` (`pwa/partials/modale-export`).
     */
    public string $formatExport = 'pdf';

    /**
     * La case « tout selectionner » de l'entete — voir `Achats` : `updated*`
     * est un point d'entree du cadre, il n'ecrit que l'etat d'affichage.
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur
            ? $this->facturesEtClients()['factures']->getCollection()->pluck('id')->all()
            : [];
    }

    /**
     * Un filtre qui change remet la selection ET la page a leur depart —
     * sans cela, une selection faite sous un filtre precedent survivrait,
     * invisible, et l'export porterait sur des lignes que personne ne voit
     * (PA-119).
     *
     * @param  mixed  $valeur
     */
    public function updated(string $propriete, $valeur): void
    {
        if (in_array($propriete, ['recherche', 'activite'], true)) {
            $this->selection = [];
            $this->toutSelectionne = false;
            $this->pageCourante = 1;
        }
    }

    // --- Modale d'avoir (RG-03) ------------------------------------------

    public string $avoirFactureId = '';

    public string $avoirMontant = '';

    public string $avoirMotif = '';

    /**
     * Le registre FERME des formulaires de l'ecran.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'avoir' => ['avoirFactureId', 'avoirMontant', 'avoirMotif'],
        ];
    }

    // =====================================================================
    // RG-03 — l'avoir, unique chemin de correction
    // =====================================================================

    /**
     * Ouvre la modale d'avoir sur une facture du registre.
     *
     * Le droit est exige par `ouvrirFormulaire()` AVANT toute lecture :
     * presenter un formulaire a quelqu'un qui ne pourra pas le soumettre lui
     * fait perdre sa saisie et ne lui apprend rien.
     */
    public function ouvrirFormulaireAvoir(string $facture): void
    {
        $this->ouvrirFormulaire('avoir');

        $piece = Facture::query()->find($facture);

        if ($piece === null) {
            // Un identifiant inconnu est une erreur d'appel du composant, pas
            // une saisie : la modale se referme plutot que d'offrir un
            // formulaire qui ne pourrait viser aucune facture.
            $this->etatFormulaire = null;

            return;
        }

        $this->avoirFactureId = (string) $piece->id;
    }

    /**
     * Emet l'avoir par le Service de domaine.
     *
     * Le plafond — un avoir ne depasse jamais le TTC de sa facture — vit dans
     * `EmissionFactureService::emettreAvoir()`. La regle `max:` posee ici est
     * la meme borne rendue a l'ecran AVANT la soumission, jamais une seconde
     * verite : le service reste l'autorite, et c'est lui qui refuse.
     */
    public function enregistrerAvoir(EmissionFactureService $emission): void
    {
        $facture = Facture::query()->find($this->avoirFactureId);

        if ($facture === null) {
            $this->exigerEcriture(self::MODULE);
            $this->addError('avoirFactureId', __('facturation_pwa.avoir_introuvable'));

            return;
        }

        $valide = $this->validerEcriture([
            'avoirFactureId' => ['required', 'string'],
            'avoirMontant' => ['required', 'numeric', 'gt:0', 'max:'.(string) $facture->montant_ttc],
            'avoirMotif' => ['required', 'string', 'max:255'],
        ]);

        $montant = bcadd((string) $valide['avoirMontant'], '0', 2);

        $emission->emettreAvoir($facture, $montant, trim((string) $valide['avoirMotif']));

        $this->terminerFormulaire(__('facturation_pwa.avoir_emis', [
            'montant' => MontantFcfa::format($montant),
            'numero' => (string) ($facture->numero_mecef ?? MontantFcfa::TIRET),
        ]));
    }

    /**
     * LECTURE — fermer une modale ne touche aucune table. `exigerEcriture()`
     * y a vecu tant que le seul formulaire de l'ecran etait l'avoir (une
     * ecriture) ; depuis que la modale d'export s'ouvre aux roles en `L`
     * (02/09/2026), la garder aurait laisse un comptable ouvrir la modale
     * sans pouvoir la refermer — la meme lecon que `HistoriqueVentes`.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Le document A4 — et son filigrane
    // =====================================================================

    /**
     * Produit la facture au format A4.
     *
     * Le filigrane « DOCUMENT DE DEMONSTRATION » est commande par
     * `estCertifiee()`, jamais par `estFigee()` : une facture `MECEF-DEMO-`
     * passee a `certifiee` par le job de rejeu est figee, et elle n'a
     * pourtant AUCUNE valeur fiscale. C'est la troisieme obligation ouverte
     * de PA-124, qui n'avait jusqu'ici aucun document ou s'imprimer.
     */
    public function imprimerFacture(string $facture, ReportHeaderService $entetes): ?Response
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);

        $piece = Facture::query()->with(['lignes', 'avoirs', 'paiements'])->find($facture);

        if ($piece === null) {
            return null;
        }

        $avoirs = '0.00';

        foreach ($piece->avoirs as $avoir) {
            $avoirs = bcadd($avoirs, (string) $avoir->montant, 2);
        }

        $pdf = Pdf::loadView('pdf.facture-mecef', [
            'facture' => $piece,
            'client' => Client::query()->find($piece->client_id),
            'activites' => self::ACTIVITES,
            'modesPaiement' => VenteService::MODES_PAIEMENT,
            'totalAvoirs' => $avoirs,
            'net' => bcsub((string) $piece->montant_ttc, $avoirs, 2),
            // Autorite unique du reste du (PA-165) — jamais une seconde formule.
            'resteDu' => $piece->resteDu(),
            'auteur' => $utilisateur->login,
            // En-tete etablissement — source unique RG-19, jamais recopiee en dur.
            'entete' => $entetes->genererEnTete(
                typeRapport: __('facturation_pwa.document_titre'),
                periode: '',
                auteur: $utilisateur,
            ),
        ])->setPaper('a4', 'portrait');

        $nom = __('facturation_pwa.document_fichier').'_'
            .($piece->numero_mecef ?? substr((string) $piece->id, 0, 8)).'.pdf';

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom);
    }

    // =====================================================================

    /**
     * Les pièces AFFICHÉES et leurs clients, filtres compris — le SEUL
     * chemin qui les produit, appelé par `render()` ET par
     * `genererExport()`. PA-119 impose qu'un export porte sur ce qui est
     * affiché ; une deuxième requête ici ferait diverger l'écran et le
     * fichier au premier changement de filtre — exactement ce que la note du
     * fournisseur d'export nomme.
     *
     * @return array{requete: \Illuminate\Database\Eloquent\Builder<Facture>, activite: string, terme: string, total: int, factures: \Illuminate\Pagination\LengthAwarePaginator<int, Facture>, clients: \Illuminate\Support\Collection<string, Client>, montant: string}
     */
    private function facturesEtClients(): array
    {
        $activite = array_key_exists($this->activite, self::ACTIVITES) ? $this->activite : '';
        $terme = trim($this->recherche);

        // ⚠ `Facture` N'A PAS DE RELATION `client()`, alors que
        // `factures.client_id` est une vraie cle etrangere — releve le
        // 27/08/2026 sur `App\Domain\Facturation\Models\Facture`, qui ne
        // declare que `lignes()` et `avoirs()`. Les noms sont donc charges en
        // UNE requete et indexes par identifiant, plutot que ligne par ligne :
        // un `Client::find()` dans la boucle ferait une requete par facture.
        // L'absence de relation est signalee au rapport, pas comblee ici —
        // `app/Domain/**` est hors du perimetre de ce lot.
        $requete = Facture::query()->with(['lignes', 'avoirs']);

        if ($activite !== '') {
            $requete->whereHas('lignes', static function ($l) use ($activite): void {
                $l->where('source_module', $activite);
            });
        }

        if ($terme !== '') {
            // Meme portee que le maitre (l.168) : le numero et le nom du
            // client.
            $clientsTrouves = Client::query()
                ->where('nom', 'like', '%' . $terme . '%')
                ->orWhere('prenom', 'like', '%' . $terme . '%')
                ->pluck('id');

            $requete->where(function ($sous) use ($terme, $clientsTrouves): void {
                $sous->where('numero_mecef', 'like', '%' . $terme . '%')
                    ->orWhereIn('client_id', $clientsTrouves);
            });
        }

        $total = (clone $requete)->count();

        // PAGINATION du maitre (`crud-engine.js` l.21) — page courante lue de
        // la propriete `#[Url]`, jamais du resolveur implicite (voir `Achats`).
        $factures = (clone $requete)
            ->orderByDesc('date_emission')->orderByDesc('id')
            ->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));

        // Le montant est somme en `bcadd` sur les CHAINES rendues par PDO,
        // jamais par `sum()` sur des flottants : quinze chiffres significatifs
        // depassent la precision d'un double, et l'ecart se verrait d'abord sur
        // les plus gros totaux. Il porte sur le JEU FILTRE ENTIER, pas sur la
        // page affichee : un KPI qui changerait en tournant les pages dirait
        // deux verites sur le meme filtre.
        $montant = '0.00';

        foreach ((clone $requete)->pluck('montant_ttc') as $ttc) {
            $montant = bcadd($montant, (string) $ttc, 2);
        }

        /** @var \Illuminate\Support\Collection<string, Client> $clients */
        $clients = Client::query()
            ->whereIn('id', $factures->pluck('client_id')->unique()->all())
            ->get()
            ->keyBy('id');

        return compact('requete', 'activite', 'terme', 'total', 'factures', 'clients', 'montant');
    }

    /**
     * Ouvre la modale d'export partagée — LECTURE (`METHODES_DE_LECTURE`).
     *
     * ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026 : le « Export
     * Excel » direct (`m2-facturation.html` l.112-113) devient UN bouton
     * « Exporter » ouvrant la modale partagée, où le format se choisit.
     * Voir le docblock de classe et `DerogationsMaquette`
     * (export_bouton_unique).
     */
    public function ouvrirExport(): void
    {
        $this->resetValidation();
        $this->etatFormulaire = 'export';
    }

    /**
     * Produit le document choisi (PDF A4 / Excel) sur les pièces AFFICHÉES
     * (PA-119) — LECTURE : un export ne produit rien de neuf.
     *
     * Le PDF est le REGISTRE de l'écran — jamais une facture : le document
     * fiscal individuel reste `imprimerFacture()` (« Facture A4 », par
     * ligne). Une liste vide se REFUSE.
     */
    public function genererExport(ReportHeaderService $entetes): mixed
    {
        ['requete' => $requete] = $this->facturesEtClients();

        // Le JEU FILTRE ENTIER, pas la page courante : le maitre exporte ce
        // que le filtre retient, et la selection — quand elle existe — le
        // restreint encore (« utilisez la case a cocher du tableau pour
        // n'exporter qu'une selection », `crud-ui.js` l.160).
        $factures = (clone $requete)
            ->when($this->selection !== [], fn ($q) => $q->whereIn('id', $this->selection))
            ->orderByDesc('date_emission')->orderByDesc('id')
            ->get();

        if ($factures->isEmpty()) {
            $this->etatFormulaire = null;
            $this->addError('export', __('pwa.facturation.export_vide'));

            return null;
        }

        $clients = Client::query()
            ->whereIn('id', $factures->pluck('client_id')->unique()->all())
            ->get()
            ->keyBy('id');

        $this->etatFormulaire = null;
        $nom = 'facturation_'.now()->format('Ymd_His');

        if ($this->formatExport === 'excel') {
            return Excel::download(new FacturationExport($factures, $clients), $nom.'.xlsx');
        }

        // Le total du document est somme en bcadd sur les CHAINES, comme le
        // compteur de l'ecran — jamais `sum()` sur des flottants.
        $montant = '0.00';

        foreach ($factures as $piece) {
            $montant = bcadd($montant, (string) $piece->montant_ttc, 2);
        }

        $pdf = Pdf::loadView('pdf.facturation-registre', [
            'factures' => $factures,
            'clients' => $clients,
            'activites' => self::ACTIVITES,
            'statuts' => self::STATUTS,
            'montant' => $montant,
            'filtre' => $this->descriptionDuFiltre($factures->count()),
            // En-tete etablissement — source unique RG-19, meme chemin que
            // `imprimerFacture()`.
            'entete' => $entetes->genererEnTete(
                typeRapport: __('pwa.facturation.export_document'),
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
     * sélection comprise, et « Aucun filtre » se dit aussi, jamais rien.
     */
    private function descriptionDuFiltre(int $nombre): string
    {
        $parts = [];
        $terme = trim($this->recherche);

        if ($terme !== '') {
            $parts[] = __('pwa.facturation.export_filtre_recherche', ['terme' => $terme]);
        }

        if ($this->activite !== '' && isset(self::ACTIVITES[$this->activite])) {
            $parts[] = __('pwa.facturation.export_filtre_activite', [
                'valeur' => self::ACTIVITES[$this->activite],
            ]);
        }

        if ($this->selection !== []) {
            $parts[] = __('pwa.facturation.export_filtre_selection', ['nombre' => $nombre]);
        }

        return $parts === [] ? __('pwa.facturation.export_filtre_aucun') : implode(' · ', $parts);
    }

    public function render(): View
    {
        [
            'activite' => $activite,
            'terme' => $terme,
            'total' => $total,
            'factures' => $factures,
            'clients' => $clients,
            'montant' => $montant,
        ] = $this->facturesEtClients();

        return view('pwa.facturation.facturation', array_merge($this->socle(), [
            'clients' => $clients,
            'factures' => $factures,
            'total' => $total,
            'montant' => $montant,
            // Le decompte d'avoirs porte sur les pieces AFFICHEES, comme le
            // reste de la bande : un compteur global sous une liste filtree
            // ferait croire que le filtre n'a rien ecarte (PA-119).
            'avoirs' => Avoir::query()->whereIn('facture_id', $factures->getCollection()->pluck('id')->all())->count(),
            // DERIVE des pieces, jamais fige (PA-119, PA-61, PA-100).
            'certifiees' => $factures->getCollection()->filter(fn (Facture $f): bool => $f->estCertifiee())->count(),
            'activiteAppliquee' => $activite,
            // La facture visee par la modale d'avoir : son TTC est le plafond
            // annonce a l'ecran AVANT la saisie. `null` tant qu'aucune modale
            // n'est ouverte — la vue ne rend alors rien.
            'avoirFacture' => $this->avoirFactureId === '' ? null : Facture::query()->find($this->avoirFactureId),
            'filtreApplique' => $terme !== '' || $activite !== '',
            // PA-119 — le sous-titre de la modale d'export DIT le filtre.
            'filtreExport' => $this->descriptionDuFiltre(count($this->selection)),
            // `data-module="M2"` — celui du `<body>` du maitre (l.16).
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }
}
