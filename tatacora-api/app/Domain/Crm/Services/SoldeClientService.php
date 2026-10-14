<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Solde dû par client — CALCULÉ, jamais lu d'une colonne (M3).
 *
 * ## Pourquoi ce service existe, et pourquoi il n'existait pas
 *
 * `clients.solde` est une colonne que RIEN n'écrit : elle vaut zéro pour tout
 * le monde (PA-126, vérifié le 28/08/2026 — aucun `update` ne la touche dans
 * tout `app/`). L'afficher donnerait un zéro plausible sur la fiche d'un
 * client qui doit 200 000 F, sur l'écran même où l'on décide de relancer.
 * Ce service est le SEUL chemin légitime vers un solde client ; la colonne
 * n'est jamais lue, ni ici ni ailleurs.
 *
 * ## LA SOURCE UNIQUE DU PRÉDICAT « facture impayée » (PA-121)
 *
 * Le prédicat existait déjà — `TableauDeBordService::facturesImpayees()` :
 * une facture `certifiee` dont `montant_ttc` dépasse la somme de ses
 * `paiements`. Il est EXTRAIT ici (`appliquerPredicatImpayee()`) et le
 * tableau de bord l'appelle désormais : deux formules pour la même grandeur
 * auraient fini par diverger, et l'écran Clients aurait affiché une dette que
 * le tableau de bord ne compte pas — deux vérités sur le même serveur.
 *
 * ## Ce que ce solde EST, et ce qu'il n'est PAS
 *
 * - Il vient des factures certifiées non soldées, la seule matière que le
 *   schéma serveur porte avec un montant. Les restes à payer sur séjours du
 *   maître (`m3-clients-creances.html` l.29-31) n'entrent PAS dedans :
 *   `reservations` ne porte aucun montant de séjour — ni tarif, ni total,
 *   seulement `acompte` (PA-29, PA-57).
 * - C'est un MAXIMUM. Les recouvrements n'existent pas (PA-21 : le modèle
 *   `Paiement` est absent, et RIEN n'écrit la table `paiements` — vérifié le
 *   28/08/2026, aucun writer dans `app/`). Un encaissement réel non saisi ne
 *   peut donc pas diminuer ce chiffre. Tout écran ou document qui l'affiche
 *   doit le dire : relancer un client qui a déjà payé coûte plus cher que ne
 *   pas relancer.
 * - Une facture `brouillon` ou `en_attente_certification` n'y entre pas :
 *   c'est le prédicat du tableau de bord, conservé tel quel — un brouillon
 *   n'est pas une créance opposable.
 *
 * ## Pourquoi la balance âgée n'est PAS ici
 *
 * Les tranches 30/60/90 jours (PA-20) sont une extension absente des 61 EF et
 * jamais arbitrée par le Product Owner. Les calculer « puisque les dates sont
 * là » trancherait seul une question de périmètre — et une ancienneté
 * supposerait une date d'échéance que personne n'a décidée (PA-126) :
 * « 45 j » se lit comme un retard constaté, pas comme une convention de
 * développeur.
 *
 * @see EF-M3-04 Suivi des soldes et créances
 * @see RG-18 Fiche client unique
 * @see PA-20 (balance âgée non arbitrée), PA-21 (recouvrements absents), PA-126
 */
class SoldeClientService
{
    /** Le statut MECeF qui rend une facture opposable — jamais un statut de paiement (PA-49). */
    public const STATUT_CERTIFIEE = 'certifiee';

    /**
     * La formule du reste dû vit sur `Facture` depuis PA-165 (01/09/2026) —
     * le premier writer de `paiements` l'a enrichie (avoirs, acomptes des
     * réservations liées) et la créance est un fait de la FACTURE : deux
     * copies auraient divergé au premier terme ajouté. Ces alias restent pour
     * les lecteurs existants ; l'auteur est {@see \App\Domain\Facturation\Models\Facture}.
     */
    public const SQL_PAIEMENTS_RECUS = \App\Domain\Facturation\Models\Facture::SQL_PAIEMENTS_RECUS;

    public const SQL_RESTE_DU = \App\Domain\Facturation\Models\Facture::SQL_RESTE_DU;

    /**
     * Applique le prédicat « facture impayée » à une requête sur `factures`.
     *
     * C'est LA source unique : `TableauDeBordService::facturesImpayees()`
     * (compteur global M11) et le registre par client ci-dessous l'appellent
     * tous deux. Comparaison en SQL sur `DECIMAL`, jamais en flottant PHP.
     */
    public static function appliquerPredicatImpayee(Builder $requete): Builder
    {
        return $requete
            ->where('factures.statut', self::STATUT_CERTIFIEE)
            ->whereRaw(self::SQL_RESTE_DU . ' > 0');
    }

    /**
     * Le registre des clients avec leur solde calculé.
     *
     * Tous les clients y figurent — un client sans dette rend `solde = "0.00"`
     * et `pieces = 0` : l'écran Liste des clients du maître montre TOUT le
     * référentiel, pas les seuls débiteurs. Tri du maître
     * (`m3-clients-creances.js` l.99) : solde décroissant, puis nom.
     *
     * @param  string|null  $terme  filtre sur nom/prénom/téléphone — l'export dit son filtre (PA-119)
     * @param  string|null  $etat  `debiteur` (solde > 0) | `solde` (aucune dette) | null (tous)
     * @return list<object{id: string, nom: string, prenom: string|null, telephone: string, type_client: string, solde: string, pieces: int, anciennete: int|null, actif: bool}>
     */
    public function registre(?string $terme = null, ?string $etat = null): array
    {
        $impayees = self::appliquerPredicatImpayee(DB::table('factures'))
            ->selectRaw('factures.client_id AS client_id')
            ->selectRaw('SUM' . self::SQL_RESTE_DU . ' AS solde')
            ->selectRaw('COUNT(*) AS pieces')
            // La plus ancienne piece impayee — MEME prédicat que le solde,
            // jamais une seconde formule (02/09/2026 : la colonne
            // « Ancienneté » de la liste rendait un tiret EN DUR alors que
            // la donnée se dérive ; l'onglet « Suivi des dettes » la
            // calculait déjà de son côté).
            ->selectRaw('MIN(factures.date_emission) AS plus_ancienne')
            ->groupBy('factures.client_id');

        $requete = DB::table('clients')
            ->leftJoinSub($impayees, 'impayees', 'impayees.client_id', '=', 'clients.id')
            // ⚠ `clients.solde` n'apparaît PAS dans ce select, et ne doit
            // jamais y entrer : c'est la colonne morte de PA-126.
            ->selectRaw('clients.id, clients.nom, clients.prenom, clients.telephone, clients.type_client')
            // `actif` — l'ARCHIVE du referentiel (03/09/2026). L'ecran
            // marque la ligne et offre « Restaurer » : masquer un client
            // archive le rendrait indiscernable d'une fiche inexistante,
            // et « reste restaurable » ne serait tenue nulle part.
            ->selectRaw('clients.actif AS actif')
            ->selectRaw('COALESCE(impayees.solde, 0) AS solde')
            ->selectRaw('COALESCE(impayees.pieces, 0) AS pieces')
            ->selectRaw('impayees.plus_ancienne AS plus_ancienne');

        if ($terme !== null && $terme !== '') {
            $requete->where(function (Builder $sous) use ($terme): void {
                $sous->where('clients.nom', 'like', '%' . $terme . '%')
                    ->orWhere('clients.prenom', 'like', '%' . $terme . '%')
                    ->orWhere('clients.telephone', 'like', '%' . $terme . '%');
            });
        }

        if ($etat === 'debiteur') {
            $requete->whereRaw('COALESCE(impayees.solde, 0) > 0');
        } elseif ($etat === 'solde') {
            $requete->whereRaw('COALESCE(impayees.solde, 0) = 0');
        }

        /** @var list<object{id: string, nom: string, prenom: string|null, telephone: string, type_client: string, solde: string, pieces: int, anciennete: int|null, actif: bool}> $lignes */
        $lignes = $requete
            ->orderByDesc('solde')
            ->orderBy('clients.nom')
            ->orderBy('clients.id')
            ->get()
            ->map(static function (object $ligne): object {
                // MySQL rend le DECIMAL en chaîne, mais un agrégat NULL passé
                // par COALESCE peut sortir en entier : on renormalise à deux
                // décimales via bcadd, jamais un cast flottant.
                $ligne->solde = bcadd((string) $ligne->solde, '0', 2);
                $ligne->pieces = (int) $ligne->pieces;
                $ligne->actif = (bool) $ligne->actif;
                // Jours ENTIERS depuis la plus ancienne impayée ; `null`
                // (aucune dette) reste `null` — jamais un zéro plausible.
                $ligne->anciennete = $ligne->plus_ancienne === null
                    ? null
                    : (int) \Illuminate\Support\Carbon::parse((string) $ligne->plus_ancienne)->diffInDays(now());

                return $ligne;
            })
            ->values()
            ->all();

        return $lignes;
    }

    /**
     * Les totaux de la bande d'indicateurs — sur le registre ENTIER, jamais
     * sur la page affichée (même règle qu'en `Locations` : la bande surplombe
     * le tableau et doit porter sur le même ensemble que son compteur).
     *
     * @return array{total_du: string, nb_pieces: int, nb_clients: int}
     */
    public function totaux(): array
    {
        /** @var object{total_du: string|int|null, nb_pieces: int|string, nb_clients: int|string}|null $ligne */
        $ligne = self::appliquerPredicatImpayee(DB::table('factures'))
            ->selectRaw('SUM' . self::SQL_RESTE_DU . ' AS total_du')
            ->selectRaw('COUNT(*) AS nb_pieces')
            ->selectRaw('COUNT(DISTINCT factures.client_id) AS nb_clients')
            ->first();

        return [
            'total_du' => bcadd((string) ($ligne->total_du ?? '0'), '0', 2),
            'nb_pieces' => (int) ($ligne->nb_pieces ?? 0),
            'nb_clients' => (int) ($ligne->nb_clients ?? 0),
        ];
    }

    /**
     * Le total RÉELLEMENT encaissé depuis une date — la somme des paiements
     * ACTIFS de la table `paiements`.
     *
     * Remontée de l'écran M3 (`ClientsCreances::encaisseSur30Jours()`) le
     * 02/09/2026 pour que la carte « Clients & créances » de l'accueil lise
     * la même mesure (PA-121) — et CORRIGÉE au passage : la version d'écran
     * ne filtrait pas `statut = 'actif'`, donc comptait les paiements
     * ANNULÉS (PA-168), à rebours de `Facture::SQL_PAIEMENTS_RECUS` et de
     * `Facture::totalEncaisse()` qui les excluent tous deux. Un encaissement
     * annulé n'est pas un encaissement.
     */
    public function encaisseDepuis(\DateTimeInterface $depuis): string
    {
        $total = DB::table('paiements')
            ->where('statut', 'actif')
            ->where('date_paiement', '>=', $depuis)
            ->sum('montant');

        return bcadd((string) $total, '0', 2);
    }
}
