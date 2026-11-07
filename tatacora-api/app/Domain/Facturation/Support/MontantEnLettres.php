<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

use InvalidArgumentException;

/**
 * Montant en lettres, en FRANÇAIS, pour « Arrêté la présente facture à la somme de » (PO, 07/11/2026).
 *
 * Fonction de domaine UNIQUE côté serveur ; le poste a la sienne (`montant_en_lettres.dart`), confrontée
 * à celle-ci sur la même table de cas (`tool/proforma/cas_montant_en_lettres.json`, rejouée par
 * `rejouer_proforma.php`).
 *
 * Règles (orthographe traditionnelle, le modèle papier : « QUATRE CENT MILLE FRANCS CFA ») :
 *  - « vingt » et « cent » prennent un s quand ils sont multipliés ET terminent le nombre ou précèdent
 *    « million(s) / milliard(s) » : « quatre-vingts », « deux cents », « deux cents millions » ;
 *    jamais devant « mille » (invariable) ni suivis d'un autre nombre : « quatre-vingt mille »,
 *    « deux cent un », « quatre-vingt-un » ;
 *  - « et » seulement pour 21, 31, 41, 51, 61 et 71 (« vingt et un », « soixante et onze »), jamais pour 81 et 91 ;
 *  - trait d'union entre dizaines et unités ; « mille » vaut 1000 (jamais « un mille ») ;
 *  - « un million », « deux millions », « un milliard » ; un multiple exact du million prend « de » :
 *    « un million de francs CFA » ;
 *  - FRANC au singulier pour 0 et 1, sinon FRANCS ; tout en MAJUSCULES.
 * Entiers de 0 à 999 999 999 999 ; un FCFA n'a pas de virgule.
 */
final class MontantEnLettres
{
    private const UNITES = [
        'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix',
        'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize',
    ];

    private const DIZAINES = [2 => 'vingt', 3 => 'trente', 4 => 'quarante', 5 => 'cinquante', 6 => 'soixante'];

    public const MAXIMUM = 999_999_999_999;

    public static function francsCfa(int $montant): string
    {
        $lettres = self::nombre($montant);
        $de = $montant >= 1_000_000 && $montant % 1_000_000 === 0 ? ' de' : '';
        $unite = $montant === 0 || $montant === 1 ? 'franc' : 'francs';

        return mb_strtoupper($lettres.$de.' '.$unite.' CFA');
    }

    /** Le nombre en lettres minuscules. */
    public static function nombre(int $n): string
    {
        if ($n < 0 || $n > self::MAXIMUM) {
            throw new InvalidArgumentException('Montant hors limites : '.$n);
        }

        if ($n === 0) {
            return 'zéro';
        }

        $milliards = intdiv($n, 1_000_000_000);
        $millions = intdiv($n % 1_000_000_000, 1_000_000);
        $milliers = intdiv($n % 1_000_000, 1_000);
        $reste = $n % 1_000;
        $parties = [];

        if ($milliards > 0) {
            $parties[] = self::groupe($milliards, true).' milliard'.($milliards > 1 ? 's' : '');
        }
        if ($millions > 0) {
            $parties[] = self::groupe($millions, true).' million'.($millions > 1 ? 's' : '');
        }
        if ($milliers > 0) {
            $parties[] = $milliers === 1 ? 'mille' : self::groupe($milliers, false).' mille';
        }
        if ($reste > 0) {
            $parties[] = self::groupe($reste, true);
        }

        return implode(' ', $parties);
    }

    /** Un groupe de 1 à 999 ; `$accorde` : « cent » et « vingt » peuvent prendre leur s. */
    private static function groupe(int $n, bool $accorde): string
    {
        $centaines = intdiv($n, 100);
        $reste = $n % 100;
        $texte = '';

        if ($centaines === 1) {
            $texte = 'cent';
        } elseif ($centaines > 1) {
            $texte = self::UNITES[$centaines].' cent'.($reste === 0 && $accorde ? 's' : '');
        }

        if ($reste > 0) {
            $texte .= ($texte === '' ? '' : ' ').self::dizaines($reste, $accorde);
        }

        return $texte;
    }

    private static function dizaines(int $n, bool $accorde): string
    {
        if ($n <= 16) {
            return self::UNITES[$n];
        }
        if ($n < 20) {
            return 'dix-'.self::UNITES[$n - 10];
        }

        $dizaine = intdiv($n, 10);
        $unite = $n % 10;

        if ($dizaine >= 2 && $dizaine <= 6) {
            return self::DIZAINES[$dizaine].match (true) {
                $unite === 0 => '',
                $unite === 1 => ' et un',
                default => '-'.self::UNITES[$unite],
            };
        }

        if ($dizaine === 7) {
            return $n === 71 ? 'soixante et onze' : 'soixante-'.self::dizaines($n - 60, false);
        }

        // 80 à 99 : « quatre-vingts » seulement s'il termine le nombre.
        return $n === 80
            ? 'quatre-vingt'.($accorde ? 's' : '')
            : 'quatre-vingt-'.self::dizaines($n - 80, false);
    }
}
