/// Les alertes de la CLOCHE de la barre supérieure — réplique de
/// `App\Pwa\Support\AlertesOuverture::pour()` du serveur (14/10/2026, lot B du
/// plan du PO). Fonctions PURES : aucune base, aucun widget.
///
/// ## La règle du serveur, reprise telle quelle
///
/// Chaque alerte est DÉRIVÉE à la lecture depuis la table qui la fonde, jamais
/// stockée : une alerte affichée est vraie au moment où elle s'affiche, et
/// disparaît d'elle-même avec sa cause (PA-59/60/61). Seul l'état « vu » se
/// stocke (`alertes_vues_local`). Quatre familles, dans l'ordre du serveur
/// (`toutes()`), chacune plafonnée à [plafondParFamille] :
///
/// | Famille | Règle du serveur | Ici |
/// |---|---|---|
/// | Stock (M6) | `VerificationSeuilService::articlesCritiques()` — couples (article, point) PORTANT des mouvements, solde `<=` seuil ; rupture si solde `<= 0` | [alertesStock], sur les mouvements de `StocksDao` (même signe que `EXPRESSION_SOLDE`) |
/// | Caisse (M5) | session non clôturée ouverte AVANT aujourd'hui, plus ancienne d'abord | [alertesCaisse], sur `sessions_caisse_local` |
/// | Réservation (M1) | arrivée du jour SANS séjour au check-in enregistré | [alertesArrivees], sur `SejourDao.arriveesSansCheckIn` (dérivée depuis le 14/10/2026, lot C : `sejours_local`, v23) |
/// | Créance (M3) | facture impayée (`SQL_RESTE_DU > 0`) émise il y a 30 jours ou plus, plus ancienne d'abord | [alertesCreances], sur `creances.dart` (la seule formule du poste) |
///
/// Le RBAC filtre par MODULE (`MenuLateral::moduleAccessible`, masqué sur `-`
/// seulement) : [alertesVisibles]. La bascule « Alertes à l'ouverture de
/// session » éteint tout, pour tous les profils (`OptionsSysteme`).
///
/// ## Écarts au serveur, nommés (14/10/2026)
///
/// * **Ordre des alertes de stock** : la requête du serveur n'a AUCUN
///   `ORDER BY` (l'ordre est celui que rend MySQL) ; le poste trie par article
///   puis par point, pour qu'une même base rende toujours les mêmes cinq lignes.
/// * **Nom du client d'une créance** : le serveur relit la fiche client
///   (`prenom nom`) ; le registre du poste porte le nom COPIÉ à l'émission
///   (`PieceFacturation.clientNom`), qui est celui qu'il affiche partout.
/// * **Arrivées du jour** : DÉRIVÉES depuis le 14/10/2026 (lot C) — la table
///   des séjours est répliquée (v23), la ligne « Sur ce poste : … ne sont pas
///   signalées » du panneau est retirée (D403 levée).
///
/// @see EF-M6-05 Alerte de sous-stock
/// @see RG-07 Alerte de seuil
library;

import '../../../core/rbac/garde_acces.dart';
import '../../caisse/domain/entities/session_caisse.dart';
import '../../facturation/domain/creances.dart';
import '../../stocks/domain/calcul_stock.dart';

/// `AlertesOuverture::PLAFOND_PAR_FAMILLE` — « la cloche invite, l'écran
/// détaille ».
const int plafondParFamille = 5;

/// `AlertesOuverture::ANCIENNETE_CREANCE_JOURS`.
const int ancienneteCreanceJours = 30;

/// Les chaînes de la cloche — `lang/fr/pwa.php`, groupes `cloche` et
/// `coquille`, au mot (apostrophe droite).
abstract final class LibellesCloche {
  /// `pwa.coquille.notifications` — titre du panneau et `aria-label` du bouton.
  static const String notifications = 'Notifications';

  /// `pwa.cloche.tout_marquer_lu`.
  static const String toutMarquerLu = 'Tout marquer comme lu';

  /// `pwa.coquille.filtre_toutes`, `pwa.coquille.filtre_non_lues`.
  static const String filtreToutes = 'Toutes';
  static const String filtreNonLues = 'Non lues';

  /// `pwa.coquille.aucune_notification`, `pwa.cloche.aucune_non_lue`.
  static const String aucuneNotification = 'Aucune notification.';
  static const String aucuneNonLue = 'Aucune notification non lue.';

  /// `pwa.coquille.voir_notifications` — le lien de pied, vers le Journal
  /// d'Audit (`liensChassis()['journal_audit']`).
  static const String voirNotifications = 'Voir toutes les notifications →';

  /// `pwa.cloche.*` — titres et détails des alertes.
  static const String ruptureTitre = 'Rupture de stock';
  static String ruptureDetail(String article, String stock) =>
      '$article — stock épuisé ($stock).';
  static const String seuilTitre = 'Stock sous seuil';
  static String seuilDetail(String article, String stock, String seuil) =>
      '$article — $stock en stock (seuil $seuil).';
  static const String caisseTitre = 'Clôture de caisse en attente';
  static String caisseDetail(String point, String date) =>
      "La session $point ouverte le $date n'est pas clôturée.";
  static const String arriveeTitre = "Arrivée attendue aujourd'hui";
  static String arriveeDetail(String client) =>
      "$client — le check-in n'est pas enregistré.";
  static const String creanceTitre = 'Créance à relancer';
  static String creanceDetail(String client, String montant, String date) =>
      '$client — $montant restant dus depuis le $date.';
  static const String clientInconnu = 'Client inconnu';

  /// AJOUT déclaré (14/10/2026) — la vue n'a pas d'état d'échec (une erreur y
  /// est une page d'erreur du serveur). Ici, une lecture locale qui lève ne
  /// doit pas se lire « Aucune notification » : ce serait un « tout va bien »
  /// que rien n'a vérifié (PA-59/60/61).
  static const String lectureImpossible =
      "Les alertes n'ont pas pu être lues sur ce poste.";

  // ⚠ `sourcesNonDerivees` (« Sur ce poste : les arrivées du jour sans
  // check-in ne sont pas signalées… ») a été RETIRÉE le 14/10/2026 (lot C) :
  // sa prémisse — « la table des séjours n'existe pas sur ce poste » — est
  // tombée avec la v23. La garder aurait dit une absence qui n'est plus vraie.
}

/// La famille d'une alerte — `famille` du serveur.
enum FamilleAlerte { rupture, seuil, caisse, reservation, creance }

/// Une alerte de la cloche.
final class AlerteOuverture {
  const AlerteOuverture({
    required this.cle,
    required this.module,
    required this.famille,
    required this.titre,
    required this.detail,
    required this.routePwa,
    this.vue = false,
  });

  /// La clé DÉRIVÉE, celle du serveur (`stock:<article>:<point>`,
  /// `caisse:<session>`, `creance:<facture>`) — c'est elle que retient l'état
  /// « vu ».
  final String cle;

  /// Le module dont le droit décide de la visibilité.
  final ModuleTatacora module;

  final FamilleAlerte famille;
  final String titre;
  final String detail;

  /// Le NOM de route de la vue (`pwa.stocks.liste`), traduit en route Flutter
  /// par le registre unique `routesFlutterParRoutePwa`.
  final String routePwa;

  /// L'état « vu » du compte connecté.
  final bool vue;

  AlerteOuverture avecVue(bool vue) => AlerteOuverture(
    cle: cle,
    module: module,
    famille: famille,
    titre: titre,
    detail: detail,
    routePwa: routePwa,
    vue: vue,
  );
}

/// `AlertesOuverture::quantite()` — « 12 » plutôt que « 12.00 », « 0.5 » tel
/// quel, depuis un entier de CENTIÈMES.
String quantiteAffichee(int centiemes) {
  final brut = ecrireCentiemes(centiemes);
  var net = brut;
  if (net.contains('.')) {
    while (net.endsWith('0')) {
      net = net.substring(0, net.length - 1);
    }
    if (net.endsWith('.')) net = net.substring(0, net.length - 1);
  }
  return net.isEmpty || net == '-' || net == '-0' ? '0' : net;
}

/// La famille Stock — `alertesStock()` du serveur.
///
/// [articles] : le référentiel ; [mouvements] : TOUS les mouvements. Un couple
/// (article, point) n'existe que s'il porte au moins un mouvement (jointure du
/// serveur) ; son solde est la somme signée ([variation]).
List<AlerteOuverture> alertesStock({
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

  final alertes = <AlerteOuverture>[];
  for (final couple in couples) {
    final article = parId[couple.$1];
    // Jointure INTERNE du serveur (`join articles`) : un mouvement orphelin
    // ne produit aucune alerte.
    if (article == null) continue;
    final solde = soldes[couple]!;
    if (solde > article.seuilCentiemes) continue;
    final rupture = solde <= 0;
    final stock = quantiteAffichee(solde);
    alertes.add(
      AlerteOuverture(
        cle: 'stock:${couple.$1}:${couple.$2}',
        module: ModuleTatacora.m6Stocks,
        famille: rupture ? FamilleAlerte.rupture : FamilleAlerte.seuil,
        titre: rupture
            ? LibellesCloche.ruptureTitre
            : LibellesCloche.seuilTitre,
        detail: rupture
            ? LibellesCloche.ruptureDetail(article.libelle, stock)
            : LibellesCloche.seuilDetail(
                article.libelle,
                stock,
                quantiteAffichee(article.seuilCentiemes),
              ),
        routePwa: 'pwa.stocks.liste',
      ),
    );
    if (alertes.length == plafondParFamille) break;
  }
  return alertes;
}

/// `Carbon::today()` : minuit du jour de [maintenant].
DateTime _minuit(DateTime maintenant) =>
    DateTime(maintenant.year, maintenant.month, maintenant.day);

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year}';

/// La famille Caisse — `alertesCaisse()` du serveur : une session NON clôturée
/// ouverte avant aujourd'hui, la plus ancienne d'abord.
List<AlerteOuverture> alertesCaisse({
  required List<SessionCaisse> sessions,
  required DateTime maintenant,
}) {
  final aujourdhui = _minuit(maintenant);
  final ouvertes = [
    for (final s in sessions)
      if (s.estOuverte && s.dateOuverture.isBefore(aujourdhui)) s,
  ]..sort((a, b) => a.dateOuverture.compareTo(b.dateOuverture));
  return [
    for (final s in ouvertes.take(plafondParFamille))
      AlerteOuverture(
        cle: 'caisse:${s.id}',
        module: ModuleTatacora.m5Bar,
        famille: FamilleAlerte.caisse,
        titre: LibellesCloche.caisseTitre,
        // `(string) $session->point_vente` : le CODE de l'`enum`, tel quel.
        detail: LibellesCloche.caisseDetail(
          s.point.code,
          _date(s.dateOuverture),
        ),
        routePwa: 'pwa.pos.comptant',
      ),
  ];
}

/// La famille Réservation — `alertesReservations()` du serveur : une arrivée
/// du jour SANS séjour au check-in enregistré, la plus anciennement créée
/// d'abord, plafonnée à [plafondParFamille]. [arrivees] est déjà filtrée et
/// triée par la lecture (`SejourDao.arriveesSansCheckIn`) : `(réservation,
/// nom du client « prénom nom », null si la fiche est introuvable)`.
///
/// La clé est celle du serveur, `arrivee:<réservation>:<AAAA-MM-JJ>` : la même
/// arrivée, vue hier, redevient « non lue » si elle est encore attendue
/// aujourd'hui.
List<AlerteOuverture> alertesArrivees({
  required List<(String, String?)> arrivees,
  required DateTime maintenant,
}) {
  final jour = _minuit(maintenant);
  final iso =
      '${jour.year}-${jour.month.toString().padLeft(2, '0')}-'
      '${jour.day.toString().padLeft(2, '0')}';
  return [
    for (final (reservationId, client) in arrivees.take(plafondParFamille))
      AlerteOuverture(
        cle: 'arrivee:$reservationId:$iso',
        module: ModuleTatacora.m1Hebergement,
        famille: FamilleAlerte.reservation,
        titre: LibellesCloche.arriveeTitre,
        detail: LibellesCloche.arriveeDetail(
          client ?? LibellesCloche.clientInconnu,
        ),
        routePwa: 'pwa.hebergement',
      ),
  ];
}

/// `MontantFcfa::format` : arrondi au franc (moitié éloignée de zéro), groupes
/// de trois, suffixe « FCFA ».
String _montant(int centimes, String Function(int francs) formater) {
  final francs = centimes >= 0
      ? (centimes + 50) ~/ 100
      : -((-centimes + 50) ~/ 100);
  return formater(francs);
}

/// La famille Créance — `alertesCreances()` du serveur : facture IMPAYÉE émise
/// il y a [ancienneteCreanceJours] jours ou plus (`Carbon::today()->subDays`),
/// la plus ancienne d'abord.
List<AlerteOuverture> alertesCreances({
  required List<CreanceFacture> creances,
  required DateTime maintenant,
  required String Function(int francs) formaterFcfa,
}) {
  final aujourdhui = _minuit(maintenant);
  final seuil = DateTime(
    aujourdhui.year,
    aujourdhui.month,
    aujourdhui.day - ancienneteCreanceJours,
  );
  final anciennes =
      [
        for (final c in creances)
          if (c.estImpayee && !c.piece.dateEmission.isAfter(seuil)) c,
      ]..sort((a, b) {
        final parDate = a.piece.dateEmission.compareTo(b.piece.dateEmission);
        return parDate != 0
            ? parDate
            : a.piece.numero.compareTo(b.piece.numero);
      });
  return [
    for (final c in anciennes.take(plafondParFamille))
      AlerteOuverture(
        cle: 'creance:${c.piece.id}',
        module: ModuleTatacora.m3Crm,
        famille: FamilleAlerte.creance,
        titre: LibellesCloche.creanceTitre,
        detail: LibellesCloche.creanceDetail(
          c.piece.clientNom.trim().isEmpty
              ? LibellesCloche.clientInconnu
              : c.piece.clientNom.trim(),
          _montant(c.resteDuBrutCentimes, formaterFcfa),
          _date(c.piece.dateEmission),
        ),
        routePwa: 'pwa.clients',
      ),
  ];
}

/// `AlertesOuverture::pour()` : les familles dans l'ordre du serveur (stock,
/// caisse, réservations, créances), filtrées par le droit de LECTURE sur leur
/// module (masquées sur `-` seulement), marquées « vues » d'après [vues].
List<AlerteOuverture> alertesVisibles({
  required GardeAcces droits,
  required List<AlerteOuverture> toutes,
  required Set<String> vues,
}) => [
  for (final a in toutes)
    if (droits.peutLire(a.module)) a.avecVue(vues.contains(a.cle)),
];
