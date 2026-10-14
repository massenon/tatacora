<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Services\DepenseService;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Schema;

/**
 * Cinq dépenses de démonstration — passées PAR le service, écritures comprises.
 *
 * ## Ce seeder est aussi une preuve d'exécution
 *
 * Il appelle `DepenseService::enregistrer()`, donc `PasserEcritureService`,
 * donc `EcritureComptableService`. Un `db:seed` qui aboutit prouve que le
 * chemin dépense → pièce comptable équilibrée → grand livre fonctionne
 * réellement, sur une vraie base. La version antérieure écrivait `Depense` en
 * direct et n'a jamais rien prouvé : les cinq dépenses qu'elle posait étaient
 * précisément celles qu'aucune écriture ne suivait.
 *
 * Il exige donc `ComptabiliteReferentielSeeder` avant lui — sans plan
 * comptable, sans journaux et sans exercice ouvert, chaque dépense est refusée.
 * L'ordre est posé dans `DatabaseSeeder`.
 *
 * ## Les numéros de compte ont CHANGÉ, et ce n'est pas cosmétique
 *
 * Les codes antérieurs — `601`, `614`, `6051`, `6052`, `628` — n'existent dans
 * aucun plan comptable du dépôt. Ils venaient d'une saisie de mémoire, et
 * n'avaient jamais été confrontés à un référentiel puisqu'aucune écriture
 * n'était tentée. Ils sont remplacés par les numéros de
 * `docs/ATELIER_PLAN_COMPTABLE.md` §3.
 *
 * ⚠ **Une lacune du plan documenté, signalée au Comptable** : il ne porte
 * aucun compte dédié à l'eau et à l'électricité. La dépense correspondante est
 * imputée depuis le 10/10/2026 à 6052 « Fournitures non stockables- Electricité »
 * et 6051 « Fournitures non stockables-Eau » du plan du PO (l'ancien 604000 n'y
 * figure pas sous ce sens).
 */
class DepensesSeeder extends Seeder
{
    public function run(): void
    {
        if (!Schema::hasTable('depenses')) {
            return;
        }

        if (Depense::count() > 0) {
            return;
        }

        $service = app(DepenseService::class);
        $admin = User::first();

        // Centre de coût de chaque dépense semée, selon sa nature (RG-12) : denrées
        // -> Restaurant, minibus des groupes -> Tourisme, énergie -> Structure,
        // forfait de la Réception -> Hébergement.
        $centres = \App\Domain\Comptabilite\Models\CentreCout::query()->pluck('id', 'libelle')->all();

        $exemples = [
            [
                'libelle' => 'Marché du matin — Légumes & condiments',
                'centre' => 'Restaurant',
                'tresorerie' => 'caisse',
                'jours' => 2,
                'lignes' => [
                    ['libelle' => 'Achat d\'oignons (2 sacs)', 'compte_charge' => ComptesSyscohada::ACHATS_MARCHANDISES, 'nature' => 'Oignon', 'famille' => 'Marché', 'montant' => '15000.00'],
                    ['libelle' => 'Tomates fraîches', 'compte_charge' => ComptesSyscohada::ACHATS_MARCHANDISES, 'nature' => 'Tomate', 'famille' => 'Marché', 'montant' => '8500.00'],
                    ['libelle' => 'Piments & condiments', 'compte_charge' => ComptesSyscohada::ACHATS_MARCHANDISES, 'nature' => 'Piment', 'famille' => 'Marché', 'montant' => '3500.00'],
                ],
            ],
            [
                'libelle' => 'Location de minibus — groupe touristique',
                'centre' => 'Tourisme',
                'tresorerie' => 'caisse',
                'jours' => 5,
                'lignes' => [
                    ['libelle' => 'Location minibus à la journée', 'compte_charge' => ComptesSyscohada::LOCATION_MATERIEL_TRANSPORT, 'nature' => 'Transport', 'famille' => 'Services', 'montant' => '25000.00'],
                ],
            ],
            [
                'libelle' => 'Facture d\'électricité SBEE & Eau SONEB',
                'centre' => 'Structure',
                'tresorerie' => 'banque',
                'jours' => 10,
                'lignes' => [
                    ['libelle' => 'Recharge compteur Électricité', 'compte_charge' => ComptesSyscohada::ELECTRICITE, 'nature' => 'Électricité / eau', 'famille' => 'Services', 'montant' => '45000.00'],
                    ['libelle' => 'Abonnement Eau', 'compte_charge' => ComptesSyscohada::EAU, 'nature' => 'Électricité / eau', 'famille' => 'Services', 'montant' => '18000.00'],
                ],
            ],
            [
                'libelle' => 'Recharge Crédit Flotte Téléphonique',
                'centre' => 'Hébergement',
                'tresorerie' => 'momo',
                'jours' => 12,
                'lignes' => [
                    ['libelle' => 'Forfait Internet & GSM Réception', 'compte_charge' => ComptesSyscohada::TELEPHONE_INTERNET, 'nature' => 'Communication', 'famille' => 'Services', 'montant' => '12000.00'],
                ],
            ],
            [
                'libelle' => 'Approvisionnement Poissonnerie & Boucherie',
                'centre' => 'Restaurant',
                'tresorerie' => 'caisse',
                'jours' => 15,
                'lignes' => [
                    ['libelle' => 'Lot de viande de bœuf (15kg)', 'compte_charge' => ComptesSyscohada::ACHATS_MARCHANDISES, 'nature' => 'Viande', 'famille' => 'Marché', 'montant' => '48000.00'],
                    ['libelle' => 'Poissons Capitaine frais', 'compte_charge' => ComptesSyscohada::ACHATS_MARCHANDISES, 'nature' => 'Poisson', 'famille' => 'Marché', 'montant' => '32000.00'],
                ],
            ],
        ];

        foreach ($exemples as $item) {
            $service->enregistrer([
                'centre_id' => $centres[$item['centre']] ?? null,
                'date_transaction' => CarbonImmutable::today()->subDays($item['jours'])->format('Y-m-d'),
                'tresorerie' => $item['tresorerie'],
                'libelle' => $item['libelle'],
                'lignes' => $item['lignes'],
            ], $admin);
        }
    }
}
