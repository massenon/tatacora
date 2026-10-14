<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Exceptions;

use RuntimeException;

/**
 * Un etat de M10 depasse le nombre de lignes qu'il peut rendre d'un bloc.
 *
 * ## Pourquoi REFUSER plutot que tronquer ou paginer
 *
 * Le Journal General et le Grand Livre portent un TOTAL et un bandeau
 * d'equilibre calcules sur l'ensemble affiche (`m10-journal.html` l.41-47 et
 * l.100-104). C'est la raison pour laquelle ils ne sont pas pagines : « un
 * total pose au-dessus d'une seule page se lirait comme le total de ce qu'on
 * voit » — le meme raisonnement que `GET /stocks/etat` et `GET
 * /restaurant/carte`.
 *
 * Deux mauvaises sorties, donc, et une bonne :
 *
 * - **Tronquer** rendrait des totaux faux sous un bandeau qui annoncerait
 *   « Journal desequilibre — anomalie a investiguer avant cloture ». On
 *   enverrait un comptable chercher une anomalie technique grave qui n'existe
 *   pas.
 * - **Paginer** rendrait des totaux justes au-dessus de lignes qui ne les font
 *   pas — PA-121.
 * - **Refuser en le disant** laisse l'ecran intact et nomme le geste qui
 *   debloque : filtrer par journal, controle que le maitre presente deja
 *   (l.32, l.76-79).
 *
 * L'exception porte le decompte reel : un refus qui ne dit pas de combien on
 * depasse ne permet pas de decider quoi filtrer.
 */
class EtatTropVolumineuxException extends RuntimeException
{
    public function __construct(
        public readonly int $lignes,
        public readonly int $maximum,
        ?string $message = null,
    ) {
        parent::__construct($message ?? __('comptabilite.etat_trop_volumineux', [
            'lignes' => $lignes,
            'maximum' => $maximum,
        ]));
    }
}
