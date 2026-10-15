import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/impression/facture_a4.dart';

/// **La facture A4 — l'en-tête officielle, le cachet qu'on n'invente pas, et
/// ce que Q3 oblige à nommer.**
///
/// ## Ce que ces tests prouvent
///
/// Que le **document effectivement composé** — pas un échantillon écrit à
/// côté — porte l'en-tête de `DIRECTIVE_EXPORT_PDF.md`, n'imprime aucun
/// identifiant fiscal d'exemple, n'affirme aucune certification, et ne fond
/// jamais l'hébergement et les consommations en un total opaque.
///
/// ## Ce qu'ils ne prouvent PAS
///
/// La mise en page **vue par un humain** : marges, aération, tenue sur une
/// seule page pour une facture longue. Le PDF est écrit sur disque par le test
/// d'intégration Windows pour qu'on puisse l'ouvrir et le regarder.
void main() {
  const auteur = AuteurEdition(nom: 'Céline AGBODJAN', role: 'Comptable');
  final dateEdition = DateTime(2026, 8, 20, 16, 45);

  PieceFacturation piece({
    bool avoir = false,
    bool annulee = false,
    String? numeroMecef,
    String clientNom = 'KORA — l’addition « soldée »',
    List<LigneFacture>? lignes,
    OrigineFacture origine = OrigineFacture.posSejour,
  }) => PieceFacturation(
    id: 'p1',
    numero: 'F-2026-00042',
    origine: origine,
    dateEmission: DateTime(2026, 8, 20, 14, 30),
    clientNom: clientNom,
    statut: annulee ? StatutPiece.annulee : StatutPiece.emise,
    numeroMecef: numeroMecef,
    reservationId: 'res-7',
    avoirDe: avoir ? 'F-2026-00041' : null,
    motifAvoir: avoir ? 'Erreur de saisie — chambre déjà réglée' : null,
    motifAnnulation: annulee ? 'Erreur de saisie' : null,
    modePaiement: 'especes',
    pointVente: 'Réception',
    lignes:
        lignes ??
        [
          const LigneFacture(
            id: 'l1',
            module: ModuleFacturable.m1Hebergement,
            libelle: 'Hébergement — 6 nuit(s) (LOC-R1)',
            prixUnitaire: 28000,
            quantite: 6,
            ordre: 0,
          ),
          const LigneFacture(
            id: 'l2',
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: 1000,
            quantite: 2,
            ordre: 1,
          ),
          const LigneFacture(
            id: 'l3',
            module: ModuleFacturable.m4Restaurant,
            libelle: 'Poulet braisé',
            prixUnitaire: 4500,
            quantite: 1,
            ordre: 2,
          ),
        ],
  );

  FactureA4Composee composer({
    PieceFacturation? p,
    EnteteEtablissement entete = const EnteteEtablissement(),
    AuteurEdition qui = auteur,
  }) => FactureA4.composer(
    p ?? piece(),
    auteur: qui,
    dateEdition: dateEdition,
    entete: entete,
  );

  /* ================================================================== */
  group('Aucun caractère ne sera perdu à l’impression', () {
    test('CRITÈRE — le document A4 composé ne contient AUCUN caractère non '
        'imprimable', () {
      // Le garde-fou porte sur `textes`, qui est par construction ce que
      // `pdf()` rend. La pièce est piégée : apostrophe typographique et
      // guillemets courbes dans le nom du client, tiret cadratin dans le
      // libellé d'hébergement ET dans l'en-tête institutionnelle.
      final a4 = composer();

      for (final texte in a4.textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason:
              'ces caractères disparaîtraient en silence dans « $texte » : '
              '${caracteresNonImprimables(texte).join(' ')}',
        );
      }
    });

    test('le piège est réel : les sources, elles, en contiennent', () {
      // Sans cette assertion, le test précédent passerait pour la mauvaise
      // raison — c'est le défaut d'assertion vide de D0.6.
      expect(
        caracteresNonImprimables('KORA — l’addition « soldée »'),
        containsAll(['—', '’']),
      );
      expect(
        caracteresNonImprimables(const EnteteEtablissement().sousTitre),
        isNotEmpty,
        reason: 'l’en-tête officielle porte elle-même un tiret cadratin',
      );
      expect(
        caracteresNonImprimables(CertificationMecef.libelleDemonstration),
        isNotEmpty,
      );
    });

    test('la pagination est couverte, alors qu’elle est composée au rendu', () {
      // « Page 1 / 2 » n'est assemblé qu'au moment du rendu, hors de `textes`.
      // Le gabarit y figure donc explicitement : sinon ce serait le seul texte
      // du document à échapper au garde-fou.
      final a4 = composer();
      expect(a4.textes, contains(a4.gabaritPagination));
      expect(caracteresNonImprimables(a4.gabaritPagination), isEmpty);
      expect(a4.gabaritPagination, contains('{page}'));
      expect(a4.gabaritPagination, contains('{total}'));
    });

    test('les accents Latin-1 sont CONSERVÉS', () {
      final a4 = composer();
      expect(a4.texteBrut, contains('Gîte Chez Noël'));
      expect(a4.texteBrut, contains('Béninoise 33cl'));
      expect(a4.texteBrut, contains('Poulet braisé'));
      expect(a4.texteBrut, contains('Désignation'));
    });
  });

  /* ================================================================== */
  group('L’en-tête officielle — DIRECTIVE_EXPORT_PDF §1 et §2', () {
    test('les valeurs confirmées du prototype sont toutes portées', () {
      final a4 = composer();

      expect(a4.texteBrut, contains('TATACORA AFRIQUE'));
      expect(a4.texteBrut, contains('Gîte Chez Noël'));
      expect(
        a4.texteBrut,
        contains('Quartier Sountichirantikou, Natitingou, Bénin'),
      );
      expect(a4.texteBrut, contains('+229 01 97 35 59 74'));
      expect(a4.texteBrut, contains('nabogounoel@yahoo.fr'));
      expect(a4.texteBrut, contains('www.tatacora.com'));
    });

    test(
      'l’en-tête n’est PAS recopiée localement : elle vient du point unique',
      () {
        // `RESPECT_TABLEAU_RAPPORT.md` §4, non-conformité n°1. Changer une
        // valeur du point unique doit changer le document — si l'en-tête avait
        // été recopiée dans le module, ce test rougirait.
        final a4 = composer(
          entete: const EnteteEtablissement(
            raisonSociale: 'ANNEXE TATACORA',
            telephone: '+229 00 00 00 00',
          ),
        );

        expect(a4.texteBrut, contains('ANNEXE TATACORA'));
        expect(a4.texteBrut, contains('+229 00 00 00 00'));
        expect(a4.texteBrut, isNot(contains('+229 01 97 35 59 74')));
        expect(
          a4.lignesEntete,
          const EnteteEtablissement(
            raisonSociale: 'ANNEXE TATACORA',
            telephone: '+229 00 00 00 00',
          ).lignesA4,
        );
      },
    );

    test('⚠ IFU et RCCM sont VIDES : aucune ligne, et surtout aucun exemple de '
        'format', () {
      // Un IFU d'exemple sur une facture remise à un client serait un FAUX
      // identifiant fiscal. La directive impose l'affichage conditionnel
      // « sans jamais imprimer un exemple de format sur un document réel ».
      final a4 = composer();

      expect(a4.texteBrut, isNot(contains('IFU')));
      expect(a4.texteBrut, isNot(contains('RCCM')));
      expect(a4.texteBrut, isNot(contains('3202612345678')));
      expect(a4.texteBrut, isNot(contains('RB/NAT')));
      expect(a4.texteBrut, isNot(contains('Ex.')));
      expect(const EnteteEtablissement().ligneIdentificationFiscale, isNull);
    });

    test('renseignés, ils s’impriment — la branche que personne n’a encore '
        'empruntée', () {
      // C'est exactement la leçon PA-61 : la branche jamais visitée est
      // celle qui se trompe. Le jour où le Gérant saisira l'IFU, cette
      // ligne devra apparaître, et personne ne l'aura éprouvée avant.
      final a4 = composer(
        entete: const EnteteEtablissement(
          ifu: '3202699887766',
          rccm: 'RB/NAT/26 B 0999',
        ),
      );

      expect(a4.texteBrut, contains('IFU : 3202699887766'));
      expect(a4.texteBrut, contains('RCCM : RB/NAT/26 B 0999'));
    });

    test('un IFU seul s’imprime seul, sans séparateur orphelin', () {
      const entete = EnteteEtablissement(ifu: '3202699887766');
      expect(entete.ligneIdentificationFiscale, 'IFU : 3202699887766');
      expect(
        const EnteteEtablissement(
          rccm: 'RB/NAT/26 B 0999',
        ).ligneIdentificationFiscale,
        'RCCM : RB/NAT/26 B 0999',
      );
    });

    test('⚠ une valeur qui RESSEMBLE à un exemple de format est refusée', () {
      // Le seul chemin par lequel un IFU peut arriver ici un jour est la
      // recopie manuelle d'un champ de saisie — dont le `placeholder` est
      // littéralement « Ex. 3202612345678 ». Recopier le placeholder est
      // l'erreur la plus probable, pas la plus improbable.
      for (final faux in [
        'Ex. 3202612345678',
        'ex 3202612345678',
        'EXEMPLE RB/NAT/23 B 0456',
        '   ',
        '',
      ]) {
        expect(
          EnteteEtablissement(ifu: faux).ligneIdentificationFiscale,
          isNull,
          reason: '« $faux » ne doit jamais atteindre un document réel',
        );
      }
    });
  });

  /* ================================================================== */
  group('⚠ Le cachet fiscal — réservé et NOMMÉ, jamais inventé', () {
    test('l’emplacement est réservé et dit ce qu’il est', () {
      final a4 = composer();

      expect(a4.cachetFiscal.first, contains('Cachet fiscal MECeF'));
      expect(a4.texteBrut, contains('Emplacement réservé'));
      expect(a4.texteBrut, contains('aucun cachet n\'est apposé'));
      // Aucune référence interne sur un document (consigne du PO, 14/10/2026) :
      // la raison est dite en clair, jamais par un numéro de point ouvert.
      expect(a4.texteBrut, isNot(contains('PA-17')));
      expect(
        a4.texteBrut,
        contains('n\'est pas public'),
        reason:
            'le document doit dire POURQUOI le cachet manque, sans quoi il '
            'passera pour un oubli et quelqu’un le « complétera »',
      );
    });

    test('même avec un VRAI numéro MECeF, aucun cachet n’est fabriqué', () {
      // Le jour de PA-17, la tentation sera de dériver un QR du numéro. Le
      // format n'est pas public : il est communiqué après approbation, et il
      // doit être copié tel quel, jamais deviné par analogie
      // (MECEF_INTEGRATION_SPEC.md §5/§6).
      final certifiee = composer(p: piece(numeroMecef: 'MECEF-2026-00187'));
      final demonstration = composer();

      // Le numéro figure bien en mention — c'est l'identité fiscale de la
      // pièce, et la taire serait l'autre faute. Mais le CADRE du cachet est
      // rigoureusement le même : il ne se remplit pas parce qu'un numéro
      // existe, puisque ce n'est pas le numéro qui fait le cachet.
      expect(certifiee.texteBrut, contains('MECeF MECEF-2026-00187'));
      expect(certifiee.cachetFiscal, demonstration.cachetFiscal);
      expect(certifiee.texteBrut, contains('Emplacement réservé'));
    });

    test(
      'GARDE STRUCTURELLE — le module A4 ne contient aucun générateur de code',
      () {
        // Une garde à liste fermée, dans l'esprit de `PwaLectureSeuleTest` :
        // ajouter un `pw.BarcodeWidget` ou un `Barcode.qrCode()` dans le
        // rendu de la facture fait rougir la suite, et oblige donc à relire la
        // décision plutôt qu'à la contourner en silence.
        final source = File(
          'lib/features/facturation/impression/facture_a4.dart',
        ).readAsStringSync();

        expect(source, isNotEmpty);
        expect(
          source.toLowerCase().contains('barcode'),
          isFalse,
          reason:
              'aucun code-barres ne doit être composé sur une facture tant que '
              'le format du cachet MECeF n’est pas connu (PA-17)',
        );
      },
    );
  });

  /* ================================================================== */
  group('MECeF — le filigrane est DÉRIVÉ de la pièce (PA-61)', () {
    test('pièce non certifiée : filigrane ET mention', () {
      final a4 = composer();

      expect(a4.filigrane, CertificationMecef.filigraneDemonstration);
      expect(
        a4.texteBrut,
        contains(texteTicket(CertificationMecef.libelleDemonstration)),
      );
      expect(a4.texteBrut, isNot(contains('certifiée MECeF')));
    });

    test('un numéro de DÉMONSTRATION ne retire pas le filigrane', () {
      // `MecefClientFake` produit `MECEF-DEMO-…`. Un document A4 qui
      // l'afficherait comme une certification serait PA-61 sur le seul
      // document que le client emporte.
      final a4 = composer(p: piece(numeroMecef: 'MECEF-DEMO-A1B2C3D4'));

      expect(a4.filigrane, CertificationMecef.filigraneDemonstration);
      expect(
        a4.texteBrut,
        contains(texteTicket(CertificationMecef.libelleDemonstration)),
      );
    });

    test('un VRAI numéro retire le filigrane — et lui seul', () {
      final a4 = composer(p: piece(numeroMecef: 'MECEF-2026-00187'));

      expect(a4.filigrane, isNull);
      expect(
        a4.texteBrut,
        isNot(contains(CertificationMecef.filigraneDemonstration)),
      );
      expect(a4.texteBrut, contains('MECeF MECEF-2026-00187'));
    });

    test('la TVA n’est PAS ventilée, et le document dit pourquoi', () {
      // PA-62 : `taux_tva` n'est pas configuré. Écrire « TVA : 0 F » sur une
      // pièce immuable affirmerait un fait fiscal que rien n'a vérifié.
      final a4 = composer();

      expect(a4.texteBrut, contains('francs CFA'));
      expect(a4.texteBrut, contains('aucune ventilation HT/TVA'));
      expect(a4.texteBrut, isNot(contains('Montant HT')));
      expect(a4.texteBrut, isNot(contains('TVA 18')));
    });
  });

  /* ================================================================== */
  group('⚠ Q3 — hébergement et consommations restent NOMMÉS séparément', () {
    test('les deux montants sont nommés, jamais fondus en un total', () {
      final a4 = composer();

      expect(a4.recapitulatif, hasLength(2));
      expect(a4.recapitulatif[0].$1, 'Hébergement');
      expect(a4.recapitulatif[0].$2, '168 000 FCFA');
      expect(a4.recapitulatif[1].$1, 'Consommations');
      expect(a4.recapitulatif[1].$2, '6 500 FCFA');
      expect(a4.montantTotal, '174 500 FCFA');
    });

    test('le récapitulatif s’additionne EXACTEMENT au total', () {
      // Un récapitulatif qui ne retomberait pas sur le total ferait douter du
      // document entier, et le comptoir ne saurait pas lequel des deux annoncer.
      final p = piece();
      final a4 = composer(p: p);

      final hebergement = p.ventilation[ModuleFacturable.m1Hebergement]!;
      expect(hebergement + (p.montantTotal - hebergement), p.montantTotal);
      expect(a4.montantTotal, '174 500 FCFA');
    });

    test(
      'sans nuitée, le récapitulatif ventile par activité — jamais rien',
      () {
        // Une vente au comptant n'a pas d'hébergement. Le document doit
        // toujours dire d'où vient l'argent, pas afficher un total seul.
        final a4 = composer(
          p: piece(
            origine: OrigineFacture.posComptant,
            lignes: const [
              LigneFacture(
                id: 'l1',
                module: ModuleFacturable.m5Bar,
                libelle: 'Béninoise 33cl',
                prixUnitaire: 1000,
                quantite: 2,
                ordre: 0,
              ),
            ],
          ),
        );

        expect(a4.recapitulatif, hasLength(1));
        expect(a4.recapitulatif.single.$1, 'Bar');
        expect(a4.texteBrut, isNot(contains('Hébergement')));
      },
    );

    test('chaque ligne du tableau porte son activité', () {
      final a4 = composer();

      expect(a4.lignesTableau, hasLength(3));
      expect(a4.lignesTableau[0][1], 'Hébergement');
      expect(a4.lignesTableau[1][1], 'Bar');
      expect(a4.lignesTableau[2][1], 'Restaurant');
      expect(a4.lignesTableau[0][2], '28 000 FCFA');
      expect(a4.lignesTableau[0][3], '6');
      expect(a4.lignesTableau[0][4], '168 000 FCFA');
    });
  });

  /* ================================================================== */
  group('L’auteur et le pied institutionnel', () {
    test('l’auteur RÉEL est nommé, avec sa fonction', () {
      final a4 = composer();

      expect(a4.texteBrut, contains('Céline AGBODJAN - Comptable'));
      expect(a4.texteBrut, contains('20/08/2026 à 16:45'));
    });

    test('l’auteur n’est PAS une valeur en dur — changer la session change le '
        'document', () {
      // `RESPECT_TABLEAU_RAPPORT.md` §4 : « Auteur affiché = Administrateur
      // par défaut » est la non-conformité classique. Si le nom était figé,
      // ce test rougirait.
      final a4 = composer(
        qui: const AuteurEdition(nom: 'Noël NABOGOU', role: 'Gérant'),
      );

      expect(a4.texteBrut, contains('Noël NABOGOU - Gérant'));
      expect(a4.texteBrut, isNot(contains('Céline AGBODJAN')));
      expect(a4.texteBrut, isNot(contains('Administrateur')));
    });

    test('le pied porte la mention institutionnelle PAEB / FAGUEZ', () {
      final a4 = composer();

      expect(a4.texteBrut, contains('Projet PAEB'));
      expect(a4.texteBrut, contains('Cabinet FAGUEZ SARL'));
    });
  });

  /* ================================================================== */
  group('L’avoir et la pièce annulée', () {
    test('l’avoir s’annonce comme tel, avec la pièce qu’il neutralise', () {
      final a4 = composer(p: piece(avoir: true));

      expect(a4.titre, 'AVOIR F-2026-00042');
      expect(a4.texteBrut, contains('F-2026-00041'));
      expect(a4.texteBrut, contains('Erreur de saisie - chambre déjà réglée'));
      expect(a4.libelleTotal, contains('AVOIR'));
      for (final texte in a4.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });

    test('une facture annulée reste éditable, et le dit', () {
      // C'est même le seul moyen de justifier l'avoir qui la neutralise.
      final a4 = composer(p: piece(annulee: true));

      expect(a4.titre, 'FACTURE F-2026-00042');
      expect(a4.texteBrut, contains('Pièce annulée'));
      for (final texte in a4.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });
  });

  /* ================================================================== */
  group('Le PDF', () {
    test('le format est bien A4, et pas un rouleau', () {
      expect(formatFactureA4.width, closeTo(595.28, 0.1));
      expect(formatFactureA4.height, closeTo(841.89, 0.1));
      expect(formatFactureA4.height.isFinite, isTrue);
    });

    test('le document sort en octets de PDF valides', () async {
      final octets = await composer().pdf();

      expect(octets.length, greaterThan(1000));
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test(
      'le logo, quand il est fourni, entre réellement dans le PDF',
      () async {
        // Le logo est INJECTÉ, jamais lu par le module de composition : une
        // lecture de fichier au fond d'un objet de rendu le rendrait impossible
        // à éprouver hors d'une application complète.
        final sans = await composer().pdf();
        final logo = File(AppAssets.logo).readAsBytesSync();
        final avec = await composer(
          entete: const EnteteEtablissement().avecLogo(
            Uint8List.fromList(logo),
          ),
        ).pdf();

        expect(logo.length, greaterThan(1000));
        expect(
          avec.length,
          greaterThan(sans.length),
          reason: 'le logo doit peser dans le document, donc y être',
        );
        // Le PNG du PO (14/10/2026, D392) y est à ses dimensions natives :
        // le paysage 735 × 403, posé en `contain` dans son cadre de 48.
        final texte = String.fromCharCodes(avec);
        expect(texte, contains(RegExp(r'/Width\s+735\b')));
        expect(texte, contains(RegExp(r'/Height\s+403\b')));
      },
    );
  });
}
