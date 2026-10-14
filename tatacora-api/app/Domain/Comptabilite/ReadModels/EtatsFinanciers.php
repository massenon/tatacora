<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Les quatre etats financiers d'un exercice, en une seule lecture —
 * `m10-etats-financiers.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Pourquoi une route de plus, et non quatre appels du client
 *
 * Le maitre le pose lui-meme sous son bouton d'export (l.42) : « L'export
 * appelle les MEMES services que chaque ecran individuel — aucun recalcul
 * independant ». Cette classe ne recalcule rien : elle porte les quatre read
 * models produits par les quatre services.
 *
 * Ce qu'elle apporte, et qu'aucun enchainement de quatre appels ne peut donner :
 * les quatre documents proviennent de la MEME lecture. Quatre requetes
 * successives peuvent encadrer une ecriture — un bilan d'avant et un compte de
 * resultat d'apres, remis ensemble au comptable comme un jeu coherent. Sur des
 * etats financiers destines a etre signes, c'est exactement l'erreur qu'on ne
 * peut pas rattraper apres coup.
 */
final readonly class EtatsFinanciers
{
    public function __construct(
        public string $exerciceId,
        public Bilan $bilan,
        public CompteResultat $compteResultat,
        public Tafire $tafire,
        public NotesAnnexes $notesAnnexes,
    ) {
    }
}
