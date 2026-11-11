<?php

declare(strict_types=1);

namespace App\Shared\Mail\Support;

use Symfony\Component\Mailer\Exception\TransportExceptionInterface;
use Throwable;

/**
 * La CAUSE LISIBLE d'un échec d'envoi SMTP — celle que l'écran affiche et que
 * la colonne `derniere_erreur` conserve, jamais une trace de pile.
 *
 * Mêmes phrases que le poste (`TextesEnvoiEditeur`) : un message qui échoue au
 * serveur et un message qui échoue au poste disent la même chose. Le mot de
 * passe SMTP est expurgé de tout texte (`expurger`), quoi que le transport
 * ait répondu.
 */
final class CauseEchecEmail
{
    public const LONGUEUR_MAX = 500;

    public static function depuis(Throwable $erreur, ?string $secret = null): string
    {
        $detail = trim($erreur->getMessage());
        $minuscule = mb_strtolower($detail);

        $phrase = match (true) {
            str_contains($minuscule, 'authenticat')
                || str_contains($minuscule, 'username and password not accepted')
                || str_contains($minuscule, ' 535')
                || str_contains($minuscule, ' 534') => 'Le serveur SMTP a refusé les identifiants (utilisateur ou mot de passe SMTP).',
            str_contains($minuscule, 'timed out')
                || str_contains($minuscule, 'timeout') => 'Le serveur SMTP n’a pas répondu à temps (connexion absente ?).',
            str_contains($minuscule, 'connection could not be established')
                || str_contains($minuscule, 'connection refused')
                || str_contains($minuscule, 'getaddrinfo')
                || str_contains($minuscule, 'name or service not known')
                || str_contains($minuscule, 'network is unreachable') => 'Serveur SMTP injoignable (connexion absente ?) : '.$detail,
            default => 'Envoi refusé par le serveur SMTP : '.($detail === '' ? $erreur::class : $detail),
        };

        return self::borner(self::expurger($phrase, $secret));
    }

    /**
     * Une erreur de CONNEXION ou de délai se retente ; un refus d'identifiants
     * ou une adresse refusée n'ira pas mieux à la seconde tentative immédiate
     * (le job ne s'obstine pas, la relance horaire reprendra).
     */
    public static function estTransitoire(Throwable $erreur): bool
    {
        $minuscule = mb_strtolower($erreur->getMessage());

        return $erreur instanceof TransportExceptionInterface
            && (str_contains($minuscule, 'timed out')
                || str_contains($minuscule, 'timeout')
                || str_contains($minuscule, 'connection'));
    }

    public static function expurger(string $texte, ?string $secret): string
    {
        $secret = (string) $secret;

        foreach ([$secret, config('mail.mailers.smtp.password')] as $motif) {
            if (is_string($motif) && $motif !== '') {
                $texte = str_replace($motif, '***', $texte);
            }
        }

        return $texte;
    }

    private static function borner(string $texte): string
    {
        return mb_strlen($texte) > self::LONGUEUR_MAX ? mb_substr($texte, 0, self::LONGUEUR_MAX - 1).'…' : $texte;
    }
}
