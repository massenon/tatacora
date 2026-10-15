<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

/**
 * Ce qu'un gestionnaire rend après une écriture ACCEPTÉE.
 *
 * `entiteId` est l'identifiant SERVEUR de l'élément écrit — celui du poste
 * dans le cas nominal, celui de l'élément existant en cas de fusion. Le
 * client remappe sur `fusionneAvec` (décision PO du 15/10/2026) : sans ce
 * champ, il ne pourrait pas distinguer « accepté sous mon UUID » de « fondu
 * dans un élément que je ne connais pas encore ».
 *
 * `complements` porte les informations métier destinées à l'écran du poste
 * (l'avertissement de doublon RG-18 d'un client, la cible archivée d'une
 * fusion) : elles accompagnent une écriture réussie, elles ne la refusent pas.
 *
 * `statut` est le statut rendu au poste — `synchronise` sauf exception
 * DÉCLARÉE : une clôture de caisse d'une session que le serveur ne connaît
 * pas rend `cloture_sans_session_serveur` (décision PO du 15/10/2026). Ce
 * n'est pas une erreur : le poste retire l'opération de sa file comme une
 * réussite, et le serveur a signalé l'anomalie.
 */
final readonly class EcritureSynchronisee
{
    public const SYNCHRONISE = 'synchronise';

    /** Clôture acceptée d'une session inconnue du serveur (décision PO du 15/10/2026). */
    public const CLOTURE_SANS_SESSION_SERVEUR = 'cloture_sans_session_serveur';

    /**
     * @param  array<string, mixed>  $complements
     */
    public function __construct(
        public string $entiteId,
        public ?string $fusionneAvec = null,
        public array $complements = [],
        public string $statut = self::SYNCHRONISE,
    ) {
    }
}
