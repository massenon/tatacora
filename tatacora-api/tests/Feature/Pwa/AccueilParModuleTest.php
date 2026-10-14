<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\Rh\Services\LivreDePaieService;
use App\Models\User;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\DemonstrationSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Par module » — les NEUF cartes du maître (`m11-pilotage.js`,
 * `rendreModules()` l.362-475), éprouvées contre le jeu de démonstration
 * COMPLET (`DemonstrationSeeder`), directive du Product Owner du 02/09/2026.
 *
 * ## Pourquoi un fichier séparé d'`AccueilM11Test`
 *
 * `DemonstrationSeeder` refuse une base déjà peuplée — ses seeders d'exploitation
 * exigent les référentiels de LEURS auteurs (« un référentiel a UN SEUL
 * auteur », PA-160/PA-161) et lèvent sur toute fiche inattendue. Le
 * `setUp()` d'`AccueilM11Test` sème ses propres fixtures ; semer la
 * démonstration par-dessus échoue donc à raison. Ici, la démonstration est
 * la SEULE population, comme chez `AmorcageDemonstrationTest`.
 *
 * ## Ce que ces cas prouvent
 *
 * Chaque valeur vérifiée est REDÉRIVÉE par un chemin indépendant du
 * composant quand c'en est un possible (nuitées, ventes du jour,
 * répartition du suivi) — sinon citée depuis l'auteur unique que la carte
 * doit reprendre tel quel (total dû `SoldeClientService`, fourchette
 * `LivreDePaieService`). Et le jeu est exigé NON VIDE sur chaque grandeur :
 * un zéro qui traverse ne prouverait rien.
 *
 * ## PREUVES PAR MUTATION (02/09/2026) — posées, vues rouges, retirées
 *
 * | Mutation | Assertion devenue rouge |
 * |---|---|
 * | `moduleReservations()` ne compte plus les nuitées « en cours » | `les_neuf_cartes…` (ligne « Nuitées ») |
 * | le `bcdiv` du panier moyen remplacé par `'0.00'` | `les_neuf_cartes…` (ligne « Panier moyen ») |
 *
 * @see EF-M11-01 Tableau de bord global
 */
final class AccueilParModuleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DemonstrationSeeder::class);
    }

    #[Test]
    public function les_neuf_cartes_par_module_rendent_les_donnees_reelles_de_la_demonstration(): void
    {
        $this->actingAs($this->administrateur());

        $html = (string) $this->get('/pwa/?panel=pilotage')->assertOk()->getContent();

        // Les neuf titres, dans l'ordre du maître : chaque titre doit
        // apparaître APRÈS le précédent.
        $titres = [
            __('accueil_pwa.pilotage.modules.reservations.titre'),
            __('accueil_pwa.pilotage.modules.pos.titre'),
            __('accueil_pwa.pilotage.modules.stocks.titre'),
            __('accueil_pwa.pilotage.modules.vehicules.titre'),
            __('accueil_pwa.pilotage.modules.tourisme.titre'),
            __('accueil_pwa.pilotage.module_paie_titre'),
            __('accueil_pwa.pilotage.module_creances_titre'),
            __('accueil_pwa.pilotage.module_compta_titre'),
            __('accueil_pwa.pilotage.modules.depenses.titre'),
        ];

        $position = 0;

        foreach ($titres as $titre) {
            $suivante = strpos($html, e((string) $titre), $position);
            $this->assertNotFalse(
                $suivante,
                "La carte « {$titre} » n'est pas rendue, ou pas à la place que le maître lui donne.",
            );
            $position = (int) $suivante;
        }

        // M1 — les nuitées, REDÉRIVÉES en SQL : « à venir » + « en cours »
        // est exactement « départ aujourd'hui ou plus tard » chez une
        // réservation non annulée (la dérivation de PA-111). Un jeu sans
        // séjour futur ne prouverait rien : on l'exige non vide.
        $nuitees = (int) DB::table('reservations')
            ->where('statut', '!=', 'annulee')
            ->whereDate('date_depart', '>=', CarbonImmutable::today()->toDateString())
            ->selectRaw('COALESCE(SUM(DATEDIFF(date_depart, date_arrivee)), 0) AS nuitees')
            ->value('nuitees');

        $this->assertGreaterThan(0, $nuitees, 'Le jeu de démonstration ne porte aucun séjour à venir ou en cours.');
        $this->assertMatchesRegularExpression(
            $this->motifLigneDeCarte((string) __('accueil_pwa.pilotage.modules.reservations.nuitees'), (string) $nuitees),
            $html,
            'La carte M1 ne rend pas les nuitées réelles des séjours à venir et en cours.',
        );

        // M4/M5 — le nombre de ventes du JOUR, redérivé en SQL (annulées
        // exclues), non vide sur la démonstration.
        $ventesDuJour = (int) DB::table('ventes')
            ->where('statut', '!=', 'annulee')
            ->whereDate('created_at', CarbonImmutable::today()->toDateString())
            ->count();

        $this->assertGreaterThan(0, $ventesDuJour, 'Le jeu de démonstration ne porte aucune vente du jour.');
        $this->assertMatchesRegularExpression(
            $this->motifLigneDeCarte((string) __('accueil_pwa.pilotage.modules.pos.ventes'), (string) $ventesDuJour),
            $html,
            'La carte M4/M5 ne rend pas le nombre réel de ventes du jour.',
        );

        // Le panier moyen est CA / nombre — redérivé ici depuis les mêmes
        // ventes, par `bcdiv` comme la règle du dépôt l'exige.
        $caDuJour = (string) DB::table('ventes')
            ->where('statut', '!=', 'annulee')
            ->whereDate('created_at', CarbonImmutable::today()->toDateString())
            ->sum('montant_total');

        $this->assertMatchesRegularExpression(
            $this->motifLigneDeCarte(
                (string) __('accueil_pwa.pilotage.modules.pos.panier_moyen'),
                preg_quote(e(MontantFcfa::format(bcdiv($caDuJour, (string) $ventesDuJour, 2))), '/'),
            ),
            $html,
            'La carte M4/M5 ne rend pas le panier moyen réel (CA du jour / nombre de ventes).',
        );

        // M6 — la répartition du suivi, redérivée en SQL sur la colonne
        // `articles.suivi`.
        $journaliers = (int) DB::table('articles')->where('suivi', 'journalier')->count();
        $permanents = (int) DB::table('articles')->count() - $journaliers;

        $this->assertGreaterThan(0, $permanents, 'Le jeu de démonstration ne porte aucun article suivi.');
        $this->assertMatchesRegularExpression(
            $this->motifLigneDeCarte((string) __('accueil_pwa.pilotage.modules.stocks.suivies'), (string) $permanents),
            $html,
            'La carte M6 ne rend pas le compte réel des références suivies.',
        );

        // M3 — le total dû vient de l'AUTEUR UNIQUE (`SoldeClientService::
        // totaux()`), et la démonstration porte une créance réelle : un zéro
        // plausible ici ne prouverait rien.
        $creances = app(SoldeClientService::class)->totaux();

        $this->assertSame(1, bccomp($creances['total_du'], '0.00', 2), 'Le jeu de démonstration ne porte aucune créance.');
        $this->assertMatchesRegularExpression(
            $this->motifLigneDeCarte(
                (string) __('accueil_pwa.pilotage.module_creances_total'),
                preg_quote(e(MontantFcfa::format($creances['total_du'])), '/'),
            ),
            $html,
            'La carte M3 ne rend pas le total dû de `SoldeClientService::totaux()`.',
        );

        // M13 — la fourchette du coût employeur, jamais un total unique
        // (PA-53) : la valeur rendue est « min à max », bornes de
        // `LivreDePaieService::totaux()`.
        $paie = app(LivreDePaieService::class)->totaux(CarbonImmutable::today()->format('Y-m'));
        $fourchette = (string) __('accueil_pwa.pilotage.modules.paie.cout_valeur', [
            'min' => MontantFcfa::format($paie['cout_min']),
            'max' => MontantFcfa::format($paie['cout_max']),
        ]);

        $this->assertStringContainsString(
            e($fourchette),
            $html,
            'La carte M13 ne rend pas la fourchette de coût employeur de `LivreDePaieService::totaux()`.',
        );

        // Et la note FIXE du maître qui explique la fourchette.
        $this->assertStringContainsString(
            e((string) __('accueil_pwa.pilotage.modules.paie.note')),
            $html,
            'La note du maître sur la fourchette du coût employeur manque.',
        );
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Un compte administrateur de test — `DemonstrationSeeder` ne crée AUCUN
     * utilisateur (aucun mot de passe par défaut n'existe dans ce dépôt),
     * le rôle vient donc du seeder et le compte d'ici.
     */
    private function administrateur(): User
    {
        return User::create([
            'login' => 'parmodule.admin',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * Le motif d'une ligne de carte du maître : le libellé, la fermeture de
     * son `<span>`, puis la valeur dans le `<span>` suivant. `$valeur` est
     * insérée telle quelle — la passer par `preg_quote()` quand elle porte
     * des caractères spéciaux (montants avec espaces fines).
     */
    private function motifLigneDeCarte(string $libelle, string $valeur): string
    {
        return '/'.preg_quote(e($libelle), '/').'<\/span>\s*<span[^>]*>'.$valeur.'</';
    }
}
