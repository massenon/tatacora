<?php

declare(strict_types=1);

/*
| Rejoue un scenario d'ACOMPTES et d'ANNULATIONS de reservation par les VRAIS
| composants et services du serveur (12/10/2026, lot 6 de la reprise locale) :
| `ReservationService::creer` (l'acompte produit sa piece : debit tresorerie du
| mode, credit 4191) et le composant Livewire `Hebergement\Reservations`
| (`confirmerAnnulation`, `annulerReservation`) qui appelle
| `AnnulationReservationService` (commission sur le MONTANT GLOBAL, remboursement
| borne par l'acompte, piece debit 4191 / credit 5711). Le test Flutter compare,
| champ a champ, ce que `ReservationDao` fait du MEME scenario.
|
| Rien n'est modifie dans `tatacora-api`. Il travaille sur `tatacora_test` (il
| REFUSE toute autre base), seme le referentiel comptable par le VRAI seeder et
| les roles par le VRAI `RolePermissionSeeder`, puis ANNULE tout. Jamais deux
| processus PHP en parallele sur cette base.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15", "parc": {...}, "ops": [ ... ] }
|   {"op":"parametre","cle":"...","valeur":"..."|null}
|   {"op":"reserver","ref":"r1","client":"c1","unite":"u1","arrivee":"2031-07-10",
|    "depart":"2031-07-12","acompte":"5000","mode":"mobile_money"|null,
|    "remise_type":"aucune","remise_valeur":"0"}
|   {"op":"annuler","ref":"r1","directe":false,"taux":"50","mode":"pourcentage",
|    "valeur":"60"}                  (taux null : on s'arrete a l'ouverture)
|   {"op":"effacer_tarif","ref":"r1"}       (le montant total devient inconnu)
|   {"op":"horloge","date":"2035-01-02"}
|   {"op":"compter"}  {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un resultat par operation ... ] }
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'], $scenario['parc'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . BASE_AUTORISEE);
$_ENV['DB_DATABASE'] = BASE_AUTORISEE;
$_SERVER['DB_DATABASE'] = BASE_AUTORISEE;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Pwa\Livewire\Hebergement\Reservations;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');

$resultats = [];

/** @var array<string, string> $reservations ref => identifiant serveur */
$reservations = [];
/** @var array<string, string> $clients ref => identifiant */
$clients = [];
/** @var array<string, string> $unites ref => identifiant */
$unites = [];

/**
 * Les lignes d'une piece, triees de facon canonique. Le libelle est rendu avec
 * l'identifiant de la reservation remplace par sa REFERENCE de scenario : le
 * poste genere ses propres UUID.
 *
 * @return list<array<string, string>>
 */
$decrirePiece = static function (iterable $lignes, array $identifiants): array {
    $piece = [];

    foreach ($lignes as $e) {
        $e->loadMissing(['journal', 'compte', 'centre']);
        $libelle = (string) $e->libelle;
        foreach ($identifiants as $ref => $id) {
            $libelle = str_replace($id, '<' . $ref . '>', $libelle);
        }
        $piece[] = [
            'numero_piece' => (string) $e->numero_piece,
            'journal' => $e->journal->code,
            'date' => $e->date_ecriture->format('Y-m-d'),
            'compte' => $e->compte->numero_compte,
            'centre' => $e->centre->libelle,
            'libelle' => $libelle,
            'debit' => (string) $e->debit,
            'credit' => (string) $e->credit,
            'statut' => $e->statut,
        ];
    }

    usort($piece, static fn (array $a, array $b): int => strcmp(
        implode('|', [$a['compte'], $a['debit'], $a['credit']]),
        implode('|', [$b['compte'], $b['debit'], $b['credit']]),
    ));

    return $piece;
};

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    // Gerant : M1 = C et ANNULATIONS = C (le composant exige les DEUX).
    $gerant = User::create([
        'login' => 'gerant.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($gerant);

    foreach ($scenario['parc']['categories'] as $c) {
        CategorieHebergement::create([
            'id' => $c['id'],
            'libelle' => $c['libelle'],
            'capacite_max' => 2,
            'tarif_base' => $c['tarif'],
        ]);
    }
    foreach ($scenario['parc']['unites'] as $u) {
        UniteHebergement::create([
            'id' => $u['id'],
            'categorie_id' => $u['categorie'],
            'numero' => $u['numero'],
            'statut' => 'libre',
        ]);
        $unites[$u['ref']] = $u['id'];
    }
    foreach ($scenario['parc']['clients'] as $c) {
        Client::create([
            'id' => $c['id'],
            'nom' => $c['nom'],
            'prenom' => $c['prenom'],
            'telephone' => '97000000',
            'type_client' => 'particulier',
        ]);
        $clients[$c['ref']] = $c['id'];
    }

    $departReservations = Reservation::count();
    $departEcritures = EcritureComptable::count();
    $service = $app->make(ReservationService::class);
    $annulations = $app->make(AnnulationReservationService::class);

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'parametre':
                    DB::table('parametres_systeme')->where('cle', $op['cle'])->delete();
                    if ($op['valeur'] !== null) {
                        DB::table('parametres_systeme')->insert([
                            'id' => (string) Str::uuid(),
                            'cle' => $op['cle'],
                            'valeur' => $op['valeur'],
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'horloge':
                    Carbon::setTestNow($op['date'] . ' 10:00:00');
                    $resultats[] = ['ok' => true];
                    break;

                case 'reserver':
                    $id = (string) Str::uuid();
                    $reservations[$op['ref']] = $id;

                    $categorie = UniteHebergement::findOrFail($unites[$op['unite']])->categorie;

                    $r = $service->creer([
                        'id' => $id,
                        'client_id' => $clients[$op['client']],
                        'unite_id' => $unites[$op['unite']],
                        'date_arrivee' => $op['arrivee'],
                        'date_depart' => $op['depart'],
                        'tarif_nuit' => (string) $categorie->tarif_base,
                        'acompte' => $op['acompte'],
                        'mode_paiement' => $op['mode'],
                        'remise_type' => $op['remise_type'],
                        'remise_valeur' => $op['remise_valeur'],
                    ]);

                    $resultats[] = [
                        'ok' => true,
                        'acompte' => (string) $r->acompte,
                        'mode' => $r->mode_paiement,
                        'piece' => $decrirePiece(
                            EcritureComptable::where('libelle', 'Acompte réservation — ' . $id)->get(),
                            $reservations,
                        ),
                    ];
                    break;

                case 'annuler':
                    $id = $reservations[$op['ref']];
                    $c = Livewire::actingAs($gerant)->test(Reservations::class);
                    $erreursDe = static fn ($composant): array => array_map(
                        static fn (array $m): array => array_values($m),
                        $composant->errors()->toArray(),
                    );

                    $sortie = [];

                    if (! ($op['directe'] ?? false)) {
                        $c->call('confirmerAnnulation', $id);

                        if (isset($erreursDe($c)['annulation'])) {
                            $resultats[] = ['banniere' => $erreursDe($c)['annulation'][0]];
                            break;
                        }

                        $sortie['ouverture'] = [
                            'taux' => (string) $c->get('aTaux'),
                            'mode' => (string) $c->get('aModeRemboursement'),
                            'valeur' => (string) $c->get('aRembourseValeur'),
                            'delai' => number_format((float) $c->get('aDelaiHeures'), 1),
                            'sous_seuil' => (bool) $c->get('aSousLeSeuil'),
                        ];
                    }

                    if ($op['taux'] === null) {
                        $resultats[] = $sortie + ['ok' => true];
                        break;
                    }

                    $c->set('aTaux', $op['taux'])
                        ->set('aModeRemboursement', $op['mode'])
                        ->set('aRembourseValeur', $op['valeur'])
                        ->call('annulerReservation', $id);

                    $erreurs = $erreursDe($c);

                    if ($erreurs !== []) {
                        $resultats[] = $sortie + ['erreurs' => $erreurs];
                        break;
                    }

                    $r = Reservation::findOrFail($id);
                    $piece = [];
                    if ($r->ecriture_remboursement_id !== null) {
                        $numero = EcritureComptable::findOrFail($r->ecriture_remboursement_id)->numero_piece;
                        $piece = $decrirePiece(
                            EcritureComptable::where('numero_piece', $numero)->get(),
                            $reservations,
                        );
                    }

                    $resultats[] = $sortie + [
                        'ok' => true,
                        'statut' => $r->statut,
                        'taux' => (string) $r->taux_annulation,
                        'total' => (string) $r->montant_total_annulation,
                        'commission' => (string) $r->montant_commission_annulation,
                        'rembourse' => (string) $r->montant_rembourse_annulation,
                        'mode_saisie' => $r->mode_saisie_remboursement,
                        'date_renseignee' => $r->date_annulation !== null,
                        'date' => $r->date_annulation?->format('Y-m-d'),
                        'auteur_renseigne' => $r->utilisateur_annulation_id !== null,
                        'ecriture_renseignee' => $r->ecriture_remboursement_id !== null,
                        'piece' => $piece,
                    ];
                    break;

                case 'effacer_tarif':
                    // Une reservation d'AVANT le tarif ffige : `tarif_nuit` est
                    // nullable au serveur, et le montant total devient INCONNU.
                    DB::table('reservations')
                        ->where('id', $reservations[$op['ref']])
                        ->update(['tarif_nuit' => null]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'compter':
                    $resultats[] = ['ok' => true, 'compte' => [
                        'reservations' => Reservation::count() - $departReservations,
                        'ecritures' => EcritureComptable::count() - $departEcritures,
                    ]];
                    break;

                case 'libelles':
                    $resultats[] = ['ok' => true, 'libelles' => [
                        'annulation_impossible' => __('hebergement_pwa.reservations.annulation_impossible'),
                        'montant_total_inconnu' => __('hebergement.annulation_montant_total_inconnu'),
                        'taux_invalide' => __('hebergement.annulation_taux_invalide'),
                        'remboursement_negatif' => __('hebergement.annulation_remboursement_negatif'),
                        'mode_inconnu' => __('hebergement.annulation_mode_remboursement_inconnu', ['mode' => ':mode']),
                        'superieur_acompte' => __('hebergement.annulation_remboursement_superieur_acompte'),
                        'libelle_ecriture' => __('hebergement.annulation_libelle_ecriture', ['client' => ':client']),
                        'delai' => __('hebergement_pwa.reservations.annulation_delai', ['heures' => ':heures']),
                        'delai_passe' => __('hebergement_pwa.reservations.annulation_delai_passe'),
                        'sous_seuil' => __('hebergement_pwa.reservations.annulation_sous_seuil'),
                        'titre' => __('hebergement_pwa.reservations.annulation_titre'),
                        'element' => __('hebergement_pwa.reservations.annulation_element', ['client' => ':client', 'arrivee' => ':arrivee', 'depart' => ':depart']),
                        'montant_total' => __('hebergement_pwa.reservations.annulation_montant_total'),
                        'acompte_verse' => __('hebergement_pwa.reservations.annulation_acompte_verse'),
                        'champ_taux' => __('hebergement_pwa.reservations.annulation_champ_taux'),
                        'taux_aide' => __('hebergement_pwa.reservations.annulation_taux_aide'),
                        'champ_remboursement' => __('hebergement_pwa.reservations.annulation_champ_remboursement'),
                        'mode_pourcentage' => __('hebergement_pwa.reservations.annulation_mode_pourcentage'),
                        'mode_montant' => __('hebergement_pwa.reservations.annulation_mode_montant'),
                        'remboursement_aide' => __('hebergement_pwa.reservations.annulation_remboursement_aide'),
                        'aucun_acompte' => __('hebergement_pwa.reservations.annulation_aucun_acompte'),
                        'rappel' => __('hebergement_pwa.reservations.annulation_rappel'),
                        'confirmer' => __('hebergement_pwa.reservations.annulation_confirmer'),
                        'renoncer' => __('pwa.modale.annuler'),
                        'validation_required' => __('validation.required', ['attribute' => ':attribute']),
                        'validation_numeric' => __('validation.numeric', ['attribute' => ':attribute']),
                        'validation_in' => __('validation.in', ['attribute' => ':attribute']),
                        'validation_min' => __('validation.min.numeric', ['attribute' => ':attribute', 'min' => ':min']),
                        'validation_max' => __('validation.max.numeric', ['attribute' => ':attribute', 'max' => ':max']),
                        'seuil_heures' => AnnulationReservationService::SEUIL_HEURES,
                        'taux_reference' => AnnulationReservationService::TAUX_REFERENCE_PAR_DEFAUT,
                        'cle_taux' => AnnulationReservationService::CLE_TAUX_MOINS_24H,
                        'compte_avances' => AnnulationReservationService::COMPTE_AVANCES_CLIENTS,
                        'tresorerie_acompte' => ReservationService::TRESORERIE_ACOMPTE_PAR_MODE,
                        'tresoreries' => \App\Domain\Depenses\Services\DepenseService::TRESORERIES,
                    ]];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = ['refus' => $e->getMessage()];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
