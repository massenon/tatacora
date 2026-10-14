<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Auth;
use RuntimeException;

/**
 * Deux commandes d'achat de démonstration — écrites par `CommandeAchatService`.
 *
 * ## Ce que ce seeder remplace, et pourquoi le remplacement était nécessaire
 *
 * `FournisseursCommandesSeeder` (supprimé le 31/08/2026) posait UNE commande en
 * `DB::table()`, **sans aucune ligne**, avec `statut = 'receptionnee'` et
 * `montant_regle = montant_total = 240 000 F`. Trois défauts dans une seule
 * insertion :
 *
 * 1. une commande « Reçue » dont **aucune marchandise n'est jamais entrée en
 *    stock** — l'indicateur qui affirme un état qu'il n'a pas vérifié
 *    (PA-59/60/61). `CommandeAchatService` refuse ce statut à la création
 *    précisément pour cela, et le `DB::table()` contournait le refus ;
 * 2. une commande **sans ligne** est réceptionnable, et sa réception serait
 *    déclarée `non_conforme` pour un motif que personne ne pourrait expliquer
 *    (`ReceptionService::evaluerConformite()` ne trouve rien en face) ;
 * 3. `montant_regle` renseigné alors qu'aucun paiement n'existe — le modèle
 *    `Paiement` n'existe pas (PA-21), et l'arbitrage (d) du 31/08/2026 a
 *    entériné que ces deux colonnes restent « — » tant qu'il n'existe pas.
 *    Ce seeder ne les écrit donc pas : le service ne les touche pas non plus.
 *
 * ## Les deux statuts absents sont un REFUS, pas un oubli
 *
 * Le maître (`prototype_v2/pages/m7-achats.html` l.281-284) montre quatre
 * commandes, dont « Réceptionnée » et « Réceptionnée partiellement ». Ces deux
 * états ne se posent pas : ils sont **produits par une réception qui a
 * réellement généré ses entrées de stock**. Or une réception exige
 * `tolerance_reception_pct` (RG-10), et l'arbitrage (e) du 31/08/2026 a
 * tranché que cette clé se saisit à l'écran Paramètres et n'est **jamais
 * semée** — un pourcentage deviné ferait accepter ou refuser des livraisons
 * sur un critère arbitraire. La démonstration montre donc les deux statuts
 * saisissables ; les deux autres apparaîtront le jour où un Administrateur
 * aura renseigné la tolérance et où quelqu'un aura réceptionné.
 *
 * ## Les montants
 *
 * Les prix unitaires sont construits pour que la somme des lignes retrouve le
 * `montant_estime` du maître (420 000 F et 62 000 F) : ce sont des ordres de
 * grandeur d'amorçage traçables à leur source, pas des tarifs constatés —
 * même clause que `BarSeeder`. Aucun n'entre dans une valorisation : le coût
 * moyen pondéré se construit par les réceptions, pas par les commandes.
 *
 * Dév/Recette UNIQUEMENT. Idempotent.
 *
 * @see EF-M7-02 Émission de commandes d'achat rattachées à un ou plusieurs articles
 * @see RG-10 Tolérance de réception (paramètre non semé, voir ci-dessus)
 */
class AchatsDemonstrationSeeder extends Seeder
{
    public function run(): void
    {
        if (CommandeAchat::query()->exists()) {
            return;
        }

        // L'auteur vient du jeton : `CommandeAchatService` lit `auth()->id()`
        // et `commandes_achat.utilisateur_id` est NOT NULL (RG-15). Sans
        // connexion, la commande ne peut pas naître — et c'est bien ainsi.
        $acheteur = User::query()->where('login', 'achats')->first();

        if ($acheteur === null) {
            return;
        }

        $commandes = [
            [
                'fournisseur' => 'Bénin Boissons Distribution',
                'statut' => 'envoyee',
                'jours' => 40,
                // 420 000 F : le montant du maître (`m7-achats.html` l.282),
                // qui ne donne que le TOTAL. Le détail est reconstruit en
                // unités de stock RÉELLES depuis le 03/09/2026 — on commande
                // des casiers, pas des bouteilles à l'unité —, aux prix
                // d'achat du référentiel (`seed-donnees.js` l.64 et l.78) :
                // 40 × 7 200 + 22 × 6 000 = 420 000 F, le total est conservé.
                'lignes' => [
                    ['article' => 'Béninoise 66 cl (casier 12)', 'quantite' => '40.00', 'prix' => '7200.00'],
                    ['article' => 'Sucrerie 66 cl (casier 12)', 'quantite' => '22.00', 'prix' => '6000.00'],
                ],
            ],
            [
                'fournisseur' => 'Coopérative Maraîchère Atacora',
                'statut' => 'brouillon',
                'jours' => 36,
                // 62 000 F : le montant du maître (`m7-achats.html` l.284).
                // « Poisson frais (tilapia) » n'existe plus au référentiel —
                // le maître range « Poisson carpe (kg) » en cuisine. Aux prix
                // d'achat réels : 15 × 2 800 + 8 × 2 500 = 62 000 F.
                'lignes' => [
                    ['article' => 'Poisson carpe (kg)', 'quantite' => '15.00', 'prix' => '2800.00'],
                    ['article' => 'Fromage peulh (kg)', 'quantite' => '8.00', 'prix' => '2500.00'],
                ],
            ],
        ];

        Auth::login($acheteur);

        try {
            $service = app(CommandeAchatService::class);

            foreach ($commandes as $c) {
                $service->creer([
                    'fournisseur_id' => $this->fournisseurId($c['fournisseur']),
                    'date_commande' => now()->subDays($c['jours'])->toDateString(),
                    'statut' => $c['statut'],
                    'lignes' => array_map(fn (array $l): array => [
                        'article_id' => $this->articleId($l['article']),
                        'quantite_commandee' => $l['quantite'],
                        'prix_unitaire' => $l['prix'],
                    ], $c['lignes']),
                ]);
            }
        } finally {
            Auth::logout();
        }
    }

    /**
     * Référentiel LU, jamais recréé — un second auteur produirait le doublon
     * corrigé le 31/08/2026 sur le parc d'hébergement. Le refus est explicite :
     * un seeder qui « réussit » sans rien semer est la forme PA-59/60/61 du
     * peuplement de données.
     */
    private function fournisseurId(string $raisonSociale): string
    {
        $id = Fournisseur::query()->where('raison_sociale', $raisonSociale)->value('id');

        if ($id === null) {
            // Message exploitant, jamais affiché a un utilisateur.
            throw new RuntimeException(
                'AchatsDemonstrationSeeder pose des commandes sur le referentiel de '
                .'FournisseurSeeder : fournisseur introuvable ('.$raisonSociale.'). '
                .'Ce seeder ne cree AUCUN fournisseur.',
            );
        }

        return (string) $id;
    }

    private function articleId(string $libelle): string
    {
        $id = Article::query()->where('libelle', $libelle)->value('id');

        if ($id === null) {
            // Message exploitant, jamais affiché a un utilisateur.
            throw new RuntimeException(
                'AchatsDemonstrationSeeder pose des lignes sur les articles de '
                .'StocksSeeder et BarSeeder : article introuvable ('.$libelle.'). '
                .'Ce seeder ne cree AUCUN article.',
            );
        }

        return (string) $id;
    }
}
