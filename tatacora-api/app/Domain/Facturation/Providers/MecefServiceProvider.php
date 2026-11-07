<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Providers;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Services\MecefClientEmecef;
use App\Domain\Facturation\Services\MecefClientFake;
use App\Domain\Facturation\Services\MecefClientInterface;
use App\Domain\Facturation\Services\MecefClientRefus;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\Secrets\Services\SecretsConfigurationService;
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
        $this->app->bind(MecefClientInterface::class, function (): MecefClientInterface {
            // Le MODE de la facturation normalisée choisit l'implémentation
            // (docs/SPEC_FACTURATION_NORMALISEE_MECEF.md §1) :
            //  - désactivé : le faux client, factures DEMO sans valeur fiscale ;
            //  - e-MECeF : le client réel SI IFU, adresse https, opérateur et jeton sont
            //    là — sinon un refus clair, en français, jamais un repli sur la démo ;
            //  - boîtier : le serveur ne certifie PAS (la facture attend le poste) ; le
            //    faux client n'est lié que pour que le contrat reste satisfait, et
            //    `EmissionFactureService::certifier` ne l'appelle pas dans ce mode.
            return match (ModeFacturation::courant()) {
                ModeFacturation::Emecef => $this->clientEmecef(),
                default => new MecefClientFake(),
            };
        });
    }

    private function clientEmecef(): MecefClientInterface
    {
        $reglages = app(ReglagesMecef::class);
        $manques = $reglages->manquantsEmecef();

        return $manques === []
            ? new MecefClientEmecef($reglages, app(SecretsConfigurationService::class), app(CalculTvaService::class))
            : new MecefClientRefus($manques);
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
     * @return 'non_configuree'|'configuration_partielle'|'en_attente_implementation'|'active'|'emecef_incomplet'|'emecef_actif'|'boitier_au_poste'
     */
    public static function etatConfiguration(): string
    {
        // Facturation normalisée (07/11/2026) : dès qu'un mode réel est CHOISI,
        // l'état dérive du mode et du client réellement lié.
        $mode = ModeFacturation::courant();

        if ($mode === ModeFacturation::Boitier) {
            return 'boitier_au_poste';
        }

        if ($mode === ModeFacturation::Emecef) {
            return app(ReglagesMecef::class)->manquantsEmecef() === [] && app(MecefClientInterface::class)->estModeReel()
                ? 'emecef_actif'
                : 'emecef_incomplet';
        }

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
