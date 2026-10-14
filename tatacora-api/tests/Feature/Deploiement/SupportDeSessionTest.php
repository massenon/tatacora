<?php

declare(strict_types=1);

namespace Tests\Feature\Deploiement;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le pilote de session déclaré POUR LA PRODUCTION doit avoir son support —
 * 06/09/2026, né d'une panne totale en ligne (PA-183).
 *
 * ## Le défaut, et pourquoi aucune suite ne pouvait le voir
 *
 * `.env.production.example` pose `SESSION_DRIVER=database`, le bon choix sur
 * un hébergement mutualisé. Mais la table `sessions` n'était créée par AUCUNE
 * migration : elle vit d'ordinaire dans `create_users_table`, remplacée ici
 * par `create_utilisateurs.php`, et elle est partie avec.
 *
 * En développement et en test, `SESSION_DRIVER=file` : les sessions vivent
 * sur le disque, la table n'est jamais lue, et 1 445 cas restaient verts.
 * Le défaut n'est apparu qu'à la première requête du premier visiteur en
 * ligne — avant toute page, avant toute authentification :
 *
 *   SQLSTATE[42S02] : Table 'digitonp_logirestock.sessions' doesn't exist
 *
 * Ce cas confronte donc le GABARIT DE PRODUCTION au SCHÉMA, deux fichiers que
 * rien ne reliait. Il ne dépend pas de la configuration de la suite : il lit
 * `.env.production.example` lui-même, parce que c'est ce fichier que
 * l'installateur copie sur le serveur.
 */
final class SupportDeSessionTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Les pilotes de session qui exigent une table, avec son nom.
     *
     * @var array<string, string>
     */
    private const TABLES_EXIGEES = ['database' => 'sessions'];

    #[Test]
    public function le_pilote_de_session_de_production_a_son_support_au_schema(): void
    {
        $gabarit = base_path('.env.production.example');

        $this->assertFileExists($gabarit, 'Le gabarit de production est introuvable : la procédure de déploiement le copie.');

        $contenu = (string) file_get_contents($gabarit);

        $this->assertSame(
            1,
            preg_match('/^SESSION_DRIVER=(.+)$/m', $contenu, $trouve),
            'Le gabarit de production ne déclare aucun SESSION_DRIVER : le serveur retomberait sur le défaut de config/session.php sans que personne ne l\'ait choisi.',
        );

        $pilote = trim($trouve[1]);
        $table = self::TABLES_EXIGEES[$pilote] ?? null;

        if ($table === null) {
            // Un pilote sans table (`file`, `cookie`, `array`) n'a rien à
            // prouver ici — mais le cas ne doit pas devenir vide en silence.
            $this->assertNotSame('', $pilote);

            return;
        }

        $this->assertTrue(
            Schema::hasTable($table),
            'Le gabarit de production pose SESSION_DRIVER='.$pilote.', qui lit la table « '.$table
                .' » — et aucune migration ne la crée. La PREMIÈRE requête du premier visiteur '
                .'echouerait en ligne, avant toute page (panne constatee le 06/09/2026).',
        );

        // Les colonnes que le gestionnaire de session de Laravel ecrit
        // reellement : une table presente mais amputee tomberait plus tard,
        // a l'ecriture, ce qui est pire qu'a la lecture.
        foreach (['id', 'user_id', 'ip_address', 'user_agent', 'payload', 'last_activity'] as $colonne) {
            $this->assertTrue(
                Schema::hasColumn($table, $colonne),
                'La table « '.$table.' » n\'a pas la colonne « '.$colonne.' » que Laravel y ecrit.',
            );
        }
    }
}
