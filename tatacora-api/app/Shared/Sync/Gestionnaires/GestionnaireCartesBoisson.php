<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Bar\Http\Requests\EnregistrerBoissonRequest;
use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use Illuminate\Database\Eloquent\Model;

/**
 * Boissons de la carte du bar créées hors connexion (M5, EF-M5-02) — lot S2,
 * décision du Product Owner du 15/10/2026. Patron commun :
 * `GestionnaireReferentielAbstrait`.
 *
 * ## Clé naturelle : le libellé normalisé
 *
 * La règle du poste (`CatalogueDao.libelleBoissonExiste`) : deux « Béninoise
 * 33 cl » mettent deux entrées au point de vente, et le barman ne peut pas
 * savoir laquelle décrémente quoi — « deux contenances = deux articles »,
 * donc un libellé, une boisson. L'article lié n'entre pas dans la clé : la
 * même boisson liée à deux articles différents par deux postes reste UNE
 * boisson, et c'est le lien du serveur qui fait foi.
 *
 * ## L'article cité est traduit, puis exigé
 *
 * `article_id` est NOT NULL au schéma (RG-05) : il passe par les
 * correspondances (article créé hors connexion et fusionné), puis par la
 * règle `exists` de l'API — un article jamais synchronisé est rejeté avec la
 * phrase de l'écran en ligne. Le poste doit donc pousser l'article AVANT la
 * boisson, dans sa file.
 *
 * ## Module M5, niveau C — celui de `POST /bar/boissons`.
 *
 * ## Modification refusée
 *
 * Un prix de vente changé hors connexion serait appliqué à de vrais clients
 * par tous les postes, et l'historique des prix (`historique_prix_carte`)
 * daterait du jour de réception un changement fait trois jours plus tôt. Le
 * lien au stock porte un conditionnement (×24) qui décrémente le stock : se
 * tromper vide le stock 24 fois trop vite. Le serveur est maître.
 */
final class GestionnaireCartesBoisson extends GestionnaireReferentielAbstrait
{
    protected const REFERENCES = ['article_id' => 'articles'];

    public function __construct(
        private readonly CarteBoissonService $carte,
        ResolveurCorrespondances $correspondances,
    ) {
        parent::__construct($correspondances);
    }

    public function table(): string
    {
        return 'cartes_boisson';
    }

    public function module(): string
    {
        return 'M5';
    }

    public function serviceDomaine(): string
    {
        return CarteBoissonService::class;
    }

    protected function validerCreation(array $payload): array
    {
        return $this->valider(
            $payload,
            $this->reglesDeLApi(EnregistrerBoissonRequest::class),
            EnregistrerBoissonRequest::class,
        );
    }

    protected function equivalent(array $donnees): ?Model
    {
        return $this->premierDeCle(
            CarteBoisson::query()->orderBy('date_creation')->orderBy('id'),
            $this->cle((string) $donnees['libelle']),
            fn (CarteBoisson $b): string => $this->cle($b->libelle),
        );
    }

    protected function ecrire(string $entiteId, array $donnees, ContexteSynchronisation $contexte): void
    {
        $this->carte->creer([...$donnees, 'id' => $entiteId]);
    }
}
