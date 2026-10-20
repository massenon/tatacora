<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Ouverture et clôture d'exercice — commande du Product Owner (Vague E,
 * 01/09/2026), pour les deux boutons de l'onglet « Clôtures » du hub SYSCOHADA
 * qui n'avaient, jusqu'ici, aucun Service à appeler.
 *
 * ## Périmètre DÉLIBÉRÉMENT minimal — ce que ce service NE fait PAS
 *
 * `EtatClotureService` documente une clôture COMPLÈTE en trois opérations :
 * solder les comptes de gestion (6, 7, 8) par le compte 13, verrouiller
 * l'exercice, puis rouvrir le suivant par une écriture d'à-nouveaux au
 * journal AN qui reprend les seuls comptes de bilan. Le Product Owner a
 * explicitement borné ce lot à MOINS que cela :
 *
 *  - **ouvrir** un exercice = créer la ligne `exercices_comptables`, rien
 *    d'autre — aucune écriture d'à-nouveaux, aucune reprise de solde ;
 *  - **clôturer** un exercice = changer son statut, REFUSÉ si des écritures
 *    en brouillon subsistent — aucun solde des comptes de gestion, aucune
 *    écriture de résultat vers le compte 131/139.
 *
 * C'est un choix de PÉRIMÈTRE assumé, pas un oubli : router la clôture
 * comptable complète depuis ce lot aurait exigé de vérifier au plan
 * comptable les comptes 131/139 et le journal AN — exactement ce que
 * `EtatClotureService::BLOCAGE_JOURNAL_AN_ABSENT` et
 * `BLOCAGE_COMPTES_RESULTAT_ABSENTS` existent pour détecter, et que ce
 * service ne fait PAS ici. La clôture comptable complète reste à faire, sous
 * l'arbitrage du Comptable — voir `EtatClotureService` pour l'état détaillé
 * des six étapes.
 *
 * ## « Résultat reporté » reste un calcul, jamais une colonne écrite ici
 *
 * `exercices_comptables` ne porte toujours aucune colonne de ce nom (PA-151).
 * L'écran continue de le CALCULER via `EtatClotureService::resultatAReporter`
 * pour l'exercice consulté — cette classe n'écrit jamais ce chiffre nulle
 * part.
 */
class ExerciceComptableService
{
    /**
     * Ouvre un nouvel exercice — l'année entière, du 1er janvier au 31
     * décembre.
     *
     * @throws RuntimeException année déjà ouverte, ou hors de portée raisonnable
     */
    public function ouvrir(int $annee): ExerciceComptable
    {
        if ($annee < 2000 || $annee > 2100) {
            // Bornes larges mais réelles : un exercice n'est pas une donnée
            // arbitraire, une année à quatre chiffres saisie de travers
            // (« 226 », « 20266 ») ne doit pas produire une ligne silencieuse.
            throw new RuntimeException(__('comptabilite.exercice_annee_invalide'));
        }

        if (ExerciceComptable::query()->where('annee', $annee)->exists()) {
            throw new RuntimeException(__('comptabilite.exercice_deja_existant', ['annee' => (string) $annee]));
        }

        return DB::transaction(fn (): ExerciceComptable => ExerciceComptable::create([
            'annee' => $annee,
            'date_debut' => sprintf('%d-01-01', $annee),
            'date_fin' => sprintf('%d-12-31', $annee),
            'statut' => 'ouvert',
        ]));
    }

    /**
     * L'exercice de [annee], OUVERT S'IL MANQUE — lot 1 du passage d'année
     * (décision du Product Owner du 20/10/2026 : « quand on bascule à
     * N+1, toutes les données des modules sont enregistrées »).
     *
     * Sans lui, le 1er janvier, toute vente, dépense, encaissement, acompte
     * ou règlement était refusé (« aucun exercice ne couvre la date ») tant
     * qu'un Administrateur n'avait pas ouvert l'année à la main — et les
     * ventes des postes tombaient « À traiter ».
     *
     * Idempotent et sûr en concurrence : deux premières ventes de l'année
     * simultanées n'ouvrent qu'UN exercice (`annee` unique, `insertOrIgnore`,
     * relecture verrouillée qui voit la ligne de l'autre transaction).
     * N'ouvre jamais qu'un exercice MANQUANT : un exercice clôturé reste
     * clôturé. Tracé au journal d'audit quand il crée.
     */
    public function assurer(int $annee, string $motif): ExerciceComptable
    {
        if ($annee < 2000 || $annee > 2100) {
            throw new RuntimeException(__('comptabilite.exercice_annee_invalide'));
        }

        $existant = ExerciceComptable::query()->where('annee', $annee)->first();

        if ($existant !== null) {
            return $existant;
        }

        $id = (string) Str::uuid();
        $cree = DB::table('exercices_comptables')->insertOrIgnore([
            'id' => $id,
            'annee' => $annee,
            'date_debut' => sprintf('%d-01-01', $annee),
            'date_fin' => sprintf('%d-12-31', $annee),
            'statut' => 'ouvert',
            'created_at' => now(),
            'updated_at' => now(),
        ]) === 1;

        if ($cree) {
            JournalAudit::create([
                'id' => (string) Str::uuid(),
                'utilisateur_id' => auth()->id(),
                'action' => 'exercice_ouvert_automatiquement',
                'entite_concernee' => 'exercices_comptables',
                'entite_id' => $id,
                'valeur_avant' => null,
                'valeur_apres' => ['annee' => $annee, 'motif' => $motif],
                'adresse_poste' => request()->ip(),
            ]);
        }

        return ExerciceComptable::query()->where('annee', $annee)->lockForUpdate()->firstOrFail();
    }

    /**
     * L'année d'une pièce qui peut ouvrir son exercice D'ELLE-MÊME : l'année
     * en cours, et la suivante en décembre seulement (une date mal saisie,
     * « 2062 », ne crée pas un exercice ; une année passée manquante non
     * plus — elle se crée à la main, en connaissance de cause).
     */
    public static function ouvertureAutomatiquePermise(int $annee): bool
    {
        $maintenant = now();

        return $annee === $maintenant->year
            || ($annee === $maintenant->year + 1 && $maintenant->month === 12);
    }

    /**
     * Clôture un exercice — REFUSE tant qu'une écriture y reste en brouillon.
     *
     * Le refus est délibéré et n'a pas de contournement automatique : une
     * pièce en brouillon n'est pas opposable (RG-11), et la clôturer quand
     * même verrouillerait l'exercice sur un état que personne n'a validé —
     * elle resterait alors invisible à toute lecture, qui filtre
     * `statut = 'validee'` (voir `EcritureComptableService::soldeCompte()`).
     *
     * @throws RuntimeException exercice déjà clôturé, ou brouillons restants
     */
    public function cloturer(ExerciceComptable $exercice, User $utilisateur): ExerciceComptable
    {
        if ($exercice->statut === 'cloture') {
            throw new RuntimeException(__('comptabilite.exercice_deja_cloture', ['annee' => (string) $exercice->annee]));
        }

        $brouillons = EcritureComptable::query()
            ->where('exercice_id', $exercice->id)
            ->where('statut', 'brouillon')
            ->count();

        if ($brouillons > 0) {
            throw new RuntimeException(__('comptabilite.cloture_brouillons_restants', [
                'nombre' => (string) $brouillons,
                'annee' => (string) $exercice->annee,
            ]));
        }

        return DB::transaction(function () use ($exercice, $utilisateur): ExerciceComptable {
            $exercice->update([
                'statut' => 'cloture',
                'date_cloture' => now(),
                'utilisateur_cloture_id' => $utilisateur->id,
            ]);

            return $exercice->refresh();
        });
    }
}
