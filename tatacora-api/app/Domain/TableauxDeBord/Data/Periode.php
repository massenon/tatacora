<?php

declare(strict_types=1);

namespace App\Domain\TableauxDeBord\Data;

use Carbon\CarbonImmutable;
use InvalidArgumentException;

/**
 * Période d'analyse d'un tableau de bord — EF-M11-04.
 *
 * `SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §2 : Aujourd'hui / 7 derniers jours /
 * 30 derniers jours (défaut) / Ce trimestre / Cette année.
 *
 * ## Bornes semi-ouvertes, comme RG-01
 *
 * L'intervalle est `[debut, fin)` : `fin` est le premier instant **exclu**.
 * C'est la même convention que `VerificationChevauchementService`, et elle est
 * choisie pour la même raison — une borne incluse fait compter deux fois la
 * journée charnière entre deux périodes consécutives, ce qui rend faux tout
 * comparatif période courante / période précédente (EF-M11-03).
 *
 * ⚠ La convention vaut pour **les deux familles** de fabriques décrites plus
 * bas. Une seule classe, une seule convention : deux sémantiques de `fin`
 * dans le même objet feraient de `nombreJours()`, `precedente()` et
 * `libelle()` des méthodes dont le résultat dépendrait de qui a construit la
 * période — exactement le genre d'écart qu'aucun test ne montre.
 *
 * ## Deux familles de fabriques, et elles ne disent pas la même chose
 *
 * 1. **Fenêtres « à date »** — `depuisCode()` et les constantes `CODES`.
 *    Elles s'arrêtent TOUJOURS à la fin de la journée en cours : « ce
 *    trimestre » y signifie « du 1er juillet à ce soir », soit 47 jours au
 *    16 août. C'est le contrat de l'API `/api/v1/tableau-de-bord` et du
 *    moteur d'états (RG-19).
 * 2. **Fenêtres calendaires** — `aujourdhui()`, `semaine()`, `mois()`,
 *    `trimestre()`, `semestre()`, `annee()`, `personnalisee()`, groupées par
 *    `resoudre()`. Elles couvrent la période ENTIÈRE, passée ou à venir :
 *    « ce trimestre » y signifie « du 1er juillet au 30 septembre ». C'est ce
 *    dont la série mensuelle a besoin (`TableauDeBordService::serieMensuelle`,
 *    PA-121) — un mois tronqué à aujourd'hui ferait un dernier point de
 *    courbe systématiquement plus bas que les précédents, sans que rien ne le
 *    signale.
 *
 * `trimestre` et `annee` existent donc dans les deux familles avec des bornes
 * différentes. Ce n'est pas un doublon à réduire : ce sont deux questions
 * distinctes, et les confondre changerait les chiffres d'un écran livré.
 *
 * ## Immuable
 *
 * `CarbonImmutable` et non `Carbon` : un KPI qui appellerait `->addDay()` sur
 * la période décalerait silencieusement tous les KPI calculés après lui.
 */
final readonly class Periode
{
    // ------------------------------------------------ Fenêtres « à date »

    public const AUJOURD_HUI = 'aujourdhui';

    public const SEPT_JOURS = '7j';

    public const TRENTE_JOURS = '30j';

    public const TRIMESTRE = 'trimestre';

    public const ANNEE = 'annee';

    /** Défaut du prototype (§2). */
    public const DEFAUT = self::TRENTE_JOURS;

    public const CODES = [
        self::AUJOURD_HUI,
        self::SEPT_JOURS,
        self::TRENTE_JOURS,
        self::TRIMESTRE,
        self::ANNEE,
    ];

    // ------------------------------------------------ Fenêtres calendaires

    /**
     * Codes acceptés par `resoudre()`.
     *
     * Registre FERMÉ et exposé : un écran qui laisse choisir la période doit
     * pouvoir valider le code AVANT d'appeler `resoudre()`, qui refuse tout
     * code inconnu. Sans cette liste, chaque appelant recopierait la sienne.
     */
    public const CODES_CALENDAIRES = [
        'aujourdhui',
        'semaine',
        'mois',
        'trimestre',
        'semestre',
        'annee',
        'personnalisee',
    ];

    private function __construct(
        public string $code,
        public CarbonImmutable $debut,
        /** Premier instant EXCLU de la période. */
        public CarbonImmutable $fin,
    ) {
    }

    // ---------------------------------------------------------------------
    // Fenêtres « à date » — contrat de l'API M11 et du moteur d'états
    // ---------------------------------------------------------------------

    public static function depuisCode(string $code, ?CarbonImmutable $reference = null): self
    {
        $maintenant = $reference ?? CarbonImmutable::now();
        $finJournee = $maintenant->startOfDay()->addDay();

        return match ($code) {
            self::AUJOURD_HUI => new self($code, $maintenant->startOfDay(), $finJournee),
            self::SEPT_JOURS => new self($code, $finJournee->subDays(7), $finJournee),
            self::TRENTE_JOURS => new self($code, $finJournee->subDays(30), $finJournee),
            self::TRIMESTRE => new self($code, $maintenant->startOfQuarter(), $finJournee),
            self::ANNEE => new self($code, $maintenant->startOfYear(), $finJournee),
            default => throw new InvalidArgumentException(
                __('tableaux_de_bord.periode_inconnue', ['code' => $code]),
            ),
        };
    }

    // ---------------------------------------------------------------------
    // Fenêtres calendaires — séries et filtres d'écran
    // ---------------------------------------------------------------------

    /**
     * Le mois calendaire complet. `code` vaut `Y-m` : c'est l'étiquette d'un
     * point de série (`serieMensuelle`), et elle doit rester lisible telle
     * quelle sur un axe des temps.
     */
    public static function mois(?CarbonImmutable $reference = null): self
    {
        $debut = ($reference ?? CarbonImmutable::now())->startOfMonth();

        return new self($debut->format('Y-m'), $debut, $debut->addMonth());
    }

    public static function aujourdhui(?CarbonImmutable $reference = null): self
    {
        $debut = ($reference ?? CarbonImmutable::now())->startOfDay();

        return new self('aujourdhui', $debut, $debut->addDay());
    }

    public static function semaine(?CarbonImmutable $reference = null): self
    {
        $debut = ($reference ?? CarbonImmutable::now())->startOfWeek();

        return new self('semaine', $debut, $debut->addWeek());
    }

    public static function trimestre(?CarbonImmutable $reference = null): self
    {
        $debut = ($reference ?? CarbonImmutable::now())->startOfQuarter();

        return new self('trimestre', $debut, $debut->addMonths(3));
    }

    public static function semestre(?CarbonImmutable $reference = null): self
    {
        $date = $reference ?? CarbonImmutable::now();
        $debut = $date->month <= 6
            ? $date->startOfYear()
            : $date->startOfYear()->addMonths(6);

        return new self('semestre', $debut, $debut->addMonths(6));
    }

    public static function annee(?CarbonImmutable $reference = null): self
    {
        $debut = ($reference ?? CarbonImmutable::now())->startOfYear();

        return new self('annee', $debut, $debut->addYear());
    }

    /**
     * Intervalle saisi à la main, bornes INCLUSES côté saisie.
     *
     * L'utilisateur qui écrit « du 1er au 31 » attend le 31 entier : la borne
     * haute est donc portée au lendemain minuit pour rester dans la
     * convention `[debut, fin)` de la classe. Sans ce décalage, une vente de
     * 23 h le dernier jour tomberait hors de l'export de ce même jour.
     */
    public static function personnalisee(string $debut, string $fin): self
    {
        return new self(
            'personnalisee',
            CarbonImmutable::parse($debut)->startOfDay(),
            CarbonImmutable::parse($fin)->startOfDay()->addDay(),
        );
    }

    /**
     * Résout un code calendaire — **refuse** tout code inconnu.
     *
     * ⚠ Aucun repli sur le mois courant : un repli silencieux ferait afficher
     * les chiffres du mois sous le libellé d'une période demandée pour tout
     * autre chose, et personne ne verrait jamais que la demande n'a pas été
     * comprise. Validez le code contre `CODES_CALENDAIRES` avant d'appeler.
     *
     * Seule exception, et elle ne ment pas : `personnalisee` sans ses deux
     * dates n'est pas une période inconnue mais une période **pas encore
     * saisie**. On rend le mois courant, dont `libelle()` imprime les dates
     * réelles — l'écran affiche donc exactement ce qu'il calcule.
     */
    public static function resoudre(string $cle, ?string $du = null, ?string $au = null): self
    {
        return match ($cle) {
            'aujourdhui' => self::aujourdhui(),
            'semaine' => self::semaine(),
            'mois' => self::mois(),
            'trimestre' => self::trimestre(),
            'semestre' => self::semestre(),
            'annee' => self::annee(),
            'personnalisee' => ($du !== null && $du !== '' && $au !== null && $au !== '')
                ? self::personnalisee($du, $au)
                : self::mois(),
            default => throw new InvalidArgumentException(
                __('tableaux_de_bord.periode_calendaire_inconnue', ['code' => $cle]),
            ),
        };
    }

    // ---------------------------------------------------------------------

    /**
     * Période immédiatement antérieure, de **même durée** — EF-M11-03.
     *
     * Calculée par décalage plutôt que par un second appel à `depuisCode()` :
     * « les 30 derniers jours d'il y a 30 jours » n'a pas d'expression en code
     * de période, et « ce trimestre » précédent n'a pas la même durée que le
     * courant. Le décalage garde deux fenêtres strictement comparables, ce qui
     * est la condition pour qu'une variation en pourcentage veuille dire
     * quelque chose.
     */
    public function precedente(): self
    {
        $duree = (int) $this->debut->diffInSeconds($this->fin);

        return new self(
            $this->code,
            $this->debut->subSeconds($duree),
            $this->debut,
        );
    }

    /**
     * Nombre de jours entiers couverts — base du calcul de nuitées.
     */
    public function nombreJours(): int
    {
        return (int) $this->debut->diffInDays($this->fin);
    }

    /**
     * Libellé imprimable en tête d'un état (RG-19).
     */
    public function libelle(): string
    {
        return __('tableaux_de_bord.periode.du_au', [
            'debut' => $this->debut->format('d/m/Y'),
            // On affiche le dernier jour INCLUS : « du 1er au 30 » se comprend,
            // « du 1er au 31 exclu » ne se dit pas sur un document.
            'fin' => $this->fin->subDay()->format('d/m/Y'),
        ]);
    }
}
