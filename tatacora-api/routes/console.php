<?php

declare(strict_types=1);

use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Facturation\Jobs\RejouerCertificationsMecefEnEchecJob;
use App\Domain\Stocks\Jobs\VerifierSeuilsStockJob;
use App\Shared\Audit\Jobs\PurgerJournalAuditJob;
use App\Shared\Backup\Jobs\SauvegardeBaseQuotidienneJob;
use App\Shared\ContactEditeur\Services\MessageEditeurService;
use App\Shared\Exploitation\Services\BattementPlanificateur;
use App\Shared\Sync\Jobs\NettoyerDeduplicationSyncJob;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

/*
|---------------------------------------------------------------------------
| Taches planifiees — LISTE_DES_CRON_JOBS_CPANEL.md
|---------------------------------------------------------------------------
| Regle de revue du document source : toute tache ajoutee ici DOIT etre
| ajoutee au document dans la meme Pull Request. Une tache non listee la-bas
| est consideree non documentee, donc bloquante en revue.
|
| Sur cPanel mutualise, un seul cron systeme appelle `schedule:run` chaque
| minute ; c'est Laravel qui distribue ensuite (CPANEL_DEPLOYMENT.md §6).
*/

// Le BATTEMENT du planificateur (19/10/2026) : la preuve que le cron cPanel
// tourne, lue par `tatacora:verifier-production`. Sans lui, un cron jamais
// configure ne se voit pas : toutes les taches ci-dessous seraient mortes en
// silence.
Artisan::command('tatacora:battement-planificateur', function (BattementPlanificateur $battement): int {
    $battement->battre();

    return 0;
})->purpose('Pose l\'heure du dernier passage du planificateur (preuve que le cron tourne)');

Schedule::command('tatacora:battement-planificateur')
    ->everyMinute();

// Passage d'annee (20/10/2026) : l'exercice comptable de l'annee en cours est
// ouvert s'il manque, et celui de l'annee SUIVANTE des le 1er decembre — sans
// quoi, le 1er janvier, toute vente et toute depense serait refusee jusqu'a
// une ouverture manuelle. Les pieces l'ouvrent aussi a la volee (filet).
Artisan::command('tatacora:ouvrir-exercices', function (ExerciceComptableService $exercices): int {
    $annees = [now()->year, ...(now()->month === 12 ? [now()->year + 1] : [])];

    foreach ($annees as $annee) {
        $exercice = $exercices->assurer($annee, 'planificateur');
        $this->info("Exercice {$annee} : {$exercice->statut}.");
    }

    return 0;
})->purpose('Ouvre l\'exercice de l\'annee en cours, et celui de l\'annee suivante en decembre');

Schedule::command('tatacora:ouvrir-exercices')
    ->dailyAt('00:05')
    ->withoutOverlapping();

// Contournement de l'absence de processus persistant sur hebergement mutualise :
// la file est videe par salves d'une minute plutot que par un worker permanent.
Schedule::command('queue:work --stop-when-empty --max-time=50')
    ->everyMinute()
    ->withoutOverlapping();

// RG-07 — filet de securite des alertes de stock. Complete la verification
// synchrone : un seuil releve sans mouvement ne declencherait rien sans lui.
Schedule::job(new VerifierSeuilsStockJob())
    ->everyFifteenMinutes()
    ->withoutOverlapping();

// RG-03 — rattrape les factures dont la certification DGI a echoue, sans
// jamais bloquer leur emission initiale.
Schedule::job(new RejouerCertificationsMecefEnEchecJob())
    ->everyThirtyMinutes()
    ->withoutOverlapping();

// NFR sauvegarde. Echoue bruyamment : une sauvegarde muette en echec pendant
// trois mois ressemble en tout point a une sauvegarde qui fonctionne.
Schedule::job(new SauvegardeBaseQuotidienneJob())
    ->dailyAt('02:00')
    ->withoutOverlapping();

// LARAVEL_SYNC_FLUTTER.md §5 — purge de la memoire d'idempotence (TTL 7 jours).
Schedule::job(new NettoyerDeduplicationSyncJob())
    ->dailyAt('03:00');

// RG-15 — purge du journal d'audit. PLANIFIEE MAIS INERTE : le job refuse de
// purger tant que la duree de retention contractuelle n'est pas definie
// (PA-08). Le planifier des maintenant evite un deploiement le jour ou le
// Product Owner tranchera ; l'inertie est dans le job, pas dans le planning.
Schedule::job(new PurgerJournalAuditJob())
    ->monthlyOn(1, '04:00');

// « Contactez l'editeur » (directive PO du 14/10/2026) — rejoue les messages
// restes « en attente d'envoi » apres un echec SMTP. Sans messagerie reelle
// configuree, la commande le DIT et ne tente rien.
Artisan::command('contact-editeur:rejouer', function (MessageEditeurService $service): int {
    $bilan = $service->rejouerEnAttente();

    if ($bilan === null) {
        $this->warn('Messagerie non configuree (MAIL_MAILER/MAIL_HOST) : aucun envoi tente.');

        return 1;
    }

    $this->info("Transmis : {$bilan['transmis']} ; toujours en attente : {$bilan['en_attente']}.");

    return $bilan['en_attente'] === 0 ? 0 : 1;
})->purpose('Rejoue les messages a l\'editeur restes en attente d\'envoi');

Schedule::command('contact-editeur:rejouer')
    ->hourly()
    ->withoutOverlapping();

/*
|---------------------------------------------------------------------------
| Taches documentees mais NON planifiees a ce stade
|---------------------------------------------------------------------------
| Volontairement absentes, et non declarees en coquilles vides : une tache qui
| s'execute sans rien faire rend le planning faussement complet, et personne ne
| remarque que la fonction manque.
|
| - SyntheseQuotidienneJob (21h00, RG-20 / EF-M12-04) : le module M12
|   Notifications n'est pas implemente et le canal WhatsApp n'existe pas. La
|   synthese pourrait etre calculee mais pas diffusee — or c'est la diffusion
|   qui remplace la remontee manuelle.
| - ExecuterEtatsPlanifiesJob (06h00, EF-M14-05) : le domaine M14 Etats est
|   vide, et RG-19 (en-tete normalisee) n'est pas implementee.
| - VerifierCouvertureCongesJob (07h00, RG-14) : conges et plannings du domaine
|   M13 ne sont pas implementes.
|
| Ces trois taches sont a ajouter au sprint de leur domaine respectif.
*/
