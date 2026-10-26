<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

use App\Domain\Notifications\Jobs\EnvoyerNotificationEmailJob;
use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\ModeleNotification;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * La file d'attente de M12 — onglet PAR DÉFAUT du maître
 * (`m12-notifications-hub.html` l.73, `notifications-engine.js` l.402-461).
 *
 * ## Ce que ce Service fait — et ne fait PAS
 *
 * `detecter()` COMPOSE des messages réels à partir de vraies données
 * (`Domain/Notifications/Detecteurs/`) et les met en file ; un message
 * e-mail ayant une adresse est AUSSI mis en file d'envoi (jobs) — l'envoi
 * est RÉEL depuis le 26/10/2026, par `EnvoiEmailNotificationService`.
 * `marquerTraite()` et `abandonner()` en sortent le message. Les canaux autres
 * que l'e-mail ne partent pas : RG-20 n'y est pas implémentée (voir
 * `RegistreDeclencheurs`).
 *
 * ## Idempotence — `unique(modele_id, reference)` au SCHÉMA
 *
 * `detecter()` ne revérifie PAS en mémoire si une occurrence est déjà en
 * file : il laisse la contrainte du schéma faire foi, capture la violation
 * et la traite comme « déjà composé », jamais comme une erreur remontée à
 * l'écran. Deux détections concurrentes (deux clics, deux onglets) ne
 * peuvent donc jamais dupliquer un message.
 */
class FileAttenteNotificationsService
{
    public function __construct(private readonly ModeleNotificationService $modeles)
    {
    }

    /**
     * @return array{composes: int, echecs: list<array{modele: string, reference: string|null, motif: string}>}
     */
    public function detecter(): array
    {
        $composes = 0;
        $echecs = [];

        /** @var EloquentCollection<int, ModeleNotification> $modelesActifs */
        $modelesActifs = ModeleNotification::query()->where('actif', true)->get();

        foreach ($modelesActifs as $modele) {
            $declencheurCode = RegistreDeclencheurs::detecteur($modele->evenement);

            if ($declencheurCode === null) {
                // Déclencheur inconnu du registre, OU couvert par aucun
                // détecteur (voir les raisons datées de `RegistreDeclencheurs`)
                // : ni l'un ni l'autre n'est une erreur à signaler ici, un
                // modèle actif sur un déclencheur non couvert n'est pas une
                // faute de saisie.
                continue;
            }

            $detecteur = app($declencheurCode);

            try {
                $occurrences = $detecteur->detecter();
            } catch (\Throwable $erreur) {
                $echecs[] = ['modele' => $modele->evenement, 'reference' => null, 'motif' => $erreur->getMessage()];

                continue;
            }

            foreach ($occurrences as $occurrence) {
                try {
                    $compose = $this->modeles->composerMessage($modele, $occurrence['variables']);
                } catch (RuntimeException $erreur) {
                    $echecs[] = [
                        'modele' => $modele->evenement,
                        'reference' => $occurrence['reference'],
                        'motif' => $erreur->getMessage(),
                    ];

                    continue;
                }

                try {
                    $cree = DB::transaction(function () use ($modele, $occurrence, $compose): MessageNotificationCompose {
                        return MessageNotificationCompose::create([
                            'modele_id' => $modele->id,
                            'canal' => $modele->canal,
                            'reference' => $occurrence['reference'],
                            'destinataire' => $occurrence['destinataire'],
                            // L'adresse RÉELLE, quand le détecteur sait la
                            // résoudre — `null` sinon (01/09/2026, envoi
                            // e-mail réel). Jamais `destinataire`, qui est un
                            // nom d'affichage, en repli : un nom n'est pas
                            // une adresse.
                            'email_destinataire' => $occurrence['email'] ?? null,
                            'objet' => $compose['objet'],
                            'contenu' => $compose['contenu'],
                            'longueur' => $compose['longueur'],
                            'statut' => MessageNotificationCompose::STATUT_EN_ATTENTE,
                        ]);
                    });
                    $composes++;
                    $this->mettreEnFileSiEmail($cree);
                } catch (\Illuminate\Database\QueryException $e) {
                    // Violation de `unique(modele_id, reference)` : l'occurrence
                    // est déjà composée (en file ou déjà traitée). C'est
                    // l'idempotence attendue, jamais un échec à signaler.
                    if (! str_contains($e->getMessage(), 'notifications_composees')) {
                        throw $e;
                    }
                }
            }
        }

        return ['composes' => $composes, 'echecs' => $echecs];
    }

    /**
     * L'e-mail composé PART : mis en file d'envoi (`EnvoyerNotificationEmailJob`)
     * dès qu'il a une adresse RÉELLE. Une file en panne ne casse jamais la
     * détection : le message est composé, la relance planifiée le reprendra.
     */
    private function mettreEnFileSiEmail(MessageNotificationCompose $message): void
    {
        if ($message->canal !== RegistreCanaux::EMAIL || blank($message->email_destinataire)) {
            return;
        }

        try {
            EnvoyerNotificationEmailJob::dispatch($message->id);
        } catch (\Throwable $erreur) {
            \Illuminate\Support\Facades\Log::warning('Mise en file d\'une notification e-mail impossible', [
                'message_id' => $message->id,
                'erreur' => $erreur->getMessage(),
            ]);
        }
    }

    /**
     * « Transmis à la main » — le message a été transmis HORS du système
     * (un appel, un message envoyé manuellement), et le déclare. Ce n'est
     * jamais un envoi système : `statut` ne devient jamais « envoyé ».
     */
    public function marquerTraite(
        MessageNotificationCompose $message,
        ?string $commentaire,
    ): MessageNotificationCompose {
        if (! $message->enAttente()) {
            throw new RuntimeException(__('notifications_pwa.message_deja_traite'));
        }

        $message->update([
            'statut' => MessageNotificationCompose::STATUT_TRAITE_MANUELLEMENT,
            'commentaire' => filled($commentaire) ? trim((string) $commentaire) : null,
        ]);

        return $message->refresh();
    }

    /**
     * Abandonne un message — il ne sera JAMAIS envoyé. Le motif est
     * obligatoire, comme au maître (`notifications-engine.js` l.526).
     */
    public function abandonner(
        MessageNotificationCompose $message,
        string $motif,
    ): MessageNotificationCompose {
        if (! $message->enAttente()) {
            throw new RuntimeException(__('notifications_pwa.message_deja_traite'));
        }

        $motifPropre = trim($motif);

        if ($motifPropre === '') {
            throw new RuntimeException(__('notifications_pwa.motif_abandon_requis'));
        }

        $message->update([
            'statut' => MessageNotificationCompose::STATUT_ABANDONNE,
            'motif_abandon' => $motifPropre,
        ]);

        return $message->refresh();
    }

    /**
     * @return EloquentCollection<int, MessageNotificationCompose>
     */
    public function file(): EloquentCollection
    {
        return MessageNotificationCompose::query()
            ->with('modele')
            ->where('statut', MessageNotificationCompose::STATUT_EN_ATTENTE)
            ->orderByDesc('date_creation')
            ->get();
    }

    /**
     * Les messages traités OU abandonnés — la moitié « composée » du
     * journal (l'autre moitié, les envois réellement partis, vient de
     * `ModeleNotificationService::journal()`, table `notifications_envoyees`).
     *
     * @return EloquentCollection<int, MessageNotificationCompose>
     */
    public function journalTraitement(): EloquentCollection
    {
        return MessageNotificationCompose::query()
            ->with(['modele', 'traitePar'])
            ->whereIn('statut', [
                MessageNotificationCompose::STATUT_TRAITE_MANUELLEMENT,
                MessageNotificationCompose::STATUT_ABANDONNE,
            ])
            ->orderByDesc('date_modification')
            ->get();
    }
}
