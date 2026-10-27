/// Les DEUX MODALES d'ouverture de session — réplique de
/// `App\Pwa\Livewire\Transverse\AlertesOuvertureModales` et des trois
/// collecteurs de `App\Pwa\Support\AlertesOuverture` qui les nourrissent
/// (`stockCritiqueModale`, `departsAEcheance`, `creancesModale`). Fonctions
/// PURES : aucune base, aucun widget.
///
/// ## Ce que la cloche n'est pas
///
/// La CLOCHE (`alertes_ouverture.dart`) plafonne chaque famille à cinq lignes ;
/// les modales NON : le maître affiche dix lignes par bloc puis « … et N
/// autre(s) » ([lignesParBloc]). Ce sont deux mécanismes que le serveur
/// distingue lui-même — d'où deux fichiers.
///
/// ## L'enchaînement
///
/// Deux étapes au plus, dans cet ordre : « Stock critique », puis « Opérations
/// du jour » (départs ET créances ensemble). Une étape vide n'existe pas : si
/// tout est vide, rien ne s'ouvre. [etapesOuverture] les compose sous le RBAC de
/// leur bloc (module lisible : stock M6, départs M1, créances M3).
///
/// ## Écarts au serveur, nommés (27/10/2026)
///
/// * L'ordre des lignes de stock à criticité égale est celui des articles puis
///   des points (le serveur : l'ordre que rend MySQL, sans `ORDER BY`).
/// * Le nom d'une créance est celui COPIÉ à l'émission de la facture (le
///   serveur relit la fiche client) ; une facture sans client identifié forme
///   une ligne à part, listée mais SANS action (aucune relance ne peut la
///   citer).
/// * Les lignes sont figées à l'ouverture de la modale : une ligne traitée y
///   reste, estompée, « Fait » / « Tracée » (la vue le décrit ; le serveur,
///   qui recalcule à chaque rendu, la ferait disparaître).
library;

import '../../facturation/domain/creances.dart';
import '../../stocks/domain/calcul_stock.dart';
import 'alertes_ouverture.dart' show ancienneteCreanceJours, quantiteAffichee;

/// `AlertesOuverture::LIGNES_PAR_BLOC` — le maître coupe chaque bloc à dix.
const int lignesParBloc = 10;

/// `AlertesOuverture::JOURS_RELANCE_RECENTE` — « relancer un client contacté
/// avant-hier abîme la relation sans rien accélérer ».
const int joursRelanceRecente = 14;

/// Au-delà, la créance est « douteuse » : sa pastille passe au rouge.
const int joursCreanceDouteuse = 90;

/// Les canaux de relance de la modale (`RelanceClient::CANAUX`), dans l'ordre
/// du serveur, avec le libellé de `pwa.alertes_ouverture.canal_*`. Le premier
/// est le canal par défaut (`$canalRelance = 'telephone'`).
const List<(String, String)> canauxRelanceOuverture = [
  ('telephone', 'Appel téléphonique'),
  ('whatsapp', 'WhatsApp'),
  ('email', 'E-mail'),
  ('courrier', 'Courrier'),
  ('visite', 'Visite'),
];

/// `lang/fr/pwa.php`, groupe `alertes_ouverture`, au mot.
abstract final class TextesOuverture {
  static const String titreStock = 'Stock critique';
  static const String sousTitreStock =
      'Articles au niveau ou sous leur seuil de réapprovisionnement. Les lignes '
      'en rouge sont déjà en rupture.';
  static const String titreOperations = 'Opérations du jour à traiter';
  static const String sousTitreOperations =
      'Départs arrivés à échéance et créances à relancer. Rien n’est bloquant, '
      'mais tout se dégrade si personne ne le voit.';

  static const String blocStockTitre = 'Articles à réapprovisionner';
  static const String blocStockSousTitre =
      'Relevé à l’ouverture de votre session';
  static String stockDetail(String stock, String unite, String seuil) =>
      'Stock $stock $unite — seuil d’alerte $seuil';
  static const String lienStocks = 'Ouvrir les stocks';

  static const String blocDepartsTitre = 'Réservations arrivées à échéance';
  static const String blocDepartsSousTitre =
      'Départ du jour, ou départ dépassé sans check-out (en rouge)';
  static String departDepasse(String date) =>
      'Départ prévu le $date — check-out non effectué';
  static const String departAujourdhui = 'Départ aujourd’hui';
  static const String lienReservations = 'Ouvrir les réservations';
  static const String checkout = 'Check-out';
  static const String fait = 'Fait';
  static const String sejourIntrouvable =
      'Ce séjour n’existe plus : rien n’a été modifié.';

  static const String blocCreancesTitre = 'Créances à relancer';
  static const String blocCreancesSousTitre =
      'Sommes échues de plus de 30 jours — en rouge, au-delà de 90 jours';
  static String creanceDetail(String montant, int jours) =>
      '$montant restant dus · $jours j d’ancienneté';
  static const String jamaisRelance = ' · jamais relancé';
  static String relanceLe(String date) => ' · relancé le $date';
  static const String lienCreances = 'Ouvrir les créances';
  static const String relancer = 'Relancer';
  static const String tracee = 'Tracée';
  static const String relanceRecente = 'relance récente';
  static const String relanceIndisponible =
      'Cette créance n’est pas relançable pour le moment.';
  static const String relanceCommentaire =
      'Relance déclenchée depuis les alertes d’ouverture de session';

  static const String suivant = 'Suivant →';
  static const String prisConnaissance = 'J’ai pris connaissance';
  static const String droitManquant =
      'Votre rôle ne permet pas ce geste depuis les alertes d’ouverture.';
  static String etAutres(int nombre) => '… et $nombre autre(s).';
}

/// Une ligne du bloc « Stock critique ».
final class LigneStockOuverture {
  const LigneStockOuverture({
    required this.articleId,
    required this.libelle,
    required this.detail,
    required this.critique,
  });

  final String articleId;
  final String libelle;
  final String detail;

  /// En rupture (stock `<= 0`) : pastille rouge.
  final bool critique;
}

/// Une ligne du bloc « Réservations arrivées à échéance ».
final class LigneDepartOuverture {
  const LigneDepartOuverture({
    required this.sejourId,
    required this.reservationId,
    required this.libelle,
    required this.detail,
    required this.critique,
  });

  final String sejourId;

  /// Le geste « Check-out » du poste porte sur la réservation (`SejourDao`).
  final String reservationId;
  final String libelle;
  final String detail;

  /// Départ DÉPASSÉ sans check-out : pastille rouge.
  final bool critique;
}

/// Une ligne du bloc « Créances à relancer ».
final class LigneCreanceOuverture {
  const LigneCreanceOuverture({
    required this.clientId,
    required this.libelle,
    required this.detail,
    required this.critique,
    required this.relanceRequise,
    required this.resteCentimes,
  });

  /// `null` : facture sans client identifié — listée, sans action.
  final String? clientId;
  final String libelle;
  final String detail;

  /// Plus ancienne échéance de plus de [joursCreanceDouteuse] jours.
  final bool critique;

  /// Plus de 30 jours d'ancienneté ET aucune relance depuis [joursRelanceRecente].
  final bool relanceRequise;

  /// Le reste dû réel du client — le montant réclamé par « Relancer ».
  final int resteCentimes;

  /// La clé de « traité » (`client:<id>`).
  String get cleTraitee => 'client:$clientId';
}

/// Une étape de la séquence.
sealed class EtapeOuverture {
  const EtapeOuverture();
}

/// L'étape 1 : `['nom' => 'stock', 'stock' => …]`.
final class EtapeStock extends EtapeOuverture {
  const EtapeStock(this.lignes);
  final List<LigneStockOuverture> lignes;
}

/// L'étape 2 : `['nom' => 'operations', 'departs' => …, 'creances' => …]`.
final class EtapeOperations extends EtapeOuverture {
  const EtapeOperations({required this.departs, required this.creances});
  final List<LigneDepartOuverture> departs;
  final List<LigneCreanceOuverture> creances;
}

/// `Carbon::today()`.
DateTime _minuit(DateTime maintenant) =>
    DateTime(maintenant.year, maintenant.month, maintenant.day);

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `AlertesOuverture::stockCritiqueModale()` : tous les couples (article, point)
/// qui portent des mouvements et dont le solde est au niveau ou sous le seuil,
/// SANS plafond de famille, les ruptures d'abord (tri stable).
List<LigneStockOuverture> stockCritiqueModale({
  required List<ArticleCalcul> articles,
  required List<MouvementCalcul> mouvements,
}) {
  final parId = {for (final a in articles) a.id: a};
  final soldes = <(String, String), int>{};
  for (final m in mouvements) {
    final cle = (m.articleId, m.pointId);
    soldes[cle] = (soldes[cle] ?? 0) + variation(m.type, m.centiemes);
  }
  final couples = soldes.keys.toList()
    ..sort((a, b) {
      final parArticle = a.$1.compareTo(b.$1);
      return parArticle != 0 ? parArticle : a.$2.compareTo(b.$2);
    });

  final lignes = <LigneStockOuverture>[];
  for (final couple in couples) {
    final article = parId[couple.$1];
    if (article == null) continue; // jointure interne du serveur
    final solde = soldes[couple]!;
    if (solde > article.seuilCentiemes) continue;
    lignes.add(
      LigneStockOuverture(
        articleId: article.id,
        libelle: article.libelle,
        detail: TextesOuverture.stockDetail(
          quantiteAffichee(solde),
          article.uniteMesure,
          quantiteAffichee(article.seuilCentiemes),
        ),
        critique: solde <= 0,
      ),
    );
  }
  // `usort` de PHP 8 est stable : les ruptures d'abord, l'ordre conservé.
  return [
    ...lignes.where((l) => l.critique),
    ...lignes.where((l) => !l.critique),
  ];
}

/// Un séjour ouvert dont le départ est prévu aujourd'hui ou avant — la lecture
/// de `SejourDao.departsAEcheance`.
typedef DepartAEcheance = ({
  String sejourId,
  String reservationId,
  DateTime dateDepart,
  String? clientPrenom,
  String clientNom,
  String uniteNumero,
});

/// `AlertesOuverture::departsAEcheance()` : départ du jour, ou dépassé sans
/// check-out (en rouge). [departs] est déjà filtrée (séjour ouvert, départ
/// `<=` aujourd'hui) et triée par date de départ.
List<LigneDepartOuverture> departsAEcheance({
  required List<DepartAEcheance> departs,
  required DateTime maintenant,
}) {
  final aujourdhui = _iso(_minuit(maintenant));
  return [
    for (final d in departs)
      LigneDepartOuverture(
        sejourId: d.sejourId,
        reservationId: d.reservationId,
        libelle:
            "${'${d.clientPrenom ?? ''} ${d.clientNom}'.trim()} — ${d.uniteNumero}",
        detail: _iso(d.dateDepart).compareTo(aujourdhui) < 0
            ? TextesOuverture.departDepasse(_date(d.dateDepart))
            : TextesOuverture.departAujourdhui,
        critique: _iso(d.dateDepart).compareTo(aujourdhui) < 0,
      ),
  ];
}

/// `MontantFcfa::format(bcadd($reste, '0', 2))` : arrondi au franc (moitié
/// éloignée de zéro), groupes de trois, suffixe « FCFA ».
String _montant(int centimes, String Function(int francs) formaterFcfa) {
  final francs = centimes >= 0
      ? (centimes + 50) ~/ 100
      : -((-centimes + 50) ~/ 100);
  return formaterFcfa(francs);
}

/// `AlertesOuverture::creancesModale()` : une ligne par CLIENT qui doit des
/// factures impayées émises il y a [ancienneteCreanceJours] jours ou plus ;
/// la plus ancienne d'abord, puis celles qui appellent une relance en tête
/// (tri stable). [derniereRelance] : la date de la dernière relance de chaque
/// client.
List<LigneCreanceOuverture> creancesModale({
  required List<CreanceFacture> creances,
  required Map<String, DateTime> derniereRelance,
  required DateTime maintenant,
  required String Function(int francs) formaterFcfa,
}) {
  final aujourdhui = _minuit(maintenant);
  final seuil = DateTime(
    aujourdhui.year,
    aujourdhui.month,
    aujourdhui.day - ancienneteCreanceJours,
  );
  final seuilRecente = _iso(
    DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day - joursRelanceRecente,
    ),
  );
  final seuilDouteuse = _iso(
    DateTime(
      aujourdhui.year,
      aujourdhui.month,
      aujourdhui.day - joursCreanceDouteuse,
    ),
  );

  // GROUP BY client : la plus ancienne émission et la somme des restes dus.
  final groupes = <String, _Groupe>{};
  for (final c in creances) {
    if (!c.estImpayee || c.piece.dateEmission.isAfter(seuil)) continue;
    final id = c.piece.clientId;
    final cle = id ?? 'nom:${c.piece.clientNom.trim()}';
    final g = groupes.putIfAbsent(
      cle,
      () => _Groupe(id, c.piece.clientNom.trim()),
    );
    g.reste += c.resteDuBrutCentimes;
    if (g.plusAncienne == null ||
        c.piece.dateEmission.isBefore(g.plusAncienne!)) {
      g.plusAncienne = c.piece.dateEmission;
    }
  }
  final ordonnes = groupes.values.toList()
    ..sort((a, b) => a.plusAncienne!.compareTo(b.plusAncienne!));

  final lignes = <LigneCreanceOuverture>[];
  for (final g in ordonnes) {
    final derniere = g.clientId == null ? null : derniereRelance[g.clientId];
    final plusAncienne = _minuit(g.plusAncienne!);
    final anciennete = aujourdhui.difference(plusAncienne).inDays;
    final relanceRequise =
        g.clientId != null &&
        (derniere == null || _iso(derniere).compareTo(seuilRecente) < 0);
    lignes.add(
      LigneCreanceOuverture(
        clientId: g.clientId,
        libelle: g.nom.isEmpty ? 'Client inconnu' : g.nom,
        detail:
            TextesOuverture.creanceDetail(
              _montant(g.reste, formaterFcfa),
              anciennete,
            ) +
            (derniere == null
                ? TextesOuverture.jamaisRelance
                : TextesOuverture.relanceLe(_date(derniere))),
        critique: _iso(plusAncienne).compareTo(seuilDouteuse) <= 0,
        relanceRequise: relanceRequise,
        resteCentimes: g.reste,
      ),
    );
  }
  return [
    ...lignes.where((l) => l.relanceRequise),
    ...lignes.where((l) => !l.relanceRequise),
  ];
}

class _Groupe {
  _Groupe(this.clientId, this.nom);
  final String? clientId;
  final String nom;
  int reste = 0;
  DateTime? plusAncienne;
}

/// `AlertesOuvertureModales::etapes()` : les étapes NON VIDES, dans l'ordre. Un
/// bloc dont le module n'est pas lisible passe `null` (il n'est pas lu).
List<EtapeOuverture> etapesOuverture({
  List<LigneStockOuverture>? stock,
  List<LigneDepartOuverture>? departs,
  List<LigneCreanceOuverture>? creances,
}) {
  final etapes = <EtapeOuverture>[];
  if (stock != null && stock.isNotEmpty) etapes.add(EtapeStock(stock));
  final d = departs ?? const <LigneDepartOuverture>[];
  final c = creances ?? const <LigneCreanceOuverture>[];
  if (d.isNotEmpty || c.isNotEmpty) {
    etapes.add(EtapeOperations(departs: d, creances: c));
  }
  return etapes;
}
