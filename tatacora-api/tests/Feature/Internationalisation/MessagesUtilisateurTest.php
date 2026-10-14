<?php

declare(strict_types=1);

namespace Tests\Feature\Internationalisation;

use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Lang;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Internationalisation des messages utilisateur — 06_DEVELOPMENT_STANDARDS.md §4.4.
 *
 * ## Le défaut que cette suite existe pour empêcher
 *
 * Avant ce correctif, l'application n'avait **aucun répertoire `lang/`**. La
 * locale valait pourtant `fr`. Conséquence observée sur un appel réel à
 * `POST /api/v1/crm/clients` avec un corps vide :
 *
 * ```json
 * "nom":         ["Le nom du client est obligatoire."],   ← messages() du FormRequest
 * "type_client": ["validation.required"]                  ← la CLÉ BRUTE
 * ```
 *
 * Tout champ sans entrée explicite dans `messages()` renvoyait le nom de la
 * règle de validation au client Flutter. Aucun test ne l'avait vu : les suites
 * existantes assertent sur les *clés* d'erreur (`assertJsonValidationErrors`),
 * jamais sur le texte rendu. D'où les vérifications ci-dessous, qui portent
 * spécifiquement sur ce que l'utilisateur lit.
 */
final class MessagesUtilisateurTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // ------------------------------------------------------------ Validation

    /**
     * Le cas exact qui échouait : un champ sans message personnalisé.
     */
    #[Test]
    public function aucun_message_de_validation_ne_fuit_sa_cle_de_traduction(): void
    {
        $reponse = $this->actingAs($this->utilisateur('receptionniste'))
            ->postJson('/api/v1/crm/clients', []);

        $reponse->assertStatus(422);

        /** @var array<string, list<string>> $erreurs */
        $erreurs = $reponse->json('errors');
        $this->assertNotSame([], $erreurs);

        foreach ($erreurs as $champ => $messages) {
            foreach ($messages as $message) {
                $this->assertStringNotContainsString(
                    'validation.',
                    $message,
                    "Le champ « {$champ} » renvoie la clé de traduction brute au lieu du message : {$message}",
                );
            }
        }
    }

    /**
     * Le message agrégé de `message` était en anglais (« and 2 more errors »)
     * alors que le corps `errors` était en français.
     */
    #[Test]
    public function le_message_agrege_est_lui_aussi_en_francais(): void
    {
        $reponse = $this->actingAs($this->utilisateur('receptionniste'))
            ->postJson('/api/v1/crm/clients', []);

        $this->assertStringNotContainsString('more error', (string) $reponse->json('message'));
    }

    /**
     * Sans table `attributes`, un message générique affichait le nom technique
     * de la colonne (« Le champ date_depart... »).
     */
    #[Test]
    public function les_noms_de_champs_sont_lisibles_et_non_les_noms_de_colonnes(): void
    {
        $this->assertSame(
            'Le champ date de départ est obligatoire.',
            (string) __('validation.required', ['attribute' => __('validation.attributes.date_depart')]),
        );
    }

    // ------------------------------------------------ Exceptions métier

    #[Test]
    public function les_exceptions_metier_portent_un_message_resolu_par_traduction(): void
    {
        $rupture = new RuptureStockException(
            articleId: (string) Str::uuid(),
            pointId: (string) Str::uuid(),
            stockDisponible: '3.00',
            quantiteDemandee: '10.00',
        );

        // Les paramètres sont bien substitués : un « :disponible » résiduel
        // signalerait une clé mal nommée entre le fichier de langue et l'appel.
        $this->assertStringContainsString('3.00', $rupture->getMessage());
        $this->assertStringContainsString('10.00', $rupture->getMessage());
        $this->assertDoesNotMatchRegularExpression('#:[a-z_]+#', $rupture->getMessage());

        $recette = new RecetteManquanteException('Poulet DG');
        $this->assertStringContainsString('Poulet DG', $recette->getMessage());
        $this->assertStringNotContainsString(':plat', $recette->getMessage());
    }

    #[Test]
    public function le_refus_rbac_est_traduit_et_non_ecrit_en_dur(): void
    {
        // Le magasinier n'a aucun droit sur M3 (CRM).
        $reponse = $this->actingAs($this->utilisateur('magasinier'))
            ->getJson('/api/v1/crm/clients');

        $reponse->assertStatus(403);
        $this->assertSame(__('auth.module_refuse'), $reponse->json('message'));
    }

    // -------------------------------------------- Complétude des fichiers

    /**
     * Toutes les clés référencées par le code doivent exister. Une clé absente
     * ne lève aucune erreur en PHP : `__()` renvoie la clé elle-même, et le
     * défaut ne se voit qu'à l'écran de l'utilisateur.
     */
    #[Test]
    public function toutes_les_cles_appelees_par_le_code_existent_reellement(): void
    {
        $manquantes = [];

        foreach ($this->clesAppelees() as $cle => $fichiers) {
            // Clé construite dynamiquement (`'pwa.ecrans.' . $module`) : le
            // préfixe seul n'existe pas, c'est normal. Ces clés-là sont
            // vérifiées exhaustivement par le test suivant.
            if (str_ends_with($cle, '.')) {
                continue;
            }

            if (! Lang::has($cle)) {
                $manquantes[$cle] = $fichiers;
            }
        }

        $this->assertSame(
            [],
            $manquantes,
            'Clés de traduction appelées mais absentes de lang/fr/ : '
            . json_encode($manquantes, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        );
    }

    /**
     * Les libellés d'écrans PWA sont résolus par une clé construite au vol
     * (`pwa.ecrans.<module>`) : le test générique ne peut pas la voir. Un
     * module ajouté à la liste sans son libellé afficherait la clé brute à
     * l'écran d'accueil — c'est exactement ce qui est vérifié ici.
     */
    #[Test]
    public function chaque_ecran_expose_par_la_pwa_a_son_libelle_traduit(): void
    {
        foreach (\App\Pwa\Livewire\Accueil::ECRANS_AUTORISES as $module) {
            $this->assertTrue(
                Lang::has("pwa.ecrans.{$module}.libelle"),
                "L'écran {$module} est exposé par la PWA sans libellé traduit.",
            );
            $this->assertTrue(
                Lang::has("pwa.ecrans.{$module}.description"),
                "L'écran {$module} est exposé par la PWA sans description traduite.",
            );
        }
    }

    /**
     * Le garde-fou de non-régression : plus aucune chaîne française en dur
     * dans un `throw`, un `abort()` ou un `addError()`.
     *
     * Un accent est le marqueur retenu — imparfait mais suffisant : les
     * messages du domaine en contiennent tous au moins un, et aucun
     * identifiant technique (nom de classe, clé, colonne) n'en porte.
     */
    #[Test]
    public function aucune_chaine_francaise_ne_subsiste_dans_les_messages_leves(): void
    {
        $coupables = [];

        foreach ($this->fichiersPhpApplicatifs() as $fichier) {
            $contenu = (string) file_get_contents($fichier);

            // Retire commentaires et docblocks : ils sont en français par
            // exigence de projet et n'atteignent jamais l'utilisateur.
            $sansCommentaires = (string) preg_replace(
                ['#/\*.*?\*/#s', '#//[^\n]*#'],
                ' ',
                $contenu,
            );

            preg_match_all(
                '#(?:throw new [\\\\\w]+|abort|addError)\s*\(([^;]*?)\)\s*;#s',
                $sansCommentaires,
                $occurrences,
            );

            foreach ($occurrences[1] as $arguments) {
                if (preg_match('#[éèêàçùôûîï]#u', $arguments) === 1) {
                    $coupables[] = str_replace(base_path() . DIRECTORY_SEPARATOR, '', $fichier)
                        . ' → ' . trim(preg_replace('#\s+#', ' ', $arguments) ?? '');
                }
            }
        }

        $this->assertSame(
            [],
            $coupables,
            "Chaînes utilisateur écrites en dur (06 §4.4) :\n" . implode("\n", $coupables),
        );
    }

    // ------------------------------------------------------------- Helpers

    /**
     * Recense les appels `__('domaine.cle')` du code et des vues.
     *
     * @return array<string, list<string>> clé => fichiers qui l'appellent
     */
    private function clesAppelees(): array
    {
        $cles = [];

        foreach ([...$this->fichiersPhpApplicatifs(), ...$this->fichiersBlade()] as $fichier) {
            preg_match_all(
                "#__\(\s*'([a-z_]+\.[a-zA-Z0-9_.]+)'#",
                (string) file_get_contents($fichier),
                $occurrences,
            );

            foreach ($occurrences[1] as $cle) {
                $cles[$cle][] = str_replace(base_path() . DIRECTORY_SEPARATOR, '', $fichier);
            }
        }

        return $cles;
    }

    /**
     * @return list<string>
     */
    private function fichiersPhpApplicatifs(): array
    {
        return $this->fichiersSous(app_path(), 'php');
    }

    /**
     * @return list<string>
     */
    private function fichiersBlade(): array
    {
        return array_values(array_filter(
            $this->fichiersSous(resource_path('views'), 'php'),
            static fn (string $chemin): bool => str_ends_with($chemin, '.blade.php'),
        ));
    }

    /**
     * @return list<string>
     */
    private function fichiersSous(string $racine, string $extension): array
    {
        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
        );

        $fichiers = [];

        foreach ($iterateur as $fichier) {
            if ($fichier instanceof \SplFileInfo && $fichier->getExtension() === $extension) {
                $fichiers[] = $fichier->getPathname();
            }
        }

        return $fichiers;
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
