<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

/**
 * L'AIDE lisible sous l'échec de « Envoyer un email de test » (09/11/2026).
 *
 * Le message du transport reste affiché TEL QUEL (il est fidèle : « Failed host
 * lookup: 'mail.exemple.com' ») ; ce service y ajoute, dessous, une phrase
 * française qui dit quoi vérifier. Trois cas, reconnus à des fragments du message du
 * transport — celui du serveur (Symfony Mailer) comme celui du poste (le client SMTP
 * de Dart) —, dans cet ordre : nom du serveur introuvable, identifiants refusés,
 * connexion refusée ou expirée. Un message inconnu n'a pas d'aide : on ne devine pas.
 *
 * L'aide est une PHRASE FIXE, de `lang/fr/pwa.php` : elle ne reprend jamais le
 * message du transport, donc ni nom de compte ni mot de passe. Le poste en porte la
 * copie exacte (`aide_echec_email.dart`), confrontée à ce service par
 * `aide_email_contre_serveur_test`.
 */
final class AideEchecEmail
{
    public const HOTE = 'hote';

    public const AUTHENTIFICATION = 'authentification';

    public const CONNEXION = 'connexion';

    /**
     * Les fragments (en minuscules) de chaque cas, dans l'ordre d'examen : un nom
     * introuvable est AUSSI « une connexion impossible » pour Symfony, il doit donc passer
     * avant elle.
     *
     * @var array<string, list<string>>
     */
    public const FRAGMENTS = [
        self::HOTE => [
            'failed host lookup', 'getaddrinfo', 'php_network_getaddresses', 'name or service not known',
            'nodename nor servname', 'no address associated with hostname', 'temporary failure in name resolution',
            'could not resolve host', 'nom d’hôte introuvable',
        ],
        self::AUTHENTIFICATION => [
            'authenticat', 'username and password not accepted', 'invalid credentials', 'bad credentials',
            'a refusé les identifiants', 'code "535"', ' 535 ',
        ],
        self::CONNEXION => [
            'connection refused', 'connection timed out', 'timed out', 'timeout', 'connection could not be established',
            'connection reset', 'connection closed', 'network is unreachable', 'no route to host', 'handshake',
            'wrong version number', 'n’a pas répondu à temps',
        ],
    ];

    /** Le cas reconnu dans [$erreur] (`hote`, `authentification`, `connexion`), ou `null`. */
    public static function cas(string $erreur): ?string
    {
        $texte = mb_strtolower($erreur);

        foreach (self::FRAGMENTS as $cas => $fragments) {
            foreach ($fragments as $fragment) {
                if (str_contains($texte, $fragment)) {
                    return $cas;
                }
            }
        }

        return null;
    }

    /** La phrase d'aide à poser sous l'échec, ou `null` quand le message n'est pas reconnu. */
    public static function pour(string $erreur): ?string
    {
        $cas = self::cas($erreur);

        return $cas === null ? null : __('pwa.parametres.email_test_aide_' . $cas);
    }
}
