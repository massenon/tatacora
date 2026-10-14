<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Rh;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Domain\Rh\Models\Service;
use App\Domain\Rh\Services\CongeService;
use App\Domain\Rh\Services\PlanningService;
use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Planification et congés — RG-13, RG-14, EF-M13-02, EF-M13-04.
 *
 * `07_TESTING_QA.md` §2 impose pour RG-13 les mêmes cas que RG-01 : les deux
 * sens de chevauchement partiel, et surtout **le créneau adjacent valide** —
 * une équipe du matin qui finit à 12h et une du midi qui commence à 12h ne se
 * chevauchent pas.
 */
final class Rg13Rg14PlanningCongesTest extends TestCase
{
    use RefreshDatabase;

    private const JOUR = '2026-09-15';

    private Service $cuisine;

    private Employe $chef;

    private User $responsable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->responsable = $this->utilisateur('rh');
        $this->actingAs($this->responsable);

        $this->cuisine = Service::create(['libelle' => 'Cuisine']);
        $this->chef = $this->employe('KOSSOU', 'Bernard');
    }

    private function plannings(): PlanningService
    {
        return app(PlanningService::class);
    }

    private function conges(): CongeService
    {
        return app(CongeService::class);
    }

    // ------------------------------------------------------------- RG-13

    #[Test]
    public function rg13_un_chevauchement_de_creneau_est_refuse(): void
    {
        $this->planifier('08:00', '16:00');

        $this->assertThrows(
            fn () => $this->planifier('12:00', '20:00'),
            ChevauchementDetecteException::class,
        );

        $this->assertSame(1, Planning::count());
    }

    #[Test]
    public function rg13_le_chevauchement_est_detecte_dans_les_deux_sens(): void
    {
        $this->planifier('12:00', '18:00');

        // Déborde par le début...
        $this->assertThrows(fn () => $this->planifier('08:00', '14:00'), ChevauchementDetecteException::class);
        // ...par la fin...
        $this->assertThrows(fn () => $this->planifier('16:00', '22:00'), ChevauchementDetecteException::class);
        // ...et englobant.
        $this->assertThrows(fn () => $this->planifier('06:00', '23:00'), ChevauchementDetecteException::class);

        $this->assertSame(1, Planning::count());
    }

    /**
     * Le faux positif à ne surtout pas produire : l'équipe du matin finit à
     * 12h, celle de l'après-midi commence à 12h. Une erreur de bornes
     * refuserait un planning parfaitement normal.
     */
    #[Test]
    public function rg13_deux_creneaux_adjacents_restent_valides(): void
    {
        $this->planifier('08:00', '12:00');
        $apresMidi = $this->planifier('12:00', '18:00');

        $this->assertSame(2, Planning::count());
        $this->assertSame('12:00', substr((string) $apresMidi->heure_debut, 0, 5));
    }

    /**
     * **Le cas que l'extension du service partagé existe pour traiter.**
     *
     * Le même créneau horaire à deux dates différentes n'est évidemment pas un
     * conflit. Sans filtre sur la date, `VerificationChevauchementService`
     * aurait bloqué tout second créneau 08h–16h, quel que soit le jour.
     */
    #[Test]
    public function rg13_le_meme_creneau_a_une_autre_date_n_est_pas_un_conflit(): void
    {
        $this->planifier('08:00', '16:00');
        $lendemain = $this->planifier('08:00', '16:00', date: '2026-09-16');

        $this->assertSame(2, Planning::count());
        $this->assertSame('2026-09-16', $lendemain->date->toDateString());
    }

    #[Test]
    public function rg13_deux_employes_differents_ne_se_bloquent_pas(): void
    {
        $this->planifier('08:00', '16:00');

        $second = $this->employe('DOSSOU', 'Marie');
        $this->planifier('08:00', '16:00', employe: $second);

        $this->assertSame(2, Planning::count());
    }

    /**
     * RG-13 verrouille l'**employé**, pas le service : le même employé prêté à
     * un autre service reste indisponible sur son créneau. C'est précisément
     * le libellé de la règle — « deux services simultanément ».
     */
    #[Test]
    public function rg13_le_verrou_porte_sur_l_employe_et_non_sur_le_service(): void
    {
        $this->planifier('08:00', '16:00');

        $bar = Service::create(['libelle' => 'Bar']);

        $this->assertThrows(
            fn () => $this->planifier('10:00', '14:00', service: $bar),
            ChevauchementDetecteException::class,
        );
    }

    /**
     * Règle dérivée (PA-53) : planifier quelqu'un dont l'absence est déjà
     * validée produit un planning que personne ne pourra tenir.
     */
    #[Test]
    public function un_employe_en_conge_valide_n_est_pas_planifiable(): void
    {
        $this->parametrerRg14(preavis: '0', couverture: '0');

        $conge = $this->conges()->demander([
            'employe_id' => $this->chef->id,
            'type' => 'annuel',
            'date_debut' => '2026-09-14',
            'date_fin' => '2026-09-16',
        ]);
        $this->conges()->valider($conge, $this->responsable, Carbon::parse('2026-09-01'));

        $this->assertThrows(fn () => $this->planifier('08:00', '16:00'), RuntimeException::class);

        // Une demande seulement EN ATTENTE ne bloque pas : tant qu'elle n'est
        // pas validée, l'employé est censé travailler.
        $autre = $this->employe('AGBO', 'Paul');
        $this->conges()->demander([
            'employe_id' => $autre->id, 'type' => 'annuel',
            'date_debut' => '2026-09-14', 'date_fin' => '2026-09-16',
        ]);

        $this->assertSame(
            $autre->id,
            $this->planifier('08:00', '16:00', employe: $autre)->employe_id,
        );
    }

    // ------------------------------------------------------------- RG-14

    /**
     * Les deux seuils sont paramétrés. Sans valeur, la validation **refuse** —
     * même discipline que la tolérance de réception et le taux de TVA.
     */
    #[Test]
    public function rg14_sans_parametre_de_preavis_aucune_validation_n_est_possible(): void
    {
        $conge = $this->demandeStandard();

        $this->assertThrows(
            fn () => $this->conges()->valider($conge, $this->responsable),
            RuntimeException::class,
        );

        $this->assertSame(Conge::STATUT_EN_ATTENTE, $conge->fresh()->statut_validation);
    }

    #[Test]
    public function rg14_un_preavis_insuffisant_bloque_la_validation(): void
    {
        $this->parametrerRg14(preavis: '15', couverture: '0');

        $conge = $this->demandeStandard();

        // Demande validée 5 jours avant le départ : préavis de 15 exigé.
        $this->assertThrows(
            fn () => $this->conges()->valider($conge, $this->responsable, Carbon::parse('2026-09-10')),
            RuntimeException::class,
        );

        // 20 jours avant : le préavis est tenu.
        $valide = $this->conges()->valider($conge->fresh(), $this->responsable, Carbon::parse('2026-08-26'));
        $this->assertSame(Conge::STATUT_VALIDE, $valide->statut_validation);
        $this->assertSame($this->responsable->id, $valide->validateur_id);
    }

    /**
     * La couverture s'apprécie sur l'effectif **restant**, congés validés
     * déduits : c'est le nombre de personnes réellement présentes qui fait
     * tourner un service.
     */
    #[Test]
    public function rg14_la_couverture_minimale_du_service_bloque_le_troisieme_depart(): void
    {
        $this->parametrerRg14(preavis: '0', couverture: '2');

        $second = $this->employe('DOSSOU', 'Marie');
        $troisieme = $this->employe('AGBO', 'Paul');
        $this->employe('KPADE', 'Sylvie');

        // Effectif de 4. Deux départs laissent 2 en poste : conforme.
        foreach ([$this->chef, $second] as $employe) {
            $conge = $this->conges()->demander([
                'employe_id' => $employe->id, 'type' => 'annuel',
                'date_debut' => '2026-09-15', 'date_fin' => '2026-09-20',
            ]);
            $this->conges()->valider($conge, $this->responsable, Carbon::parse('2026-09-01'));
        }

        // Le troisième laisserait 1 seul en poste.
        $troisiemeConge = $this->conges()->demander([
            'employe_id' => $troisieme->id, 'type' => 'annuel',
            'date_debut' => '2026-09-15', 'date_fin' => '2026-09-20',
        ]);

        $this->assertThrows(
            fn () => $this->conges()->valider($troisiemeConge, $this->responsable, Carbon::parse('2026-09-01')),
            RuntimeException::class,
        );

        $this->assertSame(Conge::STATUT_EN_ATTENTE, $troisiemeConge->fresh()->statut_validation);
    }

    /**
     * Des périodes disjointes ne se concurrencent pas : le service n'est à
     * découvert que si les absences se recoupent.
     */
    #[Test]
    public function rg14_des_conges_a_des_periodes_disjointes_ne_se_bloquent_pas(): void
    {
        $this->parametrerRg14(preavis: '0', couverture: '1');

        $second = $this->employe('DOSSOU', 'Marie');

        $premier = $this->conges()->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => '2026-09-01', 'date_fin' => '2026-09-10',
        ]);
        $this->conges()->valider($premier, $this->responsable, Carbon::parse('2026-08-01'));

        $suivant = $this->conges()->demander([
            'employe_id' => $second->id, 'type' => 'annuel',
            'date_debut' => '2026-09-11', 'date_fin' => '2026-09-20',
        ]);

        $this->assertSame(
            Conge::STATUT_VALIDE,
            $this->conges()->valider($suivant, $this->responsable, Carbon::parse('2026-08-01'))->statut_validation,
        );
    }

    /**
     * Un seul jour de recouvrement suffit à mettre le service à découvert.
     */
    #[Test]
    public function rg14_un_seul_jour_de_recouvrement_suffit_a_bloquer(): void
    {
        $this->parametrerRg14(preavis: '0', couverture: '1');

        $second = $this->employe('DOSSOU', 'Marie');

        $premier = $this->conges()->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => '2026-09-01', 'date_fin' => '2026-09-10',
        ]);
        $this->conges()->valider($premier, $this->responsable, Carbon::parse('2026-08-01'));

        // Commence le 10 : recouvre d'un jour.
        $chevauchant = $this->conges()->demander([
            'employe_id' => $second->id, 'type' => 'annuel',
            'date_debut' => '2026-09-10', 'date_fin' => '2026-09-20',
        ]);

        $this->assertThrows(
            fn () => $this->conges()->valider($chevauchant, $this->responsable, Carbon::parse('2026-08-01')),
            RuntimeException::class,
        );
    }

    /**
     * RG-14 porte sur la **validation**, pas sur le dépôt : un employé peut
     * exprimer un besoin hors délai, c'est au responsable de trancher.
     */
    #[Test]
    public function rg14_une_demande_hors_delai_reste_deposable(): void
    {
        $this->parametrerRg14(preavis: '30', couverture: '0');

        $conge = $this->conges()->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => now()->addDay()->toDateString(),
            'date_fin' => now()->addDays(3)->toDateString(),
        ]);

        $this->assertSame(Conge::STATUT_EN_ATTENTE, $conge->statut_validation);

        // ...mais elle ne se valide pas.
        $this->assertThrows(
            fn () => $this->conges()->valider($conge, $this->responsable),
            RuntimeException::class,
        );
    }

    /**
     * Un refus conserve la trace : un employé dont le congé a été refusé doit
     * pouvoir le prouver.
     */
    #[Test]
    public function un_conge_refuse_conserve_sa_trace_et_ne_se_retraite_pas(): void
    {
        $conge = $this->conges()->refuser($this->demandeStandard(), $this->responsable);

        $this->assertSame(Conge::STATUT_REFUSE, $conge->statut_validation);
        $this->assertDatabaseHas('conges', ['id' => $conge->id, 'statut_validation' => 'refuse']);

        $this->parametrerRg14(preavis: '0', couverture: '0');
        $this->assertThrows(
            fn () => $this->conges()->valider($conge->fresh(), $this->responsable),
            RuntimeException::class,
        );
    }

    #[Test]
    public function le_nombre_de_jours_de_conge_inclut_les_deux_bornes(): void
    {
        $conge = $this->conges()->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => '2026-09-10', 'date_fin' => '2026-09-10',
        ]);

        // Un congé du 10 au 10 dure un jour, pas zéro — convention différente
        // de RG-01, qui compte des nuitées entre deux dates.
        $this->assertSame(1, $conge->nombreJours());
        $this->assertSame(3, $this->demandeStandard()->nombreJours());
    }

    // ------------------------------------------------------------- Helpers

    private function planifier(
        string $debut,
        string $fin,
        string $date = self::JOUR,
        ?Employe $employe = null,
        ?Service $service = null,
    ): Planning {
        return $this->plannings()->planifier([
            'employe_id' => ($employe ?? $this->chef)->id,
            'service_id' => ($service ?? $this->cuisine)->id,
            'date' => $date,
            'heure_debut' => $debut,
            'heure_fin' => $fin,
        ]);
    }

    private function demandeStandard(): Conge
    {
        return $this->conges()->demander([
            'employe_id' => $this->chef->id,
            'type' => 'annuel',
            'date_debut' => '2026-09-15',
            'date_fin' => '2026-09-17',
        ]);
    }

    private function parametrerRg14(string $preavis, string $couverture): void
    {
        ParametreSysteme::create([
            'cle' => CongeService::CLE_PREAVIS, 'valeur' => $preavis,
            'description' => 'Délai de préavis minimal, en jours (RG-14).',
        ]);
        ParametreSysteme::create([
            'cle' => CongeService::CLE_COUVERTURE, 'valeur' => $couverture,
            'description' => 'Effectif minimal restant en poste par service (RG-14).',
        ]);
    }

    private function employe(string $nom, string $prenom): Employe
    {
        return Employe::create([
            'nom' => $nom, 'prenom' => $prenom, 'poste' => 'Cuisinier',
            'service_id' => $this->cuisine->id, 'date_embauche' => '2025-01-06',
            'salaire_base' => '85000.00', 'statut' => 'actif',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
