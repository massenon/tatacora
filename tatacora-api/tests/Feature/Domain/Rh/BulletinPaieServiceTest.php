<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Rh;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Domain\Rh\Services\BulletinPaieService;
use App\Domain\Rh\Services\CalculPaieService;
use App\Domain\Rh\Services\LivreDePaieService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\Feature\Domain\Rh\Concerns\PoseLeReferentielDePaie;
use Tests\TestCase;

/**
 * EF-M13-07 — l'établissement d'un bulletin, et surtout ses deux REFUS.
 *
 * ## Ce que ce fichier tient, et qui n'est vérifié nulle part ailleurs
 *
 * 1. **Le référentiel de taux peut être VIDE, et le service le dit.**
 *    ⚠ Découverte en écrivant ce lot, le 31/08/2026 : `PaieReferentielSeeder`
 *    existe, il est documenté… et il n'est appelé par PERSONNE — il ne figure
 *    pas dans `DatabaseSeeder`, et `grep` rend zéro appelant hors autoload.
 *    Sur une base fraîchement semée, `parametres_systeme` ne porte donc aucun
 *    taux de paie et `CalculPaieService` lève à chaque calcul. C'est le défaut
 *    PA-161 — un seeder écrit, décroché, jamais exécuté. Le cas
 *    `sans_referentiel_l_etat_est_nomme_et_aucun_bulletin_n_est_etabli`
 *    tourne DÉLIBÉRÉMENT sans le seeder pour tenir cet état.
 * 2. **Le total de charge patronale n'est jamais produit** (PA-53) : la
 *    colonne stockée porte la part CONFIRMÉE, et le coût employeur est une
 *    fourchette.
 * 3. **Le VPS n'est jamais une retenue salariale** — il est compris dans la
 *    part patronale et absent de `total_retenues`. C'est la vérification qui
 *    manquait quand le prélèvement était absent du dépôt entier.
 * 4. **Le barème ITS refuse au-delà de 500 000 F**, et le refus remonte.
 * 5. **L'établissement est idempotent** : `unique(employe_id, periode)` et
 *    aucun numéro brûlé au second appel — le piège de
 *    `FactureDao.numeroSuivant()` (PA-101).
 * 6. **Un bulletin annulé sort du livre**, il n'est pas supprimé.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les quatre ont mordu
 *
 * Chacune a été appliquée au service, la cible relancée, puis le fichier remis
 * en l'état.
 *
 * | Mutation                                                                  | Cible rougie |
 * |---------------------------------------------------------------------------|--------------|
 * | `etatReferentiel()` rendant toujours `complet => true`                     | `sans_referentiel_l_etat_est_nomme_et_aucun_bulletin_n_est_etabli` |
 * | écrire `chargesPatronales()` (avec RP) au lieu de `chargesPatronalesConfirmees()` | `la_part_patronale_stockee_est_la_part_confirmee_sans_risques_professionnels` |
 * | ajouter le VPS à `total_retenues`                                          | `le_vps_n_est_jamais_retenu_au_salarie` |
 * | retirer la relecture de l'existant avant `create()`                        | `etablir_deux_fois_ne_brule_aucun_numero` |
 *
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 * @see PA-53 Le refus de calculer est le livrable
 */
final class BulletinPaieServiceTest extends TestCase
{
    use PoseLeReferentielDePaie;
    use RefreshDatabase;

    private const PERIODE = '2026-07';

    private function service(): BulletinPaieService
    {
        return app(BulletinPaieService::class);
    }

    private function employe(string $salaire = '150000.00', string $nom = 'HOUNSOU'): Employe
    {
        $service = ServiceRh::create(['libelle' => 'Réception '.bin2hex(random_bytes(3))]);

        return Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => $nom,
            'prenom' => 'Marceline',
            'poste' => 'Réceptionniste',
            'service_id' => $service->id,
            'date_embauche' => '2023-02-01',
            'salaire_base' => $salaire,
            'statut' => 'actif',
        ]);
    }

    // =================================================================
    // 1 — le référentiel absent
    // =================================================================

    #[Test]
    public function sans_referentiel_l_etat_est_nomme_et_aucun_bulletin_n_est_etabli(): void
    {
        // AUCUN seeder de paie : c'est l'état réel d'une base fraîchement
        // semée par `DatabaseSeeder`, qui ne l'appelle pas.
        $etat = $this->service()->etatReferentiel();

        $this->assertFalse($etat['complet'], 'Le référentiel de paie est annoncé complet alors que rien n est en base.');
        $this->assertContains(CalculPaieService::CLE_CNSS_SALARIE, $etat['cles_absentes']);
        $this->assertContains(CalculPaieService::CLE_VPS, $etat['cles_absentes']);

        // Et le coût employeur ne prétend rien : il rend `null`, l'écran
        // affiche un tiret. Un zéro se lirait comme « ce salarié ne coûte
        // rien à l'employeur ».
        $this->assertNull($this->service()->coutEmployeur('150000.00'));

        $this->expectException(RuntimeException::class);
        $this->service()->etablirBulletin($this->employe(), self::PERIODE);
    }

    // =================================================================
    // 2 et 3 — PA-53 : la part confirmée, et le VPS jamais retenu
    // =================================================================

    #[Test]
    public function la_part_patronale_stockee_est_la_part_confirmee_sans_risques_professionnels(): void
    {
        $this->poserLeReferentielDePaie();

        $bulletin = $this->service()->etablirBulletin($this->employe('150000.00'), self::PERIODE);

        // 19,4 % de 150 000 = 29 100 — CNSS pension 6,4 %, prestations
        // familiales 9 %, VPS 4 %. Les risques professionnels (1 % à 4 %) n'y
        // sont PAS : leur taux n'est pas confirmé pour l'hôtellerie.
        $this->assertSame(
            0,
            bccomp('29100.00', (string) $bulletin->charges_patronales_confirmees, 2),
            'La part patronale stockée inclut un taux non confirmé.',
        );

        // Et la fourchette publie l'écart plutôt que de le moyenner.
        $cout = $this->service()->coutEmployeur('150000.00');
        $this->assertNotNull($cout);
        $this->assertSame(0, bccomp('1500.00', $cout['rp_min'], 2));
        $this->assertSame(0, bccomp('6000.00', $cout['rp_max'], 2));
        $this->assertSame(0, bccomp('4500.00', $cout['ecart'], 2));
        // Aucune valeur centrale n'est jamais rendue : il n'y a pas de clé
        // pour la porter.
        $this->assertArrayNotHasKey('rp_retenu', $cout);
    }

    #[Test]
    public function le_vps_n_est_jamais_retenu_au_salarie(): void
    {
        $this->poserLeReferentielDePaie();

        $bulletin = $this->service()->etablirBulletin($this->employe('150000.00'), self::PERIODE);

        // CNSS salariale 3,6 % de 150 000 = 5 400. Imposable = 150 000 - 5 400
        // = 144 600 — le bareme s'applique au brut MOINS la cotisation, sans
        // quoi chaque bulletin serait surtaxe.
        // ITS : 0 % sur les 60 000 premiers, puis 10 % sur 84 600 = 8 460.
        // La tranche a 15 % ne s'ouvre qu'a 150 000 : elle reste vide ici.
        $this->assertSame(0, bccomp('5400.00', (string) $bulletin->cnss_salarie, 2));
        $this->assertSame(0, bccomp('8460.00', (string) $bulletin->its, 2));

        // Le total des retenues est exactement CNSS + ITS. 4 % du brut de plus
        // (6 000 F) signifierait que le VPS a glissé au débit du salarié.
        $this->assertSame(0, bccomp('13860.00', (string) $bulletin->total_retenues, 2));
        $this->assertSame(0, bccomp('136140.00', (string) $bulletin->net_a_payer, 2));
    }

    // =================================================================
    // 4 — le barème ITS refuse au-delà de 500 000 F
    // =================================================================

    #[Test]
    public function au_dela_du_bareme_confirme_le_bulletin_est_refuse(): void
    {
        $this->poserLeReferentielDePaie();

        // 600 000 F de brut : l'imposable dépasse 500 000 F, et deux sources
        // divergent sur le haut de barème.
        $this->expectException(RuntimeException::class);
        $this->service()->etablirBulletin($this->employe('600000.00'), self::PERIODE);
    }

    #[Test]
    public function le_lot_ne_perd_pas_les_bulletins_corrects_a_cause_d_un_seul_refus(): void
    {
        $this->poserLeReferentielDePaie();

        $this->employe('150000.00', 'ADJOVI');
        $this->employe('600000.00', 'ZOSSOU');
        $this->employe('90000.00', 'BIO');

        $bilan = $this->service()->etablirBulletinsManquants(self::PERIODE);

        $this->assertSame(2, $bilan['etablis'], 'Un refus a emporté les bulletins corrects du lot.');
        $this->assertCount(1, $bilan['refus']);
        $this->assertSame('ZOSSOU Marceline', $bilan['refus'][0]['employe']);
    }

    // =================================================================
    // 5 — idempotence, et aucun numéro brûlé
    // =================================================================

    #[Test]
    public function etablir_deux_fois_ne_brule_aucun_numero(): void
    {
        $this->poserLeReferentielDePaie();
        $employe = $this->employe();

        $premier = $this->service()->etablirBulletin($employe, self::PERIODE);
        $second = $this->service()->etablirBulletin($employe, self::PERIODE);

        $this->assertSame($premier->id, $second->id);
        $this->assertSame($premier->numero, $second->numero);
        $this->assertSame(1, BulletinPaie::query()->count());
    }

    // =================================================================
    // 6 — l'annulation sort du livre, elle ne supprime rien
    // =================================================================

    #[Test]
    public function un_bulletin_annule_sort_du_livre_mais_reste_au_dossier(): void
    {
        $this->poserLeReferentielDePaie();

        $bulletin = $this->service()->etablirBulletin($this->employe(), self::PERIODE);
        $livre = app(LivreDePaieService::class);

        $this->assertSame(1, $livre->totaux(self::PERIODE)['effectif']);

        $this->service()->annulerBulletin($bulletin, 'Erreur de salaire de base.');

        $this->assertSame(0, $livre->totaux(self::PERIODE)['effectif']);
        $this->assertSame(0, bccomp('0.00', $livre->totaux(self::PERIODE)['net'], 2));

        // La ligne demeure : rien n'est effacé (RG-15).
        $this->assertSame(1, BulletinPaie::query()->count());
        $this->assertSame(
            BulletinPaie::STATUT_ANNULEE,
            BulletinPaie::query()->firstOrFail()->statut,
        );

        // Et le salarié ne redevient PAS « manquant » : le réétablir buterait
        // sur `unique(employe_id, periode)`.
        $this->assertSame(0, $this->service()->employesSansBulletin(self::PERIODE)->count());
    }

    #[Test]
    public function une_annulation_sans_motif_est_refusee(): void
    {
        $this->poserLeReferentielDePaie();
        $bulletin = $this->service()->etablirBulletin($this->employe(), self::PERIODE);

        $this->expectException(RuntimeException::class);
        $this->service()->annulerBulletin($bulletin, '   ');
    }

    // =================================================================
    // Les déclarations disent lesquelles sont ARRÊTÉES
    // =================================================================

    #[Test]
    public function la_declaration_cnss_est_annoncee_incomplete_et_le_vps_porte_son_echeance(): void
    {
        $this->poserLeReferentielDePaie();
        $this->service()->etablirBulletin($this->employe('150000.00'), self::PERIODE);

        $declarations = collect(app(LivreDePaieService::class)->declarations(self::PERIODE))
            ->keyBy('code');

        // CNSS : salariale 5 400 + pension 9 600 + familiales 13 500 = 28 500,
        // HORS risques professionnels — donc annoncée incomplète.
        $this->assertFalse($declarations['CNSS']['complet']);
        $this->assertSame(0, bccomp('28500.00', $declarations['CNSS']['montant'], 2));

        // VPS : 4 % de 150 000 = 6 000, exigible le 10 du mois SUIVANT.
        $this->assertTrue($declarations['VPS']['complet']);
        $this->assertSame(0, bccomp('6000.00', $declarations['VPS']['montant'], 2));
        $this->assertSame('10/08/2026', $declarations['VPS']['echeance']);
    }
}
