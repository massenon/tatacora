<?php

declare(strict_types=1);

namespace App\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Plat;

/**
 * Les deux marques de prix de la carte — PA-161 (b).
 *
 * ## Un seul endroit pour les deux rayons
 *
 * Le bar (M5) et le restaurant (M4) sont le MÊME écran chez le maître
 * (`prototype_v2/pages/carte-module.js`), qui écrit lui-même sa raison l.7 :
 * « Deux écrans jumeaux finiraient par diverger au premier ajustement ». La
 * règle qui pose `prix_corrige_main` vit donc ici, dans le domaine déjà
 * partagé par les deux cartes (celui d'`IndisponibiliteCarte`), et non
 * recopiée dans `CarteBoissonService` puis dans `CartePlatMenuService`.
 *
 * ## Ce que chaque marque veut dire
 *
 * - `prix_provisoire` : le tarif a été POSÉ faute de relevé. Six boissons du
 *   maître sont dans ce cas — l'ardoise du bar ne donnait aucun montant pour
 *   EKU 66 cl, Guinness 66 cl, Vody / Loco, le vin blanc, le vin rouge et le
 *   rhum. C'est une DÉCISION, elle se coche et se décoche.
 * - `prix_corrige_main` : le tarif a été corrigé à la main. C'est un FAIT, et
 *   c'est pour cela qu'il se déduit : quand quelqu'un change au clavier le prix
 *   d'un article qui portait un tarif provisoire, la correction manuelle a bien
 *   eu lieu — la lui faire cocher en plus reviendrait à lui demander de
 *   déclarer ce qu'il vient de faire, et il oublierait.
 *
 * ## Une décision explicite l'emporte toujours sur la déduction
 *
 * Quand l'appelant soumet lui-même `prix_corrige_main`, la déduction ne
 * s'applique pas : sans cela, LEVER la marque serait impossible dès lors qu'on
 * corrige le prix du même geste, et l'écran refuserait en silence une action
 * qu'il vient d'offrir. Même raisonnement que PA-124 : la cohérence
 * s'apprécie sur l'état RÉSULTANT, jamais clé par clé.
 *
 * ## `bccomp`, jamais `!=`
 *
 * `prix_vente` est un `DECIMAL(15,2)` : « 1500 » et « 1500.00 » sont le même
 * montant et deux chaînes différentes. Une comparaison d'égalité poserait la
 * marque sur un enregistrement qui n'a rien changé.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-161 (b) Marques de prix
 */
final class MarquesDePrix
{
    /** Le tarif a été posé faute de relevé — il reste à confronter à la carte. */
    public const PROVISOIRE = 'prix_provisoire';

    /** Le tarif imprimé a été remplacé à la main — la carte est instable. */
    public const CORRIGE_MAIN = 'prix_corrige_main';

    /** Précision de `prix_vente` au schéma. */
    private const PRECISION = 2;

    /**
     * Complète les champs soumis de la marque « corrigé à la main » quand elle
     * est méritée, et les rend inchangés sinon.
     *
     * Quatre conditions, toutes nécessaires : un prix est soumis, l'appelant
     * n'a pas tranché lui-même, l'article portait un tarif provisoire, et le
     * montant change réellement.
     *
     * @param  array<string, mixed>  $donnees  les champs soumis à la modification
     * @return array<string, mixed>
     */
    public static function completer(CarteBoisson|Plat $article, array $donnees): array
    {
        if (! array_key_exists('prix_vente', $donnees)) {
            return $donnees;
        }

        if (array_key_exists(self::CORRIGE_MAIN, $donnees)) {
            return $donnees;
        }

        if ($article->prix_provisoire !== true) {
            return $donnees;
        }

        $soumis = $donnees['prix_vente'];

        if (! is_scalar($soumis) || ! is_numeric((string) $soumis)) {
            // Une valeur non numérique sera refusée par la validation en
            // amont : y déduire une marque poserait un fait à partir d'une
            // saisie qui n'aboutira pas.
            return $donnees;
        }

        if (bccomp((string) $soumis, (string) $article->prix_vente, self::PRECISION) === 0) {
            return $donnees;
        }

        $donnees[self::CORRIGE_MAIN] = true;

        return $donnees;
    }
}
