<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * LE CYCLE M7 DEPUIS LA PWA — besoin → commande → réception → entrée de stock.
 *
 * ## Ce que ce fichier prouve, et qui n'est prouvé nulle part ailleurs
 *
 * `AchatsEcritureFournisseurTest` tient la PREMIÈRE écriture de la PWA
 * (EF-M7-01). Ce fichier tient les DEUX suivantes, celles de l'écran
 * Approvisionnement : émettre un bon de commande depuis les besoins (EF-M7-02)
 * et le réceptionner (EF-M7-03), ce qui GÉNÈRE l'entrée de stock.
 *
 * La réception est l'écriture la plus lourde du module : elle crée un bon,
 * écrit des `mouvements_stock` d'entrée et recalcule le coût moyen pondéré.
 * Chaque cas ci-dessous emprunte réellement ce chemin — vérifier qu'une garde
 * est *déclarée* ne dit rien de ce qu'elle fait quand elle *tourne*
 * (PA-59/60/61).
 *
 * ## MUTATIONS RÉELLEMENT JOUÉES (31/08/2026) — un test qui ne peut pas
 * échouer ne compte pas
 *
 *  1. `Approvisionnement::ouvrirFormulaireCommande()` — remplacer
 *     `$this->ouvrirFormulaire('commande')` par une pose directe de
 *     `$this->etatFormulaire = 'commande'` (la garde RBAC saute) :
 *     `un_role_sans_droit_ne_peut_pas_ouvrir_la_commande` ROUGE.
 *  2. `Approvisionnement::enregistrerReception()` — remplacer l'appel à
 *     `ReceptionService::receptionner()` par la seule création du bon :
 *     `la_reception_genere_reellement_l_entree_de_stock` ROUGE (aucun
 *     mouvement de stock).
 *  3. Vue `approvisionnement.blade.php` — rendre `montant_regle` et
 *     `montantTotal() - montant_regle` à la place des deux tirets de l'onglet
 *     Dettes : `les_colonnes_de_reglement_rendent_un_tiret_et_non_un_zero`
 *     ROUGE. ⚠ La PREMIÈRE version de cette mutation, posée sur la colonne
 *     « Réglé » de l'onglet Commandes, n'a PAS mordu — le cas visé lit
 *     l'onglet Dettes. Une mutation qui ne mord pas dit exactement où le
 *     contrôle ne va pas, et c'est ce qui a fait écrire ce cas-ci.
 *  4. `Achats::genererExport()` — retirer le refus sur liste vide :
 *     `un_export_sur_une_liste_vide_est_refuse` ROUGE.
 *  5. `Achats::ouvrirFormulaireFournisseur()` — ignorer l'identifiant reçu :
 *     `le_bouton_modifier_ouvre_la_fiche_existante` ROUGE.
 *
 * @see EF-M7-02 Émission de commandes d'achat
 * @see EF-M7-03 Réception et entrée de stock
 * @see RG-10 Tolérance de réception
 */
final class AchatsCyclePwaTest extends TestCase
{
    use OuvreLaSaisie;
    use RefreshDatabase;

    private PointStockage $magasin;

    private Article $sucre;

    private Fournisseur $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // =====================================================================
    // EF-M7-02 — émettre un bon de commande depuis les besoins
    // =====================================================================

    #[Test]
    public function une_commande_est_emise_depuis_la_selection_des_besoins(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Approvisionnement::class)
            ->set('selection', [$this->sucre->id])
            ->call('ouvrirFormulaireCommande')
            ->assertSet('etatFormulaire', 'commande')
            ->set('cFournisseurId', $this->fournisseur->id)
            ->set('cLignes.0.quantite', '6')
            ->set('cLignes.0.prix_unitaire', '500')
            ->call('enregistrerCommande')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $commande = CommandeAchat::query()->firstOrFail();
        $this->assertSame($this->fournisseur->id, $commande->fournisseur_id);
        // Le seul statut que le geste du maitre decrit : « Creer le bon de
        // commande » l'envoie au fournisseur. Il est SAISISSABLE au Service ;
        // les trois autres sont produits par une reception reelle.
        $this->assertSame('envoyee', $commande->statut);

        $ligne = LigneCommandeAchat::query()->firstOrFail();
        $this->assertSame($this->sucre->id, $ligne->article_id);
        $this->assertSame('6.00', (string) $ligne->quantite_commandee);
        $this->assertSame('500.00', (string) $ligne->prix_unitaire);

        // Le montant AFFICHÉ est CALCULÉ depuis les lignes (`montantTotal()`),
        // jamais lu seul dans `montant_total`.
        //
        // ⚠ CETTE ASSERTION AFFIRMAIT LE DÉFAUT COMME UN FAIT (jusqu'au
        // 02/09/2026) : `assertSame('0.00', ...montant_total)` prenait pour
        // acquis que la colonne restait à zéro — exactement PA-59/60/61, un
        // test qui certifie une panne. `ReglementFournisseurService::
        // resteDu()` LIT cette colonne : la laisser à 0.00 aurait fait
        // refuser TOUT règlement positif comme un sur-paiement, découvert en
        // REJOUANT réellement le geste (voir le docblock de
        // `Approvisionnement::enregistrerCommande()`). Elle est désormais
        // SYNCHRONISÉE à la création — assignation directe, hors
        // `$fillable`, le Service et le modèle restant intacts.
        $this->assertSame('3000.00', $commande->montantTotal());
        $this->assertSame('3000.00', (string) $commande->fresh()->montant_total);
    }

    /**
     * La quantité suggérée remonte au DOUBLE du seuil, jamais au seuil pile.
     *
     * Recommander à l'exact ferait repasser l'article sous alerte à la première
     * sortie — c'est la règle du maître (`m7-approvisionnement.html` l.248-251),
     * et elle n'a de sens que si elle est vérifiée sur un chiffre.
     */
    #[Test]
    public function la_quantite_suggeree_remonte_au_double_du_seuil(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        // Sucre : seuil 4, stock 2 → cible 8, suggestion 6.
        Livewire::test(Approvisionnement::class)
            ->set('selection', [$this->sucre->id])
            ->call('ouvrirFormulaireCommande')
            ->assertSet('cLignes.0.quantite', '6.00');
    }

    #[Test]
    public function une_selection_vide_ne_produit_aucune_commande(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireCommande')
            ->assertSet('etatFormulaire', null)
            ->assertHasErrors('selection');

        $this->assertSame(0, CommandeAchat::query()->count());
    }

    /**
     * Un prix unitaire à zéro est refusé — et le refus est LISIBLE.
     *
     * Sans prix, aucun montant de commande ne peut être calculé ni aucun coût
     * moyen pondéré mis à jour à la réception : l'article entrerait en stock
     * valorisé à rien, et la valeur du stock deviendrait fausse en silence.
     */
    #[Test]
    public function un_prix_unitaire_nul_est_refuse(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Approvisionnement::class)
            ->set('selection', [$this->sucre->id])
            ->call('ouvrirFormulaireCommande')
            ->set('cFournisseurId', $this->fournisseur->id)
            ->set('cLignes.0.prix_unitaire', '0')
            ->call('enregistrerCommande')
            ->assertHasErrors('cLignes.0.prix_unitaire');

        $this->assertSame(0, CommandeAchat::query()->count());
    }

    #[Test]
    public function un_role_sans_droit_ne_peut_pas_ouvrir_la_commande(): void
    {
        $this->jeu();

        $this->assertLOuvertureEstRefuseeEtTracee(
            $this->utilisateur('comptable'),   // M7 = 'L'
            Approvisionnement::class,
            'ouvrirFormulaireCommande',
            'M7',
        );

        $this->assertSame(0, CommandeAchat::query()->count());
    }

    #[Test]
    public function un_role_sans_droit_n_enregistre_aucune_commande(): void
    {
        $this->jeu();
        $utilisateur = $this->utilisateur('guide');    // M7 = '-'
        $this->actingAs($utilisateur);

        Livewire::test(Approvisionnement::class)
            ->call('enregistrerCommande')
            ->assertForbidden();

        $this->assertSame(0, CommandeAchat::query()->count());
        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateur->id,
            'module_concerne' => 'M7',
        ]);
    }

    // =====================================================================
    // EF-M7-03 / RG-10 — la réception, et l'entrée de stock qu'elle génère
    // =====================================================================

    /**
     * LE CAS QUI COMPTE : la réception écrit un bon ET un mouvement d'entrée.
     *
     * « EF-M7-03 déclenche `mouvements_stock` (entrée) — jamais de double
     * saisie manuelle du stock après réception ». Un écran qui créerait le bon
     * sans le mouvement annoncerait une réception faite pendant que le stock
     * reste au même niveau, et le magasinier le saisirait une seconde fois.
     */
    #[Test]
    public function la_reception_genere_reellement_l_entree_de_stock(): void
    {
        $this->jeu();
        $this->tolerance('5.00');
        $commande = $this->commandeEnvoyee('4.00', '1000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        $entreesAvant = MouvementStock::query()->where('type_mouvement', 'entree')->count();

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReception', $commande->id)
            ->assertSet('etatFormulaire', 'reception')
            ->assertSet('rQuantites.'.$this->sucre->id, '4.00')
            ->call('enregistrerReception')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $bon = BonReception::query()->firstOrFail();
        $this->assertSame($commande->id, $bon->commande_id);
        // La conformite vient du SERVICE (RG-10), jamais d'un calcul refait
        // dans l'ecran : 4 recus sur 4 commandes, tolerance 5 % → totale.
        $this->assertSame('totale', $bon->conformite);

        $this->assertSame(
            $entreesAvant + 1,
            MouvementStock::query()->where('type_mouvement', 'entree')->count(),
            'La reception n a genere AUCUNE entree de stock : l ecran annonce une '
            .'reception que le stock ne reflete pas.',
        );

        $this->assertSame('receptionnee', $commande->fresh()->statut);
    }

    /**
     * La tolérance RG-10 n'est PAS configurée par défaut, et le refus du
     * Service atteint l'écran au lieu d'être avalé.
     *
     * C'est l'inverse exact du défaut corrigé le 31/08/2026 : l'écran attrapait
     * l'exception et affichait « Réception enregistrée en base », alors
     * qu'AUCUN bon et AUCUN mouvement n'avaient été écrits.
     */
    #[Test]
    public function le_refus_du_service_est_affiche_et_rien_n_est_ecrit(): void
    {
        $this->jeu();
        // Aucune tolerance posee : `ReceptionService` refuse d'evaluer.
        $commande = $this->commandeEnvoyee('4.00', '1000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReception', $commande->id)
            ->call('enregistrerReception')
            ->assertHasErrors('rQuantites')
            // La modale RESTE ouverte : la fermer laisserait croire que le
            // geste est passe.
            ->assertSet('etatFormulaire', 'reception');

        $this->assertSame(0, BonReception::query()->count());
        $this->assertSame('envoyee', $commande->fresh()->statut);
    }

    #[Test]
    public function une_reception_a_zero_partout_est_refusee(): void
    {
        $this->jeu();
        $this->tolerance('5.00');
        $commande = $this->commandeEnvoyee('4.00', '1000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReception', $commande->id)
            ->set('rQuantites.'.$this->sucre->id, '0')
            ->call('enregistrerReception')
            ->assertHasErrors('rQuantites');

        $this->assertSame(0, BonReception::query()->count());
    }

    #[Test]
    public function un_role_sans_droit_ne_peut_pas_ouvrir_la_reception(): void
    {
        $this->jeu();
        $commande = $this->commandeEnvoyee('4.00', '1000.00');
        $utilisateur = $this->utilisateur('comptable');
        $this->actingAs($utilisateur);

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReception', $commande->id)
            ->assertSet('etatFormulaire', null)
            ->assertForbidden();

        $this->assertSame(0, BonReception::query()->count());
        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateur->id,
            'module_concerne' => 'M7',
        ]);
    }

    /**
     * « Réglé » rend « — » sur une commande jamais réglée ; « Reste dû »
     * rend le MONTANT RÉEL — plus jamais « 0 F » ni « — » sur ce qui reste
     * dû, ni l'inverse (PA-165, 02/09/2026).
     *
     * ⚠ CE CAS AFFIRMAIT L'INVERSE JUSQU'AU 02/09/2026 : « Reste dû » devait
     * rendre un tiret, au motif que rien n'écrivait `montant_regle` ni
     * `montant_total`. `ReglementFournisseurService` écrit désormais le
     * premier ; `Approvisionnement::enregistrerCommande()` synchronise le
     * second (voir son docblock — la colonne existe au schéma depuis le
     * 28/08/2026 mais aucun Service ne l'écrivait, ce qui aurait fait refuser
     * tout règlement comme un sur-paiement). Un « 0 F » plausible sur une
     * commande RÉELLEMENT soldée reste évité par `formatOuTiret()` ; ici la
     * commande n'est PAS soldée, le reste dû est un FAIT et doit se voir.
     */
    #[Test]
    public function le_reste_du_est_chiffre_et_le_regle_rend_un_tiret_sur_une_commande_jamais_reglee(): void
    {
        $this->jeu();
        $commande = $this->commandeEnvoyee('4.00', '1000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        $html = (string) $this->get('/pwa/achats/approvisionnement?onglet=dettes')
            ->assertOk()->getContent();

        $ligne = $this->extraireLigne($html, 'dette-cmd-'.$commande->id);

        // Le montant COMMANDE est un fait, il s'affiche...
        $this->assertStringContainsString('4'."\u{00A0}".'000 FCFA', $ligne);

        // ... « Reste dû » aussi : la commande n'est pas réglée, elle doit
        // au fournisseur les 4 000 F commandés.
        $this->assertSame(
            2,
            substr_count($ligne, '4'."\u{00A0}".'000 FCFA'),
            'Le montant commandé ET le reste dû doivent tous deux afficher 4 000 F '
            .'sur une commande jamais réglée.',
        );

        // ... et « Réglé » seul rend un tiret : aucun règlement n'existe.
        $this->assertSame(
            1,
            substr_count($ligne, '—'),
            'La colonne « Réglé » doit rendre « — » : aucun règlement n\'a été enregistré.',
        );
    }

    // =====================================================================
    // EF-M7-01 — l'édition depuis la liste et depuis la fiche de détail
    // =====================================================================

    /**
     * « Modifier » ouvre la fiche EXISTANTE, il ne recrée pas un doublon.
     *
     * C'est le second bouton de la modale « Détail — » du maître
     * (`crud-ui.js` l.118), et le chemin normal vers l'édition depuis une
     * consultation.
     */
    #[Test]
    public function le_bouton_modifier_ouvre_la_fiche_existante(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur', $this->fournisseur->id)
            ->assertSet('etatFormulaire', 'fournisseur')
            ->assertSet('fRaisonSociale', 'Grand Marché Natitingou SARL')
            ->assertSet('fEvaluation', 'bon')
            ->set('fContact', '01 00 00 00 00')
            ->call('enregistrerFournisseur')
            ->assertHasNoErrors();

        $this->assertSame(
            1,
            Fournisseur::query()->where('raison_sociale', 'Grand Marché Natitingou SARL')->count(),
            'La modification a cree un second fournisseur au lieu de mettre a jour le premier.',
        );
        $this->assertSame('01 00 00 00 00', $this->fournisseur->fresh()->contact);
    }

    /**
     * Rouvrir « Ajouter » après une modification ne réécrit pas la fiche
     * précédente.
     *
     * `fId` fait partie des propriétés remises à zéro par le motif : sans lui,
     * le formulaire d'ajout resterait branché sur le dernier fournisseur
     * ouvert, et l'utilisateur écraserait une fiche en croyant en créer une.
     */
    #[Test]
    public function ajouter_apres_modifier_cree_bien_une_nouvelle_fiche(): void
    {
        $this->jeu();
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur', $this->fournisseur->id)
            ->call('ouvrirFormulaireFournisseur')
            ->assertSet('fId', null)
            ->assertSet('fRaisonSociale', '')
            ->set('fRaisonSociale', 'Bénin Boissons Distribution')
            ->call('enregistrerFournisseur')
            ->assertHasNoErrors();

        $this->assertSame(2, Fournisseur::query()->count());
        $this->assertSame(
            'Grand Marché Natitingou SARL',
            $this->fournisseur->fresh()->raison_sociale,
            'La fiche precedente a ete ecrasee par une creation.',
        );
    }

    // =====================================================================
    // Export — PA-119
    // =====================================================================

    /**
     * Une liste vide se REFUSE : une page blanche ne dirait pas si le filtre
     * est trop étroit ou si la donnée n'existe pas.
     */
    #[Test]
    public function un_export_sur_une_liste_vide_est_refuse(): void
    {
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(Achats::class)
            ->set('recherche', 'aucun-fournisseur-ne-porte-ce-nom')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }

    /**
     * LES QUATRE EXPORTS SONT RÉELLEMENT PRODUITS — pas seulement relus.
     *
     * ## Pourquoi ce cas existe, et ce qu'il a déjà attrapé ailleurs
     *
     * Deux exports de ce dépôt levaient à l'exécution sans qu'aucun test ne le
     * montre : `InventairesExport::collection()` appelait trois arguments
     * nommés qui n'existent pas (`ArgumentCountError` sur chaque édition de
     * fiche de stock), et `StocksExport::collection()` rendait un paginateur là
     * où `FromCollection` attend une `Enumerable`. Les deux se relisent comme
     * du code correct : seule une exécution les révèle.
     *
     * `Excel::download()` construit RÉELLEMENT le classeur — `collection()`,
     * `headings()`, `map()` et `styles()` sont traversés —, et `Pdf::loadView()`
     * compile et rend la vue Blade. Un `map()` qui lirait une relation absente,
     * une vue qui attendrait une variable que plus personne ne passe, tombent
     * ici.
     *
     * ⚠ Aucune de ces quatre méthodes n'exige `M7 = C` : un export ne produit
     * rien de neuf, il rend sur un autre papier ce qui est déjà à l'écran, et
     * le droit de LIRE est porté par le middleware de la route. Un rôle en `L`
     * doit pouvoir exporter — le cas ci-dessous le vérifie avec `comptable`.
     *
     * ## ⚠ ET IL NE LE VÉRIFIAIT PAS (corrigé le 31/08/2026)
     *
     * > **Livewire rend un `abort(403)` comme un STATUT de réponse, pas comme
     * > une exception. Ni `assertHasNoErrors()` ni `assertSet()` ne le voient.**
     *
     * Ce cas enchaînait `->call('genererExport')->assertHasNoErrors()` puis
     * `assertNotNull($reponse)` — or `$reponse` est l'objet `Testable` du
     * cadre, **jamais nul**, quel que soit le statut. Les deux assertions
     * étaient donc vraies même si le `comptable` avait été refusé sur les
     * quatre exports : le cas affirmait un droit qu'il ne mesurait pas.
     *
     * Éprouvé par mutation le 31/08/2026 : remettre `exigerEcriture(M7)` en
     * tête de `genererExport()` laissait ce cas VERT dans son ancienne forme,
     * et le rend ROUGE dans celle-ci.
     *
     * La règle, qui vaut au-delà de ce fichier : **un cas qui affirme « ce
     * rôle peut faire X » dit `assertStatus(200)`.** C'est le motif « un
     * balayage vide est vert » appliqué aux droits — et il est plus dangereux
     * ici, parce que le vert porte sur une autorisation.
     */
    #[Test]
    public function les_quatre_exports_sont_reellement_produits(): void
    {
        $this->jeu();
        $commande = $this->commandeEnvoyee('4.00', '1000.00');

        // Un bon de reception, pour que la branche « receptions » du document
        // ait REELLEMENT quelque chose a rendre. Sans lui, l'export se refuse
        // — a juste titre, une liste vide ne produit pas de page blanche — et
        // le rendu de cette branche resterait jamais execute.
        BonReception::create([
            'commande_id' => $commande->id,
            'date_reception' => now()->toDateString(),
            'utilisateur_id' => $this->utilisateurQuiEcrit()->id,
            'conformite' => 'partielle',
        ]);

        // `comptable` porte `M7 = 'L'` : la lecture, jamais l'ecriture.
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M7'));
        $this->actingAs($comptable);

        foreach (['pdf', 'excel'] as $format) {
            foreach (['fournisseurs', 'commandes'] as $onglet) {
                // `assertStatus(200)` est la SEULE assertion qui voit un
                // refus : `assertNotNull($reponse)` portait sur l'objet
                // `Testable` du cadre, qui n'est jamais nul (voir l'en-tete).
                Livewire::test(Achats::class)
                    ->set('onglet', $onglet)
                    ->set('formatExport', $format)
                    ->call('genererExport')
                    // ⚠ L'ORDRE COMPTE POUR L'ANALYSE STATIQUE : `assertStatus()`
                    // est type comme rendant une `TestResponse`, qui ne porte
                    // pas `assertHasNoErrors()`. Le controle de statut vient
                    // donc en DERNIER — c'est lui qui voit le 403, l'autre non.
                    ->assertHasNoErrors()
                    ->assertStatus(200);
            }

            // Les TROIS branches de `pdf/approvisionnement-bon.blade.php` —
            // besoins, commandes, receptions. N'en traverser qu'une laisserait
            // les deux autres jamais rendues : c'est exactement par ce chemin
            // que cette vue attendait encore une variable `$commande` que plus
            // aucun appelant ne lui passait.
            foreach (['besoins', 'commandes', 'receptions'] as $onglet) {
                Livewire::test(Approvisionnement::class)
                    ->set('onglet', $onglet)
                    ->set('formatExport', $format)
                    ->call('genererExport')
                    // ⚠ L'ORDRE COMPTE POUR L'ANALYSE STATIQUE : `assertStatus()`
                    // est type comme rendant une `TestResponse`, qui ne porte
                    // pas `assertHasNoErrors()`. Le controle de statut vient
                    // donc en DERNIER — c'est lui qui voit le 403, l'autre non.
                    ->assertHasNoErrors()
                    ->assertStatus(200);
            }
        }
    }

    /**
     * L'export porte sur la SÉLECTION quand il y en a une, et le document dit
     * son périmètre.
     */
    #[Test]
    public function l_export_porte_sur_la_selection_et_dit_son_perimetre(): void
    {
        $this->jeu();
        Fournisseur::create(['raison_sociale' => 'Fournisseur muet']);
        $this->actingAs($this->utilisateurQuiEcrit());

        // La phrase de perimetre vit dans la modale d'export : elle n'est
        // rendue qu'une fois celle-ci ouverte — un formulaire ne se rend jamais
        // au premier GET.
        $composant = Livewire::test(Achats::class)
            ->set('selection', [$this->fournisseur->id])
            ->set('etatFormulaire', 'export');

        $composant->assertSee('1 ligne(s) sélectionnées', false);

        // Sans selection, le perimetre est la liste filtree ENTIERE.
        $composant->set('selection', [])->assertSee('2 ligne(s) affichées', false);
    }

    // ----------------------------------------------------------- auxiliaires

    /**
     * La ligne <tr> qui porte une cle Livewire donnee.
     *
     * Compter les tirets sur la page entiere ne dirait rien : le bloc de refus
     * en contient, et le decompte resterait vert quoi qu il arrive.
     */
    private function extraireLigne(string $html, string $cle): string
    {
        $position = strpos($html, 'wire:key="'.$cle.'"');
        $this->assertIsInt($position, "Aucune ligne ne porte la cle {$cle}.");

        $debut = strrpos(substr($html, 0, $position), '<tr');
        $this->assertIsInt($debut);

        $fin = strpos($html, '</tr>', $position);
        $this->assertIsInt($fin);

        return substr($html, $debut, $fin - $debut);
    }

    private function jeu(): void
    {
        $auteur = $this->utilisateurQuiEcrit();
        $this->actingAs($auteur);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->sucre = Article::create([
            'libelle' => 'Sucre en poudre',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '4.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        app(MouvementStockService::class)
            ->entree($this->sucre->id, $this->magasin->id, '2.00', 'Réception initiale', '500.00');

        $this->fournisseur = Fournisseur::create([
            'raison_sociale' => 'Grand Marché Natitingou SARL',
            'contact' => '01 90 12 34 56',
            'categorie' => 'Denrées alimentaires',
            'conditions_paiement' => 'Comptant',
            'evaluation' => 'bon',
        ]);
    }

    private function commandeEnvoyee(string $quantite, string $prix): CommandeAchat
    {
        $commande = CommandeAchat::create([
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => now()->toDateString(),
            'statut' => 'envoyee',
            'utilisateur_id' => $this->utilisateurQuiEcrit()->id,
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->sucre->id,
            'quantite_commandee' => $quantite,
            'prix_unitaire' => $prix,
        ]);

        return $commande->refresh();
    }

    private function tolerance(string $pourcentage): void
    {
        // RG-10 — la tolerance est PARAMETRABLE et n'est seedee nulle part :
        // une tolerance devinee ferait accepter ou refuser des livraisons sur
        // un critere arbitraire (meme discipline que le taux d'IS, PA-19).
        ParametreSysteme::create([
            'cle' => 'tolerance_reception_pct',
            'valeur' => $pourcentage,
            'description' => 'Tolérance de réception (RG-10) — posée par le test.',
        ]);
    }

    /** Le rôle qui porte `M7 = C`, lu du référentiel plutôt que supposé. */
    private function utilisateurQuiEcrit(): User
    {
        foreach (['achats', 'gerant', 'administrateur'] as $role) {
            $modele = Role::where('libelle', $role)->first();
            if ($modele !== null && $modele->niveauSurModule('M7') === 'C') {
                return $this->utilisateur($role);
            }
        }

        $this->fail('Aucun role du referentiel ne porte `M7 = C`.');
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
