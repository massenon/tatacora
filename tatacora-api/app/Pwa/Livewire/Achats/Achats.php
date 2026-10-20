<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Achats;

use App\Domain\Achats\Http\Requests\EnregistrerFournisseurRequest;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Exports\AchatsExport;
use App\Exports\FournisseursExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\AutoriseArchivage;
use App\Pwa\Support\ExerciceConsulte;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Fournisseurs & Achats (M7) — maître : `prototype_v2/pages/m7-achats.html`.
 *
 * ## Ce que le maître pose ici, et ce qu'il ne pose PAS
 *
 * DEUX onglets, pas quatre : « Fournisseurs » et « Commandes d'achat ». Le
 * maître écrit lui-même, en tête de `m7-approvisionnement.html` (l.75-81), que
 * cette page « n'est qu'un annuaire fournisseurs […] sans aucune commande ni
 * réception » et que « le cycle complet est [là-bas] ». Les onglets « Bons de
 * réception » et « Dettes fournisseurs » que cet écran portait n'existent sur
 * aucune de ses deux configurations : ils DUPLIQUAIENT l'écran
 * Approvisionnement, à deux jeux de requêtes et deux rendus près.
 *
 * ## La PREMIÈRE écriture de la PWA vit ici — EF-M7-01
 *
 * « Ajouter fournisseur » est le motif de référence du plan CRUD : le trait
 * `FormulaireModal` porte les gestes (droit exigé À L'OUVERTURE et à
 * l'enregistrement, remise à zéro de la saisie, fermeture + message), et cet
 * écran ne fait que les appeler. Les règles de validation sont LUES dans
 * `EnregistrerFournisseurRequest` — celles de l'API, jamais une seconde liste
 * écrite à la main qui resterait verte le jour où l'API durcirait une
 * contrainte.
 *
 * ## Ce que cet écran refuse, avec sa raison DATÉE
 *
 * Le formulaire « Commandes d'achat » du maître demande un « Montant estimé
 * (FCFA) » SAISI. `commandes_achat` n'a aucune colonne de montant qu'un chemin
 * de ce dépôt écrive, et `CommandeAchat::montantTotal()` somme les lignes en
 * `bcadd`. Une commande se crée donc là où ses lignes existent — l'écran
 * Approvisionnement, depuis les besoins. Les autres refus (suppression,
 * import, duplication) sont nommés à l'écran, chacun daté du 31/08/2026.
 *
 * ## La pagination n'est PAS `WithPagination`, et c'est mesuré
 *
 * Le trait ajouterait sept méthodes publiques, donc sept actions Livewire, sur
 * le chemin que `ForcerLectureSeule` ne couvre pas (PA-67) — même arbitrage
 * qu'en `Etats` et `JournalAudit`, à ceci près qu'ici la liste est réellement
 * paginée plutôt que tronquée.
 *
 * La page courante est une propriété `#[Url]` passée EXPLICITEMENT en
 * quatrième argument de `paginate()`. C'est ce qui la rend fiable des deux
 * côtés : `->links()` rend de vrais liens `?page=N`, relus par `#[Url]` au
 * chargement suivant, et une action Livewire — qui n'emporte pas la chaîne de
 * requête — repart de la même propriété plutôt que de retomber à la page 1
 * sans le dire. S'en remettre au résolveur de page de Laravel aurait justement
 * produit ce retour silencieux au début de liste.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 * @see EF-M7-02 Émission de commandes d'achat (lecture ici, écriture en Approvisionnement)
 * @see RG-15 Journalisation (trait Auditable sur Fournisseur)
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 4, 6, 7, 8
 */
#[Title('Fournisseurs & Achats — TATACORA AFRIQUE')]
class Achats extends PageMetier
{
    use AutoriseArchivage;
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M7"` du maître (l.16). */
    public const MODULE = 'M7';

    /** Les DEUX onglets du maître (`m7-achats.html` l.31-32). */
    public const ONGLETS = ['fournisseurs', 'commandes'];

    /**
     * Les libellés du maître pour l'`enum` `fournisseurs.evaluation`.
     *
     * Le maître filtre et affiche « Excellent », « À revoir » ; la base stocke
     * `excellent`, `a_revoir`. La traduction vit ICI, à un seul endroit : deux
     * tables de correspondance auraient fini par diverger, et un filtre
     * incompris rendrait la liste entière sous un intitulé promettant le
     * contraire.
     *
     * Couleurs : `m7-achats.html` l.106-123.
     *
     * @var array<string, array{libelle: string, fond: string, texte: string}>
     */
    public const EVALUATIONS = [
        'excellent' => ['libelle' => 'Excellent', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'],
        'bon' => ['libelle' => 'Bon', 'fond' => '#E8EEFD', 'texte' => '#1D4ED8'],
        'moyen' => ['libelle' => 'Moyen', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
        'a_revoir' => ['libelle' => 'À revoir', 'fond' => '#FDECEC', 'texte' => '#C62828'],
    ];

    /**
     * Les statuts de commande, avec les libellés et couleurs du maître
     * (`m7-achats.html` l.266-270).
     *
     * @var array<string, array{libelle: string, fond: string, texte: string}>
     */
    public const STATUTS = [
        'brouillon' => ['libelle' => 'Brouillon', 'fond' => '#F3F4F6', 'texte' => '#6B7280'],
        'envoyee' => ['libelle' => 'Envoyée', 'fond' => '#E8EEFD', 'texte' => '#1D4ED8'],
        'receptionnee_partiellement' => ['libelle' => 'Réceptionnée partiellement', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
        'receptionnee' => ['libelle' => 'Réceptionnée', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'],
        'cloturee' => ['libelle' => 'Clôturée', 'fond' => '#F3F4F6', 'texte' => '#6B7280'],
    ];

    /**
     * Les CINQ catégories et les TROIS conditions du formulaire du maître
     * (`m7-achats.html` l.153-170).
     *
     * ⚠ Ce sont des SUGGESTIONS, pas un registre fermé :
     * `EnregistrerFournisseurRequest` les laisse en chaîne libre, et son
     * docblock dit pourquoi — fermer la liste rendrait inmodifiable tout
     * fournisseur déjà enregistré hors d'elle. La vue rend donc un `<select>`
     * qui accepte aussi « Non renseigné ».
     *
     * @var list<string>
     */
    public const CATEGORIES = ['Denrées alimentaires', 'Boissons', 'Fournitures', 'Carburant', 'Pièces auto'];

    /** @var list<string> */
    public const CONDITIONS_PAIEMENT = ['Comptant', '30 jours', '60 jours'];

    /** Lignes par page — le maître pagine, il ne tronque pas. */
    public const PAR_PAGE = 25;

    #[Url(as: 'onglet')]
    public string $onglet = 'fournisseurs';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'evaluation')]
    public string $evaluation = '';

    #[Url(as: 'statut')]
    public string $statut = '';

    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /**
     * La SÉLECTION du tableau — identifiants cochés.
     *
     * Elle n'écrit rien : c'est le périmètre que l'export reprendra, et c'est
     * exactement ce que le conseil de la modale d'export du maître désigne
     * (« utilisez la case à cocher du tableau pour n'exporter qu'une
     * sélection », `crud-ui.js` l.160).
     *
     * @var list<string>
     */
    public array $selection = [];

    /** La case d'entête du maître (`crud-ui.js` l.66, `#crud-case-tout`). */
    public bool $toutSelectionne = false;

    /** La fiche ouverte par « Voir le détail » — `null` : aucune. */
    public ?string $detailId = null;

    /** Format demandé à la modale d'export partagée : `pdf` ou `excel`. */
    public string $formatExport = 'pdf';

    // --- Formulaire fournisseur (EF-M7-01) -------------------------------

    /** L'identifiant modifié — `null` en création. */
    public ?string $fId = null;

    public string $fRaisonSociale = '';

    public string $fContact = '';

    public string $fCategorie = '';

    public string $fConditionsPaiement = '';

    public string $fEvaluation = '';

    // --- Archivage du référentiel (directive PO du 03/09/2026) ------------
    //
    // « Supprimer = archiver » : le geste passe `fournisseurs.actif` à `false`
    // par `ReferentielFournisseurService::archiver()` — jamais un `delete()`
    // (`commandes_achat.fournisseur_id` est `restrictOnDelete`, et effacer la
    // fiche rendrait illisible chaque commande qui la cite). La sélection
    // multiple reprend le motif déjà présent sur cet écran (case d'entête +
    // cases de ligne), qui ne servait jusqu'ici qu'à l'export.

    /** @var list<string> Les fournisseurs retenus par la modale de confirmation. */
    public array $fournisseursAArchiver = [];

    /** @var list<string> Les motifs de blocage affichés dans la modale. */
    public array $verrousArchivage = [];

    /** Vrai quand TOUT le lot est engagé : le bouton de confirmation disparaît. */
    public bool $archivageBloque = false;

    /** Nombre d'éléments qui resteront (état PARTIEL du maître). */
    public int $conservesArchivage = 0;

    /** Le nom de l'élément visé quand le lot n'en compte qu'un. */
    public string $libelleArchivage = '';

    /**
     * Le registre FERMÉ des formulaires de l'écran (contrat de
     * `FormulaireModal`).
     *
     * `fId` en fait partie : sans lui, rouvrir « Ajouter » après une
     * modification écraserait le fournisseur précédent au lieu d'en créer un.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'fournisseur' => ['fId', 'fRaisonSociale', 'fContact', 'fCategorie', 'fConditionsPaiement', 'fEvaluation'],
            'archivage' => [
                'fournisseursAArchiver', 'verrousArchivage', 'archivageBloque',
                'conservesArchivage', 'libelleArchivage',
            ],
        ];
    }

    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'fournisseurs';
    }

    /**
     * La case « tout sélectionner » de l'entête.
     *
     * `updated*` est un point d'entrée du cadre Livewire : il n'écrit rien
     * d'autre que l'état d'affichage du composant. La propriété est déclarée
     * `bool`, et c'est le cadre qui la convertit avant d'appeler ce point
     * d'entrée — inutile de relire une chaîne « 1 » ici.
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur ? $this->identifiantsAffiches() : [];
    }

    /**
     * Un filtre qui change remet la sélection ET la page à leur départ.
     *
     * Sans cela, une sélection faite sur un filtre précédent survivrait,
     * invisible, et l'export porterait sur des lignes que personne ne voit —
     * exactement ce que PA-119 interdit.
     *
     * @param  mixed  $valeur
     */
    public function updated(string $propriete, $valeur): void
    {
        if (in_array($propriete, ['recherche', 'evaluation', 'statut', 'onglet'], true)) {
            $this->selection = [];
            $this->toutSelectionne = false;
            $this->pageCourante = 1;
        }
    }

    // =====================================================================
    // EF-M7-01 — l'écriture, et sa garde
    // =====================================================================

    /**
     * Ouvre le formulaire fournisseur — en création, ou sur une fiche
     * existante quand un identifiant est donné (« Modifier », depuis la liste
     * comme depuis la modale de détail du maître).
     *
     * Le droit est exigé par `ouvrirFormulaire()` AVANT toute lecture :
     * présenter un formulaire à quelqu'un qui ne pourra pas le soumettre lui
     * fait perdre sa saisie et ne lui apprend rien.
     */
    public function ouvrirFormulaireFournisseur(?string $id = null): void
    {
        $this->ouvrirFormulaire('fournisseur');

        if ($id === null) {
            return;
        }

        $fournisseur = Fournisseur::query()->find($id);

        if ($fournisseur === null) {
            // Un identifiant inconnu est une erreur d'appel du composant, pas
            // une saisie : le formulaire reste en création plutôt que de
            // prétendre modifier une fiche absente.
            return;
        }

        $this->fId = $fournisseur->id;
        $this->fRaisonSociale = (string) $fournisseur->raison_sociale;
        $this->fContact = (string) ($fournisseur->contact ?? '');
        $this->fCategorie = (string) ($fournisseur->categorie ?? '');
        $this->fConditionsPaiement = (string) ($fournisseur->conditions_paiement ?? '');
        $this->fEvaluation = (string) ($fournisseur->evaluation ?? '');
        $this->detailId = null;
    }

    /**
     * Enregistre le fournisseur — création ou modification, par le Service de
     * domaine, jamais par de l'Eloquent réécrit ici (LARAVEL_PWA.md §3).
     *
     * ⚠ Les champs vides deviennent `null`, pas `''` : `evaluation` est un
     * `enum` MySQL qu'une chaîne vide ferait rejeter par la BASE, avec un
     * message SQL illisible plutôt qu'une erreur lisible — et surtout,
     * « pas encore évalué » n'est pas « À revoir ».
     */
    public function enregistrerFournisseur(ReferentielFournisseurService $referentiel): void
    {
        $regles = (new EnregistrerFournisseurRequest())->rules();

        // Les règles de l'API, transposées aux noms de propriétés de l'écran.
        // Le pont est vérifié par un test : une seconde liste écrite à la main
        // resterait verte le jour où l'API durcirait une contrainte.
        $this->validerEcriture([
            'fRaisonSociale' => $regles['raison_sociale'],
            'fContact' => $this->sansSometimes($regles['contact']),
            'fCategorie' => $this->sansSometimes($regles['categorie']),
            'fConditionsPaiement' => $this->sansSometimes($regles['conditions_paiement']),
            'fEvaluation' => $this->sansSometimes($regles['evaluation']),
        ]);

        $donnees = [
            'raison_sociale' => trim($this->fRaisonSociale),
            'contact' => $this->ouNull($this->fContact),
            'categorie' => $this->ouNull($this->fCategorie),
            'conditions_paiement' => $this->ouNull($this->fConditionsPaiement),
            'evaluation' => $this->ouNull($this->fEvaluation),
        ];

        $existant = $this->fId === null ? null : Fournisseur::query()->find($this->fId);

        if ($existant !== null) {
            $referentiel->modifier($existant, $donnees);
            $this->terminerFormulaire(__('achats_pwa.achats.modifie', ['nom' => $donnees['raison_sociale']]));

            return;
        }

        $referentiel->creer($donnees);
        $this->terminerFormulaire(__('achats_pwa.achats.cree', ['nom' => $donnees['raison_sociale']]));
    }

    // =====================================================================
    // Archivage du référentiel — « supprimer = archiver » (PO, 03/09/2026)
    // =====================================================================

    /**
     * Ouvre la confirmation d'archivage — une ligne, ou la sélection entière.
     *
     * Le droit d'ARCHIVER est exigé DÈS l'ouverture, en plus du droit
     * d'écriture posé par `ouvrirFormulaire()` : sans lui, un `magasinier`
     * bascule fermée ouvrirait une modale que l'exécution refuserait en 403.
     *
     * La sélection porte sur CE QUI EST AFFICHÉ (même règle que l'export,
     * PA-119) : cocher tout le référentiel puis changer de filtre ne doit pas
     * archiver des lignes que l'écran ne montre plus.
     */
    public function confirmerArchivageFournisseur(?string $id = null): void
    {
        $this->exigerArchivage();

        $ids = $id !== null
            ? [$id]
            : array_values(array_intersect($this->selection, $this->identifiantsAffiches()));

        if ($ids === []) {
            return;
        }

        // `ouvrirFormulaire` (droit + remise à zéro) AVANT de poser le lot :
        // il réinitialise les propriétés du registre, dont celles-ci.
        $this->ouvrirFormulaire('archivage');

        $referentiel = app(ReferentielFournisseurService::class);
        $lot = $this->composerLotArchivage(
            Fournisseur::query()->whereIn('id', $ids)->where('actif', true)->orderBy('raison_sociale')->get(),
            static function (Fournisseur $f) use ($referentiel): array {
                $engagements = $referentiel->engagements($f);

                return $engagements->isEmpty() ? [] : [(string) __('achats_pwa.archivage.verrou', [
                    'nombre' => $engagements->count(),
                ])];
            },
            static fn (Fournisseur $f): string => (string) $f->raison_sociale,
        );

        $this->fournisseursAArchiver = $lot['ids'];
        $this->verrousArchivage = $lot['motifs'];
        $this->archivageBloque = $lot['bloque'];
        $this->conservesArchivage = $lot['conserves'];
        $this->libelleArchivage = $lot['libelle'];
    }

    /**
     * Archive le lot confirmé — par le SERVICE, jamais un `update()` écrit ici.
     *
     * Un refus du service (une commande née entre l'ouverture et le clic)
     * s'affiche et n'empêche PAS les autres archivages du lot : perdre le lot
     * entier pour une ligne devenue engagée serait le refus d'opération de
     * PA-65 appliqué à l'envers.
     */
    public function archiverFournisseurs(ReferentielFournisseurService $referentiel): void
    {
        $this->exigerArchivage();

        if ($this->fournisseursAArchiver === []) {
            return;
        }

        $archives = 0;

        foreach (Fournisseur::query()->whereIn('id', $this->fournisseursAArchiver)->get() as $fournisseur) {
            try {
                $referentiel->archiver($fournisseur);
                $archives++;
            } catch (RuntimeException $refus) {
                $this->addError('archivage', $refus->getMessage());
            }
        }

        $this->fournisseursAArchiver = [];
        $this->selection = [];
        $this->toutSelectionne = false;
        $this->etatFormulaire = null;

        if ($archives > 0) {
            session()->flash('pwa-succes', trans_choice('achats_pwa.archivage.succes', $archives, [
                'nombre' => $archives,
            ]));
        }
    }

    /**
     * Le pendant de l'archivage.
     *
     * ⚠ Il n'est PAS derrière `exigerArchivage()`, délibérément : restaurer
     * n'est pas supprimer — fermer la bascule pendant qu'un fournisseur est
     * aux archives ne doit jamais l'y enfermer (« reste restaurable » serait
     * sinon une promesse que rien ne tient, PA-59/60/61). Même arbitrage que
     * `Hebergement::restaurerUnite()`.
     */
    public function restaurerFournisseur(string $id, ReferentielFournisseurService $referentiel): void
    {
        $this->exigerEcriture(self::MODULE);

        $fournisseur = Fournisseur::findOrFail($id);
        $referentiel->restaurer($fournisseur);

        session()->flash('pwa-succes', __('achats_pwa.archivage.restaure', [
            'nom' => (string) $fournisseur->raison_sociale,
        ]));
    }

    // =====================================================================
    // Export — PA-119 : ce qui est AFFICHÉ, et il DIT son filtre
    // =====================================================================

    /**
     * Ferme la modale ouverte.
     *
     * Requise par le châssis d'export partagé
     * (`pwa/partials/modale-export.blade.php`), qui la nomme. Elle ne touche
     * que l'état d'affichage du composant.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->detailId = null;
    }

    /**
     * Produit le document — sur les lignes SÉLECTIONNÉES si la case à cocher
     * du tableau en désigne, sur la liste filtrée sinon.
     *
     * Une liste vide se REFUSE : une page blanche ne dirait pas si le filtre
     * est trop étroit ou si la donnée n'existe pas.
     */
    public function genererExport(): ?Response
    {
        $onglet = $this->ongletValide();
        $lignes = $onglet === 'fournisseurs'
            ? $this->requeteFournisseurs()->when($this->selection !== [], fn (Builder $q) => $q->whereIn('id', $this->selection))->get()
            : $this->requeteCommandes()->when($this->selection !== [], fn (Builder $q) => $q->whereIn('id', $this->selection))->get();

        if ($lignes->isEmpty()) {
            $this->addError('formatExport', __('achats_pwa.export.vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $horodatage = now()->format('Y_m_d_His');

        if ($this->formatExport === 'excel') {
            $classeur = $onglet === 'fournisseurs'
                ? new FournisseursExport($lignes)
                : new AchatsExport($lignes);

            /** @var Response $reponse */
            $reponse = Excel::download(
                $classeur,
                ($onglet === 'fournisseurs' ? __('achats_pwa.export.fichier_fournisseurs') : __('achats_pwa.export.fichier_commandes')).'_'.$horodatage.'.xlsx',
            );

            return $reponse;
        }

        $vue = $onglet === 'fournisseurs' ? 'pdf.fournisseurs-liste' : 'pdf.achats';
        $entete = $this->enTeteRapport(
            $onglet === 'fournisseurs' ? __('achats_pwa.export.document_fournisseurs') : __('achats_pwa.export.document_commandes'),
            $this->descriptionDuFiltre(),
        );
        $donnees = $onglet === 'fournisseurs'
            ? ['entete' => $entete, 'lignes' => $lignes, 'auteur' => $this->auteur(), 'filtre' => $this->descriptionDuFiltre()]
            : ['entete' => $entete, 'commandes' => $lignes, 'auteur' => $this->auteur(), 'filtre' => $this->descriptionDuFiltre()];

        $pdf = Pdf::loadView($vue, $donnees)->setPaper('a4', 'portrait');
        // Cle LITTERALE de chaque cote du ternaire, jamais concatenee :
        // une cle construite est invisible a `grep` et a la garde i18n, qui
        // ne peut plus prouver qu'elle existe (mesure du 31/08/2026).
        $nom = ($onglet === 'fournisseurs' ? __('achats_pwa.export.fichier_fournisseurs') : __('achats_pwa.export.fichier_commandes')).'_'.$horodatage.'.pdf';

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom);
    }

    // =====================================================================

    public function render(): View
    {
        $onglet = $this->ongletValide();

        $fournisseurs = $this->requeteFournisseurs()->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));
        $commandes = $this->requeteCommandes()->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));

        return view('pwa.achats.achats', array_merge($this->socle(), [
            'onglet' => $onglet,
            'fournisseurs' => $fournisseurs,
            'commandes' => $commandes,
            'detail' => $this->detailId === null ? null : Fournisseur::query()->find($this->detailId),
            'peutEcrire' => (Auth::user()?->niveauSurModule(self::MODULE) ?? '-') === 'C',
            // La vue ne rejoue JAMAIS la règle d'archivage : elle la reçoit
            // (voir `AutoriseArchivage` — un seul auteur, deux lecteurs).
            'peutArchiver' => $this->peutArchiver(),
            'descriptionFiltre' => $this->descriptionDuFiltre(),
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // ------------------------------------------------------------- requêtes

    /**
     * @return Builder<Fournisseur>
     */
    private function requeteFournisseurs(): Builder
    {
        $terme = trim($this->recherche);

        return Fournisseur::query()
            // `colonnesRecherchables` du maître (l.69-72) : raison sociale et
            // contact, jamais toutes les colonnes.
            ->when($terme !== '', static fn (Builder $q): Builder => $q->where(
                static fn (Builder $sous): Builder => $sous
                    ->where('raison_sociale', 'like', '%'.$terme.'%')
                    ->orWhere('contact', 'like', '%'.$terme.'%'),
            ))
            ->when(
                array_key_exists($this->evaluation, self::EVALUATIONS),
                fn (Builder $q): Builder => $q->where('evaluation', $this->evaluation),
            )
            ->orderBy('raison_sociale')
            // Départ STABLE : deux fournisseurs homonymes se partageraient
            // sinon un rang indéterminé d'une page à l'autre.
            ->orderBy('id');
    }

    /**
     * @return Builder<CommandeAchat>
     */
    private function requeteCommandes(): Builder
    {
        $terme = trim($this->recherche);

        // `lignes` est chargé d'avance : `montantTotal()` les parcourt, et une
        // page de 25 commandes en ferait 25 requêtes de plus sans cela.
        // Sélecteur d'exercice global (PO, 20/10/2026) : les commandes PASSÉES
        // dans l'exercice consulté.
        return ExerciceConsulte::borner(CommandeAchat::query(), 'date_commande')
            ->with(['fournisseur', 'lignes'])
            ->when($terme !== '', static fn (Builder $q): Builder => $q->whereHas(
                'fournisseur',
                static fn (Builder $f): Builder => $f->where('raison_sociale', 'like', '%'.$terme.'%'),
            ))
            ->when(
                array_key_exists($this->statut, self::STATUTS),
                fn (Builder $q): Builder => $q->where('statut', $this->statut),
            )
            ->orderByDesc('date_commande')
            ->orderBy('id');
    }

    /**
     * Les identifiants de la PAGE affichée — c'est ce que « tout
     * sélectionner » sélectionne au maître, jamais le registre entier.
     *
     * @return list<string>
     */
    private function identifiantsAffiches(): array
    {
        $requete = $this->ongletValide() === 'fournisseurs'
            ? $this->requeteFournisseurs()
            : $this->requeteCommandes();

        /** @var list<string> $ids */
        $ids = $requete
            ->forPage(max(1, $this->pageCourante), self::PAR_PAGE)
            ->pluck('id')
            ->map(static fn (mixed $id): string => (string) $id)
            ->all();

        return $ids;
    }

    /**
     * La phrase qui DIT sur quoi porte l'export (PA-119).
     */
    private function descriptionDuFiltre(): string
    {
        if ($this->selection !== []) {
            return __('achats_pwa.export.sous_titre_selection', ['nombre' => count($this->selection)]);
        }

        $total = $this->ongletValide() === 'fournisseurs'
            ? $this->requeteFournisseurs()->count()
            : $this->requeteCommandes()->count();

        return __('achats_pwa.export.sous_titre_filtre', ['nombre' => $total]);
    }

    private function auteur(): string
    {
        $utilisateur = Auth::user();

        return $utilisateur === null ? '' : (string) $utilisateur->login;
    }

    /**
     * `sometimes` n'a de sens que sur une requête HTTP où la clé peut manquer.
     * Une propriété Livewire est TOUJOURS présente : la garder ferait sauter
     * la règle entière si la valeur était vide.
     *
     * @param  array<int, mixed>  $regles
     * @return array<int, mixed>
     */
    private function sansSometimes(array $regles): array
    {
        return array_values(array_filter($regles, static fn (mixed $r): bool => $r !== 'sometimes'));
    }

    private function ouNull(string $valeur): ?string
    {
        $propre = trim($valeur);

        return $propre === '' ? null : $propre;
    }
}
