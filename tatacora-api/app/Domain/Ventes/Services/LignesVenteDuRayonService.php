<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Services;

use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Les LIGNES DE VENTE d'un rayon (bar M5, restaurant M4) — lecture seule,
 * AUTEUR UNIQUE de leur filtrage et de leur total.
 *
 * ## Pourquoi un service, et pourquoi le 11/09/2026 (PA-197)
 *
 * La requête et le total vivaient dans le trait Livewire `EcranDeCarte`
 * (onglet « Ventes du rayon », Product Owner, 03/09/2026). Le client Flutter
 * doit rendre le même onglet ; une route d'API qui aurait réécrit la requête
 * aurait donné deux lectures, et le docblock du total le dit déjà : « le jour
 * où l'un changerait, le papier remis au client et l'écran depuis lequel il a
 * été édité afficheraient deux chiffres différents ». L'écran PWA, son export
 * et la route d'API appellent désormais CE service.
 *
 * ## Le filtre de module est la substance
 *
 * Une vente est multi-modules par nature — le même ticket porte une bière
 * (M5) et un poulet (M4) —, et c'est la LIGNE qui porte son module, jamais
 * la vente. Filtrer sur la vente afficherait au bar les plats du même ticket.
 *
 * @see EF-M5 — carte du bar, onglet des ventes
 * @see RG-02 — une vente annulée reste au registre, son montant n'est pas de l'argent
 */
final class LignesVenteDuRayonService
{
    private const PRECISION_MONTANT = 2;

    /** Le rayon du bar — code de module estampillé sur la ligne (VenteService::MODULES). */
    public const RAYON_BAR = 'M5';

    /**
     * Lignes par page — celle de l'onglet PWA (EcranDeCarte::PAR_PAGE),
     * pour que « TOTAL DE LA PAGE » désigne la même page sur les deux clients.
     */
    public const PAR_PAGE = 10;

    /**
     * Les lignes du rayon, filtres appliqués, du plus récent au plus ancien.
     *
     * - `$recherche` : le nom FIGÉ de la ligne, le numéro du ticket, le login
     *   de qui a encaissé — les trois colonnes que le tableau rend. Chercher
     *   sur une donnée absente de l'écran ferait disparaître des lignes sans
     *   que rien n'explique pourquoi.
     * - `$statut` : hors du registre `Vente::STATUTS`, il est ignoré.
     * - `$debut`, `$fin` : `AAAA-MM-JJ`, **bornes incluses** ; une borne
     *   illisible est IGNORÉE, jamais appliquée à moitié (voir [dateLisible]).
     *
     * Le tri passe par une JOINTURE plutôt que par une sous-requête : c'est
     * `ventes.created_at` qui ordonne le journal, et `lignes_vente` n'a aucune
     * colonne de date métier.
     *
     * @return Builder<LigneVente>
     */
    public function requete(
        string $module,
        string $recherche = '',
        string $statut = '',
        string $debut = '',
        string $fin = '',
    ): Builder {
        if (! in_array($module, VenteService::MODULES_ENCAISSABLES, true)) {
            // Un rayon hors registre rendrait une liste VIDE, lue comme « rien
            // vendu » : c'est un défaut d'appel, il se nomme.
            throw new \InvalidArgumentException('Rayon de vente inconnu : '.$module);
        }

        /** @var Builder<LigneVente> $requete */
        $requete = LigneVente::query()
            ->select('lignes_vente.*')
            ->join('ventes', 'ventes.id', '=', 'lignes_vente.vente_id')
            ->where('lignes_vente.module', $module);

        $terme = trim($recherche);

        if ($terme !== '') {
            $requete->where(function (Builder $sous) use ($terme): void {
                $sous->where('lignes_vente.nom', 'like', '%'.$terme.'%')
                    ->orWhere('ventes.numero', 'like', '%'.$terme.'%')
                    ->orWhereIn(
                        'ventes.utilisateur_id',
                        User::query()->where('login', 'like', '%'.$terme.'%')->select('id'),
                    );
            });
        }

        if (in_array($statut, Vente::STATUTS, true)) {
            $requete->where('ventes.statut', $statut);
        }

        $debutLisible = self::dateLisible($debut);
        $finLisible = self::dateLisible($fin);

        if ($debutLisible !== null) {
            $requete->whereDate('ventes.created_at', '>=', $debutLisible);
        }

        if ($finLisible !== null) {
            // ⚠ BORNES INCLUSES, LES DEUX. `whereDate()` compare la DATE de
            // `created_at`, pas l'instant : une vente encaissée à 19 h 40 le
            // dernier jour de la plage est retenue. Un `where('created_at',
            // '<=', $fin)` la perdrait — la borne vaudrait minuit, et la
            // journée entière disparaîtrait du tableau sans un mot.
            $requete->whereDate('ventes.created_at', '<=', $finLisible);
        }

        return $requete
            ->orderByDesc('ventes.created_at')
            ->orderByDesc('lignes_vente.id');
    }

    /**
     * Les compteurs du JEU FILTRÉ ENTIER — jamais de la page.
     *
     * Le total N'ADDITIONNE QUE LES LIGNES VALIDÉES : une vente annulée reste
     * au registre (RG-02) mais son montant n'est pas de l'argent — l'additionner
     * gonflerait le chiffre du rayon. Un total qui changerait en tournant les
     * pages dirait deux vérités sur le même filtre.
     *
     * @param  Builder<LigneVente>  $requete
     * @return array{total: string, annulees: int, lignes: int}
     */
    public function totaux(Builder $requete): array
    {
        $total = '0.00';
        $annulees = 0;
        $lignes = 0;

        foreach ((clone $requete)->select(['lignes_vente.montant', 'ventes.statut as statut_vente'])->get() as $brute) {
            $lignes++;

            if ($brute->getAttribute('statut_vente') === 'annulee') {
                $annulees++;

                continue;
            }

            $total = bcadd($total, (string) $brute->getAttribute('montant'), self::PRECISION_MONTANT);
        }

        return ['total' => $total, 'annulees' => $annulees, 'lignes' => $lignes];
    }

    /**
     * Une date de filtre RÉELLEMENT exploitable, ou `null`.
     *
     * Une chaîne quelconque passée telle quelle à `whereDate()` produirait une
     * comparaison sur une date nulle, donc un tableau vide qui ressemblerait à
     * « aucune vente ce jour-là ».
     */
    public static function dateLisible(string $saisie): ?string
    {
        $saisie = trim($saisie);

        if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $saisie) !== 1) {
            return null;
        }

        return checkdate(
            (int) substr($saisie, 5, 2),
            (int) substr($saisie, 8, 2),
            (int) substr($saisie, 0, 4),
        ) ? $saisie : null;
    }
}
