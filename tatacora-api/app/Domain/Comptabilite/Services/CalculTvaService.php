<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;
use RuntimeException;

/**
 * Calcul de la TVA sur un montant (M10 / M2).
 *
 * ## Le taux n'est JAMAIS codé en dur
 *
 * Un taux de TVA est une donnée réglementaire : il change par décision de
 * l'État, pas par décision de l'équipe. Le coder en dur imposerait un
 * déploiement pour s'y conformer, et surtout recalculerait rétroactivement des
 * factures déjà émises sous l'ancien taux si un historique était régénéré.
 *
 * Il vit donc dans `parametres_systeme` (clé `taux_tva`), au même titre que les
 * taux CNSS/ITS (RG-10). Si le paramètre est absent, ce service **refuse de
 * calculer** plutôt que de retomber sur une valeur par défaut — même discipline
 * que `CompteResultatService` avec le taux d'IS non fixé (PA-19,
 * A1_MASTER_PROMPT.md §2.1). Une TVA calculée avec un taux supposé produirait
 * des factures fausses que personne ne remarquerait avant un contrôle DGI.
 *
 * ## Précision
 *
 * `bcmath` exclusivement : arrondir une TVA en virgule flottante sur des
 * milliers de factures produit un écart de déclaration inexplicable.
 */
class CalculTvaService
{
    public const CLE_PARAMETRE_TAUX = 'taux_tva';

    /**
     * Assujettissement à la TVA. Permet d'exploiter le système avant
     * l'assujettissement effectif, ou de le suspendre, sans toucher au code.
     * Désactivée, la TVA vaut 0 et HT = TTC.
     */
    public const CLE_PARAMETRE_ACTIVE = 'tva_active';

    /**
     * Convention des prix du catalogue : `ht` ou `ttc`.
     *
     * Résout PA-37 par configuration. Les deux sens restent implémentés ;
     * ce paramètre dit lequel s'applique aux tarifs saisis (tarif_base d'une
     * catégorie d'hébergement, prix de vente d'un plat ou d'une boisson).
     */
    public const CLE_PARAMETRE_CONVENTION = 'convention_prix';

    public const CONVENTION_HT = 'ht';

    public const CONVENTION_TTC = 'ttc';

    private const PRECISION = 2;

    /** Précision intermédiaire, pour n'arrondir qu'au dernier moment. */
    private const PRECISION_CALCUL = 6;

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Taux applicable, en pourcentage (ex. « 18.00 »).
     *
     * @throws RuntimeException si le paramètre n'est pas configuré
     */
    public function taux(): string
    {
        $taux = $this->parametres->get(self::CLE_PARAMETRE_TAUX);

        if (blank($taux)) {
            throw new RuntimeException(__('comptabilite.taux_absent', ['cle' => self::CLE_PARAMETRE_TAUX]));
        }

        return $taux;
    }

    /**
     * Le taux est-il renseigné ? Répond sur la CAPACITÉ à calculer, jamais sur
     * l'intention de le faire — {@see estActive()} porte l'intention.
     */
    public function estConfigure(): bool
    {
        return filled($this->parametres->get(self::CLE_PARAMETRE_TAUX));
    }

    /**
     * État réel de la TVA, destiné au badge de l'écran Paramètres.
     *
     * **Dérivé de ce que le service peut réellement faire, jamais du seul
     * commutateur d'activation** (PA-62, 19/08/2026). `estActive()` et
     * `estConfigure()` sont deux commutateurs indépendants : rien n'empêche
     * `tva_active = true` avec `taux_tva` absent. Cet état existe, il a été
     * reproduit, et sa conséquence est une `RuntimeException` **au moment
     * d'émettre la facture** — c'est-à-dire au comptoir, en présence du client.
     *
     * Le refus est la bonne décision : émettre à 0 % pendant qu'un
     * Administrateur croit la TVA active serait une sous-taxation silencieuse
     * sur un document fiscal immuable, que seul un avoir pourrait corriger.
     * Ce qui manquait, c'est un endroit où l'incohérence se **voie avant**
     * d'atteindre une vente.
     *
     * Même règle que `MecefServiceProvider::etatConfiguration()` (PA-61) :
     * un indicateur d'état se dérive de ce qui est en place, jamais de ce qui
     * est configuré pour l'être.
     *
     * @return 'inactive'|'activee_sans_taux'|'activee_convention_invalide'|'active'
     */
    public function etatTva(): string
    {
        if (! $this->estActive()) {
            return 'inactive';
        }

        if (! $this->estConfigure()) {
            return 'activee_sans_taux';
        }

        try {
            $this->convention();
        } catch (RuntimeException) {
            // `convention()` refuse une valeur illisible plutôt que de replier
            // sur « HT » — un repli ferait facturer 18 % de trop sur des tarifs
            // qui les incluaient déjà. Ici on nomme le refus sans le relancer :
            // un badge d'état ne doit pas faire tomber l'écran qui l'affiche.
            return 'activee_convention_invalide';
        }

        return 'active';
    }

    /**
     * TVA calculée sur une base HORS TAXE : montant × taux / 100.
     */
    public function depuisHt(string $montantHt): string
    {
        $tva = bcdiv(
            bcmul($montantHt, $this->taux(), self::PRECISION_CALCUL),
            '100',
            self::PRECISION_CALCUL,
        );

        return $this->arrondir($tva);
    }

    /**
     * TVA incluse dans un montant TOUTES TAXES : TTC × taux / (100 + taux).
     *
     * Les deux sens sont fournis parce que la documentation ne tranche pas si
     * les tarifs du gîte (`categories_hebergement.tarif_base`) sont HT ou TTC —
     * question ouverte signalée au Product Owner. Se tromper de sens sur un
     * tarif à 25 000 F fait un écart de 3 813 F par nuitée.
     */
    public function depuisTtc(string $montantTtc): string
    {
        $taux = $this->taux();

        $tva = bcdiv(
            bcmul($montantTtc, $taux, self::PRECISION_CALCUL),
            bcadd('100', $taux, self::PRECISION_CALCUL),
            self::PRECISION_CALCUL,
        );

        return $this->arrondir($tva);
    }

    public function htVersTtc(string $montantHt): string
    {
        return bcadd($montantHt, $this->depuisHt($montantHt), self::PRECISION);
    }

    public function ttcVersHt(string $montantTtc): string
    {
        return bcsub($montantTtc, $this->depuisTtc($montantTtc), self::PRECISION);
    }

    // ------------------------------------------------------------ Commutateurs

    /**
     * L'entreprise est-elle assujettie à la TVA ?
     *
     * Par défaut **non** : tant qu'un Administrateur n'a pas activé la TVA en
     * connaissance de cause, le système ne doit pas en ajouter aux factures.
     * Une TVA appliquée par défaut serait facturée à des clients réels sans
     * qu'aucune décision ne l'ait autorisée.
     *
     * **Cette méthode répond sur l'INTENTION, jamais sur la capacité.** Elle
     * peut être vraie alors que le taux est absent. Un badge, un écran ou un
     * rapport qui veut dire « la TVA fonctionne » doit lire {@see etatTva()}
     * (PA-62).
     */
    public function estActive(): bool
    {
        return filter_var(
            $this->parametres->get(self::CLE_PARAMETRE_ACTIVE, 'false'),
            FILTER_VALIDATE_BOOLEAN,
        );
    }

    /**
     * Convention appliquée aux prix du catalogue : `ht` ou `ttc`.
     *
     * @throws RuntimeException si la valeur configurée n'est ni l'une ni l'autre
     */
    public function convention(): string
    {
        $convention = strtolower(trim(
            $this->parametres->get(self::CLE_PARAMETRE_CONVENTION, self::CONVENTION_HT) ?? '',
        ));

        if (! in_array($convention, [self::CONVENTION_HT, self::CONVENTION_TTC], true)) {
            // Refus plutôt qu'un repli silencieux : une convention illisible
            // traitée comme « HT » par défaut ferait facturer 18 % de trop sur
            // des tarifs qui les incluaient déjà.
            throw new RuntimeException(__('comptabilite.convention_inconnue', [
                'convention' => $convention,
                'cle' => self::CLE_PARAMETRE_CONVENTION,
            ]));
        }

        return $convention;
    }

    /**
     * Ventile un montant du catalogue en HT / TVA / TTC selon les deux
     * commutateurs. **Point d'entrée unique** : aucun appelant ne doit décider
     * lui-même du sens du calcul, sans quoi la convention finirait appliquée
     * différemment selon les modules.
     *
     * @return array{ht: string, tva: string, ttc: string, taux: string, convention: string, tva_active: bool}
     */
    public function ventiler(string $montantCatalogue): array
    {
        if (! $this->estActive()) {
            // Non assujetti : le montant est ce qu'il est, sans taxe.
            return [
                'ht' => $montantCatalogue,
                'tva' => '0.00',
                'ttc' => $montantCatalogue,
                'taux' => '0.00',
                'convention' => $this->conventionSansValidation(),
                'tva_active' => false,
            ];
        }

        $convention = $this->convention();

        if ($convention === self::CONVENTION_TTC) {
            $tva = $this->depuisTtc($montantCatalogue);

            return [
                'ht' => bcsub($montantCatalogue, $tva, self::PRECISION),
                'tva' => $tva,
                'ttc' => $montantCatalogue,
                'taux' => $this->taux(),
                'convention' => $convention,
                'tva_active' => true,
            ];
        }

        $tva = $this->depuisHt($montantCatalogue);

        return [
            'ht' => $montantCatalogue,
            'tva' => $tva,
            'ttc' => bcadd($montantCatalogue, $tva, self::PRECISION),
            'taux' => $this->taux(),
            'convention' => $convention,
            'tva_active' => true,
        ];
    }

    /**
     * Convention affichée quand la TVA est inactive : la valeur configurée est
     * alors sans effet sur le calcul, on ne la valide donc pas.
     */
    private function conventionSansValidation(): string
    {
        return strtolower(trim(
            $this->parametres->get(self::CLE_PARAMETRE_CONVENTION, self::CONVENTION_HT) ?? self::CONVENTION_HT,
        ));
    }

    /**
     * Arrondi commercial au centime (demi vers le haut), appliqué une seule
     * fois en fin de calcul.
     */
    private function arrondir(string $montant): string
    {
        $ajustement = bccomp($montant, '0', self::PRECISION_CALCUL) >= 0 ? '0.005' : '-0.005';

        return bcadd($montant, $ajustement, self::PRECISION);
    }
}
