import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Le vérificateur qui permet d'ouvrir le comptoir **sans le serveur**.
///
/// ## Pourquoi cette pièce existe
///
/// Au Gîte, le lien vers Cotonou tombe. Jusqu'au 21/08/2026, `connecter()`
/// levait `ReseauIndisponible` dès que l'API était injoignable : **personne ne
/// pouvait ouvrir le comptoir**, alors que tout le reste de l'application est
/// conçu pour travailler hors ligne. Une caisse qui refuse d'ouvrir parce
/// qu'un routeur a redémarré n'est pas un logiciel offline-first.
///
/// ## Ce qui n'est JAMAIS stocké
///
/// **Le mot de passe ne l'est pas.** Ni en clair, ni chiffré — un chiffrement
/// suppose une clé, et une clé posée sur le même disque que le secret qu'elle
/// protège n'en protège aucun.
///
/// Ce qui est conservé est un **dérivé PBKDF2-HMAC-SHA256** : sel aléatoire de
/// 32 octets, [iterations] tours, empreinte de 32 octets. Il permet de
/// **vérifier** un mot de passe, jamais de le retrouver.
///
/// La comparaison est **à temps constant** ([_egalConstant]) : comparer deux
/// empreintes octet par octet avec sortie anticipée laisse fuir, par le temps
/// de réponse, combien d'octets de tête sont justes.
///
/// ## Les trois conditions, et aucune n'est facultative
///
/// 1. **Le serveur a déjà vu ce compte sur ce poste.** Le vérificateur n'est
///    posé qu'après une connexion **en ligne réussie** : c'est le serveur qui
///    a validé les identifiants, jamais ce fichier. Un compte inconnu du poste
///    ne peut pas s'y connecter hors ligne.
/// 2. **Les droits sont ceux que le serveur a accordés**, mémorisés à la
///    dernière connexion en ligne. Ils ne sont pas recalculés localement — le
///    client n'a aucune autorité sur le RBAC (RG-16, premier des trois
///    niveaux).
/// 3. **La validité est bornée dans le temps.** Sans borne, un compte révoqué
///    garderait l'accès indéfiniment sur un poste laissé hors ligne.
///
/// ## ⚠ La fenêtre de validité n'est PAS tranchée
///
/// [fenetreValiditeParDefaut] vaut **7 jours**, et c'est une valeur **posée
/// par défaut, pas arbitrée**. Elle met en balance deux risques réels et
/// opposés :
///
///  - **trop courte** — le comptoir refuse d'ouvrir après une coupure longue,
///    ce qui est exactement la panne que ce fichier existe pour éviter ;
///  - **trop longue** — un employé dont le compte a été révoqué continue
///    d'encaisser sur un poste qu'on garde hors ligne, précisément parce qu'on
///    le garde hors ligne.
///
/// Le second n'est pas théorique : c'est le mode opératoire d'un détournement.
/// **Le Product Owner et l'Architecte doivent trancher cette durée**, et elle
/// est isolée à cette seule constante pour que l'arbitrage coûte une ligne.
final class VerificateurHorsLigne {
  const VerificateurHorsLigne({
    required this.login,
    required this.sel,
    required this.empreinte,
    required this.iterations,
    required this.derniereConnexionEnLigne,
  });

  /// L'identifiant, tel qu'il a été saisi à la dernière connexion en ligne.
  final String login;

  final String sel;
  final String empreinte;
  final int iterations;

  /// Horodatage de la dernière connexion **en ligne** — l'origine de la
  /// fenêtre de validité.
  final DateTime derniereConnexionEnLigne;

  /// Le nombre de tours PBKDF2.
  ///
  /// 120 000 : assez pour qu'une attaque par dictionnaire sur un disque volé
  /// coûte cher, assez peu pour que l'ouverture du comptoir reste immédiate
  /// sur la machine du Gîte. C'est le seul endroit à relever le jour où le
  /// matériel change.
  static const int iterationsParDefaut = 120000;

  /// ⚠ **Valeur par défaut, non arbitrée** — voir la documentation de classe.
  static const Duration fenetreValiditeParDefaut = Duration(days: 7);

  /// Le vérificateur est-il encore valable à [maintenant] ?
  bool estValide(DateTime maintenant, {Duration? fenetre}) {
    final limite = derniereConnexionEnLigne.add(
      fenetre ?? fenetreValiditeParDefaut,
    );
    return maintenant.isBefore(limite);
  }

  /// Le mot de passe fourni correspond-il ?
  ///
  /// Rend `false` — jamais une exception — quand il ne correspond pas : un
  /// message d'erreur qui distingue « compte inconnu » de « mot de passe
  /// faux » renseigne un attaquant sur les comptes existants.
  bool correspond(String motDePasse) {
    final calculee = deriver(
      motDePasse: motDePasse,
      sel: base64Decode(sel),
      iterations: iterations,
    );
    return _egalConstant(calculee, base64Decode(empreinte));
  }

  /// Fabrique un vérificateur après une connexion **en ligne** réussie.
  static VerificateurHorsLigne creer({
    required String login,
    required String motDePasse,
    required DateTime maintenant,
    int iterations = iterationsParDefaut,
    Random? aleatoire,
  }) {
    final sel = _selAleatoire(aleatoire);
    return VerificateurHorsLigne(
      login: login,
      sel: base64Encode(sel),
      empreinte: base64Encode(
        deriver(motDePasse: motDePasse, sel: sel, iterations: iterations),
      ),
      iterations: iterations,
      derniereConnexionEnLigne: maintenant,
    );
  }

  Map<String, dynamic> versJson() => {
    'login': login,
    'sel': sel,
    'empreinte': empreinte,
    'iterations': iterations,
    'derniere_connexion_en_ligne': derniereConnexionEnLigne
        .toUtc()
        .toIso8601String(),
  };

  static VerificateurHorsLigne depuisJson(Map<String, dynamic> j) =>
      VerificateurHorsLigne(
        login: j['login'] as String,
        sel: j['sel'] as String,
        empreinte: j['empreinte'] as String,
        iterations: j['iterations'] as int,
        derniereConnexionEnLigne: DateTime.parse(
          j['derniere_connexion_en_ligne'] as String,
        ).toLocal(),
      );

  /// Sel de 32 octets, tiré du générateur **sûr** du système.
  ///
  /// `Random()` ordinaire est prédictible et suffirait à recalculer les sels
  /// d'un poste entier. `Random.secure()` est le seul acceptable ici ;
  /// [aleatoire] n'existe que pour rendre les tests reproductibles.
  static Uint8List _selAleatoire(Random? aleatoire) {
    final r = aleatoire ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256, RFC 2898 §5.2, longueur de sortie 32 octets.
  ///
  /// Écrit ici faute de KDF dans `crypto`, et **éprouvé contre un vecteur de
  /// référence connu** (`verificateur_hors_ligne_test.dart`) : une dérivation
  /// écrite de mémoire qui se tromperait d'un octet produirait un vérificateur
  /// parfaitement cohérent avec lui-même — donc indétectable sans vecteur
  /// externe, et sans la résistance qu'on lui prête.
  /// **Exposee** pour etre eprouvee contre des vecteurs publics.
  ///
  /// C'est le seul moyen de savoir que cette derivation est la bonne : une
  /// PBKDF2 fausse produit un verificateur coherent avec lui-meme, donc
  /// indetectable de l'interieur.
  static Uint8List deriver({
    required String motDePasse,
    required Uint8List sel,
    required int iterations,
  }) {
    const longueur = 32; // une seule passe : SHA-256 rend déjà 32 octets
    final hmac = Hmac(sha256, utf8.encode(motDePasse));

    // U1 = PRF(P, S || INT(1))
    final bloc = Uint8List(sel.length + 4)
      ..setRange(0, sel.length, sel)
      ..[sel.length + 3] = 1;

    var u = Uint8List.fromList(hmac.convert(bloc).bytes);
    final resultat = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < longueur; k++) {
        resultat[k] ^= u[k];
      }
    }
    return resultat;
  }

  /// Comparaison à temps constant.
  static bool _egalConstant(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
