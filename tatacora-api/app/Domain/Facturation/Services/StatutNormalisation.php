<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

/**
 * Le STATUT DE NORMALISATION d'une facture ou d'un avoir — registre fermé,
 * miroir du poste (`StatutNormalisation`, Dart ; parité prouvée par
 * `rejouer_regles_communes.php`). `docs/SPEC_FACTURATION_NORMALISEE_MECEF.md` §6.
 *
 * Absent (NULL en base) ne veut PAS dire « normalisée » : il dit « non
 * concernée » (démonstration, mode désactivé, pièce d'avant).
 */
enum StatutNormalisation: string
{
    /** Le boîtier ou la DGI a rendu un code : la pièce a une valeur fiscale. */
    case Normalisee = 'normalisee';

    /** Rien n'a été enregistré : la pièce attend et se rejoue. */
    case EnAttente = 'en_attente';

    /** Le boîtier ou la DGI a explicitement refusé la pièce. */
    case Refusee = 'refusee';

    /** On ne peut pas trancher : jamais rejouée automatiquement. */
    case AVerifier = 'a_verifier';

    public function libelle(): string
    {
        return match ($this) {
            self::Normalisee => 'Normalisée',
            self::EnAttente => 'En attente de normalisation',
            self::Refusee => 'Refusée',
            self::AVerifier => 'À vérifier',
        };
    }

    /** Une pièce que « Réessayer » ou le job de rejeu peut reprendre. */
    public function rejouable(): bool
    {
        return $this === self::EnAttente || $this === self::Refusee;
    }

    /** @return list<string> */
    public static function valeurs(): array
    {
        return array_map(static fn (self $s): string => $s->value, self::cases());
    }

    public static function depuis(?string $valeur): ?self
    {
        return self::tryFrom((string) $valeur);
    }
}
