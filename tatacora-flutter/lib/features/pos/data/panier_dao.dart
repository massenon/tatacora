import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent être dans la portée du fichier : `@DriftAccessor`
// les résout par leur type, et un import de `app_database.dart` seul ne les
// réexporte pas. Sans ces lignes, le mixin généré est VIDE — sans erreur de
// génération, ce qui rend le diagnostic trompeur (leçon `reservation_dao.dart`).
import '../../../core/database/tables/bar_tables.dart';
import '../../../core/database/tables/caisse_tables.dart';
import '../../../core/database/tables/hebergement_tables.dart';
import '../../../core/database/tables/panier_tables.dart';
import '../../../core/database/tables/tourisme_tables.dart';
import '../../../core/database/tables/vehicules_tables.dart';
import '../../facturation/domain/regles_encaissement.dart'
    show estVideAuSensDePhp;
import '../../caisse/data/sessions_caisse_dao.dart';
import '../../caisse/domain/entities/session_caisse.dart';
import '../../caisse/domain/messages_caisse.dart';
import '../../caisse/domain/regles_caisse.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/calcul_tva.dart';
import '../../hebergement/domain/entities/fiche_reservation.dart'
    show TypeRemise;
import '../../parametres/data/parametres_dao.dart';
import '../domain/entities/article_vendable.dart';
import '../domain/entities/mode_reglement.dart';
import '../domain/entities/panier.dart';
import '../domain/entities/reference_catalogue.dart';
import '../domain/messages_ventes.dart';
import '../domain/remise_panier.dart';
import '../domain/repositories/panier_repository.dart';
import '../domain/unicite_panier_ouvert.dart';
import 'piece_de_la_vente.dart';
import 'tables_pos_dao.dart';
import '../../synchronisation/data/documents_autres_postes.dart';

import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';

part 'panier_dao.g.dart';

/// Accès Drift aux paniers.
///
/// ⚠ **Portage d'une PROPOSITION** (`docs/PROPOSITION_MODELE_PANIER_POS.md`),
/// non ratifiée : Q1, Q2 et Q3 restent ouvertes. Ce fichier porte deux des
/// trois points nommés — Q1 dans [_verifierCatalogue], Q2 dans [ouvrir].
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `PaniersLocalData`. La forme des tables ne
/// franchit pas cette frontière : sans quoi renommer une colonne casserait un
/// widget, et la couche présentation saurait qu'une base existe.
///
/// ## Aucune entrée n'est mise en file de synchronisation
///
/// C'est délibéré et vérifié par un test. `SynchronisationService::
/// TABLES_SYNCHRONISABLES` ne connaît que `reservations` et `clients` : une
/// opération sur `paniers` serait refusée à chaque tentative, et le poste
/// afficherait « en attente de synchronisation » sur quelque chose qui ne
/// partira jamais. C'est la famille de défauts PA-59 / PA-60 / PA-61 — un
/// indicateur qui dit que tout va bien pendant que rien n'a lieu.
@DriftAccessor(
  tables: [
    PaniersLocal,
    LignesPanierLocal,
    SessionsCaisseLocal,
    ReservationsLocal,
    CartesBoissonLocal,
    VehiculesLocal,
    CircuitsLocal,
  ],
)
class PanierDao extends DatabaseAccessor<AppDatabase> with _$PanierDaoMixin {
  PanierDao(
    super.db, {
    Uuid? uuid,
    DateTime Function()? maintenant,
    this.moteur,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : la règle 5 dépend du jour courant, et un test qui dépend de
  /// l'heure réelle échoue un jour sur mille — celui du départ.
  final DateTime Function() _maintenant;

  /// Le résolveur du moteur comptable, qui écrit la PIÈCE de la vente.
  ///
  /// Un résolveur et non une instance : `moteurComptableProvider` attend
  /// l'installation du référentiel, et un moteur construit trop tôt servirait un
  /// plan vide. **Sans résolveur, clôturer LÈVE** (`StateError`) : jamais une
  /// vente sans sa pièce par omission (règle du PO du 31/08/2026). Les lectures
  /// et les autres gestes du panier n'en ont pas besoin.
  final Future<MoteurComptable> Function()? moteur;

  Future<MoteurComptable> _moteurObligatoire() {
    final resolveur = moteur;
    if (resolveur == null) {
      throw StateError(
        'PanierDao sans moteur comptable : une vente ne s’encaisse jamais '
        'sans sa pièce.',
      );
    }
    return resolveur();
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  Future<List<Panier>> paniers({
    StatutPanier? statut,
    TypeVente? typeVente,
  }) async {
    final requete = select(paniersLocal);
    if (statut != null) {
      requete.where((p) => p.statut.equals(statut.code));
    }
    if (typeVente != null) {
      requete.where((p) => p.typeVente.equals(typeVente.code));
    }
    // Départage par identifiant après l'horodatage : deux paniers ouverts dans
    // la même milliseconde auraient sinon un ordre indéfini, et la liste
    // changerait d'ordre à chaque rafraîchissement sans qu'aucune donnée n'ait
    // bougé (même raison que `ReservationDao.reservations`).
    requete.orderBy([
      (p) => OrderingTerm.desc(p.ouvertLe),
      (p) => OrderingTerm.desc(p.id),
    ]);

    final entetes = await requete.get();
    return Future.wait(entetes.map(_avecLignes));
  }

  Future<Panier?> parId(String id) async {
    final entete = await (select(
      paniersLocal,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (entete == null) return null;
    return _avecLignes(entete);
  }

  /// ⚠ **Q2** — le panier ouvert d'un séjour, s'il existe.
  ///
  /// C'est aussi le garde-fou de [ouvrir], et il n'y en a pas d'autre : voir
  /// `unicite_panier_ouvert.dart` pour ce que cette garantie couvre, et ce
  /// qu'elle ne couvre pas.
  Future<Panier?> panierOuvertPour(String reservationId) async {
    final entete =
        await (select(paniersLocal)..where(
              (p) =>
                  p.reservationId.equals(reservationId) &
                  p.statut.equals(StatutPanier.ouvert.code),
            ))
            .getSingleOrNull();
    if (entete == null) return null;
    return _avecLignes(entete);
  }

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// Ouvre un panier.
  ///
  /// ⚠ **Q2 atterrit ici.** La lecture du panier existant et l'écriture du
  /// nouveau sont dans la **même transaction** : les séparer ouvrirait une
  /// fenêtre — courte, mais réelle — où deux ouvertures simultanées passeraient
  /// toutes les deux, ce qui est exactement ce que la règle 1 interdit.
  ///
  /// C'est le patron de `VerificationChevauchementService` (RG-01), transposé.
  Future<Panier> ouvrir({
    required TypeVente typeVente,
    String? reservationId,
    String? clientNom,
    String? pointVente,
    DateTime? dateDepartPrevue,
    String? tableId,
    String? espace,
  }) async {
    // Un panier sur séjour EXIGE un séjour, et un panier au comptant n'en a
    // pas. Sans cette contrainte, un panier de séjour orphelin verrait ses
    // consommations n'atteindre jamais la facture de départ.
    if (typeVente == TypeVente.surSejour && reservationId == null) {
      throw ArgumentError.value(
        reservationId,
        'reservationId',
        'Un panier de séjour doit être rattaché à une réservation.',
      );
    }
    if (typeVente == TypeVente.comptant && reservationId != null) {
      throw ArgumentError.value(
        reservationId,
        'reservationId',
        'Un panier au comptant ne se rattache à aucun séjour.',
      );
    }

    final id = _uuid.v4();
    final ouvertLe = _maintenant();

    await transaction(() async {
      if (reservationId != null) {
        final existant =
            await (select(paniersLocal)..where(
                  (p) =>
                      p.reservationId.equals(reservationId) &
                      p.statut.equals(StatutPanier.ouvert.code),
                ))
                .getSingleOrNull();
        if (existant != null) {
          throw PanierDejaOuvertException(
            reservationId: reservationId,
            panierExistantId: existant.id,
          );
        }
      }

      // Une TABLE ne porte qu'un panier ouvert a la fois — meme raison que
      // l'unicite par sejour : deux paniers sur une table scinderaient
      // l'addition, et la moitie manquerait au depart du client. La garde vit
      // DANS la transaction, sans quoi deux ouvertures simultanees passeraient
      // toutes les deux.
      if (tableId != null) {
        final surLaTable =
            await (select(paniersLocal)..where(
                  (p) =>
                      p.tableId.equals(tableId) &
                      p.statut.equals(StatutPanier.ouvert.code),
                ))
                .getSingleOrNull();
        if (surLaTable != null) {
          throw TableDejaServie(
            tableId: tableId,
            panierExistantId: surLaTable.id,
          );
        }
        // Lot F6 : occupée sur un AUTRE poste (descendu) — refusée ici comme
        // le serveur la refuserait.
        final ailleurs =
            await (select(attachedDatabase.occupationsTablesLocal)..where(
                  (o) => o.tableId.equals(tableId) & o.ouvert.equals(true),
                ))
                .get();
        if (ailleurs.isNotEmpty) {
          final table = await (select(
            attachedDatabase.tablesLocal,
          )..where((t) => t.id.equals(tableId))).getSingleOrNull();
          throw TableOccupeeAilleurs(
            tableId: tableId,
            libelle: table?.libelle ?? tableId,
          );
        }
      }

      await into(paniersLocal).insert(
        PaniersLocalCompanion.insert(
          id: id,
          typeVente: typeVente.code,
          tableId: Value(tableId),
          espace: Value(espace),
          reservationId: Value(reservationId),
          clientNom: Value(clientNom),
          pointVente: Value(pointVente),
          dateDepartPrevue: Value(dateDepartPrevue),
          statut: Value(StatutPanier.ouvert.code),
          ouvertLe: Value(ouvertLe),
        ),
      );

      // Lot F6 : l'OCCUPATION de la table part, arbitrée au serveur entre
      // postes (la table elle-même d'abord, si le serveur ne l'a pas).
      if (tableId != null) {
        await TablesPosDao(attachedDatabase).assurerConnueDuServeur(tableId);
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.paniers,
          entiteId: id,
          type: TypeOperationSync.creation,
          payload: chargeOuvertureTable(
            pointVente: pointVente ?? espace ?? 'Salle',
            tableId: tableId,
          ),
          horodatage: ouvertLe,
        );
      }
    });

    return (await parId(id))!;
  }

  /// Ajoute une consommation — prix ET libellé **copiés** (règle 3).
  ///
  /// [quantite] à `null` signifie « non précisée » et vaut 1. Une quantité
  /// explicitement nulle ou négative est **refusée**, jamais ramenée à 1 :
  /// c'est le défaut `Number(quantite) || 1` du prototype, qui facturait une
  /// unité pour une saisie à zéro.
  Future<Panier> ajouterLigne(
    String panierId,
    ArticleVendable article, {
    int? quantite,
  }) async {
    final prix = article.prix;
    if (prix == null) {
      // Un montant deviné est une perte à chaque service.
      throw PrixInconnu(article.libelle);
    }

    final q = quantite ?? 1;
    if (q <= 0) {
      throw ArgumentError.value(
        quantite,
        'quantite',
        'La quantité doit être un nombre positif.',
      );
    }

    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      await _verifierCatalogue(article.reference);

      // Regroupement : réajouter le même article **au même prix** incrémente
      // la ligne au lieu d'en créer une seconde. Deux lignes identiques sur une
      // addition font douter le client, et douter d'une addition suffit à
      // gâcher un départ.
      //
      // Le prix fait partie de la clé de regroupement : un article dont la
      // carte a changé pendant le séjour crée une ligne DISTINCTE, sans quoi
      // l'incrément écraserait l'ancien prix — c'est-à-dire réécrirait une
      // consommation déjà servie (règle 3).
      final existante =
          await (select(lignesPanierLocal)..where(
                (l) =>
                    l.panierId.equals(entete.id) &
                    l.moduleSource.equals(article.reference.module.code) &
                    l.codeArticle.equals(article.reference.code) &
                    l.prixUnitaire.equals(prix),
              ))
              .getSingleOrNull();

      if (existante != null) {
        await (update(
          lignesPanierLocal,
        )..where((l) => l.id.equals(existante.id))).write(
          LignesPanierLocalCompanion(quantite: Value(existante.quantite + q)),
        );
        return;
      }

      await into(lignesPanierLocal).insert(
        LignesPanierLocalCompanion.insert(
          id: _uuid.v4(),
          panierId: entete.id,
          moduleSource: article.reference.module.code,
          codeArticle: article.reference.code,
          libelle: article.libelle,
          prixUnitaire: prix,
          quantite: q,
          categorie: Value(article.categorie),
          ajouteeLe: Value(_maintenant()),
        ),
      );
    });

    return (await parId(panierId))!;
  }

  Future<Panier> retirerLigne(String panierId, String ligneId) async {
    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      final supprimees =
          await (delete(lignesPanierLocal)..where(
                (l) => l.id.equals(ligneId) & l.panierId.equals(entete.id),
              ))
              .go();
      // `go()` rend 0 sans lever quand rien ne correspond : sans ce contrôle,
      // retirer une ligne d'un AUTRE panier passerait pour un succès.
      if (supprimees == 0) throw LigneIntrouvable(ligneId);
    });

    return (await parId(panierId))!;
  }

  /// Retire **toutes** les lignes sans fermer le panier — « Vider » du maître.
  ///
  /// `pos.html:1012` : `panier = []; rendrePanier();`. Le panier reste
  /// **ouvert** et la table reste occupée ; c'est ce qui distingue ce geste
  /// d'« Abandonner », qui ferme et libère.
  ///
  /// En une seule transaction, et non une boucle sur [retirerLigne] : une
  /// coupure au milieu d'une boucle laisserait un panier à moitié vidé, que
  /// l'utilisateur croirait vide en voyant l'écran se rafraîchir.
  ///
  /// Passe par [_enteteModifiable], comme tous les autres gestes d'écriture :
  /// un panier clôturé est immuable (règle 2), et le vider serait une
  /// modification d'une vente déjà encaissée.
  Future<Panier> vider(String panierId) async {
    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      await (delete(
        lignesPanierLocal,
      )..where((l) => l.panierId.equals(entete.id))).go();
    });

    // Aucun contrôle de « 0 ligne supprimée » ici, contrairement à
    // `retirerLigne` : vider un panier déjà vide est un geste sans effet, pas
    // une erreur. Le refuser ferait échouer un clic anodin.
    return (await parId(panierId))!;
  }

  Future<Panier> modifierQuantite(
    String panierId,
    String ligneId,
    int quantite,
  ) async {
    if (quantite <= 0) {
      throw ArgumentError.value(
        quantite,
        'quantite',
        'La quantité doit être un nombre positif.',
      );
    }

    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      final modifiees =
          await (update(lignesPanierLocal)..where(
                (l) => l.id.equals(ligneId) & l.panierId.equals(entete.id),
              ))
              .write(LignesPanierLocalCompanion(quantite: Value(quantite)));
      if (modifiees == 0) throw LigneIntrouvable(ligneId);
    });

    return (await parId(panierId))!;
  }

  /// Clôture le panier, **fige** son montant et **passe la pièce comptable de
  /// la vente** — dans la MÊME transaction (règle du PO du 31/08/2026 : tout
  /// mouvement d'argent produit son écriture, et une pièce refusée n'écrit
  /// RIEN).
  ///
  /// Règle 5 : pour un panier de séjour, clôturer avant le jour du départ exige
  /// [anticipe]. Refuser en silence serait pire ; laisser passer sans rien dire
  /// aussi. La question se pose à l'écran, elle ne se tranche pas ici.
  ///
  /// ## Le déroulement est celui du SERVEUR, étage par étage
  ///
  /// Au comptoir, `PosComptant::encaissementReel` : panier vide, mode « note de
  /// chambre » refusé, caisse ouverte, puis `VenteService::enregistrer` — mode
  /// connu, chaque ligne (module encaissable, référence au catalogue), TVA, puis
  /// la pièce (journal, exercice, compte, centre). Pour un séjour,
  /// `PosHeberges::cloturerEtFacturer` enregistre la vente EN NOTE DE CHAMBRE,
  /// toujours : la consommation devient une créance (`4111`), aucune trésorerie
  /// ne bouge, et c'est l'encaissement de la facture qui la soldera.
  /// `test/features/pos/ventes_contre_serveur_test.dart` rejoue les VRAIS
  /// service et composant sur MySQL et compare chaque refus, sa phrase et chaque
  /// ligne de la pièce.
  ///
  /// ## Ce que le serveur fait ici et que le poste NE fait PAS (écarts nommés)
  ///
  /// * **Aucune sortie de stock** (RG-05/06). Le serveur sort les boissons du
  ///   stock du bar (`quantité / unites_vendables_par_unite_stock`) et crée puis
  ///   transmet une commande de cuisine pour les plats. Le poste détient le
  ///   stock M6, mais `cartes_boisson_local` ne porte pas le facteur de
  ///   conditionnement, et le poste n'a ni commande de cuisine ni dialogue
  ///   « Vendre quand même » : sortir « une unité par unité vendue » serait
  ///   inventer ce facteur. Le refus de rupture du serveur n'existe donc pas
  ///   ici. Lot à ordonner.
  /// * **Aucun numéro `V-AAAA-NNNNN`** : voir [libelleDeLaPiece].
  /// * **La remise** (21/10/2026, v35) : le TYPE et la VALEUR posés sur le
  ///   panier par [appliquerRemise] ; le montant est DÉRIVÉ par la réplique de
  ///   `Panier::remiseSur()` (`remise_panier.dart`), de nouveau JUGÉ ici — hors
  ///   bornes (une ligne retirée après coup), l'encaissement est refusé. La pièce
  ///   porte le NET : la ventilation par module est ramenée au net comme
  ///   `VenteService::ventilerAuNet` (le dernier module prend l'écart
  ///   d'arrondi). `montantCloture` est le net arrondi AU FRANC (le poste compte
  ///   en francs entiers ; un pourcentage peut donner des centimes que seule la
  ///   pièce garde), et la vente part avec le type et la valeur.
  /// * **Le prix est celui de l'AJOUT** (règle 3), là où le serveur relit le
  ///   catalogue à l'encaissement : la pièce suit l'argent réellement annoncé au
  ///   client et figé dans `montantCloture`.
  ///
  /// [auteurId] nomme celui qui encaisse (RG-15) : une pièce sans auteur est
  /// refusée par le moteur.
  Future<Panier> cloturer(
    String panierId, {
    bool anticipe = false,
    String? modePaiement,
    required String auteurId,
  }) async {
    // Avant toute lecture : un câblage manquant est une erreur de programme,
    // pas un refus métier, et elle ne doit dépendre d'aucune donnée.
    final moteurComptable = await _moteurObligatoire();

    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      final panier = await _avecLignes(entete);

      final estSejour = panier.typeVente == TypeVente.surSejour;

      // Le serveur ne dit pas la même chose au comptoir (« rien à encaisser »)
      // et au séjour (« Le panier du séjour est vide »).
      if (panier.lignes.isEmpty) {
        throw estSejour
            ? const PanierVide.duSejour()
            : const PanierVide.auComptoir();
      }

      // LE MODE. Un séjour est TOUJOURS porté sur la note de chambre
      // (`PosHeberges` écrit `'mode_paiement' => 'note_chambre'` en dur) : le
      // mode que l'écran aurait gardé en mémoire n'a aucun sens pour lui, et
      // l'enregistrer en espèces ferait entrer en caisse un argent que personne
      // n'a remis. Au comptoir, le mode vient de l'écran.
      final ModeReglement? mode = estSejour
          ? ModeReglement.noteChambre
          : ModeReglement.values
                .where((m) => m.code == modePaiement)
                .firstOrNull;

      // `PosComptant` refuse la note de chambre AVANT de regarder la caisse :
      // aucune chambre n'y porte de note.
      if (!estSejour && mode == ModeReglement.noteChambre) {
        throw const RefusVente(MessagesVentes.noteChambreAuComptoir);
      }

      // L'ENCAISSEMENT AU COMPTANT SE RATTACHE À UNE CAISSE OUVERTE — comme
      // `PosComptant::encaissementReel` (D221 option a, décision du PO). Le
      // serveur lit la session ouverte du point `bar`, REFUSE s'il n'y en a pas
      // (« Aucune caisse n'est ouverte à ce point de vente. »), puis écrit
      // `ventes.session_id`. Cette lecture et l'écriture ci-dessous sont dans la
      // MÊME transaction : une caisse close entre les deux ne laisserait pas
      // une vente rattachée à un tiroir fermé. L'ordre est celui du serveur :
      // panier vide d'abord, caisse ensuite.
      //
      // Un panier de SÉJOUR n'est pas concerné : il se porte sur la note de
      // chambre et le serveur n'écrit pas `session_id` dans `PosHeberges`.
      String? sessionId;
      if (!estSejour) {
        final session = await SessionsCaisseDao(
          attachedDatabase,
        ).sessionOuverte(pointDeCaisseDuComptoir);
        if (session == null) {
          throw const RefusCaisse(MessagesCaisse.refusSansCaisse);
        }
        sessionId = session.id;
      }

      if (!anticipe && panier.clotureEstAnticipee(_maintenant())) {
        throw ClotureAnticipeeNonConfirmee(panier.dateDepartPrevue!);
      }

      // ---- `VenteService::enregistrer` ------------------------------------
      //
      // Le mode d'abord. ⚠ ÉCART du poste : le serveur, appelé sans mode,
      // retombe sur les espèces ; ce poste REFUSE. Son journal des ventes
      // distingue « non renseigné » d'« espèces » exprès (`vente.dart`) : faire
      // entrer en caisse un argent que personne n'a compté est le défaut que ce
      // registre existe pour empêcher. L'écran envoie toujours un mode.
      if (mode == null) {
        throw RefusVente(
          modePaiement == null
              ? MessagesVentes.modeReglementAbsent
              : MessagesVentes.modeInconnu(modePaiement),
        );
      }

      // Chaque ligne, dans l'ordre du panier : le module d'abord, puis la
      // référence au catalogue — c'est l'ordre de `resoudreLignes`.
      final parModule = <String, int>{};
      for (final ligne in panier.lignes) {
        final code = ligne.reference.module.code;
        // Le séjour (note de chambre) ne porte que le bar et le restaurant :
        // tourisme et location s'encaissent au comptoir seulement.
        if (!modulesEncaissables.contains(code) ||
            (estSejour && !modulesEncaissablesAuSejour.contains(code))) {
          throw RefusVente(
            MessagesVentes.moduleNonEncaissable(
              MessagesVentes.modulesDuServeur[code] ?? code,
            ),
          );
        }
        if (!await _articleExiste(ligne.reference)) {
          throw RefusVente(
            MessagesVentes.referenceInconnue(ligne.reference.code),
          );
        }
        parModule[code] =
            (parModule[code] ?? 0) + centimesDeFrancs(ligne.montant);
      }

      // La remise, jugée comme `VenteService::enregistrer` (après les lignes,
      // avant la pièce) : hors bornes, elle REFUSE avant toute écriture. La
      // ventilation brute est d'abord mise dans l'ordre du serveur (les
      // modules encaissables, dans leur ordre) : c'est lui qui désigne le
      // dernier module, celui qui prend l'écart d'arrondi.
      final remiseCentimes = montantRemiseCentimes(
        totalFrancs: panier.total,
        type: panier.remiseType,
        valeurCentiemes: panier.remiseValeurCentiemes,
      );
      final netCentimes = panier.total * 100 - remiseCentimes;
      final netFrancs = (netCentimes + 50) ~/ 100;
      final parModuleNet = ventilerAuNet({
        for (final m in modulesEncaissables)
          if (parModule.containsKey(m)) m: parModule[m]!,
        for (final e in parModule.entries)
          if (!modulesEncaissables.contains(e.key)) e.key: e.value,
      }, netCentimes);

      final comptabilite = ComptabiliteDao(attachedDatabase);
      final centres = <String, String?>{
        for (final module in parModule.keys)
          module: (await comptabilite.centreParLibelle(
            centresParModule[module] ?? '',
          ))?.id,
      };
      final tva = ParametresTva.depuis(
        await ParametresDao(attachedDatabase).lireTout(),
      );

      final maintenant = _maintenant();
      await moteurComptable.passerEtValider(
        pieceDeLaVente(
          libelle: libelleDeLaPiece(entete.id),
          dateIso: formaterDateIso(maintenant),
          mode: mode,
          montantsParModule: parModuleNet,
          tva: tva,
          centreDuModule: (module) => centres[module],
        ),
        auteurId: auteurId,
      );

      await (update(paniersLocal)..where((p) => p.id.equals(entete.id))).write(
        PaniersLocalCompanion(
          statut: Value(StatutPanier.cloture.code),
          clotureLe: Value(maintenant),
          modePaiement: Value(mode.code),
          // Figé : le total d'un panier clôturé ne se recalcule plus. C'est le
          // NET encaissé (remise déduite), arrondi au franc.
          montantCloture: Value(netFrancs),
          sessionEncaissementId: Value(sessionId),
        ),
      );

      // Lot F1 : la vente part au serveur (document source, D246 : la pièce
      // `VTE` ci-dessus ne part JAMAIS, le serveur passe la sienne). Depuis
      // le lot F5 (17/10/2026), la vente de SÉJOUR aussi : portée en note de
      // chambre, rattachée à sa réservation (`GestionnaireVentes`).
      {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.ventes,
          entiteId: entete.id,
          type: TypeOperationSync.creation,
          payload: chargeVente(
            typeVente: estSejour ? 'sur_sejour' : 'comptant',
            reservationId: estSejour ? entete.reservationId : null,
            modePaiement: mode.code,
            sessionEncaissementId: sessionId,
            clotureLe: maintenant,
            pointVente: entete.pointVente,
            tableId: entete.tableId,
            clientNom: entete.clientNom,
            montantCloture: netFrancs,
            remiseType: panier.remiseType.name,
            remiseValeurCentiemes: panier.remiseValeurCentiemes,
            lignes: [
              for (final l in panier.lignes)
                (
                  moduleSource: l.reference.module.code,
                  codeArticle: l.reference.code,
                  libelle: l.libelle,
                  prixUnitaire: l.prixUnitaire,
                  quantite: l.quantite,
                ),
            ],
          ),
          horodatage: maintenant,
          dateMetier: jourIso(maintenant),
        );
      }

      // Lot F6 : la table se LIBÈRE au serveur, après la vente qu'elle porte.
      await _libererLaTable(entete.id, entete.tableId);
    });

    return (await parId(panierId))!;
  }

  /// Pose la REMISE du panier ouvert — « Remise » de la vue du comptoir
  /// (`appliquerRemise`, directive du PO du 02/09/2026).
  ///
  /// Le TYPE et la VALEUR sont stockés, jamais le montant. La validation EST la
  /// formule ([montantRemiseCentimes], réplique de `Panier::remiseSur`) : valeur
  /// non numérique ou négative, pourcentage au-delà de 100, montant au-delà du
  /// total — [RefusVente] avec la phrase du serveur, rien d'écrit. Un panier
  /// clôturé est refusé ([PanierNonModifiable]) : la remise se fige à la
  /// clôture comme les prix. Sans type (« Aucune »), la valeur retombe à zéro.
  ///
  /// [valeurSaisie] est le texte du champ (« 10 », « 12,5 », « 500 »).
  /// Rien n'est mis en file : la remise part avec la vente, à la clôture.
  Future<Panier> appliquerRemise(
    String panierId,
    TypeRemise type,
    String valeurSaisie,
  ) async {
    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      final panier = await _avecLignes(entete);
      var valeur = 0;
      if (type != TypeRemise.aucune) {
        final lue = centiemesDepuisSaisie(valeurSaisie);
        if (lue == null || lue < 0) {
          throw const RefusVente(MessagesVentes.remiseValeurInvalide);
        }
        valeur = lue;
      }
      // La dérivation VALIDE : hors bornes, elle lève ici, avant l'écriture.
      montantRemiseCentimes(
        totalFrancs: panier.total,
        type: type,
        valeurCentiemes: valeur,
      );
      await (update(paniersLocal)..where((p) => p.id.equals(entete.id))).write(
        PaniersLocalCompanion(
          remiseType: Value(type.name),
          remiseValeurCentiemes: Value(valeur),
        ),
      );
    });
    return (await parId(panierId))!;
  }

  /// Annule un panier ouvert. **Les lignes sont conservées.**
  ///
  /// Un panier annulé sans ses lignes ne dit plus ce qui avait été servi : on
  /// garde la trace pour que la question « qu'est-ce qui a été consommé ? »
  /// reste répondable après coup.
  Future<Panier> annuler(String panierId, String motif) async {
    final motifNet = motif.trim();
    if (motifNet.isEmpty) {
      throw ArgumentError.value(
        motif,
        'motif',
        'Un motif est requis : un panier annulé sans raison est '
            'indistinguable d’une erreur de manipulation.',
      );
    }

    await transaction(() async {
      final entete = await _enteteModifiable(panierId);
      await (update(paniersLocal)..where((p) => p.id.equals(entete.id))).write(
        PaniersLocalCompanion(
          statut: Value(StatutPanier.annule.code),
          clotureLe: Value(_maintenant()),
          motifAnnulation: Value(motifNet),
        ),
      );
      await _libererLaTable(entete.id, entete.tableId);
    });

    return (await parId(panierId))!;
  }

  /// Annule une VENTE encaissée — `VenteService::annuler`, RG-02 : la vente
  /// reste au journal, marquée annulée, rien n'est effacé.
  ///
  /// ## Dans l'ordre du serveur
  ///
  /// Le motif d'abord (`PosComptant::annulerVente` : « le journal doit dire
  /// pourquoi »), puis la vente (absente : un panier ouvert n'est pas une vente),
  /// puis « déjà annulée ». S'y ajoute la règle Q3 de ce poste : la vente d'un
  /// AUTRE poste ne s'annule que par l'administration ou le comptable, comme le
  /// serveur le refuserait à la synchronisation.
  ///
  /// ## Ce que l'annulation écrit, dans UNE transaction
  ///
  /// 1. la pièce `VTE` de la vente est CONTRE-PASSÉE en entier (RG-11 : jamais
  ///    supprimée) — une vente d'avant la pièce (31/08/2026) n'en a pas, et il
  ///    n'y a alors rien à inverser ;
  /// 2. le panier passe à `annule`, son motif écrit ; son montant figé, son mode
  ///    et sa session restent : ils disent ce qui a été encaissé avant
  ///    l'annulation ;
  /// 3. l'opération `ventes` / modification (`statut: annulee`, `motif`) part en
  ///    file si le serveur détient la vente. C'est LE SERVEUR qui compense les
  ///    sorties de stock (retour des boissons) et passe sa propre contre-pièce :
  ///    le poste n'écrit aucun mouvement de stock (RG-05, D240), il n'a donc
  ///    rien à compenser.
  ///
  /// Une facture émise pour la vente n'est PAS annulée : le serveur ne le fait
  /// pas non plus (une facture s'annule par avoir, autre geste).
  Future<Panier> annulerVente(
    String panierId,
    String motif, {
    required String auteurId,
  }) async {
    // Avant toute lecture : un câblage manquant est une erreur de programme.
    final moteurComptable = await _moteurObligatoire();

    if (estVideAuSensDePhp(motif)) {
      throw const RefusVente(MessagesVentes.motifAnnulationObligatoire);
    }
    final motifNet = motif.trim();

    await transaction(() async {
      final entete = await (select(
        paniersLocal,
      )..where((p) => p.id.equals(panierId))).getSingleOrNull();
      final statut = entete == null
          ? null
          : StatutPanier.depuisCode(entete.statut);
      if (entete == null || statut == StatutPanier.ouvert) {
        throw const RefusVente(MessagesVentes.venteAbsente);
      }
      if (statut == StatutPanier.annule) {
        throw RefusVente(MessagesVentes.dejaAnnulee(_numero(panierId)));
      }
      if (!await DocumentsAutresPostes(
        attachedDatabase,
      ).peutAnnuler(TableSynchronisee.ventes.nomServeur, panierId, auteurId)) {
        throw const RefusVente(DocumentsAutresPostes.refus);
      }

      final lignes = await ComptabiliteDao(
        attachedDatabase,
      ).lignesParLibelle(libelleDeLaPiece(panierId));
      if (lignes.isNotEmpty) {
        await moteurComptable.contrepasserPiece(
          lignes,
          auteurId: auteurId,
          motif: MessagesVentes.libelleContrepassation(_numero(panierId)),
        );
      }

      await (update(paniersLocal)..where((p) => p.id.equals(panierId))).write(
        PaniersLocalCompanion(
          statut: Value(StatutPanier.annule.code),
          motifAnnulation: Value(motifNet),
        ),
      );

      if (await DocumentsAutresPostes(
        attachedDatabase,
      ).connuDuServeur(TableSynchronisee.ventes, panierId)) {
        await OperationsSyncDao(attachedDatabase).enfiler(
          table: TableSynchronisee.ventes,
          entiteId: panierId,
          type: TypeOperationSync.modification,
          payload: chargeAnnulationVente(motif: motifNet),
        );
      }
    });

    return (await parId(panierId))!;
  }

  /// La référence lue à l'écran (`Vente.referenceLocale`) : huit caractères.
  static String _numero(String panierId) {
    final brut = panierId.replaceAll('-', '').toUpperCase();
    return brut.length <= 8 ? brut : brut.substring(0, 8);
  }

  /* ================================================================== */
  /* Gardes internes                                                     */
  /* ================================================================== */

  /// Lot F6 (18/10/2026) : la vente de CE poste, ANNULÉE au serveur
  /// (`VenteService::annuler`, à la PWA). Le panier clôturé devient annulé,
  /// et sa pièce `VTE` locale est CONTRE-PASSÉE en entier dans la même
  /// transaction — le journal du poste ne garde pas une vente que le serveur
  /// a défaite. Rejeu : déjà annulée, rien ne bouge. Appelé par la descente.
  Future<void> suivreAnnulationDuServeur(
    String panierId, {
    required String? motif,
    required String auteurId,
  }) => transaction(() async {
    final entete = await (select(
      paniersLocal,
    )..where((p) => p.id.equals(panierId))).getSingleOrNull();
    if (entete == null || entete.statut != StatutPanier.cloture.code) return;
    final lignes = await ComptabiliteDao(
      attachedDatabase,
    ).lignesParLibelle(libelleDeLaPiece(panierId));
    final motifNet = (motif == null || motif.trim().isEmpty)
        ? 'Annulée au serveur'
        : motif.trim();
    if (lignes.isNotEmpty) {
      await (await _moteurObligatoire()).contrepasserPiece(
        lignes,
        auteurId: auteurId,
        motif: motifNet,
      );
    }
    await (update(paniersLocal)..where((p) => p.id.equals(panierId))).write(
      PaniersLocalCompanion(
        statut: Value(StatutPanier.annule.code),
        motifAnnulation: Value(motifNet),
      ),
    );
  });

  /// Lot F6 : la fermeture de l'addition d'une TABLE part, si son ouverture
  /// est partie (le serveur arbitre l'occupation). Dans la transaction.
  Future<void> _libererLaTable(String panierId, String? tableId) async {
    if (tableId == null) return;
    if (!await DocumentsAutresPostes(
      attachedDatabase,
    ).connuDuServeur(TableSynchronisee.paniers, panierId)) {
      return;
    }
    await OperationsSyncDao(attachedDatabase).enfiler(
      table: TableSynchronisee.paniers,
      entiteId: panierId,
      type: TypeOperationSync.modification,
      payload: chargeFermetureTable(),
    );
  }

  /// L'en-tête du panier, à condition qu'il soit encore modifiable (règle 2).
  Future<PaniersLocalData> _enteteModifiable(String panierId) async {
    final entete = await (select(
      paniersLocal,
    )..where((p) => p.id.equals(panierId))).getSingleOrNull();
    if (entete == null) throw PanierIntrouvable(panierId);

    final statut = StatutPanier.depuisCode(entete.statut);
    if (statut != StatutPanier.ouvert) throw PanierNonModifiable(statut);
    return entete;
  }

  /// ⚠ **Q1 atterrit ici.** L'existence de l'article, vérifiée avant écriture.
  ///
  /// C'est ce qui remplace, sur ce client, la clé étrangère de l'option A du
  /// document — et c'est ce qui distingue ce modèle de l'identifiant polymorphe
  /// libre qu'il exclut (PA-76 : un champ qui peut viser une cible qui
  /// n'existe pas).
  ///
  /// **M4 Restaurant est vérifié comme les autres** depuis le 09/10/2026 :
  /// `plats_local` existe (schéma v14), et un code qui ne désigne aucun plat est
  /// refusé comme le ferait une clé étrangère. Jusqu'à cette date la ligne M4
  /// était acceptée sans rien vérifier — le seul écart avec l'option A, écrit
  /// plutôt que découvert plus tard, et désormais refermé.
  Future<void> _verifierCatalogue(ReferenceCatalogue reference) async {
    if (!await _articleExiste(reference)) {
      throw ArticleHorsCatalogue(reference.toString());
    }
  }

  /// L'article désigné figure-t-il au catalogue local ? Une seule lecture, deux
  /// appelants : l'ajout au panier ([_verifierCatalogue]) et la clôture, qui
  /// relit la référence comme `VenteService::resoudreLignes`.
  Future<bool> _articleExiste(ReferenceCatalogue reference) async {
    return switch (reference.module) {
      ModuleVendable.m5Bar =>
        await (select(
              cartesBoissonLocal,
            )..where((c) => c.id.equals(reference.code))).getSingleOrNull() !=
            null,
      ModuleVendable.m8Vehicules =>
        await (select(
              vehiculesLocal,
            )..where((v) => v.id.equals(reference.code))).getSingleOrNull() !=
            null,
      ModuleVendable.m9Tourisme =>
        await (select(
              circuitsLocal,
            )..where((c) => c.id.equals(reference.code))).getSingleOrNull() !=
            null,
      // Par `attachedDatabase` et non par le mixin : l'accesseur n'a pas
      // `PlatsLocal` dans sa liste de tables, et l'y ajouter ferait regénérer
      // un mixin pour une seule lecture.
      ModuleVendable.m4Restaurant =>
        await (select(
              attachedDatabase.platsLocal,
            )..where((p) => p.id.equals(reference.code))).getSingleOrNull() !=
            null,
    };
  }

  /* ================================================================== */
  /* Correspondances                                                    */
  /* ================================================================== */

  Future<Panier> _avecLignes(PaniersLocalData entete) async {
    final lignes =
        await (select(lignesPanierLocal)
              ..where((l) => l.panierId.equals(entete.id))
              ..orderBy([
                (l) => OrderingTerm.asc(l.ajouteeLe),
                (l) => OrderingTerm.asc(l.id),
              ]))
            .get();

    return Panier(
      id: entete.id,
      typeVente: TypeVente.depuisCode(entete.typeVente),
      statut: StatutPanier.depuisCode(entete.statut),
      ouvertLe: entete.ouvertLe,
      lignes: lignes.map(_versLigne).toList(growable: false),
      reservationId: entete.reservationId,
      clientNom: entete.clientNom,
      pointVente: entete.pointVente,
      tableId: entete.tableId,
      espace: entete.espace,
      dateDepartPrevue: entete.dateDepartPrevue,
      clotureLe: entete.clotureLe,
      modePaiement: entete.modePaiement,
      montantCloture: entete.montantCloture,
      motifAnnulation: entete.motifAnnulation,
      sessionEncaissementId: entete.sessionEncaissementId,
      statutTransmission: StatutTransmissionPanier.depuisCode(
        entete.statutTransmission,
      ),
      remiseType:
          TypeRemise.values
              .where((t) => t.name == entete.remiseType)
              .firstOrNull ??
          TypeRemise.aucune,
      remiseValeurCentiemes: entete.remiseValeurCentiemes,
    );
  }

  LignePanier _versLigne(LignesPanierLocalData d) => LignePanier(
    id: d.id,
    reference: ReferenceCatalogue(
      module: ModuleVendable.depuisCode(d.moduleSource),
      code: d.codeArticle,
    ),
    libelle: d.libelle,
    prixUnitaire: d.prixUnitaire,
    quantite: d.quantite,
    categorie: d.categorie,
    ajouteeLe: d.ajouteeLe,
  );
}
