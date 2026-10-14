<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\NotificationEnvoyee;
use App\Shared\Mail\Services\ConfigurationMailService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use RuntimeException;
use Throwable;

/**
 * L'envoi RÉEL par e-mail — directive du Product Owner du 01/09/2026 :
 * « pour le moment utilise le SMTP ».
 *
 * ## Un canal SEUL, jusqu'à nouvel ordre
 *
 * WhatsApp reste sans API contractée, Android sans application Flutter qui
 * enregistre un appareil, SMS sans agrégateur retenu — voir `RegistreCanaux`.
 * `envoyer()` refuse tout message dont le canal n'est pas `email` : le
 * porter à un canal non branché produirait exactement le défaut que ce lot
 * corrige pour l'e-mail, appliqué à l'envers.
 *
 * ## Deux conditions, et JAMAIS d'affirmation sans elles (PA-59/60/61)
 *
 * 1. Une adresse RÉELLE (`MessageNotificationCompose::email_destinataire`,
 *    posée par le détecteur qui a composé le message — jamais `destinataire`,
 *    qui est un nom d'affichage).
 * 2. Un mailer RÉELLEMENT configuré (`ConfigurationMailService`, le même
 *    contrôle que « Contactez l'éditeur », PA-159 — un seul auteur pour
 *    cette question, voir son en-tête).
 *
 * Sans l'une des deux, le message reste `en_attente` : aucune écriture n'a
 * lieu, jamais un statut qui affirmerait un envoi que rien n'a vérifié.
 *
 * ## Un échec de transport laisse le message EN FILE
 *
 * `Mail::raw()` qui lève (hôte injoignable, identifiants refusés) est
 * journalisé et **avalé** : contrairement à « Contactez l'éditeur » (où
 * l'enregistrement existe déjà et ne fait que rester `a_transmettre`), ici
 * rien n'a encore quitté la file — le message est donc rendu tel quel,
 * toujours disponible pour « Transmis à la main » ou une nouvelle tentative.
 *
 * ## Le succès écrit DEUX choses, dans la MÊME transaction
 *
 * `notifications_envoyees` (le journal RÉEL, jusqu'ici jamais alimenté — voir
 * le docblock de `NotificationEnvoyee`, désormais partiellement périmé pour
 * le canal e-mail) reçoit la trace de ce que le transport a RÉELLEMENT
 * accepté ; `notifications_composees.statut` passe à `envoye`, un
 * TROISIÈME sort distinct de « transmis à la main » (personne n'a fait le
 * geste manuel) et d'« abandonné ». Les deux ensemble, ou aucun des deux : un
 * message ne doit jamais quitter la file sans laisser de trace au journal.
 */
class EnvoiEmailNotificationService
{
    public function __construct(private readonly ConfigurationMailService $configurationMail)
    {
    }

    /**
     * @return array{envoye: bool, motif: string|null}
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
            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_sans_adresse')];
        }

        if (! $this->configurationMail->estReelle()) {
            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_sans_configuration')];
        }

        try {
            Mail::raw($message->contenu, function ($courriel) use ($message, $adresse): void {
                $courriel->to($adresse)->subject($message->objet ?: (string) config('app.name'));
            });
        } catch (Throwable $erreur) {
            Log::warning('Échec de l\'envoi d\'une notification par e-mail', [
                'message_id' => $message->id,
                'erreur' => $erreur->getMessage(),
            ]);

            return ['envoye' => false, 'motif' => __('notifications_pwa.envoi_echec')];
        }

        DB::transaction(function () use ($message, $adresse): void {
            NotificationEnvoyee::create([
                'modele_id' => $message->modele_id,
                'destinataire' => $adresse,
                'date_envoi' => now(),
                'statut_remise' => 'envoye',
            ]);

            $message->update(['statut' => MessageNotificationCompose::STATUT_ENVOYE]);
        });

        return ['envoye' => true, 'motif' => null];
    }
}
