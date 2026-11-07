<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;

/**
 * Le MODE de la facturation normalisée — docs/SPEC_FACTURATION_NORMALISEE_MECEF.md §1.
 *
 * Registre fermé : une valeur inconnue en base (clé effacée, valeur écrite à
 * la main) retombe sur `Desactive`, jamais sur un mode réel. Se tromper dans
 * ce sens produit des factures de démonstration (visibles, marquées DEMO) ;
 * l'autre sens produirait une transmission fiscale non voulue.
 */
enum ModeFacturation: string
{
    /** Comportement historique : `MecefClientFake`, factures DEMO sans valeur fiscale. */
    case Desactive = 'desactive';

    /** e-MECeF : le SERVEUR certifie par l'API de la DGI (réseau exigé). */
    case Emecef = 'emecef';

    /** Boîtier CC300 : le POSTE de la réception certifie ; le serveur ne certifie PAS. */
    case Boitier = 'boitier';

    public const CLE = 'facturation_mode';

    public static function courant(): self
    {
        return self::depuis(app(ParametreSystemeService::class)->get(self::CLE));
    }

    public static function depuis(?string $valeur): self
    {
        return self::tryFrom(strtolower(trim((string) $valeur))) ?? self::Desactive;
    }

    public function libelle(): string
    {
        return match ($this) {
            self::Desactive => 'Désactivé',
            self::Emecef => 'e-MECeF (en ligne)',
            self::Boitier => 'Boîtier CC300 (poste)',
        };
    }

    /** @return list<string> */
    public static function valeurs(): array
    {
        return array_map(static fn (self $m): string => $m->value, self::cases());
    }
}
