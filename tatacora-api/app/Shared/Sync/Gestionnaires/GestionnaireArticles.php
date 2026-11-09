<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Stocks\Http\Requests\EnregistrerArticleRequest;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Articles de stock créés hors connexion (M6, EF-M6-01) — lot S2, décision du
 * Product Owner du 15/10/2026. Patron commun : `GestionnaireReferentielAbstrait`.
 *
 * ## Clé naturelle : libellé ET unité de mesure, normalisés
 *
 * Le serveur n'impose aucune unicité sur `articles` ; la clé est donc décidée
 * ici, et le libellé seul ne suffit pas. « Riz » au kilo et « Riz » au sac de
 * 50 kg sont deux articles : les fusionner ferait compter dans une même
 * colonne des kilos et des sacs, et chaque mouvement synchronisé ensuite (S3)
 * fausserait le stock d'un facteur 50 sans que rien ne le signale. Une
 * fusion à tort est pire qu'un doublon : le doublon se voit au catalogue, la
 * quantité fausse ne se voit qu'à l'inventaire. La catégorie, elle, n'entre
 * pas dans la clé — elle classe l'article, elle ne le définit pas.
 *
 * Les archivés sont cherchés aussi (un article rangé reste le même produit) ;
 * à clé égale, l'actif gagne, et la cible archivée est signalée au poste
 * (`cible_archivee`).
 *
 * ## Validation : `EnregistrerArticleRequest`, champs calculés compris
 *
 * Stock d'ouverture, coût moyen pondéré, dernier prix d'achat sont INTERDITS
 * comme à l'API (PA-24) : le stock d'ouverture saisi sur le poste remonte
 * comme un MOUVEMENT d'entrée (S3), jamais comme une colonne. Le point de
 * rattachement cité est traduit par les correspondances (un point créé hors
 * connexion puis fusionné).
 *
 * ## Module M6, niveau C — celui de `POST /stocks/articles`.
 *
 * ## Modification : acceptée, dernier écrit gagnant
 *
 * Décision du Product Owner du 15/10/2026, qui REMPLACE le refus du lot S2
 * (« le serveur est maître, modification refusée » ne vaut plus).
 * Par `ReferentielArticleService::modifier()`, règles de
 * `PUT /stocks/articles/{article}` sur les seuls champs présents : stock,
 * CMP, prix d'achat restent INTERDITS (phrase `valeur_calculee`). Le risque
 * qui motivait le refus — un poste resté hors ligne qui efface la correction
 * du gérant — est tenu par l'arbitrage sur l'horodatage de SAISIE : sa
 * modification, plus ancienne, perd (`version_serveur_conservee`).
 *
 * `actif` archive / restaure par `ReferentielArticleService` (verrous :
 * stock, commandes) sans juger le compte du jeton (09/11/2026).
 */
final class GestionnaireArticles extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['point_stockage_id' => 'points_stockage'];

    protected const REQUETE = EnregistrerArticleRequest::class;

    protected const PARAMETRE_ROUTE = 'article';

    public function __construct(
        private readonly ReferentielArticleService $referentiel,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'articles';
    }

    public function module(): string
    {
        return 'M6';
    }

    public function serviceDomaine(): string
    {
        return ReferentielArticleService::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerArticleRequest::class),
            EnregistrerArticleRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            Article::query()->orderByDesc('actif')->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle'], (string) $donnees['unite_mesure']),
            fn (Article $a): string => $this->cle($a->libelle, $a->unite_mesure),
        );
    }

    protected function estArchive(Model $element): bool
    {
        return ! (bool) $element->getAttribute('actif');
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->referentiel->creer([...$donnees, 'id' => $entiteId]);
    }

    protected function trouver(string $entiteId): Model
    {
        return Article::query()->lockForUpdate()->findOrFail($entiteId);
    }

    protected function ecrireModification(Model $element, array $donnees, ContexteSynchronisation $contexte): void
    {
        /** @var Article $element */
        $this->referentiel->modifier($element, $donnees);
    }

    /**
     * 09/11/2026 (PO) : la valeur d'achat de référence saisie au poste (colonne « Valeur
     * d'achat » des imports, v57) REMONTE sous `valeur_achat_reference` (décimal texte). Ce
     * n'est pas le champ `prix_achat` de la requête d'API (interdit : valeur calculée) : elle
     * est posée ici, SEULEMENT si l'article n'en porte pas déjà une, et descend ensuite à
     * tous les postes avec `prix_achat`.
     */
    protected function extraireComplements(array &$payload): array
    {
        $valeur = $payload['valeur_achat_reference'] ?? null;
        unset($payload['valeur_achat_reference']);

        if (! is_string($valeur) && ! is_int($valeur) && ! is_float($valeur)) {
            return [];
        }

        if (! is_numeric($valeur) || bccomp(number_format((float) $valeur, 2, '.', ''), '0', 2) <= 0) {
            return [];
        }

        return ['prix_achat' => number_format((float) $valeur, 2, '.', '')];
    }

    protected function appliquerComplements(Model $element, array $complements): void
    {
        /** @var Article $element */
        if ($element->prix_achat === null && isset($complements['prix_achat'])) {
            $element->forceFill(['prix_achat' => $complements['prix_achat']])->save();
        }
    }

    protected function archivable(): bool
    {
        return true;
    }

    protected function archiver(Model $element): void
    {
        /** @var Article $element */
        $this->referentiel->archiver($element);
    }

    protected function restaurer(Model $element): void
    {
        /** @var Article $element */
        $this->referentiel->restaurer($element);
    }
}
