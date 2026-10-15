import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/presentation/vocabulaire_pos.dart';

import '../../support/vue_blade.dart';

/// Le vocabulaire des deux POS, **confronté à la vue Blade elle-même**.
///
/// ## Pourquoi ce test lit la vue Blade de la PWA
///
/// La doctrine est explicite : *« le template est le maître de mise en
/// page ; le code Flutter est une traduction, pas une réinterprétation »*. Le
/// template, depuis PA-182/PA-183, est la vue Blade de `tatacora-api` —
/// `prototype_v2/` est une ancienne version. Un test qui se contenterait de
/// figer `'Encaisser'` dans une constante ne vérifierait rien d'autre que
/// lui-même — il resterait vert le jour où la vue change, et la traduction
/// dériverait sans que personne ne le voie.
///
/// Ici, chaque libellé est **cherché dans la vue, ses libellés résolus**.
/// C'est la seule forme de fidélité qui se tienne toute seule.
///
/// ## Le défaut que ces cas empêchent de revenir (24/08/2026)
///
/// `VueCatalogue` et `VuePanier` sont partagés par les deux écrans, et rien ne
/// portait la différence de vocabulaire : le comptoir affichait les mots des
/// séjours. « Clôturer et facturer » nommait une fin de séjour là où le
/// caissier encaisse une vente de passage, et « Abandonner » — qui libère la
/// table — avait disparu derrière un « Annuler » qui ne dit pas qu'une table
/// se libère.
void main() {
  const comptoir = 'pos/comptant';
  const sejours = 'pos/heberges';

  /// La vue, ses libellés résolus, ses COMMENTAIRES Blade retirés — ils citent
  /// souvent les mots de l'ancien prototype, et un libellé qui n'existe qu'en
  /// commentaire n'est pas affiché. **Échoue plutôt que de sauter** si elle
  /// manque (voir [VueBlade.fichier]).
  String vue(String nom) => VueBlade.resolue(nom)
      .replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' ')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ');

  void present(String nom, String libelle) {
    expect(
      vue(nom),
      contains(libelle.replaceAll('’', "'")),
      reason:
          '« $libelle » ne figure pas dans pwa/$nom.blade.php. Le code Flutter '
          'emploie un mot que la vue n’écrit pas : c’est une réinterprétation, '
          'pas une traduction.',
    );
  }

  group('Le comptoir parle la langue de pos/comptant', () {
    final v = VocabulairePos.de(PointDeVentePos.comptoir);

    test('« Encaisser » est bien le bouton de la vue', () {
      present(comptoir, v.actionPrincipale);
    });

    test('« Vider » et « Abandonner » sont deux gestes de la vue', () {
      expect(v.retirerLignes, isNotNull);
      present(comptoir, v.retirerLignes!);
      present(comptoir, v.fermerPanier);
    });

    test('le champ de recherche reprend l’invite de la vue', () {
      present(comptoir, v.indicationRecherche);
    });

    test('« Mode de règlement » est le libellé de la vue', () {
      expect(v.libelleReglement, isNotNull);
      present(comptoir, v.libelleReglement!);
    });
  });

  group('Les séjours parlent la langue de pos/heberges', () {
    final v = VocabulairePos.de(PointDeVentePos.sejours);

    test('« Clôturer et facturer » est bien le bouton de la vue', () {
      present(sejours, v.actionPrincipale);
    });

    test('« Annuler » est le geste de la vue', () {
      present(sejours, v.fermerPanier);
    });

    test('le champ de recherche reprend l’invite de la vue', () {
      present(sejours, v.indicationRecherche);
    });

    test('aucun règlement dans ce panneau — un séjour se règle au départ', () {
      expect(v.libelleReglement, isNull);
      expect(v.retirerLignes, isNull);
      // Et la vue ne le pose pas non plus : c'est l'absence qui est fidèle.
      expect(
        vue(sejours),
        isNot(contains('Mode de règlement')),
        reason:
            'La vue des séjours ne propose aucun règlement. En ajouter un '
            'serait un ajout, que la doctrine traite comme un écart au même '
            'titre qu’un manque.',
      );
    });
  });

  group('Les deux POS ne se confondent pas', () {
    final vComptoir = VocabulairePos.de(PointDeVentePos.comptoir);
    final vSejours = VocabulairePos.de(PointDeVentePos.sejours);

    test('leurs mots diffèrent réellement', () {
      // Le cas qui aurait rougi AVANT le correctif : les deux écrans
      // partageaient les mêmes chaînes.
      expect(vComptoir.actionPrincipale, isNot(vSejours.actionPrincipale));
      expect(
        vComptoir.indicationRecherche,
        isNot(vSejours.indicationRecherche),
      );
      expect(vComptoir.fermerPanier, isNot(vSejours.fermerPanier));
    });

    test('et aucun n’emprunte le bouton de l’autre à sa vue', () {
      expect(
        vue(comptoir),
        isNot(contains(vSejours.actionPrincipale)),
        reason:
            'La vue du comptoir ne dit jamais « Clôturer et facturer » : '
            'l’employer là serait exactement le défaut corrigé.',
      );
    });
  });

  group('Les modes de règlement viennent du SERVEUR', () {
    // `app/Domain/Ventes/Services/VenteService.php` : `MODES_PAIEMENT` est le
    // registre que l'API valide et que les deux vues de la PWA affichent.
    // Le moteur JavaScript du prototype qui le portait avant est archivé.
    String venteService() => VueBlade.fichier(
      'app/Domain/Ventes/Services/VenteService.php',
      role: 'le registre des modes de règlement',
    );

    List<String> clesDe(String source, String constante) {
      final debut = source.indexOf('const $constante = [');
      if (debut < 0) {
        fail('`$constante` a disparu de VenteService : rien à confronter.');
      }
      final bloc = source.substring(debut, source.indexOf('];', debut));
      return RegExp(
        r"'([a-z_]+)' =>",
      ).allMatches(bloc).map((m) => m.group(1)!).toList();
    }

    test('les codes du client sont ceux du serveur, et eux seuls', () {
      final serveur = clesDe(venteService(), 'MODES_PAIEMENT');

      expect(
        serveur,
        isNotEmpty,
        reason: 'extraction vide : ce cas passerait à vide, donc vert',
      );
      expect(
        ModeReglement.values.map((m) => m.code).toSet(),
        serveur.toSet(),
        reason:
            'Un code divergent rendrait les ventes des deux canaux '
            'incomparables, et le serveur le refuserait.',
      );
      expect(ModeReglement.values.length, serveur.length);
    });

    test('« porté sur la note de chambre » n’encaisse PAS', () {
      // La propriété qui compte : ce mode crée une créance, réglée au départ.
      // L'enregistrer comme un encaissement ferait entrer en caisse un argent
      // qui n'y est pas — et le ferait disparaître de ce que le client doit.
      // Côté serveur, c'est le seul mode sans trésorerie débitée
      // (`CONTREPARTIES_TRESORERIE`).
      final source = venteService();
      final tous = clesDe(source, 'MODES_PAIEMENT').toSet();
      final encaisses = clesDe(source, 'CONTREPARTIES_TRESORERIE').toSet();

      expect(encaisses, isNotEmpty);
      expect(tous.difference(encaisses), {'note_chambre'});

      expect(ModeReglement.noteChambre.encaisse, isFalse);
      expect(
        ModeReglement.values.where((m) => !m.encaisse).map((m) => m.code),
        tous.difference(encaisses),
      );
    });

    test('un code inconnu LÈVE au lieu de se replier sur les espèces', () {
      // Un repli silencieux rangerait en caisse une vente réglée autrement.
      expect(() => ModeReglement.parCode('bitcoin'), throwsArgumentError);
      expect(ModeReglement.parCode('note_chambre'), ModeReglement.noteChambre);
    });
  });
}
