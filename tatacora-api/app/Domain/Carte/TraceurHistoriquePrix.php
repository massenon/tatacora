<?php

declare(strict_types=1);

namespace App\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Restaurant\Models\Plat;

/**
 * Trace un changement de prix — appelé par `CarteBoissonObserver` et
 * `PlatObserver`, jamais depuis un composant Livewire.
 *
 * ## Un seul endroit pour les deux rayons
 *
 * Même raisonnement que `MarquesDePrix`, dans ce même domaine : le bar et le
 * restaurant partagent l'écran de carte (`carte-module.js`), et dupliquer
 * cette logique dans `App\Domain\Bar\Observers` ET `App\Domain\Restaurant\
 * Observers` l'aurait fait diverger au premier ajustement.
 *
 * ## `bccomp`, jamais `!=` — y compris sur `prix_corrige_main`
 *
 * `prix_vente` est un `DECIMAL(15,2)` : « 1500 » et « 1500.00 » sont le même
 * montant et deux chaînes différentes (`MarquesDePrix` l.44-46). La bascule
 * booléenne de `prix_corrige_main` est convertie en `'1.00'`/`'0.00'` pour
 * être comparée par la MÊME règle — un registre uniforme plutôt qu'une
 * exception pour le seul champ non monétaire.
 *
 * ## LA comparaison qui empêche la double trace
 *
 * `estIdentique()` est le SEUL gate de cette classe : elle est appelée pour
 * les DEUX champs à chaque sauvegarde, changés ou non, et c'est délibéré —
 * une trace n'existe QUE parce que la comparaison a dit « différent »,
 * jamais parce qu'une sauvegarde a eu lieu. Retirer cet appel (ou le
 * remplacer par une égalité qui accepterait tout) fait tracer les DEUX
 * champs à CHAQUE sauvegarde : modifier uniquement `prix_vente` tracerait
 * aussi `prix_corrige_main`, alors qu'il n'a pas bougé — une ligne qui
 * affirme un changement qui n'a pas eu lieu, exactement le défaut que
 * PA-59/60/61 nomme. `HistoriquePrixCarteTest` le prouve par mutation.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 */
final class TraceurHistoriquePrix
{
    private const PRECISION = 2;

    /**
     * Les champs retracés, dans l'ordre où ils apparaissent à l'écran.
     *
     * @var list<string>
     */
    private const CHAMPS = [
        HistoriquePrixCarte::CHAMP_PRIX_VENTE,
        HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN,
    ];

    public static function tracer(string $source, CarteBoisson|Plat $article): void
    {
        foreach (self::CHAMPS as $champ) {
            $avant = self::versDecimal($champ, $article->getOriginal($champ));
            $apres = self::versDecimal($champ, $article->getAttribute($champ));

            if (self::estIdentique($avant, $apres)) {
                continue;
            }

            HistoriquePrixCarte::create([
                'source' => $source,
                'source_id' => $article->getKey(),
                'champ' => $champ,
                'ancien_prix' => $avant,
                'nouveau_prix' => $apres,
            ]);
        }
    }

    /**
     * `bccomp`, jamais `==` ou `===` sur les deux chaînes : c'est la règle du
     * dépôt pour tout montant (`CLAUDE.md`, « Comparaison de montants »), et
     * elle est appliquée ici même pour `prix_corrige_main` — voir l'entête.
     * `null` ne se compare qu'à `null` : un passage de/vers `null` EST un
     * changement, jamais une égalité par défaut.
     */
    private static function estIdentique(?string $avant, ?string $apres): bool
    {
        if ($avant === null || $apres === null) {
            return $avant === $apres;
        }

        return bccomp($avant, $apres, self::PRECISION) === 0;
    }

    /**
     * Ramène la valeur du champ à une chaîne décimale comparable par
     * `bccomp`, ou `null` — jamais un flottant.
     */
    private static function versDecimal(string $champ, mixed $valeur): ?string
    {
        if ($valeur === null) {
            return null;
        }

        if ($champ === HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN) {
            return ((bool) $valeur) ? '1.00' : '0.00';
        }

        return (string) $valeur;
    }
}
