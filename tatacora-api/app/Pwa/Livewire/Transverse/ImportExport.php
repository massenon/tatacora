<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Shared\Backup\Services\ExportTableService;
use App\Shared\Backup\Services\SauvegardeManuelleService;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Models\JournalImport;
use App\Shared\ImportExport\Services\CarteGiteChezNoelService;
use App\Shared\ImportExport\Services\ControleImportService;
use App\Shared\ImportExport\Services\ImportReferentielsService;
use App\Shared\ImportExport\Services\RegistreArchivesService;
use App\Shared\ImportExport\Services\TableurService;
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
 *   modules), fiche « Colonnes attendues », modèle `.xlsx` généré depuis la MÊME
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
 * - **Réinitialiser les données de test** — n'est PLUS ici : « Ramène le bouton
 *   RÉINITIALISER LES DONNÉES DE TEST dans PARAMÈTRES » (PO, 09/11/2026). La
 *   fonction, ses verrous (environnement, bascule `reinitialisation_seeders`,
 *   phase d'essais), la phrase « VIDER » à retaper et le journal d'audit vivent
 *   dans l'onglet « Activation & Sécurité » de `Parametres`, INCHANGÉS.
 *
 * ## Qui voit quoi (11/11/2026, PO : le CRUD de la page suit le droit `IMPORT_EXPORT`)
 *
 * EXCEPTION (PO, 11/11/2026) : les utilisateurs SYSTÈME (`super_admin`, `administrateur`) ont
 * TOUJOURS l'accès complet (écran, trois onglets, import, sauvegarde, téléchargement, export,
 * restauration), même sans RBAC : `User::niveauSurModule('IMPORT_EXPORT')` rend `C` pour eux
 * (`User::MODULES_IMPLICITES_SYSTEME`), quelle que soit la ligne en base. Le reste suit le RBAC.
 *
 * `IMPORT_EXPORT` en `L` : la page s'ouvre en LECTURE SEULE (fiche des colonnes attendues,
 * historique, bandeau « Accès lecture seule »), sans onglets de sauvegarde ni geste. En `C`
 * (gérant, comptable, administrateurs par défaut) : import (modèle, contrôle, confirmation),
 * génération / retrait / téléchargement de sauvegarde, export d'une table, restauration. Le droit
 * est relu à CHAQUE requête (aucun cache) : un droit passé de `C` à `L` change la page à la
 * requête suivante, sans reconnexion. L'import d'un module exige en plus l'ÉCRITURE du module
 * importé (`ModuleImport::$module`). Gardes conservées, par sécurité : la purge définitive reste
 * réservée au super administrateur, et la réinitialisation des données de test reste dans
 * Paramètres (administrateurs). Le téléchargement d'une sauvegarde (copie intégrale de la base)
 * et l'export de table exigent `C`, jamais `L` : le droit de lecture est ouvert à tous les rôles.
 *
 * @see LARAVEL_PWA.md §1, §3
 * @see DIRECTIVE_CONFORMITE_100.md Article 3.3, Article 8
 */
#[Title('Import & Export — LogiReStock — TATACORA AFRIQUE')]
class ImportExport extends PageTransverse
{
    use FormulaireModal;
    use WithFileUploads;

    /**
     * Le module RBAC de l'écran : le droit transverse `IMPORT_EXPORT` (11/11/2026, PO), modifiable
     * à l'écran Rôles & Permissions — `L` voit la page en lecture seule, `C` agit (import,
     * sauvegardes, export, restauration). Ce n'est plus `PARAM` ni un nom de rôle.
     */
    public const MODULE = 'IMPORT_EXPORT';

    public const ONGLETS = ['importer', 'sauvegardes', 'restaurer'];

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

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'export_table' => ['tableExport'],
            'retrait_sauvegarde' => ['sauvegardeARetirer'],
            'purge' => ['purgeType', 'purgeId', 'purgeLibelle'],
        ];
    }

    // =====================================================================
    // Onglet 1 — Importer les données
    // =====================================================================

    /**
     * Le fichier modèle — un VRAI classeur `.xlsx`, généré depuis la MÊME
     * déclaration que le contrôle (`ReferentielsImport`), règle du maître :
     * « il ne peut pas s'en écarter ». Feuille « Modèle » (en-têtes en gras,
     * une ligne d'exemple) et feuille « Aide » (une ligne par colonne).
     *
     * Le CSV au point-virgule qui l'a précédé s'ouvrait en UNE seule colonne
     * dans un Excel réglé sur la virgule (30/10/2026, `TableurService`).
     */
    public function telechargerModele(TableurService $tableur): ?StreamedResponse
    {
        $this->exigerEcriture(self::MODULE);

        $module = ReferentielsImport::parCle($this->moduleImport);

        if ($module === null) {
            return null;
        }

        $octets = $tableur->ecrireClasseur($module->nom, $module->description, $module->colonnes);

        return $this->fluxXlsx(__('imports.xlsx.nom_fichier', ['cle' => $module->cle]), $octets);
    }

    /**
     * « Carte du Gîte Chez Noël (exemple) » — le modèle du module choisi,
     * PRÉREMPLI avec la carte des affiches (m6 articles des boissons, m5
     * boissons, m4 plats). Sans stock ni quantité : il s'ajoute après.
     */
    public function telechargerExempleGite(CarteGiteChezNoelService $carte): ?StreamedResponse
    {
        $this->exigerEcriture(self::MODULE);

        if (! in_array($this->moduleImport, CarteGiteChezNoelService::MODULES, true)) {
            return null;
        }

        return $this->fluxXlsx(
            __('imports.xlsx.nom_fichier_gite', ['cle' => $this->moduleImport]),
            $carte->classeur($this->moduleImport),
        );
    }

    /**
     * Lit le fichier déposé — `.xlsx` d'abord, CSV en secours.
     *
     * @return list<list<string>>|null `null` : refus, déjà posé sur le champ
     */
    private function lireFichierDepose(ControleImportService $controle): ?array
    {
        try {
            return $controle->analyserFichier(
                (string) $this->fichierImport?->getRealPath(),
                (string) $this->fichierImport?->getClientOriginalName(),
            );
        } catch (RuntimeException $refus) {
            $this->addError('fichierImport', $refus->getMessage());

            return null;
        }
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
            'fichierImport' => ['required', 'file', 'mimes:xlsx,csv,txt', 'max:4096'],
        ]);

        $module = ReferentielsImport::parCle((string) $donnees['moduleImport']);

        if ($module === null) {
            $this->addError('moduleImport', __('imports.controle.module_inconnu'));

            return;
        }

        $this->exigerEcritureDuModuleImporte($module);
        $tableau = $this->lireFichierDepose($controle);

        if ($tableau === null) {
            return;
        }

        $rapport = $controle->controler($module, $tableau);

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
            'fichierImport' => ['required', 'file', 'mimes:xlsx,csv,txt', 'max:4096'],
        ]);

        $module = ReferentielsImport::parCle((string) $donnees['moduleImport']);

        if ($module === null) {
            $this->addError('moduleImport', __('imports.controle.module_inconnu'));

            return;
        }

        $this->exigerEcritureDuModuleImporte($module);
        $tableau = $this->lireFichierDepose($controle);

        if ($tableau === null) {
            return;
        }

        $rapport = $controle->controler($module, $tableau);

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

        if ($rapport->lignes === [] && $rapport->ignorees > 0) {
            // Ré-import d'un fichier déjà importé : rien à ajouter, rien d'écrasé.
            $this->reset(['fichierImport', 'rapportControle']);
            session()->flash('pwa-succes', __('imports.controle.rien_a_ajouter', ['nombre' => (string) $rapport->ignorees, 'module' => $module->nom]));

            return;
        }

        try {
            $nombre = $import->appliquer($module, $rapport->lignes);
        } catch (RuntimeException $refus) {
            $this->addError('fichierImport', $refus->getMessage());

            return;
        }

        $this->reset(['fichierImport', 'rapportControle']);
        session()->flash('pwa-succes', trim(__('imports.controle.import_fait', [
            'nombre' => (string) $nombre,
            'module' => $module->nom,
        ]).($rapport->ignorees > 0 ? ' '.__('imports.controle.dont_ignorees', ['nombre' => (string) $rapport->ignorees]) : '').' '.($import->bilanRapprochement ?? '')));
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
        $this->exigerRoleAdministration();

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
        $this->exigerRoleAdministration();

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
        $this->exigerRoleAdministration();

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
     * Les onglets « Sauvegardes de la base » et « Restaurer » et leurs gestes de LECTURE
     * (téléchargement d'une sauvegarde, export d'une table) exigent le droit `IMPORT_EXPORT` en
     * ÉCRITURE (`C`) : une sauvegarde est la copie intégrale de la base, et `IMPORT_EXPORT = L`
     * est accordé à tous les rôles par défaut (il ne commande que la visibilité de la page).
     */
    /** L'import d'un module exige en plus l'ÉCRITURE du module importé (clients M3, stocks M6…). */
    private function exigerEcritureDuModuleImporte(\App\Shared\ImportExport\Data\ModuleImport $module): void
    {
        $this->exigerEcriture($module->module);
    }

    private function exigerRoleAdministration(): void
    {
        abort_unless($this->accesSauvegardes(), 403);
    }

    private function accesSauvegardes(): bool
    {
        $utilisateur = auth()->user();

        return $utilisateur !== null && $utilisateur->estActif() && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // ================================================================ rendu

    public function render(
        SauvegardeManuelleService $sauvegardes,
        ExportTableService $exportTables,
        RegistreArchivesService $registreArchives,
    ): View {
        $accesAdministration = $this->accesSauvegardes();
        $fichiers = $accesAdministration ? $sauvegardes->fichiers() : [];
        $archives = $accesAdministration ? $registreArchives->archives() : [];
        $restaurees = $accesAdministration ? $registreArchives->restaurees() : [];

        $module = ReferentielsImport::parCle($this->moduleImport);

        return view('pwa.transverse.import-export', array_merge($this->socle(), [
            'onglet' => $this->ongletValide(),
            'titrePage' => __('pwa.import_export.titre'),
            'peutEcrire' => $this->peutEcrire(),
            'accesAdministration' => $accesAdministration,
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
            'nombreTables' => $accesAdministration ? $sauvegardes->nombreTables() : 0,
            'sauvegardeEnAttente' => collect($fichiers)->first(
                static fn (array $f): bool => ! $f['telechargee'],
            ),
            'sauvegardeGeneree' => session('ie-sauvegarde-generee'),

            // Onglet 3 — restaurer
            'archives' => $this->archivesFiltrees($archives, $restaurees),
            'nombreRestaurables' => count($archives),
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
        // Un rôle sans écriture de `IMPORT_EXPORT` n'a que l'onglet « Importer » (lecture seule).
        if (! $this->accesSauvegardes()) {
            return 'importer';
        }

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
     * Un classeur `.xlsx` en téléchargement — le vrai type MIME, jamais
     * `text/csv` : le navigateur et Excel n'ont ainsi rien à deviner.
     */
    private function fluxXlsx(string $nom, string $octets): StreamedResponse
    {
        return response()->streamDownload(
            static function () use ($octets): void {
                echo $octets;
            },
            $nom,
            ['Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
        );
    }
}
