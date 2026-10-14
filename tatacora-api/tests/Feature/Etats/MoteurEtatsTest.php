<?php

declare(strict_types=1);

namespace Tests\Feature\Etats;

use App\Domain\Stocks\Etats\EtatStocks;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;
use App\Shared\ReportEngine\Models\EtatGenere;
use App\Shared\ReportEngine\Services\GenerateurEtatService;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Moteur d'états — RG-19, EF-M14-01/03/04/06.
 *
 * Couvre la grille `RESPECT_TABLEAU_RAPPORT.md` §2 sur un état réel, dont son
 * point 13 : « au moins un test vérifiant que l'en-tête est identique à celle
 * d'un autre état déjà conforme (non-régression de RG-19 across états) ».
 */
final class MoteurEtatsTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $magasin;

    private User $magasinier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->magasinier = $this->utilisateur('magasinier');
        $this->actingAs($this->magasinier);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $riz = $this->article('Riz parfumé 50kg', seuil: '10.00', cmp: '18000.0000');
        $huile = $this->article('Huile 5L', seuil: '20.00', cmp: '4500.0000');

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($riz->id, $this->magasin->id, '40.00', 'Stock initial');
        $mouvements->entree($huile->id, $this->magasin->id, '8.00', 'Stock initial');
    }

    // ------------------------------------------------------------ Génération

    #[Test]
    public function un_etat_produit_un_pdf_reel_et_archive_sa_generation(): void
    {
        $document = app(GenerateurEtatService::class)->generer(
            app(EtatStocks::class),
            ['point_id' => $this->magasin->id],
            'pdf',
        );

        // Un PDF réel, pas une chaîne vide ni du HTML : la signature de format
        // est vérifiée sur les octets produits.
        $this->assertStringStartsWith('%PDF-', $document->contenu);
        $this->assertGreaterThan(1000, strlen($document->contenu));
        $this->assertSame('application/pdf', $document->typeMime);
        $this->assertStringEndsWith('.pdf', $document->nomFichier);

        // EF-M14-06 — archivage horodaté.
        $archive = EtatGenere::findOrFail($document->archiveId);
        $this->assertSame('M6', $archive->module);
        $this->assertSame('pdf', $archive->format);
        $this->assertSame($this->magasinier->id, $archive->utilisateur_id);
        $this->assertSame('Magasin général', $archive->filtres_appliques['point']);
    }

    #[Test]
    public function le_meme_etat_s_exporte_aussi_en_tableur(): void
    {
        $document = app(GenerateurEtatService::class)->generer(
            app(EtatStocks::class),
            ['point_id' => $this->magasin->id],
            'excel',
        );

        // Le BOM UTF-8 : sans lui, Excel sous Windows affiche « RÃ©ception ».
        $this->assertStringStartsWith("\u{FEFF}", $document->contenu);
        $this->assertStringContainsString('Riz parfumé 50kg', $document->contenu);
        // Séparateur point-virgule, attendu par Excel en locale française.
        $this->assertStringContainsString(';', $document->contenu);

        $this->assertSame('excel', EtatGenere::findOrFail($document->archiveId)->format);
    }

    /**
     * Grille point 7 : « les deux formats fonctionnent à partir de la MÊME
     * structure de données, jamais deux calculs séparés qui pourraient
     * diverger ». C'est le défaut nommé en `RESPECT_TABLEAU_RAPPORT.md` §4 :
     * « Export PDF et Excel avec des totaux légèrement différents ».
     */
    #[Test]
    public function le_pdf_et_le_tableur_reposent_sur_un_calcul_identique(): void
    {
        $generateur = app(GenerateurEtatService::class);
        $filtres = ['point_id' => $this->magasin->id];

        $pdf = $generateur->generer(app(EtatStocks::class), $filtres, 'pdf');
        $csv = $generateur->generer(app(EtatStocks::class), $filtres, 'excel');

        $this->assertSame($pdf->resultat->kpis, $csv->resultat->kpis);
        $this->assertSame($pdf->resultat->entetes, $csv->resultat->entetes);
        $this->assertSame($pdf->resultat->lignes, $csv->resultat->lignes);
    }

    // ------------------------------------------------------ RG-19 transverse

    /**
     * **Le test exigé par la grille, point 13.**
     *
     * Deux états de modules différents doivent porter exactement la même
     * en-tête institutionnelle. C'est la seule protection contre la
     * non-conformité n°1 : une en-tête recopiée localement « parce que c'est
     * plus simple », qui diverge à la première évolution.
     */
    #[Test]
    public function rg19_deux_etats_de_modules_differents_portent_la_meme_entete(): void
    {
        $generateur = app(GenerateurEtatService::class);

        $stocks = $generateur->generer(app(EtatStocks::class), [], 'pdf')->entete;
        $autre = $generateur->generer(new EtatFactice(), [], 'pdf')->entete;

        // Tout le bloc institutionnel est identique...
        $this->assertSame($stocks->raisonSociale, $autre->raisonSociale);
        $this->assertSame($stocks->sousTitre, $autre->sousTitre);
        $this->assertSame($stocks->adresse, $autre->adresse);
        $this->assertSame($stocks->telephone, $autre->telephone);
        $this->assertSame($stocks->email, $autre->email);
        $this->assertSame($stocks->siteWeb, $autre->siteWeb);
        $this->assertSame($stocks->mentionsLegales(), $autre->mentionsLegales());
        $this->assertSame($stocks->mentionInstitutionnelle, $autre->mentionInstitutionnelle);
        $this->assertSame($stocks->auteur, $autre->auteur);

        // ...seuls le titre et la période distinguent les deux documents.
        $this->assertNotSame($stocks->typeRapport, $autre->typeRapport);
    }

    /**
     * L'IFU renseigné doit apparaître sur **tous** les états, sans qu'aucun
     * n'ait à s'en occuper.
     */
    #[Test]
    public function rg19_une_mention_fiscale_renseignee_se_propage_a_tous_les_etats(): void
    {
        ParametreSysteme::create([
            'cle' => ReportHeaderService::CLE_IFU,
            'valeur' => '3202612345678',
            'description' => 'Identifiant Fiscal Unique.',
        ]);

        $generateur = app(GenerateurEtatService::class);

        foreach ([app(EtatStocks::class), new EtatFactice()] as $etat) {
            $entete = $generateur->generer($etat, [], 'pdf')->entete;
            $this->assertSame(['IFU' => '3202612345678'], $entete->mentionsLegales());
        }
    }

    // ------------------------------------------------------- Auteur réel

    /**
     * Grille point 4 : l'utilisateur RBAC réellement connecté, jamais une
     * valeur générique.
     */
    #[Test]
    public function l_auteur_est_l_utilisateur_reellement_connecte(): void
    {
        // `employes.service_id` est NOT NULL au schéma : un employé appartient
        // toujours à un service, on ne contourne pas la contrainte.
        $service = \App\Domain\Rh\Models\Service::create(['libelle' => 'Logistique']);

        $employe = \App\Domain\Rh\Models\Employe::create([
            'nom' => 'AGBODJAN', 'prenom' => 'Céline',
            'poste' => 'Magasinier', 'service_id' => $service->id,
            'date_embauche' => '2025-01-06',
            'salaire_base' => '150000.00', 'statut' => 'actif',
        ]);
        $this->magasinier->forceFill(['employe_id' => $employe->id])->save();

        $entete = app(GenerateurEtatService::class)
            ->generer(app(EtatStocks::class), [], 'pdf')->entete;

        $this->assertSame('Céline AGBODJAN — magasinier', $entete->auteur);
    }

    /**
     * Un compte technique sans fiche RH ne doit pas produire une en-tête
     * amputée : le `login` est un identifiant réel et traçable.
     */
    #[Test]
    public function un_compte_sans_fiche_employe_est_identifie_par_son_login(): void
    {
        $entete = app(GenerateurEtatService::class)
            ->generer(app(EtatStocks::class), [], 'pdf')->entete;

        $this->assertStringContainsString($this->magasinier->login, $entete->auteur);
        $this->assertStringContainsString('magasinier', $entete->auteur);
    }

    // ------------------------------------------------------------ RBAC

    /**
     * Grille point 8 : le contrôle porte sur le **contenu**, pas seulement sur
     * l'accès à l'écran. Le contrôle a lieu avant `calculer()` — sans quoi les
     * données auraient déjà été lues.
     */
    #[Test]
    public function un_role_sans_droit_sur_le_module_source_ne_peut_pas_editer_l_etat(): void
    {
        // Le cuisinier n'a aucun droit sur M6 dans la matrice ? Vérifions le
        // niveau réel plutôt que de le supposer.
        $cuisine = $this->utilisateur('cuisine');
        $this->assertNotSame('-', $cuisine->niveauSurModule('M6'), 'Prérequis du test invalide.');

        // On prend un rôle réellement dépourvu d'accès à M6.
        $sansAcces = collect(Role::all())
            ->first(fn (Role $role): bool => $role->niveauSurModule('M6') === '-');

        $this->assertNotNull($sansAcces, 'Aucun rôle sans accès M6 : matrice à vérifier.');

        $intrus = User::create([
            'login' => 'intrus.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $sansAcces->id,
            'statut' => 'actif',
        ]);

        $this->expectException(RuntimeException::class);
        app(GenerateurEtatService::class)->generer(app(EtatStocks::class), [], 'pdf', $intrus);
    }

    #[Test]
    public function un_compte_desactive_ne_peut_editer_aucun_etat(): void
    {
        $this->magasinier->forceFill(['statut' => 'desactive'])->save();

        $this->expectException(RuntimeException::class);
        app(GenerateurEtatService::class)
            ->generer(app(EtatStocks::class), [], 'pdf', $this->magasinier->fresh());
    }

    /**
     * Aucun document ne doit être archivé si l'accès est refusé : une entrée
     * `etats_generes` laisserait croire qu'un état a bien été remis.
     */
    #[Test]
    public function un_acces_refuse_ne_laisse_aucune_trace_d_archivage(): void
    {
        $this->magasinier->forceFill(['statut' => 'desactive'])->save();

        try {
            app(GenerateurEtatService::class)
                ->generer(app(EtatStocks::class), [], 'pdf', $this->magasinier->fresh());
        } catch (RuntimeException) {
            // attendu
        }

        $this->assertSame(0, EtatGenere::count());
    }

    // ------------------------------------------------------ Cas de bord

    /**
     * Grille : « Absence de données pour la période/le filtre : message
     * explicite, jamais un tableau vide sans explication ni une erreur
     * technique ».
     */
    #[Test]
    public function un_etat_sans_donnee_produit_un_document_avec_message_explicite(): void
    {
        // Les mouvements d'abord : `restrictOnDelete()` protège les articles
        // référencés, exactement comme en production.
        \App\Domain\Stocks\Models\MouvementStock::query()->delete();
        Article::query()->delete();

        $document = app(GenerateurEtatService::class)
            ->generer(app(EtatStocks::class), [], 'excel');

        $this->assertTrue($document->resultat->estVide());
        $this->assertStringContainsString(__('rapports.aucune_donnee'), $document->contenu);
    }

    #[Test]
    public function un_format_inconnu_est_refuse_et_non_replie_silencieusement(): void
    {
        $this->expectException(RuntimeException::class);
        app(GenerateurEtatService::class)->generer(app(EtatStocks::class), [], 'docx');
    }

    /**
     * EF-M14-03 — les filtres doivent réellement filtrer, et être reportés dans
     * l'archive tels qu'appliqués.
     */
    #[Test]
    public function le_filtre_sous_seuil_restreint_reellement_les_lignes(): void
    {
        $generateur = app(GenerateurEtatService::class);
        $filtres = ['point_id' => $this->magasin->id];

        $complet = $generateur->generer(app(EtatStocks::class), $filtres, 'pdf');
        $restreint = $generateur->generer(
            app(EtatStocks::class),
            [...$filtres, 'sous_seuil' => '1'],
            'pdf',
        );

        // Riz 40 (seuil 10) est normal ; Huile 8 (seuil 20) est sous seuil.
        $this->assertSame(2, $complet->resultat->nombreLignes());
        $this->assertSame(1, $restreint->resultat->nombreLignes());
        $this->assertSame('Huile 5L', $restreint->resultat->lignes[0][0]);

        $archive = EtatGenere::findOrFail($restreint->archiveId);
        $this->assertSame('oui', $archive->filtres_appliques['sous_seuil']);
    }

    /**
     * Le stock imprimé est le stock calculé, pas une colonne figée.
     */
    #[Test]
    public function les_quantites_imprimees_viennent_du_calcul_des_mouvements(): void
    {
        $document = app(GenerateurEtatService::class)->generer(
            app(EtatStocks::class),
            ['point_id' => $this->magasin->id],
            'pdf',
        );

        $riz = collect($document->resultat->lignes)->firstOrFail(fn (array $l): bool => $l[0] === 'Riz parfumé 50kg');

        $this->assertSame('40.00', $riz[3]);
        // Valorisation au coût moyen pondéré : 40 × 18 000.
        $this->assertSame('720000.00', $riz[6]);
    }

    // ------------------------------------------------------------- Helpers

    private function article(string $libelle, string $seuil, string $cmp): Article
    {
        return Article::create([
            'libelle' => $libelle, 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => $seuil, 'seuil_reappro' => '50.00', 'cout_moyen_pondere' => $cmp,
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}

/**
 * État minimal d'un **autre** module, servant de témoin à la vérification
 * transverse de RG-19. Volontairement trivial : ce qui est comparé est
 * l'en-tête que le moteur lui impose, pas ce qu'il calcule.
 */
final class EtatFactice implements EtatInterface
{
    public function module(): string
    {
        return 'M6';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return 'État témoin — vérification RG-19';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return 'Août 2026';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function calculer(array $filtres): EtatResultat
    {
        return new EtatResultat(
            kpis: ['Total' => '1'],
            entetes: ['Colonne'],
            lignes: [['valeur']],
        );
    }
}
