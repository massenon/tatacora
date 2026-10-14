<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\RepartitionStatuts;
use Illuminate\Database\Eloquent\Builder;

/**
 * Le 3e niveau du RBAC applique a M10 : le FILTRAGE EN BASE.
 *
 * @see RG-16 RBAC a trois niveaux
 *
 * ## Ce que ce service centralise, et pourquoi c'est un seul endroit
 *
 * Les trois etats de ce lot — Journal, Grand Livre, Balance — partagent la meme
 * portee : un exercice, un statut. Ecrite trois fois, cette portee finirait par
 * diverger, et deux ecrans afficheraient deux verites sur la meme donnee. C'est
 * exactement le raisonnement de PA-121 sur les series du tableau de bord : les
 * points d'une courbe se calculent COMME le KPI, jamais par un agregat
 * parallele.
 *
 * ## L'exercice est une portee OBLIGATOIRE, pas un filtre facultatif
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §1 : « Tout ecran de M10 filtre
 * systematiquement par `exercice_id` — jamais un etat "toutes annees
 * confondues" par defaut, qui n'aurait pas de sens comptable. » Aucune methode
 * de ce service ne sait produire une requete sans exercice : l'oubli est
 * impossible parce que le parametre n'est pas nullable.
 *
 * ## Le statut est un registre FERME
 *
 * `EcritureComptable::FILTRES_STATUT`. Une valeur inconnue est refusee par le
 * `FormRequest`, jamais interpretee « au mieux » — un statut ajoute demain
 * n'obtiendra pas un comportement par omission.
 */
class PorteeEcrituresService
{
    /**
     * La requete de base de tout etat de M10.
     *
     * @param  list<string>  $statuts
     * @return Builder<EcritureComptable>
     */
    public function requete(string $exerciceId, array $statuts, ?string $journalId = null): Builder
    {
        return EcritureComptable::query()
            ->where('exercice_id', $exerciceId)
            ->whereIn('statut', $statuts)
            ->when(
                $journalId !== null,
                fn (Builder $q): Builder => $q->where('journal_id', $journalId),
            );
    }

    /**
     * L'ordre chronologique de TOUS les etats de M10.
     *
     * `MODULE_COMPTABILITE_COMPLET.md` §2 ordonne par `date_ecriture` puis
     * `created_at`, en commentant « ordre de saisie a date egale — jamais un
     * ordre non deterministe ».
     *
     * ⚠ **Le couple ne suffit pourtant pas.** Les `timestamps` de Laravel sont
     * des `DATETIME` sans fraction de seconde : les lignes d'une meme piece,
     * ecrites dans une seule transaction par `enregistrerPiece()`, partagent
     * systematiquement leur `created_at` a la seconde pres. Leur ordre relatif
     * serait alors celui que MySQL choisit, et il peut changer d'une execution a
     * l'autre — le Grand Livre rendrait le meme solde final mais une colonne
     * « solde progressif » differente. `id` ferme le classement : ce n'est pas
     * un ordre metier, c'est une garantie de reproductibilite.
     *
     * @param  Builder<EcritureComptable>  $requete
     * @return Builder<EcritureComptable>
     */
    public function ordonner(Builder $requete): Builder
    {
        return $requete
            ->orderBy('date_ecriture')
            ->orderBy('created_at')
            ->orderBy('id');
    }

    /**
     * Le decompte par statut sur la portee, SANS le filtre de statut.
     *
     * C'est tout l'interet : il dit ce qui existe, pas ce qui a ete retenu. Le
     * calculer avec le filtre rendrait toujours le nombre de lignes affichees
     * et n'apprendrait rien.
     *
     * @param  list<string>  $statutsRetenus
     */
    public function statuts(string $exerciceId, array $statutsRetenus, ?string $journalId = null, ?string $compteId = null): RepartitionStatuts
    {
        $decompte = EcritureComptable::query()
            ->where('exercice_id', $exerciceId)
            ->when(
                $journalId !== null,
                fn (Builder $q): Builder => $q->where('journal_id', $journalId),
            )
            ->when(
                $compteId !== null,
                fn (Builder $q): Builder => $q->where('compte_id', $compteId),
            )
            ->selectRaw('statut, COUNT(*) AS total')
            ->groupBy('statut')
            ->pluck('total', 'statut');

        return new RepartitionStatuts(
            statutsRetenus: $statutsRetenus,
            brouillon: (int) $decompte->get('brouillon', 0),
            validee: (int) $decompte->get('validee', 0),
        );
    }
}
