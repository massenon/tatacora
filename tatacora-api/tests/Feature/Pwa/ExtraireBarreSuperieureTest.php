<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use DOMDocument;
use DOMElement;
use DOMNode;
use DOMXPath;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * GENERATEUR (pas une garde) de la structure RENDUE de la barre SUPERIEURE —
 * Phase 1C de `docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md`.
 *
 * Pour chacun des roles, trois variantes du bloc `<header>` :
 *  - `barre`        : ce qui se voit en permanence ;
 *  - `menu-profil`  : le menu de compte ouvert (`#menu-profil`, masque par
 *                     defaut et ouvert par script) ;
 *  - `cloche`       : le panneau de notifications ouvert (`#menu-notifications`).
 *
 * Chaque variante est la liste ORDONNEE des textes visibles, des info-bulles
 * (`title`, `aria-label`) et des invites de champ. Le client Flutter confronte
 * son rendu dans `test/core/qualite/barre_superieure_blade_test.dart`.
 *
 * Il ne tourne que si `STRUCTURE_BLADE_SORTIE` designe un dossier.
 */
final class ExtraireBarreSuperieureTest extends TestCase
{
    use RefreshDatabase;

    /** Identifiant du panneau masque a montrer, par variante. */
    private const VARIANTES = [
        'barre' => null,
        'menu-profil' => 'menu-profil',
        'cloche' => 'menu-notifications',
    ];

    private ?string $panneauMontre = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function extraire_la_barre_superieure_de_chaque_role(): void
    {
        $sortie = getenv('STRUCTURE_BLADE_SORTIE');

        if ($sortie === false || $sortie === '') {
            $this->markTestSkipped('Generateur : definir STRUCTURE_BLADE_SORTIE pour ecrire les structures.');
        }

        if (! is_dir($sortie)) {
            mkdir($sortie, 0777, true);
        }

        $resultat = [];

        foreach (Role::query()->orderBy('libelle')->pluck('libelle')->all() as $role) {
            $utilisateur = User::create([
                'login' => 'barre.'.$role,
                'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
                'statut' => 'actif',
            ]);
            $this->actingAs($utilisateur);

            $html = $this->pageAccessible();

            foreach (self::VARIANTES as $variante => $panneau) {
                $this->panneauMontre = $panneau;
                $elements = $this->releverEntete($html);
                $this->assertNotEmpty($elements, "Barre superieure vide ({$role}/{$variante}).");
                $resultat[$role][$variante] = $elements;
            }
        }

        file_put_contents(
            rtrim($sortie, '/\\').'/barre-superieure.json',
            json_encode([
                '_lisez-moi' => 'PRODUIT par ExtraireBarreSuperieureTest, jamais ecrit a la main. '
                    .'Par role et variante (barre, menu-profil, cloche) : textes, info-bulles et '
                    .'invites du <header>, dans l\'ordre du document.',
                'roles' => $resultat,
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)."\n",
        );
    }

    private function pageAccessible(): string
    {
        foreach (['/pwa/mon-profil', '/pwa/aide-a-propos', '/pwa/'] as $url) {
            $reponse = $this->get($url);

            if ($reponse->status() === 200 && str_contains((string) $reponse->getContent(), 'id="shell-topbar"')) {
                return (string) $reponse->getContent();
            }
        }

        $this->fail('Aucune page ne rend la barre superieure pour ce role.');
    }

    /**
     * @return list<array{type: string, texte: string}>
     */
    private function releverEntete(string $html): array
    {
        $dom = new DOMDocument();
        libxml_use_internal_errors(true);
        $dom->loadHTML('<?xml encoding="UTF-8">'.$html);
        libxml_clear_errors();

        $barre = (new DOMXPath($dom))->query('//*[@id="shell-topbar"]')->item(0);
        $this->assertInstanceOf(DOMElement::class, $barre, 'Le bloc #shell-topbar est introuvable.');

        $elements = [];
        $this->parcourir($barre, $elements);

        return $elements;
    }

    /**
     * @param  list<array{type: string, texte: string}>  $elements
     */
    private function parcourir(?DOMNode $noeud, array &$elements): void
    {
        if (! $noeud instanceof DOMElement) {
            return;
        }

        $balise = strtolower($noeud->tagName);

        if (in_array($balise, ['script', 'style', 'svg', 'template', 'noscript', 'img'], true) || $this->estCache($noeud)) {
            return;
        }

        $propre = '';
        foreach ($noeud->childNodes as $enfant) {
            if ($enfant->nodeType === XML_TEXT_NODE) {
                $propre .= ' '.$enfant->textContent;
            }
        }
        $texte = trim((string) preg_replace('/\s+/u', ' ', $propre));

        if (mb_strlen($texte) >= 3) {
            $elements[] = ['type' => $balise, 'texte' => $texte];
        }

        // Info-bulles : `title` puis `aria-label`, sans doublon ni redite du texte.
        $deja = [$texte];
        foreach (['title', 'aria-label'] as $attribut) {
            $valeur = trim((string) preg_replace('/\s+/u', ' ', $noeud->getAttribute($attribut)));
            if (mb_strlen($valeur) >= 3 && ! in_array($valeur, $deja, true)) {
                $elements[] = ['type' => 'info-bulle', 'texte' => $valeur];
                $deja[] = $valeur;
            }
        }

        if (in_array($balise, ['input', 'textarea'], true)) {
            $invite = trim($noeud->getAttribute('placeholder'));
            if (mb_strlen($invite) >= 3) {
                $elements[] = ['type' => 'champ', 'texte' => $invite];
            }
        }

        foreach ($noeud->childNodes as $enfant) {
            $this->parcourir($enfant, $elements);
        }
    }

    /** Masque par `hidden`, `display:none`, `x-cloak` — sauf le panneau montre. */
    private function estCache(DOMElement $element): bool
    {
        $id = $element->getAttribute('id');

        if ($id !== '' && in_array($id, array_filter(self::VARIANTES), true)) {
            return $id !== $this->panneauMontre;
        }

        $classes = ' '.preg_replace('/\s+/', ' ', $element->getAttribute('class')).' ';

        // `hidden md:block` : masque en mobile, VISIBLE au poste de travail
        // (le seul gabarit du client : bureau).
        $visibleEnBureau = (bool) preg_match('/ (sm|md|lg|xl):(block|flex|inline|inline-flex|grid) /', $classes);

        // `lg:hidden` : visible en mobile seulement (bouton d'ouverture du menu).
        $masqueEnBureau = (bool) preg_match('/ (md|lg|xl):hidden /', $classes);

        return $masqueEnBureau
            || (str_contains($classes, ' hidden ') && ! $visibleEnBureau)
            || $element->hasAttribute('hidden')
            || $element->hasAttribute('x-cloak')
            || (bool) preg_match('/display\s*:\s*none/i', $element->getAttribute('style'));
    }
}
