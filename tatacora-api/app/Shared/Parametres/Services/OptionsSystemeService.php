<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use App\Shared\Backup\Services\ReinitialisationDonneesTestService;

/**
 * Les bascules d'activation du maître (`prototype_v2/assets/js/options-systeme.js`,
 * `OptionsSysteme`) — portées comme clés serveur le 02/09/2026 (directive
 * Product Owner), lues ICI et nulle part ailleurs.
 *
 * ## Trois bascules sur six, et la différence est nommée
 *
 * Le maître déclare six options. Trois ont un consommateur réel côté serveur
 * et sont donc portées :
 *
 * - `activation_suppression` — lue par l'archivage du parc d'hébergement
 *   (`App\Pwa\Livewire\Hebergement\Hebergement`), le seul geste « supprimer =
 *   archiver » que la PWA expose. Fermée par défaut, comme au maître : sur un
 *   ERP d'exploitation, l'action destructrice n'est pas à portée de clic tant
 *   qu'un Administrateur ne l'a pas ouverte.
 * - `reinitialisation_seeders` — lue par
 *   {@see \App\Shared\Backup\Services\ReinitialisationDonneesTestService}
 *   (`estOuverte()`, revérifiée par `executer()` au moment d'agir) : l'onglet
 *   « Seeders » d'Import & Export l'exige EN PLUS du refus d'environnement
 *   (les deux s'appliquent, la plus restrictive gagne). La clé est la
 *   constante du lecteur, `CLE_BASCULE` — refonte Import & Export du
 *   02/09/2026, agent parallèle.
 * - `activation_alertes_ouverture` — lue par
 *   {@see \App\Pwa\Support\AlertesOuverture} : fermée, la cloche ne dérive
 *   plus aucune alerte d'ouverture. Ouverte par défaut, comme au maître.
 *
 * Les trois autres (`duplication`, `suppression_groupee`,
 * `sauvegarde_hebdomadaire`) ne sont PAS portées, et la raison est datée dans
 * la vue de l'écran Paramètres : aucun consommateur n'existe côté serveur
 * (aucun geste « Dupliquer », aucune sélection multiple, et la sauvegarde
 * réelle est QUOTIDIENNE — `SauvegardeBaseQuotidienneJob`, plus forte que la
 * promesse hebdomadaire du maître). Une bascule que rien ne lit est
 * l'indicateur qui affirme un état qu'il n'a pas vérifié (PA-59/60/61).
 *
 * ## Le défaut vit ICI, pas chez les lecteurs
 *
 * Une clé absente de `parametres_systeme` vaut son DÉFAUT du maître, pas
 * `false` : `activation_alertes_ouverture` naît ouverte. Chaque lecteur qui
 * réimplémenterait « absent = faux » éteindrait les alertes de tout poste
 * jamais paramétré. `actif()` est donc l'unique formule, et l'écran Paramètres
 * affiche l'état EFFECTIF par elle — jamais un tiret qui laisserait croire la
 * bascule sans état.
 *
 * @see RG-10 paramétrage sans déploiement
 * @see RG-15 traçabilité — chaque bascule passe par `EnregistrerParametreService`,
 *      dont l'écriture est journalisée (trait Auditable de `ParametreSysteme`)
 */
class OptionsSystemeService
{
    public const CLE_SUPPRESSION = 'activation_suppression';

    /**
     * ⚠ La clé est CELLE du lecteur (`ReinitialisationDonneesTestService::CLE_BASCULE`,
     * refonte Import & Export du 02/09/2026), jamais réécrite en littéral :
     * son `estOuverte()` lit la même clé avec le même défaut fermé —
     * `actif()` ci-dessous sert l'AFFICHAGE de l'écran Paramètres, `executer()`
     * du service revérifie par sa propre lecture au moment d'agir.
     */
    public const CLE_REINITIALISATION_SEEDERS = ReinitialisationDonneesTestService::CLE_BASCULE;

    public const CLE_ALERTES_OUVERTURE = 'activation_alertes_ouverture';

    /**
     * Les défauts du maître (`options-systeme.js`, `DEFAUTS`) — pour les
     * seules bascules portées.
     *
     * @var array<string, bool>
     */
    public const DEFAUTS = [
        self::CLE_SUPPRESSION => false,
        self::CLE_REINITIALISATION_SEEDERS => false,
        self::CLE_ALERTES_OUVERTURE => true,
    ];

    public function __construct(
        private readonly ParametreSystemeService $lecture,
    ) {
    }

    /**
     * L'état EFFECTIF d'une bascule : la valeur stockée, ou le défaut du
     * maître quand rien n'est stocké. Une clé hors registre rend faux,
     * jamais vrai — même règle que `OptionsSysteme.actif()` au maître.
     */
    public function actif(string $cle): bool
    {
        if (! array_key_exists($cle, self::DEFAUTS)) {
            return false;
        }

        $valeur = $this->lecture->get($cle);

        if (blank($valeur)) {
            return self::DEFAUTS[$cle];
        }

        return filter_var($valeur, FILTER_VALIDATE_BOOLEAN);
    }

    public function suppressionActive(): bool
    {
        return $this->actif(self::CLE_SUPPRESSION);
    }

    // Pas de `reinitialisationSeedersActive()` : le consommateur de cette
    // bascule est `ReinitialisationDonneesTestService::estOuverte()` — un
    // alias ici serait une seconde lecture du même fait, qui finirait par
    // diverger de la première (défaut du référentiel à double auteur).

    public function alertesOuvertureActives(): bool
    {
        return $this->actif(self::CLE_ALERTES_OUVERTURE);
    }
}
