<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Services;

use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Shared\Integrite\Services\VerificationChevauchementService;
use RuntimeException;

/**
 * Création de contrats de location — EF-M8-03, RG-08.
 *
 * @see EF-M8-02 Disponibilité et planning de location
 * @see EF-M8-03 Contrat de location
 * @see RG-08 Prévention des doubles locations
 * @see RG-09 Pièces justificatives conditionnelles
 *
 * ## Jamais `ContratLocation::create()` en direct
 *
 * Même interdiction qu'en M1 sur `reservations` : une insertion directe
 * contourne le verrou pessimiste et laisse passer deux contrats concurrents
 * sur le même véhicule. `05_MODULE_SPECIFICATIONS.md` §M8 le dit explicitement
 * — « RG-08, `VerificationChevauchementService` identique au pattern M1 ».
 *
 * Le cas n'est pas théorique en exploitation : le réceptionniste et le
 * Responsable Véhicules peuvent saisir le même 4x4 au même instant depuis deux
 * postes, et un poste Flutter revenu hors connexion rejoue sa file.
 *
 * ## RG-09 est vérifiée ici ET dans le `FormRequest`
 *
 * Le `FormRequest` protège le chemin HTTP. Ce service protège **tous** les
 * chemins — synchronisation différée, import, job planifié. Une règle qui
 * n'existe que dans un `FormRequest` est absente de la file de synchronisation,
 * qui est justement le chemin par lequel arrivent les saisies de terrain.
 */
class ContratLocationService
{
    /** Le seul statut qui libère le véhicule : un contrat annulé reste lisible mais ne bloque plus RG-08. */
    public const STATUT_ANNULE = 'annule';

    /**
     * Les statuts qui ne bloquent PAS le véhicule (RG-08).
     *
     * ⚠ Jusqu'au 26/10/2026 cette liste était vide (« aucune colonne `statut`,
     * PA-50 ») alors que la colonne existe depuis `add_missing_pwa_columns` et
     * que la PWA annule des contrats : un contrat ANNULÉ bloquait encore son
     * véhicule sur toute sa plage, pendant que l'écran disait « le véhicule
     * redevient disponible » (`vehicules.pwa.archivage_contrat_fait`). Le poste
     * et le serveur lisent désormais la même règle.
     */
    private const STATUTS_INACTIFS = [self::STATUT_ANNULE];

    public function __construct(
        private readonly VerificationChevauchementService $chevauchement,
    ) {
    }

    /**
     * @param  array{vehicule_id: string, client_id: string, date_debut: string, date_fin: string, guide_id?: string|null, piece_identite?: string|null, permis_conduire?: string|null, id?: string}  $donnees
     *
     * @throws \App\Shared\Integrite\Exceptions\ChevauchementDetecteException
     * @throws RuntimeException si RG-09 n'est pas satisfaite, ou si le véhicule n'est pas louable
     */
    public function creer(array $donnees): ContratLocation
    {
        $vehicule = Vehicule::findOrFail($donnees['vehicule_id']);

        $this->verifierEtatDuVehicule($vehicule);
        $this->verifierPieces($vehicule, $donnees);

        return $this->chevauchement->executerSousVerrou(
            tablePlages: 'contrats_location',
            tableRessource: 'vehicules',
            colonneRessource: 'vehicule_id',
            ressourceId: $vehicule->id,
            colonneDebut: 'date_debut',
            colonneFin: 'date_fin',
            debut: $donnees['date_debut'],
            fin: $donnees['date_fin'],
            ecriture: fn (): ContratLocation => ContratLocation::create($donnees)->refresh(),
            statutsInactifs: self::STATUTS_INACTIFS,
            messageConflit: __('vehicules.chevauchement'),
        );
    }

    /**
     * Annule le contrat — `statut = annule`, jamais un `delete()` : la pièce
     * reste lisible, le véhicule redevient libre sur la plage (RG-08).
     *
     * Le SEUL chemin d'annulation : l'écran « Locations » de la PWA et la
     * synchronisation d'un poste (`GestionnaireContratsLocation::modifier`) le
     * partagent, de sorte que la phrase de refus est la même partout.
     *
     * @throws RuntimeException le contrat est déjà annulé
     */
    public function annuler(ContratLocation $contrat): void
    {
        if ($contrat->statut === self::STATUT_ANNULE) {
            throw new RuntimeException(__('vehicules.pwa.verrou_contrat_annule'));
        }

        // `forceFill` : `statut` est hors de `$fillable` — ce service est le
        // seul chemin qui le pose, comme `ReferentielClientService::archiver`.
        $contrat->forceFill(['statut' => self::STATUT_ANNULE])->save();
    }

    /**
     * Le véhicule est-il libre sur la période ? Lecture sans verrou, destinée
     * à l'affichage d'un planning — ne remplace jamais `creer()`.
     *
     * @see EF-M8-02
     */
    public function estDisponible(string $vehiculeId, string $debut, string $fin, ?string $exclureId = null): bool
    {
        return $this->chevauchement->plagesEnConflit(
            tablePlages: 'contrats_location',
            colonneRessource: 'vehicule_id',
            ressourceId: $vehiculeId,
            colonneDebut: 'date_debut',
            colonneFin: 'date_fin',
            debut: $debut,
            fin: $fin,
            statutsInactifs: self::STATUTS_INACTIFS,
            exclureId: $exclureId,
        ) === [];
    }

    /**
     * RG-09 — pièce d'identité toujours, permis sauf catégorie dispensée.
     *
     * @param  array<string, mixed>  $donnees
     */
    private function verifierPieces(Vehicule $vehicule, array $donnees): void
    {
        if (blank($donnees['piece_identite'] ?? null)) {
            throw new RuntimeException(__('vehicules.piece_identite_requise'));
        }

        if ($vehicule->exigePermis() && blank($donnees['permis_conduire'] ?? null)) {
            throw new RuntimeException(__('vehicules.permis_requis', [
                'categorie' => $vehicule->categorie,
            ]));
        }
    }

    /**
     * Un véhicule en entretien ou hors service ne se loue pas, même si son
     * calendrier est vide — c'est précisément parce qu'il est immobilisé que
     * son calendrier l'est.
     */
    private function verifierEtatDuVehicule(Vehicule $vehicule): void
    {
        if (! $vehicule->estLouable()) {
            throw new RuntimeException(__('vehicules.non_louable', [
                'statut' => $vehicule->statut,
            ]));
        }
    }
}
