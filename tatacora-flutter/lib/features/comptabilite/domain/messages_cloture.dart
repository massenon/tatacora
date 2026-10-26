/// Les phrases de la CLÔTURE ANNUELLE SYSCOHADA du poste — RECOPIÉES MOT POUR
/// MOT du serveur, clé par clé (26/10/2026).
///
/// ## D'où elles viennent, et comment on sait qu'elles ne divergent pas
///
/// Les refus de `ClotureExerciceService` (`lang/fr/comptabilite.php`), les libellés
/// des pièces qu'elle passe, les écrans de l'onglet « Clôtures »
/// (`lang/fr/comptabilite_pwa.php`) et les motifs de la liste de contrôle
/// (`lang/fr/pwa.php`, `pwa.comptabilite.motifs.*`). `cloture_contre_serveur_test.dart`
/// EXÉCUTE PHP (`tool/comptabilite/rejouer_cloture.php`), relit chacune de ces
/// clés dans les fichiers de langue du serveur et exige l'égalité exacte, des deux
/// côtés (aucune clé en trop, aucune manquante).
///
/// Séparées de `messages_comptables.dart` : ce fichier-là épingle SES 26 clés par
/// un test qui les compte, et un geste de clôture n'est pas une règle d'écriture.
///
/// Le remplacement des variables est celui de Laravel (`MessagesComptables.dire`).
library;

import 'messages_comptables.dart';

abstract final class MessagesCloture {
  /// Les gabarits bruts du serveur, `fichier.clé` -> texte.
  static const gabarits = <String, String>{
    // lang/fr/comptabilite.php
    'comptabilite.cloture_demarrage_impossible':
        "La clôture de l'exercice :annee ne peut pas démarrer : il est :statut (seul un exercice ouvert peut entrer en clôture).",
    'comptabilite.cloture_reprise_impossible':
        "La saisie de l'exercice :annee ne peut pas reprendre : il est :statut.",
    'comptabilite.cloture_exige_en_cloture':
        "L'exercice :annee doit d'abord entrer en clôture (« Démarrer la clôture ») : les modules n'y passent alors plus de pièce, seules les écritures d'inventaire du comptable y entrent.",
    'comptabilite.cloture_ordre':
        "L'exercice :annee ne peut pas être clôturé avant l'exercice :precedent : les exercices se clôturent dans l'ordre (ses à-nouveaux en dépendent).",
    'comptabilite.cloture_conditions_non_reunies':
        "L'exercice :annee ne peut pas être clôturé : :blocages",
    'comptabilite.cloture_suivant_clos':
        "L'exercice :annee est déjà clôturé : les à-nouveaux ne peuvent pas y être reportés.",
    'comptabilite.libelle_piece_cloture':
        'Clôture :annee — solde des comptes de gestion',
    'comptabilite.libelle_piece_a_nouveaux': "À-nouveaux de l'exercice :annee",
    'comptabilite.libelle_reouverture':
        "Réouverture de l'exercice :annee — :motif",
    'comptabilite.reouverture_reservee':
        'Seul le comptable peut rouvrir un exercice clôturé.',
    'comptabilite.reouverture_non_cloture':
        "L'exercice :annee n'est pas clôturé : il n'y a rien à rouvrir.",
    'comptabilite.reouverture_motif':
        "Le motif de la réouverture est obligatoire (:min caractères au moins) : il est écrit au journal d'audit et sur les contre-passations.",
    'comptabilite.reouverture_suivant_clos':
        "L'exercice :annee ne peut pas être rouvert : l'exercice :suivant, qui porte ses à-nouveaux, est déjà clôturé. Rouvrez d'abord :suivant.",
    'comptabilite.archive_cloture_rouverte':
        "Cette clôture a été rouverte : son archive n'est plus celle de l'exercice.",
    'comptabilite.archive_sans_cloture':
        "Cet exercice n'a pas de clôture active : il n'y a pas d'archive.",
    'comptabilite.archive_alteree':
        "L'archive de clôture ne correspond plus à son empreinte : un fichier a été modifié ou supprimé. Elle n'est pas délivrée.",
    // lang/fr/pwa.php, pwa.comptabilite.motifs.*
    'pwa.comptabilite.motifs.journal_a_nouveaux_absent':
        "Les journaux de clôture (CL) et d'à-nouveaux (AN) ne sont pas tous deux au référentiel.",
    'pwa.comptabilite.motifs.comptes_de_resultat_absents':
        'Les comptes 131 et 139 ne sont pas tous deux au plan comptable.',
    'pwa.comptabilite.motifs.centre_de_cloture_absent':
        'Le centre de coût qui porte les écritures de clôture est absent.',
    'pwa.comptabilite.motifs.ecritures_en_brouillon':
        'Des écritures restent en brouillon.',
    'pwa.comptabilite.motifs.balance_desequilibree':
        "La balance générale n'est pas équilibrée.",
    'pwa.comptabilite.motifs.bilan_desequilibre':
        "Le bilan n'est pas équilibré.",
    'pwa.comptabilite.motifs.impot_non_comptabilise':
        "Aucun impôt sur le résultat n'est comptabilisé en classe 89.",
    // lang/fr/comptabilite_pwa.php — les gestes de l'onglet « Clôtures »
    'comptabilite_pwa.cloture_demarrer':
        'Démarrer la clôture de l’exercice :annee',
    'comptabilite_pwa.cloture_demarrer_note':
        'Les modules ne passent plus de pièce dans :annee (ventes, dépenses… vont dans l’exercice suivant, ouvert d’office) ; seules vos écritures d’inventaire y entrent encore.',
    'comptabilite_pwa.cloture_demarree':
        'Exercice :annee en clôture : les modules n’y passent plus de pièce.',
    'comptabilite_pwa.cloture_reprendre': 'Reprendre la saisie',
    'comptabilite_pwa.saisie_reprise':
        'Exercice :annee rouvert à la saisie des modules.',
    'comptabilite_pwa.cloture_definitive':
        'Clôturer définitivement l’exercice :annee',
    'comptabilite_pwa.cloture_definitive_note':
        'Solde les comptes de gestion (6, 7, 8) en 131 ou 139, reporte les comptes de bilan au journal AN du 1er janvier suivant, puis verrouille l’exercice.',
    'comptabilite_pwa.exercice_cloture':
        'Exercice :annee clôturé : comptes de gestion soldés, à-nouveaux reportés, exercice verrouillé.',
    'comptabilite_pwa.cloture_passee':
        'Clôturé le :date — pièce de clôture :cloture, à-nouveaux :an.',
    'comptabilite_pwa.reouvrir': 'Rouvrir l’exercice :annee',
    'comptabilite_pwa.reouvrir_note':
        'Réservé au comptable. Les pièces de clôture et d’à-nouveaux sont contre-passées (rien ne s’efface) et l’exercice repasse en clôture.',
    'comptabilite_pwa.reouvrir_motif': 'Motif de la réouverture',
    'comptabilite_pwa.reouvrir_reserve':
        'Seul le comptable peut rouvrir un exercice clôturé.',
    'comptabilite_pwa.exercice_rouvert':
        'Exercice :annee rouvert : il repasse en clôture.',
    'comptabilite_pwa.archive_ecran': 'Archive légale',
    'comptabilite_pwa.archive_ecran_note':
        'Fichier des écritures, balance et états de clôture (PDF), avec leur empreinte SHA-256. Format SYSCOHADA révisé ; le format exact attendu par la DGI reste à confirmer avec l’expert-comptable.',
    'comptabilite_pwa.archive_empreinte': 'Empreinte (SHA-256) :',
    'comptabilite_pwa.archive_telecharger': 'Télécharger l’archive (ZIP)',
    'comptabilite_pwa.archive_absente':
        'L’archive de cette clôture n’a pas été générée.',
    'comptabilite_pwa.archive_generer': 'Générer l’archive',
    'comptabilite_pwa.archive_generee':
        'Archive de clôture de l’exercice :annee générée.',
    'comptabilite_pwa.archive_titre': 'Archive de clôture — exercice :annee',
    'comptabilite_pwa.archive_section_cloture': 'Clôture',
    'comptabilite_pwa.archive_section_balance': 'Balance générale',
    'comptabilite_pwa.archive_section_resultat': 'Compte de résultat',
    'comptabilite_pwa.archive_section_bilan': 'Bilan',
    'comptabilite_pwa.archive_cloturee_le': 'Clôturé le',
    'comptabilite_pwa.archive_piece_cloture': 'Pièce de clôture (journal CL)',
    'comptabilite_pwa.archive_piece_a_nouveaux':
        'Pièce d’à-nouveaux (journal AN)',
    'comptabilite_pwa.archive_resultat': 'Résultat net de l’exercice',
    'comptabilite_pwa.archive_solde_debiteur': 'Solde débiteur',
    'comptabilite_pwa.archive_solde_crediteur': 'Solde créditeur',
    'comptabilite_pwa.archive_poste': 'Poste',
    'comptabilite_pwa.archive_brut': 'Brut',
    'comptabilite_pwa.archive_amortissement': 'Amort./Dépréc.',
    'comptabilite_pwa.archive_net': 'Net',
    'comptabilite_pwa.archive_total_actif': 'Total actif',
    'comptabilite_pwa.archive_total_passif': 'Total passif',
    'comptabilite_pwa.archive_visa_comptable': 'Visa du comptable',
    'comptabilite_pwa.col_compte': 'Compte',
    'comptabilite_pwa.col_libelle_ligne': 'Libellé de la ligne',
    'comptabilite_pwa.col_debit': 'Débit',
    'comptabilite_pwa.col_credit': 'Crédit',
    'comptabilite_pwa.totaux': 'Totaux',
  };

  /// La phrase de la clé [cle], variables remplacées. Une clé inconnue LÈVE.
  static String dire(String cle, [Map<String, String> variables = const {}]) {
    final gabarit = gabarits[cle];
    if (gabarit == null) {
      throw ArgumentError.value(
        cle,
        'cle',
        'Clé de langue de clôture inconnue.',
      );
    }
    return MessagesComptables.remplacer(gabarit, variables);
  }
}
