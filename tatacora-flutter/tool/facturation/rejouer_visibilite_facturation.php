<?php

declare(strict_types=1);

/*
| Outillage de l'essai « VISIBILITÉ des factures et des proformas » (bug du PO du 09/11/2026 : « j'ai activé
| MECeF, enregistré une réservation, et je ne vois ni proforma ni facture ») contre le VRAI serveur :
| `php artisan serve` sur une base d'essai PRIVÉE `tatacora_<nom>_test` (convention `TATACORA_BASE_ESSAI`),
| créée puis supprimée par le test `visibilite_facturation_contre_serveur_test.dart`.
|
|   preparer     : sème les rôles, le référentiel comptable (exercice de l'année), les réglages MECeF (mode choisi
|                  par le test), un compte `administrateur`, un client ;
|   creer_au_web : crée, par les services du domaine, ce que le WEB crée (une proforma émise, un brouillon, une
|                  facture simple) : ils doivent DESCENDRE aux postes ;
|   ecrans       : rend les DEUX écrans web (registre des factures, page Proformas) sous le compte administrateur,
|                  par les vrais composants Livewire, et rend ce qu'ils AFFICHENT (identifiants, libellé de
|                  statut de chaque facture, état vide).
|
| Il REFUSE toute base qui n'est pas une base d'essai privée. Entrée (stdin, JSON) : { "action": "...", ... }.
*/

$baseEssai = (static function (): string {
    $voulue = getenv('TATACORA_BASE_ESSAI');

    return is_string($voulue) && preg_match('/^tatacora_[a-z0-9_]+_test$/', $voulue) === 1 ? $voulue : '';
})();

if ($baseEssai === '') {
    fwrite(STDERR, "Refus : TATACORA_BASE_ESSAI=tatacora_<nom>_test est obligatoire.\n");
    exit(1);
}

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['action'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ProformaService;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Facturation\Proformas;
use App\Pwa\Support\EtiquetteFacture;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

switch ((string) $entree['action']) {
    case 'preparer':
        (new RolePermissionSeeder())->run();
        (new ComptabiliteReferentielSeeder())->run();

        foreach ([
            'entreprise_ifu' => '0202011344660',
            'mecef_operateur_id' => 'RECEPTION01',
            'mecef_operateur_nom' => 'Réception',
            'facturation_mode' => (string) ($entree['mode'] ?? 'emecef'),
            'tva_active' => 'false',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }

        $admin = User::create([
            'login' => (string) $entree['login'],
            'mot_de_passe_hash' => Hash::make((string) $entree['mot_de_passe']),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $client = Client::create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '96000003', 'type_client' => 'particulier']);

        echo json_encode(['base' => $base, 'client_id' => (string) $client->id, 'utilisateur_id' => (string) $admin->id], JSON_UNESCAPED_UNICODE);

        break;

    case 'creer_au_web':
        $proformas = app(ProformaService::class);
        $brouillon = $proformas->creer(['client_nom' => 'WEB BROUILLON', 'lignes' => [['designation' => 'Salle', 'quantite' => 1, 'prix_unitaire' => 40000]]]);
        $emise = $proformas->emettre($proformas->creer(['client_nom' => 'WEB EMISE', 'source_module' => 'hebergement', 'lignes' => [['designation' => 'Chambre', 'quantite' => 2, 'prix_unitaire' => 25000]]]));

        $emission = app(EmissionFactureService::class);
        $facture = $emission->emettreVide((string) $entree['client_id']);
        $emission->ajouterLigne($facture, 'M1', (string) $facture->id, 'Nuitée web', '2', '25000.00');
        $emission->figerEmission($facture);

        echo json_encode([
            'proforma_brouillon' => (string) $brouillon->id,
            'proforma_emise' => (string) $emise->id,
            'numero_proforma_emise' => $emise->numero,
            'facture' => (string) $facture->id,
        ], JSON_UNESCAPED_UNICODE);

        break;

    case 'ecrans':
        $admin = User::query()->where('login', (string) $entree['login'])->firstOrFail();
        Auth::login($admin);

        $registre = Livewire::actingAs($admin)->test(Facturation::class);
        $vue = $registre->instance()->render();
        $factures = $vue->getData()['factures'];
        $mode = ModeFacturation::courant();

        $lignes = [];
        foreach (Facture::query()->get() as $f) {
            $lignes[(string) $f->id] = [
                'affichee' => str_contains($registre->html(), 'wire:key="facture-' . $f->id . '"'),
                'libelle' => EtiquetteFacture::pour($f, $mode)['libelle'],
                'numero' => $f->numero,
                'normalisation_statut' => $f->normalisation_statut,
            ];
        }

        $page = Livewire::actingAs($admin)->test(Proformas::class);
        $listees = [];
        foreach (Proforma::query()->get() as $p) {
            $listees[(string) $p->id] = [
                'affichee' => str_contains($page->html(), $p->numero ?? 'Brouillon') && str_contains($page->html(), $p->client_nom),
                'numero' => $p->numero,
                'statut' => $p->statut,
            ];
        }

        echo json_encode([
            'mode' => $mode->value,
            'total_registre' => $factures->total(),
            'registre_vide' => str_contains($registre->html(), 'Une réservation ne crée pas de facture'),
            'factures' => $lignes,
            'proformas' => $listees,
            'proformas_vide' => str_contains($page->html(), 'Aucune proforma.'),
        ], JSON_UNESCAPED_UNICODE);

        break;

    default:
        fwrite(STDERR, "Action inconnue.\n");
        exit(4);
}
