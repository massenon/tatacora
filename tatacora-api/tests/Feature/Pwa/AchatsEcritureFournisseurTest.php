<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Models\Fournisseur;
use App\Models\User;
use App\Pwa\Livewire\Achats\Achats;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\OuvreLaSaisie;
use Tests\TestCase;

/**
 * La PREMIÈRE écriture de la PWA — « Ajouter fournisseur », EF-M7-01.
 *
 * ## Ce que ce fichier prouve, et pourquoi chaque cas existe
 *
 * Le 27/08/2026, le Product Owner a levé la lecture seule de la PWA. La garde
 * n'a pas été supprimée mais inversée (`PwaEcritureAutoriseeTest`) : toute
 * action qui persiste doit exiger un droit. Cette exigence est **structurelle**
 * — elle vérifie que l'appel est écrit. Elle ne dit rien de ce qui se passe
 * quand il s'exécute.
 *
 * C'est la leçon PA-59/60/61 du dépôt, dans sa forme la plus directe : *un test
 * qui vérifie qu'une garde est déclarée ne dit rien de ce qu'elle fait quand
 * elle tourne*. Les cas ci-dessous empruntent donc réellement le chemin.
 */
final class AchatsEcritureFournisseurTest extends TestCase
{
    use OuvreLaSaisie;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function utilisateur(string $role, string $statut = 'actif'): User
    {
        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => $statut,
        ]);
    }

    /** Le rôle qui porte `M7 = C`, lu du référentiel plutôt que supposé. */
    private function roleQuiEcritSurM7(): string
    {
        foreach (['achats', 'gerant', 'administrateur'] as $role) {
            $u = Role::where('libelle', $role)->first();
            if ($u !== null && $u->niveauSurModule('M7') === 'C') {
                return $role;
            }
        }

        $this->fail(
            'Aucun rôle du référentiel ne porte `M7 = C`. Ce fichier ne peut '
            .'plus rien éprouver : la matrice RBAC a changé, et cet écran '
            .'serait devenu inaccessible en écriture à tout le monde.',
        );
    }

    // =====================================================================

    #[Test]
    public function un_role_autorise_enregistre_reellement_un_fournisseur(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->assertSet('etatFormulaire', 'fournisseur')
            ->set('fRaisonSociale', 'Grand Marché Natitingou SARL')
            ->set('fContact', '01 90 12 34 56')
            ->set('fCategorie', 'Denrées alimentaires')
            ->set('fConditionsPaiement', '30 jours')
            ->set('fEvaluation', 'bon')
            ->call('enregistrerFournisseur')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        // La ligne existe VRAIMENT. Sans cette lecture en base, le test
        // vérifierait que la modale se ferme — c'est-à-dire exactement le
        // « bouton qui confirme sans rien enregistrer » que l'Article 6
        // interdit.
        $fournisseur = Fournisseur::where('raison_sociale', 'Grand Marché Natitingou SARL')->first();
        $this->assertNotNull($fournisseur, 'Aucun fournisseur n a été écrit en base.');
        $this->assertSame('01 90 12 34 56', $fournisseur->contact);
        $this->assertSame('Denrées alimentaires', $fournisseur->categorie);
        $this->assertSame('30 jours', $fournisseur->conditions_paiement);
        $this->assertSame('bon', $fournisseur->evaluation);

        // L'UUID est fourni par l'applicatif, convention offline-first du
        // projet : c'est lui qui rend un rejeu idempotent.
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f-]{36}$/',
            $fournisseur->id,
            'L identifiant n est pas un UUID : la convention de clé du projet '
            .'n est pas respectée par ce chemin d écriture.',
        );
    }

    #[Test]
    public function une_evaluation_laissee_vide_devient_null_et_non_une_chaine_vide(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->set('fRaisonSociale', 'Fournisseur sans évaluation')
            ->call('enregistrerFournisseur')
            ->assertHasNoErrors();

        $fournisseur = Fournisseur::where('raison_sociale', 'Fournisseur sans évaluation')->firstOrFail();

        // `evaluation` est un `enum` MySQL. Une chaîne vide y serait refusée
        // par la base, avec un message SQL illisible plutôt qu'une erreur de
        // validation lisible — et surtout, « pas encore évalué » n'est pas
        // « À revoir » : les confondre reprocherait à un fournisseur neuf une
        // mauvaise note que personne ne lui a donnée.
        $this->assertNull($fournisseur->evaluation);
        $this->assertNull($fournisseur->contact);
        $this->assertNull($fournisseur->categorie);
    }

    #[Test]
    public function une_raison_sociale_vide_est_refusee_par_les_regles_de_l_api(): void
    {
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->set('fRaisonSociale', '')
            ->call('enregistrerFournisseur')
            ->assertHasErrors('fRaisonSociale');

        $this->assertSame(
            0,
            Fournisseur::count(),
            'Une saisie refusée a tout de même écrit une ligne.',
        );
    }

    #[Test]
    public function un_role_sans_droit_d_ecriture_est_refuse_et_trace(): void
    {
        // `guide` n'a aucun droit sur M7 — le même refus que lui oppose l API.
        $utilisateur = $this->utilisateur('guide');
        $this->actingAs($utilisateur);

        Livewire::test(Achats::class)
            ->call('enregistrerFournisseur')
            ->assertForbidden();

        $this->assertSame(
            0,
            Fournisseur::count(),
            'Un rôle sans droit a écrit une ligne : le canal web accorde ce '
            .'que le canal API refuse, ce qui est la divergence que le RBAC '
            .'partagé existe pour empêcher.',
        );

        // SECURITY_STRICT.md §10 — un refus se TRACE. Sans cette trace, une
        // tentative répétée depuis le web serait invisible.
        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateur->id,
            'module_concerne' => 'M7',
        ]);
    }

    #[Test]
    public function le_formulaire_ne_s_ouvre_meme_pas_pour_un_role_sans_droit(): void
    {
        // Le droit est exigé DÈS L'OUVERTURE : présenter un formulaire à
        // quelqu un qui ne pourra pas le soumettre lui fait perdre sa saisie
        // et ne lui apprend rien.
        $this->actingAs($this->utilisateur('guide'));

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->assertForbidden();
    }

    #[Test]
    public function un_compte_desactive_n_ecrit_rien_malgre_un_role_autorise(): void
    {
        // RG-15 : un compte ne se supprime jamais, il se désactive. Le rôle
        // reste donc porteur du droit ; c est le STATUT qui doit trancher.
        // Sans ce cas, désactiver un compte le laisserait écrire par le web.
        $utilisateur = $this->utilisateur($this->roleQuiEcritSurM7(), 'desactive');
        $this->actingAs($utilisateur);

        Livewire::test(Achats::class)
            ->call('enregistrerFournisseur')
            ->assertUnauthorized();

        $this->assertSame(0, Fournisseur::count());
    }

    #[Test]
    public function le_bouton_est_masque_pour_un_role_sans_droit(): void
    {
        // 1er niveau du RBAC. Il ne protège rien — les cas ci-dessus le
        // prouvent côté serveur — mais son absence proposerait un geste qui
        // sera refusé.
        $this->actingAs($this->utilisateur('guide'));
        Livewire::test(Achats::class)->assertDontSee('Ajouter fournisseur');

        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));
        Livewire::test(Achats::class)->assertSee('Ajouter fournisseur');
    }

    #[Test]
    public function les_regles_de_la_pwa_sont_bien_CELLES_de_l_api(): void
    {
        // Le composant lit `EnregistrerFournisseurRequest::rules()`. Ce cas
        // vérifie que le lien n est pas rompu : une seconde liste écrite à la
        // main resterait verte le jour où l API durcirait une contrainte, et
        // la PWA accepterait alors ce que l API refuse.
        $reglesApi = (new \App\Domain\Achats\Http\Requests\EnregistrerFournisseurRequest())->rules();

        $this->assertContains(
            'required',
            $reglesApi['raison_sociale'],
            'La règle de référence a changé de forme : le pont entre la PWA et '
            .'le FormRequest de l API doit être relu.',
        );

        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));

        // Une valeur hors de l enum est refusée ICI, pas par la base.
        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->set('fRaisonSociale', 'Maison Test')
            ->set('fEvaluation', 'excellentissime')
            ->call('enregistrerFournisseur')
            ->assertHasErrors('fEvaluation');
    }

    /**
     * Le contrat du trait partagé `OuvreLaSaisie` (lot 0.5), éprouvé sur le
     * PREMIER écran d'écriture — c'est ce trait que chaque vague future
     * appellera au lieu de réécrire ces assertions.
     *
     * « Exactement les champs » : la modale fait apparaître les cinq liaisons
     * du formulaire fournisseur, ni une de moins (formulaire amputé), ni une
     * de plus (propriété saisissable que personne n'a relue).
     */
    #[Test]
    public function la_modale_rend_exactement_les_champs_declares_du_formulaire(): void
    {
        $this->assertLaModaleSOuvreEtRendExactementSesChamps(
            $this->utilisateur($this->roleQuiEcritSurM7()),
            Achats::class,
            'ouvrirFormulaireFournisseur',
            ['fRaisonSociale', 'fContact', 'fCategorie', 'fConditionsPaiement', 'fEvaluation'],
        );
    }

    /**
     * Et son refus : `comptable` porte `M7 = 'L'` — la lecture d'un module ne
     * donne aucun droit d'y écrire, la modale ne s'ouvre pas, et le refus est
     * tracé au `journal_securite`.
     */
    #[Test]
    public function la_modale_ne_s_ouvre_pas_pour_un_role_en_lecture_et_le_refus_est_trace(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->assertSame(
            'L',
            $comptable->niveauSurModule('M7'),
            'Le referentiel a change : ce cas suppose un role a M7 = L.',
        );

        $this->assertLOuvertureEstRefuseeEtTracee(
            $comptable,
            Achats::class,
            'ouvrirFormulaireFournisseur',
            'M7',
        );
    }

    #[Test]
    public function aucun_refus_n_est_trace_quand_l_ecriture_reussit(): void
    {
        // Contre-épreuve du cas de traçage : si `journal_securite` se
        // remplissait à chaque écriture, la trace ne signalerait plus rien.
        $this->actingAs($this->utilisateur($this->roleQuiEcritSurM7()));

        Livewire::test(Achats::class)
            ->call('ouvrirFormulaireFournisseur')
            ->set('fRaisonSociale', 'Maison Correcte')
            ->call('enregistrerFournisseur')
            ->assertHasNoErrors();

        $this->assertSame(0, JournalSecurite::count());
    }
}
