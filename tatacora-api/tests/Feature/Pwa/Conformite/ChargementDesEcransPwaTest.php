<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use ReflectionMethod;
use Tests\Feature\Pwa\Concerns\InventaireDesEcransPwa;
use Tests\Feature\Pwa\Concerns\SertLesEcransPwa;
use Tests\TestCase;

/**
 * G1 — « Chaque écran se charge vraiment », et chaque bouton désigne quelque
 * chose qui existe.
 *
 * ## Le défaut qui a rendu cette garde nécessaire
 *
 * Mesuré le 31/08/2026 : `GET /pwa/stocks` répond **500**.
 * `resources/views/pwa/stocks/stocks.blade.php` est une copie de
 * `inventaires.blade.php` et appelle `lancerInventaire`,
 * `cloturerEtRegulariser`, `definirPeriode` et `imprimerRapportInventairePdf`
 * — quatre méthodes qui n'existent nulle part sur le composant `Stocks`. Un
 * écran de module entier était donc hors service, sur un dépôt dont la suite
 * était verte, parce qu'aucun test n'avait jamais demandé cette URL.
 *
 * ## Deux contrôles, et pourquoi il en faut deux
 *
 * 1. **La route répond 200.** C'est le contrôle grossier, celui qui aurait
 *    suffi ici. Il ne dit rien de la page qu'il reçoit.
 * 2. **Chaque `wire:click` désigne une méthode publique déclarée.** C'est le
 *    contrôle qui vaut pour les écrans À VENIR : un bouton qui appelle une
 *    méthode absente ne casse pas le rendu, il casse le clic — et un clic
 *    cassé ne se voit qu'en cliquant. Livewire répond alors par une exception
 *    au moment de l'action, jamais au chargement.
 *
 * Le second contrôle lit DEUX sources et les réunit : le HTML servi (qui
 * porte les partiels et composants inclus) ET le source de la vue Blade. Le
 * source seul manquerait les inclusions ; le rendu seul serait aveugle sur
 * une page qui, comme `/pwa/stocks` aujourd'hui, ne se rend pas du tout —
 * c'est-à-dire précisément sur l'écran le plus atteint.
 *
 * ## Preuve que ces cas peuvent échouer
 *
 * **Mutation exécutée le 31/08/2026** — `str_starts_with($uri, 'pwa/')` a été
 * remplacé par `'zzz/'` dans `InventaireDesEcransPwa` : le balayage est tombé à
 * 1 écran et `le_balayage_rencontre_reellement_les_ecrans_de_la_pwa` a rougi
 * en nommant le chiffre. C'est le seul cas de cette classe qui soit VERT
 * aujourd'hui ; les deux autres échouent déjà sur des défauts réels, ce qui
 * est la même preuve obtenue sans rien casser.
 *
 * **Rouge de départ, reproduit :** `GET /pwa/stocks` → HTTP 500, et six
 * méthodes appelées par sa vue sont absentes du composant `Stocks`
 * (`lancerInventaire`, `cloturerEtRegulariser`, `definirPeriode`,
 * `definirPeriodicite`, `imprimerRapportInventairePdf`, `sauvegarderComptage`).
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md Article 3.3 (aucune entrée inerte)
 * @see docs/LARAVEL_PWA.md §1
 */
final class ChargementDesEcransPwaTest extends TestCase
{
    use InventaireDesEcransPwa;
    use RefreshDatabase;
    use SertLesEcransPwa;

    /**
     * Plancher : 44 routes GET sous `/pwa` mesurées le 31/08/2026. Un balayage
     * vide est vert — c'est le défaut arrivé trois fois dans ce dépôt (le plus
     * récent : PA-131, une garde qui sautait à chaque exécution sans rien
     * mesurer). Le plancher est délibérément sous le nombre mesuré : des
     * routes s'ajoutent, aucune ne doit disparaître en silence.
     */
    private const PLANCHER_ECRANS = 40;

    /**
     * Cinq URL que le balayage DOIT rencontrer. Le plancher seul ne protège
     * pas d'un filtre qui aurait dérivé : 40 routes d'un autre préfixe le
     * satisferaient. Ces cinq-là sont les écrans de module les plus exposés.
     *
     * @var list<string>
     */
    private const ECRANS_ATTENDUS = [
        'pwa/stocks',
        'pwa/achats',
        'pwa/facturation',
        'pwa/reservations',
        'pwa/vehicules',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function le_balayage_rencontre_reellement_les_ecrans_de_la_pwa(): void
    {
        $ecrans = $this->ecransPwa();
        $uris = array_column($ecrans, 'uri');

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_ECRANS,
            count($ecrans),
            'Le balayage des routes /pwa est retombe a '.count($ecrans).' ecrans '
            .'(plancher '.self::PLANCHER_ECRANS.', mesure 44 le 31/08/2026). '
            .'Un balayage vide est vert : c est ce que ce plancher refuse.',
        );

        foreach (self::ECRANS_ATTENDUS as $attendu) {
            $this->assertContains(
                $attendu,
                $uris,
                "L ecran {$attendu} n est plus atteint par le balayage. Soit la "
                .'route a disparu, soit le filtre de ce test a derive.',
            );
        }
    }

    /**
     * Toutes les routes `/pwa`, servies pour de vrai.
     *
     * Les routes `guest` (l'écran de connexion) sont demandées SANS session :
     * un Administrateur authentifié y serait redirigé, et compter cette
     * redirection comme un échec ferait rougir la garde sur un comportement
     * correct.
     */
    #[Test]
    public function chaque_ecran_pwa_repond_200(): void
    {
        $echecs = [];
        $servis = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $html = $this->htmlDe($ecran, $code);

            if ($html === null) {
                $echecs[] = "{$ecran['url']} → HTTP {$code} (".($ecran['composant'] ?? $ecran['vue'] ?? '?').')';

                continue;
            }

            $servis++;
        }

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_ECRANS - count($echecs),
            $servis + count($echecs),
            'Aucun ecran n a ete demande : le balayage est vide.',
        );

        $this->assertSame(
            [],
            $echecs,
            "Des ecrans de la PWA ne se chargent pas :\n  ".implode("\n  ", $echecs),
        );
    }

    /**
     * Chaque action liée dans une vue existe sur le composant qui la sert.
     *
     * Les actions magiques de Livewire (`$set`, `$toggle`, `$refresh`,
     * `$dispatch`, `$parent`…) sont exclues : elles ne sont pas des méthodes du
     * composant, et les inclure produirait un faux positif sur chaque page. De
     * même, une expression contenant `=` est une affectation de propriété, pas
     * un appel — Livewire l'accepte et il n'y a pas de méthode à trouver.
     */
    #[Test]
    public function chaque_action_liee_designe_une_methode_publique_du_composant(): void
    {
        $manquantes = [];
        $actionsRelues = 0;
        $composantsRelus = 0;

        foreach ($this->ecransPwa() as $ecran) {
            $composant = $ecran['composant'] ?? null;
            if (! is_string($composant) || ! class_exists($composant)) {
                continue;   // `Route::view` : aucune action Livewire a verifier.
            }

            $composantsRelus++;

            $sources = [];

            $html = $this->htmlDe($ecran, $code);
            if ($html !== null) {
                $sources[] = $html;
            }

            $fichierVue = $ecran['fichierVue'] ?? null;
            if (is_string($fichierVue) && is_file($fichierVue)) {
                $sources[] = (string) file_get_contents($fichierVue);
            }

            $publiques = $this->methodesPubliques($composant);

            // Les composants montés PAR LE LAYOUT ou IMBRIQUÉS dans la
            // barre supérieure apparaissent dans le HTML de chaque page avec
            // LEURS actions : elles se vérifient contre LEUR classe, jamais
            // contre le composant de la page. Liste FERMÉE — le verrou de
            // session (01/09/2026), puis la cloche d'alertes et la recherche
            // globale (audit PO du 01-02/09/2026) — chaque entrée réellement
            // relue par réflexion : une faute de frappe ne blanchirait rien.
            $publiquesDuChassis = array_merge(
                $this->methodesPubliques(\App\Pwa\Livewire\Transverse\VerrouSession::class),
                $this->methodesPubliques(\App\Pwa\Livewire\Transverse\ClocheNotifications::class),
                $this->methodesPubliques(\App\Pwa\Livewire\Transverse\RechercheGlobale::class),
                $this->methodesPubliques(\App\Pwa\Livewire\Transverse\AlertesOuvertureModales::class),
            );

            foreach ($this->actionsLiees(implode("\n", $sources)) as $action) {
                $actionsRelues++;

                if (in_array($action, $publiquesDuChassis, true)) {
                    continue;
                }

                if (! in_array($action, $publiques, true)) {
                    $manquantes[] = "{$ecran['url']} → wire:…=\"{$action}(…)\" absente de {$composant}";
                }
            }
        }

        // Planchers mesures le 31/08/2026 : 42 composants Livewire routes,
        // plusieurs centaines d actions liees. Sans eux, un `wire:click` dont
        // l ecriture aurait change (`wire:click.prevent`, apostrophes simples)
        // rendrait ce cas vert en ne relisant plus rien.
        $this->assertGreaterThanOrEqual(
            35,
            $composantsRelus,
            "Seuls {$composantsRelus} composants ont ete relus (plancher 35, mesure 42 le 31/08/2026).",
        );
        $this->assertGreaterThanOrEqual(
            120,
            $actionsRelues,
            "Seules {$actionsRelues} actions liees ont ete relues (plancher 120). "
            .'Le motif de lecture des attributs wire: ne mord plus.',
        );

        $manquantes = array_values(array_unique($manquantes));
        sort($manquantes);

        $this->assertSame(
            [],
            $manquantes,
            "Des boutons appellent une methode qui n existe pas — le clic levera "
            ."une exception, jamais le chargement :\n  ".implode("\n  ", $manquantes),
        );
    }

    // ------------------------------------------------------------------ outils

    /**
     * Les noms de méthode appelés par un attribut `wire:` d'action.
     *
     * @return list<string>
     */
    private function actionsLiees(string $source): array
    {
        $motif = '#wire:(?:click|submit|change|blur|keydown|keyup|mouseenter|dblclick)'
            .'(?:\.[A-Za-z0-9._-]+)*\s*=\s*"([^"]*)"#';

        if (preg_match_all($motif, $source, $trouves) < 1) {
            return [];
        }

        $actions = [];

        foreach ($trouves[1] as $expression) {
            $expression = trim($expression);

            if ($expression === '' || str_starts_with($expression, '$')) {
                continue;   // action magique Livewire
            }

            if (preg_match('#(?<![=!<>])=(?!=)#', $expression) === 1) {
                continue;   // affectation de propriete, pas un appel
            }

            if (preg_match('#^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|$)#', $expression, $nom) === 1) {
                $actions[] = $nom[1];
            }
        }

        return array_values(array_unique($actions));
    }

    /**
     * @return list<string>
     */
    private function methodesPubliques(string $composant): array
    {
        $noms = [];

        foreach ((new ReflectionClass($composant))->getMethods(ReflectionMethod::IS_PUBLIC) as $methode) {
            $noms[] = $methode->getName();
        }

        return $noms;
    }
}
