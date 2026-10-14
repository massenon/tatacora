<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

/**
 * Les canaux de diffusion — registre FERME, et aucun n'est branche.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html`, onglet Canaux, et
 * `prototype_v2/assets/js/notifications-engine.js` l.52-61.
 *
 * ## Pourquoi un registre plutot qu'une table
 *
 * Un canal n'est pas une donnee de gestion : c'est une capacite technique du
 * produit. Une table le rendrait creable depuis l'ecran, et un utilisateur
 * pourrait poser « Fax » sans que rien ne sache l'emprunter. Meme raisonnement
 * que `RegistreParametres` (PA-124) : le jeu est ferme cote serveur, et une
 * valeur inconnue est refusee, jamais creee.
 *
 * ## `branche` — TROIS restent figes a `false`, le QUATRIEME se DERIVE (01/09/2026)
 *
 * - WhatsApp : l'API WhatsApp Business n'est pas contractee. C'est un contrat
 *   commercial et un numero verifie, pas un developpement.
 * - E-mail : DERIVE de `ConfigurationMailService::estReelle()` — exactement
 *   la garde anticipee ci-dessous avant le 01/09/2026 : « branche devra se
 *   DERIVER de l'existence reelle du client qui porte le canal, jamais d'une
 *   constante ». Un mot de passe SMTP n'entre pas pour autant dans
 *   `parametres_systeme`, lisible par tout profil ayant acces a l'ecran
 *   (PA-125) — il reste en `.env`.
 * - Android : l'application Flutter n'expose aucun appareil enregistre.
 * - SMS : aucun agregateur n'est retenu.
 *
 * Le jour ou WhatsApp, Android ou SMS sera brancher a son tour, meme regle :
 * DERIVER de l'existence reelle du client qui porte le canal, jamais poser un
 * drapeau a la main — l'erreur exacte que le badge MECeF a corrigee (PA-61),
 * et que l'e-mail vient d'eviter des sa premiere mise en service.
 *
 * @see RG-20 Diffusion automatique — les trois canaux restants
 */
final class RegistreCanaux
{
    public const WHATSAPP = 'whatsapp';

    public const EMAIL = 'email';

    public const ANDROID = 'android';

    public const SMS = 'sms';

    /**
     * Les codes, dans l'ordre du maitre.
     *
     * @return list<string>
     */
    public static function codes(): array
    {
        return [self::WHATSAPP, self::EMAIL, self::ANDROID, self::SMS];
    }

    public static function existe(string $code): bool
    {
        return in_array($code, self::codes(), true);
    }

    /**
     * Un canal, libelles resolus.
     *
     * `limite` est le nombre de caracteres au-dela duquel le canal decoupe ou
     * refuse le message. `null` pour l'e-mail : il n'en impose aucune.
     *
     * `branche` est MESURE pour l'e-mail (`ConfigurationMailService`), pose a
     * `false` pour les trois autres — voir l'en-tete de la classe.
     *
     * @return array{code: string, libelle: string, branche: bool, blocage: string, limite: int|null, cible: string}
     */
    public static function canal(string $code): array
    {
        $limites = [
            self::WHATSAPP => 4096,
            self::EMAIL => null,
            self::ANDROID => 240,
            self::SMS => 160,
        ];

        $branche = $code === self::EMAIL
            && app(\App\Shared\Mail\Services\ConfigurationMailService::class)->estReelle();

        return [
            'code' => $code,
            'libelle' => __('notifications_pwa.canal.'.$code.'.libelle'),
            'branche' => $branche,
            'blocage' => $branche
                ? __('notifications_pwa.canal.email.blocage_leve')
                : __('notifications_pwa.canal.'.$code.'.blocage'),
            'limite' => $limites[$code] ?? null,
            'cible' => __('notifications_pwa.canal.'.$code.'.cible'),
        ];
    }

    /**
     * @return list<array{code: string, libelle: string, branche: bool, blocage: string, limite: int|null, cible: string}>
     */
    public static function tous(): array
    {
        return array_map(static fn (string $code): array => self::canal($code), self::codes());
    }

    /**
     * Le nombre de canaux effectivement branches — zero, et il se COMPTE.
     *
     * Ecrire `0` a l'ecran serait juste aujourd'hui et faux le jour du premier
     * branchement, sans que personne ne rouvre la question.
     */
    public static function nombreBranches(): int
    {
        return count(array_filter(self::tous(), static fn (array $c): bool => $c['branche']));
    }
}
