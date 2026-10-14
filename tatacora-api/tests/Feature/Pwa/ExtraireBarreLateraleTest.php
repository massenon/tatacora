<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use DOMDocument;
use DOMElement;
use DOMXPath;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * GENERATEUR (pas une garde) de la structure RENDUE de la barre laterale —
 * Phase 1B de `docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md`.
 *
 * Pour chacun des onze roles : connexion, rendu d'une page, releve de
 * `#sidebar nav` dans l'ordre (entrees epinglees, titres de groupe, entrees,
 * badges), plus l'etat ACTIF (une page par entree pour l'administrateur) et
 * la partition des ICONES (quelles entrees partagent le meme trace). Le
 * client Flutter confronte son rendu a ce releve
 * (`test/core/qualite/barre_laterale_blade_test.dart`).
 *
 * Il ne tourne que si `STRUCTURE_BLADE_SORTIE` designe un dossier.
 *
 * @see RG-16 RBAC a trois niveaux (masquage d'interface)
 */
final class ExtraireBarreLateraleTest extends TestCase
{
    use RefreshDatabase;

    private const MODULES = [
        'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7',
        'M8', 'M9', 'M10', 'M11', 'M12', 'M13', 'M14',
        'ROLES', 'PARAM',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function extraire_la_barre_laterale_de_chaque_role(): void
    {
        $sortie = getenv('STRUCTURE_BLADE_SORTIE');

        if ($sortie === false || $sortie === '') {
            $this->markTestSkipped('Generateur : definir STRUCTURE_BLADE_SORTIE pour ecrire les structures.');
        }

        if (! is_dir($sortie)) {
            mkdir($sortie, 0777, true);
        }

        $roles = Role::query()->orderBy('libelle')->pluck('libelle')->all();
        $this->assertGreaterThanOrEqual(11, count($roles), 'Les onze roles du seeder sont attendus.');

        $resultat = [];

        foreach ($roles as $role) {
            $utilisateur = User::create([
                'login' => 'barre.'.$role,
                'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
                'statut' => 'actif',
            ]);
            $this->actingAs($utilisateur);

            $droits = [];
            foreach (self::MODULES as $module) {
                $droits[$module] = $utilisateur->niveauSurModule($module);
            }

            $html = $this->pageAccessible();

            $resultat[$role] = [
                'droits' => $droits,
                'barre' => $this->releverBarre($html),
            ];
        }

        // L'ETAT ACTIF : l'administrateur parcourt une page par entree.
        $this->actingAs(User::where('login', 'barre.administrateur')->firstOrFail());
        $actif = [];
        foreach ($resultat['administrateur']['barre']['entrees'] as $entree) {
            if (($entree['href'] ?? null) === null) {
                continue;
            }
            $reponse = $this->get($entree['href']);
            if ($reponse->status() !== 200) {
                continue;
            }
            $barre = $this->releverBarre((string) $reponse->getContent());
            $actives = array_values(array_map(
                static fn (array $e): string => $e['nom'],
                array_filter($barre['entrees'], static fn (array $e): bool => $e['actif'] === true),
            ));
            $actif[$entree['nom']] = $actives;
        }

        $this->assertNotEmpty($actif, 'Aucune page n\'a pu etre parcourue : l\'extraction est cassee.');

        file_put_contents(
            rtrim($sortie, '/\\').'/barre-laterale.json',
            json_encode([
                '_lisez-moi' => 'PRODUIT par ExtraireBarreLateraleTest, jamais ecrit a la main. '
                    .'Par role : droits (16 modules) et barre laterale rendue. `actif` : pour chaque '
                    .'entree visitee par l\'administrateur, les entrees allumees.',
                'roles' => $resultat,
                'actif' => $actif,
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)."\n",
        );
    }

    /** Une page que tout role authentifie peut voir : on essaie dans l'ordre. */
    private function pageAccessible(): string
    {
        foreach (['/pwa/mon-profil', '/pwa/aide', '/pwa/', '/pwa/reservations', '/pwa/hebergement'] as $url) {
            $reponse = $this->get($url);

            if ($reponse->status() === 200 && str_contains((string) $reponse->getContent(), 'id="sidebar"')) {
                return (string) $reponse->getContent();
            }
        }

        $this->fail('Aucune page ne rend la barre laterale pour ce role.');
    }

    /**
     * @return array{entrees: list<array<string, mixed>>, pied: array<string, string>}
     */
    private function releverBarre(string $html): array
    {
        $dom = new DOMDocument();
        libxml_use_internal_errors(true);
        $dom->loadHTML('<?xml encoding="UTF-8">'.$html);
        libxml_clear_errors();

        $xpath = new DOMXPath($dom);
        $nav = $xpath->query('//*[@id="sidebar"]//nav')->item(0);
        $this->assertInstanceOf(DOMElement::class, $nav, 'La barre laterale doit porter un <nav>.');

        $entrees = [];
        $groupeCourant = null;

        foreach ($nav->childNodes as $noeud) {
            if (! $noeud instanceof DOMElement) {
                continue;
            }

            $balise = strtolower($noeud->tagName);
            $classes = ' '.preg_replace('/\s+/', ' ', $noeud->getAttribute('class')).' ';

            if ($balise === 'p') {
                $groupeCourant = trim($noeud->textContent);
                $entrees[] = ['type' => 'groupe', 'nom' => $groupeCourant, 'actif' => false];

                continue;
            }

            $epingle = $balise === 'div' && str_contains($classes, ' epingle ');
            $lien = $epingle
                ? $xpath->query('.//*[contains(concat(" ", normalize-space(@class), " "), " lien-sidebar ")]', $noeud)->item(0)
                : (str_contains($classes, ' lien-sidebar ') ? $noeud : null);

            if (! $lien instanceof DOMElement) {
                continue;
            }

            $spans = $xpath->query('./span', $lien);
            $nom = $spans->length > 0 ? trim($spans->item(0)->textContent) : '';
            $badge = $spans->length > 1 ? trim($spans->item(1)->textContent) : null;
            $trace = $xpath->query('./svg', $lien)->item(0)?->C14N() ?? '';
            $href = $lien->getAttribute('href');

            $entrees[] = [
                'type' => $epingle ? 'epingle' : 'entree',
                'groupe' => $epingle ? null : $groupeCourant,
                'nom' => $nom,
                'badge' => $badge,
                'actif' => str_contains(' '.$lien->getAttribute('class').' ', ' actif '),
                'cliquable' => strtolower($lien->tagName) === 'a',
                'href' => $href === '' ? null : parse_url($href, PHP_URL_PATH),
                'icone' => substr(md5($trace), 0, 8),
            ];
        }

        $pied = [];
        $lignes = $xpath->query('//*[@id="sidebar"]//div[contains(@class,"border-t")]//p');
        foreach ($lignes as $p) {
            $pied[] = trim($p->textContent);
        }
        $bouton = $xpath->query('//*[@id="bouton-deconnexion-sidebar"]')->item(0);

        return [
            'entrees' => $entrees,
            'pied' => [
                'lignes' => $pied,
                'deconnexion' => $bouton ? trim(preg_replace('/\s+/', ' ', $bouton->textContent)) : '',
            ],
        ];
    }
}
