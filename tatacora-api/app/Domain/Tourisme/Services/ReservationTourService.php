<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Services;

use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Réservation et suivi des circuits — EF-M9-03/04/05.
 *
 * @see EF-M9-03 Réservation avec affectation de guide
 * @see EF-M9-04 Gestion des groupes et capacité maximale
 * @see EF-M9-05 Suivi du déroulement
 *
 * ## Pourquoi ce service ne réutilise PAS VerificationChevauchementService
 *
 * Le service partagé raisonne sur des **intervalles** `[debut, fin)` portés
 * par deux colonnes. `reservations_tour` n'a qu'une `date_circuit` unique, et
 * `circuits.duree` est un `varchar` libre (« 2 jours », « Journée ») dont
 * aucune durée n'est extractible (PA-51). Il n'y a donc pas d'intervalle à
 * comparer : la règle porte sur une égalité de date.
 *
 * Le **verrou pessimiste**, lui, est repris à l'identique : sans lui, deux
 * réservations concurrentes sur le dernier siège passeraient toutes deux le
 * contrôle de capacité avant que l'une ait écrit.
 *
 * ## La capacité est CUMULÉE sur le départ, pas par réservation
 *
 * `SPEC_ECRAN_M9_TOURISME.md` §91 écrit « nombre de participants <= capacité ».
 * Lu littéralement, cela n'empêcherait pas trois groupes de 5 de partir sur un
 * circuit à 12 places. EF-M9-04 parle de « gestion des **groupes** et de la
 * capacité maximale par circuit » : le contrôle porte donc sur la somme des
 * participants du même circuit à la même date. Écart de lecture tracé en
 * PA-51.
 */
class ReservationTourService
{
    public function __construct()
    {
    }

    /**
     * Réservation d'un départ — EF-M9-03.
     *
     * **`guide_id` est obligatoire** : la colonne est NOT NULL au schéma
     * documenté (`FULL_MIGRATIONS_DATABASE_PART2.md` §14), contrairement à
     * `contrats_location.guide_id` qui est explicitement nullable. Une
     * prestation touristique ne peut donc pas exister sans guide — et UC-39
     * (« affecter un guide à une prestation ») est en conséquence une
     * **ré**affectation, jamais une affectation initiale différée. Écart de
     * lecture tracé en PA-51.
     *
     * @param  array{circuit_id: string, client_id: string, guide_id: string, date_circuit: string, nb_participants: int, statut?: string, id?: string}  $donnees
     *
     * @throws RuntimeException capacité dépassée ou guide déjà affecté
     */
    public function reserver(array $donnees): ReservationTour
    {
        return DB::transaction(function () use ($donnees): ReservationTour {
            // Verrou sur le circuit : tout concurrent visant le même départ
            // attend ici, y compris s'il n'existe encore aucune réservation.
            $circuit = Circuit::whereKey($donnees['circuit_id'])->lockForUpdate()->firstOrFail();

            $this->verifierCapacite($circuit, $donnees['date_circuit'], (int) $donnees['nb_participants']);
            $this->verifierGuideDuDepart($circuit->id, $donnees['date_circuit'], $donnees['guide_id']);
            $this->verifierGuideLibre($donnees['guide_id'], $donnees['date_circuit'], $circuit->id);

            return ReservationTour::create([
                ...$donnees,
                'statut' => $donnees['statut'] ?? 'reservee',
            ])->refresh();
        });
    }

    /**
     * Réaffectation d'un guide sur une prestation existante — UC-39.
     *
     * Le cas réel : le guide initialement prévu est malade ou immobilisé, et
     * un autre doit reprendre le départ. Le contrôle d'exclusivité s'applique
     * au remplaçant, en excluant la prestation elle-même du calcul.
     */
    public function affecterGuide(ReservationTour $reservation, string $guideId): ReservationTour
    {
        if ($reservation->estAnnulee() || $reservation->estTerminee()) {
            throw new RuntimeException(__('tourisme.affectation_impossible'));
        }

        return DB::transaction(function () use ($reservation, $guideId): ReservationTour {
            $date = $reservation->date_circuit->toDateString();

            $this->verifierGuideLibre($guideId, $date, $reservation->circuit_id, $reservation->id);

            // La réaffectation porte sur le DÉPART, pas sur la seule ligne
            // ouverte à l'écran. Un départ a un guide (voir
            // `verifierGuideDuDepart`) : n'en changer qu'une réservation en
            // laisserait deux sur le même car, et la prochaine réservation
            // serait refusée par une incohérence que personne n'aurait vue
            // se créer.
            ReservationTour::query()
                ->where('circuit_id', $reservation->circuit_id)
                ->whereDate('date_circuit', $date)
                ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
                ->update(['guide_id' => $guideId]);

            return $reservation->refresh();
        });
    }

    /**
     * Clôture d'une prestation — UC-40, EF-M9-05.
     */
    public function cloturer(ReservationTour $reservation): ReservationTour
    {
        if ($reservation->estAnnulee()) {
            throw new RuntimeException(__('tourisme.cloture_apres_annulation'));
        }

        // Aucun contrôle « guide affecté » ici : `guide_id` est NOT NULL au
        // schéma, une prestation sans guide ne peut pas exister. Un garde-fou
        // inatteignable donnerait l'illusion d'une protection.
        $reservation->update(['statut' => 'terminee']);

        return $reservation->refresh();
    }

    /**
     * Annulation — libère aussitôt la place au départ, comme RG-02 en M1.
     */
    public function annuler(ReservationTour $reservation): ReservationTour
    {
        if ($reservation->estTerminee()) {
            throw new RuntimeException(__('tourisme.annulation_apres_cloture'));
        }

        $reservation->update(['statut' => 'annulee']);

        return $reservation->refresh();
    }

    /**
     * Places encore disponibles sur un départ — EF-M9-04.
     *
     * Lecture sans verrou : confort d'affichage, jamais une garantie. Entre
     * cette lecture et l'écriture, un concurrent peut réserver.
     */
    public function placesRestantes(Circuit $circuit, string $date): int
    {
        return max(0, $circuit->capacite_max - $this->participantsReserves($circuit->id, $date));
    }

    /**
     * Circuits assurés par un guide à une date — base du planning guide.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, ReservationTour>
     */
    public function affectationsDuGuide(string $guideId, string $date): \Illuminate\Database\Eloquent\Collection
    {
        return ReservationTour::query()
            ->where('guide_id', $guideId)
            ->whereDate('date_circuit', $date)
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->get();
    }

    /**
     * Les lignes de réservation d'une fenêtre de dates — la requête de
     * l'écran M9, remontée ici le 02/09/2026 pour que la carte « Tourisme &
     * circuits » de l'accueil lise la même population que l'écran (PA-121).
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, ReservationTour>
     */
    public function reservationsSurFenetre(\Carbon\CarbonImmutable $debut, \Carbon\CarbonImmutable $fin): \Illuminate\Database\Eloquent\Collection
    {
        return ReservationTour::query()
            ->with(['circuit', 'client', 'guide'])
            ->whereBetween('date_circuit', [$debut->format('Y-m-d'), $fin->format('Y-m-d')])
            ->orderByDesc('date_circuit')
            ->get();
    }

    /**
     * Les DÉPARTS dérivés des lignes de réservation — il n'existe aucune
     * table `departs` : un départ est le couple (circuit, date), reconstruit
     * ici. Extrait de l'écran M9 (`Pwa\Livewire\Tourisme\Departs`) le
     * 02/09/2026 pour que la carte d'accueil et l'écran dérivent les mêmes
     * départs — deux dérivations finiraient par se contredire (PA-121).
     *
     * @param  \Illuminate\Database\Eloquent\Collection<int, ReservationTour>  $reservations
     * @return list<array{circuit_id: string, circuit_nom: string, duree: string|null, duree_indeterminee: bool, date: string, guide: string|null, guide_id: string|null, capacite: int, places_vendues: int, prix_unitaire: string, chiffre_affaires: string, annule: bool, places_restantes: int}>
     */
    public function departsDerives(\Illuminate\Database\Eloquent\Collection $reservations): array
    {
        $departs = [];

        foreach ($reservations as $reservation) {
            // `circuit_id` est NOT NULL au schema : la relation est toujours
            // resolue, il n'y a pas de branche « circuit absent » a ecrire.
            $circuit = $reservation->circuit;

            $date = $reservation->date_circuit->format('Y-m-d');
            $cle = $circuit->id.'|'.$date;

            if (! isset($departs[$cle])) {
                $departs[$cle] = [
                    'circuit_id' => $circuit->id,
                    'circuit_nom' => $circuit->nom,
                    'duree' => $circuit->duree,
                    'duree_indeterminee' => $this->dureeIndeterminee($circuit->duree),
                    'date' => $date,
                    'guide' => null,
                    'guide_id' => null,
                    'capacite' => $circuit->capacite_max,
                    'places_vendues' => 0,
                    'prix_unitaire' => (string) $circuit->prix,
                    'chiffre_affaires' => '0.00',
                    'annule' => true,
                ];
            }

            if ($reservation->estAnnulee()) {
                continue;
            }

            $departs[$cle]['annule'] = false;
            $departs[$cle]['places_vendues'] += $reservation->nb_participants;
            $departs[$cle]['chiffre_affaires'] = bcadd(
                $departs[$cle]['chiffre_affaires'],
                bcmul((string) $circuit->prix, (string) $reservation->nb_participants, 2),
                2,
            );
            // Le guide du départ est celui de ses lignes actives : elles
            // portent forcement le meme, `verifierGuideLibre` interdisant
            // qu'un guide serve deux fois le meme jour.
            $departs[$cle]['guide'] ??= $reservation->guide?->nom;
            $departs[$cle]['guide_id'] ??= $reservation->guide_id;
        }

        foreach ($departs as $cle => $depart) {
            $departs[$cle]['places_restantes'] = max(0, $depart['capacite'] - $depart['places_vendues']);
        }

        return array_values($departs);
    }

    /**
     * `circuits.duree` est un varchar LIBRE (PA-51) : une durée exploitable
     * contient un chiffre (« 3 jours »). La règle réelle teste la PRÉSENCE
     * d'un chiffre, pas sa position — reprise telle quelle de l'écran M9 le
     * 02/09/2026, sans « correction » silencieuse.
     */
    public function dureeIndeterminee(?string $duree): bool
    {
        if ($duree === null) {
            return true;
        }

        return preg_match('/\d/', $duree) !== 1;
    }

    /**
     * Les cinq agrégats de départs de l'écran M9 — UNE formule pour l'écran
     * et pour la carte « Tourisme & circuits » de l'accueil (extraite de
     * `Departs::render()` le 02/09/2026). Le taux est celui de l'écran
     * (arrondi à une décimale) ; `null` quand aucune capacité n'est offerte —
     * « — » à l'affichage, jamais « 0 % » qui affirmerait un remplissage
     * mesuré.
     *
     * @param  list<array{capacite: int, places_vendues: int, chiffre_affaires: string, places_restantes: int, duree_indeterminee: bool}>  $departs
     * @return array{departs: int, places_vendues: int, capacite_offerte: int, complets: int, chiffre_affaires: string, taux_remplissage: float|null, duree_indeterminee: int}
     */
    public static function agregerDeparts(array $departs): array
    {
        $placesVendues = 0;
        $capaciteOfferte = 0;
        $chiffreAffaires = '0.00';
        $complets = 0;
        $dureeIndeterminee = 0;

        foreach ($departs as $depart) {
            $placesVendues += $depart['places_vendues'];
            $capaciteOfferte += $depart['capacite'];
            $chiffreAffaires = bcadd($chiffreAffaires, $depart['chiffre_affaires'], 2);

            if ($depart['places_restantes'] === 0) {
                $complets++;
            }

            if ($depart['duree_indeterminee']) {
                $dureeIndeterminee++;
            }
        }

        return [
            'departs' => count($departs),
            'places_vendues' => $placesVendues,
            'capacite_offerte' => $capaciteOfferte,
            'complets' => $complets,
            'chiffre_affaires' => $chiffreAffaires,
            'taux_remplissage' => $capaciteOfferte > 0
                ? round(($placesVendues / $capaciteOfferte) * 100, 1)
                : null,
            'duree_indeterminee' => $dureeIndeterminee,
        ];
    }

    // ------------------------------------------------------------- Contrôles

    private function verifierCapacite(Circuit $circuit, string $date, int $participants): void
    {
        if ($participants < 1) {
            throw new RuntimeException(__('tourisme.participants_minimum'));
        }

        $dejaReserves = $this->participantsReserves($circuit->id, $date);
        $restantes = $circuit->capacite_max - $dejaReserves;

        if ($participants > $restantes) {
            throw new RuntimeException(__('tourisme.capacite_depassee', [
                'demandes' => $participants,
                'restantes' => max(0, $restantes),
                'capacite' => $circuit->capacite_max,
            ]));
        }
    }

    /**
     * Un guide ne peut pas assurer deux circuits le même jour.
     *
     * **Règle dérivée, non adossée à une RG explicite** — RG-13 vise les
     * `plannings` d'employés, et un guide n'est pas nécessairement salarié
     * (`01_BUSINESS_ANALYSIS_SPEC.md` §acteurs : « personnel **ou
     * prestataire** »). Elle est appliquée parce qu'un même guide ne peut
     * physiquement pas conduire deux groupes simultanément ; tracée en PA-51.
     *
     * Portée limitée à la journée : `circuits.duree` étant un libellé libre,
     * un circuit de 3 jours ne bloque que sa date de départ.
     */
    /**
     * L'exclusivité du guide porte sur le DÉPART, jamais sur la réservation.
     *
     * ## Le défaut que cette signature corrige (31/08/2026)
     *
     * La version d'origine refusait toute seconde réservation du même guide à
     * la même date, **sans regarder le circuit**. Or un départ, c'est un
     * circuit à une date, un guide, et *plusieurs* réservations — une par
     * groupe. La deuxième réservation d'un même départ était donc toujours
     * refusée, et `verifierCapacite()`, qui cumule précisément les
     * participants d'un même départ (PA-51), devenait **inatteignable au-delà
     * du premier groupe**.
     *
     * Le contrôle cumulé et l'exclusivité se contredisaient : l'un suppose
     * plusieurs réservations sur un départ, l'autre les interdit.
     *
     * ⚠ Aucun test ne le montrait, et la raison mérite d'être retenue : le
     * helper `reserver()` de `CircuitsEtGuidesTest` affectait **un guide neuf
     * à chaque appel**. Le cas cumulé était donc éprouvé sur un départ à deux
     * guides — une situation qui ne peut pas exister au Gîte. La suite était
     * verte parce qu'elle construisait l'impossible pour éviter le conflit.
     *
     * La règle réelle, celle du terrain : un guide ne peut pas conduire deux
     * groupes **partant ailleurs** le même jour. Le conflit est donc une
     * réservation active, même guide, même date, **sur un autre circuit**.
     */
    private function verifierGuideLibre(string $guideId, string $date, string $circuitId, ?string $exclureId = null): void
    {
        Guide::findOrFail($guideId);

        $conflit = ReservationTour::query()
            ->where('guide_id', $guideId)
            ->whereDate('date_circuit', $date)
            ->where('circuit_id', '!=', $circuitId)
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->when($exclureId !== null, fn ($q) => $q->where('id', '!=', $exclureId))
            ->exists();

        if ($conflit) {
            throw new RuntimeException(__('tourisme.guide_deja_affecte', ['date' => $date]));
        }
    }

    /**
     * Un départ a UN guide — corollaire direct de la règle ci-dessus.
     *
     * Sans ce contrôle, autoriser plusieurs réservations sur un même départ
     * laisserait chacune arriver avec son propre guide, et le départ en
     * aurait autant que de groupes. C'est exactement ce que la suite de tests
     * produisait sans le voir.
     *
     * Le guide du départ est celui de sa première réservation ; les suivantes
     * doivent le reprendre. Le changer pour tout le monde relève d'UC-39
     * (`affecterGuide`), pas d'une réservation qui s'ajoute.
     */
    private function verifierGuideDuDepart(string $circuitId, string $date, string $guideId): void
    {
        $guideEnPlace = ReservationTour::query()
            ->where('circuit_id', $circuitId)
            ->whereDate('date_circuit', $date)
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->value('guide_id');

        if ($guideEnPlace !== null && $guideEnPlace !== $guideId) {
            throw new RuntimeException(__('tourisme.guide_du_depart_impose', [
                'date' => $date,
            ]));
        }
    }

    private function participantsReserves(string $circuitId, string $date): int
    {
        return (int) ReservationTour::query()
            ->where('circuit_id', $circuitId)
            ->whereDate('date_circuit', $date)
            ->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS)
            ->sum('nb_participants');
    }
}
