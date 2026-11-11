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
        "Seul le comptable ou le gérant peut passer ou contre-passer l'affectation du résultat.",
    'comptabilite.affectation_exige_cloture':
        "L'exercice :annee n'est pas clôturé : son résultat ne peut pas être affecté avant sa clôture.",
    'comptabilite.affectation_resultat_nul':
        "Le résultat de l'exercice :annee est nul : il n'y a rien à affecter.",
    'comptabilite.affectation_deja_passee':
        "Le résultat de l'exercice :annee est déjà affecté (pièce :piece). Contre-passez cette affectation avant d'en passer une autre.",
    'comptabilite.affectation_date_invalide':
        "La date de l'approbation des comptes ou de la décision de l'exploitant « :date » n'est pas une date valide.",
    'comptabilite.affectation_date_hors_exercice':
        "La date de l'approbation des comptes ou de la décision de l'exploitant (:date) doit tomber dans l'exercice :annee, celui qui suit l'exercice clôturé.",
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
    'comptabilite.affectation_poste_compte_exploitant':
        "Compte de l'exploitant",
    'comptabilite.forme_juridique_entreprise_individuelle':
        'Entreprise individuelle',
    'comptabilite.forme_juridique_sarl': 'SARL',
    'comptabilite.forme_juridique_sa': 'SA',
    'comptabilite.affectation_ei_reserve_legale':
        "Une entreprise individuelle n'a pas de réserve légale : le montant de la réserve légale doit être nul. Ventilez entre le compte de l'exploitant, le report à nouveau et les autres réserves.",
    'comptabilite.affectation_ei_dividende':
        "Une entreprise individuelle ne verse pas de dividendes (compte 465) : le bénéfice revient à l'exploitant. Portez-le au compte de l'exploitant, au report à nouveau ou aux autres réserves.",
    'comptabilite.affectation_societe_compte_exploitant':
        "Le compte de l'exploitant n'existe que dans une entreprise individuelle : la forme juridique de l'établissement est « :forme ». Ventilez entre les postes d'une société.",
    'comptabilite.affectation_reserve_legale_insuffisante':
        "La réserve légale est obligatoire : elle doit recevoir au moins :minimum (10 % de :base, le bénéfice net des pertes antérieures de :pertes), tant qu'elle n'atteint pas 20 % du capital (:capital) ; la ventilation en prévoit :saisi.",
    'comptabilite.affectation_dividende_capitaux_propres':
        'La distribution de :dividendes ferait passer les capitaux propres à :apres, sous le capital augmenté des réserves non distribuables (:plancher) : un dividende ne peut pas entamer le capital ni les réserves que la loi interdit de distribuer.',
    'comptabilite.affectation_avertissement_capital_indetermine':
        "Le capital n'est pas déterminable (aucun solde créditeur au compte 101) : la réserve légale obligatoire ne peut pas être contrôlée et aucune n'est proposée. À vérifier avec le comptable avant de passer l'affectation.",
    'comptabilite.affectation_alerte_moitie_capital':
        "ALERTE : après cette perte, les capitaux propres (:propres) sont inférieurs à la moitié du capital (:capital). L'assemblée doit se prononcer dans les quatre mois sur la poursuite de l'activité (Acte uniforme, art. 664 : à faire confirmer par le comptable).",
    'comptabilite.affectation_contrepassation_exercice_non_ouvert':
        "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : l'exercice :suivant, qui la porte, est :statut. La contre-passation ne se passe que dans un exercice ouvert.",
    'comptabilite.affectation_contrepassation_date_hors_exercice':
        "La contre-passation se date du jour de la correction (:date) : elle doit tomber dans l'exercice :suivant, qui porte l'affectation.",
    'comptabilite.affectation_contrepassation_anterieure':
        "La contre-passation (:date) ne peut pas être datée avant la pièce d'affectation (:origine).",
    'comptabilite.affectation_dividende_regle':
        "L'affectation du résultat de l'exercice :annee ne peut pas être contre-passée : un dividende est déjà réglé en tout ou partie (:regle réglé sur :dividendes). Annulez d'abord le règlement du dividende, puis contre-passez l'affectation.",
    'comptabilite.affectation_reference_trop_longue':
        'La référence de la décision est limitée à :max caractères.',
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
        'Réserve légale obligatoire : au moins 10 % du bénéfice net des pertes antérieures, tant qu’elle n’atteint pas 20 % du capital. En dessous, l’affectation est refusée ; le report à nouveau reçoit le reste.',
    'comptabilite_pwa.affectation_reserve_plafond':
        'La réserve légale a atteint 20 % du capital : aucune réserve légale n’est due.',
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
        'Seul le comptable ou le gérant peut passer ou contre-passer l’affectation du résultat.',
    'comptabilite_pwa.affectation_non_affectable':
        'L’affectation se passe dans l’exercice :suivant, qui doit exister et être ouvert.',
    'comptabilite_pwa.affectation_faite':
        'Affectation du résultat de l’exercice :annee passée (pièce :piece).',
    'comptabilite_pwa.affectation_note_ei':
        'La clôture laisse le résultat en :compte ; l’exploitant en décide le sort (compte de l’exploitant, report à nouveau, réserves) : une entreprise individuelle n’a ni réserve légale, ni dividendes, ni assemblée. Une pièce du journal OD, datée de la décision de l’exploitant, est passée dans l’exercice :suivant ; elle est validée, donc immuable (on la corrige par contre-passation).',
    'comptabilite_pwa.affectation_forme': 'Forme juridique : :forme',
    'comptabilite_pwa.affectation_date_ei':
        'Date de la décision de l’exploitant',
    'comptabilite_pwa.affectation_contrepasser_reference':
        'Référence de la décision (PV d’assemblée / décision de l’exploitant)',
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
