<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les deux marques de prix de la carte — PA-161 (b).
 *
 * ## Ce que ce fichier prouve, et pourquoi
 *
 * Six boissons du maître portent un tarif INVENTÉ : l'ardoise du bar ne
 * donnait aucun montant pour EKU 66 cl, Guinness 66 cl, Vody / Loco, le vin
 * blanc, le vin rouge et le rhum, et un prix a été posé sur décision du
 * Product Owner pour débloquer le point de vente — ce que l'ancienne maquette
 * disait sans détour. Ces montants sont appliqués à de vrais clients à chaque
 * service.
 *
 * La PWA dérivait la marque de `prix_vente <= 0` sur une colonne NOT NULL :
 * elle affichait donc « aucun prix provisoire » en permanence, sans l'avoir
 * vérifié une seule fois (PA-59/60/61). La colonne existe depuis la migration
 * `2026_09_02_200000`, et ce fichier tient les deux règles qui la font vivre.
 *
 * ## `prix_corrige_main` se DÉDUIT, et c'est le point qui compte
 *
 * C'est un FAIT, pas une case à cocher : changer au clavier le prix d'un
 * article marqué provisoire EST la correction manuelle. Le faire déclarer en
 * plus reviendrait à demander à quelqu'un de décrire ce qu'il vient de faire,
 * et il l'oublierait — après quoi le document remis au client afficherait un
 * prix corrigé sans le dire.
 *
 * ## Mutations RÉELLEMENT rejouées le 02/09/2026
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `MarquesDePrix::completer()` rend `$donnees` sans jamais poser la marque | `modifier_le_prix_d_un_tarif_provisoire_pose_la_marque_corrige_a_la_main` | 1 failed |
 * | `MarquesDePrix::completer()` pose la marque même quand le prix ne change pas (`bccomp` retiré) | `un_enregistrement_sans_changement_de_prix_ne_pose_aucune_marque` | 1 failed |
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-161 (b) Marques de prix
 */
final class MarquesDePrixCarteTest extends TestCase
{
    use RefreshDatabase;

    private Article $article;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->utilisateur('administrateur'));

        $this->article = Article::create([
            'libelle' => 'Casier EKU 66 cl',
            'categorie' => 'Boissons',
            'unite_mesure' => 'casier',
            'seuil_alerte' => '2.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
    }

    /* ------------------------------------------------------ le socle */

    /**
     * Les deux colonnes naissent à `false` sur les DEUX tables.
     *
     * `false` par défaut décrit exactement l'état des lignes existantes —
     * aucune n'a jamais été marquée. Un `null` aurait introduit un troisième
     * état, « on ne sait pas », qui se rendrait comme une absence de marque de
     * toute façon.
     */
    #[Test]
    public function les_deux_marques_naissent_a_faux_sur_les_deux_tables(): void
    {
        // ⚠ `refresh()`, jamais l'instance qui sort de `create()` : le défaut
        // est posé par la BASE, et l'objet en mémoire ne le connaît pas — il
        // rend `null`, qui n'est ni vrai ni faux. Le même piège a déjà mordu
        // sur `cout_moyen_pondere` (`ReferentielArticleService`).
        $boisson = $this->boisson('800.00')->refresh();

        $this->assertFalse($boisson->prix_provisoire);
        $this->assertFalse($boisson->prix_corrige_main);

        $plat = $this->plat('2000.00')->refresh();

        $this->assertFalse($plat->prix_provisoire);
        $this->assertFalse($plat->prix_corrige_main);
    }

    /**
     * Le cast `boolean` est indispensable, et son absence est INVISIBLE.
     *
     * Sans lui, MySQL rend le `tinyint(1)` comme la chaîne « 0 », qui est
     * VRAIE dans un `@if` Blade : la marque « provisoire » s'afficherait sur
     * toute la carte, y compris sur le papier remis au client.
     */
    #[Test]
    public function les_marques_sont_de_vrais_booleens_et_non_des_chaines(): void
    {
        $boisson = $this->boisson('800.00');
        $boisson->refresh();

        // `assertSame(false, ...)` et non `assertIsBool()` : la seconde est
        // toujours vraie sous le cast, donc vide de sens ; la premiere echoue
        // sur l'entier `0` ou la chaine « 0 » que MySQL rendrait sans lui.
        $this->assertSame(false, $boisson->prix_provisoire, 'Sans le cast, « 0 » arrive en entier ou en chaîne — et « 0 » est vrai en PHP.');
        $this->assertSame(false, $boisson->prix_corrige_main);
    }

    /* ------------------------------------------- la déduction, au bar */

    /**
     * Modifier au clavier le prix d'un tarif PROVISOIRE pose « corrigé à la
     * main ».
     *
     * C'est la sémantique du maître, et la raison est pratique : sans cette
     * déduction, la fiche des prix remise au client afficherait un tarif
     * corrigé sans le signaler.
     */
    #[Test]
    public function modifier_le_prix_d_un_tarif_provisoire_pose_la_marque_corrige_a_la_main(): void
    {
        $boisson = $this->boisson('1200.00', provisoire: true);

        app(CarteBoissonService::class)->modifier($boisson, ['prix_vente' => '1500.00']);

        $boisson->refresh();

        $this->assertTrue($boisson->prix_corrige_main, 'Le prix a changé à la main sur un tarif provisoire.');
        $this->assertTrue($boisson->prix_provisoire, 'Corriger un prix ne lève pas la marque provisoire : elle reste à confronter à la carte.');
    }

    /**
     * Le même geste sur un tarif NON provisoire ne pose rien.
     *
     * Sans cette borne, toute mise à jour de tarif marquerait la carte comme
     * instable, et la marque cesserait de vouloir dire quelque chose (PA-135 :
     * une mention permanente cesse d'être lue).
     */
    #[Test]
    public function modifier_le_prix_d_un_tarif_definitif_ne_pose_aucune_marque(): void
    {
        $boisson = $this->boisson('800.00');

        app(CarteBoissonService::class)->modifier($boisson, ['prix_vente' => '900.00']);

        $this->assertFalse($boisson->refresh()->prix_corrige_main);
    }

    /**
     * Un enregistrement qui ne change PAS le montant ne pose rien.
     *
     * ⚠ `bccomp`, jamais `!=` : « 1200 » et « 1200.00 » sont le même montant et
     * deux chaînes différentes. Une comparaison d'égalité marquerait « corrigé
     * à la main » à chaque ouverture-fermeture du formulaire.
     */
    #[Test]
    public function un_enregistrement_sans_changement_de_prix_ne_pose_aucune_marque(): void
    {
        $boisson = $this->boisson('1200.00', provisoire: true);

        app(CarteBoissonService::class)->modifier($boisson, [
            'prix_vente' => '1200',
            'libelle' => 'EKU 66 cl',
        ]);

        $this->assertFalse(
            $boisson->refresh()->prix_corrige_main,
            'Le montant est identique : « 1200 » et « 1200.00 » ne sont pas deux prix.',
        );
    }

    /**
     * Une décision EXPLICITE l'emporte sur la déduction.
     *
     * Sans cette porte, lever la marque serait impossible dès qu'on corrige le
     * prix du même geste : l'écran refuserait en silence une action qu'il vient
     * d'offrir. Même raisonnement que PA-124 — la cohérence s'apprécie sur
     * l'état RÉSULTANT, jamais clé par clé.
     */
    #[Test]
    public function une_decision_explicite_l_emporte_sur_la_deduction(): void
    {
        $boisson = $this->boisson('1200.00', provisoire: true);
        $boisson->forceFill(['prix_corrige_main' => true])->save();

        app(CarteBoissonService::class)->modifier($boisson, [
            'prix_vente' => '1500.00',
            'prix_corrige_main' => false,
        ]);

        $this->assertFalse($boisson->refresh()->prix_corrige_main);
    }

    /* ------------------------------------- la même règle, au restaurant */

    /**
     * La déduction est la MÊME des deux côtés — c'est pour cela qu'elle vit
     * dans `App\Domain\Carte\MarquesDePrix` et non recopiée dans chaque
     * service. Deux copies auraient divergé au premier ajustement, et le
     * maître écrit lui-même cette raison (`carte-module.js` l.7).
     */
    #[Test]
    public function la_deduction_vaut_aussi_pour_un_plat(): void
    {
        $plat = $this->plat('3000.00', provisoire: true);

        app(CartePlatMenuService::class)->modifierPlat($plat, ['prix_vente' => '3500.00']);

        $this->assertTrue($plat->refresh()->prix_corrige_main);
    }

    /* -------------------------------------------------------- fabriques */

    private function boisson(string $prix, bool $provisoire = false): CarteBoisson
    {
        return app(CarteBoissonService::class)->creer([
            'article_id' => $this->article->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'EKU 66 cl',
            'categorie' => 'importee',
            'prix_vente' => $prix,
            'prix_provisoire' => $provisoire,
        ]);
    }

    private function plat(string $prix, bool $provisoire = false): Plat
    {
        // `menus.type` est un enum FERME au schema : `local`, `europeen`,
        // `special`. Un `a_la_carte` plausible y est tronque par MySQL, sans
        // erreur en mode non strict — un avertissement, pas un refus.
        $menu = Menu::create([
            'libelle' => 'Carte du jour',
            'type' => 'local',
        ]);

        $recette = Recette::create(['libelle' => 'Chawarma poulet']);

        return app(CartePlatMenuService::class)->creerPlat([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Chawarma poulet',
            'prix_vente' => $prix,
            'prix_provisoire' => $provisoire,
        ]);
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
}
