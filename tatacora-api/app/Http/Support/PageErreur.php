<?php

declare(strict_types=1);

namespace App\Http\Support;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Throwable;

/**
 * Ce que les pages d'erreur (`resources/views/errors/`) ont le droit de savoir.
 *
 * Une page d'erreur est servie dans le pire moment : base indisponible,
 * session absente, requête hors de toute route. Chaque méthode est donc
 * défensive (jamais d'exception à son tour) et ne renvoie QUE des valeurs
 * sûres à afficher — jamais un message d'exception, un chemin ou une requête.
 */
final class PageErreur
{
    /**
     * Identifiant d'incident COURT et NON SENSIBLE, à communiquer au support.
     *
     * Empreinte à sens unique de la classe, du fichier et de la ligne de
     * l'exception d'origine, du jour : rien ne s'en déduit, mais le même
     * identifiant est versé au contexte du journal (`bootstrap/app.php`), ce
     * qui permet de retrouver l'entrée sans rien exposer à l'écran.
     */
    public static function incident(Throwable $e): string
    {
        $origine = $e instanceof HttpExceptionInterface && $e->getPrevious() instanceof Throwable
            ? $e->getPrevious()
            : $e;

        $empreinte = hash('sha256', implode('|', [
            $origine::class,
            $origine->getFile(),
            $origine->getLine(),
            date('Y-m-d'),
        ]));

        return 'INC-' . strtoupper(substr($empreinte, 0, 8));
    }

    /** Délai (secondes, entier positif) annoncé par l'en-tête `Retry-After`, sinon null. */
    public static function delaiAvantNouvelEssai(?Throwable $e): ?int
    {
        if (! $e instanceof HttpExceptionInterface) {
            return null;
        }

        $valeur = $e->getHeaders()['Retry-After'] ?? null;

        return is_numeric($valeur) && (int) $valeur > 0 ? (int) $valeur : null;
    }

    /** Vrai si un utilisateur est connecté ; faux pour un invité ou si la session est indisponible. */
    public static function estConnecte(): bool
    {
        try {
            return Auth::check();
        } catch (Throwable) {
            return false;
        }
    }

    /**
     * Vrai si la requête fautive vient de l'écran de connexion (adresse
     * demandée ou page d'origine, du même site). Sert à mettre « Retour à la
     * connexion » en bouton principal de la page 419.
     */
    public static function venaitDeLaConnexion(Request $request): bool
    {
        try {
            $connexion = parse_url(route('pwa.connexion'), PHP_URL_PATH);
            $origine = (string) $request->headers->get('referer', '');
            $memeSite = $origine !== '' && str_starts_with($origine, url('/'));

            return $request->path() === ltrim((string) $connexion, '/')
                || ($memeSite && parse_url($origine, PHP_URL_PATH) === $connexion);
        } catch (Throwable) {
            return false;
        }
    }
}
