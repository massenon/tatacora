@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/parametres/domain/entities/parametre.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/taux_paie.dart';

import 'registre_serveur.dart';

/// Le registre LOCAL confronté à sa SOURCE, le registre PHP.
///
/// Aucune liste n'est recopiée ici : tout ce qui est attendu est lu de
/// `RegistreParametres::definitions()` et de `lang/fr/parametres.php`, par
/// l'exécution de PHP. Chaque garde commence par prouver que ce qu'elle
/// balaie n'est pas vide — sans quoi elle serait verte à vide (PA-136).
/// Les trois bascules d'activation se lisent par leur constante, jamais par le
/// littéral (`OptionsSysteme`, un seul auteur de la lecture).
const Map<String, String> _constanteDeCle = {
  'activation_suppression': 'OptionsSysteme.cleSuppression',
  'reinitialisation_seeders': 'OptionsSysteme.cleReinitialisationSeeders',
  'activation_alertes_ouverture': 'OptionsSysteme.cleAlertesOuverture',
};

/// Les fichiers qui NOMMENT une clé sans la lire pour un module — exemptés de
/// la sonde des lecteurs pour CES clés seulement (R-C, D284). Tout autre clé
/// nommée dans ces fichiers est un lecteur probable, comme partout ailleurs.
const Map<String, Set<String>> _nommeesSansLecture = {
  // Les règles de Paramètres dérivent les BADGES de l'écran (TVA, MECeF) des
  // valeurs saisies : un affichage de Paramètres lui-même, aucun module n'y
  // lit la valeur.
  'lib/features/parametres/domain/regles_parametres.dart': {
    'entreprise_numero_mecef',
    'tva_active',
    'taux_tva',
    'convention_prix',
  },
  // L'écran CLASSE ces clés par onglet (`_clesLegales`, `_clesCommunication`,
  // `_cleAdresse`) : il les nomme pour les placer, il ne les lit pas. Il
  // nomme aussi deux bascules (21/10/2026) pour leur poser la pastille de
  // RISQUE de la vue (`_risqueDe`) : un habillage, aucun module n'y lit la
  // valeur — l'état d'une bascule passe par `OptionsSysteme.actif`, le lecteur
  // commun.
  'lib/features/parametres/presentation/ecran_parametres.dart': {
    'entreprise_ifu',
    'entreprise_rccm',
    'entreprise_numero_mecef',
    'communication_whatsapp',
    'entreprise_site_web',
    'entreprise_adresse',
    'activation_suppression',
    'activation_alertes_ouverture',
  },
};

/// Les fichiers de `lib/` qui nomment [cle] (littéral ou constante) sans être
/// son lecteur [declare], ni un fichier de DÉFINITION, ni exemptés pour elle.
List<String> _lecteursNonDeclares(String cle, {required String? declare}) {
  final constante = _constanteDeCle[cle];
  final trouves = <String>[];
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final chemin = f.path.replaceAll(r'\', '/');
    if (chemin.endsWith('.g.dart') ||
        chemin == declare ||
        // Les DEUX fichiers qui définissent les clés : le registre et les
        // constantes des bascules.
        chemin ==
            'lib/features/parametres/domain/registre_parametres_local.dart' ||
        chemin == 'lib/features/parametres/domain/options_systeme.dart' ||
        (_nommeesSansLecture[chemin]?.contains(cle) ?? false)) {
      continue;
    }
    final source = f.readAsStringSync();
    if (source.contains("'$cle'") ||
        (constante != null && source.contains(constante))) {
      trouves.add(chemin);
    }
  }
  return trouves;
}

void main() {
  final serveur = RegistreServeur.charger();
  final locales = RegistreParametresLocal.definitions;

  test('le balayage n’est pas vide : 31 définitions côté serveur', () {
    // 31 = 10 identité + 4 fiscalité + 5 social + 5 exploitation + 4 email
    // + 3 activation. Le compte est écrit pour que le test échoue si la
    // lecture de PHP rendait une liste vide ou tronquée.
    expect(serveur.definitions.length, 31);
    expect(locales.length, 31);
  });

  test('mêmes clés, dans le même ordre, ni plus ni moins', () {
    expect(RegistreParametresLocal.cles, [
      for (final d in serveur.definitions) d['cle'],
    ]);
  });

  test('groupe, type, libellé et choix identiques au serveur, clé par clé', () {
    for (final d in serveur.definitions) {
      final l = RegistreParametresLocal.parCle(d['cle'] as String)!;
      expect(l.groupe, d['groupe'], reason: l.cle);
      expect(l.type.code, d['type'], reason: l.cle);
      expect(l.libelle, d['libelle'], reason: l.cle);
      expect(
        l.choix,
        (d['choix'] as List<dynamic>).cast<String>(),
        reason: l.cle,
      );
    }
  });

  test('bornes et formats déduits des règles du serveur, clé par clé', () {
    var bornes = 0;
    for (final d in serveur.definitions) {
      final regles = (d['regles'] as List<dynamic>).cast<String>();
      final l = RegistreParametresLocal.parCle(d['cle'] as String)!;
      final estNombre =
          l.type == TypeParametre.decimal || l.type == TypeParametre.entier;

      String? valeurDe(String prefixe) {
        for (final r in regles) {
          if (r.startsWith(prefixe)) return r.substring(prefixe.length);
        }
        return null;
      }

      expect(l.minimum, estNombre ? valeurDe('min:') : null, reason: l.cle);
      expect(l.maximum, estNombre ? valeurDe('max:') : null, reason: l.cle);
      expect(
        l.longueurMax,
        l.type == TypeParametre.texte
            ? int.tryParse(valeurDe('max:') ?? '')
            : null,
        reason: l.cle,
      );
      expect(
        l.format,
        regles.any((r) => r.startsWith('regex:'))
            ? FormatTexte.telephone
            : regles.any((r) => r.startsWith('email'))
            ? FormatTexte.courriel
            : FormatTexte.libre,
        reason: l.cle,
      );
      if (l.minimum != null) bornes++;
    }
    // Les bornes ne sont pas vides : 12 champs numériques ont un `min:`
    // (taux de TVA, cinq taux de la paie, tolérance, annulation, préavis,
    // couverture, rétention, port SMTP).
    expect(bornes, 12);
  });

  test('l’aide est celle du serveur, MOT POUR MOT — ce que ce poste ajoute '
      'vit dans `note`, jamais fondu dans l’aide', () {
    for (final d in serveur.definitions) {
      final l = RegistreParametresLocal.parCle(d['cle'] as String)!;
      expect(l.aide, d['aide'], reason: l.cle);
    }
  });

  test('trois clés voisines d’un secret portent la phrase de refus, et elles '
      'seules', () {
    final avecNote = [
      for (final s in RegistreParametresLocal.definitions)
        if (s.note != null) s.cle,
    ];
    // Dans l'ordre du registre.
    expect(avecNote, [
      'communication_whatsapp',
      'entreprise_numero_mecef',
      'email_smtp_utilisateur',
    ]);
    expect(
      RegistreParametresLocal.parCle('entreprise_numero_mecef')!.note,
      'Sur ce poste, aucune clé d’API MECeF n’est enregistrable : un secret '
      'n’entre jamais dans cette base.',
    );
    expect(
      RegistreParametresLocal.parCle('communication_whatsapp')!.note,
      'Sur ce poste, aucune clé d’API WhatsApp n’est enregistrable : un secret '
      'n’entre jamais dans cette base.',
    );
    // Lot J2 (14/10/2026) : l'envoi SMTP à l'éditeur est porté ; le mot de
    // passe reste HORS base, et la note dit OÙ il se pose.
    expect(
      RegistreParametresLocal.parCle('email_smtp_utilisateur')!.note,
      'Sur ce poste, aucun mot de passe SMTP n’est enregistrable : un secret '
      'n’entre jamais dans cette base. Il se pose dans le fichier '
      r'%APPDATA%\TATACORA\poste.json du poste.',
    );
  });

  test('cinq clés dont l’aide du serveur affirme un fait FAUX sur ce poste '
      'portent une correction visible, et elles seules', () {
    // Lot J1 (3/4, 14/10/2026) : l'en-tête A4 des documents est LU des
    // paramètres (`entete_etablissement.dart`) — la correction « aucun
    // document n'imprime encore cette valeur » serait désormais FAUSSE sur
    // ses cinq clés, et ne doit plus être dite.
    for (final cle in const [
      'entreprise_promoteur',
      'communication_whatsapp',
      'entreprise_ifu',
      'entreprise_rccm',
      'fiscalite_regime',
    ]) {
      expect(
        RegistreParametresLocal.parCle(cle)!.correction,
        isNull,
        reason: cle,
      );
      expect(
        RegistreParametresLocal.parCle(cle)!.lecteur,
        'lib/core/impression/entete_etablissement.dart',
        reason: cle,
      );
    }
    final attendu = {
      'tva_active':
          'Sur ce poste : HT/TVA ventilés dans la pièce des ventes ; sans taux, '
          'la vente est refusée.',
      'duree_retention_audit_jours':
          'Sur ce poste, aucune purge n’a lieu : pas de journal d’audit.',
      // Lot J2 (14/10/2026) : l'hôte SMTP est lu par « Contactez l'éditeur ».
      'email_smtp_hote':
          'Sur ce poste : lu par « Contactez l’éditeur » ; vide, aucun message '
          'ne part (il reste en attente).',
      // L'aide du serveur dit « tous les modules » : seuls les fournisseurs
      // M7 honorent la bascule (la Paie garde sa règle, D272).
      'activation_suppression':
          'Sur ce poste : seuls les fournisseurs (M7), les unités '
          'd’hébergement (M1) et les articles de stock (M6) honorent cette '
          'bascule ; la Paie garde sa règle.',
      // Lue par la cloche depuis le lot B (14/10/2026) ; les fenêtres
      // d'alertes à la connexion de la vue ne sont pas portées.
      'activation_alertes_ouverture':
          'Sur ce poste : seule la cloche de la barre supérieure honore cette '
          "bascule ; les fenêtres d'alertes à la connexion ne sont pas portées.",
    };
    final reel = {
      for (final s in RegistreParametresLocal.definitions)
        if (s.correction != null) s.cle: s.correction!,
    };
    expect(reel, attendu);
    // Chaque correction répond à une aide qui existe : on ne corrige pas le
    // silence.
    for (final cle in attendu.keys) {
      expect(RegistreParametresLocal.parCle(cle)!.aide, isNotNull, reason: cle);
    }
  });

  test('aucun secret au registre : aucune clé ne porte un motif de secret', () {
    expect(serveur.motifsSecret.length, 9);
    for (final cle in RegistreParametresLocal.cles) {
      for (final motif in serveur.motifsSecret) {
        expect(cle, isNot(contains(motif)), reason: '$cle contient $motif');
      }
    }
  });

  test('aucune spécification ne porte de valeur par défaut', () {
    // La classe n’a PAS de champ « valeur » : un taux plausible ne peut pas
    // entrer par le registre. On le vérifie sur la source, pas sur une
    // convention : si quelqu’un ajoutait `valeurParDefaut`, ce test rougit.
    final source = File(
      'lib/features/parametres/domain/registre_parametres_local.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('valeurParDefaut')));
    expect(source, isNot(contains('defaut:')));
    expect(source, isNot(contains('par_defaut')));
  });

  group('« qui lit cette clé » — pas de réglage sans effet qui se croie lu', () {
    test('les cinq taux de la paie sont routés vers taux_paie_local et lus '
        'par ClesTaux', () {
      expect(RegistreParametresLocal.clesDeLaPaie, [
        ClesTaux.cnssSalarie,
        ClesTaux.cnssPensionEmployeur,
        ClesTaux.cnssPrestationsFamiliales,
        ClesTaux.vps,
        ClesTaux.cnssRisquesProfessionnels,
      ]);
      for (final cle in RegistreParametresLocal.clesDeLaPaie) {
        expect(
          RegistreParametresLocal.parCle(cle)!.lecteur,
          'lib/features/rh/domain/entities/taux_paie.dart',
        );
      }
    });

    test('chaque lecteur déclaré existe et contient la clé (relu du code)', () {
      var verifies = 0;
      for (final s in RegistreParametresLocal.definitions) {
        final lecteur = s.lecteur;
        if (lecteur == null) continue;
        final f = File(lecteur);
        expect(f.existsSync(), isTrue, reason: '${s.cle} : $lecteur');
        // Une bascule d'activation se lit par sa CONSTANTE
        // (`OptionsSysteme.cleSuppression`), jamais par le littéral : le lecteur
        // déclaré doit contenir l'un OU l'autre.
        final source = f.readAsStringSync();
        final constante = _constanteDeCle[s.cle];
        expect(
          source.contains("'${s.cle}'") ||
              (constante != null && source.contains(constante)),
          isTrue,
          reason: '${s.cle} : ni le littéral ni $constante dans $lecteur',
        );
        verifies++;
      }
      // Cinq taux de la paie, la tolérance de réception de M7 (lue par
      // `AchatsDao` depuis le 09/10/2026), les trois réglages fiscaux (lus
      // par `calcul_tva.dart` depuis le 12/10/2026, lot 6), le taux
      // d'annulation d'une réservation (lu par `annulation_reservation.dart`
      // le même jour) et la bascule de suppression (lue par
      // `providers_options_systeme.dart` depuis le lot 7, D269) ; la bascule
      // des alertes d'ouverture (lue par la cloche, lot B du 14/10/2026) ; la
      // bascule de réinitialisation (lue par `reinitialisation_locale.dart`,
      // lot E du 14/10/2026, D429) ; les DIX clés de l'en-tête A4 (identité,
      // contacts, IFU, RCCM, régime fiscal — lues par
      // `entete_etablissement.dart`, lot J1 3/4 du 14/10/2026) ; les QUATRE
      // clés SMTP (lues par `envoi_messages_editeur.dart`, lot J2 du
      // 14/10/2026) ; les DEUX réglages de RG-14, préavis et couverture (lus
      // par `conges_plannings_dao.dart` depuis le 21/10/2026). 13 + 10 + 4 +
      // 2 = 29.
      expect(verifies, 29);
    });

    test('2 clés n’ont AUCUN lecteur sur ce poste, et c’est dit', () {
      final sansLecteur = [
        for (final s in RegistreParametresLocal.definitions)
          if (s.lecteur == null) s.cle,
      ];
      // 20 → 19 le 14/10/2026 : `activation_alertes_ouverture` (cloche) ;
      // 19 → 18 le même jour : `reinitialisation_seeders` (D429) ; 18 → 8 :
      // les dix clés de l'en-tête A4 (lot J1 3/4) ; 8 → 4 : les quatre clés
      // SMTP (lot J2) ; 4 → 2 le 21/10/2026 : le préavis et la couverture des
      // congés (RG-14, `conges_plannings_dao.dart`). Les deux restantes,
      // NOMMÉES :
      expect(sansLecteur, [
        'entreprise_numero_mecef',
        'duree_retention_audit_jours',
      ]);
      expect(sansLecteur, isNot(contains('reinitialisation_seeders')));
      expect(sansLecteur, isNot(contains('tolerance_reception_pct')));
      // Et les cinq clés dont le lecteur est apparu : le registre l'a déclaré —
      // ce que ce balayage exige.
      for (final cle in const [
        'tva_active',
        'taux_tva',
        'convention_prix',
        'hebergement_taux_annulation_moins_24h',
        'activation_suppression',
      ]) {
        expect(sansLecteur, isNot(contains(cle)), reason: cle);
      }
      // Aucun code de ce poste ne les consomme : le relever, c’est empêcher
      // qu’un lecteur apparaisse sans que le registre le sache.
      //
      // La sonde balaie TOUT `lib/`, `features/parametres/` COMPRIS (elle
      // l'excluait en bloc : un lecteur logé dans Paramètres — c'était
      // précisément le cas de `activation_suppression` — lui était invisible).
      // Ne sont écartés EN ENTIER que les DEUX fichiers qui DÉFINISSENT les
      // clés : le registre et `options_systeme.dart` (les constantes). Les
      // fichiers qui NOMMENT une clé sans la lire pour un module ne sont
      // écartés que POUR CES CLÉS-LÀ (`_nommeesSansLecture`, R-C, D284) :
      // jusqu'au 12/10/2026 l'écran et les règles de Paramètres étaient exclus
      // en entier, et un lecteur non déclaré de N'IMPORTE QUELLE autre clé y
      // aurait été invisible. Elle cherche le littéral ET la constante.
      for (final cle in sansLecteur) {
        expect(_lecteursNonDeclares(cle, declare: null), isEmpty, reason: cle);
      }
    });

    test('une clé QUI A un lecteur n’en a pas un SECOND, non déclaré '
        '(R-C, D284)', () {
      // `providers_achats.dart` relisait `activation_suppression` à côté de
      // son lecteur déclaré : la bascule avait deux lecteurs, le registre en
      // nommait un. Le second passe désormais par le lecteur déclaré.
      var balayees = 0;
      for (final s in RegistreParametresLocal.definitions) {
        final lecteur = s.lecteur;
        if (lecteur == null) continue;
        expect(
          _lecteursNonDeclares(s.cle, declare: lecteur),
          isEmpty,
          reason: s.cle,
        );
        balayees++;
      }
      expect(balayees, 29, reason: 'balayage non vide');
    });

    test('chaque exemption NOMME réellement sa clé : une exemption périmée '
        'se retire', () {
      var exemptions = 0;
      for (final MapEntry(key: fichier, value: cles)
          in _nommeesSansLecture.entries) {
        final source = File(fichier).readAsStringSync();
        for (final cle in cles) {
          expect(
            source.contains("'$cle'"),
            isTrue,
            reason: '$fichier ne nomme plus $cle',
          );
          exemptions++;
        }
      }
      expect(exemptions, 12);
    });
  });

  group('les phrases du serveur, relues de lang/fr/parametres.php', () {
    final langue = serveur.langue;
    final etats = langue['etats'] as Map<String, dynamic>;
    final tva = etats['tva'] as Map<String, dynamic>;
    final mecef = etats['mecef'] as Map<String, dynamic>;

    test('les libellés d’état communs au serveur sont identiques, mot pour '
        'mot', () {
      expect(libellesEtat[CodesEtat.tvaInactive], tva['inactive']);
      expect(
        libellesEtat[CodesEtat.tvaConventionInvalide],
        tva['activee_convention_invalide'],
      );
      expect(
        libellesEtat[CodesEtat.mecefNonConfiguree],
        mecef['non_configuree'],
      );
      expect(
        libellesEtat[CodesEtat.mecefEnAttente],
        mecef['en_attente_implementation'],
      );
    });

    test('« activée SANS TAUX » est un ÉCART NOMMÉ : le serveur refuse '
        'l’émission de facture, ce poste refuse la clôture de la vente', () {
      final serveurDit = tva['activee_sans_taux'] as String;
      final posteDit = libellesEtat[CodesEtat.tvaSansTaux]!;
      // Le début est commun (TVA activée sans taux) ; la CONSÉQUENCE diffère.
      expect(serveurDit, contains('l’émission de facture est refusée'));
      expect(posteDit, isNot(contains('facture')));
      expect(posteDit, contains('la clôture d’une vente est refusée'));
      expect(
        posteDit.split('—').first,
        serveurDit.split('—').first,
        reason: 'même état, même début de phrase',
      );
    });

    test('la phrase propre à ce poste est nommée : le serveur n’a pas '
        'd’état « paramétrée mais non appliquée »', () {
      expect(tva.keys, [
        'inactive',
        'activee_sans_taux',
        'activee_convention_invalide',
        'active',
      ]);
      expect(
        tva.values,
        isNot(contains(libellesEtat[CodesEtat.tvaParametreeNonAppliquee])),
      );
      // Et le « TVA active. » du serveur n’est PAS repris : aucun module de ce
      // poste n’applique la TVA.
      expect(libellesEtat.values, isNot(contains(tva['active'])));
      expect(libellesEtat.values, isNot(contains(mecef['active'])));
    });

    test('les refus de forme reprennent la phrase du serveur', () {
      expect(
        refusConventionInvalide('xyz'),
        (langue['convention_invalide'] as String).replaceAll(
          ':convention',
          'xyz',
        ),
      );
      expect(
        (langue['tva_sans_taux'] as String),
        startsWith('La TVA ne peut pas être active sans taux.'),
      );
      expect(
        refusTvaSansTaux,
        startsWith('La TVA ne peut pas être active sans taux.'),
      );
    });
  });
}
