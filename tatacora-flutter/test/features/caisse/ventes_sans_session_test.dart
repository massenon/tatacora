import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/caisse/domain/especes_de_la_session.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';

/// Réserve R2 : les ventes en espèces de la période qui ne sont rattachées à
/// AUCUNE session (celles d'avant la v18). Fonction pure : chaque critère du
/// filtre a son cas, sinon un critère retiré passerait inaperçu.
void main() {
  final ouverture = DateTime(2026, 10, 12, 8);

  Panier panier({
    String id = 'p',
    TypeVente type = TypeVente.comptant,
    StatutPanier statut = StatutPanier.cloture,
    String? mode = 'especes',
    String? session,
    DateTime? cloture,
    int? montant = 3000,
  }) => Panier(
    id: id,
    typeVente: type,
    statut: statut,
    ouvertLe: DateTime(2026, 10, 12, 7),
    lignes: const [],
    clotureLe: cloture ?? DateTime(2026, 10, 12, 9),
    modePaiement: mode,
    montantCloture: montant,
    sessionEncaissementId: session,
  );

  ({int nombre, int montant}) mesure(List<Panier> l) =>
      ventesEnEspecesSansSession(l, ouverture);

  test('une vente en espèces, clôturée après l’ouverture, sans session : '
      'comptée avec son montant', () {
    expect(mesure([panier(), panier(id: 'q', montant: 1500)]), (
      nombre: 2,
      montant: 4500,
    ));
  });

  test('rattachée à une session : jamais comptée', () {
    expect(mesure([panier(session: 's')]).nombre, 0);
  });

  test('un autre mode que les espèces n’entre pas dans un tiroir', () {
    for (final m in [
      'mobile_money',
      'carte',
      'virement',
      'note_chambre',
      null,
    ]) {
      expect(mesure([panier(mode: m)]).nombre, 0, reason: '$m');
    }
  });

  test('un séjour (note de chambre) n’est pas une vente en espèces', () {
    expect(mesure([panier(type: TypeVente.surSejour)]).nombre, 0);
  });

  test('un panier non clôturé n’est pas une vente', () {
    expect(mesure([panier(statut: StatutPanier.ouvert)]).nombre, 0);
    expect(mesure([panier(statut: StatutPanier.annule)]).nombre, 0);
  });

  test('clôturé AVANT l’ouverture de cette caisse : hors période ; à '
      'l’instant exact de l’ouverture : dans la période', () {
    expect(
      mesure([
        panier(cloture: ouverture.subtract(const Duration(minutes: 1))),
      ]).nombre,
      0,
    );
    expect(mesure([panier(cloture: ouverture)]).nombre, 1);
  });

  test('un montant non figé compte zéro franc mais une vente', () {
    expect(mesure([panier(montant: null)]), (nombre: 1, montant: 0));
  });

  test('la phrase : singulier, pluriel, et jamais « comptée » à tort', () {
    final un = MessagesCaisse.ventesSansSession(1, '2 000 FCFA');
    final deux = MessagesCaisse.ventesSansSession(2, '5 000 FCFA');
    expect(un, startsWith('Une vente en espèces (2 000 FCFA)'));
    expect(deux, startsWith('2 ventes en espèces (5 000 FCFA au total)'));
    expect(un, contains('PAS comptée'));
  });
}
