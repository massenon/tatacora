<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Jobs;

use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Services\EnvoiEmailNotificationService;
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use RuntimeException;

/**
 * Envoie UN message de notification par e-mail (M12) — le travail de la file
 * `queue:work` planifiée chaque minute.
 *
 * Unique par message (`ShouldBeUnique`) : la composition et la relance qui
 * mettent le même message en file ne produisent pas deux e-mails ; le verrou
 * du service ferme le reste. Une erreur de connexion se retente (3 essais,
 * 1 puis 5 minutes) ; tout autre refus est noté (`derniere_erreur`) et laissé
 * à la relance planifiée — le job ne s'obstine pas.
 */
class EnvoyerNotificationEmailJob implements ShouldBeUnique, ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public int $uniqueFor = 300;

    public function __construct(public readonly string $messageId)
    {
    }

    public function uniqueId(): string
    {
        return $this->messageId;
    }

    /**
     * @return list<int>
     */
    public function backoff(): array
    {
        return [60, 300];
    }

    public function handle(EnvoiEmailNotificationService $service): void
    {
        $message = MessageNotificationCompose::query()->find($this->messageId);

        if ($message === null || ! $message->enAttente()) {
            return;
        }

        $resultat = $service->envoyer($message);

        if (! $resultat['envoye'] && $resultat['transitoire']) {
            // Relancé par la file selon `backoff()`.
            throw new RuntimeException((string) $resultat['motif']);
        }
    }
}
