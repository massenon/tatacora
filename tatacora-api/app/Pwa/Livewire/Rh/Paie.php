<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Rh;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Services\BulletinPaieService;
use App\Domain\Rh\Services\CalculPaieService;
use App\Domain\Rh\Services\EmployeService;
use App\Domain\Rh\Services\LivreDePaieService;
use App\Exports\PaieExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\AutoriseArchivage;
use App\Pwa\Support\ExerciceConsulte;
use App\Pwa\Support\MontantFcfa;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;

/**
 * M13 — Personnel & Paie, en ÉCRITURE.
 *
 * Maître : `prototype_v2/pages/m13-paie.html` et `m13-paie.js` ; la forme du
 * bulletin et du livre vient de `prototype_v2/assets/js/paie-engine.js`.
 *
 * ## AUCUN MONTANT DE PAIE N'EST SAISI
 *
 * Le prototype d'origine offrait un champ « Net à payer » — l'un des
 * anti-patterns nommés en tête de ce dépôt. Ici, le net, la CNSS, l'ITS et la
 * part patronale sont tous CALCULÉS par `CalculPaieService` et rendus en
 * lecture seule. Le seul montant saisi de l'écran est le **salaire de base**,
 * qui est une donnée du contrat de travail, pas un résultat de calcul.
 *
 * ## Les deux refus de PA-53 traversent cet écran sans être adoucis
 *
 * 1. **Le total de charge patronale n'est jamais affiché.** Le taux CNSS de
 *    risques professionnels est « 1 % à 4 % selon l'activité » et n'est pas
 *    confirmé pour l'hôtellerie-restauration. Chaque coût employeur est rendu
 *    en FOURCHETTE, et le bandeau permanent du maître dit pourquoi. Retenir
 *    2,5 % « au milieu » serait exactement l'hypothèse refusée : sur une masse
 *    salariale annuelle, l'écart entre 1 % et 4 % est un redressement.
 * 2. **Le barème ITS s'arrête à 500 000 F.** Deux sources divergent sur le
 *    haut de barème, et le moteur du maître porte la même note. Un bulletin
 *    au-delà est REFUSÉ, avec le message du service rendu mot pour mot.
 *
 * ## Ce qui est OMIS, avec sa raison datée (31/08/2026)
 *
 * - **Pointage, primes et évaluations.** Les tables `presences`,
 *   `primes_sanctions` et `evaluations` existent au schéma, mais aucun modèle
 *   ni service ne les touche dans ce dépôt. Les rendre afficherait des
 *   colonnes que rien n'alimente (PA-126). Conséquence visible et assumée :
 *   le « + Ajouter un élément » de la modale d'établissement n'est pas rendu,
 *   et `total_primes` vaut zéro.
 * - **Téléphone et centre analytique du salarié.** Aucune colonne sur
 *   `employes` ; les inventer ferait saisir une donnée qui ne serait
 *   persistée nulle part.
 * - **La pièce comptable de paie et « Comptabiliser la paie ».** Le
 *   listener « GenererEcritureDepuisPaie » que `create_rh.php` annonce
 *   lui-même n'existe nulle part, et écrire la pièce depuis M13 doublerait le
 *   seul point d'entrée d'écriture comptable, où vit RG-11. Depuis le
 *   01/09/2026, l'onglet Livre rend le SQUELETTE du tableau « Écriture
 *   comptable proposée » du maître (Compte, Libellé, Débit, Crédit) avec un
 *   état vide qui nomme ce refus — aucune ligne d'écriture n'est inventée.
 *
 * Aucun de ces blocs n'est rendu inerte : ils sont omis, et nommés en jeton de
 * refus (`docs/DIRECTIVE_CONFORMITE_100.md` Article 3.3).
 *
 * ## ⚠ Le référentiel de taux peut être VIDE, et l'écran doit le dire
 *
 * `PaieReferentielSeeder` existe, il est documenté… et il n'est appelé par
 * personne : il ne figure pas dans `DatabaseSeeder`. Sur une base fraîchement
 * semée, `parametres_systeme` ne porte donc aucun taux de paie. C'est le même
 * défaut que PA-161 — un seeder écrit, décroché, jamais exécuté.
 *
 * L'écran interroge `BulletinPaieService::etatReferentiel()` AVANT tout
 * calcul : il affiche l'état réel et nomme les clés manquantes, plutôt que de
 * laisser une exception traverser le rendu. C'est le geste d'`etatTva()`
 * (PA-62) : nommer l'incohérence avant qu'elle atteigne une opération.
 *
 * @see EF-M13-01 Dossier du personnel
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 * @see RG-15 Journalisation des opérations
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4, 7
 */
#[Layout('layouts.pwa')]
#[Title('Personnel & Paie — TATACORA AFRIQUE')]
class Paie extends PageMetier
{
    // « Qui peut archiver » vit dans le trait partagé, jamais recopié ici :
    // `administrateur` et `super_admin` sans la bascule des Paramètres, les
    // autres rôles en `C` derrière elle (directive PO du 03/09/2026).
    use AutoriseArchivage;
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M13"` au maître. */
    public const MODULE = 'M13';

    public const ONGLETS = ['personnel', 'bulletins', 'livre', 'declarations', 'bareme'];

    // ---------------------------------------------------------------- filtres

    #[Url(as: 'onglet')]
    public string $onglet = 'personnel';

    #[Url(as: 'periode')]
    public string $periode = '';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'service')]
    public string $filtreService = '';

    #[Url(as: 'contrat')]
    public string $filtreContrat = '';

    #[Url(as: 'statut')]
    public string $filtreStatut = 'actif';

    // ---- Archivage du personnel (PO 02/09/2026, elargi le 03/09/2026) ----
    //
    // « Supprimer = archiver » : le geste passe l'employe a `parti` par
    // `EmployeService::archiver()` — jamais une suppression (RG-15). La
    // selection multiple reprend le motif de `Facturation` (case d'entete +
    // cases de ligne), et la modale de confirmation NOMME les employes qui
    // n'ont pas de bulletin sur la periode courante : la generation les
    // sauterait sans un mot une fois partis — c'est le piege reel, porte a
    // l'ecran plutot qu'en verrou (un depart sans solde du est legitime).
    //
    // ⚠ La regle « qui peut archiver » N'EST PAS ecrite ici. Elle vit dans
    // `App\Pwa\Support\AutoriseArchivage` (`peutArchiver()` pour le rendu,
    // `exigerArchivage()` pour le refus serveur), partagee avec les autres
    // ecrans qui archivent. Elle y a ete repliee le 03/09/2026 : une copie
    // privee dans ce composant aurait ete un second auteur de la meme
    // decision, exactement ce que PA-160/161 condamne.

    /** @var list<string> */
    public array $selection = [];

    public bool $toutSelectionne = false;

    /** @var list<string> Les employes confirmes dans la modale d'archivage. */
    public array $employesAArchiver = [];

    /**
     * Le bulletin ouvert en consultation.
     *
     * ⚠ C'est une PROPRIÉTÉ, pas une action, et le choix est délibéré : la
     * consultation d'un bulletin est une LECTURE, et toute méthode publique
     * d'un composant PWA est présumée écrire tant qu'elle n'est pas inscrite
     * dans la liste relue de `PwaEcritureAutoriseeTest`. La rendre gardée
     * interdirait à un `comptable` en `L` sur M13 de lire un bulletin que la
     * page lui affiche déjà. La modale s'ouvre donc par
     * `$set('bulletinAffiche', …)`, qui ne franchit aucune garde d'écriture
     * parce qu'il n'en a pas à franchir.
     */
    public ?string $bulletinAffiche = null;

    // ------------------------------------------------ formulaire « employé »

    public ?string $employeId = null;

    public string $nomSaisi = '';

    public string $prenomSaisi = '';

    public string $posteSaisi = '';

    public string $serviceSaisi = '';

    public string $embaucheSaisie = '';

    public string $finContratSaisie = '';

    public string $numeroCnssSaisi = '';

    public string $contratSaisi = 'CDI';

    public string $salaireBaseSaisi = '';

    public string $statutSaisi = 'actif';

    public bool $doublonConfirme = false;

    // ------------------------------------------ formulaire « établissement »

    public ?string $employeAEtablir = null;

    // ------------------------------------------------ formulaire « annulation »

    public ?string $bulletinAAnnuler = null;

    public string $motifAnnulation = '';

    // ------------------------------------------------------ simulateur

    public string $brutSimule = '150000';

    // ---------------------------------------------------------------- export

    public string $formatExport = 'pdf';

    public function mount(): void
    {
        if ($this->periode === '') {
            // Sélecteur d'exercice global (PO, 20/10/2026) : le mois courant,
            // ou le dernier mois de l'exercice consulté quand il est passé.
            $this->periode = ExerciceConsulte::reference()->format('Y-m');
        }
    }

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'employe' => [
                'employeId', 'nomSaisi', 'prenomSaisi', 'posteSaisi', 'serviceSaisi',
                'embaucheSaisie', 'finContratSaisie', 'numeroCnssSaisi', 'contratSaisi',
                'salaireBaseSaisi', 'statutSaisi', 'doublonConfirme',
            ],
            'etablissement' => ['employeAEtablir'],
            'archivage' => ['employesAArchiver'],
            'annulation' => ['bulletinAAnnuler', 'motifAnnulation'],
            'export' => ['formatExport'],
        ];
    }

    // =====================================================================
    // Écritures — dossier du personnel
    // =====================================================================

    /**
     * Ouvre « Nouvel employé » ou « Modifier <matricule> ».
     */
    public function ouvrirFormulaireEmploye(?string $employeId = null): void
    {
        $this->ouvrirFormulaire('employe');

        if ($employeId === null) {
            $this->contratSaisi = 'CDI';
            $this->statutSaisi = 'actif';
            $this->embaucheSaisie = CarbonImmutable::today()->format('Y-m-d');
            $this->serviceSaisi = (string) app(EmployeService::class)->services()->first()?->id;

            return;
        }

        $employe = Employe::findOrFail($employeId);

        $this->employeId = $employe->getKey();
        $this->nomSaisi = $employe->nom;
        $this->prenomSaisi = (string) $employe->prenom;
        $this->posteSaisi = $employe->poste;
        $this->serviceSaisi = $employe->service_id;
        $this->embaucheSaisie = $employe->date_embauche->format('Y-m-d');
        $this->finContratSaisie = $employe->date_fin_contrat?->format('Y-m-d') ?? '';
        $this->numeroCnssSaisi = (string) $employe->numero_cnss;
        $this->contratSaisi = (string) ($employe->type_contrat ?? 'CDI');
        $this->salaireBaseSaisi = (string) $employe->salaire_base;
        $this->statutSaisi = $employe->statut;
    }

    /**
     * Enregistre le dossier — RG-18 appliquée au personnel : les homonymes
     * AVERTISSENT, ils ne bloquent pas, et la confirmation est un second geste
     * explicite. Deux homonymes réels existent dans un village ; refuser la
     * saisie ferait contourner le contrôle par une faute d'orthographe
     * volontaire, et le doublon deviendrait indétectable.
     */
    public function enregistrerEmploye(): void
    {
        $donnees = $this->validerEcriture([
            'nomSaisi' => ['required', 'string', 'max:120'],
            'prenomSaisi' => ['required', 'string', 'max:120'],
            'posteSaisi' => ['required', 'string', 'max:120'],
            'serviceSaisi' => ['required', 'string'],
            'embaucheSaisie' => ['required', 'date'],
            'finContratSaisie' => ['nullable', 'date'],
            'numeroCnssSaisi' => ['nullable', 'string', 'max:60'],
            'contratSaisi' => ['required', 'string'],
            'salaireBaseSaisi' => ['required', 'numeric', 'min:0'],
            'statutSaisi' => ['required', 'string'],
        ]);

        $service = app(EmployeService::class);

        $homonymes = $service->homonymes(
            (string) $donnees['nomSaisi'],
            (string) $donnees['prenomSaisi'],
            $this->employeId,
        );

        if ($homonymes->isNotEmpty() && ! $this->doublonConfirme) {
            $this->addError('nomSaisi', __('rh_pwa.homonymes_non_confirme'));

            return;
        }

        $charge = [
            'nom' => (string) $donnees['nomSaisi'],
            'prenom' => (string) $donnees['prenomSaisi'],
            'poste' => (string) $donnees['posteSaisi'],
            'service_id' => (string) $donnees['serviceSaisi'],
            'date_embauche' => (string) $donnees['embaucheSaisie'],
            'date_fin_contrat' => (string) $donnees['finContratSaisie'],
            'numero_cnss' => (string) $donnees['numeroCnssSaisi'],
            'type_contrat' => (string) $donnees['contratSaisi'],
            'salaire_base' => (string) $donnees['salaireBaseSaisi'],
            'statut' => (string) $donnees['statutSaisi'],
        ];

        try {
            if ($this->employeId === null) {
                $employe = $service->creerEmploye($charge);
                $message = __('rh_pwa.employe_cree', ['matricule' => (string) $employe->matricule]);
            } else {
                $service->mettreAJourEmploye(Employe::findOrFail($this->employeId), $charge);
                $message = __('rh_pwa.employe_modifie');
            }
        } catch (RuntimeException $refus) {
            $this->addError('nomSaisi', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire($message);
    }

    // =====================================================================
    // Écritures — bulletins
    // =====================================================================

    public function ouvrirEtablissementBulletin(string $employeId): void
    {
        $this->ouvrirFormulaire('etablissement');

        $this->employeAEtablir = Employe::findOrFail($employeId)->getKey();
    }

    /**
     * Établit le bulletin du salarié visé, sur la période affichée.
     */
    public function etablirBulletin(): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->employeAEtablir === null) {
            abort(404);
        }

        try {
            $bulletin = app(BulletinPaieService::class)->etablirBulletin(
                Employe::findOrFail($this->employeAEtablir),
                $this->periodeValide(),
            );
        } catch (RuntimeException $refus) {
            // Le refus de `CalculPaieService` (barème ITS, référentiel absent)
            // est RENDU tel quel : c'est lui qui nomme la raison exacte.
            $this->addError('employeAEtablir', $refus->getMessage());

            return;
        }

        $this->bulletinAffiche = $bulletin->getKey();

        $this->terminerFormulaire(__('rh_pwa.bulletin_etabli', [
            'numero' => (string) $bulletin->numero,
            'net' => MontantFcfa::format((string) $bulletin->net_a_payer),
        ]));
    }

    /**
     * Établit tous les bulletins manquants de la période.
     *
     * Un salarié REFUSÉ (barème ITS dépassé) n'interrompt pas les autres : son
     * motif est rendu, nommé. Échouer le lot entier ferait perdre neuf
     * bulletins corrects pour un cas non tranché.
     */
    public function genererBulletinsManquants(): void
    {
        $this->exigerEcriture(self::MODULE);

        $bilan = app(BulletinPaieService::class)->etablirBulletinsManquants($this->periodeValide());

        foreach ($bilan['refus'] as $refus) {
            $this->addError('periode', $refus['employe'].' : '.$refus['motif']);
        }

        if ($bilan['etablis'] === 0 && $bilan['refus'] === []) {
            session()->flash('pwa-succes', __('rh_pwa.bulletins_aucun_manquant'));

            return;
        }

        if ($bilan['etablis'] > 0) {
            session()->flash('pwa-succes', __('rh_pwa.bulletins_generes', ['nombre' => $bilan['etablis']]));
        }
    }

    public function ouvrirAnnulationBulletin(string $bulletinId): void
    {
        $this->ouvrirFormulaire('annulation');

        $this->bulletinAAnnuler = BulletinPaie::findOrFail($bulletinId)->getKey();
    }

    /**
     * Annule un bulletin — jamais une suppression, et le motif est obligatoire.
     */
    public function annulerBulletin(): void
    {
        $donnees = $this->validerEcriture([
            'motifAnnulation' => ['required', 'string', 'max:500'],
        ]);

        if ($this->bulletinAAnnuler === null) {
            abort(404);
        }

        try {
            app(BulletinPaieService::class)->annulerBulletin(
                BulletinPaie::findOrFail($this->bulletinAAnnuler),
                (string) $donnees['motifAnnulation'],
            );
        } catch (RuntimeException $refus) {
            $this->addError('motifAnnulation', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('rh_pwa.bulletin_annule_fait'));
    }

    // =====================================================================
    // Export et impression — LECTURES
    // =====================================================================

    public function ouvrirExport(): void
    {
        $this->reset('formatExport');
        $this->resetValidation();
        $this->etatFormulaire = 'export';
    }

    /**
     * @return \Symfony\Component\HttpFoundation\StreamedResponse|\Symfony\Component\HttpFoundation\BinaryFileResponse|null
     */
    public function genererExport()
    {
        $onglet = $this->ongletValide();
        $lignes = $this->lignesExportables($onglet);

        if ($lignes === []) {
            $this->addError('formatExport', __('rh_pwa.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;

        if ($this->formatExport === 'excel') {
            return Excel::download(
                new PaieExport($onglet, $lignes, $this->descriptionDuFiltre()),
                'paie_'.$onglet.'_'.now()->format('Ymd_His').'.xlsx',
            );
        }

        $utilisateur = auth()->user();

        $pdf = Pdf::loadView('pdf.paie', [
            'entete' => $this->enTeteRapport($this->libelleOnglet($onglet), $this->descriptionDuFiltre()),
            'titreDocument' => $this->libelleOnglet($onglet),
            'entetes' => PaieExport::entetesDe($onglet),
            'lignes' => $lignes,
            'filtre' => $this->descriptionDuFiltre(),
            'auteur' => $utilisateur instanceof User ? $utilisateur->login : null,
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'paie_'.$onglet.'_'.now()->format('Ymd_His').'.pdf',
        );
    }

    /**
     * Le bulletin sur papier A4 — LECTURE, inscrite comme telle.
     *
     * Un salarié doit pouvoir recevoir son bulletin ; le droit de le lire est
     * déjà porté par `module:M13,L` sur la route. Exiger le niveau `C` pour
     * imprimer retirerait le document à tous les rôles en consultation.
     *
     * @return \Symfony\Component\HttpFoundation\StreamedResponse
     */
    public function exporterPdf(string $bulletinId)
    {
        $bulletin = BulletinPaie::with('employe.service')->findOrFail($bulletinId);
        $utilisateur = auth()->user();

        $pdf = Pdf::loadView('pdf.paie-bulletin', [
            // L'identité seulement : le bulletin garde sa propre mise en page.
            'entete' => $this->enTeteRapport(__('rh_pwa.bulletin_entete'), $this->periodeLongue($bulletin->periode)),
            'bulletin' => $bulletin,
            'recapitulatif' => app(BulletinPaieService::class)->recapitulatif($bulletin),
            'auteur' => $utilisateur instanceof User ? $utilisateur->login : null,
            'periodeLongue' => $this->periodeLongue($bulletin->periode),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static fn () => print ($pdf->output()),
            'bulletin_'.$bulletin->numero.'.pdf',
        );
    }

    /**
     * La case « tout selectionner » de l'entete — meme motif que
     * `Facturation::updatedToutSelectionne()` : elle retient les employes
     * VISIBLES sous les filtres courants, jamais l'effectif entier.
     *
     * Elle saute les employes DEJA PARTIS (03/09/2026) : sous le filtre
     * « Tous », les inclure ferait rendre un refus par ligne deja traitee a
     * chaque archivage de lot. Le refus du service reste, et il sert : deux
     * Administrateurs simultanes peuvent archiver la meme ligne.
     */
    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur
            ? $this->employesAffiches()
                ->filter(static fn (Employe $e): bool => $e->statut !== 'parti')
                ->pluck('id')
                ->values()
                ->all()
            : [];
    }

    /**
     * Ouvre la confirmation d'archivage — pour UNE ligne (bouton rouge de la
     * colonne d'actions) ou pour la SELECTION (bouton d'entete). Motif
     * `FormulaireModal` : le droit est exige a l'ouverture ET a
     * l'enregistrement, l'ouverture ne protegeant rien par elle-meme.
     */
    public function ouvrirArchivageEmployes(?string $employeId = null): void
    {
        // Le droit d'ARCHIVER est exige des l'ouverture, en plus du droit
        // d'ecriture pose par `ouvrirFormulaire()` : sans lui, un `rh` bascule
        // fermee ouvrirait une modale que l'enregistrement refuserait en 403.
        $this->exigerArchivage();

        // La selection porte sur CE QUI EST AFFICHE (meme regle que l'export,
        // PA-119) : cocher tout l'effectif puis changer de filtre ne doit pas
        // archiver des lignes que l'ecran ne montre plus.
        $ids = $employeId !== null ? [$employeId] : $this->selectionAffichee();

        if ($ids === []) {
            return;
        }

        // `ouvrirFormulaire` (droit + remise a zero) AVANT de poser la liste :
        // il reinitialise les proprietes du registre, dont celle-ci.
        $this->ouvrirFormulaire('archivage');
        $this->employesAArchiver = $ids;
    }

    /**
     * Archive les employes confirmes — ecriture M13, derriere `peutArchiver()`
     * (administrateur et super_admin sans condition ; les autres roles en `C`
     * derriere la bascule de suppression des Parametres, meme garde que le
     * parc, `Hebergement`).
     * Un refus du service (deja parti) est affiche et n'empeche PAS les
     * autres archivages du lot : perdre le lot entier pour une ligne deja
     * traitee serait le refus d'operation de PA-65 applique a l'envers.
     */
    public function archiverEmployes(): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->exigerArchivage();

        if ($this->employesAArchiver === []) {
            return;
        }

        $service = app(EmployeService::class);
        $archives = 0;

        foreach (Employe::query()->whereIn('id', $this->employesAArchiver)->get() as $employe) {
            try {
                $service->archiver($employe);
                $archives++;
            } catch (\RuntimeException $refus) {
                $this->addError('archivage', $refus->getMessage());
            }
        }

        if ($archives > 0) {
            session()->flash('pwa-succes', trans_choice('rh_pwa.archivage.succes', $archives, [
                'nombre' => $archives,
            ]));
        }

        $this->employesAArchiver = [];
        $this->selection = [];
        $this->toutSelectionne = false;
        $this->etatFormulaire = null;
    }

    /**
     * La selection RESTREINTE aux lignes reellement affichees.
     *
     * Les cases restent cochees quand un filtre change : sans cette
     * intersection, « Archiver la selection (3) » porterait sur des employes
     * que l'ecran ne montre plus — le defaut que PA-119 nomme pour l'export,
     * transpose a une action destructrice.
     *
     * @return list<string>
     */
    private function selectionAffichee(): array
    {
        $visibles = $this->employesAffiches()->pluck('id')->all();

        return array_values(array_intersect($this->selection, $visibles));
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->bulletinAffiche = null;
        $this->employesAArchiver = [];
        $this->resetValidation();
    }

    // =====================================================================
    // Lectures
    // =====================================================================

    public function render(): View
    {
        $bulletins = app(BulletinPaieService::class);
        $livre = app(LivreDePaieService::class);
        $employes = app(EmployeService::class);

        $periode = $this->periodeValide();
        $etat = $bulletins->etatReferentiel();

        $effectif = $this->employesAffiches();
        $manquants = $bulletins->employesSansBulletin($periode);
        $bulletinsDuMois = $bulletins->bulletinsDuMois($periode);
        $totaux = $livre->totaux($periode);

        $masse = '0.00';
        $coutParEmploye = [];

        foreach ($effectif as $employe) {
            $masse = bcadd($masse, (string) $employe->salaire_base, 2);
            $coutParEmploye[$employe->getKey()] = $bulletins->coutEmployeur((string) $employe->salaire_base);
        }

        $bulletinOuvert = $this->bulletinAffiche === null
            ? null
            : BulletinPaie::with('employe.service')->find($this->bulletinAffiche);

        return view('pwa.rh.paie', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'periode' => $periode,
            'periodeLongue' => $this->periodeLongue($periode),
            'etatReferentiel' => $etat,
            'services' => $employes->services(),
            'typesContrat' => Employe::TYPES_CONTRAT,
            'statutsEmploye' => Employe::STATUTS,
            'employes' => $effectif,
            'coutParEmploye' => $coutParEmploye,
            'masseSalariale' => $masse,
            'coutMasse' => $bulletins->coutEmployeur($masse),
            'bulletinsDuMois' => $bulletinsDuMois,
            'bulletinsParEmploye' => $bulletinsDuMois->keyBy('employe_id'),
            // Archivage (PO 02/09/2026, elargi le 03/09/2026) : `peutArchiver`
            // commande cases, boutons rouges et modale — UNE seule regle,
            // calculee par le composant, jamais rejouee dans la vue. La liste
            // visee alimente la confirmation, qui nomme chaque employe plutot
            // qu'un compte nu ; `selectionAffichee` fait suivre le compteur du
            // bouton de lot aux filtres courants.
            'peutArchiver' => $this->peutArchiver(),
            'selectionAffichee' => array_values(array_intersect(
                $this->selection,
                $effectif->pluck('id')->all(),
            )),
            'employesVisesParArchivage' => $this->employesAArchiver === []
                ? new EloquentCollection()
                : Employe::query()->whereIn('id', $this->employesAArchiver)->orderBy('nom')->get(),
            'nombreManquants' => $manquants->count(),
            'totaux' => $totaux,
            'declarations' => $livre->declarations($periode),
            'baremeIts' => $this->baremeIts(),
            'plafondIts' => CalculPaieService::PLAFOND_ITS_CONFIRME,
            'simulation' => $bulletins->simuler($this->brutSimule === '' ? '0' : $this->brutSimule),
            'ecartAnnuel' => $this->ecartAnnuelSimule($bulletins->simuler($this->brutSimule === '' ? '0' : $this->brutSimule)),
            'bulletinOuvert' => $bulletinOuvert,
            'recapitulatifOuvert' => $bulletinOuvert instanceof BulletinPaie
                ? $bulletins->recapitulatif($bulletinOuvert)
                : null,
            'employeEnEtablissement' => $this->employeAEtablir === null
                ? null
                : Employe::find($this->employeAEtablir),
            'matriculeEnEdition' => $this->employeId === null
                ? ''
                : (string) Employe::find($this->employeId)?->matricule,
            'apercuEtablissement' => $this->apercuEtablissement($bulletins),
            'homonymes' => $this->homonymesDuFormulaire($employes),
            'sansNumeroCnss' => $effectif->filter(
                static fn (Employe $e): bool => $e->sansNumeroCnss(),
            )->count(),
            'effectifTotal' => Employe::query()->count(),
            'peutEcrire' => $this->peutEcrire(),
            'titreExport' => __('rh_pwa.export_titre', [
                'onglet' => $this->libelleOnglet($this->ongletValide()),
            ]),
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
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'personnel';
    }

    /**
     * La période affichée, ou le mois courant si la saisie est illisible.
     *
     * Le paramètre vient d'une URL, donc de l'extérieur : une période mal
     * formée ne doit pas atteindre les services, qui la refuseraient au milieu
     * d'un rendu.
     */
    private function periodeValide(): string
    {
        $reference = ExerciceConsulte::reference()->format('Y-m');
        if (preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $this->periode) !== 1) {
            return $reference;
        }

        // Un mois hors de l'exercice consulté (lien ancien, saisie) y revient.
        $bornes = ExerciceConsulte::bornes();

        return $bornes === null
            || ($this->periode >= $bornes[0]->format('Y-m') && $this->periode <= $bornes[1]->subDay()->format('Y-m'))
            ? $this->periode
            : $reference;
    }

    private function periodeLongue(string $periode): string
    {
        return CarbonImmutable::createFromFormat('Y-m-d', $periode.'-01')
            ->locale('fr')
            ->isoFormat('MMMM YYYY');
    }

    private function libelleOnglet(string $onglet): string
    {
        return match ($onglet) {
            'bulletins' => __('rh_pwa.onglet_bulletins'),
            'livre' => __('rh_pwa.onglet_livre'),
            'declarations' => __('rh_pwa.onglet_declarations'),
            'bareme' => __('rh_pwa.onglet_bareme'),
            default => __('rh_pwa.onglet_personnel'),
        };
    }

    /**
     * L'effectif retenu par les filtres affichés.
     *
     * @return Collection<int, Employe>
     */
    private function employesAffiches(): Collection
    {
        $terme = mb_strtolower(trim($this->recherche));

        /** @var EloquentCollection<int, Employe> $tous */
        $tous = Employe::query()->with('service')->orderBy('nom')->get();

        return $tous
            ->when($this->filtreService !== '', fn (Collection $c) => $c->where('service_id', $this->filtreService))
            ->when($this->filtreContrat !== '', fn (Collection $c) => $c->where('type_contrat', $this->filtreContrat))
            ->when($this->filtreStatut === 'sans_cnss', fn (Collection $c) => $c->filter(
                static fn (Employe $e): bool => $e->sansNumeroCnss(),
            ))
            ->when($this->filtreStatut === 'actif', fn (Collection $c) => $c->filter(
                static fn (Employe $e): bool => $e->estEnPoste(),
            ))
            ->when($this->filtreStatut === 'parti', fn (Collection $c) => $c->where('statut', 'parti'))
            ->when($terme !== '', fn (Collection $c) => $c->filter(
                static fn (Employe $e): bool => str_contains(
                    mb_strtolower($e->nomComplet().' '.(string) $e->matricule.' '.$e->poste),
                    $terme,
                ),
            ))
            ->values();
    }

    /**
     * Le barème ITS confirmé, avec l'impôt maximal et le cumul par tranche —
     * le tableau du maître.
     *
     * Les tranches viennent de `CalculPaieService`, jamais recopiées : deux
     * barèmes écrits à deux endroits finiraient par diverger, et c'est celui
     * qui est affiché qui tromperait.
     *
     * @return list<array{plancher: string, plafond: string, taux: string, maximum: string, cumul: string}>
     */
    private function baremeIts(): array
    {
        $calcul = app(CalculPaieService::class);
        $tranches = [];
        $cumul = '0.00';
        $plancher = '0.00';

        foreach ([60000, 150000, 250000, (int) CalculPaieService::PLAFOND_ITS_CONFIRME] as $plafond) {
            $borne = number_format((float) $plafond, 2, '.', '');
            $impotPlafond = $calcul->impotSurTraitements($borne);
            $maximum = bcsub($impotPlafond, $cumul, 2);

            $tranches[] = [
                'plancher' => $plancher,
                'plafond' => $borne,
                // Le taux se DÉDUIT de l'impôt de la tranche : le recopier
                // depuis la constante privée du service demanderait de
                // l'exposer, et une seconde liste de taux finirait par
                // diverger de celle qui calcule.
                'taux' => bccomp($borne, $plancher, 2) === 0
                    ? '0'
                    : bcmul(bcdiv($maximum, bcsub($borne, $plancher, 2), 6), '100', 0),
                'maximum' => $maximum,
                'cumul' => $impotPlafond,
            ];

            $cumul = $impotPlafond;
            $plancher = $borne;
        }

        return $tranches;
    }

    /**
     * L'écart annuel porté par le taux de risques professionnels — douze fois
     * l'écart mensuel, comme au maître.
     *
     * @param  array{refus: string|null, retenues: array<string, string>|null, cout: array<string, string>|null}  $simulation
     */
    private function ecartAnnuelSimule(array $simulation): ?string
    {
        if ($simulation['cout'] === null) {
            return null;
        }

        return bcmul($simulation['cout']['ecart'], '12', 2);
    }

    /**
     * L'aperçu chiffré de la modale d'établissement — calculé par le service,
     * jamais recomposé ici.
     *
     * @return array{refus: string|null, retenues: array<string, string>|null, cout: array<string, string>|null}|null
     */
    private function apercuEtablissement(BulletinPaieService $service): ?array
    {
        if ($this->employeAEtablir === null) {
            return null;
        }

        $employe = Employe::find($this->employeAEtablir);

        return $employe === null ? null : $service->simuler((string) $employe->salaire_base);
    }

    /**
     * Les homonymes du nom en cours de saisie — RG-18 appliquée au personnel.
     *
     * @return EloquentCollection<int, Employe>
     */
    private function homonymesDuFormulaire(EmployeService $service): EloquentCollection
    {
        if ($this->etatFormulaire !== 'employe' || trim($this->nomSaisi) === '') {
            return new EloquentCollection();
        }

        return $service->homonymes($this->nomSaisi, $this->prenomSaisi, $this->employeId);
    }

    /**
     * Les lignes RÉELLEMENT AFFICHÉES de l'onglet — PA-119.
     *
     * @return list<array<int, string>>
     */
    private function lignesExportables(string $onglet): array
    {
        $periode = $this->periodeValide();
        $livre = app(LivreDePaieService::class);
        $bulletins = app(BulletinPaieService::class);

        if ($onglet === 'declarations') {
            return array_map(static fn (array $d): array => [
                $d['code'],
                $d['libelle'],
                MontantFcfa::format($d['montant']),
                $d['echeance'] ?? MontantFcfa::TIRET,
                $d['complet'] ? __('rh_pwa.etat_arrete') : __('rh_pwa.etat_incomplet'),
            ], $livre->declarations($periode));
        }

        if ($onglet === 'livre') {
            $t = $livre->totaux($periode);

            return [
                [__('rh_pwa.livre_brut'), MontantFcfa::format($t['brut'])],
                [__('rh_pwa.livre_cnss'), MontantFcfa::format($t['cnss_salarie'])],
                [__('rh_pwa.livre_its'), MontantFcfa::format($t['its'])],
                [__('rh_pwa.livre_autres'), MontantFcfa::format($t['autres_retenues'])],
                [__('rh_pwa.livre_net'), MontantFcfa::format($t['net'])],
                [__('rh_pwa.livre_pension'), MontantFcfa::format($t['pension'])],
                [__('rh_pwa.livre_familiales'), MontantFcfa::format($t['familiales'])],
                [__('rh_pwa.livre_vps'), MontantFcfa::format($t['vps'])],
                [
                    __('rh_pwa.livre_rp'),
                    MontantFcfa::format($t['rp_min']).' — '.MontantFcfa::format($t['rp_max']),
                ],
                [__('rh_pwa.livre_total_confirmees'), MontantFcfa::format($t['patronales_confirmees'])],
                [
                    __('rh_pwa.livre_cout'),
                    MontantFcfa::format($t['cout_min']).' — '.MontantFcfa::format($t['cout_max']),
                ],
            ];
        }

        if ($onglet === 'bulletins') {
            return $bulletins->bulletinsDuMois($periode)->map(
                static fn (BulletinPaie $b): array => [
                    (string) $b->employe->matricule,
                    $b->employe->nomComplet(),
                    MontantFcfa::format($b->brut()),
                    MontantFcfa::format((string) $b->cnss_salarie),
                    MontantFcfa::format((string) $b->its),
                    MontantFcfa::format($b->autresRetenues()),
                    MontantFcfa::format((string) $b->net_a_payer),
                    MontantFcfa::format((string) $b->charges_patronales_confirmees),
                ],
            )->values()->all();
        }

        if ($onglet === 'bareme') {
            return array_map(static fn (array $t): array => [
                __('rh_pwa.tranche_de_a', [
                    'plancher' => MontantFcfa::format($t['plancher']),
                    'plafond' => MontantFcfa::format($t['plafond']),
                ]),
                $t['taux'].' %',
                MontantFcfa::format($t['maximum']),
                MontantFcfa::format($t['cumul']),
            ], $this->baremeIts());
        }

        return $this->employesAffiches()->map(static fn (Employe $e): array => [
            (string) $e->matricule,
            $e->nomComplet(),
            $e->poste,
            (string) $e->service?->libelle,
            (string) $e->type_contrat,
            $e->date_embauche->format('d/m/Y'),
            $e->sansNumeroCnss() ? __('rh_pwa.cnss_absent') : (string) $e->numero_cnss,
            MontantFcfa::format((string) $e->salaire_base),
        ])->values()->all();
    }

    private function descriptionDuFiltre(): string
    {
        $morceaux = [
            __('rh_pwa.filtre_onglet').' '.$this->libelleOnglet($this->ongletValide()),
            __('rh_pwa.filtre_periode').' '.$this->periodeLongue($this->periodeValide()),
        ];

        if ($this->filtreService !== '') {
            $service = app(EmployeService::class)->services()->firstWhere('id', $this->filtreService);

            if ($service !== null) {
                $morceaux[] = __('rh_pwa.filtre_service').' '.$service->libelle;
            }
        }

        if (trim($this->recherche) !== '') {
            $morceaux[] = __('rh_pwa.filtre_recherche').' '.trim($this->recherche);
        }

        return implode(' · ', $morceaux);
    }
}
