import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achats/presentation/ecran_approvisionnement.dart';
import '../../features/achats/presentation/ecran_fournisseurs.dart';
import '../../features/auth/presentation/ecran_connexion.dart';
import '../../features/auth/presentation/ecran_demarrage.dart';
import '../../features/bar/presentation/ecran_carte_bar.dart';
import '../../features/bar/presentation/ecran_catalogue_boissons.dart';
import '../../features/comptabilite/presentation/ecran_comptabilite.dart';
import '../../features/transverse/presentation/ecran_aide_a_propos.dart';
import '../../features/transverse/presentation/ecran_contact_editeur.dart';
import '../../features/transverse/presentation/ecran_import_export.dart';
import '../../features/transverse/presentation/ecran_journal_audit.dart';
import '../../features/transverse/presentation/ecran_mon_profil.dart';
import '../../features/transverse/presentation/ecran_roles_permissions.dart';
import '../../features/etats/presentation/ecran_etats.dart';
import '../../features/vehicules/presentation/ecran_vehicules.dart';
import '../../features/crm/presentation/ecran_clients.dart';
import '../../features/depenses/presentation/ecran_depenses.dart';
import '../../features/facturation/presentation/ecran_facturation.dart';
import '../../features/notifications/presentation/ecran_notifications.dart';
import '../../features/rh/presentation/ecran_paie.dart';
import '../../features/tourisme/presentation/ecran_tourisme.dart';
import '../../features/parametres/presentation/ecran_parametres.dart';
import '../../features/stocks/presentation/ecran_inventaires.dart';
import '../../features/stocks/presentation/ecran_stocks.dart';
import '../../features/hebergement/presentation/ecran_hebergement.dart';
import '../../features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';
import '../../features/ventes/presentation/ecran_historique_ventes.dart';
import '../../features/hebergement/presentation/fiche_reservation.dart';
import '../../features/hebergement/presentation/ecran_reservations.dart';
import '../../features/pos/presentation/ecran_pos_comptant.dart';
import '../../features/pos/presentation/ecran_pos_heberges.dart';
import '../../features/restaurant/presentation/ecran_carte_restaurant.dart';
import '../../features/restaurant/presentation/ecran_restauration.dart';
import '../di/providers.dart';
import 'coquille_application.dart';

/// Routeur — `go_router`, un arbre unique adapté par point de rupture.
///
/// ## Toutes les routes servies mènent à un écran RÉEL
///
/// ⚠ Ce paragraphe annonçait « M1, les deux POS et M2 sont réels ; les autres
/// modules sont des coquilles » et « les autres routes restent des coquilles
/// nommées ». C'était vrai au Sprint 1 et faux depuis des mois : le routeur
/// sert aujourd'hui des écrans réels pour M1, M2, M3, M4, M5, M6, M7, M8, M9,
/// M10 (dépenses), M11, M12, M13, M14 et les paramètres.
///
/// Depuis le 14/09/2026 il n'existe plus **aucune** route de coquille : la
/// dernière (`/tourisme` → `EcranModuleVide`) est retirée avec le mécanisme
/// qui la produisait. Ce qui reste à livrer n'a pas de route du tout, et se
/// lit au menu — voir la note en fin de fichier.
///
/// ## La redirection ne dépend pas de l'écran
///
/// Un utilisateur non connecté est renvoyé vers `/connexion` par le routeur,
/// pas par un contrôle à l'intérieur de chaque écran. Un contrôle par écran
/// s'oublie sur le onzième.
final routeurProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    // L'ecran de demarrage est le premier vu, comme au maitre
    // (`prototype_v2/pages/splash.html`). C'est LUI qui aiguille ensuite, en
    // lisant la session reelle.
    initialLocation: '/demarrage',
    refreshListenable: _EcouteSession(ref),
    redirect: (context, state) {
      final connecte = ref.read(sessionProvider) != null;
      final versConnexion = state.matchedLocation == '/connexion';

      // Le demarrage s'affiche TOUJOURS, connecte ou non. Sans cette
      // exemption, la redirection l'ecarterait avant sa premiere image et
      // l'ecran serait livre sans jamais etre vu — la forme la plus courante
      // du defaut « declare, jamais branche » (PA-63).
      if (state.matchedLocation == '/demarrage') return null;

      if (!connecte && !versConnexion) return '/connexion';
      if (connecte && versConnexion) return '/tableau-de-bord';
      return null;
    },
    routes: [
      GoRoute(
        path: '/demarrage',
        builder: (context, state) => const EcranDemarrage(),
      ),
      GoRoute(
        path: '/connexion',
        builder: (context, state) => const EcranConnexion(),
      ),
      ShellRoute(
        builder: (context, state, enfant) => CoquilleApplication(
          routeActive: state.matchedLocation,
          child: enfant,
        ),
        routes: [
          // M11 — le tableau de bord, LOCAL depuis le 10/10/2026 (D157-D173).
          // ⚠ « SEUL écran qui exige le réseau » figurait ici : faux depuis
          // « zéro réseau » (corrigé le 12/10/2026).
          //
          // Il n'est pas dans `_routesModules` — qui rend `EcranModuleVide` —
          // parce qu'il a désormais un écran réel. C'est aussi la destination
          // d'atterrissage après connexion : elle affichait jusqu'ici un
          // placeholder.
          GoRoute(
            path: '/tableau-de-bord',
            builder: (context, state) => const EcranTableauDeBord(),
          ),
          // M1 Hébergement — écrans réels, livrés au Sprint 1.
          GoRoute(
            path: '/hebergement',
            // La page à QUATRE ONGLETS de la vue Blade : le plan, les
            // réservations en cours, le calendrier d'occupation et — depuis le
            // 09/10/2026, décision du Product Owner du 08/10/2026 — les
            // disponibilités sur une période.
            builder: (context, state) => const EcranHebergement(),
            routes: [
              GoRoute(
                path: 'reservations',
                builder: (context, state) => const EcranReservations(),
              ),
              GoRoute(
                // La fiche SANS chambre pré-retenue : c'est le chemin du
                // maître, qui fait choisir la chambre dans les lignes du
                // service.
                path: 'nouvelle-reservation',
                builder: (context, state) => const FicheReservation(),
              ),
              // ⚠ LES ROUTES DE LA FICHE ONT ÉTÉ RETIRÉES le 25/08/2026.
              //
              // La fiche de réservation s'ouvre désormais **en modale**, comme
              // au maître, depuis la grille et depuis les disponibilités. Ses
              // trois routes n'avaient donc plus aucun appelant — et une route
              // que rien n'atteint est exactement le défaut « déclaré, jamais
              // branché » que ce dépôt a passé deux jours à démonter (PA-63) :
              // elle se serait mise à diverger de la modale sans que personne
              // ne s'en aperçoive, faute de l'ouvrir jamais.
              //
              // Ce qui est perdu : le lien profond vers un formulaire. Il n'a
              // pas d'usage au comptoir — on ne met pas une saisie en favori —
              // et le maître n'en a jamais eu.
            ],
          ),
          // D2 — les deux points de vente. Un SEUL panier derrière les deux
          // écrans : la différence tient dans `typeVente` et `reservationId`,
          // et nulle part ailleurs.
          //
          // ⚠ Portage d'une PROPOSITION non ratifiée
          // (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3).
          //
          // Les deux routes sont sous `/bar` — le module M5 porte le droit
          // RBAC de vente au comptoir. Ce rattachement est à revoir le jour où
          // le panier deviendra multi-modules côté droits : un panier mêlant
          // bar et tourisme relève aujourd'hui du seul M5, ce qui est une
          // simplification assumée et non une décision d'architecture.
          GoRoute(
            path: '/pos',
            builder: (context, state) => const EcranPosComptant(),
            routes: [
              GoRoute(
                path: 'heberges',
                builder: (context, state) => const EcranPosHeberges(),
              ),
            ],
          ),
          // D3 — M2 Facturation : le registre, ses trois origines et le
          // ticket. Un SEUL registre derrière les trois onglets d'origine ;
          // le filtre est une colonne, pas trois entrepôts.
          // M6 — Gestion des stocks. LOCAL depuis le 09/10/2026 (schema v12,
          // `StocksDao`) : stock et CMP rejoues des mouvements du poste.
          // ⚠ Ce commentaire et le precedent (Parametres) disaient « EN LIGNE
          // SEULEMENT » (corrige le 12/10/2026, meme passe que M8 et M14 ;
          // Parametres est local depuis le 09/10/2026, schema v11).
          GoRoute(
            path: '/stocks',
            builder: (context, state) => const EcranStocks(),
          ),

          // M6 — Inventaires & fiches de stock. Meme regime que /stocks :
          // local, la fiche etant rejouee des mouvements du poste.
          GoRoute(
            path: '/stocks/inventaires',
            builder: (context, state) => const EcranInventaires(),
          ),

          // M7 — Approvisionnement et Fournisseurs. SOURCE LOCALE depuis le
          // 09/10/2026 (schema v13, `AchatsDao`) : plus aucun appel reseau, la
          // saisie est enregistree sur ce poste et ne part nulle part. Ce
          // commentaire disait « EN LIGNE SEULEMENT » : il decrivait le client
          // d'avant le 14/09/2026.
          GoRoute(
            path: '/approvisionnement',
            builder: (context, state) => const EcranApprovisionnement(),
          ),

          GoRoute(
            path: '/fournisseurs',
            builder: (context, state) => const EcranFournisseurs(),
          ),

          // M5 — Carte du bar. Lecture LOCALE : le catalogue est replique
          // (PA-129), l'ecran s'affiche donc au comptoir sans reseau. Poste
          // zero reseau : aucune colonne n'exige plus le serveur (la source du
          // stock de la carte est dans boissons_api.dart, a reverifier, 12/10/2026).
          GoRoute(
            path: '/bar',
            builder: (context, state) => const EcranCarteBar(),
          ),

          // Le catalogue des boissons — `m5-bar.html`. LOCAL, comme /bar
          // (`boissons_api.dart` lit la base du poste). ⚠ Ce commentaire
          // disait « EN LIGNE SEULEMENT » : faux depuis « zero reseau »
          // (corrige le 12/10/2026, meme passe que M8 et M14).
          //
          // ECART DELIBERE — `prototype_v2/pages/m5-bar.html` l.19-25.
          // Le maitre : declare la page « Ecran remplace », hors menu, et
          // renvoie vers `m5-bar-carte.html`.
          // Ici : elle recoit sa propre route, atteinte depuis la Carte du
          // bar.
          // Raison : `m5-bar-carte.html` a ete relue — elle n'a NI bouton
          // d'ajout NI modale de formulaire. La page annoncee comme
          // remplacante ne cree aucune boisson, alors que `cartes_boisson` est
          // vide sur une base neuve et que `POST /bar/boissons` n'avait aucun
          // client. Sans point d'entree, le point de vente n'aurait rien a
          // vendre — la forme exacte de PA-129. L'incoherence du maitre est
          // SIGNALEE au commanditaire, pas tranchee : c'est lui qui dira si
          // cette page revient au menu ou si la Carte recoit un formulaire.
          //
          // ⚠ PERIME depuis le 11/09/2026 : la Carte a recu son formulaire
          // (vue Blade, PO 03/09/2026 ; porte dans `modale_nouvelle_boisson`).
          // La route reste pour la modification et l'export du catalogue ; son
          // maintien est a la decision du Product Owner.
          GoRoute(
            path: '/bar/boissons',
            builder: (context, state) => const EcranCatalogueBoissons(),
          ),

          // M8 — Vehicules & Locations. Lecture et saisie LOCALES
          // (`vehicule_dao.dart`) : le poste est zero reseau depuis le
          // 14/09/2026, rien ne part au serveur. ⚠ Ce commentaire disait « EN
          // LIGNE SEULEMENT, sans cache » : il decrivait le client d'avant
          // « zero reseau » (corrige le 12/10/2026, controle du lot 1 B-6).
          //
          // L'entree « Vehicules » du menu pointait sur `EcranModuleVide` —
          // ce que l'Article 3.3 de la directive de conformite interdit
          // desormais : « l'entree doit naviguer vers l'ecran reel ». Les cinq
          // routes de `Route::prefix('vehicules')` existaient et n'avaient
          // AUCUN client.
          //
          // ⚠ Le drapeau `horsLigne: true` que portait l'ancienne entree etait
          // FAUX : il venait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` §0, qui
          // range M8 parmi les modules repliques. Aucune table de M8 n'existe
          // au schema Drift, et `TABLES_SYNCHRONISABLES` n'en connait aucune.
          // (Historique : l'ecran a dit un temps qu'il exigeait le reseau ;
          // depuis « zero reseau », ses tables sont sur le poste.)
          GoRoute(
            path: '/vehicules',
            builder: (context, state) => const EcranVehicules(),
          ),

          // M14 — Etats & Rapports. LOCAL depuis le 10/10/2026 (D175-D187) :
          // registre ferme de 12 etats relu du code PHP, catalogue filtre par
          // le droit de lecture sur le module SOURCE de la session du poste,
          // apercus calcules par les lecteurs des modules sources. ⚠ Ce
          // commentaire disait « EN LIGNE SEULEMENT, sans cache » et « droits
          // calcules au serveur » (corrige le 12/10/2026, controle du lot 1
          // B-6).
          //
          // L'entree « Etats & Rapports » du menu rendait `EcranModuleVide` —
          // ce que l'Article 3.3 de la directive de conformite interdit
          // desormais : « l'entree doit naviguer vers l'ecran reel ». Les
          // trois routes de `Route::prefix('etats')` existaient et n'avaient
          // AUCUN client.
          //
          // ⚠ La page du maitre est `m14-etats-studio.html`, PAS
          // `m14-etats.html` : cette derniere porte en tete un bandeau du
          // maitre lui-meme — « Ecran remplace… elle n'est plus au menu ».
          GoRoute(
            path: '/etats',
            builder: (context, state) => const EcranEtats(),
          ),

          // M4 — Restaurant & Cuisine. LOCAL depuis le 09/10/2026 (schema v14,
          // `RestaurantDao`) : portions et cout matiere rejoues du stock local
          // de M6. ⚠ Ce commentaire disait « EN LIGNE SEULEMENT, sans cache »
          // (corrige le 12/10/2026, meme passe que M8 et M14).
          //
          // L'entree « Restaurant » du menu pointe ici depuis le 26/08/2026 :
          // elle etait inerte faute d'API (PA-146), ce que l'Article 3.3 de la
          // directive de conformite interdit desormais.
          GoRoute(
            path: '/restaurant',
            builder: (context, state) => const EcranCarteRestaurant(),
          ),

          // Le catalogue de plats — `m4-restauration.html`.
          //
          // ECART DELIBERE — `prototype_v2/assets/js/shell.js` l.68.
          // Le maitre : la barre laterale ne porte qu'une entree pour M4,
          // « Restaurant », qui pointe sur `m4-restaurant-carte.html`. AUCUNE
          // page ni aucun menu du maitre ne lie vers `m4-restauration.html` :
          // elle est orpheline (verifie par balayage des 50 pages et des
          // scripts).
          // Ici : elle recoit sa propre route, atteinte depuis l'ecran de
          // carte.
          // Raison : c'est le SEUL endroit ou un plat se cree, et `plats` est
          // vide sur une base neuve. Sans point d'entree, l'ecran serait
          // inatteignable par un clic — le defaut de PA-133 — et le parc de
          // plats ne pourrait jamais etre renseigne, forme exacte de PA-128.
          // L'incoherence du maitre est signalee au commanditaire, pas
          // tranchee : c'est lui qui dira si cette page doit entrer au menu.
          GoRoute(
            path: '/restaurant/plats',
            builder: (context, state) => const EcranRestauration(),
          ),

          // M3 — Clients & Creances. Lecture entierement LOCALE : les clients
          // sont au registre synchronisable, le poste en detient une copie.
          GoRoute(
            path: '/crm',
            builder: (context, state) => const EcranClients(),
          ),

          // Les QUATRE modules d'exploitation, portés en local pur le
          // 14/09/2026 (« zéro réseau »). Leurs écrans existaient et
          // n'étaient atteignables PAR AUCUN CLIC : ni route, ni `route:`
          // au menu — l'Article 3.3 de la directive l'interdit, et c'est la
          // troisième fois que ce défaut est corrigé ici après Véhicules et
          // États & Rapports.
          //
          // ⚠ `/tourisme` était servi, mais par `_routesModules`, donc rendait
          // `EcranModuleVide` : une entrée qui ouvrait une coquille vide sur
          // un écran livré. La garde ne pouvait pas le voir — elle relit les
          // `path:` LITTÉRAUX du routeur, et celui-là venait d'une variable.
          GoRoute(
            path: '/depenses',
            builder: (context, state) => const EcranDepenses(),
          ),
          GoRoute(
            path: '/tourisme',
            builder: (context, state) => const EcranTourisme(),
          ),
          GoRoute(
            path: '/paie',
            builder: (context, state) => const EcranPaie(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const EcranNotifications(),
          ),

          GoRoute(
            path: '/parametres',
            builder: (context, state) => const EcranParametres(),
          ),

          GoRoute(
            path: '/facturation',
            builder: (context, state) => const EcranFacturation(),
          ),

          // Le JOURNAL des ventes — a ne pas confondre avec /facturation, qui
          // sert le REGISTRE des pieces. Une vente peut exister sans facture,
          // et une vente annulee reste une vente la ou une facture annulee
          // produit un avoir : les deux ecrans lisent des tables differentes
          // et n'affichent jamais le meme total.
          //
          // Lecture entierement LOCALE — les paniers, le referentiel des
          // tables et le registre de facturation vivent tous les trois dans la
          // base du poste. Premier ecran hors ligne depuis M11, Parametres, M6
          // et M7.
          GoRoute(
            path: '/historique-ventes',
            builder: (context, state) => const EcranHistoriqueVentes(),
          ),
          GoRoute(
            path: '/synchronisation',
            builder: (context, state) =>
                const EcranReservations(seulementEnSuspens: true),
          ),

          // Lot D du plan du PO (14/10/2026, PA-204) : les sept écrans qui
          // manquaient au menu latéral, au menu de compte, au panneau Accès
          // rapides, à la cloche et à la consultation de secours. Chacun suit
          // sa vue et DIT ce que le poste ne détient pas.
          //
          // M10 — le hub Comptabilité. `?onglet=` ouvre l'onglet que désigne
          // le lien (« Journal comptable », « Balance générale »… du panneau
          // Accès rapides), comme les pages séparées de la vue.
          GoRoute(
            path: '/comptabilite',
            builder: (context, state) => EcranComptabilite(
              ongletInitial: state.uri.queryParameters['onglet'],
            ),
          ),
          GoRoute(
            path: '/import-export',
            builder: (context, state) => const EcranImportExport(),
          ),
          GoRoute(
            path: '/roles-permissions',
            builder: (context, state) => const EcranRolesPermissions(),
          ),
          GoRoute(
            path: '/mon-profil',
            builder: (context, state) => const EcranMonProfil(),
          ),
          GoRoute(
            path: '/journal-audit',
            builder: (context, state) => const EcranJournalAudit(),
          ),
          GoRoute(
            path: '/aide-a-propos',
            builder: (context, state) => const EcranAideAPropos(),
          ),
          GoRoute(
            path: '/contact-editeur',
            builder: (context, state) => const EcranContactEditeur(),
          ),
        ],
      ),
    ],
  );
});

/// Redéclenche l'évaluation de `redirect` à chaque changement de session.
///
/// Sans cela, la déconnexion laisserait l'utilisateur sur l'écran courant
/// jusqu'à sa prochaine navigation manuelle.
final class _EcouteSession extends ChangeNotifier {
  _EcouteSession(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

// ⚠ `_RouteModule`, `_routesModules` et la boucle qui en tirait des
// `GoRoute` vers `EcranModuleVide` sont RETIRÉS le 14/09/2026. Le dernier
// module qu'ils servaient — Tourisme — a un écran réel depuis ce lot, et son
// entrée de menu ouvrait donc une coquille vide sur un écran livré.
//
// `lib/core/router/ecran_module_vide.dart` est SUPPRIMÉ le 08/10/2026, sur
// décision du Product Owner : il n'avait aucun appelant et aucune vue Blade
// (`docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md` §4ter).
//
// ⚠ Les trois entrées sans route (Comptabilité, Import & Export, Rôles &
// Permissions) et les cinq entrées du menu de compte (PA-204, 12/10/2026)
// ont leur écran depuis le 14/10/2026 (lot D, D424) : `/comptabilite`,
// `/import-export`, `/roles-permissions`, `/mon-profil`, `/journal-audit`,
// `/aide-a-propos`, `/contact-editeur`. Le message « écran non encore
// porté » ne vise plus aucune d'elles ; il reste le repli générique d'une
// entrée qui perdrait sa route.
