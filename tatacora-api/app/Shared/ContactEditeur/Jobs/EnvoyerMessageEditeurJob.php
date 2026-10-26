<?php

declare(strict_types=1);

namespace App\Shared\ContactEditeur\Jobs;

use App\Shared\ContactEditeur\Models\MessageEditeur;
use App\Shared\ContactEditeur\Services\MessageEditeurService;
use App\Shared\Mail\Services\ConfigurationMailService;
use Illuminate\Contracts\Queue\ShouldBeUnique;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Cache;

/**
 * Envoie UN message à l'éditeur par SMTP — le travail de la file `queue:work`
 * planifiée chaque minute. Unique par message, verrouillé : jamais deux
 * courriels pour un message. Un échec est noté sur la ligne
 * (`tentatives`, `derniere_erreur`) et repris par `contact-editeur:rejouer`.
 */
class EnvoyerMessageEditeurJob implements ShouldBeUnique, ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public int $uniqueFor = 300;

    public function __construct(public readonly string $messageId)
    {
    }

    public function uniqueId(): string
    {
        return $this->messageId;
    }

    public function handle(MessageEditeurService $service, ConfigurationMailService $configuration): void
    {
        if (! $configuration->estReelle()) {
            return;
        }

        $verrou = Cache::lock('message-editeur:'.$this->messageId, 120);

        if (! $verrou->get()) {
            return;
        }

        try {
            $message = MessageEditeur::query()->find($this->messageId);

            if ($message !== null && ! $message->estTransmis()) {
                $service->tenterEnvoi($message);
            }
        } finally {
            $verrou->release();
        }
    }
}
