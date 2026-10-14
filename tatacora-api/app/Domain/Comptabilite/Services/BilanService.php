<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\Bilan;
use App\Domain\Comptabilite\ReadModels\PosteBilan;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;

/**
 * Bilan SYSCOHADA revise, Systeme Normal — `MODULE_COMPTABILITE_COMPLET_PART2.md`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * Maitre : `m10-bilan.html` — trois postes d'actif, deux de passif, un bandeau
 * d'equilibre. La Tresorerie-Passif est calculee et descendue en plus, sans
 * etre rendue par cette page : `MODULE_COMPTABILITE_COMPLET_PART2.md` §2.3
 * l'exige explicitement (« rubrique presente dans la structure pour
 * extensibilite future, jamais supprimee du modele meme si actuellement a
 * zero »). Un decouvert bancaire ouvert un jour ne doit pas tomber
 * silencieusement hors du bilan.
 *
 * ⚠ ECART DELIBERE — `m10-syscohada.html`, onglet « Bilan »
 * Le maitre : l'onglet du hub repartit les comptes par `type` (19 types :
 * `immo_corporelle`, `dette_fiscale`…, `plan-comptable-syscohada.js` l.276-293)
 * et rend les references de liasse AD/AI/AQ/BB/BH/BT et CA/CB/DA/DR/DT/DZ.
 * Ici : la repartition se fait par PREFIXE de numero de compte, selon
 * `MODULE_COMPTABILITE_COMPLET_PART2.md` §1 et §2, et aucune reference de
 * liasse n'est inventee.
 * Raison : `plan_comptable` n'a pas de colonne `type` — seulement `classe` et
 * `nature` (actif/passif/charge/produit), trop grossiere pour distinguer une
 * dette fiscale d'une dette fournisseur. Le modele du hub n'est donc pas
 * portable en l'etat. Emettre des references de liasse deduites « au mieux »
 * placerait un faux repere reglementaire sur un etat financier. La question est
 * ouverte au rapport de lot.
 */
class BilanService
{
    private const PRECISION = 2;

    private const ZERO = '0.00';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly CompteResultatService $compteResultat,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        string $exerciceId,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): Bilan {
        $balance = $this->balance->genererPourExercice($exerciceId, $statuts, $filtreStatut);
        $resultat = $this->compteResultat->genererPourExercice($exerciceId, $statuts, $filtreStatut);

        $lignes = $balance->lignes;

        // --- ACTIF ---
        $immobilisationsBrutes = $this->sommeDebitrice($lignes, RubriquesSyscohada::IMMOBILISATIONS_BRUTES);
        $amortissements = $this->sommeCreditrice($lignes, RubriquesSyscohada::AMORTISSEMENTS);

        $prefixesCirculant = [...RubriquesSyscohada::STOCKS, ...RubriquesSyscohada::CREANCES];
        $actifCirculant = $this->sommeDebitrice($lignes, $prefixesCirculant);
        $tresorerieActif = $this->sommeDebitrice($lignes, RubriquesSyscohada::TRESORERIE_ACTIF);

        $actif = [
            new PosteBilan(
                section: PosteBilan::SECTION_ACTIF,
                code: 'actif_immobilise',
                libelle: 'Actif immobilisé',
                brut: $immobilisationsBrutes,
                amortissement: $amortissements,
                net: bcsub($immobilisationsBrutes, $amortissements, self::PRECISION),
                prefixes: [...RubriquesSyscohada::IMMOBILISATIONS_BRUTES, ...RubriquesSyscohada::AMORTISSEMENTS],
            ),
            $this->posteSansAmortissement(
                PosteBilan::SECTION_ACTIF,
                'actif_circulant',
                'Actif circulant',
                $actifCirculant,
                $prefixesCirculant,
            ),
            $this->posteSansAmortissement(
                PosteBilan::SECTION_ACTIF,
                'tresorerie_actif',
                'Trésorerie-Actif',
                $tresorerieActif,
                RubriquesSyscohada::TRESORERIE_ACTIF,
            ),
        ];

        // --- PASSIF ---
        //
        // Le resultat de l'exercice figure au passif. AVANT cloture il vient des
        // classes de gestion (c'est `XI`) ; APRES cloture il vient du compte 131
        // ou 139, les classes de gestion ayant ete soldees. L'un des deux est
        // toujours nul, donc l'addition est juste dans les deux etats — et elle
        // reste juste pendant la cloture elle-meme, ou les deux coexistent
        // partiellement (`comptabilite-engine.js` l.632-636).
        $capital = $this->sommeCreditrice($lignes, RubriquesSyscohada::CAPITAL);
        $resultatReporte = $this->sommeCreditrice($lignes, RubriquesSyscohada::RESULTAT_REPORTE);
        $resultatExercice = bcadd($resultatReporte, $resultat->resultatNet, self::PRECISION);

        $capitauxPropres = bcadd($capital, $resultatExercice, self::PRECISION);
        $passifCirculant = $this->sommeCreditrice($lignes, RubriquesSyscohada::DETTES_CIRCULANTES);
        $tresoreriePassif = $this->sommeCreditrice($lignes, RubriquesSyscohada::TRESORERIE_PASSIF);

        $passif = [
            $this->posteSansAmortissement(
                PosteBilan::SECTION_PASSIF,
                'capitaux_propres',
                'Capitaux propres',
                $capitauxPropres,
                [...RubriquesSyscohada::CAPITAL, ...RubriquesSyscohada::RESULTAT_REPORTE],
            ),
            $this->posteSansAmortissement(
                PosteBilan::SECTION_PASSIF,
                'passif_circulant',
                'Passif circulant',
                $passifCirculant,
                RubriquesSyscohada::DETTES_CIRCULANTES,
            ),
            $this->posteSansAmortissement(
                PosteBilan::SECTION_PASSIF,
                'tresorerie_passif',
                'Trésorerie-Passif',
                $tresoreriePassif,
                RubriquesSyscohada::TRESORERIE_PASSIF,
            ),
        ];

        $totalActifBrut = $this->totaliser($actif, 'brut');
        $totalActifAmortissement = $this->totaliser($actif, 'amortissement');
        $totalActif = $this->totaliser($actif, 'net');
        $totalPassif = $this->totaliser($passif, 'net');

        return new Bilan(
            exerciceId: $exerciceId,
            actif: $actif,
            passif: $passif,
            comptesHorsRubrique: $this->comptesHorsRubrique($lignes),
            totalActifBrut: $totalActifBrut,
            totalActifAmortissement: $totalActifAmortissement,
            totalActif: $totalActif,
            totalPassif: $totalPassif,
            // `bccomp`, jamais `==` : les montants sont des DECIMAL(15,2) rendus
            // en chaines, et une egalite flottante sur deux totaux d'une
            // dizaine de termes est le piege d'arrondi classique.
            equilibre: bccomp($totalActif, $totalPassif, self::PRECISION) === 0,
            ecart: bcsub($totalActif, $totalPassif, self::PRECISION),
            resultatExercice: $resultatExercice,
            impotNonComptabilise: $resultat->impotNonComptabilise,
            motifResultatAvantImpot: $resultat->motifResultatAvantImpot,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * Les comptes MOUVEMENTES qui n'entrent ni au Bilan ni au Compte de
     * Resultat — donc dont le solde n'apparait nulle part.
     *
     * La repartition par prefixe n'est pas exhaustive par construction (voir
     * l'entete de `Bilan`). Sans cette liste, un compte ouvert hors nomenclature
     * ne produirait qu'un desequilibre inexplicable ; avec elle, l'ecran nomme
     * le compte fautif et son solde.
     *
     * @param  list<\App\Domain\Comptabilite\ReadModels\LigneBalance>  $lignes
     * @return list<array{numero_compte: string, libelle: string, solde: string}>
     */
    private function comptesHorsRubrique(array $lignes): array
    {
        $connus = [
            ...RubriquesSyscohada::prefixesBilan(),
            ...\App\Domain\Comptabilite\Support\SoldesIntermediairesGestion::tousLesPrefixes(),
        ];

        $orphelins = [];

        foreach ($lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, $connus)) {
                continue;
            }

            $orphelins[] = [
                'numero_compte' => $ligne->numeroCompte,
                'libelle' => $ligne->libelle,
                'solde' => bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION),
            ];
        }

        return $orphelins;
    }

    /**
     * @param  list<string>  $prefixes
     */
    private function posteSansAmortissement(
        string $section,
        string $code,
        string $libelle,
        string $montant,
        array $prefixes,
    ): PosteBilan {
        // `amortissement` a `0.00` plutot qu'absent : c'est un zero CALCULE sur
        // un poste qui ne s'amortit pas, et la colonne « Amort./Depr. » du
        // maitre attend une valeur a chaque ligne.
        return new PosteBilan(
            section: $section,
            code: $code,
            libelle: $libelle,
            brut: $montant,
            amortissement: self::ZERO,
            net: $montant,
            prefixes: $prefixes,
        );
    }

    /**
     * Somme SIGNEE `debit - credit` — sens normal d'un compte d'actif.
     *
     * @param  list<\App\Domain\Comptabilite\ReadModels\LigneBalance>  $lignes
     * @param  list<string>  $prefixes
     */
    private function sommeDebitrice(array $lignes, array $prefixes): string
    {
        $total = self::ZERO;

        foreach ($lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                $total = bcadd($total, bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION), self::PRECISION);
            }
        }

        return $total;
    }

    /**
     * Somme SIGNEE `credit - debit` — sens normal d'un compte de passif.
     *
     * @param  list<\App\Domain\Comptabilite\ReadModels\LigneBalance>  $lignes
     * @param  list<string>  $prefixes
     */
    private function sommeCreditrice(array $lignes, array $prefixes): string
    {
        $total = self::ZERO;

        foreach ($lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                $total = bcadd($total, bcsub($ligne->totalCredit, $ligne->totalDebit, self::PRECISION), self::PRECISION);
            }
        }

        return $total;
    }

    /**
     * @param  list<PosteBilan>  $postes
     */
    private function totaliser(array $postes, string $champ): string
    {
        $total = self::ZERO;

        foreach ($postes as $poste) {
            /** @var string $valeur */
            $valeur = $poste->{$champ};
            $total = bcadd($total, $valeur, self::PRECISION);
        }

        return $total;
    }
}
