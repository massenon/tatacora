<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use App\Shared\Secrets\Services\SecretsConfigurationService;

/**
 * Lecteur UNIQUE des réglages de la facturation normalisée (non secrets) —
 * l'IFU, l'adresse de l'API de la DGI, l'opérateur — et vérificateur de leur
 * complétude. Le JETON, lui, ne passe ici que par {@see jetonRenseigne()} (un
 * booléen) : sa valeur n'est lue que par `MecefClientEmecef`.
 */
final class ReglagesMecef
{
    public const CLE_API_URL = 'mecef_api_url';

    public const CLE_OPERATEUR_ID = 'mecef_operateur_id';

    public const CLE_OPERATEUR_NOM = 'mecef_operateur_nom';

    public const URL_API_PAR_DEFAUT = 'https://developper.impots.bj/sygmef-emcf/api';

    /** L'IFU béninois : 13 chiffres (règle unique, serveur et poste). */
    public const FORMAT_IFU = '/^[0-9]{13}$/';

    /**
     * Les clés que seul un administrateur règle. Depuis le 09/11/2026 un poste les
     * écrit aussi (« le poste fait ce que le web fait »), SI le compte de son jeton
     * d'appairage est administrateur (`GestionnaireParametres::refusDeDroit`). Le
     * JETON e-MECeF, lui, n'est pas un paramètre : il ne descend ni ne monte jamais.
     *
     * @var list<string>
     */
    public const CLES_ADMINISTRATEUR = [
        ModeFacturation::CLE,
        self::CLE_API_URL,
        self::CLE_OPERATEUR_ID,
        self::CLE_OPERATEUR_NOM,
    ];

    public function __construct(
        private readonly ParametreSystemeService $parametres,
        private readonly SecretsConfigurationService $secrets,
    ) {
    }

    public function ifu(): string
    {
        return trim((string) $this->parametres->get(ReportHeaderService::CLE_IFU));
    }

    public static function ifuValide(string $ifu): bool
    {
        // `strlen` : `$` accepte un retour à la ligne final, jamais une IFU de 13 chiffres.
        return strlen($ifu) === 13 && preg_match(self::FORMAT_IFU, $ifu) === 1;
    }

    /** L'adresse saisie, sinon celle de la DGI — sans barre finale. */
    public function urlApi(): string
    {
        $saisie = trim((string) $this->parametres->get(self::CLE_API_URL));

        return rtrim($saisie !== '' ? $saisie : self::URL_API_PAR_DEFAUT, '/');
    }

    public function operateurId(): string
    {
        return trim((string) $this->parametres->get(self::CLE_OPERATEUR_ID));
    }

    public function operateurNom(): string
    {
        return trim((string) $this->parametres->get(self::CLE_OPERATEUR_NOM));
    }

    public function jetonRenseigne(): bool
    {
        return $this->secrets->lire(SecretsConfigurationService::MECEF_JETON) !== null;
    }

    /**
     * Ce qui manque pour le mode e-MECeF (liste de phrases françaises), vide
     * quand tout est là. Aucune valeur n'est jamais citée.
     *
     * @return list<string>
     */
    public function manquantsEmecef(): array
    {
        $manques = [];

        if (! self::ifuValide($this->ifu())) {
            $manques[] = __('parametres.mecef_manque_ifu');
        }
        if (! str_starts_with(strtolower($this->urlApi()), 'https://')) {
            $manques[] = __('parametres.mecef_manque_https');
        }
        if ($this->operateurId() === '' || $this->operateurNom() === '') {
            $manques[] = __('parametres.mecef_manque_operateur');
        }
        if (! $this->jetonRenseigne()) {
            $manques[] = __('parametres.mecef_manque_jeton');
        }

        return $manques;
    }
}
