<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Contracts;

use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * Contrat que respecte tout état du système — Hub M14 ou export ponctuel d'un
 * autre module.
 *
 * `09_CLAUDE_CODE_SKILLS_LIBRARY.md` §2.4 : « une fonction `calculer(filtres)`
 * retournant une structure générique `{ kpis, entetes, lignes }` ».
 *
 * Un état implémente **uniquement** son calcul. Il ne connaît ni l'en-tête
 * (RG-19), ni le format de sortie, ni l'archivage : ces trois responsabilités
 * appartiennent à `GenerateurEtatService`. C'est ce qui rend structurellement
 * impossible la non-conformité n°1 de `RESPECT_TABLEAU_RAPPORT.md` §4 —
 * un état ne *peut pas* régénérer son en-tête, il n'y a pas accès.
 */
interface EtatInterface
{
    /**
     * Module d'origine (`M1` … `M14`) — sert au filtrage RBAC et à l'archivage.
     */
    public function module(): string;

    /**
     * Libellé exact imprimé en tête du document.
     *
     * `DIRECTIVE_EXPORT_PDF.md` §2 : « libellé exact de l'état généré
     * (ex. "Grand Livre — Exercice 2026"), jamais un intitulé technique de
     * route/contrôleur ».
     *
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string;

    /**
     * Période réellement filtrée, telle qu'elle sera imprimée.
     *
     * `RESPECT_TABLEAU_RAPPORT.md` grille point 3 : la période de filtrage
     * réellement appliquée, jamais une valeur par défaut muette si
     * l'utilisateur a changé le filtre.
     *
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string;

    /**
     * @param  array<string, string>  $filtres
     */
    public function calculer(array $filtres): EtatResultat;
}
