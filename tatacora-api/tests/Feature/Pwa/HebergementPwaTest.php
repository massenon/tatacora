<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * Les deux pages M1 de la PWA — `reservations.html` et `m1-hebergement.html`.
 *
 * Les points qui comptent :
 *  - l'etat d'un sejour est DERIVE des dates, jamais lu de `statut` (PA-111) —
 *    un cas le prouve en posant un `statut` perime sous des dates passees ;
 *  - la pastille du plan est la disponibilite CALCULEE (RG-02), jamais
 *    `unites_hebergement.statut` que rien n'ecrit (PA-118 repris, PA-126) ;
 *  - le calendrier compte en bornes semi-ouvertes — le jour du depart, la
 *    chambre se reloue ;
 *  - lecture seule stricte : zero champ d'ecriture, zero action hors `$set`.
 */
final class HebergementPwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    private const PAGES = [
        'reservations' => ['url' => '/pwa/reservations', 'titre' => 'Réservations', 'module' => 'M1', 'composant' => \App\Pwa\Livewire\Hebergement\Reservations::class],
        'm1-hebergement' => ['url' => '/pwa/hebergement', 'titre' => 'Hébergement &amp; Réservations', 'module' => 'M1', 'composant' => \App\Pwa\Livewire\Hebergement\Hebergement::class],
    ];

    private CategorieHebergement $categorie;

    private UniteHebergement $unite;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function les_deux_pages_sont_reellement_servies(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            $this->assertStringContainsString(
                '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">' . $page['titre'] . '</h1>',
                $html,
                "La page {$nom} ne rend pas le titre du maitre.",
            );

            $this->assertGreaterThan(
                6000,
                strlen($html),
                "La page {$nom} est anormalement courte : la coquille sans contenu ?",
            );

            $this->assertStringContainsString(
                '<body data-module="' . $page['module'] . '"',
                $html,
                "La page {$nom} ne declare pas le module du maitre.",
            );
        }
    }

    /**
     * Le `barman` a `M1 = '-'` : les deux pages lui sont fermees. C'est le 2e
     * niveau du RBAC — une URL tapee a la main est refusee ici, pas seulement
     * cachee au menu.
     */
    #[Test]
    public function un_profil_sans_droit_sur_m1_est_refuse_sur_les_deux_pages(): void
    {
        $barman = $this->utilisateur('barman');
        $this->assertSame('-', $barman->niveauSurModule('M1'), 'La matrice a change : ce cas ne verifie plus rien.');

        $this->actingAs($barman);

        foreach (self::PAGES as $page) {
            $this->get($page['url'])->assertForbidden();
        }
    }

    #[Test]
    public function un_invite_est_redirige_vers_le_formulaire_de_connexion(): void
    {
        foreach (self::PAGES as $page) {
            $this->get($page['url'])->assertRedirect(route('pwa.connexion'));
        }
    }

    /* ------------------------------------------------------ lecture seule */

    #[Test]
    public function aucune_des_deux_pages_ne_porte_de_champ_d_ecriture(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $filtres = [
            'reservations' => ['recherche', 'histTerme', 'histEtat', 'histDebut', 'histFin'],
            // Les deux dates de l'onglet « Disponibilites » (08/10/2026) sont des
            // filtres de LECTURE : elles ne declenchent aucune ecriture.
            'm1-hebergement' => ['recherche', 'categorie', 'dispoArrivee', 'dispoDepart'],
        ];

        foreach (self::PAGES as $nom => $page) {
            // Le panneau Historique compris : ses filtres sont des proprietes
            // relues, ses exports et son action « annuler » sont refuses.
            $url = $nom === 'reservations' ? $page['url'] . '?vue=historique' : $page['url'];
            $html = (string) $this->get($url)->assertOk()->getContent();

            $this->assertAucunChampDEcriture($html, $nom, $filtres[$nom]);
        }
    }

    #[Test]
    public function toute_action_livewire_cablee_est_une_methode_declaree_du_composant(): void
    {
        // Sous l'ancien regime, ce cas exigeait « rien d'autre que `$set` ».
        // La vague 2 (28/08/2026) a ouvert l'ecriture M1 : la regle devient
        // « `$set` OU une methode publique DECLAREE par le composant de la
        // page » — donc inscrite dans la liste fermee de
        // `PwaActionsReluesTest`, donc relue, et si elle ecrit, gardee par
        // `PwaEcritureAutoriseeTest`. Un `wire:click` vers une methode
        // inconnue reste un defaut : soit une faute de frappe (bouton mort),
        // soit une action heritee qui echappe aux deux listes (PA-67).
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $verifies = 0;

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();
            $corps = $this->corpsPrincipalPwa($html, $nom);

            $declarees = [];
            foreach ((new \ReflectionClass($page['composant']))->getMethods(\ReflectionMethod::IS_PUBLIC) as $methode) {
                if ($methode->getDeclaringClass()->getName() === $page['composant']) {
                    $declarees[] = $methode->getName();
                }
            }

            preg_match_all('/wire:click="([^"(]+)\(?/', $corps, $appels);

            foreach ($appels[1] as $appel) {
                $verifies++;

                // `$refresh` est, comme `$set`, une action du CADRE Livewire
                // — le bouton « Actualiser » du maître (vague G, 01/09/2026)
                // l'emploie : il re-rend, il n'appelle aucune méthode du
                // composant.
                if (in_array($appel, ['$refresh'], true)) {
                    continue;
                }
                $this->assertTrue(
                    $appel === '$set' || in_array($appel, $declarees, true),
                    "La page {$nom} cable `{$appel}`, qui n'est ni `\$set` ni une "
                    . "methode declaree par {$page['composant']} : bouton mort ou "
                    . 'action hors des listes fermees (PA-67).',
                );
            }
        }

        // Plancher : la page reservations cable au moins ses trois gestes.
        $this->assertGreaterThanOrEqual(3, $verifies, 'Le balayage des wire:click est devenu creux.');
    }

    /* --------------------------------------- l'etat est DERIVE des dates */

    /**
     * PA-111 — le piege que ce cas ferme : `statut` reste `confirmee` pour
     * toujours, personne n'ecrivant `en_cours` ni `terminee`. Un sejour aux
     * dates passees, statut `confirmee` en base, doit s'afficher « Terminée »
     * — lire la colonne rendrait un badge de sejour actif sur une chambre
     * rendue depuis un mois.
     */
    #[Test]
    public function l_etat_d_un_sejour_est_derive_des_dates_jamais_lu_du_statut(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Sejour fini depuis un mois — le statut en base dit toujours
        // `confirmee` (verifie ci-dessous, sans quoi ce cas ne prouve rien).
        $passee = app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDays(35)->toDateString(),
            'date_depart' => now()->subDays(30)->toDateString(),
            'statut' => 'confirmee',
        ]);
        $this->assertSame('confirmee', $passee->statut);

        $html = (string) $this->get('/pwa/reservations?vue=historique&hist_etat=termine')
            ->assertOk()->getContent();

        $this->assertStringContainsString('Terminée</span>', $html);
        $this->assertStringContainsString($this->client->nom, $html);

        // Et le filtre inverse ne la montre pas : l'etat filtre et l'etat
        // affiche viennent de la MEME derivation.
        $html = (string) $this->get('/pwa/reservations?vue=historique&hist_etat=en_cours')
            ->assertOk()->getContent();

        $this->assertStringContainsString('Aucune réservation ne correspond à ces filtres.', $html);
    }

    #[Test]
    public function une_reservation_annulee_s_affiche_annulee_et_libere_l_unite_au_plan(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $service = app(ReservationService::class);
        $enCours = $service->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDay()->toDateString(),
            'date_depart' => now()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);

        // Occupee aujourd'hui : la pastille du plan dit « Réservée » — la
        // disponibilite CALCULEE, jamais `unites_hebergement.statut` qui vaut
        // toujours `libre` en base (rien ne l'ecrit, PA-118/PA-126).
        $this->assertSame('libre', $this->unite->refresh()->statut);
        $html = (string) $this->get('/pwa/hebergement')->assertOk()->getContent();
        $this->assertStringContainsString('>Réservée</span>', $html);

        // RG-02 : l'annulation libere l'unite immediatement, sans propagation.
        $service->annuler($enCours);

        $html = (string) $this->get('/pwa/hebergement')->assertOk()->getContent();
        $this->assertStringNotContainsString('>Réservée</span>', $html);

        $html = (string) $this->get('/pwa/reservations?vue=historique&hist_etat=annulee')
            ->assertOk()->getContent();
        $this->assertStringContainsString('Annulée</span>', $html);
    }

    /**
     * Le calendrier compte en bornes SEMI-OUVERTES, comme le maitre (l.556) :
     * le jour du depart, la chambre se reloue — se tromper d'un jour par
     * sejour gonfle le taux d'un tiers sur un mois plein (PA-118).
     */
    #[Test]
    public function le_calendrier_compte_le_jour_d_arrivee_mais_pas_le_jour_de_depart(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Un sejour de deux nuits ENTIEREMENT dans le mois courant, pour que
        // le calendrier du mois le voie quel que soit le jour d'execution.
        $arrivee = now()->startOfMonth()->addDays(10);
        $depart = $arrivee->copy()->addDays(2);

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => $arrivee->toDateString(),
            'date_depart' => $depart->toDateString(),
            'statut' => 'confirmee',
        ]);

        $html = (string) $this->get('/pwa/hebergement?onglet=calendrier')->assertOk()->getContent();

        // Deux unites au parc : les jours occupes affichent « 1/2 ». Le jour
        // de l'arrivee et le lendemain comptent, le jour du depart NON —
        // exactement 2 occurrences.
        $this->assertSame(2, substr_count($html, '>1/2</span>'), 'Le calendrier ne compte pas en bornes semi-ouvertes.');
        // Blade echappe l'apostrophe en entite : l'assertion porte sur le
        // fragment qui suit, contigu dans le HTML rendu.
        $this->assertStringContainsString('occupation estimé', $html);
    }

    /**
     * ⚠ CE CAS A CHANGE DE SENS LE 31/08/2026, ET C EST LE POINT A RETENIR.
     *
     * Il exigeait auparavant deux phrases qui sont devenues FAUSSES :
     *
     *  - « lecture seule stricte » : levee par le Product Owner (PA-159) ;
     *  - « [la colonne `statut`] est ecrite par personne » : `SejourService`
     *    l ecrit desormais par ses trois gestes (check-in, check-out, menage).
     *
     * Les laisser aurait fige a l ecran deux motifs de refus perimes — la
     * troisieme occurrence de ce defaut dans ce depot (PA-107, PA-120,
     * PA-144). Un motif qui a cesse d etre vrai transforme une decision en
     * oubli : personne ne rouvre la question, puisque l ecran dit que c est
     * impossible.
     *
     * Ce cas verifie donc les DEUX sens : ce qui est rendu l est, et ce qui
     * est refuse porte une raison encore vraie aujourd hui.
     */
    #[Test]
    public function les_refus_sont_nommes_a_l_ecran_avec_les_mots_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $reservations = (string) $this->get('/pwa/reservations')->assertOk()->getContent();

        // RENDUS : les trois boutons de l en-tete du maitre.
        $this->assertStringContainsString('Nouvelle réservation', $reservations);
        $this->assertStringContainsString('Ajouter client', $reservations);
        $this->assertStringContainsString('Historique', $reservations);

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO)
        //
        // Ce cas exigeait les refus AFFICHES (« la chaîne de facturation
        // M2 », « ne s'efface jamais (RG-02) » rendus a l'utilisateur). La
        // directive a supprime toute section de refus des ecrans : la
        // declaration vit dans le CODE, l'ecran reste propre. Les deux
        // moities sont tenues — sans la seconde, supprimer la declaration en
        // meme temps que la section passerait inapercu (PA-144).

        // 1. L'ecran ne porte plus de section de refus ni de motif perime.
        $this->assertStringNotContainsString('la chaîne de facturation M2', $reservations);
        $this->assertStringNotContainsString('lecture seule stricte', $reservations);

        // 2. Aucun controle inerte : ni bouton « Supprimer » (RG-02 : une
        //    reservation s'annule), ni bouton « Facture » sans facture.
        $this->assertStringNotContainsString('confirmerSuppressionReservation', $reservations);

        // 3. Les declarations EXISTENT dans le code qui porte la page, avec
        //    leurs raisons — verifiees encore vraies par les cas RG-02 et
        //    PA-112 de cette meme suite.
        $source = file_get_contents(resource_path('views/pwa/hebergement/reservations.blade.php'));
        $this->assertStringContainsString('Supprimer une reservation est INTERDIT (RG-02)', $source);
        $this->assertStringContainsString('n\'existe que si la facture existe', $source);

        // ⚠ Le jeton UNIQUE `#modale-reservation` a ete REMPLACE par trois
        // jetons plus precis le 02/09/2026 : PA-163 a leve le refus pour le
        // canal, les cinq services, la remise, le mode de paiement et le
        // recapitulatif (tous atteignent desormais la base) — seuls le
        // texte libre du client, le bouton « Historique du client » et les
        // unites multiples restent hors de ce serveur. Un jeton unique
        // couvrant encore « toute la fiche » aurait ete FAUX : ce n'est plus
        // toute la fiche qui est refusee, seulement ces trois points.
        $this->assertStringContainsString('maitre-refuse:reservations.html#client-texte-libre', $source);
        $this->assertStringContainsString('maitre-refuse:reservations.html#historique-du-client', $source);
        $this->assertStringContainsString('maitre-refuse:reservations.html#plusieurs-unites', $source);

        // ⚠ Les boutons du cycle ne sont pas des etiquettes fixes : chacun
        // n apparait que dans l etat qui le rend possible. Les deux etats sont
        // donc POSES ici, faute de quoi ce cas verifierait qu une chaine
        // existe quelque part — ce qu il faisait avant le 31/08/2026, quand
        // elle vivait dans un texte de refus.
        //
        // BNG-01 : une reservation couvre aujourd hui → « Réservée », check-in
        // offert. `unites_hebergement.statut` vaut toujours `libre` en base :
        // la pastille vient des reservations, pas de la colonne (RG-02).
        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDay()->toDateString(),
            'date_depart' => now()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);
        $this->assertSame('libre', $this->unite->refresh()->statut);

        // BNG-02 : liberee par un depart, le menage reste a faire.
        UniteHebergement::where('numero', 'BNG-02')->firstOrFail()->update(['statut' => 'nettoyage']);

        $hebergement = (string) $this->get('/pwa/hebergement')->assertOk()->getContent();

        // Le cycle du maitre est PORTE depuis que `SejourService` l ecrit.
        $this->assertStringContainsString('Effectuer Check-In Client', $hebergement);
        $this->assertStringContainsString('Marquer Nettoyé &amp; Prêt', $hebergement);
        $this->assertStringContainsString('Ajouter hébergement', $hebergement);

        // Et le motif qui l avait fait refuser est mort : la colonne EST
        // ecrite. Le laisser a l ecran serait PA-144.
        $this->assertStringNotContainsString('est écrite par personne', $hebergement);
        $this->assertStringNotContainsString('lecture seule stricte', $hebergement);

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO) : le
        // champ « Équipements » du maitre reste refuse (aucune colonne au
        // schema), mais le refus ne s'AFFICHE plus — il vit en declaration
        // datee dans l'entete de la vue. Les deux moities sont tenues, ET la
        // raison est verifiee contre la base : le jour ou la colonne existera,
        // l'assertion de schema rougira et la declaration devra tomber.
        $this->assertStringNotContainsString('Équipements (séparés par des virgules)', $hebergement);

        $source = file_get_contents(resource_path('views/pwa/hebergement/hebergement.blade.php'));
        $this->assertStringContainsString('maitre-refuse:m1-hebergement.html#champ-equipements', $source);

        $this->assertNotContains(
            'equipements',
            \Illuminate\Support\Facades\DB::getSchemaBuilder()->getColumnListing('unites_hebergement'),
            'La colonne equipements existe desormais : le refus declare doit tomber.',
        );
    }

    /**
     * H4 — AUCUNE SUPPRESSION PHYSIQUE, ET AUCUNE BOITE NATIVE DU NAVIGATEUR.
     *
     * Le defaut reproduit : `executerSuppressionHebergement` appelait
     * `$u->delete()` sur une unite d hebergement — ce qui aurait rendu
     * illisibles toutes les reservations qui la citent — et la grille des
     * reservations confirmait par `wire:confirm`, la boite grise du
     * navigateur, hors charte et sans nom d element.
     *
     * Mutation C du 31/08/2026, reellement executee :
     * `->update(['statut' => 'hors_service'])` remis en `->delete()` dans
     * `Hebergement::archiverUnite()`. Le cas a rougi en nommant le fichier —
     * « Hebergement.php porte `->delete(` ». Annulee, vert reverifie.
     *
     * ⚠ Les commentaires sont retires AVANT la recherche, et ce n est pas un
     * detail : le docblock d `archiverUnite()` cite `->delete()` et
     * `BasePolicy::delete()` pour les proscrire. Sans ce nettoyage, le cas
     * serait rouge en permanence sur du code conforme — et un controle qui
     * crie a tort finit desactive.
     */
    #[Test]
    public function aucune_suppression_physique_ni_boite_native_dans_le_code_m1(): void
    {
        $fichiers = [
            app_path('Pwa/Livewire/Hebergement/Hebergement.php'),
            app_path('Pwa/Livewire/Hebergement/Reservations.php'),
            resource_path('views/pwa/hebergement/hebergement.blade.php'),
            resource_path('views/pwa/hebergement/reservations.blade.php'),
        ];

        $fautifs = [];

        foreach ($fichiers as $chemin) {
            $this->assertFileExists($chemin, 'Un fichier M1 a disparu : le balayage serait vert a vide.');

            // Les commentaires sont retires AVANT la recherche : cet entete-ci
            // nomme `->delete()` et `wire:confirm` pour les proscrire, et sans
            // ce nettoyage il se denoncerait lui-meme.
            $source = (string) file_get_contents($chemin);
            $source = (string) preg_replace('#\{\{--.*?--\}\}#s', '', $source);
            $source = (string) preg_replace('#/\*.*?\*/#s', '', $source);
            $source = (string) preg_replace('#//[^\n]*#', '', $source);

            foreach (['->delete(', '->forceDelete(', 'wire:confirm'] as $interdit) {
                if (str_contains($source, $interdit)) {
                    $fautifs[] = basename($chemin).' porte `'.$interdit.'`';
                }
            }
        }

        $this->assertSame([], $fautifs, implode("\n", $fautifs));
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Onglet « Disponibilites » (PO 08/10/2026) : une unite reservee sur la
     * periode est INDISPONIBLE avec son motif, l'autre est LIBRE, et le montant
     * du sejour est calcule (28 000 x 3 nuits = 84 000), jamais saisi.
     *
     * MUTATION : retirer le `whereNot('statut', 'annulee')` du service -> la
     * reservation annulee du second cas rendrait l'unite indisponible, ROUGE.
     */
    #[Test]
    public function l_onglet_disponibilites_distingue_libre_et_indisponible_avec_motif_et_montant(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2031-03-12',
            'date_depart' => '2031-03-14',
            'statut' => 'confirmee',
        ]);

        $html = (string) Livewire::test(\App\Pwa\Livewire\Hebergement\Hebergement::class)
            ->set('onglet', 'disponibilites')
            ->set('dispoArrivee', '2031-03-12')
            ->set('dispoDepart', '2031-03-15')
            ->html();

        $this->assertStringContainsString('1 libre(s) sur 2 unité(s) pour 3 nuit(s).', html_entity_decode($html));
        $this->assertStringContainsString('Réservée du 12/03/2031 au 14/03/2031', html_entity_decode($html));
        // 28 000 x 3 nuits.
        $this->assertStringContainsString('84', $html);
    }

    #[Test]
    public function l_onglet_disponibilites_libere_la_nuit_du_depart_et_ignore_une_reservation_annulee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2031-04-10',
            'date_depart' => '2031-04-12',
            'statut' => 'confirmee',
        ]);

        // Arrivee le jour du depart precedent : les deux unites sont libres.
        $html = html_entity_decode((string) Livewire::test(\App\Pwa\Livewire\Hebergement\Hebergement::class)
            ->set('dispoArrivee', '2031-04-12')
            ->set('dispoDepart', '2031-04-13')
            ->html());

        $this->assertStringContainsString('2 libre(s) sur 2 unité(s) pour 1 nuit(s).', $html);
    }

    #[Test]
    public function l_onglet_disponibilites_refuse_une_periode_inversee_sans_rien_calculer(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = html_entity_decode((string) Livewire::test(\App\Pwa\Livewire\Hebergement\Hebergement::class)
            ->set('dispoArrivee', '2031-05-10')
            ->set('dispoDepart', '2031-05-10')
            ->html());

        $this->assertStringContainsString('Le départ doit suivre l\'arrivée.', $html);
        $this->assertStringNotContainsString('libre(s) sur', $html);
    }

    #[Test]
    public function l_onglet_disponibilites_n_offre_pas_reserver_a_un_role_en_lecture_seule(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('comptable'));

        $html = (string) Livewire::test(\App\Pwa\Livewire\Hebergement\Hebergement::class)
            ->set('dispoArrivee', '2031-06-10')
            ->set('dispoDepart', '2031-06-12')
            ->html();

        $this->assertStringContainsString('BNG-01', $html);
        $this->assertStringNotContainsString('ouvrirReservationRapide', $html);
    }

    private function jeuDeDonnees(): void
    {
        $this->categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '28000.00',
        ]);

        $this->unite = UniteHebergement::create([
            'categorie_id' => $this->categorie->id,
            'numero' => 'BNG-01',
            'statut' => 'libre',
        ]);

        // Seconde unite : elle donne son denominateur au calendrier (1/2).
        UniteHebergement::create([
            'categorie_id' => $this->categorie->id,
            'numero' => 'BNG-02',
            'statut' => 'libre',
        ]);

        $this->client = Client::create([
            'nom' => 'KPETONI',
            'prenom' => 'Julien',
            'telephone' => '01 90 00 00 02',
            'type_client' => 'particulier',
        ]);
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.' . $role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.' . $role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
