<?php

declare(strict_types=1);

namespace Tests\Feature\Parametres;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Rh\Services\CalculPaieService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le chemin d'écriture des paramètres — RG-10, et les deux gardes que l'audit
 * avait laissées ouvertes faute d'endroit où les poser (PA-61, PA-62).
 *
 * ## Ce que cette suite protège
 *
 * Trois choses, et aucune n'est une validation de formulaire ordinaire :
 *
 * 1. **Le registre est fermé.** Une clé inconnue ne se crée pas. C'est le seul
 *    empêchement à un `mecef_actif = true` que l'écran confirmerait et que
 *    personne ne lirait — la famille PA-59/60/61.
 * 2. **La cohérence porte sur l'état RÉSULTANT.** Activer la TVA et poser son
 *    taux dans le même envoi doit passer ; les deux sens de l'incohérence
 *    doivent être fermés.
 * 3. **Aucun secret ne peut entrer au registre**, y compris ajouté plus tard.
 */
final class EcritureParametresTest extends TestCase
{
    use RefreshDatabase;

    private User $administrateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->administrateur = $this->compteAvecRole(
            Role::where('libelle', 'administrateur')->firstOrFail(),
        );
    }

    /* ================================================================== */
    /* Le registre fermé                                                   */
    /* ================================================================== */

    #[Test]
    public function une_cle_hors_registre_est_refusee_et_n_est_pas_creee(): void
    {
        Sanctum::actingAs($this->administrateur);

        $this->putJson('/api/v1/parametres', [
            'parametres' => ['mecef_actif' => 'true'],
        ])->assertStatus(422)
            ->assertJsonValidationErrors('parametres.mecef_actif');

        // Le point du refus : la clé ne doit pas exister après coup. Un
        // paramètre que rien ne lit donnerait l'illusion d'un réglage.
        $this->assertDatabaseMissing('parametres_systeme', ['cle' => 'mecef_actif']);
    }

    #[Test]
    public function le_service_refuse_aussi_une_cle_inconnue_sans_passer_par_la_route(): void
    {
        // La garde vit dans le service, pas seulement dans la requête : un
        // futur appel depuis une commande Artisan ne passerait pas par le
        // FormRequest.
        $this->expectException(RuntimeException::class);

        app(EnregistrerParametreService::class)->enregistrer(['cle_inventee' => '1']);
    }

    #[Test]
    public function aucune_cle_du_registre_ne_ressemble_a_un_secret(): void
    {
        // Test STRUCTUREL : il relit le registre, il ne fige pas une liste.
        // Sans lui, la règle « les secrets vont en .env » tiendrait aujourd'hui
        // et céderait le jour où quelqu'un ajouterait une ligne au registre en
        // se disant qu'un seul écran de paramétrage est plus simple.
        foreach (RegistreParametres::cles() as $cle) {
            foreach (RegistreParametres::MOTIFS_SECRET as $motif) {
                $this->assertStringNotContainsString(
                    $motif,
                    $cle,
                    "La cle « {$cle} » ressemble a un secret : sa place est en configuration serveur.",
                );
            }
        }

        // Le plancher : un registre vidé rendrait la boucle vide, donc verte.
        $this->assertGreaterThanOrEqual(15, count(RegistreParametres::cles()));
    }

    #[Test]
    public function chaque_cle_du_registre_est_reellement_lue_par_le_code(): void
    {
        // Le pendant du test precedent : une cle declaree que rien ne consulte
        // est le meme defaut vu de l'autre cote — l'ecran l'afficherait, un
        // Administrateur la renseignerait, et elle ne servirait a rien.
        $source = collect(RegistreParametres::cles())->mapWithKeys(
            fn (string $cle): array => [$cle => false],
        )->all();

        $racine = dirname(__DIR__, 3) . DIRECTORY_SEPARATOR . 'app';
        $fichiers = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));

        foreach ($fichiers as $fichier) {
            if (! $fichier->isFile() || $fichier->getExtension() !== 'php') {
                continue;
            }

            // Le registre se cite lui-meme : l'exclure, sinon toute cle
            // s'y trouverait et le test serait vide.
            if (str_contains($fichier->getPathname(), 'Parametres' . DIRECTORY_SEPARATOR . 'Data')) {
                continue;
            }

            $contenu = (string) file_get_contents($fichier->getPathname());

            foreach (array_keys($source) as $cle) {
                if (str_contains($contenu, "'" . $cle . "'")) {
                    $source[$cle] = true;
                }

                // La correspondance des comptes (26/10/2026) : la cle
                // `compte_<role>` n'est jamais ecrite en litteral, elle se
                // DERIVE du role (`CorrespondanceComptesService::cle()`). Son
                // lecteur est le fichier qui nomme le ROLE en litteral —
                // hors les trois fichiers qui le DEFINISSENT (une sonde qui
                // compte ses propres definitions est verte a vide). Le
                // comportement de chaque role est prouve par
                // `CorrespondanceComptesTest` et par les tests de parite du poste.
                $role = \App\Domain\Comptabilite\Services\CorrespondanceComptesService::roleDeCle($cle);

                if ($role !== null
                    && ! str_ends_with($fichier->getPathname(), 'RolesCorrespondance.php')
                    && ! str_ends_with($fichier->getPathname(), 'ComptesSyscohada.php')
                    && str_contains($contenu, "'" . $role . "'")) {
                    $source[$cle] = true;
                }
            }
        }

        $orphelines = array_keys(array_filter($source, static fn (bool $trouvee): bool => ! $trouvee));

        $this->assertSame([], $orphelines, 'Cles declarees au registre que personne ne lit : '
            . implode(', ', $orphelines));
    }

    /* ================================================================== */
    /* La cohérence TVA — PA-62, dans les DEUX sens                        */
    /* ================================================================== */

    #[Test]
    public function activer_la_tva_sans_taux_est_refuse(): void
    {
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '');
        $this->poser(CalculTvaService::CLE_PARAMETRE_ACTIVE, 'false');

        $reponse = $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculTvaService::CLE_PARAMETRE_ACTIVE => true],
        ]);

        $reponse->assertStatus(422);
        // 422 et non 500 : le lot est refusé pour ce qu'il contient.
        $this->assertStringContainsString('taux', (string) $reponse->json('message'));

        // Rien n'a été écrit : le lot est refusé entier.
        $this->assertSame('false', $this->valeur(CalculTvaService::CLE_PARAMETRE_ACTIVE));
    }

    #[Test]
    public function vider_le_taux_pendant_que_la_tva_est_active_est_refuse_aussi(): void
    {
        // Le SECOND sens, absent de la note d'audit d'origine : il atteint
        // exactement le même état que le premier. Une garde qui ne ferme qu'un
        // des deux chemins ne ferme rien.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '18.00');
        $this->poser(CalculTvaService::CLE_PARAMETRE_ACTIVE, 'true');

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculTvaService::CLE_PARAMETRE_TAUX => null],
        ])->assertStatus(422);

        $this->assertSame('18.00', $this->valeur(CalculTvaService::CLE_PARAMETRE_TAUX));
    }

    #[Test]
    public function activer_la_tva_ET_poser_son_taux_dans_le_meme_envoi_est_accepte(): void
    {
        // Le cas qu'un contrôle clé par clé rendrait impossible : au moment où
        // `tva_active` serait examiné, le taux serait encore vide en base.
        // L'Administrateur devrait deviner qu'il faut deux enregistrements,
        // dans un ordre que rien ne lui indique.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '');
        $this->poser(CalculTvaService::CLE_PARAMETRE_ACTIVE, 'false');

        $this->putJson('/api/v1/parametres', [
            'parametres' => [
                CalculTvaService::CLE_PARAMETRE_ACTIVE => true,
                CalculTvaService::CLE_PARAMETRE_TAUX => '18',
            ],
        ])->assertOk();

        $this->assertSame('true', $this->valeur(CalculTvaService::CLE_PARAMETRE_ACTIVE));
        $this->assertSame('18', $this->valeur(CalculTvaService::CLE_PARAMETRE_TAUX));
    }

    #[Test]
    public function desactiver_la_tva_et_vider_son_taux_ensemble_reste_possible(): void
    {
        // La sortie doit rester ouverte : sinon un établissement qui cesse
        // d'être assujetti resterait coincé avec un taux qu'il ne peut plus
        // retirer.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '18.00');
        $this->poser(CalculTvaService::CLE_PARAMETRE_ACTIVE, 'true');

        $this->putJson('/api/v1/parametres', [
            'parametres' => [
                CalculTvaService::CLE_PARAMETRE_ACTIVE => false,
                CalculTvaService::CLE_PARAMETRE_TAUX => null,
            ],
        ])->assertOk();

        $this->assertSame('false', $this->valeur(CalculTvaService::CLE_PARAMETRE_ACTIVE));
        $this->assertSame('', $this->valeur(CalculTvaService::CLE_PARAMETRE_TAUX));
    }

    #[Test]
    public function une_convention_de_prix_hors_registre_est_refusee(): void
    {
        Sanctum::actingAs($this->administrateur);

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculTvaService::CLE_PARAMETRE_CONVENTION => 'htva'],
        ])->assertStatus(422);
    }

    /* ================================================================== */
    /* L'état lu est DÉRIVÉ                                                */
    /* ================================================================== */

    #[Test]
    public function la_lecture_rend_l_etat_derive_et_non_le_commutateur_brut(): void
    {
        // PA-61 : un écran qui composerait son badge depuis `tva_active`
        // afficherait « TVA active » pendant que chaque facture lèverait au
        // comptoir. L'incohérence doit se VOIR avant d'atteindre une vente.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_ACTIVE, 'true');
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '');

        $reponse = $this->getJson('/api/v1/parametres')->assertOk();

        $this->assertSame('activee_sans_taux', $reponse->json('data.etats.tva.code'));
    }

    #[Test]
    public function le_badge_mecef_ne_dit_jamais_actif_tant_que_le_client_reel_manque(): void
    {
        // PA-61 dans sa forme d'origine : la configuration complète ne rend pas
        // les factures certifiées tant que `MecefClient` n'existe pas.
        Sanctum::actingAs($this->administrateur);
        $this->poser(RegistreParametres::CLE_NUMERO_MECEF, '3202612345678');
        config(['services.mecef.api_key' => 'une-cle-presente']);

        $reponse = $this->getJson('/api/v1/parametres')->assertOk();

        $this->assertSame('en_attente_implementation', $reponse->json('data.etats.mecef.code'));
    }

    #[Test]
    public function la_lecture_n_expose_aucune_cle_d_api(): void
    {
        Sanctum::actingAs($this->administrateur);
        config(['services.mecef.api_key' => 'SECRET-A-NE-PAS-DIVULGUER']);

        $reponse = $this->getJson('/api/v1/parametres')->assertOk();

        $this->assertStringNotContainsString(
            'SECRET-A-NE-PAS-DIVULGUER',
            (string) $reponse->getContent(),
        );
    }

    /* ================================================================== */
    /* Traçabilité et écriture                                             */
    /* ================================================================== */

    #[Test]
    public function une_modification_laisse_l_ANCIENNE_valeur_au_journal(): void
    {
        // C'est l'ancienne valeur qu'on vient chercher après une erreur de
        // saisie sur un taux : « on revient à quoi ? ».
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculPaieService::CLE_VPS, '4.00');

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_VPS => '2.00'],
        ])->assertOk();

        $trace = JournalAudit::where('entite_concernee', 'parametres_systeme')
            ->where('action', 'modification')
            ->latest('date_heure')
            ->firstOrFail();

        $this->assertSame('4.00', $trace->valeur_avant['valeur'] ?? null);
        $this->assertSame('2.00', $trace->valeur_apres['valeur'] ?? null);
        $this->assertSame($this->administrateur->id, $trace->utilisateur_id);
    }

    #[Test]
    public function une_valeur_inchangee_n_ecrit_rien_au_journal(): void
    {
        // Eloquent déclenche `updating` même sur un modèle propre, et le trait
        // y pose `utilisateur_modification_id` — ce qui salit le modèle et fait
        // naître une trace pour une modification qui n'a pas eu lieu. Le vrai
        // changement se noierait dans le bruit.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculPaieService::CLE_VPS, '4.00');
        $avant = JournalAudit::where('entite_concernee', 'parametres_systeme')->count();

        $reponse = $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_VPS => '4.00'],
        ])->assertOk();

        $this->assertSame([], $reponse->json('data.modifiees'));
        $this->assertSame($avant, JournalAudit::where('entite_concernee', 'parametres_systeme')->count());
    }

    #[Test]
    public function le_taux_de_risques_professionnels_EST_modifiable(): void
    {
        // Et c'est le point (PA-53) : il est absent parce que le taux
        // hôtellerie n'est pas confirmé, pas parce qu'il serait interdit. Le
        // refuser ici signifierait qu'il ne peut arriver que par un seeder —
        // la voie exacte que PA-53 condamne.
        Sanctum::actingAs($this->administrateur);

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS => '2.5'],
        ])->assertOk();

        $this->assertSame('2.5', $this->valeur(CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS));
    }

    #[Test]
    public function un_taux_hors_bornes_reglementaires_est_refuse(): void
    {
        Sanctum::actingAs($this->administrateur);

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS => '9'],
        ])->assertStatus(422)
            ->assertJsonValidationErrors('parametres.' . CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS);
    }

    #[Test]
    public function un_taux_de_tva_non_numerique_est_refuse(): void
    {
        Sanctum::actingAs($this->administrateur);

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculTvaService::CLE_PARAMETRE_TAUX => 'dix-huit'],
        ])->assertStatus(422);
    }

    #[Test]
    public function un_booleen_est_stocke_sous_UNE_seule_forme(): void
    {
        // Sans normalisation, `true` (booléen JSON) deviendrait `"1"` alors que
        // le seeder écrit `"false"` : deux écritures de la même intention
        // donneraient deux contenus différents en base.
        Sanctum::actingAs($this->administrateur);
        $this->poser(CalculTvaService::CLE_PARAMETRE_TAUX, '18.00');

        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculTvaService::CLE_PARAMETRE_ACTIVE => true],
        ])->assertOk();

        $this->assertSame('true', $this->valeur(CalculTvaService::CLE_PARAMETRE_ACTIVE));
    }

    /* ================================================================== */
    /* RBAC — module PARAM                                                 */
    /* ================================================================== */

    #[Test]
    public function un_role_sans_acces_ne_lit_pas_les_parametres(): void
    {
        $sansAcces = Role::all()->first(
            fn (Role $r): bool => $r->niveauSurModule('PARAM') === '-',
        );
        $this->assertNotNull($sansAcces, 'Aucun role sans acces a PARAM dans la matrice.');

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/parametres')->assertForbidden();
    }

    #[Test]
    public function un_role_en_lecture_seule_consulte_mais_n_ecrit_pas(): void
    {
        // Le Gérant a `L` sur PARAM : il doit voir les taux appliqués sans
        // pouvoir les changer. Le masquage d'interface ne protège rien.
        $lecteur = Role::all()->first(
            fn (Role $r): bool => $r->niveauSurModule('PARAM') === 'L',
        );
        $this->assertNotNull($lecteur, 'Aucun role en lecture seule sur PARAM dans la matrice.');

        Sanctum::actingAs($this->compteAvecRole($lecteur));

        $this->getJson('/api/v1/parametres')->assertOk();
        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_VPS => '9.99'],
        ])->assertForbidden();
    }

    #[Test]
    public function sans_jeton_l_ecriture_est_refusee(): void
    {
        $this->putJson('/api/v1/parametres', [
            'parametres' => [CalculPaieService::CLE_VPS => '9.99'],
        ])->assertUnauthorized();
    }

    /* ================================================================== */

    private function poser(string $cle, string $valeur): void
    {
        ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
    }

    private function valeur(string $cle): ?string
    {
        return ParametreSysteme::where('cle', $cle)->value('valeur');
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}
