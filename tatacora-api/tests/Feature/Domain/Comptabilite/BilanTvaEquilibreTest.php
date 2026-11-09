<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use Tests\TestCase;

/**
 * Le bilan reste EQUILIBRE quand les modules comptabilisent de la TVA.
 *
 * ## Ce que ce cas existe pour empecher (09/11/2026)
 *
 * `RubriquesSyscohada::DETTES_CIRCULANTES` n'avait pas `443` : une vente avec
 * TVA credite 4431 / 4432, ce credit n'etait dans AUCUNE rubrique du bilan, le
 * bilan se disait « desequilibre » (ecart = la TVA collectee) et le bandeau
 * « Comptes mouvementes hors nomenclature » nommait le compte. Meme trou pour
 * la TVA deductible (4452, lue par la declaration de TVA).
 *
 * Le balayage ne recopie AUCUNE liste de comptes : il lit les constantes de
 * `ComptesSyscohada` et les defauts de `RolesCorrespondance` — les comptes que
 * les ecritures automatiques des modules utilisent reellement — et fait passer
 * chacun par le VRAI `BilanService`.
 *
 * MUTATION PROUVEE : retirer `443` de `DETTES_CIRCULANTES` rougit les trois cas.
 */
final class BilanTvaEquilibreTest extends TestCase
{
    use RefreshDatabase;

    private VenteService $ventes;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $caissier = User::create([
            'login' => 'barman.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'barman')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($caissier);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->ventes = app(VenteService::class);
    }

    #[Test]
    public function une_vente_avec_tva_donne_un_bilan_equilibre_et_la_tva_collectee_est_au_passif(): void
    {
        $this->activerLaTva();
        [$biere, $plat] = $this->decorDeVente();

        $this->ventes->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M5', 'reference_id' => $biere->id, 'quantite' => 2],
                ['module' => 'M4', 'reference_id' => $plat->id, 'quantite' => 1],
            ],
        ]);

        $bilan = $this->bilan();

        // 2 000 TTC bar (TVA 305,08 sur 4431) + 2 500 TTC restaurant (TVA 381,36 sur 4432).
        $passifCirculant = collect($bilan->passif)->firstWhere('code', 'passif_circulant');
        $this->assertSame('686.44', $passifCirculant->net, 'La TVA collectee (4431 + 4432) est une dette envers l\'Etat.');

        $this->assertSame([], $bilan->comptesHorsRubrique);
        $this->assertTrue($bilan->equilibre, 'Ecart du bilan : '.$bilan->ecart);
        $this->assertSame('0.00', $bilan->ecart);
        $this->assertSame('4500.00', $bilan->totalActif);
        $this->assertSame('4500.00', $bilan->totalPassif);
    }

    #[Test]
    public function aucun_compte_des_ecritures_automatiques_n_est_hors_nomenclature(): void
    {
        // Les comptes REELLEMENT utilises : les constantes de la table de
        // correspondance et les defauts des roles, lus a l'execution.
        $comptes = array_values(array_unique([
            ...array_values((new ReflectionClass(ComptesSyscohada::class))->getConstants()),
            ...array_map(RolesCorrespondance::defaut(...), array_keys(RolesCorrespondance::ROLES)),
        ]));
        $this->assertContains('4431', $comptes);
        $this->assertContains('4452', $comptes);

        foreach ($comptes as $numero) {
            $numero = (string) $numero;
            $this->assertNotNull(
                CompteComptable::where('numero_compte', $numero)->first(),
                "Le compte {$numero} utilise par un module n'existe pas au plan.",
            );

            // Un mouvement sur ce seul compte, contre le capital : le bilan est
            // equilibre SI ET SEULEMENT SI le compte a une rubrique (les sommes
            // sont signees, quel que soit le sens du solde).
            $this->piece($numero, '1000.00');
            $bilan = $this->bilan();
            // Garde anti-vacuite : la balance que lit le bilan porte bien ce compte.
            $balance = app(\App\Domain\Comptabilite\Services\BalanceGeneraleService::class)->genererPourExercice(
                (string) ExerciceComptable::query()->firstOrFail()->id,
                ['validee'],
            );
            $this->assertContains($numero, array_map(fn ($l): string => (string) $l->numeroCompte, $balance->lignes), "Le compte {$numero} n'est pas dans la balance.");

            $hors = array_column($bilan->comptesHorsRubrique, 'numero_compte');
            $this->assertNotContains($numero, $hors, "Le compte {$numero} est hors nomenclature : son solde manque au bilan.");
            $this->assertTrue($bilan->equilibre, "Le compte {$numero} desequilibre le bilan (ecart {$bilan->ecart}).");
            $this->soldeDeNouveau();
        }
    }

    #[Test]
    public function les_comptes_de_tva_et_de_paie_documentes_trouvent_leur_rubrique(): void
    {
        // Comptes de la nomenclature de l'Etat et du personnel, hors constantes
        // (la paie n'a pas encore d'appelant serveur — `ComptesSyscohada`,
        // en-tete) : TVA collectee, due, credit a reporter, TVA recuperable.
        $attendus = [
            '4431' => 'passif_circulant', '4432' => 'passif_circulant', '4433' => 'passif_circulant',
            '4441' => 'passif_circulant', '4449' => 'actif_circulant',
            '4451' => 'actif_circulant', '4452' => 'actif_circulant', '4454' => 'actif_circulant',
            '431' => 'passif_circulant', '4472' => 'passif_circulant', '422' => 'passif_circulant',
        ];

        foreach ($attendus as $numero => $poste) {
            $numero = (string) $numero;
            $this->assertNotNull(CompteComptable::where('numero_compte', $numero)->first(), "Compte {$numero} absent du plan.");
            $numero = $this->imputable($numero);
            $this->piece($numero, '1000.00');
            $bilan = $this->bilan();

            $this->assertSame([], $bilan->comptesHorsRubrique, "Le compte {$numero} est hors nomenclature.");
            $this->assertTrue($bilan->equilibre, "Le compte {$numero} desequilibre le bilan.");

            $trouve = collect([...$bilan->actif, ...$bilan->passif])
                ->first(fn ($p): bool => $p->code === $poste && \App\Domain\Comptabilite\Support\RubriquesSyscohada::releveDe($numero, $p->prefixes));
            $this->assertNotNull($trouve, "Le compte {$numero} devrait figurer au poste {$poste}.");
            $this->soldeDeNouveau();
        }
    }

    // ----------------------------------------------------------------- aides

    private function bilan(): \App\Domain\Comptabilite\ReadModels\Bilan
    {
        return app(BilanService::class)->genererPourExercice(
            (string) ExerciceComptable::query()->firstOrFail()->id,
            ['validee'],
        );
    }

    /** Un mouvement de `$montant` au debit du compte, au credit du capital. */
    private function piece(string $numero, string $montant): void
    {
        $centre = (string) CentreCout::query()->firstOrFail()->id;
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD',
            'date' => now()->format('Y').'-03-01',
            'libelle' => 'Balayage '.$numero,
            'lignes' => [
                ['compte' => $numero, 'centre_id' => $centre, 'debit' => $montant, 'credit' => '0'],
                ['compte' => '1011', 'centre_id' => $centre, 'debit' => '0', 'credit' => $montant],
            ],
        ]);
    }

    /** Efface les pieces de balayage entre deux comptes (aucune immutabilite a respecter ici : base de test). */
    private function soldeDeNouveau(): void
    {
        \Illuminate\Support\Facades\DB::table('ecritures_comptables')->delete();
    }

    /** Une division du plan ne recoit aucun mouvement : on prend son premier sous-compte. */
    private function imputable(string $numero): string
    {
        if (strlen($numero) >= 4) {
            return $numero;
        }

        return (string) (CompteComptable::where('numero_compte', 'like', $numero.'%')
            ->where('numero_compte', '!=', $numero)->orderBy('numero_compte')->value('numero_compte') ?? $numero);
    }

    private function activerLaTva(): void
    {
        foreach ([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => 'ttc',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }
    }

    /** @return array{0: CarteBoisson, 1: Plat} */
    private function decorDeVente(): array
    {
        $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        $articleBiere = $this->article('Bière 65cl', 'bouteille');
        $articleRiz = $this->article('Riz', 'kg');

        $biere = CarteBoisson::create([
            'article_id' => $articleBiere->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $recette = Recette::create(['libelle' => 'Riz sauce', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([$articleRiz->id => ['quantite_unitaire' => '0.250']]);
        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);
        $plat = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Riz sauce arachide',
            'prix_vente' => '2500.00',
        ]);

        app(MouvementStockService::class)->entree($articleBiere->id, $bar->id, '48.00', 'Réception');
        app(MouvementStockService::class)->entree($articleRiz->id, $cuisine->id, '20.00', 'Réception');

        return [$biere, $plat];
    }

    private function article(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'test',
            'unite_mesure' => $unite,
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '500.0000',
        ]);
    }
}
