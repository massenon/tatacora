<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Achats\Http\Requests\EnregistrerFournisseurRequest;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Shared\Rbac\Services\DroitArchivageService;
use App\Shared\Sync\Support\CleNaturelle;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Fournisseurs créés ou modifiés hors connexion (M7, EF-M7-01) — par
 * `ReferentielFournisseurService`, et par lui seul.
 *
 * ## Le poste crée ET modifie hors connexion
 *
 * Décision du Product Owner du 15/10/2026 (« offline-first total ») : une
 * modification est appliquée en DERNIER ÉCRIT GAGNANT sur l'horodatage de
 * saisie (`SynchronisationService`), PARTIELLE (seuls les champs présents),
 * par le service ; une modification d'un fournisseur inconnu du serveur est
 * traitée comme une création si son payload est complet. La phrase « le
 * serveur est maître » ci-dessous ne vaut plus que pour la FUSION à la
 * création : une fiche équivalente n'est jamais écrasée par une création.
 *
 * ## Création : fusion sur la clé naturelle
 *
 * Décision du Product Owner du 15/10/2026 : les postes TÉLÉCHARGENT le
 * catalogue, mais un poste coupé du serveur peut créer un fournisseur (le
 * livreur est au comptoir, il n'est pas au catalogue). À la synchronisation :
 *
 * - aucun équivalent côté serveur → créé sous l'UUID du poste, par le service ;
 * - un équivalent existe (même raison sociale, à la casse, aux accents et aux
 *   espaces près) → **FUSION** : rien n'est créé, rien n'est écrasé (le
 *   serveur est maître : la fiche serveur reste telle quelle), la
 *   correspondance UUID poste → UUID serveur est retenue par le moteur, et le
 *   poste reçoit `fusionne_avec` pour remapper ses documents.
 *
 * Deux postes qui créent le même fournisseur fusionnent donc sur le MÊME
 * élément serveur — le premier arrivé le crée, le second s'y fond.
 *
 * ## La clé naturelle est la raison sociale normalisée
 *
 * C'est la seule donnée obligatoire de la fiche (`raison_sociale` required) :
 * contact, catégorie et conditions sont facultatifs et changent dans la vie
 * d'un fournisseur. « SOBEBRA », « Sobebra » et « Sobébra  » désignent la
 * même société — les saisies de deux postes ne s'accordent jamais sur la
 * casse ni sur les accents, et ne pas les confondre ferait précisément le
 * doublon que la fusion existe pour éviter.
 *
 * La comparaison est faite en PHP, sur toutes les fiches, ARCHIVÉES comprises
 * (une fiche archivée reste la même société : en créer une seconde ferait
 * renaître un doublon que l'archivage avait précisément rangé), sous verrou
 * `FOR UPDATE` : deux lots concurrents qui créent le même fournisseur se
 * sérialisent, le second voit le premier et fusionne. Le référentiel compte
 * des centaines de lignes, pas des millions — un parcours est sûr ; une
 * colonne normalisée indexée serait la suite si le volume l'exigeait.
 *
 * ## Validation : celle de l'API, mot pour mot
 *
 * Les champs sont ceux d'`EnregistrerFournisseurRequest`, validés par ses
 * règles et rendus avec ses phrases : le poste affiche le même refus que
 * l'écran en ligne. Un document invalide est rejeté AVANT toute recherche
 * d'équivalent — la fusion ne blanchit pas une saisie fausse.
 *
 * ## Archivage par `actif`
 *
 * Une `modification` portant `actif` archive ou restaure — par le service
 * (verrou d'engagement : un fournisseur sous commande en cours ne s'archive
 * pas) et sous la règle d'archivage de la directive du 03/09/2026
 * (`DroitArchivageService`), la même que l'écran PWA. À la création, `actif`
 * est ignoré : une fiche naît active, l'archiver est un geste à part.
 */
final class GestionnaireFournisseurs extends GestionnaireAbstrait
{
    public function __construct(
        private readonly ReferentielFournisseurService $referentiel,
        private readonly DroitArchivageService $droitArchivage,
    ) {
    }

    public function table(): string
    {
        return 'fournisseurs';
    }

    public function module(): string
    {
        return 'M7';
    }

    public function serviceDomaine(): string
    {
        return ReferentielFournisseurService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    /**
     * La clé naturelle d'un fournisseur : raison sociale sans casse, sans
     * accents, espaces resserrés.
     */
    public static function cleNaturelle(string $raisonSociale): string
    {
        // Normalisation commune à tout le référentiel depuis S2 (15/10/2026).
        return CleNaturelle::normaliser($raisonSociale);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        unset($payload['id'], $payload['actif']);

        $donnees = $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerFournisseurRequest::class),
            EnregistrerFournisseurRequest::class,
        );

        $equivalent = $this->equivalent((string) $donnees['raison_sociale']);

        if ($equivalent !== null) {
            return new EcritureSynchronisee(
                $equivalent->id,
                fusionneAvec: $equivalent->id,
                // Le poste doit savoir que la fiche à laquelle il se rattache
                // est rangée : ses prochaines commandes la citeront, et l'écran
                // ne la propose plus.
                complements: (bool) $equivalent->actif ? [] : ['cible_archivee' => true],
            );
        }

        $this->referentiel->creer([...$donnees, 'id' => $entiteId]);

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * Création perdue en route : traitée comme une création si le payload
     * est complet (décision PO du 15/10/2026), sinon rejet motivé.
     */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return $this->creerDepuisModification($entiteId, $payload, $contexte);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $fournisseur = Fournisseur::query()->lockForUpdate()->findOrFail($entiteId);

        $actif = array_key_exists('actif', $payload) ? $payload['actif'] : null;
        unset($payload['actif'], $payload['id']);

        // Payload PARTIEL (décision PO du 15/10/2026) : seuls les champs
        // présents changent, validés par les règles de
        // `PUT /achats/fournisseurs/{id}` ; un payload réduit à `actif` est un
        // archivage (ou une restauration) seul.
        if ($payload !== []) {
            $donnees = $this->validerPartiel(
                $fournisseur,
                $payload,
                $this->reglesDeLApi(EnregistrerFournisseurRequest::class, 'fournisseur', $fournisseur),
                EnregistrerFournisseurRequest::class,
            );

            if ($donnees !== []) {
                $this->referentiel->modifier($fournisseur, $donnees);
            }
        }

        if ($actif !== null) {
            $this->basculerArchive($fournisseur, $this->booleen($actif), $contexte);
        }

        return new EcritureSynchronisee($entiteId);
    }

    private function basculerArchive(Fournisseur $fournisseur, bool $actif, ContexteSynchronisation $contexte): void
    {
        if ((bool) $fournisseur->actif === $actif) {
            return;
        }

        if (! $this->droitArchivage->peutArchiver($contexte->utilisateur, $this->module())) {
            throw new RuntimeException(__('pwa.archivage.refus_bascule'));
        }

        $actif
            ? $this->referentiel->restaurer($fournisseur)
            : $this->referentiel->archiver($fournisseur);
    }

    /**
     * La fiche serveur de même clé naturelle — active de préférence, si deux
     * fiches historiques la partagent (le référentiel en ligne n'interdit pas
     * l'homonymie).
     */
    private function equivalent(string $raisonSociale): ?Fournisseur
    {
        $cle = self::cleNaturelle($raisonSociale);

        return Fournisseur::query()
            ->lockForUpdate()
            ->orderBy('date_creation')
            ->get(['id', 'raison_sociale', 'actif'])
            ->filter(static fn (Fournisseur $f): bool => self::cleNaturelle((string) $f->raison_sociale) === $cle)
            ->sortByDesc(static fn (Fournisseur $f): int => (int) (bool) $f->actif)
            ->first();
    }
}
