<?php

declare(strict_types=1);

namespace App\Shared\Integrite\Services;

use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Closure;
use Illuminate\Support\Facades\DB;

/**
 * Garantit qu'une ressource ne peut pas être réservée deux fois sur une même
 * période — RG-01 (`reservations`), RG-08 (`contrats_location`), RG-13
 * (`plannings`).
 *
 * ## Pourquoi ce service existe
 *
 * Le schéma d'origine reposait sur `EXCLUDE USING gist` (PostgreSQL), une
 * contrainte déclarative que la base faisait respecter d'elle-même. La bascule
 * MySQL du 15/08/2026 a supprimé cette garantie : MySQL n'a aucun équivalent.
 * La garantie est donc devenue **applicative**, ce qui change sa nature — elle
 * n'est plus inviolable, elle est seulement aussi solide que la discipline
 * d'appel. D'où les deux règles qui suivent, non négociables.
 *
 * ## Règle d'appel n°1 — jamais de création directe
 *
 * `Reservation::create()` appelé hors de ce service contourne le verrou sans
 * lever la moindre erreur. Sur ces trois tables, toute écriture passe par
 * `executerSousVerrou()`, sans exception.
 *
 * ## Règle d'appel n°2 — le verrou porte sur la RESSOURCE, pas sur les lignes
 *
 * Verrouiller les réservations existantes ne suffirait pas : deux transactions
 * concurrentes qui ne trouvent aucune ligne existante n'ont rien à verrouiller,
 * et inséreraient toutes les deux. C'est le scénario réel de la synchronisation
 * différée, où deux postes hors connexion créent la même réservation.
 * Verrouiller la ligne de la ressource elle-même (l'unité d'hébergement, le
 * véhicule, l'employé) sérialise les candidats quoi qu'il arrive.
 *
 * @see 03_DATABASE_ENGINEERING.md §3
 * @see A1_MASTER_PROMPT.md §2.9
 */
class VerificationChevauchementService
{
    /**
     * Exécute une écriture après s'être assuré, sous verrou, qu'elle ne
     * chevauche aucune plage existante sur la même ressource.
     *
     * @template T
     *
     * @param  string  $tablePlages  Table portant les plages (ex. `reservations`)
     * @param  string  $tableRessource  Table de la ressource à verrouiller (ex. `unites_hebergement`)
     * @param  string  $colonneRessource  Colonne de rattachement (ex. `unite_id`)
     * @param  string  $ressourceId  Identifiant de la ressource concernée
     * @param  string  $colonneDebut  Colonne de début de plage (ex. `date_arrivee`)
     * @param  string  $colonneFin  Colonne de fin de plage (ex. `date_depart`)
     * @param  string  $debut  Début de la plage demandée
     * @param  string  $fin  Fin de la plage demandée
     * @param  list<string>  $statutsInactifs  Statuts ne bloquant pas (RG-02 : une réservation annulée libère l'unité)
     * @param  string|null  $exclureId  Enregistrement à ignorer (cas d'une modification)
     * @param  array<string, string>  $filtresSupplementaires  Égalités additionnelles restreignant la recherche de conflit
     * @param  Closure(): T  $ecriture  L'écriture à réaliser une fois la place garantie libre
     * @return T
     *
     * @throws ChevauchementDetecteException
     */
    public function executerSousVerrou(
        string $tablePlages,
        string $tableRessource,
        string $colonneRessource,
        string $ressourceId,
        string $colonneDebut,
        string $colonneFin,
        string $debut,
        string $fin,
        Closure $ecriture,
        array $statutsInactifs = ['annulee'],
        ?string $exclureId = null,
        // Null plutôt qu'un libellé par défaut : une valeur par défaut de
        // paramètre ne peut pas être un appel à __(), elle serait figée à la
        // compilation et échapperait donc à la traduction (06 §4.4).
        ?string $messageConflit = null,
        // RG-13 : un planning se chevauche sur des HEURES, mais seulement à
        // l'intérieur d'une même journée. Sans ce filtre, deux créneaux
        // 08h-12h à deux dates différentes seraient vus comme un conflit.
        array $filtresSupplementaires = [],
    ): mixed {
        return DB::transaction(function () use (
            $tablePlages,
            $tableRessource,
            $colonneRessource,
            $ressourceId,
            $colonneDebut,
            $colonneFin,
            $debut,
            $fin,
            $ecriture,
            $statutsInactifs,
            $exclureId,
            $messageConflit,
            $filtresSupplementaires
        ) {
            // Verrou pessimiste sur la ressource : tout concurrent visant la
            // même unité attend ici, y compris s'il n'existe encore aucune
            // plage à verrouiller.
            DB::table($tableRessource)->where('id', $ressourceId)->lockForUpdate()->first();

            $conflits = $this->plagesEnConflit(
                $tablePlages,
                $colonneRessource,
                $ressourceId,
                $colonneDebut,
                $colonneFin,
                $debut,
                $fin,
                $statutsInactifs,
                $exclureId,
                $filtresSupplementaires,
            );

            if ($conflits !== []) {
                throw new ChevauchementDetecteException(
                    $messageConflit ?? __('integrite.chevauchement_generique'),
                    $ressourceId,
                    $conflits,
                );
            }

            return $ecriture();
        });
    }

    /**
     * Vérification sans verrou, destinée à un retour d'interface AVANT
     * soumission (message d'erreur exploitable côté client).
     *
     * Ne remplace jamais `executerSousVerrou()` : entre cette lecture et
     * l'écriture réelle, un concurrent peut insérer. C'est un confort
     * d'ergonomie, pas une garantie d'intégrité.
     *
     * @param  list<string>  $statutsInactifs
     * @param  array<string, string>  $filtresSupplementaires
     * @return list<string>
     */
    public function plagesEnConflit(
        string $tablePlages,
        string $colonneRessource,
        string $ressourceId,
        string $colonneDebut,
        string $colonneFin,
        string $debut,
        string $fin,
        array $statutsInactifs = ['annulee'],
        ?string $exclureId = null,
        array $filtresSupplementaires = [],
    ): array {
        return DB::table($tablePlages)
            ->where($colonneRessource, $ressourceId)
            ->when($statutsInactifs !== [], fn ($q) => $q->whereNotIn('statut', $statutsInactifs))
            ->when($exclureId !== null, fn ($q) => $q->where('id', '!=', $exclureId))
            // Restreint la fenêtre de recherche : une date pour un planning,
            // au besoin un service. Les valeurs passent par le binding du
            // query builder, jamais par concaténation.
            ->where($filtresSupplementaires)
            // Intervalles semi-ouverts [debut, fin) : un départ le 4 et une
            // arrivée le 4 ne se chevauchent PAS. L'erreur de bornes inverse
            // (>= / <=) refuserait des réservations parfaitement valides et
            // serait signalée par les clients, pas par les tests — d'où le cas
            // « réservation adjacente valide » rendu obligatoire en
            // 07_TESTING_QA.md §2.
            ->where($colonneDebut, '<', $fin)
            ->where($colonneFin, '>', $debut)
            ->pluck('id')
            ->map(fn ($id): string => (string) $id)
            ->all();
    }
}
