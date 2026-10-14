<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Accueil;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Support\BanniereEcriture;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le bandeau de la coquille dit le DROIT RÉEL — lot 0.6.
 *
 * ## Le bandeau qui mentait
 *
 * Jusqu'au 28/08/2026, les 37 pages affichaient en permanence « Cette
 * interface web sert à consulter. Toute saisie se fait depuis l'application
 * TATACORA. » — faux dès la première écriture, et faux sur l'écran même qui
 * porte le bouton « Ajouter fournisseur ». Ces cas empruntent RÉELLEMENT les
 * trois états (PA-59/60/61 : une garde déclarée ne dit rien de ce qu'elle
 * fait quand elle tourne) :
 *
 * - rôle `C` sur un écran qui écrit → AUCUN bandeau ;
 * - rôle sans `C` sur un écran qui écrit → le bandeau du maître
 *   (`shell.js` l.237-251), conditionné comme chez lui ;
 * - écran sans écriture → AUCUN bandeau (contrat inversé le 31/08/2026 sur
 *   relevé du Product Owner : l'ancien « Consultation pour l'instant — les
 *   saisies arrivent vague par vague » était un récit de feuille de route
 *   servi comme un état ; le maître n'affiche la bannière QUE si
 *   `TATACORA_LECTURE_SEULE` est posé, `shell.js` l.269).
 *
 * Et dans les TROIS états, le bloc `#shell-banniere` subsiste :
 * `ConformiteMaquettePwaTest` (l.150/156) fige la présence et l'ordre des
 * blocs de la coquille — le maître laisse la zone vide, il ne la retire pas.
 */
final class BannierePwaTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /**
     * La forme dans le HTML servi : Blade echappe les apostrophes des
     * libelles (`&#039;`). Comparer la forme BRUTE ferait passer a vide les
     * `assertStringNotContainsString` — la chaine brute n'apparait jamais,
     * meme quand le bandeau est rendu. Mesure sur ce fichier meme : le titre
     * « pour l'instant » a fait echouer la premiere execution.
     */
    private function echappe(string $texte): string
    {
        return htmlspecialchars($texte, ENT_QUOTES);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    // ------------------------------------------------------------ dérivation

    #[Test]
    public function l_etat_derive_du_droit_et_de_ce_que_l_ecran_offre(): void
    {
        $gerant = $this->utilisateur('gerant');        // M7 = C
        $comptable = $this->utilisateur('comptable');  // M7 = L

        // `Achats` offre l'écriture (trait + MODULE) : l'état suit le rôle.
        $this->assertSame(
            ['etat' => BanniereEcriture::AUCUNE, 'module' => 'M7'],
            BanniereEcriture::pour($gerant, Achats::class),
        );
        $this->assertSame(
            ['etat' => BanniereEcriture::LECTURE_SEULE, 'module' => 'M7'],
            BanniereEcriture::pour($comptable, Achats::class),
        );

        // ⚠ L'EXEMPLE « NON OUVERT » N'EST PLUS ÉCRIT EN DUR (31/08/2026).
        //
        // Ce cas nommait `Stocks` et `Accueil` : les deux écrivent désormais,
        // et il échouait sur un correctif. Un exemple figé vieillit — c'est le
        // défaut PA-144 transposé dans une garde. L'écran non ouvert est donc
        // CHOISI PAR RÉFLEXION sur le registre réel, à chaque exécution : la
        // liste suit la livraison au lieu de la contredire.
        $nonOuverts = $this->ecransSansEcriture();

        // Plancher : une liste vide rendrait la boucle vide, donc verte.
        $this->assertNotEmpty(
            $nonOuverts,
            'Plus aucun écran sans écriture : la boucle ci-dessous ne prouve plus rien.',
        );

        foreach ($nonOuverts as $composant) {
            // ## Contrat inversé le 31/08/2026, sur relevé du Product Owner
            //
            // Jusque-là, un écran sans écriture affichait « Consultation pour
            // l'instant — les saisies arrivent vague par vague » : un RÉCIT
            // DE FEUILLE DE ROUTE servi comme un état, à un gérant plein
            // droit, sur des écrans de consultation PAR NATURE (états M10,
            // clients M3). Le maître tranche : `shell.js` n'affiche la
            // bannière QUE si `TATACORA_LECTURE_SEULE` est posé (l.269) —
            // jamais pour un écran de consultation. Un écran sans écriture
            // n'affiche RIEN.
            $this->assertSame(
                BanniereEcriture::AUCUNE,
                BanniereEcriture::pour($gerant, $composant)['etat'],
                "{$composant} n'offre aucune écriture : le maître n'affiche RIEN là-dessus.",
            );
        }
    }

    /**
     * Les composants Livewire de la PWA qui n'offrent AUCUNE écriture.
     *
     * Dérivé, jamais recopié : `BanniereEcriture::pour()` lit exactement ces
     * deux traits — la constante `MODULE` et le trait `AutoriseEcriture` —, et
     * ce balayage les relit sur les mêmes classes.
     *
     * @return list<class-string>
     */
    private function ecransSansEcriture(): array
    {
        $racine = app_path('Pwa/Livewire');
        $fichiers = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));

        $sans = [];
        $relus = 0;

        foreach ($fichiers as $fichier) {
            if (! $fichier instanceof \SplFileInfo || $fichier->getExtension() !== 'php') {
                continue;
            }

            $relatif = substr($fichier->getPathname(), strlen($racine) + 1);
            $classe = 'App\\Pwa\\Livewire\\'
                .str_replace([DIRECTORY_SEPARATOR, '.php'], ['\\', ''], $relatif);

            if (! class_exists($classe)) {
                continue;
            }

            $reflexion = new \ReflectionClass($classe);

            if ($reflexion->isAbstract() || ! $reflexion->isSubclassOf(\Livewire\Component::class)) {
                continue;
            }

            $relus++;

            if (! in_array(\App\Pwa\Support\AutoriseEcriture::class, class_uses_recursive($classe), true)) {
                $sans[] = $classe;
            }
        }

        // Plancher de balayage : un répertoire renommé rendrait la liste vide
        // — donc verte au premier `assertNotEmpty` d'un jour malchanceux.
        $this->assertGreaterThanOrEqual(
            30,
            $relus,
            'Seuls '.$relus.' composants Livewire relus : le balayage est devenu creux.',
        );

        return $sans;
    }

    // ------------------------------------------------------------ rendu réel

    #[Test]
    public function un_role_qui_peut_ecrire_ne_voit_aucun_bandeau_mais_le_bloc_subsiste(): void
    {
        $this->actingAs($this->utilisateur('gerant'));

        $html = Livewire::test(Achats::class)->html();

        $this->assertStringContainsString('shell-banniere', $html);
        $this->assertStringNotContainsString($this->echappe(__('pwa.coquille.banniere_lecture_titre')), $html);
        $this->assertStringNotContainsString('Consultation pour l', $html);
    }

    #[Test]
    public function un_role_en_lecture_voit_le_bandeau_du_maitre_avec_son_bouton(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        $html = Livewire::test(Achats::class)->html();

        $this->assertStringContainsString('shell-banniere', $html);
        $this->assertStringContainsString($this->echappe(__('pwa.coquille.banniere_lecture_titre')), $html);
        // Le bouton du maître, avec son libellé exact (la flèche comprise).
        $this->assertStringContainsString('bouton-changer-compte-banniere', $html);
        $this->assertStringContainsString(
            $this->echappe(__('pwa.coquille.banniere_changer_profil')),
            $html,
        );
        // Et jamais les deux messages à la fois : deux vérités sur le même
        // écran, c'est le défaut de PA-121.
        $this->assertStringNotContainsString('Consultation pour l', $html);
    }

    #[Test]
    public function un_ecran_sans_ecriture_n_affiche_aucun_bandeau(): void
    {
        // ## Ce cas affirmait L'INVERSE jusqu'au 31/08/2026
        //
        // Il exigeait « Consultation pour l'instant — les saisies arrivent
        // vague par vague » sur `ClientsCreances`, même pour un gérant plein
        // droit. Le Product Owner l'a relevé à l'écran, et le maître le
        // confirme : `shell.js` n'affiche la bannière QUE si
        // `TATACORA_LECTURE_SEULE` est posé (l.269) — un écran de
        // consultation n'affiche rien. Le récit de feuille de route n'était
        // pas un état, et le servir comme tel disait au gérant qu'une
        // livraison manquait sur un écran de consultation PAR NATURE.
        $gerant = $this->utilisateur('gerant');

        // La prémisse, VÉRIFIÉE plutôt que supposée : le cas prouve bien
        // qu'un PLEIN DROIT ne voit rien — pas qu'un rôle refusé ne voit rien.
        $this->assertSame('C', $gerant->niveauSurModule(ClientsCreances::MODULE));

        $this->actingAs($gerant);

        $html = Livewire::test(ClientsCreances::class)->html();

        // La ZONE existe (l'ordre topbar → bannière → sidebar du maître est
        // structurel), mais elle est VIDE : ni récit, ni bouton, ni lecture
        // seule.
        $this->assertStringContainsString('shell-banniere', $html);
        $this->assertStringNotContainsString('Consultation pour l', $html);
        $this->assertStringNotContainsString($this->echappe(__('pwa.coquille.banniere_lecture_titre')), $html);
        $this->assertStringNotContainsString('bouton-changer-compte-banniere', $html);
    }

    #[Test]
    public function l_ancien_bandeau_permanent_n_existe_plus_nulle_part(): void
    {
        // La phrase du bandeau qui mentait ne doit revenir sur aucun état.
        $this->actingAs($this->utilisateur('gerant'));

        foreach ([Achats::class, ClientsCreances::class, Accueil::class] as $composant) {
            $this->assertStringNotContainsString(
                'Cette interface web sert à consulter',
                Livewire::test($composant)->html(),
                "L'ancien bandeau permanent est revenu sur {$composant}.",
            );
        }
    }
}
