import '../../caisse/domain/entities/session_caisse.dart';
import '../../facturation/domain/creances.dart';
import '../../facturation/domain/entities/paiement_facture.dart';
import '../../facturation/domain/entities/piece_facturation.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../hebergement/domain/entities/unite_hebergement.dart';
import '../../rh/domain/entities/employe.dart';
import '../../stocks/data/stocks_api.dart';
import '../domain/entities/tableau_de_bord.dart';
import '../domain/indicateurs_locaux.dart';
import '../domain/periode_locale.dart';

/// Ce que la consultation du tableau de bord peut rendre.
///
/// Deux issues : « reçu » et « refusé » (le droit de lecture de M11 manque).
/// « Injoignable » n'existe plus : une base locale n'est pas hors
/// connexion, et une issue qu'aucun chemin ne produit est une branche morte
/// qui, au pire, affiche « fonctionnalité nécessitant une connexion » à un
/// poste qui n'en aura jamais.
sealed class ResultatTableauDeBord {
  const ResultatTableauDeBord();
}

final class TableauDeBordRecu extends ResultatTableauDeBord {
  const TableauDeBordRecu(this.tableau);
  final TableauDeBord tableau;
}

final class TableauDeBordRefuse extends ResultatTableauDeBord {
  const TableauDeBordRefuse({required this.motif});
  final String motif;
}

/// Les mêmes issues, pour les séries.
sealed class ResultatSeries {
  const ResultatSeries();
}

final class SeriesRecues extends ResultatSeries {
  const SeriesRecues(this.series);
  final SeriesTableauDeBord series;
}

final class SeriesRefusees extends ResultatSeries {
  const SeriesRefusees(this.motif);
  final String motif;
}

/// Les raisons d'absence, DATÉES. Une raison non datée vieillit sans que
/// personne la rouvre (PA-107, PA-120, PA-144).
///
/// ⚠ Trois raisons ont été RETIRÉES le 12/10/2026 (lot 5) parce que leur prémisse
/// est tombée : « aucun module de ce poste n'écrit de paiement » était vrai le
/// 10/10 et ne l'est plus (`PaiementsFactureDao`, schéma v18). Les indicateurs
/// « Chiffre d'affaires encaissé », « Trésorerie de caisse » et « Factures non
/// soldées » sont désormais calculés, par les fonctions de
/// `indicateurs_locaux.dart` confrontées au vrai `TableauDeBordService`.
abstract final class RaisonsTableauDeBord {
  static const String refusLecture =
      'Votre rôle ne permet pas de consulter le tableau de bord.';

  /// ⚠ Revue le 12/10/2026 (R7, D289) : la version du 10/10 rangeait « les
  /// achats reçus » et « la paie » parmi ce que le POSTE ne comptabilise pas.
  /// Le serveur ne les comptabilise pas non plus (aucune pièce à la réception,
  /// aucune dans `LivreDePaieService`) : ils entrent en classe 6 au serveur par
  /// la SAISIE MANUELLE du comptable, que ce poste n'offre pas. C'est elle, et
  /// les dépenses d'avant le portage des pièces, qui font le minorant.
  static const String depensesCumulees =
      'Ce chiffre se lit dans la comptabilité (classe 6, écritures validées). '
      'Ce poste n\'y passe que les pièces des dépenses courantes saisies ; la '
      'saisie manuelle des pièces du comptable (dont la paie), qui n\'existe '
      'qu\'au serveur, et les dépenses d\'avant n\'y entrent pas : la somme '
      'serait un minorant présenté comme le total. Les dépenses courantes '
      'saisies ont leur carte dans le pilotage consolidé (constaté le '
      '10/10/2026, revu le 12/10/2026).';

  /// ⚠ Revue le 12/10/2026 (D282) : la version du 10/10 disait que les DEUX
  /// courbes lisaient « des paiements … que ce poste n'écrit pas ». La moitié
  /// « paiements » est tombée avec le lot 5 ; seule la courbe des dépenses
  /// reste sans source complète, et le graphique trace les deux ensemble.
  ///
  /// ⚠ Revue le 14/10/2026 (lot C, PA-205) : la prémisse TIENT. Les pièces que
  /// ce poste passe depuis (ventes `VTE`, acomptes, remboursements,
  /// encaissements, règlements fournisseur) ne touchent pas la classe 6 ; la
  /// SAISIE MANUELLE de pièces du comptable n'a toujours aucun écran ici
  /// (Comptabilité, PA-204). Ce qui manque, exactement : (1) les pièces de
  /// charges saisies à la main (dont la paie), (2) les dépenses d'avant le
  /// portage des pièces (10/10/2026), sans pièce rétroactive.
  static const String serieMensuelle =
      'Les deux courbes (chiffre d’affaires encaissé, dépenses) se tracent '
      'ensemble. Celle des dépenses lit la comptabilité (classe 6), où ce '
      'poste ne passe que les pièces des dépenses courantes saisies : elle '
      'serait un minorant tracé comme le total. Le chiffre d’affaires encaissé '
      'de la période a sa carte dans la bande d’indicateurs (constaté le '
      '10/10/2026, revu le 14/10/2026).';
}

/// Le tableau de bord, établi sur la base du poste.
///
/// ## Aucune table, aucun cache
///
/// M11 est une LECTURE : chaque appel relit les modules sources et recalcule.
/// Garder la dernière réponse présenterait les chiffres d'hier comme ceux
/// d'aujourd'hui (PA-120) — le provider est `autoDispose` pour la même raison.
///
/// ## Les lecteurs sont INJECTÉS
///
/// Les écrans le câblent aux DAO ; un test l'appelle avec des listes
/// construites à la main, y compris celles qu'une base peine à produire.
final class TableauDeBordLocal {
  const TableauDeBordLocal({
    required this.unites,
    required this.reservations,
    required this.employes,
    required this.stock,
    required this.pieces,
    required this.creances,
    required this.paiements,
    required this.sessions,
    required this.peutLire,
    required this.maintenant,
  });

  final Future<List<UniteHebergement>> Function() unites;
  final Future<List<Reservation>> Function() reservations;
  final Future<List<Employe>> Function() employes;

  /// Passe par `StocksApi.etat()` : le droit de lecture de M6 est RESPECTÉ. Un
  /// profil sans M6 voit « — » et la phrase de refus, jamais la valeur.
  final Future<ResultatStock> Function() stock;
  final Future<List<PieceFacturation>> Function() pieces;

  /// Les créances (factures, avoirs, encaissements actifs et acomptes déduits) :
  /// la lecture UNIQUE que partagent le solde des clients et l'indicateur
  /// « Factures non soldées ».
  final Future<List<CreanceFacture>> Function() creances;

  /// Les encaissements de factures, annulés compris (le serveur ne filtre pas).
  final Future<List<PaiementFacture>> Function() paiements;

  /// Les sessions de caisse, ouvertes et closes.
  final Future<List<SessionCaisse>> Function() sessions;

  final bool Function() peutLire;
  final DateTime Function() maintenant;

  /// Le tableau de bord de l'ÉCRAN, sur la période CALENDAIRE du sélecteur —
  /// `Accueil::render()` : `$service->indicateurs($this->periode())`.
  Future<ResultatTableauDeBord> consulter(SelectionPeriode selection) =>
      _etablir(() => FenetreTableauDeBord.resoudre(selection, maintenant()));

  /// Le tableau de bord sur une fenêtre « À DATE » — `EtatTableauDeBord` du
  /// moteur d'états (`Periode::depuisCode`), pour l'aperçu M14. Ce n'est PAS
  /// la fenêtre de l'écran : le serveur pose les deux, et ce poste aussi.
  Future<ResultatTableauDeBord> consulterADate(PeriodeADate periode) =>
      _etablir(() => FenetreTableauDeBord.depuis(periode, maintenant()));

  Future<ResultatTableauDeBord> _etablir(
    FenetreTableauDeBord Function() resoudre,
  ) async {
    if (!peutLire()) {
      return const TableauDeBordRefuse(
        motif: RaisonsTableauDeBord.refusLecture,
      );
    }

    final fenetre = resoudre();
    final avant = fenetre.precedente;

    final parc = await unites();
    final resas = await reservations();
    final salaries = await employes();
    final etatStock = await stock();
    final encaissements = await paiements();
    final caisses = await sessions();
    final creancesDuPoste = await creances();

    // Taux : courant ET précédent, sur le même parc — comparer deux photos du
    // parc n'aurait pas de sens.
    final tauxCourant = tauxOccupationCentiemes(
      unites: parc,
      reservations: resas,
      fenetre: fenetre,
    );
    final tauxAvant = tauxOccupationCentiemes(
      unites: parc,
      reservations: resas,
      fenetre: avant,
    );

    final attenteCourant = reservationsEnAttente(resas, fenetre);
    final attenteAvant = reservationsEnAttente(resas, avant);

    final indicateurs = <IndicateurTableauDeBord>[
      _montant(
        'chiffre_affaires_encaisse',
        chiffreAffairesEncaisseCentimes(encaissements, fenetre),
        chiffreAffairesEncaisseCentimes(encaissements, avant),
      ),
      if (tauxCourant == null)
        const IndicateurTableauDeBord.indisponible(
          cle: 'taux_occupation',
          unite: UniteIndicateur.pourcentage,
          raison:
              'Aucune unité louable au parc : le taux n’est pas calculable '
              '(un parc vide ne dit pas « 0 % », il dit qu’il est vide).',
        )
      else
        IndicateurTableauDeBord(
          cle: 'taux_occupation',
          valeur: centiemesEnChaine(tauxCourant),
          // Un précédent non calculable vaut « 0.00 » côté serveur, d'où une
          // variation absente : on n'invente pas de base de comparaison.
          precedent: centiemesEnChaine(tauxAvant ?? 0),
          variationPct: variationEnPourcent(
            centiemesEnChaine(tauxCourant),
            centiemesEnChaine(tauxAvant ?? 0),
          ),
          unite: UniteIndicateur.pourcentage,
        ),
      _montant(
        'tresorerie_caisse',
        tresorerieCaisseCentimes(
          sessions: caisses,
          paiements: encaissements,
          fenetre: fenetre,
        ),
        tresorerieCaisseCentimes(
          sessions: caisses,
          paiements: encaissements,
          fenetre: avant,
        ),
      ),
      const IndicateurTableauDeBord.indisponible(
        cle: 'depenses_cumulees',
        unite: UniteIndicateur.montant,
        raison: RaisonsTableauDeBord.depensesCumulees,
      ),
      IndicateurTableauDeBord(
        cle: 'reservations_en_attente',
        valeur: '$attenteCourant',
        precedent: '$attenteAvant',
        variationPct: variationEnPourcent('$attenteCourant', '$attenteAvant'),
        unite: UniteIndicateur.nombre,
      ),
      _nombre(
        'factures_impayees',
        facturesImpayeesDansLaFenetre(creancesDuPoste, fenetre),
        facturesImpayeesDansLaFenetre(creancesDuPoste, avant),
      ),
      switch (etatStock) {
        StockRecu(:final etat) => IndicateurTableauDeBord(
          cle: 'valeur_stock',
          valeur: etat.kpis.valeurStock,
          // Une photographie à l'instant : le serveur ne compare pas deux
          // photos, et le précédent y vaut '0.00' sans variation.
          precedent: '0.00',
          unite: UniteIndicateur.montant,
          // Une somme partielle DIT ce qu'elle ne comprend pas : un article en
          // stock sans entrée valorisée compte pour zéro franc (D119).
          mention: etat.kpis.sansValorisation == 0
              ? null
              : 'hors ${mentionStockSansCout(etat.kpis)}',
        ),
        StockRefuse(:final motif) => IndicateurTableauDeBord.indisponible(
          cle: 'valeur_stock',
          unite: UniteIndicateur.montant,
          raison: motif,
        ),
        StockInjoignable() => const IndicateurTableauDeBord.indisponible(
          cle: 'valeur_stock',
          unite: UniteIndicateur.montant,
          raison: 'Le stock n’a pas pu être lu.',
        ),
      },
      IndicateurTableauDeBord(
        cle: 'employes_actifs',
        valeur: '${employesActifs(salaries)}',
        // `precedent` porte le total de la note « Sur N au total » — le même
        // détournement que le serveur, qui n'a pas de précédent pour l'effectif.
        precedent: '${effectifTotal(salaries)}',
        unite: UniteIndicateur.nombre,
      ),
    ];

    return TableauDeBordRecu(
      TableauDeBord(
        libellePeriode: fenetre.libelle,
        indicateurs: indicateurs,
        debut: fenetre.debut,
        finExclue: fenetre.finExclue,
      ),
    );
  }

  /// Un indicateur en MONTANT, avec sa variation — `comparer()` du serveur : les
  /// deux valeurs en chaînes à deux décimales, la variation tronquée.
  IndicateurTableauDeBord _montant(String cle, int courant, int precedent) {
    final valeur = centiemesEnChaine(courant);
    final avant = centiemesEnChaine(precedent);
    return IndicateurTableauDeBord(
      cle: cle,
      valeur: valeur,
      precedent: avant,
      variationPct: variationEnPourcent(valeur, avant),
      unite: UniteIndicateur.montant,
    );
  }

  /// Un indicateur en NOMBRE, avec sa variation.
  IndicateurTableauDeBord _nombre(String cle, int courant, int precedent) =>
      IndicateurTableauDeBord(
        cle: cle,
        valeur: '$courant',
        precedent: '$precedent',
        variationPct: variationEnPourcent('$courant', '$precedent'),
        unite: UniteIndicateur.nombre,
      );

  /// La ventilation suit la période du sélecteur (`ventilationParActivite(
  /// $periode)` de la vue) ; la série mensuelle a sa propre étendue.
  Future<ResultatSeries> consulterSeries({
    required SelectionPeriode selection,
    required int mois,
  }) async {
    if (!peutLire()) {
      return const SeriesRefusees(RaisonsTableauDeBord.refusLecture);
    }

    final fenetre = FenetreTableauDeBord.resoudre(selection, maintenant());
    final registre = await pieces();

    return SeriesRecues(
      SeriesTableauDeBord(
        mensuelle: const [],
        raisonMensuelle: RaisonsTableauDeBord.serieMensuelle,
        ventilation: ventilationParActivite(registre, fenetre),
      ),
    );
  }
}

/// Le chiffre d'affaires FACTURÉ par activité — `ventilationParActivite()` du
/// serveur, sur le registre unique des pièces de ce poste.
///
/// ## Ce n'est pas la mesure du prototype, et le serveur non plus
///
/// On ventile des MONTANTS facturés (`lignes_facture.source_module`), pas des
/// occurrences de service. Les avoirs viennent en diminution — leurs lignes ont
/// une quantité négative au registre — et la facture ANNULÉE reste comptée
/// avec son avoir : les deux s'annulent, comme au serveur. Les exclure
/// gonflerait l'activité d'un chiffre annulé.
///
/// Tri : montant décroissant ; à égalité, le code de module — le serveur n'en
/// fixe aucun, et deux exécutions ne doivent pas dessiner deux camemberts.
List<PartActivite> ventilationParActivite(
  List<PieceFacturation> pieces,
  FenetreTableauDeBord fenetre,
) {
  final parModule = <String, int>{};
  for (final piece in pieces) {
    if (!fenetre.contientComme(piece.dateEmission)) continue;
    for (final entree in piece.ventilation.entries) {
      parModule[entree.key.code] =
          (parModule[entree.key.code] ?? 0) + entree.value;
    }
  }
  final lignes = parModule.entries.toList()
    ..sort((a, b) {
      final ecart = b.value.compareTo(a.value);
      return ecart != 0 ? ecart : a.key.compareTo(b.key);
    });
  return [
    for (final e in lignes)
      PartActivite(module: e.key, montant: '${e.value}.00'),
  ];
}
