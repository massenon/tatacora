<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Notifications;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\ModeleNotificationService;
use App\Domain\Notifications\Services\RegistreCanaux;
use App\Domain\Notifications\Services\RegistreDeclencheurs;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * EF-M12-01 — le référentiel des modèles de notification, et ce qu'il REFUSE.
 *
 * ## Ce que ce fichier tient
 *
 * 1. **Les deux registres sont FERMÉS.** Un événement ou un canal inconnu est
 *    refusé, jamais créé. Un modèle posé sur un événement que rien ne
 *    déclenche serait affiché comme actif et n'aurait aucun emprunteur — même
 *    famille que la clé `mecef_actif` qu'un écran confirmerait et que rien ne
 *    lit (PA-124).
 * 2. **Aucun canal n'est branché, et le compte est MESURÉ.**
 *    `RegistreCanaux::nombreBranches()` compte, il ne rend pas une constante.
 *    C'est la nuance de PA-61 : un drapeau posé à la main resterait juste
 *    jusqu'au jour où il compterait.
 * 3. **Le journal est vide parce que RIEN N'ÉCRIT**, et il lit la vraie table.
 *    Le service n'expose AUCUN geste d'envoi : la garde de source ci-dessous
 *    le vérifie sur le fichier, pour qu'un `envoyer()` ne revienne pas dans
 *    une méthode que personne ne rejoue.
 * 4. **Désactiver n'est pas supprimer** : le modèle demeure.
 * 5. **Les variables hors registre sont signalées** — un `{montant}` inconnu
 *    du déclencheur resterait littéral dans le message.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les trois ont mordu
 *
 * | Mutation                                                          | Cible rougie |
 * |--------------------------------------------------------------------|--------------|
 * | `RegistreDeclencheurs::existe()` rendant toujours `true`            | `un_evenement_hors_registre_est_refuse` |
 * | retirer le contrôle d'unicité avant `create()`                      | `un_second_modele_sur_le_meme_couple_est_refuse` |
 * | `variablesInconnues()` rendant toujours `[]`                        | `une_variable_hors_declencheur_est_signalee` |
 *
 * ⚠ La deuxième n'a PAS mordu au premier essai, et la raison mérite d'être
 * écrite : `unique(evenement, canal)` existe aussi au schéma, et une violation
 * de contrainte remonte une `QueryException` — qui hérite de `RuntimeException`
 * via `PDOException`. Le cas attendait le seul type, et restait donc vert sans
 * le contrôle du service. Il vérifie désormais le MESSAGE, qui est exactement
 * ce que le service apporte : une erreur SQL ne dit pas à l'opérateur quel
 * couple est déjà pris.
 *
 * @see EF-M12-01 Modèles de notification paramétrables par événement et canal
 * @see RG-20 Diffusion automatique — seule règle de gestion non implémentée
 */
final class ModeleNotificationServiceTest extends TestCase
{
    use RefreshDatabase;

    private function service(): ModeleNotificationService
    {
        return app(ModeleNotificationService::class);
    }

    // =================================================================
    // 1 — les registres sont fermés
    // =================================================================

    #[Test]
    public function un_evenement_hors_registre_est_refuse(): void
    {
        $this->expectException(RuntimeException::class);

        $this->service()->creerModele([
            'evenement' => 'anniversaire_du_gerant',
            'canal' => RegistreCanaux::WHATSAPP,
            'contenu_template' => 'Bon anniversaire !',
        ]);
    }

    #[Test]
    public function un_canal_hors_registre_est_refuse(): void
    {
        $this->expectException(RuntimeException::class);

        $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => 'pigeon',
            'contenu_template' => 'Bonjour {client}.',
        ]);
    }

    #[Test]
    public function un_second_modele_sur_le_meme_couple_est_refuse(): void
    {
        $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::WHATSAPP,
            'contenu_template' => 'Bonjour {client}, votre séjour commence demain {date_arrivee}.',
        ]);

        // ⚠ Le MESSAGE est verifie, pas seulement le type d'exception.
        // `unique(evenement, canal)` existe aussi au schema, et une violation
        // de contrainte remonte une `QueryException` — qui herite de
        // `RuntimeException` via `PDOException`. Attendre le type seul aurait
        // rendu ce cas vert meme sans le controle du service : mesure faite le
        // 31/08/2026, la mutation n'a PAS mordu au premier essai. Ce que le
        // service apporte, c'est un refus NOMME : une erreur SQL ne dit pas a
        // l'operateur quel couple est deja pris.
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('notifications_pwa.modele_deja_pose'));

        $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::WHATSAPP,
            'contenu_template' => 'Autre formulation.',
        ]);
    }

    #[Test]
    public function un_contenu_vide_est_refuse(): void
    {
        $this->expectException(RuntimeException::class);

        $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::EMAIL,
            'contenu_template' => "   \n  ",
        ]);
    }

    // =================================================================
    // 2 — aucun canal branché, et c'est MESURÉ
    // =================================================================

    #[Test]
    public function aucun_canal_n_est_branche_et_le_compte_est_mesure(): void
    {
        $this->assertCount(4, RegistreCanaux::tous());
        $this->assertSame(0, RegistreCanaux::nombreBranches());

        foreach (RegistreCanaux::tous() as $canal) {
            $this->assertFalse($canal['branche'], $canal['code'].' est annoncé branché.');
            $this->assertNotSame('', $canal['blocage'], $canal['code'].' ne dit pas ce qui le bloque.');
        }
    }

    // =================================================================
    // 3 — aucun envoi, ni dans le journal ni dans le code
    // =================================================================

    #[Test]
    public function le_journal_est_vide_parce_que_rien_n_ecrit_la_table(): void
    {
        $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::WHATSAPP,
            'contenu_template' => 'Bonjour {client}.',
        ]);

        $this->assertSame(0, $this->service()->journal()->count());
        $this->assertSame(0, $this->service()->nombreEnvoisReels());
    }

    #[Test]
    public function le_service_n_expose_aucun_geste_d_envoi(): void
    {
        // Garde de SOURCE. Sans elle, un `envoyer()` pourrait revenir dans une
        // méthode qu'aucun test ne rejoue, et l'écran finirait par annoncer un
        // envoi que rien n'exécute — la forme la plus directe de PA-59/60/61.
        $source = (string) file_get_contents(
            app_path('Domain/Notifications/Services/ModeleNotificationService.php'),
        );

        foreach (['function envoyer', 'function diffuser', 'function marquerEnvoye'] as $interdit) {
            $this->assertStringNotContainsString(
                $interdit,
                $source,
                "Un geste d envoi ($interdit) est reapparu alors qu aucun canal n est branche.",
            );
        }

        // Et rien n'écrit `notifications_envoyees` : la table n'est atteinte
        // qu'en lecture.
        $this->assertStringNotContainsString('NotificationEnvoyee::create', $source);
    }

    // =================================================================
    // 4 — désactiver n'est pas supprimer
    // =================================================================

    #[Test]
    public function desactiver_un_modele_le_conserve(): void
    {
        $modele = $this->service()->creerModele([
            'evenement' => 'creance_echue',
            'canal' => RegistreCanaux::EMAIL,
            'objet' => 'Solde en attente — Gîte Chez Noël',
            'contenu_template' => 'Bonjour {client}, un solde de {montant} reste ouvert.',
        ]);

        $this->assertTrue($modele->actif, 'Un modèle doit naître actif, comme au maître.');

        $bascule = $this->service()->basculerActivationModele($modele);

        $this->assertFalse($bascule->actif);
        $this->assertSame(1, ModeleNotification::query()->count());
    }

    // =================================================================
    // 5 — les variables hors déclencheur sont signalées
    // =================================================================

    #[Test]
    public function une_variable_hors_declencheur_est_signalee(): void
    {
        $modele = $this->service()->creerModele([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::WHATSAPP,
            // `{client}` appartient au déclencheur ; `{numero_chambre}` non.
            'contenu_template' => 'Bonjour {client}, chambre {numero_chambre}.',
        ]);

        $this->assertSame(['numero_chambre'], $this->service()->variablesInconnues($modele));
    }

    #[Test]
    public function le_registre_des_declencheurs_porte_les_neuf_evenements_du_maitre(): void
    {
        $this->assertCount(9, RegistreDeclencheurs::codes());

        foreach (RegistreDeclencheurs::tous() as $declencheur) {
            $this->assertContains($declencheur['public'], RegistreDeclencheurs::PUBLICS);
            $this->assertNotSame('', $declencheur['libelle']);
            // Un déclencheur sans variable ne pourrait porter aucun message
            // personnalisé : ce serait un modèle figé annoncé comme dynamique.
            $this->assertNotSame([], $declencheur['variables'], $declencheur['code']);
        }

        // Un code inconnu rend `null` plutôt qu'une entrée fabriquée : un
        // modèle orphelin doit se VOIR à l'écran.
        $this->assertNull(RegistreDeclencheurs::declencheur('inconnu'));
    }
}
