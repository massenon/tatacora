<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Routing\Route;
use LogicException;

/**
 * Fait le pont entre les validations des composants Livewire et les `FormRequest` de l'API.
 */
final class ReglesDeLApi
{
    /**
     * Extrait les règles de validation pour une CRÉATION.
     *
     * @param class-string<FormRequest> $requete
     * @param array<string, string> $correspondance Champ API => Propriété Livewire
     * @return array<string, mixed>
     */
    public static function pourCreation(string $requete, array $correspondance): array
    {
        return self::remapper(self::reglesAvecRoute($requete, []), $correspondance, $requete);
    }

    /**
     * Extrait les règles de validation pour une MODIFICATION.
     *
     * @param class-string<FormRequest> $requete
     * @param array<string, string> $correspondance Champ API => Propriété Livewire
     * @return array<string, mixed>
     */
    public static function pourModification(
        string $requete,
        string $parametreDeRoute,
        Model $modele,
        array $correspondance,
    ): array {
        return self::remapper(
            self::reglesAvecRoute($requete, [$parametreDeRoute => $modele]),
            $correspondance,
            $requete,
        );
    }

    /**
     * @param  class-string<FormRequest>  $classe
     * @param  array<string, Model>  $parametres
     * @return array<string, mixed>
     */
    private static function reglesAvecRoute(string $classe, array $parametres): array
    {
        $requete = new $classe();

        if (! method_exists($requete, 'rules')) {
            throw new LogicException(__('pwa.support.regles_sans_methode', ['classe' => $classe]));
        }

        $route = new Route(['POST'], '/pwa/regles-internes', static fn () => null);
        $route->parameters = $parametres;

        $requete->setRouteResolver(static fn (): Route => $route);

        return $requete->rules();
    }

    /**
     * @param  array<string, mixed>  $regles
     * @param  array<string, string>  $correspondance
     * @return array<string, mixed>
     */
    private static function remapper(array $regles, array $correspondance, string $classe): array
    {
        $resultat = [];

        foreach ($correspondance as $champApi => $propriete) {
            if (! array_key_exists($champApi, $regles)) {
                throw new LogicException(__('pwa.support.champ_api_inconnu', [
                    'champ' => $champApi,
                    'classe' => $classe,
                ]));
            }

            $resultat[$propriete] = $regles[$champApi];
        }

        return $resultat;
    }
}
