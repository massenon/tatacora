<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Services;

use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use RuntimeException;
use Throwable;

/**
 * Suivi du parc : entretiens et carburations (M8, EF-M8-05) — et, depuis le
 * 02/09/2026, les décisions de parc archiver/restaurer/purger.
 *
 * Extrait de `VehiculeController::enregistrerEntretien` (PA-159, lot 0b) :
 * `LARAVEL_PWA.md` §3 impose qu'un composant Livewire appelle un Service de
 * domaine — ce service est le point d'entrée commun de l'API et de la PWA.
 * Les règles de saisie vivent dans `EnregistrerEntretienRequest`, créée dans
 * le même lot pour que la PWA ait une source de règles à réutiliser via
 * `ReglesDeLApi` (le contrôleur validait EN LIGNE, donc rien n'était
 * réutilisable).
 *
 * ## Pourquoi « Parc » et pas « Entretien »
 *
 * C'est le service des écritures de suivi du parc, pas d'une seule table.
 * ⚠ « Aucun chemin du dépôt ne crée un véhicule » (plan PA-159) est FAUX
 * depuis la vague CRUD : `Locations::enregistrerVehicule()` crée au parc —
 * la phrase avait vieilli ici sans être rouverte (PA-144), corrigée le
 * 02/09/2026.
 *
 * ## Archiver / restaurer / purger vivent ICI depuis le 02/09/2026
 *
 * Extraits de l'écran `Locations` pour que l'onglet « Restaurer »
 * d'Import & Export emprunte le MÊME chemin — deux écrivains du même statut
 * auraient divergé au premier verrou oublié. `hors_service` est l'archive de
 * ce schéma (`contrats_location` n'a pas d'équivalent — PA-50) ; `entretien`
 * et `loue` sont des états d'exploitation, jamais touchés par ces gestes.
 *
 * @see EF-M8-05 Suivi des entretiens et carburations
 * @see RG-15 Journalisation (trait Auditable sur EntretienVehicule et Vehicule)
 */
class ParcVehiculeService
{
    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerEntretienRequest` ou les règles qui en dérivent
     */
    public function enregistrerEntretien(array $donnees): EntretienVehicule
    {
        return EntretienVehicule::create($donnees);
    }

    /**
     * Les contrats qui ENGAGENT le véhicule — le verrou du maître : un
     * élément engagé ailleurs ne s'archive pas et ne se purge pas.
     *
     * @return Collection<int, ContratLocation>
     */
    public function contratsEngages(Vehicule $vehicule): Collection
    {
        return ContratLocation::query()
            ->where('vehicule_id', $vehicule->id)
            ->where('statut', '!=', 'annule')
            ->where('date_fin', '>=', CarbonImmutable::today()->format('Y-m-d'))
            ->orderBy('date_debut')
            ->get();
    }

    /**
     * Les contrats qui CHEVAUCHENT la fenêtre demandée — la requête de
     * l'écran M8, remontée ici le 02/09/2026 pour que la carte « Location de
     * véhicules » de l'accueil lise la même population que l'écran, jamais
     * une seconde requête écrite à côté (PA-121). Le prédicat de
     * chevauchement est celui de RG-08 (`date_fin >= début ET date_début <=
     * fin`), bornes inclusives.
     *
     * @return \Illuminate\Database\Eloquent\Builder<ContratLocation>
     */
    public function contratsSurFenetre(CarbonImmutable $debut, CarbonImmutable $fin): \Illuminate\Database\Eloquent\Builder
    {
        return ContratLocation::query()
            ->where('date_fin', '>=', $debut->format('Y-m-d'))
            ->where('date_debut', '<=', $fin->format('Y-m-d'));
    }

    /**
     * Les quatre agrégats de contrats de l'écran M8 — actifs, jours loués,
     * chiffre d'affaires, reste à encaisser — UNE seule formule pour l'écran
     * et pour la carte d'accueil (extraite de `Locations::render()` le
     * 02/09/2026, jamais recopiée).
     *
     * « Actif » = `statut !== 'annule'` : la seule définition du dépôt
     * (l'écran M8 et `contratsEngages()` l'écrivent déjà ainsi). Le montant
     * est LA COLONNE `montant` (celle que l'écran affiche), pas le calcul
     * `tarif_jour × jours` d'`EtatLocations` — les deux peuvent diverger, et
     * la carte d'accueil renvoie vers l'écran. Le repli `?? '0'` est
     * délibéré : `montant` et `reste_a_payer` ne sont pas dans `$fillable`,
     * les contrats créés par l'API ne portent que le défaut zéro.
     *
     * @param  Collection<int, ContratLocation>  $contrats
     * @return array{contrats_actifs: int, jours_loues: int, chiffre_affaires: string, reste_a_encaisser: string}
     */
    public static function agregerContratsActifs(Collection $contrats): array
    {
        $actifs = $contrats->filter(static fn (ContratLocation $c): bool => $c->statut !== 'annule');

        $joursLoues = 0;
        $chiffreAffaires = '0.00';
        $resteAEncaisser = '0.00';

        foreach ($actifs as $contrat) {
            $joursLoues += $contrat->nombreJours();
            $chiffreAffaires = bcadd($chiffreAffaires, (string) ($contrat->montant ?? '0'), 2);
            $resteAEncaisser = bcadd($resteAEncaisser, (string) ($contrat->reste_a_payer ?? '0'), 2);
        }

        return [
            'contrats_actifs' => $actifs->count(),
            'jours_loues' => $joursLoues,
            'chiffre_affaires' => $chiffreAffaires,
            'reste_a_encaisser' => $resteAEncaisser,
        ];
    }

    /**
     * Archive le véhicule — `hors_service`, jamais un `delete()` : les
     * contrats passés qui le citent doivent rester lisibles.
     *
     * @throws RuntimeException le véhicule est engagé sur un contrat en cours
     */
    public function archiver(Vehicule $vehicule): void
    {
        $contrats = $this->contratsEngages($vehicule);

        if ($contrats->isNotEmpty()) {
            throw new RuntimeException($this->messageVerrou($contrats));
        }

        $vehicule->update(['statut' => 'hors_service']);
    }

    /**
     * Remet au parc un véhicule archivé ou immobilisé — la moitié qui
     * manquerait sinon : « reste restaurable » sans chemin de retour est le
     * défaut PA-59/60/61 sous une autre forme.
     */
    public function remettreEnService(Vehicule $vehicule): void
    {
        $vehicule->update(['statut' => 'disponible']);
    }

    /**
     * Purge DÉFINITIVE d'un véhicule ARCHIVÉ — l'écran ajoute sa garde de rôle.
     *
     * @throws RuntimeException non archivé, engagé, ou encore référencé (les
     *                          FK `restrictOnDelete` du schéma ont le dernier mot)
     */
    public function purger(Vehicule $vehicule): void
    {
        if ($vehicule->statut !== 'hors_service') {
            throw new RuntimeException(__('pwa.import_export.purge_refusee_non_archive'));
        }

        $contrats = $this->contratsEngages($vehicule);

        if ($contrats->isNotEmpty()) {
            throw new RuntimeException($this->messageVerrou($contrats));
        }

        // Un contrat ou un entretien PASSÉ (hors du verrou d'engagement) le
        // référence encore : refus AVANT le `delete()` — le même verdict que
        // `restrictOnDelete`, mais nommé.
        if (ContratLocation::query()->where('vehicule_id', $vehicule->id)->exists()
            || EntretienVehicule::query()->where('vehicule_id', $vehicule->id)->exists()) {
            throw new RuntimeException(__('pwa.import_export.purge_refusee_referencee'));
        }

        try {
            $vehicule->delete();
        } catch (Throwable) {
            // Le filet des références que ce service ne connaît pas : une FK
            // ajoutée demain doit rendre le même refus nommé, jamais une
            // page d'erreur.
            throw new RuntimeException(__('pwa.import_export.purge_refusee_referencee'));
        }
    }

    /**
     * @param  Collection<int, ContratLocation>  $contrats
     */
    private function messageVerrou(Collection $contrats): string
    {
        $apercu = $contrats->take(3)->map(static fn (ContratLocation $c): string => __(
            'vehicules.pwa.verrou_contrat',
            [
                'numero' => (string) ($c->numero ?? $c->id),
                'debut' => $c->date_debut->format('d/m/Y'),
                'fin' => $c->date_fin->format('d/m/Y'),
            ],
        ))->implode(' · ');

        return __('vehicules.pwa.verrou', [
            'nombre' => $contrats->count(),
            'apercu' => $apercu.($contrats->count() > 3 ? ' …' : ''),
        ]);
    }
}
