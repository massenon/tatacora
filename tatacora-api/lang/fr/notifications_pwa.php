<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| M12 — NOTIFICATIONS (PWA)
|--------------------------------------------------------------------------
|
| Maître : prototype_v2/pages/m12-notifications-hub.html
|          prototype_v2/assets/js/notifications-engine.js (registres)
|
| Les libellés rendus reprennent la casse et la ponctuation du maître,
| apostrophe typographique comprise : une apostrophe droite là où le maître
| pose une apostrophe courbe est un écart de gabarit comme un autre.
|
| Déclarations pour la garde des trois sources (t-trois-sources.js) — voir la
| vue et le composant, où chaque refus porte sa raison datée.
|
*/

return [

    // ------------------------------------------------------------- en-tête
    'titre' => 'Notifications',

    // ⚠ Le sous-titre du maître dit « Les messages sont réellement composés à
    // partir des données du jour ». C'est vrai de son moteur de démonstration
    // et FAUX ici : aucune composition n'a lieu côté serveur, et le recopier
    // annoncerait un travail qui n'est pas fait. Celui-ci dit ce que l'écran
    // tient réellement.
    'sous_titre' => 'Le référentiel des notifications : modèles de messages, événements déclencheurs '
        .'et canaux de diffusion. Relisez les textes avant que les canaux soient contractés.',

    // ------------------------------------------------------------- bandeau
    'bandeau_titre' => 'Seul l’e-mail peut réellement partir, et sous conditions.',
    'bandeau_texte' => 'WhatsApp, Android et SMS restent à transmettre à la main : aucun des trois n’est '
        .'contracté, ni configuré. Pour l’e-mail, l’envoi n’a lieu que si l’adresse du destinataire est connue '
        .'et qu’un relais SMTP réel est configuré ; sinon le message reste en file, avec la raison affichée.',

    // -------------------------------------------------------------- onglets
    'onglet_file' => 'File d’attente',
    'onglet_modeles' => 'Modèles',
    'onglet_declencheurs' => 'Déclencheurs',
    'onglet_journal' => 'Journal',
    'onglet_canaux' => 'Canaux',

    // ---------------------------------------------------------------- KPI
    'kpis_accordeon' => 'Indicateurs des notifications',
    'kpis_aide' => 'Repliez la bande pour gagner de la hauteur de tableau.',

    'kpi_en_attente' => 'En file d’attente',
    'kpi_en_attente_detail' => 'Composés, prêts, non partis',
    'kpi_envoyes' => 'Réellement envoyés',
    'kpi_envoyes_detail' => 'E-mails partis',
    'kpi_traites' => 'Transmis à la main',
    'kpi_traites_detail' => 'Par un opérateur',
    'kpi_abandonnes' => 'Abandonnés',
    'kpi_abandonnes_detail' => 'Avec motif',
    'kpi_modeles' => 'Modèles actifs',
    'kpi_modeles_detail' => ':nombre déclencheurs',
    'kpi_canaux' => 'Canaux branchés',
    'kpi_canaux_detail' => 'Dépendances externes',

    // -------------------------------------------------------- onglet File d'attente
    'detecter_maintenant' => 'Détecter maintenant',
    'file_vide' => 'Aucun message en attente. Lancez « Détecter maintenant » pour composer les messages du jour.',
    'file_module' => 'Module :module',
    'file_non_envoye' => 'non envoyé',
    'file_envoyer' => 'Envoyer',
    'file_a_parametrer' => 'à paramétrer au déploiement',
    'file_sans_adresse' => 'Aucune adresse e-mail connue',
    'file_sans_configuration' => 'Aucun relais SMTP réel configuré',
    'file_transmis_bouton' => 'Transmis à la main',
    'file_abandonner_bouton' => 'Abandonner',
    'file_objet' => 'Objet : :objet',
    'file_meta' => ':longueur caractère(s):limite · composé le :date · réf. :reference',
    'file_meta_avec_limite' => ' / :limite',
    'detection_resultat' => ':nombre message(s) composé(s) — aucun n’est parti.',
    'detection_aucun' => 'Aucun nouvel événement à notifier.',

    // ------------------------------------------------------------ modale transmission
    'transmission_titre' => 'Message transmis hors du système',
    'transmission_texte' => 'Il sortira de la file, mais restera marqué « non envoyé par le système ». '
        .'Ce n’est pas le logiciel qui l’a fait partir : la distinction doit rester lisible à l’audit.',
    'transmission_champ' => 'Comment a-t-il été transmis ?',
    'transmission_confirmer' => 'Sortir de la file',
    'transmission_faite' => 'Message sorti de la file.',

    // ---------------------------------------------------------------- modale abandon
    'abandon_titre' => 'Abandonner ce message',
    'abandon_texte' => 'Il ne sera jamais envoyé. Le message reste au journal, marqué abandonné, avec son motif.',
    'abandon_champ' => 'Motif de l’abandon',
    'abandon_confirmer' => 'Abandonner',
    'abandon_fait' => 'Message abandonné.',

    // -------------------------------------------------------- onglet Journal (traitement)
    'journal_statut_traite' => 'Transmis à la main',
    'journal_statut_abandonne' => 'Abandonné',
    'col_par' => 'Par',
    'col_commentaire' => 'Commentaire',

    // ------------------------------------------------------------ filtres
    'recherche' => 'Destinataire, contenu, modèle…',
    'tous_canaux' => 'Tous les canaux',
    'tous_publics' => 'Tous les publics',
    'tous_etats' => 'Tous les états',
    'etat_actif' => 'Actifs',
    'etat_inactif' => 'Désactivés',
    'nouveau_modele' => '+ Modèle',
    'pdf' => 'PDF',
    'excel' => 'Excel',

    // ----------------------------------------------------------- onglet Modèles
    'modeles_titre' => 'Modèles de message',
    'modele_actif' => 'actif',
    'modele_desactive' => 'désactivé',
    'modele_objet' => 'Objet :',
    'modele_variables' => 'Variables disponibles :',
    'modele_activer' => 'Activer',
    'modele_desactiver' => 'Désactiver',
    'modele_modifier' => 'Modifier',
    'modele_declencheur_inconnu' => 'Événement hors registre — ce modèle n’est rattaché à aucun déclencheur connu.',
    'modele_variables_inconnues' => 'Variable(s) non résolue(s) : :variables — le message serait refusé.',
    'modele_trop_long' => ':longueur caractère(s) — le canal en accepte :limite.',
    'modele_longueur' => ':longueur caractère(s)',
    'modele_longueur_limite' => ':longueur caractère(s) / :limite',

    // ------------------------------------------------------ onglet Déclencheurs
    'declencheurs_titre' => 'Déclencheurs — :nombre événements du registre',
    'col_declencheur' => 'Déclencheur',
    'col_public' => 'Public',
    'col_module' => 'Module',
    'col_modeles' => 'Modèles',
    'col_variables' => 'Variables',

    'public.client' => 'Client',
    'public.personnel' => 'Salarié',
    'public.interne' => 'Équipe interne',

    'declencheur.sejour_demain.libelle' => 'Séjour — arrivée demain',
    'declencheur.sejour_demain.description' => 'Rappel la veille de l’arrivée, avec les informations d’accès.',
    'declencheur.sejour_depart.libelle' => 'Séjour — départ du jour',
    'declencheur.sejour_depart.description' => 'Remerciement au départ, avec le solde restant s’il y en a un.',
    'declencheur.creance_echue.libelle' => 'Créance échue — plus de 30 jours',
    'declencheur.creance_echue.description' => 'Relance amiable sur une créance que le moteur signale à relancer.',
    'declencheur.creance_douteuse.libelle' => 'Créance de plus de 90 jours',
    'declencheur.creance_douteuse.description' => 'Alerte au Gérant : une provision pour dépréciation est à envisager.',
    'declencheur.stock_sous_seuil.libelle' => 'Article sous le seuil d’alerte',
    'declencheur.stock_sous_seuil.description' => 'Alerte au magasinier, article par article.',
    'declencheur.depart_circuit_demain.libelle' => 'Circuit — départ demain',
    'declencheur.depart_circuit_demain.description' => 'Rappel aux clients inscrits, avec l’heure et le guide.',
    'declencheur.restitution_vehicule.libelle' => 'Véhicule — restitution du jour',
    'declencheur.restitution_vehicule.description' => 'Rappel de restitution, avec le solde éventuel.',
    'declencheur.bulletin_disponible.libelle' => 'Bulletin de paie disponible',
    'declencheur.bulletin_disponible.description' => 'Information au salarié : son bulletin du mois est établi.',
    'declencheur.echeance_vps.libelle' => 'Échéance VPS — le 10 du mois',
    'declencheur.echeance_vps.description' => 'Rappel au Comptable : le VPS est exigible au plus tard le 10.',

    // ----------------------------------------------------------- onglet Journal
    'journal_titre' => 'Journal — :nombre message(s)',
    'journal_reserve' => 'La colonne « Envoi système » dit « oui » uniquement pour un message que le '
        .'transport a réellement accepté — WhatsApp, Android et SMS restent « non » tant qu’aucun n’est branché.',
    'journal_vide' => 'Aucun message n’est encore parti. '
        .'Le journal se remplit dès qu’un e-mail est réellement délivré.',
    'col_date' => 'Date',
    'col_destinataire' => 'Destinataire',
    'col_canal' => 'Canal',
    'col_statut' => 'Statut',
    'col_envoi_systeme' => 'Envoi système',

    // ------------------------------------------------------------ onglet Canaux
    'canaux_titre' => 'Canaux de diffusion',
    'col_etat' => 'État',
    'col_blocage' => 'Ce qui bloque',
    'col_limite' => 'Limite',
    'col_cible' => 'Destinataire attendu',
    // « En file » (maitre, onglet Canaux) — rendue depuis le 02/09/2026 :
    // le decompte reel des messages composes en attente par canal.
    'col_enfile' => 'En file',
    'canal_branche' => 'branché',
    'canal_non_branche' => 'non branché',
    'canal_caracteres' => ':limite car.',

    'canal.whatsapp.libelle' => 'WhatsApp',
    'canal.whatsapp.blocage' => 'API WhatsApp Business non contractée — contrat commercial et numéro vérifié requis.',
    'canal.whatsapp.cible' => 'telephone',
    'canal.email.libelle' => 'E-mail',
    'canal.email.blocage' => 'Aucun relais SMTP réel configuré.',
    'canal.email.blocage_leve' => 'Envoi conditionné à une adresse connue pour chaque destinataire.',
    'canal.email.cible' => 'email',
    'canal.android.libelle' => 'Android (push)',
    'canal.android.blocage' => 'L’application Android n’est pas démarrée : aucun appareil n’est enregistré.',
    'canal.android.cible' => 'appareil',
    'canal.sms.libelle' => 'SMS',
    'canal.sms.blocage' => 'Aucun agrégateur SMS retenu.',
    'canal.sms.cible' => 'telephone',


    // ----------------------------------------------------------------- modale
    'modale_nouveau' => 'Nouveau modèle',
    'modale_modifier' => 'Modifier le modèle',
    'champ_declencheur' => 'Déclencheur',
    'champ_canal' => 'Canal',
    'champ_objet' => 'Objet',
    'champ_objet_aide' => '(e-mail et push)',
    'champ_message' => 'Message',
    'champ_actif' => 'Modèle actif — il sera pris en compte à la prochaine détection',
    'champ_variables' => 'Variables :',
    'enregistrer' => 'Enregistrer',

    // ------------------------------------------------------------- messages
    'modele_cree' => 'Modèle enregistré.',
    'modele_modifie' => 'Modèle enregistré.',
    'modele_active' => 'Modèle activé — il sera pris en compte à la prochaine détection.',
    'modele_desactive_fait' => 'Modèle désactivé.',
    'aucun_resultat' => 'Aucun résultat',
    'aucun_modele' => 'Aucun modèle ne correspond.',

    // ------------------------------------------------------------- refus
    'declencheur_inconnu' => 'Déclencheur hors registre : :code.',
    'canal_inconnu' => 'Canal hors registre : :code.',
    'contenu_vide' => 'Le contenu du message est obligatoire.',
    'modele_deja_pose' => 'Un modèle existe déjà pour cet événement et ce canal.',
    'export_vide' => 'Aucune ligne à exporter : la liste affichée est vide.',
    'variables_non_resolues' => 'Variable(s) non résolue(s) : :variables — le message n’est pas mis en file : '
        .'un client ne doit jamais lire une accolade.',
    'message_deja_traite' => 'Ce message a déjà été transmis ou abandonné.',
    'motif_abandon_requis' => 'Le motif de l’abandon est obligatoire.',
    'envoi_canal_non_supporte' => 'Seul le canal e-mail peut être envoyé automatiquement pour le moment.',
    'envoi_sans_adresse' => 'Aucune adresse e-mail connue pour ce destinataire — à transmettre à la main.',
    'envoi_sans_configuration' => 'Aucun relais SMTP réel n’est configuré — à transmettre à la main.',
    'envoi_echec' => 'L’envoi a échoué — le message reste en file, à transmettre à la main si besoin.',
    'envoi_reussi' => 'Message envoyé par e-mail.',

    // ------------------------------------------------------------ export
    'export_titre' => 'Exporter — :onglet',
    'filtre_onglet' => 'Onglet :',
    'filtre_recherche' => 'Recherche :',
    'filtre_canal' => 'Canal :',
];
