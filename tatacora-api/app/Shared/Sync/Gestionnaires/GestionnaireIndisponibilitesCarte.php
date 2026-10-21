<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Carte\Services\DisponibiliteCarteService;
use App\Domain\Restaurant\Models\Plat;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Le retrait d'un article de la carte du jour (`indisponibilites_carte`)
 * fait sur un poste — lot « indisponibilités de la carte » (21/10/2026,
 * décision du PO : « ce que le web fait, le poste le fait »).
 *
 * Par `DisponibiliteCarteService`, et lui seul. Une boisson relève de M5, un
 * plat de M4 : le droit exigé est celui du RAYON de l'article (RG-16), comme
 * à la PWA.
 *
 * - création : l'article devient indisponible (rupture, saison, retiré) à
 *   l'instant du poste ; une indisponibilité déjà EN COURS pour le même
 *   article FUSIONNE (`fusionne_avec`) — l'article est indisponible, qui que
 *   l'ait retiré, et on ne double jamais la ligne ;
 * - modification : la remise à la carte (`date_retour_disponibilite`) ; déjà
 *   remise ailleurs, elle ne rejette pas (l'article est bien disponible).
 */
final class GestionnaireIndisponibilitesCarte extends GestionnaireAbstrait
{
    public function __construct(private readonly DisponibiliteCarteService $carte)
    {
    }

    public function table(): string
    {
        return 'indisponibilites_carte';
    }

    /** Par défaut le bar ; un plat exige M4 (`modulesRequis`). */
    public function module(): string
    {
        return 'M5';
    }

    public function modulesRequis(array $payload): array
    {
        return [isset($payload['plat_id']) && $payload['plat_id'] !== null ? 'M4' : 'M5'];
    }

    public function serviceDomaine(): string
    {
        return DisponibiliteCarteService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerGeste($payload, [
            'boisson_id' => ['nullable', 'string'],
            'plat_id' => ['nullable', 'string'],
            'motif' => ['required', 'string'],
            'commentaire' => ['nullable', 'string', 'max:500'],
            'date_indisponibilite' => ['nullable', 'date'],
        ]);

        $article = $this->article($donnees);
        $existante = $this->carte->indisponibilite($article);

        if ($existante !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existante->id);
        }

        $this->carte->rendreIndisponible(
            $article,
            (string) $donnees['motif'],
            $donnees['commentaire'] ?? null,
            (string) $contexte->utilisateur->id,
            $entiteId,
            isset($donnees['date_indisponibilite']) ? CarbonImmutable::parse((string) $donnees['date_indisponibilite']) : $contexte->horodatageClient,
        );

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), ['date_retour_disponibilite']);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.carte.champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        $ligne = IndisponibiliteCarte::query()->findOrFail($entiteId);

        if ($ligne->date_retour_disponibilite !== null) {
            return new EcritureSynchronisee($entiteId);
        }

        $article = $ligne->boisson_id !== null
            ? CarteBoisson::query()->findOrFail($ligne->boisson_id)
            : Plat::query()->findOrFail($ligne->plat_id);

        $retour = isset($payload['date_retour_disponibilite'])
            ? CarbonImmutable::parse((string) $payload['date_retour_disponibilite'])
            : $contexte->horodatageClient;

        $this->carte->rendreDisponible($article, (string) $contexte->utilisateur->id, $retour);

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    private function article(array $donnees): CarteBoisson|Plat
    {
        $boisson = $donnees['boisson_id'] ?? null;
        $plat = $donnees['plat_id'] ?? null;

        if (($boisson === null) === ($plat === null)) {
            throw new RuntimeException(__('sync.carte.un_seul_article'));
        }

        $article = $boisson !== null
            ? CarteBoisson::query()->find((string) $boisson)
            : Plat::query()->find((string) $plat);

        return $article ?? throw new RuntimeException(__('sync.carte.article_inconnu'));
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $regles
     * @return array<string, mixed>
     */
    private function validerGeste(array $payload, array $regles): array
    {
        $validateur = Validator::make($payload, $regles);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
    }
}
