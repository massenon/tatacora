<?php

declare(strict_types=1);

namespace App\Shared\ContactEditeur\Services;

use App\Shared\ContactEditeur\Mail\MessageEditeurMail;
use App\Shared\ContactEditeur\Models\MessageEditeur;
use App\Shared\Mail\Services\ConfigurationMailService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Envoi vers l'éditeur — maître : `prototype_v2/pages/contact-editeur.html`.
 *
 * ## Ce que ce Service corrige (01/09/2026)
 *
 * `ContactEditeur::envoyerMessage()`/`signalerBug()` avaient été SUPPRIMÉS le
 * 31/08/2026 : ils écrivaient dans une table `messages_editeur` qui
 * n'existait nulle part, `Schema::hasTable()` rendait toujours `false`,
 * l'insertion n'avait donc jamais lieu — et pourtant l'écran annonçait
 * « Votre message a été transmis à l'éditeur ». C'est PA-59/60/61 : un
 * indicateur qui dit que tout va bien pendant que rien n'a lieu.
 *
 * La table existe désormais (migration `2026_09_04_100000`), et ce Service
 * en est l'unique auteur.
 *
 * ## L'envoi SMTP est TENTÉ, jamais affirmé
 *
 * `statut` naît à `a_transmettre` (« en attente d'envoi »). Il ne passe à
 * `transmis` QUE si l'envoi du Mailable `MessageEditeurMail` a réellement
 * réussi (SMTP réel depuis le 14/10/2026, mot de passe en `.env` seulement) — jamais parce qu'une configuration
 * existe en apparence. `configurationMailReelle()` refuse les mailers
 * `log`/`array`/`null`, qui écrivent dans un journal ou nulle part et ne
 * délivrent jamais rien : les accepter ferait passer `statut` à `transmis`
 * sur un message que personne, à l'éditeur, n'a reçu — exactement le défaut
 * du badge MECeF que PA-61 a fermé.
 *
 * Un échec d'envoi (hôte injoignable, identifiants refusés) est journalisé
 * et **avalé** : l'enregistrement reste — c'est la garantie que l'écran
 * « Vos envois » ne perd jamais la trace du message —, et son statut reste
 * honnêtement `a_transmettre`. Contrairement à MECeF (une panne à Cotonou ne
 * doit jamais bloquer un encaissement), ici rien ne bloque non plus : le
 * message est capturé quoi qu'il arrive à SMTP, parce que le geste de
 * l'utilisateur — signaler, questionner — a une valeur même non transmis.
 */
class MessageEditeurService
{
    public function __construct(private readonly ConfigurationMailService $configurationMail)
    {
    }

    /**
     * @param  array{type: string, objet: string, module_concerne: string|null, corps: string, etapes: string|null, capture_nom: string|null, capture_chemin: string|null}  $donnees
     */
    public function enregistrer(array $donnees): MessageEditeur
    {
        $message = DB::transaction(function () use ($donnees): MessageEditeur {
            /** @var MessageEditeur $cree */
            $cree = MessageEditeur::create($donnees + ['statut' => MessageEditeur::STATUT_A_TRANSMETTRE]);

            return $cree;
        });

        if ($this->configurationMailReelle()) {
            $this->tenterEnvoi($message);
        }

        return $message->fresh() ?? $message;
    }

    /**
     * Un mailer réellement susceptible de délivrer — pas `log`/`array`/`null`,
     * et pour `smtp`, un hôte configuré.
     *
     * Délègue à `ConfigurationMailService`, l'unique auteur de cette
     * question depuis le 01/09/2026 (voir son en-tête) : la méthode reste ici
     * pour ne rien casser des appelants existants.
     */
    public function configurationMailReelle(): bool
    {
        return $this->configurationMail->estReelle();
    }

    /**
     * Rejoue les messages restés `a_transmettre` (SMTP injoignable, mot de
     * passe pas encore posé dans `.env`…) — directive PO du 14/10/2026.
     * Appelé par la commande planifiée `contact-editeur:rejouer`.
     *
     * Sans configuration mail réelle, AUCUNE tentative : `null` le dit, au
     * lieu d'un « 0 transmis » qui se lirait comme « rien en attente ».
     *
     * @return array{transmis: int, en_attente: int}|null
     */
    public function rejouerEnAttente(): ?array
    {
        if (! $this->configurationMailReelle()) {
            return null;
        }

        $transmis = 0;
        $enAttente = 0;

        MessageEditeur::query()
            ->where('statut', MessageEditeur::STATUT_A_TRANSMETTRE)
            ->orderBy('date_creation')
            ->limit(100)
            ->get()
            ->each(function (MessageEditeur $message) use (&$transmis, &$enAttente): void {
                $this->tenterEnvoi($message) ? $transmis++ : $enAttente++;
            });

        return ['transmis' => $transmis, 'en_attente' => $enAttente];
    }

    /**
     * Envoi par le Mailable au support (`contact_editeur.destinataires`).
     * `true` seulement si l'envoi a réellement réussi.
     */
    private function tenterEnvoi(MessageEditeur $message): bool
    {
        /** @var list<string> $destinataires */
        $destinataires = config('contact_editeur.destinataires', []);

        if ($destinataires === []) {
            return false;
        }

        try {
            Mail::to($destinataires)->send(new MessageEditeurMail($message));

            $message->forceFill(['statut' => MessageEditeur::STATUT_TRANSMIS])->save();

            return true;
        } catch (Throwable $erreur) {
            // Avalé délibérément (voir l'en-tête) : l'enregistrement reste,
            // honnêtement `a_transmettre`, et la commande de rejeu le reprendra.
            Log::warning('Échec de transmission d\'un message à l\'éditeur', [
                'message_id' => $message->id,
                'erreur' => $erreur->getMessage(),
            ]);

            return false;
        }
    }
}
