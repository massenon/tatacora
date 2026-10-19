import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/historique_reservations.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';

import '../../support/vue_blade.dart';

/// Le vocabulaire de la réservation, **confronté à la vue Blade elle-même**.
///
/// ## Pourquoi ce test lit la vue Blade de la PWA
///
/// La doctrine est explicite : *« le template est le maître de mise en page ;
/// le code Flutter est une traduction, pas une réinterprétation »*
/// (`docs/DOCTRINE_PORTAGE_FIDELE_FLUTTER.md`). Le template est, depuis
/// PA-182/PA-183, la vue Blade de `tatacora-api` — `prototype_v2/` est une
/// ancienne version, et ses moteurs JavaScript ne font plus foi. Un test qui
/// figerait `'Hébergement'` dans une constante ne vérifierait que lui-même :
/// il resterait vert le jour où la vue change, et la traduction dériverait
/// sans que personne ne le voie.
///
/// Chaque libellé est donc **cherché dans la vue, ses libellés résolus**, ou
/// dans la classe Livewire qui la pilote (`app/Pwa/Livewire/Hebergement/
/// Reservations.php`). Les registres fermés viennent du SERVEUR
/// (`LigneReservation::SERVICES`, `Reservations::MODES_PAIEMENT`…).
///
/// ## Ce que ces cas empêchent de revenir (25/08/2026)
///
/// Le client Flutter ne connaissait qu'une chambre et un tarif de nuit, là où
/// la fiche compose une réservation de **cinq services**. Le sous-total valait
/// `tarif × nuits` — juste pour un séjour sec, faux dès qu'un circuit entrait
/// dans la même fiche, et sans que rien ne le signale.
void main() {
  const vueReservations = 'hebergement/reservations';

  String normaliser(String t) => t
      // L'apostrophe DROITE est repliée sur la typographique : c'est la même
      // phrase, et seule la formulation est vérifiée ici.
      .replaceAll("'", '’')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Le texte de la vue, libellés résolus : BRUT (les invites et les titres
  /// de modale vivent dans des attributs — `placeholder`, `:titre`) PLUS sa
  /// version sans balises (une phrase coupée par un `<strong>` se lit d'un
  /// tenant). Retirer les balises seules effaçait les attributs, et le test
  /// déclarait absente une invite pourtant affichée.
  ///
  /// Les COMMENTAIRES Blade sont retirés : ils citent souvent les mots de
  /// l'ancien prototype, et un libellé qui n'existe qu'en commentaire n'est
  /// pas affiché.
  String vue() {
    final resolue = VueBlade.resolue(
      vueReservations,
    ).replaceAll(RegExp(r'\{\{--[\s\S]*?--\}\}'), ' ');
    return normaliser(
      '$resolue\n${resolue.replaceAll(RegExp(r'<[^>]*>'), '')}',
    );
  }

  /// La classe Livewire de l'écran, telle quelle.
  String classe() => VueBlade.fichier(
    'app/Pwa/Livewire/Hebergement/Reservations.php',
    role: 'la classe Livewire de l’écran Réservations',
  );

  /// Les libellés RÉSOLUS des clés de langue d'une constante `NOM = [
  /// 'code' => 'cle.de.langue' ]` de la classe — dans leur ordre.
  Map<String, String> libellesDeLaConstante(String nom) {
    final source = classe();
    final debut = source.indexOf('const $nom = [');
    if (debut < 0) fail('`Reservations::$nom` a disparu : rien à confronter.');
    final bloc = source.substring(debut, source.indexOf('];', debut));
    final paires = {
      for (final m in RegExp(
        r"'([a-z_]+)' => '([a-z_]+(?:\.[a-z_]+)+)'",
      ).allMatches(bloc))
        m.group(1)!: VueBlade.libelle(m.group(2)!) ?? m.group(2)!,
    };
    if (paires.isEmpty) fail('`Reservations::$nom` : extraction vide.');
    return paires;
  }

  void present(String libelle) {
    expect(
      vue(),
      contains(normaliser(libelle)),
      reason:
          '« $libelle » ne figure pas dans pwa/$vueReservations.blade.php. Le '
          'code Flutter emploie un mot que la vue n’écrit pas : c’est une '
          'réinterprétation, pas une traduction.',
    );
  }

  group('Les cinq services sont ceux de la PWA', () {
    test('aucun service de plus, aucun de moins', () {
      // Le registre est FERMÉ : l'hébergement porté par `reservations.
      // unite_id`, et les quatre autres par `lignes_reservation.service`.
      final serveur = VueBlade.fichier(
        'app/Domain/Hebergement/Models/LigneReservation.php',
        role: 'le registre des services d’une ligne de réservation',
      );
      final m = RegExp(r'const SERVICES = \[(.*?)\];').firstMatch(serveur);
      expect(m, isNotNull, reason: '`LigneReservation::SERVICES` a disparu');
      final lignes = RegExp(
        "'([a-z_]+)'",
      ).allMatches(m!.group(1)!).map((c) => c.group(1)!).toList();

      expect(lignes, hasLength(4));
      expect(ServiceReservation.values, hasLength(5));
      expect(ServiceReservation.values.first.cle, 'hebergement');
      expect(ServiceReservation.values.skip(1).map((s) => s.cle), lignes);
    });

    test(
      'chaque nom, chaque intitulé de quantité et de ligne est celui de la PWA',
      () {
        // Les noms et les intitulés de ligne vivent dans
        // `app/Pwa/Support/CouleursServices.php` (`libelle()` et
        // `labelLigne()`, clés littérales par `match`) ; les intitulés de
        // quantité dans `Reservations::LIBELLES_QUANTITE`.
        final source = VueBlade.fichier(
          'app/Pwa/Support/CouleursServices.php',
          role: 'les noms et intitulés des services de la fiche',
        );
        Map<String, String> parService(String fonction) {
          final debut = source.indexOf('function $fonction(');
          if (debut < 0) fail('`CouleursServices::$fonction` a disparu.');
          final bloc = source.substring(debut, source.indexOf('});', debut));
          final paires = {
            for (final m in RegExp(
              r"'([a-z_]+)' => '([a-z_]+(?:\.[a-z_]+)+)'",
            ).allMatches(bloc))
              m.group(1)!: m.group(2)!,
          };
          final defaut = RegExp(
            r"default => '([a-z_]+(?:\.[a-z_]+)+)'",
          ).firstMatch(bloc);
          if (defaut != null) paires['hebergement'] = defaut.group(1)!;
          return {
            for (final e in paires.entries)
              e.key: VueBlade.libelle(e.value) ?? e.value,
          };
        }

        final noms = parService('libelle');
        final lignes = parService('labelLigne');
        final quantites = libellesDeLaConstante('LIBELLES_QUANTITE');

        expect(noms, hasLength(5));
        expect(lignes, hasLength(5));

        for (final service in ServiceReservation.values) {
          expect(
            noms[service.cle],
            service.nom,
            reason:
                'le nom du service `${service.cle}` n’est pas celui de la PWA',
          );
          expect(
            lignes[service.cle],
            service.labelLigne,
            reason:
                'l’intitulé de ligne de « ${service.nom} » n’est pas celui de '
                '`CouleursServices::labelLigne`',
          );
          if (service.cle == 'hebergement') continue;
          expect(
            quantites[service.cle],
            service.labelQuantite,
            reason:
                'l’intitulé de quantité de « ${service.nom} » n’est pas celui '
                'de `Reservations::LIBELLES_QUANTITE`',
          );
        }
      },
    );

    test('seul l’hébergement a une quantité calculée', () {
      // La PWA ne propose AUCUN intitulé de quantité pour l'hébergement : ses
      // nuits se déduisent des dates, elles ne se saisissent pas.
      final quantites = libellesDeLaConstante('LIBELLES_QUANTITE');
      expect(quantites.containsKey('hebergement'), isFalse);
      expect(ServiceReservation.values.where((s) => s.quantiteEstCalculee), [
        ServiceReservation.hebergement,
      ]);
    });
  });

  group('La fiche client parle la langue de la vue', () {
    test('les quatre types de client', () {
      final types = libellesDeLaConstante('TYPES_CLIENT');
      expect(
        TypeClient.values.map((t) => t.libelle).toSet(),
        types.values.toSet(),
      );
    });

    test('les modes de paiement — et PAS ceux du point de vente', () {
      final modes = libellesDeLaConstante('MODES_PAIEMENT');
      expect(
        ModePaiementReservation.values.map((m) => m.libelle).toList(),
        modes.values.toList(),
        reason:
            'les modes de paiement de la fiche ne sont pas ceux de '
            '`Reservations::MODES_PAIEMENT`',
      );

      // Le contre-exemple, et c'est lui qui donne sa valeur au cas : « Porté
      // sur la note de chambre » est un mode du COMPTOIR. Le voir apparaître
      // ici signifierait que les deux registres ont été fusionnés « parce
      // qu'ils se ressemblent ».
      expect(
        ModePaiementReservation.values.map((m) => m.libelle),
        isNot(contains('Porté sur la note de chambre')),
      );
    });

    test('les types de remise', () {
      for (final r in TypeRemise.values) {
        present(r.libelle);
      }
    });
  });

  group('Le récapitulatif a exactement les cinq lignes de la vue', () {
    const lignes = [
      'Sous-total',
      'Remise',
      'Total à payer',
      'Acompte versé',
      'Reste à payer',
    ];

    for (final ligne in lignes) {
      test('« $ligne »', () => present(ligne));
    }

    test('les cinq lignes sont dans l’ordre de la vue', () {
      // PA-185 (11/09/2026) — ce cas exigeait que la vue porte les `id`
      // `recap-*` de l'ancien prototype. La vue Blade n'en pose aucun : ce
      // sont des clés de widget, un détail de test du client, pas un élément
      // affiché. Ce qui se voit, c'est l'ORDRE des cinq lignes — c'est lui
      // qui est confronté, dans le bloc du récapitulatif de la fiche.
      final brute = VueBlade.brute(vueReservations);
      var position = brute.indexOf(r'@if ($recapFiche !== null)');
      expect(position, greaterThan(-1), reason: 'le récapitulatif a disparu');
      for (final cle in const [
        'pwa.reservations.recap_sous_total',
        'pwa.reservations.champ_remise',
        'pwa.reservations.recap_total',
        'pwa.reservations.recap_acompte',
        'pwa.reservations.recap_reste',
      ]) {
        final trouve = brute.indexOf(cle, position);
        expect(
          trouve,
          greaterThan(position),
          reason: '`$cle` n’apparaît pas à sa place dans le récapitulatif',
        );
        position = trouve;
      }
    });
  });

  group('Le panneau Historique parle la langue de la vue', () {
    test('les quatre états, avec leur code ET leur libellé', () {
      // Le code est celui des `<option>` du filtre ; il doit être aussi celui
      // du registre de la classe (`Reservations::ETATS`).
      expect(EtatSejour.values, hasLength(4));
      final brute = VueBlade.brute(vueReservations);
      for (final e in EtatSejour.values) {
        expect(brute, contains('value="${e.code}"'));
        expect(classe(), contains("'${e.code}'"));
        present(e.libelle);
      }
    });

    test('le titre, le sous-titre et le message d’absence', () {
      present('Historique des réservations');
      present(
        'Toutes les réservations, passées et à venir, avec leur état réel.',
      );
      present('Aucune réservation ne correspond à ces filtres.');
    });

    test('les intitulés des filtres', () {
      for (final libelle in const [
        'Client, canal ou n°…',
        'Tous les états',
        'Tous les services',
        'Réinitialiser',
      ]) {
        present(libelle);
      }
    });

    test('les six indicateurs, dans l’ordre de la vue', () {
      // Un indicateur déplacé se relit mal — on compare de mémoire d'un jour
      // sur l'autre.
      const attendus = [
        'Réservations',
        'À venir',
        'En cours',
        'Nuitées',
        'Chiffre d’affaires',
        'Reste à encaisser',
      ];
      final source = VueBlade.brute(vueReservations);
      final cles = [
        'hist_kpi_total',
        'hist_kpi_a_venir',
        'hist_kpi_en_cours',
        'hist_kpi_nuitees',
        'hist_kpi_ca',
        'hist_kpi_reste',
      ];
      var position = 0;
      for (var i = 0; i < cles.length; i++) {
        expect(
          normaliser(VueBlade.libelle('pwa.reservations.${cles[i]}') ?? ''),
          normaliser(attendus[i]),
        );
        final trouve = source.indexOf('pwa.reservations.${cles[i]}', position);
        expect(
          trouve,
          greaterThanOrEqualTo(position),
          reason:
              '« ${attendus[i]} » n’apparaît pas après le précédent indicateur : '
              'l’ordre du bandeau diverge de celui de la vue.',
        );
        position = trouve;
      }
    });

    test('les colonnes du tableau', () {
      for (final entete in const [
        'Client',
        'Séjour',
        'Nuits',
        'Unités',
        'Services',
        'Total',
        'Reste dû',
        'État',
      ]) {
        present(entete);
      }
    });
  });

  group('Les cartes de la grille parlent la langue de la vue', () {
    test('les libellés de montants', () {
      // Deux lignes, jamais un total unique : « un montant unique de 62 400 F
      // laisserait croire que la nuitée a changé de prix ».
      for (final libelle in const ['Séjour', 'Consommations', 'Total']) {
        present(libelle);
      }
      present('Reste à payer');
    });

    // PA-185 (11/09/2026) — deux cas exigeaient ici « panier ouvert » et
    // « autre(s) ligne(s) », mots de l'ancien prototype que la vue n'écrit
    // pas : sa carte ne détaille aucune ligne et ne porte aucune mention de
    // panier. Le Flutter les a retirés ; ce qui est confronté désormais, ce
    // sont les mots que la carte de la vue écrit réellement.
    test('l’unité et les quatre montants de la carte', () {
      expect(VueBlade.libelle('pwa.reservations.unite'), 'Unité');
      for (final libelle in const [
        'Unité',
        'Séjour',
        'Consommations',
        'Acompte versé',
        'Reste à payer',
      ]) {
        present(libelle);
      }
    });

    test('la carte ne dit ni « panier ouvert » ni « autre(s) ligne(s) »', () {
      // Le code Flutter est relu, commentaires ôtés : ces mots n'existent pas
      // dans la vue, ils ne doivent plus être AFFICHÉS par la carte.
      final carte = File(
        'lib/features/hebergement/presentation/widgets/carte_reservation.dart',
      ).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
      expect(carte, isNot(contains('panier ouvert')));
      expect(carte, isNot(contains('autre(s) ligne(s)')));
    });

    test('le message de grille vide et la recherche', () {
      present('Aucune réservation pour l’instant.');
      present('Rechercher un client...');
    });

    test('les boutons de l’en-tête de page', () {
      for (final libelle in const [
        'Historique',
        'Ajouter client',
        'Nouvelle réservation',
      ]) {
        present(libelle);
      }
    });
  });

  group('La modale d’impression parle la langue de la vue', () {
    test('les quatre textes, mot pour mot', () {
      for (final texte in const [
        'Réservation enregistrée',
        'Voulez-vous imprimer la facture de cette réservation ?',
        'Plus tard',
        'Imprimer la facture',
      ]) {
        present(texte);
      }
    });

    test('le papier imprimé n’a AUCUN numéro alloué — d’où le titre porté', () {
      // `Reservations::imprimerConfirmation()` n'alloue aucun numéro : le
      // document n'a ni numéro, ni IFU, ni cachet. C'est ce constat, vérifié
      // ici dans la PWA elle-même, qui justifie de ne PAS titrer ce papier
      // « facture » (PA-113).
      final source = classe();
      expect(source, contains('function imprimerConfirmation('));
      expect(source, isNot(contains('SequenceDocumentService')));
    });
  });

  group('La modale de détail parle la langue de la vue', () {
    // PA-185 (11/09/2026) — la modale du Flutter portait Client, Période,
    // Canal, Lignes réservées et un récapitulatif à quatre lignes : les champs
    // de l'ancien prototype, que la vue n'a pas. Elle porte désormais les sept
    // de la vue (l.908-918), et ces cas relisent le code Flutter lui-même pour
    // qu'un mot de l'ancien maître ne puisse pas y revenir.
    String dialogue() => File(
      'lib/features/hebergement/presentation/widgets/'
      'dialogue_detail_reservation.dart',
    ).readAsStringSync().replaceAll(r"\'", "'");

    test('le titre, et les sept étiquettes de la vue, dans son ordre', () {
      final titre = VueBlade.libelle(
        'hebergement_pwa.reservations.modale_detail_titre',
      );
      expect(titre, isNotNull);
      expect(titre, startsWith('Détail —'));

      final source = dialogue();
      var position = 0;
      for (final cle in const [
        'pwa.reservations.champ_unite',
        'pwa.reservations.champ_arrivee',
        'pwa.reservations.champ_depart',
        'pwa.reservations.hist_col_nuits',
        'pwa.reservations.champ_acompte',
        'hebergement_pwa.reservations.detail_statut',
        'hebergement_pwa.reservations.detail_etat_derive',
      ]) {
        final libelle = VueBlade.libelle(cle);
        expect(libelle, isNotNull, reason: '`$cle` a disparu de lang/fr');
        present(libelle!);
        final trouve = source.indexOf("'$libelle'", position);
        expect(
          trouve,
          greaterThanOrEqualTo(position),
          reason:
              '« $libelle » manque à la modale Flutter, ou n’y est pas à la '
              'place que la vue lui donne',
        );
        position = trouve;
      }
    });

    test('la vue n’y met aucun récapitulatif — le Flutter non plus', () {
      final brute = VueBlade.brute(vueReservations);
      final debut = brute.indexOf(
        "__('hebergement_pwa.reservations.modale_detail_titre'",
      );
      expect(debut, greaterThan(-1), reason: 'la modale de détail a disparu');
      final bloc = brute.substring(
        debut,
        brute.indexOf('</x-pwa.modale>', debut),
      );
      expect(bloc, isNot(contains('recap_')));
      expect(dialogue(), isNot(contains('RÉCAPITULATIF')));
      expect(dialogue(), isNot(contains('LIGNES RÉSERVÉES')));
    });

    test('le pied : « Annuler la réservation », « Fermer », « Modifier »', () {
      for (final cle in const [
        'hebergement_pwa.reservations.annulation_bouton_fiche',
        'hebergement_pwa.reservations.modale_detail_fermer',
        'pwa.reservations.action_modifier',
      ]) {
        final libelle = VueBlade.libelle(cle);
        expect(libelle, isNotNull, reason: '`$cle` a disparu de lang/fr');
        present(libelle!);
        expect(dialogue(), contains("'$libelle'"));
      }
    });
  });

  group('La modification emploie la MÊME fiche que la création', () {
    test('la vue réutilise sa modale, et change seulement le titre', () {
      // Une seule modale, deux titres : il n'y a pas de second écran
      // d'édition. Un formulaire séparé finirait par diverger — la création
      // recevrait un champ que la modification n'aurait pas.
      final brute = VueBlade.brute(vueReservations);
      final ligne = brute
          .split('\n')
          .firstWhere(
            (l) => l.contains('modale_titre_modification'),
            orElse: () => '',
          );
      expect(ligne, contains('modale_titre_creation'));
      present('Nouvelle réservation');
    });

    test('le contrôle de chevauchement du serveur EXCLUT la réservation', () {
      // C'est le paramètre sans lequel l'édition ne peut rien enregistrer :
      // la fiche se refuserait elle-même.
      final disponibilite = VueBlade.fichier(
        'app/Domain/Hebergement/Services/DisponibiliteService.php',
      );
      expect(disponibilite, contains('exclureReservationId'));
      expect(
        VueBlade.fichier(
          'app/Domain/Hebergement/Services/ReservationService.php',
        ),
        contains(r'exclureId: $reservation->id'),
      );
    });
  });

  group('Les deux règles de calcul sont celles du domaine', () {
    test('le total ne descend jamais sous zéro', () {
      // Une remise supérieure au sous-total ne doit pas produire un montant
      // négatif, qui se lirait comme un avoir.
      final r = RecapitulatifReservation.calculer(
        sousTotal: 10000,
        typeRemise: TypeRemise.montant,
        valeurRemise: 50000,
        acompte: 0,
      );
      expect(r.total, 0);
      expect(r.montantRemise, 10000);
    });

    test('le reste à payer non plus', () {
      final r = RecapitulatifReservation.calculer(
        sousTotal: 10000,
        typeRemise: TypeRemise.aucune,
        valeurRemise: 0,
        acompte: 30000,
      );
      // Un acompte supérieur au total ne signifie pas que l'établissement doit
      // de l'argent : il signifie qu'une saisie est fausse.
      expect(r.reste, 0);
    });

    test('une remise en pourcentage est arrondie une seule fois', () {
      final r = RecapitulatifReservation.calculer(
        sousTotal: 28000,
        typeRemise: TypeRemise.pourcentage,
        valeurRemise: 7.5,
        acompte: 0,
      );
      expect(r.montantRemise, 2100);
      expect(r.total, 25900);
    });
  });
}
