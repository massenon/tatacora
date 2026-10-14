<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Stocks\Services\VerificationSeuilService;
use App\Models\User;
use App\Shared\Parametres\Services\OptionsSystemeService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Les alertes d'ouverture de la cloche (audit du 01/09/2026) — DÉRIVÉES,
 * jamais stockées.
 *
 * ## La règle qui gouverne ce fichier
 *
 * Chaque alerte est recalculée à la lecture depuis la table opérationnelle
 * qui la fonde : stocker « il y a une rupture » ferait vieillir l'alerte
 * pendant que la condition disparaît — l'indicateur qui affirme un état qu'il
 * n'a pas vérifié (PA-59/60/61). Ici, une alerte qui s'affiche est VRAIE au
 * moment où elle s'affiche, et disparaît d'elle-même avec sa cause. Seul
 * l'état « vu » se stocke (`alertes_vues`), parce qu'il n'est dérivable de
 * rien.
 *
 * ## Un calcul par RÈGLE EXISTANTE, jamais une seconde formule
 *
 * - Stock sous seuil / rupture : `VerificationSeuilService::articlesCritiques()`
 *   (RG-07, `stock <= seuil_alerte`) — l'auteur unique de cette règle.
 * - Créances : le prédicat « impayée » de `SoldeClientService` est
 *   `Facture::SQL_RESTE_DU` ; on le reprend tel quel (PA-126 : une seconde
 *   formule en SQL finirait par diverger de l'écran des clients).
 * - Arrivées / départs du jour : la même dérivation d'état que l'écran
 *   Hébergement (dates + `sejours`), jamais un statut stocké (PA-111).
 * - Caisse : `sessions_caisse.date_cloture IS NULL` et ouverture avant
 *   aujourd'hui — la définition même de « clôture en retard » que la barre
 *   supérieure affiche déjà (`etat === 'tardive'`).
 *
 * Le RBAC filtre par module via `MenuLateral::moduleAccessible()` — la même
 * source que le menu, jamais un second calcul de droits.
 */
final class AlertesOuverture
{
    /** Fenêtre d'ancienneté d'une créance avant rappel (jours). */
    public const ANCIENNETE_CREANCE_JOURS = 30;

    /** Plafond de lignes par famille — la cloche invite, l'écran détaille. */
    public const PLAFOND_PAR_FAMILLE = 5;

    /**
     * Les alertes visibles par CET utilisateur, plus récentes d'abord.
     *
     * @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string, vue: bool}>
     */
    public static function pour(?User $utilisateur): array
    {
        if ($utilisateur === null) {
            return [];
        }

        // Bascule « Alertes à l'ouverture de session » (écran Paramètres,
        // 02/09/2026) — ouverte par défaut, comme au maître
        // (`options-systeme.js`, DEFAUTS). Fermée : la cloche ne dérive plus
        // aucune alerte, pour TOUS les profils — c'est un réglage d'application,
        // pas un droit, et le RBAC ci-dessous continue de s'appliquer quand
        // elle est ouverte.
        if (! app(OptionsSystemeService::class)->alertesOuvertureActives()) {
            return [];
        }

        $alertes = [];

        foreach (self::toutes() as $alerte) {
            if (! MenuLateral::moduleAccessible($utilisateur, $alerte['module'])) {
                continue;
            }

            $alertes[] = $alerte;
        }

        $vues = DB::table('alertes_vues')
            ->where('utilisateur_id', $utilisateur->id)
            ->pluck('cle_alerte')
            ->all();

        return array_map(
            static fn (array $alerte): array => $alerte + ['vue' => in_array($alerte['cle'], $vues, true)],
            $alertes,
        );
    }

    /**
     * Toutes les alertes, sans RBAC ni état « vu » — chaque famille plafonnée.
     *
     * @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string}>
     */
    private static function toutes(): array
    {
        return array_merge(
            self::alertesStock(),
            self::alertesCaisse(),
            self::alertesReservations(),
            self::alertesCreances(),
        );
    }

    // =====================================================================
    // LES DEUX MODALES D'OUVERTURE DE SESSION (maitre :
    // `prototype_v2/assets/js/alertes-ouverture.js`) — verifiees manquantes
    // par le Product Owner le 02/09/2026. La CLOCHE ci-dessus est un autre
    // mecanisme, que le maitre distingue lui-meme (« pourquoi une modale, et
    // pas une notification de plus ») : les collecteurs des modales ne sont
    // PAS plafonnes a 5 par famille — le maitre affiche 10 lignes puis
    // « … et N autres ».
    // =====================================================================

    /** Le maitre coupe chaque bloc a 10 lignes, le reste est compte. */
    public const LIGNES_PAR_BLOC = 10;

    /**
     * Regle du maitre pour « a relancer » : creance echue de plus de
     * ANCIENNETE_CREANCE_JOURS ET aucune relance depuis 14 jours —
     * « relancer un client contacte avant-hier abime la relation sans rien
     * accelerer ». Distincte du seuil de l'ecran M3
     * (ClientsCreances::JOURS_AVANT_RELANCE = 30), comme au maitre.
     */
    public const JOURS_RELANCE_RECENTE = 14;

    /**
     * Modale 1 — stock critique, SANS plafond de famille : rupture d'abord.
     *
     * @return list<array{article_id: string, libelle: string, detail: string, critique: bool}>
     */
    public static function stockCritiqueModale(): array
    {
        $critiques = app(VerificationSeuilService::class)->articlesCritiques();

        $articles = DB::table('articles')
            ->whereIn('id', $critiques->pluck('article_id')->unique()->all())
            ->get(['id', 'libelle', 'unite_mesure'])
            ->keyBy('id');

        $lignes = [];

        foreach ($critiques as $ligne) {
            $article = $articles->get($ligne['article_id']);
            $rupture = bccomp($ligne['stock'], '0', 2) <= 0;

            $lignes[] = [
                'article_id' => $ligne['article_id'],
                'libelle' => (string) ($article->libelle ?? $ligne['article_id']),
                'detail' => __('pwa.alertes_ouverture.stock_detail', [
                    'stock' => self::quantite($ligne['stock']),
                    'unite' => (string) ($article->unite_mesure ?? ''),
                    'seuil' => self::quantite($ligne['seuil']),
                ]),
                'critique' => $rupture,
            ];
        }

        usort($lignes, static fn (array $a, array $b): int => (int) $b['critique'] <=> (int) $a['critique']);

        return $lignes;
    }

    /**
     * Modale 2, bloc 1 — sejours arrives a echeance : depart prevu
     * aujourd'hui, ou depart depasse SANS check-out (en rouge — « l'oubli
     * d'hier n'est pas la routine du jour »). Un sejour deja clos n'appelle
     * aucune action et n'encombre pas la liste.
     *
     * @return list<array{sejour_id: string, libelle: string, detail: string, critique: bool}>
     */
    public static function departsAEcheance(): array
    {
        $aujourdhui = Carbon::today()->toDateString();

        $sejours = DB::table('sejours')
            ->join('reservations', 'reservations.id', '=', 'sejours.reservation_id')
            ->join('clients', 'clients.id', '=', 'reservations.client_id')
            ->join('unites_hebergement', 'unites_hebergement.id', '=', 'reservations.unite_id')
            ->whereNotNull('sejours.date_checkin_reel')
            ->whereNull('sejours.date_checkout_reel')
            ->whereDate('reservations.date_depart', '<=', $aujourdhui)
            ->orderBy('reservations.date_depart')
            ->get([
                'sejours.id AS sejour_id',
                'reservations.date_depart',
                'clients.nom', 'clients.prenom',
                'unites_hebergement.numero AS unite',
            ]);

        $lignes = [];

        foreach ($sejours as $sejour) {
            $depasse = (string) $sejour->date_depart < $aujourdhui;

            $lignes[] = [
                'sejour_id' => (string) $sejour->sejour_id,
                'libelle' => trim(($sejour->prenom ?? '') . ' ' . $sejour->nom) . ' — ' . $sejour->unite,
                'detail' => $depasse
                    ? __('pwa.alertes_ouverture.depart_depasse', [
                        'date' => Carbon::parse((string) $sejour->date_depart)->format('d/m/Y'),
                    ])
                    : __('pwa.alertes_ouverture.depart_aujourdhui'),
                'critique' => $depasse,
            ];
        }

        return $lignes;
    }

    /**
     * Modale 2, bloc 2 — creances a relancer. `relance_requise` suit la
     * regle du maitre (plus de 30 jours d'anciennete ET aucune relance
     * depuis 14 jours) ; une creance echue relancee recemment reste LISTEE
     * sans action (« le gerant doit la voir, sans qu'on lui propose une
     * action qui serait deplacee »). Reste du : `Facture::SQL_RESTE_DU`,
     * l'auteur unique — jamais une seconde formule.
     *
     * @return list<array{client_id: string, libelle: string, detail: string, critique: bool, relance_requise: bool, reste: string}>
     */
    public static function creancesModale(): array
    {
        $anciennes = \App\Domain\Crm\Services\SoldeClientService::appliquerPredicatImpayee(DB::table('factures'))
            ->where('date_emission', '<=', Carbon::today()->subDays(self::ANCIENNETE_CREANCE_JOURS))
            ->selectRaw('factures.client_id, MIN(factures.date_emission) AS plus_ancienne, SUM' . Facture::SQL_RESTE_DU . ' AS reste')
            ->groupBy('factures.client_id')
            ->orderBy('plus_ancienne')
            ->get();

        if ($anciennes->isEmpty()) {
            return [];
        }

        $clients = DB::table('clients')
            ->whereIn('id', $anciennes->pluck('client_id')->all())
            ->get(['id', 'nom', 'prenom'])
            ->keyBy('id');

        $dernieres = DB::table('relances_clients')
            ->whereIn('client_id', $anciennes->pluck('client_id')->all())
            ->selectRaw('client_id, MAX(date_relance) AS derniere')
            ->groupBy('client_id')
            ->pluck('derniere', 'client_id');

        $seuilRecente = Carbon::today()->subDays(self::JOURS_RELANCE_RECENTE)->toDateString();
        $seuilDouteuse = Carbon::today()->subDays(90)->toDateString();

        $lignes = [];

        foreach ($anciennes as $creance) {
            $client = $clients->get($creance->client_id);
            $derniere = $dernieres[$creance->client_id] ?? null;
            $anciennete = (int) Carbon::parse((string) $creance->plus_ancienne)->diffInDays(Carbon::today());

            $lignes[] = [
                'client_id' => (string) $creance->client_id,
                'libelle' => $client === null
                    ? __('pwa.cloche.client_inconnu')
                    : trim(($client->prenom ?? '') . ' ' . $client->nom),
                'detail' => __('pwa.alertes_ouverture.creance_detail', [
                    'montant' => MontantFcfa::format(bcadd((string) $creance->reste, '0', 2)),
                    'jours' => $anciennete,
                ]) . ($derniere === null
                    ? __('pwa.alertes_ouverture.jamais_relance')
                    : __('pwa.alertes_ouverture.relance_le', [
                        'date' => Carbon::parse((string) $derniere)->format('d/m/Y'),
                    ])),
                'critique' => (string) $creance->plus_ancienne <= $seuilDouteuse,
                'relance_requise' => $derniere === null || (string) $derniere < $seuilRecente,
                'reste' => bcadd((string) $creance->reste, '0', 2),
            ];
        }

        usort($lignes, static fn (array $a, array $b): int => (int) $b['relance_requise'] <=> (int) $a['relance_requise']);

        return $lignes;
    }

    /** @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string}> */
    private static function alertesStock(): array
    {
        $critiques = app(VerificationSeuilService::class)->articlesCritiques();

        $libelles = DB::table('articles')
            ->whereIn('id', $critiques->pluck('article_id')->unique()->all())
            ->pluck('libelle', 'id');

        $alertes = [];

        foreach ($critiques->take(self::PLAFOND_PAR_FAMILLE) as $ligne) {
            $rupture = bccomp($ligne['stock'], '0', 2) <= 0;

            $alertes[] = [
                'cle' => 'stock:' . $ligne['article_id'] . ':' . $ligne['point_id'],
                'module' => 'M6',
                'famille' => $rupture ? 'rupture' : 'seuil',
                'titre' => $rupture
                    ? __('pwa.cloche.rupture_titre')
                    : __('pwa.cloche.seuil_titre'),
                'detail' => __($rupture ? 'pwa.cloche.rupture_detail' : 'pwa.cloche.seuil_detail', [
                    'article' => (string) ($libelles[$ligne['article_id']] ?? $ligne['article_id']),
                    'stock' => self::quantite($ligne['stock']),
                    'seuil' => self::quantite($ligne['seuil']),
                ]),
                'route' => 'pwa.stocks.liste',
            ];
        }

        return $alertes;
    }

    /**
     * Une quantité de stock, sans décimales muettes — « 12 » plutôt que
     * « 12.00 », « 0.5 » conservé tel quel.
     */
    private static function quantite(string $valeur): string
    {
        $nette = rtrim(rtrim($valeur, '0'), '.');

        return $nette === '' || $nette === '-' ? '0' : $nette;
    }

    /** @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string}> */
    private static function alertesCaisse(): array
    {
        $sessions = DB::table('sessions_caisse')
            ->whereNull('date_cloture')
            ->where('date_ouverture', '<', Carbon::today())
            ->orderBy('date_ouverture')
            ->limit(self::PLAFOND_PAR_FAMILLE)
            ->get(['id', 'point_vente', 'date_ouverture']);

        $alertes = [];

        foreach ($sessions as $session) {
            $alertes[] = [
                'cle' => 'caisse:' . $session->id,
                'module' => 'M5',
                'famille' => 'caisse',
                'titre' => __('pwa.cloche.caisse_titre'),
                'detail' => __('pwa.cloche.caisse_detail', [
                    'point' => (string) $session->point_vente,
                    'date' => Carbon::parse((string) $session->date_ouverture)->format('d/m/Y'),
                ]),
                'route' => 'pwa.pos.comptant',
            ];
        }

        return $alertes;
    }

    /** @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string}> */
    private static function alertesReservations(): array
    {
        $aujourdhui = Carbon::today()->toDateString();

        // Arrivées du jour sans check-in : même dérivation que l'écran
        // Hébergement — la date d'arrivée est aujourd'hui, la réservation
        // n'est pas annulée, et aucun séjour n'a enregistré l'arrivée.
        $arrivees = DB::table('reservations')
            ->whereNot('statut', 'annulee')
            ->whereDate('date_arrivee', $aujourdhui)
            ->whereNotExists(static function ($sous) {
                $sous->select(DB::raw(1))
                    ->from('sejours')
                    ->whereColumn('sejours.reservation_id', 'reservations.id')
                    ->whereNotNull('sejours.date_checkin_reel');
            })
            ->orderBy('date_creation')
            ->limit(self::PLAFOND_PAR_FAMILLE)
            ->get(['id', 'client_id']);

        $clients = DB::table('clients')
            ->whereIn('id', $arrivees->pluck('client_id')->unique()->all())
            ->get(['id', 'nom', 'prenom'])
            ->keyBy('id');

        $alertes = [];

        foreach ($arrivees as $reservation) {
            $client = $clients->get($reservation->client_id);

            $alertes[] = [
                'cle' => 'arrivee:' . $reservation->id . ':' . $aujourdhui,
                'module' => 'M1',
                'famille' => 'reservation',
                'titre' => __('pwa.cloche.arrivee_titre'),
                'detail' => __('pwa.cloche.arrivee_detail', [
                    'client' => $client === null
                        ? __('pwa.cloche.client_inconnu')
                        : trim(($client->prenom ?? '') . ' ' . $client->nom),
                ]),
                'route' => 'pwa.hebergement',
            ];
        }

        return $alertes;
    }

    /** @return list<array{cle: string, module: string, famille: string, titre: string, detail: string, route: string}> */
    private static function alertesCreances(): array
    {
        // Le prédicat est `Facture::SQL_RESTE_DU`, l'auteur unique du reste
        // dû (PA-165) — jamais une seconde formule. Le solde reste un MAXIMUM
        // au sens de PA-21, et le libellé de l'alerte parle de « reste dû »,
        // pas de « solde certifié ».
        $anciennes = \App\Domain\Crm\Services\SoldeClientService::appliquerPredicatImpayee(DB::table('factures'))
            ->where('date_emission', '<=', Carbon::today()->subDays(self::ANCIENNETE_CREANCE_JOURS))
            ->selectRaw('factures.id, factures.client_id, factures.date_emission, ' . Facture::SQL_RESTE_DU . ' AS reste')
            ->orderBy('date_emission')
            ->limit(self::PLAFOND_PAR_FAMILLE)
            ->get();

        $clients = DB::table('clients')
            ->whereIn('id', $anciennes->pluck('client_id')->unique()->all())
            ->get(['id', 'nom', 'prenom'])
            ->keyBy('id');

        $alertes = [];

        foreach ($anciennes as $facture) {
            $client = $clients->get($facture->client_id);

            $alertes[] = [
                'cle' => 'creance:' . $facture->id,
                'module' => 'M3',
                'famille' => 'creance',
                'titre' => __('pwa.cloche.creance_titre'),
                'detail' => __('pwa.cloche.creance_detail', [
                    'client' => $client === null
                        ? __('pwa.cloche.client_inconnu')
                        : trim(($client->prenom ?? '') . ' ' . $client->nom),
                    'montant' => MontantFcfa::format(bcadd((string) $facture->reste, '0', 2)),
                    'date' => Carbon::parse((string) $facture->date_emission)->format('d/m/Y'),
                ]),
                'route' => 'pwa.clients',
            ];
        }

        return $alertes;
    }
}
