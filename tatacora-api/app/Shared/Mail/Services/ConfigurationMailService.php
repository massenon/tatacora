<?php

declare(strict_types=1);

namespace App\Shared\Mail\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Support\Facades\Mail;

/**
 * Un mailer RÉELLEMENT susceptible de délivrer — jamais une apparence de
 * configuration.
 *
 * ## Un seul auteur pour cette question, posée deux fois dans le dépôt
 *
 * `MessageEditeurService::configurationMailReelle()` (Contact éditeur,
 * PA-159) posait déjà exactement ce contrôle. `EnvoiEmailNotificationService`
 * (M12, notification par e-mail, 01/09/2026) en a besoin à l'identique — deux
 * copies auraient fini par diverger (même défaut que les référentiels à
 * double auteur nommés dans `CLAUDE.md`). Ce Service est donc l'UNIQUE
 * auteur ; les deux appelants s'y réfèrent, jamais une seconde formule.
 *
 * `log`/`array`/`null` écrivent dans un journal ou nulle part et ne
 * délivrent jamais rien : les accepter ferait passer un envoi pour réussi
 * sur un message que personne, en pratique, n'a reçu — le défaut exact que
 * PA-61 (badge MECeF) a fermé, transposé au courrier électronique.
 *
 * ## L'onglet « Email (SMTP) » de Paramètres écrit ici ses quatre clés
 * (02/09/2026, directive Product Owner)
 *
 * Serveur, port, sécurité et utilisateur SMTP sont des paramètres MÉTIER,
 * modifiables sans déploiement (RG-10) : ils vivent dans `parametres_systeme`
 * sous les constantes `CLE_SMTP_*` ci-dessous, et ce service est leur unique
 * lecteur. Le MOT DE PASSE, lui, est un secret : il reste en `.env`
 * (`MAIL_PASSWORD`) et n'entrera jamais dans une table lisible par tout
 * profil ayant accès à l'écran — règle absolue du dépôt, reprise de
 * `ParametreSystemeService`.
 *
 * `appliquer()` superpose ces clés à la configuration d'environnement AU
 * MOMENT de l'envoi : tant que le serveur SMTP n'est pas renseigné en
 * Paramètres, la configuration `.env` reste seule maîtresse. `estReelle()`
 * applique AVANT de juger — juger une configuration qu'on n'applique pas
 * affirmerait un état que l'envoi ne rencontrera jamais (PA-59/60/61), et
 * c'est ce qui fait profiter tous les chemins d'envoi existants
 * (notifications M12, Contact éditeur) du paramétrage sans qu'aucun n'ait à
 * connaître ces clés.
 */
class ConfigurationMailService
{
    public const CLE_SMTP_HOTE = 'email_smtp_hote';

    public const CLE_SMTP_PORT = 'email_smtp_port';

    public const CLE_SMTP_SECURITE = 'email_smtp_securite';

    public const CLE_SMTP_UTILISATEUR = 'email_smtp_utilisateur';

    /** Les trois valeurs du maître (`parametres.html` l.89) — TLS / SSL / Aucune. */
    public const SECURITE_TLS = 'tls';

    public const SECURITE_SSL = 'ssl';

    public const SECURITE_AUCUNE = 'aucune';

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Superpose les clés SMTP de `parametres_systeme` à la configuration
     * d'exécution. Sans hôte paramétré, ne touche à rien.
     *
     * Le mot de passe n'est JAMAIS lu des paramètres : celui de `.env`
     * (`mail.mailers.smtp.password`) reste tel quel.
     */
    public function appliquer(): void
    {
        $hote = $this->parametres->get(self::CLE_SMTP_HOTE);

        if (blank($hote)) {
            return;
        }

        $port = $this->parametres->get(self::CLE_SMTP_PORT);
        $securite = $this->parametres->get(self::CLE_SMTP_SECURITE);
        $utilisateur = $this->parametres->get(self::CLE_SMTP_UTILISATEUR);

        config([
            'mail.default' => 'smtp',
            'mail.mailers.smtp.transport' => 'smtp',
            'mail.mailers.smtp.host' => $hote,
            'mail.mailers.smtp.port' => filled($port) ? (int) $port : 587,
            // Symfony Mailer : `smtps` chiffre la connexion entière (SSL) ;
            // en `smtp`, STARTTLS est négocié automatiquement quand le
            // serveur l'offre — « TLS » et « Aucune » partagent donc le même
            // schéma, la différence se joue à la négociation.
            'mail.mailers.smtp.scheme' => $securite === self::SECURITE_SSL ? 'smtps' : 'smtp',
            'mail.mailers.smtp.username' => filled($utilisateur) ? $utilisateur : null,
        ]);

        // Le gestionnaire de mail MÉMORISE un transport une fois construit :
        // sans purge, un mailer résolu avant cet appel continuerait d'envoyer
        // avec l'ancienne configuration — et l'écran confirmerait un réglage
        // que l'envoi n'emprunte pas (PA-59/60/61).
        Mail::purge('smtp');
    }

    public function estReelle(): bool
    {
        $this->appliquer();

        $mailer = config('mail.default');

        if (! is_string($mailer) || in_array($mailer, ['log', 'array', 'null'], true)) {
            return false;
        }

        /** @var array<string, mixed> $config */
        $config = config("mail.mailers.{$mailer}", []);

        if (($config['transport'] ?? $mailer) === 'smtp') {
            return filled($config['host'] ?? null);
        }

        // Un autre transport (ex. `ses`, `postmark`...) : sa seule présence en
        // configuration active suffit, `smtp` étant le seul de ce dépôt à
        // porter un hôte qui peut rester vide par défaut (voir .env.example).
        return true;
    }
}
