<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Les champs de « Mon profil » que leur titulaire peut modifier SOUS DROIT
 * (décision du PO du 03/11/2026) : leur droit RBAC, leurs bornes et leur
 * normalisation — une seule source pour l'écran, le serveur et le poste (qui
 * recopie ces règles dans `champs_profil.dart`).
 *
 * La FONCTION n'est pas ici : c'est le rôle RBAC (ou la fiche RH), gérée par
 * l'administrateur. L'« intitulé de poste » est un texte libre, informatif,
 * sans effet sur les droits.
 */
final class ChampsProfil
{
    public const NOM = 'nom_complet';

    public const TELEPHONE = 'telephone';

    public const INTITULE = 'intitule_poste';

    /** Le droit RBAC (module transverse, `C` = autorisé) de chaque champ. */
    public const DROITS = [
        self::NOM => 'PROFIL_NOM',
        self::TELEPHONE => 'PROFIL_TELEPHONE',
        self::INTITULE => 'PROFIL_INTITULE',
    ];

    public const NOM_MAX = 120;

    public const TELEPHONE_MAX = 30;

    public const INTITULE_MAX = 120;

    /** Chiffres, plus, espaces, tirets — rien d'autre. */
    public const MOTIF_TELEPHONE = '/^[0-9+\s-]+$/';

    /** Un texte libre ne porte aucun caractère de contrôle. */
    public const MOTIF_CONTROLE = '/[\p{Cc}]/u';

    /**
     * Trim, espaces internes réduits à un seul ; vide → null.
     */
    public static function normaliser(?string $valeur): ?string
    {
        $propre = trim((string) preg_replace('/\s+/u', ' ', (string) $valeur));

        return $propre === '' ? null : $propre;
    }
}
