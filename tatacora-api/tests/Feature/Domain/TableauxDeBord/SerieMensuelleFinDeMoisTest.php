<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\TableauxDeBord;

use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La série mensuelle rend chaque mois UNE fois — même le 31 du mois.
 *
 * ## Le défaut que ce test épingle (31/08/2026)
 *
 * `serieMensuelle()` faisait `$maintenant->subMonths($i)` sur la date brute.
 * Or `subMonths()` de Carbon retranche les mois puis GARDE le jour : appelé
 * un 31, « 31 juin » déborde au 1er juillet, « 31 avril » au 1er mai. Relevé
 * sur la réponse HTTP réelle du 31/08/2026 : la série de 6 mois rendait
 * `2026-03, 2026-05, 2026-05, 2026-07, 2026-07, 2026-08` — avril et juin
 * ABSENTS, mai et juillet DOUBLÉS.
 *
 * Le graphique du tableau de bord et son export montraient donc un mois deux
 * fois et en perdaient deux, sans que rien ne le signale. Et le défaut est
 * INTERMITTENT — trois jours par mois au plus (29, 30, 31) : un test qui
 * court à la date du jour serait vert vingt-huit jours sur trente et un.
 * C'est pourquoi chaque cas fige sa référence au lieu de lire l'horloge.
 *
 * Correctif : `startOfMonth()` AVANT la soustraction — ancrée au premier du
 * mois, elle ne peut plus déborder.
 *
 * ## Mutation prouvée
 *
 * Retirer `startOfMonth()` du service (revenir à la date brute) rend
 * `le_31_du_mois_la_serie_ne_saute_ni_ne_double_aucun_mois` ROUGE
 * (« 2026-05 apparaît 2 fois ») pendant que le cas du 15 reste vert — la
 * paire montre exactement la fenêtre du défaut. Rejouée le 31/08/2026,
 * service restauré ensuite.
 */
final class SerieMensuelleFinDeMoisTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function le_31_du_mois_la_serie_ne_saute_ni_ne_double_aucun_mois(): void
    {
        $this->assertSame(
            ['2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08'],
            $this->moisDeLaSerie('2026-08-31 23:30:00'),
            'La série du 31 août doit couvrir six mois consécutifs, chacun une fois.',
        );
    }

    #[Test]
    public function les_autres_fins_de_mois_debordantes_sont_couvertes_aussi(): void
    {
        // Le 30 saute février et avril ; le 29 (hors année bissextile) saute
        // février. Chaque borne de la fenêtre du défaut est tenue, pas
        // seulement celle qui l'a révélé.
        $this->assertSame(
            ['2025-12', '2026-01', '2026-02', '2026-03', '2026-04', '2026-05'],
            $this->moisDeLaSerie('2026-05-30 12:00:00'),
        );

        $this->assertSame(
            ['2025-10', '2025-11', '2025-12', '2026-01', '2026-02', '2026-03'],
            $this->moisDeLaSerie('2026-03-29 12:00:00'),
        );
    }

    #[Test]
    public function un_jour_ordinaire_rend_la_meme_fenetre_que_la_fin_de_mois(): void
    {
        // Le contre-cas : au 15, l'ancienne version était déjà juste. Si ce
        // cas rougit un jour en même temps que les deux autres, le défaut
        // n'est pas le débordement de fin de mois — chercher ailleurs.
        $this->assertSame(
            ['2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08'],
            $this->moisDeLaSerie('2026-08-15 12:00:00'),
        );
    }

    /**
     * @return list<string>
     */
    private function moisDeLaSerie(string $reference): array
    {
        $serie = app(TableauDeBordService::class)->serieMensuelle(
            6,
            CarbonImmutable::parse($reference),
        );

        return array_column($serie, 'mois');
    }
}
