<?php

declare(strict_types=1);

namespace Tests\Feature\Auth;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Permission;
use App\Shared\Rbac\Models\Role;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Authentification de l'API — le contrat que consomme le client Flutter.
 *
 * Ces tests existent parce que la route était **absente** : les 32 routes
 * protégées exigeaient un jeton qu'aucun code n'émettait. Ils figent donc le
 * contrat exact, pour qu'une régression le casse visiblement plutôt que de
 * rendre l'API silencieusement inaccessible.
 *
 * @see RG-15, RG-16
 */
final class ConnexionApiTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @param  array<string, string>  $droits  module => niveau ('C' ou 'L')
     */
    private function utilisateur(
        string $login = 'jkora',
        string $motDePasse = 'motdepasse123',
        string $statut = 'actif',
        array $droits = ['M1' => 'C', 'M6' => 'L'],
    ): User {
        $role = Role::create([
            'id' => (string) Str::uuid(),
            'libelle' => 'receptionniste',
        ]);

        foreach ($droits as $module => $niveau) {
            // Une seule action = lecture seule ; plusieurs = accès complet.
            // C'est la dérivation que `Role::niveauSurModule()` applique.
            $actions = $niveau === 'C' ? ['lire', 'creer', 'modifier'] : ['lire'];
            foreach ($actions as $action) {
                $permission = Permission::create([
                    'id' => (string) Str::uuid(),
                    'module' => $module,
                    'action' => $action,
                ]);
                $role->permissions()->attach($permission->id);
            }
        }

        return User::create([
            'id' => (string) Str::uuid(),
            'login' => $login,
            'mot_de_passe_hash' => Hash::make($motDePasse),
            'role_id' => $role->id,
            'statut' => $statut,
        ]);
    }

    /**
     * Prepare une requete authentifiee par jeton.
     *
     * `forgetGuards()` est indispensable : le `RequestGuard` de Sanctum
     * memorise l'utilisateur resolu, et sans cette remise a zero la deuxieme
     * requete d'un meme test reutiliserait la session de la premiere — un
     * jeton revoque paraitrait encore valide. En production le probleme
     * n'existe pas, chaque requete ayant son propre conteneur.
     */
    private function avecJeton(string $jeton): self
    {
        $this->app->make('auth')->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$jeton);
    }

    /**
     * 3e niveau du RBAC — « aucune donnee sensible renvoyee par une requete qui
     * contournerait la policy » (`00_MASTER_INSTRUCTIONS.md` §3.2, principe 2).
     *
     * Le hash est masque par `User::$hidden`. C'etait verifie par LECTURE du
     * modele, jamais par execution : or `$hidden` ne protege que la
     * serialisation Eloquent — un `response()->json($utilisateur->toArray())`
     * ecrit un jour sans y penser, ou un `attributesToArray()` sur une requete
     * brute, ne passerait pas par la. Ces tests parcourent les trois reponses
     * qui portent reellement un profil et verifient l'absence du hash dans le
     * CORPS BRUT, pas dans un tableau deja filtre.
     *
     * @see PA-68 — le 3e niveau etait respecte, mais rien ne l'aurait signale
     *              s'il avait cesse de l'etre
     */
    #[Test]
    public function aucune_reponse_d_authentification_ne_porte_le_hash(): void
    {
        $utilisateur = $this->utilisateur();

        $connexion = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ]);
        $connexion->assertOk();

        $jeton = (string) $connexion->json('token');
        $profil = $this->avecJeton($jeton)->getJson('/api/v1/utilisateur');
        $profil->assertOk();

        foreach ([$connexion, $profil] as $reponse) {
            $corps = $reponse->getContent();

            $this->assertIsString($corps);
            $this->assertStringNotContainsString('mot_de_passe', $corps);
            // Le hash lui-meme, au cas ou la cle serait renommee un jour.
            $this->assertStringNotContainsString(
                substr($utilisateur->mot_de_passe_hash, 0, 20),
                $corps,
            );
        }
    }

    /**
     * Le corollaire : le profil n'expose QUE des champs choisis.
     *
     * Une liste fermee plutot qu'une liste d'exclusions — c'est ce qui protege
     * d'une colonne sensible ajoutee au schema plus tard, que personne ne
     * penserait a masquer.
     */
    #[Test]
    public function le_profil_expose_une_liste_fermee_de_champs(): void
    {
        $this->utilisateur();

        $reponse = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ]);

        $this->assertSame(
            ['id', 'login', 'nom', 'role', 'droits'],
            array_keys((array) $reponse->json('utilisateur')),
        );
    }

    #[Test]
    public function la_connexion_emet_un_jeton_et_le_profil(): void
    {
        $this->utilisateur();

        $reponse = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
            'poste' => 'Tablette reception',
        ]);

        $reponse->assertOk()
            ->assertJsonStructure([
                'token',
                'utilisateur' => ['id', 'login', 'nom', 'role', 'droits'],
            ]);

        $this->assertNotEmpty($reponse->json('token'));
        $this->assertSame('receptionniste', $reponse->json('utilisateur.role'));
    }

    /**
     * Le contrat qui compte pour le client : **tous** les modules sont
     * présents, y compris ceux sans droit.
     *
     * Omettre un module laisserait le client décider quoi faire d'une clé
     * manquante, et un droit ne s'obtient jamais par omission.
     */
    #[Test]
    public function les_droits_couvrent_les_seize_modules_meme_sans_acces(): void
    {
        $this->utilisateur(droits: ['M1' => 'C']);

        $droits = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->json('utilisateur.droits');

        $this->assertCount(16, $droits);
        $this->assertSame('C', $droits['M1']);
        // M13 n'a jamais été accordé : il doit apparaître explicitement.
        $this->assertArrayHasKey('M13', $droits);
        $this->assertSame('-', $droits['M13']);
    }

    #[Test]
    public function un_mot_de_passe_faux_est_refuse(): void
    {
        $this->utilisateur();

        $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'mauvais',
        ])->assertStatus(401);
    }

    /**
     * Le message doit être **identique** pour un login inconnu et un mot de
     * passe faux : les distinguer indiquerait quels comptes existent.
     */
    #[Test]
    public function le_message_ne_revele_pas_si_le_compte_existe(): void
    {
        $this->utilisateur();

        $inconnu = $this->postJson('/api/v1/login', [
            'identifiant' => 'personne',
            'mot_de_passe' => 'motdepasse123',
        ]);

        $mauvaisMdp = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'mauvais',
        ]);

        $inconnu->assertStatus(401);
        $mauvaisMdp->assertStatus(401);
        $this->assertSame(
            $inconnu->json('message'),
            $mauvaisMdp->json('message'),
        );
    }

    #[Test]
    public function un_compte_desactive_est_refuse_malgre_le_bon_mot_de_passe(): void
    {
        $this->utilisateur(statut: 'suspendu');

        $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->assertStatus(403);
    }

    #[Test]
    public function cinq_echecs_declenchent_la_limitation_de_debit(): void
    {
        $this->utilisateur();

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/login', [
                'identifiant' => 'jkora',
                'mot_de_passe' => 'mauvais',
            ])->assertStatus(401);
        }

        // Le bon mot de passe est refusé lui aussi : le blocage porte sur le
        // couple (login + IP), pas sur la validité de la tentative.
        $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->assertStatus(429);

        RateLimiter::clear('connexion:jkora|127.0.0.1');
    }

    #[Test]
    public function le_jeton_emis_ouvre_les_routes_protegees(): void
    {
        $this->utilisateur();

        $jeton = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->json('token');

        $this->avecJeton($jeton)
            ->getJson('/api/v1/utilisateur')
            ->assertOk()
            ->assertJsonPath('login', 'jkora');
    }

    #[Test]
    public function sans_jeton_les_routes_protegees_sont_refusees(): void
    {
        $this->getJson('/api/v1/utilisateur')->assertStatus(401);
    }

    /**
     * La déconnexion révoque **le jeton courant seulement**.
     *
     * Révoquer tous les jetons déconnecterait l'utilisateur de ses autres
     * postes, ce qu'il n'a pas demandé.
     */
    #[Test]
    public function la_deconnexion_ne_revoque_que_le_jeton_courant(): void
    {
        $this->utilisateur();

        $identifiants = ['identifiant' => 'jkora', 'mot_de_passe' => 'motdepasse123'];
        $jetonA = $this->postJson('/api/v1/login', $identifiants + ['poste' => 'Poste A'])->json('token');
        $jetonB = $this->postJson('/api/v1/login', $identifiants + ['poste' => 'Poste B'])->json('token');

        $this->avecJeton($jetonA)
            ->postJson('/api/v1/logout')
            ->assertOk();

        $this->avecJeton($jetonA)
            ->getJson('/api/v1/utilisateur')
            ->assertStatus(401);

        // L'autre poste reste connecté.
        $this->avecJeton($jetonB)
            ->getJson('/api/v1/utilisateur')
            ->assertOk();
    }

    /**
     * Se reconnecter depuis le MÊME poste révoque le jeton précédent de ce
     * poste : un appareil perdu ne doit pas conserver un accès.
     */
    #[Test]
    public function une_reconnexion_du_meme_poste_revoque_le_jeton_precedent(): void
    {
        $this->utilisateur();

        $identifiants = [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
            'poste' => 'Tablette reception',
        ];

        $ancien = $this->postJson('/api/v1/login', $identifiants)->json('token');
        $nouveau = $this->postJson('/api/v1/login', $identifiants)->json('token');

        $this->assertNotSame($ancien, $nouveau);

        $this->avecJeton($ancien)
            ->getJson('/api/v1/utilisateur')
            ->assertStatus(401);

        $this->avecJeton($nouveau)
            ->getJson('/api/v1/utilisateur')
            ->assertOk();
    }

    #[Test]
    public function la_connexion_est_tracee_au_journal_daudit(): void
    {
        $utilisateur = $this->utilisateur();

        $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
            'poste' => 'Tablette reception',
        ])->assertOk();

        $this->assertDatabaseHas('journal_audit', [
            'action' => 'connexion',
            'entite_concernee' => 'utilisateurs',
            'entite_id' => $utilisateur->id,
        ]);
    }

    /**
     * Le journal d'audit est consultable : y déposer un secret le diffuserait.
     */
    #[Test]
    public function le_journal_ne_contient_ni_jeton_ni_mot_de_passe(): void
    {
        $this->utilisateur();

        $jeton = $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->json('token');

        $entrees = JournalAudit::query()->where('action', 'connexion')->get();
        $this->assertNotEmpty($entrees);

        foreach ($entrees as $entree) {
            $serialise = json_encode($entree->toArray(), JSON_THROW_ON_ERROR);
            $this->assertStringNotContainsString('motdepasse123', $serialise);
            $this->assertStringNotContainsString($jeton, $serialise);
        }
    }

    #[Test]
    public function la_derniere_connexion_est_horodatee(): void
    {
        $utilisateur = $this->utilisateur();
        $this->assertNull($utilisateur->derniere_connexion);

        $this->postJson('/api/v1/login', [
            'identifiant' => 'jkora',
            'mot_de_passe' => 'motdepasse123',
        ])->assertOk();

        $this->assertNotNull($utilisateur->fresh()?->derniere_connexion);
    }

    #[Test]
    public function les_champs_obligatoires_sont_valides(): void
    {
        $this->postJson('/api/v1/login', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['identifiant', 'mot_de_passe']);
    }
}
