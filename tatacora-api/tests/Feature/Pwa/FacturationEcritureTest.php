<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * M2 — l'avoir (RG-03) et le document A4 avec son filigrane.
 *
 * ## Ce que ces cas gardent, et pourquoi
 *
 * Avant ce lot, `Facturation` n'avait qu'une méthode publique : `render()`.
 * Le module était présenté comme livré et ne permettait rien. Deux gestes
 * l'ouvrent, et chacun porte un piège nommé dans le dépôt :
 *
 * - **L'avoir est la SEULE correction admise** (RG-03). Ni modification ni
 *   suppression : la facture d'origine doit rester rigoureusement intacte,
 *   sinon les deux pièces ne coexistent plus et la trace de l'erreur
 *   disparaît. C'est le point de la règle, et un cas le vérifie champ par
 *   champ.
 * - **Le filigrane se dérive de `estCertifiee()`, jamais de `estFigee()`**
 *   (PA-100). Une facture `MECEF-DEMO-` passée à `certifiee` par le job de
 *   rejeu EST figée et n'a AUCUNE valeur fiscale : fonder le filigrane sur le
 *   cycle de vie le ferait disparaître de l'exact document qu'il doit marquer.
 *
 * ## Preuve par MUTATION (31/08/2026), rejouée puis restaurée
 *
 * 1. `le_filigrane_de_demonstration_est_present…` : remplacer
 *    `@unless ($facture->estCertifiee())` par `@unless ($facture->estFigee())`
 *    dans `pdf/facture-mecef.blade.php` → ROUGE (le filigrane disparaît d'une
 *    facture `MECEF-DEMO-` certifiée). Restauré.
 * 2. `une_facture_figee_refuse_toute_modification` : neutraliser le refus de
 *    `FactureObserver::updating()` → ROUGE. Restauré.
 * 3. `un_avoir_laisse_la_facture_d_origine_intacte` : décrémenter
 *    `montant_ttc` après l'avoir → ROUGE.
 *
 * @see EF-M2-01 Émission de facture normalisée
 * @see RG-03 Immutabilité — l'avoir, unique chemin de correction
 * @see PA-100 `estFigee()` et `estCertifiee()`, deux prédicats de sens opposé
 * @see PA-124 Le filigrane « DOCUMENT DE DÉMONSTRATION »
 */
final class FacturationEcritureTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
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

    /** Le rôle qui porte `M2 = C`, lu du référentiel plutôt que supposé. */
    private function roleQuiEcritSurM2(): string
    {
        foreach (['receptionniste', 'gerant', 'administrateur'] as $role) {
            $trouve = Role::where('libelle', $role)->first();
            if ($trouve !== null && $trouve->niveauSurModule('M2') === 'C') {
                return $role;
            }
        }

        $this->fail('Aucun rôle du référentiel ne porte `M2 = C`.');
    }

    private function facture(string $statut = 'en_attente_certification', ?string $numero = null, array $extra = []): Facture
    {
        $client = Client::create([
            'nom' => 'KORA',
            'prenom' => 'Jean',
            'telephone' => '0190123456',
            'type_client' => 'particulier',
        ]);

        $facture = Facture::create([
            'client_id' => $client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '50000.00',
            'montant_tva' => '0.00',
            'montant_ttc' => '50000.00',
            'statut' => $statut,
            'numero_mecef' => $numero,
            ...$extra,
        ]);

        LigneFacture::create([
            'facture_id' => $facture->id,
            'source_module' => 'M1',
            'source_id' => $client->id,
            'libelle' => 'Hébergement — 2 nuitées',
            'quantite' => '2.00',
            'prix_unitaire' => '25000.00',
            'montant' => '50000.00',
        ]);

        return $facture->refresh();
    }

    // =====================================================================
    // RG-03 — l'avoir
    // =====================================================================

    #[Test]
    public function un_avoir_laisse_la_facture_d_origine_intacte(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM2()));

        $facture = $this->facture();
        $avant = $facture->only(['numero_mecef', 'client_id', 'montant_ht', 'montant_tva', 'montant_ttc', 'statut']);

        Livewire::test(Facturation::class)
            ->call('ouvrirFormulaireAvoir', $facture->id)
            ->assertSet('etatFormulaire', 'avoir')
            ->assertSet('avoirFactureId', $facture->id)
            ->set('avoirMontant', '12000')
            ->set('avoirMotif', 'Prestation non fournie — nuitée annulée')
            ->call('enregistrerAvoir')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $avoir = Avoir::query()->firstOrFail();
        $this->assertSame($facture->id, $avoir->facture_id);
        $this->assertSame(0, bccomp((string) $avoir->montant, '12000.00', 2));
        $this->assertSame('Prestation non fournie — nuitée annulée', $avoir->motif);

        // C'EST LE POINT DE LA RÈGLE : la facture d'origine ne bouge pas. Un
        // avoir n'est pas une facture négative — les deux pièces coexistent,
        // ce qu'une administration fiscale attend précisément.
        $this->assertSame(
            $avant,
            $facture->refresh()->only(array_keys($avant)),
            "La facture d origine a été modifiée par l émission de l avoir : RG-03 "
            .'exige qu elle reste rigoureusement intacte.',
        );
    }

    #[Test]
    public function un_avoir_superieur_au_ttc_est_refuse_et_n_ecrit_rien(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM2()));

        $facture = $this->facture();

        Livewire::test(Facturation::class)
            ->call('ouvrirFormulaireAvoir', $facture->id)
            ->set('avoirMontant', '90000')
            ->set('avoirMotif', 'Avoir plus grand que la facture')
            ->call('enregistrerAvoir')
            ->assertHasErrors('avoirMontant')
            ->assertSet('etatFormulaire', 'avoir');

        $this->assertSame(0, Avoir::query()->count(), 'Un avoir excédentaire a été écrit.');
    }

    #[Test]
    public function un_role_en_lecture_seule_ne_peut_ni_ouvrir_ni_emettre_un_avoir(): void
    {
        // `comptable` porte `M2 = 'L'` : il consulte le registre, il n'écrit
        // pas dedans. C'est le cas le plus utile — un rôle qui VOIT l'écran.
        $this->assertSame('L', Role::where('libelle', 'lecteur')->firstOrFail()->niveauSurModule('M2'));

        $this->actingAs($this->utilisateur('lecteur'));
        $facture = $this->facture();

        Livewire::test(Facturation::class)
            ->call('ouvrirFormulaireAvoir', $facture->id)
            ->assertForbidden();

        // L'ouverture ne protège rien : `etatFormulaire` est modifiable depuis
        // le navigateur.
        Livewire::test(Facturation::class)
            ->set('etatFormulaire', 'avoir')
            ->set('avoirFactureId', $facture->id)
            ->set('avoirMontant', '1000')
            ->set('avoirMotif', 'Tentative sans droit')
            ->call('enregistrerAvoir')
            ->assertForbidden();

        $this->assertSame(0, Avoir::query()->count());
    }

    #[Test]
    public function une_facture_figee_refuse_toute_modification(): void
    {
        // `estFigee()` porte l'ÉTAT DU CYCLE DE VIE : une facture certifiée en
        // démonstration se fige comme une vraie, sans quoi ce chemin ne serait
        // jamais emprunté hors Production.
        $facture = $this->facture('certifiee', null);
        $this->assertTrue($facture->estFigee());

        $leve = false;

        try {
            $facture->update(['montant_ttc' => '1.00']);
        } catch (\Throwable $refus) {
            $leve = true;
        }

        $this->assertTrue($leve, "Une facture figée a accepté une modification : RG-03 n est plus tenue.");
        $this->assertSame(
            0,
            bccomp((string) $facture->refresh()->montant_ttc, '50000.00', 2),
            'Le montant de la facture figée a changé en base.',
        );
    }

    // =====================================================================
    // Le document A4 et son filigrane (PA-124)
    // =====================================================================

    private function modeFacturation(string $mode): void
    {
        \App\Shared\Parametres\Models\ParametreSysteme::updateOrCreate(
            ['cle' => \App\Domain\Facturation\Services\ModeFacturation::CLE],
            ['valeur' => $mode],
        );
    }

    /**
     * ⚠ CONTRAT RENVERSÉ le 07/11/2026 — décision du PO : en mode DÉSACTIVÉ, la facture est une
     * facture SIMPLE, ordinaire, intitulée « Facture » : AUCUNE mention du tout (ni démonstration,
     * ni « non normalisé », ni « en attente », ni cachet réservé), AUCUN numéro MECeF, AUCUN QR.
     */
    #[Test]
    public function en_mode_desactive_la_facture_simple_ne_porte_aucune_mention_ni_numero_mecef(): void
    {
        $this->modeFacturation('desactive');
        $facture = $this->facture('certifiee', null);

        $this->assertTrue($facture->estFigee());
        $this->assertFalse($facture->estCertifiee());

        $html = $this->documentDe($facture);

        $this->assertStringContainsString('Facture', $html);
        $this->assertStringContainsString((string) $facture->numero, $html, 'Le numéro continu de la facture manque.');
        foreach (['DÉMONSTRATION', 'MECEF-DEMO', 'en attente', 'non normalisé', 'normalisation', 'normalisée', 'MECeF', 'cachet fiscal', 'code QR', 'sans valeur fiscale'] as $mention) {
            $this->assertStringNotContainsStringIgnoringCase($mention, $html, "La facture simple porte « {$mention} ».");
        }
        $this->assertStringNotContainsString('<svg', $html);
        $this->assertDoesNotMatchRegularExpression('/FAC-\d{4}-[0-9A-F]{8}/', $html, 'Une référence inventée remplace le numéro de la facture.');
    }

    /** e-MECeF / boîtier : « en attente de normalisation » ne s'affiche QUE dans ces modes. */
    #[Test]
    public function en_mode_normalisable_une_facture_non_normalisee_dit_qu_elle_attend_sa_normalisation(): void
    {
        foreach (['emecef', 'boitier'] as $mode) {
            $this->modeFacturation($mode);
            $html = $this->documentDe($this->facture('certifiee', null));

            $this->assertStringContainsString('Facture en attente de normalisation', $html, $mode);
            $this->assertStringNotContainsString('<svg', $html, 'aucun QR avant la normalisation');
            $this->assertStringNotContainsString('Facture normalisée MECeF', $html);
        }
    }

    #[Test]
    public function une_facture_normalisee_porte_son_numero_mecef_son_qr_et_ses_mentions(): void
    {
        $this->modeFacturation('emecef');
        $facture = $this->facture('certifiee', 'ED04000999-12', [
            'normalisation_statut' => 'normalisee',
            'normalisation_mode' => 'emecef',
            'qr_code_fiscal' => 'F;ED04000999;ABCD-EFGH-IJKL-MNOP;3201910768821;20261107101500',
            'code_mecef' => 'ABCD-EFGH-IJKL-MNOP',
        ]);

        $this->assertTrue($facture->estNormalisee());
        $html = $this->documentDe($facture);

        $this->assertStringContainsString('ED04000999-12', $html);
        $this->assertStringContainsString('Facture normalisée MECeF', $html);
        $this->assertStringContainsString('data:image/svg+xml;base64', $html, 'le QR est DESSINÉ');
        $this->assertStringNotContainsString('en attente', $html);
    }

    #[Test]
    public function le_document_ne_porte_ni_identifiant_fiscal_ni_cachet_tant_que_la_facture_n_est_pas_normalisee(): void
    {
        $this->modeFacturation('desactive');
        $facture = $this->facture('certifiee', null);

        $html = $this->documentDe($facture);

        // IFU et RCCM sont CONDITIONNELS et vides sur cette installation :
        // imprimer un exemple de format sur un document remis à un client
        // serait un faux identifiant fiscal (PA-101, PA-113).
        foreach (['IFU', 'RCCM'] as $mention) {
            $this->assertStringNotContainsString($mention, $html, "Le document porte « {$mention} » alors qu aucun n est renseigné.");
        }

        $this->assertStringNotContainsString('Emplacement réservé au cachet fiscal MECeF', $html);
        $this->assertStringNotContainsString('Aucun cachet n', $html);
        $this->assertStringNotContainsString('<svg', $html);
        $this->assertStringNotContainsString('data:image/png;base64', $html);
    }

    #[Test]
    public function l_ifu_et_le_nom_saisis_pour_le_client_s_impriment_sur_la_facture(): void
    {
        $facture = $this->facture('certifiee', null, ['acheteur_ifu' => '3201910768821', 'acheteur_nom' => 'SARL Atacora']);

        $html = $this->documentDe($facture);

        $this->assertStringContainsString('SARL Atacora', $html);
        $this->assertStringContainsString('3201910768821', $html);
    }

    #[Test]
    public function le_document_rend_les_avoirs_rattaches_et_le_net(): void
    {
        $valideur = $this->utilisateur($this->roleQuiEcritSurM2());
        $facture = $this->facture('certifiee', null);

        Avoir::create([
            'facture_id' => $facture->id,
            'motif' => 'Nuitée annulée',
            'montant' => '12000.00',
            'date_emission' => now()->toDateString(),
            // `utilisateur_validation_id` est NOT NULL au schéma : un avoir
            // doit toujours porter qui l a validé (RG-15).
            'utilisateur_validation_id' => $valideur->id,
        ]);

        $html = $this->documentDe($facture->refresh());

        // Libellé sans « (RG-03) » depuis le 01/09/2026 : les références de
        // règles ne s'impriment plus sur les documents remis (même règle que
        // les écrans).
        $this->assertStringContainsString('Avoirs rattachés', $html);
        $this->assertStringContainsString('Nuitée annulée', $html);
        // Le net est affiché EN PLUS du TTC, jamais à sa place : l'avoir ne
        // modifie pas la facture, il la neutralise.
        $this->assertStringContainsString('Net après avoirs', $html);
        $this->assertStringContainsString('50', $html, 'Le TTC d origine ne figure plus au document.');
    }

    #[Test]
    public function le_pdf_est_reellement_produit_et_n_est_pas_vide(): void
    {
        // « Le code livré a été réellement exécuté, pas seulement relu. » Un
        // gabarit Blade qui rend correctement peut encore produire un PDF vide
        // — dompdf est un second moteur, et c est le fichier remis au client
        // qui compte, pas le HTML qui le précède.
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM2()));

        $facture = $this->facture('certifiee', null);

        // Le composant est appele DIRECTEMENT : c est son flux qui est lu,
        // pas un rendu refait a cote. `imprimerFacture()` exige le droit,
        // charge la piece et passe par dompdf — tout le chemin.
        $instance = Livewire::test(Facturation::class)->instance();
        \assert($instance instanceof Facturation);
        $reponse = $instance->imprimerFacture($facture->id, app(\App\Shared\ReportEngine\Services\ReportHeaderService::class));

        $this->assertNotNull($reponse, 'Aucun document produit pour une facture qui existe.');

        ob_start();
        $reponse->sendContent();
        $binaire = (string) ob_get_clean();
        $this->assertStringStartsWith('%PDF-', $binaire, 'Le flux produit n est pas un PDF.');
        $this->assertGreaterThan(
            2500,
            strlen($binaire),
            'Le PDF est anormalement petit : page vide ?',
        );
    }

    /**
     * Le document, rendu par la MÊME vue que l'écran — jamais une copie.
     *
     * `imprimerFacture()` produit un PDF binaire ; c'est le HTML qui précède
     * dompdf qui porte les mentions à vérifier. La vue est donc rendue
     * directement, avec exactement les variables que le composant lui passe.
     */
    private function documentDe(Facture $facture): string
    {
        $facture->loadMissing(['lignes', 'avoirs', 'paiements']);

        $avoirs = '0.00';

        foreach ($facture->avoirs as $avoir) {
            $avoirs = bcadd($avoirs, (string) $avoir->montant, 2);
        }

        return view('pdf.facture-mecef', [
            'facture' => $facture,
            'client' => Client::query()->find($facture->client_id),
            'activites' => Facturation::ACTIVITES,
            'modesPaiement' => \App\Domain\Ventes\Services\VenteService::MODES_PAIEMENT,
            'totalAvoirs' => $avoirs,
            'net' => bcsub((string) $facture->montant_ttc, $avoirs, 2),
            'resteDu' => $facture->resteDu(),
            'auteur' => 'compte.test',
            'entete' => app(\App\Shared\ReportEngine\Services\ReportHeaderService::class)->genererEnTete(
                typeRapport: (string) __('facturation_pwa.document_titre'),
                periode: '',
                auteur: null,
            ),
        ])->render();
    }
}
