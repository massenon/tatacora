<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Services;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Models\LignePanier;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\Vente;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Le panier des deux points de vente — point d'entree UNIQUE d'ecriture.
 *
 * ## Le defaut corrige (PA-161, arbitrage (f) du 31/08/2026)
 *
 * Le panier des clients heberges vivait dans la SESSION HTTP, celui du
 * comptoir dans une propriete de composant Livewire. Les deux disparaissaient
 * au meme endroit : un changement d'equipe, un navigateur different, une
 * session expiree au bout de 120 minutes. Le client avait consomme, et plus
 * rien ne le portait — sur l'ecran meme qui promet un panier ouvert « de
 * l'arrivee au depart ». Le panier est desormais une table.
 *
 * ## R-a — « un seul panier ouvert par sejour », tenu ICI
 *
 * L'expression naturelle serait un index unique partiel : *unique sur
 * `reservation_id` la ou `statut = 'ouvert'`*. **MySQL ne connait pas les
 * index partiels**, et un index unique sur le couple entier interdirait un
 * second panier CLOTURE sur le meme sejour — c'est-a-dire le cas normal d'un
 * client qui consomme, se fait facturer, puis reconsomme.
 *
 * L'arbitrage retient donc l'option A de Q2 : **verrou pessimiste dans une
 * transaction**, exactement le patron de `VerificationChevauchementService`
 * pour RG-01, ou le CdCF prevoyait un `EXCLUDE USING gist` que MySQL n'a pas.
 * Deux ouvertures concurrentes sur le meme sejour se serialisent sur la ligne
 * `reservations` : la seconde attend, relit, et rend le panier de la premiere.
 *
 * ⚠ **Le comptoir n'a pas de ligne parente a verrouiller.** Une reservation
 * existe deja ; une « table de salle » n'existe pas au schema. Le verrou de
 * `ouvrirPourPoste()` porte donc sur la PLAGE d'index `(point_vente, table_id,
 * statut)` — un verrou de trou InnoDB, qui interdit l'insertion concurrente
 * dans la meme plage. C'est plus faible qu'un verrou de ligne, c'est ecrit ici
 * plutot que suppose, et c'est ce que le schema permet aujourd'hui : le jour
 * ou `tables_service` existera (§4.3 de la proposition), ce chemin prendra un
 * verrou de ligne comme l'autre.
 *
 * ## Prix et libelle FIGES a l'ajout — et jamais transmis par l'appelant
 *
 * `ajouterLigne()` recoit un MODULE et une REFERENCE, jamais un montant : le
 * catalogue est relu ici. Le maitre, lui, porte le prix dans le DOM
 * (`data-ajouter`) et le renvoie tel quel — le reprendre laisserait n'importe
 * qui appeler l'action avec le prix de son choix. C'est le meme raisonnement
 * que `VenteService`, une couche plus tot, et que `tarifNuit` (PA-55).
 *
 * ## Ce que ce service ne fait PAS, deliberement
 *
 * Il n'enregistre aucune vente, n'alloue aucun numero et ne touche aucun
 * stock : la cloture recoit une `Vente` deja produite par `VenteService`.
 * Ecrire ici une seconde logique de vente ferait diverger les deux au premier
 * changement de regle — le defaut que PA-159 a paye sur `ventes_bar`.
 *
 * ⚠ `paniers` n'est PAS au registre `TABLES_SYNCHRONISABLES` : rien de ce que
 * ce service ecrit ne part vers un autre poste. L'ecran dit « enregistre sur
 * ce poste » (PA-59/60/61).
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 (R-a a R-d), §8 (Q1, Q2)
 * @see RG-02 Aucune suppression — un panier se cloture
 * @see EF-M5-06 Vente au comptoir du bar
 * @see EF-M4-03 Prise de commande
 */
class PanierService
{
    private const PRECISION = 2;

    // =================================================================
    // LECTURE — aucune de ces methodes n'ecrit, et aucune ne verrouille
    // =================================================================

    public function panierOuvertDuSejour(string $reservationId): ?Panier
    {
        return Panier::query()
            ->with('lignes')
            ->where('reservation_id', $reservationId)
            ->where('statut', Panier::STATUT_OUVERT)
            ->first();
    }

    public function panierOuvertDuPoste(string $pointVente, ?string $tableId): ?Panier
    {
        return $this->requetePosteOuvert($pointVente, $tableId)->with('lignes')->first();
    }

    /**
     * Les paniers ouverts de plusieurs sejours, en UNE requete.
     *
     * L'ecran des clients heberges affiche un badge et un encours par sejour :
     * une requete par ligne rendrait la liste inutilisable des la haute saison.
     *
     * @param  list<string>  $reservationIds
     * @return Collection<string, Panier> indexee par `reservation_id`
     */
    public function paniersOuvertsDesSejours(array $reservationIds): Collection
    {
        if ($reservationIds === []) {
            return collect();
        }

        /** @var Collection<string, Panier> $paniers */
        $paniers = Panier::query()
            ->with('lignes')
            ->whereIn('reservation_id', $reservationIds)
            ->where('statut', Panier::STATUT_OUVERT)
            ->get()
            ->keyBy(fn (Panier $panier): string => (string) $panier->reservation_id);

        return $paniers;
    }

    /**
     * Tous les paniers comptant ouverts, indexes par table.
     *
     * La cle est le `table_id`, ou la chaine vide pour le comptoir — qui n'en
     * a pas. Elle vaut identifiant a elle seule : le plan de salle est un
     * registre ferme d'ecran, ou aucun identifiant ne se repete d'un espace a
     * l'autre.
     *
     * @return Collection<string, Panier>
     */
    public function paniersComptantOuverts(): Collection
    {
        /** @var Collection<string, Panier> $paniers */
        $paniers = Panier::query()
            ->with('lignes')
            ->where('type_vente', Panier::TYPE_COMPTANT)
            ->where('statut', Panier::STATUT_OUVERT)
            ->get()
            ->keyBy(fn (Panier $panier): string => (string) ($panier->table_id ?? ''));

        return $paniers;
    }

    /**
     * Les lignes du panier au format attendu par `VenteService::enregistrer()`
     * — ni prix ni libelle : il les figera lui-meme depuis le catalogue.
     *
     * Les lignes des modules non encaissables sont ecartees ici plutot que
     * refusees : elles ne peuvent pas entrer au panier (voir
     * {@see resoudre()}), donc ce filtre est une ceinture, pas une porte.
     *
     * @return list<array{module: string, reference_id: string, quantite: int}>
     */
    public function lignesPourVente(Panier $panier): array
    {
        $lignes = [];

        foreach ($panier->lignes as $ligne) {
            if (! in_array($ligne->module, VenteService::MODULES_ENCAISSABLES, true)) {
                continue;
            }

            $lignes[] = [
                'module' => (string) $ligne->module,
                'reference_id' => (string) $ligne->reference_id,
                'quantite' => (int) $ligne->quantite,
            ];
        }

        return $lignes;
    }

    // =================================================================
    // OUVERTURE — R-a, sous verrou pessimiste
    // =================================================================

    /**
     * Le panier ouvert du sejour, ou celui qu'on vient d'ouvrir.
     *
     * ⚠ Ce n'est PAS une lecture avec repli : la lecture et l'ecriture vivent
     * dans la MEME transaction, derriere un `lockForUpdate()` sur la ligne
     * `reservations`. Les separer laisserait deux caissiers ouvrir chacun leur
     * panier sur le meme sejour — et la facture finale en oublierait la
     * moitie, l'ecart n'apparaissant qu'a la reclamation du client.
     *
     * @throws RuntimeException sejour inconnu
     */
    public function ouvrirPourSejour(string $reservationId, string $pointVente, ?string $sessionId = null): Panier
    {
        return DB::transaction(function () use ($reservationId, $pointVente, $sessionId): Panier {
            // Le verrou porte sur la ligne PARENTE, comme
            // `VerificationChevauchementService` verrouille l'unite avant de
            // chercher un chevauchement.
            $reservation = Reservation::query()->whereKey($reservationId)->lockForUpdate()->first();

            if ($reservation === null) {
                throw new RuntimeException(__('ventes.sejour_inconnu'));
            }

            $existant = Panier::query()
                ->where('reservation_id', $reservationId)
                ->where('statut', Panier::STATUT_OUVERT)
                ->first();

            if ($existant !== null) {
                return $existant;
            }

            return Panier::create([
                'reservation_id' => $reservationId,
                'type_vente' => Panier::TYPE_SEJOUR,
                'point_vente' => $pointVente,
                'table_id' => null,
                'session_id' => $sessionId,
                'statut' => Panier::STATUT_OUVERT,
            ]);
        });
    }

    /**
     * Le panier ouvert de ce poste, ou celui qu'on vient d'ouvrir.
     *
     * `$sessionId` est la caisse OUVERTE au moment ou le panier nait, pas
     * celle qui l'encaissera : les deux peuvent differer, et c'est precisement
     * ce que ce lot rend possible. `ventes.session_id`, lui, porte le tiroir
     * qui a reellement encaisse.
     */
    public function ouvrirPourPoste(string $pointVente, ?string $tableId, ?string $sessionId = null): Panier
    {
        return DB::transaction(function () use ($pointVente, $tableId, $sessionId): Panier {
            // Verrou de PLAGE, faute de ligne parente : voir l'entete de la
            // classe. L'index `(point_vente, table_id, statut)` est ce qui
            // donne au verrou une plage a tenir.
            $existant = $this->requetePosteOuvert($pointVente, $tableId)->lockForUpdate()->first();

            if ($existant !== null) {
                return $existant;
            }

            return Panier::create([
                'reservation_id' => null,
                'type_vente' => Panier::TYPE_COMPTANT,
                'point_vente' => $pointVente,
                'table_id' => $tableId,
                'session_id' => $sessionId,
                'statut' => Panier::STATUT_OUVERT,
            ]);
        });
    }

    // =================================================================
    // COMPOSITION — prix et libelle figes, quantite jamais nulle
    // =================================================================

    /**
     * Porte une reference au panier, au prix et au libelle du CATALOGUE.
     *
     * Une seconde unite du meme article ne cree pas une seconde ligne : elle
     * incremente la premiere, qui garde le prix fige a son ouverture. C'est le
     * comportement du maitre, et c'est aussi ce qui evite qu'un meme article
     * apparaisse deux fois au ticket a deux prix differents.
     *
     * @throws RuntimeException panier cloture, quantite nulle, module non
     *                          encaissable, reference introuvable, article sans prix
     */
    public function ajouterLigne(Panier $panier, string $module, string $reference, int $quantite = 1): Panier
    {
        $this->exigerOuvert($panier);

        if ($quantite < 1) {
            // Une quantite saisie a zero ne devient jamais une unite facturee
            // (PA-98) : elle ne cree pas une ligne a zero franc, elle ne cree
            // rien du tout.
            throw new RuntimeException(__('ventes.quantite_minimale'));
        }

        // Resolue AVANT la transaction : une reference introuvable est une
        // erreur d'appel, pas une condition de course.
        $article = $this->resoudre($module, $reference);

        DB::transaction(function () use ($panier, $module, $reference, $quantite, $article): void {
            $ligne = LignePanier::query()
                ->where('panier_id', $panier->id)
                ->where('module', $module)
                ->where('reference_id', $reference)
                ->lockForUpdate()
                ->first();

            if ($ligne !== null) {
                $ligne->update(['quantite' => $ligne->quantite + $quantite]);

                return;
            }

            LignePanier::create([
                'panier_id' => $panier->id,
                'module' => $module,
                'reference_id' => $reference,
                // FIGES ici, et nulle part ailleurs.
                'libelle' => $article['libelle'],
                'prix_unitaire' => $article['prix'],
                'quantite' => $quantite,
            ]);
        });

        return $panier->refresh();
    }

    /**
     * Fait varier la quantite d'une ligne. Atteindre zero RETIRE la ligne —
     * une ligne a zero unite n'est pas une commande, c'est un residu.
     */
    public function changerQuantite(Panier $panier, string $ligneId, int $delta): Panier
    {
        $this->exigerOuvert($panier);

        DB::transaction(function () use ($panier, $ligneId, $delta): void {
            $ligne = LignePanier::query()
                ->where('panier_id', $panier->id)
                ->whereKey($ligneId)
                ->lockForUpdate()
                ->first();

            if ($ligne === null) {
                return;
            }

            $quantite = $ligne->quantite + $delta;

            if ($quantite < 1) {
                $ligne->delete();

                return;
            }

            $ligne->update(['quantite' => $quantite]);
        });

        return $panier->refresh();
    }

    /**
     * Retire une ligne et rend son libelle FIGE, pour que l'ecran puisse le
     * nommer. `null` : la ligne n'existait deja plus.
     */
    public function retirerLigne(Panier $panier, string $ligneId): ?string
    {
        $this->exigerOuvert($panier);

        $ligne = LignePanier::query()
            ->where('panier_id', $panier->id)
            ->whereKey($ligneId)
            ->first();

        if ($ligne === null) {
            return null;
        }

        $libelle = (string) $ligne->libelle;
        $ligne->delete();
        $panier->refresh();

        return $libelle;
    }

    /**
     * Vide le panier de ses lignes SANS le clore : la table reste ouverte,
     * c'est l'etat « ouverte » du maitre. Le geste « Vider » du maitre ne
     * libere pas la table.
     */
    public function vider(Panier $panier): Panier
    {
        $this->exigerOuvert($panier);

        DB::transaction(function () use ($panier): void {
            foreach ($panier->lignes()->get() as $ligne) {
                $ligne->delete();
            }
        });

        return $panier->refresh();
    }

    /**
     * Applique une remise au panier — directive Product Owner du 02/09/2026.
     *
     * Le motif est celui de la fiche de réservation : le TYPE et la VALEUR
     * sont stockés, jamais le montant — un montant figé deviendrait faux au
     * premier article ajouté. Le montant se dérive par l'auteur unique
     * {@see Panier::remiseSur()}, qui borne (0-100 %, jamais au-delà du
     * total) et refuse tout net négatif : la validation est LA formule,
     * pas une copie posée devant elle.
     *
     * Un panier clôturé refuse ({@see exigerOuvert()}) : la remise se fige à
     * la clôture comme les prix.
     *
     * @throws RuntimeException panier clôturé, ou remise hors bornes
     */
    public function appliquerRemise(Panier $panier, string $type, string $valeur): Panier
    {
        $this->exigerOuvert($panier);

        $valeurNormalisee = $type === Panier::REMISE_AUCUNE ? '0.00' : trim($valeur);

        // La dérivation VALIDE : type inconnu, valeur non numérique ou hors
        // bornes lèvent ici, avant toute écriture.
        Panier::remiseSur($panier->total(), $type, $valeurNormalisee);

        $panier->update([
            'remise_type' => $type,
            'remise_valeur' => $valeurNormalisee,
        ]);

        return $panier->refresh();
    }

    // =================================================================
    // CLOTURE — jamais silencieuse, jamais reversible
    // =================================================================

    /**
     * Clot le panier SANS vente — le geste « Abandonner » du maitre.
     *
     * Le panier reste au registre, `vente_id` a NULL : c'est ce qui distingue
     * une table ouverte puis quittee d'une table jamais servie. L'effacer
     * rendrait les deux indiscernables.
     */
    public function abandonner(Panier $panier): Panier
    {
        $this->exigerOuvert($panier);

        return DB::transaction(function () use ($panier): Panier {
            $panier->update([
                'statut' => Panier::STATUT_CLOTURE,
                'vente_id' => null,
                'cloture_at' => now(),
            ]);

            return $panier->refresh();
        });
    }

    /**
     * Clot le panier sur la vente qui vient d'en etre tiree.
     *
     * La vente est fournie, jamais produite ici : `VenteService` est le seul
     * chemin d'ecriture du registre des ventes, avec sa numerotation sous
     * verrou et sa deduction de stock (RG-05). Une seconde logique ici
     * divergerait au premier changement de regle.
     *
     * ⚠ A appeler DANS la meme transaction que l'enregistrement de la vente :
     * une vente enregistree sur un panier reste ouvert serait encaissee deux
     * fois au coup suivant.
     */
    public function cloturerSurVente(Panier $panier, Vente $vente): Panier
    {
        $this->exigerOuvert($panier);

        $panier->update([
            'statut' => Panier::STATUT_CLOTURE,
            'vente_id' => $vente->id,
            'cloture_at' => now(),
        ]);

        return $panier->refresh();
    }

    // =================================================================
    // Outils prives
    // =================================================================

    /**
     * @return Builder<Panier>
     */
    private function requetePosteOuvert(string $pointVente, ?string $tableId): Builder
    {
        $requete = Panier::query()
            ->where('point_vente', $pointVente)
            ->where('statut', Panier::STATUT_OUVERT);

        // `where('table_id', null)` produirait `= NULL`, qui n'est jamais vrai
        // en SQL : le comptoir n'aurait jamais retrouve son propre panier et en
        // aurait ouvert un neuf a chaque article.
        return $tableId === null
            ? $requete->whereNull('table_id')
            : $requete->where('table_id', $tableId);
    }

    private function exigerOuvert(Panier $panier): void
    {
        if ($panier->estOuvert()) {
            return;
        }

        throw new RuntimeException(__('ventes.panier_cloture_immuable'));
    }

    /**
     * Relit le catalogue pour une reference et rend ce qui sera FIGE.
     *
     * Le registre des modules acceptes est celui de
     * `VenteService::MODULES_ENCAISSABLES` — jamais une seconde liste : un
     * article qui entrerait au panier sans pouvoir etre encaisse produirait un
     * total que la cloture refuserait, sans que rien ne l'ait dit a l'ajout.
     *
     * @return array{libelle: string, prix: string}
     */
    private function resoudre(string $module, string $reference): array
    {
        if (! in_array($module, VenteService::MODULES_ENCAISSABLES, true)) {
            throw new RuntimeException(__('ventes.module_non_encaissable', [
                'module' => VenteService::MODULES[$module] ?? $module,
            ]));
        }

        // Tourisme (M9) et location (M8), encaissables depuis le 22/10/2026 :
        // le prix est celui du circuit / le tarif jour du véhicule.
        $article = match ($module) {
            'M5' => CarteBoisson::find($reference),
            'M8' => Vehicule::find($reference),
            'M9' => Circuit::find($reference),
            default => Plat::find($reference),
        };

        if ($article === null) {
            throw new RuntimeException(__('ventes.reference_inconnue', ['reference' => $reference]));
        }

        [$libelle, $prix] = match ($module) {
            'M8' => [$article->immatriculation.' ('.$article->categorie.')', (string) $article->tarif_jour],
            'M9' => [$article->nom, (string) $article->prix],
            default => [$article->libelle, (string) $article->prix_vente],
        };

        // Un article sans prix ne se vend pas — le maitre le dit lui-meme
        // (pos.html l.520). `bccomp` et non une egalite : c'est un montant.
        if (bccomp($prix, '0.00', self::PRECISION) <= 0) {
            throw new RuntimeException(__('ventes.article_sans_prix', [
                'article' => (string) $libelle,
            ]));
        }

        return [
            'libelle' => (string) $libelle,
            'prix' => $prix,
        ];
    }
}
