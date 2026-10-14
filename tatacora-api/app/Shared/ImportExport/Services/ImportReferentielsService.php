<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\SejourService;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Shared\ImportExport\Data\ModuleImport;
use App\Shared\ImportExport\Models\JournalImport;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * Application d'un import CONTRÔLÉ — la moitié « appliquer » du maître
 * (`import-export-engine.js` §2, `appliquer`), 02/09/2026.
 *
 * ## AUCUN IMPORT PARTIEL — une transaction unique
 *
 * Règle du maître (`import-export.html` l.135-139) : « Tant qu'une erreur
 * subsiste, rien n'entre en base. Importer "ce qui passe" laisserait un jeu
 * incomplet dont personne ne saurait dire ce qui manque. » Tout le lot passe
 * dans UNE transaction ; le refus d'un service de domaine sur une seule ligne
 * — même après un contrôle vert, la base a pu bouger entre-temps — annule
 * TOUT, historique compris, et nomme la ligne fautive.
 *
 * ⚠ L'écran M6 Stocks importe autrement (ligne fautive NOMMÉE, lot conservé,
 * `m6-stocks.html` l.487-490) : ce sont les règles de DEUX écrans distincts
 * du maître, pas une divergence à réconcilier.
 *
 * ## Chaque écriture passe par le chemin du domaine
 *
 * Les modules qui ont un `Service` de création l'appellent (M3, M5, M4, M6,
 * M7) ; M1, M8 et M9 écrivent les MÊMES attributs que leur écran PWA
 * (`Hebergement::enregistrerUnite()`, `Locations::enregistrerVehicule()`,
 * `Departs::enregistrerPrestation()`) — référentiels sans verrou RG, comme
 * ces écrans. Jamais un `DB::table()` sur une table gardée par une RG.
 */
class ImportReferentielsService
{
    /**
     * @param  list<array<string, mixed>>  $lignes  lignes CONVERTIES par le contrôle
     * @return int nombre de lignes importées
     *
     * @throws RuntimeException lot refusé — rien n'a été écrit
     */
    public function appliquer(ModuleImport $module, array $lignes): int
    {
        if ($lignes === []) {
            throw new RuntimeException(__('imports.controle.aucune_ligne'));
        }

        return DB::transaction(function () use ($module, $lignes): int {
            foreach ($lignes as $ligne) {
                try {
                    $this->importerLigne($module, $ligne);
                } catch (Throwable $refus) {
                    // Le rollback de la transaction efface TOUT le lot : la
                    // ligne fautive est nommée avec le mot du domaine, jamais
                    // reformulé.
                    throw new RuntimeException(__('imports.controle.refus_service', [
                        'ligne' => (string) ($ligne['_ligne'] ?? '?'),
                        'element' => (string) ($ligne[$module->identifiant] ?? '?'),
                        'raison' => $refus->getMessage(),
                    ]), 0, $refus);
                }
            }

            // L'historique s'écrit DANS la transaction : hors d'elle, un
            // rollback laisserait une entrée annonçant un import effacé.
            JournalImport::create([
                'module_cle' => $module->cle,
                'nombre_lignes' => count($lignes),
                'utilisateur_id' => auth()->id(),
                'date_heure' => now(),
            ]);

            return count($lignes);
        });
    }

    /**
     * @param  array<string, mixed>  $ligne
     */
    private function importerLigne(ModuleImport $module, array $ligne): void
    {
        match ($module->cle) {
            'm3-clients' => app(EnregistrementClientService::class)->creer([
                'nom' => (string) $ligne['nom'],
                'prenom' => $ligne['prenom'] ?? null,
                'type_client' => (string) $ligne['type_client'],
                'telephone' => (string) $ligne['telephone'],
                'email' => $ligne['email'] ?? null,
            ]),
            // Mêmes attributs que `Hebergement::enregistrerUnite()` : l'unité
            // entre au parc LIBRE, le statut n'est jamais importé.
            'm1-hebergement' => UniteHebergement::create([
                'numero' => (string) $ligne['numero'],
                'categorie_id' => (string) $ligne['categorie'],
                'statut' => SejourService::STATUT_LIBRE,
            ]),
            'm5-bar' => app(CarteBoissonService::class)->creer([
                'libelle' => (string) $ligne['libelle'],
                'categorie' => (string) $ligne['categorie'],
                'prix_vente' => (string) $ligne['prix_vente'],
                'article_id' => (string) $ligne['article'],
            ]),
            'm4-restaurant' => app(CartePlatMenuService::class)->creerPlat([
                'libelle' => (string) $ligne['libelle'],
                'categorie' => (string) $ligne['categorie'],
                'prix_vente' => (string) $ligne['prix_vente'],
                'menu_id' => (string) $ligne['menu'],
                'recette_id' => (string) $ligne['recette'],
            ]),
            'm6-stocks' => app(ReferentielArticleService::class)->creer([
                'libelle' => (string) $ligne['libelle'],
                'categorie' => (string) $ligne['categorie'],
                'unite_mesure' => (string) $ligne['unite_mesure'],
                'seuil_alerte' => (string) $ligne['seuil_alerte'],
                // Le mode de suivi n'est pas une colonne d'import ici (il
                // l'est sur l'écran M6, qui a son propre modèle) : le défaut
                // du schéma, `permanent`, décrit le comportement habituel.
                'suivi' => 'permanent',
                'point_stockage_id' => $ligne['point_stockage'] ?? null,
            ]),
            'm7-achats' => app(ReferentielFournisseurService::class)->creer([
                'raison_sociale' => (string) $ligne['raison_sociale'],
                'contact' => $ligne['contact'] ?? null,
                'categorie' => $ligne['categorie'] ?? null,
                'conditions_paiement' => $ligne['conditions_paiement'] ?? null,
                'evaluation' => $ligne['evaluation'] ?? null,
            ]),
            // Mêmes attributs que `Locations::enregistrerVehicule()` : un
            // véhicule importé entre au parc DISPONIBLE.
            'm8-vehicules' => Vehicule::create([
                'immatriculation' => (string) $ligne['immatriculation'],
                'categorie' => (string) $ligne['categorie'],
                'annee' => (int) $ligne['annee'],
                'capacite' => $ligne['capacite'] === null ? null : (int) $ligne['capacite'],
                'transmission' => $ligne['transmission'] ?? null,
                'tarif_jour' => (string) $ligne['tarif_jour'],
                'statut' => 'disponible',
            ]),
            // Mêmes attributs que `Departs::enregistrerPrestation()`.
            'm9-tourisme' => Circuit::create([
                'nom' => (string) $ligne['nom'],
                'theme' => (string) $ligne['theme'],
                'zone' => (string) $ligne['zone'],
                'duree' => (string) $ligne['duree'],
                'prix' => (string) $ligne['prix'],
                'capacite_max' => (int) $ligne['capacite_max'],
            ]),
            default => throw new RuntimeException(__('imports.controle.module_inconnu')),
        };
    }
}
