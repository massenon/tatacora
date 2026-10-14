<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Shared\Backup\Services\ExportTableService;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Backup\Services\SauvegardeManuelleService;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Models\JournalImport;
use App\Shared\ImportExport\Services\ControleImportService;
use App\Shared\ImportExport\Services\ImportReferentielsService;
use App\Shared\ImportExport\Services\RegistreArchivesService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\WithFileUploads;
use RuntimeException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Import & Export — maitre : `prototype_v2/pages/import-export.html`.
 *
 * ## DIRECTIVE DU PRODUCT OWNER (02/09/2026) : LES QUATRE ONGLETS SONT RÉELS
 *
 * La transcription suit le maître onglet par onglet, avec un fonctionnement
 * réel derrière chaque geste :
 *
 * - **Importer les données** — registre fermé `ReferentielsImport` (huit
 *   modules), fiche « Colonnes attendues », modèle CSV généré depuis la MÊME
 *   déclaration que le contrôle, rapport ERREUR/AVERTIS., et application en
 *   TRANSACTION UNIQUE : aucun import partiel (`ImportReferentielsService`).
 *   Historique réel (`journal_imports`). Le refus antérieur (« aucun moteur
 *   d'import n'existe ») est levé par ce lot, pas contourné.
 * - **Sauvegardes de la base** — `SauvegardeManuelleService` appelle le MÊME
 *   `SauvegardeBaseQuotidienneJob::handle()` que la tâche planifiée de 02h00.
 *   KPI mesurés, bandeau « en attente de téléchargement » dérivé des fichiers
 *   réels, export d'une table (lecture, liste fermée `ExportTableService`).
 * - **Restaurer** — `RegistreArchivesService` : l'agrégat DÉRIVÉ des deux
 *   familles réellement archivables (`hors_service` — unités M1, véhicules
 *   M8), restauration par les services de parc, purge réservée à
 *   l'administrateur avec refus motivé. Le refus antérieur (« aucun registre
 *   d'archives ») est levé : le registre existe désormais, en dérivé.
 * - **Réinitialiser les données de test** — « Réinitialiser comme neuf »
 *   (demande PO du 14/10/2026, `ReinitialisationDonneesTestService`) :
 *   transactionnel ET tiers (clients, employés, fournisseurs, guides) vidés,
 *   comptes, paramètres, journaux et référentiels désignés par le PO gardés,
 *   sauvegarde automatique AVANT, réservé aux rôles d'administration.
 *   Verrous : l'environnement (jamais en Production) et la bascule
 *   `reinitialisation_seeders` (fermée par défaut — état verrouillé du
 *   maître, cadenas et renvoi vers Paramètres). Modale au markup du maître :
 *   la phrase « VIDER » à retaper (jamais `wire:confirm`,
 *   `MotifsInterditsPwaTest`).
 *
 * @see LARAVEL_PWA.md §1, §3
 * @see DIRECTIVE_CONFORMITE_100.md Article 3.3, Article 8
 */
#[Title('Import & Export — TATACORA AFRIQUE')]
class ImportExport extends PageTransverse
{
    use FormulaireModal;
    use WithFileUploads;

    /** Le module RBAC de l'écran — `data-module="PARAM"` au maître. */
    public const MODULE = 'PARAM';

    public const ONGLETS = ['importer', 'sauvegardes', 'restaurer', 'seeders'];

    /** Plafonds d'affichage du rapport de contrôle — ceux du maître (l.499-501). */
    public const PLAFOND_ERREURS = 60;

    public const PLAFOND_AVERTISSEMENTS = 40;

    #[Url(as: 'onglet')]
    public string $onglet = 'importer';

    // ------------------------------------------------------------- importer
    public string $moduleImport = '';

    /** @var \Livewire\Features\SupportFileUploads\TemporaryUploadedFile|null */
    public $fichierImport = null;

    /**
     * Le dernier rapport de contrôle, prêt pour l'affichage — `null` : aucun.
     *
     * Il porte la clé du module contrôlé : changer de module au sélecteur le
     * rend caduc sans hook Livewire (la vue ne le rend que si les clés
     * correspondent), et `confirmerImport()` RECONTRÔLE le fichier de toute
     * façon — l'affichage n'autorise rien.
     *
     * @var array{cle: string, ok: bool, erreurs: list<array{ligne: int, colonne: ?string, message: string}>,
     *            avertissements: list<array{ligne: int, colonne: ?string, message: string}>,
     *            total_erreurs: int, resume: array{total: int, valides: int, en_erreur: int}}|null
     */
    public ?array $rapportControle = null;

    // ---------------------------------------------------------- sauvegardes
    public string $tableExport = '';

    public ?string $sauvegardeARetirer = null;

    // ------------------------------------------------------------ restaurer
    #[Url(as: 'q')]
    public string $rechercheArchives = '';

    #[Url(as: 'filtre')]
    public string $filtreArchives = 'restaurables';

    public ?string $purgeType = null;

    public ?string $purgeId = null;

    public ?string $purgeLibelle = null;

    // -------------------------------------------------------------- seeders
    public string $phraseConfirmationReset = '';

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'export_table' => ['tableExport'],
            'retrait_sauvegarde' => ['sauvegardeARetirer'],
            'purge' => ['purgeType', 'purgeId', 'purgeLibelle'],
            'reinitialisation' => ['phraseConfirmationReset'],
        ];
    }

    // =====================================================================
    // Onglet 1 — Importer les données
    // =====================================================================

    /**
     * Le fichier modèle — généré depuis la MÊME déclaration que le contrôle
     * (`ReferentielsImport`), règle du maître : « il ne peut pas s'en
     * écarter ». En-têtes + une ligne d'exemple, CSV UTF-8 avec BOM.
     */
    public function telechargerModeleCsv(): ?StreamedResponse
    {
        $this->exigerEcriture(self::MODULE);

        $module = ReferentielsImport::parCle($this->moduleImport);

        if ($module === null) {
            return null;
        }

        $entetes = array_map(static fn ($c): string => $c->libelle, $module->colonnes);
        $exemples = array_map(static fn ($c): string => $c->exemple, $module->colonnes);

        return $this->fluxCsv('modele_import_'.$module->cle.'.csv', static function ($sortie) use ($entetes, $exemples): void {
            fputcsv($sortie, $entetes, ';');
            fputcsv($sortie, $exemples, ';');
        });
    }

    /**
     * « Valider et contrôler le fichier » — produit le RAPPORT, n'importe
     * RIEN : « Déposez le fichier et lancez le contrôle. Rien n'est importé à
     * ce stade. » (maître, démarche à suivre, étape 4).
     */
    public function controlerFichierImport(ControleImportService $controle): void
    {
        $donnees = $this->validerEcriture([
            'moduleImport' => ['required', 'string'],
            'fichierImport' => ['required', 'file', 'mimes:csv,txt', 'max:4096'],
        ]);

        $module = ReferentielsImport::parCle((string) $donnees['moduleImport']);

        if ($module === null) {
            $this->addError('moduleImport', __('imports.controle.module_inconnu'));

            return;
        }

        $contenu = (string) file_get_contents((string) $this->fichierImport?->getRealPath());
        $rapport = $controle->controler($module, $controle->analyserCsv($contenu));

        $this->rapportControle = [
            'cle' => $module->cle,
            'ok' => $rapport->ok,
            // Plafond d'affichage du maître — le TOTAL reste annoncé.
            'erreurs' => array_slice($rapport->erreurs, 0, self::PLAFOND_ERREURS),
            'avertissements' => array_slice($rapport->avertissements, 0, self::PLAFOND_AVERTISSEMENTS),
            'total_erreurs' => count($rapport->erreurs),
            'resume' => $rapport->resume,
        ];
    }

    /**
     * « Confirmer l'import de N ligne(s) » — le fichier est RECONTRÔLÉ (la
     * base a pu bouger depuis l'affichage du rapport), puis appliqué en
     * TRANSACTION UNIQUE : une erreur, et rien n'entre en base.
     */
    public function confirmerImport(ControleImportService $controle, ImportReferentielsService $import): void
    {
        $donnees = $this->validerEcriture([
            'moduleImport' => ['required', 'string'],
            'fichierImport' => ['required', 'file', 'mimes:csv,txt', 'max:4096'],
        ]);

        $module = ReferentielsImport::parCle((string) $donnees['moduleImport']);

        if ($module === null) {
            $this->addError('moduleImport', __('imports.controle.module_inconnu'));

            return;
        }

        $contenu = (string) file_get_contents((string) $this->fichierImport?->getRealPath());
        $rapport = $controle->controler($module, $controle->analyserCsv($contenu));

        if (! $rapport->ok) {
            // L'état a changé entre le contrôle affiché et la confirmation :
            // le rapport frais remplace l'ancien, rien n'est importé.
            $this->rapportControle = [
                'cle' => $module->cle,
                'ok' => false,
                'erreurs' => array_slice($rapport->erreurs, 0, self::PLAFOND_ERREURS),
                'avertissements' => array_slice($rapport->avertissements, 0, self::PLAFOND_AVERTISSEMENTS),
                'total_erreurs' => count($rapport->erreurs),
                'resume' => $rapport->resume,
            ];

            return;
        }

        try {
            $nombre = $import->appliquer($module, $rapport->lignes);
        } catch (RuntimeException $refus) {
            $this->addError('fichierImport', $refus->getMessage());

            return;
        }

        $this->reset(['fichierImport', 'rapportControle']);
        session()->flash('pwa-succes', __('imports.controle.import_fait', [
            'nombre' => (string) $nombre,
            'module' => $module->nom,
        ]));
    }

    // =====================================================================
    // Onglet 2 — Sauvegardes de la base
    // =====================================================================

    public function genererSauvegarde(SauvegardeManuelleService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        try {
            $resultat = $service->genererMaintenant();
        } catch (RuntimeException $refus) {
            $this->addError('sauvegarde', $refus->getMessage());

            return;
        }

        // Le bandeau VERT du maître (« Sauvegarde générée … Téléchargez-la »)
        // — porté par la session, pour une seule requête, comme un flash.
        session()->flash('ie-sauvegarde-generee', basename($resultat['fichier']));
        session()->flash('pwa-succes', __('pwa.import_export.sauvegardes_generation_reussie', [
            'fichier' => basename($resultat['fichier']),
            'taille' => $this->formaterTaille($resultat['octets']),
        ]));
    }

    /**
     * Téléchargement — LECTURE d'un fichier déjà produit, jamais une écriture
     * en base. Le fichier témoin « téléchargée » posé au passage est ce qui
     * éteint le rappel du maître : c'est le téléchargement qui met à l'abri.
     */
    public function telechargerSauvegarde(string $nom, SauvegardeManuelleService $service): ?BinaryFileResponse
    {
        $chemin = $service->cheminSiExiste($nom);

        if ($chemin === null) {
            abort(404);
        }

        $service->marquerTelechargee($nom);

        return response()->download($chemin);
    }

    /**
     * « Retirer de la liste » — la confirmation forte du maître ne s'ouvre
     * QUE pour une sauvegarde jamais téléchargée (« il n'en existe aucune
     * copie ailleurs ») ; une sauvegarde téléchargée se retire directement.
     */
    public function retirerSauvegarde(string $nom, SauvegardeManuelleService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        $fichier = collect($service->fichiers())->firstWhere('nom', $nom);

        if ($fichier === null) {
            return;
        }

        if (! $fichier['telechargee']) {
            $this->ouvrirFormulaire('retrait_sauvegarde');
            $this->sauvegardeARetirer = $nom;

            return;
        }

        $service->supprimer($nom);
        session()->flash('pwa-succes', __('pwa.import_export.sauvegarde_retiree'));
    }

    public function confirmerRetraitSauvegarde(SauvegardeManuelleService $service): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->sauvegardeARetirer !== null) {
            $service->supprimer($this->sauvegardeARetirer);
        }

        $this->terminerFormulaire(__('pwa.import_export.sauvegarde_retiree'));
    }

    /**
     * « Exporter une table existante » — ouvre la modale du maître. État
     * d'interface, aucune écriture (inscrite en `METHODES_DE_LECTURE`).
     */
    public function ouvrirExport(): void
    {
        // PAS `ouvrirFormulaire()` : ce délégué exige le niveau C, et
        // l'export est une LECTURE ouverte à qui peut lire l'écran (même
        // famille que PA-119 — un rôle en L doit pouvoir sortir une table
        // que l'écran de son module lui affiche déjà). Remise à zéro à la
        // main, comme `MonProfil::ouvrirFormulaireMotDePasse()`.
        $this->reset(['tableExport']);
        $this->resetValidation();
        $this->etatFormulaire = 'export_table';
    }

    /**
     * Le contenu RÉEL de la table choisie, au format JSON — une LECTURE, sur
     * la liste fermée d'`ExportTableService` (jamais `utilisateurs` ni les
     * jetons). Journalisée nulle part : l'export rend ce que l'écran d'un
     * module affiche déjà à qui a le droit de le lire.
     */
    public function exporterTable(ExportTableService $service): ?StreamedResponse
    {
        if ($this->tableExport === '') {
            $this->addError('tableExport', __('pwa.import_export.export_table_choisir'));

            return null;
        }

        try {
            $json = $service->exporterJson($this->tableExport);
        } catch (RuntimeException $refus) {
            $this->addError('tableExport', $refus->getMessage());

            return null;
        }

        $nom = $this->tableExport.'.json';
        $this->etatFormulaire = null;

        return response()->streamDownload(static function () use ($json): void {
            echo $json;
        }, $nom, ['Content-Type' => 'application/json; charset=UTF-8']);
    }

    // =====================================================================
    // Onglet 3 — Restaurer
    // =====================================================================

    public function restaurerArchive(string $type, string $id, RegistreArchivesService $registre): void
    {
        $this->exigerEcriture(self::MODULE);

        try {
            $libelle = $registre->restaurer($type, $id);
        } catch (RuntimeException $refus) {
            $this->addError('archives', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('pwa.import_export.archive_restauree', ['element' => $libelle]));
    }

    /**
     * La purge s'OUVRE en modale de confirmation forte — et seulement pour
     * l'administrateur : « réservée à l'administrateur et n'a pas de retour »
     * (encadré du maître). Le rôle est revérifié à l'exécution.
     */
    public function ouvrirPurge(string $type, string $id, RegistreArchivesService $registre): void
    {
        $this->exigerSuperAdmin();
        $this->ouvrirFormulaire('purge');

        $entree = collect($registre->archives())
            ->first(static fn (array $e): bool => $e['type'] === $type && $e['id'] === $id);

        if ($entree === null) {
            $this->etatFormulaire = null;

            return;
        }

        $this->purgeType = $type;
        $this->purgeId = $id;
        $this->purgeLibelle = $entree['libelle'];
    }

    public function purgerArchive(RegistreArchivesService $registre): void
    {
        $this->exigerSuperAdmin();
        $this->exigerEcriture(self::MODULE);

        if ($this->purgeType === null || $this->purgeId === null) {
            $this->etatFormulaire = null;

            return;
        }

        try {
            $libelle = $registre->purger($this->purgeType, $this->purgeId);
        } catch (RuntimeException $refus) {
            // Refus MOTIVÉ, affiché dans la modale restée ouverte — un
            // élément engagé ou référencé ne se purge pas.
            $this->addError('purge', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('pwa.import_export.archive_purgee', ['element' => $libelle]));
    }

    // =====================================================================
    // Onglet 4 — Réinitialiser les données de test
    // =====================================================================

    /**
     * « Réinitialiser comme neuf » (demande PO du 14/10/2026, lot E) — réservé
     * aux rôles d'administration, revérifié à l'ouverture ET à l'exécution.
     */
    public function ouvrirReinitialisation(ReinitialisationDonneesTestService $service): void
    {
        $this->exigerAdministration($service);
        $this->ouvrirFormulaire('reinitialisation');
    }

    public function reinitialiserDonneesTest(ReinitialisationDonneesTestService $service): void
    {
        $this->exigerAdministration($service);

        $donnees = $this->validerEcriture([
            'phraseConfirmationReset' => ['required', 'string'],
        ]);

        $attendue = __('pwa.import_export.seeders_phrase_confirmation');

        // La casse est tolérée (le maître compare en majuscules, l.865) — le
        // MOT, jamais : une saisie plutôt qu'un simple clic est « la seule
        // barrière qui résiste à un double-clic distrait ».
        if (mb_strtoupper(trim((string) $donnees['phraseConfirmationReset'])) !== $attendue) {
            $this->addError('phraseConfirmationReset', __('pwa.import_export.seeders_phrase_invalide', [
                'phrase' => $attendue,
            ]));

            return;
        }

        try {
            /** @var \App\Models\User|null $auteur */
            $auteur = auth()->user();
            // La session de l'administrateur qui agit est épargnée : il reste
            // connecté (pilote de session `database` ; sans effet sinon).
            $resultat = $service->executer($auteur, session()->getId());
        } catch (RuntimeException $refus) {
            $this->addError('phraseConfirmationReset', $refus->getMessage());

            return;
        }

        // Le compte et la session SURVIVENT : les tables préservées portent
        // l'identité. Rien n'est semé à nouveau : le système est neuf.
        $this->terminerFormulaire(__('pwa.import_export.seeders_fait', [
            'nombre' => (string) $resultat['videes'],
            'lignes' => (string) $resultat['lignes'],
            'sauvegarde' => $resultat['sauvegarde'],
        ]));
    }

    private function exigerAdministration(ReinitialisationDonneesTestService $service): void
    {
        /** @var \App\Models\User|null $utilisateur */
        $utilisateur = auth()->user();

        if (! $service->estPermisA($utilisateur)) {
            abort(403, __('pwa.import_export.reset_refuse_role'));
        }
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // ================================================================ rendu

    public function render(
        SauvegardeManuelleService $sauvegardes,
        ReinitialisationDonneesTestService $reinitialisation,
        ExportTableService $exportTables,
        RegistreArchivesService $registreArchives,
    ): View {
        $fichiers = $sauvegardes->fichiers();
        $archives = $registreArchives->archives();
        $restaurees = $registreArchives->restaurees();

        $module = ReferentielsImport::parCle($this->moduleImport);

        return view('pwa.transverse.import-export', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'titrePage' => __('pwa.import_export.titre'),
            'peutEcrire' => $this->peutEcrire(),
            'estAdministrateur' => auth()->user()?->role?->libelle === 'administrateur',
            // Le bouton de purge n'est offert qu'au SUPER_ADMIN (PO 03/09/2026).
            'estSuperAdmin' => auth()->user()?->estSuperAdmin() ?? false,

            // Onglet 1 — importer
            'modulesImportables' => ReferentielsImport::definitions(),
            'moduleChoisi' => $module,
            'historiqueImports' => JournalImport::query()->with('utilisateur')
                ->orderByDesc('date_heure')->limit(20)->get(),

            // Onglet 2 — sauvegardes
            'fichiersSauvegarde' => $fichiers,
            'nombreTables' => $sauvegardes->nombreTables(),
            'sauvegardeEnAttente' => collect($fichiers)->first(
                static fn (array $f): bool => ! $f['telechargee'],
            ),
            'sauvegardeGeneree' => session('ie-sauvegarde-generee'),

            // Onglet 3 — restaurer
            'archives' => $this->archivesFiltrees($archives, $restaurees),
            'nombreRestaurables' => count($archives),

            // Onglet 4 — seeders
            'reinitialisationAutorisee' => $reinitialisation->estAutorisee(),
            'reinitialisationOuverte' => $reinitialisation->estOuverte(),
            'reinitialisationPermise' => $reinitialisation->estPermisA(auth()->user()),
            'tablesEffacables' => $reinitialisation->tablesEffacables(),
            'tablesPreservees' => $reinitialisation->tablesPreservees(),
        ]))->layout('layouts.pwa', ['title' => __('pwa.import_export.titre_page')]);
    }

    // ---------------------------------------------------------------- privé

    /**
     * Le filtre et la recherche du maître, appliqués côté serveur.
     *
     * @param  list<array{type: string, id: string, libelle: string, module: string,
     *                    archive_le: ?\Carbon\CarbonInterface, archive_par: ?string, restaure: bool}>  $archives
     * @param  list<array{type: string, id: string, libelle: string, module: string,
     *                    archive_le: ?\Carbon\CarbonInterface, archive_par: ?string, restaure: bool}>  $restaurees
     * @return list<array{type: string, id: string, libelle: string, module: string,
     *                    archive_le: ?\Carbon\CarbonInterface, archive_par: ?string, restaure: bool}>
     */
    private function archivesFiltrees(array $archives, array $restaurees): array
    {
        $liste = match ($this->filtreArchives) {
            'toutes' => array_merge($archives, $restaurees),
            'restaurees' => $restaurees,
            default => $archives,
        };

        $terme = mb_strtolower(trim($this->rechercheArchives));

        if ($terme === '') {
            return $liste;
        }

        return array_values(array_filter(
            $liste,
            static fn (array $e): bool => str_contains(mb_strtolower($e['libelle']), $terme)
                || str_contains(mb_strtolower($e['module']), $terme),
        ));
    }

    /**
     * La PURGE (suppression physique d'un element archive) est reservee au
     * SUPER_ADMIN — directive PO du 03/09/2026. L'administrateur restaure
     * et reinitialise ; lui seul purge.
     */
    private function exigerSuperAdmin(): void
    {
        if (! (auth()->user()?->estSuperAdmin() ?? false)) {
            abort(403);
        }
    }

    private function peutEcrire(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur !== null
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    private function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'importer';
    }

    private function formaterTaille(int $octets): string
    {
        if ($octets >= 1_048_576) {
            return number_format($octets / 1_048_576, 1, ',', ' ') . ' Mo';
        }

        if ($octets >= 1024) {
            return number_format($octets / 1024, 1, ',', ' ') . ' Ko';
        }

        return $octets . ' o';
    }

    /**
     * Un flux CSV avec BOM UTF-8 et séparateur point-virgule — convention
     * serveur RG-19, celle qu'Excel francophone ouvre sans boîte de dialogue.
     *
     * @param  callable(resource): void  $ecrire
     */
    private function fluxCsv(string $nom, callable $ecrire): StreamedResponse
    {
        return response()->streamDownload(
            static function () use ($ecrire): void {
                $sortie = fopen('php://output', 'w');

                if ($sortie === false) {
                    return;
                }

                fwrite($sortie, "\xEF\xBB\xBF");
                $ecrire($sortie);
                fclose($sortie);
            },
            $nom,
            ['Content-Type' => 'text/csv; charset=UTF-8'],
        );
    }
}
