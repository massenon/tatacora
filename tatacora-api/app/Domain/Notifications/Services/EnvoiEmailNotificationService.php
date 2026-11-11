<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\NotificationEnvoyee;
use App\Shared\Mail\Services\ConfigurationMailService;
use App\Shared\Mail\Support\CauseEchecEmail;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use RuntimeException;
use Throwable;

/**
 * L'envoi RÉEL par e-mail — directive du Product Owner du 01/09/2026 :
 * « pour le moment utilise le SMTP », complétée le 26/10/2026 : « l'envoi
 * réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB » (file d'attente,
 * tentatives, relance, cause lisible de l'échec).
 *
 * ## Un canal SEUL, jusqu'à nouvel ordre
 *
 * WhatsApp reste sans API contractée, Android sans application Flutter qui
 * enregistre un appareil, SMS sans agrégateur retenu — voir `RegistreCanaux`.
 * `envoyer()` refuse tout message dont le canal n'est pas `email` : le
 * porter à un canal non branché produirait exactement le défaut que ce lot
 * corrige pour l'e-mail, appliqué à l'envers.
 *
 * ## Qui appelle (le déclencheur, pas un commentaire)
 *
 * * `FileAttenteNotificationsService::detecter()` : à la composition d'un
 *   message e-mail ayant une adresse, il met `EnvoyerNotificationEmailJob`
 *   en file (jobs, `queue:work` planifié chaque minute) ;
 * * le bouton « Envoyer » / « Renvoyer » du hub (envoi immédiat) ;
 * * `notifications:relancer-emails` (planifiée) : `relancer()` remet en file
 *   les messages dont le délai de relance est écoulé.
 *
 * ## Deux conditions, et JAMAIS d'affirmation sans elles (PA-59/60/61)
 *
 * 1. Une adresse RÉELLE (`MessageNotificationCompose::email_destinataire`,
 *    posée par le détecteur qui a composé le message — jamais `destinataire`,
 *    qui est un nom d'affichage).
 * 2. Un mailer RÉELLEMENT configuré (`ConfigurationMailService`).
 *
 * Sans l'une des deux, le message reste `en_attente` : aucune tentative n'est
 * comptée (rien n'a été essayé), la raison est dite.
 *
 * ## Jamais deux e-mails pour un message
 *
 * Un verrou par message (`Cache::lock`) et une relecture du statut sous ce
 * verrou : le bouton et le job qui se croisent n'envoient qu'une fois. La
 * clé d'idempotence de la COMPOSITION est, elle, au schéma
 * (`unique(modele_id, reference)`).
 *
 * ## Un échec de transport laisse le message EN FILE, avec sa cause
 *
 * `tentatives`, `derniere_erreur` (cause lisible, jamais le mot de passe) et
 * `derniere_tentative_le` sont écrits à chaque tentative RÉELLE. Au-delà de
 * `TENTATIVES_MAX` les relances automatiques s'arrêtent ; le message n'est
 * jamais supprimé.
 *
 * ## Le succès écrit DEUX choses, dans la MÊME transaction
 *
 * `notifications_envoyees` (le journal RÉEL) reçoit la trace de ce que le
 * transport a RÉELLEMENT accepté ; `notifications_composees.statut` passe à
 * `envoye` et `envoye_le` est posé. Les deux ensemble, ou aucun.
 */
class EnvoiEmailNotificationService
{
    public function __construct(private readonly ConfigurationMailService $configurationMail)
    {
    }

    /**
     * @return array{envoye: bool, motif: string|null, transitoire: bool}
     *
     * @throws RuntimeException message déjà traité, ou canal non pris en charge
     */
    public function envoyer(MessageNotificationCompose $message): array
    {
        if (! $message->enAttente()) {
            throw new RuntimeException(__('notifications_pwa.message_deja_traite'));
        }

        if ($message->canal !== RegistreCanaux::EMAIL) {
            throw new RuntimeException(__('notifications_pwa.envoi_canal_non_supporte'));
        }

        $adresse = trim((string) $message->email_destinataire);

        if ($adresse === '') {
            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_sans_adresse'), 'transitoire' => false];
        }

        if (! $this->configurationMail->estReelle()) {
            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_sans_configuration'), 'transitoire' => false];
        }

        $verrou = Cache::lock('notification-email:'.$message->id, 120);

        if (! $verrou->get()) {
            // L'autre chemin (bouton ou job) l'envoie en ce moment même.
            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_deja_en_cours'), 'transitoire' => false];
        }

        try {
            // Relu sous verrou : l'autre chemin a pu l'envoyer entre-temps.
            $message->refresh();

            if (! $message->enAttente()) {
                throw new RuntimeException(__('notifications_pwa.message_deja_traite'));
            }

            return $this->tenter($message, $adresse);
        } finally {
            $verrou->release();
        }
    }

    /**
     * Remet en file (job) les messages e-mail dont la relance est due. Sans
     * messagerie réelle : RIEN n'est tenté, `null` le dit (« 0 relancé »
     * se lirait « rien en attente »).
     *
     * @return int|null le nombre de messages remis en file
     */
    public function relancer(): ?int
    {
        if (! $this->configurationMail->estReelle()) {
            return null;
        }

        $maintenant = now();
        $relances = 0;

        MessageNotificationCompose::query()
            ->where('statut', MessageNotificationCompose::STATUT_EN_ATTENTE)
            ->where('canal', RegistreCanaux::EMAIL)
            ->whereNotNull('email_destinataire')
            ->where('email_destinataire', '!=', '')
            ->where('tentatives', '<', MessageNotificationCompose::TENTATIVES_MAX)
            ->orderBy('date_creation')
            ->limit(100)
            ->get()
            ->each(function (MessageNotificationCompose $message) use ($maintenant, &$relances): void {
                $due = $message->relanceDueLe();

                if ($due !== null && $due->greaterThan($maintenant)) {
                    return;
                }

                \App\Domain\Notifications\Jobs\EnvoyerNotificationEmailJob::dispatch($message->id);
                $relances++;
            });

        return $relances;
    }

    /**
     * « Renvoyer » après épuisement des relances : le compteur repart de zéro
     * (le message n'est pas supprimé, l'historique d'erreur reste lisible
     * jusqu'à la nouvelle tentative).
     */
    public function remettreEnFile(MessageNotificationCompose $message): void
    {
        if ($message->enAttente()) {
            $message->forceFill(['tentatives' => 0])->save();
        }
    }

    /**
     * @return array{envoye: bool, motif: string|null, transitoire: bool}
     */
    private function tenter(MessageNotificationCompose $message, string $adresse): array
    {
        try {
            Mail::raw($message->contenu, function ($courriel) use ($message, $adresse): void {
                $courriel->to($adresse)->subject($message->objet ?: (string) config('app.name'));
            });
        } catch (Throwable $erreur) {
            $cause = CauseEchecEmail::depuis($erreur);

            Log::warning('Échec de l\'envoi d\'une notification par e-mail', [
                'message_id' => $message->id,
                'erreur' => $cause,
            ]);

            // Une tentative RÉELLE : comptée, datée, expliquée.
            $message->forceFill([
                'tentatives' => $message->tentatives + 1,
                'derniere_erreur' => $cause,
                'derniere_tentative_le' => now(),
            ])->save();

            return ['envoye' => false, 'motif' => $cause, 'transitoire' => CauseEchecEmail::estTransitoire($erreur)];
        }

        DB::transaction(function () use ($message, $adresse): void {
            NotificationEnvoyee::create([
                'modele_id' => $message->modele_id,
                'destinataire' => $adresse,
                'date_envoi' => now(),
                'statut_remise' => 'envoye',
            ]);

            $message->forceFill([
                'statut' => MessageNotificationCompose::STATUT_ENVOYE,
                'tentatives' => $message->tentatives + 1,
                'derniere_erreur' => null,
                'derniere_tentative_le' => now(),
                'envoye_le' => now(),
            ])->save();
        });

        return ['envoye' => true, 'motif' => null, 'transitoire' => false];
    }
}
