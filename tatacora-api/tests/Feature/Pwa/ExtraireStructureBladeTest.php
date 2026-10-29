<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use DOMDocument;
use DOMElement;
use DOMNode;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * GENERATEUR (pas une garde) de la structure RENDUE d'une vue Blade — Phase 1A
 * de `docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md`.
 *
 * Le comparateur de libelles (`tool/conformite_blade/t-blade-flutter.js`) lit le
 * SOURCE et dit ce qui MANQUE ; il ne dit pas si ce qui est la est bien PLACE.
 * Ce generateur rend la page pour de vrai (administrateur, jeu de donnees
 * minimal), puis releve, dans l'ordre du document, chaque texte visible du
 * contenu de `<main>` — les barres (laterale, superieure) sont les Phases 1B
 * et 1C. Le client Flutter rend le meme ecran dans un test de widget et
 * compare l'ORDRE (`test/core/qualite/emplacement_blade_test.dart`).
 *
 * Il ne tourne que si `STRUCTURE_BLADE_SORTIE` designe un dossier :
 *
 *   STRUCTURE_BLADE_SORTIE=../tatacora_flutter/tool/conformite_blade/structure \
 *     php artisan test --filter=ExtraireStructureBladeTest
 *
 * Il ECRIT des fichiers ; sans la variable il saute, et ce saut est son seul
 * role : il n'affirme rien, donc il ne peut pas passer a vide.
 *
 * @see EF-M3-01 Liste des clients (page pilote)
 */
final class ExtraireStructureBladeTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Pages relevees : vue => [url, variantes (cle => query), jeu de donnees].
     * Chaque jeu est le MEME que celui que le test Flutter pose dans sa base :
     * la structure ne doit pas dependre des donnees.
     */
    private const PAGES = [
        'crm/clients-creances' => [
            'url' => '/pwa/clients',
            'variantes' => [
                'clients' => '?onglet=clients',
                'dettes' => '?onglet=dettes',
                'relances' => '?onglet=relances',
                'avances' => '?onglet=avances',
            ],
            'jeu' => 'clients',
        ],
        'hebergement/hebergement' => [
            'url' => '/pwa/hebergement',
            'variantes' => [
                'plan' => '?onglet=plan',
                'reservations' => '?onglet=reservations',
                'calendrier' => '?onglet=calendrier',
                'disponibilites' => '?onglet=disponibilites',
            ],
            'jeu' => 'parc',
        ],
        'hebergement/reservations' => [
            'url' => '/pwa/reservations',
            'variantes' => [
                'principal' => '',
                'historique' => '?vue=historique',
            ],
            'jeu' => 'parc',
        ],
        // Lot 4 : les ecrans que le client Flutter servait EN LIGNE ou presque.
        'vehicules/locations' => [
            'url' => '/pwa/vehicules',
            'variantes' => [
                'parc' => '?onglet=parc',
                'contrats' => '?onglet=contrats',
                'planning' => '?onglet=planning',
                'immo' => '?onglet=immo',
            ],
            'jeu' => 'parc',
        ],
        // 21/10/2026 : l'écran créé à la PWA, repris par le poste.
        'rh/conges-plannings' => [
            'url' => '/pwa/rh/conges-plannings',
            'variantes' => [
                'plannings' => '?onglet=plannings',
                'conges' => '?onglet=conges',
            ],
            'jeu' => 'vide',
        ],
        'tourisme/departs' => [
            'url' => '/pwa/tourisme',
            'variantes' => [
                'departs' => '?onglet=departs',
                'reservations' => '?onglet=reservations',
                'catalogue' => '?onglet=catalogue',
            ],
            'jeu' => 'parc',
        ],
        'achats/achats' => [
            'url' => '/pwa/achats',
            'variantes' => [
                'fournisseurs' => '?onglet=fournisseurs',
                'commandes' => '?onglet=commandes',
            ],
            'jeu' => 'parc',
        ],
        'achats/approvisionnement' => [
            'url' => '/pwa/achats/approvisionnement',
            'variantes' => [
                'besoins' => '?onglet=besoins',
                'commandes' => '?onglet=commandes',
                'receptions' => '?onglet=receptions',
                'dettes' => '?onglet=dettes',
            ],
            'jeu' => 'parc',
        ],
        // Lot 5a : stocks, restauration, carte du bar.
        'stocks/stocks' => [
            'url' => '/pwa/stocks',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'stocks/inventaires' => [
            'url' => '/pwa/stocks/inventaires',
            'variantes' => [
                'fiche' => '?onglet=fiche',
                'inventaire' => '?onglet=inventaire',
                'historique' => '?onglet=historique',
            ],
            'jeu' => 'parc',
        ],
        'restaurant/restauration' => [
            'url' => '/pwa/restaurant/plats',
            'variantes' => [
                'plats' => '?onglet=plats',
                'fiches' => '?onglet=fiches',
                'menus' => '?onglet=menus',
            ],
            'jeu' => 'parc',
        ],
        'bar/carte' => [
            'url' => '/pwa/bar/carte',
            'variantes' => [
                'carte' => '?onglet=carte',
                'couverture' => '?onglet=couverture',
                'ventes' => '?onglet=ventes',
            ],
            'jeu' => 'parc',
        ],
        // Lot 5b : carte du restaurant, studio d'etats, parametres.
        'restaurant/carte' => [
            'url' => '/pwa/restaurant/carte',
            'variantes' => [
                'carte' => '?onglet=carte',
                'couverture' => '?onglet=couverture',
                'ventes' => '?onglet=ventes',
            ],
            'jeu' => 'parc',
        ],
        'etats/studio' => [
            'url' => '/pwa/etats',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/parametres' => [
            'url' => '/pwa/parametres',
            'variantes' => [
                'identite' => '?onglet=identite',
                'communication' => '?onglet=communication',
                'email' => '?onglet=email',
                'apparence' => '?onglet=apparence',
                'canaux' => '?onglet=canaux',
                'tables' => '?onglet=tables',
                'activation' => '?onglet=activation',
            ],
            'jeu' => 'parc',
        ],
        // Lot 6 : l'accueil (tableau de bord), dont les onglets sont portes
        // par `?panel=`.
        'livewire/accueil' => [
            'url' => '/pwa/',
            'variantes' => [
                'exploitation' => '?panel=exploitation',
                'pilotage' => '?panel=pilotage',
                'croise' => '?panel=croise',
            ],
            'panneaux' => true,
            'jeu' => 'parc',
        ],
        // Lot 3 : les pages d'accueil, servies a un visiteur non connecte.
        'livewire/connexion' => [
            'url' => '/pwa/connexion',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
            'invite' => true,
        ],
        'demarrage' => [
            'url' => '/pwa/demarrage',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
            'invite' => true,
        ],
        // Lot 2 (08/10/2026) : les ecrans a donnees LOCALES du client Flutter.
        'pos/comptant' => [
            'url' => '/pwa/pos/comptant',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'pos/heberges' => [
            'url' => '/pwa/pos/heberges',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'pos/historique-ventes' => [
            'url' => '/pwa/historique-ventes',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'facturation/facturation' => [
            'url' => '/pwa/facturation',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'depenses/depenses' => [
            'url' => '/pwa/depenses',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'notifications/hub' => [
            'url' => '/pwa/notifications',
            'variantes' => [
                'file' => '?onglet=file',
                'modeles' => '?onglet=modeles',
                'declencheurs' => '?onglet=declencheurs',
                'journal' => '?onglet=journal',
                'canaux' => '?onglet=canaux',
            ],
            'jeu' => 'parc',
        ],
        'rh/paie' => [
            'url' => '/pwa/paie',
            'variantes' => [
                'personnel' => '?onglet=personnel',
                'bulletins' => '?onglet=bulletins',
                'livre' => '?onglet=livre',
                'declarations' => '?onglet=declarations',
                'bareme' => '?onglet=bareme',
            ],
            'jeu' => 'parc',
        ],
        // Lot D (14/10/2026, D417-D424) : les ecrans portes sans mesure
        // d'emplacement jusqu'au 15/10/2026 (angle mort releve par la
        // consolidation de `emplacement_blade_test.dart`).
        'comptabilite/hub' => [
            'url' => '/pwa/comptabilite',
            'variantes' => [
                'saisie' => '?onglet=saisie',
                'journal' => '?onglet=journal',
                'grandlivre' => '?onglet=grandlivre',
                'balance' => '?onglet=balance',
                'resultat' => '?onglet=resultat',
                'bilan' => '?onglet=bilan',
                'analytique' => '?onglet=analytique',
                'immo' => '?onglet=immo',
                'plan' => '?onglet=plan',
                'clotures' => '?onglet=clotures',
            ],
            'jeu' => 'parc',
        ],
        // Correspondance des comptes (26/10/2026) : la vue ouverte depuis l'onglet
        // Plan du hub, rôle -> compte comptable modifiable.
        'comptabilite/correspondance-comptes' => [
            'url' => '/pwa/comptabilite/correspondance-comptes',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/aide-a-propos' => [
            'url' => '/pwa/aide-a-propos',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/contact-editeur' => [
            'url' => '/pwa/contact-editeur',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/import-export' => [
            'url' => '/pwa/import-export',
            'variantes' => [
                'importer' => '?onglet=importer',
                'sauvegardes' => '?onglet=sauvegardes',
                'restaurer' => '?onglet=restaurer',
                'seeders' => '?onglet=seeders',
            ],
            'jeu' => 'parc',
        ],
        'transverse/journal-audit' => [
            'url' => '/pwa/journal-audit',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        // Décision PO du 18/10/2026 : le bouton « Synchroniser » du serveur.
        'transverse/synchronisation-postes' => [
            'url' => '/pwa/synchronisation-postes',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/mon-profil' => [
            'url' => '/pwa/mon-profil',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        'transverse/roles-permissions' => [
            'url' => '/pwa/roles-permissions',
            'variantes' => ['principal' => ''],
            'jeu' => 'parc',
        ],
        // 29/10/2026 (PO, option A du « mot de passe perdu ») : la liste des comptes et
        // « Réinitialiser le mot de passe ».
        'transverse/comptes-utilisateurs' => [
            'url' => '/pwa/comptes-utilisateurs',
            'variantes' => ['principal' => ''],
            'jeu' => 'vide',
        ],
    ];

    /** Elements dont le texte propre est releve (le reste est du decor). */
    private const BALISES = [
        'h1', 'h2', 'h3', 'h4', 'button', 'a', 'th', 'td', 'label', 'p', 'span', 'option', 'legend', 'div',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function extraire_la_structure_rendue_des_pages(): void
    {
        $sortie = getenv('STRUCTURE_BLADE_SORTIE');

        if ($sortie === false || $sortie === '') {
            $this->markTestSkipped('Generateur : definir STRUCTURE_BLADE_SORTIE pour ecrire les structures.');
        }

        if (! is_dir($sortie)) {
            mkdir($sortie, 0777, true);
        }

        $this->poserLesJeux();
        $administrateur = $this->administrateur();

        foreach (self::PAGES as $vue => $page) {
            $parOnglet = [];
            $invite = ($page['invite'] ?? false) === true;

            // Les pages d'ACCUEIL (connexion, demarrage) se servent a un
            // visiteur NON authentifie, sans `<main>` : le releve prend alors
            // le corps de la page.
            if ($invite) {
                $this->app['auth']->forgetGuards();
            } else {
                $this->actingAs($administrateur);
            }

            foreach ($page['variantes'] as $cle => $requete) {
                $html = (string) $this->get($page['url'].$requete)->assertOk()->getContent();
                // Ecran a panneaux basculés par JAVASCRIPT (`data-panneau-tb`) : le
                // serveur rend les trois, deux masques par `hidden`. Le panneau
                // de la variante est montre, les autres restent masques.
                $this->panneauMontre = ($page['panneaux'] ?? false) === true ? (string) $cle : null;
                $parOnglet[$cle] = $this->releverMain($html, $invite);
            }

            foreach ($parOnglet as $cle => $elements) {
                $this->assertGreaterThan(3, count($elements), "Variante {$cle} de {$vue} : releve vide, l'extraction est cassee.");
            }

            file_put_contents(
                rtrim($sortie, '/\\').'/'.str_replace('/', '__', $vue).'.json',
                json_encode([
                    '_lisez-moi' => 'PRODUIT par ExtraireStructureBladeTest, jamais ecrit a la main. '
                        .'Chaque variante (onglet) : les textes VISIBLES de <main>, dans l\'ordre du document.',
                    'vue' => $vue,
                    'jeu' => $page['jeu'],
                    'onglets' => $parOnglet,
                ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)."\n",
            );
        }

        // La reponse du serveur pour l'ecran Parametres : il est PILOTE par
        // `RegistreParametres` (onglets, champs, aides). Le client Flutter n'a
        // plus de client HTTP : le test de widget rejoue cette reponse.
        $this->actingAs($administrateur, 'sanctum');
        $reponse = $this->getJson('/api/v1/parametres');
        if ($reponse->status() === 200) {
            file_put_contents(
                rtrim($sortie, '/\\').'/reponse-serveur__parametres.json',
                json_encode($reponse->json(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)."\n",
            );
        }

        // Le catalogue des etats (registre ferme du serveur), meme raison.
        $catalogue = $this->getJson('/api/v1/etats');
        if ($catalogue->status() === 200) {
            file_put_contents(
                rtrim($sortie, '/\\').'/reponse-serveur__etats.json',
                json_encode($catalogue->json(), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT)."\n",
            );
        }
    }

    /**
     * Les deux jeux de donnees, identiques a ceux du test Flutter : un client
     * (`clients`) et un petit parc avec son client (`parc`).
     */
    private function poserLesJeux(): void
    {
        Client::create([
            'nom' => 'KORA',
            'telephone' => '97111111',
            'type_client' => 'particulier',
        ]);

        Client::create([
            'nom' => 'KORA',
            'prenom' => 'Jean',
            'telephone' => '+229 01 00 00 00 01',
            'type_client' => 'particulier',
        ]);

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '28000.00',
        ]);

        foreach (['BNG-01', 'BNG-02'] as $numero) {
            UniteHebergement::create([
                'categorie_id' => $categorie->id,
                'numero' => $numero,
                'statut' => 'libre',
            ]);
        }
    }

    /**
     * @return list<array{type: string, texte: string, cle?: string}>
     */
    private function releverMain(string $html, bool $invite = false): array
    {
        $dom = new DOMDocument();
        libxml_use_internal_errors(true);
        $dom->loadHTML('<?xml encoding="UTF-8">'.$html);
        libxml_clear_errors();

        $mains = $dom->getElementsByTagName('main');

        if ($invite) {
            $racine = $dom->getElementsByTagName('body')->item(0);
        } else {
            $this->assertSame(1, $mains->length, 'La page doit porter exactement un <main>.');
            $racine = $mains->item(0);
        }

        $elements = [];
        $this->parcourir($racine, $elements);

        // Les MODALES et panneaux lateraux vivent apres `<main>` (le chassis
        // les pose en fin de page) : une variante qui ouvre un panneau
        // (`?vue=historique`) serait sinon identique a la page seule.
        foreach ((new \DOMXPath($dom))->query(
            "//*[contains(concat(' ', normalize-space(@class), ' '), ' fixed ')"
            ." and contains(concat(' ', normalize-space(@class), ' '), ' inset-0 ')"
            ." and not(ancestor::main)]",
        ) ?: [] as $recouvrement) {
            $this->parcourir($recouvrement, $elements);
        }

        return $elements;
    }

    /**
     * @param  list<array{type: string, texte: string, cle?: string}>  $elements
     */
    private function parcourir(?DOMNode $noeud, array &$elements): void
    {
        if (! $noeud instanceof DOMElement) {
            return;
        }

        $balise = strtolower($noeud->tagName);

        if (in_array($balise, ['script', 'style', 'svg', 'template', 'noscript'], true) || $this->estCache($noeud)) {
            return;
        }

        if (in_array($balise, self::BALISES, true)) {
            $propre = '';
            foreach ($noeud->childNodes as $enfant) {
                if ($enfant->nodeType === XML_TEXT_NODE) {
                    $propre .= ' '.$enfant->textContent;
                }
            }
            $texte = trim((string) preg_replace('/\s+/u', ' ', $propre));

            // Un bouton qui change d'onglet (`$set('onglet', ...)`) est un
            // ONGLET : le client Flutter doit en avoir un cliquable, pas un
            // texte qui le nomme.
            // Un LIEN `?onglet=cle` (ecran Parametres : « changer d'onglet est
            // une navigation ») est un onglet au meme titre.
            $cleOnglet = null;
            if ($balise === 'button'
                && preg_match("/'onglet'\s*,\s*'([a-z0-9_-]+)'/i", $noeud->getAttribute('wire:click'), $m) === 1) {
                $cleOnglet = $m[1];
            } elseif ($balise === 'a'
                && preg_match('/[?&]onglet=([a-z0-9_-]+)/i', $noeud->getAttribute('href'), $m) === 1) {
                $cleOnglet = $m[1];
            }

            $type = $cleOnglet !== null || ($balise === 'button' && str_contains($noeud->getAttribute('wire:click'), "'onglet'"))
                ? 'onglet'
                : $balise;

            if (mb_strlen($texte) >= 3) {
                $element = ['type' => $type, 'texte' => $texte];

                if ($cleOnglet !== null) {
                    // La cle sert au client Flutter a savoir QUEL onglet ouvrir.
                    $element['cle'] = $cleOnglet;
                }

                $elements[] = $element;
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

    /** Un element masque (`hidden`, `display:none`, `x-cloak`) n'est pas VU : il ne compte pas. */
    /** Panneau `data-panneau-tb` a montrer pour la variante en cours. */
    private ?string $panneauMontre = null;

    private function estCache(DOMElement $element): bool
    {
        if ($this->panneauMontre !== null && $element->hasAttribute('data-panneau-tb')) {
            return $element->getAttribute('data-panneau-tb') !== $this->panneauMontre;
        }

        $classes = ' '.preg_replace('/\s+/', ' ', $element->getAttribute('class')).' ';

        return str_contains($classes, ' hidden ')
            || str_contains($classes, ' invisible ')
            || $element->hasAttribute('hidden')
            || $element->hasAttribute('x-cloak')
            || (bool) preg_match('/display\s*:\s*none/i', $element->getAttribute('style'));
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'compte.structure',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
