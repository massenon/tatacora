<?php

declare(strict_types=1);

namespace Tests\Feature\Securite;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les en-têtes de sécurité HTTP sont réellement POSÉS sur les réponses.
 *
 * ## Pourquoi ce fichier existe
 *
 * L'audit du 27/08/2026 a mesuré qu'**aucun** des cinq en-têtes n'était posé,
 * par aucun canal : ni middleware, ni `public/.htaccess`, ni balise `meta`.
 * Le middleware `EnTetesSecurite` comble ce manque.
 *
 * Mais un middleware **déclaré** n'est pas un middleware **branché** — c'est la
 * famille de défauts que ce dépôt traque depuis PA-59/60/61, et elle a une
 * forme précise ici : `bootstrap/app.php` peut cesser d'appeler `append()` lors
 * d'une fusion, sans qu'aucune erreur ne se produise. Les pages continueraient
 * de s'afficher, les 863 tests resteraient verts, et la PWA redeviendrait
 * clickjackable en silence.
 *
 * Ce fichier emprunte donc le chemin réel : il émet une requête HTTP et relit
 * les en-têtes de la réponse.
 *
 * ## Il éprouve les DEUX canaux
 *
 * Le middleware est global. Le vérifier sur la seule PWA laisserait l'API
 * découverte le jour où quelqu'un le déplacerait dans le groupe `web` —
 * changement plausible, et invisible autrement.
 */
final class EnTetesSecuriteTest extends TestCase
{
    /**
     * Les en-têtes exigés, avec leur valeur attendue.
     *
     * Figés ici DÉLIBÉRÉMENT, contrairement aux gardes de conformité qui
     * relisent le maître : il n'existe aucune source externe à relire pour une
     * politique de sécurité. La valeur est une décision, et ce tableau est
     * l'endroit où elle se discute.
     *
     * @return array<string, string>
     */
    private function enTetesAttendus(): array
    {
        return [
            'X-Frame-Options' => 'DENY',
            'X-Content-Type-Options' => 'nosniff',
            'Referrer-Policy' => 'same-origin',
            'Permissions-Policy' => 'camera=(), microphone=(), geolocation=()',
        ];
    }

    #[Test]
    public function la_pwa_porte_les_quatre_en_tetes_de_securite(): void
    {
        $reponse = $this->get(route('pwa.connexion'));

        $reponse->assertOk();

        foreach ($this->enTetesAttendus() as $entete => $valeur) {
            $reponse->assertHeader($entete, $valeur);
        }
    }

    #[Test]
    public function l_api_porte_les_memes_en_tetes_que_la_pwa(): void
    {
        // Une route d'API sans authentification : la réponse est un refus, et
        // c'est très bien — un refus est une réponse comme une autre, et elle
        // doit porter les mêmes en-têtes. Les vérifier sur le seul chemin
        // heureux laisserait les pages d'erreur découvertes, alors que ce sont
        // elles qui fuient le plus.
        $reponse = $this->postJson('/api/v1/login', []);

        foreach ($this->enTetesAttendus() as $entete => $valeur) {
            $reponse->assertHeader($entete, $valeur);
        }
    }

    #[Test]
    public function la_politique_de_contenu_est_posee_en_REPORT_ONLY(): void
    {
        $reponse = $this->get(route('pwa.connexion'));

        // ⚠ Ce cas fige l'état RÉEL, qui n'est pas encore une protection.
        // `Report-Only` mesure ce qu'une politique bloquerait ; il ne bloque
        // rien. L'affirmer autrement serait l'indicateur qui déclare un état
        // qu'il n'a pas vérifié.
        $reponse->assertHeader('Content-Security-Policy-Report-Only');

        $politique = $reponse->headers->get('Content-Security-Policy-Report-Only');

        $this->assertStringContainsString("default-src 'self'", $politique);
        $this->assertStringContainsString("frame-ancestors 'none'", $politique);
        $this->assertStringContainsString("object-src 'none'", $politique);

        // Et le mode BLOQUANT n'est pas encore posé. Le jour où il le sera, ce
        // cas rougira — c'est voulu : le passage de la mesure à la protection
        // est une décision, et elle doit être vue.
        $this->assertNull(
            $reponse->headers->get('Content-Security-Policy'),
            'Une CSP BLOQUANTE est apparue. Ce n est pas une regression, mais '
            .'ce n est pas non plus un detail : verifiez ecran par ecran que la '
            .'PWA fonctionne encore, puis mettez ce cas a jour. Une CSP trop '
            .'stricte ne degrade pas, elle casse en silence.',
        );
    }

    #[Test]
    public function HSTS_n_est_PAS_pose_sur_une_reponse_en_clair(): void
    {
        // Le poser sur HTTP est sans effet par la specification, mais surtout :
        // en developpement, il epinglerait `localhost` en HTTPS dans le
        // navigateur pour des mois. Ce cas verrouille la condition
        // `$request->secure()`, dont le retrait ne casserait rien de visible.
        $reponse = $this->get(route('pwa.connexion'));

        $this->assertNull($reponse->headers->get('Strict-Transport-Security'));
    }

    #[Test]
    public function le_cookie_de_session_est_SECURISE_par_defaut_hors_local(): void
    {
        // L'audit a mesure que `config/session.php` lisait
        // `env('SESSION_SECURE_COOKIE')` SANS defaut — donc `null` — et que la
        // variable n'existait ni dans `.env` ni dans `.env.example`. Le cookie
        // n'etait alors marque `Secure` que si Laravel detectait HTTPS, ce qui
        // echoue derriere un proxy cPanel non configure.
        //
        // Le defaut est desormais l'inverse. Ce cas verifie la REGLE, pas la
        // valeur courante : en `local` le cookie reste non securise, sans quoi
        // le developpement en HTTP cesserait de fonctionner.
        // (1) L'ETAT EFFECTIF ici. `phpunit.xml` l.21 pose `APP_ENV=testing`,
        //     et le client HTTP de PHPUnit parle en clair : un cookie `Secure`
        //     ne lui serait jamais renvoye.
        //
        //     ⚠ Ce cas n'est pas theorique. La premiere ecriture du defaut
        //     avait oublie `testing` : **21 tests sont tombes d'un coup**, tous
        //     ceux qui dependent d une session authentifiee, et le symptome se
        //     lisait comme un probleme d authentification.
        $this->assertFalse(
            config('session.secure'),
            'Le cookie de session est `Secure` en environnement de test : le '
            .'client HTTP de PHPUnit ne le renverra pas, et toute la suite '
            .'dependant d une session tombera sans que la cause se voie.',
        );

        // (2) LA REGLE, relue dans le fichier de configuration.
        //
        //     ⚠ La premiere version de ce cas ecrivait
        //     `assertTrue(env('SESSION_SECURE_COOKIE', 'production' !== 'local'))`.
        //     PHPStan l a signalee : une comparaison entre deux litteraux est
        //     TOUJOURS vraie, donc l assertion ne pouvait jamais echouer. Elle
        //     ne verifiait rien — piege 12 du depot, un predicat derive de
        //     lui-meme. Elle est remplacee, pas annotee.
        //
        //     On ancre sur une source EXTERIEURE : le fichier de configuration.
        //     Son defaut est evalue au chargement et ne peut pas etre
        //     re-resolu en memoire avec un autre `APP_ENV` — mais il peut etre
        //     relu.
        $source = file_get_contents(config_path('session.php'));
        $this->assertIsString($source);

        $this->assertStringNotContainsString(
            "'secure' => env('SESSION_SECURE_COOKIE'),",
            $source,
            'Le defaut vulnerable est revenu : sans second argument, `env()` '
            .'rend `null`, et Symfony ne marque alors le cookie `Secure` que '
            .'s il DETECTE HTTPS — detection qui echoue derriere un proxy '
            .'cPanel sans `TrustProxies`, absent de ce depot.',
        );

        foreach (['local', 'testing'] as $environnement) {
            $this->assertStringContainsString(
                "'".$environnement."'",
                $source,
                "L environnement `$environnement` a disparu de la liste des "
                .'exceptions au cookie securise.',
            );
        }
    }
}
