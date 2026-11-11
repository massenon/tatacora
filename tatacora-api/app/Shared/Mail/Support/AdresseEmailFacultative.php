<?php

declare(strict_types=1);

namespace App\Shared\Mail\Support;

/**
 * L'adresse e-mail FACULTATIVE d'un employé ou d'un compte (décision du PO du
 * 28/10/2026) — UNE seule règle, rejouée à l'identique par le poste
 * (`adresse_email_facultative.dart`).
 *
 * Facultative : blanc = « non renseignée » = `null`, jamais une erreur.
 * Normalisée : `trim` puis minuscules (une même boîte ne se saisit pas en deux
 * graphies). Format : `email:filter` — le FILTER_VALIDATE_EMAIL de PHP, choisi
 * parce que le poste peut le rejouer (le RFC complet, lui, accepte des formes qu'un
 * poste hors ligne n'a aucun moyen de relire), sans guillemets ni crochets ; 255 caractères
 * au plus, la largeur de la colonne. Aucune unicité : deux salariés peuvent
 * partager une boîte.
 */
final class AdresseEmailFacultative
{
    public const LONGUEUR_MAX = 255;

    /**
     * `not_regex` écarte les deux formes rares que `FILTER_VALIDATE_EMAIL` accepte
     * (partie locale entre guillemets, domaine en adresse IP entre crochets) : aucun
     * salarié du Gîte n'en a, et le poste n'a aucune raison de les rejouer.
     *
     * @var list<string>
     */
    public const REGLES = ['nullable', 'email:filter', 'max:255', 'not_regex:/["\[\]]/'];

    /** `trim` + minuscules ; `null` quand il ne reste rien. */
    public static function normaliser(?string $valeur): ?string
    {
        $propre = mb_strtolower(trim((string) $valeur));

        return $propre === '' ? null : $propre;
    }
}
