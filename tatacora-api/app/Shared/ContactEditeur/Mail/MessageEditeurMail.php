<?php

declare(strict_types=1);

namespace App\Shared\ContactEditeur\Mail;

use App\Shared\ContactEditeur\Models\MessageEditeur;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Attachment;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Support\Facades\Storage;

/**
 * Le courriel « Contactez l'éditeur » — directive PO du 14/10/2026 : envoi
 * réel par SMTP au support de l'éditeur.
 *
 * Le corps est du TEXTE de l'utilisateur, rendu échappé (`e()`) : un message
 * saisi dans la PWA ne doit jamais injecter de HTML dans la boîte du support.
 * La capture d'écran d'un signalement est jointe quand elle existe encore sur
 * le disque public — absente, le courriel part sans elle plutôt que d'échouer.
 *
 * @see \App\Shared\ContactEditeur\Services\MessageEditeurService unique expéditeur
 */
class MessageEditeurMail extends Mailable
{
    public function __construct(public readonly MessageEditeur $message)
    {
    }

    public function envelope(): Envelope
    {
        return new Envelope(subject: '[TATACORA] ' . $this->message->objet);
    }

    public function content(): Content
    {
        return new Content(htmlString: nl2br(e($this->corps()), false));
    }

    /**
     * @return list<Attachment>
     */
    public function attachments(): array
    {
        $chemin = $this->message->capture_chemin;

        if ($chemin === null || ! Storage::disk('public')->exists($chemin)) {
            return [];
        }

        return [
            Attachment::fromStorageDisk('public', $chemin)
                ->as($this->message->capture_nom ?? basename($chemin)),
        ];
    }

    public function corps(): string
    {
        $auteur = $this->message->auteur;

        $lignes = [
            'Type : ' . $this->message->type,
            'Auteur : ' . ($auteur !== null ? $auteur->login : '—'),
        ];

        if ($this->message->module_concerne !== null) {
            $lignes[] = 'Module concerné : ' . $this->message->module_concerne;
        }

        $lignes[] = '';
        $lignes[] = $this->message->corps;

        if ($this->message->etapes !== null && trim($this->message->etapes) !== '') {
            $lignes[] = '';
            $lignes[] = 'Étapes pour reproduire :';
            $lignes[] = $this->message->etapes;
        }

        return implode("\n", $lignes);
    }
}
