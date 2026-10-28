-- Schéma RÉEL v24 : commit 0d8d53eb0 (2026-10-14), construit avec le code de ce commit.
-- Généré par tool/migration/extraire_schemas_anciens.dart : ne pas éditer.
-- user_version: 24
-- ----
CREATE TABLE "utilisateurs_local" ("id" TEXT NOT NULL, "login" TEXT NOT NULL UNIQUE, "nom" TEXT NOT NULL, "role" TEXT NOT NULL, "droits_json" TEXT NOT NULL, "sel" TEXT NOT NULL, "empreinte" TEXT NOT NULL, "iterations" INTEGER NOT NULL, "actif" INTEGER NOT NULL DEFAULT 1 CHECK ("actif" IN (0, 1)), "date_creation" INTEGER NOT NULL, "date_mot_de_passe" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "clients_local" ("id" TEXT NOT NULL, "nom" TEXT NOT NULL, "prenom" TEXT NULL, "telephone" TEXT NOT NULL, "email" TEXT NULL, "type_client" TEXT NOT NULL, "solde" REAL NOT NULL DEFAULT 0.0, "statut_sync" TEXT NOT NULL DEFAULT 'synchronise', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "categories_hebergement_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "capacite_max" INTEGER NOT NULL, "tarif_base" REAL NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "unites_hebergement_local" ("id" TEXT NOT NULL, "categorie_id" TEXT NOT NULL REFERENCES categories_hebergement_local (id), "numero" TEXT NOT NULL, "statut" TEXT NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "exercices_local" ("id" TEXT NOT NULL, "annee" INTEGER NOT NULL UNIQUE, "date_debut" TEXT NOT NULL, "date_fin" TEXT NOT NULL, "statut" TEXT NOT NULL DEFAULT 'ouvert', "date_cloture" INTEGER NULL, "utilisateur_cloture_id" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"), CHECK (date_fin > date_debut), CHECK (statut IN ('ouvert', 'en_cloture', 'cloture')));
-- ----
CREATE TABLE "journaux_local" ("id" TEXT NOT NULL, "code" TEXT NOT NULL UNIQUE, "libelle" TEXT NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "centres_cout_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "type" TEXT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "plan_comptable_local" ("id" TEXT NOT NULL, "numero_compte" TEXT NOT NULL UNIQUE, "libelle" TEXT NOT NULL, "classe" TEXT NOT NULL, "nature" TEXT NULL, "centre_cout_defaut_id" TEXT NULL REFERENCES centres_cout_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "ecritures_local" ("id" TEXT NOT NULL, "exercice_id" TEXT NOT NULL REFERENCES exercices_local (id), "journal_id" TEXT NOT NULL REFERENCES journaux_local (id), "compte_id" TEXT NOT NULL REFERENCES plan_comptable_local (id), "centre_id" TEXT NOT NULL REFERENCES centres_cout_local (id), "date_ecriture" TEXT NOT NULL, "libelle" TEXT NOT NULL, "debit_centimes" INTEGER NOT NULL DEFAULT 0, "credit_centimes" INTEGER NOT NULL DEFAULT 0, "statut" TEXT NOT NULL DEFAULT 'brouillon', "ecriture_contrepassee_id" TEXT NULL REFERENCES ecritures_local (id), "numero_piece" TEXT NULL, "cree_le" INTEGER NOT NULL, "cree_par" TEXT NOT NULL REFERENCES utilisateurs_local (id), "modifie_le" INTEGER NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"), CHECK (debit_centimes >= 0 AND credit_centimes >= 0), CHECK (NOT (debit_centimes > 0 AND credit_centimes > 0)), CHECK (statut IN ('brouillon', 'validee')));
-- ----
CREATE TABLE "reservations_local" ("id" TEXT NOT NULL, "reference" TEXT NOT NULL, "client_id" TEXT NOT NULL REFERENCES clients_local (id), "unite_id" TEXT NOT NULL REFERENCES unites_hebergement_local (id), "date_arrivee" INTEGER NOT NULL, "date_depart" INTEGER NOT NULL, "statut" TEXT NOT NULL, "tarif_nuit" INTEGER NOT NULL, "acompte" REAL NOT NULL DEFAULT 0.0, "type_client" TEXT NULL, "canal" TEXT NULL, "mode_paiement" TEXT NULL, "remise_type" TEXT NULL, "remise_valeur" REAL NULL, "statut_sync" TEXT NOT NULL DEFAULT 'local', "motif_rejet" TEXT NULL, "motif_annulation" TEXT NULL, "taux_annulation_centiemes" INTEGER NULL, "montant_total_annulation_centimes" INTEGER NULL, "montant_commission_annulation_centimes" INTEGER NULL, "montant_rembourse_annulation_centimes" INTEGER NULL, "mode_saisie_remboursement" TEXT NULL, "date_annulation" INTEGER NULL, "utilisateur_annulation_id" TEXT NULL REFERENCES utilisateurs_local (id), "ecriture_remboursement_id" TEXT NULL REFERENCES ecritures_local (id), "date_creation_locale" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_reservation_local" ("id" TEXT NOT NULL, "reservation_id" TEXT NOT NULL REFERENCES reservations_local (id), "service" TEXT NOT NULL, "item_id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "prix_unitaire" INTEGER NOT NULL, "quantite" INTEGER NOT NULL, "ordre" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "factures_local" ("id" TEXT NOT NULL, "numero_mecef" TEXT NULL, "client_id" TEXT NOT NULL REFERENCES clients_local (id), "date_emission" INTEGER NOT NULL, "montant_ht" REAL NOT NULL, "montant_tva" REAL NOT NULL, "montant_ttc" REAL NOT NULL, "statut" TEXT NOT NULL, "statut_sync" TEXT NOT NULL DEFAULT 'synchronise', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_facture_local" ("id" TEXT NOT NULL, "facture_id" TEXT NOT NULL REFERENCES factures_local (id), "source_module" TEXT NOT NULL, "source_id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "quantite" REAL NOT NULL, "prix_unitaire" REAL NOT NULL, "montant" REAL NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "paiements_local" ("id" TEXT NOT NULL, "facture_id" TEXT NOT NULL REFERENCES factures_local (id), "mode_paiement" TEXT NOT NULL, "montant" REAL NOT NULL, "date_paiement" INTEGER NOT NULL, "statut_sync" TEXT NOT NULL DEFAULT 'synchronise', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "cartes_boisson_local" ("id" TEXT NOT NULL, "article_id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "categorie" TEXT NOT NULL, "prix_vente" REAL NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "ventes_bar_local" ("id" TEXT NOT NULL, "client_id" TEXT NULL, "date_vente" INTEGER NOT NULL, "montant" REAL NOT NULL, "statut_sync" TEXT NOT NULL DEFAULT 'en_attente_synchronisation', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_vente_bar_local" ("id" TEXT NOT NULL, "vente_id" TEXT NOT NULL REFERENCES ventes_bar_local (id), "boisson_id" TEXT NOT NULL REFERENCES cartes_boisson_local (id), "quantite" INTEGER NOT NULL, "prix_unitaire" REAL NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "points_stockage_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "type" TEXT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "articles_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "categorie" TEXT NOT NULL, "unite_mesure" TEXT NOT NULL, "seuil_alerte" REAL NOT NULL, "suivi" TEXT NOT NULL DEFAULT 'permanent', "point_stockage_id" TEXT NULL REFERENCES points_stockage_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "mouvements_stock_local" ("id" TEXT NOT NULL, "article_id" TEXT NOT NULL REFERENCES articles_local (id), "point_id" TEXT NOT NULL REFERENCES points_stockage_local (id), "type_mouvement" TEXT NOT NULL, "quantite" REAL NOT NULL, "motif" TEXT NOT NULL, "date_mouvement" INTEGER NOT NULL, "statut_sync" TEXT NOT NULL DEFAULT 'en_attente_synchronisation', "cout_unitaire_dix_milliemes" INTEGER NULL, "utilisateur_id" TEXT NULL REFERENCES utilisateurs_local (id), "rupture_forcee" INTEGER NOT NULL DEFAULT 0 CHECK ("rupture_forcee" IN (0, 1)), "ordre" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "vehicules_local" ("id" TEXT NOT NULL, "categorie" TEXT NOT NULL, "immatriculation" TEXT NOT NULL, "tarif_jour" REAL NOT NULL, "statut" TEXT NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "contrats_location_local" ("id" TEXT NOT NULL, "vehicule_id" TEXT NOT NULL REFERENCES vehicules_local (id), "client_id" TEXT NOT NULL REFERENCES clients_local (id), "guide_id" TEXT NULL, "date_debut" INTEGER NOT NULL, "date_fin" INTEGER NOT NULL, "chemin_piece_identite_local" TEXT NULL, "chemin_permis_conduire_local" TEXT NULL, "statut_upload_pieces" TEXT NOT NULL DEFAULT 'en_attente', "statut_sync" TEXT NOT NULL DEFAULT 'synchronise', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "circuits_local" ("id" TEXT NOT NULL, "nom" TEXT NOT NULL, "theme" TEXT NOT NULL, "zone" TEXT NOT NULL, "prix" REAL NOT NULL, "capacite_max" INTEGER NOT NULL, "duree" TEXT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "guides_local" ("id" TEXT NOT NULL, "nom" TEXT NOT NULL, "zone_competence" TEXT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "reservations_tour_local" ("id" TEXT NOT NULL, "circuit_id" TEXT NOT NULL REFERENCES circuits_local (id), "client_id" TEXT NOT NULL REFERENCES clients_local (id), "guide_id" TEXT NOT NULL REFERENCES guides_local (id), "date_circuit" INTEGER NOT NULL, "nb_participants" INTEGER NOT NULL, "statut" TEXT NOT NULL, "statut_sync" TEXT NOT NULL DEFAULT 'en_attente_synchronisation', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "tables_local" ("id" TEXT NOT NULL, "espace" TEXT NOT NULL, "numero" INTEGER NOT NULL, "libelle" TEXT NOT NULL, "places" INTEGER NOT NULL DEFAULT 4, "actif" INTEGER NOT NULL DEFAULT 1 CHECK ("actif" IN (0, 1)), "cree_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"), UNIQUE ("espace", "numero"));
-- ----
CREATE TABLE "sessions_caisse_local" ("id" TEXT NOT NULL, "point_vente" TEXT NOT NULL, "utilisateur_ouverture_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), "date_ouverture" INTEGER NOT NULL, "montant_fond_centimes" INTEGER NOT NULL, "date_cloture" INTEGER NULL, "montant_theorique_centimes" INTEGER NULL, "montant_constate_centimes" INTEGER NULL, PRIMARY KEY ("id"), CHECK (point_vente IN ('reception', 'restaurant', 'bar')));
-- ----
CREATE TABLE "paniers_local" ("id" TEXT NOT NULL, "type_vente" TEXT NOT NULL, "reservation_id" TEXT NULL REFERENCES reservations_local (id), "client_nom" TEXT NULL, "point_vente" TEXT NULL, "table_id" TEXT NULL REFERENCES tables_local (id), "espace" TEXT NULL, "date_depart_prevue" INTEGER NULL, "statut" TEXT NOT NULL DEFAULT 'ouvert', "ouvert_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "cloture_le" INTEGER NULL, "mode_paiement" TEXT NULL, "montant_cloture" INTEGER NULL, "motif_annulation" TEXT NULL, "session_encaissement_id" TEXT NULL REFERENCES sessions_caisse_local (id), "statut_transmission" TEXT NOT NULL DEFAULT 'non_transmissible', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_panier_local" ("id" TEXT NOT NULL, "panier_id" TEXT NOT NULL REFERENCES paniers_local (id), "module_source" TEXT NOT NULL, "code_article" TEXT NOT NULL, "libelle" TEXT NOT NULL, "prix_unitaire" INTEGER NOT NULL, "quantite" INTEGER NOT NULL, "categorie" TEXT NULL, "ajoutee_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "pieces_facturation_local" ("id" TEXT NOT NULL, "numero" TEXT NOT NULL UNIQUE, "origine" TEXT NOT NULL, "date_emission" INTEGER NOT NULL, "client_nom" TEXT NOT NULL, "client_id" TEXT NULL REFERENCES clients_local (id), "reservation_id" TEXT NULL REFERENCES reservations_local (id), "panier_id" TEXT NULL REFERENCES paniers_local (id), "mode_paiement" TEXT NULL, "point_vente" TEXT NULL, "numero_mecef" TEXT NULL, "statut" TEXT NOT NULL DEFAULT 'emise', "avoir_de" TEXT NULL REFERENCES pieces_facturation_local (numero), "motif_avoir" TEXT NULL, "motif_annulation" TEXT NULL, "date_annulation" INTEGER NULL, "statut_transmission" TEXT NOT NULL DEFAULT 'non_transmissible', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_piece_facturation_local" ("id" TEXT NOT NULL, "piece_id" TEXT NOT NULL REFERENCES pieces_facturation_local (id), "module_source" TEXT NOT NULL, "code_article" TEXT NULL, "libelle" TEXT NOT NULL, "prix_unitaire" INTEGER NOT NULL, "quantite" INTEGER NOT NULL, "ordre" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "sequences_facture_local" ("annee" INTEGER NOT NULL, "dernier_numero" INTEGER NOT NULL, PRIMARY KEY ("annee"));
-- ----
CREATE TABLE "depenses_local" ("id" TEXT NOT NULL, "date_transaction" INTEGER NOT NULL, "tresorerie" TEXT NOT NULL, "libelle" TEXT NOT NULL, "saisie_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "ecriture_id" TEXT NULL REFERENCES ecritures_local (id), "ecriture_refus" TEXT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_depense_local" ("id" TEXT NOT NULL, "depense_id" TEXT NOT NULL REFERENCES depenses_local (id), "libelle" TEXT NOT NULL, "compte_charge" TEXT NOT NULL, "nature" TEXT NOT NULL, "famille" TEXT NOT NULL, "montant" INTEGER NOT NULL, "ajoutee_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "modeles_notification_local" ("id" TEXT NOT NULL, "evenement" TEXT NOT NULL, "canal" TEXT NOT NULL, "objet" TEXT NULL, "contenu_template" TEXT NOT NULL, "actif" INTEGER NOT NULL DEFAULT 1 CHECK ("actif" IN (0, 1)), "cree_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "modifie_le" INTEGER NULL, PRIMARY KEY ("id"), UNIQUE ("evenement", "canal"));
-- ----
CREATE TABLE "messages_notification_local" ("id" TEXT NOT NULL, "modele_id" TEXT NOT NULL REFERENCES modeles_notification_local (id), "canal" TEXT NOT NULL, "reference" TEXT NOT NULL, "destinataire" TEXT NOT NULL, "objet" TEXT NULL, "contenu" TEXT NOT NULL, "longueur" INTEGER NOT NULL, "statut" TEXT NOT NULL DEFAULT 'en_attente', "commentaire" TEXT NULL, "motif_abandon" TEXT NULL, "traite_par" TEXT NULL, "compose_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "traite_le" INTEGER NULL, PRIMARY KEY ("id"), UNIQUE ("modele_id", "reference"));
-- ----
CREATE TABLE "services_rh_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "employes_local" ("id" TEXT NOT NULL, "matricule" TEXT NOT NULL, "nom" TEXT NOT NULL, "prenom" TEXT NOT NULL DEFAULT '', "poste" TEXT NOT NULL, "service_id" TEXT NOT NULL REFERENCES services_rh_local (id), "date_embauche" INTEGER NOT NULL, "date_fin_contrat" INTEGER NULL, "numero_cnss" TEXT NULL, "type_contrat" TEXT NULL, "salaire_base" INTEGER NOT NULL, "statut" TEXT NOT NULL DEFAULT 'actif', PRIMARY KEY ("id"));
-- ----
CREATE TABLE "bulletins_paie_local" ("id" TEXT NOT NULL, "numero" TEXT NOT NULL, "employe_id" TEXT NOT NULL REFERENCES employes_local (id), "periode" TEXT NOT NULL, "salaire_base" INTEGER NOT NULL, "total_primes" INTEGER NOT NULL DEFAULT 0, "total_retenues" INTEGER NOT NULL, "cnss_salarie" INTEGER NOT NULL, "its" INTEGER NOT NULL, "charges_patronales_confirmees" INTEGER NOT NULL, "net_a_payer" INTEGER NOT NULL, "statut" TEXT NOT NULL DEFAULT 'brouillon', "motif_annulation" TEXT NULL, "etabli_le" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), PRIMARY KEY ("id"), UNIQUE ("employe_id", "periode"));
-- ----
CREATE TABLE "taux_paie_local" ("cle" TEXT NOT NULL, "valeur" TEXT NOT NULL, "description" TEXT NOT NULL DEFAULT '', PRIMARY KEY ("cle"));
-- ----
CREATE TABLE "parametres_systeme_local" ("cle" TEXT NOT NULL, "valeur" TEXT NOT NULL, "modifie_le" INTEGER NOT NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("cle"));
-- ----
CREATE TABLE "fournisseurs_local" ("id" TEXT NOT NULL, "raison_sociale" TEXT NOT NULL, "contact" TEXT NULL, "categorie" TEXT NULL, "conditions_paiement" TEXT NULL, "evaluation" TEXT NULL, "cree_le" INTEGER NOT NULL, "cree_par" TEXT NOT NULL REFERENCES utilisateurs_local (id), "modifie_le" INTEGER NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), "actif" INTEGER NOT NULL DEFAULT 1 CHECK ("actif" IN (0, 1)), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "commandes_achat_local" ("id" TEXT NOT NULL, "fournisseur_id" TEXT NOT NULL REFERENCES fournisseurs_local (id), "date_commande" TEXT NOT NULL, "statut" TEXT NOT NULL, "cree_le" INTEGER NOT NULL, "utilisateur_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_commande_achat_local" ("id" TEXT NOT NULL, "commande_id" TEXT NOT NULL REFERENCES commandes_achat_local (id), "article_id" TEXT NOT NULL REFERENCES articles_local (id), "article_libelle" TEXT NOT NULL, "unite_mesure" TEXT NOT NULL, "quantite_centiemes" INTEGER NOT NULL, "prix_unitaire_centimes" INTEGER NOT NULL, "rang" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "bons_reception_local" ("id" TEXT NOT NULL, "commande_id" TEXT NOT NULL REFERENCES commandes_achat_local (id), "date_reception" TEXT NOT NULL, "conformite" TEXT NOT NULL, "point_stockage_id" TEXT NOT NULL REFERENCES points_stockage_local (id), "cree_le" INTEGER NOT NULL, "utilisateur_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "lignes_bon_reception_local" ("id" TEXT NOT NULL, "bon_id" TEXT NOT NULL REFERENCES bons_reception_local (id), "article_id" TEXT NOT NULL REFERENCES articles_local (id), "quantite_centiemes" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "menus_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "type" TEXT NOT NULL, "date_debut" TEXT NULL, "date_fin" TEXT NULL, "cree_le" INTEGER NOT NULL, "cree_par" TEXT NOT NULL REFERENCES utilisateurs_local (id), "modifie_le" INTEGER NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "recettes_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "cree_le" INTEGER NOT NULL, "cree_par" TEXT NOT NULL REFERENCES utilisateurs_local (id), "modifie_le" INTEGER NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "ingredients_recette_local" ("recette_id" TEXT NOT NULL REFERENCES recettes_local (id), "article_id" TEXT NOT NULL REFERENCES articles_local (id), "quantite_milliemes" INTEGER NOT NULL, PRIMARY KEY ("recette_id", "article_id"));
-- ----
CREATE TABLE "plats_local" ("id" TEXT NOT NULL, "menu_id" TEXT NOT NULL REFERENCES menus_local (id), "recette_id" TEXT NOT NULL REFERENCES recettes_local (id), "libelle" TEXT NOT NULL, "prix_vente" INTEGER NOT NULL, "prix_provisoire" INTEGER NOT NULL DEFAULT 0 CHECK ("prix_provisoire" IN (0, 1)), "prix_corrige_main" INTEGER NOT NULL DEFAULT 0 CHECK ("prix_corrige_main" IN (0, 1)), "cree_le" INTEGER NOT NULL, "cree_par" TEXT NOT NULL REFERENCES utilisateurs_local (id), "modifie_le" INTEGER NULL, "modifie_par" TEXT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"));
-- ----
CREATE TABLE "sequences_piece_local" ("journal_id" TEXT NOT NULL REFERENCES journaux_local (id), "annee" INTEGER NOT NULL, "dernier_rang" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("journal_id", "annee"));
-- ----
CREATE TABLE "paiements_facture_local" ("id" TEXT NOT NULL, "piece_id" TEXT NOT NULL REFERENCES pieces_facturation_local (id), "session_id" TEXT NOT NULL REFERENCES sessions_caisse_local (id), "mode_paiement" TEXT NOT NULL, "montant_centimes" INTEGER NOT NULL, "date_paiement" INTEGER NOT NULL, "statut" TEXT NOT NULL DEFAULT 'actif', "motif_annulation" TEXT NULL, "annule_par_id" TEXT NULL REFERENCES utilisateurs_local (id), "date_annulation" INTEGER NULL, "utilisateur_creation_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"), CHECK (mode_paiement IN ('especes', 'mobile_money', 'carte', 'virement')), CHECK (statut IN ('actif', 'annule')), CHECK (montant_centimes > 0), CHECK ((statut = 'annule') = (motif_annulation IS NOT NULL AND date_annulation IS NOT NULL)));
-- ----
CREATE TABLE "reglements_fournisseur_local" ("id" TEXT NOT NULL, "commande_id" TEXT NOT NULL REFERENCES commandes_achat_local (id), "montant_centimes" INTEGER NOT NULL, "tresorerie" TEXT NOT NULL, "date_reglement" TEXT NOT NULL, "statut" TEXT NOT NULL DEFAULT 'actif', "motif_annulation" TEXT NULL, "annule_par_id" TEXT NULL REFERENCES utilisateurs_local (id), "date_annulation" INTEGER NULL, "utilisateur_creation_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), PRIMARY KEY ("id"), CHECK (tresorerie IN ('caisse', 'momo', 'banque')), CHECK (statut IN ('actif', 'annule')), CHECK (montant_centimes > 0), CHECK ((statut = 'annule') = (motif_annulation IS NOT NULL AND date_annulation IS NOT NULL)));
-- ----
CREATE TABLE "alertes_vues_local" ("id" TEXT NOT NULL, "utilisateur_id" TEXT NOT NULL REFERENCES utilisateurs_local (id), "cle_alerte" TEXT NOT NULL, "date_vue" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("utilisateur_id", "cle_alerte"));
-- ----
CREATE TABLE "sejours_local" ("id" TEXT NOT NULL, "reservation_id" TEXT NOT NULL REFERENCES reservations_local (id), "date_checkin_reel" INTEGER NULL, "date_checkout_reel" INTEGER NULL, "occupants" TEXT NULL, "date_creation" INTEGER NOT NULL, "date_modification" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TABLE "roles_local" ("id" TEXT NOT NULL, "libelle" TEXT NOT NULL, "description" TEXT NULL, "droits_json" TEXT NOT NULL, "date_creation" INTEGER NOT NULL, "date_modification" INTEGER NOT NULL, PRIMARY KEY ("id"));
-- ----
CREATE TRIGGER rg11_ecriture_validee_immuable BEFORE UPDATE ON ecritures_local WHEN OLD.statut = 'validee' AND (NEW.id IS NOT OLD.id OR NEW.exercice_id IS NOT OLD.exercice_id OR NEW.journal_id IS NOT OLD.journal_id OR NEW.compte_id IS NOT OLD.compte_id OR NEW.centre_id IS NOT OLD.centre_id OR NEW.date_ecriture IS NOT OLD.date_ecriture OR NEW.libelle IS NOT OLD.libelle OR NEW.debit_centimes IS NOT OLD.debit_centimes OR NEW.credit_centimes IS NOT OLD.credit_centimes OR NEW.statut IS NOT OLD.statut OR NEW.ecriture_contrepassee_id IS NOT OLD.ecriture_contrepassee_id OR NEW.numero_piece IS NOT OLD.numero_piece OR NEW.cree_le IS NOT OLD.cree_le OR NEW.cree_par IS NOT OLD.cree_par) BEGIN SELECT RAISE(ABORT, 'comptabilite.ecriture_immuable'); END;
-- ----
CREATE TRIGGER rg11_brouillon_exercice_clos_maj BEFORE UPDATE ON ecritures_local WHEN OLD.statut <> 'validee' AND EXISTS (SELECT 1 FROM exercices_local WHERE id = NEW.exercice_id AND statut = 'cloture') BEGIN SELECT RAISE(ABORT, 'comptabilite.exercice_clos'); END;
-- ----
CREATE TRIGGER rg11_exercice_clos_ajout BEFORE INSERT ON ecritures_local WHEN EXISTS (SELECT 1 FROM exercices_local WHERE id = NEW.exercice_id AND statut = 'cloture') BEGIN SELECT RAISE(ABORT, 'comptabilite.exercice_clos'); END;
-- ----
CREATE TRIGGER rg11_ecriture_jamais_supprimee BEFORE DELETE ON ecritures_local BEGIN SELECT RAISE(ABORT, 'comptabilite.ecriture_suppression_interdite'); END;
