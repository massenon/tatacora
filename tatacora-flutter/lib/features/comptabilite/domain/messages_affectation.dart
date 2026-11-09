/// Les phrases de l'AFFECTATION DU RÉSULTAT du poste — RECOPIÉES MOT POUR MOT du
/// serveur, clé par clé (09/11/2026, demande du PO : « ajoute l'affectation du
/// résultat »).
///
/// Les refus d'`AffectationResultatService` (`lang/fr/comptabilite.php`), les
/// libellés des pièces qu'il passe et la carte de l'onglet « Clôtures »
/// (`lang/fr/comptabilite_pwa.php`). `affectation_contre_serveur_test.dart`
/// EXÉCUTE PHP (`tool/comptabilite/rejouer_affectation.php`), relit chacune de
/// ces clés dans les fichiers de langue du serveur et exige l'égalité exacte.
///
/// Le remplacement des variables est celui de Laravel
/// (`MessagesComptables.remplacer`).
library;

import 'messages_comptables.dart';

abstract final class MessagesAffectation {
  /// Les gabarits bruts du serveur, `fichier.clé` -> texte.
  static const gabarits = <String, String>{
    // lang/fr/comptabilite.php
    'comptabilite.affectation_reservee':
        "Seul le comptable peut passer ou contre-passer l'affectation du résultat.",
    'comptabilite.affectation_exige_cloture':
        "L'exercice :annee n'est pas clôturé : son résultat ne peut pas être affecté avant sa clôture.",
    'comptabilite.affectation_resultat_nul':
        "Le résultat de l'exercice :annee est nul : il n'y a rien à affecter.",
    'comptabilite.affectation_deja_passee':
        "Le résultat de l'exercice :annee est déjà affecté (pièce :piece). Contre-passez cette affectation avant d'en passer une autre.",
    'comptabilite.affectation_date_invalide':
        "La date d'approbation des comptes « :date » n'est pas une date valide.",
    'comptabilite.affectation_date_hors_exercice':
        "La date d'approbation des comptes (:date) doit tomber dans l'exercice :annee, celui qui suit l'exercice clôturé.",
    'comptabilite.affectation_exercice_non_ouvert':
        "L'exercice :annee est :statut : l'affectation du résultat ne peut être passée que dans un exercice ouvert.",
    'comptabilite.affectation_montant_illisible':
        "Le montant de « :poste » n'est pas lisible (« :valeur ») : saisissez un nombre positif, deux décimales au plus.",
    'comptabilite.affectation_montant_negatif':
        'Le montant de « :poste » ne peut pas être négatif.',
    'comptabilite.affectation_dividende_sur_perte':
        'Aucun dividende ne se verse sur une perte : le résultat à affecter est une perte.',
    'comptabilite.affectation_reserve_legale_sur_perte':
        "Une perte ne s'affecte pas à la réserve légale : elle se reporte à nouveau ou s'impute sur les réserves.",
    'comptabilite.affectation_imputation_sur_benefice':
        "L'imputation sur le report à nouveau créditeur ne vaut que pour une perte.",
    'comptabilite.affectation_somme_differente':
        "La ventilation totalise :somme alors que le résultat à affecter est de :resultat (écart :ecart) : elle doit l'égaler exactement.",
    'comptabilite.affectation_imputation_excessive':
        "L'imputation sur « :poste » (:montant) dépasse son solde créditeur (:solde).",
    'comptabilite.affectation_centre_absent':
        "Le centre de coût « :centre » est introuvable : l'affectation du résultat ne peut pas être passée.",
    'comptabilite.affectation_motif':
        "Le motif de la contre-passation est obligatoire (:min caractères au moins) : il est écrit au journal d'audit et sur les contre-passations.",
    'comptabilite.affectation_aucune':
        "Le résultat de l'exercice :annee n'a aucune affectation active : il n'y a rien à contre-passer.",
    'comptabilite.affectation_contrepassation_exercice_clos':
        "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : l'exercice :suivant, qui la porte, est clôturé. Rouvrez d'abord :suivant.",
    'comptabilite.affectation_piece_divergente':
        "La pièce d'affectation envoyée par le poste ne correspond pas à celle que le serveur passerait pour cette ventilation : vérifiez la correspondance des comptes des deux côtés.",
    'comptabilite.affectation_poste_reserve_legale': 'Réserve légale',
    'comptabilite.affectation_poste_autres_reserves': 'Autres réserves',
    'comptabilite.affectation_poste_dividendes': 'Dividendes',
    'comptabilite.affectation_poste_report_a_nouveau': 'Report à nouveau',
    'comptabilite.affectation_poste_imputation_report_crediteur':
        'Imputation sur le report à nouveau créditeur',
    'comptabilite.libelle_affectation_resultat':
        "Affectation du résultat de l'exercice :annee",
    'comptabilite.libelle_contrepassation_affectation':
        "Contre-passation de l'affectation du résultat :annee — :motif",
    // lang/fr/comptabilite_pwa.php — la carte de l'onglet « Clôtures »
    'comptabilite_pwa.affectation_titre':
        'Affectation du résultat de l’exercice :annee',
    'comptabilite_pwa.affectation_note':
        'La clôture laisse le résultat en :compte ; l’assemblée qui approuve les comptes le ventile. Une pièce du journal OD, datée de l’approbation, est passée dans l’exercice :suivant ; elle est validée, donc immuable (on la corrige par contre-passation).',
    'comptabilite_pwa.affectation_resultat': 'Résultat à affecter',
    'comptabilite_pwa.affectation_resultat_benefice':
        'Bénéfice, compte :compte',
    'comptabilite_pwa.affectation_resultat_perte': 'Perte, compte :compte',
    'comptabilite_pwa.affectation_date': 'Date d’approbation des comptes',
    'comptabilite_pwa.affectation_ventilation': 'Ventilation',
    'comptabilite_pwa.affectation_ventilation_perte': 'Imputation de la perte',
    'comptabilite_pwa.affectation_total': 'Total ventilé',
    'comptabilite_pwa.affectation_reste': 'Reste à ventiler',
    'comptabilite_pwa.affectation_somme_ok':
        'La ventilation égale le résultat.',
    'comptabilite_pwa.affectation_somme_ecart':
        'La ventilation diffère du résultat de :ecart.',
    'comptabilite_pwa.affectation_reserve_proposee':
        'Proposition : 10 % du bénéfice en réserve légale, tant qu’elle n’atteint pas 20 % du capital. Modifiable, jamais bloquante ; le report à nouveau reçoit le reste.',
    'comptabilite_pwa.affectation_reserve_plafond':
        'La réserve légale a atteint 20 % du capital : aucune réserve légale n’est proposée.',
    'comptabilite_pwa.affectation_reserve_indeterminee':
        'Le capital n’est pas déterminable (aucun solde créditeur au compte 101) : aucune réserve légale n’est proposée.',
    'comptabilite_pwa.affectation_passer': 'Passer l’affectation',
    'comptabilite_pwa.affectation_confirmer_titre':
        'Passer l’affectation du résultat de l’exercice :annee ?',
    'comptabilite_pwa.affectation_confirmer_texte':
        'Une pièce de :montant sera passée au journal OD le :date. Elle sera validée donc immuable : seule une contre-passation la corrige.',
    'comptabilite_pwa.affectation_confirmer': 'Confirmer l’affectation',
    'comptabilite_pwa.affectation_annuler': 'Annuler',
    'comptabilite_pwa.affectation_passee':
        'Affectation passée le :date par :auteur (pièce n° :piece).',
    'comptabilite_pwa.affectation_passee_ventilation': ':poste : :montant',
    'comptabilite_pwa.affectation_contrepasser': 'Contre-passer l’affectation',
    'comptabilite_pwa.affectation_contrepasser_note':
        'Réservé au comptable. La pièce d’affectation est inversée (rien ne s’efface) ; le résultat pourra être affecté de nouveau.',
    'comptabilite_pwa.affectation_contrepasser_motif':
        'Motif de la contre-passation',
    'comptabilite_pwa.affectation_reserve_comptable':
        'Seul le comptable peut passer ou contre-passer l’affectation du résultat.',
    'comptabilite_pwa.affectation_non_affectable':
        'L’affectation se passe dans l’exercice :suivant, qui doit exister et être ouvert.',
    'comptabilite_pwa.affectation_faite':
        'Affectation du résultat de l’exercice :annee passée (pièce :piece).',
    'comptabilite_pwa.affectation_contrepassee':
        'Affectation du résultat de l’exercice :annee contre-passée.',
  };

  /// La phrase de la clé [cle], variables remplacées. Une clé inconnue LÈVE.
  static String dire(String cle, [Map<String, String> variables = const {}]) {
    final gabarit = gabarits[cle];
    if (gabarit == null) {
      throw ArgumentError.value(
        cle,
        'cle',
        "Clé de langue d'affectation inconnue.",
      );
    }
    return MessagesComptables.remplacer(gabarit, variables);
  }
}
