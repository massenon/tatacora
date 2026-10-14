<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Calculs par service de la fiche de réservation — extraits de la vue
 * (`pwa.hebergement.reservations`) vers des méthodes NOMMÉES.
 *
 * ## Pourquoi ces calculs ne vivent PAS dans un `@php … @endphp` de la vue
 *
 * Constaté sur ce formulaire (02/09/2026) : une variable assignée par un BLOC
 * `@php … @endphp` À L'INTÉRIEUR de `@foreach ($rServices as $service)` se
 * perd avant la ligne suivante — « Undefined variable » — alors que la MÊME
 * donnée, lue depuis un appel de méthode statique répété à chaque usage,
 * survit. La boucle porte plus bas des liaisons `wire:model` sur des index de
 * tableau (`rLignes.INDEX.…`) ; c'est cette combinaison qui déclenche la
 * perte, reproduite sur une variable aussi triviale que `$x = 1;`. Plutôt que
 * de contourner une limite non comprise du compilateur avec des expressions
 * `@php(...)` de plus en plus longues, le calcul est déplacé ici : une
 * méthode statique n'a pas de « scope de vue » à perdre.
 *
 * @see \App\Pwa\Livewire\Hebergement\Reservations::recapFiche() la même
 *      formule ligne par ligne, jamais réécrite en parallèle.
 */
final class FicheReservationServices
{
    /**
     * Nombre de nuits du séjour — MÊME formule que
     * `Reservations::recapFiche()`, jamais réécrite en parallèle. `null` tant
     * que les deux dates ne sont pas saisies : le bandeau du maître s'affiche
     * alors, plutôt qu'un zéro qui ressemblerait à un compte juste.
     *
     * Portée en méthode statique, comme le reste de cette classe : une
     * variable de vue posée par un bloc `@php … @endphp` DANS le corps de la
     * modale (`<x-pwa.modale>`) ne survit pas de façon fiable jusqu'à sa
     * lecture plus bas — constaté sur ce formulaire (02/09/2026) — alors
     * qu'un appel de méthode répété n'a pas de « scope de vue » à perdre.
     */
    public static function nuits(string $dateArrivee, string $dateDepart): ?int
    {
        if ($dateArrivee === '' || $dateDepart === '') {
            return null;
        }

        try {
            $n = (int) \Carbon\CarbonImmutable::parse($dateArrivee)->diffInDays(\Carbon\CarbonImmutable::parse($dateDepart));
        } catch (\Throwable $echec) {
            // Une date mal formée ne doit pas afficher un chiffre plausible :
            // le bandeau du maître dit qu'il manque une date, jamais un
            // nombre de nuits inventé. L'échec est nommé, pas avalé.
            report($echec);

            return null;
        }

        return $n > 0 ? $n : null;
    }

    /**
     * Les index de `$rLignes` qui appartiennent à CE service, dans l'ordre
     * de saisie — remplace un `array_filter` qui vivait dans la vue.
     *
     * @param  list<array{service: string, source_id: string, quantite: string}>  $lignes
     * @return list<int>
     */
    public static function indexParService(array $lignes, string $service): array
    {
        $index = [];

        foreach ($lignes as $i => $ligne) {
            if ($ligne['service'] === $service) {
                $index[] = $i;
            }
        }

        return $index;
    }

    /**
     * Le sous-total d'UN service — même lecture ligne par ligne que
     * `Reservations::recapFiche()`, jamais une formule différente.
     *
     * @param  list<array{service: string, source_id: string, quantite: string}>  $lignes
     * @param  array<string, list<array{id: string, libelle: string, prix: string}>>  $catalogues
     */
    public static function sousTotal(array $lignes, array $catalogues, string $service): string
    {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            if ($ligne['service'] !== $service) {
                continue;
            }

            $prix = self::prixLigne($catalogues, $service, $ligne['source_id']);

            if ($prix === null || ! is_numeric($ligne['quantite'])) {
                continue;
            }

            $total = bcadd($total, bcmul($prix, (string) $ligne['quantite'], 2), 2);
        }

        return $total;
    }

    /**
     * Le prix catalogue d'un élément choisi, ou `null` si la source a disparu.
     *
     * @param  array<string, list<array{id: string, libelle: string, prix: string}>>  $catalogues
     */
    public static function prixLigne(array $catalogues, string $service, string $sourceId): ?string
    {
        foreach ($catalogues[$service] ?? [] as $element) {
            if ($element['id'] === $sourceId) {
                return $element['prix'];
            }
        }

        return null;
    }

    /**
     * Le sous-total du bloc Hébergement — tarif de la catégorie × nuits,
     * MÊME formule que `Reservations::recapFiche()`. `null` tant que l'unité
     * ou les dates manquent (séjour non déterminé), jamais zéro.
     *
     * @param  \Illuminate\Support\Collection<int, \App\Domain\Hebergement\Models\UniteHebergement>  $unites
     */
    public static function sousTotalHebergement(\Illuminate\Support\Collection $unites, ?string $uniteId, string $dateArrivee, string $dateDepart): string
    {
        $nuits = self::nuits($dateArrivee, $dateDepart);
        $unite = $uniteId === null ? null : $unites->firstWhere('id', $uniteId);
        $tarif = $unite?->categorie?->tarif_base;

        return ($tarif !== null && $nuits !== null)
            ? bcmul((string) $tarif, (string) $nuits, 2)
            : '0.00';
    }

    /**
     * Le montant affiché EN FACE d'une ligne en cours de saisie — prix
     * catalogue × quantité, ou zéro tant que la ligne est incomplète (source
     * pas encore choisie, quantité non numérique). Jamais un refus : le
     * récapitulatif suit la frappe, seul l'enregistrement refuse.
     *
     * @param  array<string, list<array{id: string, libelle: string, prix: string}>>  $catalogues
     */
    public static function sousTotalLigne(array $catalogues, string $service, string $sourceId, string $quantite): string
    {
        $prix = self::prixLigne($catalogues, $service, $sourceId);

        return $prix !== null && is_numeric($quantite)
            ? bcmul($prix, $quantite, 2)
            : '0.00';
    }
}
