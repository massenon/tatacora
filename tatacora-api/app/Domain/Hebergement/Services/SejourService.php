<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Check-in, check-out et cycle opérationnel de l'unité (M1).
 *
 * **Unique point d'entrée d'écriture sur `sejours` et sur
 * `unites_hebergement.statut`.**
 *
 * ## Ce qui manquait, et ce qui ne manquait pas
 *
 * `sejours.date_checkin_reel` et `date_checkout_reel` existaient depuis la
 * migration d'origine (`create_hebergement.php` l.63-64), le modèle `Sejour`
 * les exposait et en dérivait `estEnCours()`. Ce qui n'existait pas, c'est le
 * **geste** : aucune route, aucun service ne faisait de check-in. La note du
 * dépôt qui affirmait « le check-in/check-out n'existe nulle part » était donc
 * fausse à moitié, et c'est cette moitié fausse qui avait fait refuser un
 * écran (PA-118, motif 2). Aucune migration n'était nécessaire.
 *
 * ## ⚠ DEUX sources, DEUX questions — l'arbitrage est ici et il fait foi
 *
 * Le dépôt porte désormais deux informations sur l'occupation d'une unité.
 * Elles ne répondent pas à la même question, et les confondre contredit RG-02.
 *
 * | Question | Source qui fait foi | Source à NE PAS lire |
 * |---|---|---|
 * | « Cette unité est-elle libre du 1er au 4 ? » (vente, planning, RG-01/RG-02) | `DisponibiliteService`, calculé depuis les réservations actives | `unites_hebergement.statut` |
 * | « Quelqu'un dort-il dans cette unité cette nuit ? » | `Sejour::estEnCours()` — check-in fait, check-out pas encore | `reservations.statut` |
 * | « L'unité est-elle prête à recevoir MAINTENANT ? » (ménage, maintenance) | `unites_hebergement.statut` | les réservations |
 *
 * La raison est dans le sens des données : `statut` est un état **instantané**,
 * il ne connaît ni date ni période. Le lire pour répondre à « libre du 1er au
 * 4 ? » donnerait une réponse fausse dès qu'une réservation future existe, et
 * une annulation ne la corrigerait jamais — c'est exactement ce que RG-02
 * interdit. Inversement, les réservations ne savent rien du ménage : une
 * chambre sans réservation peut être hors service.
 *
 * Le seul usage légitime de `statut` dans une décision commerciale reste
 * `UniteHebergement::estCommercialisable()` — un **filtre** appliqué après le
 * calcul de disponibilité, jamais à sa place.
 *
 * ## Pourquoi ce service écrit `statut` alors que PA-118 constatait que
 * personne ne l'écrivait
 *
 * C'était le vrai motif du refus de l'écran « Plan d'Hébergement » : la colonne
 * portait le cycle exact du maître (`libre → reservee → occupee → nettoyage`)
 * et **aucune écriture hors seeder** ne l'alimentait. L'afficher aurait été
 * PA-126, une colonne rendue comme un fait. Le cycle est désormais écrit par
 * les trois gestes qui le font réellement avancer — check-in, check-out,
 * ménage terminé — et par eux seuls. L'écran peut donc l'afficher, pour la
 * question à laquelle il répond, et pour elle seule.
 *
 * @see EF-M1-03 Check-in
 * @see EF-M1-04 Check-out
 * @see RG-02 Disponibilité toujours calculée, jamais stockée
 * @see RG-15 Journalisation (trait Auditable sur Reservation)
 */
class SejourService
{
    /**
     * Statuts d'unité, dans l'ordre du cycle opérationnel du maître.
     *
     * `reservee` n'est écrit par aucun geste de ce service : il désignerait une
     * unité tenue pour un client attendu dans la journée, et rien dans le
     * dépôt ne dit à quel moment une réservation future devient une tenue du
     * jour. L'inventer ferait afficher « réservée » sur des chambres libres
     * pendant des semaines. Le registre le NOMME pour que son absence se voie.
     */
    public const STATUT_LIBRE = 'libre';

    public const STATUT_OCCUPEE = 'occupee';

    public const STATUT_NETTOYAGE = 'nettoyage';

    /**
     * Enregistre l'arrivée réelle du client — EF-M1-03.
     *
     * @param  list<array<string, mixed>>  $occupants pièces d'identité des occupants (EF-M1-04)
     *
     * @throws RuntimeException réservation annulée, ou séjour déjà commencé
     */
    public function checkin(Reservation $reservation, array $occupants = []): Sejour
    {
        return DB::transaction(function () use ($reservation, $occupants): Sejour {
            // Verrou sur la réservation : deux réceptionnistes qui valident la
            // même arrivée créeraient deux séjours pour un seul client, et
            // `estEnCours()` deviendrait indécidable. Même famille de condition
            // de course que RG-01.
            $verrouillee = Reservation::whereKey($reservation->id)->lockForUpdate()->firstOrFail();

            if ($verrouillee->statut === 'annulee') {
                throw new RuntimeException(__('sejour.reservation_annulee'));
            }

            $existant = Sejour::where('reservation_id', $verrouillee->id)->first();

            if ($existant !== null) {
                throw new RuntimeException(__('sejour.deja_arrive', [
                    'date' => $existant->date_checkin_reel?->format('d/m/Y H:i') ?? '',
                ]));
            }

            $sejour = Sejour::create([
                'reservation_id' => $verrouillee->id,
                'date_checkin_reel' => now(),
                // Tableau vide plutôt que `null` : « aucun occupant relevé » et
                // « champ jamais renseigné » ne doivent pas se ressembler.
                'occupants' => $occupants,
            ]);

            $verrouillee->update(['statut' => 'en_cours']);
            $this->changerStatutUnite($verrouillee->unite_id, self::STATUT_OCCUPEE);

            return $sejour->refresh();
        });
    }

    /**
     * Enregistre le départ réel du client — EF-M1-04.
     *
     * L'unité passe en `nettoyage`, pas en `libre` : elle n'est pas prête à
     * recevoir tant que le ménage n'est pas fait. La déclarer libre ici ferait
     * accueillir un client dans une chambre non faite — et personne ne saurait
     * lesquelles restent à traiter.
     *
     * @throws RuntimeException séjour déjà clos
     */
    public function checkout(Sejour $sejour): Sejour
    {
        return DB::transaction(function () use ($sejour): Sejour {
            $verrouille = Sejour::whereKey($sejour->id)->lockForUpdate()->firstOrFail();

            if (! $verrouille->estEnCours()) {
                throw new RuntimeException(__('sejour.deja_parti', [
                    'date' => $verrouille->date_checkout_reel?->format('d/m/Y H:i') ?? '',
                ]));
            }

            $verrouille->update(['date_checkout_reel' => now()]);

            $reservation = $verrouille->reservation;
            $reservation->update(['statut' => 'terminee']);
            $this->changerStatutUnite($reservation->unite_id, self::STATUT_NETTOYAGE);

            return $verrouille->refresh();
        });
    }

    /**
     * Ménage terminé : l'unité redevient prête à recevoir.
     *
     * Troisième geste du cycle, et il compte autant que les deux autres : sans
     * lui, toute unité libérée resterait en `nettoyage` indéfiniment, et le
     * cycle du maître s'arrêterait à son avant-dernier état — un indicateur
     * bloqué, que personne ne penserait à rouvrir.
     *
     * `hors_service` n'est pas touché : une unité en maintenance ne redevient
     * pas disponible parce qu'on a passé le balai.
     *
     * @throws RuntimeException si l'unité n'était pas en nettoyage
     */
    public function marquerNettoyee(UniteHebergement $unite): UniteHebergement
    {
        if ($unite->statut !== self::STATUT_NETTOYAGE) {
            throw new RuntimeException(__('sejour.pas_en_nettoyage', [
                'unite' => $unite->numero,
                'statut' => $unite->statut,
            ]));
        }

        $unite->update(['statut' => self::STATUT_LIBRE]);

        return $unite->refresh();
    }

    /**
     * Le séjour en cours d'une unité, ou `null`.
     *
     * Lit `sejours`, jamais `unites_hebergement.statut` : le statut dit qu'une
     * chambre est occupée, il ne dit pas PAR QUI.
     */
    public function sejourEnCours(UniteHebergement $unite): ?Sejour
    {
        return Sejour::query()
            ->whereNull('date_checkout_reel')
            ->whereHas('reservation', fn ($requete) => $requete->where('unite_id', $unite->id))
            ->with('reservation.client')
            ->first();
    }

    /**
     * Écriture centralisée du cycle opérationnel — le seul endroit du dépôt.
     *
     * Une unité `hors_service` n'est jamais touchée : la maintenance prime sur
     * l'exploitation, et un check-in sur une chambre condamnée est un problème
     * à signaler, pas un statut à écraser.
     */
    private function changerStatutUnite(string $uniteId, string $statut): void
    {
        $unite = UniteHebergement::findOrFail($uniteId);

        if ($unite->statut === 'hors_service') {
            throw new RuntimeException(__('sejour.unite_hors_service', ['unite' => $unite->numero]));
        }

        $unite->update(['statut' => $statut]);
    }
}
