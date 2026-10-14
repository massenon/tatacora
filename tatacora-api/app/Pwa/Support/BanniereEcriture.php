<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;

/**
 * Calcul dynamique de l'état du bandeau de la coquille d'en-tête selon les droits RBAC de l'utilisateur.
 */
final class BanniereEcriture
{
    public const AUCUNE = 'aucune';

    public const LECTURE_SEULE = 'lecture_seule';

    /**
     * Détermine l'état du bandeau d'écriture pour un composant donné.
     *
     * @param class-string $composant
     * @return array{etat: string, module: string|null}
     */
    public static function pour(?User $utilisateur, string $composant): array
    {
        $module = defined($composant.'::MODULE') ? constant($composant.'::MODULE') : null;
        $module = is_string($module) && $module !== '' ? $module : null;

        $offreEcriture = $module !== null && in_array(
            AutoriseEcriture::class,
            class_uses_recursive($composant),
            true,
        );

        // Un ecran sans ecriture n'affiche AUCUN bandeau — retire le
        // 31/08/2026 sur relevee du Product Owner, et le maitre le confirme :
        // `shell.js` n'affiche la banniere QUE si `TATACORA_LECTURE_SEULE`
        // est pose (l.269), jamais pour un ecran de consultation. L'etat
        // MODULE_NON_OUVERT et son texte « Les saisies... arrivent vague par
        // vague » etaient un RECIT DE FEUILLE DE ROUTE de l'ere lecture
        // seule, servi comme un etat — un gerant plein droit lisait
        // « Consultation pour l'instant » sur des ecrans de consultation PAR
        // NATURE (etats M10, clients M3), comme si une livraison manquait.
        // La garde `BannierePwaTest` portait elle-meme le contrat de sortie :
        // « ce cas n'a plus de sujet, et la branche est a retirer ».
        if (! $offreEcriture) {
            return ['etat' => self::AUCUNE, 'module' => $module];
        }

        if ($utilisateur !== null && $utilisateur->niveauSurModule($module) === 'C') {
            return ['etat' => self::AUCUNE, 'module' => $module];
        }

        return ['etat' => self::LECTURE_SEULE, 'module' => $module];
    }
}
