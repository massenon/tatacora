<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Exports\FacturationExport;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Support\NumeroRegistre;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Barryvdh\DomPDF\Facade\Pdf;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use Maatwebsite\Excel\Facades\Excel;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La colonne « N° » du registre des factures (PO, 09/11/2026) : le numéro FISCAL quand la facture est
 * normalisée, SINON le numéro INTERNE de la séquence (`F-AAAA-NNNNN`) avec la légende « n° interne » —
 * jamais « — ». Écran, registre imprimé, PDF et tableur portent la même valeur ; la recherche trouve
 * par l'un ou l'autre ; une facture simple ne dit rien de la normalisation.
 */
final class NumeroRegistreFactureTest extends TestCase
{
    use RefreshDatabase;

    private const FISCAL = 'ED04000999-42';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs(User::create([
            'login' => 'nabogou', 'mot_de_passe_hash' => Hash::make('x-mot-de-passe-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id, 'statut' => 'actif',
        ]));
    }

    private function facture(?string $fiscal, ?string $norm, string $mode = 'emecef', string $nom = 'HOUNSOU'): Facture
    {
        ParametreSysteme::updateOrCreate(['cle' => 'facturation_mode'], ['valeur' => $mode]);
        $client = Client::create(['nom' => $nom, 'prenom' => 'M', 'telephone' => '01 90 00 00 0'.random_int(1, 9), 'type_client' => 'particulier']);

        return Facture::create([
            'numero_mecef' => $fiscal,
            'client_id' => $client->id, 'date_emission' => now()->toDateString(),
            'montant_ht' => '10000.00', 'montant_tva' => '1800.00', 'montant_ttc' => '11800.00',
            'statut' => 'certifiee', 'normalisation_statut' => $norm,
            'normalisation_mode' => $norm === null ? null : 'emecef',
            'qr_code_fiscal' => $norm === 'normalisee' ? 'F;ED04000999;ABCD;3201910768821;20261107101500' : null,
        ]);
    }

    /** Le contenu de la ligne de l'écran (hors registre imprimé : `wire:key="facture-…"`). */
    private function ligne(string $html, Facture $facture): string
    {
        $this->assertSame(1, preg_match('/wire:key="facture-'.$facture->id.'".*?<\/tr>/s', $html, $m), 'ligne absente');

        return $m[0];
    }

    #[Test]
    public function une_facture_normalisee_affiche_son_numero_fiscal_sans_legende(): void
    {
        $f = $this->facture(self::FISCAL, 'normalisee');
        $ligne = $this->ligne(Livewire::test(Facturation::class)->html(), $f);

        $this->assertStringContainsString(self::FISCAL, $ligne);
        $this->assertStringNotContainsString((string) $f->numero, $ligne, 'Le numéro interne ne double pas le numéro fiscal.');
        $this->assertStringNotContainsString('n° interne', $ligne);
    }

    #[Test]
    #[DataProvider('nonNormalisees')]
    public function une_facture_non_normalisee_affiche_son_numero_interne_et_jamais_un_tiret(string $mode, ?string $norm, ?string $fiscal): void
    {
        $f = $this->facture($fiscal, $norm, $mode);
        $this->assertMatchesRegularExpression('/^F-\d{4}-\d{5}$/', (string) $f->numero);

        $ligne = $this->ligne(Livewire::test(Facturation::class)->html(), $f);

        $this->assertMatchesRegularExpression('/font-mono-tatacora[^>]*>\s*'.preg_quote((string) $f->numero, '/').'\s*(?:<!--.*?-->)?\s*<span[^>]*>n° interne</us', $ligne);
    }

    /** @return array<string, array{string, ?string, ?string}> */
    public static function nonNormalisees(): array
    {
        return [
            'simple (désactivé)' => ['desactive', null, null],
            'en attente' => ['emecef', 'en_attente', null],
            'refusée' => ['boitier', 'refusee', null],
            'à vérifier' => ['boitier', 'a_verifier', null],
            'démonstration' => ['emecef', null, 'MECEF-DEMO-0001'],
        ];
    }

    #[Test]
    public function une_facture_simple_ne_dit_rien_de_la_normalisation(): void
    {
        $f = $this->facture(null, null, 'desactive');
        $ligne = $this->ligne(Livewire::test(Facturation::class)->html(), $f);

        $this->assertStringNotContainsStringIgnoringCase('normalis', $ligne);
        $this->assertStringNotContainsStringIgnoringCase('fiscal', $ligne);
        $this->assertStringNotContainsString('MECeF', $ligne);
    }

    #[Test]
    public function une_facture_refusee_porte_son_numero_interne_et_son_statut(): void
    {
        $f = $this->facture(null, 'refusee', 'boitier');
        $ligne = $this->ligne(Livewire::test(Facturation::class)->html(), $f);

        $this->assertStringContainsString((string) $f->numero, $ligne);
        $this->assertStringContainsString('normalisation refusée', $ligne);
    }

    #[Test]
    public function la_recherche_trouve_par_le_numero_fiscal_comme_par_le_numero_interne(): void
    {
        $normalisee = $this->facture(self::FISCAL, 'normalisee', 'emecef', 'ADJOVI');
        $simple = $this->facture(null, null, 'desactive', 'BIO');

        Livewire::test(Facturation::class)->set('recherche', self::FISCAL)
            ->assertSeeHtml('wire:key="facture-'.$normalisee->id.'"')
            ->assertDontSeeHtml('wire:key="facture-'.$simple->id.'"');

        Livewire::test(Facturation::class)->set('recherche', (string) $normalisee->numero)
            ->assertSeeHtml('wire:key="facture-'.$normalisee->id.'"')
            ->assertDontSeeHtml('wire:key="facture-'.$simple->id.'"');

        Livewire::test(Facturation::class)->set('recherche', (string) $simple->numero)
            ->assertSeeHtml('wire:key="facture-'.$simple->id.'"')
            ->assertDontSeeHtml('wire:key="facture-'.$normalisee->id.'"');
    }

    #[Test]
    public function le_tableur_porte_la_meme_valeur_que_l_ecran(): void
    {
        $normalisee = $this->facture(self::FISCAL, 'normalisee', 'emecef', 'ADJOVI');
        $simple = $this->facture(null, null, 'desactive', 'BIO');
        Excel::fake();
        Excel::matchByRegex();

        Livewire::test(Facturation::class)->set('formatExport', 'excel')->call('genererExport');

        Excel::assertDownloaded('/^facturation_.*\.xlsx$/', function (FacturationExport $export) use ($normalisee, $simple): bool {
            $valeurs = $export->collection()->mapWithKeys(fn (Facture $f): array => [$f->id => $export->map($f)[0]]);

            $this->assertSame(self::FISCAL, $valeurs[$normalisee->id]);
            $this->assertSame((string) $simple->numero, $valeurs[$simple->id]);

            return true;
        });
    }

    #[Test]
    public function le_pdf_et_le_registre_imprime_portent_la_meme_valeur_que_l_ecran(): void
    {
        $normalisee = $this->facture(self::FISCAL, 'normalisee', 'emecef', 'ADJOVI');
        $simple = $this->facture(null, null, 'desactive', 'BIO');

        $html = '';
        $faux = Pdf::loadHTML('<p>x</p>');
        Pdf::shouldReceive('loadView')->once()->andReturnUsing(function (string $vue, array $donnees) use (&$html, $faux) {
            $html = view($vue, $donnees)->render();

            return $faux;
        });

        Livewire::test(Facturation::class)->set('formatExport', 'pdf')->call('genererExport');

        $this->assertStringContainsString('>'.self::FISCAL.'<', $html);
        $this->assertStringContainsString('>'.$simple->numero.'<', $html);
        $this->assertStringNotContainsString($normalisee->numero, $html);

        // Registre imprimé de l'écran (`hidden print:block`) : même règle.
        $ecran = Livewire::test(Facturation::class)->html();
        $this->assertSame(1, preg_match('/wire:key="doc-facture-'.$simple->id.'".*?<\/tr>/s', $ecran, $m));
        $this->assertStringContainsString((string) $simple->numero, $m[0]);
        $this->assertSame(1, preg_match('/wire:key="doc-facture-'.$normalisee->id.'".*?<\/tr>/s', $ecran, $n));
        $this->assertStringContainsString(self::FISCAL, $n[0]);
        $this->assertStringNotContainsString((string) $normalisee->numero, $n[0]);
    }

    #[Test]
    public function un_avoir_suit_la_meme_regle(): void
    {
        $f = $this->facture(self::FISCAL, 'normalisee');
        $avoir = Avoir::create([
            'facture_id' => $f->id, 'motif' => 'Erreur', 'montant' => '1000.00', 'date_emission' => now()->toDateString(),
            'utilisateur_validation_id' => auth()->id(),
        ]);
        $this->assertMatchesRegularExpression('/^AV-\d{4}-\d{5}$/', (string) $avoir->numero);

        $this->assertSame(['valeur' => (string) $avoir->numero, 'interne' => true], NumeroRegistre::pour($avoir));

        $avoir->numero_mecef = 'ED04000999-43';
        $this->assertSame(['valeur' => 'ED04000999-43', 'interne' => false], NumeroRegistre::pour($avoir));
    }
}
