<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Domain\Rh\Services\BulletinPaieService;
use App\Models\User;
use App\Pwa\Livewire\Rh\Paie;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Domain\Rh\Concerns\PoseLeReferentielDePaie;
use Tests\TestCase;

/**
 * M13 en ÉCRITURE — `m13-paie.html`, vague du 31/08/2026.
 *
 * Ce fichier remplace la suite de l'écran de refus : `Rh\Paie` sert désormais
 * l'effectif réel, les bulletins calculés, le livre de paie, les déclarations
 * et les barèmes.
 *
 * ## Ce qu'il tient, et qui n'est vérifié nulle part ailleurs
 *
 * 1. **Les cinq onglets se chargent réellement**, y compris avec un
 *    référentiel de taux VIDE — l'état qu'une base fraîchement semée produit,
 *    puisque `PaieReferentielSeeder` n'est appelé par personne. Sans ce cas,
 *    la première visite en production aurait rendu une exception au lieu d'un
 *    écran.
 * 2. **Aucun champ de montant calculé n'est saisi** : ni « Net à payer », ni
 *    « Charges patronales ». Garde de SOURCE sur la vue, parce que
 *    l'anti-pattern « Net à payer saisi » est nommément recensé au dépôt.
 * 3. **Le coût employeur n'est jamais un chiffre unique** (PA-53) : l'écran
 *    rend deux bornes.
 * 4. **Le RBAC d'écriture** : `barman` (`M13 = '-'`) n'atteint pas la route ;
 *    `comptable` (`M13 = 'L'`) lit mais n'écrit pas ; `rh` (`M13 = 'C'`) écrit.
 * 5. **La consultation d'un bulletin n'exige AUCUN droit d'écriture** — un
 *    `comptable` en `L` doit pouvoir lire un bulletin que la page lui affiche.
 *
 * ## Mutations RÉELLEMENT EXÉCUTÉES le 31/08/2026 — les trois ont mordu
 *
 * | Mutation                                                              | Cible rougie |
 * |------------------------------------------------------------------------|--------------|
 * | retirer `exigerEcriture()` de `genererBulletinsManquants()`              | `un_role_en_lecture_ne_genere_aucun_bulletin` |
 * | remplacer la fourchette de coût par `cout_min` seul dans la vue          | `le_cout_employeur_est_rendu_en_fourchette_jamais_en_chiffre_unique` |
 * | `etatReferentiel()` rendant toujours `complet => true`                   | `les_cinq_onglets_se_chargent_meme_sans_referentiel_de_taux` |
 *
 * ⚠ La deuxième n'a PAS mordu au premier essai, et la raison est instructive :
 * le cas asseyait les deux bornes SÉPARÉMENT, et la borne haute survivait dans
 * la carte d'indicateur « Coût employeur », qui la rend par un autre chemin.
 * Le cas était donc vert sur une valeur affichée ailleurs que là où il croyait
 * la lire. Il exige désormais les deux bornes dans la MÊME chaîne, celle que
 * seule la fonction de fourchette produit.
 *
 * @see EF-M13-01 Dossier du personnel
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 * @see PA-53 Le refus de calculer est le livrable
 */
final class RhPaiePwaTest extends TestCase
{
    use PoseLeReferentielDePaie;
    use RefreshDatabase;

    private const PERIODE = '2026-07';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.m13.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function serviceRh(): ServiceRh
    {
        return ServiceRh::firstOrCreate(['libelle' => 'Réception']);
    }

    private function employe(string $salaire = '150000.00'): Employe
    {
        return Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => 'HOUNSOU',
            'prenom' => 'Marceline',
            'poste' => 'Réceptionniste',
            'service_id' => $this->serviceRh()->id,
            'date_embauche' => '2023-02-01',
            'salaire_base' => $salaire,
            'statut' => 'actif',
        ]);
    }

    // =================================================================
    // 1 — les cinq onglets, référentiel vide compris
    // =================================================================

    #[Test]
    public function les_cinq_onglets_se_chargent_meme_sans_referentiel_de_taux(): void
    {
        // AUCUN taux en base : l'état réel d'une base semée par
        // `DatabaseSeeder`, qui n'appelle pas `PaieReferentielSeeder`.
        $this->employe();

        foreach (Paie::ONGLETS as $onglet) {
            $this->actingAs($this->compte('rh'));

            Livewire::test(Paie::class)
                ->set('periode', self::PERIODE)
                ->set('onglet', $onglet)
                ->assertOk()
                ->assertSee(__('rh_pwa.referentiel_titre'));
        }
    }

    #[Test]
    public function les_cinq_onglets_se_chargent_avec_le_referentiel_pose(): void
    {
        $this->poserLeReferentielDePaie();
        app(BulletinPaieService::class)->etablirBulletin($this->employe(), self::PERIODE);

        foreach (Paie::ONGLETS as $onglet) {
            $this->actingAs($this->compte('rh'));

            Livewire::test(Paie::class)
                ->set('periode', self::PERIODE)
                ->set('onglet', $onglet)
                ->assertOk()
                ->assertDontSee(__('rh_pwa.referentiel_titre'));
        }
    }

    // =================================================================
    // 2 — aucun montant calculé n'est saisi
    // =================================================================

    #[Test]
    public function aucun_montant_calcule_n_est_un_champ_de_formulaire(): void
    {
        // Garde de SOURCE : « Net à payer » saisi est l'un des anti-patterns
        // nommément recensés au dépôt (prototype d'origine, M13). Un test de
        // rendu ne le verrait pas si le champ n'apparaît qu'après un clic.
        $vue = (string) file_get_contents(resource_path('views/pwa/rh/paie.blade.php'));

        foreach (['wire:model="netSaisi"', 'wire:model="chargesSaisies"', 'wire:model="itsSaisi"'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $vue, "Un montant calculé est devenu saisissable : $interdit");
        }

        // Et le composant n'expose aucune propriété de ce genre.
        foreach (['netSaisi', 'itsSaisi', 'cnssSaisi', 'chargesSaisies'] as $propriete) {
            $this->assertFalse(
                property_exists(Paie::class, $propriete),
                "La propriété $propriete rendrait un montant calculé saisissable.",
            );
        }
    }

    // =================================================================
    // 3 — PA-53 : la fourchette, jamais un chiffre unique
    // =================================================================

    #[Test]
    public function le_cout_employeur_est_rendu_en_fourchette_jamais_en_chiffre_unique(): void
    {
        $this->poserLeReferentielDePaie();
        $this->employe('150000.00');

        // 150 000 + 29 100 (part confirmée) + 1 500 (RP à 1 %) = 180 600
        //                                    + 6 000 (RP à 4 %) = 185 100
        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->set('onglet', 'personnel')
            // ⚠ Les bornes passent par `MontantFcfa::format()`, jamais par une
            // chaine ecrite a la main : le separateur de milliers du formateur
            // est une espace insecable (U+00A0 depuis le 02/09/2026 — la fine
            // U+202F n'a pas de glyphe en Helvetica/WinAnsi et sortait « ? »
            // sur les PDF), pas une espace ordinaire.
            // La premiere version de ce cas comparait « 180 600 » et echouait
            // sur un rendu pourtant exact.
            // ⚠ Les DEUX bornes sont exigees ENSEMBLE, dans la meme chaine.
            // Mesure du 31/08/2026 : les asserter separement n'a PAS fait
            // mordre la mutation « rendre `cout_min` seul » — la borne haute
            // survivait dans la carte d'indicateur « Cout employeur », qui la
            // rend par un autre chemin. Un cas vert sur une valeur affichee
            // AILLEURS que la ou on la croit est exactement le genre de
            // couverture qui ne protege rien.
            ->assertSee(
                MontantFcfa::format('180600.00').' — '.MontantFcfa::format('185100.00'),
            )
            // Le bandeau qui explique pourquoi il y a deux bornes reste affiché.
            ->assertSee(__('rh_pwa.rp_titre'));
    }

    #[Test]
    public function le_bareme_its_affiche_son_refus_au_dela_du_plafond_confirme(): void
    {
        $this->poserLeReferentielDePaie();

        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->set('onglet', 'bareme')
            ->assertSee(__('rh_pwa.bareme_non_tranche'))
            ->assertSee(__('rh_pwa.bareme_refus'))
            ->assertSee(__('rh_pwa.source_non_confirme'));
    }

    #[Test]
    public function le_simulateur_rend_le_refus_du_service_au_dela_du_bareme(): void
    {
        $this->poserLeReferentielDePaie();

        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->set('onglet', 'bareme')
            ->set('brutSimule', '600000')
            ->assertSee(__('rh_pwa.simulateur_refus'));
    }

    // =================================================================
    // 4 — RBAC
    // =================================================================

    #[Test]
    public function un_role_sans_acces_au_module_n_atteint_pas_la_route(): void
    {
        // `barman` : M13 = '-'.
        $this->actingAs($this->compte('barman'))
            ->get('/pwa/paie')
            ->assertForbidden();
    }

    #[Test]
    public function un_role_en_lecture_voit_l_ecran_mais_n_ouvre_aucun_formulaire(): void
    {
        // `comptable` : M13 = 'L'.
        $this->actingAs($this->compte('comptable'))
            ->get('/pwa/paie')
            ->assertOk();

        $this->actingAs($this->compte('comptable'));

        Livewire::test(Paie::class)
            ->call('ouvrirFormulaireEmploye')
            ->assertForbidden();
    }

    #[Test]
    public function un_role_en_lecture_ne_genere_aucun_bulletin(): void
    {
        $this->poserLeReferentielDePaie();
        $this->employe();

        $this->actingAs($this->compte('comptable'));

        Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->call('genererBulletinsManquants')
            ->assertForbidden();

        $this->assertSame(0, BulletinPaie::query()->count());
    }

    // =================================================================
    // 5 — consulter un bulletin est une LECTURE
    // =================================================================

    #[Test]
    public function un_role_en_lecture_consulte_un_bulletin(): void
    {
        $this->poserLeReferentielDePaie();
        $bulletin = app(BulletinPaieService::class)->etablirBulletin($this->employe(), self::PERIODE);

        $this->actingAs($this->compte('comptable'));

        Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->set('bulletinAffiche', $bulletin->id)
            ->assertOk()
            ->assertSee(__('rh_pwa.bulletin_entete'))
            ->assertSee(__('rh_pwa.bulletin_net'));
    }

    // =================================================================
    // Le CRUD, via les Services
    // =================================================================

    #[Test]
    public function un_role_rh_cree_un_employe_et_son_matricule_est_alloue(): void
    {
        $service = $this->serviceRh();

        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->call('ouvrirFormulaireEmploye')
            ->set('nomSaisi', 'DOSSOU')
            ->set('prenomSaisi', 'Paul')
            ->set('posteSaisi', 'Chef cuisinier')
            ->set('serviceSaisi', $service->id)
            ->set('embaucheSaisie', '2026-01-15')
            ->set('contratSaisi', 'CDI')
            ->set('salaireBaseSaisi', '110000')
            ->set('statutSaisi', 'actif')
            ->call('enregistrerEmploye')
            ->assertHasNoErrors();

        $employe = Employe::query()->where('nom', 'DOSSOU')->firstOrFail();

        $this->assertNotNull($employe->matricule);
        $this->assertStringStartsWith('EMP-', (string) $employe->matricule);
        $this->assertSame($service->id, $employe->service_id);
    }

    #[Test]
    public function un_homonyme_doit_etre_confirme_avant_d_etre_enregistre(): void
    {
        $this->employe();
        $service = $this->serviceRh();

        $this->actingAs($this->compte('rh'));

        $composant = Livewire::test(Paie::class)
            ->call('ouvrirFormulaireEmploye')
            ->set('nomSaisi', 'HOUNSOU')
            ->set('prenomSaisi', 'Marceline')
            ->set('posteSaisi', 'Serveuse')
            ->set('serviceSaisi', $service->id)
            ->set('embaucheSaisie', '2026-01-15')
            ->set('salaireBaseSaisi', '70000')
            ->call('enregistrerEmploye');

        $composant->assertHasErrors('nomSaisi');
        $this->assertSame(1, Employe::query()->count());

        // AVERTIR, jamais bloquer : la confirmation est un second geste.
        $composant->set('doublonConfirme', true)
            ->call('enregistrerEmploye')
            ->assertHasNoErrors();

        $this->assertSame(2, Employe::query()->count());
    }

    #[Test]
    public function un_role_rh_etablit_un_bulletin_et_le_net_est_calcule(): void
    {
        $this->poserLeReferentielDePaie();
        $employe = $this->employe('150000.00');

        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->call('ouvrirEtablissementBulletin', $employe->id)
            ->call('etablirBulletin')
            ->assertHasNoErrors();

        $bulletin = BulletinPaie::query()->firstOrFail();

        $this->assertSame(0, bccomp('136140.00', (string) $bulletin->net_a_payer, 2));
        $this->assertSame(0, bccomp('29100.00', (string) $bulletin->charges_patronales_confirmees, 2));
    }

    #[Test]
    public function annuler_un_bulletin_exige_un_motif_et_ne_supprime_rien(): void
    {
        $this->poserLeReferentielDePaie();
        $bulletin = app(BulletinPaieService::class)->etablirBulletin($this->employe(), self::PERIODE);

        $this->actingAs($this->compte('rh'));

        $composant = Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->call('ouvrirAnnulationBulletin', $bulletin->id)
            ->call('annulerBulletin');

        $composant->assertHasErrors('motifAnnulation');

        $composant->set('motifAnnulation', 'Erreur de salaire de base.')
            ->call('annulerBulletin')
            ->assertHasNoErrors();

        $this->assertSame(1, BulletinPaie::query()->count());
        $this->assertSame(BulletinPaie::STATUT_ANNULEE, $bulletin->refresh()->statut);
    }

    #[Test]
    public function un_export_sur_une_liste_vide_est_refuse(): void
    {
        // PA-119 : une liste vide se REFUSE, elle ne produit pas une page
        // blanche que le Comptable croirait avoir vérifiée.
        $this->actingAs($this->compte('rh'));

        Livewire::test(Paie::class)
            ->set('periode', self::PERIODE)
            ->set('onglet', 'bulletins')
            ->call('ouvrirExport')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }

    // =================================================================
    // Archivage du personnel — directive PO du 02/09/2026
    // =================================================================

    private function ouvrirLaSuppression(): void
    {
        \App\Shared\Parametres\Models\ParametreSysteme::create([
            'cle' => \App\Shared\Parametres\Services\OptionsSystemeService::CLE_SUPPRESSION,
            'valeur' => 'true',
        ]);
    }

    #[Test]
    public function archiver_un_employe_le_passe_a_parti_sans_rien_supprimer(): void
    {
        $this->poserLeReferentielDePaie();
        $this->ouvrirLaSuppression();
        $employe = $this->employe();

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);
        $composant->call('ouvrirArchivageEmployes', $employe->id);
        $composant->call('archiverEmployes');
        $composant->assertHasNoErrors();

        $this->assertSame('parti', $employe->refresh()->statut);
        // RG-15 : la ligne existe toujours — archive, jamais supprime.
        $this->assertDatabaseHas('employes', ['id' => $employe->id]);
    }

    #[Test]
    public function l_archivage_en_bloc_traite_toute_la_selection(): void
    {
        $this->poserLeReferentielDePaie();
        $this->ouvrirLaSuppression();
        $premier = $this->employe();
        $second = Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => 'AGOSSOU',
            'prenom' => 'Pierre',
            'poste' => 'Barman',
            'service_id' => $this->serviceRh()->id,
            'date_embauche' => '2024-05-01',
            'salaire_base' => '90000.00',
            'statut' => 'actif',
        ]);

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);
        $composant->set('selection', [$premier->id, $second->id]);
        $composant->call('ouvrirArchivageEmployes');
        $composant->call('archiverEmployes');
        $composant->assertHasNoErrors();

        $this->assertSame('parti', $premier->refresh()->statut);
        $this->assertSame('parti', $second->refresh()->statut);
    }

    #[Test]
    public function un_employe_deja_parti_est_refuse_sans_faire_echouer_le_lot(): void
    {
        $this->poserLeReferentielDePaie();
        $this->ouvrirLaSuppression();
        $parti = $this->employe();
        $parti->update(['statut' => 'parti']);
        $actif = Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => 'DOSSA',
            'prenom' => 'Reine',
            'poste' => 'Cuisiniere',
            'service_id' => $this->serviceRh()->id,
            'date_embauche' => '2024-01-15',
            'salaire_base' => '80000.00',
            'statut' => 'actif',
        ]);

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);
        // Filtre « tous » (03/09/2026) : depuis que la selection est restreinte
        // aux lignes AFFICHEES, un employe deja parti est invisible sous le
        // filtre « actifs » par defaut — donc jamais dans le lot. Le cas de
        // refus reste atteignable ici, ou l'ecran montre bien les deux.
        $composant->set('filtreStatut', '');
        $composant->set('selection', [$parti->id, $actif->id]);
        $composant->call('ouvrirArchivageEmployes');
        $composant->call('archiverEmployes');

        // Le refus est AFFICHE, et l actif est archive quand meme : perdre le
        // lot pour une ligne deja traitee serait PA-65 a l envers.
        $composant->assertHasErrors('archivage');
        $this->assertSame('parti', $actif->refresh()->statut);
    }

    #[Test]
    public function la_bascule_fermee_refuse_l_archivage_en_403(): void
    {
        $this->poserLeReferentielDePaie();
        // Bascule NON posee : fermee par defaut.
        $employe = $this->employe();

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);
        $composant->set('employesAArchiver', [$employe->id]);
        $composant->call('archiverEmployes');
        $composant->assertStatus(403);

        $this->assertSame('actif', $employe->refresh()->statut);
    }

    // =================================================================
    // Qui peut archiver — directive PO du 03/09/2026
    //
    // La demande du Product Owner : « Supprimer » doit etre present sur CHAQUE
    // ligne et en BLOC, pour `administrateur` et `super_admin`. L'etat livre la
    // veille conditionnait tout a la bascule `activation_suppression`, fermee
    // par defaut : sur une installation neuve, l'Administrateur ne voyait rien.
    // Les cas ci-dessous tiennent la regle de `Paie::peutArchiver()` — ecrite
    // a UN SEUL endroit, lue par la vue et par le geste.
    //
    // ## Mutation REELLEMENT EXECUTEE le 03/09/2026 — elle a mordu deux fois
    //
    // Mutation : dans `App\Pwa\Support\AutoriseArchivage::peutArchiver()` — le
    // trait partage ou la regle a ete repliee le 03/09/2026, `Paie` en portait
    // une copie privee le meme jour —, remplacer la condition de role
    // `in_array(..., ROLES_ARCHIVAGE_HORS_BASCULE, true)` par `true` — donc
    // « tout role en `C` archive sans bascule », l'erreur exacte que la
    // demande du PO invitait a commettre.
    //
    // | Cible rougie                                                        |
    // |---------------------------------------------------------------------|
    // | `un_role_rh_ne_voit_aucun_archivage_tant_que_la_bascule_est_fermee`  |
    // | `la_bascule_fermee_refuse_l_archivage_en_403` (cas du 02/09/2026)    |
    //
    // Releve : 2 failed, 24 passed. Condition restauree, 26 passed apres.
    // =================================================================

    /** Le role qui archive sans bascule doit le faire SUR UNE BASE NEUVE. */
    private function assertArchiveSansBascule(string $role): void
    {
        $this->poserLeReferentielDePaie();
        // Bascule NON posee : c'est l'etat d'une installation neuve, et c'est
        // exactement celui que le PO a constate.
        $employe = $this->employe();

        $this->actingAs($this->compte($role));
        $composant = Livewire::test(Paie::class);

        // 1. Le bouton de LIGNE est rendu.
        $composant->assertSeeHtml("ouvrirArchivageEmployes('".$employe->id."')");
        // 2. La case de selection de ligne l'est aussi — c'est elle qui ouvre
        //    l'archivage en bloc.
        $composant->assertSeeHtml('wire:model.live="selection"');

        // 3. Et le geste s'execute reellement.
        $composant->call('ouvrirArchivageEmployes', $employe->id);
        $composant->call('archiverEmployes');
        $composant->assertHasNoErrors();

        $this->assertSame('parti', $employe->refresh()->statut);
        $this->assertDatabaseHas('employes', ['id' => $employe->id]);
    }

    #[Test]
    public function l_administrateur_archive_bascule_fermee(): void
    {
        $this->assertArchiveSansBascule('administrateur');
    }

    #[Test]
    public function le_super_admin_archive_bascule_fermee(): void
    {
        $this->assertArchiveSansBascule('super_admin');
    }

    #[Test]
    public function un_role_rh_ne_voit_aucun_archivage_tant_que_la_bascule_est_fermee(): void
    {
        // `rh` a bien `C` sur M13 : il etablit des bulletins, il modifie des
        // fiches. Ce que la bascule protege, c'est le geste destructeur — et
        // la levee accordee a l'administrateur ne doit pas fuir jusqu'a lui.
        $this->poserLeReferentielDePaie();
        $employe = $this->employe();

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);

        $composant->assertDontSeeHtml('ouvrirArchivageEmployes');
        $composant->assertDontSeeHtml('wire:model.live="selection"');

        // L'action FORGEE depuis le navigateur — l'absence du bouton ne
        // protege rien : `ouvrirArchivageEmployes` est une action Livewire
        // appelable telle quelle.
        $composant->call('ouvrirArchivageEmployes', $employe->id);
        $composant->assertStatus(403);

        $this->assertSame('actif', $employe->refresh()->statut);
    }

    #[Test]
    public function un_role_rh_retrouve_l_archivage_quand_la_bascule_est_ouverte(): void
    {
        // L'autre moitie de la regle : la bascule n'est pas devenue inerte.
        $this->poserLeReferentielDePaie();
        $this->ouvrirLaSuppression();
        $employe = $this->employe();

        $this->actingAs($this->compte('rh'));
        $composant = Livewire::test(Paie::class);
        $composant->assertSeeHtml("ouvrirArchivageEmployes('".$employe->id."')");
    }

    #[Test]
    public function un_role_en_lecture_ne_voit_ni_n_execute_l_archivage(): void
    {
        // `comptable` est en `L` sur M13 : ni la bascule ni le role ne peuvent
        // lui ouvrir le geste — `peutEcrire()` tranche en premier.
        $this->poserLeReferentielDePaie();
        $this->ouvrirLaSuppression();
        $employe = $this->employe();

        $this->actingAs($this->compte('comptable'));
        $composant = Livewire::test(Paie::class);
        $composant->assertDontSeeHtml('ouvrirArchivageEmployes');

        $composant->set('employesAArchiver', [$employe->id]);
        $composant->call('archiverEmployes');
        $composant->assertStatus(403);

        $this->assertSame('actif', $employe->refresh()->statut);
    }

    #[Test]
    public function un_employe_deja_parti_n_offre_pas_le_bouton(): void
    {
        $this->poserLeReferentielDePaie();
        $parti = $this->employe();
        $parti->update(['statut' => 'parti']);

        $this->actingAs($this->compte('administrateur'));
        // Filtre « parti » : la ligne EST affichee, mais sans bouton rouge.
        $composant = Livewire::test(Paie::class)->set('filtreStatut', 'parti');

        $composant->assertSeeHtml($parti->matricule);
        $composant->assertDontSeeHtml("ouvrirArchivageEmployes('".$parti->id."')");
    }

    #[Test]
    public function le_compteur_du_lot_suit_les_filtres_affiches(): void
    {
        // Cocher tout l'effectif puis changer de filtre ne doit pas archiver
        // des lignes que l'ecran ne montre plus (meme regle que l'export,
        // PA-119, transposee a une action destructrice).
        $this->poserLeReferentielDePaie();
        $actif = $this->employe();
        $parti = Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => 'KPOSSOU',
            'prenom' => 'Ines',
            'poste' => 'Femme de chambre',
            'service_id' => $this->serviceRh()->id,
            'date_embauche' => '2023-09-01',
            'salaire_base' => '70000.00',
            'statut' => 'parti',
        ]);

        $this->actingAs($this->compte('administrateur'));
        $composant = Livewire::test(Paie::class);

        // Case d'en-tete sous le filtre « actifs » : elle ne retient que les
        // employes VISIBLES, jamais l'effectif entier.
        $composant->set('toutSelectionne', true);
        $this->assertSame([$actif->id], $composant->get('selection'));

        // Selection forgee sur un employe hors filtre : le compteur ne le
        // compte pas, et l'ouverture du lot ne le vise pas.
        $composant->set('selection', [$actif->id, $parti->id]);
        $composant->assertSeeHtml(trans_choice('rh_pwa.archivage.bouton_lot', 1, ['nombre' => 1]));

        $composant->call('ouvrirArchivageEmployes');
        $this->assertSame([$actif->id], $composant->get('employesAArchiver'));
    }
}
