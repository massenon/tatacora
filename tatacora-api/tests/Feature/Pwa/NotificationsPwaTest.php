<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\RegistreCanaux;
use App\Models\User;
use App\Pwa\Livewire\Notifications\Hub;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * M12 en ÉCRITURE — `m12-notifications-hub.html`, vague du 31/08/2026.
 *
 * Ce fichier remplace la suite de l'écran de refus : `Notifications\Hub` sert
 * désormais le référentiel réel (modèles, déclencheurs, journal, canaux) au
 * lieu d'annoncer que le module n'existe pas.
 *
 * ## Ce qu'il tient
 *
 * 1. **Les quatre onglets rendus se chargent**, et le cinquième du maître —
 *    « File d'attente » — n'existe NULLE PART : ni onglet, ni bouton
 *    d'envoi. Un bouton inerte violerait l'Article 3.3 ; un bouton qui
 *    simulerait serait un faux écran.
 * 2. **Le bandeau rouge du maître est rendu mot pour mot** : c'est la seule
 *    phrase qui dise au Gérant que rien ne part.
 * 3. **Le RBAC d'écriture** : un `barman` (`M12 = '-'`) n'atteint pas la
 *    route ; un `receptionniste` (`M12 = 'L'`) la lit mais ne peut pas
 *    ouvrir le formulaire ; un `gerant` (`M12 = 'C'`) écrit.
 * 4. **Le CRUD passe par le Service**, jamais par une logique réécrite.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les deux ont mordu
 *
 * | Mutation                                                          | Cible rougie |
 * |--------------------------------------------------------------------|--------------|
 * | retirer `exigerEcriture()` de `basculerModele()`                     | `un_role_en_lecture_ne_bascule_aucun_modele` |
 * | rendre le bandeau RG-20 conditionnel à un canal branché              | `le_bandeau_rg20_du_maitre_est_rendu_mot_pour_mot` |
 *
 * @see EF-M12-01 Modèles de notification paramétrables par événement et canal
 * @see RG-20 Diffusion automatique — seule règle de gestion non implémentée
 */
final class NotificationsPwaTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.m12.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function modele(string $evenement = 'sejour_demain'): ModeleNotification
    {
        return ModeleNotification::create([
            'evenement' => $evenement,
            'canal' => RegistreCanaux::WHATSAPP,
            'contenu_template' => 'Bonjour {client}, votre séjour commence demain {date_arrivee}.',
            'actif' => true,
        ]);
    }

    // =================================================================
    // 1 — les quatre onglets, et le cinquième qui n'existe pas
    // =================================================================

    #[Test]
    public function les_quatre_onglets_rendus_se_chargent_reellement(): void
    {
        $this->modele();

        foreach (['modeles', 'declencheurs', 'journal', 'canaux'] as $onglet) {
            $this->actingAs($this->compte('gerant'));

            Livewire::test(Hub::class)
                ->set('onglet', $onglet)
                ->assertOk();
        }
    }

    /**
     * ⚠ GARDE INVERSÉE le 01/09/2026 — décision du Product Owner : « pour le
     * moment utilise le SMTP ». L'envoi par EMAIL est un geste RÉEL
     * (`envoyerMessage`), conditionné à une adresse ET une configuration
     * mail réelles — jamais un statut « envoyé » sans envoi (PA-59/60/61).
     * Ce qui reste interdit : WhatsApp/SMS (non contractés, étiquetés « à
     * paramétrer au déploiement »).
     */
    #[Test]
    public function l_envoi_email_est_reel_et_les_canaux_non_contractes_restent_fermes(): void
    {
        $methodes = get_class_methods(Hub::class);

        $this->assertContains('envoyerMessage', $methodes, 'Le geste d envoi email (SMTP, decision PO) manque.');

        // Le service d'envoi refuse sans adresse et sans configuration —
        // c'est lui qui tient la promesse, le composant ne fait qu'appeler.
        $source = (string) file_get_contents(app_path('Domain/Notifications/Services/EnvoiEmailNotificationService.php'));
        $this->assertStringContainsString('ConfigurationMailService', $source);

        // WhatsApp : toujours aucun envoi — le jeton du refus est déclaré.
        $sourceHub = (string) file_get_contents(app_path('Pwa/Livewire/Notifications/Hub.php'))
            .(string) file_get_contents(resource_path('views/pwa/notifications/hub.blade.php'));
        $this->assertStringContainsString('maitre-refuse:m12-notifications-hub.html#bouton-envoyer', $sourceHub);
    }

    // =================================================================
    // 2 — le bandeau du maître
    // =================================================================

    #[Test]
    public function le_bandeau_rg20_du_maitre_est_rendu_mot_pour_mot(): void
    {
        $this->actingAs($this->compte('gerant'));

        Livewire::test(Hub::class)
            ->assertSee(__('notifications_pwa.bandeau_titre'))
            ->assertSee(__('notifications_pwa.bandeau_texte'));
    }

    #[Test]
    public function le_compteur_d_envois_reels_vaut_zero_et_vient_de_la_table(): void
    {
        $this->modele();

        // Il vaut zéro parce que `notifications_envoyees` est vide, pas parce
        // qu'une constante le dit : trois modèles de plus n'y changent rien.
        $this->actingAs($this->compte('gerant'));

        Livewire::test(Hub::class)
            ->assertSee(__('notifications_pwa.kpi_envoyes'))
            ->assertSee(__('notifications_pwa.kpi_envoyes_detail'));
    }

    // =================================================================
    // 3 — RBAC
    // =================================================================

    #[Test]
    public function un_role_sans_acces_au_module_n_atteint_pas_la_route(): void
    {
        // `barman` : M12 = '-'.
        $this->actingAs($this->compte('barman'))
            ->get('/pwa/notifications')
            ->assertForbidden();
    }

    #[Test]
    public function un_role_en_lecture_voit_l_ecran_mais_n_ouvre_aucun_formulaire(): void
    {
        // `receptionniste` : M12 = 'L'.
        $this->actingAs($this->compte('receptionniste'))
            ->get('/pwa/notifications')
            ->assertOk();

        $this->actingAs($this->compte('receptionniste'));

        Livewire::test(Hub::class)
            ->call('ouvrirFormulaireModele')
            ->assertForbidden();
    }

    #[Test]
    public function un_role_en_lecture_ne_bascule_aucun_modele(): void
    {
        $modele = $this->modele();

        $this->actingAs($this->compte('receptionniste'));

        Livewire::test(Hub::class)
            ->call('basculerModele', $modele->id)
            ->assertForbidden();

        $this->assertTrue($modele->refresh()->actif, 'Un rôle en lecture a désactivé un modèle.');
    }

    // =================================================================
    // 4 — le CRUD, via le Service
    // =================================================================

    #[Test]
    public function un_gerant_cree_un_modele_depuis_l_ecran(): void
    {
        $this->actingAs($this->compte('gerant'));

        Livewire::test(Hub::class)
            ->call('ouvrirFormulaireModele')
            ->set('declencheurSaisi', 'creance_echue')
            ->set('canalSaisi', RegistreCanaux::EMAIL)
            ->set('objetSaisi', 'Solde en attente — Gîte Chez Noël')
            ->set('contenuSaisi', 'Bonjour {client}, un solde de {montant} reste ouvert.')
            ->call('enregistrerModele')
            ->assertHasNoErrors();

        $modele = ModeleNotification::query()->firstOrFail();

        $this->assertSame('creance_echue', $modele->evenement);
        $this->assertSame(RegistreCanaux::EMAIL, $modele->canal);
        $this->assertTrue($modele->actif);
    }

    #[Test]
    public function un_evenement_hors_registre_est_refuse_a_l_ecran(): void
    {
        $this->actingAs($this->compte('gerant'));

        Livewire::test(Hub::class)
            ->call('ouvrirFormulaireModele')
            ->set('declencheurSaisi', 'anniversaire_du_gerant')
            ->set('contenuSaisi', 'Bon anniversaire !')
            ->call('enregistrerModele')
            ->assertHasErrors('contenuSaisi');

        $this->assertSame(0, ModeleNotification::query()->count());
    }

    #[Test]
    public function basculer_un_modele_le_desactive_sans_le_supprimer(): void
    {
        $modele = $this->modele();

        $this->actingAs($this->compte('gerant'));

        Livewire::test(Hub::class)
            ->call('basculerModele', $modele->id)
            ->assertOk();

        $this->assertFalse($modele->refresh()->actif);
        $this->assertSame(1, ModeleNotification::query()->count());
    }
}
