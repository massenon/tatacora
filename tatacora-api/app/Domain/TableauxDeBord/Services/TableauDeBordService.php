<?php

declare(strict_types=1);

namespace App\Domain\TableauxDeBord\Services;

use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\TableauxDeBord\Data\Periode;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Indicateurs consolidés multi-activités — EF-M11-01, EF-M11-03, EF-M11-04.
 *
 * @see EF-M11-01 Tableau de bord global (chiffre d'affaires, taux d'occupation)
 * @see EF-M11-03 Indicateurs comparatifs (période courante vs précédente)
 * @see EF-M11-04 Filtres dynamiques par période
 * @see RG-02 Disponibilité toujours calculée
 *
 * ## M11 ne possède aucune table
 *
 * `05_MODULE_SPECIFICATIONS.md` §M11 : « service de lecture agrégée
 * interrogeant les domaines existants, **jamais de duplication de données pour
 * "accélérer" l'affichage** sans passer par une vue matérialisée documentée ».
 * Tous les KPI ci-dessous relisent donc les tables sources à chaque appel.
 *
 * Un KPI = une méthode dédiée (`SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §4,
 * « jamais un calcul en ligne dans le contrôleur »).
 *
 * ## Trois KPI ne sont PAS calculés comme l'écrit le prototype — PA-49
 *
 * Le prototype décrit des calculs qui reposent sur des colonnes absentes du
 * schéma. Plutôt que d'inventer ces colonnes ou de renvoyer zéro, les KPI sont
 * dérivés des sources réelles, et l'écart est tracé en PA-49 :
 *
 * 1. **CA payé** — le prototype filtre `factures.statut = 'Payée'`. Cette
 *    valeur **n'existe pas** : l'`enum` réel est
 *    `brouillon|en_attente_certification|certifiee|echec_certification`,
 *    c'est-à-dire le cycle de **certification MECeF**, pas de paiement. Le CA
 *    encaissé est donc la somme des `paiements` de la période — ce qui est
 *    aussi le seul chiffre défendable devant un comptable : un statut de
 *    facture ne prouve pas un encaissement.
 * 2. **Taux d'occupation** — le prototype compte `unites.statut = 'Occupée'`.
 *    Utiliser cette colonne contredirait RG-02 (« la disponibilité est
 *    toujours calculée, jamais stockée ») : `statut` est un état opérationnel
 *    (nettoyage, hors service), pas une occupation. Le taux est calculé en
 *    **nuitées** depuis `reservations`.
 * 3. **Factures en attente** — même cause que (1). Compté comme « certifiées
 *    dont le règlement est incomplet ».
 */
class TableauDeBordService
{
    private const PRECISION = 2;

    /** Classe SYSCOHADA des comptes de charges. */
    private const CLASSE_CHARGES = '6';

    /** Réservations qui n'occupent pas physiquement une unité. */
    private const STATUTS_NON_OCCUPANTS = ['annulee', 'en_attente'];

    /**
     * Les 8 KPI de `SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §4, avec leur variation
     * par rapport à la période précédente (EF-M11-03).
     *
     * @return array<string, array{valeur: string, precedent: string, variation_pct: string|null, unite: string}>
     */
    public function indicateurs(Periode $periode): array
    {
        $precedente = $periode->precedente();

        return [
            'chiffre_affaires_encaisse' => $this->comparer(
                $this->chiffreAffairesEncaisse($periode),
                $this->chiffreAffairesEncaisse($precedente),
                'montant',
            ),
            'taux_occupation' => $this->comparer(
                $this->tauxOccupation($periode),
                $this->tauxOccupation($precedente),
                'pourcentage',
            ),
            'tresorerie_caisse' => $this->comparer(
                $this->tresorerieCaisse($periode),
                $this->tresorerieCaisse($precedente),
                'montant',
            ),
            'depenses_cumulees' => $this->comparer(
                $this->depensesCumulees($periode),
                $this->depensesCumulees($precedente),
                'montant',
            ),
            'reservations_en_attente' => $this->comparer(
                (string) $this->reservationsEnAttente($periode),
                (string) $this->reservationsEnAttente($precedente),
                'nombre',
            ),
            'factures_impayees' => $this->comparer(
                (string) $this->facturesImpayees($periode),
                (string) $this->facturesImpayees($precedente),
                'nombre',
            ),
            // Photographie à l'instant : un stock n'a pas de valeur « sur une
            // période », et comparer deux photos n'aurait pas de sens ici.
            'valeur_stock' => [
                'valeur' => $this->valeurStock(),
                'precedent' => '0.00',
                'variation_pct' => null,
                'unite' => 'montant',
            ],
            'employes_actifs' => [
                'valeur' => (string) $this->employesActifs(),
                // La carte de l'accueil interpole ce champ comme `:total` de
                // sa note (« Sur :total au total ») : un zéro figé y écrivait
                // « 10 employés actifs — Sur 0 au total » (02/09/2026,
                // passage navigateur). Le total réel vient d'`effectif()`,
                // l'auteur unique du décompte.
                'precedent' => (string) $this->effectif()['total'],
                'variation_pct' => null,
                'unite' => 'nombre',
            ],
        ];
    }

    // ------------------------------------------------------------- KPI 1

    /**
     * Chiffre d'affaires réellement **encaissé** sur la période.
     *
     * Somme des `paiements`, pas un statut de facture : voir la note PA-49 de
     * l'en-tête de classe.
     */
    public function chiffreAffairesEncaisse(Periode $periode): string
    {
        $total = DB::table('paiements')
            ->whereBetween('date_paiement', [$periode->debut, $periode->fin])
            ->sum('montant');

        return $this->montant($total);
    }

    /**
     * Chiffre d'affaires **facturé** (certifié), distinct de l'encaissé.
     *
     * Exposé séparément parce que l'écart entre les deux EST l'information
     * utile au Gérant : un CA facturé très supérieur à l'encaissé signale un
     * problème de recouvrement, qu'un chiffre unique masquerait.
     */
    public function chiffreAffairesFacture(Periode $periode): string
    {
        $total = DB::table('factures')
            ->where('statut', 'certifiee')
            ->whereBetween('date_emission', [$periode->debut, $periode->fin])
            ->sum('montant_ttc');

        return $this->montant($total);
    }

    // ------------------------------------------------------------- KPI 2

    /**
     * Taux d'occupation en **nuitées**, calculé — jamais lu dans une colonne.
     *
     * Nuitées vendues / (unités × jours de la période). Le décompte se fait par
     * intersection de la réservation avec la fenêtre, en bornes semi-ouvertes :
     * une réservation qui déborde de la période ne compte que ses nuits
     * intérieures, sans quoi le taux dépasserait 100 % en fin de mois.
     *
     * @see RG-02
     */
    public function tauxOccupation(Periode $periode): string
    {
        $unites = DB::table('unites_hebergement')
            // Une unité hors service n'est pas louable : la compter au
            // dénominateur ferait chuter le taux sans qu'aucune vente n'ait
            // été manquée.
            ->where('statut', '!=', 'hors_service')
            ->count();

        $jours = $periode->nombreJours();
        $capacite = $unites * $jours;

        if ($capacite === 0) {
            return '0.00';
        }

        $nuitees = (int) DB::table('reservations')
            ->whereNotIn('statut', self::STATUTS_NON_OCCUPANTS)
            ->where('date_arrivee', '<', $periode->fin)
            ->where('date_depart', '>', $periode->debut)
            ->selectRaw(
                'COALESCE(SUM(DATEDIFF(LEAST(date_depart, ?), GREATEST(date_arrivee, ?))), 0) AS nuitees',
                [$periode->fin->toDateString(), $periode->debut->toDateString()],
            )
            ->value('nuitees');

        return bcdiv(bcmul((string) $nuitees, '100', 4), (string) $capacite, self::PRECISION);
    }

    // ------------------------------------------------------------- KPI 3

    /**
     * Trésorerie de caisse : fonds des sessions **ouvertes** plus les
     * encaissements qui y ont été rattachés.
     *
     * Il n'existe aucune table `mouvements_caisse` au schéma — le solde est
     * donc reconstitué depuis `sessions_caisse` et `paiements`. Les sessions
     * closes sont exclues : leur numéraire a été remis, il n'est plus en caisse.
     */
    public function tresorerieCaisse(Periode $periode): string
    {
        $fonds = DB::table('sessions_caisse')
            ->whereNull('date_cloture')
            ->sum('montant_fond');

        $encaissements = DB::table('paiements')
            ->join('sessions_caisse', 'paiements.session_id', '=', 'sessions_caisse.id')
            ->whereNull('sessions_caisse.date_cloture')
            ->whereBetween('paiements.date_paiement', [$periode->debut, $periode->fin])
            ->sum('paiements.montant');

        return bcadd($this->montant($fonds), $this->montant($encaissements), self::PRECISION);
    }

    // ------------------------------------------------------------- KPI 4

    /**
     * Dépenses de la période — écritures **validées** de classe 6.
     *
     * Aucune table `depenses` n'existe : la source est la comptabilité, ce qui
     * est de toute façon la seule qui fasse foi. Les écritures en brouillon
     * sont exclues — non opposables (RG-12).
     */
    public function depensesCumulees(Periode $periode): string
    {
        $total = DB::table('ecritures_comptables')
            ->join('plan_comptable', 'ecritures_comptables.compte_id', '=', 'plan_comptable.id')
            ->where('plan_comptable.classe', self::CLASSE_CHARGES)
            ->where('ecritures_comptables.statut', 'validee')
            ->whereBetween('ecritures_comptables.date_ecriture', [$periode->debut, $periode->fin])
            // Une charge se lit au débit ; le crédit d'un compte de charge est
            // un avoir fournisseur, qui doit venir en diminution.
            ->selectRaw('COALESCE(SUM(debit) - SUM(credit), 0) AS total')
            ->value('total');

        return $this->montant($total);
    }

    // ------------------------------------------------------------- KPI 5

    public function reservationsEnAttente(Periode $periode): int
    {
        return DB::table('reservations')
            ->where('statut', 'en_attente')
            ->whereBetween('date_creation', [$periode->debut, $periode->fin])
            ->count();
    }

    // ------------------------------------------------------------- KPI 6

    /**
     * Factures certifiées dont le règlement reste incomplet.
     *
     * ⚠ LE PRÉDICAT NE VIT PLUS ICI — `SoldeClientService` (M3) est la source
     * unique depuis le 28/08/2026. Ce KPI le portait seul ; le jour où l'écran
     * Clients & Créances a eu besoin d'un solde PAR client, le recopier aurait
     * produit deux formules pour la même grandeur (PA-121) : la dette d'un
     * client sur son écran et le compteur du tableau de bord auraient fini par
     * diverger. Le prédicat est extrait, et les deux appellent le même code.
     * Comparaison en SQL sur `DECIMAL`, jamais en flottant côté PHP.
     */
    public function facturesImpayees(Periode $periode): int
    {
        return SoldeClientService::appliquerPredicatImpayee(DB::table('factures'))
            ->whereBetween('date_emission', [$periode->debut, $periode->fin])
            ->count();
    }

    // ------------------------------------------------------------- KPI 7

    /**
     * Valorisation du stock au coût moyen pondéré — jamais au prix de vente.
     *
     * Agrégat en une seule requête plutôt qu'un appel par article à
     * `StockTheoriqueService` : un tableau de bord sur un référentiel de
     * plusieurs centaines d'articles ferait autant de requêtes. La **règle**
     * de calcul reste partagée via `TYPES_ENTRANTS` — la dupliquer ici ferait
     * diverger silencieusement le tableau de bord de l'état des stocks le jour
     * où un type de mouvement serait ajouté.
     */
    public function valeurStock(): string
    {
        $total = DB::table('articles')
            ->leftJoin('mouvements_stock', 'articles.id', '=', 'mouvements_stock.article_id')
            ->selectRaw(
                'COALESCE(SUM(CASE WHEN mouvements_stock.type_mouvement IN (?, ?) '
                . 'THEN mouvements_stock.quantite ELSE -mouvements_stock.quantite END '
                . '* articles.cout_moyen_pondere), 0) AS valeur',
                StockTheoriqueService::TYPES_ENTRANTS,
            )
            ->value('valeur');

        return $this->montant($total);
    }

    // ------------------------------------------------------------- KPI 8

    /**
     * @return array{actifs: int, total: int}
     */
    public function effectif(): array
    {
        return [
            'actifs' => DB::table('employes')->where('statut', 'actif')->count(),
            'total' => DB::table('employes')->whereNot('statut', 'parti')->count(),
        ];
    }

    public function employesActifs(): int
    {
        return $this->effectif()['actifs'];
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @return array{valeur: string, precedent: string, variation_pct: string|null, unite: string}
     */
    private function comparer(string $courant, string $precedent, string $unite): array
    {
        return [
            'valeur' => $courant,
            'precedent' => $precedent,
            'variation_pct' => $this->variation($courant, $precedent),
            'unite' => $unite,
        ];
    }

    /**
     * Variation en pourcentage, ou `null` quand elle n'a pas de sens.
     *
     * Une base précédente nulle ne donne pas « +100 % » ni « +∞ » : passer de
     * 0 à 1 réservation n'est pas une progression de 100 %, c'est un
     * démarrage. Renvoyer `null` laisse l'interface afficher « — » plutôt
     * qu'un chiffre spectaculaire et faux.
     */
    private function variation(string $courant, string $precedent): ?string
    {
        if (bccomp($precedent, '0', self::PRECISION) === 0) {
            return null;
        }

        $ecart = bcsub($courant, $precedent, 4);

        return bcdiv(bcmul($ecart, '100', 4), $precedent, self::PRECISION);
    }

    // ------------------------------------------------------- SERIES (EF-M11-01)

    /**
     * Nombre de mois maximal d'une série — le « 1 an » du prototype.
     *
     * Borne FERMÉE : sans elle, `?mois=600` ferait exécuter 1 200 requêtes
     * sur un hébergement mutualisé, depuis une URL que n'importe qui peut
     * composer.
     */
    public const MOIS_MAX = 12;

    /**
     * Série mensuelle « Chiffre d'affaires encaissé » et « Dépenses ».
     *
     * ## Chaque point est calculé comme le KPI, pas comme un agrégat parallèle
     *
     * Les deux valeurs passent par `chiffreAffairesEncaisse()` et
     * `depensesCumulees()`, sur une `Periode::mois()`. C'est deux requêtes par
     * mois — vingt-quatre pour un an, toutes sur des colonnes indexées — et
     * c'est le prix de la seule garantie qui compte ici : **la courbe et la
     * bande d'indicateurs ne peuvent pas se contredire**, puisqu'elles
     * exécutent le même code.
     *
     * Un `GROUP BY` unique serait plus rapide et dupliquerait les prédicats
     * (classe 6, écritures validées, exclusion des brouillons). Le jour où
     * l'un des deux changerait, l'écran afficherait deux vérités.
     *
     * @param  int  $nbMois  Nombre de mois, borné à [1, self::MOIS_MAX].
     * @return list<array{mois: string, debut: string, chiffre_affaires_encaisse: string, depenses: string}>
     */
    public function serieMensuelle(int $nbMois, ?CarbonImmutable $reference = null): array
    {
        $nbMois = max(1, min($nbMois, self::MOIS_MAX));

        // ⚠ `startOfMonth()` AVANT `subMonths()` — corrigé le 31/08/2026.
        //
        // `subMonths()` sur une date au 29/30/31 DÉBORDE : Carbon retranche
        // les mois puis garde le jour, et « 31 juin » devient le 1er juillet.
        // Relevé sur la réponse HTTP réelle du 31/08/2026 : `serieMensuelle(6)`
        // rendait `2026-03, 2026-05, 2026-05, 2026-07, 2026-07, 2026-08` —
        // avril et juin ABSENTS, mai et juillet DOUBLÉS. Le graphique et
        // l'export montraient un mois deux fois et en perdaient deux, sans que
        // rien ne le signale — trois jours par mois, le tableau de bord
        // racontait une autre année que la comptabilité.
        //
        // Ancré au premier du mois, la soustraction ne peut plus déborder :
        // chaque itération part d'un jour qui existe dans tous les mois.
        $maintenant = ($reference ?? CarbonImmutable::now())->startOfMonth();

        $points = [];
        for ($i = $nbMois - 1; $i >= 0; $i--) {
            $periode = Periode::mois($maintenant->subMonths($i));

            $points[] = [
                'mois' => $periode->code,
                'debut' => $periode->debut->toIso8601String(),
                'chiffre_affaires_encaisse' => $this->chiffreAffairesEncaisse($periode),
                'depenses' => $this->depensesCumulees($periode),
            ];
        }

        return $points;
    }

    /**
     * Ventilation du chiffre d'affaires **par activité**, sur la période.
     *
     * ## ⚠ Ce n'est PAS la mesure du prototype, et l'écart est délibéré
     *
     * `tableau-de-bord.js` compte les **réservations** qui contiennent chaque
     * service (`compteurs[s]++`). Cette mesure n'existe pas ici : le schéma
     * serveur ne porte aucun service sur `reservations` — c'est une table du
     * client Flutter (PA-110), pas du serveur. La compter reviendrait à
     * l'inventer.
     *
     * Ce qui existe, et qui répond mieux à la question posée par un tableau de
     * bord : `lignes_facture.source_module` porte l'activité d'origine de
     * chaque ligne facturée (RG-04). On ventile donc des **montants
     * facturés**, pas des occurrences — « le bar représente 12 % du chiffre »
     * dit davantage que « le bar apparaît dans 7 réservations ».
     *
     * Les avoirs viennent en diminution : leurs lignes portent des montants
     * négatifs au registre, et les exclure gonflerait l'activité concernée
     * d'un chiffre annulé.
     *
     * @return list<array{module: string, montant: string}>
     */
    public function ventilationParActivite(Periode $periode): array
    {
        $lignes = DB::table('lignes_facture')
            ->join('factures', 'lignes_facture.facture_id', '=', 'factures.id')
            ->whereBetween('factures.date_emission', [$periode->debut, $periode->fin])
            ->groupBy('lignes_facture.source_module')
            ->selectRaw('lignes_facture.source_module AS module, COALESCE(SUM(lignes_facture.montant), 0) AS total')
            ->orderByDesc('total')
            ->get();

        return $lignes
            ->map(fn (object $ligne): array => [
                'module' => (string) $ligne->module,
                'montant' => $this->montant($ligne->total),
            ])
            ->all();
    }

    /**
     * Un `SUM()` vide renvoie `0` et non `0.00`, et MySQL rend les agrégats
     * `DECIMAL` sous forme de chaîne. On normalise via `bcadd` et **jamais**
     * `number_format`, qui repasserait par un flottant — la conversion même
     * que la règle projet interdit sur un montant.
     */
    private function montant(mixed $valeur): string
    {
        return bcadd((string) ($valeur ?? '0'), '0', self::PRECISION);
    }
}
