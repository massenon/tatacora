<?php

declare(strict_types=1);

namespace App\Shared\Sync\Exceptions;

use RuntimeException;

/**
 * L'opération cite un élément que le serveur ne connaît PAS ENCORE (réservation,
 * table, client, commande, véhicule… « pas encore reçue, ou refusée »).
 *
 * Ce n'est pas un refus définitif : l'élément cité peut arriver dans un lot
 * suivant (ordre d'envoi, réseau coupé entre deux lots, création renvoyée depuis
 * « À traiter »). Le moteur le rend sous le code `dependance_manquante`, SANS le
 * mémoriser (la même opération rejugée plus tard, sous le même identifiant, est
 * rejouée pour de bon), et le poste la remet en file avec un repli au lieu de la
 * rejeter — décision du PO du 09/11/2026, « aucune opération ne doit bloquer la
 * synchronisation ». La phrase du serveur reste celle d'un refus lisible : si
 * l'élément n'arrive jamais, le poste finit par la montrer dans « À traiter ».
 */
class DependanceManquanteException extends RuntimeException
{
}
