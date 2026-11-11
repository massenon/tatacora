<?php

declare(strict_types=1);

/*
| TEST DE CARACTERISATION du REGLEMENT FOURNISSEUR du serveur (12/10/2026,
| lot 7 de la reprise locale, D66). Ce script rejoue, par les VRAIS services et
| le VRAI composant du serveur, un scenario que le test Flutter joue ensuite
| sur le poste, pour comparer CHAMP A CHAMP :
|
|   - `ReglementFournisseurService::regler` / `annuler` / `totalRegle` /
|     `resteDu` (refus dans l'ordre, phrases, reglement ecrit, piece
|     comptable Dr 4011 / Cr tresorerie, `montant_regle` recalcule) ;
|   - `Approvisionnement` (composant Livewire) : `ouvrirFormulaireReglement`
|     (droit M7, commande introuvable, commande soldee, valeurs de depart),
|     `enregistrerReglement` (validation des trois proprietes, refus du
|     service sous le champ montant, message de succes), et `render()` :
|     `reglesEtRestes`, `totalDu`, `fournisseursAPayer`, groupes de dettes ;
|   - `CommandeAchatService::creer` (montant_total ecrit a la creation).
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le
| touche pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base),
| seme les roles et le referentiel comptable par les VRAIS seeders, puis
| ANNULE tout (rollback). Si MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) : { "aujourdhui": "2026-10-13", "ops": [ ... ] }
|   {"op":"utilisateur","ref":"g","role":"gerant"}
|   {"op":"fournisseur","ref":"f1","nom":"Grand Marche SARL"}
|   {"op":"article","ref":"a1","libelle":"Sucre"}
|   {"op":"commande","ref":"c1","fournisseur":"f1","user":"g",
|    "date":"2026-10-01","statut":"envoyee",
|    "lignes":[{"article":"a1","quantite":"4","prix":"1000"}]}
|   {"op":"statut","commande":"c1","statut":"receptionnee"}
|   {"op":"regler_service","commande":"c1","user":"g","montant":"1500",
|    "tresorerie":"caisse"}
|   {"op":"regler_pwa","commande":"c1","user":"g","montant":"1500",
|    "tresorerie":"caisse","ouvrir":true}
|   {"op":"ouvrir_pwa","commande":"c1","user":"g"}
|   {"op":"annuler","reglement":0,"motif":"Doublon","user":"g"}
|   {"op":"vue","user":"g","statut":"","recherche":""}
|   {"op":"droits","role":"gerant"}
|   {"op":"parametre","cle":"compte_caisse","valeur":"5712"|null}
|   {"op":"etat"}  {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par operation ... ] }
|
| Usage : php tool/achats/rejouer_reglements.php < scenario.json
| Ne JAMAIS en lancer deux en parallele : ils partagent `tatacora_test`.
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'])) {
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

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Etats\EtatAchatsFournisseurs;
use App\Domain\Achats\Models\ReglementFournisseur;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Achats\Services\ReglementFournisseurService;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Shared\Rbac\Models\JournalSecurite;
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

/** @var array<string, User> $utilisateurs */
$utilisateurs = [];
/** @var array<string, Fournisseur> $fournisseurs */
$fournisseurs = [];
/** @var array<string, Article> $articles */
$articles = [];
/** @var array<string, CommandeAchat> $commandes */
$commandes = [];
/** @var list<ReglementFournisseur> $reglements dans l'ordre de creation */
$reglements = [];
/** @var array<string, true> $reglementsConnus */
$reglementsConnus = [];
$resultats = [];

$refDe = static function (array $table, string $id): ?string {
    foreach ($table as $ref => $objet) {
        $cle = is_object($objet) ? (string) $objet->id : (string) $objet;
        if ($cle === $id) {
            return (string) $ref;
        }
    }

    return null;
};

$m2 = static fn (mixed $v): string => bcadd((string) $v, '0', 2);

/** @return array<string, list<string>> */
$erreursDe = static function ($composant): array {
    $erreurs = [];
    foreach ($composant->errors()->toArray() as $champ => $messages) {
        $erreurs[$champ] = array_values($messages);
    }

    return $erreurs;
};

/** Le message de succes (bandeau `pwa-succes`) du composant. */
$succesDe = static function ($composant): ?string {
    $html = (string) $composant->html();

    if (preg_match('/background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">\s*(.*?)\s*<\/div>/s', $html, $m) !== 1) {
        return null;
    }

    return html_entity_decode(trim($m[1]), ENT_QUOTES, 'UTF-8');
};

/**
 * Le sous-titre de la modale « Regler », tel que la vue le rend : la commande
 * (ramenee a sa reference de scenario) et le « reste du » AFFICHE, qui est en
 * realite la valeur courante du champ montant (voir la vue, l.576-579).
 *
 * @return array{commande: string|null, reste: string}|null
 */
$sousTitreModale = static function ($composant) use (&$commandes, $refDe): ?array {
    $html = (string) $composant->html();

    if (preg_match('/Commande\s+(\S+)\s+—\s+reste dû\s+([^<]*?)\s*</u', $html, $m) !== 1) {
        return null;
    }

    return [
        'commande' => $refDe($commandes, $m[1]),
        'reste' => html_entity_decode(trim($m[2]), ENT_QUOTES, 'UTF-8'),
    ];
};

$statutHttp = static function ($composant): int {
    foreach ([401, 403] as $code) {
        try {
            $composant->assertStatus($code);

            return $code;
        } catch (Throwable) {
            // pas ce statut
        }
    }

    return 200;
};

$moduleRefuse = static function (User $u): ?string {
    return JournalSecurite::query()
        ->where('utilisateur_id', $u->id)
        ->where('type_evenement', 'acces_refuse_rbac')
        ->orderByDesc('id')
        ->first()?->module_concerne;
};

/** @return array<string, mixed>|null */
$refusRbac = static function (Throwable $e, User $u) use ($moduleRefuse): ?array {
    if (! str_contains($e->getMessage(), 'Invalid Livewire snapshot')) {
        return null;
    }

    $module = $moduleRefuse($u);

    return $module === null ? null : ['statut' => 403, 'module_refuse' => $module];
};

/** @return array<string, mixed> */
$decrireReglement = static function (ReglementFournisseur $r) use (&$commandes, &$utilisateurs, $refDe, $m2): array {
    $r->refresh();

    return [
        'commande' => $refDe($commandes, (string) $r->commande_id),
        'montant' => $m2($r->montant),
        'tresorerie' => $r->tresorerie,
        'date_reglement' => $r->date_reglement->format('Y-m-d'),
        'statut' => $r->statut,
        'motif_annulation' => $r->motif_annulation,
        'annule_par' => $r->annule_par_id === null ? null : $refDe($utilisateurs, (string) $r->annule_par_id),
        'date_annulation_renseignee' => $r->date_annulation !== null,
        'par' => $r->utilisateur_creation_id === null ? null : $refDe($utilisateurs, (string) $r->utilisateur_creation_id),
    ];
};

/** @return list<array<string, mixed>> */
$decrireEcritures = static function (): array {
    $lignes = [];

    foreach (EcritureComptable::with(['journal', 'compte', 'centre'])->orderBy('created_at')->orderBy('id')->get() as $e) {
        $lignes[] = [
            'journal' => $e->journal->code,
            'compte' => $e->compte->numero_compte,
            'centre' => $e->centre->libelle,
            'libelle' => $e->libelle,
            'debit' => bcadd((string) $e->debit, '0', 2),
            'credit' => bcadd((string) $e->credit, '0', 2),
            'statut' => $e->statut,
            'numero_piece_renseigne' => $e->numero_piece !== null,
            'numero_piece' => $e->numero_piece,
            'date' => $e->date_ecriture->format('Y-m-d'),
            'contrepasse' => $e->ecriture_contrepassee_id !== null,
        ];
    }

    return $lignes;
};

/**
 * Le nouveau reglement ecrit depuis le dernier releve (jamais un tri par date :
 * deux ecritures de la meme seconde n'ont pas d'ordre).
 */
$nouveauReglement = static function () use (&$reglementsConnus, &$reglements): ?ReglementFournisseur {
    $nouveau = ReglementFournisseur::query()->whereNotIn('id', array_keys($reglementsConnus))->first();

    if ($nouveau !== null) {
        $reglements[] = $nouveau;
        $reglementsConnus[(string) $nouveau->id] = true;
    }

    return $nouveau;
};

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    foreach (ReglementFournisseur::pluck('id') as $id) {
        $reglementsConnus[(string) $id] = true;
    }

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'utilisateur':
                    $utilisateurs[$op['ref']] = User::create([
                        'login' => $op['ref'] . '.' . Str::random(6),
                        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                        'role_id' => Role::where('libelle', $op['role'])->firstOrFail()->id,
                        'statut' => 'actif',
                    ]);
                    $resultats[] = ['ok' => true, 'niveau_m7' => $utilisateurs[$op['ref']]->niveauSurModule('M7')];
                    break;

                case 'fournisseur':
                    $fournisseurs[$op['ref']] = Fournisseur::create(['raison_sociale' => $op['nom']]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'article':
                    $articles[$op['ref']] = Article::create([
                        'libelle' => $op['libelle'],
                        'categorie' => 'Denrées',
                        'unite_mesure' => 'kg',
                        'seuil_alerte' => '4.00',
                        'seuil_reappro' => '10.00',
                        'cout_moyen_pondere' => '0.0000',
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'commande':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $lignes = [];
                    foreach ($op['lignes'] as $l) {
                        $lignes[] = [
                            'article_id' => $articles[$l['article']]->id,
                            'quantite_commandee' => $l['quantite'],
                            'prix_unitaire' => $l['prix'],
                        ];
                    }
                    $c = $app->make(CommandeAchatService::class)->creer([
                        'fournisseur_id' => $fournisseurs[$op['fournisseur']]->id,
                        'date_commande' => $op['date'],
                        'statut' => $op['statut'] ?? 'brouillon',
                        'lignes' => $lignes,
                    ]);
                    $commandes[$op['ref']] = $c;
                    $resultats[] = ['ok' => true, 'montant_total' => $m2($c->montant_total)];
                    break;

                case 'parametre':
                    // La correspondance des comptes (26/10/2026) : une cle
                    // `compte_<role>` posee DIRECTEMENT en base (la validation de
                    // l'ecran n'est pas ce qu'on mesure : c'est la LECTURE au
                    // moment de regler). `null` retire la ligne : le defaut.
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

                case 'statut':
                    // Un statut produit par une reception reelle ailleurs : ici on
                    // le POSE, pour eprouver les gardes de la liste des dettes.
                    DB::table('commandes_achat')->where('id', $commandes[$op['commande']]->id)
                        ->update(['statut' => $op['statut']]);
                    $commandes[$op['commande']]->refresh();
                    $resultats[] = ['ok' => true];
                    break;

                case 'regler_service':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $commande = $commandes[$op['commande']]->refresh();
                    $r = $app->make(ReglementFournisseurService::class)
                        ->regler($commande, $op['montant'], $op['tresorerie']);
                    $nouveau = $nouveauReglement();
                    $resultats[] = [
                        'reglement' => $decrireReglement($r),
                        'montant_regle' => $m2($commande->refresh()->montant_regle),
                    ];
                    break;

                case 'regler_pwa':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(Approvisionnement::class);
                        if ($op['ouvrir'] ?? true) {
                            $c->call('ouvrirFormulaireReglement', $commandes[$op['commande']]->id);
                        } else {
                            // Un etat FORGE : une propriete publique Livewire se
                            // fixe depuis le navigateur sans passer par l'ouverture.
                            $c->set('regCommandeId', $commandes[$op['commande']]->id);
                        }
                        $c->set('regMontant', $op['montant'])
                            ->set('regTresorerie', $op['tresorerie'])
                            ->call('enregistrerReglement');
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    if ($statutHttp($c) === 403) {
                        $resultats[] = ['statut' => 403, 'module_refuse' => $moduleRefuse($u)];
                        break;
                    }
                    $nouveau = $nouveauReglement();
                    $resultats[] = [
                        'erreurs' => $erreursDe($c),
                        'succes' => $succesDe($c),
                        'reglement' => $nouveau === null ? null : $decrireReglement($nouveau),
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                        'sous_titre' => $sousTitreModale($c),
                        'reg_montant' => $c->get('regMontant'),
                    ];
                    break;

                case 'ouvrir_pwa':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(Approvisionnement::class)
                            ->call('ouvrirFormulaireReglement', $op['commande_inconnue'] ?? $commandes[$op['commande']]->id);
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    if ($statutHttp($c) === 403) {
                        $resultats[] = ['statut' => 403, 'module_refuse' => $moduleRefuse($u)];
                        break;
                    }
                    $resultats[] = [
                        'erreurs' => $erreursDe($c),
                        'modale_ouverte' => $c->get('etatFormulaire') === 'reglement',
                        'reg_montant' => $c->get('regMontant'),
                        'reg_tresorerie' => $c->get('regTresorerie'),
                        'fournisseur_nom' => $c->get('regFournisseurNom'),
                        'sous_titre' => $sousTitreModale($c),
                    ];
                    break;

                case 'annuler':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $r = $reglements[$op['reglement']];
                    $apres = $app->make(ReglementFournisseurService::class)->annuler($r, $op['motif']);
                    $resultats[] = [
                        'reglement' => $decrireReglement($apres),
                        'montant_regle' => $m2($apres->commande->refresh()->montant_regle),
                    ];
                    break;

                case 'vue':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(Approvisionnement::class)
                        ->set('statut', $op['statut'] ?? '')
                        ->set('recherche', $op['recherche'] ?? '');
                    $html = (string) $c->html();
                    $texte = static function (string $fragment): string {
                        $sansBalises = trim((string) preg_replace('/\s+/u', ' ', strip_tags($fragment)));

                        return str_replace("\u{00A0}", ' ', html_entity_decode($sansBalises, ENT_QUOTES, 'UTF-8'));
                    };
                    $cellules = static function (string $ligne) use ($texte): array {
                        preg_match_all('/<td\b[^>]*>(.*?)<\/td>/s', $ligne, $m);

                        return array_map($texte, $m[1]);
                    };
                    // Ligne par ligne du tableau « Commandes » : ce que la vue
                    // RENDUE dit, cellule par cellule, jamais ce que le script en
                    // pense.
                    $rendu_commandes = [];
                    if (preg_match_all('/<tr wire:key="cmd-([^"]+)"[^>]*>(.*?)<\/tr>/s', $html, $lignes, PREG_SET_ORDER)) {
                        foreach ($lignes as $l) {
                            $cells = $cellules($l[2]);
                            $cells[0] = (string) $refDe($commandes, $l[1]);
                            $rendu_commandes[] = $cells;
                        }
                    }
                    // Les boutons de chaque ligne (libelles seulement).
                    $rendu_dettes = [];
                    if (preg_match_all('/<tbody class="border-t border-slate-100" wire:key="dette-\d+">(.*?)<\/tbody>/s', $html, $groupes)) {
                        foreach ($groupes[1] as $bloc) {
                            preg_match('/<tr class="bg-slate-50">(.*?)<\/tr>/s', $bloc, $entete);
                            $entete = $cellules($entete[1] ?? '');
                            preg_match_all('/<tr class="border-t border-slate-50" wire:key="dette-cmd-([^"]+)">(.*?)<\/tr>/s', $bloc, $cmds, PREG_SET_ORDER);
                            $rendu_dettes[] = [
                                'fournisseur' => $entete[0] ?? null,
                                'total' => $entete[1] ?? null,
                                'lignes' => array_map(function ($l) use ($cellules, $refDe, $commandes) {
                                    $cells = $cellules($l[2]);
                                    $cells[0] = (string) $refDe($commandes, $l[1]);

                                    return $cells;
                                }, $cmds),
                            ];
                        }
                    }
                    $rendu_kpis = [];
                    $debutKpis = strpos($html, 'id="kpis-appro"');
                    if ($debutKpis !== false) {
                        $zone = substr($html, $debutKpis, 4000);
                        preg_match_all('/<p class="text-\[10px\][^>]*>(.*?)<\/p>\s*<p class="text-lg[^>]*>(.*?)<\/p>/s', $zone, $paires, PREG_SET_ORDER);
                        foreach (array_slice($paires, 0, 5) as $p) {
                            $rendu_kpis[$texte($p[1])] = $texte($p[2]);
                        }
                    }
                    $totalDettes = null;
                    if (preg_match('/<span class="text-\[13px\]">\s*Total dû\s*<strong[^>]*>(.*?)<\/strong>/su', $html, $td)) {
                        $totalDettes = $texte($td[1]);
                    }
                    $restes = [];
                    foreach ((array) $c->viewData('reglesEtRestes') as $id => $ligne) {
                        $restes[(string) $refDe($commandes, (string) $id)] = [
                            'regle' => $ligne['regle'],
                            'reste' => $ligne['reste'],
                        ];
                    }
                    $dettes = [];
                    foreach ((array) $c->viewData('dettes') as $groupe) {
                        $dettes[] = [
                            'fournisseur' => $groupe['fournisseur'],
                            'commandes' => array_map(
                                static fn ($cmd) => $refDe($commandes, (string) $cmd->id),
                                $groupe['commandes'],
                            ),
                        ];
                    }
                    $resultats[] = [
                        'ordre_commandes' => $c->viewData('commandes')->map(
                            static fn ($cmd) => $refDe($commandes, (string) $cmd->id),
                        )->values()->all(),
                        'reglesEtRestes' => $restes,
                        'totalDu' => $c->viewData('totalDu'),
                        'fournisseursAPayer' => $c->viewData('fournisseursAPayer'),
                        'dettes' => $dettes,
                        'peutEcrire' => $c->viewData('peutEcrire'),
                        'rendu_commandes' => $rendu_commandes,
                        'rendu_dettes' => $rendu_dettes,
                        'rendu_kpis' => $rendu_kpis,
                        'rendu_total_dettes' => $totalDettes,
                    ];
                    break;

                case 'etat_achats':
                    // L'ETAT M14 « achats et dettes fournisseurs » du serveur, lu de
                    // `montant_regle` (recalcule des reglements actifs) : ce que le
                    // poste rend desormais au lieu d'un tiret (D264).
                    $etat = $app->make(EtatAchatsFournisseurs::class)->calculer($op['filtres'] ?? []);
                    $resultats[] = [
                        'indicateurs' => array_values($etat->kpis),
                        'entetes' => $etat->entetes,
                        'lignes' => $etat->lignes,
                    ];
                    break;

                case 'droits':
                    // Le geste « Regler » joue par chaque ROLE : quel module
                    // refuse, ou aucun.
                    $u = User::create([
                        'login' => 'droit.' . $op['role'] . '.' . Str::random(6),
                        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                        'role_id' => Role::where('libelle', $op['role'])->firstOrFail()->id,
                        'statut' => 'actif',
                    ]);
                    $commande = $commandes[$op['commande']];
                    try {
                        $c = Livewire::actingAs($u)->test(Approvisionnement::class)
                            ->call('ouvrirFormulaireReglement', $commande->id);
                        $statut = $statutHttp($c);
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = ['role' => $op['role'], 'refus' => true, 'niveau_m7' => $u->niveauSurModule('M7')];
                        break;
                    }
                    $resultats[] = [
                        'role' => $op['role'],
                        'refus' => $statut === 403,
                        'niveau_m7' => $u->niveauSurModule('M7'),
                    ];
                    break;

                case 'etat':
                    $ecritures = $decrireEcritures();
                    // L'identifiant d'un reglement est dans le LIBELLE de sa piece
                    // (PA-52) : on le ramene a son rang de creation, que le poste
                    // connait aussi.
                    foreach ($ecritures as &$ligneEcriture) {
                        foreach ($reglements as $rang => $reglementConnu) {
                            $ligneEcriture['libelle'] = str_replace(
                                (string) $reglementConnu->id,
                                'REGL:' . $rang,
                                $ligneEcriture['libelle'],
                            );
                        }
                    }
                    unset($ligneEcriture);
                    $regs = [];
                    // Dans l'ordre de CREATION du scenario, jamais un tri en base : le
                    // temps est fige (`setTestNow`), donc les identifiants ordonnes
                    // d'un meme instant n'ont entre eux aucun ordre.
                    foreach ($reglements as $r) {
                        $regs[] = $decrireReglement($r);
                    }
                    $cmds = [];
                    foreach ($commandes as $ref => $cmd) {
                        $cmd->refresh();
                        $cmds[$ref] = [
                            'montant_total' => $m2($cmd->montant_total),
                            'montant_regle' => $m2($cmd->montant_regle),
                            'statut' => $cmd->statut,
                        ];
                    }
                    $resultats[] = [
                        'reglements' => $regs,
                        'ecritures' => $ecritures,
                        'commandes' => $cmds,
                        'nb_reglements' => count($regs),
                        'nb_ecritures' => count($ecritures),
                    ];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'tresorerie_inconnue' => __('achats.reglement_tresorerie_inconnue', ['code' => ':code']),
                        'montant_invalide' => __('achats.reglement_montant_invalide'),
                        'superieur_au_reste' => __('achats.reglement_superieur_au_reste', ['reste' => ':reste']),
                        'deja_annule' => __('achats.reglement_deja_annule'),
                        'motif_requis' => __('achats.reglement_motif_requis'),
                        'piece_introuvable' => __('achats.reglement_piece_introuvable', ['libelle' => ':libelle']),
                        'commande_cloturee' => __('achats.commande_cloturee'),
                        'form_reglement' => __('achats_pwa.appro.form_reglement', ['fournisseur' => ':fournisseur']),
                        'form_reglement_sous_titre' => __('achats_pwa.appro.form_reglement_sous_titre', ['commande' => ':commande', 'reste' => ':reste']),
                        'form_montant_regle' => __('achats_pwa.appro.form_montant_regle'),
                        'form_tresorerie' => __('achats_pwa.appro.form_tresorerie'),
                        'form_valider_reglement' => __('achats_pwa.appro.form_valider_reglement'),
                        'reglement_enregistre' => __('achats_pwa.appro.reglement_enregistre', ['montant' => ':montant', 'fournisseur' => ':fournisseur']),
                        'reglement_commande_soldee' => __('achats_pwa.appro.reglement_commande_soldee'),
                        'tresorerie_caisse' => __('achats_pwa.appro.tresorerie_caisse'),
                        'tresorerie_momo' => __('achats_pwa.appro.tresorerie_momo'),
                        'tresorerie_banque' => __('achats_pwa.appro.tresorerie_banque'),
                        'regler' => __('achats_pwa.appro.regler'),
                        'annuler' => __('pwa.modale.annuler'),
                        'col_regle' => __('pwa.appro.col_regle'),
                        'col_reste_du' => __('achats_pwa.appro.col_reste_du'),
                        'col_numero_commande' => __('achats_pwa.appro.col_numero_commande'),
                        'col_anciennete' => __('achats_pwa.appro.col_anciennete'),
                        'col_date' => __('pwa.appro.col_date'),
                        'col_montant' => __('pwa.appro.col_montant'),
                        'kpi_a_payer' => __('pwa.appro.kpi_a_payer'),
                        'kpi_total_du' => __('pwa.appro.kpi_total_du'),
                        'dettes_titre' => __('pwa.appro.dettes_titre'),
                        'dettes_portee' => __('achats_pwa.appro.dettes_portee'),
                        'dettes_vide' => __('pwa.appro.dettes_vide'),
                        'total_du' => __('pwa.appro.total_du'),
                        'jours' => __('pwa.appro.jours', ['nombre' => ':nombre']),
                        'validation_required' => __('validation.required', ['attribute' => ':attribute']),
                        'validation_numeric' => __('validation.numeric', ['attribute' => ':attribute']),
                        'validation_in' => __('validation.in', ['attribute' => ':attribute']),
                        'validation_exists' => __('validation.exists', ['attribute' => ':attribute']),
                        'validation_gt' => __('validation.gt.numeric'),
                        'tresoreries' => DepenseService::TRESORERIES,
                        'plafond' => Approvisionnement::PLAFOND,
                    ]];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = [
                'refus' => (new ReflectionClass($e))->getShortName(),
                'message' => $e->getMessage(),
            ];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
