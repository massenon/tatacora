<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Providers;

use App\Domain\Facturation\Services\MecefClientFake;
use App\Domain\Facturation\Services\MecefClientInterface;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Support\ServiceProvider;

/**
 * Bascule Fake/Réel de la certification MECeF — MECEF_INTEGRATION_SPEC.md §7.3.
 *
 * **La bascule dépend de la PRÉSENCE de la clé en configuration serveur, jamais
 * d'un paramètre lisible en base.** Un drapeau `mecef_actif` dans
 * `parametres_systeme` permettrait à un Administrateur d'activer le mode réel
 * sans que la clé existe — les factures partiraient alors en échec de
 * certification silencieux. La configuration est la seule source qui ne peut
 * pas mentir sur sa propre disponibilité.
 *
 * Deux conditions cumulatives :
 * - `entreprise_numero_mecef` renseigné (identifiant, donc en base — ce n'est
 *   pas un secret, au même titre que l'IFU) ;
 * - `MECEF_API_KEY` présent en `.env` (secret, donc jamais en base).
 *
 * Tant que PA-17 n'est pas résolue, **aucune configuration ne suffit** :
 * `MecefClient` n'existe pas, `MecefClientFake` est le seul liable.
 */
final class MecefServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->bind(MecefClientInterface::class, function () {
            // PA-17 : `MecefClient` (implémentation réelle) n'existe pas encore
            // — la documentation technique DGI n'a pas été reçue. Le contrat
            // interne est figé (`MecefClientInterface`), seule l'implémentation
            // manque.
            //
            // Il n'y a donc RIEN à arbitrer ici : le jour où le client réel
            // existera, la condition de bascule reviendra, mais l'écrire
            // aujourd'hui produirait un `if` dont les deux branches rendent le
            // même objet — c'est-à-dire du code qui a l'apparence d'un choix
            // sans en être un. `estModeRelDisponible()` porte la condition,
            // seule et testable.
            return new MecefClientFake();
        });
    }

    /**
     * La configuration serveur est-elle en état de porter le mode réel ?
     *
     * Répond sur la CONFIGURATION seule, jamais sur ce qui est réellement lié.
     * Séparer les deux est le point de PA-61 : une configuration complète ne
     * rend pas les factures certifiées tant que le client réel n'existe pas.
     */
    public static function estModeReelDisponible(): bool
    {
        $numeroContribuable = app(ParametreSystemeService::class)->get('entreprise_numero_mecef');
        $cleApi = config('services.mecef.api_key');

        // `filled()` et non `isset()` : une valeur présente mais vide, ou
        // restée au marqueur CHANGE_ME_ du .env.example, ne doit surtout pas
        // faire basculer en mode réel.
        return filled($numeroContribuable)
            && filled($cleApi)
            && ! str_starts_with((string) $cleApi, 'CHANGE_ME_');
    }

    /**
     * État de configuration, destiné au badge de l'écran Paramètres
     * (MECEF_INTEGRATION_SPEC.md §7.4). Quatre états distincts, jamais un
     * simple booléen : « numéro renseigné mais clé absente » est une situation
     * réelle qu'un administrateur doit pouvoir diagnostiquer.
     *
     * **`active` est dérivé du client RÉELLEMENT LIÉ, pas de la configuration**
     * (PA-61, 19/08/2026). La version précédente renvoyait `active` dès que le
     * numéro et la clé étaient présents — alors que `register()` liait le faux
     * client dans les deux branches de son ternaire. Le badge aurait donc
     * annoncé « active » pendant que chaque facture partait avec
     * `DONNEES-NON-CERTIFIEES-DEMO` en cachet fiscal. C'est la même famille de
     * défaut que le fichier de sauvegarde de 802 octets (PA-60) — un indicateur
     * qui dit « tout va bien » pendant que rien n'a lieu — mais sur une matière
     * fiscale, et sur un document remis au client.
     *
     * @return 'non_configuree'|'configuration_partielle'|'en_attente_implementation'|'active'
     */
    public static function etatConfiguration(): string
    {
        $numero = app(ParametreSystemeService::class)->get('entreprise_numero_mecef');

        if (blank($numero)) {
            return 'non_configuree';
        }

        if (! self::estModeReelDisponible()) {
            return 'configuration_partielle';
        }

        // Configuration complète. Reste à savoir si elle sert à quelque chose :
        // seul le client lié peut le dire.
        return app(MecefClientInterface::class)->estModeReel()
            ? 'active'
            : 'en_attente_implementation';
    }
}
