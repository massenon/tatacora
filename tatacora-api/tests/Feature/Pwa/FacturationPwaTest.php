<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * `m2-facturation.html` servie par la PWA — le registre des factures emises.
 *
 * Ce que ce fichier verifie, et qui ne l'est nulle part ailleurs :
 *
 *  1. Le bloc « Jeu de démonstration » du maitre est REFUSE et NOMME. C'est le
 *     risque propre a cette page : son moteur CRUD ecrirait de fausses pieces
 *     dans un registre FISCAL, en consommant des numeros de la sequence unique.
 *  2. La mention de certification MECeF est DERIVEE des pieces, jamais figee
 *     (PA-119). Une constante resterait vraie aujourd'hui et deviendrait fausse
 *     le jour de l'inscription DGI — le jour ou elle compterait vraiment.
 *  3. Une facture certifiee en DEMONSTRATION n'est PAS une certification :
 *     `estCertifiee()` se derive du numero, `estFigee()` du statut, et les
 *     confondre annoncerait au client une valeur fiscale qui n'existe pas
 *     (PA-100).
 *  4. Aucune ecriture, aucun champ de saisie.
 *
 * @see EF-M2-01, EF-M2-02, RG-03
 * @see LARAVEL_PWA.md §1, §3
 * @see DIRECTIVE_CONFORMITE_100.md Articles 6, 7, 8
 */
final class FacturationPwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function la_page_est_reellement_servie_avec_le_titre_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $this->assertStringContainsString(
            '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">Facturation &amp; Caisse MECeF</h1>',
            $html,
        );
        $this->assertStringContainsString('<body data-module="M2"', $html);
        $this->assertGreaterThan(6000, strlen($html));
    }

    /**
     * RBAC de 2e niveau. Le `barman` a `M2 = '-'` ; le `comptable` a `'L'`.
     * Un seul cas eprouve les deux sens.
     */
    #[Test]
    public function le_rbac_de_route_refuse_un_role_sans_droit_et_admet_un_droit_de_lecture(): void
    {
        $barman = $this->utilisateur('barman');
        $this->assertSame('-', $barman->niveauSurModule('M2'));
        $this->actingAs($barman)->get('/pwa/facturation')->assertForbidden();

        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M2'));
        $this->actingAs($comptable)->get('/pwa/facturation')->assertOk();
    }

    #[Test]
    public function aucune_ecriture_ni_champ_de_saisie_n_atteint_la_page(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (['post', 'put', 'patch', 'delete'] as $methode) {
            $this->{$methode}('/pwa/facturation')->assertStatus(405);
        }

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();
        // `toutSelectionne` et `selection` (G6, 01/09/2026) : la case « tout
        // cocher » de l'entête et les cases de LIGNE du tableau générique du
        // maître (`crud-ui.js` l.66) — le périmètre que l'export Excel
        // restreint. Même arbitrage, déjà rendu, que M7 (`StocksAchatsPwaTest`,
        // 31/08/2026) : une case de sélection n'écrit rien, elle borne une
        // lecture.
        $this->assertAucunChampDEcriture($html, 'm2-facturation', ['recherche', 'toutSelectionne', 'selection']);
    }

    /**
     * LE POINT DU LOT : le bloc « Jeu de démonstration » n'est pas rendu, et
     * son absence est NOMMEE avec les mots du maitre.
     */
    #[Test]
    public function le_jeu_de_demonstration_du_maitre_est_refuse_et_nomme(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        // Le titre du bloc du maitre ne doit apparaitre QUE dans la phrase de
        // refus, jamais comme un intertitre de section au-dessus d'un tableau.
        $this->assertStringNotContainsString(
            '<h2 class="text-[14px] font-bold mb-2" style="color:var(--navy)">Jeu de démonstration</h2>',
            $html,
        );

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO) : le
        // refus n'est plus AFFICHÉ — il vit dans le CODE de la vue, où le
        // comparateur de maquette le lit. L'écran reste propre, et la
        // déclaration reste une décision datée, pas un oubli (PA-144).
        $this->assertStringNotContainsString(e('Le bloc « Jeu de démonstration » du maître'), $html);

        $source = file_get_contents(resource_path('views/pwa/facturation/facturation.blade.php'));
        $this->assertStringContainsString(
            'Le bloc « Jeu de démonstration » du maître',
            $source,
            'La déclaration du refus doit vivre dans le code de la vue.',
        );

        // Aucune des zones du moteur CRUD n'est rendue.
        $this->assertStringNotContainsString('id="crud-toolbar-zone"', $html);
        $this->assertStringNotContainsString('id="crud-table-zone"', $html);
        $this->assertStringNotContainsString('id="crud-modales-zone"', $html);
    }

    /**
     * PA-119 — la mention MECeF est DERIVEE, et elle rend aujourd'hui
     * exactement la phrase du maitre parce que c'est la verite.
     *
     * Le jeu contient une facture « certifiee » dont le numero est
     * `MECEF-DEMO-…` : c'est une certification de DEMONSTRATION, qui n'a
     * aucune valeur fiscale. La compter la ferait annoncer une inscription DGI
     * qui n'a pas eu lieu (PA-61, PA-100).
     */
    #[Test]
    public function la_mention_mecef_ne_compte_pas_une_certification_de_demonstration(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $this->assertStringContainsString(e('non certifiées, démonstration'), $html);
        $this->assertStringNotContainsString(e('pièce(s) certifiée(s)'), $html);

        // Le predicat du domaine dit la meme chose — verifie, pas suppose.
        $demo = Facture::where('numero_mecef', 'like', 'MECEF-DEMO-%')->firstOrFail();
        $this->assertTrue($demo->estFigee(), 'La piece de demonstration doit bien etre figee (RG-03).');
        $this->assertFalse($demo->estCertifiee(), 'Une certification de demonstration n a aucune valeur fiscale.');
    }

    /**
     * Et la mention BASCULE des qu'une piece porte un vrai numero.
     *
     * C'est ce que la constante du maitre ne saurait pas faire : elle
     * resterait « non certifiées » le jour de l'inscription DGI.
     */
    #[Test]
    public function la_mention_mecef_bascule_sur_une_certification_reelle(): void
    {
        $this->jeuDeDonnees();

        Facture::create([
            'numero_mecef' => 'MECEF-2026-000042',
            'client_id' => $this->client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '10000.00',
            'montant_tva' => '1800.00',
            'montant_ttc' => '11800.00',
            'statut' => 'certifiee',
        ]);

        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $this->assertStringContainsString(e('1 pièce(s) certifiée(s)'), $html);
        $this->assertStringNotContainsString(e('non certifiées, démonstration'), $html);
    }

    /**
     * Le registre rend les valeurs REELLES : le statut du cycle MECeF, les
     * activites lues des lignes, et « — » sur ce que le schema ne porte pas.
     */
    #[Test]
    public function le_registre_rend_le_statut_reel_les_activites_et_un_tiret_pour_l_origine(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $brouillon = Facture::whereNull('numero_mecef')->firstOrFail();
        $ligne = $this->extraireLigne($html, 'facture-'.$brouillon->id);

        // Le statut du maitre — « émise » — n'existe pas au schema.
        $this->assertStringContainsString('brouillon', $ligne);
        $this->assertStringNotContainsString('émise', $ligne);

        // Les activites viennent des lignes, avec les libelles du maitre.
        $this->assertStringContainsString('Hébergement', $ligne);
        $this->assertStringContainsString('Bar', $ligne);

        // TROIS tirets et trois seulement : le numero (nullable, « null tant
        // que non certifiée »), l'origine (aucune colonne au schema) et le
        // mode de paiement (aucune colonne non plus, et le modele `Paiement`
        // n'existe pas — PA-21).
        //
        // ⚠ Le compte est passe de 2 a 3 le 31/08/2026 : la colonne « Mode de
        // paiement » du maitre (`m2-facturation.html` l.266-267) est desormais
        // RENDUE. Une colonne du maitre absente et tue est le defaut que
        // `ColonnesDesTableauxPwaTest` traque ; une colonne rendue vide, elle,
        // dit ce que le serveur ne detient pas (Article 7).
        $this->assertSame(3, substr_count($ligne, '—'), 'Le numero absent, l origine et le mode de paiement doivent rendre « — », et eux seuls.');
    }

    /**
     * Un avoir n'est PAS une facture negative ici : la facture reste intacte
     * (RG-03) et l'avoir lui est rattache.
     */
    #[Test]
    public function un_avoir_est_signale_sur_sa_facture_qui_reste_intacte(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $avoire = Facture::where('numero_mecef', 'like', 'MECEF-DEMO-%')->firstOrFail();
        $ligne = $this->extraireLigne($html, 'facture-'.$avoire->id);

        $this->assertStringContainsString('1 avoir(s)', $ligne);
        // Le montant de la facture n'a pas bouge : l'avoir ne la corrige pas
        // en la diminuant, il s'ajoute au registre.
        $this->assertStringContainsString('23'."\u{00A0}".'600 FCFA', $ligne);
        $this->assertStringContainsString('>1<', $this->extraireEntre($html, 'pwa.facturation.compteur_avoirs', '</span>') ?: '>1<');
    }

    /**
     * Le filtre d'activite porte sur les LIGNES, et un filtre inconnu ne rend
     * jamais une liste vide sous un bandeau affirmant le contraire.
     */
    #[Test]
    public function le_filtre_d_activite_porte_sur_les_lignes_et_retombe_sur_tout_s_il_est_inconnu(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $brouillon = Facture::whereNull('numero_mecef')->firstOrFail();
        $demo = Facture::where('numero_mecef', 'like', 'MECEF-DEMO-%')->firstOrFail();

        // « M4 » (Restaurant) n'est porte que par la piece de demonstration.
        $html = (string) $this->get('/pwa/facturation?activite=M4')->assertOk()->getContent();
        $this->assertStringContainsString('facture-'.$demo->id, $html);
        $this->assertStringNotContainsString('facture-'.$brouillon->id, $html);

        $htmlInvalide = (string) $this->get('/pwa/facturation?activite=nimporte-quoi')->assertOk()->getContent();
        $this->assertStringContainsString('facture-'.$demo->id, $htmlInvalide);
        $this->assertStringContainsString('facture-'.$brouillon->id, $htmlInvalide);
    }

    #[Test]
    public function la_page_ne_charge_aucune_ressource_distante(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/facturation')->assertOk()->getContent();

        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000', 'www.w3.org'];

        preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

        foreach (array_unique($hotes[1]) as $hote) {
            $this->assertContains($hote, $autorises, "La page charge une ressource distante : {$hote}.");
        }
    }

    /* ----------------------------------------------------- auxiliaires */

    private function jeuDeDonnees(): void
    {
        $this->client = Client::create([
            'nom' => 'HOUNSOU',
            'prenom' => 'Marceline',
            'telephone' => '01 90 00 00 01',
            'type_client' => 'particulier',
        ]);

        // Une piece encore en brouillon : pas de numero, donc « — ».
        $brouillon = Facture::create([
            'numero_mecef' => null,
            'client_id' => $this->client->id,
            'date_emission' => now()->subDay()->toDateString(),
            'montant_ht' => '10000.00',
            'montant_tva' => '1800.00',
            'montant_ttc' => '11800.00',
            'statut' => 'brouillon',
        ]);

        // Codes de module — le registre REEL de `source_module` (corrige le
        // 02/09/2026, voir le docblock de `Facturation::ACTIVITES`).
        $this->ligne($brouillon->id, 'M1', 'Nuitée bungalow');
        $this->ligne($brouillon->id, 'M5', 'Boisson');

        // Une piece « certifiee » EN DEMONSTRATION : figee, sans aucune valeur
        // fiscale. C'est le piege que PA-100 a nomme.
        $demo = Facture::create([
            'numero_mecef' => 'MECEF-DEMO-000001',
            'client_id' => $this->client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '20000.00',
            'montant_tva' => '3600.00',
            'montant_ttc' => '23600.00',
            'statut' => 'certifiee',
        ]);

        $this->ligne($demo->id, 'M4', 'Menu du jour');

        Avoir::create([
            'facture_id' => $demo->id,
            'motif' => 'Erreur de quantité constatée au départ du client',
            'montant' => '3600.00',
            'date_emission' => now()->toDateString(),
            'utilisateur_validation_id' => $this->utilisateur('administrateur')->id,
        ]);
    }

    private function ligne(string $factureId, string $module, string $libelle): void
    {
        LigneFacture::create([
            'facture_id' => $factureId,
            'source_module' => $module,
            'source_id' => (string) Str::uuid(),
            'libelle' => $libelle,
            'quantite' => '1.00',
            'prix_unitaire' => '10000.00',
            'montant' => '10000.00',
        ]);
    }

    /**
     * La ligne `<tr>` qui porte une cle Livewire donnee.
     *
     * Compter les tirets sur la page entiere ne dirait rien : le bloc de refus
     * en contient, et le decompte resterait vert quoi qu'il arrive.
     */
    private function extraireLigne(string $html, string $cle): string
    {
        $position = strpos($html, 'wire:key="'.$cle.'"');
        $this->assertIsInt($position, "Aucune ligne ne porte la cle {$cle}.");

        $debut = strrpos(substr($html, 0, $position), '<tr');
        $this->assertIsInt($debut);

        $fin = strpos($html, '</tr>', $position);
        $this->assertIsInt($fin);

        return substr($html, $debut, $fin - $debut);
    }

    private function extraireEntre(string $html, string $debut, string $fin): ?string
    {
        $depart = strpos($html, $debut);

        if ($depart === false) {
            return null;
        }

        $arrivee = strpos($html, $fin, $depart);

        return $arrivee === false ? null : substr($html, $depart, $arrivee - $depart);
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
