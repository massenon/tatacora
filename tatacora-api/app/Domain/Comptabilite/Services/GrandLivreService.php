<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\GrandLivre;
use App\Domain\Comptabilite\ReadModels\LigneGrandLivre;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;

/**
 * Grand Livre — `MODULE_COMPTABILITE_COMPLET.md` §3, `m10-grand-livre.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Seuls les comptes MOUVEMENTES apparaissent au selecteur
 *
 * §3 : « un compte jamais mouvemente sur l'exercice n'apparait pas, coherent
 * avec la pratique comptable standard : le Grand Livre restitue l'activite
 * reelle, pas le referentiel complet ». Le maitre applique exactement cette
 * regle (`m10-grand-livre.html` l.52-55) et cite ce paragraphe.
 *
 * `comptesMouvementes()` sert donc le `<select>` de l'ecran. Il n'y a pas de
 * seconde liste : le referentiel complet reste sur
 * `GET /comptabilite/plan-comptable`, qui est un autre ecran et une autre
 * question.
 *
 * ## Le solde progressif se cumule en `bcsub`/`bcadd`
 *
 * Un cumul flottant sur plusieurs milliers de lignes derive : l'erreur se
 * propage ligne apres ligne, et c'est la colonne la plus lue de l'ecran.
 */
class GrandLivreService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly PorteeEcrituresService $portee,
        private readonly BalanceGeneraleService $balance,
        private readonly int $maxLignes = JournalGeneralService::MAX_LIGNES_DEFAUT,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     *
     * @throws EtatTropVolumineuxException
     */
    public function genererPourCompte(
        string $exerciceId,
        CompteComptable $compte,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): GrandLivre {
        $requete = $this->portee->requete($exerciceId, $statuts)
            ->where('compte_id', $compte->id);

        $nombre = (clone $requete)->count();

        if ($nombre > $this->maxLignes) {
            throw new EtatTropVolumineuxException($nombre, $this->maxLignes);
        }

        $ecritures = $this->portee->ordonner($requete)
            ->with(['journal', 'centre'])
            ->get();

        $solde = '0.00';
        $lignes = [];

        foreach ($ecritures as $ecriture) {
            // Debit - credit : positif = debiteur, negatif = crediteur (§3).
            $solde = bcadd(
                $solde,
                bcsub((string) $ecriture->debit, (string) $ecriture->credit, self::PRECISION),
                self::PRECISION,
            );

            $lignes[] = new LigneGrandLivre($ecriture, $solde);
        }

        // Le report à nouveau existe (lot 2) : l'ouverture se LIT. Les comptes
        // de gestion (classes 6 à 9) repartent de zéro chaque exercice ; les
        // comptes de bilan portent leur à-nouveau — écrit (précédent
        // clôturé, déjà DANS les lignes ci-dessus) ou provisoire (calculé,
        // absent des lignes : il s'ajoute).
        $report = $this->balance->soldesOuverture($exerciceId);
        $gestion = in_array(substr((string) $compte->numero_compte, 0, 1), ['6', '7', '8', '9'], true);
        $inconnue = ! $gestion && ! $report['connu'];
        $ouverture = $gestion ? '0.00' : ($report['soldes'][(string) $compte->numero_compte] ?? '0.00');

        return new GrandLivre(
            exerciceId: $exerciceId,
            compte: $compte,
            lignes: $lignes,
            soldeMouvements: $solde,
            statuts: $this->portee->statuts($exerciceId, $statuts, compteId: $compte->id),
            filtresAppliques: ['statut' => $filtreStatut],
            // Ouverture INCONNUE (précédent clôturé avant le lot 2, sans pièce
            // d'à-nouveaux) : « — », jamais zéro (Article 7).
            soldeOuverture: $inconnue ? null : $ouverture,
            soldeCloture: $inconnue ? null : ($report['provisoire'] ? bcadd($ouverture, $solde, self::PRECISION) : $solde),
            motifSoldesIndisponibles: $inconnue ? GrandLivre::MOTIF_REPORT_ABSENT : null,
            ouvertureProvisoire: $report['provisoire'] && ! $gestion,
            anneeOuverture: $report['annee'],
        );
    }

    /**
     * Les comptes reellement mouvementes sur l'exercice, dans l'ordre du
     * selecteur du maitre (par numero de compte, l.55 : `.sort()`).
     *
     * @param  list<string>  $statuts
     * @return EloquentCollection<int, CompteComptable>
     */
    public function comptesMouvementes(string $exerciceId, array $statuts): EloquentCollection
    {
        return CompteComptable::query()
            ->whereIn(
                'id',
                $this->portee->requete($exerciceId, $statuts)->select('compte_id'),
            )
            ->orderBy('numero_compte')
            ->get();
    }
}
