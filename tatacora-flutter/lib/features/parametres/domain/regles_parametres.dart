/// Les RÈGLES des paramètres — des fonctions PURES, sans base ni écran.
///
/// Elles reprennent, sur ce poste, les trois choses que le serveur tient dans
/// `EnregistrerParametreService` : la forme d'une valeur (`normaliser`), la
/// cohérence de l'état RÉSULTANT (`verifierCoherence`) et les états DÉRIVÉS
/// qui nourrissent les badges (`etatTva`, `etatMecef`).
///
/// @see RG-10 paramétrage sans déploiement
/// @see PA-61 un badge se dérive, il ne se lit jamais d'un champ brut
/// @see PA-62 / PA-124 la cohérence se juge sur l'état résultant, dans les
///      DEUX sens
library;

import '../../comptabilite/domain/messages_comptables.dart';
import '../../comptabilite/domain/regle_numero_compte.dart';
import 'entities/parametre.dart';
import 'registre_parametres_local.dart';

/// Les clés que les règles de cohérence nomment — les mêmes que le serveur.
abstract final class ClesFiscales {
  static const String tvaActive = 'tva_active';
  static const String tauxTva = 'taux_tva';
  static const String convention = 'convention_prix';
  static const String conventionHt = 'ht';
  static const String conventionTtc = 'ttc';
  static const String numeroMecef = 'entreprise_numero_mecef';
}

/* ====================================================================== */
/* Normalisation d'une valeur soumise                                      */
/* ====================================================================== */

/// Ce que la normalisation d'UNE valeur peut rendre.
sealed class Normalisation {
  const Normalisation();
}

/// La valeur est admise. [valeur] `null` = « vider » : la clé redevient
/// « non renseignée », ce qui n'est pas une chaîne vide.
final class ValeurNormalisee extends Normalisation {
  const ValeurNormalisee(this.valeur);
  final String? valeur;
}

final class ValeurRefusee extends Normalisation {
  const ValeurRefusee(this.motif);
  final String motif;
}

/// Un décimal lu comme un rationnel entier : « 3,6 » devient 36 sur une échelle
/// de 10. Aucun flottant ne touche une borne (règle du dépôt) : `4.0000001`
/// serait sinon accepté ou refusé selon la façon dont IEEE 754 l'arrondit.
final class _Decimal implements Comparable<_Decimal> {
  const _Decimal(this._unites, this._echelle);

  final BigInt _unites;
  final int _echelle;

  /// `null` sur toute entrée illisible — jamais zéro.
  static _Decimal? lire(String texte) {
    final t = texte.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
    final point = t.indexOf('.');
    final decimales = point < 0 ? 0 : t.length - point - 1;
    return _Decimal(BigInt.parse(t.replaceAll('.', '')), decimales);
  }

  @override
  int compareTo(_Decimal autre) {
    final echelle = _echelle > autre._echelle ? _echelle : autre._echelle;
    final a = _unites * BigInt.from(10).pow(echelle - _echelle);
    final b = autre._unites * BigInt.from(10).pow(echelle - autre._echelle);
    return a.compareTo(b);
  }
}

final RegExp _motifTelephone = RegExp(r'^\+?[0-9 ().\-]{6,}$');
final RegExp _motifCourriel = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Normalise [brut] selon [spec] — la forme STOCKÉE, une seule par type.
///
/// Les entrées admises sont celles de l'écran : un booléen (`bool`), un texte
/// (`String`) ou `null`/chaîne vide pour « vider ». Les messages sont écrits
/// pour l'exploitant, en français, avec le libellé du champ.
Normalisation normaliser(SpecParametre spec, Object? brut) {
  if (spec.type == TypeParametre.booleen) {
    return switch (brut) {
      true || 'true' || '1' => const ValeurNormalisee('true'),
      false || 'false' || '0' => const ValeurNormalisee('false'),
      _ => ValeurRefusee(
        '« ${spec.libelle} » est un interrupteur : choisissez Oui ou Non, '
        'il ne se vide pas.',
      ),
    };
  }

  final texte = brut == null ? '' : '$brut'.trim();

  if (texte.isEmpty) {
    final raison = spec.videRefuse;
    return raison == null
        ? const ValeurNormalisee(null)
        : ValeurRefusee(raison);
  }

  switch (spec.type) {
    case TypeParametre.choix:
      final choix = texte.toLowerCase();
      if (!spec.choix.contains(choix)) {
        return ValeurRefusee(
          '« ${spec.libelle} » : la valeur « $texte » n’est pas admise.',
        );
      }
      return ValeurNormalisee(choix);

    case TypeParametre.entier:
      if (!RegExp(r'^\d+$').hasMatch(texte)) {
        return ValeurRefusee(
          '« ${spec.libelle} » doit être un nombre entier, sans signe ni '
          'décimale.',
        );
      }
      return _borner(spec, texte, texte);

    case TypeParametre.decimal:
      final lu = _Decimal.lire(texte);
      if (lu == null) {
        return ValeurRefusee(
          '« ${spec.libelle} » doit être un nombre décimal positif '
          '(exemple : 18 ou 3,6).',
        );
      }
      return _borner(spec, texte, texte.replaceAll(',', '.'));

    case TypeParametre.texte:
      final max = spec.longueurMax;
      if (max != null && texte.length > max) {
        return ValeurRefusee(
          '« ${spec.libelle} » ne peut pas dépasser $max caractères.',
        );
      }
      if (spec.format == FormatTexte.telephone &&
          !_motifTelephone.hasMatch(texte)) {
        return ValeurRefusee(
          '« ${spec.libelle} » n’est pas un numéro valide : chiffres, '
          'espaces et indicatif uniquement.',
        );
      }
      if (spec.format == FormatTexte.courriel &&
          !_motifCourriel.hasMatch(texte)) {
        return ValeurRefusee(
          '« ${spec.libelle} » n’est pas une adresse électronique valide.',
        );
      }
      // Le numéro d'un compte de la correspondance : LA règle du plan
      // (`RegleNumeroCompte`, `PlanComptableService::NUMERO_COMPTE_FORMAT`), et
      // la phrase du serveur, mot pour mot.
      if (spec.format == FormatTexte.numeroCompte &&
          !RegleNumeroCompte.format.hasMatch(texte)) {
        return ValeurRefusee(
          MessagesComptables.dire('comptabilite.compte_numero_invalide', {
            'numero': texte,
          }),
        );
      }
      return ValeurNormalisee(texte);

    case TypeParametre.booleen:
      // Traité plus haut ; la branche existe pour que le `switch` reste
      // exhaustif — un type ajouté demain ne doit pas obtenir un comportement
      // par omission.
      return const ValeurRefusee('Type booléen non traité.');
  }
}

Normalisation _borner(SpecParametre spec, String saisi, String stocke) {
  final lu = _Decimal.lire(saisi)!;
  final min = spec.minimum == null ? null : _Decimal.lire(spec.minimum!);
  final max = spec.maximum == null ? null : _Decimal.lire(spec.maximum!);

  if ((min != null && lu.compareTo(min) < 0) ||
      (max != null && lu.compareTo(max) > 0)) {
    final bornes = switch ((spec.minimum, spec.maximum)) {
      (final a?, final b?) => 'compris entre $a et $b',
      (final a?, null) => 'au moins $a',
      (null, final b?) => 'au plus $b',
      _ => '',
    };
    return ValeurRefusee('« ${spec.libelle} » doit être $bornes.');
  }
  return ValeurNormalisee(stocke);
}

/* ====================================================================== */
/* Cohérence de l'état RÉSULTANT                                           */
/* ====================================================================== */

/// L'état qui existera APRÈS l'écriture : le stocké, recouvert par le soumis
/// (`null` = vidé = absent).
///
/// Juger la cohérence sur le stocké seul refuserait d'activer la TVA et de
/// poser son taux du même geste ; la juger sur le soumis seul laisserait vider
/// le taux d'une TVA active. C'est PA-62, et PA-124 pour le second sens.
Map<String, String> etatResultant(
  Map<String, String> stocke,
  Map<String, String?> soumis,
) {
  final resultat = Map<String, String>.of(stocke);
  for (final e in soumis.entries) {
    final v = e.value;
    if (v == null) {
      resultat.remove(e.key);
    } else {
      resultat[e.key] = v;
    }
  }
  return resultat;
}

String _libelle(String cle) => RegistreParametresLocal.parCle(cle)!.libelle;

/// La phrase de refus d'une TVA active sans taux — les DEUX sens.
///
/// Écrite pour ce poste : le serveur justifie son refus par « l'émission de la
/// facture serait refusée au comptoir », ce que ce poste ne fait pas (il ne
/// calcule aucune TVA). Dire une conséquence qui n'existe pas ici serait
/// affirmer un état qu'on n'a pas vérifié.
String get refusTvaSansTaux =>
    'La TVA ne peut pas être active sans taux. Renseignez « '
    '${_libelle(ClesFiscales.tauxTva)} » avant d’activer « '
    '${_libelle(ClesFiscales.tvaActive)} », et désactivez-la avant de vider '
    'son taux : une TVA activée sans taux est un état incohérent que ce poste '
    'refuse d’enregistrer.';

String refusConventionInvalide(String convention) =>
    'Convention de prix « $convention » inconnue. Les seules valeurs admises '
    'sont « ht » (la TVA s’ajoute aux tarifs) et « ttc » (elle en est '
    'extraite).';

bool _active(Map<String, String> v) => v[ClesFiscales.tvaActive] == 'true';

bool _vide(String? v) => v == null || v.trim().isEmpty;

/// Le motif de refus de l'état [resultant], ou `null` s'il est cohérent.
String? verifierCoherence(Map<String, String> resultant) {
  if (!_active(resultant)) return null;

  if (_vide(resultant[ClesFiscales.tauxTva])) return refusTvaSansTaux;

  final convention = resultant[ClesFiscales.convention];
  if (!_vide(convention) &&
      convention != ClesFiscales.conventionHt &&
      convention != ClesFiscales.conventionTtc) {
    return refusConventionInvalide(convention!);
  }
  return null;
}

/* ====================================================================== */
/* États DÉRIVÉS — les badges (PA-61)                                      */
/* ====================================================================== */

/// Les libellés d'état, repris de `lang/fr/parametres.php` (`etats.*`) — le
/// test les relit du fichier de langue du serveur. Deux phrases sont propres à
/// ce poste ([CodesEtat.tvaParametreeNonAppliquee], et [CodesEtat.tvaSansTaux]
/// dont la conséquence nommée par le serveur — l'émission de facture — n'existe
/// pas ici : c'est la vente qui est refusée) ; le test les nomme.
abstract final class CodesEtat {
  // TVA.
  static const String tvaInactive = 'inactive';
  static const String tvaSansTaux = 'activee_sans_taux';
  static const String tvaConventionInvalide = 'activee_convention_invalide';

  /// ⚠ Propre à ce poste (le serveur dit `active`). Aucun module de ce poste
  /// n'applique la TVA : l'afficher « TVA active. » affirmerait que les
  /// factures la portent (PA-61). Le badge dit ce qui est vrai.
  static const String tvaParametreeNonAppliquee = 'parametree_non_appliquee';

  // MECeF.
  static const String mecefNonConfiguree = 'non_configuree';
  static const String mecefEnAttente = 'en_attente_implementation';
}

const Map<String, String> libellesEtat = {
  CodesEtat.tvaInactive:
      'TVA inactive — aucune taxe n’est ajoutée aux factures.',
  // ⚠ Propre à ce poste (le serveur dit « … l’émission de facture est refusée »,
  // `lang/fr/parametres.php` etats.tva.activee_sans_taux). Ici aucune facture
  // n'est émise avec TVA : c'est la CLÔTURE DU PANIER qui lève (`RefusTva` de
  // `PanierDao.cloturer`, lot 6) quand la TVA est active sans taux. Reprendre la
  // phrase du serveur annoncerait un refus qui n'a pas lieu à cet endroit.
  CodesEtat.tvaSansTaux:
      'TVA activée SANS TAUX — la clôture d’une vente est refusée.',
  CodesEtat.tvaConventionInvalide:
      'TVA activée, mais la convention de prix est illisible.',
  CodesEtat.tvaParametreeNonAppliquee:
      'TVA activée et paramétrée : ce poste ventile HT/TVA dans la pièce '
      'comptable de chaque vente, mais ne l’applique encore à aucune facture — '
      'aucune ventilation HT/TVA n’y est calculée.',
  CodesEtat.mecefNonConfiguree:
      'MECeF non configurée — les factures mentionnent que la certification '
      'électronique est en attente d\'inscription auprès de la DGI.',
  CodesEtat.mecefEnAttente:
      'Configuration complète, mais le client MECeF réel n’est pas encore '
      'implémenté : les factures mentionnent l’attente d’inscription auprès '
      'de la DGI.',
};

EtatDerive _etat(String code) =>
    EtatDerive(code: code, libelle: libellesEtat[code]!);

/// L'état de la TVA, dérivé des valeurs RÉSULTANTES — jamais du seul champ
/// `tva_active`.
///
/// ⚠ Le serveur dit « … l'émission de facture est refusée » ; ce poste dit
/// « … la clôture d'une vente est refusée », ce qu'il fait réellement. Sur ce
/// poste l'état est inatteignable par l'écran
/// (la cohérence le refuse), mais il reste NOMMÉ : une base ouverte avec une
/// ligne incohérente ne doit pas se lire « TVA active ».
EtatDerive etatTva(Map<String, String> valeurs) {
  if (!_active(valeurs)) return _etat(CodesEtat.tvaInactive);
  if (_vide(valeurs[ClesFiscales.tauxTva])) {
    return _etat(CodesEtat.tvaSansTaux);
  }
  final convention = valeurs[ClesFiscales.convention];
  if (!_vide(convention) &&
      convention != ClesFiscales.conventionHt &&
      convention != ClesFiscales.conventionTtc) {
    return _etat(CodesEtat.tvaConventionInvalide);
  }
  return _etat(CodesEtat.tvaParametreeNonAppliquee);
}

/// L'état de MECeF. Il n'est JAMAIS « actif » sur ce poste : aucun client
/// MECeF n'est implémenté (PA-17, l'inscription DGI n'est pas faite). Renseigner
/// le numéro contribuable ne certifie rien.
EtatDerive etatMecef(Map<String, String> valeurs) =>
    _vide(valeurs[ClesFiscales.numeroMecef])
    ? _etat(CodesEtat.mecefNonConfiguree)
    : _etat(CodesEtat.mecefEnAttente);
