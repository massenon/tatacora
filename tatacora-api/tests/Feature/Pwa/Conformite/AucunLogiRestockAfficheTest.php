<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « LogiRestock » n'est plus AFFICHE nulle part — decision du Product Owner du
 * 13/10/2026 (PA-208, ticket D385), qui etend aux ecrans de demarrage, de
 * connexion et d'aide le remplacement deja fait sur la barre superieure (D373) :
 * « faut remplacer logiRestock par systeme d'information integre ».
 *
 * SECONDE DECISION DU PO DU 13/10/2026 (PA-209, ticket D389) : « remplace
 * [...] Systeme d'Information Integre [...] -> Systeme de gestion Integre,
 * remplace system d'information par system de gestion ». La mention retenue
 * est donc « Système de gestion Intégré » (casse EXACTE du PO), et l'ancienne
 * formule est refusee comme l'ancien nom — quelle que soit sa casse, ses
 * accents ou son apostrophe (droite ou typographique).
 *
 * LogiRestock est le nom d'un autre produit. La garde porte sur ce qui est
 * RENDU (pages servies, chaines de langue resolues, en-tete des etats), jamais
 * sur les commentaires : un commentaire qui raconte l'historique de la decision
 * n'est pas un affichage. Elle relit aussi la VUE (quelle cle chaque ecran
 * rend) : le client Flutter suit ces cles, et une vue qui se remettrait a
 * ecrire la mention en dur echapperait a la seule relecture des langues.
 *
 * MISE A JOUR DU 26/10/2026 (PO) : le nom COMMERCIAL de l'application est
 * « LogiReStock » (S majuscule) et l'onglet du navigateur dit « <page> —
 * LogiReStock — TATACORA AFRIQUE ». La garde reste exacte sur l'ancienne
 * ORTHOGRAPHE « LogiRestock » (comparaison sensible a la casse) : c'est le nom
 * d'un autre produit, et c'est lui qui ne doit jamais s'afficher.
 *
 * Hors perimetre, laisses deliberement : `.env.production.example` (domaine de
 * deploiement), `docs/DEPLOIEMENT_LOGIRESTOCK.md` et les documents
 * historiques — aucun n'est affiche par la PWA.
 */
final class AucunLogiRestockAfficheTest extends TestCase
{
    use RefreshDatabase;

    private const NOM_RETIRE = 'LogiRestock';

    /**
     * L'ancienne mention (PA-209) : « Système d'Information » sous toutes ses
     * graphies — casse, accent du « è », apostrophe droite ou typographique.
     */
    private const MENTION_RETIREE = "/syst[eèÈE]me\\s+d['\u{2019}]\\s*information/iu";

    private const MENTION_RETENUE = 'Système de gestion Intégré';

    /** Plancher mesure le 13/10/2026 : plus de 4 000 chaines resolues. */
    private const PLANCHER_CHAINES = 1000;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function les_trois_ecrans_rendent_la_mention_retenue_et_jamais_l_ancien_nom(): void
    {
        $demarrage = (string) $this->get('/pwa/demarrage')->assertOk()->getContent();
        $connexion = (string) $this->get('/pwa/connexion')->assertOk()->getContent();

        $this->actingAs($this->administrateur());
        // L'aide est servie dans la coquille : sa barre superieure rend aussi
        // la ligne de localisation (D373).
        $aide = (string) $this->get('/pwa/aide-a-propos')->assertOk()->getContent();

        foreach (['demarrage' => $demarrage, 'connexion' => $connexion, 'aide' => $aide] as $ecran => $html) {
            $this->assertStringNotContainsString(self::NOM_RETIRE, $html, "L'ecran {$ecran} affiche encore l'ancien nom.");
            // Le navigateur recoit l'apostrophe echappee par `{{ }}` : la
            // garde lit le texte decode, sinon `&#039;` la rendrait aveugle.
            $this->assertDoesNotMatchRegularExpression(
                self::MENTION_RETIREE,
                html_entity_decode($html, ENT_QUOTES | ENT_HTML5, 'UTF-8'),
                "L'ecran {$ecran} affiche encore « Système d'Information » (PA-209).",
            );
        }

        // Les nouvelles phrases, telles que le navigateur les recoit.
        // Decision PO du 14/10/2026 : la mention sous la marque.
        $this->assertStringContainsString(e('Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)'), $demarrage);
        $this->assertStringContainsString(e('Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)'), $aide);
        // Refonte du 29/10/2026 : la connexion n'a plus de panneau portant la
        // mention ; son onglet est « Connexion — LogiReStock ».
        $this->assertStringContainsString(
            '<title>'.e('Connexion — LogiReStock').'</title>',
            $connexion,
        );
        $this->assertStringContainsString(e('Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)'), $aide);
    }

    #[Test]
    public function chaque_vue_rend_la_cle_retenue_et_les_cles_disent_la_phrase_retenue(): void
    {
        $vues = [
            'pwa/demarrage' => "{{ __('rapports.entete.localisation') }}",
            'pwa/partials/barre-superieure' => "{{ __('pwa.barre_localisation') }}",
            'pwa/transverse/aide-a-propos' => "{{ __('pwa.aide.enseigne') }}",
        ];
        foreach ($vues as $vue => $rendu) {
            $source = $this->sansCommentairesBlade($vue);
            $this->assertStringContainsString($rendu, $source, "La vue {$vue} ne rend plus la cle attendue.");
            $this->assertStringNotContainsString(self::NOM_RETIRE, $source, "La vue {$vue} ecrit l'ancien nom en dur.");
            $this->assertDoesNotMatchRegularExpression(self::MENTION_RETIREE, $source, "La vue {$vue} ecrit l'ancienne mention en dur.");
        }

        // La cle dediee du demarrage est retiree : une seconde cle de meme
        // valeur divergerait a la premiere retouche (meme raison que D373).
        $this->assertSame('pwa.demarrage.localisation', __('pwa.demarrage.localisation'));

        $this->assertSame('Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)', __('rapports.entete.localisation'));
        $this->assertSame('Connexion — LogiReStock', __('pwa.connexion.titre_page'));
        $this->assertSame('Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)', __('pwa.aide.enseigne'));
    }

    /**
     * L'en-tete des etats (PDF, CSV) imprime la meme cle : le papier dit la
     * mention retenue, jamais l'ancienne (PA-209).
     */
    #[Test]
    public function l_en_tete_des_etats_imprime_la_mention_retenue(): void
    {
        $entete = app(ReportHeaderService::class)->genererEnTete('Essai', 'Periode', null);

        $this->assertStringContainsString(self::MENTION_RETENUE, $entete->sousTitre);
        $this->assertDoesNotMatchRegularExpression(self::MENTION_RETIREE, $entete->sousTitre);
    }

    /**
     * Le manifeste est AFFICHE par le navigateur (fenetre d'installation de
     * l'application web) : sa description suit la meme decision (PA-209).
     */
    #[Test]
    public function le_manifeste_de_l_application_web_ne_porte_pas_l_ancienne_mention(): void
    {
        $manifeste = json_decode((string) file_get_contents(public_path('manifest.json')), true, flags: JSON_THROW_ON_ERROR);
        $this->assertIsArray($manifeste);
        $this->assertIsString($manifeste['description'] ?? null);

        foreach (['name', 'short_name', 'description'] as $champ) {
            $valeur = (string) ($manifeste[$champ] ?? '');
            $this->assertStringNotContainsString(self::NOM_RETIRE, $valeur);
            $this->assertDoesNotMatchRegularExpression(self::MENTION_RETIREE, $valeur, "manifest.json#{$champ}");
        }
        $this->assertStringContainsString('systeme de gestion', $manifeste['description']);
    }

    #[Test]
    public function aucune_chaine_de_langue_resolue_ne_porte_l_ancien_nom(): void
    {
        $fautives = [];
        $relues = 0;

        foreach (glob(lang_path('fr/*.php')) ?: [] as $fichier) {
            $domaine = basename($fichier, '.php');
            $valeurs = require $fichier;
            if (! is_array($valeurs)) {
                continue;
            }
            array_walk_recursive($valeurs, function (mixed $valeur, int|string $cle) use (&$fautives, &$relues, $domaine): void {
                if (! is_string($valeur)) {
                    return;
                }
                $relues++;
                if (str_contains($valeur, self::NOM_RETIRE) || preg_match(self::MENTION_RETIREE, $valeur) === 1) {
                    $fautives[] = "{$domaine}.…{$cle} : « {$valeur} »";
                }
            });
        }

        $this->assertGreaterThanOrEqual(self::PLANCHER_CHAINES, $relues, 'Balayage des langues vide.');
        $this->assertSame([], $fautives, "Des chaines de langue affichent encore l'ancien nom ou l'ancienne mention :\n  ".implode("\n  ", $fautives));
    }

    #[Test]
    public function le_motif_de_l_ancienne_mention_reconnait_toutes_ses_graphies(): void
    {
        // Preuve que la garde n'est pas vide : chaque graphie connue mord, et
        // la mention retenue ne mord pas.
        foreach ([
            "Système d'Information Intégré",
            'Système d’Information Intégré',
            "système d'information intégré",
            "Systeme d'information",
            "SYSTÈME D'INFORMATION",
        ] as $graphie) {
            $this->assertMatchesRegularExpression(self::MENTION_RETIREE, $graphie, "Graphie non reconnue : {$graphie}");
        }
        $this->assertDoesNotMatchRegularExpression(self::MENTION_RETIREE, self::MENTION_RETENUE);
    }

    private function sansCommentairesBlade(string $vue): string
    {
        $chemin = resource_path('views/'.$vue.'.blade.php');
        $this->assertFileExists($chemin);

        return (string) preg_replace('/\{\{--.*?--\}\}/s', '', (string) file_get_contents($chemin));
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'administrateur.logirestock',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
