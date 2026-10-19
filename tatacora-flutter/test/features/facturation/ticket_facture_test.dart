import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';

/// **Le ticket, et le garde-fou qui évite de découvrir l'amputation sur le
/// papier.**
///
/// ## Ce que ces tests prouvent
///
/// Que **le document effectivement composé** ne contient aucun caractère que
/// les polices intégrées du PDF supprimeraient en silence. Pas un échantillon
/// écrit à côté : la liste `TicketCompose.textes` est, par construction,
/// exactement ce que `TicketCompose.pdf()` rend.
///
/// La distinction n'est pas théorique. En D0.6, une assertion « les accents
/// survivent » ne vérifiait que des octets non nuls : elle est passée au vert
/// en masquant le défaut qu'elle prétendait couvrir.
///
/// ## Ce qu'ils ne prouvent PAS, et qu'aucun test ne prouvera
///
/// Ni la **largeur réelle du papier**, ni le **jeu de caractères du pilote**,
/// ni la **lisibilité**. Cela demande la machine du comptoir. Rapporter
/// « le ticket sort correctement » sur la foi de ces tests serait exactement
/// l'indicateur que la campagne PA-59 → PA-98 a démonté.
void main() {
  PieceFacturation piece({
    bool avoir = false,
    bool annulee = false,
    String? numeroMecef,
    String clientNom = 'KORA — l’addition « soldée »',
    List<LigneFacture>? lignes,
  }) => PieceFacturation(
    id: 'p1',
    numero: 'F-2026-00042',
    origine: OrigineFacture.posSejour,
    dateEmission: DateTime(2026, 8, 20, 14, 30),
    clientNom: clientNom,
    statut: annulee ? StatutPiece.annulee : StatutPiece.emise,
    numeroMecef: numeroMecef,
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

  /* ================================================================== */
  group('Aucun caractère ne sera perdu à l’impression', () {
    test(
      'CRITÈRE — le document composé ne contient AUCUN caractère non imprimable',
      () {
        // Le garde-fou qui compte, et il porte sur le document réel : on
        // refuse en amont tout caractère que la police ne rend pas, plutôt que
        // de constater l'amputation sur le papier.
        //
        // La pièce est volontairement piégée : le nom du client porte une
        // apostrophe typographique et des guillemets courbes, le libellé
        // d'hébergement un tiret cadratin. Sans normalisation,
        // « l’addition » sortirait « laddition ».
        final ticket = TicketFacture.composer(piece());

        for (final texte in ticket.textes) {
          expect(
            caracteresNonImprimables(texte),
            isEmpty,
            reason:
                'ces caractères disparaîtraient en silence dans « $texte » : '
                '${caracteresNonImprimables(texte).join(' ')}',
          );
        }
      },
    );

    test('le piège est réel : la source, elle, en contient', () {
      // Sans cette assertion, le test précédent pourrait passer parce que le
      // jeu d'essai ne contient rien de dangereux — donc pour la mauvaise
      // raison. C'est exactement le défaut d'assertion vide de D0.6.
      const source = 'KORA — l’addition « soldée »';
      expect(caracteresNonImprimables(source), isNotEmpty);
      expect(caracteresNonImprimables(source), containsAll(['—', '’']));
    });

    test('les accents Latin-1 sont CONSERVÉS', () {
      // Ils passent : les retirer appauvrirait le ticket sans raison.
      final ticket = TicketFacture.composer(piece());

      expect(ticket.texteBrut, contains('GÎTE CHEZ NOËL'));
      expect(ticket.texteBrut, contains('Béninoise 33cl'));
      expect(ticket.texteBrut, contains('Poulet braisé'));
      expect(ticket.texteBrut, contains('DOCUMENT DE DÉMONSTRATION'));
    });

    test('le tiret cadratin est substitué, jamais supprimé', () {
      final ticket = TicketFacture.composer(piece());

      expect(ticket.texteBrut, contains('Natitingou - Bénin'));
      expect(ticket.texteBrut, isNot(contains('Natitingou  Bénin')));
      expect(ticket.texteBrut, contains("l'addition"));
    });

    test('l’avoir n’échappe pas au garde-fou', () {
      // Son motif porte lui aussi un tiret cadratin, et il n'est composé que
      // sur cette branche : un test qui ne couvrirait que la facture laisserait
      // ce chemin non exécuté.
      final ticket = TicketFacture.composer(piece(avoir: true));

      expect(ticket.texteBrut, contains('AVOIR F-2026-00042'));
      expect(ticket.texteBrut, contains('Neutralise la facture F-2026-00041'));
      for (final texte in ticket.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });

    test('la facture annulée n’y échappe pas non plus', () {
      final ticket = TicketFacture.composer(piece(annulee: true));

      expect(ticket.texteBrut, contains('ANNULÉE'));
      for (final texte in ticket.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
    });

    test('un en-tête personnalisé passe par la même normalisation', () {
      // Le jour où l'en-tête viendra des paramètres, il portera ce que
      // quelqu'un aura saisi — apostrophes typographiques comprises. Le
      // chemin doit donc être sûr par construction, pas par convention.
      final ticket = TicketFacture.composer(
        piece(),
        entete: const EnteteEtablissement(
          etablissement: 'Gîte de l’Atacora — Annexe',
          localite: 'Natitingou · Bénin…',
        ),
      );

      for (final texte in ticket.textes) {
        expect(caracteresNonImprimables(texte), isEmpty, reason: texte);
      }
      expect(ticket.texteBrut, contains('Gîte de l\'Atacora - Annexe'));
    });
  });

  /* ================================================================== */
  group('MECeF — le ticket dit la vérité (PA-61)', () {
    test('non certifiée : la mention ET le filigrane', () {
      final ticket = TicketFacture.composer(piece());

      // La comparaison passe par `texteTicket` : la mention elle-même contient
      // un tiret cadratin, et l'attendre brut ferait échouer un ticket
      // pourtant correct. C'est le meilleur rappel qu'AUCUN texte n'échappe à
      // la normalisation, pas même celui du garde-fou MECeF.
      expect(
        ticket.texteBrut,
        contains(texteTicket(CertificationMecef.libelleDemonstration)),
      );
      expect(
        ticket.texteBrut,
        contains(CertificationMecef.filigraneDemonstration),
        reason:
            'obligation ouverte du dépôt : une pièce non certifiée remise à un '
            'client doit le dire sur le DOCUMENT, pas seulement à l’écran',
      );
      expect(ticket.texteBrut, isNot(contains('certifiée MECeF')));
      expect(ticket.texteBrut, isNot(contains('MECeF F-')));
    });

    test('un numéro de DÉMONSTRATION ne retire pas le filigrane', () {
      // Le piège : `MecefClientFake` produit `MECEF-DEMO-…`. Un ticket qui
      // afficherait ce numéro comme une certification serait exactement PA-61,
      // sur le seul document que le client emporte.
      final ticket = TicketFacture.composer(
        piece(numeroMecef: 'MECEF-DEMO-A1B2C3D4'),
      );

      expect(
        ticket.texteBrut,
        contains(CertificationMecef.filigraneDemonstration),
      );
      expect(
        ticket.texteBrut,
        contains(texteTicket(CertificationMecef.libelleDemonstration)),
      );
    });

    test('un VRAI numéro retire le filigrane — et lui seul', () {
      // La branche que personne n'a encore empruntée, et c'est précisément
      // pourquoi elle est éprouvée : PA-61 vivait dans une branche `active`
      // qu'aucun test ne visitait.
      final ticket = TicketFacture.composer(
        piece(numeroMecef: 'MECEF-2026-00187'),
      );

      expect(
        ticket.texteBrut,
        isNot(contains(CertificationMecef.filigraneDemonstration)),
      );
      expect(ticket.texteBrut, contains('MECeF MECEF-2026-00187'));
    });
  });

  /* ================================================================== */
  group('Le montant', () {
    test('les milliers sont séparés par une espace ORDINAIRE', () {
      // Une espace fine insécable (U+202F) est hors Latin-1 : elle serait
      // supprimée en silence, et « 172 000 F » sortirait « 172000 F » — un
      // caractère qu'on ne pense jamais à vérifier parce qu'il est invisible.
      expect(TicketFacture.montant(172000), '172 000 FCFA');
      expect(TicketFacture.montant(6500), '6 500 FCFA');
      expect(TicketFacture.montant(500), '500 FCFA');
      expect(TicketFacture.montant(0), '0 FCFA');
      expect(caracteresNonImprimables(TicketFacture.montant(1234567)), isEmpty);
    });

    test('un avoir s’imprime en négatif', () {
      expect(TicketFacture.montant(-6500), '-6 500 FCFA');
    });

    test('le total du ticket est celui de la pièce', () {
      final p = piece();
      final ticket = TicketFacture.composer(p);

      expect(p.montantTotal, 174500);
      expect(ticket.texteBrut, contains('174 500 FCFA'));
    });
  });

  /* ================================================================== */
  group('Le PDF au format rouleau 80 mm', () {
    test('le format est bien celui d’un rouleau, pas d’une page', () {
      // Un ticket composé en A4 sort tronqué sur la moitié droite, ou
      // minuscule, selon le pilote.
      expect(formatRouleau80mm.width, 80 * PdfPageFormatMm.mm);
      expect(formatRouleau80mm.height, double.infinity);
    });

    test('le document sort en octets de PDF valides', () async {
      // NB — `dart_pdf` imprime « Helvetica has no Unicode support » à chaque
      // création de police base-14. C'est un `assert` **inconditionnel** de la
      // bibliothèque (`type1_font.dart`), pas le signalement d'un caractère
      // perdu : il rappelle la limite Latin-1 que la normalisation traite déjà.
      // Le lire comme un défaut ferait chercher au mauvais endroit.
      final octets = await TicketFacture.composer(piece()).pdf();

      expect(octets.length, greaterThan(500));
      // Un PDF commence par `%PDF`. Le vérifier évite de valider un tableau
      // d'octets vide qui aurait l'air d'un succès.
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });
  });
}

/// Petit alias pour éviter d'importer `package:pdf` dans les assertions.
extension PdfPageFormatMm on Never {
  static const double mm = 72.0 / 25.4;
}
