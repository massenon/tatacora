<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Services;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\CommandeRestaurantService;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Registre unique des ventes encaissées — point d'entrée UNIQUE d'écriture.
 *
 * ## Le défaut corrigé (PA-159, lot 0b, T1)
 *
 * Deux registres de ventes coexistaient et ne se rencontraient jamais.
 * `HistoriqueVentes` lisait `ventes` pendant que `PosComptant` écrivait
 * `ventes_bar`. Le journal de caisse n'affichait donc que ce qu'avait posé le
 * seeder : trois lignes de démonstration, immuables, pendant que les vraies
 * ventes s'accumulaient ailleurs. Personne ne voyait rien manquer — l'écran
 * était plein.
 *
 * Ce service écrit le registre que l'historique lit. `VenteBarService` reste
 * en place et garde son rôle : la vente au comptoir du seul bar, avec sa
 * session de caisse (EF-M5-06). Les deux ne doivent jamais être appelés pour
 * le MÊME encaissement, sans quoi le défaut reviendrait à l'envers — un même
 * argent compté deux fois.
 *
 * ## Multi-modules par nature
 *
 * Une vente au comptoir mélange des boissons (M5) et des plats (M4) sur le
 * même ticket. Le module est estampillé sur la LIGNE au moment de
 * l'encaissement, jamais déduit après coup de sa catégorie
 * (`ventes-engine.js` l.267-273) : deviner sur une donnée financière est ce
 * que ce dépôt s'interdit.
 *
 * ## Prix et libellé FIGÉS à l'encaissement
 *
 * Ils sont recopiés du catalogue au moment de la vente, jamais relus à
 * l'affichage — même raisonnement que `tarifNuit` (PA-55) et que les lignes de
 * panier (PA-98). Ils ne sont **jamais** acceptés depuis l'appelant : un prix
 * transmis par l'écran ressusciterait l'anti-pattern « montant saisi » que
 * PA-24 condamne.
 *
 * ## Idempotence : c'est l'UUID du client, pas le numéro
 *
 * `id` est fourni par le client (offline-first). Un second appel avec le même
 * `id` rend la vente existante **sans allouer de numéro** : allouer à chaque
 * tentative brûlerait la séquence à chaque coupure réseau, comme le test que
 * PA-101 a corrigé côté Flutter.
 *
 * ## RG-05 : deux chemins, jamais deux déductions
 *
 * Les lignes M5 sortent du stock ici, par `MouvementStockService`, avec la
 * conversion de conditionnement de la carte. Les lignes M4 passent par
 * `CommandeRestaurantService` — c'est **la transmission en cuisine** qui
 * engage les denrées, pas l'encaissement. Quand la vente référence une
 * commande déjà transmise, rien n'est déduit ici et la raison est écrite dans
 * `stock_non_impacte` : sans elle, un ticket sans mouvement de stock se lirait
 * comme un défaut.
 *
 * ## Une vente sans écriture comptable n'est plus enregistrée du tout
 *
 * Règle du Product Owner du 31/08/2026 : tout mouvement d'argent produit son
 * écriture comptable réelle, côté domaine, dans la MÊME transaction. Si la
 * pièce est refusée, rien n'est écrit — ni la vente, ni ses lignes, ni la
 * sortie de stock — et le caissier voit pourquoi.
 *
 * C'est le raisonnement de `DepenseService`, et il vaut à l'identique ici :
 * les causes de refus — journal, compte, exercice ou centre de coût — sont
 * toutes **locales et corrigibles**, jamais la panne d'un service tiers.
 * Enregistrer quand même reproduirait le défaut que PA-159 a corrigé sur les
 * dépenses, sous une forme plus douce : un ticket imprimé, une caisse qui se
 * remplit, une comptabilité qui l'ignore.
 *
 * ## Le sens de la pièce
 *
 * Un débit unique — la trésorerie encaissée, ou le compte client quand la
 * consommation est portée sur la note de chambre — et un crédit par MODULE,
 * sur son compte de produits de classe 7. La ventilation par module n'est pas
 * une commodité d'affichage : c'est ce qui permet au compte de résultat de
 * distinguer le bar du restaurant, sur la seule donnée fiable dont on
 * dispose — le module estampillé sur la ligne à l'encaissement.
 *
 * @see EF-M5-06 Vente au comptoir du bar
 * @see EF-M4-03 Prise de commande
 * @see EF-M10-02 Saisie des écritures comptables
 * @see RG-05 Sortie de stock automatique
 * @see RG-06 Blocage au-delà du disponible
 * @see RG-11 Immutabilité — une annulation contre-passe, elle n'efface rien
 * @see RG-15 Journalisation — `utilisateur_id` est une vraie clé étrangère
 */
class VenteService
{
    private const PRECISION = 2;

    private const PREFIXE_NUMERO = 'V';

    private const TYPE_POINT_BAR = 'bar';

    /**
     * @var array<string, string>
     */
    public const MODES_PAIEMENT = [
        'especes' => 'Espèces',
        'mobile_money' => 'Mobile Money',
        'carte' => 'Carte bancaire',
        'virement' => 'Virement',
        'note_chambre' => 'Porté sur la note de chambre',
    ];

    /**
     * @var array<string, string>
     */
    public const MODULES = [
        'M1' => 'Hébergement',
        'M4' => 'Restaurant',
        'M5' => 'Bar',
        'M8' => 'Véhicules',
        'M9' => 'Tourisme',
    ];

    /**
     * Modules réellement encaissables ici, parce qu'ils ont un catalogue
     * serveur d'où figer un prix et un libellé.
     *
     * Les trois autres modules de `MODULES` restent nommés — le registre décrit
     * ce qu'une ligne PEUT porter, y compris ce qui viendra — mais un
     * encaissement les refuse. Les accepter obligerait l'écran à transmettre
     * un prix au clavier, exactement l'anti-pattern PA-24. Le jour où M1, M8
     * et M9 auront leur catalogue, il n'y aura qu'à les ajouter ici.
     *
     * @var list<string>
     */
    public const MODULES_ENCAISSABLES = ['M4', 'M5'];

    /**
     * Journal d'imputation des ventes.
     *
     * `MODULE_COMPTABILITE_COMPLET.md` §2 déclare cinq journaux, dont « VTE —
     * Journal des ventes ». Imputer les encaissements au journal de caisse
     * (CAI) ou de banque (BQ) selon le mode de paiement, comme le fait
     * `DepenseService` pour les sorties, laisserait le journal des ventes
     * VIDE pour toujours — un journal déclaré au référentiel et alimenté par
     * personne. C'est un choix d'organisation, signalé au Comptable, et il se
     * change ici, à un seul endroit.
     */
    public const JOURNAL = 'VTE';

    /**
     * Contrepartie de DÉBIT par mode de paiement — code de trésorerie, jamais
     * un numéro de compte recopié.
     *
     * Les numéros font foi chez `DepenseService::TRESORERIES` et nulle part
     * ailleurs : deux listes de comptes de trésorerie finiraient par diverger,
     * et l'écart ne se verrait qu'au rapprochement bancaire. On désigne donc
     * la trésorerie, on ne la redéfinit pas.
     *
     * `note_chambre` est absent de ce registre **et ce n'est pas un oubli** :
     * aucune trésorerie ne bouge, la consommation devient une créance client
     * ({@see self::COMPTE_CLIENTS}). Débiter la caisse pour une note de
     * chambre gonflerait le fond de caisse d'un argent que personne n'a remis.
     *
     * @var array<string, string>
     */
    public const CONTREPARTIES_TRESORERIE = [
        'especes' => 'caisse',
        'mobile_money' => 'momo',
        'carte' => 'banque',
        'virement' => 'banque',
    ];

    /**
     * Compte de tiers d'une consommation portée sur la note de chambre —
     * `ATELIER_PLAN_COMPTABLE.md` §4, « 4111 Clients ».
     */
    public const COMPTE_CLIENTS = ComptesSyscohada::CLIENTS;

    /**
     * Comptes de produits par module — `ATELIER_PLAN_COMPTABLE.md` §2.
     *
     * Ce registre couvre exactement {@see self::MODULES_ENCAISSABLES} : y
     * inscrire M1, M8 et M9 aujourd'hui produirait trois entrées qu'aucun
     * chemin n'atteint. Le plan documenté les porte déjà (hébergement sur 7061, location de véhicules sur 7073 ;
     * le plan du PO n'a pas de compte dédié aux circuits touristiques) : le jour
     * où ces modules deviennent encaissables, il n'y a qu'à les ajouter ici.
     *
     * @var array<string, string>
     */
    /**
     * SYSCOHADA `443` « État, TVA facturée » — au plan depuis le 01/09/2026
     * (décision PO : prix TTC, TVA 18 % ; recommandation d'expertise
     * comptable). La part TVA de chaque vente s'y crédite quand la TVA est
     * active ; le compte fait foi ici et dans `ComptabiliteReferentielSeeder`.
     */
    public const COMPTE_TVA_FACTUREE = ComptesSyscohada::TVA_FACTUREE_BIENS;

    /**
     * TVA facturée par module : boissons revendues (M5) sur 4431, prestations
     * servies (M4, repas) sur 4432 — table `ComptesSyscohada`, à valider par
     * le comptable.
     *
     * @var array<string, string>
     */
    public const COMPTES_TVA = [
        'M4' => ComptesSyscohada::TVA_FACTUREE_PRESTATIONS,
        'M5' => ComptesSyscohada::TVA_FACTUREE_BIENS,
    ];

    /**
     * Centre de coût de chaque module : les comptes de produit 7061/7011 ne
     * distinguent plus restaurant et bar, le centre le fait (RG-12).
     *
     * @var array<string, string>
     */
    public const CENTRES_PAR_MODULE = [
        'M4' => 'Restaurant',
        'M5' => 'Bar',
    ];

    public const COMPTES_PRODUIT = [
        'M4' => ComptesSyscohada::PRODUIT_PRESTATIONS,
        'M5' => ComptesSyscohada::PRODUIT_MARCHANDISES,
    ];

    private const MODE_NOTE_CHAMBRE = 'note_chambre';

    /**
     * Les modes de règlement du COMPTOIR — directive PO du 02/09/2026 :
     * « Porté sur la note de chambre » n'a de sens qu'au POS des clients
     * hébergés (aucune chambre au comptoir). DÉRIVÉ de `MODES_PAIEMENT`,
     * jamais une seconde liste écrite à la main : un mode ajouté au registre
     * apparaît au comptoir sans qu'on y pense, et l'exclusion reste unique.
     *
     * @return array<string, string>
     */
    public static function modesPaiementComptoir(): array
    {
        return array_diff_key(self::MODES_PAIEMENT, [self::MODE_NOTE_CHAMBRE => null]);
    }

    /** Le mode « note de chambre » est-il celui-ci ? — pour le refus du comptoir. */
    public static function estModeNoteChambre(string $mode): bool
    {
        return $mode === self::MODE_NOTE_CHAMBRE;
    }

    public function __construct(
        private readonly MouvementStockService $mouvements,
        private readonly CommandeRestaurantService $commandes,
        private readonly SequenceDocumentService $sequences,
        private readonly PasserEcritureService $ecritures,
        private readonly CalculTvaService $tva,
    ) {
    }

    /**
     * Enregistre une vente encaissée, ses lignes et ses sorties de stock.
     *
     * ## Remise (directive PO du 02/09/2026)
     *
     * `remise_type`/`remise_valeur` viennent du PANIER clôturé (le motif de
     * `reservations`) : le montant encaissé — `montant_total`, la pièce
     * comptable, le théorique de caisse — est le NET, dérivé par l'auteur
     * unique {@see Panier::remiseSur()} (bornes comprises : un net négatif
     * refuse ici, jamais un montant plausible). Les LIGNES restent au prix
     * brut figé du catalogue : le ticket montre les lignes, la remise, puis
     * le net — jamais des prix unitaires réécrits.
     *
     * @param  array{id?: string, point_vente?: string, session_id?: string|null, client_id?: string|null, client_mention?: string|null, table?: string|null, table_id?: string|null, mode_paiement?: string, remise_type?: string, remise_valeur?: string, utilisateur_id?: string|null, commande_id?: string|null, validation_rupture?: bool, lignes?: list<array{module: string, reference_id: string, quantite: int|string}>}  $donnees
     *
     * @throws RuntimeException panier vide, mode de paiement ou module inconnu,
     *                          quantité non positive, remise hors bornes,
     *                          référence de catalogue introuvable,
     *                          ou pièce comptable refusée (journal, compte, exercice, centre)
     * @throws \App\Domain\Stocks\Exceptions\RuptureStockException
     * @throws \App\Domain\Restaurant\Exceptions\RecetteManquanteException
     */
    public function enregistrer(array $donnees): Vente
    {
        $lignes = $donnees['lignes'] ?? [];

        if ($lignes === []) {
            throw new RuntimeException(__('ventes.panier_vide'));
        }

        $modePaiement = (string) ($donnees['mode_paiement'] ?? 'especes');

        if (! array_key_exists($modePaiement, self::MODES_PAIEMENT)) {
            throw new RuntimeException(__('ventes.mode_paiement_inconnu', ['mode' => $modePaiement]));
        }

        $identifiant = (string) ($donnees['id'] ?? (string) \Illuminate\Support\Str::uuid());

        // Idempotence AVANT toute allocation : une reprise après coupure ne
        // doit ni créer un doublon ni consommer un numéro.
        $existante = Vente::find($identifiant);

        if ($existante !== null) {
            return $existante;
        }

        $resolues = $this->resoudreLignes($lignes);

        // Le total est arrêté AVANT la transaction, depuis les lignes
        // résolues : la pièce comptable en a besoin, et il n'a jamais été
        // saisi par le caissier — c'est le catalogue qui le porte.
        $total = $this->totaliser($resolues);

        // La remise dérive de L'UNIQUE formule (`Panier::remiseSur()`),
        // jamais d'une seconde arithmétique ici : hors bornes, elle REFUSE
        // avant toute écriture.
        $remise = \App\Domain\Ventes\Models\Panier::remiseSur(
            $total,
            (string) ($donnees['remise_type'] ?? \App\Domain\Ventes\Models\Panier::REMISE_AUCUNE),
            (string) ($donnees['remise_valeur'] ?? '0.00'),
        );
        $net = bcsub($total, $remise, self::PRECISION);

        // La pièce porte le NET encaissé : la ventilation brute par module est
        // ramenée au net, dernier module ajusté pour un équilibre exact.
        $ventilation = self::ventilerAuNet($this->ventilerParModule($resolues), $total, $net);
        $compteContrepartie = $this->compteDeContrepartie($modePaiement);

        return DB::transaction(function () use (
            $donnees,
            $resolues,
            $modePaiement,
            $identifiant,
            $net,
            $ventilation,
            $compteContrepartie
        ): Vente {
            // Le numéro est alloué DANS la transaction : `suivant()` lit le
            // maximum sous verrou sur cette même table, donc un rejet plus bas
            // le rend réellement à la séquence.
            $numero = $this->sequences->suivant('ventes', self::PREFIXE_NUMERO);

            // La pièce est passée D'ABORD, comme dans `DepenseService` : si
            // elle est refusée, ni la vente, ni ses lignes, ni la sortie de
            // stock n'existent — et le caissier reçoit la raison comptable.
            $piece = $this->ecritures->passerEtValider([
                'journal' => self::JOURNAL,
                'date' => now()->toDateString(),
                'libelle' => $this->libelleDeLaPiece($numero),
                'lignes' => $this->lignesDeLaPiece($ventilation, $compteContrepartie, $net),
            ]);

            $vente = Vente::create([
                'id' => $identifiant,
                'numero' => $numero,
                'session_id' => $donnees['session_id'] ?? null,
                'point_vente' => (string) ($donnees['point_vente'] ?? 'Bar'),
                'client_id' => $donnees['client_id'] ?? null,
                // MENTION imprimée, jamais une FK — décision PO du 02/09/2026,
                // vente au comptoir anonyme par nature : ce nom n'alimente
                // aucun registre client (voir la migration du 07/09).
                'client_mention' => blank($donnees['client_mention'] ?? null)
                    ? null
                    : trim((string) $donnees['client_mention']),
                'table' => $donnees['table'] ?? null,
                'table_id' => $donnees['table_id'] ?? null,
                // Le NET après remise : c'est l'argent réellement encaissé —
                // le théorique de caisse et la pièce comptable le lisent.
                'montant_total' => $net,
                'mode_paiement' => $modePaiement,
                // Une note de chambre n'est pas encaissée : c'est une créance
                // client, réglée au check-out. La confondre avec un
                // encaissement fausserait la caisse ET le suivi des créances.
                'encaisse' => $modePaiement !== self::MODE_NOTE_CHAMBRE,
                'statut' => 'validee',
                'utilisateur_id' => $donnees['utilisateur_id'] ?? auth()->id(),
                'ecriture_id' => $this->ligneDeContrepartie($piece),
            ]);

            foreach ($resolues as $ligne) {
                LigneVente::create([
                    'vente_id' => $vente->id,
                    'code' => $ligne['reference_id'],
                    'nom' => $ligne['nom'],
                    'categorie' => $ligne['categorie'],
                    'module' => $ligne['module'],
                    'prix_unitaire' => $ligne['prix_unitaire'],
                    'quantite' => $ligne['quantite'],
                    'montant' => $ligne['montant'],
                ]);
            }

            $nonImpacte = $this->deduireStock($vente, $resolues, $donnees);

            $vente->update([
                // Tableau vide plutôt que `null` : « rien à signaler » et
                // « jamais renseigné » ne doivent pas se ressembler.
                'stock_non_impacte' => $nonImpacte,
            ]);

            return $vente->refresh();
        });
    }

    /**
     * Rattrapage : passe la pièce d'une vente qui n'en a pas.
     *
     * Sert les ventes écrites avant le 31/08/2026, quand aucune écriture
     * n'était produite — et les trois ventes de démonstration, posées en
     * direct par `VentesSeeder` pour ne pas vider le stock semé. Une vente
     * déjà comptabilisée est rendue telle quelle : la repasser créerait une
     * seconde pièce pour le même argent.
     *
     * Une vente ANNULÉE est refusée. Lui passer sa pièce aujourd'hui
     * créditerait un compte de produits pour un chiffre d'affaires qui n'a
     * pas eu lieu, et la contre-passation qui aurait dû l'équilibrer est
     * derrière nous : le grand livre garderait un produit fantôme.
     *
     * @throws RuntimeException vente annulée, ou pièce refusée
     */
    public function comptabiliser(Vente $vente): Vente
    {
        if ($vente->estComptabilisee()) {
            return $vente;
        }

        if ($vente->estAnnulee()) {
            throw new RuntimeException(__('ventes.comptabilisation_sur_annulee', [
                'numero' => $vente->numero,
            ]));
        }

        $lignes = $vente->lignes()->get()
            ->map(fn (LigneVente $ligne): array => [
                'module' => (string) $ligne->module,
                'montant' => (string) $ligne->montant,
            ])
            ->all();

        if ($lignes === []) {
            throw new RuntimeException(__('ventes.panier_vide'));
        }

        // Une vente à remise (02/09/2026) porte un `montant_total` NET plus
        // petit que la somme de ses lignes : la ventilation est ramenée au
        // net ici aussi, sans quoi la pièce de rattrapage ne s'équilibrerait
        // pas et serait refusée en bloc.
        $ventilation = self::ventilerAuNet(
            $this->ventilerParModule($lignes),
            $this->totaliser(array_map(
                static fn (array $ligne): array => ['montant' => $ligne['montant']],
                $lignes,
            )),
            (string) $vente->montant_total,
        );
        $compteContrepartie = $this->compteDeContrepartie($vente->mode_paiement);

        return DB::transaction(function () use ($vente, $ventilation, $compteContrepartie): Vente {
            $piece = $this->ecritures->passerEtValider([
                'journal' => self::JOURNAL,
                // La date de la VENTE, jamais celle du rattrapage : une pièce
                // datée d'aujourd'hui rangerait un encaissement de la semaine
                // dernière dans le mauvais mois, et le compte de résultat
                // mensuel s'en trouverait faux des deux côtés.
                'date' => $vente->created_at->toDateString(),
                'libelle' => $this->libelleDeLaPiece($vente->numero),
                'lignes' => $this->lignesDeLaPiece(
                    $ventilation,
                    $compteContrepartie,
                    (string) $vente->montant_total,
                ),
            ]);

            $vente->update(['ecriture_id' => $this->ligneDeContrepartie($piece)]);

            return $vente->refresh();
        });
    }

    /**
     * Annulation — la vente conserve sa trace et son numéro (RG-02).
     *
     * Les sorties de stock sont compensées par des ENTRÉES non valorisées, pas
     * effacées : supprimer les mouvements rendrait la fiche de stock
     * incompréhensible et l'inventaire invérifiable. Sans coût unitaire —
     * aucun achat n'a eu lieu, recalculer le CMP créerait de la valeur ex
     * nihilo.
     *
     * Les lignes M4 passées par une commande transmise ne sont PAS compensées,
     * et la raison est celle de `CommandeRestaurantService::annuler()` : après
     * transmission, les denrées sont dans la casserole. Leur retour éventuel
     * est un mouvement de `perte` décidé par un responsable, pas un effet de
     * bord d'une annulation de ticket.
     *
     * ## Côté comptabilité : contre-passation, jamais suppression (RG-11)
     *
     * La pièce d'origine reste au grand livre et une pièce inverse s'y ajoute.
     * Une vente ANTÉRIEURE au 31/08/2026 n'a pas de pièce (`ecriture_id` à
     * NULL) : il n'y a alors rien à contre-passer, et l'annulation le constate
     * plutôt que d'inventer une écriture pour un argent que la comptabilité
     * n'a jamais vu entrer.
     */
    public function annuler(Vente $vente, string $motif): Vente
    {
        if ($vente->estAnnulee()) {
            throw new RuntimeException(__('ventes.deja_annulee', ['numero' => $vente->numero]));
        }

        return DB::transaction(function () use ($vente, $motif): Vente {
            if ($vente->estComptabilisee()) {
                $this->ecritures->contrepasserPiece(
                    $this->pieceDeLaVente($vente),
                    __('ventes.libelle_contrepassation', ['numero' => $vente->numero]),
                );
            }

            $pointBar = $this->pointBar();

            foreach ($vente->lignes()->get() as $ligne) {
                if ($ligne->module !== 'M5') {
                    continue;
                }

                $boisson = CarteBoisson::find($ligne->code);

                if ($boisson === null) {
                    // Boisson retirée de la carte depuis la vente : le
                    // mouvement d'origine reste au grand livre du stock, sa
                    // compensation est impossible sans son article. Taire le
                    // cas laisserait croire à une compensation complète.
                    continue;
                }

                $this->mouvements->entree(
                    articleId: $boisson->article_id,
                    pointId: $pointBar->id,
                    quantite: $this->mouvements->arrondirQuantite(
                        $boisson->stockConsommePour((string) $ligne->quantite),
                    ),
                    motif: __('ventes.motif_annulation_stock', ['numero' => $vente->numero]),
                );
            }

            $vente->update([
                'statut' => 'annulee',
                'motif_annulation' => $motif,
                'annulee_at' => now(),
            ]);

            return $vente->refresh();
        });
    }

    /**
     * Construction de requête filtrée.
     *
     * @param  array<string, mixed>  $filtres
     * @return Builder<Vente>
     */
    public function filtrer(array $filtres = []): Builder
    {
        // `with('lignes')` : l'historique affiche le détail de chaque ticket,
        // et sans lui chaque ligne de la liste ferait sa propre requête (N+1).
        $query = Vente::query()->with('lignes')->orderByDesc('created_at');

        if (! empty($filtres['recherche'])) {
            $terme = mb_strtolower(trim((string) $filtres['recherche']));
            $query->where(function (Builder $sous) use ($terme): void {
                $sous->whereRaw('LOWER(numero) LIKE ?', ['%'.$terme.'%'])
                    ->orWhereRaw('LOWER(`table`) LIKE ?', ['%'.$terme.'%']);
            });
        }

        if (! empty($filtres['point'])) {
            $query->where('point_vente', $filtres['point']);
        }

        if (! empty($filtres['mode'])) {
            $query->where('mode_paiement', $filtres['mode']);
        }

        if (! empty($filtres['statut'])) {
            $query->where('statut', $filtres['statut']);
        }

        if (! empty($filtres['debut'])) {
            $query->whereDate('created_at', '>=', $filtres['debut']);
        }

        if (! empty($filtres['fin'])) {
            $query->whereDate('created_at', '<=', $filtres['fin']);
        }

        if (! empty($filtres['activite'])) {
            $query->whereHas('lignes', function (Builder $sous) use ($filtres): void {
                $sous->where('module', $filtres['activite']);
            });
        }

        return $query;
    }

    /**
     * Résout chaque ligne contre son catalogue et fige prix et libellé.
     *
     * Résolution faite AVANT la transaction : une référence introuvable est
     * une erreur de saisie, pas une condition de course, et la découvrir après
     * avoir alloué un numéro le brûlerait pour rien.
     *
     * @param  list<array<string, mixed>>  $lignes
     * @return list<array<string, mixed>>
     */
    private function resoudreLignes(array $lignes): array
    {
        $resolues = [];

        foreach ($lignes as $ligne) {
            $module = (string) $ligne['module'];

            if (! in_array($module, self::MODULES_ENCAISSABLES, true)) {
                throw new RuntimeException(__('ventes.module_non_encaissable', [
                    'module' => self::MODULES[$module] ?? $module,
                ]));
            }

            $quantite = (int) $ligne['quantite'];

            if ($quantite < 1) {
                // Une quantité saisie à zéro ne devient jamais une unité
                // facturée — le piège que le client Flutter nomme
                // explicitement (PA-98, `QuantiteSaisie`).
                throw new RuntimeException(__('ventes.quantite_minimale'));
            }

            $reference = (string) $ligne['reference_id'];

            $resolues[] = $module === 'M5'
                ? $this->resoudreBoisson($reference, $quantite)
                : $this->resoudrePlat($reference, $quantite);
        }

        return $resolues;
    }

    /**
     * @return array<string, mixed>
     */
    private function resoudreBoisson(string $reference, int $quantite): array
    {
        $boisson = CarteBoisson::find($reference);

        if ($boisson === null) {
            throw new RuntimeException(__('ventes.reference_inconnue', ['reference' => $reference]));
        }

        $prix = (string) $boisson->prix_vente;

        return [
            'module' => 'M5',
            'reference_id' => $boisson->id,
            'nom' => $boisson->libelle,
            'categorie' => $boisson->categorie,
            'prix_unitaire' => $prix,
            'quantite' => $quantite,
            'montant' => bcmul($prix, (string) $quantite, self::PRECISION),
            'article_id' => $boisson->article_id,
            'stock' => $this->mouvements->arrondirQuantite(
                $boisson->stockConsommePour((string) $quantite),
            ),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function resoudrePlat(string $reference, int $quantite): array
    {
        $plat = Plat::find($reference);

        if ($plat === null) {
            throw new RuntimeException(__('ventes.reference_inconnue', ['reference' => $reference]));
        }

        $prix = (string) $plat->prix_vente;

        return [
            'module' => 'M4',
            'reference_id' => $plat->id,
            'nom' => $plat->libelle,
            'categorie' => $plat->categorie,
            'prix_unitaire' => $prix,
            'quantite' => $quantite,
            'montant' => bcmul($prix, (string) $quantite, self::PRECISION),
        ];
    }

    /**
     * RG-05 — sorties de stock, chacune par le service qui en a la charge.
     *
     * @param  list<array<string, mixed>>  $resolues
     * @param  array<string, mixed>  $donnees
     * @return list<array{ligne: string, module: string, motif: string}>
     */
    private function deduireStock(Vente $vente, array $resolues, array $donnees): array
    {
        $validationRupture = (bool) ($donnees['validation_rupture'] ?? false);
        $commandeId = $donnees['commande_id'] ?? null;
        $nonImpacte = [];

        $lignesBar = array_values(array_filter($resolues, fn (array $l): bool => $l['module'] === 'M5'));
        $lignesRestaurant = array_values(array_filter($resolues, fn (array $l): bool => $l['module'] === 'M4'));

        if ($lignesBar !== []) {
            $pointBar = $this->pointBar();

            foreach ($lignesBar as $ligne) {
                $this->mouvements->sortie(
                    articleId: (string) $ligne['article_id'],
                    pointId: $pointBar->id,
                    quantite: (string) $ligne['stock'],
                    motif: __('ventes.motif_sortie_stock', [
                        'numero' => $vente->numero,
                        'article' => $ligne['nom'],
                    ]),
                    validationRupture: $validationRupture,
                );
            }
        }

        if ($lignesRestaurant === []) {
            return $nonImpacte;
        }

        if ($commandeId !== null) {
            // Le stock est sorti à la transmission en cuisine, pas ici. La
            // vente le DIT : un ticket sans mouvement de stock se lirait
            // autrement comme un défaut de déduction.
            $commande = CommandeRestaurant::findOrFail((string) $commandeId);

            foreach ($lignesRestaurant as $ligne) {
                $nonImpacte[] = [
                    'ligne' => (string) $ligne['nom'],
                    'module' => 'M4',
                    'motif' => __('ventes.stock_deja_sorti_commande', ['commande' => $commande->id]),
                ];
            }

            return $nonImpacte;
        }

        // Pas de commande préalable : le plat est composé au comptoir. La
        // commande est créée ET transmise, parce que c'est la transmission qui
        // engage les denrées (RG-05) et qui produit le bon de cuisine
        // (EF-M4-05). Réécrire la déduction ici en ferait une seconde source
        // de vérité, qui divergerait de M4 au premier changement de recette.
        $commande = $this->commandes->creer(
            lignes: array_map(
                fn (array $ligne): array => [
                    'plat_id' => (string) $ligne['reference_id'],
                    'quantite' => (int) $ligne['quantite'],
                ],
                $lignesRestaurant,
            ),
            clientId: $donnees['client_id'] ?? null,
            tableOuChambreId: $donnees['table_id'] ?? null,
        );

        $this->commandes->transmettreEnCuisine($commande, $validationRupture);

        return $nonImpacte;
    }

    // =====================================================================
    // La pièce comptable — règle du 31/08/2026
    // =====================================================================

    /**
     * Libellé porté par TOUTES les lignes de la pièce d'une vente.
     *
     * Il est identique d'une ligne à l'autre, et c'est délibéré : faute
     * d'identifiant de pièce au schéma (PA-52), ce libellé est le seul lien
     * qui rassemble les lignes d'un même encaissement. Le numéro de vente
     * étant unique par la séquence, il suffit à discriminer — {@see
     * self::pieceDeLaVente()} l'utilise, et vérifie sa trouvaille.
     */
    private function libelleDeLaPiece(string $numero): string
    {
        return __('ventes.libelle_ecriture', ['numero' => $numero]);
    }

    /**
     * Les lignes de la pièce : la contrepartie au débit, les produits au crédit.
     *
     * @param  array<string, string>  $ventilation module => montant
     * @return list<array<string, mixed>>
     *
     * @throws RuntimeException TVA assujettie (aucun compte de collecte au plan),
     *                          ou module sans compte de produits
     */
    private function lignesDeLaPiece(array $ventilation, string $compteContrepartie, string $total): array
    {
        /*
         * LA LACUNE DE TVA COLLECTÉE EST COMBLÉE (01/09/2026) — décision du
         * Product Owner (« les prix du catalogue sont TTC, la TVA est 18 % »),
         * appliquée sur recommandation d'expertise comptable : le compte
         * SYSCOHADA `4431` « État, TVA facturée » est au plan
         * (`ComptabiliteReferentielSeeder`). Le refus antérieur — jamais
         * créditer la totalité aux produits pendant que l'établissement est
         * assujetti — devient le CALCUL qu'il protégeait : chaque montant du
         * catalogue (TTC par convention) se ventile par `CalculTvaService` —
         * jamais une seconde formule ici — en part HT au compte de produits
         * du module et part TVA, cumulée sur `4431`.
         *
         * La part TVA de chaque module est la DIFFÉRENCE ttc − ht, jamais un
         * second arrondi : c'est ce qui garantit l'équilibre exact de la
         * pièce (somme des crédits = débit de contrepartie), centime par
         * centime, quel que soit le nombre de modules.
         *
         * Si `4431` disparaissait du plan, `PasserEcritureService::compte()`
         * refuserait la pièce entière et rien ne serait écrit — le refus de
         * PA-162 reste le filet, il n'est plus le chemin nominal.
         */
        $tvaActive = $this->tva->estActive();

        $piece = [];

        $piece[] = [
            'compte' => $compteContrepartie,
            'debit' => $total,
            'credit' => '0.00',
        ];

        $tvaParCompte = [];
        $centres = [];

        foreach ($ventilation as $module => $montant) {
            $compte = self::COMPTES_PRODUIT[$module] ?? null;

            if ($compte === null) {
                throw new RuntimeException(__('ventes.compte_produit_absent', [
                    'module' => self::MODULES[$module] ?? $module,
                ]));
            }

            $credit = $montant;

            if ($tvaActive) {
                $ht = $this->tva->ventiler($montant)['ht'];
                $compteTva = self::COMPTES_TVA[$module];
                $tvaParCompte[$compteTva] = bcadd(
                    $tvaParCompte[$compteTva] ?? '0.00',
                    bcsub($montant, $ht, self::PRECISION),
                    self::PRECISION,
                );
                $credit = $ht;
            }

            $piece[] = [
                'compte' => $compte,
                'debit' => '0.00',
                'credit' => $credit,
                'centre_id' => $this->centreDuModule($module),
            ];
        }

        foreach ($tvaParCompte as $compteTva => $tva) {
            if (bccomp($tva, '0.00', self::PRECISION) > 0) {
                $piece[] = [
                    'compte' => (string) $compteTva,
                    'debit' => '0.00',
                    'credit' => $tva,
                ];
            }
        }

        return $piece;
    }

    /**
     * Identifiant du centre de coût d'un module, ou null s'il n'existe pas :
     * `PasserEcritureService` refuse alors la ligne en nommant le compte.
     */
    private function centreDuModule(string $module): ?string
    {
        $libelle = self::CENTRES_PAR_MODULE[$module] ?? null;

        return $libelle === null ? null : CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    /**
     * Compte de débit d'une vente, selon le mode de paiement.
     *
     * @throws RuntimeException mode de paiement sans contrepartie déclarée
     */
    private function compteDeContrepartie(string $modePaiement): string
    {
        if ($modePaiement === self::MODE_NOTE_CHAMBRE) {
            return self::COMPTE_CLIENTS;
        }

        $tresorerie = self::CONTREPARTIES_TRESORERIE[$modePaiement] ?? null;

        if ($tresorerie === null) {
            // Inatteignable tant que `CONTREPARTIES_TRESORERIE` couvre les
            // quatre modes encaissés de `MODES_PAIEMENT` : si ce refus tombe,
            // c'est qu'un mode a été ajouté sans dire où va l'argent, et le
            // dire vaut mieux que de l'imputer à la caisse par défaut.
            throw new RuntimeException(__('ventes.contrepartie_absente', [
                'mode' => self::MODES_PAIEMENT[$modePaiement] ?? $modePaiement,
            ]));
        }

        return DepenseService::TRESORERIES[$tresorerie]['compte'];
    }

    /**
     * L'identifiant de la ligne de contrepartie de la pièce.
     *
     * Elle est reconnue à son SENS — dans une vente, la contrepartie est
     * l'unique débit, les produits sont tous au crédit — plutôt qu'à sa
     * position, qui n'est pas une garantie, ou à son compte, qui coûterait une
     * requête. Voir la note de la migration `2026_09_02_600000`.
     *
     * @param  EloquentCollection<int, EcritureComptable>  $piece
     */
    private function ligneDeContrepartie(EloquentCollection $piece): string
    {
        foreach ($piece as $ecriture) {
            if (bccomp((string) $ecriture->debit, '0.00', self::PRECISION) > 0) {
                return $ecriture->id;
            }
        }

        // Inatteignable tant que `lignesDeLaPiece()` ouvre par le débit : si ce
        // refus tombe un jour, c'est que la pièce a changé de forme, et le dire
        // vaut mieux que de rattacher la vente à une ligne de produits.
        throw new RuntimeException(__('ventes.ligne_contrepartie_absente'));
    }

    /**
     * Les lignes de la pièce d'une vente déjà écrite.
     *
     * ## Pourquoi une recherche par libellé, et ce qui la rend sûre
     *
     * `ecritures_comptables` n'a aucune colonne groupant les lignes d'une même
     * pièce (PA-52), et `ventes.ecriture_id` ne désigne qu'UNE ligne — la
     * contrepartie. Reconstituer la pièce demande donc un autre lien, et le
     * seul disponible est le libellé, qui porte le numéro de vente : unique
     * par la séquence, préfixé, jamais saisi par un opérateur.
     *
     * Ce n'est pas une recherche à l'aveugle : le résultat est VÉRIFIÉ — il
     * doit contenir la ligne que la vente désigne, et être équilibré. Sans ce
     * contrôle, une pièce partiellement retrouvée serait contre-passée à
     * moitié, et le grand livre resterait faux du reste, en silence.
     *
     * @return EloquentCollection<int, EcritureComptable>
     *
     * @throws RuntimeException pièce introuvable, incomplète ou déséquilibrée
     */
    private function pieceDeLaVente(Vente $vente): EloquentCollection
    {
        $piece = EcritureComptable::query()
            ->where('libelle', $this->libelleDeLaPiece($vente->numero))
            // Les inverses d'une contre-passation antérieure portent leur
            // propre libellé ; ce filtre les écarte quand même, pour que le
            // jour où un motif serait omis ne double pas l'annulation.
            ->whereNull('ecriture_contrepassee_id')
            ->get();

        $contient = $piece->contains(
            fn (EcritureComptable $ecriture): bool => $ecriture->id === $vente->ecriture_id,
        );

        $debits = '0.00';
        $credits = '0.00';

        foreach ($piece as $ecriture) {
            $debits = bcadd($debits, (string) $ecriture->debit, self::PRECISION);
            $credits = bcadd($credits, (string) $ecriture->credit, self::PRECISION);
        }

        if (! $contient || bccomp($debits, $credits, self::PRECISION) !== 0) {
            throw new RuntimeException(__('ventes.piece_introuvable', [
                'numero' => $vente->numero,
            ]));
        }

        return $piece;
    }

    /**
     * Montants cumulés par module, dans l'ordre de `MODULES_ENCAISSABLES`.
     *
     * L'ordre est fixé plutôt que laissé à celui du panier : deux tickets
     * portant les mêmes articles doivent produire la même pièce, sans quoi
     * comparer deux journaux devient un exercice de tri.
     *
     * @param  list<array<string, mixed>>  $lignes chacune porte `module` et `montant`
     * @return array<string, string>
     */
    private function ventilerParModule(array $lignes): array
    {
        $cumuls = [];

        foreach ($lignes as $ligne) {
            $module = (string) $ligne['module'];
            $cumuls[$module] = bcadd(
                $cumuls[$module] ?? '0.00',
                (string) $ligne['montant'],
                self::PRECISION,
            );
        }

        $ordonnes = [];

        foreach (self::MODULES_ENCAISSABLES as $module) {
            if (isset($cumuls[$module])) {
                $ordonnes[$module] = $cumuls[$module];
                unset($cumuls[$module]);
            }
        }

        // Ce qui reste n'est pas encaissable : `lignesDeLaPiece()` le refusera
        // en nommant le module. Le jeter ici ferait passer une vente dont la
        // pièce n'équilibrerait pas — et l'équilibre est vérifié trop tard.
        return $ordonnes + $cumuls;
    }

    /**
     * Ramène la ventilation brute par module au NET encaissé (remise déduite).
     *
     * Chaque module cède sa quote-part de remise au prorata de son montant ;
     * le DERNIER module prend l'écart d'arrondi, pour que la somme des
     * crédits égale le débit de contrepartie centime par centime — même
     * garantie d'équilibre exact que la part TVA « différence, jamais un
     * second arrondi » de {@see lignesDeLaPiece()}.
     *
     * Sans remise (`net == brut`), la ventilation ressort inchangée.
     *
     * PUBLIC et statique : la facture du séjour (`PosHeberges`) ventile la
     * même remise sur les mêmes modules — une seconde proration écrite
     * ailleurs divergerait de la pièce comptable au premier centime d'arrondi.
     *
     * @param  array<string, string>  $ventilation module => montant brut
     * @return array<string, string> module => montant net
     */
    public static function ventilerAuNet(array $ventilation, string $totalBrut, string $net): array
    {
        if ($ventilation === [] || bccomp($totalBrut, $net, self::PRECISION) === 0
            || bccomp($totalBrut, '0.00', self::PRECISION) <= 0) {
            return $ventilation;
        }

        $nette = [];
        $resteNet = $net;
        $modules = array_keys($ventilation);
        $dernier = end($modules);

        foreach ($ventilation as $module => $montant) {
            if ($module === $dernier) {
                $nette[$module] = $resteNet;

                continue;
            }

            $part = bcdiv(bcmul($montant, $net, 4), $totalBrut, self::PRECISION);
            $nette[$module] = $part;
            $resteNet = bcsub($resteNet, $part, self::PRECISION);
        }

        return $nette;
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     */
    private function totaliser(array $lignes): string
    {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            $total = bcadd($total, (string) $ligne['montant'], self::PRECISION);
        }

        return $total;
    }

    private function pointBar(): PointStockage
    {
        $point = PointStockage::where('type', self::TYPE_POINT_BAR)->first();

        if ($point === null) {
            throw new RuntimeException(__('stocks.point_type_absent', ['type' => self::TYPE_POINT_BAR]));
        }

        return $point;
    }
}
