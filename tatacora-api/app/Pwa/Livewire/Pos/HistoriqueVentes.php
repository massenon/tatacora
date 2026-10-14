<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Pos;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Exports\VentesExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Journal des ventes — maitre : prototype_v2/pages/historique-ventes.html.
 *
 * ## P2 — l'ecran lisait une table que personne n'ecrivait
 *
 * `HistoriqueVentes` interrogeait `ventes` pendant que `PosComptant` ecrivait
 * `ventes_bar`. Le journal n'affichait donc que les trois lignes du seeder —
 * et l'ecran etait PLEIN, ce qui est la raison pour laquelle personne n'a vu
 * qu'il manquait tout le reste. Les deux points de vente ecrivent desormais
 * `ventes` par `VenteService`, et cet ecran lit ce meme registre.
 *
 * ## P5 — une vente s'ANNULE, elle ne se supprime pas
 *
 * L'annulation passe par `VenteService::annuler()` : motif obligatoire,
 * horodatage, compensation de stock par mouvement inverse, et la vente reste
 * au journal avec son numero (RG-02). Aucune suppression Eloquent n'existe ici.
 *
 * ## PA-119 — un export porte sur CE QUI EST AFFICHE, et il DIT son filtre
 *
 * L'export reprend exactement les filtres de l'ecran et les ecrit sur le
 * document. Quelqu'un qui filtre puis exporte attend son filtre : lui rendre
 * le registre entier lui ferait envoyer au comptable un document qu'il croit
 * avoir verifie. Une liste vide se REFUSE — une page blanche ne dit pas si le
 * filtre est trop etroit ou si la donnee n'existe pas.
 *
 * ## Ce qui est PILOTE PAR `$set`, et pourquoi
 *
 * Ouvrir et fermer la modale de detail ne touche aucune table : ce sont des
 * expressions `$set`, pas des actions du composant. Cet ecran n'est protege
 * par aucun middleware `module:` — il est le journal de caisse, que le
 * comptable et la gerance doivent pouvoir consulter. En faire des methodes
 * gardees leur en interdirait la lecture.
 *
 * @see RG-02 Aucune suppression
 * @see RG-19 Tout export passe par un gabarit unique
 */
#[Layout('layouts.pwa')]
#[Title('Historique des ventes — TATACORA AFRIQUE')]
class HistoriqueVentes extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'ecran : le journal des ventes du comptoir. */
    public const MODULE = 'M5';

    private const PRECISION_MONTANT = 2;

    /**
     * La pagination du tableau d'ecran — decision du Product Owner du
     * 13/10/2026 (« pour que les deux applications restent identiques ») :
     * dix ventes par page, comme le client Flutter et le pied « Reservations
     * en cours » de l'hebergement. AJOUT a la vue maitre, qui rendait tout le
     * journal d'un bloc.
     *
     * Seul le TABLEAU D'ECRAN est pagine : les cinq indicateurs, l'export et
     * le document imprime portent toujours sur la liste FILTREE ENTIERE (une
     * page n'est pas un filtre, PA-119).
     *
     * Meme mecanique que la grille du parc d'hebergement : une propriete
     * PUBLIQUE pilotee par `$set('page', …)` depuis la vue, jamais
     * `WithPagination` (sept methodes publiques de plus, PA-67).
     */
    public const VENTES_PAR_PAGE = 10;

    public int $page = 1;

    /**
     * L'empreinte des filtres au dernier rendu : un filtre CHANGE ramene a la
     * page 1 (comme le client Flutter). Rester en page 3 d'un resultat qui
     * n'en a plus qu'une montrerait un tableau vide sous un filtre qui trouve
     * pourtant des ventes. Une propriete plutot qu'un crochet `updated…()` :
     * un crochet est une methode publique de plus (`PwaActionsReluesTest`).
     */
    public string $empreinteFiltres = '';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'point')]
    public string $point = '';

    #[Url(as: 'activite')]
    public string $activite = '';

    #[Url(as: 'mode')]
    public string $mode = '';

    #[Url(as: 'statut')]
    public string $statut = '';

    #[Url(as: 'du')]
    public string $debut = '';

    #[Url(as: 'au')]
    public string $fin = '';

    /** La vente ouverte au detail — pose et retire par `$set`, sans action. */
    public ?string $venteDetailId = null;

    public string $motifAnnulation = '';

    public string $formatExport = 'pdf';

    /**
     * Le registre FERME des modales de l'ecran.
     *
     * La modale de DETAIL n'y figure pas : elle ne fait rien d'autre
     * qu'afficher, et elle est pilotee par `$set('venteDetailId', …)`.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'export' => ['formatExport'],
        ];
    }

    // =====================================================================
    // Lecture
    // =====================================================================

    /**
     * @return array<string, string>
     */
    private function filtres(): array
    {
        return [
            'recherche' => $this->recherche,
            'point' => $this->point,
            'activite' => $this->activite,
            'mode' => $this->mode,
            'statut' => $this->statut,
            'debut' => $this->debut,
            'fin' => $this->fin,
        ];
    }

    /**
     * @return Collection<int, Vente>
     */
    private function ventesAffichees(): Collection
    {
        return app(VenteService::class)->filtrer($this->filtres())->get();
    }

    /**
     * La phrase qui DIT le filtre sur le document exporte (PA-119).
     */
    private function descriptionDuFiltre(): string
    {
        $parts = [];

        if (trim($this->recherche) !== '') {
            $parts[] = __('pos_pwa.journal.filtre_recherche', ['terme' => trim($this->recherche)]);
        }

        if ($this->point !== '') {
            $parts[] = __('pos_pwa.journal.filtre_point', ['valeur' => $this->point]);
        }

        if ($this->activite !== '') {
            $parts[] = __('pos_pwa.journal.filtre_activite', [
                'valeur' => VenteService::MODULES[$this->activite] ?? $this->activite,
            ]);
        }

        if ($this->mode !== '') {
            $parts[] = __('pos_pwa.journal.filtre_mode', [
                'valeur' => VenteService::MODES_PAIEMENT[$this->mode] ?? $this->mode,
            ]);
        }

        if ($this->statut !== '') {
            $parts[] = __('pos_pwa.journal.filtre_statut', ['valeur' => $this->statut]);
        }

        if ($this->debut !== '') {
            $parts[] = __('pos_pwa.journal.filtre_debut', ['date' => $this->debut]);
        }

        if ($this->fin !== '') {
            $parts[] = __('pos_pwa.journal.filtre_fin', ['date' => $this->fin]);
        }

        return $parts === []
            ? __('pos_pwa.journal.filtre_aucun')
            : implode(' · ', $parts);
    }

    // =====================================================================
    // L'annulation — RG-02
    // =====================================================================

    public function annulerVente(VenteService $ventes): void
    {
        $this->exigerEcriture(self::MODULE);

        if (trim($this->motifAnnulation) === '') {
            $this->addError('motifAnnulation', __('pos_pwa.journal.refus_motif_obligatoire'));

            return;
        }

        $vente = $this->venteDetailId === null ? null : Vente::find($this->venteDetailId);

        if ($vente === null) {
            $this->addError('motifAnnulation', __('pos_pwa.journal.refus_vente_absente'));

            return;
        }

        try {
            $ventes->annuler($vente, trim($this->motifAnnulation));
        } catch (RuntimeException $refus) {
            // Le refus du domaine est ecrit pour l'operateur (`lang/fr/ventes.php`).
            $this->addError('motifAnnulation', $refus->getMessage());

            return;
        }

        $this->reset(['motifAnnulation', 'venteDetailId']);
        session()->flash('pwa-succes', __('pos_pwa.journal.vente_annulee', [
            'numero' => $vente->numero,
        ]));
    }

    /**
     * Le TICKET de la vente ouverte au detail — bouton « Telecharger » du
     * maitre (`ov-vente`).
     *
     * PA-101 : c'est la MEME piece que celle imprimee au comptoir, rendue sur
     * un autre papier. Ajouter un format est un ajout de RENDU, jamais une
     * reprise du modele — d'ou le gabarit partage `pdf.facture-ticket`, qui
     * reserve et NOMME l'emplacement du cachet fiscal sans rien y imprimer de
     * scannable.
     */
    public function telechargerTicket(ReportHeaderService $entetes): ?Response
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        $vente = $this->venteDetailId === null
            ? null
            : Vente::with('lignes')->find($this->venteDetailId);

        if ($vente === null) {
            $this->addError('motifAnnulation', __('pos_pwa.journal.refus_vente_absente'));

            return null;
        }

        $pdf = Pdf::loadView('pdf.facture-ticket', [
            'vente' => $vente,
            'quand' => $vente->created_at?->format('d/m/Y H:i') ?? '',
            'auteur' => $this->auteur(),
            // En-tete etablissement — source unique RG-19, jamais recopiee en dur.
            'entete' => $entetes->genererEnTete(
                typeRapport: __('pos_pwa.document.ticket_titre'),
                periode: '',
                auteur: $utilisateur,
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, 'ticket_'.$vente->numero.'.pdf');
    }

    // =====================================================================
    // L'export — PA-119
    // =====================================================================

    /**
     * LECTURE — inscrite comme telle dans `METHODES_DE_LECTURE` le 31/08/2026.
     *
     * Cet ecran ne porte aucun middleware `module:` : c'est le journal de
     * caisse, et le comptable (M5 = `L`) doit pouvoir l'exporter — c'est
     * precisement son metier. Exiger `C` ici le lui retirait.
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        $this->resetValidation();

        $this->formatExport = in_array($format, ['pdf', 'excel'], true) ? $format : 'pdf';
        $this->etatFormulaire = 'export';
    }

    /**
     * LECTURE — un export ne touche aucune table, il rend un document.
     */
    public function genererExport(): ?Response
    {
        $ventes = $this->ventesAffichees();

        if ($ventes->isEmpty()) {
            // Une liste vide se REFUSE : une page blanche ne dirait pas si le
            // filtre est trop etroit ou si la donnee n'existe pas.
            $this->addError('formatExport', __('pos_pwa.journal.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $nom = __('pos_pwa.journal.export_fichier').'_'.now()->format('Y_m_d_His');
        $filtre = $this->descriptionDuFiltre();

        if ($this->formatExport === 'excel') {
            /** @var Response $reponse */
            $reponse = Excel::download(new VentesExport($ventes, $filtre), $nom.'.xlsx');

            return $reponse;
        }

        $pdf = Pdf::loadView('pdf.ventes-rapport', [
            'entete' => $this->enTeteRapport(__('pos_pwa.document.journal_titre'), $filtre),
            'ventes' => $ventes,
            'filtre' => $filtre,
            'chiffreAffaires' => $this->chiffreAffaires($ventes),
            'encaisse' => $this->encaisse($ventes),
            'porteEnNote' => $this->porteEnNote($ventes),
            'auteur' => $this->auteur(),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    /**
     * Ferme la modale ouverte — exigee par le chassis d'export partage.
     */
    /**
     * LECTURE — fermer une modale ne touche aucune table. La garder sous
     * `exigerEcriture()` aurait laisse un comptable ouvrir la modale d'export
     * sans pouvoir la refermer.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    /**
     * Le nom de qui edite le document (RG-15).
     *
     * `Auth::user()` est type non-nullable par l'analyse statique, mais un
     * document peut etre demande hors session : le `instanceof` dit les deux
     * verites a la fois.
     */
    private function auteur(): string
    {
        $utilisateur = Auth::user();

        return $utilisateur instanceof User ? $utilisateur->login : '';
    }

    // =====================================================================
    // Les indicateurs — en bcmath, jamais en flottant
    // =====================================================================

    /**
     * @param  Collection<int, Vente>  $ventes
     */
    private function chiffreAffaires(Collection $ventes): string
    {
        return $this->somme($ventes->filter(fn (Vente $v): bool => ! $v->estAnnulee()));
    }

    /**
     * @param  Collection<int, Vente>  $ventes
     */
    private function encaisse(Collection $ventes): string
    {
        return $this->somme($ventes->filter(
            fn (Vente $v): bool => ! $v->estAnnulee() && $v->encaisse,
        ));
    }

    /**
     * @param  Collection<int, Vente>  $ventes
     */
    private function porteEnNote(Collection $ventes): string
    {
        return $this->somme($ventes->filter(
            fn (Vente $v): bool => ! $v->estAnnulee() && ! $v->encaisse,
        ));
    }

    /**
     * @param  Collection<int, Vente>  $ventes
     */
    private function somme(Collection $ventes): string
    {
        $cumul = '0.00';

        foreach ($ventes as $vente) {
            $cumul = bcadd($cumul, (string) $vente->montant_total, self::PRECISION_MONTANT);
        }

        return $cumul;
    }

    /**
     * La facture liee a chaque vente, quand elle existe — maitre,
     * `historique-ventes.html` l.211/234 :
     * `FactureEngine.factures().find(f => f.vente_id === v.id && !f.avoir_de)`.
     *
     * ⚠ `factures` NE PORTE AUCUNE colonne `vente_id` (PA-52 — aucun
     * identifiant de piece au schema serveur) : le lien se retrouve par les
     * LIGNES. `lignes_facture.source_id` reference l'identifiant de la ligne
     * de VENTE quand une consommation de sejour est facturee
     * ({@see \App\Pwa\Livewire\Pos\PosHeberges::cloturerEtFacturer()}), et
     * c'est le SEUL chemin qui cree ce lien a ce jour : une vente du comptoir
     * (POS Comptant) n'a jamais de facture liee, faute d'appel a
     * `EmissionFactureService` sur ce point de vente — ce n'est pas un defaut
     * de cette methode, c'est l'etat reel du dépôt (voir CLAUDE.md, § PA-124).
     *
     * UNE requete pour tout l'ecran, jamais une par ligne (N+1) : le journal
     * peut afficher des centaines de ventes.
     *
     * `avoir_de` n'a pas d'equivalent ici : un avoir est une ligne de la
     * table `avoirs`, jamais une seconde `Facture` — le filtre du maitre est
     * donc sans objet cote serveur.
     *
     * @param  Collection<int, Vente>  $ventes
     * @return array<string, Facture> vente_id => facture
     */
    private function facturesParVenteId(Collection $ventes): array
    {
        /** @var Collection<string, string> $ligneVenteVersVenteId */
        $ligneVenteVersVenteId = collect();

        foreach ($ventes as $vente) {
            foreach ($vente->lignes as $ligne) {
                $ligneVenteVersVenteId[$ligne->id] = $vente->id;
            }
        }

        if ($ligneVenteVersVenteId->isEmpty()) {
            return [];
        }

        $facturesParVenteId = [];

        LigneFacture::query()
            ->whereIn('source_id', $ligneVenteVersVenteId->keys())
            ->with('facture')
            ->get()
            ->each(function (LigneFacture $ligneFacture) use ($ligneVenteVersVenteId, &$facturesParVenteId): void {
                $venteId = $ligneVenteVersVenteId->get($ligneFacture->source_id);

                if ($venteId !== null && $ligneFacture->facture !== null) {
                    $facturesParVenteId[$venteId] = $ligneFacture->facture;
                }
            });

        return $facturesParVenteId;
    }

    // =====================================================================

    public function render(): View
    {
        $ventes = $this->ventesAffichees();
        $validees = $ventes->filter(fn (Vente $v): bool => ! $v->estAnnulee());

        $empreinte = md5((string) json_encode($this->filtres()));
        if ($empreinte !== $this->empreinteFiltres) {
            $this->empreinteFiltres = $empreinte;
            $this->page = 1;
        }
        $totalVentes = $ventes->count();
        $pagesVentes = max(1, (int) ceil($totalVentes / self::VENTES_PAR_PAGE));
        // Une page hors bornes est RAMENEE : `$page` n'est PAS lie a l'URL
        // (aucun #[Url]), mais c'est une propriete publique, forgeable depuis
        // le navigateur par `$set('page', …)`, et la liste peut se reduire sans
        // que l'empreinte des filtres change (une vente annulee sous le filtre
        // « validee »).
        $this->page = max(1, min($this->page, $pagesVentes));

        return view('pwa.pos.historique-ventes', array_merge($this->socle(), [
            'ventes' => $ventes,
            'ventesPage' => $ventes->forPage($this->page, self::VENTES_PAR_PAGE)->values(),
            'totalVentes' => $totalVentes,
            'pagesVentes' => $pagesVentes,
            'facturesParVenteId' => $this->facturesParVenteId($ventes),
            'valideesCount' => $validees->count(),
            'annuleesCount' => $ventes->count() - $validees->count(),
            'chiffreAffaires' => $this->chiffreAffaires($ventes),
            'encaisseTotal' => $this->encaisse($ventes),
            'porteEnNoteTotal' => $this->porteEnNote($ventes),
            'sansImpactStockCount' => $validees->filter(
                fn (Vente $v): bool => $v->aDesLignesSansImpactStock(),
            )->count(),
            'points' => Vente::query()
                ->select('point_vente')
                ->distinct()
                ->orderBy('point_vente')
                ->pluck('point_vente')
                ->all(),
            'venteDetail' => $this->venteDetailId === null
                ? null
                : Vente::with('lignes')->find($this->venteDetailId),
            'modules' => VenteService::MODULES,
            'modesPaiement' => VenteService::MODES_PAIEMENT,
            'descriptionDuFiltre' => $this->descriptionDuFiltre(),
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            'title' => __('pos_pwa.journal.titre_page'),
        ]);
    }
}
