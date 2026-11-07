import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/bloc_signature_a4.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';
import 'package:tatacora_flutter/features/facturation/impression/facture_a4.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';

/// La signature et le cachet sur la FACTURE A4 du poste (PO, 07/11/2026) : selon l'interrupteur
/// des Paramètres, et RIEN de plus — jamais sur le ticket, jamais de mention fiscale ajoutée.
void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  const auteur = AuteurEdition(nom: 'Céline', role: 'Comptable');

  final piece = PieceFacturation(
    id: 'p1',
    numero: 'F-2026-00042',
    origine: OrigineFacture.factureDirecte,
    dateEmission: DateTime(2026, 11, 7, 10),
    clientNom: 'KORA',
    statut: StatutPiece.emise,
    lignes: const [
      LigneFacture(
        id: 'l1',
        module: ModuleFacturable.m9Tourisme,
        libelle: 'Circuit',
        prixUnitaire: 10000,
        quantite: 2,
        ordre: 0,
      ),
    ],
  );

  BlocSignatureA4? bloc(bool affichee) => BlocSignatureA4.depuis(
    ReglagesDocuments.depuis({
      ClesReglagesDocuments.signatureAffichee: '$affichee',
      ClesReglagesDocuments.signataireNom: 'NABOGOU Winribassé Noël',
      ClesReglagesDocuments.signataireFonction: 'Directeur Général',
    }),
    raisonSociale: 'TATACORA AFRIQUE',
    signature: png,
    cachet: png,
  );

  FactureA4Composee composer(BlocSignatureA4? b) => FactureA4.composer(
    piece,
    auteur: auteur,
    dateEdition: DateTime(2026, 11, 7, 11),
    signature: b,
  );

  test('Non : la facture n\'a ni nom, ni fonction, ni images', () {
    final f = composer(bloc(false));
    expect(f.signature, isNull);
    expect(f.texteBrut, isNot(contains('NABOGOU')));
    expect(f.texteBrut, isNot(contains('Pour TATACORA')));
  });

  test('Oui : nom, fonction et images ; le PDF est produit', () async {
    final f = composer(bloc(true));
    expect(f.texteBrut, contains('Pour TATACORA AFRIQUE'));
    expect(f.texteBrut, contains('NABOGOU Winribassé Noël'));
    expect(f.texteBrut, contains('Directeur Général'));
    final pdf = await f.pdf();
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });

  test('RIEN de plus : la signature n\'ajoute aucune mention fiscale', () {
    final sans = composer(null).texteBrut;
    final avec = composer(bloc(true)).texteBrut;
    final ajoute = avec.replaceFirst(sans, '');
    expect(ajoute.toUpperCase(), isNot(contains('MECEF')));
    expect(ajoute.toUpperCase(), isNot(contains('NORMALIS')));
  });

  test('le ticket 80 mm n\'appelle jamais le bloc signature', () {
    final ticket = TicketFacture.composer(piece);
    expect(ticket.toString(), isNot(contains('NABOGOU')));
  });
}
