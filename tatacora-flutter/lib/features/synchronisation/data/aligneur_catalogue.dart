import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../achats/domain/entities/fournisseur.dart';
import '../../achats/data/reglements_fournisseur_dao.dart';
import '../../comptabilite/data/comptabilite_dao.dart';
import '../../comptabilite/data/ecritures_serveur_dao.dart';
import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/entities/comptabilite.dart'
    show StatutExercice;
import '../../facturation/data/facture_dao.dart';
import '../../hebergement/domain/entities/fiche_reservation.dart'
    show CanalReservation;
import '../../notifications/data/notifications_dao.dart';
import '../../parametres/data/parametres_depot_local.dart';
import '../../transverse/data/roles_dao.dart';
import '../../pos/data/panier_dao.dart';
import '../../facturation/data/paiements_facture_dao.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import '../../facturation/domain/entities/piece_facturation.dart';
import '../../facturation/domain/repositories/facture_repository.dart';
import '../../restaurant/domain/calcul_restaurant.dart' show typesDeMenu;
import '../../rh/domain/entities/conge_planning.dart';
import '../../stocks/domain/calcul_stock.dart' show echelleQuantite;
import '../../stocks/domain/entities/etat_stock.dart';
import '../domain/descente_catalogue.dart';
import '../domain/operation_sync.dart';
import 'descente_catalogue_dao.dart';
import 'operations_sync_dao.dart';

part 'aligneur_documents.dart';

/// Les ÉCRIVAINS « aligner » du catalogue descendu (lot F2b, 15/10/2026) :
/// un par table, chacun écrit UNE définition du serveur sur le poste. Depuis
/// le lot F3 (16/10/2026), aussi les clients et les réservations des autres
/// postes ([_client], [_reservation]).
///
/// ## Ce qu'ils ne font JAMAIS
///
///  * enfiler : ils n'appellent pas `OperationsSyncDao.enfiler` — ce qui
///    descend du serveur n'y remonte pas (une boucle). Un test balaie ce
///    fichier, et un autre compte la file après une descente ;
///  * supprimer : un élément archivé au serveur (`actif: false`) est archivé
///    ici quand la table locale sait archiver (fournisseur `actif`, unité
///    `hors_service`) ; sinon il reste, et le bilan le compte ;
///  * écrire une valeur CALCULÉE (stock, coût moyen, coût matière — PA-129) :
///    le serveur ne les envoie pas, et aucune colonne ici ne les reçoit ;
///  * réécrire une clé primaire locale : l'identifiant serveur est traduit
///    par `correspondances_sync_local` ;
///  * violer une clé étrangère : un élément qui cite ce que le poste n'a pas
///    encore est rendu [EnAttenteDeDependance], et gardé pour la reprise ;
///  * écraser une modification locale NON POUSSÉE : [ConserveLocalement] —
///    elle partira, et le dernier écrit gagnant du serveur tranchera.
///
/// ## L'auteur d'une création descendue
///
/// `menus_local`, `recettes_local`, `plats_local` et `fournisseurs_local`
/// exigent un `cree_par` (vraie clé étrangère vers `utilisateurs_local`). Le
/// serveur ne descend pas ses colonnes d'audit (le poste n'a pas ses
/// comptes) : la ligne descendue porte le compte local qui a déclenché la
/// synchronisation, à défaut le plus ancien administrateur actif du poste
/// ([auteur]). C'est l'auteur de l'ÉCRITURE sur ce poste, pas l'auteur de
/// la fiche au serveur — écart nommé ; aucun écran ne l'affiche. Sans aucun
/// compte local, l'élément attend ([EnAttenteDeDependance]).
class AligneurCatalogue {
  AligneurCatalogue(
    this._db,
    this._dao, {
    required this._auteur,
    DateTime Function()? maintenant,
    this._moteur,
  }) : _maintenant = maintenant ?? DateTime.now;

  /// Lot F6 : voir `DescenteCatalogue.moteur` — remis aux DAO qui
  /// contre-passent la pièce d'un document de CE poste annulé au serveur.
  final Future<MoteurComptable> Function()? _moteur;

  final AppDatabase _db;
  final DescenteCatalogueDao _dao;
  final Future<String?> Function() _auteur;
  final DateTime Function() _maintenant;

  OperationsSyncDao get _file => OperationsSyncDao(_db);

  /// Aligne UN élément. À appeler dans une transaction (le moteur l'isole
  /// dans un point de sauvegarde : une exception n'emporte que lui).
  Future<IssueAlignement> aligner(ElementCatalogue e) async {
    final idLocal = await _dao.idLocal(e.table.nomServeur, e.id);
    final synchronisee = e.table.tableSynchronisee;
    if (synchronisee != null &&
        await _file.enSuspens(synchronisee.nomServeur, idLocal)) {
      return const ConserveLocalement(
        'une modification locale de cet élément attend encore de partir',
      );
    }
    final d = e.donnees;
    return switch (e.table) {
      TableDescendue.pointsStockage => _pointStockage(idLocal, d),
      TableDescendue.articles => _article(idLocal, e),
      TableDescendue.cartesBoisson => _boisson(idLocal, d),
      TableDescendue.menus => _menu(idLocal, d),
      TableDescendue.recettes => _recette(idLocal, d),
      TableDescendue.plats => _plat(idLocal, d),
      TableDescendue.indisponibilitesCarte => _indisponibilite(idLocal, d),
      TableDescendue.categoriesHebergement => _categorie(idLocal, d),
      TableDescendue.unitesHebergement => _unite(idLocal, e),
      TableDescendue.fournisseurs => _fournisseur(idLocal, e),
      TableDescendue.clients => _client(idLocal, e),
      TableDescendue.reservations => _reservation(idLocal, e),
      // Lot F4 : les documents des autres postes (`aligneur_documents.dart`).
      TableDescendue.sejours ||
      TableDescendue.sessionsCaisse ||
      TableDescendue.ventes ||
      TableDescendue.depenses ||
      TableDescendue.tablesSalle ||
      TableDescendue.paniers ||
      TableDescendue.factures ||
      TableDescendue.avoirs ||
      TableDescendue.paiements ||
      TableDescendue.commandesAchat ||
      TableDescendue.bonsReception ||
      TableDescendue.reglementsFournisseur ||
      TableDescendue.mouvementsStock ||
      TableDescendue.circuits ||
      TableDescendue.guides ||
      TableDescendue.reservationsTour ||
      TableDescendue.vehicules ||
      TableDescendue.contratsLocation ||
      TableDescendue.entretiensVehicule ||
      TableDescendue.servicesRh ||
      TableDescendue.employes ||
      TableDescendue.bulletinsPaie ||
      TableDescendue.plannings ||
      TableDescendue.conges => alignerDocument(idLocal, e),
      TableDescendue.centresCout => _centre(e),
      TableDescendue.parametresSysteme => _parametre(e),
      TableDescendue.roles => _role(idLocal, e),
      TableDescendue.modelesNotification => _modeleNotification(idLocal, e),
      TableDescendue.exercicesComptables => _exercice(e),
      TableDescendue.ecrituresComptables => _ecritureServeur(e),
    };
  }

  /* ================================================================== */
  /* Outils                                                              */
  /* ================================================================== */

  static String? _texte(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static bool _booleen(Object? v) => v == true || v == 1 || v == '1';

  /// `AAAA-MM-JJ` d'une date du serveur (`2026-10-01` ou
  /// `2026-10-01 00:00:00`), `null` si absente ; lève si illisible.
  static String? _jour(Object? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch('$v');
    if (m == null) throw const FormatException('date illisible');
    return m.group(1);
  }

  /// L'identifiant LOCAL d'un élément CITÉ, ou `null` si le poste ne le
  /// détient pas encore.
  Future<String?> _cite(
    TableDescendue table,
    String idServeur,
    TableInfo<Table, Object?> locale,
  ) async {
    final id = await _dao.idLocal(table.nomServeur, idServeur);
    final r = await _db
        .customSelect(
          'SELECT 1 FROM ${locale.actualTableName} WHERE id = ? LIMIT 1',
          variables: [Variable.withString(id)],
        )
        .get();
    return r.isEmpty ? null : id;
  }

  /// Une ligne d'un AUTRE identifiant porte-t-elle la même clé naturelle ET
  /// une opération encore non poussée ? Alors c'est très probablement le
  /// même élément créé ici hors ligne : l'envoi le fera fusionner au serveur
  /// et la correspondance reviendra — l'insérer maintenant ferait un doublon.
  Future<bool> _homonymeEnSuspens(
    TableDescendue table,
    String idLocal,
    String cle,
    Iterable<({String id, String cle})> lignes,
  ) async {
    final synchronisee = table.tableSynchronisee;
    if (synchronisee == null) return false;
    for (final l in lignes) {
      if (l.id == idLocal || l.cle != cle) continue;
      if (await _file.enSuspens(synchronisee.nomServeur, l.id)) return true;
    }
    return false;
  }

  /* ================================================================== */
  /* Retraits de la carte du jour (21/10/2026)                           */
  /* ================================================================== */

  /// Un retrait du serveur (un autre poste, la PWA). L'article cité doit être
  /// détenu ici. Le serveur tient UN retrait en cours par article : celui qui
  /// arrive remplace un retrait local EN COURS du même article (déjà parti), et
  /// attend si ce dernier n'est pas encore envoyé (l'envoi le fera fusionner).
  Future<IssueAlignement> _indisponibilite(
    String id,
    Map<String, Object?> d,
  ) async {
    final motif = _texte(d['motif']);
    if (motif == null) return const RefuseParLePoste('motif absent');
    final boissonServeur = _texte(d['boisson_id']);
    final platServeur = _texte(d['plat_id']);
    if ((boissonServeur == null) == (platServeur == null)) {
      return const RefuseParLePoste(
        'un retrait porte sur une boisson ou sur un plat, pas sur les deux',
      );
    }
    DateTime? instant(Object? v) {
      if (v == null) return null;
      final lu = DateTime.tryParse('$v'.trim().replaceFirst(' ', 'T'));
      if (lu == null) throw const FormatException('instant illisible');
      return lu;
    }

    final debut = instant(d['date_indisponibilite']);
    if (debut == null) return const RefuseParLePoste('date de retrait absente');
    final retour = instant(d['date_retour_disponibilite']);

    String? boisson;
    String? plat;
    if (boissonServeur != null) {
      boisson = await _cite(
        TableDescendue.cartesBoisson,
        boissonServeur,
        _db.cartesBoissonLocal,
      );
      if (boisson == null) {
        return const EnAttenteDeDependance('boisson pas encore reçue');
      }
    } else {
      plat = await _cite(TableDescendue.plats, platServeur!, _db.platsLocal);
      if (plat == null) {
        return const EnAttenteDeDependance('plat pas encore reçu');
      }
    }

    final t = _db.indisponibilitesCarteLocal;
    if (retour == null) {
      final memeArticle =
          await (_db.select(t)..where(
                (l) =>
                    l.id.equals(id).not() &
                    l.dateRetourDisponibilite.isNull() &
                    (boisson != null
                        ? l.boissonId.equals(boisson)
                        : l.platId.equals(plat!)),
              ))
              .get();
      for (final autre in memeArticle) {
        if (await _file.enSuspens('indisponibilites_carte', autre.id)) {
          return _homonyme;
        }
      }
      for (final autre in memeArticle) {
        await (_db.delete(t)..where((l) => l.id.equals(autre.id))).go();
      }
    }
    await _db
        .into(t)
        .insertOnConflictUpdate(
          IndisponibilitesCarteLocalCompanion.insert(
            id: id,
            boissonId: Value(boisson),
            platId: Value(plat),
            motif: motif,
            commentaire: Value(_texte(d['commentaire'])),
            dateIndisponibilite: debut,
            dateRetourDisponibilite: Value(retour),
          ),
        );
    return const Aligne();
  }

  static const _homonyme = ConserveLocalement(
    'un élément du même nom, créé sur ce poste, attend encore de partir',
  );

  Future<String?> _auteurOuNull() => _auteur();

  static const _sansAuteur = EnAttenteDeDependance(
    'aucun compte local pour porter l’écriture',
  );

  /* ================================================================== */
  /* Points de stockage                                                  */
  /* ================================================================== */

  Future<IssueAlignement> _pointStockage(
    String id,
    Map<String, Object?> d,
  ) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final type = _texte(d['type']);
    if (type != null && TypePoint.depuisCode(type) == null) {
      return RefuseParLePoste('type de point de stockage inconnu « $type »');
    }
    final t = _db.pointsStockageLocal;
    final existant = await (_db.select(
      t,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (existant == null) {
      final tous = await _db.select(t).get();
      if (await _homonymeEnSuspens(
        TableDescendue.pointsStockage,
        id,
        cleNaturelle(libelle),
        [for (final p in tous) (id: p.id, cle: cleNaturelle(p.libelle))],
      )) {
        return _homonyme;
      }
    }
    await _db
        .into(t)
        .insertOnConflictUpdate(
          PointsStockageLocalCompanion.insert(
            id: id,
            libelle: libelle,
            type: Value(type),
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Articles                                                            */
  /* ================================================================== */

  Future<IssueAlignement> _article(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final libelle = _texte(d['libelle']);
    final unite = _texte(d['unite_mesure']);
    if (libelle == null || unite == null) {
      return const RefuseParLePoste('libellé ou unité de mesure absent');
    }
    final suivi = SuiviArticle.depuisCode(_texte(d['suivi']) ?? 'permanent');
    if (suivi == null) {
      return RefuseParLePoste('suivi inconnu « ${d['suivi']} »');
    }
    final seuil = d['seuil_alerte'] == null
        ? 0
        : entierDepuisDecimal(d['seuil_alerte'], 2);
    if (seuil == null) {
      return RefuseParLePoste(
        'seuil d’alerte « ${d['seuil_alerte']} » : deux décimales au plus',
      );
    }
    String? point;
    final pointServeur = _texte(d['point_stockage_id']);
    if (pointServeur != null) {
      point = await _cite(
        TableDescendue.pointsStockage,
        pointServeur,
        _db.pointsStockageLocal,
      );
      if (point == null) {
        return const EnAttenteDeDependance('point de stockage pas encore reçu');
      }
    }

    final t = _db.articlesLocal;
    final existant = await (_db.select(
      t,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (existant == null) {
      final tous = await _db.select(t).get();
      if (await _homonymeEnSuspens(
        TableDescendue.articles,
        id,
        cleNaturelle(libelle),
        [for (final a in tous) (id: a.id, cle: cleNaturelle(a.libelle))],
      )) {
        return _homonyme;
      }
    } else if (existant.uniteMesure != unite) {
      // La règle de `StocksDao.modifierArticle` : l'historique serait relu
      // dans une autre unité, et le stock changerait de sens.
      final mouvements = await _db
          .customSelect(
            'SELECT COUNT(*) AS n FROM mouvements_stock_local '
            'WHERE article_id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();
      if ((mouvements.data['n'] as int) > 0) {
        return RefuseParLePoste(
          'unité de mesure changée au serveur (« ${existant.uniteMesure} » → '
          '« $unite ») sur un article qui a des mouvements ici',
        );
      }
    }
    await _db
        .into(t)
        .insertOnConflictUpdate(
          ArticlesLocalCompanion.insert(
            id: id,
            libelle: libelle,
            categorie: _texte(d['categorie']) ?? '',
            uniteMesure: unite,
            // La conversion de `StocksDao._seuil` : centièmes → unité, zéro
            // pour un article journalier.
            seuilAlerte: suivi == SuiviArticle.journalier
                ? 0
                : seuil / echelleQuantite,
            suivi: Value(suivi.code),
            pointStockageId: Value(point),
          ),
        );
    return Aligne(archiveNonPortee: !e.actif);
  }

  /* ================================================================== */
  /* Boissons                                                            */
  /* ================================================================== */

  static const _categoriesBoisson = {'locale', 'maison', 'importee'};

  Future<IssueAlignement> _boisson(String id, Map<String, Object?> d) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final categorie = _texte(d['categorie']);
    if (!_categoriesBoisson.contains(categorie)) {
      return RefuseParLePoste('catégorie de boisson inconnue « $categorie »');
    }
    final prix = entierDepuisDecimal(d['prix_vente'], 0);
    if (prix == null) {
      return RefuseParLePoste(
        'prix « ${d['prix_vente']} » : une fraction de franc ne se vend pas '
        'sur ce poste',
      );
    }
    var article = '';
    final articleServeur = _texte(d['article_id']);
    if (articleServeur != null) {
      final local = await _cite(
        TableDescendue.articles,
        articleServeur,
        _db.articlesLocal,
      );
      if (local == null) {
        return const EnAttenteDeDependance('article de stock pas encore reçu');
      }
      article = local;
    }
    final unites = _decimalPositif(d['unites_vendables_par_unite_stock']);
    final t = _db.cartesBoissonLocal;
    if (await (_db.select(
          t,
        )..where((b) => b.id.equals(id))).getSingleOrNull() ==
        null) {
      final tous = await _db.select(t).get();
      if (await _homonymeEnSuspens(
        TableDescendue.cartesBoisson,
        id,
        cleNaturelle(libelle),
        [for (final b in tous) (id: b.id, cle: cleNaturelle(b.libelle))],
      )) {
        return _homonyme;
      }
    }
    await _db
        .into(t)
        .insertOnConflictUpdate(
          CartesBoissonLocalCompanion.insert(
            id: id,
            articleId: article,
            libelle: libelle,
            categorie: categorie!,
            prixVente: prix.toDouble(),
            unitesVendables: Value(unites),
          ),
        );
    return const Aligne();
  }

  /// Un décimal strictement positif, gardé EN TEXTE (`24.0000`) ; tout le
  /// reste est « non reçu » (`null`) — jamais un 1 inventé.
  static String? _decimalPositif(Object? brut) {
    final texte = brut?.toString().trim();
    if (texte == null || !RegExp(r'^\d+(\.\d+)?$').hasMatch(texte)) return null;
    return double.parse(texte) > 0 ? texte : null;
  }

  /* ================================================================== */
  /* Menus, fiches techniques, plats                                     */
  /* ================================================================== */

  Future<IssueAlignement> _menu(String id, Map<String, Object?> d) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final type = _texte(d['type']);
    if (!typesDeMenu.contains(type)) {
      return RefuseParLePoste('type de menu inconnu « $type »');
    }
    final String? debut;
    final String? fin;
    try {
      debut = _jour(d['date_debut']);
      fin = _jour(d['date_fin']);
    } on FormatException {
      return const RefuseParLePoste('dates de saison illisibles');
    }
    final t = _db.menusLocal;
    final existant = await (_db.select(
      t,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (existant != null) {
      await (_db.update(t)..where((m) => m.id.equals(id))).write(
        MenusLocalCompanion(
          libelle: Value(libelle),
          type: Value(type!),
          dateDebut: Value(debut),
          dateFin: Value(fin),
        ),
      );
      return const Aligne();
    }
    final tous = await _db.select(t).get();
    if (await _homonymeEnSuspens(
      TableDescendue.menus,
      id,
      cleNaturelle(libelle),
      [for (final m in tous) (id: m.id, cle: cleNaturelle(m.libelle))],
    )) {
      return _homonyme;
    }
    final auteur = await _auteurOuNull();
    if (auteur == null) return _sansAuteur;
    await _db
        .into(t)
        .insert(
          MenusLocalCompanion.insert(
            id: id,
            libelle: libelle,
            type: type!,
            dateDebut: Value(debut),
            dateFin: Value(fin),
            creeLe: _maintenant(),
            creePar: auteur,
          ),
        );
    return const Aligne();
  }

  Future<IssueAlignement> _recette(String id, Map<String, Object?> d) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final lignesBrutes = d['lignes'];
    if (lignesBrutes is! List) {
      return const RefuseParLePoste('composition absente');
    }
    final lignes = <({String article, int milliemes})>[];
    for (final l in lignesBrutes) {
      if (l is! Map) {
        return const RefuseParLePoste('ligne de composition illisible');
      }
      final articleServeur = _texte(l['article_id']);
      final milliemes = entierDepuisDecimal(l['quantite_unitaire'], 3);
      if (articleServeur == null || milliemes == null || milliemes <= 0) {
        return RefuseParLePoste(
          'quantité unitaire « ${l['quantite_unitaire']} » : trois décimales '
          'au plus, strictement positive',
        );
      }
      final local = await _cite(
        TableDescendue.articles,
        articleServeur,
        _db.articlesLocal,
      );
      if (local == null) {
        return const EnAttenteDeDependance(
          'un article de la composition pas encore reçu',
        );
      }
      lignes.add((article: local, milliemes: milliemes));
    }

    final t = _db.recettesLocal;
    final existante = await (_db.select(
      t,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (existante != null) {
      await (_db.update(t)..where((r) => r.id.equals(id))).write(
        RecettesLocalCompanion(libelle: Value(libelle)),
      );
    } else {
      final tous = await _db.select(t).get();
      if (await _homonymeEnSuspens(
        TableDescendue.recettes,
        id,
        cleNaturelle(libelle),
        [for (final r in tous) (id: r.id, cle: cleNaturelle(r.libelle))],
      )) {
        return _homonyme;
      }
      final auteur = await _auteurOuNull();
      if (auteur == null) return _sansAuteur;
      await _db
          .into(t)
          .insert(
            RecettesLocalCompanion.insert(
              id: id,
              libelle: libelle,
              creeLe: _maintenant(),
              creePar: auteur,
            ),
          );
    }
    // La composition est REMPLACÉE, jamais fusionnée — comme
    // `RestaurantDao.enregistrerRecette` et le serveur.
    await (_db.delete(
      _db.ingredientsRecetteLocal,
    )..where((l) => l.recetteId.equals(id))).go();
    for (final l in lignes) {
      await _db
          .into(_db.ingredientsRecetteLocal)
          .insertOnConflictUpdate(
            IngredientsRecetteLocalCompanion.insert(
              recetteId: id,
              articleId: l.article,
              quantiteMilliemes: l.milliemes,
            ),
          );
    }
    return const Aligne();
  }

  Future<IssueAlignement> _plat(String id, Map<String, Object?> d) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final menuServeur = _texte(d['menu_id']);
    final recetteServeur = _texte(d['recette_id']);
    if (menuServeur == null || recetteServeur == null) {
      // `plats_local` exige un menu ET une fiche (vraies clés étrangères) :
      // le rattachement direct à un article n'est pas porté sur ce poste.
      return const RefuseParLePoste(
        'plat sans menu ou sans fiche technique : non porté sur ce poste',
      );
    }
    final prix = entierDepuisDecimal(d['prix_vente'], 0);
    if (prix == null) {
      return RefuseParLePoste(
        'prix « ${d['prix_vente']} » : une fraction de franc ne se vend pas '
        'sur ce poste',
      );
    }
    final menu = await _cite(TableDescendue.menus, menuServeur, _db.menusLocal);
    if (menu == null) {
      return const EnAttenteDeDependance('menu pas encore reçu');
    }
    final recette = await _cite(
      TableDescendue.recettes,
      recetteServeur,
      _db.recettesLocal,
    );
    if (recette == null) {
      return const EnAttenteDeDependance('fiche technique pas encore reçue');
    }
    final t = _db.platsLocal;
    final existant = await (_db.select(
      t,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    if (existant != null) {
      await (_db.update(t)..where((p) => p.id.equals(id))).write(
        PlatsLocalCompanion(
          menuId: Value(menu),
          recetteId: Value(recette),
          libelle: Value(libelle),
          prixVente: Value(prix),
          prixProvisoire: Value(_booleen(d['prix_provisoire'])),
          prixCorrigeMain: Value(_booleen(d['prix_corrige_main'])),
        ),
      );
      return const Aligne();
    }
    final tous = await _db.select(t).get();
    if (await _homonymeEnSuspens(
      TableDescendue.plats,
      id,
      cleNaturelle(libelle),
      [for (final p in tous) (id: p.id, cle: cleNaturelle(p.libelle))],
    )) {
      return _homonyme;
    }
    final auteur = await _auteurOuNull();
    if (auteur == null) return _sansAuteur;
    await _db
        .into(t)
        .insert(
          PlatsLocalCompanion.insert(
            id: id,
            menuId: menu,
            recetteId: recette,
            libelle: libelle,
            prixVente: prix,
            prixProvisoire: Value(_booleen(d['prix_provisoire'])),
            prixCorrigeMain: Value(_booleen(d['prix_corrige_main'])),
            creeLe: _maintenant(),
            creePar: auteur,
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Hébergement                                                         */
  /* ================================================================== */

  Future<IssueAlignement> _categorie(String id, Map<String, Object?> d) async {
    final libelle = _texte(d['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final capacite = d['capacite_max'] is int
        ? d['capacite_max']! as int
        : entierDepuisDecimal(d['capacite_max'], 0);
    if (capacite == null || capacite <= 0) {
      return RefuseParLePoste('capacité « ${d['capacite_max']} » invalide');
    }
    final tarif = entierDepuisDecimal(d['tarif_base'], 0);
    if (tarif == null) {
      return RefuseParLePoste(
        'tarif « ${d['tarif_base']} » : une fraction de franc ne se vend pas '
        'sur ce poste',
      );
    }
    final t = _db.categoriesHebergementLocal;
    if (await (_db.select(
          t,
        )..where((c) => c.id.equals(id))).getSingleOrNull() ==
        null) {
      final tous = await _db.select(t).get();
      if (await _homonymeEnSuspens(
        TableDescendue.categoriesHebergement,
        id,
        cleNaturelle(libelle),
        [for (final c in tous) (id: c.id, cle: cleNaturelle(c.libelle))],
      )) {
        return _homonyme;
      }
    }
    await _db
        .into(t)
        .insertOnConflictUpdate(
          CategoriesHebergementLocalCompanion.insert(
            id: id,
            libelle: libelle,
            capaciteMax: capacite,
            tarifBase: tarif.toDouble(),
          ),
        );
    return const Aligne();
  }

  static const _statutsUnite = {
    'libre',
    'reservee',
    'occupee',
    'nettoyage',
    'hors_service',
  };

  /// Une unité. Le STATUT appartient au cycle de ce poste (séjours) : une
  /// unité existante ne reçoit du serveur que son archivage (`actif: false`
  /// → `hors_service`) ou sa réintégration (`actif: true` sur une unité hors
  /// service → `libre`, comme `ParcDao.restaurer`). Une unité NOUVELLE naît
  /// dans le statut du serveur.
  Future<IssueAlignement> _unite(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final numero = _texte(d['numero']);
    if (numero == null) return const RefuseParLePoste('numéro absent');
    final categorieServeur = _texte(d['categorie_id']);
    if (categorieServeur == null) {
      return const RefuseParLePoste('catégorie absente');
    }
    final categorie = await _cite(
      TableDescendue.categoriesHebergement,
      categorieServeur,
      _db.categoriesHebergementLocal,
    );
    if (categorie == null) {
      return const EnAttenteDeDependance('catégorie pas encore reçue');
    }
    final t = _db.unitesHebergementLocal;
    final existante = await (_db.select(
      t,
    )..where((u) => u.id.equals(id))).getSingleOrNull();
    if (existante != null) {
      final statut = !e.actif
          ? 'hors_service'
          : existante.statut == 'hors_service'
          ? 'libre'
          : existante.statut;
      await (_db.update(t)..where((u) => u.id.equals(id))).write(
        UnitesHebergementLocalCompanion(
          numero: Value(numero),
          categorieId: Value(categorie),
          statut: Value(statut),
        ),
      );
      return const Aligne();
    }
    final tous = await _db.select(t).get();
    if (await _homonymeEnSuspens(
      TableDescendue.unitesHebergement,
      id,
      cleNaturelle(numero),
      [for (final u in tous) (id: u.id, cle: cleNaturelle(u.numero))],
    )) {
      return _homonyme;
    }
    final serveur = _texte(d['statut']);
    await _db
        .into(t)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: id,
            categorieId: categorie,
            numero: numero,
            statut: !e.actif
                ? 'hors_service'
                : _statutsUnite.contains(serveur)
                ? serveur!
                : 'libre',
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Fournisseurs                                                        */
  /* ================================================================== */

  Future<IssueAlignement> _fournisseur(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final raison = _texte(d['raison_sociale']);
    if (raison == null) return const RefuseParLePoste('raison sociale absente');
    final evaluation = _texte(d['evaluation']);
    if (evaluation != null &&
        EvaluationFournisseur.depuisCode(evaluation) == null) {
      return RefuseParLePoste('évaluation inconnue « $evaluation »');
    }
    final t = _db.fournisseursLocal;
    final existant = await (_db.select(
      t,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (existant != null) {
      await (_db.update(t)..where((f) => f.id.equals(id))).write(
        FournisseursLocalCompanion(
          raisonSociale: Value(raison),
          contact: Value(_texte(d['contact'])),
          categorie: Value(_texte(d['categorie'])),
          conditionsPaiement: Value(_texte(d['conditions_paiement'])),
          evaluation: Value(evaluation),
          actif: Value(e.actif),
        ),
      );
      return const Aligne();
    }
    final tous = await _db.select(t).get();
    if (await _homonymeEnSuspens(
      TableDescendue.fournisseurs,
      id,
      cleNaturelle(raison),
      [for (final f in tous) (id: f.id, cle: cleNaturelle(f.raisonSociale))],
    )) {
      return _homonyme;
    }
    final auteur = await _auteurOuNull();
    if (auteur == null) return _sansAuteur;
    await _db
        .into(t)
        .insert(
          FournisseursLocalCompanion.insert(
            id: id,
            raisonSociale: raison,
            contact: Value(_texte(d['contact'])),
            categorie: Value(_texte(d['categorie'])),
            conditionsPaiement: Value(_texte(d['conditions_paiement'])),
            evaluation: Value(evaluation),
            creeLe: _maintenant(),
            creePar: auteur,
            actif: Value(e.actif),
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Clients (lot F3)                                                    */
  /* ================================================================== */

  static const _typesClient = {'particulier', 'groupe', 'agence', 'structure'};

  /// Un client. Le serveur ne FUSIONNE jamais deux clients
  /// (`GestionnaireClients` : deux homonymes peuvent être deux personnes) :
  /// aucun contrôle d'homonyme ici non plus. La modification d'une fiche
  /// part au serveur (dernière saisie gagnante) : la version descendue est
  /// celle qui a gagné, et elle remplace la fiche locale quand plus rien
  /// n'attend (garde d'[aligner]). `solde` ne descend pas (calcul) ; un
  /// client archivé reste proposé (aucune archive locale), et le bilan le
  /// compte.
  Future<IssueAlignement> _client(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final nom = _texte(d['nom']);
    final telephone = _texte(d['telephone']);
    if (nom == null || telephone == null) {
      return const RefuseParLePoste('nom ou téléphone absent');
    }
    final type = _texte(d['type_client']);
    if (!_typesClient.contains(type)) {
      return RefuseParLePoste('type de client inconnu « $type »');
    }
    await _db
        .into(_db.clientsLocal)
        .insertOnConflictUpdate(
          ClientsLocalCompanion.insert(
            id: id,
            nom: nom,
            prenom: Value(_texte(d['prenom'])),
            telephone: telephone,
            email: Value(_texte(d['email'])),
            typeClient: type!,
            statutSync: const Value('synchronise'),
          ),
        );
    return Aligne(archiveNonPortee: !e.actif);
  }

  /* ================================================================== */
  /* Réservations (lot F3)                                               */
  /* ================================================================== */

  /// Le rang d'un statut dans le cycle d'un séjour ; `annulee` est à part
  /// (terminal, depuis n'importe quel rang).
  static const _rangStatut = {
    'en_attente': 0,
    'confirmee': 1,
    'en_cours': 2,
    'terminee': 3,
  };

  static const _modesServeur = {
    'especes': 'especes',
    'mobile_money': 'mobileMoney',
    'virement': 'virement',
    'cheque': 'cheque',
    'credit': 'credit',
  };

  static const _remises = {'aucune', 'pourcentage', 'montant'};

  /// Une réservation d'un AUTRE poste (ou de la PWA) : c'est ce qui fait
  /// qu'un poste ne revend pas une chambre déjà prise (RG-01, décision du
  /// PO du 16/10/2026).
  ///
  /// ## Nouvelle sur ce poste : écrite telle que le serveur la tient
  ///
  /// Référence `SRV-` + 8 caractères de l'identifiant (le serveur n'en a
  /// pas — la convention de `ReservationDto`, PA-57) ; tarif absent = 0,
  /// visiblement faux plutôt que recalculé au tarif du jour (même
  /// précédent) ; aucune ligne de service ; le canal ne descend pas (le
  /// serveur cite SES canaux) ; AUCUNE pièce comptable — le serveur a passé
  /// celle de l'acompte, il est le seul comptable (D246).
  ///
  /// ## Déjà sur ce poste : seul le STATUT avance, jamais il ne recule
  ///
  /// Le poste ne pousse que la CRÉATION d'une réservation (le serveur
  /// refuse toute modification) : un séjour ouvert ou annulé ICI n'est pas
  /// connu du serveur. Réécrire la fiche locale avec la version du serveur
  /// effacerait ces gestes. Donc :
  ///  * annulée ici → rien ne change (l'annulation locale porte sa pièce) ;
  ///  * annulée au serveur → annulée ici, avec ses conditions (taux,
  ///    montants, date), sans pièce ;
  ///  * sinon le statut du serveur n'est pris que s'il est PLUS AVANCÉ dans
  ///    le cycle (`en_attente` → `confirmee` → `en_cours` → `terminee`).
  /// Les dates, l'unité, le client et les montants d'une réservation
  /// existante ne sont pas réécrits — écart nommé : un séjour déplacé au
  /// serveur garde ici ses anciennes dates.
  Future<IssueAlignement> _reservation(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final statut = _texte(d['statut']);
    if (statut == null ||
        (statut != 'annulee' && !_rangStatut.containsKey(statut))) {
      return RefuseParLePoste('statut de réservation inconnu « $statut »');
    }
    final t = _db.reservationsLocal;
    final existante = await (_db.select(
      t,
    )..where((r) => r.id.equals(id))).getSingleOrNull();

    final ({
      int? taux,
      int? total,
      int? commission,
      int? rembourse,
      DateTime? date,
    })
    annulation;
    try {
      annulation = _conditionsAnnulation(d);
    } on FormatException catch (erreur) {
      return RefuseParLePoste(erreur.message);
    }

    if (existante != null) {
      if (existante.statut == 'annulee') return const Aligne();
      if (statut == 'annulee') {
        await (_db.update(t)..where((r) => r.id.equals(id))).write(
          ReservationsLocalCompanion(
            statut: const Value('annulee'),
            tauxAnnulationCentiemes: Value(annulation.taux),
            montantTotalAnnulationCentimes: Value(annulation.total),
            montantCommissionAnnulationCentimes: Value(annulation.commission),
            montantRembourseAnnulationCentimes: Value(annulation.rembourse),
            dateAnnulation: Value(annulation.date),
          ),
        );
        return const Aligne();
      }
      final rangLocal = _rangStatut[existante.statut] ?? 0;
      if (_rangStatut[statut]! > rangLocal) {
        await (_db.update(t)..where((r) => r.id.equals(id))).write(
          ReservationsLocalCompanion(statut: Value(statut)),
        );
      }
      return const Aligne();
    }

    final clientServeur = _texte(d['client_id']);
    final uniteServeur = _texte(d['unite_id']);
    if (clientServeur == null || uniteServeur == null) {
      return const RefuseParLePoste('client ou unité absent');
    }
    final DateTime arrivee;
    final DateTime depart;
    try {
      arrivee = _jourUtc(d['date_arrivee']);
      depart = _jourUtc(d['date_depart']);
    } on FormatException {
      return const RefuseParLePoste('dates de séjour illisibles');
    }
    if (!depart.isAfter(arrivee)) {
      return const RefuseParLePoste('départ antérieur ou égal à l’arrivée');
    }
    final acompte = entierDepuisDecimal(d['acompte'] ?? '0', 0);
    final tarif = d['tarif_nuit'] == null
        ? 0
        : entierDepuisDecimal(d['tarif_nuit'], 0);
    if (acompte == null || tarif == null) {
      return const RefuseParLePoste(
        'acompte ou tarif : une fraction de franc ne se tient pas sur ce poste',
      );
    }
    final remiseType = _texte(d['remise_type']) ?? 'aucune';
    if (!_remises.contains(remiseType)) {
      return RefuseParLePoste('type de remise inconnu « $remiseType »');
    }
    final remiseCentiemes = entierDepuisDecimal(d['remise_valeur'] ?? '0', 2);
    if (remiseCentiemes == null) {
      return RefuseParLePoste('remise « ${d['remise_valeur']} » illisible');
    }
    final modeServeur = _texte(d['mode_paiement']);
    final mode = modeServeur == null ? null : _modesServeur[modeServeur];
    if (modeServeur != null && mode == null) {
      return RefuseParLePoste('mode de paiement inconnu « $modeServeur »');
    }

    final client = await _cite(
      TableDescendue.clients,
      clientServeur,
      _db.clientsLocal,
    );
    if (client == null) {
      return const EnAttenteDeDependance('client pas encore reçu');
    }
    final unite = await _cite(
      TableDescendue.unitesHebergement,
      uniteServeur,
      _db.unitesHebergementLocal,
    );
    if (unite == null) {
      return const EnAttenteDeDependance(
        'unité d’hébergement pas encore reçue',
      );
    }

    // Les services de la réservation (lot F6) — lus AVANT l'écriture : une
    // ligne illisible refuse la réservation entière (jamais à moitié).
    const tablesDesServices = {
      'restauration': TableDescendue.plats,
      'bar': TableDescendue.cartesBoisson,
      'tourisme': TableDescendue.circuits,
      'vehicule': null,
    };
    final lignesService =
        <
          ({
            String service,
            String item,
            String libelle,
            int prix,
            int quantite,
          })
        >[];
    final brutes = d['lignes'];
    for (final l in brutes is List ? brutes : const <Object?>[]) {
      if (l is! Map) return const RefuseParLePoste('service illisible');
      final service = _texte(l['service']);
      final source = _texte(l['source_id']);
      final libelleService = _texte(l['libelle']);
      final prix = entierDepuisDecimal(l['prix_unitaire'], 0);
      final quantite = entierDepuisDecimal(l['quantite'], 0);
      if (service == null ||
          !tablesDesServices.containsKey(service) ||
          source == null ||
          libelleService == null ||
          prix == null ||
          quantite == null) {
        return RefuseParLePoste(
          'service de réservation illisible ou inconnu « $service » '
          '(ou fraction de franc / de quantité)',
        );
      }
      final table = tablesDesServices[service];
      lignesService.add((
        service: service,
        item: table == null
            ? source
            : await _dao.idLocal(table.nomServeur, source),
        libelle: libelleService,
        prix: prix,
        quantite: quantite,
      ));
    }
    await _db
        .into(t)
        .insert(
          ReservationsLocalCompanion.insert(
            id: id,
            reference:
                'SRV-${(id.length > 8 ? id.substring(0, 8) : id).toUpperCase()}',
            clientId: client,
            uniteId: unite,
            dateArrivee: arrivee,
            dateDepart: depart,
            statut: statut,
            tarifNuit: tarif,
            acompte: Value(acompte.toDouble()),
            modePaiement: Value(mode),
            // Lot 10f : le canal descend par son NOM (celui du serveur) ;
            // un nom que ce poste ne connaît pas reste sans canal.
            canal: Value(
              CanalReservation.values
                  .where((c) => c.libelle == _texte(d['canal']))
                  .firstOrNull
                  ?.code,
            ),
            remiseType: Value(remiseType),
            remiseValeur: Value(
              remiseType == 'aucune' ? null : remiseCentiemes / 100,
            ),
            statutSync: const Value('synchronise'),
            tauxAnnulationCentiemes: Value(annulation.taux),
            montantTotalAnnulationCentimes: Value(annulation.total),
            montantCommissionAnnulationCentimes: Value(annulation.commission),
            montantRembourseAnnulationCentimes: Value(annulation.rembourse),
            dateAnnulation: Value(annulation.date),
            dateCreationLocale: Value(_maintenant()),
          ),
        );
    // Lot F6 (audit de couverture) : ses services, au prix et au libellé
    // figés au serveur.
    for (var i = 0; i < lignesService.length; i++) {
      final l = lignesService[i];
      await _db
          .into(_db.lignesReservationLocal)
          .insert(
            LignesReservationLocalCompanion.insert(
              id: '$id:$i',
              reservationId: id,
              service: l.service,
              itemId: l.item,
              libelle: l.libelle,
              prixUnitaire: l.prix,
              quantite: l.quantite,
              ordre: i,
            ),
          );
    }
    // Lot F6 : son origine (Q3, et « connue du serveur »).
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Minuit UTC du jour d'une date du serveur — la convention de
  /// `PeriodeSejour` (un `DateTime` local décalerait le séjour d'un jour
  /// dans un fuseau négatif).
  static DateTime _jourUtc(Object? v) {
    final jour = _jour(v);
    if (jour == null) throw const FormatException('date absente');
    final p = jour.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Les conditions d'annulation du serveur, dans les unités de la v19 :
  /// taux en centièmes de pour cent, montants en centimes.
  static ({
    int? taux,
    int? total,
    int? commission,
    int? rembourse,
    DateTime? date,
  })
  _conditionsAnnulation(Map<String, Object?> d) {
    int? centiemes(String colonne) {
      if (d[colonne] == null) return null;
      final v = entierDepuisDecimal(d[colonne], 2);
      if (v == null) {
        throw FormatException('« $colonne » illisible : ${d[colonne]}');
      }
      return v;
    }

    DateTime? date;
    if (d['date_annulation'] != null) {
      date = DateTime.tryParse(
        '${d['date_annulation']}'.replaceFirst(' ', 'T'),
      );
      if (date == null) {
        throw const FormatException('date d’annulation illisible');
      }
    }
    return (
      taux: centiemes('taux_annulation'),
      total: centiemes('montant_total_annulation'),
      commission: centiemes('montant_commission_annulation'),
      rembourse: centiemes('montant_rembourse_annulation'),
      date: date,
    );
  }

  /* ================================================================== */
  /* Centres de coût                                                     */
  /* ================================================================== */

  /// Un centre de coût : le poste a les SIENS (installés au démarrage par
  /// libellé, cités par ses écritures). Il les RECONNAÎT — par
  /// correspondance ou identifiant, puis par libellé normalisé — et retient
  /// la correspondance ; il n'en crée un qu'en l'absence de tout équivalent,
  /// sous l'identifiant du serveur. Un centre local n'est jamais renommé :
  /// l'installateur le retrouve par son libellé.
  Future<IssueAlignement> _centre(ElementCatalogue e) async {
    final libelle = _texte(e.donnees['libelle']);
    if (libelle == null) return const RefuseParLePoste('libellé absent');
    final t = _db.centresCoutLocal;
    final idLocal = await _dao.idLocal(e.table.nomServeur, e.id);
    if (await (_db.select(
          t,
        )..where((c) => c.id.equals(idLocal))).getSingleOrNull() !=
        null) {
      return const Aligne();
    }
    final cle = cleNaturelle(libelle);
    for (final c in await _db.select(t).get()) {
      if (cleNaturelle(c.libelle) == cle) {
        await _dao.retenirCorrespondance(
          table: e.table.nomServeur,
          idServeur: e.id,
          idLocal: c.id,
          origine: 'libelle',
        );
        return const Aligne();
      }
    }
    await _db
        .into(t)
        .insert(
          CentresCoutLocalCompanion.insert(
            id: e.id,
            libelle: libelle,
            type: Value(_texte(e.donnees['type'])),
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Paramétrage et rôles (lot 10e, 18/10/2026)                          */
  /* ================================================================== */

  /// Une clé du paramétrage du serveur, routée par le dépôt des paramètres
  /// (les taux de la paie vers `PaieDao`). Vide au serveur = vidée ici. Un
  /// enregistrement de CE poste qui porte la clé et attend de partir la
  /// garde : l'opération est un LOT sous son propre identifiant, la règle
  /// commune (par élément) ne la voit pas.
  Future<IssueAlignement> _parametre(ElementCatalogue e) async {
    final cle = _texte(e.donnees['cle']);
    if (cle == null) return const RefuseParLePoste('paramètre sans clé');
    final valeur = e.donnees['valeur'];
    for (final o in await _file.operations(
      table: TableSynchronisee.parametresSysteme,
    )) {
      if (o.statut != StatutOperationSync.enAttente &&
          o.statut != StatutOperationSync.enCours) {
        continue;
      }
      final valeurs = (jsonDecode(o.payload) as Map)['valeurs'];
      if (valeurs is Map && valeurs.containsKey(cle)) {
        return const ConserveLocalement(
          'un enregistrement local de ce paramètre attend encore de partir',
        );
      }
    }
    await ParametresDepotLocal(_db).inscrireDescendue(
      cle,
      valeur is String && valeur.isNotEmpty ? valeur : null,
    );
    return const Aligne();
  }

  /// Un exercice du serveur (20/10/2026), apparié par son ANNÉE (unique des
  /// deux côtés) : l'exercice local garde son identifiant — ses écritures le
  /// désignent —, il prend les dates et le STATUT du serveur, qui est maître
  /// de la clôture. Un exercice absent d'ici y naît.
  Future<IssueAlignement> _exercice(ElementCatalogue e) async {
    final d = e.donnees;
    final annee = d['annee'] is int
        ? d['annee']! as int
        : int.tryParse('${d['annee']}');
    final debut = _texte(d['date_debut']);
    final fin = _texte(d['date_fin']);
    final brut = _texte(d['statut']);
    final statut = StatutExercice.values
        .where((x) => x.valeur == brut)
        .firstOrNull;
    if (annee == null || debut == null || fin == null || statut == null) {
      return const RefuseParLePoste('exercice illisible');
    }
    await ComptabiliteDao(_db).alignerExerciceDescendu(
      annee: annee,
      dateDebut: debut.substring(0, 10),
      dateFin: fin.substring(0, 10),
      statut: statut,
      dateCloture: DateTime.tryParse(_texte(d['date_cloture']) ?? ''),
    );
    return const Aligne();
  }

  /// Une écriture VALIDÉE du serveur, en miroir de lecture (v34). Ajoutée si
  /// elle manque, jamais réécrite (RG-11) ; aucune clé étrangère, donc rien à
  /// attendre. Une fraction de centime ou un champ manquant la refuse.
  Future<IssueAlignement> _ecritureServeur(ElementCatalogue e) async {
    final d = e.donnees;
    final annee = d['annee'] is int
        ? d['annee']! as int
        : int.tryParse('${d['annee']}');
    final journal = _texte(d['code_journal']);
    final compte = _texte(d['numero_compte']);
    final classe = _texte(d['classe']);
    final jour = _jour(d['date_ecriture']);
    final libelle = d['libelle'] is String ? d['libelle'] as String : null;
    final debit = entierDepuisDecimal(d['debit'], 2);
    final credit = entierDepuisDecimal(d['credit'], 2);
    if (annee == null ||
        annee <= 0 ||
        journal == null ||
        compte == null ||
        classe == null ||
        jour == null ||
        libelle == null ||
        debit == null ||
        credit == null) {
      return const RefuseParLePoste('écriture illisible');
    }
    await EcrituresServeurDao(_db).ajouterSiAbsente(
      id: e.id,
      annee: annee,
      codeJournal: journal,
      numeroCompte: compte,
      libelleCompte: _texte(d['libelle_compte']) ?? compte,
      classe: classe,
      dateEcriture: jour,
      libelle: libelle,
      debitCentimes: debit,
      creditCentimes: credit,
      numeroPiece: _texte(d['numero_piece']),
      ecritureContrepasseeId: _texte(d['ecriture_contrepassee_id']),
    );
    return const Aligne();
  }

  /// Un rôle du serveur et sa matrice, recopiée sur les comptes qui le
  /// portent. Apparié par son LIBELLÉ à un rôle du socle né ici sous un
  /// autre UUID (correspondance retenue) ; une matrice locale en attente
  /// d'envoi est conservée.
  Future<IssueAlignement> _role(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final libelle = _texte(d['libelle']);
    final brutes = d['droits'];
    if (libelle == null || brutes is! Map) {
      return const RefuseParLePoste('rôle sans libellé ni matrice');
    }
    final droits = <String, String>{
      for (final x in brutes.entries)
        if (x.value == 'C' || x.value == 'L' || x.value == '-')
          '${x.key}': x.value as String,
    };
    final roles = RolesDao(_db, horloge: _maintenant);
    var cible = id;
    final connu = await (_db.select(
      _db.rolesLocal,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (connu == null) {
      final homonyme = await roles.parLibelle(libelle);
      if (homonyme != null) {
        if (await _file.enSuspens(
          TableSynchronisee.roles.nomServeur,
          homonyme.id,
        )) {
          return const ConserveLocalement(
            'une matrice locale de ce rôle attend encore de partir',
          );
        }
        await _dao.retenirCorrespondance(
          table: e.table.nomServeur,
          idServeur: e.id,
          idLocal: homonyme.id,
          origine: 'libelle',
        );
        cible = homonyme.id;
      }
    }
    await roles.inscrireDescendu(
      id: cible,
      libelle: libelle,
      description: _texte(d['description']),
      droits: droits,
    );
    return const Aligne();
  }

  /// Un modèle de notification du serveur. Apparié par son couple
  /// (événement, canal) à un modèle né ici sous un autre UUID
  /// (correspondance retenue) ; une retouche locale en attente est gardée.
  Future<IssueAlignement> _modeleNotification(
    String id,
    ElementCatalogue e,
  ) async {
    final d = e.donnees;
    final evenement = _texte(d['evenement']);
    final canal = _texte(d['canal']);
    final contenu = _texte(d['contenu_template']);
    if (evenement == null || canal == null || contenu == null) {
      return const RefuseParLePoste('modèle de notification incomplet');
    }
    final dao = NotificationsDao(_db);
    var cible = id;
    final connu = await (_db.select(
      _db.modelesNotificationLocal,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (connu == null) {
      final homonyme = await dao.parCouple(evenement, canal);
      if (homonyme != null) {
        if (await _file.enSuspens(
          TableSynchronisee.modelesNotification.nomServeur,
          homonyme.id,
        )) {
          return const ConserveLocalement(
            'une retouche locale de ce modèle attend encore de partir',
          );
        }
        await _dao.retenirCorrespondance(
          table: e.table.nomServeur,
          idServeur: e.id,
          idLocal: homonyme.id,
          origine: 'libelle',
        );
        cible = homonyme.id;
      }
    }
    await dao.inscrireDescendu(
      id: cible,
      evenement: evenement,
      canal: canal,
      objet: _texte(d['objet']),
      contenuTemplate: contenu,
      actif: e.actif,
    );
    return const Aligne();
  }
}
