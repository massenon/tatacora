/// La TVA d'un montant du catalogue — RÉPLIQUE de `CalculTvaService` du serveur,
/// en FONCTIONS PURES (aucune base, aucun écran).
///
/// ## Qui lit les trois paramètres fiscaux sur ce poste (pièges 1 et 9)
///
/// `tva_active`, `taux_tva` et `convention_prix` ont UN lecteur : ce fichier. Il
/// est déclaré au registre des paramètres (`lecteur:`), et un test exige que le
/// fichier déclaré contienne la clé. Avant le lot 6 (12/10/2026) ces trois
/// réglages n'agissaient sur RIEN ; ils agissent désormais sur la PIÈCE
/// COMPTABLE d'une vente (`pos/domain/piece_de_la_vente.dart`), et sur rien
/// d'autre : aucune facture n'est ventilée HT/TVA sur ce poste.
///
/// ## Le calcul est celui de `bcmath`, centime pour centime
///
/// Le serveur calcule `TTC × taux / (100 + taux)` en `bcmath` : le produit est
/// arrondi (par troncature) à SIX décimales, le quotient aussi, puis on ajoute
/// `0,005` et on tronque à deux décimales — un arrondi « demi vers le haut »
/// appliqué UNE fois, en fin de calcul. Ici les montants sont des CENTIMES
/// entiers et le calcul se fait en `BigInt`, avec les mêmes troncatures aux mêmes
/// endroits : un flottant donnerait parfois un centime d'écart sur une pièce
/// immuable. `tva_contre_serveur` (confrontation) l'éprouve sur des montants
/// choisis pour tomber sur les arrondis.
///
/// ## Un taux absent ou une convention illisible REFUSENT
///
/// Jamais un repli : calculer à 0 % pendant qu'un Administrateur croit la TVA
/// active serait une sous-taxation silencieuse sur une pièce immuable (PA-62).
/// Les phrases sont celles du serveur (`lang/fr/comptabilite.php`).
///
/// @see PA-62 deux commutateurs indépendants : l'intention et la capacité
/// @see EF-M10-02 Saisie des écritures comptables
library;

/// Les deux conventions admises — `CalculTvaService::CONVENTION_*`.
abstract final class ConventionsPrix {
  static const String ht = 'ht';
  static const String ttc = 'ttc';
}

/// La ventilation d'un montant du catalogue, en centimes.
final class VentilationTva {
  const VentilationTva({
    required this.htCentimes,
    required this.tvaCentimes,
    required this.ttcCentimes,
  });

  final int htCentimes;
  final int tvaCentimes;
  final int ttcCentimes;
}

/// Les trois paramètres fiscaux, tels que le poste les STOCKE (chaînes), et les
/// gestes que le serveur en tire.
final class ParametresTva {
  const ParametresTva({this.active, this.taux, this.convention});

  /// Lit les trois clés d'une table de paramètres déjà chargée
  /// (`ParametresDao.lireTout`). Une clé absente reste `null` : le serveur
  /// applique alors son propre défaut, reproduit plus bas.
  factory ParametresTva.depuis(Map<String, String> valeurs) => ParametresTva(
    active: valeurs['tva_active'],
    taux: valeurs['taux_tva'],
    convention: valeurs['convention_prix'],
  );

  final String? active;
  final String? taux;
  final String? convention;

  /// `CalculTvaService::estActive` — `filter_var(.., FILTER_VALIDATE_BOOLEAN)`
  /// sur la valeur stockée, `'false'` à défaut. L'INTENTION, jamais la
  /// capacité : elle peut être vraie quand le taux est absent.
  bool get estActive => lireBooleenPhp(active ?? 'false');

  /// La convention lue comme le serveur : `strtolower(trim(..))`, `'ht'` à
  /// défaut, refus si ni `ht` ni `ttc`.
  String conventionOuRefus() {
    final lue = (convention ?? ConventionsPrix.ht).trim().toLowerCase();
    if (lue != ConventionsPrix.ht && lue != ConventionsPrix.ttc) {
      throw RefusTva(PhrasesTva.conventionInconnue(lue, 'convention_prix'));
    }
    return lue;
  }

  /// `CalculTvaService::taux` — refus si le paramètre est vide (`blank()`).
  _Decimal _tauxOuRefus() {
    final brut = taux;
    if (brut == null || brut.trim().isEmpty) {
      throw RefusTva(PhrasesTva.tauxAbsent('taux_tva'));
    }
    final lu = _Decimal.lire(brut);
    if (lu == null) {
      // Le serveur lève ici une `ValueError` de `bcmath` (HTTP 500), sans
      // phrase. Le poste refuse au MÊME endroit, mais dit quelque chose. En
      // pratique inatteignable : l'écran Paramètres normalise le taux.
      throw RefusTva(PhrasesTva.tauxIllisible(brut));
    }
    return lu;
  }

  /// `CalculTvaService::ventiler` — l'UNIQUE point d'entrée. Inactive : le
  /// montant est ce qu'il est, sans taxe. Active : la convention est jugée
  /// AVANT le taux (le serveur appelle `convention()` puis `taux()`).
  VentilationTva ventiler(int montantCentimes) {
    if (!estActive) {
      return VentilationTva(
        htCentimes: montantCentimes,
        tvaCentimes: 0,
        ttcCentimes: montantCentimes,
      );
    }

    final convention = conventionOuRefus();
    if (convention == ConventionsPrix.ttc) {
      final tva = _depuisTtc(montantCentimes, _tauxOuRefus());
      return VentilationTva(
        htCentimes: montantCentimes - tva,
        tvaCentimes: tva,
        ttcCentimes: montantCentimes,
      );
    }

    final tva = _depuisHt(montantCentimes, _tauxOuRefus());
    return VentilationTva(
      htCentimes: montantCentimes,
      tvaCentimes: tva,
      ttcCentimes: montantCentimes + tva,
    );
  }
}

/// Un refus du calcul de TVA : rien n'a été écrit.
final class RefusTva implements Exception {
  const RefusTva(this.message);

  final String message;

  @override
  String toString() => 'RefusTva: $message';
}

/// Les phrases du serveur (`lang/fr/comptabilite.php`), relues par PHP dans
/// `test/features/ventes/ventes_contre_serveur_test.dart`.
abstract final class PhrasesTva {
  /// `comptabilite.convention_inconnue`.
  static String conventionInconnue(String convention, String cle) =>
      'Convention de prix inconnue : « $convention ». '
      'Valeurs admises : « ht » ou « ttc » (paramètre « $cle »).';

  /// `comptabilite.taux_absent`.
  static String tauxAbsent(String cle) =>
      'Le taux de TVA n\'est pas paramétré ($cle). '
      'Aucun montant de taxe ne peut être calculé tant qu\'un Administrateur '
      'ne l\'a pas renseigné.';

  /// Écart du poste : le serveur lève une `ValueError` de `bcmath` (HTTP 500).
  static String tauxIllisible(String valeur) =>
      'Le taux de TVA paramétré (« $valeur ») n\'est pas un nombre décimal '
      'simple : aucun montant de taxe ne peut être calculé. Rien n\'est '
      'enregistré.';
}

/// `filter_var($v, FILTER_VALIDATE_BOOLEAN)` — vrai pour `1`, `true`, `on`,
/// `yes` (casse indifférente, espaces de bord ignorés) ; faux pour tout le
/// reste (le `null` de PHP pour une valeur illisible est lu comme faux par le
/// serveur).
bool lireBooleenPhp(String valeur) {
  switch (valeur.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'on':
    case 'yes':
      return true;
    default:
      return false;
  }
}

/* ====================================================================== */
/* L'arithmétique de bcmath, en entiers                                    */
/* ====================================================================== */

/// Une échelle de six décimales — `PRECISION_CALCUL` du serveur.
final BigInt _e6 = BigInt.from(1000000);

/// Un décimal non signé, valeur = [unites] / 10^[echelle].
final class _Decimal {
  const _Decimal(this.unites, this.echelle);

  final BigInt unites;
  final int echelle;

  /// `null` sur toute entrée qui n'est pas « chiffres[.chiffres] » — jamais
  /// zéro.
  static _Decimal? lire(String texte) {
    final t = texte.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
    final point = t.indexOf('.');
    final decimales = point < 0 ? 0 : t.length - point - 1;
    return _Decimal(BigInt.parse(t.replaceAll('.', '')), decimales);
  }
}

BigInt _dix(int puissance) => BigInt.from(10).pow(puissance);

/// `bcmul($montant, $taux, 6)` : le produit EXACT, tronqué à six décimales,
/// rendu comme un entier d'échelle 10^6. [montantCentimes] a deux décimales.
BigInt _produit6(int montantCentimes, _Decimal taux) {
  final produit = BigInt.from(montantCentimes) * taux.unites;
  final echelle = 2 + taux.echelle;
  return echelle <= 6
      ? produit * _dix(6 - echelle)
      : produit ~/ _dix(echelle - 6);
}

/// L'arrondi final : `bcadd($x, '0.005', 2)` — on ajoute un demi-centime et on
/// TRONQUE à deux décimales. [x6] est d'échelle 10^6 ; le résultat est en
/// centimes.
int _arrondi(BigInt x6) =>
    ((x6 + BigInt.from(5000)) ~/ BigInt.from(10000)).toInt();

/// `CalculTvaService::depuisHt` — `HT × taux / 100`.
int _depuisHt(int htCentimes, _Decimal taux) {
  final x6 = _produit6(htCentimes, taux) ~/ BigInt.from(100);
  return _arrondi(x6);
}

/// `CalculTvaService::depuisTtc` — `TTC × taux / (100 + taux)`.
int _depuisTtc(int ttcCentimes, _Decimal taux) {
  final numerateur = _produit6(ttcCentimes, taux);
  // `bcadd('100', $taux, 6)` : le dénominateur est lui aussi tronqué à six
  // décimales.
  final tauxEn6 = taux.echelle <= 6
      ? taux.unites * _dix(6 - taux.echelle)
      : taux.unites ~/ _dix(taux.echelle - 6);
  final denominateur = BigInt.from(100) * _e6 + tauxEn6;
  // `bcdiv($num, $den, 6)` : quotient tronqué à six décimales.
  final x6 = (numerateur * _e6) ~/ denominateur;
  return _arrondi(x6);
}
