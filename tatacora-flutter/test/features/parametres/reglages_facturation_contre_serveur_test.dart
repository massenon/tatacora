@Timeout(Duration(minutes: 5))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/domain/mode_facturation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Les réglages de la facturation normalisée, la forme juridique et les documents
/// commerciaux ÉCRITS SUR LE POSTE (09/11/2026, décision du PO : « le poste fait ce que le
/// web fait »), CONTRE le vrai moteur de synchronisation du serveur.
///
/// `tool/parametres/rejouer_reglages_facturation.php` pousse chaque cas comme un poste le
/// ferait (`SynchronisationService::traiterLot`, compte du jeton administrateur ou non) ;
/// le même cas passe par `EnregistrerParametres` sur une base neuve. Ce qui se compare :
/// l'acceptation ou le refus, la PHRASE du refus, et ce qui est rangé — jamais une règle
/// recopiée. Le serveur a RÉELLEMENT accepté et RÉELLEMENT refusé : les compteurs le disent.
///
/// La base d'essai privée se donne par `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
class _Cas {
  const _Cas(
    this.nom,
    this.valeurs, {
    this.attendu = 'ok',
    this.auteur = 'admin',
    this.prealable = const {},
    this.affectation = false,
  });

  final String nom;
  final Map<String, String?> valeurs;

  /// `ok` ou `refus` : ce que le SERVEUR doit rendre (ancre contre un test vert à vide).
  final String attendu;
  final String auteur;
  final Map<String, String> prealable;
  final bool affectation;
}

const _ifu = '0202011344660';
const _complet = {
  'entreprise_ifu': _ifu,
  'mecef_operateur_id': 'RECEPTION01',
  'mecef_operateur_nom': 'Réception',
};
const _completEnBoitier = {..._complet, 'facturation_mode': 'boitier'};

final _cas = <_Cas>[
  // ---- Acceptés
  const _Cas('admin : mode boîtier, lot complet', {
    ..._complet,
    'mecef_api_url': 'https://sygmef.exemple.bj/api',
    'facturation_mode': 'boitier',
  }),
  const _Cas('admin : mode en majuscules', {
    'facturation_mode': 'BOITIER',
  }, prealable: _complet),
  const _Cas('admin : mode désactivé, rien d’exigé', {
    'facturation_mode': 'desactive',
  }),
  const _Cas('admin : revenir à désactivé', {
    'facturation_mode': 'desactive',
  }, prealable: _completEnBoitier),
  const _Cas('admin : mode vidé', {
    'facturation_mode': null,
  }, prealable: _completEnBoitier),
  const _Cas(
    'admin : adresse de l’API vidée (adresse par défaut)',
    {'mecef_api_url': null},
    prealable: {'mecef_api_url': 'https://a.exemple.bj'},
  ),
  const _Cas('admin : nom de l’opérateur de 30 caractères', {
    'mecef_operateur_nom': 'abcdefghijabcdefghijabcdefghij',
  }),
  const _Cas('admin : forme juridique SARL', {'forme_juridique': 'sarl'}),
  const _Cas(
    'admin : forme juridique inchangée',
    {'forme_juridique': 'sarl'},
    prealable: {'forme_juridique': 'sarl'},
  ),
  const _Cas('comptable (PARAM, non administrateur) : les documents', {
    'entreprise_activites': 'Tourisme, Hébergement',
    'proforma_validite_jours': '45',
    'facture_signature_affichee': 'true',
    'facture_reference': 'GCN',
  }, auteur: 'comptable'),
  const _Cas('comptable : un paramètre ordinaire', {
    'tolerance_reception_pct': '6',
  }, auteur: 'comptable'),

  // ---- Refusés : le droit
  const _Cas(
    'comptable : le mode',
    {'facturation_mode': 'boitier'},
    auteur: 'comptable',
    prealable: _complet,
    attendu: 'refus',
  ),
  const _Cas(
    'comptable : l’adresse de l’API',
    {'mecef_api_url': 'https://a.exemple.bj'},
    auteur: 'comptable',
    attendu: 'refus',
  ),
  const _Cas(
    'comptable : l’identifiant de l’opérateur',
    {'mecef_operateur_id': 'R1'},
    auteur: 'comptable',
    attendu: 'refus',
  ),
  const _Cas(
    'comptable : le nom de l’opérateur',
    {'mecef_operateur_nom': 'Réception'},
    auteur: 'comptable',
    attendu: 'refus',
  ),
  const _Cas(
    'comptable : la forme juridique',
    {'forme_juridique': 'sarl'},
    auteur: 'comptable',
    attendu: 'refus',
  ),
  const _Cas(
    'comptable : un lot mêlant le mode et un réglage ordinaire',
    {'facturation_mode': 'boitier', 'tolerance_reception_pct': '6'},
    auteur: 'comptable',
    prealable: _complet,
    attendu: 'refus',
  ),

  // ---- Refusés : la forme
  const _Cas('mode inconnu', {
    'facturation_mode': 'quantique',
  }, attendu: 'refus'),
  const _Cas('adresse de l’API sans https', {
    'mecef_api_url': 'http://sygmef.exemple.bj',
  }, attendu: 'refus'),
  const _Cas('adresse de l’API avec une espace', {
    'mecef_api_url': 'https://a b.bj',
  }, attendu: 'refus'),
  const _Cas('nom de l’opérateur de 31 caractères', {
    'mecef_operateur_nom': 'abcdefghijabcdefghijabcdefghijk',
  }, attendu: 'refus'),
  const _Cas('identifiant de l’opérateur de 31 caractères', {
    'mecef_operateur_id': 'abcdefghijabcdefghijabcdefghijk',
  }, attendu: 'refus'),
  const _Cas('forme juridique inconnue', {
    'forme_juridique': 'gie',
  }, attendu: 'refus'),
  const _Cas('forme juridique vidée', {
    'forme_juridique': null,
  }, attendu: 'refus'),
  const _Cas('référence facture non alphanumérique', {
    'facture_reference': 'G-N',
  }, attendu: 'refus'),
  const _Cas('validité de la proforma : 400 jours', {
    'proforma_validite_jours': '400',
  }, attendu: 'refus'),
  const _Cas('validité de la proforma : 0 jour', {
    'proforma_validite_jours': '0',
  }, attendu: 'refus'),
  const _Cas('validité de la proforma : du texte', {
    'proforma_validite_jours': 'abc',
  }, attendu: 'refus'),
  const _Cas('interrupteur de signature vidé', {
    'facture_signature_affichee': null,
  }, attendu: 'refus'),
  _Cas('activités de 256 caractères', {
    'entreprise_activites': 'a' * 256,
  }, attendu: 'refus'),
  const _Cas('IFU de 12 chiffres', {
    'entreprise_ifu': '320261234567',
  }, attendu: 'refus'),

  // ---- Refusés : la cohérence du mode
  const _Cas('mode boîtier sans IFU ni opérateur', {
    'facturation_mode': 'boitier',
  }, attendu: 'refus'),
  const _Cas(
    'mode boîtier sans le nom de l’opérateur',
    {'facturation_mode': 'boitier'},
    prealable: {'entreprise_ifu': _ifu, 'mecef_operateur_id': 'R1'},
    attendu: 'refus',
  ),
  const _Cas(
    'mode boîtier sans IFU',
    {'facturation_mode': 'boitier'},
    prealable: {'mecef_operateur_id': 'R1', 'mecef_operateur_nom': 'Réception'},
    attendu: 'refus',
  ),
  const _Cas(
    'opérateur vidé sous un mode réel',
    {'mecef_operateur_nom': null},
    prealable: _completEnBoitier,
    attendu: 'refus',
  ),
  const _Cas(
    'IFU vidé sous un mode réel',
    {'entreprise_ifu': null},
    prealable: _completEnBoitier,
    attendu: 'refus',
  ),

  // ---- Refusé : une affectation du résultat est active
  const _Cas(
    'forme juridique sous une affectation active',
    {'forme_juridique': 'sarl'},
    affectation: true,
    attendu: 'refus',
  ),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_reglages_facturation.php',
      dossier: 'parametres',
      entree: {
        'cas': [
          for (final c in _cas)
            {
              'nom': c.nom,
              'auteur': c.auteur,
              'prealable': c.prealable,
              'valeurs': c.valeurs,
              'affectation': c.affectation,
            },
        ],
      },
    );
  });

  /// Rejoue [c] sur le poste : une base neuve, les valeurs préalables, un auteur
  /// administrateur ou non.
  Future<(ResultatEcriture, Map<String, String?>)> surLePoste(_Cas c) async {
    final db = AppDatabase.enMemoire();
    try {
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: c.auteur == 'admin' ? 'administrateur' : 'comptable',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 11, 9),
              dateMotDePasse: DateTime(2026, 11, 9),
            ),
          );
      for (final e in c.prealable.entries) {
        await db
            .into(db.parametresSystemeLocal)
            .insert(
              ParametresSystemeLocalCompanion.insert(
                cle: e.key,
                valeur: e.value,
                modifieLe: DateTime(2026, 11, 9),
              ),
            );
      }
      final depot = ParametresDepotLocal(db);
      final r =
          await EnregistrerParametres(
            depot,
            affectationActive: () async => c.affectation,
          ).executer(
            c.valeurs,
            peutEcrire: true,
            auteurId: 'u-essai',
            estAdministrateur: c.auteur == 'admin',
          );
      final stocke = await depot.lireTout();
      return (r, {for (final cle in c.valeurs.keys) cle: stocke[cle]});
    } finally {
      await db.close();
    }
  }

  test('chaque cas : même acceptation, même PHRASE, même valeur rangée que '
      'le serveur', () async {
    final resultats = serveur['resultats'] as Map<String, dynamic>;
    var acceptes = 0;
    var refuses = 0;
    for (final c in _cas) {
      final attendu = resultats[c.nom] as Map<String, dynamic>;
      final (poste, stocke) = await surLePoste(c);

      // Le serveur a fait ce que le cas annonce (ancre contre un balayage à vide).
      expect(
        attendu['statut'],
        c.attendu == 'ok' ? 'synchronise' : 'rejete',
        reason: '${c.nom} : le serveur a dit ${attendu['motif']}',
      );

      switch (poste) {
        case EcritureAcceptee():
          expect(
            attendu['statut'],
            'synchronise',
            reason: '${c.nom} : le poste accepte, pas le serveur',
          );
          // Ce qui est rangé : même forme normalisée (vide au serveur = absent ici).
          final rangees = attendu['stockees'] as Map<String, dynamic>;
          for (final cle in c.valeurs.keys) {
            final s = rangees[cle] as String?;
            expect(
              stocke[cle],
              (s == null || s.isEmpty) ? null : s,
              reason: '${c.nom} : $cle',
            );
          }
          acceptes++;
        case EcritureRefusee(:final motif):
          expect(
            attendu['statut'],
            'rejete',
            reason: '${c.nom} : le poste refuse (« $motif »), pas le serveur',
          );
          expect(motif, attendu['motif'], reason: c.nom);
          // Rien n'est écrit d'un lot refusé.
          for (final cle in c.valeurs.keys) {
            expect(stocke[cle], c.prealable[cle], reason: '${c.nom} : $cle');
          }
          refuses++;
      }
    }
    // Le serveur a RÉELLEMENT accepté et RÉELLEMENT refusé : la comparaison compte.
    expect(acceptes, 11);
    expect(refuses, _cas.length - 11);
    expect(refuses, greaterThan(25));
  });

  test('le refus de droit du serveur est `droit_manquant`, lisible dans « À '
      'traiter » ; les autres refus sont des règles métier', () {
    final resultats = serveur['resultats'] as Map<String, dynamic>;
    var droits = 0;
    for (final c in _cas.where(
      (c) => c.auteur == 'comptable' && c.attendu == 'refus',
    )) {
      expect(
        (resultats[c.nom] as Map)['code_motif'],
        'droit_manquant',
        reason: c.nom,
      );
      droits++;
    }
    expect(droits, 6);
    for (final c in _cas.where(
      (c) => c.auteur == 'admin' && c.attendu == 'refus',
    )) {
      expect(
        (resultats[c.nom] as Map)['code_motif'],
        'regle_metier',
        reason: c.nom,
      );
    }
  });

  test('les phrases du poste sont celles du serveur, au mot', () {
    final p = serveur['phrases'] as Map<String, dynamic>;
    expect(MessagesReglagesAdministrateur.mecefReserve, p['mecef_reserve']);
    expect(MessagesReglagesAdministrateur.formeReservee, p['forme_reservee']);
    expect(
      MessagesReglagesAdministrateur.formeAffectationActive,
      p['forme_affectation_active'],
    );
    expect(MessagesReglagesAdministrateur.manqueIfu, p['manque_ifu']);
    expect(
      MessagesReglagesAdministrateur.manqueOperateur,
      p['manque_operateur'],
    );
    expect(
      MessagesReglagesAdministrateur.formeInconnue('VALEUR', ['ADMISES']),
      p['forme_inconnue'],
    );
    expect(
      MessagesReglagesAdministrateur.modeRefuse('MODE', 'MANQUES'),
      p['mode_refuse'],
    );
  });

  test(
    'les libellés du mode sont ceux du serveur (« Boîtier CC300 (poste) »)',
    () {
      final libelles = serveur['libelles_mode'] as Map<String, dynamic>;
      expect({
        for (final m in ModeFacturation.values) m.code: m.libelle,
      }, libelles);
    },
  );

  test('ÉCART NOMMÉ : le mode e-MECeF sans jeton — le serveur refuse, le poste '
      'ne le sait pas (le jeton ne descend JAMAIS)', () async {
    final serveurEmecef = await executerPhp(
      'rejouer_reglages_facturation.php',
      dossier: 'parametres',
      entree: {
        'cas': [
          {
            'nom': 'emecef',
            'auteur': 'admin',
            'prealable': _complet,
            'valeurs': {'facturation_mode': 'emecef'},
          },
        ],
      },
    );
    final attendu = (serveurEmecef['resultats'] as Map)['emecef'] as Map;
    final p = serveurEmecef['phrases'] as Map;
    expect(attendu['statut'], 'rejete');
    expect(attendu['motif'], contains(p['manque_jeton'] as String));

    // Le poste, lui, accepte : il ne reçoit ni ne saisit jamais le jeton, il ne peut
    // pas l'affirmer absent. Le refus du serveur reviendra dans « À traiter ».
    final (poste, _) = await surLePoste(
      const _Cas('emecef', {'facturation_mode': 'emecef'}, prealable: _complet),
    );
    expect(poste, isA<EcritureAcceptee>());
  });

  test('les cinq clés réservées sont celles du serveur', () {
    expect((serveur['cles_administrateur'] as List).cast<String>()..sort(), [
      'facturation_mode',
      'forme_juridique',
      'mecef_api_url',
      'mecef_operateur_id',
      'mecef_operateur_nom',
    ]);
  });
}
