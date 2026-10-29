<?php

declare(strict_types=1);

use App\Pwa\Http\Controllers\TicketThermiqueController;
use App\Pwa\Livewire\Accueil;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Pwa\Livewire\Bar\CarteBar;
use App\Pwa\Livewire\ChangementMotDePasseObligatoire;
use App\Pwa\Livewire\CodeSecours;
use App\Pwa\Livewire\Comptabilite\Analytique;
use App\Pwa\Livewire\Comptabilite\Balance;
use App\Pwa\Livewire\Comptabilite\Bilan;
use App\Pwa\Livewire\Comptabilite\Cloture;
use App\Pwa\Livewire\Comptabilite\CompteResultat;
use App\Pwa\Livewire\Comptabilite\CorrespondanceComptes;
use App\Pwa\Livewire\Comptabilite\EtatsFinanciers;
use App\Pwa\Livewire\Comptabilite\FluxTresorerie;
use App\Pwa\Livewire\Comptabilite\GrandLivre;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Livewire\Comptabilite\Journal;
use App\Pwa\Livewire\Comptabilite\NotesAnnexes;
use App\Pwa\Livewire\Comptabilite\PlanComptable;
use App\Pwa\Livewire\Connexion;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Etats\Etats;
use App\Pwa\Livewire\Etats\EtatsStudio;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Hebergement\Hebergement as PwaHebergement;
use App\Pwa\Livewire\Hebergement\Reservations as PwaReservations;
use App\Pwa\Livewire\Notifications\Hub as NotificationsHub;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Pwa\Livewire\Pos\PosHeberges;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use App\Pwa\Livewire\Restaurant\Restauration;
use App\Pwa\Livewire\Rh\CongesPlannings as PwaCongesPlannings;
use App\Pwa\Livewire\Rh\Paie as PwaPaie;
use App\Pwa\Livewire\Stocks\Inventaires;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Pwa\Livewire\Tourisme\Departs;
use App\Pwa\Livewire\Transverse\AideAPropos;
use App\Pwa\Livewire\Transverse\ComptesUtilisateurs;
use App\Pwa\Livewire\Transverse\ContactEditeur;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Pwa\Livewire\Transverse\JournalAudit;
use App\Pwa\Livewire\Transverse\MonProfil;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Pwa\Livewire\Transverse\RolesPermissions;
use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Pwa\Middleware\ExigerChangementMotDePasse;
use App\Pwa\Middleware\FermerLesSessionsPerimees;
use App\Pwa\Middleware\ForcerLectureSeule;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

/*
|---------------------------------------------------------------------------
| PWA TATACORA AFRIQUE — CANAL WEB OPÉRATIONNEL (CRUD RÉEL ET COMPLET)
|---------------------------------------------------------------------------
*/

Route::redirect('/', '/pwa/demarrage');

// Route Logout explicite pour résoudre RouteNotFoundException
Route::post('/logout', function (Request $request) {
    Auth::logout();
    $request->session()->invalidate();
    $request->session()->regenerateToken();

    return redirect()->route('pwa.connexion');
})->name('logout');

Route::prefix('pwa')
    ->middleware(ForcerLectureSeule::class)
    ->group(function () {
        Route::view('/demarrage', 'pwa.demarrage')->name('pwa.demarrage');
        Route::view('/hors-connexion', 'pwa.hors-connexion')->name('pwa.hors-connexion');

        // Logo / favicon téléversés (onglet « Logo & Apparence », 02/09/2026)
        // — servis par route car `storage:link` n'est pas garanti sur cPanel
        // mutualisé. Hors `auth` : le favicon est demandé sur l'écran de
        // connexion aussi — voir le docblock du contrôleur.
        Route::get('/apparence/{type}', \App\Pwa\Http\Controllers\ApparenceController::class)
            ->where('type', 'logo|favicon')
            ->name('pwa.apparence');

        Route::middleware('guest')->group(function () {
            Route::get('/connexion', Connexion::class)->name('pwa.connexion');
            // « J'ai perdu mon mot de passe administrateur » (29/10/2026) :
            // login + code de secours + nouveau mot de passe, sans session.
            Route::get('/mot-de-passe-administrateur-perdu', CodeSecours::class)->name('pwa.code-secours');
        });

        Route::middleware('auth')->group(function () {
            // Le compte dont le mot de passe vient d'être réinitialisé (29/10/2026) :
            // authentifié, mais hors des modules — c'est la SEULE page qu'il atteint.
            // `FermerLesSessionsPerimees` ferme d'abord les sessions d'un compte dont
            // le mot de passe a changé ; `ExigerChangementMotDePasse` enferme ensuite
            // le compte « changement obligatoire ».
            Route::middleware([FermerLesSessionsPerimees::class, ExigerChangementMotDePasse::class])
                ->get('/changement-mot-de-passe', ChangementMotDePasseObligatoire::class)
                ->name('pwa.changement-mot-de-passe');

            Route::middleware([FermerLesSessionsPerimees::class, ExigerChangementMotDePasse::class])->group(function () {
                // ACCUEIL & TABLEAU DE BORD (M11)
                Route::get('/', Accueil::class)->name('pwa.accueil');

                // PAGES TRANSVERSES
                Route::get('/aide-a-propos', AideAPropos::class)->name('pwa.aide-a-propos');
                Route::get('/contact-editeur', ContactEditeur::class)->name('pwa.contact-editeur');
                Route::get('/mon-profil', MonProfil::class)->name('pwa.mon-profil');
                // Décision PO du 18/10/2026 : le bouton « Synchroniser » du serveur.
                Route::get('/synchronisation-postes', SynchronisationPostes::class)->name('pwa.synchronisation-postes');

                Route::middleware('module:M14,L')
                    ->get('/journal-audit', JournalAudit::class)->name('pwa.journal-audit');

                Route::middleware('module:ROLES,L')->group(function () {
                    Route::get('/roles-permissions', RolesPermissions::class)->name('pwa.roles-permissions');
                    // Réinitialisation du mot de passe d'un compte par un administrateur (29/10/2026).
                    Route::get('/comptes-utilisateurs', ComptesUtilisateurs::class)->name('pwa.comptes-utilisateurs');
                });

                Route::middleware('module:PARAM,L')->group(function () {
                    Route::get('/parametres', Parametres::class)->name('pwa.parametres');
                    Route::get('/import-export', ImportExport::class)->name('pwa.import-export');
                });

                // HISTORIQUE DES VENTES (JOURNAL DE CAISSE - M5/M4)
                Route::get('/historique-ventes', \App\Pwa\Livewire\Pos\HistoriqueVentes::class)->name('pwa.historique-ventes');

                // DÉPENSES COURANTES (M10)
                Route::get('/depenses', \App\Pwa\Livewire\Depenses\Depenses::class)->name('pwa.depenses');

                // STOCKS (M6)
                Route::middleware('module:M6,L')
                    ->prefix('stocks')
                    ->name('pwa.stocks.')
                    ->group(function () {
                        Route::get('/', Stocks::class)->name('liste');
                        Route::get('/inventaires', Inventaires::class)->name('inventaires');
                    });

                // ACHATS & FOURNISSEURS (M7)
                Route::middleware('module:M7,L')
                    ->prefix('achats')
                    ->name('pwa.achats.')
                    ->group(function () {
                        Route::get('/', Achats::class)->name('liste');
                        Route::get('/approvisionnement', Approvisionnement::class)->name('approvisionnement');
                    });

                // HÉBERGEMENT & RÉSERVATIONS (M1)
                Route::middleware('module:M1,L')->group(function () {
                    Route::get('/reservations', PwaReservations::class)->name('pwa.reservations');
                    Route::get('/hebergement', PwaHebergement::class)->name('pwa.hebergement');
                });

                // CLIENTS & CRÉANCES (M3)
                Route::middleware('module:M3,L')
                    ->get('/clients', ClientsCreances::class)->name('pwa.clients');

                // POINT DE VENTE (POS TRANSVERSAL - M5/M4/M1)
                Route::middleware('module:M5,L')->prefix('pos')->name('pwa.pos.')->group(function () {
                    // ⚠ Aucune route `/pwa/pos` (retiree le 31/08/2026).
                    //
                    // Elle servait `PosComptant` comme `/pos/comptant`, donc deux
                    // URL rendaient la meme page et le meme <title> : rien ne
                    // disait au lecteur laquelle est la vraie.
                    //
                    // Une redirection a d'abord ete posee a la place ; elle ne
                    // faisait que deplacer le probleme, la garde de chargement
                    // traitant tout non-200 comme un echec. Or `grep` sur
                    // `pwa.pos.index` rend ZERO appelant dans tout le depot, et
                    // la barre laterale pointe deja sur `pwa.pos.comptant` :
                    // l'alias ne servait personne. On supprime plutot que de
                    // rediriger — une URL morte de moins vaut mieux qu'un saut
                    // qu'il faut ensuite expliquer a chaque garde.
                    Route::get('/comptant', PosComptant::class)->name('comptant');
                    Route::get('/heberges', PosHeberges::class)->name('heberges');

                    // TICKET DE CAISSE 80 mm — décision du Product Owner du
                    // 01/09/2026, en attendant la validation de l'API MECeF par
                    // la Direction des impôts (PA-101, troisième papier de la
                    // même pièce). Un CONTRÔLEUR, pas un composant Livewire —
                    // voir le docblock de `TicketThermiqueController` : la page
                    // ne persiste rien, `module:M5,L` (hérité du groupe) et
                    // `ForcerLectureSeule` (GET) suffisent à la protéger.
                    Route::get('/ventes/{vente}/ticket-thermique', TicketThermiqueController::class)
                        ->name('ticket-thermique');
                });

                // ⚠ RETIRÉ le 31/08/2026 : `Route::get('/pwa/pos')` était déclarée
                // DANS le groupe `prefix('pwa')` et produisait l'URL `/pwa/pwa/pos`.
                // Les trois routes `pwa.pos.*` ci-dessus servent déjà l'écran, et
                // elles portent le RBAC `module:M5,L` que celle-ci n'avait pas.

                // BAR (M5)
                Route::middleware('module:M5,L')
                    ->get('/bar/carte', CarteBar::class)->name('pwa.bar.carte');

                // RESTAURANT (M4)
                Route::middleware('module:M4,L')
                    ->prefix('restaurant')
                    ->name('pwa.restaurant.')
                    ->group(function () {
                        Route::get('/carte', CarteRestaurant::class)->name('carte');
                        Route::get('/plats', Restauration::class)->name('plats');
                    });

                // TOURISME (M9)
                Route::middleware('module:M9,L')
                    ->get('/tourisme', Departs::class)->name('pwa.tourisme');

                // VÉHICULES (M8)
                Route::middleware('module:M8,L')
                    ->get('/vehicules', Locations::class)->name('pwa.vehicules');

                // FACTURATION (M2)
                Route::middleware('module:M2,L')
                    ->get('/facturation', Facturation::class)->name('pwa.facturation');

                // RESSOURCES HUMAINES & PAIE (M13)
                //
                // ⚠ Ces DEUX routes ont pointé sur `JournalAudit` : l'entrée de
                // menu « Personnel & Paie » ouvrait le Journal d'Audit, et
                // « Notifications » aussi. Une entrée de menu qui ouvre un AUTRE
                // écran est pire qu'une entrée inerte — l'utilisateur croit avoir
                // vu le module et en repart persuadé qu'il n'existe pas.
                //
                // ⚠ La phrase qui suivait — « les deux composants nomment leur
                // refus à l'écran » — est PÉRIMÉE depuis le 02/09/2026 : les deux
                // écrans de refus ont été remplacés par les écrans réels. `Rh\Paie`
                // sert l'effectif, les bulletins calculés, le livre de paie, les
                // déclarations et les barèmes ; `Notifications\Hub` sert le
                // référentiel des modèles, des déclencheurs et des canaux. Ce qui
                // reste vrai : chacun OMET ce qu'il ne peut pas tenir et le nomme
                // en jeton de refus dans sa vue, jamais en bouton inerte.
                //
                // ⚠ AUCUNE route n'est ajoutée pour `m13-rh.html` ni pour
                // `m12-notifications.html` : le maître déclare LUI-MÊME ces deux
                // pages remplacées et hors menu (« Écran remplacé. […] elle n'est
                // plus au menu »), exactement comme `m3-crm.html`. Leur porter une
                // route créerait une seconde entrée menant à un écran que le
                // client a retiré — le défaut même que le bloc ci-dessus décrit.
                Route::middleware('module:M13,L')
                    ->get('/paie', PwaPaie::class)->name('pwa.paie');

                // CONGÉS & PLANNINGS (M13) — écran créé le 21/10/2026 : les services
                // de domaine (RG-13, RG-14) n'avaient aucun écran.
                Route::middleware('module:M13,L')
                    ->get('/rh/conges-plannings', PwaCongesPlannings::class)->name('pwa.conges-plannings');

                // NOTIFICATIONS (M12)
                Route::middleware('module:M12,L')
                    ->get('/notifications', NotificationsHub::class)->name('pwa.notifications');

                // ÉTATS & RAPPORTS (M14)
                Route::middleware('module:M14,L')
                    ->prefix('etats')
                    ->name('pwa.etats.')
                    ->group(function () {
                        Route::get('/', EtatsStudio::class)->name('studio');
                        Route::get('/bibliotheque', Etats::class)->name('bibliotheque');
                    });


                // COMPTABILITÉ SYSCOHADA (M10)
                Route::middleware('module:M10,L')
                    ->prefix('comptabilite')
                    ->name('pwa.comptabilite.')
                    ->group(function () {
                        Route::get('/', Hub::class)->name('hub');
                        Route::get('/plan-comptable', PlanComptable::class)->name('plan-comptable');
                        // Décision du PO du 26/10/2026 : les comptes se modifient sur le web.
                        Route::get('/correspondance-comptes', CorrespondanceComptes::class)->name('correspondance-comptes');
                        Route::get('/journal', Journal::class)->name('journal');
                        Route::get('/grand-livre', GrandLivre::class)->name('grand-livre');
                        Route::get('/balance', Balance::class)->name('balance');
                        Route::get('/compte-resultat', CompteResultat::class)->name('compte-resultat');
                        Route::get('/bilan', Bilan::class)->name('bilan');
                        Route::get('/flux-tresorerie', FluxTresorerie::class)->name('flux-tresorerie');
                        Route::get('/notes-annexes', NotesAnnexes::class)->name('notes-annexes');
                        Route::get('/etats-financiers', EtatsFinanciers::class)->name('etats-financiers');
                        Route::get('/analytique', Analytique::class)->name('analytique');
                        Route::get('/cloture', Cloture::class)->name('cloture');
                    });
            });
        });
    });
