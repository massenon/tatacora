<?php

declare(strict_types=1);

namespace App\Domain\Numerotation\Services;

use Illuminate\Support\Facades\DB;

/**
 * Allocation d'un numéro de document séquentiel par année — `PREFIXE-AAAA-NNNNN`.
 *
 * ## Ce que ce service remplace, et pourquoi c'était faux
 *
 * Trois numérotations coexistaient dans le dépôt, toutes cassées de la même
 * façon :
 *
 *  - `'V-' . date('Y') . '-' . substr($venteBar->id, 0, 5)` — cinq caractères
 *    d'un UUID, ni séquentiel ni unique : deux ventes peuvent partager le même
 *    préfixe, et le numéro ne dit rien de l'ordre des encaissements ;
 *  - `'V-' . date('YmdHis')` en repli — deux ventes dans la même seconde
 *    portent le même numéro ;
 *  - `Depense::count() + 1` — faux dès la première annulation (le compteur
 *    recule), et deux saisies simultanées lisent le même total, donc
 *    produisent le même numéro. L'index unique le rejette, et l'opérateur voit
 *    une erreur SQL pour une raison qui n'a rien à voir avec sa saisie.
 *
 * ## Comment l'unicité est réellement tenue
 *
 * Le maximum de l'année est lu **sous verrou pessimiste** (`FOR UPDATE`) dans
 * la transaction appelante : InnoDB pose alors un verrou d'intervalle sur
 * l'index unique du numéro, ce qui sérialise deux allocations concurrentes.
 * Même famille de garantie que RG-01 — la lecture avant écriture ne suffit
 * jamais, seul le verrou empêche la condition de course.
 *
 * L'index unique de la colonne reste le dernier rempart : ce service le sert,
 * il ne le remplace pas.
 *
 * ## Ce service N'EST PAS idempotent, et c'est voulu
 *
 * Chaque appel ALLOUE un numéro — comme `FactureDao.numeroSuivant()` côté
 * Flutter, dont PA-101 rappelle qu'un test l'avait pris pour une lecture et
 * brûlait deux numéros à chaque exécution. L'idempotence d'un enregistrement
 * se joue **avant** cet appel, sur l'identifiant fourni par le client : si le
 * document existe déjà, on le rend tel quel sans repasser ici.
 *
 * ## Emplacement
 *
 * `app/Shared/` serait le foyer naturel d'un service transverse de ce genre.
 * Le lot 0b (PA-159) a un périmètre de fichiers qui n'inclut pas `Shared/` —
 * le service y est donc posé dans un domaine dédié plutôt que dupliqué entre
 * `Ventes` et `Depenses`, où il aurait divergé au premier changement de
 * format. Déplacement à prévoir lors d'une passe transverse.
 */
class SequenceDocumentService
{
    private const LARGEUR = 5;

    /**
     * Alloue le prochain numéro de l'année pour une table donnée.
     *
     * À appeler DANS la transaction qui écrit le document : hors transaction,
     * le verrou est relâché immédiatement et deux appels concurrents peuvent
     * rendre le même numéro.
     *
     * @param  string  $table   table portant la colonne `numero` (ou `$colonne`), avec un index
     * @param  string  $prefixe `V` pour une vente, `DEP` pour une dépense
     * @param  int|null  $annee année du document — celle du jour par défaut
     * @param  string  $colonne nom de la colonne portant le numéro — `numero` par défaut.
     *                          Ajouté pour `ecritures_comptables.numero_piece` (Vague E, 01/09/2026) :
     *                          plusieurs lignes d'une même pièce y partagent la même valeur, ce que
     *                          `orderByDesc()`/`value()` traitent sans distinction — le maximum d'un
     *                          ensemble de doublons reste ce même maximum.
     */
    public function suivant(string $table, string $prefixe, ?int $annee = null, string $colonne = 'numero'): string
    {
        $annee ??= (int) now()->format('Y');
        $motif = sprintf('%s-%d-', $prefixe, $annee);

        $dernier = DB::table($table)
            ->where($colonne, 'like', $motif.'%')
            ->orderByDesc($colonne)
            ->lockForUpdate()
            ->value($colonne);

        $rang = $dernier === null
            ? 0
            // Le rang est le SUFFIXE, pas le numéro entier : `V-2026-00042`
            // lu comme un entier vaudrait 2026.
            : (int) substr((string) $dernier, strlen($motif));

        return $motif.str_pad((string) ($rang + 1), self::LARGEUR, '0', STR_PAD_LEFT);
    }
}
