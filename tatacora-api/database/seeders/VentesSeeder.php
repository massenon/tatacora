<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Schema;

/**
 * Trois ventes de démonstration pour l'historique de caisse.
 *
 * ## Pourquoi ce seeder n'appelle PAS `VenteService`
 *
 * Le service résout chaque ligne contre le catalogue et sort le stock
 * correspondant (RG-05). Un seeder qui l'emprunterait viderait le stock de
 * démonstration à chaque `db:seed`, et échouerait sur une rupture (RG-06) dès
 * que les quantités semées dépasseraient les articles semés — un ordre de
 * seeders devenu fragile pour trois lignes d'illustration.
 *
 * Ces ventes sont donc écrites en direct, et c'est assumé : elles illustrent
 * un écran, elles ne prouvent aucun chemin. Le chemin réel est prouvé par
 * `tests/Feature/Domain/Ventes/VenteServiceTest.php`, contre une vraie base.
 *
 * ## Mais elles sont COMPTABILISÉES, et par le service
 *
 * Depuis la règle du 31/08/2026 — tout mouvement d'argent produit son écriture
 * comptable réelle —, trois ventes de démonstration sans pièce laisseraient le
 * journal des ventes VIDE pendant que celui des dépenses se remplit : la
 * démonstration montrerait une comptabilité qui ne voit que les charges, et le
 * compte de résultat serait négatif de tout le chiffre d'affaires.
 *
 * `VenteService::comptabiliser()` est appelé pour cela — le rattrapage prévu
 * pour les ventes antérieures à la règle. Recopier ici la construction de la
 * pièce aurait été la faute inverse : deux sources de vérité pour une même
 * imputation, qui divergent au premier changement de plan comptable.
 *
 * Cet appel impose l'ordre de `DatabaseSeeder` : ce seeder passe APRÈS
 * `ComptabiliteReferentielSeeder`, qui fournit le plan, les journaux et
 * l'exercice ouvert. Placé avant, il refuserait chaque vente — et le refus
 * serait juste.
 *
 * `utilisateur_id` est désormais une vraie clé étrangère (RG-15) : la
 * détection de type qui vivait ici — « si la colonne est un entier, mettre à
 * NULL » — décrivait le schéma cassé que
 * `2026_09_01_100000_reprendre_ventes_en_uuid` a repris. Elle est retirée : un
 * contournement laissé en place après la correction redevient la règle.
 */
class VentesSeeder extends Seeder
{
    public function __construct(private readonly VenteService $ventes)
    {
    }

    public function run(): void
    {
        if (!Schema::hasTable('ventes')) {
            return;
        }

        if (Vente::count() > 0) {
            return;
        }

        $admin = User::first();
        $utilisateurId = $admin?->id;

        $exemples = [
            [
                'point' => 'Bar',
                'table' => 'Table 3',
                'mode' => 'especes',
                'encaisse' => true,
                'jours' => 0,
                'lignes' => [
                    ['code' => 'BEA-66', 'nom' => 'Béninoise 66 cl', 'categorie' => 'Bar', 'module' => 'M5', 'prix' => 800, 'qte' => 3],
                    ['code' => 'EAU-15', 'nom' => 'Eau minérale 1,5 L', 'categorie' => 'Bar', 'module' => 'M5', 'prix' => 500, 'qte' => 2],
                ],
            ],
            [
                'point' => 'Restaurant',
                'table' => 'Terrasse 1',
                'mode' => 'carte',
                'encaisse' => true,
                'jours' => 1,
                'lignes' => [
                    ['code' => 'PLT-DG', 'nom' => 'Poulet DG', 'categorie' => 'Plats', 'module' => 'M4', 'prix' => 4500, 'qte' => 2],
                    ['code' => 'ENT-SLD', 'nom' => 'Salade peulh', 'categorie' => 'Entrées', 'module' => 'M4', 'prix' => 2000, 'qte' => 1],
                ],
            ],
            [
                'point' => 'Bar',
                'table' => 'Bungalow Wassa',
                'mode' => 'note_chambre',
                'encaisse' => false,
                'jours' => 2,
                'lignes' => [
                    ['code' => 'COCK-TK', 'nom' => 'Cocktail Tatacora', 'categorie' => 'Bar', 'module' => 'M5', 'prix' => 2500, 'qte' => 2],
                ],
            ],
        ];

        foreach ($exemples as $i => $item) {
            $total = 0;
            foreach ($item['lignes'] as $l) {
                $total += ($l['prix'] * $l['qte']);
            }

            $date = CarbonImmutable::now()->subDays($item['jours']);
            $numero = 'V-' . date('Y') . '-' . sprintf('%05d', $i + 1);

            $vente = Vente::create([
                'numero' => $numero,
                'point_vente' => $item['point'],
                'table' => $item['table'],
                'montant_total' => $total,
                'mode_paiement' => $item['mode'],
                'encaisse' => $item['encaisse'],
                'statut' => 'validee',
                'utilisateur_id' => $utilisateurId,
                'created_at' => $date,
            ]);

            if (Schema::hasTable('lignes_vente')) {
                foreach ($item['lignes'] as $lg) {
                    LigneVente::create([
                        'vente_id' => $vente->id,
                        'code' => $lg['code'],
                        'nom' => $lg['nom'],
                        'categorie' => $lg['categorie'],
                        'module' => $lg['module'],
                        'prix_unitaire' => $lg['prix'],
                        'quantite' => $lg['qte'],
                        'montant' => $lg['prix'] * $lg['qte'],
                    ]);
                }
            }

            // La pièce est passée APRÈS les lignes : elle ventile le chiffre
            // d'affaires par module, et le module est porté par la ligne.
            $this->ventes->comptabiliser($vente->refresh());
        }
    }
}
