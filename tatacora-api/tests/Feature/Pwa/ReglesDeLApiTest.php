<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Http\Requests\EnregistrerFournisseurRequest;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Restaurant\Http\Requests\EnregistrerMenuRequest;
use App\Domain\Restaurant\Http\Requests\EnregistrerPlatRequest;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Pwa\Support\ReglesDeLApi;
use LogicException;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le pont `ReglesDeLApi` rend les règles du BON mode — lot 0.1.
 *
 * ## Le défaut que ces cas ferment, mesuré avant d'être fermé
 *
 * `EnregistrerFournisseurRequest::rules()` branche sur
 * `$this->route('fournisseur') instanceof Fournisseur`. Instancié à nu, le
 * résolveur de route rend `null` : les règles de CRÉATION sortent toujours,
 * quel que soit le geste. Sur « Modifier », l'écran validerait
 * `id => sometimes|uuid|unique` là où l'API impose `prohibited` — la PWA
 * accepterait ce que l'API refuse. Même piège dans `EnregistrerPlatRequest`
 * (l.82) et `EnregistrerMenuRequest` (l.47) : les trois requêtes sont
 * éprouvées ici, pas seulement celle du premier écran.
 *
 * Aucune base n'est touchée : construire des règles ne requiert aucune
 * requête, et les modèles passés au binding sont des instances nues.
 */
final class ReglesDeLApiTest extends TestCase
{
    #[Test]
    public function en_creation_le_pont_rend_les_regles_de_creation_remappees(): void
    {
        $regles = ReglesDeLApi::pourCreation(EnregistrerFournisseurRequest::class, [
            'raison_sociale' => 'fRaisonSociale',
            'id' => 'fId',
        ]);

        // Les clés sont les PROPRIÉTÉS Livewire, pas les champs API.
        $this->assertArrayHasKey('fRaisonSociale', $regles);
        $this->assertArrayNotHasKey('raison_sociale', $regles);
        $this->assertContains('required', $regles['fRaisonSociale']);

        // Et le mode est bien la création : l'UUID fourni par le client est
        // ACCEPTÉ (convention offline-first), jamais interdit.
        $this->assertContains('sometimes', $regles['fId']);
        $this->assertNotContains('prohibited', $regles['fId']);
    }

    #[Test]
    public function en_modification_le_pont_rend_les_regles_de_modification(): void
    {
        // C'est LE cas qui a motivé le pont : sans le route-binding, `id`
        // sortirait `sometimes|uuid|unique` au lieu de `prohibited`.
        $regles = ReglesDeLApi::pourModification(
            EnregistrerFournisseurRequest::class,
            'fournisseur',
            new Fournisseur(),
            ['id' => 'fId', 'raison_sociale' => 'fRaisonSociale'],
        );

        $this->assertSame(['prohibited'], $regles['fId']);
        $this->assertContains('required', $regles['fRaisonSociale']);
    }

    #[Test]
    public function les_deux_autres_requetes_piegees_rendent_aussi_leur_mode(): void
    {
        // `EnregistrerPlatRequest` l.82 et `EnregistrerMenuRequest` l.47
        // portent le même branchement sur le route-binding : les éprouver ici
        // évite que la vague 4 découvre le piège en production.
        $plat = ReglesDeLApi::pourModification(
            EnregistrerPlatRequest::class,
            'plat',
            new Plat(),
            ['id' => 'pId'],
        );
        $this->assertSame(['prohibited'], $plat['pId']);

        $menu = ReglesDeLApi::pourModification(
            EnregistrerMenuRequest::class,
            'menu',
            new Menu(),
            ['id' => 'mId'],
        );
        $this->assertSame(['prohibited'], $menu['mId']);

        // Et la création reste la création.
        $platCreation = ReglesDeLApi::pourCreation(EnregistrerPlatRequest::class, ['id' => 'pId']);
        $this->assertNotContains('prohibited', $platCreation['pId']);
    }

    #[Test]
    public function un_nom_de_parametre_de_route_faux_rendrait_les_regles_de_creation(): void
    {
        // La LIMITE du pont, démontrée plutôt que tue : le nom du paramètre
        // n'est pas vérifiable contre la requête (elle ne le déclare nulle
        // part). Un nom faux ne lève pas — il fait silencieusement retomber
        // dans le mode création. C'est pourquoi chaque écran de vague DOIT
        // éprouver son mode modification par un cas comme ceux ci-dessus.
        $regles = ReglesDeLApi::pourModification(
            EnregistrerFournisseurRequest::class,
            'mauvais_nom',
            new Fournisseur(),
            ['id' => 'fId'],
        );

        $this->assertNotContains('prohibited', $regles['fId']);
    }

    #[Test]
    public function un_champ_api_inconnu_leve_au_lieu_de_valider_par_rien(): void
    {
        // Si l'API renomme un champ, la correspondance devient muette. La
        // sauter validerait la propriété avec AUCUNE règle, en silence — le
        // pont échoue à la place, au moment du rendu du formulaire.
        $this->expectException(LogicException::class);

        ReglesDeLApi::pourCreation(EnregistrerFournisseurRequest::class, [
            'champ_disparu' => 'fChamp',
        ]);
    }
}
