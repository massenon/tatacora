/// Ramene un fichier de base au schema d'une version ANTERIEURE.
///
/// ## Pourquoi ce fichier existe
///
/// Une fixture de migration ne peut pas partir d'une vraie base ancienne : il
/// n'y en a plus. Elle part donc d'un fichier neuf — que Drift cree avec la
/// definition **courante** des tables — et le ramene en arriere. C'est plus
/// fidele que de transcrire un vieux schema a la main, mais cela porte un
/// piege : tout ce que les versions posterieures ont ajoute est **deja la**.
///
/// Le piege s'est referme deux fois. A la v6, `m.addColumn(paniers.tableId)`
/// a echoue sur « duplicate column name » (PA-108, cote production ET cote
/// fixtures). A la v7, les quatre fixtures de migration du depot sont tombees
/// ensemble sur « duplicate column name: type_client » : chacune retirait a la
/// main les ajouts qu'elle connaissait, et aucune ne pouvait connaitre ceux
/// qui viendraient apres elle.
///
/// La cause n'est pas l'oubli mais la **duplication** : cinq listes ecrites a
/// cinq endroits, qu'une nouvelle version oblige a modifier toutes les cinq.
/// Elles sont ici, une fois. Ajouter une version au schema, c'est ajouter son
/// entree a [_ajoutsParVersion] — et les fixtures suivent sans etre touchees.
///
/// ## Ce que ce fichier ne fait PAS
///
/// Il ne restitue pas les donnees d'une ancienne version, et n'essaie pas :
/// une colonne retiree perd son contenu, definitivement. Les fixtures sement
/// donc **apres** l'appel, au format de la version visee.
library;

import 'package:tatacora_flutter/core/database/app_database.dart';

/// Ce que chaque version AJOUTE, exprime par ce qu'il faut defaire pour
/// revenir a la version precedente.
///
/// L'ordre a l'interieur d'une entree est celui de l'annulation, pas celui de
/// la migration : on retire les colonnes d'une table avant la table elle-meme.
/// Les six tables que la v15 AJOUTE (M10 Comptabilite, moteur local). Les
/// tests de retour arriere qui traversent la v15 s'y referent : une liste
/// ecrite a chaque endroit divergerait au premier ajout (PA-109).
const tablesAjouteesEnV15 = <String>{
  'centres_cout_local',
  'journaux_local',
  'plan_comptable_local',
  'exercices_local',
  'ecritures_local',
  'sequences_piece_local',
};

/// La table que la v17 AJOUTE (sessions de caisse, réplique du serveur). Même
/// raison que [tablesAjouteesEnV15] : les tests qui traversent la v17 s'y
/// réfèrent, une liste écrite à chaque endroit divergerait (PA-109).
const tablesAjouteesEnV17 = <String>{'sessions_caisse_local'};

/// La table que la v18 AJOUTE (encaissement de facture, réplique du serveur).
/// Même raison que [tablesAjouteesEnV15] et [tablesAjouteesEnV17].
const tablesAjouteesEnV18 = <String>{'paiements_facture_local'};

/// La table que la v20 AJOUTE (règlement fournisseur, réplique du serveur).
/// Même raison que [tablesAjouteesEnV15], [tablesAjouteesEnV17] et
/// [tablesAjouteesEnV18].
const tablesAjouteesEnV20 = <String>{'reglements_fournisseur_local'};

/// La table que la v22 AJOUTE (état « vu » des alertes, lot B du 14/10/2026).
const tablesAjouteesEnV22 = <String>{'alertes_vues_local'};

/// La table que la v23 AJOUTE (séjours, lot C du 14/10/2026, D408).
const tablesAjouteesEnV23 = <String>{'sejours_local'};

/// La table que la v24 AJOUTE (rôles, 14/10/2026, D438).
const tablesAjouteesEnV24 = <String>{'roles_local'};

/// La table que la v25 AJOUTE (boîte d'envoi de « Contactez l'éditeur »,
/// 14/10/2026).
const tablesAjouteesEnV25 = <String>{'messages_editeur_local'};

/// La table que la v26 AJOUTE (file d'envoi du poste, lot F1 du 15/10/2026).
const tablesAjouteesEnV26 = <String>{'operations_sync_local'};

/// Les tables que la v27 AJOUTE (descente du catalogue, lot F2b du
/// 15/10/2026).
const tablesAjouteesEnV27 = <String>{
  'etat_synchronisation_local',
  'correspondances_sync_local',
};

/// La table que la v28 AJOUTE (origine des documents descendus, lot F4 du
/// 17/10/2026).
const tablesAjouteesEnV28 = <String>{'origines_documents_local'};

/// La table que la v29 AJOUTE (occupation des tables par les autres postes,
/// lot F6 du 18/10/2026).
const tablesAjouteesEnV29 = <String>{'occupations_tables_local'};

/// La table que la v31 AJOUTE (retraits de la carte du jour, 21/10/2026).
const tablesAjouteesEnV31 = <String>{'indisponibilites_carte_local'};

/// La table que la v32 AJOUTE (entretiens de véhicules, 21/10/2026).
const tablesAjouteesEnV32 = <String>{'entretiens_vehicule_local'};

/// Les tables que la v33 AJOUTE (plannings et congés, 21/10/2026).
const tablesAjouteesEnV33 = <String>{'plannings_local', 'conges_local'};

/// La table que la v34 AJOUTE (écritures validées du serveur, 21/10/2026).
const tablesAjouteesEnV34 = <String>{'ecritures_serveur_local'};

/// Les tables que la v35 AJOUTE (21/10/2026).
const tablesAjouteesEnV35 = <String>{
  'immobilisations_local',
  'relances_clients_local',
  'inventaires_local',
  'lignes_inventaire_local',
  'canaux_reservation_local',
};

/// La table que la v37 AJOUTE (journal de réception du poste, 26/10/2026).
const tablesAjouteesEnV37 = <String>{'journal_reception_local'};

/// La table que la v38 AJOUTE (historique des prix de la carte, 26/10/2026).
const tablesAjouteesEnV38 = <String>{'historique_prix_carte_local'};

/// La table que la v39 AJOUTE (boîte d'envoi des e-mails, 26/10/2026).
const tablesAjouteesEnV39 = <String>{'boite_envoi_emails_local'};

/// La table que la v40 AJOUTE (clôtures d'exercice du poste, 26/10/2026).
const tablesAjouteesEnV40 = <String>{'clotures_exercices_local'};

const _ajoutsParVersion = <int, List<String>>{
  // La v42 (27/10/2026, le recu en image d'une depense) ajoute SIX colonnes
  // nullables a `depenses_local`, aucune table, ni indexees ni referencees :
  // retour arriere symetrique.
  42: <String>[
    'ALTER TABLE depenses_local DROP COLUMN recu_nom',
    'ALTER TABLE depenses_local DROP COLUMN recu_sha256',
    'ALTER TABLE depenses_local DROP COLUMN recu_taille',
    'ALTER TABLE depenses_local DROP COLUMN recu_type',
    'ALTER TABLE depenses_local DROP COLUMN recu_statut',
    'ALTER TABLE depenses_local DROP COLUMN recu_cause',
  ],

  // La v41 (27/10/2026, les champs du web que le poste ne portait pas) ajoute DIX
  // colonnes nullables, aucune table, ni indexees ni referencees : retour arriere
  // symetrique.
  41: <String>[
    'ALTER TABLE vehicules_local DROP COLUMN annee',
    'ALTER TABLE vehicules_local DROP COLUMN capacite',
    'ALTER TABLE vehicules_local DROP COLUMN transmission',
    'ALTER TABLE contrats_location_local DROP COLUMN numero',
    'ALTER TABLE contrats_location_local DROP COLUMN remise',
    'ALTER TABLE contrats_location_local DROP COLUMN acompte',
    'ALTER TABLE contrats_location_local DROP COLUMN montant',
    'ALTER TABLE plats_local DROP COLUMN categorie',
    'ALTER TABLE guides_local DROP COLUMN certification',
    'ALTER TABLE guides_local DROP COLUMN tarif_jour',
  ],

  // La v40 (26/10/2026, la cloture annuelle sur le poste) ajoute UNE table
  // neuve : ses cles etrangeres (exercices, utilisateurs) pointent vers des
  // tables qui existent deja, rien ne la reference — retour arriere symetrique.
  40: <String>['DROP TABLE clotures_exercices_local'],

  // La v39 (26/10/2026, l'envoi reel d'e-mails) ajoute UNE table neuve, sans
  // cle etrangere : retour arriere symetrique.
  39: <String>['DROP TABLE boite_envoi_emails_local'],

  // La v38 (26/10/2026, « le poste fait ce que le web fait ») ajoute UNE table
  // neuve et SIX colonnes nullables, ni indexees ni referencees : retour
  // arriere symetrique (les colonnes d'une table avant la table elle-meme n'a
  // pas lieu d'etre ici, aucune de ces tables n'est retiree par la v38).
  38: <String>[
    'DROP TABLE historique_prix_carte_local',
    'ALTER TABLE contrats_location_local DROP COLUMN statut',
    'ALTER TABLE operations_sync_local DROP COLUMN auteur_login',
    'ALTER TABLE operations_sync_local DROP COLUMN poste_nom',
    'ALTER TABLE paniers_local DROP COLUMN numero_vente',
    'ALTER TABLE paniers_local DROP COLUMN auteur_login',
  ],

  // La v37 (journal de reception, 26/10/2026) ajoute UNE table neuve, sans
  // index ni cle etrangere : retour arriere symetrique.
  37: <String>['DROP TABLE journal_reception_local'],

  // La v36 (lien direct plat -> article, 21/10/2026) AJOUTE deux colonnes
  // nullables a `plats_local`, ni indexees ni referencees : retour symetrique.
  36: <String>[
    'ALTER TABLE plats_local DROP COLUMN article_id',
    'ALTER TABLE plats_local DROP COLUMN unites_vendables',
  ],

  // La v35 ajoute CINQ tables neuves et CINQ colonnes (sans index ni cle
  // etrangere) : retour arriere symetrique.
  35: <String>[
    'DROP TABLE immobilisations_local',
    'DROP TABLE relances_clients_local',
    'DROP TABLE inventaires_local',
    'DROP TABLE lignes_inventaire_local',
    'DROP TABLE canaux_reservation_local',
    'ALTER TABLE articles_local DROP COLUMN actif',
    'ALTER TABLE clients_local DROP COLUMN actif',
    'ALTER TABLE recettes_local DROP COLUMN composition_provisoire',
    'ALTER TABLE paniers_local DROP COLUMN remise_type',
    'ALTER TABLE paniers_local DROP COLUMN remise_valeur_centiemes',
  ],

  // La v34 ajoute UNE table neuve, sans index ni cle etrangere.
  34: <String>['DROP TABLE ecritures_serveur_local'],

  // La v33 ajoute DEUX tables neuves, sans index ni cle etrangere.
  33: <String>['DROP TABLE plannings_local', 'DROP TABLE conges_local'],

  // La v32 ajoute UNE table neuve, sans index ni cle etrangere.
  32: <String>['DROP TABLE entretiens_vehicule_local'],

  // La v31 (retraits de la carte du jour, 21/10/2026) ajoute UNE table neuve,
  // sans index ni cle etrangere : retour arriere symetrique.
  31: <String>['DROP TABLE indisponibilites_carte_local'],

  // La v30 (facteur de conversion des boissons, 21/10/2026) AJOUTE une colonne
  // nullable à `cartes_boisson_local` : retour arriere symetrique, la colonne
  // n'est ni indexee ni referencee.
  30: <String>['ALTER TABLE cartes_boisson_local DROP COLUMN unites_vendables'],

  // La v29 (occupation des tables, lot F6 du 18/10/2026) ajoute UNE table
  // neuve, sans index ni cle etrangere : retour arriere symetrique.
  29: <String>['DROP TABLE occupations_tables_local'],

  // La v28 (origine des documents descendus, lot F4 du 17/10/2026) ajoute UNE
  // table neuve, sans index ni cle etrangere, et ne touche rien d'existant :
  // son retour arriere est symetrique. Les lignes sont perdues : la fixture
  // seme APRES l'appel.
  28: <String>['DROP TABLE origines_documents_local'],

  // La v27 (descente du catalogue, lot F2b du 15/10/2026) ajoute DEUX tables
  // neuves, sans index declare, et ne touche rien d'existant : son retour
  // arriere est symetrique. Aucune cle etrangere ne pointe vers elles, elles
  // n'en portent aucune. Les lignes sont perdues : la fixture seme APRES
  // l'appel.
  27: <String>[
    'DROP TABLE correspondances_sync_local',
    'DROP TABLE etat_synchronisation_local',
  ],

  // La v26 (file d'envoi, lot F1 du 15/10/2026) ajoute UNE table neuve et ses
  // deux index, et ne touche rien d'existant : son retour arriere est
  // symetrique. Aucune cle etrangere ne pointe vers elle, elle n'en porte
  // aucune ; le DROP emporte ses index. Les lignes sont perdues : la fixture
  // seme APRES l'appel.
  26: <String>['DROP TABLE operations_sync_local'],

  // La v25 (boite d'envoi de « Contactez l'editeur », 14/10/2026) ajoute UNE
  // table neuve et ne touche rien d'existant : son retour arriere est
  // symetrique. Sa cle etrangere pointe VERS `utilisateurs_local`, aucune ne
  // pointe vers elle : le DROP est direct. Les lignes sont perdues : la
  // fixture seme APRES l'appel.
  25: <String>['DROP TABLE messages_editeur_local'],

  // La v24 (roles, 14/10/2026, D438) ajoute UNE table neuve et ne touche rien
  // d'existant : son retour arriere est symetrique. Aucune cle etrangere ne
  // pointe vers elle (le rattachement d'un compte passe par le LIBELLE du role,
  // pas par une cle) : le DROP est direct. Les lignes sont perdues : la fixture
  // seme APRES l'appel.
  24: <String>['DROP TABLE roles_local'],

  // La v23 (sejours, lot C du 14/10/2026) ajoute UNE table neuve et ne touche
  // rien d'existant : son retour arriere est symetrique. Elle porte une cle
  // etrangere VERS `reservations_local`, aucune ne pointe vers elle : le DROP
  // est direct. Les lignes sont perdues : la fixture seme APRES l'appel.
  23: <String>['DROP TABLE sejours_local'],

  // La v22 (etat « vu » des alertes, lot B du 14/10/2026) ajoute UNE table
  // neuve, referencant `utilisateurs_local`, referencee par rien : symetrique.
  22: <String>['DROP TABLE alertes_vues_local'],

  // La v21 (archivage d'un fournisseur, lot 7) AJOUTE une colonne a
  // `fournisseurs_local` (`actif`, BOOLEAN NOT NULL DEFAULT 1 avec son CHECK de
  // colonne) et AUCUNE table. `DROP COLUMN` est admis : la colonne n'est ni
  // indexee, ni referencee, et son CHECK lui est propre. Les donnees qu'elle
  // portait sont perdues, comme pour toute annulation d'ajout : la fixture seme
  // APRES l'appel.
  21: <String>['ALTER TABLE fournisseurs_local DROP COLUMN actif'],

  // La v20 (règlement fournisseur, lot 7) ajoute UNE table neuve et ne touche
  // rien d'existant : son retour arriere est symetrique. Les lignes qu'elle
  // porte sont perdues, comme pour toute annulation d'ajout : la fixture seme
  // APRES l'appel. Aucune cle etrangere ne pointe VERS elle (rien d'autre ne la
  // reference sur ce poste), le DROP est donc direct.
  20: <String>['DROP TABLE reglements_fournisseur_local'],

  // La v19 (annulation avec commission et remboursement, lot 6) AJOUTE huit
  // colonnes NULLABLES a `reservations_local` et AUCUNE table. Les deux
  // premieres a retirer portent une cle etrangere (`utilisateur_annulation_id`,
  // `ecriture_remboursement_id`) : elles partent d'abord, comme la colonne de la
  // v18 — c'est verifie par les tests de migration v18 -> v19, qui franchissent
  // cette annulation. Les donnees qu'elles portaient sont perdues, comme pour
  // toute annulation d'ajout : la fixture seme APRES l'appel.
  19: <String>[
    'ALTER TABLE reservations_local DROP COLUMN ecriture_remboursement_id',
    'ALTER TABLE reservations_local DROP COLUMN utilisateur_annulation_id',
    'ALTER TABLE reservations_local DROP COLUMN date_annulation',
    'ALTER TABLE reservations_local DROP COLUMN mode_saisie_remboursement',
    'ALTER TABLE reservations_local '
        'DROP COLUMN montant_rembourse_annulation_centimes',
    'ALTER TABLE reservations_local '
        'DROP COLUMN montant_commission_annulation_centimes',
    'ALTER TABLE reservations_local '
        'DROP COLUMN montant_total_annulation_centimes',
    'ALTER TABLE reservations_local DROP COLUMN taux_annulation_centiemes',
  ],

  // La v18 (encaissement de facture, lot 5) AJOUTE une table neuve
  // (`paiements_facture_local`) ET une colonne a `paniers_local`
  // (`session_encaissement_id`, le `ventes.session_id` du serveur). La table
  // d'abord : rien d'autre ne la reference, le DROP est direct. La colonne
  // ensuite : elle porte une cle etrangere vers `sessions_caisse_local`, et
  // SQLite refuse `DROP COLUMN` d'une colonne contrainte — c'est verifie par
  // les tests de migration v17 -> v18, qui franchissent cette annulation.
  18: <String>[
    'DROP TABLE paiements_facture_local',
    'ALTER TABLE paniers_local DROP COLUMN session_encaissement_id',
  ],

  // La v17 (sessions de caisse, reprise locale) ajoute UNE table neuve et ne
  // touche rien d'existant : son retour arriere est symetrique. Les lignes
  // qu'elle porte sont perdues, comme pour toute annulation d'ajout : la
  // fixture seme APRES l'appel. Aucune cle etrangere ne pointe VERS elle (rien
  // d'autre ne la reference sur ce poste), le DROP est donc direct.
  17: <String>['DROP TABLE sessions_caisse_local'],

  // La v16(M10 Depenses, piece comptable) AJOUTE deux colonnes a
  // `depenses_local` (`ecriture_id`, `ecriture_refus`), qui existe depuis la
  // v10. Aucune table neuve.
  //
  // ⚠ Elle ne se defait pas par `ALTER TABLE ... DROP COLUMN` : SQLite refuse
  // de retirer une colonne portant une cle etrangere (`ecriture_id`). Les deux
  // tables sont donc RECREEES a leur definition v15 — copiee ici, parce qu'une
  // fixture ne peut pas importer la definition courante (c'est tout le piege 3).
  // C'est sans perte pour la fixture : elle seme APRES l'appel. L'ordre est celui
  // de l'annulation : l'enfant (les lignes) avant le parent.
  16: <String>[
    'DROP TABLE lignes_depense_local',
    'DROP TABLE depenses_local',
    'CREATE TABLE depenses_local ('
        'id TEXT NOT NULL, '
        'date_transaction INTEGER NOT NULL, '
        'tresorerie TEXT NOT NULL, '
        'libelle TEXT NOT NULL, '
        "saisie_le INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "
        'PRIMARY KEY (id))',
    'CREATE TABLE lignes_depense_local ('
        'id TEXT NOT NULL, '
        'depense_id TEXT NOT NULL REFERENCES depenses_local (id), '
        'libelle TEXT NOT NULL, '
        'compte_charge TEXT NOT NULL, '
        'nature TEXT NOT NULL, '
        'famille TEXT NOT NULL, '
        'montant INTEGER NOT NULL, '
        "ajoutee_le INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "
        'PRIMARY KEY (id))',
  ],

  // La v15 (M10 Comptabilite, moteur local) ajoute SIX tables neuves et ne
  // touche rien d'existant : son retour arriere est symetrique. L'ordre est
  // celui de l'annulation, l'enfant avant le parent (cles etrangeres actives) :
  // les ecritures d'abord (elles referencent exercices, journaux, plan et
  // centres), puis la sequence (journaux), les exercices, le plan (centres),
  // les journaux et les centres. Les quatre triggers de RG-11 sont portes par
  // `ecritures_local` : ils disparaissent avec elle. Les lignes qu'elles
  // portent sont perdues, comme pour toute annulation d'ajout : la fixture seme
  // APRES l'appel.
  15: <String>[
    'DROP TABLE ecritures_local',
    'DROP TABLE sequences_piece_local',
    'DROP TABLE exercices_local',
    'DROP TABLE plan_comptable_local',
    'DROP TABLE journaux_local',
    'DROP TABLE centres_cout_local',
  ],

  // La v14 (M4 Restaurant, source locale) ajoute CINQ tables neuves et ne
  // touche rien d'existant : son retour arriere est symetrique. L'ordre est
  // celui de l'annulation, l'enfant avant le parent (cles etrangeres actives) :
  // la composition et les plats avant les fiches et les menus. Les lignes
  // qu'elles portent sont perdues, comme pour toute annulation d'ajout : la
  // fixture seme APRES l'appel.
  14: <String>[
    'DROP TABLE plats_local',
    'DROP TABLE ingredients_recette_local',
    'DROP TABLE recettes_local',
    'DROP TABLE menus_local',
  ],

  // La v13 (M7 Achats, source locale) ajoute CINQ tables neuves et ne touche
  // rien d'existant : son retour arriere est symetrique. L'ordre est celui de
  // l'annulation, l'enfant avant le parent (cles etrangeres actives). Les
  // lignes qu'elles portent sont perdues, comme pour toute annulation d'ajout :
  // la fixture seme APRES l'appel.
  13: <String>[
    'DROP TABLE lignes_bon_reception_local',
    'DROP TABLE bons_reception_local',
    'DROP TABLE lignes_commande_achat_local',
    'DROP TABLE commandes_achat_local',
    'DROP TABLE fournisseurs_local',
  ],

  // La v12 (M6 Stocks, source locale) AJOUTE sept colonnes aux trois tables de
  // stock, qui existent depuis la v1. Aucune table neuve.
  //
  // ⚠ Elle ne se defait pas par `ALTER TABLE ... DROP COLUMN` : SQLite refuse
  // de retirer une colonne portant une cle etrangere (`point_stockage_id`,
  // `utilisateur_id`). Les trois tables sont donc RECREEES a leur definition
  // v11 — copiee ici, parce qu'une fixture ne peut pas importer la definition
  // courante (c'est tout le piege 3). C'est sans perte pour la fixture : ces
  // tables n'ont aucune ligne a la v11 (PA-134), et la fixture seme APRES
  // l'appel. L'ordre est celui de l'annulation : l'enfant avant le parent.
  12: <String>[
    'DROP TABLE mouvements_stock_local',
    'DROP TABLE articles_local',
    'DROP TABLE points_stockage_local',
    'CREATE TABLE points_stockage_local ('
        'id TEXT NOT NULL, '
        'libelle TEXT NOT NULL, '
        'PRIMARY KEY (id))',
    'CREATE TABLE articles_local ('
        'id TEXT NOT NULL, '
        'libelle TEXT NOT NULL, '
        'categorie TEXT NOT NULL, '
        'unite_mesure TEXT NOT NULL, '
        'seuil_alerte REAL NOT NULL, '
        'PRIMARY KEY (id))',
    'CREATE TABLE mouvements_stock_local ('
        'id TEXT NOT NULL, '
        'article_id TEXT NOT NULL REFERENCES articles_local (id), '
        'point_id TEXT NOT NULL REFERENCES points_stockage_local (id), '
        'type_mouvement TEXT NOT NULL, '
        'quantite REAL NOT NULL, '
        'motif TEXT NOT NULL, '
        'date_mouvement INTEGER NOT NULL, '
        "statut_sync TEXT NOT NULL DEFAULT 'en_attente_synchronisation', "
        'PRIMARY KEY (id))',
  ],

  // La v11 ajoute UNE table neuve (`parametres_systeme_local`, source locale
  // de l'ecran Parametres) et ne touche rien d'existant : son retour arriere
  // est symetrique, et perd les parametres saisis (ce que toute annulation
  // d'ajout fait, et que la fixture seme donc APRES l'appel).
  11: <String>['DROP TABLE parametres_systeme_local'],

  // ⚠ La v10 est la SEULE version dont le retour arriere n'est PAS symetrique.
  //
  // Elle ajoute huit tables et une colonne — ce qui se defait — mais elle
  // SUPPRIME aussi `sync_queue` et `sync_conflict_local` (decision « zero
  // reseau » du 14/09/2026). Les recreer ici les rend VIDES : les operations
  // qu'elles portaient sont perdues, et aucune fixture ne peut les rendre.
  // C'est ecrit plutot que tu, pour qu'un lecteur ne prenne pas ce retour
  // arriere pour une reversibilite.
  //
  // Les deux definitions sont copiees de `sync_queue_table.dart` et
  // `sync_conflict_table.dart`, supprimes par la v10 : une fixture ne peut pas
  // importer ce qui n'existe plus.
  10: <String>[
    'DROP TABLE taux_paie_local',
    'DROP TABLE bulletins_paie_local',
    'DROP TABLE employes_local',
    'DROP TABLE services_rh_local',
    'DROP TABLE messages_notification_local',
    'DROP TABLE modeles_notification_local',
    'DROP TABLE lignes_depense_local',
    'DROP TABLE depenses_local',
    'ALTER TABLE circuits_local DROP COLUMN duree',
    'CREATE TABLE IF NOT EXISTS sync_queue ('
        'uuid_operation TEXT NOT NULL, '
        'table_cible TEXT NOT NULL, '
        'operation TEXT NOT NULL, '
        'charge_utile TEXT NOT NULL, '
        'cree_le INTEGER NOT NULL, '
        'tentatives INTEGER NOT NULL DEFAULT 0, '
        'motif_rejet TEXT, '
        'PRIMARY KEY (uuid_operation))',
    'CREATE TABLE IF NOT EXISTS sync_conflict_local ('
        'id TEXT NOT NULL, '
        'table_cible TEXT NOT NULL, '
        'enregistrement_id TEXT NOT NULL, '
        'version_locale TEXT NOT NULL, '
        'version_distante TEXT NOT NULL, '
        'detecte_le INTEGER NOT NULL, '
        'PRIMARY KEY (id))',
  ],

  // La v9 est une migration de DONNEES (prefixe des tables du restaurant,
  // « T » -> « R »). Elle n'ajoute aucune structure : revenir a la v8 ne
  // defait donc rien du schema. La ligne existe pour que la version soit
  // NOMMEE — une absence se lirait comme un oubli.
  9: <String>[],
  8: ['DROP TABLE lignes_reservation_local'],
  7: [
    'ALTER TABLE reservations_local DROP COLUMN type_client',
    'ALTER TABLE reservations_local DROP COLUMN canal',
    'ALTER TABLE reservations_local DROP COLUMN mode_paiement',
    'ALTER TABLE reservations_local DROP COLUMN remise_type',
    'ALTER TABLE reservations_local DROP COLUMN remise_valeur',
  ],
  6: [
    'ALTER TABLE paniers_local DROP COLUMN table_id',
    'ALTER TABLE paniers_local DROP COLUMN espace',
    'DROP TABLE tables_local',
  ],
  5: ['DROP TABLE utilisateurs_local'],
  4: [
    'DROP TABLE lignes_piece_facturation_local',
    'DROP TABLE pieces_facturation_local',
    'DROP TABLE sequences_facture_local',
  ],
  3: ['DROP TABLE lignes_panier_local', 'DROP TABLE paniers_local'],
  2: [
    'ALTER TABLE reservations_local DROP COLUMN reference',
    'ALTER TABLE reservations_local DROP COLUMN tarif_nuit',
    'ALTER TABLE reservations_local DROP COLUMN motif_rejet',
    'ALTER TABLE reservations_local DROP COLUMN motif_annulation',
  ],
};

/// Defait le schema jusqu'a [cible] et pose `user_version = cible`.
///
/// La base doit etre OUVERTE — donc avoir deja subi `onCreate` — et n'est pas
/// fermee ici : l'appelant seme ensuite ses lignes au format de [cible], puis
/// ferme. Rouvrir le fichier declenchera `onUpgrade` depuis [cible], qui est
/// tout l'objet de l'exercice.
Future<void> ramenerSchemaA(AppDatabase db, int cible) async {
  if (cible < 1 || cible >= db.schemaVersion) {
    throw ArgumentError.value(
      cible,
      'cible',
      'doit etre comprise entre 1 et ${db.schemaVersion - 1}',
    );
  }

  // Force l'ouverture reelle : sans elle, `onCreate` n'a pas encore tourne et
  // les ordres ci-dessous porteraient sur des tables inexistantes.
  await db.customStatement('SELECT 1');

  for (var version = db.schemaVersion; version > cible; version--) {
    final ordres = _ajoutsParVersion[version];
    if (ordres == null) {
      throw StateError(
        'La version $version du schema n a pas d entree dans '
        '_ajoutsParVersion : aucune fixture de migration ne peut la '
        'franchir. Ajouter son annulation dans retour_arriere_schema.dart.',
      );
    }
    for (final ordre in ordres) {
      await db.customStatement(ordre);
    }
  }

  await db.customStatement('PRAGMA user_version = $cible');
}
