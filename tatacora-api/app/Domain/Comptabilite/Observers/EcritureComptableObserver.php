<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Observers;

use App\Domain\Comptabilite\Exceptions\EcritureImmuableException;
use App\Domain\Comptabilite\Models\EcritureComptable;
use Illuminate\Support\Facades\DB;

/**
 * Immutabilité des écritures comptables validées — RG-11.
 *
 * > « Toute écriture comptable validée est immuable ; toute correction
 * > s'effectue exclusivement par écriture de contre-passation, garantissant la
 * > traçabilité SYSCOHADA. »
 *
 * ## Pourquoi un Observer et pas un contrôle dans le service
 *
 * Même raison que `FactureObserver` (RG-03) : l'Observer couvre **tous** les
 * chemins d'écriture — un `update()` appelé depuis un futur service de
 * lettrage, un job de clôture, la file de synchronisation, une commande
 * artisan. Un contrôle placé dans un service ne protégerait que les appelants
 * qui pensent à passer par lui.
 *
 * Toute anomalie touchant une table financière est classée **Bloquante** par
 * le projet, quelle que soit sa gravité perçue : c'est le niveau de garantie
 * attendu ici.
 *
 * ## Deux verrous distincts
 *
 * 1. **Statut** — une écriture `validee` ne se modifie ni ne se supprime.
 * 2. **Exercice clos** — aucune écriture, même en brouillon, ne s'ajoute à un
 *    exercice `cloture`. Sans ce second verrou, un exercice signé pourrait
 *    encore bouger, et les états déjà édités ne correspondraient plus à la
 *    base.
 */
class EcritureComptableObserver
{
    /** Statuts d'exercice interdisant toute écriture nouvelle. */
    private const EXERCICES_FERMES = ['cloture'];

    public function creating(EcritureComptable $ecriture): void
    {
        $this->refuserSiExerciceClos($ecriture);
    }

    public function updating(EcritureComptable $ecriture): void
    {
        // L'état AVANT modification : une écriture qui passe de `brouillon` à
        // `validee` dans cette même écriture n'était pas encore validée, la
        // mise à jour est donc légitime.
        if ($ecriture->getOriginal('statut') !== 'validee') {
            $this->refuserSiExerciceClos($ecriture);

            return;
        }

        $champsModifies = array_values(array_diff(
            array_keys($ecriture->getDirty()),
            // Colonnes d'audit renseignées par le framework, jamais par un
            // utilisateur : les bloquer empêcherait toute traçabilité.
            ['updated_at', 'date_modification', 'utilisateur_modification_id'],
        ));

        if ($champsModifies !== []) {
            throw new EcritureImmuableException($ecriture->id, $champsModifies);
        }
    }

    /**
     * Une écriture ne se supprime jamais — validée ou non.
     *
     * Même en brouillon : `03_DATABASE_ENGINEERING.md` §15 interdit toute
     * suppression physique sur une table transactionnelle, et un trou dans la
     * séquence des écritures est précisément ce qu'un contrôle fiscal
     * recherche.
     */
    public function deleting(EcritureComptable $ecriture): void
    {
        throw new EcritureImmuableException(
            $ecriture->id,
            ['suppression'],
            __('comptabilite.ecriture_suppression_interdite'),
        );
    }

    /**
     * Aucune écriture sur un exercice clos.
     *
     * Requête directe plutôt que relation Eloquent : l'Observer tourne sur le
     * chemin d'écriture le plus chaud du système, et charger un modèle complet
     * pour lire une seule colonne se paierait sur chaque ligne d'un import.
     */
    private function refuserSiExerciceClos(EcritureComptable $ecriture): void
    {
        $statut = DB::table('exercices_comptables')
            ->where('id', $ecriture->exercice_id)
            ->value('statut');

        if (in_array($statut, self::EXERCICES_FERMES, true)) {
            throw new EcritureImmuableException(
                $ecriture->id ?? '',
                ['exercice_id'],
                __('comptabilite.exercice_clos'),
            );
        }
    }
}
