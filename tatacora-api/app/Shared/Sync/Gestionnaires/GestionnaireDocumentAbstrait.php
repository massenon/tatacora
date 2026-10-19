<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Shared\Sync\Exceptions\DonneesSynchroniseesInvalidesException;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\Exceptions\InvalidFormatException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Patron commun des DOCUMENTS synchronisés — lot S3, décisions du Product
 * Owner du 15/10/2026 (D246 : le serveur seul maître comptable).
 *
 * Un document (session de caisse, vente, dépense, commande d'achat, bon de
 * réception) diffère d'une fiche de référentiel en trois points, que cette
 * classe porte une fois pour toutes :
 *
 * 1. **Il décrit un fait accompli.** Le poste pousse la SOURCE ; le serveur en
 *    tire la pièce comptable et le mouvement de stock par SES services, à la
 *    date MÉTIER. Jamais d'écriture comptable reçue d'un poste.
 * 2. **Il est immuable.** Une correction est un autre document (contre-
 *    passation, avoir, annulation par son propre geste) : la modification
 *    reste refusée par défaut (`GestionnaireAbstrait`), seule la clôture
 *    d'une session de caisse l'accepte.
 * 3. **Il est idempotent sur son UUID.** Le service écrit sous l'UUID du
 *    poste et vérifie l'existence DANS sa transaction ; une création
 *    rejouée sur un document déjà écrit (même `uuid_operation`, ou nouvelle
 *    tentative après purge de la mémoire d'idempotence) rend le résultat
 *    d'origine — `reprendreExistant()` — sans second numéro, seconde pièce
 *    ni second mouvement.
 *
 * Ce qui s'écarte de ce que le serveur aurait calculé est SIGNALÉ
 * (`SignalementAnomalies`) et rendu au poste, jamais corrigé en silence.
 */
abstract class GestionnaireDocumentAbstrait extends GestionnaireAbstrait
{
    public function __construct(
        protected readonly ResolveurCorrespondances $correspondances,
        protected readonly SignalementAnomalies $anomalies,
    ) {
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return $this->resultat($entiteId);
    }

    /**
     * Ce que le poste reçoit pour le document écrit (numéro, montants,
     * écarts signalés) — le même au premier passage et au rejeu.
     */
    abstract protected function resultat(string $entiteId): EcritureSynchronisee;

    /**
     * Valide la FORME du payload du poste (unités et noms du poste), avec les
     * phrases de `lang/fr/validation.php` — avant toute conversion vers la
     * forme du service.
     *
     * @param  array<string, mixed>  $donnees
     * @param  array<string, mixed>  $regles
     * @param  array<string, string>  $messages
     * @return array<string, mixed>
     *
     * @throws DonneesSynchroniseesInvalidesException
     */
    protected function validerForme(array $donnees, array $regles, array $messages = []): array
    {
        try {
            return Validator::make($donnees, $regles, $messages)->validate();
        } catch (ValidationException $e) {
            throw DonneesSynchroniseesInvalidesException::depuis($e);
        }
    }

    /** Un identifiant cité, traduit par les correspondances (fusion hors connexion). */
    protected function resoudre(string $table, mixed $id): mixed
    {
        return is_string($id) && $id !== '' ? $this->correspondances->resoudre($table, $id) : $id;
    }

    /**
     * Entier du poste (centimes, centièmes) → décimal à deux chiffres du
     * serveur, en chaîne : `bc*` n'accepte rien d'autre, un flottant y
     * perdrait le centime.
     */
    protected function centiemes(int $valeur): string
    {
        return bcdiv((string) $valeur, '100', 2);
    }

    /** Francs CFA entiers du poste → décimal du serveur. */
    protected function francs(int $valeur): string
    {
        return bcadd((string) $valeur, '0', 2);
    }

    /**
     * Une date du document (déjà validée `date`), sinon la date métier du
     * contexte.
     */
    protected function dateDuDocument(mixed $brute, ContexteSynchronisation $contexte): Carbon
    {
        if ($brute === null || $brute === '') {
            return $contexte->dateMetier->copy();
        }

        try {
            return Carbon::parse((string) $brute);
        } catch (InvalidFormatException) {
            return $contexte->dateMetier->copy();
        }
    }
}
