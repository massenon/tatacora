<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

use App\Shared\Parametres\Services\ParametreSystemeService;

/**
 * LA FORME JURIDIQUE de l'établissement — décision du PO du 09/11/2026 : « le
 * Gîte est une ENTREPRISE INDIVIDUELLE (pas une SARL) ». Elle commande les
 * règles de l'affectation du résultat ({@see \App\Domain\Comptabilite\Services\AffectationResultatService}) :
 *
 *  - entreprise individuelle : ni réserve légale, ni dividendes, ni procès-verbal
 *    d'assemblée — le bénéfice se ventile librement entre le compte de
 *    l'exploitant (104), le report à nouveau et les autres réserves ;
 *  - SARL / SA : réserve légale obligatoire (10 % jusqu'à 20 % du capital),
 *    dividendes encadrés, alerte sous la moitié du capital.
 *
 * Registre fermé : une valeur inconnue ou absente retombe sur l'ENTREPRISE
 * INDIVIDUELLE (le défaut du Gîte) — le sens le plus prudent, qui n'offre ni
 * dividende ni réserve légale.
 *
 * Paramètre système `forme_juridique`, réglé au serveur par un administrateur
 * (refusé tant qu'une affectation est active), descendu aux postes en lecture.
 */
enum FormeJuridique: string
{
    case EntrepriseIndividuelle = 'entreprise_individuelle';

    case Sarl = 'sarl';

    case Sa = 'sa';

    public const CLE = 'forme_juridique';

    public static function courante(): self
    {
        return self::depuis(app(ParametreSystemeService::class)->get(self::CLE));
    }

    public static function depuis(?string $valeur): self
    {
        return self::tryFrom(strtolower(trim((string) $valeur))) ?? self::EntrepriseIndividuelle;
    }

    /** Une société (SARL, SA) a des associés, une réserve légale et des dividendes. */
    public function estSociete(): bool
    {
        return $this !== self::EntrepriseIndividuelle;
    }

    public function libelle(): string
    {
        return (string) __('comptabilite.forme_juridique_' . $this->value);
    }

    /** @return list<string> */
    public static function valeurs(): array
    {
        return array_map(static fn (self $f): string => $f->value, self::cases());
    }
}
