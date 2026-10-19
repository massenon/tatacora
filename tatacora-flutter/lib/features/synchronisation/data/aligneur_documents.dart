part of 'aligneur_catalogue.dart';

/// Les ÉCRIVAINS des DOCUMENTS descendus des autres postes (lot F4, décision
/// du Product Owner du 17/10/2026 : « on doit avoir aussi les ventes,
/// dépenses, caisses, commandes et réceptions … des autres postes. NE PLUS
/// LIMITER. »).
///
/// ## Ce qu'ils ne font JAMAIS, en plus des règles du catalogue
///
///  * passer une PIÈCE : décision Q1 du PO — le journal du poste ne tient que
///    ses propres pièces, le serveur a passé celle du document ; chaque
///    document écrit ici est inscrit dans `origines_documents_local`, que le
///    rattrapage des dépenses lit pour REFUSER ;
///  * écrire un mouvement de stock DÉRIVÉ : un bon de réception descendu
///    n'écrit pas ses entrées ; elles descendent elles-mêmes
///    (`mouvements_stock`), et le serveur ne renvoie pas à un poste celles
///    qu'il a déjà écrites (`tablesMiroirs`) ;
///  * réécrire un document déjà présent : celui du poste lui-même revient
///    par le flux ; seuls les changements d'ÉTAT qui ne reculent jamais
///    sont pris (une caisse close au serveur, une commande plus avancée, une
///    réservation de circuit annulée). Les autres gestes du cycle de vie
///    relèvent du lot F6.
///
/// ## L'auteur local
///
/// Les colonnes d'auteur (`utilisateur_id`…) sont de vraies clés étrangères
/// vers les comptes du POSTE, et le serveur ne descend pas les siens : la
/// ligne porte le compte qui synchronise (règle du catalogue). Le vrai poste
/// d'origine, lui, est dans `origines_documents_local`.
extension _AlignementDocuments on AligneurCatalogue {
  Future<IssueAlignement> alignerDocument(String id, ElementCatalogue e) =>
      switch (e.table) {
        TableDescendue.sejours => _sejour(id, e),
        TableDescendue.sessionsCaisse => _sessionCaisse(id, e),
        TableDescendue.ventes => _vente(id, e),
        TableDescendue.depenses => _depense(id, e),
        TableDescendue.tablesSalle => _tableSalle(id, e),
        TableDescendue.paniers => _occupation(id, e),
        TableDescendue.factures => _facture(id, e),
        TableDescendue.avoirs => _avoir(id, e),
        TableDescendue.paiements => _paiement(id, e),
        TableDescendue.commandesAchat => _commande(id, e),
        TableDescendue.bonsReception => _bon(id, e),
        TableDescendue.reglementsFournisseur => _reglement(id, e),
        TableDescendue.mouvementsStock => _mouvement(id, e),
        TableDescendue.circuits => _circuit(id, e),
        TableDescendue.guides => _guide(id, e),
        TableDescendue.reservationsTour => _reservationTour(id, e),
        TableDescendue.vehicules => _vehicule(id, e),
        TableDescendue.contratsLocation => _contratLocation(id, e),
        TableDescendue.servicesRh => _serviceRh(id, e),
        TableDescendue.employes => _employe(id, e),
        TableDescendue.bulletinsPaie => _bulletin(id, e),
        _ => throw StateError('${e.table} n’est pas un document'),
      };

  /* ================================================================== */
  /* Outils                                                              */
  /* ================================================================== */

  Future<bool> _existe(TableInfo<Table, Object?> t, String id) async =>
      (await _db
              .customSelect(
                'SELECT 1 FROM ${t.actualTableName} WHERE id = ? LIMIT 1',
                variables: [Variable.withString(id)],
              )
              .get())
          .isNotEmpty;

  Future<void> _retenirOrigine(ElementCatalogue e, String id) => _db
      .into(_db.originesDocumentsLocal)
      .insertOnConflictUpdate(
        OriginesDocumentsLocalCompanion.insert(
          tableServeur: e.table.nomServeur,
          entiteId: id,
          posteOrigine: Value(e.posteOrigine),
          recuLe: _maintenant(),
        ),
      );

  /// Un instant du serveur (`2026-10-15 07:00:00`), en heure locale comme le
  /// poste écrit les siens ; lève si illisible.
  static DateTime _instant(Object? v) {
    final d = DateTime.tryParse('$v'.trim().replaceFirst(' ', 'T'));
    if (d == null) throw const FormatException('instant illisible');
    return d;
  }

  /// Minuit LOCAL d'une date du serveur — la convention des dépenses, des
  /// circuits et des commandes de ce poste.
  static DateTime _jourLocal(Object? v) {
    final jour = AligneurCatalogue._jour(v);
    if (jour == null) throw const FormatException('date absente');
    final p = jour.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static List<Map<String, Object?>>? _lignes(Map<String, Object?> d) {
    final brutes = d['lignes'];
    if (brutes is! List) return null;
    return [
      for (final l in brutes)
        if (l is Map) Map<String, Object?>.from(l) else <String, Object?>{},
    ];
  }

  Future<String?> _auteurOuAttente() => _auteur();

  /* ================================================================== */
  /* Séjours (lot F5)                                                    */
  /* ================================================================== */

  /// Un séjour d'un autre poste : l'arrivée (puis le départ) réels. La
  /// réservation suit (statut vers l'avant seulement) et l'unité aussi :
  /// `occupee` à l'arrivée, `nettoyage` au départ — jamais une unité hors
  /// service. Existant : seul le DÉPART descend ; un départ n'est jamais
  /// effacé.
  Future<IssueAlignement> _sejour(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final DateTime? arrivee;
    final DateTime? depart;
    try {
      arrivee = d['date_checkin_reel'] == null
          ? null
          : _instant(d['date_checkin_reel']);
      depart = d['date_checkout_reel'] == null
          ? null
          : _instant(d['date_checkout_reel']);
    } on FormatException {
      return const RefuseParLePoste('heures de séjour illisibles');
    }
    final reservationServeur = AligneurCatalogue._texte(d['reservation_id']);
    if (reservationServeur == null) {
      return const RefuseParLePoste('réservation absente');
    }
    final reservationId = await _cite(
      TableDescendue.reservations,
      reservationServeur,
      _db.reservationsLocal,
    );
    if (reservationId == null) {
      return const EnAttenteDeDependance('réservation pas encore reçue');
    }
    final reservation = await (_db.select(
      _db.reservationsLocal,
    )..where((r) => r.id.equals(reservationId))).getSingle();

    final t = _db.sejoursLocal;
    final existant = await (_db.select(
      t,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (existant == null) {
      // Une réservation ne se pointe qu'une fois : si ce poste a pointé la
      // même arrivée hors ligne, le serveur refusera l'une des deux (« déjà
      // arrivé ») et le poste la verra dans « À traiter ». Ne rien écrire ici
      // évite deux séjours pour un client.
      final local =
          await (_db.select(t)
                ..where((s) => s.reservationId.equals(reservationId))
                ..limit(1))
              .getSingleOrNull();
      if (local != null) {
        return const RefuseParLePoste(
          'l’arrivée de ce séjour a aussi été pointée sur ce poste : le '
          'serveur tranche',
        );
      }
      await _db
          .into(t)
          .insert(
            SejoursLocalCompanion.insert(
              id: id,
              reservationId: reservationId,
              dateCheckinReel: Value(arrivee),
              dateCheckoutReel: Value(depart),
              occupants: const Value('[]'),
              dateCreation: _maintenant(),
              dateModification: _maintenant(),
            ),
          );
      await _retenirOrigine(e, id);
    } else if (existant.dateCheckoutReel == null && depart != null) {
      await (_db.update(t)..where((s) => s.id.equals(id))).write(
        SejoursLocalCompanion(
          dateCheckoutReel: Value(depart),
          dateModification: Value(_maintenant()),
        ),
      );
    } else {
      return const Aligne();
    }

    // La réservation et l'unité suivent le séjour, comme `SejourService`.
    final cible = depart != null ? 'terminee' : 'en_cours';
    const rang = {
      'en_attente': 0,
      'confirmee': 1,
      'en_cours': 2,
      'terminee': 3,
    };
    if (reservation.statut != 'annulee' &&
        (rang[cible] ?? 0) > (rang[reservation.statut] ?? 0)) {
      await (_db.update(_db.reservationsLocal)
            ..where((r) => r.id.equals(reservationId)))
          .write(ReservationsLocalCompanion(statut: Value(cible)));
    }
    final unite = await (_db.select(
      _db.unitesHebergementLocal,
    )..where((u) => u.id.equals(reservation.uniteId))).getSingleOrNull();
    if (unite != null && unite.statut != 'hors_service') {
      await (_db.update(
        _db.unitesHebergementLocal,
      )..where((u) => u.id.equals(unite.id))).write(
        UnitesHebergementLocalCompanion(
          statut: Value(depart != null ? 'nettoyage' : 'occupee'),
        ),
      );
    }
    return const Aligne();
  }

  /* ================================================================== */
  /* Caisse                                                              */
  /* ================================================================== */

  static const _points = {'reception', 'restaurant', 'bar'};

  /// Une session de caisse. Existante : seule la CLÔTURE descend (une caisse
  /// partagée close sur un autre poste, ou sur la PWA) ; une caisse n'est
  /// jamais rouverte.
  Future<IssueAlignement> _sessionCaisse(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final point = AligneurCatalogue._texte(d['point_vente']);
    if (!_points.contains(point)) {
      return RefuseParLePoste('point de vente inconnu « $point »');
    }
    final fond = entierDepuisDecimal(d['montant_fond'], 2);
    final theorique = d['montant_theorique'] == null
        ? null
        : entierDepuisDecimal(d['montant_theorique'], 2);
    final constate = d['montant_constate'] == null
        ? null
        : entierDepuisDecimal(d['montant_constate'], 2);
    if (fond == null ||
        (d['montant_theorique'] != null && theorique == null) ||
        (d['montant_constate'] != null && constate == null)) {
      return const RefuseParLePoste('montant de caisse illisible');
    }
    final DateTime ouverture;
    final DateTime? cloture;
    try {
      ouverture = _instant(d['date_ouverture']);
      cloture = d['date_cloture'] == null ? null : _instant(d['date_cloture']);
    } on FormatException {
      return const RefuseParLePoste('dates de caisse illisibles');
    }

    final t = _db.sessionsCaisseLocal;
    final existante = await (_db.select(
      t,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (existante != null) {
      if (existante.dateCloture == null && cloture != null) {
        await (_db.update(t)..where((s) => s.id.equals(id))).write(
          SessionsCaisseLocalCompanion(
            dateCloture: Value(cloture),
            montantTheoriqueCentimes: Value(theorique),
            montantConstateCentimes: Value(constate),
          ),
        );
      }
      return const Aligne();
    }
    final auteur = await _auteurOuAttente();
    if (auteur == null) return AligneurCatalogue._sansAuteur;
    await _db
        .into(t)
        .insert(
          SessionsCaisseLocalCompanion.insert(
            id: id,
            pointVente: point!,
            utilisateurOuvertureId: auteur,
            dateOuverture: ouverture,
            montantFondCentimes: fond,
            dateCloture: Value(cloture),
            montantTheoriqueCentimes: Value(theorique),
            montantConstateCentimes: Value(constate),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Ventes (POS vente)                                                  */
  /* ================================================================== */

  static const _modesComptant = {
    'especes',
    'mobile_money',
    'carte',
    'virement',
    'cheque',
  };

  /// Une vente au comptant d'un autre poste → un panier CLÔTURÉ (ou annulé)
  /// de ce poste, sans pièce. Elle entre dans les totaux du poste (caisse
  /// partagée, tableau de bord, états). La vente sur NOTE DE CHAMBRE relève
  /// du lot F5 (séjours, factures) : refusée ici, avec son motif. Une vente
  /// déjà présente n'est pas réécrite (cycle de vie : lot F6).
  Future<IssueAlignement> _vente(String id, ElementCatalogue e) async {
    final d = e.donnees;
    if (await _existe(_db.paniersLocal, id)) {
      // Lot F6 : une vente ANNULÉE au serveur (à la PWA) — celle de CE poste
      // contre-passe sa pièce ici (le DAO du comptoir s'en charge) ; celle
      // d'un autre poste, sans pièce locale, suit en statut.
      if (AligneurCatalogue._texte(d['statut']) == 'annulee') {
        final auteur = await _auteurOuAttente();
        if (auteur == null) return AligneurCatalogue._sansAuteur;
        await PanierDao(_db, moteur: _moteur).suivreAnnulationDuServeur(
          id,
          motif: AligneurCatalogue._texte(d['motif_annulation']),
          auteurId: auteur,
        );
      }
      return const Aligne();
    }
    final mode = AligneurCatalogue._texte(d['mode_paiement']);
    final noteChambre = mode == 'note_chambre';
    if (!noteChambre && !_modesComptant.contains(mode)) {
      return RefuseParLePoste('mode de paiement inconnu « $mode »');
    }
    final statutServeur = AligneurCatalogue._texte(d['statut']);
    final statut = switch (statutServeur) {
      'validee' => 'cloture',
      'annulee' => 'annule',
      _ => null,
    };
    if (statut == null) {
      return RefuseParLePoste('statut de vente inconnu « $statutServeur »');
    }
    final montant = entierDepuisDecimal(d['montant_total'], 0);
    if (montant == null) {
      return const RefuseParLePoste(
        'montant : une fraction de franc ne se tient pas sur ce poste',
      );
    }
    final DateTime le;
    try {
      // La date MÉTIER (`created_at`, la clôture du poste qui a vendu), pas
      // `date_creation` (sa réception au serveur, plus tard si la vente a
      // été faite hors ligne) ; le second reste le repli d'un serveur
      // antérieur au lot P1-1.
      le = _instant(d['created_at'] ?? d['date_creation']);
    } on FormatException {
      return const RefuseParLePoste('date de vente illisible');
    }
    final lignes = _lignes(d);
    if (lignes == null || lignes.isEmpty) {
      return const RefuseParLePoste('vente sans ligne');
    }
    final converties =
        <
          ({
            String module,
            String code,
            String nom,
            String? cat,
            int prix,
            int qte,
          })
        >[];
    for (final l in lignes) {
      final prix = entierDepuisDecimal(l['prix_unitaire'], 0);
      final qte = l['quantite'] is int
          ? l['quantite']! as int
          : entierDepuisDecimal(l['quantite'], 0);
      final nom = AligneurCatalogue._texte(l['nom']);
      final module = AligneurCatalogue._texte(l['module']);
      if (prix == null || qte == null || nom == null || module == null) {
        return const RefuseParLePoste('ligne de vente illisible');
      }
      converties.add((
        module: module,
        code: AligneurCatalogue._texte(l['code']) ?? '',
        nom: nom,
        cat: AligneurCatalogue._texte(l['categorie']),
        prix: prix,
        qte: qte,
      ));
    }

    // Lot F5 : la note de chambre se rattache à SA réservation (le panier de
    // séjour de ce poste) ; une note sans réservation connue du serveur (une
    // vente d'avant le 17/10/2026) n'a pas de séjour où se ranger.
    String? reservation;
    if (noteChambre) {
      final reservationServeur = AligneurCatalogue._texte(d['reservation_id']);
      if (reservationServeur == null) {
        return const RefuseParLePoste(
          'note de chambre sans réservation au serveur : aucun séjour où la '
          'ranger',
        );
      }
      reservation = await _cite(
        TableDescendue.reservations,
        reservationServeur,
        _db.reservationsLocal,
      );
      if (reservation == null) {
        return const EnAttenteDeDependance('réservation pas encore reçue');
      }
    }

    String? session;
    final sessionServeur = AligneurCatalogue._texte(d['session_id']);
    if (sessionServeur != null) {
      session = await _cite(
        TableDescendue.sessionsCaisse,
        sessionServeur,
        _db.sessionsCaisseLocal,
      );
      if (session == null) {
        return const EnAttenteDeDependance(
          'session de caisse pas encore reçue',
        );
      }
    }
    // La table de salle n'a de sens que si elle existe sur ce poste (le
    // plan de salle ne descend pas) ; sinon la vente garde sa mention.
    final tableServeur = AligneurCatalogue._texte(d['table_id']);
    final table =
        tableServeur != null && await _existe(_db.tablesLocal, tableServeur)
        ? tableServeur
        : null;

    await _db
        .into(_db.paniersLocal)
        .insert(
          PaniersLocalCompanion.insert(
            id: id,
            typeVente: noteChambre ? 'sur_sejour' : 'comptant',
            reservationId: Value(reservation),
            clientNom: Value(AligneurCatalogue._texte(d['client_mention'])),
            pointVente: Value(AligneurCatalogue._texte(d['point_vente'])),
            tableId: Value(table),
            statut: Value(statut),
            ouvertLe: Value(le),
            clotureLe: Value(le),
            modePaiement: Value(mode),
            montantCloture: Value(montant),
            motifAnnulation: Value(
              AligneurCatalogue._texte(d['motif_annulation']),
            ),
            sessionEncaissementId: Value(session),
          ),
        );
    for (var i = 0; i < converties.length; i++) {
      final l = converties[i];
      await _db
          .into(_db.lignesPanierLocal)
          .insert(
            LignesPanierLocalCompanion.insert(
              id: '$id:$i',
              panierId: id,
              moduleSource: l.module,
              codeArticle: l.code,
              libelle: l.nom,
              prixUnitaire: l.prix,
              quantite: l.qte,
              categorie: Value(l.cat),
              ajouteeLe: Value(le),
            ),
          );
    }
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Dépenses                                                            */
  /* ================================================================== */

  /// Une dépense d'un autre poste, SANS pièce (`ecriture_id` nul) : le
  /// rattrapage la refuse (`DepenseDao.comptabiliser`, origine lue ici).
  Future<IssueAlignement> _depense(String id, ElementCatalogue e) async {
    final d = e.donnees;
    if (await _existe(_db.depensesLocal, id)) return const Aligne();
    final libelle = AligneurCatalogue._texte(d['libelle']);
    final tresorerie = AligneurCatalogue._texte(d['tresorerie']);
    if (libelle == null || tresorerie == null) {
      return const RefuseParLePoste('libellé ou trésorerie absent');
    }
    final DateTime date;
    try {
      date = _jourLocal(d['date_transaction']);
    } on FormatException {
      return const RefuseParLePoste('date de dépense illisible');
    }
    final lignes = _lignes(d);
    if (lignes == null || lignes.isEmpty) {
      return const RefuseParLePoste('dépense sans ligne');
    }
    final converties =
        <
          ({
            String libelle,
            String compte,
            String nature,
            String famille,
            int montant,
          })
        >[];
    for (final l in lignes) {
      final montant = entierDepuisDecimal(l['montant'], 0);
      final compte = AligneurCatalogue._texte(l['compte_charge']);
      if (montant == null || compte == null) {
        return const RefuseParLePoste(
          'ligne de dépense illisible (montant à fraction de franc ?)',
        );
      }
      converties.add((
        libelle: AligneurCatalogue._texte(l['libelle']) ?? libelle,
        compte: compte,
        nature: AligneurCatalogue._texte(l['nature']) ?? '',
        famille: AligneurCatalogue._texte(l['famille']) ?? '',
        montant: montant,
      ));
    }
    await _db
        .into(_db.depensesLocal)
        .insert(
          DepensesLocalCompanion.insert(
            id: id,
            dateTransaction: date,
            tresorerie: tresorerie,
            libelle: libelle,
            saisieLe: Value(_maintenant()),
          ),
        );
    for (var i = 0; i < converties.length; i++) {
      final l = converties[i];
      await _db
          .into(_db.lignesDepenseLocal)
          .insert(
            LignesDepenseLocalCompanion.insert(
              id: '$id:$i',
              depenseId: id,
              libelle: l.libelle,
              compteCharge: l.compte,
              nature: l.nature,
              famille: l.famille,
              montant: l.montant,
              ajouteeLe: Value(_maintenant()),
            ),
          );
    }
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Véhicules et contrats — audit de couverture (18/10/2026)            */
  /* ================================================================== */

  static const _categoriesVehicule = {
    'voiture',
    '4x4',
    'pickup',
    'moto',
    'scooter',
    'velo',
    'bus',
  };
  static const _statutsVehicule = {
    'disponible',
    'loue',
    'entretien',
    'hors_service',
  };

  /// Un véhicule du parc du serveur. Détenu : catégorie, plaque, tarif et
  /// statut suivent (dernier écrit gagnant, une retouche locale en attente
  /// est conservée par la règle commune). Une plaque déjà au parc LOCAL est
  /// le même véhicule (le serveur fusionne) : correspondance, pas de
  /// doublon. Année, transmission et capacité n'ont pas de colonne ici.
  Future<IssueAlignement> _vehicule(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final plaque = AligneurCatalogue._texte(d['immatriculation']);
    final categorie = AligneurCatalogue._texte(d['categorie']);
    final statut = AligneurCatalogue._texte(d['statut']);
    final tarif = entierDepuisDecimal(d['tarif_jour'], 0);
    if (plaque == null ||
        !_categoriesVehicule.contains(categorie) ||
        !_statutsVehicule.contains(statut) ||
        tarif == null) {
      return const RefuseParLePoste(
        'véhicule incomplet (ou fraction de franc)',
      );
    }
    final t = _db.vehiculesLocal;
    final valeurs = VehiculesLocalCompanion(
      categorie: Value(categorie!),
      immatriculation: Value(plaque),
      tarifJour: Value(tarif.toDouble()),
      statut: Value(statut!),
    );
    if (await _existe(t, id)) {
      await (_db.update(t)..where((v) => v.id.equals(id))).write(valeurs);
      return const Aligne();
    }
    final homonyme = await (_db.select(
      t,
    )..where((v) => v.immatriculation.equals(plaque))).getSingleOrNull();
    if (homonyme != null) {
      await _dao.retenirCorrespondance(
        table: e.table.nomServeur,
        idServeur: e.id,
        idLocal: homonyme.id,
        origine: 'libelle',
      );
      await (_db.update(
        t,
      )..where((v) => v.id.equals(homonyme.id))).write(valeurs);
      return const Aligne();
    }
    await _db
        .into(t)
        .insert(
          VehiculesLocalCompanion.insert(
            id: id,
            categorie: categorie,
            immatriculation: plaque,
            tarifJour: tarif.toDouble(),
            statut: statut,
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Un contrat de location d'un autre poste (ou de la PWA) : il occupe le
  /// véhicule ici aussi (RG-08 du poste lit ces plages). Détenu : rien n'est
  /// réécrit. Les numéros de pièce ne descendent pas.
  Future<IssueAlignement> _contratLocation(
    String id,
    ElementCatalogue e,
  ) async {
    if (await _existe(_db.contratsLocationLocal, id)) return const Aligne();
    final d = e.donnees;
    final vehiculeServeur = AligneurCatalogue._texte(d['vehicule_id']);
    final clientServeur = AligneurCatalogue._texte(d['client_id']);
    if (vehiculeServeur == null || clientServeur == null) {
      return const RefuseParLePoste('contrat incomplet');
    }
    final DateTime debut;
    final DateTime fin;
    try {
      debut = _jourLocal(d['date_debut']);
      fin = _jourLocal(d['date_fin']);
    } on FormatException {
      return const RefuseParLePoste('dates de contrat illisibles');
    }
    final vehicule = await _cite(
      TableDescendue.vehicules,
      vehiculeServeur,
      _db.vehiculesLocal,
    );
    if (vehicule == null) {
      return const EnAttenteDeDependance('véhicule pas encore reçu');
    }
    final client = await _cite(
      TableDescendue.clients,
      clientServeur,
      _db.clientsLocal,
    );
    if (client == null) {
      return const EnAttenteDeDependance('client pas encore reçu');
    }
    final guideServeur = AligneurCatalogue._texte(d['guide_id']);
    await _db
        .into(_db.contratsLocationLocal)
        .insert(
          ContratsLocationLocalCompanion.insert(
            id: id,
            vehiculeId: vehicule,
            clientId: client,
            guideId: Value(
              guideServeur == null
                  ? null
                  : await _dao.idLocal('guides', guideServeur),
            ),
            dateDebut: debut,
            dateFin: fin,
            statutSync: const Value('synchronise'),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* RH et paie — audit de couverture (18/10/2026)                       */
  /* ================================================================== */

  /// Un service RH du serveur : reconnu par son LIBELLÉ (le référentiel est
  /// semé des deux côtés), jamais doublé.
  Future<IssueAlignement> _serviceRh(String id, ElementCatalogue e) async {
    final libelle = AligneurCatalogue._texte(e.donnees['libelle']);
    if (libelle == null) return const RefuseParLePoste('service sans libellé');
    final t = _db.servicesRhLocal;
    if (await _existe(t, id)) return const Aligne();
    final local = await (_db.select(
      t,
    )..where((s) => s.libelle.equals(libelle))).getSingleOrNull();
    if (local != null) {
      await _dao.retenirCorrespondance(
        table: e.table.nomServeur,
        idServeur: e.id,
        idLocal: local.id,
        origine: 'libelle',
      );
      return const Aligne();
    }
    await _db
        .into(t)
        .insert(ServicesRhLocalCompanion.insert(id: id, libelle: libelle));
    return const Aligne();
  }

  static const _typesContrat = {'CDI', 'CDD', 'Stage', 'Journalier'};
  static const _statutsEmploye = {'actif', 'conge', 'suspendu', 'parti'};

  /// Un employé du serveur (dernier écrit gagnant ; une retouche locale en
  /// attente est conservée par la règle commune). Le matricule du serveur
  /// fait foi — celui d'un dossier de CE poste est régularisé.
  Future<IssueAlignement> _employe(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final matricule = AligneurCatalogue._texte(d['matricule']);
    final nom = AligneurCatalogue._texte(d['nom']);
    final poste = AligneurCatalogue._texte(d['poste']);
    final serviceServeur = AligneurCatalogue._texte(d['service_id']);
    final salaire = entierDepuisDecimal(d['salaire_base'], 0);
    final statut = AligneurCatalogue._texte(d['statut']);
    final type = AligneurCatalogue._texte(d['type_contrat']);
    if (matricule == null ||
        nom == null ||
        poste == null ||
        serviceServeur == null ||
        salaire == null ||
        !_statutsEmploye.contains(statut) ||
        (type != null && !_typesContrat.contains(type))) {
      return const RefuseParLePoste('employé incomplet (ou fraction de franc)');
    }
    final DateTime embauche;
    final DateTime? fin;
    try {
      embauche = _jourLocal(d['date_embauche']);
      fin = d['date_fin_contrat'] == null
          ? null
          : _jourLocal(d['date_fin_contrat']);
    } on FormatException {
      return const RefuseParLePoste('dates d’employé illisibles');
    }
    final service = await _cite(
      TableDescendue.servicesRh,
      serviceServeur,
      _db.servicesRhLocal,
    );
    if (service == null) {
      return const EnAttenteDeDependance('service pas encore reçu');
    }
    final valeurs = EmployesLocalCompanion(
      matricule: Value(matricule),
      nom: Value(nom),
      prenom: Value(AligneurCatalogue._texte(d['prenom']) ?? ''),
      poste: Value(poste),
      serviceId: Value(service),
      dateEmbauche: Value(embauche),
      dateFinContrat: Value(fin),
      numeroCnss: Value(AligneurCatalogue._texte(d['numero_cnss'])),
      typeContrat: Value(type),
      salaireBase: Value(salaire),
      statut: Value(statut!),
    );
    final t = _db.employesLocal;
    if (await _existe(t, id)) {
      await (_db.update(t)..where((x) => x.id.equals(id))).write(valeurs);
      return const Aligne();
    }
    await _db.into(t).insert(valeurs.copyWith(id: Value(id)));
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Un bulletin du serveur (recalculé avec son barème) : il fait foi — numéro,
  /// montants et statut d'un bulletin DÉTENU suivent ; un nouveau est inscrit.
  Future<IssueAlignement> _bulletin(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final numero = AligneurCatalogue._texte(d['numero']);
    final periode = AligneurCatalogue._texte(d['periode']);
    final employeServeur = AligneurCatalogue._texte(d['employe_id']);
    final statut = AligneurCatalogue._texte(d['statut']);
    final montants = [
      for (final c in const [
        'salaire_base',
        'total_primes',
        'total_retenues',
        'cnss_salarie',
        'its',
        'charges_patronales_confirmees',
        'net_a_payer',
      ])
        entierDepuisDecimal(d[c], 0),
    ];
    if (numero == null ||
        periode == null ||
        employeServeur == null ||
        !{'brouillon', 'validee', 'annulee'}.contains(statut) ||
        montants.contains(null)) {
      return const RefuseParLePoste(
        'bulletin incomplet (ou fraction de franc)',
      );
    }
    final valeurs = BulletinsPaieLocalCompanion(
      numero: Value(numero),
      periode: Value(periode),
      salaireBase: Value(montants[0]!),
      totalPrimes: Value(montants[1]!),
      totalRetenues: Value(montants[2]!),
      cnssSalarie: Value(montants[3]!),
      its: Value(montants[4]!),
      chargesPatronalesConfirmees: Value(montants[5]!),
      netAPayer: Value(montants[6]!),
      statut: Value(statut!),
      motifAnnulation: Value(AligneurCatalogue._texte(d['motif_annulation'])),
    );
    final t = _db.bulletinsPaieLocal;
    if (await _existe(t, id)) {
      await (_db.update(t)..where((x) => x.id.equals(id))).write(valeurs);
      return const Aligne();
    }
    final employe = await _cite(
      TableDescendue.employes,
      employeServeur,
      _db.employesLocal,
    );
    if (employe == null) {
      return const EnAttenteDeDependance('employé pas encore reçu');
    }
    // Un bulletin du même employé et du même mois existe ici (établi avant
    // la fusion) : c'est le même — il prend les valeurs du serveur.
    final jumeau =
        await (_db.select(t)..where(
              (x) => x.employeId.equals(employe) & x.periode.equals(periode),
            ))
            .getSingleOrNull();
    if (jumeau != null) {
      await _dao.retenirCorrespondance(
        table: e.table.nomServeur,
        idServeur: e.id,
        idLocal: jumeau.id,
        origine: 'libelle',
      );
      await (_db.update(
        t,
      )..where((x) => x.id.equals(jumeau.id))).write(valeurs);
      return const Aligne();
    }
    await _db
        .into(t)
        .insert(valeurs.copyWith(id: Value(id), employeId: Value(employe)));
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Tables de salle et leur occupation — lot F6 (18/10/2026)            */
  /* ================================================================== */

  static const _espacesAvecTables = {'restaurant', 'jardin', 'plage'};

  /// Une table du plan du serveur. Détenue (par identifiant ou par
  /// correspondance) : numéro, libellé, places et activation suivent le
  /// serveur. Une table locale de même espace et même numéro est LA MÊME
  /// table (le serveur fusionne) : la correspondance est retenue, rien n'est
  /// doublé. Sinon, inscrite.
  Future<IssueAlignement> _tableSalle(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final espace = AligneurCatalogue._texte(d['espace']);
    final numero = d['numero'] is int
        ? d['numero'] as int
        : int.tryParse('${d['numero']}');
    final places = d['places'] is int
        ? d['places'] as int
        : int.tryParse('${d['places']}');
    final libelle = AligneurCatalogue._texte(d['libelle']);
    if (espace == null ||
        !_espacesAvecTables.contains(espace) ||
        numero == null ||
        places == null ||
        libelle == null) {
      return const RefuseParLePoste('table de salle incomplète');
    }
    final t = _db.tablesLocal;
    final valeurs = TablesLocalCompanion(
      numero: Value(numero),
      libelle: Value(libelle),
      places: Value(places),
      actif: Value(e.actif),
    );
    if (await _existe(t, id)) {
      await (_db.update(t)..where((x) => x.id.equals(id))).write(valeurs);
      return const Aligne();
    }
    final homonyme =
        await (_db.select(t)
              ..where((x) => x.espace.equals(espace) & x.numero.equals(numero)))
            .getSingleOrNull();
    if (homonyme != null) {
      await _dao.retenirCorrespondance(
        table: e.table.nomServeur,
        idServeur: e.id,
        idLocal: homonyme.id,
        origine: 'libelle',
      );
      await (_db.update(
        t,
      )..where((x) => x.id.equals(homonyme.id))).write(valeurs);
      return const Aligne();
    }
    await _db
        .into(t)
        .insert(
          TablesLocalCompanion.insert(
            id: id,
            espace: espace,
            numero: numero,
            libelle: libelle,
            places: Value(places),
            actif: Value(e.actif),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// L'addition d'une table ouverte AILLEURS (un autre poste, la PWA) : elle
  /// occupe la table ici aussi, jusqu'à sa fermeture. Celle de CE poste vit
  /// dans `paniers_local` et n'est pas dupliquée.
  Future<IssueAlignement> _occupation(String id, ElementCatalogue e) async {
    if (await _existe(_db.paniersLocal, id)) return const Aligne();
    final d = e.donnees;
    final tableServeur = AligneurCatalogue._texte(d['table_id']);
    final statut = AligneurCatalogue._texte(d['statut']);
    if (tableServeur == null || (statut != 'ouvert' && statut != 'cloture')) {
      return const RefuseParLePoste('occupation de table illisible');
    }
    final tableId = await _cite(
      TableDescendue.tablesSalle,
      tableServeur,
      _db.tablesLocal,
    );
    if (tableId == null) {
      return const EnAttenteDeDependance('table pas encore reçue');
    }
    await _db
        .into(_db.occupationsTablesLocal)
        .insertOnConflictUpdate(
          OccupationsTablesLocalCompanion.insert(
            panierId: id,
            tableId: tableId,
            pointVente: AligneurCatalogue._texte(d['point_vente']) ?? '',
            posteOrigine: Value(e.posteOrigine),
            ouvert: statut == 'ouvert',
            recuLe: _maintenant(),
          ),
        );
    return const Aligne();
  }

  /* ================================================================== */
  /* Factures, avoirs, encaissements — lots F5c et F5d                   */
  /* ================================================================== */

  /// Une facture du serveur. DÉTENUE (celle de ce poste revient par le
  /// flux) : seul son numéro suit — c'est la seconde voie de la
  /// régularisation, quand la réponse de l'envoi a été perdue. NOUVELLE :
  /// inscrite au registre sous son numéro, lignes au PRIX VENDU
  /// (`prix_catalogue`), sans pièce. Une facture ancienne du serveur sans
  /// numéro reçoit `SRV-` + 8 caractères (même convention que les
  /// réservations) ; sans prix vendu et avec de la TVA, elle est refusée :
  /// le poste ne recalcule pas un TTC.
  Future<IssueAlignement> _facture(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final numeroServeur = AligneurCatalogue._texte(d['numero']);
    final factures = FactureDao(_db);
    if (await _existe(_db.piecesFacturationLocal, id)) {
      if (numeroServeur != null) {
        try {
          await factures.regulariserNumeros(id, numero: numeroServeur);
        } on StateError catch (err) {
          return RefuseParLePoste(err.message);
        }
      }
      return const Aligne();
    }
    final DateTime date;
    try {
      date = _jourLocal(d['date_emission']);
    } on FormatException {
      return const RefuseParLePoste('date d’émission illisible');
    }
    final origineServeur = AligneurCatalogue._texte(d['origine']);
    final origine = OrigineFacture.values
        .where((o) => o.code == origineServeur)
        .firstOrNull;
    if (origineServeur != null && origine == null) {
      return RefuseParLePoste(
        'origine de facture inconnue « $origineServeur »',
      );
    }
    // Sans TVA, le prix hors taxe EST le prix vendu (facture ancienne).
    final sansTva = entierDepuisDecimal(d['montant_tva'], 2) == 0;
    final lignes = _lignes(d);
    if (lignes == null || lignes.isEmpty) {
      return const RefuseParLePoste('facture sans ligne');
    }
    final converties = <LigneBrouillon>[];
    String? reservationId;
    String? panierId;
    for (final l in lignes) {
      final module = ModuleFacturable.values
          .where((m) => m.code == l['source_module'])
          .firstOrNull;
      final quantite = entierDepuisDecimal(l['quantite'], 0);
      final prix = entierDepuisDecimal(
        l['prix_catalogue'] ?? (sansTva ? l['prix_unitaire'] : null),
        0,
      );
      final libelle = AligneurCatalogue._texte(l['libelle']);
      if (module == null || quantite == null || libelle == null) {
        return const RefuseParLePoste('ligne de facture illisible');
      }
      if (prix == null) {
        return const RefuseParLePoste(
          'ligne sans prix vendu (facture ancienne avec TVA, ou fraction '
          'de franc) : le poste ne recalcule pas un TTC',
        );
      }
      final source = AligneurCatalogue._texte(l['source_id']);
      if (source != null && module == ModuleFacturable.m1Hebergement) {
        reservationId ??= await _cite(
          TableDescendue.reservations,
          source,
          _db.reservationsLocal,
        );
      }
      if (source != null &&
          (module == ModuleFacturable.m4Restaurant ||
              module == ModuleFacturable.m5Bar)) {
        panierId ??= await _cite(
          TableDescendue.ventes,
          source,
          _db.paniersLocal,
        );
      }
      converties.add(
        LigneBrouillon(
          module: module,
          libelle: libelle,
          prixUnitaire: prix,
          quantite: quantite,
        ),
      );
    }
    final clientServeur = AligneurCatalogue._texte(d['client_id']);
    if (clientServeur == null) {
      return const RefuseParLePoste('facture sans client');
    }
    final clientId = await _cite(
      TableDescendue.clients,
      clientServeur,
      _db.clientsLocal,
    );
    if (clientId == null) {
      return const EnAttenteDeDependance('client pas encore reçu');
    }
    final client = await (_db.select(
      _db.clientsLocal,
    )..where((c) => c.id.equals(clientId))).getSingle();
    await factures.inscrireDescendue(
      id: id,
      numero: numeroServeur ?? 'SRV-${id.length > 8 ? id.substring(0, 8) : id}',
      origine: origine ?? OrigineFacture.factureDirecte,
      dateEmission: date,
      clientNom: client.nom,
      clientId: clientId,
      reservationId: reservationId,
      panierId: panierId,
      lignes: converties,
    );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Un avoir du serveur. Celui que CE poste a émis en annulant (son
  /// identifiant local diffère) reçoit le numéro du serveur ; un autre est
  /// inscrit sur sa facture, sans pièce.
  Future<IssueAlignement> _avoir(String id, ElementCatalogue e) async {
    final d = e.donnees;
    if (await _existe(_db.piecesFacturationLocal, id)) return const Aligne();
    final factureServeur = AligneurCatalogue._texte(d['facture_id']);
    final numero = AligneurCatalogue._texte(d['numero']);
    final montant = entierDepuisDecimal(d['montant'], 0);
    if (factureServeur == null || montant == null) {
      return const RefuseParLePoste('avoir incomplet (ou fraction de franc)');
    }
    final DateTime date;
    try {
      date = _jourLocal(d['date_emission']);
    } on FormatException {
      return const RefuseParLePoste('date d’avoir illisible');
    }
    final factureId = await _cite(
      TableDescendue.factures,
      factureServeur,
      _db.piecesFacturationLocal,
    );
    if (factureId == null) {
      return const EnAttenteDeDependance('facture pas encore reçue');
    }
    final factures = FactureDao(_db);
    final provisoire = await factures.avoirProvisoireDe(factureId);
    if (provisoire != null) {
      if (numero != null) {
        try {
          await factures.regulariserNumeros(factureId, numeroAvoir: numero);
        } on StateError catch (err) {
          return RefuseParLePoste(err.message);
        }
      }
      return const Aligne();
    }
    await factures.inscrireAvoirDescendu(
      id: id,
      factureId: factureId,
      numero: numero ?? 'SRV-${id.length > 8 ? id.substring(0, 8) : id}',
      motif: AligneurCatalogue._texte(d['motif']) ?? '',
      montant: montant,
      dateEmission: date,
    );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Un encaissement du serveur. DÉTENU : seule l'annulation suit, jamais
  /// à rebours. NOUVEAU : inscrit sur sa facture et sa caisse, sans pièce.
  Future<IssueAlignement> _paiement(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final statut = switch (AligneurCatalogue._texte(d['statut'])) {
      'actif' => StatutPaiementFacture.actif,
      'annule' => StatutPaiementFacture.annule,
      _ => null,
    };
    if (statut == null) {
      return RefuseParLePoste(
        'statut d’encaissement inconnu « ${d['statut']} »',
      );
    }
    DateTime? annulation;
    try {
      annulation = d['date_annulation'] == null
          ? null
          : _instant(d['date_annulation']);
    } on FormatException {
      return const RefuseParLePoste('date d’annulation illisible');
    }
    final paiements = PaiementsFactureDao(_db, moteur: _moteur);
    if (await _existe(_db.paiementsFactureLocal, id)) {
      if (statut == StatutPaiementFacture.annule) {
        final auteur = await _auteurOuAttente();
        if (auteur == null) return AligneurCatalogue._sansAuteur;
        await paiements.suivreAnnulationDescendue(
          id: id,
          motif: AligneurCatalogue._texte(d['motif_annulation']),
          date: annulation,
          auteurId: auteur,
        );
      }
      return const Aligne();
    }
    final mode = ModePaiementFacture.depuisCode('${d['mode_paiement']}');
    final montant = entierDepuisDecimal(d['montant'], 2);
    final factureServeur = AligneurCatalogue._texte(d['facture_id']);
    final sessionServeur = AligneurCatalogue._texte(d['session_id']);
    if (mode == null ||
        montant == null ||
        factureServeur == null ||
        sessionServeur == null) {
      return const RefuseParLePoste('encaissement incomplet');
    }
    final DateTime le;
    try {
      le = _instant(d['date_paiement']);
    } on FormatException {
      return const RefuseParLePoste('date d’encaissement illisible');
    }
    final pieceId = await _cite(
      TableDescendue.factures,
      factureServeur,
      _db.piecesFacturationLocal,
    );
    if (pieceId == null) {
      return const EnAttenteDeDependance('facture pas encore reçue');
    }
    final sessionId = await _cite(
      TableDescendue.sessionsCaisse,
      sessionServeur,
      _db.sessionsCaisseLocal,
    );
    if (sessionId == null) {
      return const EnAttenteDeDependance('caisse pas encore reçue');
    }
    final auteur = await _auteurOuAttente();
    if (auteur == null) return AligneurCatalogue._sansAuteur;
    await paiements.inscrireDescendu(
      id: id,
      pieceId: pieceId,
      sessionId: sessionId,
      mode: mode,
      montantCentimes: montant,
      datePaiement: le,
      statut: statut,
      motifAnnulation: AligneurCatalogue._texte(d['motif_annulation']),
      dateAnnulation: annulation,
      auteurId: auteur,
    );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Achats                                                              */
  /* ================================================================== */

  static const _rangCommande = {
    'brouillon': 0,
    'envoyee': 1,
    'receptionnee_partiellement': 2,
    'receptionnee': 3,
    'cloturee': 4,
  };

  /// Une commande d'achat. Existante : seul le statut, et seulement vers
  /// l'avant (une réception d'un autre poste la fait progresser).
  Future<IssueAlignement> _commande(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final statut = AligneurCatalogue._texte(d['statut']);
    if (!_rangCommande.containsKey(statut)) {
      return RefuseParLePoste('statut de commande inconnu « $statut »');
    }
    final t = _db.commandesAchatLocal;
    final existante = await (_db.select(
      t,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (existante != null) {
      if ((_rangCommande[statut] ?? 0) >
          (_rangCommande[existante.statut] ?? 0)) {
        await (_db.update(t)..where((c) => c.id.equals(id))).write(
          CommandesAchatLocalCompanion(statut: Value(statut!)),
        );
      }
      return const Aligne();
    }
    final fournisseurServeur = AligneurCatalogue._texte(d['fournisseur_id']);
    if (fournisseurServeur == null) {
      return const RefuseParLePoste('fournisseur absent');
    }
    final fournisseur = await _cite(
      TableDescendue.fournisseurs,
      fournisseurServeur,
      _db.fournisseursLocal,
    );
    if (fournisseur == null) {
      return const EnAttenteDeDependance('fournisseur pas encore reçu');
    }
    final String? date;
    final DateTime creee;
    try {
      date = AligneurCatalogue._jour(d['date_commande']);
      creee = _instant(d['date_creation']);
    } on FormatException {
      return const RefuseParLePoste('dates de commande illisibles');
    }
    if (date == null) return const RefuseParLePoste('date de commande absente');
    final lignes = _lignes(d);
    if (lignes == null || lignes.isEmpty) {
      return const RefuseParLePoste('commande sans ligne');
    }
    final converties =
        <({String article, String libelle, String unite, int qte, int prix})>[];
    for (final l in lignes) {
      final articleServeur = AligneurCatalogue._texte(l['article_id']);
      final qte = entierDepuisDecimal(l['quantite_commandee'], 2);
      final prix = entierDepuisDecimal(l['prix_unitaire'], 2);
      if (articleServeur == null || qte == null || prix == null) {
        return const RefuseParLePoste('ligne de commande illisible');
      }
      final article = await _cite(
        TableDescendue.articles,
        articleServeur,
        _db.articlesLocal,
      );
      if (article == null) {
        return const EnAttenteDeDependance('article pas encore reçu');
      }
      final a = await (_db.select(
        _db.articlesLocal,
      )..where((x) => x.id.equals(article))).getSingle();
      converties.add((
        article: article,
        libelle: a.libelle,
        unite: a.uniteMesure,
        qte: qte,
        prix: prix,
      ));
    }
    final auteur = await _auteurOuAttente();
    if (auteur == null) return AligneurCatalogue._sansAuteur;
    await _db
        .into(t)
        .insert(
          CommandesAchatLocalCompanion.insert(
            id: id,
            fournisseurId: fournisseur,
            dateCommande: date,
            statut: statut!,
            creeLe: creee,
            utilisateurId: auteur,
          ),
        );
    for (var i = 0; i < converties.length; i++) {
      final l = converties[i];
      await _db
          .into(_db.lignesCommandeAchatLocal)
          .insert(
            LignesCommandeAchatLocalCompanion.insert(
              id: '$id:$i',
              commandeId: id,
              articleId: l.article,
              articleLibelle: l.libelle,
              uniteMesure: l.unite,
              quantiteCentiemes: l.qte,
              prixUnitaireCentimes: l.prix,
              rang: i + 1,
            ),
          );
    }
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  static const _conformites = {'totale', 'partielle', 'non_conforme'};

  /// Un bon de réception d'un autre poste : le bon et ses lignes, AUCUNE
  /// entrée de stock (elles descendent comme `mouvements_stock`).
  Future<IssueAlignement> _bon(String id, ElementCatalogue e) async {
    final d = e.donnees;
    if (await _existe(_db.bonsReceptionLocal, id)) return const Aligne();
    final conformite = AligneurCatalogue._texte(d['conformite']);
    if (!_conformites.contains(conformite)) {
      return RefuseParLePoste('conformité inconnue « $conformite »');
    }
    final commandeServeur = AligneurCatalogue._texte(d['commande_id']);
    if (commandeServeur == null) {
      return const RefuseParLePoste('commande absente');
    }
    final commande = await _cite(
      TableDescendue.commandesAchat,
      commandeServeur,
      _db.commandesAchatLocal,
    );
    if (commande == null) {
      return const EnAttenteDeDependance('commande pas encore reçue');
    }
    final String? date;
    final DateTime creee;
    try {
      date = AligneurCatalogue._jour(d['date_reception']);
      creee = _instant(d['created_at']);
    } on FormatException {
      return const RefuseParLePoste('dates de réception illisibles');
    }
    if (date == null) {
      return const RefuseParLePoste('date de réception absente');
    }
    final lignes = _lignes(d);
    if (lignes == null || lignes.isEmpty) {
      // Le serveur relit les lignes de ses entrées de stock : un bon sans
      // entrée retrouvée n'a rien à montrer, et aucun point où le ranger.
      return const RefuseParLePoste('bon sans ligne retrouvée au serveur');
    }
    String? point;
    final converties = <({String article, int qte})>[];
    for (final l in lignes) {
      final articleServeur = AligneurCatalogue._texte(l['article_id']);
      final pointServeur = AligneurCatalogue._texte(l['point_id']);
      final qte = entierDepuisDecimal(l['quantite'], 2);
      if (articleServeur == null || pointServeur == null || qte == null) {
        return const RefuseParLePoste('ligne de réception illisible');
      }
      final article = await _cite(
        TableDescendue.articles,
        articleServeur,
        _db.articlesLocal,
      );
      point ??= await _cite(
        TableDescendue.pointsStockage,
        pointServeur,
        _db.pointsStockageLocal,
      );
      if (article == null || point == null) {
        return const EnAttenteDeDependance(
          'article ou point de stockage pas encore reçu',
        );
      }
      converties.add((article: article, qte: qte));
    }
    final auteur = await _auteurOuAttente();
    if (auteur == null) return AligneurCatalogue._sansAuteur;
    await _db
        .into(_db.bonsReceptionLocal)
        .insert(
          BonsReceptionLocalCompanion.insert(
            id: id,
            commandeId: commande,
            dateReception: date,
            conformite: conformite!,
            pointStockageId: point!,
            creeLe: creee,
            utilisateurId: auteur,
          ),
        );
    for (var i = 0; i < converties.length; i++) {
      await _db
          .into(_db.lignesBonReceptionLocal)
          .insert(
            LignesBonReceptionLocalCompanion.insert(
              id: '$id:$i',
              bonId: id,
              articleId: converties[i].article,
              quantiteCentiemes: converties[i].qte,
            ),
          );
    }
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /// Un règlement fournisseur saisi au serveur, SANS pièce locale. Existant :
  /// son annulation descend (statut, motif, date).
  Future<IssueAlignement> _reglement(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final statut = AligneurCatalogue._texte(d['statut']);
    if (statut != 'actif' && statut != 'annule') {
      return RefuseParLePoste('statut de règlement inconnu « $statut »');
    }
    DateTime? annulation;
    try {
      annulation = d['date_annulation'] == null
          ? null
          : _instant(d['date_annulation']);
    } on FormatException {
      return const RefuseParLePoste('date d’annulation illisible');
    }
    final t = _db.reglementsFournisseurLocal;
    if (await _existe(t, id)) {
      // Jamais à rebours ; celui de CE poste contre-passe sa pièce (le DAO
      // des règlements s'en charge).
      if (statut == 'annule') {
        final auteur = await _auteurOuAttente();
        if (auteur == null) return AligneurCatalogue._sansAuteur;
        await ReglementsFournisseurDao(
          _db,
          moteur: _moteur,
        ).suivreAnnulationDuServeur(
          id,
          motif: AligneurCatalogue._texte(d['motif_annulation']),
          date: annulation,
          auteurId: auteur,
        );
      }
      return const Aligne();
    }
    final commandeServeur = AligneurCatalogue._texte(d['commande_id']);
    final montant = entierDepuisDecimal(d['montant'], 2);
    final tresorerie = AligneurCatalogue._texte(d['tresorerie']);
    final String? date;
    try {
      date = AligneurCatalogue._jour(d['date_reglement']);
    } on FormatException {
      return const RefuseParLePoste('date de règlement illisible');
    }
    if (commandeServeur == null ||
        montant == null ||
        tresorerie == null ||
        date == null) {
      return const RefuseParLePoste('règlement incomplet');
    }
    final commande = await _cite(
      TableDescendue.commandesAchat,
      commandeServeur,
      _db.commandesAchatLocal,
    );
    if (commande == null) {
      return const EnAttenteDeDependance('commande pas encore reçue');
    }
    final auteur = await _auteurOuAttente();
    if (auteur == null) return AligneurCatalogue._sansAuteur;
    await _db
        .into(t)
        .insert(
          ReglementsFournisseurLocalCompanion.insert(
            id: id,
            commandeId: commande,
            montantCentimes: montant,
            tresorerie: tresorerie,
            dateReglement: date,
            statut: Value(statut!),
            motifAnnulation: Value(
              AligneurCatalogue._texte(d['motif_annulation']),
            ),
            dateAnnulation: Value(annulation),
            utilisateurCreationId: auteur,
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Stock                                                               */
  /* ================================================================== */

  static const _typesMouvement = {'entree', 'sortie', 'perte', 'inventaire'};

  /// Un mouvement de stock d'un autre poste (ou du serveur : sorties d'une
  /// vente, entrées d'une réception, inventaire). Le stock du poste est
  /// RECALCULÉ des mouvements (`calcul_stock.dart`) : il suit sans qu'aucune
  /// valeur calculée ne descende (PA-129). Même convention de signe que le
  /// serveur ; la quantité arrive en décimal à deux chiffres.
  Future<IssueAlignement> _mouvement(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final t = _db.mouvementsStockLocal;
    if (await _existe(t, id)) return const Aligne();
    final type = AligneurCatalogue._texte(d['type_mouvement']);
    if (!_typesMouvement.contains(type)) {
      return RefuseParLePoste('type de mouvement inconnu « $type »');
    }
    final centiemes = entierDepuisDecimal(d['quantite'], 2);
    if (centiemes == null) {
      return RefuseParLePoste('quantité « ${d['quantite']} » illisible');
    }
    final DateTime le;
    try {
      le = _instant(d['date_mouvement']);
    } on FormatException {
      return const RefuseParLePoste('date de mouvement illisible');
    }
    final articleServeur = AligneurCatalogue._texte(d['article_id']);
    final pointServeur = AligneurCatalogue._texte(d['point_id']);
    if (articleServeur == null || pointServeur == null) {
      return const RefuseParLePoste('article ou point absent');
    }
    final article = await _cite(
      TableDescendue.articles,
      articleServeur,
      _db.articlesLocal,
    );
    final point = await _cite(
      TableDescendue.pointsStockage,
      pointServeur,
      _db.pointsStockageLocal,
    );
    if (article == null || point == null) {
      return const EnAttenteDeDependance(
        'article ou point de stockage pas encore reçu',
      );
    }
    final dernier = await (_db.selectOnly(t)..addColumns([t.ordre.max()]))
        .map((r) => r.read(t.ordre.max()))
        .getSingle();
    await _db
        .into(t)
        .insert(
          MouvementsStockLocalCompanion.insert(
            id: id,
            articleId: article,
            pointId: point,
            typeMouvement: type!,
            quantite: centiemes / echelleQuantite,
            motif: AligneurCatalogue._texte(d['motif']) ?? '',
            dateMouvement: le,
            statutSync: const Value('synchronise'),
            ordre: Value((dernier ?? 0) + 1),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  /* ================================================================== */
  /* Tourisme                                                            */
  /* ================================================================== */

  static const _themes = {'aventure', 'culture', 'faune', 'nature'};

  /// Un circuit : une DÉFINITION, comme le catalogue — la version du serveur
  /// est prise (la saisie locale d'un circuit ne monte pas encore).
  Future<IssueAlignement> _circuit(String id, ElementCatalogue e) async {
    final d = e.donnees;
    final nom = AligneurCatalogue._texte(d['nom']);
    final theme = AligneurCatalogue._texte(d['theme']);
    final zone = AligneurCatalogue._texte(d['zone']);
    if (nom == null || zone == null) {
      return const RefuseParLePoste('nom ou zone absent');
    }
    if (!_themes.contains(theme)) {
      return RefuseParLePoste('thème de circuit inconnu « $theme »');
    }
    final prix = entierDepuisDecimal(d['prix'], 0);
    final capacite = d['capacite_max'] is int
        ? d['capacite_max']! as int
        : entierDepuisDecimal(d['capacite_max'], 0);
    if (prix == null || capacite == null || capacite <= 0) {
      return const RefuseParLePoste('prix ou capacité illisible');
    }
    await _db
        .into(_db.circuitsLocal)
        .insertOnConflictUpdate(
          CircuitsLocalCompanion.insert(
            id: id,
            nom: nom,
            theme: theme!,
            zone: zone,
            prix: prix.toDouble(),
            capaciteMax: capacite,
            duree: Value(AligneurCatalogue._texte(d['duree'])),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  Future<IssueAlignement> _guide(String id, ElementCatalogue e) async {
    final nom = AligneurCatalogue._texte(e.donnees['nom']);
    if (nom == null) return const RefuseParLePoste('nom absent');
    await _db
        .into(_db.guidesLocal)
        .insertOnConflictUpdate(
          GuidesLocalCompanion.insert(
            id: id,
            nom: nom,
            zoneCompetence: Value(
              AligneurCatalogue._texte(e.donnees['zone_competence']),
            ),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }

  static const _rangTour = {'reservee': 0, 'en_cours': 1, 'terminee': 2};

  /// Une réservation de circuit d'un autre poste : elle occupe le guide ce
  /// jour-là. Existante : le statut avance, jamais ne recule ; annulée ici,
  /// elle le reste.
  Future<IssueAlignement> _reservationTour(
    String id,
    ElementCatalogue e,
  ) async {
    final d = e.donnees;
    final statut = AligneurCatalogue._texte(d['statut']);
    if (statut != 'annulee' && !_rangTour.containsKey(statut)) {
      return RefuseParLePoste(
        'statut de réservation de circuit inconnu « $statut »',
      );
    }
    final t = _db.reservationsTourLocal;
    final existante = await (_db.select(
      t,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (existante != null) {
      if (existante.statut == 'annulee') return const Aligne();
      if (statut == 'annulee' ||
          (_rangTour[statut] ?? 0) > (_rangTour[existante.statut] ?? 0)) {
        await (_db.update(t)..where((r) => r.id.equals(id))).write(
          ReservationsTourLocalCompanion(statut: Value(statut!)),
        );
      }
      return const Aligne();
    }
    final DateTime jour;
    try {
      jour = _jourLocal(d['date_circuit']);
    } on FormatException {
      return const RefuseParLePoste('date de circuit illisible');
    }
    final participants = d['nb_participants'] is int
        ? d['nb_participants']! as int
        : entierDepuisDecimal(d['nb_participants'], 0);
    if (participants == null || participants <= 0) {
      return const RefuseParLePoste('nombre de participants illisible');
    }
    final circuitServeur = AligneurCatalogue._texte(d['circuit_id']);
    final clientServeur = AligneurCatalogue._texte(d['client_id']);
    final guideServeur = AligneurCatalogue._texte(d['guide_id']);
    if (circuitServeur == null ||
        clientServeur == null ||
        guideServeur == null) {
      return const RefuseParLePoste('circuit, client ou guide absent');
    }
    final circuit = await _cite(
      TableDescendue.circuits,
      circuitServeur,
      _db.circuitsLocal,
    );
    final client = await _cite(
      TableDescendue.clients,
      clientServeur,
      _db.clientsLocal,
    );
    final guide = await _cite(
      TableDescendue.guides,
      guideServeur,
      _db.guidesLocal,
    );
    if (circuit == null || client == null || guide == null) {
      return const EnAttenteDeDependance(
        'circuit, client ou guide pas encore reçu',
      );
    }
    await _db
        .into(t)
        .insert(
          ReservationsTourLocalCompanion.insert(
            id: id,
            circuitId: circuit,
            clientId: client,
            guideId: guide,
            dateCircuit: jour,
            nbParticipants: participants,
            statut: statut!,
            statutSync: const Value('synchronise'),
          ),
        );
    await _retenirOrigine(e, id);
    return const Aligne();
  }
}
