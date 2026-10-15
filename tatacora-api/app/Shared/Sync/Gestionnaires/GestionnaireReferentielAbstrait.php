<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\CleNaturelle;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * Le patron commun des référentiels du CATALOGUE créés hors connexion — lot S2
 * (décision du Product Owner du 15/10/2026).
 *
 * ## Le serveur est maître, le poste peut quand même créer
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
 * ## Modification : refusée pour tout le catalogue
 *
 * `accepteModification()` reste à `false` (défaut de `GestionnaireAbstrait`)
 * pour chaque table du catalogue, décision prise table par table et motivée
 * dans chaque gestionnaire. La règle commune : le serveur est maître, et une
 * modification hors connexion arbitrée en dernier écrit gagnant laisserait un
 * poste resté trois jours hors ligne réécrire un prix, une unité de mesure ou
 * une composition que le gérant a corrigés entre-temps. Aucune n'a paru
 * « trivialement sûre » : la plus anodine (un seuil d'alerte) commande les
 * alertes RG-07 de TOUS les postes. Le poste fait la modification en ligne,
 * puis la reçoit par le flux descendant.
 *
 * Les champs de cycle de vie (`actif`, `statut`) sont IGNORÉS à la création :
 * un élément naît actif (libre pour une unité) ; l'archiver est un geste à
 * part, en ligne.
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

    public function __construct(protected readonly ResolveurCorrespondances $correspondances)
    {
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
