<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| M13 — PERSONNEL & PAIE (PWA)
|--------------------------------------------------------------------------
|
| Maître : prototype_v2/pages/m13-paie.html
|          prototype_v2/pages/m13-paie.js
|          prototype_v2/assets/js/paie-engine.js (forme du bulletin et du livre)
|
| ⚠ AUCUN TAUX N'EST ÉCRIT ICI. Les pourcentages qui apparaissent dans les
| libellés (« CNSS 3,6 % », « VPS 4 % ») sont le TEXTE du maître, affiché à
| côté d'un montant que `CalculPaieService` a calculé à partir de
| `parametres_systeme`. Un taux saisi dans un fichier de langue deviendrait la
| règle affichée pendant qu'une autre serait appliquée — le défaut le plus
| difficile à voir sur un bulletin.
|
*/

return [

    // Archivage du personnel — directive PO du 02/09/2026 : supprimer =
    // archiver (statut « parti », RG-15), derriere la bascule de suppression.
    'archivage' => [
        'action' => 'Archiver',
        'bouton_lot' => 'Archiver la sélection (:nombre)|Archiver la sélection (:nombre)',
        'selection_tout' => 'Sélectionner tout le personnel affiché',
        'selection_ligne' => 'Sélectionner cet employé',
        'modale_titre' => 'Archiver cet employé ?|Archiver ces :nombre employés ?',
        // Le PO dit « Supprimer », le dépôt archive (RG-15) : l'équivalence est
        // écrite ICI, en français simple, sur le seul écran qui décide.
        'modale_sous_titre' => "« Supprimer » veut dire archiver : le statut passe à « parti », "
            ."le salarié n'est pas effacé, sa fiche et ses bulletins restent lisibles.",
        'sans_bulletin' => ":noms n'a pas de bulletin sur :periode : une fois parti, la génération de bulletins l'ignorera. Établissez d'abord son solde de tout compte s'il est dû.|:noms n'ont pas de bulletin sur :periode : une fois partis, la génération de bulletins les ignorera. Établissez d'abord leurs soldes de tout compte s'ils sont dus.",
        'reversible' => "Réversible : la fiche de l'employé permet de repasser son statut à « actif ».",
        'confirmer' => 'Archiver|Archiver le lot',
        'succes' => ':nombre employé archivé.|:nombre employés archivés.',
    ],

    // ------------------------------------------------------------- en-tête
    'titre' => 'Personnel & Paie',
    'sous_titre' => 'CNSS 3,6 % salarié · ITS progressif · charges patronales CNSS 15,4 % + <strong>VPS 4 %</strong>. '
        .'Le net à payer est <strong>calculé</strong>, jamais saisi.',
    'periode' => 'Période',
    'excel' => 'Excel',
    'pdf' => 'PDF',

    // ------------------------------------------- bandeau permanent (PA-53)
    'rp_titre' => 'Charge patronale incomplète — un seul taux manque.',
    'rp_texte' => 'CNSS <strong>risques professionnels : 1 % à 4 %</strong> selon le niveau de risque de l’entreprise. '
        .'La catégorie applicable à l’hôtellerie-restauration n’est pas confirmée par la CNSS, et elle n’est pas '
        .'supposée ici : sur une masse salariale annuelle, l’écart entre 1 % et 4 % est un redressement. '
        // Article 8 (02/09/2026) : la reference PA-53 vit ici, jamais a l'ecran.
        .'Tous les coûts employeur sont donc affichés en <strong>fourchette</strong>. '
        .'CNSS pension 6,4 %, prestations familiales 9 % et VPS 4 % sont, eux, confirmés.',

    // --------------------------------------- référentiel de taux introuvable
    'referentiel_titre' => 'Les taux de paie ne sont pas paramétrés.',
    'referentiel_texte' => 'Aucun calcul n’est possible tant que les taux confirmés ne sont pas en base : '
        .':cles. Ils sont posés par le référentiel de paie, et un Administrateur peut les renseigner '
        .'depuis l’écran Paramètres. Aucune valeur n’est supposée à leur place — un taux plausible '
        .'inscrit quelque part deviendrait la règle de production, et personne ne le rouvrirait.',
    'referentiel_incomplet' => 'Les taux de paie ne sont pas paramétrés : :cles.',
    'referentiel_incomplet_court' => 'Les taux de paie ne sont pas paramétrés : aucun calcul n’est possible.',

    // -------------------------------------------------------------- onglets
    'onglet_personnel' => 'Personnel',
    'onglet_bulletins' => 'Bulletins de paie',
    'onglet_livre' => 'Livre de paie',
    'onglet_declarations' => 'Déclarations',
    'onglet_bareme' => 'Barèmes & taux',

    // ---------------------------------------------------------------- KPI
    'kpis_accordeon' => 'Indicateurs de la paie',
    'kpis_aide' => 'Repliez la bande pour gagner de la hauteur de tableau.',
    'kpi_effectif' => 'Effectif actif',
    'kpi_effectif_detail' => ':nombre au total',
    'kpi_masse' => 'Masse salariale',
    'kpi_masse_detail' => 'Salaires de base',
    'kpi_cout' => 'Coût employeur',
    'kpi_cout_detail' => 'à :montant',
    'kpi_net' => 'Net du mois',
    'kpi_net_detail' => ':nombre bulletin(s)',
    'kpi_vps' => 'VPS à reverser',
    'kpi_vps_detail' => '4 % — au plus tard le 10',
    'kpi_manquants' => 'Bulletins manquants',
    'kpi_manquants_cnss' => ':nombre sans n° CNSS',
    'kpi_manquants_ok' => 'Tous immatriculés',

    // ------------------------------------------------------------- filtres
    'recherche' => 'Nom, matricule, poste…',
    'tous_services' => 'Tous les services',
    'tous_contrats' => 'Tous les contrats',
    'statut_actifs' => 'Actifs',
    'statut_tous' => 'Tous',
    'statut_sortis' => 'Sortis',
    'statut_sans_cnss' => 'Sans n° CNSS',
    'nouvel_employe' => '+ Employé',

    // --------------------------------------------------- onglet « Personnel »
    'effectif_titre' => 'Effectif — :periode',
    'col_matricule' => 'Matricule',
    'col_employe' => 'Employé',
    'col_contrat' => 'Contrat',
    'col_embauche' => 'Embauche',
    'col_cnss' => 'N° CNSS',
    'col_salaire_base' => 'Salaire de base',
    'col_cout_employeur' => 'Coût employeur',
    'cnss_absent' => 'absent',
    'jusquau' => 'jusqu’au :date',
    'total_effectif' => 'TOTAL — :nombre employé(s)',
    'action_etablir' => 'Établir',
    'action_bulletin' => 'Bulletin',
    'action_modifier' => 'Modifier',
    'a_montant' => 'à :montant',

    // --------------------------------------------------- onglet « Bulletins »
    'bulletins_titre' => 'Bulletins — :periode',
    'bulletins_note_rp' => '* hors risques professionnels, taux non confirmé',
    'generer_manquants' => 'Générer les bulletins manquants (:nombre)',
    'col_brut' => 'Brut',
    'col_cnss_salarie' => 'CNSS 3,6 %',
    'col_its' => 'ITS',
    'col_autres_retenues' => 'Autres retenues',
    'col_net' => 'Net à payer',
    'col_charges_patronales' => 'Charges patronales',
    'action_voir' => 'Voir',
    'action_annuler' => 'Annuler',
    'bulletin_annule' => 'Annulé — :motif',
    'total_bulletins' => 'TOTAL — :nombre bulletin(s)',
    'aucun_bulletin' => 'Aucun bulletin sur :periode.',

    // ------------------------------------------------------ onglet « Livre »
    'livre_titre' => 'Livre de paie — :periode · :nombre salarié(s)',
    'col_rubrique' => 'Rubrique',
    'col_montant' => 'Montant',
    'livre_brut' => 'Salaires bruts soumis à cotisations',
    'livre_cnss' => 'CNSS — retenue salariale (3,6 %)',
    'livre_its' => 'ITS retenu à la source',
    'livre_autres' => 'Autres retenues (avances, oppositions)',
    'livre_net' => 'NET À PAYER AUX SALARIÉS',
    'livre_patronales' => 'Charges patronales',
    'livre_pension' => 'CNSS — pension employeur (6,4 %)',
    'livre_familiales' => 'CNSS — prestations familiales (9 %)',
    'livre_vps' => 'VPS — Versement Patronal sur Salaires (4 %)',
    'livre_rp' => 'CNSS — risques professionnels (1 % à 4 %)',
    'livre_total_confirmees' => 'Total charges patronales confirmées',
    'livre_cout' => 'COÛT TOTAL EMPLOYEUR',
    'livre_sans_cnss_titre' => ':nombre salarié(s) sans numéro CNSS.',
    'livre_sans_cnss_texte' => 'Leur bulletin est calculé, mais ils ne peuvent pas figurer à la déclaration. '
        .'Régularisez l’immatriculation avant l’échéance.',
    // Le tableau « Écriture comptable proposée » du maître : son squelette est
    // rendu, son corps est l'état vide ci-dessous — aucune pièce n'est
    // inventée (voir le refus daté dans la vue).
    'ecriture_titre' => 'Écriture comptable proposée',
    'col_compte' => 'Compte',
    'col_libelle' => 'Libellé',
    'col_debit' => 'Débit',
    'col_credit' => 'Crédit',
    'livre_ecriture_absente_titre' => 'Aucune écriture comptable n’est proposée ici.',
    'livre_ecriture_absente_texte' => 'La paie se comptabilise depuis l’écran Comptabilité, sur les montants de ce livre.',

    // ------------------------------------------------ onglet « Déclarations »
    'declarations_titre' => 'Déclarations sociales et fiscales — :periode',
    'col_declaration' => 'Déclaration',
    'col_objet' => 'Objet',
    'col_echeance' => 'Échéance',
    'col_etat' => 'État',
    'etat_arrete' => 'Montant arrêté',
    'etat_incomplet' => 'Incomplet',
    'declarations_note_rp' => '* hors risques professionnels',
    'declaration_cnss_libelle' => 'Cotisations CNSS (salariales + patronales)',
    'declaration_cnss_note' => 'Hors risques professionnels — taux non confirmé.',
    'declaration_vps_libelle' => 'Versement Patronal sur Salaires (4 %)',
    'declaration_vps_note' => 'Base brute sans plafond. Déclaration et paiement au plus tard le 10 du mois suivant.',
    'declaration_its_libelle' => 'Impôt sur les Traitements et Salaires retenu à la source',
    'declaration_its_note' => 'Reversé à la DGI.',
    'vps_encadre_titre' => 'VPS — Versement Patronal sur Salaires.',
    'vps_encadre_texte' => 'Taxe directe <strong>à la charge de l’employeur</strong>, assise sur le montant total des salaires bruts '
        .'<strong>sans plafond</strong>. Taux : <strong>4 %</strong> pour les entreprises ordinaires, 2 % pour les '
        .'structures d’enseignement privé — le Gîte relève du taux ordinaire. Déclaration et paiement mensuels, '
        .'au plus tard le <strong>10 du mois suivant</strong>. Elle n’est jamais retenue sur le salaire du salarié.',

    // ----------------------------------------------------- onglet « Barèmes »
    'bareme_titre' => 'Barème ITS / IR-PTS — progressif par tranches',
    'col_tranche' => 'Tranche de revenu imposable',
    'col_taux' => 'Taux',
    'col_impot_max' => 'Impôt maximal de la tranche',
    'col_cumul' => 'Cumul',
    'tranche_de_a' => 'de :plancher à :plafond',
    'bareme_au_dela' => 'au-delà de :plafond',
    'bareme_non_tranche' => 'non tranché',
    'bareme_refus' => 'Calcul refusé — deux sources divergent sur le haut de barème',

    'taux_titre' => 'Taux appliqués',
    'col_prelevement' => 'Prélèvement',
    'col_charge_de' => 'À la charge de',
    'col_base' => 'Base',
    'col_source' => 'Source',
    'charge_salarie' => 'Salarié',
    'charge_employeur' => 'Employeur',
    'base_brut' => 'Salaire brut',
    'base_imposable' => 'Brut − CNSS salarié',
    'base_sans_plafond' => 'Brut total, sans plafond',
    'source_confirme' => 'confirmé',
    'source_non_confirme' => 'non confirmé',
    'taux_cnss_salarie' => 'CNSS — pension',
    'taux_its' => 'ITS / IR-PTS',
    'taux_its_valeur' => 'barème progressif',
    'taux_pension' => 'CNSS — pension',
    'taux_familiales' => 'CNSS — prestations familiales',
    'taux_vps' => 'VPS — Versement Patronal sur Salaires',
    'taux_rp' => 'CNSS — risques professionnels',
    'taux_rp_valeur' => '1 % à 4 %',

    'simulateur_titre' => 'Simulateur',
    'simulateur_brut' => 'Salaire brut mensuel (FCFA)',
    'simulateur_retenues' => 'Retenues salariales',
    'simulateur_patronales' => 'Charges patronales confirmées',
    'simulateur_manque' => 'Ce qui manque',
    'simulateur_cnss' => 'CNSS 3,6 %',
    'simulateur_imposable' => 'Revenu imposable',
    'simulateur_its' => 'ITS',
    'simulateur_net' => 'Net à payer',
    'simulateur_pension' => 'CNSS pension 6,4 %',
    'simulateur_familiales' => 'Prestations familiales 9 %',
    'simulateur_vps' => 'VPS 4 %',
    'simulateur_total_confirme' => 'Total 19,4 %',
    'simulateur_rp_min' => 'Risques prof. à 1 %',
    'simulateur_rp_max' => 'Risques prof. à 4 %',
    'simulateur_ecart' => 'Écart mensuel',
    'simulateur_ecart_annuel' => 'Écart annuel',
    'simulateur_cout' => 'Coût employeur entre :min et :max.',
    'simulateur_refus' => 'Calcul refusé.',

    // ------------------------------------------------- modale « employé »
    'modale_nouvel_employe' => 'Nouvel employé',
    'modale_modifier_employe' => 'Modifier :matricule',
    'champ_nom' => 'Nom',
    'champ_prenoms' => 'Prénoms',
    'champ_poste' => 'Poste',
    'champ_service' => 'Service',
    'champ_contrat' => 'Contrat',
    'champ_embauche' => 'Embauche',
    'champ_fin_contrat' => 'Fin de contrat',
    'champ_numero_cnss' => 'Numéro CNSS',
    'champ_numero_cnss_aide' => 'Facultatif à l’embauche, indispensable pour déclarer.',
    'champ_numero_cnss_invite' => 'BJ-CNSS-0000000',
    'champ_salaire_base' => 'Salaire de base (FCFA)',
    'champ_statut' => 'Statut',
    // E-mail facultatif (28/10/2026) : l'intitulé est celui de `pwa.profil.email`; ces phrases
    // sont celles que le poste rejoue mot pour mot.
    'email_invalide' => 'Adresse email invalide.',
    'email_enregistre' => 'Adresse email enregistrée.',
    'apercu_cout' => 'Coût employeur :min à :max',
    'homonymes_un' => 'Un employé existant correspond déjà',
    'homonymes_plusieurs' => ':nombre employés existants correspondent',
    'homonymes_confirmer' => 'Il s’agit bien d’une <strong>personne différente</strong> — enregistrer quand même.',
    'homonymes_non_confirme' => 'Cet employé existe déjà. Cochez la case pour confirmer qu’il s’agit d’une personne différente.',
    'creer' => 'Créer',
    'enregistrer' => 'Enregistrer',

    // ---------------------------------------------- modale « établissement »
    'modale_etablir' => 'Établir le bulletin',
    'etablir_sous_titre' => ':employe · :periode',
    'etablir_rappel' => 'Salaire de base :montant — repris automatiquement.',
    'etablir_brut' => 'Brut soumis à cotisations',
    'etablir_cout' => 'Coût employeur',

    // ------------------------------------------------- modale « bulletin »
    'modale_bulletin' => 'Bulletin de paie',
    'bulletin_entete' => 'BULLETIN DE PAIE',
    'bulletin_etablissement' => 'TATACORA AFRIQUE — Gîte Chez Noël',
    'bulletin_ville' => 'Natitingou, Bénin',
    'bulletin_salarie' => 'Salarié',
    'bulletin_affectation' => 'Affectation',
    'bulletin_matricule' => 'Matricule :valeur',
    'bulletin_cnss' => 'N° CNSS :valeur',
    'bulletin_cnss_absent' => 'non communiqué',
    'bulletin_etabli_le' => 'Établi le :date',
    'col_designation' => 'Désignation',
    'col_gain' => 'Gain',
    'col_retenue' => 'Retenue',
    'bulletin_brut' => 'Salaire brut soumis à cotisations',
    'bulletin_cnss_salariale' => 'CNSS — cotisation salariale',
    'bulletin_imposable' => 'Revenu imposable (brut − CNSS)',
    'bulletin_its' => 'ITS — Impôt sur les Traitements et Salaires',
    'bulletin_autres' => 'Autres retenues',
    'bulletin_net' => 'NET À PAYER',
    'bulletin_patronales' => 'Charges patronales — à la charge de l’employeur, hors bulletin salarié',
    'bulletin_pension' => 'CNSS — pension (part employeur)',
    'bulletin_familiales' => 'CNSS — prestations familiales',
    'bulletin_vps' => 'VPS — Versement Patronal sur Salaires',
    'bulletin_rp' => 'CNSS — risques professionnels',
    'bulletin_cout_total' => 'Coût total employeur',
    'bulletin_note_rp' => 'Le taux de risques professionnels dépend du niveau de risque de l’entreprise et n’est pas '
        .'confirmé pour l’hôtellerie-restauration. Il n’est pas supposé : le coût est donné en '
        .'fourchette. Le VPS et les cotisations CNSS ci-dessus sont, eux, confirmés. '
        .'Le VPS est <strong>dû par l’employeur</strong> — il n’apparaît jamais en retenue sur salaire.',
    'bulletin_pied' => 'Les montants sont calculés, aucun n’est saisi. Document à conserver sans limitation de durée.',
    'imprimer' => 'Imprimer',
    'fermer' => 'Fermer',

    // ------------------------------------------------ modale « annulation »
    'modale_annulation' => 'Annuler ce bulletin',
    'annulation_message' => 'Le bulletin sort du livre de paie.',
    'annulation_detail' => 'Il est conservé et reste traçable : rien n’est effacé.',
    'champ_motif' => 'Motif de l’annulation',
    'annulation_confirmer' => 'Annuler le bulletin',

    // ------------------------------------------------------------- messages
    'employe_cree' => 'Employé :matricule créé.',
    'employe_modifie' => 'Employé mis à jour.',
    'bulletin_etabli' => 'Bulletin :numero établi — net :net.',
    'bulletins_generes' => ':nombre bulletin(s) établi(s).',
    'bulletins_aucun_manquant' => 'Tous les bulletins sont déjà établis.',
    'bulletin_annule_fait' => 'Bulletin annulé.',
    'aucun_resultat' => 'Aucun résultat',
    'aucun_employe' => 'Aucun employé ne correspond à ces critères.',

    // ---------------------------------------------------------------- refus
    'service_inconnu' => 'Le service désigné n’existe pas.',
    'contrat_inconnu' => 'Type de contrat hors registre : :code.',
    'statut_inconnu' => 'Statut hors registre : :code.',
    'periode_invalide' => 'Période invalide : :periode. Format attendu AAAA-MM.',
    'employe_parti' => ':nom a quitté l’entreprise : aucun bulletin ne peut être établi.',
    'motif_annulation_requis' => 'Le motif d’annulation est obligatoire.',
    'bulletin_deja_annule' => 'Ce bulletin est déjà annulé.',
    'export_vide' => 'Aucune ligne à exporter : la liste affichée est vide.',

    // ---------------------------------------------------------------- export
    // Colonnes que le maître n'écrit qu'à l'export (`etatCourant()`,
    // m13-paie.js l.853-901) — les pourcentages sont le TEXTE du maître, pas
    // des taux appliqués (voir l'avertissement en tête de ce fichier). La
    // colonne des risques professionnels porte « (non confirmé) » comme au
    // maître : elle rend une fourchette, jamais un taux supposé (PA-53).
    'col_note' => 'Note',
    'col_prest_fam' => 'Prest. fam. 9 %',
    'col_rp_non_confirme' => 'Risques prof. (non confirmé)',
    'export_titre' => 'Exporter — :onglet',
    'filtre_periode' => 'Période :',
    'filtre_onglet' => 'Onglet :',
    'filtre_recherche' => 'Recherche :',
    'filtre_service' => 'Service :',
];
