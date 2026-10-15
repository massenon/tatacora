<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Shared\Sync\Contracts\GestionnaireSynchronisation;
use App\Shared\Sync\Gestionnaires\GestionnaireClients;
use App\Shared\Sync\Gestionnaires\GestionnaireFournisseurs;
use App\Shared\Sync\Gestionnaires\GestionnaireReservations;
use LogicException;

/**
 * Registre FERMÉ des tables synchronisables — l'UNIQUE endroit où une table
 * devient synchronisable, en nommant son gestionnaire.
 *
 * ## Pourquoi un registre de gestionnaires (15/10/2026)
 *
 * Le registre précédent (`SynchronisationService::TABLES_SYNCHRONISABLES`,
 * table → module + service ou `null`) admettait « `null` = écriture directe ».
 * C'était la porte : toute table sans service recevait le payload brut, et
 * toute `modification` — même sur `reservations` — passait par un `UPDATE`
 * brut. La décision du Product Owner du 15/10/2026 étend la synchronisation
 * aux fournisseurs, aux commandes d'achat puis aux ventes : élargir le
 * registre sans fermer la porte aurait multiplié les contournements.
 *
 * Désormais chaque entrée nomme une classe qui implémente
 * `GestionnaireSynchronisation` : module, niveau, service et refus explicite
 * des modifications sont DÉCLARÉS, et il n'existe plus de chemin d'écriture
 * en dehors d'eux. Le nom `TABLES_SYNCHRONISABLES` est conservé : une
 * vingtaine de docblocks du dépôt s'y réfèrent (« X n'est pas au registre
 * `TABLES_SYNCHRONISABLES` »), et leur sens est inchangé.
 *
 * Toute table absente est refusée explicitement : accepter une écriture sur
 * une table inconnue reviendrait à contourner les règles de son domaine.
 */
class RegistreSynchronisation
{
    /**
     * @var array<string, class-string<GestionnaireSynchronisation>>
     */
    public const TABLES_SYNCHRONISABLES = [
        'reservations' => GestionnaireReservations::class,
        'clients' => GestionnaireClients::class,
        'fournisseurs' => GestionnaireFournisseurs::class,
    ];

    /** @var array<string, GestionnaireSynchronisation> */
    private array $instances = [];

    public function estSynchronisable(string $table): bool
    {
        return array_key_exists($table, self::TABLES_SYNCHRONISABLES);
    }

    /**
     * @throws LogicException table hors registre — le moteur vérifie avant
     */
    public function pour(string $table): GestionnaireSynchronisation
    {
        if (! $this->estSynchronisable($table)) {
            throw new LogicException(__('sync.interne.hors_registre', ['table' => $table]));
        }

        if (! isset($this->instances[$table])) {
            $gestionnaire = app(self::TABLES_SYNCHRONISABLES[$table]);

            // La clé du registre et la table déclarée par le gestionnaire ne
            // peuvent pas diverger : un gestionnaire branché sous le mauvais nom
            // écrirait dans une table avec le RBAC d'une autre.
            if ($gestionnaire->table() !== $table) {
                throw new LogicException(__('sync.interne.table_incoherente', [
                    'gestionnaire' => $gestionnaire::class,
                    'declaree' => $gestionnaire->table(),
                    'cle' => $table,
                ]));
            }

            $this->instances[$table] = $gestionnaire;
        }

        return $this->instances[$table];
    }

    /**
     * @return array<string, GestionnaireSynchronisation>
     */
    public function tous(): array
    {
        $tous = [];

        foreach (array_keys(self::TABLES_SYNCHRONISABLES) as $table) {
            $tous[$table] = $this->pour($table);
        }

        return $tous;
    }
}
