<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Annulation avec commission et remboursement — EF-M1-06.
 *
 * @see `Rapport_Presentation_Echange_TATACORA_AFRIQUE.pdf` §4.3, §4.4, §6.1, §6.3
 * @see App\Domain\Hebergement\Services\AnnulationReservationService
 *
 * Chaque cas emprunte le SERVICE réel, sous transaction réelle, contre une
 * comptabilité réelle (`ComptabiliteReferentielSeeder`) — jamais un double
 * ou un calcul reconstruit dans le test.
 */
final class AnnulationReservationServiceTest extends TestCase
{
    use RefreshDatabase;

    private Client $client;

    private UniteHebergement $unite;

    private AnnulationReservationService $annulations;

    private User $auteur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $categorie = CategorieHebergement::create([
            'id' => (string) Str::uuid(), 'libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => 20000,
        ]);
        $this->unite = UniteHebergement::create([
            'id' => (string) Str::uuid(), 'categorie_id' => $categorie->id, 'numero' => 'BG-01', 'statut' => 'libre',
        ]);
        $this->client = Client::create([
            'id' => (string) Str::uuid(), 'nom' => 'ALLALE', 'prenom' => 'Rodrigue',
            'telephone' => '01 90 12 34 56', 'type_client' => 'particulier',
        ]);

        $this->annulations = app(AnnulationReservationService::class);
        $this->auteur = $this->utilisateur('administrateur');
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => 'compte.'.$role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    private function reservation(array $donnees = []): Reservation
    {
        return app(ReservationService::class)->creer(array_merge([
            'id' => (string) Str::uuid(),
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-10',
            'date_depart' => '2026-09-12', // 2 nuits
            'tarif_nuit' => '20000',
        ], $donnees));
    }

    // =========================================================================
    // §4.3 — La commission se calcule sur le MONTANT GLOBAL, jamais l'acompte
    // =========================================================================

    #[Test]
    public function la_commission_se_calcule_sur_le_montant_total_jamais_sur_le_seul_acompte(): void
    {
        // Total = 20000 × 2 nuits = 40000. Acompte = 5000, très inférieur au
        // total : si la commission portait sur l'acompte (l'erreur que le
        // client a explicitement écartée en séance), elle vaudrait 2500, pas
        // 20000.
        $reservation = $this->reservation(['acompte' => '5000']);

        $annulee = $this->annulations->annuler($reservation, [
            'taux' => '50',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '0',
        ], $this->auteur);

        $this->assertSame('40000.00', (string) $annulee->montant_total_annulation);
        $this->assertSame(
            '20000.00',
            (string) $annulee->montant_commission_annulation,
            'La commission doit porter sur les 40000 F du montant global, pas sur les 5000 F d\'acompte.',
        );
    }

    // =========================================================================
    // Le seuil de 24h — testé par MUTATION (voir le rapport de la tâche pour
    // la preuve d'exécution : cassé, rouge constaté, restauré).
    // =========================================================================

    #[Test]
    public function le_seuil_de_24h_distingue_reellement_les_deux_cotes_de_la_frontiere(): void
    {
        $reservation = $this->reservation(); // date_arrivee = 2026-09-10, minuit = référence

        $reference = \Illuminate\Support\Carbon::parse('2026-09-10 00:00:00');

        // Annulation 10h avant la référence : SOUS le seuil.
        $maintenantProche = $reference->copy()->subHours(10);
        $this->assertTrue($this->annulations->estSousLeSeuil($reservation, $maintenantProche));

        // Annulation 48h avant la référence : AU-DESSUS du seuil.
        $maintenantLoin = $reference->copy()->subHours(48);
        $this->assertFalse($this->annulations->estSousLeSeuil($reservation, $maintenantLoin));

        // Le délai en heures est bien celui annoncé, à la minute près — ancrage
        // numérique qui rendrait une mutation du calcul (ex. `<=` au lieu de
        // `<`, ou une constante `SEUIL_HEURES` modifiée) détectable : casser
        // `AnnulationReservationService::SEUIL_HEURES` (24 → 0) ou inverser
        // l'opérateur de `estSousLeSeuil()` fait échouer CE test précisément,
        // ce qui a été vérifié manuellement (voir rapport de restitution).
        $delai = $this->annulations->delaiHeuresAvantArrivee($reservation, $maintenantProche);
        $this->assertEqualsWithDelta(10.0, $delai, 0.01);
    }

    // =========================================================================
    // Remboursement : % et montant numéraire, DEUX saisies, UN seul résultat
    // =========================================================================

    #[Test]
    public function remboursement_saisi_en_pourcentage_ou_en_montant_produit_le_meme_resultat(): void
    {
        // Dates DIFFÉRENTES : RG-01 refuserait deux réservations actives sur
        // la même unité aux mêmes dates, et ce n'est pas ce que ce test mesure.
        $reservationPourcentage = $this->reservation(['acompte' => '10000']);
        $reservationMontant = $this->reservation([
            'acompte' => '10000',
            'date_arrivee' => '2026-10-10',
            'date_depart' => '2026-10-12',
        ]);

        $viaPourcentage = $this->annulations->annuler($reservationPourcentage, [
            'taux' => '50',
            'mode_remboursement' => 'pourcentage',
            'valeur_remboursement' => '50', // 50 % de 10000 = 5000
        ], $this->auteur);

        $viaMontant = $this->annulations->annuler($reservationMontant, [
            'taux' => '50',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '5000',
        ], $this->auteur);

        $this->assertSame('5000.00', (string) $viaPourcentage->montant_rembourse_annulation);
        $this->assertSame('5000.00', (string) $viaMontant->montant_rembourse_annulation);
        $this->assertSame(
            (string) $viaPourcentage->montant_rembourse_annulation,
            (string) $viaMontant->montant_rembourse_annulation,
        );
    }

    #[Test]
    public function le_remboursement_ne_peut_jamais_depasser_l_acompte_encaisse(): void
    {
        $reservation = $this->reservation(['acompte' => '5000']);

        $this->expectException(InvalidArgumentException::class);

        $this->annulations->annuler($reservation, [
            'taux' => '0',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '5001',
        ], $this->auteur);
    }

    // =========================================================================
    // Caisse ↔ comptabilité — la règle des sept qui ne souffrent aucune exception
    // =========================================================================

    #[Test]
    public function un_remboursement_numeraire_positif_produit_une_vraie_ecriture_equilibree(): void
    {
        $reservation = $this->reservation(['acompte' => '10000']);

        $annulee = $this->annulations->annuler($reservation, [
            'taux' => '0',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '10000',
        ], $this->auteur);

        $this->assertNotNull($annulee->ecriture_remboursement_id);

        $piece = EcritureComptable::all();
        $this->assertCount(2, $piece, 'DÉBIT 4191 + CRÉDIT 5711 : exactement deux lignes.');
        // `bccomp`, jamais une égalité de chaîne sur une somme Collection —
        // `sum()` repasse par un flottant PHP et perd le zéro de fin (règle
        // du dépôt : comparaison de montants toujours en `bccomp`).
        $this->assertSame(0, bccomp((string) $piece->sum('debit'), '10000.00', 2));
        $this->assertSame(0, bccomp((string) $piece->sum('credit'), '10000.00', 2));
        $this->assertSame(['validee'], $piece->pluck('statut')->unique()->values()->all());

        $ligneDebit = EcritureComptable::findOrFail($annulee->ecriture_remboursement_id);
        $compte = \App\Domain\Comptabilite\Models\CompteComptable::findOrFail($ligneDebit->compte_id);
        $this->assertSame('4191', $compte->numero_compte);
        $this->assertSame('10000.00', (string) $ligneDebit->debit);
        $this->assertSame('0.00', (string) $ligneDebit->credit);
    }

    #[Test]
    public function aucun_remboursement_ne_produit_aucun_mouvement_de_caisse(): void
    {
        // L'intégralité de l'acompte est retenue (commission = acompte) :
        // rien ne sort de la caisse.
        $reservation = $this->reservation(['acompte' => '10000']);

        $annulee = $this->annulations->annuler($reservation, [
            'taux' => '100',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '0',
        ], $this->auteur);

        $this->assertNull(
            $annulee->ecriture_remboursement_id,
            'Rien n\'est remboursé : aucune écriture ne doit être fabriquée (règle des sept, doctrine du dépôt).',
        );
        $this->assertSame(0, EcritureComptable::count());
        $this->assertSame('annulee', $annulee->statut);
    }

    // =========================================================================
    // Article 9 — refuser plutôt qu'inventer
    // =========================================================================

    #[Test]
    public function une_reservation_sans_tarif_fige_refuse_le_calcul_plutot_que_d_inventer_un_montant(): void
    {
        // Ancienne réservation, antérieure à PA-163 : aucun tarif_nuit.
        // ⚠ Depuis le 02/09/2026, `ReservationService::creer()` FIGE le tarif
        // manquant depuis le parc (PA-170 (2)) — l'état legacy ne peut plus
        // naître par le service : le test le fabrique en effaçant la colonne
        // APRÈS coup, comme le ferait une ligne synchronisée d'avant le
        // correctif.
        $reservation = $this->reservation();
        $reservation->forceFill(['tarif_nuit' => null])->save();
        $reservation->refresh();

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('inconnu');

        $this->annulations->annuler($reservation, [
            'taux' => '50',
            'mode_remboursement' => 'montant',
            'valeur_remboursement' => '0',
        ], $this->auteur);
    }

    #[Test]
    public function une_reservation_deja_annulee_refuse_une_seconde_annulation(): void
    {
        $reservation = $this->reservation();
        $this->annulations->annuler($reservation, [
            'taux' => '50', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '0',
        ], $this->auteur);

        $this->expectException(RuntimeException::class);
        $this->annulations->annuler($reservation, [
            'taux' => '50', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '0',
        ], $this->auteur);
    }

    // =========================================================================
    // Audit — qui a annulé, quand (exigence nommée du Product Owner)
    // =========================================================================

    #[Test]
    public function l_auteur_et_l_horodatage_de_l_annulation_sont_reellement_enregistres(): void
    {
        // La session d'authentification n'a PAS besoin d'être ouverte pour
        // que la colonne dédiée soit juste : `AnnulationReservationService`
        // enregistre l'AUTEUR EXPLICITEMENT TRANSMIS, jamais `auth()->id()`
        // en filigrane — c'est ce qui garantit que « qui a annulé » reste
        // exact même si un job ou une synchronisation différée appelle ce
        // service hors d'une requête HTTP authentifiée.
        $reservation = $this->reservation();
        $avant = now()->subSecond();

        $annulee = $this->annulations->annuler($reservation, [
            'taux' => '50', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '0',
        ], $this->auteur);

        $apres = now()->addSecond();

        $this->assertSame($this->auteur->id, $annulee->utilisateur_annulation_id);
        $this->assertNotNull($annulee->date_annulation);
        $this->assertTrue($annulee->date_annulation->between($avant, $apres));

        // Lisible depuis l'écran : la relation Eloquent résout le VRAI compte,
        // pas un identifiant orphelin.
        $this->assertSame($this->auteur->login, $annulee->utilisateurAnnulation?->login);
    }

    /**
     * La colonne d'audit GÉNÉRIQUE (`Auditable`, dérivée de `auth()->id()`)
     * ne doit pas être confondue avec la colonne DÉDIÉE
     * (`utilisateur_annulation_id`, transmise explicitement) : un futur
     * `update()` sans rapport avec l'annulation réécrirait la première mais
     * jamais la seconde (voir la migration 2026_09_03_220000). Ce test, lui,
     * authentifie réellement la session pour vérifier que les DEUX colonnes
     * concordent quand l'appel vient d'une requête authentifiée — le chemin
     * réel emprunté par la PWA.
     */
    #[Test]
    public function la_colonne_d_audit_dediee_et_la_colonne_generique_concordent_dans_le_flux_reel(): void
    {
        $this->actingAs($this->auteur);

        $reservation = $this->reservation();

        $annulee = $this->annulations->annuler($reservation, [
            'taux' => '50', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '0',
        ], $this->auteur);

        $this->assertSame($this->auteur->id, $annulee->utilisateur_annulation_id);
        $this->assertSame($this->auteur->id, $annulee->utilisateur_modification_id);
    }
}
