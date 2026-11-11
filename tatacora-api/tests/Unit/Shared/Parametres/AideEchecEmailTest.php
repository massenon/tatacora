<?php

declare(strict_types=1);

namespace Tests\Unit\Shared\Parametres;

use App\Shared\Parametres\Services\AideEchecEmail;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * L'AIDE sous l'échec de « Envoyer un email de test » (09/11/2026) : une chaîne par cas,
 * celles du transport du SERVEUR (Symfony Mailer) comme celles du POSTE (client SMTP de
 * Dart) ; le message d'origine reste affiché tel quel, l'aide est une phrase FIXE.
 */
final class AideEchecEmailTest extends TestCase
{
    /** @return array<string, array{string, string|null}> */
    public static function messages(): array
    {
        return [
            // Le message EXACT obtenu par le PO sur le poste.
            'hôte introuvable (poste, message du PO)' => ["Serveur SMTP injoignable (connexion absente ?) : Failed host lookup: 'mail.logirestock.digitonpro.com'", 'hote'],
            'hôte introuvable (serveur, Symfony)' => ['Connection could not be established with host "mail.exemple.bj:587": stream_socket_client(): php_network_getaddresses: getaddrinfo for mail.exemple.bj failed: Name or service not known', 'hote'],
            'hôte introuvable (résolution)' => ['Temporary failure in name resolution', 'hote'],
            'hôte introuvable (poste, sans adresse)' => ['Serveur SMTP injoignable (connexion absente ?) : No address associated with hostname', 'hote'],
            'connexion refusée (serveur)' => ['Connection could not be established with host "mail.exemple.bj:465": stream_socket_client(): Unable to connect to ssl://mail.exemple.bj:465 (Connection refused)', 'connexion'],
            'connexion refusée (poste)' => ['Serveur SMTP injoignable (connexion absente ?) : Connection refused, errno = 111', 'connexion'],
            'délai dépassé (poste)' => ['Le serveur SMTP n’a pas répondu à temps (connexion absente ?).', 'connexion'],
            'délai dépassé (serveur)' => ['Connection to "mail.exemple.bj:587" timed out.', 'connexion'],
            'poignée de main SSL (mauvais port)' => ['HandshakeException: Handshake error in client (OS Error: WRONG_VERSION_NUMBER)', 'connexion'],
            'authentification refusée (serveur)' => ['Failed to authenticate on SMTP server with username "contact@exemple.bj" using the following authenticators: "LOGIN", "PLAIN". Authenticator "LOGIN" returned "Expected response code "235" but got code "535", with message "535 Incorrect authentication data".".', 'authentification'],
            'authentification refusée (poste)' => ['Le serveur SMTP a refusé les identifiants (utilisateur ou mot de passe SMTP).', 'authentification'],
            'message inconnu : pas d’aide devinée' => ['Envoi refusé par le serveur SMTP : 550 Mailbox full', null],
            'message vide' => ['', null],
        ];
    }

    #[Test]
    #[DataProvider('messages')]
    public function une_chaine_par_cas(string $message, ?string $cas): void
    {
        $this->assertSame($cas, AideEchecEmail::cas($message));
        $this->assertSame($cas === null ? null : __('pwa.parametres.email_test_aide_' . $cas), AideEchecEmail::pour($message));
    }

    #[Test]
    public function la_phrase_du_po_pour_un_nom_de_serveur_introuvable(): void
    {
        $aide = (string) AideEchecEmail::pour("Failed host lookup: 'mail.logirestock.digitonpro.com'");

        $this->assertStringStartsWith('Le nom du serveur de messagerie n\'existe pas ou n\'est pas joignable depuis ce poste.', $aide);
        $this->assertStringContainsString('cPanel > Comptes de messagerie > Configurer le client de messagerie', $aide);
        $this->assertStringContainsString('la connexion Internet du poste', $aide);
    }

    #[Test]
    public function la_connexion_dit_les_ports_et_les_chiffrements_l_authentification_dit_l_identifiant(): void
    {
        $this->assertStringContainsString('465', (string) AideEchecEmail::pour('Connection refused'));
        $this->assertStringContainsString('SSL', (string) AideEchecEmail::pour('Connection refused'));
        $this->assertStringContainsString('587', (string) AideEchecEmail::pour('Connection refused'));
        $this->assertStringContainsString('TLS', (string) AideEchecEmail::pour('Connection refused'));
        $this->assertStringContainsString('mot de passe', (string) AideEchecEmail::pour('Failed to authenticate'));
    }

    #[Test]
    public function l_aide_est_fixe_jamais_un_secret_ni_un_morceau_du_message(): void
    {
        $secret = 'M0t-de-passe-S3cret';
        $message = "Failed to authenticate on SMTP server with password \"{$secret}\" for 'contact@exemple.bj' (Failed host lookup)";

        foreach ([$message, "Connection refused {$secret}", "authentication {$secret}"] as $m) {
            $aide = (string) AideEchecEmail::pour($m);
            $this->assertNotSame('', $aide);
            $this->assertStringNotContainsString($secret, $aide);
            $this->assertStringNotContainsString('contact@exemple.bj', $aide);
        }

        // Aucune des trois phrases ne porte de paramètre à remplacer : ce sont des constantes.
        foreach (['hote', 'connexion', 'authentification'] as $cas) {
            $phrase = __('pwa.parametres.email_test_aide_' . $cas);
            $this->assertNotSame('pwa.parametres.email_test_aide_' . $cas, $phrase, 'clé de langue manquante');
            $this->assertSame(0, preg_match('/:[a-z_]+/', $phrase), $cas);
        }
    }

    #[Test]
    public function chaque_cas_a_sa_phrase_en_francais_distincte(): void
    {
        $phrases = array_map(static fn (string $c): string => __('pwa.parametres.email_test_aide_' . $c), ['hote', 'connexion', 'authentification']);

        $this->assertCount(3, array_unique($phrases));
        foreach ($phrases as $p) {
            $this->assertStringNotContainsString('email_test_aide', $p, 'clé de langue manquante');
        }
    }
}
