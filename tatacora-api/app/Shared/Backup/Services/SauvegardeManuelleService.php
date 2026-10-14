<?php

declare(strict_types=1);

namespace App\Shared\Backup\Services;

use App\Shared\Backup\Jobs\SauvegardeBaseQuotidienneJob;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * « Sauvegardes de la base » — `import-export.html`, onglet 2.
 *
 * ## Réutilise le Job, ne le duplique JAMAIS
 *
 * `genererMaintenant()` appelle `SauvegardeBaseQuotidienneJob::handle()` —
 * LA MÊME méthode que la tâche planifiée de 02h00 (`routes/console.php`).
 * Un second `mysqldump` écrit ici à la main aurait fini par diverger du
 * premier (rétention, gestion du fichier incomplet — PA-60), exactement le
 * défaut qu'Article 10 nomme.
 *
 * ## `cheminSiExiste()` est le SEUL point qui résout un nom en chemin
 *
 * Il n'accepte QUE le motif exact produit par le Job
 * (`tatacora-AAAA-MM-JJ_HHMMSS.sql`) : un nom construit par navigation de
 * répertoire (`../../.env`) ne matche jamais ce motif et rend `null`. C'est
 * ce qui rend un téléchargement de fichier arbitraire impossible depuis un
 * simple paramètre de requête.
 */
class SauvegardeManuelleService
{
    private const MOTIF_NOM = '/^tatacora-\d{4}-\d{2}-\d{2}_\d{6}\.sql$/';

    /** Fichier témoin posé à côté d'un dump téléchargé — voir `marquerTelechargee()`. */
    private const SUFFIXE_TELECHARGEE = '.telechargee';

    public function __construct(private readonly SauvegardeBaseQuotidienneJob $job)
    {
    }

    /**
     * @return array{fichier: string, octets: int, purgees: int}
     */
    public function genererMaintenant(): array
    {
        return $this->job->handle();
    }

    /**
     * @return list<array{nom: string, taille: int, date: Carbon, telechargee: bool}>
     */
    public function fichiers(): array
    {
        $repertoire = storage_path('app/sauvegardes');

        if (! is_dir($repertoire)) {
            return [];
        }

        $fichiers = [];
        foreach (glob($repertoire . '/tatacora-*.sql') ?: [] as $chemin) {
            $fichiers[] = [
                'nom' => basename($chemin),
                'taille' => (int) filesize($chemin),
                'date' => Carbon::createFromTimestamp((int) filemtime($chemin)),
                'telechargee' => is_file($chemin . self::SUFFIXE_TELECHARGEE),
            ];
        }

        usort($fichiers, static fn (array $a, array $b): int => $b['date']->timestamp <=> $a['date']->timestamp);

        $this->purgerMarqueursOrphelins($repertoire);

        return $fichiers;
    }

    /**
     * Marque une sauvegarde comme TÉLÉCHARGÉE — un fichier témoin à côté du
     * dump, jamais une table : le marqueur suit le fichier, il disparaît avec
     * lui à la purge de rétention.
     *
     * C'est ce qui porte le rappel du maître (« Sauvegarde en attente de
     * téléchargement ») : « une sauvegarde restée sur la machine ne protège
     * de rien, c'est le téléchargement qui la met à l'abri »
     * (`import-export.html` l.204-207).
     */
    public function marquerTelechargee(string $nom): void
    {
        $chemin = $this->cheminSiExiste($nom);

        if ($chemin !== null) {
            @file_put_contents($chemin . self::SUFFIXE_TELECHARGEE, now()->toIso8601String());
        }
    }

    /**
     * Retire une sauvegarde de la liste — suppression RÉELLE du fichier.
     *
     * La confirmation « jamais téléchargée » appartient à l'écran ; ici, seul
     * le motif de nom protège (même garde que `cheminSiExiste()`).
     */
    public function supprimer(string $nom): bool
    {
        $chemin = $this->cheminSiExiste($nom);

        if ($chemin === null) {
            return false;
        }

        @unlink($chemin . self::SUFFIXE_TELECHARGEE);

        return unlink($chemin);
    }

    /**
     * KPI « Tables en base » du maître — compté sur la base RÉELLE, jamais
     * recopié d'un document (la règle « l'état se MESURE » du dépôt).
     */
    public function nombreTables(): int
    {
        $ligne = DB::selectOne(
            'SELECT COUNT(*) AS total FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()',
        );

        return (int) ($ligne->total ?? 0);
    }

    private function purgerMarqueursOrphelins(string $repertoire): void
    {
        // La rétention du Job supprime les `.sql` sans connaître les témoins :
        // un témoin dont le dump a disparu ne décrit plus rien.
        foreach (glob($repertoire . '/tatacora-*.sql' . self::SUFFIXE_TELECHARGEE) ?: [] as $marqueur) {
            if (! is_file(substr($marqueur, 0, -strlen(self::SUFFIXE_TELECHARGEE)))) {
                @unlink($marqueur);
            }
        }
    }

    /**
     * Le chemin RÉEL du fichier si — et seulement si — `$nom` respecte le
     * motif exact produit par le Job ET que le fichier existe réellement.
     */
    public function cheminSiExiste(string $nom): ?string
    {
        if (preg_match(self::MOTIF_NOM, $nom) !== 1) {
            return null;
        }

        $chemin = storage_path('app/sauvegardes/' . $nom);

        return is_file($chemin) ? $chemin : null;
    }
}
