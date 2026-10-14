<?php

declare(strict_types=1);

namespace Tests\Unit\Domain\TableauxDeBord;

use App\Domain\TableauxDeBord\Data\Periode;
use Carbon\CarbonImmutable;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Fenêtres d'analyse du tableau de bord — EF-M11-04, EF-M11-03.
 *
 * Unitaire : le découpage de période est du calcul de dates pur. Le tester
 * ici plutôt qu'à travers un KPI rend praticables les cas qui font vraiment
 * mal — la journée charnière entre deux périodes, et le comparatif d'un
 * trimestre entamé.
 *
 * La date de référence est **injectée**, jamais `now()` : un test de période
 * calé sur l'horloge réelle passe onze mois sur douze et échoue le 1er janvier.
 */
final class PeriodeTest extends TestCase
{
    /** Un mardi quelconque, milieu de trimestre, milieu d'année. */
    private const REFERENCE = '2026-08-16 14:32:00';

    private function reference(): CarbonImmutable
    {
        return CarbonImmutable::parse(self::REFERENCE);
    }

    // ------------------------------------------------------------- Bornes

    /**
     * @param  string  $code  code de période
     * @param  string  $debut  premier instant inclus
     */
    #[Test]
    #[DataProvider('bornesAttendues')]
    public function chaque_code_produit_la_fenetre_documentee(string $code, string $debut): void
    {
        $periode = Periode::depuisCode($code, $this->reference());

        $this->assertSame($debut, $periode->debut->format('Y-m-d H:i:s'));
        // La borne haute est TOUJOURS le lendemain à minuit : la journée en
        // cours doit être comptée entièrement, y compris une vente de 23 h.
        $this->assertSame('2026-08-17 00:00:00', $periode->fin->format('Y-m-d H:i:s'));
    }

    /**
     * @return array<string, array{string, string}>
     */
    public static function bornesAttendues(): array
    {
        return [
            "aujourd'hui" => [Periode::AUJOURD_HUI, '2026-08-16 00:00:00'],
            '7 derniers jours' => [Periode::SEPT_JOURS, '2026-08-10 00:00:00'],
            '30 derniers jours' => [Periode::TRENTE_JOURS, '2026-07-18 00:00:00'],
            'ce trimestre' => [Periode::TRIMESTRE, '2026-07-01 00:00:00'],
            'cette année' => [Periode::ANNEE, '2026-01-01 00:00:00'],
        ];
    }

    /**
     * Le défaut documenté au prototype (§2) est bien 30 jours — pas 7, pas
     * « aujourd'hui ». Un défaut différent changerait tous les chiffres que
     * le Gérant voit en ouvrant l'écran.
     */
    #[Test]
    public function le_defaut_est_trente_jours(): void
    {
        $this->assertSame(Periode::TRENTE_JOURS, Periode::DEFAUT);
        $this->assertSame(30, Periode::depuisCode(Periode::DEFAUT, $this->reference())->nombreJours());
    }

    #[Test]
    public function une_periode_inconnue_est_refusee_et_non_repliee_sur_le_defaut(): void
    {
        // Un repli silencieux ferait afficher 30 jours de chiffres sous un
        // libellé demandé pour tout autre chose.
        $this->expectException(InvalidArgumentException::class);
        Periode::depuisCode('ce_siecle', $this->reference());
    }

    // -------------------------------------------------- Bornes semi-ouvertes

    /**
     * Le cas que la convention `[debut, fin)` existe pour empêcher : la
     * journée charnière ne doit appartenir qu'à **une** des deux périodes.
     */
    #[Test]
    public function la_journee_charniere_n_appartient_pas_aux_deux_periodes(): void
    {
        $courante = Periode::depuisCode(Periode::SEPT_JOURS, $this->reference());
        $precedente = $courante->precedente();

        // La fin de la précédente est exactement le début de la courante :
        // contiguës, sans recouvrement d'une seule seconde.
        $this->assertTrue($precedente->fin->equalTo($courante->debut));
        $this->assertSame(
            $courante->nombreJours(),
            $precedente->nombreJours(),
            'Deux fenêtres de durées différentes rendraient toute variation ininterprétable.',
        );
    }

    /**
     * EF-M11-03 — le comparatif suppose deux fenêtres de **même durée**.
     * « Ce trimestre » entamé au 16 août dure 47 jours, pas 92 : la période
     * précédente doit durer 47 jours elle aussi, sinon la variation compare
     * un demi-trimestre à un trimestre entier.
     */
    #[Test]
    public function le_comparatif_d_un_trimestre_entame_garde_la_meme_duree(): void
    {
        $courante = Periode::depuisCode(Periode::TRIMESTRE, $this->reference());
        $precedente = $courante->precedente();

        // Du 1er juillet au 16 août inclus.
        $this->assertSame(47, $courante->nombreJours());
        $this->assertSame(47, $precedente->nombreJours());
        $this->assertSame('2026-05-15 00:00:00', $precedente->debut->format('Y-m-d H:i:s'));
    }

    // ------------------------------------------------------------- Libellé

    /**
     * Le libellé imprimé sur un état (RG-19) montre le dernier jour **inclus** :
     * « du 10 au 16 » se comprend, « du 10 au 17 exclu » ne se dit pas.
     */
    #[Test]
    public function le_libelle_affiche_le_dernier_jour_inclus(): void
    {
        $periode = Periode::depuisCode(Periode::SEPT_JOURS, $this->reference());

        $this->assertSame('Du 10/08/2026 au 16/08/2026', $periode->libelle());
    }

    // ------------------------------------------------------------ Immuabilité

    /**
     * `CarbonImmutable` : un KPI qui manipulerait la date décalerait tous les
     * KPI calculés après lui, et l'erreur ne serait visible sur aucun d'eux
     * pris isolément.
     */
    #[Test]
    public function les_bornes_ne_peuvent_pas_etre_modifiees_par_un_appelant(): void
    {
        $periode = Periode::depuisCode(Periode::TRENTE_JOURS, $this->reference());

        $periode->debut->addDays(10);
        $periode->fin->subDays(5);

        $this->assertSame('2026-07-18 00:00:00', $periode->debut->format('Y-m-d H:i:s'));
        $this->assertSame('2026-08-17 00:00:00', $periode->fin->format('Y-m-d H:i:s'));
    }
}
