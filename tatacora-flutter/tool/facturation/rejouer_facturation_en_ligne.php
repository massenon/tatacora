<?php

declare(strict_types=1);

/*
| Outillage de l'essai de bout en bout de la FACTURATION EN LIGNE du poste (décisions du PO
| du 07/11/2026) contre le VRAI serveur : `php artisan serve` sur une base d'essai PRIVÉE
| `tatacora_<nom>_test` (convention `TATACORA_BASE_ESSAI`), créée puis supprimée par le test
| `facturation_en_ligne_contre_serveur_test.dart`.
|
|   preparer : sème les rôles, le référentiel comptable, les réglages MECeF (mode choisi par le
|              test), un compte `administrateur`, un client et DEUX factures : l'une NORMALISÉE (par un
|              boîtier : NIM-TC, QR, code), l'autre SIMPLE (émise, sans normalisation) ;
|   relire    : rend les lignes de factures et d'avoirs, pour comparer ce que le serveur a RÉELLEMENT
|              écrit à ce que le poste croit.
|
| Il REFUSE toute base qui n'est pas une base d'essai privée (`tatacora_<nom>_test`) autre que
| `tatacora_test`. Entrée (stdin, JSON) : { "action": "...", ... }.
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
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

function factureDe(string $clientId, string $date, bool $normalisee): Facture
{
    $facture = Facture::create([
        'client_id' => $clientId,
        'date_emission' => $date,
        'montant_ht' => '30000.00', 'montant_tva' => '0.00', 'montant_ttc' => '30000.00',
        'statut' => 'certifiee',
        'origine' => 'facture_directe',
        ...($normalisee ? [
            'numero_mecef' => 'ED04000623-41',
            'qr_code_fiscal' => 'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;0202011344660;20261107100000',
            'code_mecef' => 'NW34NID6ZHANFNMZ2IU7LL3H',
            'normalisation_statut' => 'normalisee',
            'normalisation_mode' => 'boitier',
            'normalisation_compteur' => '41',
            'normalisee_le' => now(),
        ] : []),
    ]);

    LigneFacture::create([
        'facture_id' => $facture->id, 'source_module' => 'M5', 'source_id' => $facture->id,
        'libelle' => 'Béninoise 33cl', 'quantite' => 3, 'prix_unitaire' => '10000.00',
        'prix_catalogue' => '10000.00', 'montant' => '30000.00',
    ]);

    return $facture->refresh();
}

switch ((string) $entree['action']) {
    case 'preparer':
        (new RolePermissionSeeder())->run();
        (new ComptabiliteReferentielSeeder())->run();

        foreach ([
            'entreprise_ifu' => '0202011344660',
            'mecef_operateur_id' => 'RECEPTION01',
            'mecef_operateur_nom' => 'Réception',
            'facturation_mode' => (string) ($entree['mode'] ?? 'boitier'),
            'tva_active' => 'false',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }

        $gerant = User::create([
            'login' => (string) $entree['login'],
            'mot_de_passe_hash' => Hash::make((string) $entree['mot_de_passe']),
            // Un administrateur : il peut annuler une facture que ce poste n'a pas saisie (Q3, lot F6).
            'role_id' => Role::where('libelle', (string) ($entree['role'] ?? 'administrateur'))->firstOrFail()->id,
            'statut' => 'actif',
        ]);

        $client = Client::create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '96000003', 'type_client' => 'particulier']);
        $normalisee = factureDe((string) $client->id, '2026-11-07', true);
        $simple = factureDe((string) $client->id, '2026-11-07', false);

        echo json_encode([
            'base' => $base,
            'client_id' => (string) $client->id,
            'facture_normalisee' => (string) $normalisee->id,
            'facture_simple' => (string) $simple->id,
            'utilisateur_id' => (string) $gerant->id,
        ], JSON_UNESCAPED_UNICODE);

        break;

    case 'relire':
        $factures = [];

        foreach ($entree['factures'] as $id) {
            $f = Facture::query()->find((string) $id);
            $factures[$id] = $f === null ? null : [
                'statut' => $f->statut,
                'numero' => $f->numero,
                'numero_mecef' => $f->numero_mecef,
                'normalisation_statut' => $f->normalisation_statut,
                'normalisation_motif' => $f->normalisation_motif,
                'avoirs' => Avoir::query()->where('facture_id', $id)->orderBy('created_at')->get()->map(
                    static fn (Avoir $a): array => [
                        'id' => (string) $a->id,
                        'numero' => $a->numero,
                        'montant' => (string) $a->montant,
                        'normalisation_statut' => $a->normalisation_statut,
                        'normalisation_mode' => $a->normalisation_mode,
                    ],
                )->all(),
            ];
        }

        echo json_encode(['factures' => $factures, 'avoirs' => Avoir::count()], JSON_UNESCAPED_UNICODE);

        break;

    default:
        fwrite(STDERR, "Action inconnue.\n");
        exit(4);
}
