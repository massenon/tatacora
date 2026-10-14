<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\JournalGeneral;

/**
 * Journal General — `MODULE_COMPTABILITE_COMPLET.md` §2, `m10-journal.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see RG-11 Immutabilite — cet etat lit, il n'ecrit jamais
 *
 * ## Le controle d'equilibre est PERMANENT, pas a la demande
 *
 * §2 : « Ce controle est calcule et affiche en permanence, jamais une
 * verification ponctuelle a la demande. » Il est donc porte par la reponse
 * elle-meme, jamais par une route separee : deux appels distincts finiraient
 * par afficher un bandeau qui ne correspond pas aux lignes en dessous.
 *
 * ## Les totaux se somment en `bcadd`, jamais en `float`
 *
 * Les montants sont des `DECIMAL(15,2)` castes en chaine par Eloquent. Les
 * additionner en PHP flottant reintroduirait l'erreur d'arrondi que
 * `03_DATABASE_ENGINEERING.md` §11 interdit — et le maitre lui-meme la contourne
 * en JavaScript en comparant des centimes entiers (`m10-comptabilite-data.js`
 * l.190-194), faute de `bccomp` cote navigateur.
 */
class JournalGeneralService
{
    private const PRECISION = 2;

    /**
     * Plafond de lignes rendues d'un bloc. Voir
     * `EtatTropVolumineuxException` : ni troncature, ni pagination.
     */
    public const MAX_LIGNES_DEFAUT = 5000;

    public function __construct(
        private readonly PorteeEcrituresService $portee,
        private readonly int $maxLignes = self::MAX_LIGNES_DEFAUT,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     *
     * @throws EtatTropVolumineuxException
     */
    public function genererPourExercice(
        string $exerciceId,
        array $statuts,
        ?string $journalId = null,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): JournalGeneral {
        $requete = $this->portee->requete($exerciceId, $statuts, $journalId);

        // Le decompte AVANT le chargement : refuser apres avoir hydrate 40 000
        // modeles aurait deja coute la memoire qu'on cherche a economiser.
        $nombre = (clone $requete)->count();

        if ($nombre > $this->maxLignes) {
            throw new EtatTropVolumineuxException($nombre, $this->maxLignes);
        }

        $lignes = $this->portee->ordonner($requete)
            // `centre` est charge parce que §2 le compte parmi les colonnes du
            // Journal, meme si le maitre ne l'affiche pas : sans lui, aucune
            // ligne n'est exploitable par la comptabilite analytique.
            ->with(['journal', 'compte', 'centre'])
            ->get();

        $totalDebit = '0.00';
        $totalCredit = '0.00';

        foreach ($lignes as $ligne) {
            $totalDebit = bcadd($totalDebit, (string) $ligne->debit, self::PRECISION);
            $totalCredit = bcadd($totalCredit, (string) $ligne->credit, self::PRECISION);
        }

        return new JournalGeneral(
            exerciceId: $exerciceId,
            lignes: $lignes,
            totalDebit: $totalDebit,
            totalCredit: $totalCredit,
            equilibre: bccomp($totalDebit, $totalCredit, self::PRECISION) === 0,
            statuts: $this->portee->statuts($exerciceId, $statuts, $journalId),
            filtresAppliques: ['journal_id' => $journalId, 'statut' => $filtreStatut],
        );
    }
}
