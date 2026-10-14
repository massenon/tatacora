<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use App\Domain\Crm\Models\Client;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * ARCHIVAGE du référentiel client (M3, EF-M3-01) — « supprimer = archiver ».
 *
 * Demande du Product Owner du 03/09/2026 : chaque tableau de référentiel porte
 * son geste de retrait. Ici, ce geste pose `clients.actif = false` — jamais un
 * `delete()` : `BasePolicy::delete()` rend `false` pour les 20 policies, et
 * six tables citent `clients.id` en `restrictOnDelete` (réservations,
 * factures, avoirs, contrats de location, réservations de circuit, relances).
 * Effacer une fiche rendrait chacune de ces lignes illisible — RG-18 pose une
 * fiche client UNIQUE, partagée par tous les modules : elle doit survivre à la
 * fin de la relation commerciale.
 *
 * ## Pourquoi un service séparé d'`EnregistrementClientService`
 *
 * Celui-là porte la création et la détection de doublon (RG-18). Retirer un
 * client du référentiel n'est pas un enregistrement, et le mélange aurait fait
 * dépendre le chemin de création de quatre domaines qui ne le concernent pas.
 *
 * ## Les lectures hors M3 passent par `DB::table()`, délibérément
 *
 * `reservations` (M1), `contrats_location` (M8), `reservations_tour` (M9) et
 * `factures` (M2) n'appartiennent pas à ce domaine. Importer leurs modèles
 * ferait de M3 un dépendant de quatre modules, ce que l'architecture par
 * domaine interdit hors relation documentée. Ce sont des LECTURES : ce que ce
 * dépôt condamne dans `DB::table()` est l'ÉCRITURE directe, qui contourne un
 * verrou pessimiste (RG-01/RG-08/RG-13) — il n'y en a aucun ici.
 *
 * ⚠ Le solde, lui, n'est PAS relu à la main : `SoldeClientService` en est
 * l'auteur unique, et il délègue lui-même à `Facture::SQL_RESTE_DU`. Une
 * seconde formule de créance écrite ici aurait fini par diverger, et l'écran
 * aurait refusé d'archiver un client que la liste affiche à zéro.
 *
 * @see EF-M3-01 Référentiel clients
 * @see RG-18 Fiche client unique
 * @see RG-15 Journalisation (trait Auditable sur Client)
 */
class ReferentielClientService
{
    /**
     * Les VERROUS du client — les raisons, lisibles, de refuser l'archivage.
     *
     * Quatre engagements, et chacun décrit une conséquence réelle :
     *
     * 1. **Un séjour en cours ou à venir.** La réception a besoin du client au
     *    sélecteur jusqu'au départ. Un séjour PASSÉ n'engage rien : il reste
     *    lisible, puisque rien n'est effacé.
     * 2. **Une location de véhicule non annulée qui n'est pas terminée.**
     * 3. **Une réservation de circuit non annulée à venir.**
     * 4. **Une créance ouverte.** Archiver un débiteur le retirerait de
     *    l'écran Créances — celui-là même où l'on décide de le relancer.
     *
     * @return list<string> les motifs, un par engagement — vide : archivable
     */
    public function verrous(Client $client): array
    {
        $motifs = [];
        $aujourdhui = CarbonImmutable::today()->toDateString();

        $sejours = DB::table('reservations')
            ->where('client_id', $client->id)
            ->where('statut', '!=', 'annulee')
            ->where('date_depart', '>=', $aujourdhui)
            ->count();

        if ($sejours > 0) {
            $motifs[] = __('crm.archivage.verrou_sejour', ['nombre' => $sejours]);
        }

        $locations = DB::table('contrats_location')
            ->where('client_id', $client->id)
            ->where('statut', '!=', 'annule')
            ->where('date_fin', '>=', $aujourdhui)
            ->count();

        if ($locations > 0) {
            $motifs[] = __('crm.archivage.verrou_location', ['nombre' => $locations]);
        }

        $circuits = DB::table('reservations_tour')
            ->where('client_id', $client->id)
            ->where('statut', '!=', 'annulee')
            ->where('date_circuit', '>=', $aujourdhui)
            ->count();

        if ($circuits > 0) {
            $motifs[] = __('crm.archivage.verrou_circuit', ['nombre' => $circuits]);
        }

        // L'AUTEUR UNIQUE de la créance — jamais une seconde formule ici.
        $impayees = SoldeClientService::appliquerPredicatImpayee(DB::table('factures'))
            ->where('factures.client_id', $client->id)
            ->count();

        if ($impayees > 0) {
            $motifs[] = __('crm.archivage.verrou_creance', ['nombre' => $impayees]);
        }

        return $motifs;
    }

    /**
     * Archive le client — `actif = false`, jamais un `delete()`.
     *
     * @throws RuntimeException le client est engagé (voir `verrous()`)
     */
    public function archiver(Client $client): void
    {
        // Recontrôlé au moment d'AGIR, pas seulement à l'affichage : entre
        // l'ouverture de la modale et le clic, une réservation ou une facture
        // a pu naître.
        // Preuve par mutation (03/09/2026) : ce bloc retiré, le cas
        // `un_client_engage_est_refuse_et_reste_intact` d'`ArchivageReferentielsPwaTest`
        // passe au ROUGE — la garde mord.
        $motifs = $this->verrous($client);

        if ($motifs !== []) {
            throw new RuntimeException(implode(' ', $motifs));
        }

        // `forceFill` et non `update` : `actif` est délibérément HORS de
        // `$fillable` — ce service est le seul chemin d'archivage, et un
        // formulaire de fiche client qui recevrait la clé par erreur ne doit
        // pas pouvoir retirer quelqu'un du référentiel sans ce verrou.
        $client->forceFill(['actif' => false])->save();
    }

    /**
     * Le pendant de l'archivage — sans lui, « reste restaurable » serait une
     * promesse que rien ne tient (PA-59/60/61).
     */
    public function restaurer(Client $client): void
    {
        if ((bool) $client->actif) {
            return;
        }

        $client->forceFill(['actif' => true])->save();
    }
}
