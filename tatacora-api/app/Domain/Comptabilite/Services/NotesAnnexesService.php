<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\LigneBalance;
use App\Domain\Comptabilite\ReadModels\Note;
use App\Domain\Comptabilite\ReadModels\NotesAnnexes;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;

/**
 * Notes Annexes — `MODULE_COMPTABILITE_COMPLET_PART4.md` §1,
 * `m10-notes-annexes.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Trois notes sur sept sont INDISPONIBLES, et chacune pour une raison
 * ## differente qui est nommee
 *
 * - **Note 2, tableau des immobilisations.** §1.1 la veut « valeur brute
 *   ouverture + acquisitions - cessions = valeur brute cloture ». La valeur
 *   d'OUVERTURE suppose un report a nouveau, qui n'existe nulle part dans ce
 *   depot (Partie 4 §2.1 etape 6, non implementee). Rendre `0` affirmerait que
 *   le parc etait vide au premier jour de l'exercice — sur la note meme qui
 *   sert a suivre son evolution. Seules les ACQUISITIONS de l'exercice sont
 *   donc rendues, et l'etat le dit.
 * - **Note 5, etat des stocks.** §1.1 la veut « par point de stockage
 *   (Cuisine/Bar/Garage) et categorie, source directe `mouvements_stock` ».
 *   Cette table appartient a M6, et `02_SOFTWARE_ARCHITECTURE.md` §3 interdit a
 *   un domaine de lire le modele d'un autre hors relation documentee. La
 *   VALORISATION comptable (comptes 311/321/325) est rendue — elle est dans
 *   M10 — et le detail physique est nomme indisponible plutot que reinvente
 *   depuis la comptabilite, ou il serait faux des le premier ecart d'inventaire.
 * - **Note 6, effectif du personnel.** Donnee M13, meme regle de dependance.
 *   Aucun compte comptable ne porte un effectif : le deduire de la masse
 *   salariale serait une invention.
 *
 * Aucune de ces trois n'est omise : une note absente se lirait comme une note
 * sans objet, alors que ce sont des notes OBLIGATOIRES au sens SYSCOHADA.
 */
class NotesAnnexesService
{
    private const PRECISION = 2;

    public const MOTIF_REPORT_ABSENT = 'report_a_nouveau_absent';

    public const MOTIF_DOMAINE_STOCKS = 'detail_physique_hors_domaine_m10';

    public const MOTIF_DOMAINE_RH = 'effectif_hors_domaine_m10';

    public const MOTIF_NON_SAISI = 'non_saisi_par_le_comptable';

    /** PA-20 — le lettrage par anciennete n'est arbitre nulle part. */
    public const MOTIF_ANCIENNETE_NON_ARBITREE = 'lettrage_par_anciennete_non_arbitre';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        ExerciceComptable $exercice,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): NotesAnnexes {
        $balance = $this->balance->genererPourExercice($exercice->id, $statuts, $filtreStatut);
        $lignes = $balance->lignes;

        $notes = [
            new Note(
                numero: 1,
                titre: 'Règles et méthodes comptables',
                etat: NotesAnnexes::ETAT_DISPONIBLE,
                texte: __('comptabilite.notes.regles_et_methodes'),
            ),
            new Note(
                numero: 2,
                titre: 'Tableau des immobilisations',
                etat: NotesAnnexes::ETAT_DISPONIBLE,
                postes: $this->postesParPrefixe($lignes, RubriquesSyscohada::IMMOBILISATIONS_BRUTES, debitrice: true),
                // Les acquisitions sont reelles ; c'est la valeur d'OUVERTURE
                // qui manque, et avec elle la variation. Le motif accompagne
                // une note pourtant disponible : il borne ce qu'elle dit.
                motif: self::MOTIF_REPORT_ABSENT,
            ),
            new Note(
                numero: 3,
                titre: 'Tableau des amortissements',
                etat: NotesAnnexes::ETAT_DISPONIBLE,
                postes: $this->postesParPrefixe($lignes, RubriquesSyscohada::AMORTISSEMENTS, debitrice: false),
                motif: self::MOTIF_REPORT_ABSENT,
            ),
            new Note(
                numero: 4,
                titre: 'État des créances et dettes',
                etat: NotesAnnexes::ETAT_DISPONIBLE,
                postes: [
                    ...$this->postesParPrefixe($lignes, RubriquesSyscohada::CREANCES, debitrice: true),
                    ...$this->postesParPrefixe($lignes, RubriquesSyscohada::DETTES_CIRCULANTES, debitrice: false),
                ],
                // PA-20 : la ventilation 30/60/90 jours n'existe dans aucun
                // document de la collection. La note rend les soldes, pas leur
                // anciennete — l'inventer donnerait une analyse de recouvrement
                // dont personne n'a defini les paliers.
                motif: self::MOTIF_ANCIENNETE_NON_ARBITREE,
            ),
            new Note(
                numero: 5,
                titre: 'État des stocks',
                etat: NotesAnnexes::ETAT_DISPONIBLE,
                postes: $this->postesParPrefixe($lignes, RubriquesSyscohada::STOCKS, debitrice: true),
                motif: self::MOTIF_DOMAINE_STOCKS,
            ),
            new Note(
                numero: 6,
                titre: 'Effectif du personnel',
                etat: NotesAnnexes::ETAT_INDISPONIBLE,
                motif: self::MOTIF_DOMAINE_RH,
            ),
            new Note(
                numero: 7,
                titre: 'Événements postérieurs à la clôture',
                etat: $exercice->evenements_posterieurs === null || $exercice->evenements_posterieurs === ''
                    ? NotesAnnexes::ETAT_NON_SAISIE
                    : NotesAnnexes::ETAT_DISPONIBLE,
                texte: $exercice->evenements_posterieurs,
                motif: $exercice->evenements_posterieurs === null || $exercice->evenements_posterieurs === ''
                    ? self::MOTIF_NON_SAISI
                    : null,
            ),
        ];

        return new NotesAnnexes(
            exerciceId: $exercice->id,
            notes: $notes,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * Une ligne PAR COMPTE mouvemente relevant des prefixes — pas un total.
     *
     * Une note annexe existe precisement pour DETAILLER ce que le bilan agrege :
     * la ramener a un total la rendrait redondante avec le poste de bilan
     * qu'elle est censee expliquer.
     *
     * @param  list<LigneBalance>  $lignes
     * @param  list<string>  $prefixes
     * @return list<array{libelle: string, montant: string, prefixes: list<string>}>
     */
    private function postesParPrefixe(array $lignes, array $prefixes, bool $debitrice): array
    {
        $postes = [];

        foreach ($lignes as $ligne) {
            if (! RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                continue;
            }

            $montant = $debitrice
                ? bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION)
                : bcsub($ligne->totalCredit, $ligne->totalDebit, self::PRECISION);

            $postes[] = [
                'libelle' => $ligne->libelle.' ('.$ligne->numeroCompte.')',
                'montant' => $montant,
                'prefixes' => [$ligne->numeroCompte],
            ];
        }

        return $postes;
    }
}
