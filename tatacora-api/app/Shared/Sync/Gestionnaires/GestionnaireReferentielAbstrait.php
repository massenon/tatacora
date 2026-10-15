<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Shared\Rbac\Services\DroitArchivageService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\CleNaturelle;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use LogicException;
use RuntimeException;

/**
 * Le patron commun des référentiels du CATALOGUE créés hors connexion — lot S2
 * (décision du Product Owner du 15/10/2026).
 *
 * ## Le poste crée hors connexion, le serveur fusionne
 *
 * Les postes TÉLÉCHARGENT le catalogue (`GET /api/v1/referentiels`) : mêmes
 * identifiants partout. Mais un poste coupé du serveur doit pouvoir créer
 * l'article livré ce matin, la boisson ajoutée à l'ardoise, la chambre
 * rouverte. À la synchronisation, dans cet ordre :
 *
 * 1. les identifiants CITÉS (l'article d'une boisson, la catégorie d'une
 *    unité, le menu et la fiche d'un plat) sont traduits par
 *    `ResolveurCorrespondances` — un article fusionné hier est cité ce matin
 *    sous l'UUID du poste ;
 * 2. le document est validé par les RÈGLES ET PHRASES de l'écran en ligne
 *    (FormRequest de l'API), contrainte d'unicité de la clé naturelle seule
 *    retirée (`sansUnicite()`) : un document faux est rejeté AVANT toute
 *    recherche d'équivalent — la fusion ne blanchit pas une saisie fausse ;
 * 3. l'équivalent serveur est cherché sur la CLÉ NATURELLE normalisée
 *    (`CleNaturelle`), sous verrou `FOR UPDATE` — deux lots concurrents qui
 *    créent le même élément se sérialisent, le second voit le premier ;
 * 4. trouvé → FUSION : rien n'est créé, rien n'est écrasé, le moteur retient
 *    la correspondance et le poste reçoit `fusionne_avec` ; absent → création
 *    sous l'UUID du poste, par le SERVICE de domaine (audit RG-15 compris).
 *
 * ## Modification : ACCEPTÉE, en dernier écrit gagnant (décision PO du 15/10/2026)
 *
 * ⚠ REMPLACE la règle du lot S2 (« modification refusée pour tout le
 * catalogue, le serveur est maître »), levée par la décision du Product
 * Owner du 15/10/2026 : l'offline-first est TOTAL. Un poste coupé du serveur
 * pendant des jours doit pouvoir créer ET modifier articles, boissons, plats,
 * menus, fiches (et leur composition), points de stockage, catégories et
 * unités d'hébergement — et fournisseurs (`GestionnaireFournisseurs`).
 *
 * À la synchronisation d'une `modification` :
 *
 * 1. la cible est identifiée par son id, traduit par
 *    `ResolveurCorrespondances` (un UUID de poste fusionné plus tôt désigne
 *    l'élément serveur) — c'est le moteur qui le fait ;
 * 2. l'arbitrage est le DERNIER ÉCRIT GAGNANT sur l'horodatage de SAISIE
 *    (`SynchronisationService`, machinerie RG-17) : une modification plus
 *    ancienne que la dernière appliquée perd (`version_serveur_conservee`),
 *    une plus récente gagne. Le catalogue n'est pas financier : jamais
 *    d'arbitrage manuel, mais la ligne de conflit est enregistrée ;
 * 3. le payload est PARTIEL — seuls les champs présents changent — et validé
 *    par les règles de MODIFICATION de l'API (`validerPartiel()`), mêmes
 *    phrases ; les valeurs CALCULÉES (stock, CMP, prix d'achat, coût
 *    matière) restent refusées exactement comme la route les refuse ;
 * 4. l'écriture passe par la méthode de modification du SERVICE de domaine
 *    (audit RG-15 compris) ;
 * 5. `actif` archive ou restaure, par le service et sous la règle de droits
 *    de l'écran en ligne (`DroitArchivageService`) — pour les seules tables
 *    qui s'archivent (articles, unités d'hébergement ; fournisseurs à part).
 *    Ailleurs, demander l'archivage est refusé avec motif.
 *
 * Une modification d'un identifiant que le serveur ne connaît pas (création
 * perdue en route) est traitée comme une CRÉATION si son payload satisfait
 * les règles de création, sinon rejetée avec motif
 * (`creerDepuisModification()`).
 *
 * Les champs de cycle de vie (`actif`, `statut`) sont IGNORÉS à la création :
 * un élément naît actif (libre pour une unité) ; l'archiver est un geste à
 * part. `statut` d'une unité reste ignoré en modification : le cycle
 * appartient à `SejourService`.
 */
abstract class GestionnaireReferentielAbstrait extends GestionnaireAbstrait
{
    /**
     * Les champs du payload qui citent un autre élément du référentiel :
     * champ => table de l'élément cité.
     *
     * @var array<string, string>
     */
    protected const REFERENCES = [];

    /**
     * Champs ignorés à la création (cycle de vie, protocole).
     *
     * @var list<string>
     */
    protected const CHAMPS_IGNORES = ['id', 'actif', 'statut'];

    /**
     * Requête d'API dont les règles et phrases valident la MODIFICATION, et
     * nom du paramètre de route qui la met en mode modification.
     *
     * @var class-string<\Illuminate\Foundation\Http\FormRequest>|null
     */
    protected const REQUETE = null;

    protected const PARAMETRE_ROUTE = null;

    public function __construct(protected readonly ResolveurCorrespondances $correspondances)
    {
    }

    /** Décision PO du 15/10/2026 : tout le catalogue se modifie hors connexion. */
    public function accepteModification(): bool
    {
        return true;
    }

    final public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $element = $this->trouver($entiteId);

        $actif = array_key_exists('actif', $payload) ? $this->booleen($payload['actif']) : null;

        foreach (static::CHAMPS_IGNORES as $champ) {
            unset($payload[$champ]);
        }

        $payload = $this->resoudreReferences($payload);

        if ($payload !== []) {
            $donnees = $this->validerModification($element, $payload);

            if ($donnees !== []) {
                $this->ecrireModification($element, $donnees, $contexte);
            }
        }

        if ($actif !== null) {
            $this->basculerArchive($element->refresh(), $actif, $contexte);
        }

        return new EcritureSynchronisee($entiteId);
    }

    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return $this->creerDepuisModification($entiteId, $payload, $contexte);
    }

    /**
     * L'élément à modifier, sous verrou — l'id est déjà résolu par le moteur.
     */
    abstract protected function trouver(string $entiteId): Model;

    /**
     * Valide les champs présents par les règles de MODIFICATION de l'API.
     *
     * @param  array<string, mixed>  $payload  références déjà traduites
     * @return array<string, mixed>
     */
    protected function validerModification(Model $element, array $payload): array
    {
        $requete = static::REQUETE;

        if ($requete === null) {
            throw new LogicException(__('sync.interne.modification_non_declaree', ['table' => $this->table()]));
        }

        return $this->validerPartiel(
            $element,
            $payload,
            $this->reglesDeLApi($requete, static::PARAMETRE_ROUTE ?? 'element', $element),
            $requete,
        );
    }

    /**
     * Écrit les champs validés par la méthode de MODIFICATION du service.
     *
     * @param  array<string, mixed>  $donnees
     */
    abstract protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void;

    /** La table s'archive-t-elle (`actif` / `hors_service`) ? */
    protected function archivable(): bool
    {
        return false;
    }

    protected function archiver(Model $element): void
    {
        throw new LogicException(__('sync.interne.modification_non_declaree', ['table' => $this->table()]));
    }

    protected function restaurer(Model $element): void
    {
        throw new LogicException(__('sync.interne.modification_non_declaree', ['table' => $this->table()]));
    }

    /**
     * Archive ou restaure par le service, sous la règle de droits de l'écran
     * en ligne — la même que `GestionnaireFournisseurs`.
     */
    private function basculerArchive(Model $element, bool $actif, ContexteSynchronisation $contexte): void
    {
        if (! $this->archivable()) {
            // Rien à restaurer sur une table sans archive ; ranger, en
            // revanche, ne peut pas être promis puis ignoré.
            if (! $actif) {
                throw new RuntimeException(__('sync.archivage_non_disponible'));
            }

            return;
        }

        if ($this->estArchive($element) === ! $actif) {
            return;
        }

        if (! app(DroitArchivageService::class)->peutArchiver($contexte->utilisateur, $this->module())) {
            throw new RuntimeException(__('pwa.archivage.refus_bascule'));
        }

        $actif ? $this->restaurer($element) : $this->archiver($element);
    }

    final public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        foreach (static::CHAMPS_IGNORES as $champ) {
            unset($payload[$champ]);
        }

        $payload = $this->resoudreReferences($payload);
        $donnees = $this->validerCreation($payload);
        $equivalent = $this->equivalent($donnees);

        if ($equivalent !== null) {
            $idServeur = (string) $equivalent->getKey();

            return new EcritureSynchronisee(
                $idServeur,
                fusionneAvec: $idServeur,
                // Le poste doit savoir que l'élément auquel il se rattache est
                // rangé : l'écran ne le propose plus, ses documents le citent.
                complements: $this->estArchive($equivalent) ? ['cible_archivee' => true] : [],
            );
        }

        $this->ecrire($entiteId, $donnees, $contexte);

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * Valide le payload (références déjà traduites) — règles et phrases de
     * l'API — et rend les seules données validées.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    abstract protected function validerCreation(array $payload): array;

    /**
     * L'élément serveur équivalent sur la clé naturelle, ou `null`.
     *
     * @param  array<string, mixed>  $donnees
     */
    abstract protected function equivalent(array $donnees): ?Model;

    /**
     * Crée l'élément sous l'UUID du poste, par le service de domaine.
     *
     * @param  array<string, mixed>  $donnees
     */
    abstract protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void;

    protected function estArchive(Model $element): bool
    {
        return false;
    }

    /**
     * Le premier élément de `$requete` dont la clé naturelle vaut `$cle`, sous
     * verrou `FOR UPDATE`.
     *
     * La comparaison est faite en PHP (normalisation sans casse ni accents,
     * que SQL ne sait pas rendre identique à celle du poste) : le catalogue se
     * compte en centaines de lignes, pas en millions. Une colonne normalisée
     * indexée serait la suite si le volume l'exigeait.
     *
     * @template TModele of Model
     *
     * @param  Builder<TModele>  $requete  déjà ordonnée — le premier gagne
     * @param  callable(TModele): string  $cleDe
     * @return TModele|null
     */
    protected function premierDeCle(Builder $requete, string $cle, callable $cleDe): ?Model
    {
        return $requete->lockForUpdate()->get()->first(
            static fn (Model $element): bool => $cleDe($element) === $cle,
        );
    }

    protected function cle(?string ...$parties): string
    {
        return CleNaturelle::de(...$parties);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function resoudreReferences(array $payload): array
    {
        foreach (static::REFERENCES as $champ => $table) {
            $valeur = $payload[$champ] ?? null;

            if (is_string($valeur) && $valeur !== '') {
                $payload[$champ] = $this->correspondances->resoudre($table, $valeur);
            }
        }

        return $payload;
    }
}
