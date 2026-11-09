<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use App\Shared\Parametres\Data\DefinitionParametre;

/**
 * Le CONTRÔLE de forme d'une valeur de paramètre arrivée d'un POSTE par la
 * synchronisation (09/11/2026) : le registre déclare les règles, l'écran web les
 * applique par `validerEcriture` ; un poste, lui, n'a pas d'écran ici — sans ce
 * contrôle, une adresse « http:// » ou un nom d'opérateur de 80 caractères y
 * serait rangé tel quel. Mêmes règles, mêmes PHRASES (`parametres.valeur_*`) que le
 * poste, qui les rejoue avant d'écrire (`normaliser` de `regles_parametres.dart`) ;
 * la parité est éprouvée par `reglages_facturation_contre_serveur_test`.
 *
 * Une valeur vide n'est pas jugée ici (« vider » est permis ; le service décide de
 * ce que vide veut dire pour la clé), sauf un interrupteur, qui ne se vide pas.
 */
final class ControleValeurParametre
{
    /** La phrase du refus, ou `null` quand la valeur a la forme de son type. */
    public static function refus(DefinitionParametre $definition, mixed $valeur): ?string
    {
        $libelle = $definition->libelle;
        $texte = $valeur === null ? '' : trim((string) $valeur);

        if ($definition->type === 'booleen') {
            return in_array($texte, ['true', 'false', '1', '0'], true) || is_bool($valeur)
                ? null
                : __('parametres.valeur_booleen', ['libelle' => $libelle]);
        }

        if ($texte === '') {
            return null;
        }

        $max = self::regle($definition, 'max:');
        $min = self::regle($definition, 'min:');

        if ($definition->type === 'choix') {
            return in_array(strtolower($texte), $definition->choix, true)
                ? null
                : __('parametres.valeur_choix_inconnu', ['libelle' => $libelle, 'valeur' => $texte]);
        }

        if ($definition->type === 'entier') {
            if (preg_match('/^\d+$/', $texte) !== 1) {
                return __('parametres.valeur_entier', ['libelle' => $libelle]);
            }

            return self::bornes($libelle, (int) $texte, $min, $max);
        }

        if ($definition->type !== 'texte') {
            return null;
        }

        if ($max !== null && mb_strlen($texte) > (int) $max) {
            return __('parametres.valeur_trop_longue', ['libelle' => $libelle, 'max' => $max]);
        }

        foreach ($definition->regles as $regle) {
            if (str_starts_with($regle, 'regex:/^https:')
                && preg_match('/^https:\/\/[^\s]+$/i', $texte) !== 1) {
                return __('parametres.valeur_https', ['libelle' => $libelle]);
            }

            if ($regle === 'regex:/^[A-Za-z0-9]+$/' && preg_match('/^[A-Za-z0-9]+$/', $texte) !== 1) {
                return __('parametres.valeur_alphanumerique', ['libelle' => $libelle]);
            }
        }

        return null;
    }

    private static function bornes(string $libelle, int $valeur, ?string $min, ?string $max): ?string
    {
        if (($min !== null && $valeur < (int) $min) || ($max !== null && $valeur > (int) $max)) {
            return match (true) {
                $min !== null && $max !== null => __('parametres.valeur_entre', ['libelle' => $libelle, 'min' => $min, 'max' => $max]),
                $min !== null => __('parametres.valeur_au_moins', ['libelle' => $libelle, 'min' => $min]),
                default => __('parametres.valeur_au_plus', ['libelle' => $libelle, 'max' => $max]),
            };
        }

        return null;
    }

    private static function regle(DefinitionParametre $definition, string $prefixe): ?string
    {
        foreach ($definition->regles as $regle) {
            if (str_starts_with($regle, $prefixe)) {
                return substr($regle, strlen($prefixe));
            }
        }

        return null;
    }
}
