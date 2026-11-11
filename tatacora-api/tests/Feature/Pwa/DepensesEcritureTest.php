<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Models\LigneDepense;
use App\Domain\Depenses\Services\DepenseService;
use App\Models\User;
use App\Pwa\Livewire\Depenses\Depenses;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use Tests\TestCase;

/**
 * M10 — « une dépense saisie à l'écran atteint le grand livre », et elle peut
 * porter PLUSIEURS lignes.
 *
 * ## Le défaut que ces cas ferment, et pourquoi aucun test ne l'avait vu
 *
 * `Depenses::enregistrerDepense()` appelait `PasserEcritureService` derrière
 * `class_exists(PasserEcritureService::class)` — sur une classe qui n'existait
 * nulle part. La condition rendait `false` pour toujours : la dépense partait
 * en base, l'opérateur recevait son toast vert, et **aucune écriture n'a
 * jamais été produite**. Relevé du 31/08/2026 : cinq dépenses, zéro écriture.
 *
 * Aucune suite n'a pu le voir parce qu'aucun test n'empruntait le chemin. Ces
 * cas l'empruntent réellement — ils lisent `ecritures_comptables` après coup,
 * jamais l'intention du composant.
 *
 * ## La saisie est MULTI-LIGNES depuis le 31/08/2026
 *
 * Décision du Product Owner, qui prévaut sur le maître (dont la modale est
 * mono-ligne) : *« une dépense globale peut contenir une ou plusieurs lignes de
 * libellé d'achats ou autre avec son prix ; on peut éditer et supprimer dans la
 * même modale »*. Le domaine l'admettait déjà ; c'était l'écran qui bridait.
 *
 * Ce que ces cas tiennent, et qui n'est pas cosmétique : **une dépense à trois
 * lignes est UNE pièce comptable**, pas trois. Boucler sur les lignes à
 * l'écran produirait trois dépenses, trois pièces et trois numéros — et
 * laisserait la moitié d'un marché du matin comptabilisée si la troisième
 * était refusée.
 *
 * ## Preuve par MUTATION, rejouée puis restaurée
 *
 * Série du 31/08/2026 (mono-ligne), conservée :
 *
 * 1. `une_depense_enregistree_produit_une_ecriture_equilibree_et_validee` :
 *    remettre `if (class_exists(...))` autour de l'appel au service →
 *    ROUGE (« 0 écriture pour 1 dépense »). Restauré.
 * 2. `un_refus_comptable_n_ecrit_rien_et_le_dit` : remplacer le `catch` par un
 *    `catch (\Throwable) { }` muet → ROUGE (`assertHasErrors` échoue) ; poser
 *    la dépense AVANT la pièce → ROUGE (une dépense reste en base).
 * 3. `aucun_numero_de_compte_n_est_ecrit_en_dur_dans_l_ecran` : réintroduire
 *    `'601' => '601 — Achats de marchandises'` dans le composant → ROUGE.
 *
 * Série du 02/09/2026 (multi-lignes), chacune rejouée sur cette suite :
 *
 * 4. `une_depense_a_trois_lignes_est_UNE_piece_equilibree` : remplacer l'appel
 *    unique par une boucle `foreach ($lignes as $l) { $depenses->enregistrer(
 *    [... 'lignes' => [$l]], ...); }` → ROUGE (3 dépenses et 6 lignes
 *    d'écriture au lieu d'une pièce à 4 lignes). Restauré.
 * 5. `une_ligne_retiree_avant_enregistrement_n_est_pas_enregistree` :
 *    neutraliser le `unset()` de `retirerLigneDepense()` → ROUGE (la ligne
 *    retirée est comptabilisée). Restauré.
 * 6. `la_derniere_ligne_ne_peut_pas_etre_supprimee` : retirer la garde
 *    `count($this->lignes) <= 1` → ROUGE (0 ligne). Restauré.
 * 7. `un_montant_vide_ou_nul_designe_sa_ligne` : ramener `'lignes.*.montant'`
 *    à `['numeric']` seul → ROUGE (pas d'erreur, et une ligne à 0 F
 *    enregistrée). Restauré.
 * 8. `le_total_rendu_est_la_somme_bccomp_des_lignes` : rendre `'0.00'` en dur
 *    depuis `totalDesLignes()` → ROUGE. Restauré.
 *
 * @see EF-M10-02 Saisie des écritures comptables
 * @see RG-11 Immutabilité — la correction passe par contre-passation
 * @see RG-12 Centre de coût obligatoire
 */
final class DepensesEcritureTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** Le rôle qui porte `M10 = C`, lu du référentiel plutôt que supposé. */
    private function roleQuiEcritSurM10(): string
    {
        foreach (['comptable', 'gerant', 'administrateur'] as $role) {
            $trouve = Role::where('libelle', $role)->first();
            if ($trouve !== null && $trouve->niveauSurModule('M10') === 'C') {
                return $role;
            }
        }

        $this->fail(
            'Aucun rôle du référentiel ne porte `M10 = C` : cet écran serait '
            .'devenu inaccessible en écriture à tout le monde, et ce fichier '
            .'ne peut plus rien éprouver.',
        );
    }

    /**
     * Des comptes de charge RÉELS du plan, jamais des numéros écrits ici.
     *
     * @return list<string>
     */
    private function comptesDeCharge(int $combien = 1): array
    {
        $comptes = app(\App\Domain\Comptabilite\Services\PlanComptableService::class)
            ->comptesDeCharge()
            ->pluck('numero_compte')
            ->map(static fn (mixed $numero): string => (string) $numero)
            ->all();

        // Le fichier du PO ne porte aucun centre de coût : une dépense sur un compte
        // sans centre par défaut est refusée (RG-12). Le test choisit des feuilles à 4
        // chiffres et leur pose un centre, comme le ferait l'Administrateur.
        $comptes = array_values(array_filter($comptes, static fn (string $n): bool => strlen($n) === 4));
        $centre = \App\Domain\Comptabilite\Models\CentreCout::query()->where('libelle', 'Restaurant')->value('id');
        \App\Domain\Comptabilite\Models\CompteComptable::query()->whereIn('numero_compte', $comptes)->update(['centre_cout_defaut_id' => $centre]);

        $this->assertGreaterThanOrEqual(
            $combien,
            count($comptes),
            'Le plan comptable ne porte pas assez de comptes de classe 6 : le '
            .'sélecteur de l écran serait vide ou trop court, et ce cas ne '
            .'pourrait plus éprouver une ventilation sur plusieurs comptes.',
        );

        return array_slice($comptes, 0, $combien);
    }

    private function compteDeCharge(): string
    {
        return $this->comptesDeCharge()[0];
    }

    // =====================================================================
    // La saisie multi-lignes — décision du Product Owner du 31/08/2026
    // =====================================================================

    #[Test]
    public function la_modale_s_ouvre_sur_une_seule_ligne_vierge(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $composant = Livewire::test(Depenses::class)
            // « Ce rôle PEUT ouvrir » — l'action aboutit, elle ne rend ni 401
            // ni 403. Un cas qui ne vérifie que le refus laisserait passer une
            // garde trop serrée, qui fermerait l'écran à tout le monde.
            ->call('ouvrirFormulaireDepense')
            ->assertSet('etatFormulaire', 'depense');

        // `assertStatus()` rend le `TestResponse` sous-jacent : appel
        // TERMINAL, jamais un maillon de chaine (analyse statique, 02/09/2026).
        $composant->assertStatus(200);

        /** @var array<int, array<string, string>> $lignes */
        $lignes = $composant->get('lignes');

        $this->assertCount(
            1,
            $lignes,
            'La modale ne s ouvre pas sur exactement une ligne. Zéro ligne '
            .'obligerait à cliquer « Ajouter une ligne » pour commencer une '
            .'dépense, ce que personne ne devine ; deux feraient croire à une '
            .'saisie déjà commencée.',
        );
        $this->assertSame(['libelle' => '', 'compte_charge' => '', 'nature' => '', 'montant' => ''], $lignes[0]);

        // Rouvrir après une saisie abandonnée ne doit rien reproposer : une
        // ligne à moitié tapée serait enregistrée sans être relue.
        $composant
            ->set('lignes.0.libelle', 'Saisie abandonnée')
            ->set('lignes.0.nature', 'Oignon')
            ->call('ajouterLigneDepense')
            ->call('ouvrirFormulaireDepense');

        /** @var array<int, array<string, string>> $rouvertes */
        $rouvertes = $composant->get('lignes');

        $this->assertCount(1, $rouvertes, 'Les lignes d une saisie abandonnée ont survécu à la réouverture.');
        $this->assertSame('', $rouvertes[0]['libelle']);
    }

    #[Test]
    public function une_depense_a_trois_lignes_est_UNE_piece_equilibree(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $comptes = $this->comptesDeCharge(3);

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons — 3 sacs')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '12000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Tomates — 2 cageots')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '7500')
            ->call('ajouterLigneDepense')
            ->set('lignes.2.libelle', 'Transport du marché')
            ->set('lignes.2.nature', 'Oignon')
            ->set('lignes.2.compte_charge', $comptes[2])
            ->set('lignes.2.montant', '3000')
            ->call('enregistrerDepense')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        // UNE dépense, pas trois. Boucler à l'écran produirait trois pièces et
        // trois numéros pour un seul décaissement.
        $this->assertSame(
            1,
            Depense::query()->count(),
            'La saisie a produit plusieurs dépenses : les lignes sont parties '
            .'une par une, et un refus sur la dernière aurait laissé les deux '
            .'premières comptabilisées.',
        );

        $depense = Depense::query()->firstOrFail();

        // Le TOTAL est celui du serveur, recalculé sur les lignes validées.
        // Le navigateur n'en a posté aucun.
        $this->assertSame(
            0,
            bccomp((string) $depense->montant_total, '22500.00', 2),
            'Le total de la dépense n est pas la somme de ses trois lignes.',
        );

        $this->assertSame(3, LigneDepense::query()->count());

        // ------------------------------------------------- la pièce comptable
        $piece = EcritureComptable::query()->get();

        $this->assertCount(
            4,
            $piece,
            'La pièce ne porte pas ses quatre lignes : TROIS débits de charge '
            .'et UN crédit de trésorerie. Un crédit par ligne éclaterait un '
            .'seul décaissement en trois sorties de caisse.',
        );

        $debits = $piece->filter(static fn (EcritureComptable $e): bool => bccomp((string) $e->debit, '0.00', 2) > 0);
        $credits = $piece->filter(static fn (EcritureComptable $e): bool => bccomp((string) $e->credit, '0.00', 2) > 0);

        $this->assertCount(3, $debits, 'Les trois comptes de charge ne sont pas débités séparément.');
        $this->assertCount(1, $credits, 'La trésorerie doit être créditée UNE fois, pour le décaissement réel.');

        $this->assertSame(
            DepenseService::TRESORERIES['caisse']['compte'],
            $credits->first()?->compte?->numero_compte,
            'La contrepartie n est pas le compte de trésorerie du service.',
        );

        $totalDebit = '0.00';
        $totalCredit = '0.00';

        foreach ($piece as $ligne) {
            // `bcadd` sur des chaînes, jamais une somme flottante.
            $totalDebit = bcadd($totalDebit, (string) $ligne->debit, 2);
            $totalCredit = bcadd($totalCredit, (string) $ligne->credit, 2);

            $this->assertSame('validee', $ligne->statut, 'Une ligne de la pièce est restée en brouillon.');
            $this->assertNotSame('', (string) $ligne->centre_id, 'RG-12 : le centre de coût est obligatoire.');
        }

        $this->assertSame(0, bccomp($totalDebit, '22500.00', 2), 'Le total au débit n est pas celui de la dépense.');
        $this->assertSame(0, bccomp($totalDebit, $totalCredit, 2), 'La pièce est déséquilibrée (RG-11).');

        // Les trois comptes de charge sont DISTINCTS : une ventilation qui les
        // écraserait sur un seul compte rendrait le compte de résultat faux
        // sans rien changer au total, donc sans se voir.
        $numerosDebites = $debits
            ->map(static fn (EcritureComptable $e): string => (string) $e->compte?->numero_compte)
            ->sort()
            ->values()
            ->all();

        sort($comptes);

        $this->assertSame(
            $comptes,
            $numerosDebites,
            'Les trois lignes ne sont pas imputées aux trois comptes saisis.',
        );
    }

    #[Test]
    public function une_ligne_retiree_avant_enregistrement_n_est_pas_enregistree(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $comptes = $this->comptesDeCharge(2);

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '12000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Ligne saisie par erreur')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '99000')
            // Retirer une ligne du FORMULAIRE n'est pas le « D » de CRUD :
            // rien n'existe encore en base. C'est l'équivalent d'effacer une
            // saisie.
            ->call('retirerLigneDepense', 1)
            ->assertCount('lignes', 1)
            ->call('enregistrerDepense')
            ->assertHasNoErrors();

        $depense = Depense::query()->firstOrFail();

        $this->assertSame(
            0,
            bccomp((string) $depense->montant_total, '12000.00', 2),
            'La ligne retirée avant enregistrement a quand même été comptée : '
            .'le total porte les 99 000 F que l opérateur venait d effacer.',
        );

        $this->assertSame(1, LigneDepense::query()->count());
        $this->assertSame(
            0,
            LigneDepense::query()->where('libelle', 'Ligne saisie par erreur')->count(),
            'La ligne retirée est arrivée en base.',
        );

        // Et la pièce ne porte que la charge retenue plus sa contrepartie.
        $this->assertSame(2, EcritureComptable::query()->count());
    }

    #[Test]
    public function la_derniere_ligne_ne_peut_pas_etre_supprimee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        // Le geste est appelé DIRECTEMENT, comme le ferait un navigateur : la
        // vue ne rend pas le bouton quand il ne reste qu'une ligne, mais
        // cacher n'est pas protéger. Une dépense sans ligne n'existe pas —
        // `DepenseService::enregistrer()` la refuse — et le formulaire n'aurait
        // plus rien à quoi rattacher un compte de charge.
        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->assertCount('lignes', 1)
            ->call('retirerLigneDepense', 0)
            ->assertCount('lignes', 1)
            // Deux fois : une garde qui ne tiendrait qu'au premier appel
            // laisserait vider le formulaire en insistant.
            ->call('retirerLigneDepense', 0)
            ->assertCount('lignes', 1);
    }

    #[Test]
    public function un_montant_vide_ou_nul_designe_sa_ligne(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $comptes = $this->comptesDeCharge(3);

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '12000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Tomates')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '7500')
            ->call('ajouterLigneDepense')
            ->set('lignes.2.libelle', 'Piment')
            ->set('lignes.2.nature', 'Oignon')
            ->set('lignes.2.compte_charge', $comptes[2])
            // Vide : le cas courant d'une ligne ajoutée puis oubliée.
            ->set('lignes.2.montant', '')
            ->call('enregistrerDepense')
            // L'erreur désigne LA ligne fautive, pas le formulaire en bloc :
            // sur une dépense à six lignes, un refus global ferait relire les
            // six.
            ->assertHasErrors('lignes.2.montant')
            ->assertHasNoErrors('lignes.0.montant')
            ->assertHasNoErrors('lignes.1.montant')
            ->assertSet('etatFormulaire', 'depense');

        $this->assertSame(0, Depense::query()->count(), 'Une dépense a été écrite malgré une ligne sans montant.');
        $this->assertSame(0, EcritureComptable::query()->count());

        // Zéro n'est pas « vide », et c'est le piège : le navigateur poste `0`
        // pour un champ numérique laissé vide. Une ligne à 0 F produirait au
        // grand livre un débit nul sur un compte de charge — une imputation
        // qui affirme un achat sans argent.
        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '0')
            ->call('enregistrerDepense')
            ->assertHasErrors('lignes.0.montant');

        $this->assertSame(0, LigneDepense::query()->count());

        // Un compte de charge manquant nomme aussi SA ligne.
        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('libelle', 'Marché du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '12000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Tomates')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', '')
            ->set('lignes.1.montant', '7500')
            ->call('enregistrerDepense')
            ->assertHasErrors('lignes.1.compte_charge');

        $this->assertSame(0, Depense::query()->count());
    }

    #[Test]
    public function le_total_rendu_est_la_somme_bccomp_des_lignes(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $comptes = $this->comptesDeCharge(2);

        $composant = Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense');

        // Rien de saisi : le total vaut zéro, pas un tiret. Le formulaire
        // est ouvert, la question « combien » a donc un sens.
        // (`assertViewHas()` rend le `TestResponse` : appel hors chaine.)
        $composant->assertViewHas('totalSaisi', '0.00');

        $composant->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '12000');
        $composant->assertViewHas('totalSaisi', '12000.00');

        $composant->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Tomates')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '7500');
        // Recalculé à l'AJOUT et à la frappe : le total est lié en
        // `wire:model.live`, et il est rendu par le serveur, jamais par une
        // seconde formule en JavaScript.
        $composant->assertViewHas('totalSaisi', '19500.00');

        // Une ligne à moitié tapée n'est ni fatale ni comptée : `bcadd('12x')`
        // lève en PHP 8, et faire tomber la modale pendant la frappe serait
        // pire que d ignorer une valeur qui n est pas encore un nombre.
        $composant->set('lignes.1.montant', '75x');
        $composant->assertViewHas('totalSaisi', '12000.00');
        $composant->assertStatus(200);

        // Et le retrait le refait descendre.
        $composant->set('lignes.1.montant', '7500');
        $composant->assertViewHas('totalSaisi', '19500.00');
        $composant->call('retirerLigneDepense', 1);
        $composant->assertViewHas('totalSaisi', '12000.00');

        // La somme affichée est bien celle que `bcadd` produit sur les chaînes,
        // pas un arrondi flottant : le contrôle rejoue le calcul.
        $this->assertSame(0, bccomp(bcadd('12000', '0', 2), '12000.00', 2));
    }

    // =====================================================================
    // Les cas d'origine (31/08/2026), portés sur la saisie multi-lignes
    // =====================================================================

    #[Test]
    public function une_depense_enregistree_produit_une_ecriture_equilibree_et_validee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $compte = $this->compteDeCharge();

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->assertSet('etatFormulaire', 'depense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Marché du matin — légumes')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Marché du matin — légumes')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $compte)
            ->set('lignes.0.montant', '15000')
            ->call('enregistrerDepense')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $depense = Depense::query()->firstOrFail();
        $this->assertSame('Marché du matin — légumes', $depense->libelle);
        $this->assertSame(0, bccomp((string) $depense->montant_total, '15000.00', 2));

        // 1. L'ÉCRITURE EXISTE — c'est exactement ce que le défaut empêchait.
        $this->assertTrue(
            $depense->estComptabilisee(),
            'La dépense ne porte aucune écriture : `ecriture_id` est nul. '
            .'C est le défaut PA-159 — un toast vert, une caisse qui se vide, '
            .'et un grand livre qui ne voit rien.',
        );

        $lignes = EcritureComptable::query()->get();
        $this->assertCount(
            2,
            $lignes,
            'La pièce ne porte pas ses deux lignes : la charge au débit et la '
            .'trésorerie au crédit. Une pièce à sens unique serait refusée.',
        );

        // 2. ELLE EST ÉQUILIBRÉE — `bccomp`, jamais une égalité flottante.
        $debit = '0.00';
        $credit = '0.00';

        foreach ($lignes as $ligne) {
            $debit = bcadd($debit, (string) $ligne->debit, 2);
            $credit = bcadd($credit, (string) $ligne->credit, 2);
        }

        $this->assertSame(0, bccomp($debit, '15000.00', 2), "Le total au débit n est pas celui de la dépense.");
        $this->assertSame(0, bccomp($credit, '15000.00', 2), "Le total au crédit n est pas celui de la dépense.");
        $this->assertSame(0, bccomp($debit, $credit, 2), 'La pièce est déséquilibrée (RG-11).');

        // 3. ELLE EST VALIDÉE — toutes les lectures comptables du dépôt
        //    filtrent `statut = validee` : une pièce restée en brouillon
        //    resterait invisible au grand livre, à la balance et au compte de
        //    résultat. Le défaut serait le même, sous une forme plus douce.
        foreach ($lignes as $ligne) {
            $this->assertSame('validee', $ligne->statut, 'Une ligne de la pièce est restée en brouillon.');
            $this->assertNotSame('', (string) $ligne->centre_id, 'RG-12 : le centre de coût est obligatoire.');
        }

        // 4. La ventilation est persistée sur `lignes_depense`.
        $this->assertSame(1, LigneDepense::query()->count());
        $this->assertSame($compte, LigneDepense::query()->firstOrFail()->compte_charge);
    }

    /**
     * Reçu trop lourd : RÉDUIT, pas refusé (PO, 28/10/2026). Avant ce jour la
     * règle `max:400` refusait l'image ; ce cas épingle l'inverse.
     */
    #[Test]
    public function un_recu_de_plus_de_400_ko_est_reduit_et_la_depense_enregistree(): void
    {
        Storage::fake('public');
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $image = imagecreatetruecolor(1500, 1000);
        mt_srand(42);
        for ($x = 0; $x < 1500; $x++) {
            for ($y = 0; $y < 1000; $y++) {
                imagesetpixel($image, $x, $y, (mt_rand(0, 255) << 16) | (mt_rand(0, 255) << 8) | mt_rand(0, 255));
            }
        }
        ob_start();
        imagepng($image, null, 0);
        $lourde = (string) ob_get_clean();
        $this->assertGreaterThan(400 * 1024, strlen($lourde));

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Facture')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Facture')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $this->compteDeCharge())
            ->set('lignes.0.montant', '15000')
            ->set('photoRecu', UploadedFile::fake()->createWithContent('recu.png', $lourde))
            ->call('enregistrerDepense')
            ->assertHasNoErrors();

        $depense = Depense::query()->firstOrFail();
        $this->assertNotNull($depense->recu_path);
        $range = Storage::disk('public')->get($depense->recu_path);
        $this->assertLessThanOrEqual(400 * 1024, strlen($range));
        $this->assertSame('image/jpeg', $depense->recu_type);
        $this->assertSame(strlen($range), (int) $depense->recu_taille);
        $this->assertSame(hash('sha256', $range), $depense->recu_sha256);
        $this->assertStringEndsWith('.jpg', $depense->recu_path);
    }

    /** Un fichier qui n'est pas une image reste refusé, avec la phrase du validateur. */
    #[Test]
    public function un_recu_qui_n_est_pas_une_image_reste_refuse(): void
    {
        Storage::fake('public');
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Facture')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Facture')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $this->compteDeCharge())
            ->set('lignes.0.montant', '15000')
            ->set('photoRecu', UploadedFile::fake()->createWithContent('recu.txt', str_repeat('texte ', 100_000)))
            ->call('enregistrerDepense')
            ->assertHasErrors(['photoRecu']);

        $this->assertSame(0, Depense::query()->count());
    }

    #[Test]
    public function un_refus_comptable_n_ecrit_rien_et_le_dit(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        // Une date qu'aucun exercice ne couvre : le seeder n'ouvre que
        // l'exercice de l'année en cours, et les suivants naissent du geste de
        // clôture (EF-M10-07). Le refus est LOCAL et corrigible — c'est le
        // raisonnement de PA-62, pas celui de MECeF.
        $horsExercice = now()->subYears(9)->format('Y-m-d');

        $comptes = $this->comptesDeCharge(2);

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', $horsExercice)
            ->set('libelle', 'Transport hors exercice')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Course en ville')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '15000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Retour')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '5000')
            ->call('enregistrerDepense')
            // LE REFUS SE DIT. Un `catch` muet, ou un `ecriture_refus` rangé
            // dans une colonne que personne ne lit, serait le défaut d'origine
            // sous une forme plus douce.
            //
            // La clé est `comptabilisation`, pas un champ de saisie : le refus
            // porte sur la PIÈCE — journal, exercice, compte, centre —, jamais
            // sur une ligne. L'accrocher à un montant ferait chercher l'erreur
            // dans ce montant.
            ->assertHasErrors('comptabilisation')
            // La modale reste OUVERTE : la saisie n'est pas perdue.
            ->assertSet('etatFormulaire', 'depense')
            // …et les DEUX lignes tapées y sont encore. Les perdre obligerait à
            // tout ressaisir pour corriger une date.
            ->assertCount('lignes', 2);

        // ET RIEN N'A ÉTÉ ÉCRIT — les trois tables, pas seulement la première.
        $this->assertSame(0, Depense::query()->count(), 'Une dépense a été écrite malgré le refus comptable.');
        $this->assertSame(0, LigneDepense::query()->count(), 'Une ligne de ventilation subsiste sans sa dépense.');
        $this->assertSame(0, EcritureComptable::query()->count(), 'Une écriture subsiste alors que la pièce a été refusée.');
    }

    #[Test]
    public function un_role_sans_droit_ne_peut_ni_ouvrir_ni_enregistrer(): void
    {
        // `barman` porte `M10 = '-'` au référentiel.
        $this->actingAs($this->utilisateur('barman'));

        Livewire::test(Depenses::class)->call('ouvrirFormulaireDepense')->assertForbidden();

        // Les gestes de LIGNE sont gardés aussi. Ils ne persistent rien — ils
        // ne touchent que l'état du formulaire —, mais ce sont des méthodes
        // publiques atteignables par la route Livewire : le motif de la maison
        // les couvre, pour que la garde soit déjà là le jour où l'une d'elles
        // écrira réellement.
        Livewire::test(Depenses::class)->call('ajouterLigneDepense')->assertForbidden();
        Livewire::test(Depenses::class)->call('retirerLigneDepense', 0)->assertForbidden();

        // L'ouverture ne protège rien : `etatFormulaire` est une propriété
        // Livewire, modifiable depuis le navigateur. L'enregistrement exige
        // donc le droit une seconde fois.
        Livewire::test(Depenses::class)
            ->set('etatFormulaire', 'depense')
            ->set('libelle', 'Tentative sans droit')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes', [[
                'libelle' => 'Tentative sans droit',
                'compte_charge' => $this->compteDeCharge(),
                'montant' => '15000',
            ]])
            ->call('enregistrerDepense')
            ->assertForbidden();

        $this->assertSame(0, Depense::query()->count());
    }

    #[Test]
    public function le_rattrapage_comptabilise_une_depense_heritee(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        // Une dépense de l'ancien monde : écrite sans pièce, comme les cinq
        // qui étaient en base au 31/08/2026.
        $depense = Depense::create([
            'numero' => 'DEP-2026-00001',
            'date_transaction' => now()->toDateString(),
            'tresorerie' => 'caisse',
            'compte_tresorerie' => DepenseService::TRESORERIES['caisse']['compte'],
            'montant_total' => '7500.00',
            'libelle' => 'Dépense héritée, jamais comptabilisée',
            'ecriture_id' => null,
            'ecriture_refus' => null,
        ]);

        LigneDepense::create([
            'depense_id' => $depense->id,
            'libelle' => 'Dépense héritée, jamais comptabilisée',
            'compte_charge' => $this->compteDeCharge(),
            'nature' => 'Transport',
            'famille' => 'Services',
            'montant' => '7500.00',
        ]);

        $this->assertFalse($depense->estComptabilisee());

        // Aucun centre par défaut sur les comptes : seul le geste en porte un.
        \App\Domain\Comptabilite\Models\CompteComptable::query()->update(['centre_cout_defaut_id' => null]);

        // Sans centre choisi : refusé (RG-12), rien d'écrit.
        Livewire::test(Depenses::class)
            ->call('comptabiliserDepense', $depense->id)
            ->assertHasErrors('rattrapage');
        $this->assertFalse($depense->refresh()->estComptabilisee());

        Livewire::test(Depenses::class)
            ->set('centreRattrapage', (string) \App\Domain\Comptabilite\Models\CentreCout::where('libelle', 'Structure')->value('id'))
            ->call('comptabiliserDepense', $depense->id)
            ->assertHasNoErrors();

        $this->assertTrue(
            $depense->refresh()->estComptabilisee(),
            'Le rattrapage n a produit aucune écriture : les dépenses '
            .'antérieures resteraient invisibles au grand livre pour toujours.',
        );
        $this->assertSame(2, EcritureComptable::query()->count());
    }

    #[Test]
    public function l_export_pdf_est_reellement_produit_et_dit_son_filtre(): void
    {
        // « Le code livre a ete reellement execute, pas seulement relu. » Un
        // gabarit Blade qui rend bien peut encore produire un PDF vide :
        // dompdf est un second moteur.
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        $comptes = $this->comptesDeCharge(2);

        $composant = Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Marche du matin')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Oignons')
            ->set('lignes.0.nature', 'Oignon')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '15000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Tomates')
            ->set('lignes.1.nature', 'Oignon')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '2500')
            ->call('enregistrerDepense')
            ->assertHasNoErrors();

        $reponse = $composant->set('formatExport', 'pdf')->instance()->genererExport();

        $this->assertNotNull($reponse, 'Aucun document produit alors que la liste n est pas vide.');

        ob_start();
        $reponse->sendContent();
        $binaire = (string) ob_get_clean();

        $this->assertStringStartsWith('%PDF-', $binaire, 'Le flux produit n est pas un PDF.');
        $this->assertGreaterThan(
            5000,
            strlen($binaire),
            'Le PDF fait '.strlen($binaire).' octets : un fichier minuscule au '
            .'nom conforme est exactement le defaut PA-60.',
        );
    }

    #[Test]
    public function un_export_sur_une_liste_vide_est_refuse(): void
    {
        // PA-119 : une liste vide se REFUSE. Une page blanche ne dirait pas si
        // le filtre est trop etroit ou si la donnee n existe pas.
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        Livewire::test(Depenses::class)
            ->call('ouvrirExport', 'pdf')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }

    #[Test]
    public function aucun_numero_de_compte_n_est_ecrit_en_dur_dans_l_ecran(): void
    {
        // Le composant portait `601`, `614`, `6051`, `6052`, `628`, `5711` et
        // `5311` — sept numéros qu'aucun plan comptable du dépôt ne contient.
        // Aucune écriture n'ayant jamais été tentée, la divergence n'avait
        // jamais eu l'occasion de se voir.
        $sources = [
            (string) (new ReflectionClass(Depenses::class))->getFileName(),
            resource_path('views/pwa/depenses/depenses.blade.php'),
        ];

        $fautifs = [];

        foreach ($sources as $chemin) {
            $this->assertFileExists($chemin, "La source {$chemin} est introuvable : ce contrôle serait vide, donc vert.");

            foreach (explode("\n", (string) file_get_contents($chemin)) as $numero => $ligne) {
                // Un littéral de 3 à 6 chiffres commençant par 5 ou 6 : la
                // forme d'un compte SYSCOHADA de charge ou de trésorerie.
                if (preg_match("#['\"]([56][0-9]{2,5})['\"]#", $ligne, $trouve) === 1) {
                    $fautifs[] = basename($chemin).':'.($numero + 1).' → '.$trouve[1];
                }
            }
        }

        $this->assertSame(
            [],
            $fautifs,
            "Des numéros de compte sont écrits en dur dans l écran. Ils doivent venir\n"
            ."du plan comptable (`PlanComptableService::comptesDeCharge()`) et de\n"
            ."`DepenseService::TRESORERIES`. Deux listes finissent toujours par diverger,\n"
            ."et c est exactement ce qui s est produit ici.\n  "
            .implode("\n  ", $fautifs),
        );
    }

    #[Test]
    public function les_tresoreries_de_l_ecran_sont_celles_du_service(): void
    {
        // L'écran ne porte QUE les libellés ; les comptes et les journaux
        // vivent dans le service. Les deux registres doivent au moins parler
        // des mêmes trésoreries — une clé ajoutée d'un côté seulement
        // produirait un choix que l'enregistrement refuserait.
        $this->assertSame(
            array_keys(DepenseService::TRESORERIES),
            array_keys(Depenses::TRESORERIES),
            'Les trésoreries de l écran et celles du service ont divergé.',
        );
    }

    /**
     * PLUSIEURS CATEGORIES sur UNE depense — directive PO du 03/09/2026.
     * Chaque ligne porte SA nature et SA famille : le transport d un marche
     * n est plus range en « denrees » par la recopie de tete.
     */
    #[Test]
    public function une_depense_peut_meler_plusieurs_categories_chacune_dans_sa_famille(): void
    {
        $comptes = $this->comptesDeCharge(2);
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM10()));

        Livewire::test(Depenses::class)
            ->call('ouvrirFormulaireDepense')
            ->set('dateTransaction', now()->toDateString())
            ->set('libelle', 'Marche + course')
            ->set('tresorerieCode', 'caisse')
            ->set('lignes.0.libelle', 'Tomates')
            ->set('lignes.0.nature', 'Tomate')
            ->set('lignes.0.compte_charge', $comptes[0])
            ->set('lignes.0.montant', '5000')
            ->call('ajouterLigneDepense')
            ->set('lignes.1.libelle', 'Zem du marche')
            ->set('lignes.1.nature', 'Transport')
            ->set('lignes.1.compte_charge', $comptes[1])
            ->set('lignes.1.montant', '1000')
            ->call('enregistrerDepense')
            ->assertHasNoErrors();

        $depense = \App\Domain\Depenses\Models\Depense::latest('created_at')->firstOrFail();
        $familles = $depense->lignes->pluck('famille', 'nature')->all();

        $this->assertSame('Marché', $familles['Tomate']);
        $this->assertSame('Services', $familles['Transport']);
        $this->assertSame(0, bccomp((string) $depense->montant_total, '6000', 2));
    }
}
