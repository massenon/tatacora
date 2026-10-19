<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

use App\Models\User;
use Illuminate\Support\Carbon;

/**
 * Ce qu'un gestionnaire sait de l'opération qu'il applique, en dehors du
 * document lui-même.
 *
 * ## La date MÉTIER n'est pas la date de réception
 *
 * Un poste hors connexion pendant trois jours synchronise le jeudi une
 * réservation prise le lundi, acompte encaissé. Si le service qui produit
 * l'écriture d'acompte lisait `now()`, la pièce serait datée du jeudi : le
 * tiroir du lundi paraîtrait court, celui du jeudi trop plein, et une clôture
 * de période passée entre-temps recevrait une pièce qui ne lui appartient pas.
 * Le serveur étant le seul maître comptable (D246, décision PO du
 * 15/10/2026), c'est LUI qui produit les écritures depuis les documents
 * sources — il doit donc les dater de la date du DOCUMENT.
 *
 * Ordre de priorité, figé par `SynchronisationService::contexte()` :
 * `payload.date_metier` explicite → champ date du document déclaré par le
 * gestionnaire → date de SAISIE sur le poste (`horodatage_client`). Jamais
 * `now()` : à défaut de mieux, le moment de la saisie est toujours plus juste
 * que celui de la réception.
 */
final readonly class ContexteSynchronisation
{
    public function __construct(
        public string $posteId,
        public User $utilisateur,
        public Carbon $horodatageClient,
        public Carbon $dateMetier,
    ) {
    }

    /** La date métier au format des colonnes `date` (`Y-m-d`). */
    public function dateMetierJour(): string
    {
        return $this->dateMetier->toDateString();
    }
}
