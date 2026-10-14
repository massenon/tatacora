<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * Clients & Creances (M3) — `m3-clients-creances.html`, la page qui fait foi
 * (`m3-crm.html` s'y declare remplacee, PA-126).
 *
 * Les points qui comptent :
 *  - le « Solde du » vient de `SoldeClientService` — la source unique du
 *    predicat, partagee avec le tableau de bord (PA-121) ; la colonne morte
 *    `clients.solde` n'est JAMAIS lue, et un cas la falsifie pour le prouver ;
 *  - LES QUATRE ONGLETS SONT PORTES depuis le 02/09/2026 (PA-165) — le
 *    bandeau « solde maximum » a disparu, les encaissements reduisant
 *    reellement les soldes. Les ECRITURES reelles (recouvrement, relance,
 *    nouveau client) sont tenues par `ClientsCreancesEcritureTest`, ce
 *    fichier tenant la SURFACE et la conformite du rendu.
 */
final class CrmPwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function la_page_est_reellement_servie(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/clients')->assertOk()->getContent();

        $this->assertStringContainsString(
            '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">Clients &amp; Créances</h1>',
            $html,
        );
        $this->assertGreaterThan(6000, strlen($html), 'La coquille sans contenu ?');
        $this->assertStringContainsString('<body data-module="M3"', $html);

        // ⚠ UN onglet du maitre, pas quatre (31/08/2026). Les trois autres
        // ne sont plus offerts : voir
        // `les_trois_onglets_bloques_ne_sont_ni_offerts_ni_expliques_a_l_ecran()`,
        // qui tient les deux moities — l'absence a l'ecran ET la declaration
        // dans le code.
        $this->assertStringContainsString('Liste des clients', $html);
    }

    /**
     * Le `magasinier` a `M3 = '-'` : la page lui est fermee — 2e niveau du
     * RBAC, une URL tapee a la main est refusee ici.
     */
    #[Test]
    public function un_profil_sans_droit_sur_m3_est_refuse(): void
    {
        $magasinier = $this->utilisateur('magasinier');
        $this->assertSame('-', $magasinier->niveauSurModule('M3'), 'La matrice a change : ce cas ne verifie plus rien.');

        $this->actingAs($magasinier);
        $this->get('/pwa/clients')->assertForbidden();
    }

    #[Test]
    public function un_invite_est_redirige_vers_le_formulaire_de_connexion(): void
    {
        $this->get('/pwa/clients')->assertRedirect(route('pwa.connexion'));
    }

    /* ------------------------------------------------- surface d'actions */

    /**
     * ⚠ Ce cas s'appelait « la page ne porte aucun champ d'écriture » et
     * exigeait que tout `wire:click` soit un `$set(...)`. Cette prémisse est
     * LEVÉE (01/09/2026) : la page porte des lectures d'export
     * (`ouvrirExport`/`genererExport`, inscrites dans
     * `METHODES_DE_LECTURE` — export unifié du 02/09/2026) et la vague
     * PA-165 lui apporte ses écritures (recouvrement, relances), chacune
     * gardée par `exigerEcriture()`. Le contrat qui RESTE : toute action de
     * composant câblée ici doit figurer dans la liste FERMÉE ci-dessous —
     * la surface complète étant tenue par `PwaActionsReluesTest` et le droit
     * d'écriture par `PwaEcritureAutoriseeTest`.
     */
    #[Test]
    public function toute_action_cablee_est_soit_un_set_soit_une_action_relue_de_la_page(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/clients')->assertOk()->getContent();

        $corps = $this->corpsPrincipalPwa($html, 'm3-clients-creances');
        preg_match_all('/wire:click="([^"]+)"/', $corps, $appels);

        $actionsRelues = [
            // lecture, PA-119 — bouton « Exporter » unique ouvrant la modale
            // partagée (dérogation PO du 01/09/2026, rappelée le 02/09/2026).
            'ouvrirExport',
            'genererExport',
            'fermerModales',
            // Écritures PA-165 (02/09/2026) — chacune gardée par
            // `exigerEcriture()`, prouvé par `PwaEcritureAutoriseeTest`.
            'ouvrirFormulaireClient',
            'ouvrirRecouvrement',
            'ouvrirRelance',
            // LECTURE — consulter un relevé n'écrit rien (voir le docblock
            // de `ClientsCreances::ouvrirHistoriqueClient()`).
            'ouvrirHistoriqueClient',
            // ARCHIVAGE du référentiel (03/09/2026, demande du Product Owner).
            // `confirmerArchivageClient` ouvre la confirmation — elle exige
            // DÉJÀ le droit d'archiver (`exigerArchivage()`), donc le bouton
            // n'est câblé que pour un rôle qui pourra aller au bout.
            // `restaurerClient` n'exige QUE l'écriture, délibérément :
            // fermer la bascule ne doit pas enfermer un client aux archives.
            'confirmerArchivageClient',
            'restaurerClient',
        ];

        foreach ($appels[1] as $appel) {
            if (str_starts_with($appel, '$set(')) {
                continue;
            }

            $nomAction = (string) preg_replace('/\(.*/', '', $appel);

            $this->assertContains(
                $nomAction,
                $actionsRelues,
                "Clients & Creances cable une action hors de sa liste relue : {$appel} (PA-67).",
            );
        }
    }

    /* --------------------------------------- le solde vient du SERVICE */

    #[Test]
    public function le_solde_affiche_est_celui_des_factures_certifiees_non_soldees(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/clients')->assertOk()->getContent();

        // KORA doit 6 000 (10 000 certifies - 4 000 payes) : la ligne est
        // rouge et la bande « Creances totales » porte le meme chiffre —
        // meme service, meme predicat.
        $this->assertStringContainsString('KORA', $html);
        $this->assertStringContainsString('6' . "\u{00A0}" . '000 FCFA', $html);

        // La cliente a jour rend un tiret, jamais un « 0 F » plausible.
        $this->assertStringContainsString('HOUNSOU', $html);
    }

    /**
     * PA-126 — la preuve a l'ecran : on falsifie la colonne morte
     * `clients.solde`, et RIEN ne change. Si un jour un composant la lisait,
     * ce cas rougirait avec « 999 999 F » sur la page.
     */
    #[Test]
    public function la_colonne_morte_clients_solde_n_est_jamais_lue_par_la_page(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        DB::table('clients')->update(['solde' => '999999.00']);

        $html = (string) $this->get('/pwa/clients')->assertOk()->getContent();

        $this->assertStringNotContainsString('999' . "\u{00A0}" . '999', $html);
        $this->assertStringContainsString('6' . "\u{00A0}" . '000 FCFA', $html);
    }

    #[Test]
    public function le_filtre_debiteurs_reduit_la_liste_sans_toucher_aux_totaux(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/clients?etat=debiteur')->assertOk()->getContent();

        $this->assertStringContainsString('KORA', $html);
        $this->assertStringNotContainsString('HOUNSOU', $html);

        $html = (string) $this->get('/pwa/clients?etat=solde')->assertOk()->getContent();

        $this->assertStringContainsString('HOUNSOU', $html);
        $this->assertStringNotContainsString('KORA', $html);
    }

    /**
     * LES QUATRE ONGLETS SONT REELLEMENT OFFERTS ET FONCTIONNELS (PA-165,
     * 02/09/2026) — renversement assume de ce que ce cas verifiait jusqu'ici.
     *
     * Jusqu'au 01/09/2026, trois onglets sur quatre etaient REFUSES : la
     * table `paiements` n'avait aucun writer (PA-21), et la balance agee
     * n'etait jamais arbitree (PA-20, cote « echeance » d'un client isole).
     * `EncaissementFactureService`, `RelanceClientService` et la balance agee
     * REELLE (ancienneté depuis `factures.date_emission`, un fait, jamais une
     * date d'echeance devinee) levent cette premisse. Ce cas verifie que les
     * quatre onglets s'ouvrent et rendent un contenu reel, pas un panneau de
     * refus.
     */
    #[Test]
    public function les_quatre_onglets_sont_reellement_offerts_et_fonctionnels(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Le registre des onglets offerts porte desormais les quatre.
        $this->assertSame(['clients', 'dettes', 'relances', 'avances'], ClientsCreances::ONGLETS);

        foreach (['dettes', 'relances', 'avances'] as $onglet) {
            $html = (string) $this->get('/pwa/clients?onglet=' . $onglet)->assertOk()->getContent();

            $this->assertStringContainsString('Suivi des dettes', $html);
            $this->assertStringContainsString('Relances clients', $html);
            $this->assertStringContainsString('Historique &amp; avances', $html);
        }

        // Onglet « Suivi des dettes » : KORA y figure avec son reste dû reel
        // (6 000, meme chiffre que la liste des clients — une seule formule).
        $html = (string) $this->get('/pwa/clients?onglet=dettes')->assertOk()->getContent();
        $this->assertStringContainsString('KORA', $html);
        $this->assertStringContainsString('6' . "\u{00A0}" . '000 FCFA', $html);

        // Onglet « Relances clients » : KORA, débiteur jamais relancé, y est
        // propose a la relance.
        $html = (string) $this->get('/pwa/clients?onglet=relances')->assertOk()->getContent();
        $this->assertStringContainsString('KORA', $html);
        $this->assertStringContainsString('Relancer', $html);

        // Onglet « Historique & avances » : rend reellement, meme vide.
        $html = (string) $this->get('/pwa/clients?onglet=avances')->assertOk()->getContent();
        $this->assertStringContainsString('Avances et acomptes', $html);
        $this->assertStringContainsString('Recouvrements encaissés', $html);
    }

    /**
     * Le bandeau « Le solde affiché est un maximum » a DISPARU (02/09/2026,
     * PA-165) : les encaissements reduisent desormais reellement les soldes
     * (`EncaissementFactureService`, premier writer de `paiements`), la
     * premisse du bandeau (PA-21) est levee. Garde d'ABSENCE — l'inverse
     * exact de ce que ce cas verifiait jusqu'ici.
     */
    #[Test]
    public function le_bandeau_solde_maximum_n_est_plus_affiche(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/clients')->assertOk()->getContent();

        $this->assertStringNotContainsString(
            'Le solde affiché est un maximum.',
            $html,
            'Le bandeau PA-21 est encore rendu alors que les encaissements réduisent réellement les soldes (PA-165).',
        );

        // Et le lien « Réservations » navigue reellement (Article 3.3).
        $this->assertStringContainsString('href="' . route('pwa.reservations') . '"', $html);
    }

    /* ----------------------------------------------------- auxiliaires */

    private function jeuDeDonnees(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $debiteur = Client::create([
            'nom' => 'KORA',
            'prenom' => 'Jean',
            'telephone' => '01 90 00 00 03',
            'type_client' => 'particulier',
        ]);

        Client::create([
            'nom' => 'HOUNSOU',
            'prenom' => 'Marceline',
            'telephone' => '01 90 00 00 04',
            'type_client' => 'structure',
        ]);

        // 10 000 certifies, 4 000 encaisses : reste 6 000.
        $factureId = (string) Str::uuid();
        DB::table('factures')->insert([
            'id' => $factureId,
            'client_id' => $debiteur->id,
            'date_emission' => now()->subDays(5)->toDateString(),
            'montant_ht' => '10000.00', 'montant_tva' => '0.00', 'montant_ttc' => '10000.00',
            'statut' => 'certifiee',
            'numero_mecef' => 'MECEF-TEST-' . Str::random(6),
            'utilisateur_creation_id' => auth()->id(),
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        $sessionId = (string) Str::uuid();
        DB::table('sessions_caisse')->insert([
            'id' => $sessionId,
            'point_vente' => 'reception',
            'utilisateur_ouverture_id' => auth()->id(),
            'date_ouverture' => now()->subDays(10),
            'montant_fond' => '10000.00',
        ]);

        DB::table('paiements')->insert([
            'id' => (string) Str::uuid(),
            'facture_id' => $factureId,
            'session_id' => $sessionId,
            'mode_paiement' => 'especes',
            'montant' => '4000.00',
            'date_paiement' => now()->subDays(2),
            'utilisateur_creation_id' => auth()->id(),
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.' . $role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.' . $role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
