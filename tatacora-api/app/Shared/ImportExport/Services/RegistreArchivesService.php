<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Shared\Audit\Models\JournalAudit;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;
use RuntimeException;

/**
 * Le registre des ARCHIVES — onglet « Restaurer » d'Import & Export
 * (`import-export.html` l.213-255), 02/09/2026.
 *
 * ## Ce qu'« archive » veut dire sur CE serveur (vérifié le 02/09/2026)
 *
 * Aucune table d'archives commune n'existe : « supprimer = archiver » se
 * matérialise par un STATUT réversible sur le référentiel lui-même, et DEUX
 * familles le portent réellement — les unités d'hébergement et les véhicules,
 * tous deux `hors_service`. Les autres « suppressions » de la PWA sont des
 * gestes métier (annuler une prestation, contre-passer une écriture) qui
 * laissent l'enregistrement lisible sous son propre écran : ils n'ont rien à
 * restaurer ici. Ce registre est donc un AGRÉGAT DÉRIVÉ des statuts réels,
 * jamais une seconde table qu'il faudrait tenir à jour.
 *
 * ## « Déjà restaurées » vient du JOURNAL, pas d'un drapeau
 *
 * Une fois restaurée, l'entrée quitte l'état `hors_service` : aucun drapeau
 * ne subsiste sur la ligne. Les restaurations passées se LISENT de
 * `journal_audit` — le trait `Auditable` (posé sur `Vehicule` depuis PA-159
 * et sur `UniteHebergement` depuis ce lot) y consigne chaque transition
 * `hors_service → …`. Un drapeau dénormalisé aurait fini faux (PA-126).
 *
 * ## Restaurer et purger passent par les services de PARC
 *
 * `ParcHebergementService` et `ParcVehiculeService` — les MÊMES chemins que
 * les écrans M1 et M8, extraits pour ce lot : le verrou d'engagement et le
 * refus motivé y vivent une seule fois.
 */
class RegistreArchivesService
{
    /** Le registre FERMÉ des familles archivables. @var list<string> */
    public const TYPES = ['unite_hebergement', 'vehicule'];

    /**
     * Les éléments actuellement ARCHIVÉS (restaurables).
     *
     * @return list<array{type: string, id: string, libelle: string, module: string,
     *                    archive_le: ?CarbonInterface, archive_par: ?string, restaure: false}>
     */
    public function archives(): array
    {
        $entrees = [];

        foreach (UniteHebergement::query()->where('statut', 'hors_service')->get() as $unite) {
            $entrees[] = [
                'type' => 'unite_hebergement',
                'id' => $unite->id,
                'libelle' => $unite->numero,
                'module' => 'M1',
                // La date d'audit quand elle existe ; `updated_at` sinon — une
                // unité `hors_service` n'est plus touchée par le cycle
                // (`SejourService` l'exclut), sa dernière écriture EST
                // l'archivage. Les lignes d'avant la migration d'audit n'ont
                // pas d'auteur : « — » à l'écran, jamais un nom deviné.
                'archive_le' => $this->dateArchivage($unite->date_modification, $unite->updated_at),
                'archive_par' => $unite->utilisateur_modification_id,
                'restaure' => false,
            ];
        }

        foreach (Vehicule::query()->where('statut', 'hors_service')->get() as $vehicule) {
            $entrees[] = [
                'type' => 'vehicule',
                'id' => $vehicule->id,
                'libelle' => $vehicule->immatriculation,
                'module' => 'M8',
                'archive_le' => $this->dateArchivage($vehicule->date_modification, $vehicule->updated_at),
                'archive_par' => $vehicule->utilisateur_modification_id,
                'restaure' => false,
            ];
        }

        $this->resoudreAuteurs($entrees);

        usort($entrees, static fn (array $a, array $b): int => ($b['archive_le']?->getTimestamp() ?? 0) <=> ($a['archive_le']?->getTimestamp() ?? 0));

        return $entrees;
    }

    /**
     * Les restaurations PASSÉES, lues du journal d'audit (voir l'entête).
     *
     * @return list<array{type: string, id: string, libelle: string, module: string,
     *                    archive_le: ?CarbonInterface, archive_par: ?string, restaure: true}>
     */
    public function restaurees(): array
    {
        $entrees = [];

        $transitions = JournalAudit::query()
            ->where('action', 'modification')
            ->whereIn('entite_concernee', ['unites_hebergement', 'vehicules'])
            ->where('valeur_avant->statut', 'hors_service')
            ->whereNotNull('valeur_apres->statut')
            ->orderByDesc('date_heure')
            ->limit(100)
            ->get();

        foreach ($transitions as $trace) {
            $estUnite = $trace->entite_concernee === 'unites_hebergement';
            $modele = $estUnite
                ? UniteHebergement::find($trace->entite_id)
                : Vehicule::find($trace->entite_id);

            if ($modele === null) {
                continue;   // purgé depuis : il n'y a plus rien à montrer.
            }

            $entrees[] = [
                'type' => $estUnite ? 'unite_hebergement' : 'vehicule',
                'id' => (string) $trace->entite_id,
                'libelle' => $estUnite ? $modele->numero : $modele->immatriculation,
                'module' => $estUnite ? 'M1' : 'M8',
                'archive_le' => $trace->date_heure,
                'archive_par' => $trace->utilisateur_id,
                'restaure' => true,
            ];
        }

        $this->resoudreAuteurs($entrees);

        return $entrees;
    }

    /**
     * La date d'archivage en `Carbon` — les colonnes d'audit n'ont pas de
     * cast `datetime` sur ces modèles (mesuré le 02/09/2026 : elles arrivent
     * en chaîne brute), et l'écran doit pouvoir la formater.
     */
    private function dateArchivage(mixed $dateModification, ?CarbonInterface $updatedAt): ?CarbonInterface
    {
        if ($dateModification instanceof CarbonInterface) {
            return $dateModification;
        }

        if (is_string($dateModification) && $dateModification !== '') {
            return Carbon::parse($dateModification);
        }

        return $updatedAt;
    }

    /**
     * Remplace les identifiants d'auteur par le LOGIN réel — la même
     * convention que l'écran Journal d'audit : « le schéma ne porte aucun nom
     * sur `utilisateurs`, la PWA affiche le login réel », jamais un nom
     * fabriqué. `null` reste `null` : « — » à l'écran.
     *
     * @param  list<array<string, mixed>>  $entrees
     */
    private function resoudreAuteurs(array &$entrees): void
    {
        $identifiants = array_values(array_unique(array_filter(array_column($entrees, 'archive_par'))));

        if ($identifiants === []) {
            return;
        }

        $logins = \App\Models\User::query()->whereIn('id', $identifiants)->pluck('login', 'id');

        foreach ($entrees as &$entree) {
            $entree['archive_par'] = $entree['archive_par'] === null
                ? null
                : $logins->get($entree['archive_par']);
        }
    }

    public function restaurer(string $type, string $id): string
    {
        if ($type === 'unite_hebergement') {
            $unite = UniteHebergement::findOrFail($id);
            app(ParcHebergementService::class)->restaurer($unite);

            return $unite->numero;
        }

        if ($type === 'vehicule') {
            $vehicule = Vehicule::findOrFail($id);
            app(ParcVehiculeService::class)->remettreEnService($vehicule);

            return $vehicule->immatriculation;
        }

        throw new RuntimeException(__('pwa.import_export.archive_type_inconnu'));
    }

    /**
     * @return string le libellé de l'élément purgé
     *
     * @throws RuntimeException refus MOTIVÉ (engagé, référencé, non archivé)
     */
    public function purger(string $type, string $id): string
    {
        if ($type === 'unite_hebergement') {
            $unite = UniteHebergement::findOrFail($id);
            app(ParcHebergementService::class)->purger($unite);

            return $unite->numero;
        }

        if ($type === 'vehicule') {
            $vehicule = Vehicule::findOrFail($id);
            app(ParcVehiculeService::class)->purger($vehicule);

            return $vehicule->immatriculation;
        }

        throw new RuntimeException(__('pwa.import_export.archive_type_inconnu'));
    }
}
