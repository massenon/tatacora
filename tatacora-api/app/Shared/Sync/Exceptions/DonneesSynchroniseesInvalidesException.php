<?php

declare(strict_types=1);

namespace App\Shared\Sync\Exceptions;

use Illuminate\Validation\ValidationException;
use RuntimeException;

/**
 * Un document synchronisé refusé par les MÊMES règles que la route d'API
 * équivalente.
 *
 * `RuntimeException` et non `ValidationException` : le moteur ne transforme en
 * rejet définitif que les refus métier (`RuntimeException`) et laisse remonter
 * tout le reste en 500 pour rejeu — voir `SynchronisationService`. Une donnée
 * invalide est un refus DÉFINITIF : la rejouer ne la rendra pas valide.
 *
 * Le motif est la première phrase du serveur ; `erreurs` les porte toutes,
 * par champ, pour que le poste puisse les afficher à côté de la saisie.
 */
final class DonneesSynchroniseesInvalidesException extends RuntimeException
{
    /**
     * @param  array<string, list<string>>  $erreurs
     */
    public function __construct(string $message, public readonly array $erreurs)
    {
        parent::__construct($message);
    }

    public static function depuis(ValidationException $e): self
    {
        /** @var array<string, list<string>> $erreurs */
        $erreurs = $e->errors();

        return new self($e->validator->errors()->first(), $erreurs);
    }
}
