<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use App\Shared\Sync\Models\JournalEnvoiSynchronisation;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/**
 * Le journal d'ENVOI : ce que le serveur met à disposition de chaque poste par
 * `GET /api/v1/referentiels` — demande du PO du 26/10/2026.
 *
 * ## Ce que le contrat permet, et ce qu'il ne permet pas
 *
 * Le curseur du flux est conservé PAR LE POSTE (opaque, rendu à chaque page) :
 * le serveur n'en garde pas. Ce journal retient donc ce qu'il a RENDU (dernier
 * curseur, complet ou non) et ce qu'il a livré, table par table. « Redescendre
 * depuis le début » ne peut pas effacer un curseur qui n'est pas ici : il pose
 * une DEMANDE, que `ReferentielsController` consomme au prochain passage du
 * poste en ignorant le curseur qu'il présente — le poste repart du début sans
 * rien changer à son code, et le flux reste identique pour lui.
 *
 * Les écritures de ce journal ne font jamais échouer un téléchargement : une
 * erreur est signalée (`report`) et le flux continue.
 */
class JournalEnvoiService
{
    /**
     * Une page du flux vient d'être rendue à ce poste.
     *
     * @param  array<string, int>  $livres  table → éléments livrés dans la page
     * @param  list<string>  $nonLisibles  tables non livrées faute de droit
     */
    public function noterPage(string $posteId, User $utilisateur, array $livres, array $nonLisibles, string $curseur, bool $complet, CatalogueDescendantService $catalogue): void
    {
        try {
            DB::transaction(function () use ($posteId, $utilisateur, $livres, $nonLisibles, $curseur, $complet, $catalogue): void {
                $maintenant = now();

                foreach ($livres as $table => $nombre) {
                    $ligne = JournalEnvoiSynchronisation::query()->firstOrNew(['poste_id' => $posteId, 'table_concernee' => $table]);
                    $ligne->livres_total = (int) $ligne->livres_total + $nombre;
                    $ligne->dernier_passage_nb = $nombre;
                    $ligne->derniere_livraison_le = $maintenant;
                    $ligne->save();
                }

                // Les tables non livrées : combien d'éléments existent sans
                // être livrés. Recalculé à chaque passage — un droit accordé
                // depuis remet le compte à zéro.
                $anciennes = JournalEnvoiSynchronisation::query()
                    ->where('poste_id', $posteId)->where('en_attente_droits', '>', 0)->pluck('table_concernee')->all();
                $manquantes = $nonLisibles === [] ? [] : $catalogue->nonLivrees($utilisateur);

                foreach ($manquantes as $table => $nombre) {
                    $ligne = JournalEnvoiSynchronisation::query()->firstOrNew(['poste_id' => $posteId, 'table_concernee' => $table]);
                    $ligne->en_attente_droits = $nombre;
                    $ligne->droits_constates_le = $maintenant;
                    $ligne->save();
                }

                $levees = array_diff($anciennes, array_keys($manquantes));

                if ($levees !== []) {
                    JournalEnvoiSynchronisation::query()
                        ->where('poste_id', $posteId)->whereIn('table_concernee', $levees)
                        ->update(['en_attente_droits' => 0]);
                }

                EtatPosteSynchronisation::query()->updateOrCreate(['poste_id' => $posteId], [
                    'utilisateur_id' => $utilisateur->id,
                    'curseur_descente' => $curseur,
                    'descente_complete' => $complet,
                    ...($complet ? ['descente_complete_le' => $maintenant] : []),
                ]);
            });
        } catch (Throwable $e) {
            report($e);
        }
    }

    /** Le poste a présenté des données d'avant une réinitialisation : refus 409. */
    public function noterGenerationPerimee(?string $posteId): void
    {
        if ($posteId === null || $posteId === '') {
            return;
        }

        try {
            $etat = EtatPosteSynchronisation::query()->firstOrNew(['poste_id' => $posteId]);
            $etat->generation_perimee_le = now();
            $etat->generation_perimee_nb = (int) $etat->generation_perimee_nb + 1;
            $etat->save();
        } catch (Throwable $e) {
            report($e);
        }
    }

    /**
     * Demande à ce poste de repartir du début. Un poste déjà en attente de
     * redescente n'en reçoit pas une seconde.
     *
     * @return bool `false` si une redescente était déjà demandée
     */
    public function demanderRedescente(string $posteId, User $auteur): bool
    {
        if (! $auteur->estAdministrateur()) {
            throw new RuntimeException(__('synchronisation_journal.ecran.refus_admin'));
        }

        $connu = EtatPosteSynchronisation::query()->where('poste_id', $posteId)->exists()
            || DB::table('sessions_synchronisation')->where('poste_id', $posteId)->exists()
            || DB::table('personal_access_tokens')->where('name', $posteId)->exists();

        if (! $connu) {
            throw new RuntimeException(__('synchronisation_journal.ecran.poste_inconnu'));
        }

        return DB::transaction(function () use ($posteId, $auteur): bool {
            $etat = EtatPosteSynchronisation::query()->firstOrNew(['poste_id' => $posteId]);

            if ($etat->redescente_demandee_le !== null) {
                return false;
            }

            $etat->redescente_demandee_le = now();
            $etat->redescente_demandee_par = $auteur->id;
            $etat->save();

            JournalAudit::create([
                'id' => (string) Str::uuid(),
                'utilisateur_id' => $auteur->id,
                'action' => 'redescente_demandee',
                'entite_concernee' => 'etats_postes_synchronisation',
                'entite_id' => (string) $etat->id,
                'valeur_avant' => null,
                'valeur_apres' => ['poste' => $posteId],
                'adresse_poste' => request()->ip(),
            ]);

            return true;
        });
    }

    /**
     * Une redescente est-elle demandée pour ce poste ? Si oui, elle est
     * CONSOMMÉE : le curseur que le poste présente doit être ignoré.
     */
    public function consommerRedescente(string $posteId): bool
    {
        try {
            $etat = EtatPosteSynchronisation::query()->where('poste_id', $posteId)->first();

            if ($etat === null || $etat->redescente_demandee_le === null) {
                return false;
            }

            $etat->update(['redescente_demandee_le' => null, 'redescente_faite_le' => now()]);

            return true;
        } catch (Throwable $e) {
            report($e);

            return false;
        }
    }

    /**
     * Un résumé par poste, pour l'onglet « Envoi ».
     *
     * @return list<array{poste_id: string, utilisateur: ?string, derniere_descente: ?\Illuminate\Support\Carbon, complete: bool, a_un_curseur: bool, livres: int, non_livres_droits: int, generation_perimee_le: ?\Illuminate\Support\Carbon, generation_perimee_nb: int, redescente_demandee_le: ?\Illuminate\Support\Carbon, redescente_faite_le: ?\Illuminate\Support\Carbon}>
     */
    public function resume(): array
    {
        $livres = JournalEnvoiSynchronisation::query()
            ->select('poste_id', DB::raw('SUM(livres_total) AS livres'), DB::raw('SUM(en_attente_droits) AS droits'))
            ->groupBy('poste_id')
            ->get()
            ->keyBy('poste_id');
        $comptes = DB::table('utilisateurs')->pluck('login', 'id')->all();
        $lignes = [];

        foreach (EtatPosteSynchronisation::query()->orderBy('poste_id')->get() as $etat) {
            $total = $livres->get($etat->poste_id);
            $lignes[] = [
                'poste_id' => $etat->poste_id,
                'utilisateur' => $etat->utilisateur_id !== null ? ($comptes[$etat->utilisateur_id] ?? null) : null,
                'derniere_descente' => $etat->derniere_descente_le,
                'complete' => (bool) $etat->descente_complete,
                'a_un_curseur' => $etat->curseur_descente !== null,
                'livres' => (int) ($total->livres ?? 0),
                'non_livres_droits' => (int) ($total->droits ?? 0),
                'generation_perimee_le' => $etat->generation_perimee_le,
                'generation_perimee_nb' => (int) $etat->generation_perimee_nb,
                'redescente_demandee_le' => $etat->redescente_demandee_le,
                'redescente_faite_le' => $etat->redescente_faite_le,
            ];
        }

        return $lignes;
    }

    /**
     * Le détail d'un poste : par table, ce qui a été livré, la dernière
     * livraison, ce qui reste à livrer, ce qui n'est pas livré faute de droit.
     *
     * @return array{poste_id: string, curseur: ?string, tables: list<array{table: string, livres: int, derniere: ?\Illuminate\Support\Carbon, restants: int, droits: int}>}
     */
    public function detail(string $posteId, CatalogueDescendantService $catalogue): array
    {
        $etat = EtatPosteSynchronisation::query()->where('poste_id', $posteId)->first();
        $lignes = JournalEnvoiSynchronisation::query()->where('poste_id', $posteId)->get()->keyBy('table_concernee');
        $compte = $etat?->utilisateur_id !== null ? User::query()->find($etat->utilisateur_id) : null;
        $restants = $compte instanceof User ? $catalogue->restants($compte, $posteId, $etat?->curseur_descente) : [];
        $tables = [];

        foreach (array_unique([...array_keys($restants), ...$lignes->keys()->all()]) as $table) {
            $ligne = $lignes->get($table);
            $tables[] = [
                'table' => (string) $table,
                'livres' => (int) ($ligne->livres_total ?? 0),
                'derniere' => $ligne?->derniere_livraison_le,
                'restants' => (int) ($restants[$table] ?? 0),
                'droits' => (int) ($ligne->en_attente_droits ?? 0),
            ];
        }

        usort($tables, static fn (array $a, array $b): int => [$b['restants'] + $b['droits'], $a['table']] <=> [$a['restants'] + $a['droits'], $b['table']]);

        return ['poste_id' => $posteId, 'curseur' => $etat?->curseur_descente, 'tables' => $tables];
    }
}
