<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Services\DeclarationTvaService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * La correspondance rôle -> compte, MODIFIABLE (décision du PO du 26/10/2026 :
 * « on peut impérativement modifier les comptes sur poste et le web »).
 *
 * Ce que ce fichier prouve, et comment chaque preuve a été éprouvée par
 * mutation (voir les notes « MUTATION PROUVÉE ») :
 *
 *  1. les DÉFAUTS sont les constantes de `ComptesSyscohada`, existent au plan
 *     et sont cohérents avec leur rôle ;
 *  2. les quatre refus de la validation (format, plan, classe, division) ;
 *  3. l'écriture passe par le registre fermé et le journal d'audit ;
 *  4. une pièce FUTURE suit le compte choisi, une pièce PASSÉE n'est jamais
 *     réécrite (RG-11) ;
 *  5. un compte sans centre par défaut ne bloque pas une pièce ;
 *  6. la déclaration de TVA relit l'ancien compte ET le nouveau ;
 *  7. l'écran : droits, refus affichés tels quels, rétablissement du défaut.
 */
final class CorrespondanceComptesTest extends TestCase
{
    use RefreshDatabase;

    private CorrespondanceComptesService $comptes;

    private EnregistrerParametreService $ecriture;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->comptes = app(CorrespondanceComptesService::class);
        $this->ecriture = app(EnregistrerParametreService::class);
    }

    // ------------------------------------------------------------ Défauts

    #[Test]
    public function chaque_role_vaut_sa_constante_tant_qu_aucun_compte_n_est_choisi(): void
    {
        $this->assertGreaterThanOrEqual(15, count(RolesCorrespondance::ROLES));

        foreach (array_keys(RolesCorrespondance::ROLES) as $role) {
            $this->assertSame(constant(ComptesSyscohada::class . '::' . $role), $this->comptes->compte($role));
        }
    }

    #[Test]
    public function chaque_defaut_existe_au_plan_et_passe_la_validation_de_son_propre_role(): void
    {
        foreach (array_keys(RolesCorrespondance::ROLES) as $role) {
            $defaut = RolesCorrespondance::defaut($role);

            $this->assertTrue(
                CompteComptable::query()->where('numero_compte', $defaut)->exists(),
                "Le défaut {$defaut} du rôle {$role} n'existe pas au plan.",
            );
            // Ne lève pas : un défaut que la validation refuserait serait un
            // compte qu'on ne pourrait jamais rétablir.
            $this->comptes->verifier($role, $defaut);
        }
    }

    #[Test]
    public function les_charges_ne_sont_pas_des_roles_modifiables(): void
    {
        foreach (['ACHATS_MARCHANDISES', 'ELECTRICITE', 'EAU', 'LOCATION_MATERIEL_TRANSPORT', 'TELEPHONE_INTERNET'] as $charge) {
            $this->assertFalse(RolesCorrespondance::existe($charge), "{$charge} n'a aucun lecteur de pièce : le déclarer serait un réglage sans effet.");
        }
    }

    #[Test]
    public function chaque_role_a_sa_cle_dans_le_registre_ferme_des_parametres(): void
    {
        foreach (array_keys(RolesCorrespondance::ROLES) as $role) {
            $definition = RegistreParametres::definition(CorrespondanceComptesService::cle($role));

            $this->assertNotNull($definition, "Le rôle {$role} n'a aucune clé au registre.");
            $this->assertSame(RegistreParametres::GROUPE_COMPTES, $definition->groupe);
            $this->assertSame($role, CorrespondanceComptesService::roleDeCle($definition->cle));
        }

        // 31 clés d'avant + une par rôle.
        $this->assertCount(31 + count(RolesCorrespondance::ROLES), RegistreParametres::cles());
    }

    // ------------------------------------------------------------ Validation

    #[Test]
    public function un_numero_hors_format_est_refuse_par_la_regle_unique_du_plan(): void
    {
        foreach (['7', '07073', '70739', 'abcd', '7 73', '7073.0'] as $numero) {
            $this->refus(
                'PRODUIT_LOCATIONS',
                $numero,
                __('comptabilite.compte_numero_invalide', ['numero' => $numero]),
            );
        }

        // 70 est valide par le FORMAT (deux chiffres) : c'est une division, refusée plus loin.
        $this->assertSame(1, preg_match(PlanComptableService::NUMERO_COMPTE_FORMAT, '70'));
        $this->refus('PRODUIT_LOCATIONS', '70', __('comptabilite.compte_division', ['numero' => '70']));
    }

    #[Test]
    public function un_compte_absent_du_plan_est_refuse(): void
    {
        $this->refus('PRODUIT_LOCATIONS', '7999', __('comptes_correspondance.compte_absent', ['numero' => '7999']));
    }

    #[Test]
    public function un_compte_d_une_autre_classe_que_celle_du_role_est_refuse(): void
    {
        $this->refus('PRODUIT_LOCATIONS', '6011', __('comptes_correspondance.compte_incoherent', [
            'numero' => '6011',
            'role' => 'Produits de la location de véhicules',
            'attendu' => 'est de la classe 7',
        ]));
        $this->refus('TVA_FACTUREE_BIENS', '4452', __('comptes_correspondance.compte_incoherent', [
            'numero' => '4452',
            'role' => 'TVA facturée sur les ventes de biens (bar)',
            'attendu' => 'commence par 443',
        ]));
        $this->refus('CAISSE', '4111', 'est de la classe 5');
        $this->refus('CLIENTS', '4011', 'commence par 411');
    }

    #[Test]
    public function une_division_du_plan_est_refusee_comme_pour_une_piece(): void
    {
        // 57 « Caisse » a des sous-comptes (5711, 5712) : aucun mouvement dessus.
        $this->refus('CAISSE', '57', __('comptabilite.compte_division', ['numero' => '57']));
        // 552, feuille à trois chiffres, reste imputable.
        $this->comptes->verifier('MOBILE_MONEY', '552');
    }

    // ------------------------------------------------------------ Écriture et audit

    #[Test]
    public function l_ecriture_passe_par_le_registre_et_laisse_une_trace_d_audit_avec_l_ancienne_valeur(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->assertSame(['compte_produit_locations'], $this->ecriture->enregistrer(['compte_produit_locations' => '7078']));
        $this->assertSame('7078', $this->comptes->compte('PRODUIT_LOCATIONS'));

        $this->assertSame(['compte_produit_locations'], $this->ecriture->enregistrer(['compte_produit_locations' => '7072']));

        $ligne = ParametreSysteme::where('cle', 'compte_produit_locations')->firstOrFail();
        $trace = JournalAudit::where('entite_concernee', 'parametres_systeme')
            ->where('entite_id', $ligne->id)
            ->where('action', 'modification')
            ->firstOrFail();

        $this->assertSame('7078', $trace->valeur_avant['valeur']);
        $this->assertSame('7072', $trace->valeur_apres['valeur']);
        $this->assertNotNull($trace->utilisateur_id);

        // Inchangée : rien n'est réécrit, donc aucune trace de plus.
        $avant = JournalAudit::count();
        $this->assertSame([], $this->ecriture->enregistrer(['compte_produit_locations' => '7072']));
        $this->assertSame($avant, JournalAudit::count());
    }

    #[Test]
    public function le_service_d_ecriture_refuse_ce_que_la_validation_refuse_donc_la_synchronisation_aussi(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('comptes_correspondance.compte_absent', ['numero' => '7999']));

        $this->ecriture->enregistrer(['compte_produit_locations' => '7999']);
    }

    #[Test]
    public function un_lot_refuse_n_ecrit_aucune_de_ses_cles(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        try {
            $this->ecriture->enregistrer(['compte_caisse' => '5712', 'compte_banque' => '6011']);
            $this->fail('Le lot aurait dû être refusé.');
        } catch (RuntimeException) {
            $this->assertSame(ComptesSyscohada::CAISSE, $this->comptes->compte('CAISSE'));
            $this->assertFalse(ParametreSysteme::where('cle', 'compte_caisse')->exists());
        }
    }

    #[Test]
    public function vider_la_cle_rétablit_le_defaut(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->ecriture->enregistrer(['compte_caisse' => '5712']);
        $this->assertSame('5712', $this->comptes->compte('CAISSE'));

        $this->ecriture->enregistrer(['compte_caisse' => '']);
        $this->assertSame(ComptesSyscohada::CAISSE, $this->comptes->compte('CAISSE'));
    }

    // ------------------------------------------------------------ Les pièces suivent

    #[Test]
    public function une_vente_future_suit_le_compte_choisi_et_une_piece_passee_n_est_jamais_reecrite(): void
    {
        $this->actingAs($this->utilisateur('gerant'));
        [$circuit, $vehicule] = $this->catalogue();

        $avant = $this->vendre('especes', [
            ['module' => 'M8', 'reference_id' => $vehicule->id, 'quantite' => 1],
            ['module' => 'M9', 'reference_id' => $circuit->id, 'quantite' => 1],
        ]);
        $this->assertSame('65000.00', $this->credit($this->piece($avant), '7073'));
        $lignesAvant = $this->signature($this->piece($avant));

        $this->ecriture->enregistrer(['compte_produit_locations' => '7078', 'compte_caisse' => '5712']);

        $apres = $this->vendre('especes', [
            ['module' => 'M8', 'reference_id' => $vehicule->id, 'quantite' => 1],
            ['module' => 'M9', 'reference_id' => $circuit->id, 'quantite' => 1],
        ]);
        $piece = $this->piece($apres);

        $this->assertSame('65000.00', $this->credit($piece, '7078'), 'La location suit le compte choisi.');
        $this->assertSame('15000.00', $this->credit($piece, '7061'), 'Le circuit garde son propre rôle : le rôle du restaurant et du circuit sont distincts.');
        $this->assertSame('80000.00', $this->debit($piece, '5712'), 'La trésorerie suit aussi.');
        $this->assertNull($this->ligneOuNull($piece, '7073'));
        $this->assertNull($this->ligneOuNull($piece, '5711'));

        // RG-11 : la première pièce est intacte, ligne pour ligne.
        $this->assertSame($lignesAvant, $this->signature($this->piece($avant)));
    }

    #[Test]
    public function le_circuit_et_le_restaurant_changent_independamment(): void
    {
        $this->actingAs($this->utilisateur('gerant'));
        [$circuit] = $this->catalogue();

        $this->ecriture->enregistrer(['compte_produit_circuits' => '7062']);

        $this->assertSame('7062', $this->comptes->compte('PRODUIT_CIRCUITS'));
        $this->assertSame(ComptesSyscohada::PRODUIT_PRESTATIONS, $this->comptes->compte('PRODUIT_PRESTATIONS'));

        $vente = $this->vendre('especes', [['module' => 'M9', 'reference_id' => $circuit->id, 'quantite' => 1]]);
        $this->assertSame('15000.00', $this->credit($this->piece($vente), '7062'));
    }

    #[Test]
    public function la_tva_de_chaque_module_suit_son_role_et_la_piece_s_equilibre(): void
    {
        $this->actingAs($this->utilisateur('gerant'));
        [$circuit, $vehicule] = $this->catalogue();
        $this->activerTva();

        $this->ecriture->enregistrer(['compte_tva_facturee_prestations' => '4433']);

        $vente = $this->vendre('mobile_money', [
            ['module' => 'M9', 'reference_id' => $circuit->id, 'quantite' => 1],
            ['module' => 'M8', 'reference_id' => $vehicule->id, 'quantite' => 1],
        ]);
        $piece = $this->piece($vente);

        $this->assertSame('12203.39', $this->credit($piece, '4433'));
        $this->assertNull($this->ligneOuNull($piece, '4432'));

        $debit = '0.00';
        $credit = '0.00';
        foreach ($piece as $e) {
            $debit = bcadd($debit, (string) $e->debit, 2);
            $credit = bcadd($credit, (string) $e->credit, 2);
        }
        $this->assertSame($debit, $credit);
    }

    #[Test]
    public function une_note_de_chambre_sur_un_compte_client_sans_centre_par_defaut_n_est_pas_refusee(): void
    {
        $this->actingAs($this->utilisateur('gerant'));
        [$circuit] = $this->catalogue();

        // 4112 « Clients-Groupe » n'a AUCUN centre par défaut au plan : sans le
        // repli sur le centre du compte par défaut du rôle (4111 -> Structure),
        // chaque note de chambre serait refusée par RG-12.
        $this->assertNull(CompteComptable::where('numero_compte', '4112')->value('centre_cout_defaut_id'));
        $this->ecriture->enregistrer(['compte_clients' => '4112']);

        $vente = $this->vendre('note_chambre', [['module' => 'M9', 'reference_id' => $circuit->id, 'quantite' => 1]]);
        $ligne = $this->ligneOuNull($this->piece($vente), '4112');

        $this->assertNotNull($ligne);
        $this->assertSame('Structure', CentreCout::findOrFail($ligne->centre_id)->libelle);
    }

    #[Test]
    public function une_depense_future_suit_la_tresorerie_choisie(): void
    {
        $this->actingAs($this->utilisateur('gerant'));
        $structure = CentreCout::where('libelle', 'Structure')->firstOrFail();
        $depenses = app(DepenseService::class);
        $donnees = [
            'tresorerie' => 'caisse',
            'centre_id' => $structure->id,
            'libelle' => 'Marché',
            'lignes' => [['compte_charge' => '6011', 'montant' => '10000.00']],
        ];

        $avant = $depenses->enregistrer($donnees);
        $this->assertSame('5711', $avant->compte_tresorerie);

        $this->ecriture->enregistrer(['compte_caisse' => '5712']);

        $apres = $depenses->enregistrer($donnees);
        $this->assertSame('5712', $apres->compte_tresorerie);
        $this->assertSame('5711', $avant->fresh()->compte_tresorerie, 'La dépense passée garde son compte (RG-11).');
        $this->assertSame(
            '5712',
            CompteComptable::findOrFail(EcritureComptable::findOrFail($apres->ecriture_id)->compte_id)->numero_compte,
        );
    }

    // ------------------------------------------------------------ États qui relisent un compte

    #[Test]
    public function la_declaration_de_tva_relit_l_ancien_compte_et_le_nouveau(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $declaration = app(DeclarationTvaService::class);

        $annee = now()->format('Y');

        // Une pièce d'AVANT le changement, sur 4432 (défaut), puis le changement.
        $this->ecritureTva('4432', '381.36', "{$annee}-03-10");
        $this->ecriture->enregistrer(['compte_tva_facturee_prestations' => '4433']);
        $this->ecritureTva('4433', '100.00', "{$annee}-03-20");

        $resultat = $declaration->pourPeriode("{$annee}-03-01", "{$annee}-03-31");

        $this->assertSame('481.36', $resultat['tva_collectee']);
    }

    #[Test]
    public function deux_roles_sur_le_meme_compte_ne_comptent_qu_une_fois_dans_la_declaration(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->ecriture->enregistrer(['compte_tva_facturee_prestations' => '4431']);
        $annee = now()->format('Y');
        $this->ecritureTva('4431', '300.00', "{$annee}-03-10");

        $resultat = app(DeclarationTvaService::class)->pourPeriode("{$annee}-03-01", "{$annee}-03-31");

        $this->assertSame('300.00', $resultat['tva_collectee']);
    }

    #[Test]
    public function la_cloture_passe_le_resultat_sur_le_compte_choisi_et_le_bilan_reste_equilibre(): void
    {
        $this->travelTo('2026-10-20 10:00:00');
        $this->actingAs($this->utilisateur('comptable'));
        $exercice = \App\Domain\Comptabilite\Models\ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
        $passer = app(\App\Domain\Comptabilite\Services\PasserEcritureService::class);
        $bar = CentreCout::where('libelle', 'Bar')->value('id');
        $restaurant = CentreCout::where('libelle', 'Restaurant')->value('id');
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => '100000.00'],
            ['compte' => '7011', 'credit' => '100000.00', 'centre_id' => $bar],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-11', 'libelle' => 'Marché', 'lignes' => [
            ['compte' => '6011', 'debit' => '30000.00', 'centre_id' => $restaurant],
            ['compte' => '5711', 'credit' => '30000.00'],
        ]]);

        // Le bénéfice sera reporté sur 133, plus sur 131.
        $this->ecriture->enregistrer(['compte_resultat_benefice' => '133']);
        $service = app(\App\Domain\Comptabilite\Services\ClotureExerciceService::class);
        $service->demarrer($exercice, auth()->user());
        $cloture = $service->cloturer($exercice->refresh(), auth()->user());

        $piece = EcritureComptable::where('numero_piece', $cloture->piece_cloture)->get();
        $this->assertNotNull($this->ligneOuNull($piece, '133'));
        $this->assertNull($this->ligneOuNull($piece, '131'));
        $this->assertSame('70000.00', $this->credit($piece, '133'));

        // Le bilan de l'exercice SUIVANT, qui porte les à-nouveaux : le résultat
        // y est au passif sur 133 (groupe 13), l'actif et le passif sont égaux —
        // un résultat hors de 131/139 ne le déséquilibre pas. (Celui de 2026 est
        // « d'avant la clôture » : il ne voit pas la pièce de clôture.)
        $suivant = \App\Domain\Comptabilite\Models\ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $bilan = app(\App\Domain\Comptabilite\Services\BilanService::class)
            ->genererPourExercice($suivant->id, ['validee']);
        $this->assertSame($bilan->totalActif, $bilan->totalPassif);
        $this->assertSame('70000.00', $bilan->totalActif);
    }

    // ------------------------------------------------------------ L'écran

    #[Test]
    public function le_comptable_modifie_un_compte_a_l_ecran_et_le_refus_s_affiche_tel_quel(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(\App\Pwa\Livewire\Comptabilite\CorrespondanceComptes::class)
            ->assertSee(__('comptes_correspondance.titre'))
            ->assertSee(__('comptes_correspondance.avertissement'))
            ->call('ouvrirEditionRole', 'PRODUIT_LOCATIONS')
            ->assertSet('numeroEdite', '7073')
            ->set('numeroEdite', '6011')
            ->call('enregistrerRole')
            ->assertHasErrors('numeroEdite')
            ->assertSee('est de la classe 7')
            ->set('numeroEdite', '7078')
            ->call('enregistrerRole')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame('7078', $this->comptes->compte('PRODUIT_LOCATIONS'));

        Livewire::test(\App\Pwa\Livewire\Comptabilite\CorrespondanceComptes::class)
            ->call('ouvrirEditionRole', 'PRODUIT_LOCATIONS')
            ->call('retablirRole')
            ->assertHasNoErrors();

        $this->assertSame('7073', $this->comptes->compte('PRODUIT_LOCATIONS'));
    }

    #[Test]
    public function un_profil_en_lecture_voit_l_ecran_mais_ne_peut_rien_modifier(): void
    {
        // `rh` : M10 = L.
        $this->actingAs($this->utilisateur('rh'));

        $html = (string) $this->get('/pwa/comptabilite/correspondance-comptes')->assertOk()->getContent();
        $this->assertStringContainsString(e(__('comptes_correspondance.lecture_seule')), $html);
        $this->assertStringNotContainsString(__('comptes_correspondance.modifier'), $html);

        Livewire::test(\App\Pwa\Livewire\Comptabilite\CorrespondanceComptes::class)
            ->call('ouvrirEditionRole', 'CAISSE')
            ->assertForbidden();

        $this->assertFalse(ParametreSysteme::where('cle', 'compte_caisse')->exists());
    }

    #[Test]
    public function un_profil_sans_acces_a_la_comptabilite_est_refuse(): void
    {
        $this->actingAs($this->utilisateur('barman'));

        $this->get('/pwa/comptabilite/correspondance-comptes')->assertForbidden();
    }

    #[Test]
    public function l_ecran_affiche_le_compte_actuel_son_libelle_et_l_etat_modifie(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->ecriture->enregistrer(['compte_produit_locations' => '7078']);

        $html = (string) $this->get('/pwa/comptabilite/correspondance-comptes')->assertOk()->getContent();

        $this->assertStringContainsString('7078', $html);
        $this->assertStringContainsString('Autres produits accessoires', $html);
        $this->assertStringContainsString(__('comptes_correspondance.etat_modifie'), $html);
        $this->assertStringContainsString(__('comptes_correspondance.groupe_produits'), $html);
        // Les quinze rôles sont listés.
        foreach (RolesCorrespondance::ROLES as $role => $definition) {
            $this->assertStringContainsString('data-role="' . $role . '"', $html);
        }
    }

    #[Test]
    public function la_correspondance_n_est_pas_dans_l_ecran_parametres(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/parametres')->assertOk()->getContent();

        $this->assertStringNotContainsString('compte_produit_locations', $html);
    }

    // ------------------------------------------------------------ Outils

    private function refus(string $role, string $numero, string $phrase): void
    {
        try {
            $this->comptes->verifier($role, $numero);
            $this->fail("{$role} <- {$numero} aurait dû être refusé.");
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString($phrase, $refus->getMessage());
        }
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

    /**
     * @return array{0: Circuit, 1: Vehicule}
     */
    private function catalogue(): array
    {
        return [
            Circuit::create([
                'nom' => 'Cascades de Kota', 'theme' => 'nature', 'zone' => 'Atacora',
                'duree' => '1 jour', 'prix' => '15000.00', 'capacite_max' => 12,
            ]),
            Vehicule::create([
                'categorie' => '4x4', 'immatriculation' => 'AB-123-CD', 'annee' => 2022,
                'transmission' => 'automatique', 'capacite' => 5, 'tarif_jour' => '65000.00',
                'statut' => 'disponible',
            ]),
        ];
    }

    private function activerTva(): void
    {
        foreach ([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => 'ttc',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     */
    private function vendre(string $mode, array $lignes): Vente
    {
        return app(VenteService::class)->enregistrer(['mode_paiement' => $mode, 'lignes' => $lignes]);
    }

    /**
     * @return Collection<int, EcritureComptable>
     */
    private function piece(Vente $vente): Collection
    {
        return EcritureComptable::where('libelle', 'Vente ' . $vente->numero)
            ->whereNull('ecriture_contrepassee_id')
            ->get();
    }

    /**
     * @param  Collection<int, EcritureComptable>  $piece
     * @return list<string>
     */
    private function signature(Collection $piece): array
    {
        $lignes = $piece->map(fn (EcritureComptable $e): string => implode('|', [
            CompteComptable::findOrFail($e->compte_id)->numero_compte,
            (string) $e->debit,
            (string) $e->credit,
            (string) $e->centre_id,
        ]))->all();
        sort($lignes);

        return $lignes;
    }

    /** @param  Collection<int, EcritureComptable>  $piece */
    private function credit(Collection $piece, string $numero): string
    {
        return (string) $this->ligne($piece, $numero)->credit;
    }

    /** @param  Collection<int, EcritureComptable>  $piece */
    private function debit(Collection $piece, string $numero): string
    {
        return (string) $this->ligne($piece, $numero)->debit;
    }

    /** @param  Collection<int, EcritureComptable>  $piece */
    private function ligne(Collection $piece, string $numero): EcritureComptable
    {
        return $this->ligneOuNull($piece, $numero) ?? $this->fail("La pièce ne porte aucune ligne sur le compte {$numero}.");
    }

    /** @param  Collection<int, EcritureComptable>  $piece */
    private function ligneOuNull(Collection $piece, string $numero): ?EcritureComptable
    {
        foreach ($piece as $ecriture) {
            if (CompteComptable::findOrFail($ecriture->compte_id)->numero_compte === $numero) {
                return $ecriture;
            }
        }

        return null;
    }

    private function ecritureTva(string $numero, string $credit, string $date): void
    {
        app(\App\Domain\Comptabilite\Services\PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD',
            'date' => $date,
            'libelle' => 'TVA de test',
            'lignes' => [
                ['compte' => '4111', 'debit' => $credit, 'credit' => '0', 'centre_id' => CentreCout::where('libelle', 'Structure')->value('id')],
                ['compte' => $numero, 'debit' => '0', 'credit' => $credit, 'centre_id' => CentreCout::where('libelle', 'Structure')->value('id')],
            ],
        ]);
    }
}
