# Mise en production (état du 11/11/2026)

À dérouler dans l'ordre, depuis le dossier `tatacora-api` du serveur. Vérifications finales : `VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md`.

1. **Sauvegarde de la base** (dump complet) avant toute autre action.
2. **Dépendances** : `composer install --no-dev --optimize-autoloader`.
3. **Migrations** : `php artisan migrate --force`. Elles comprennent notamment :
   - `2026_11_09_180000_poser_droits_synchro_appairage_import_export`
   - `2026_11_09_200000_ajouter_cout_unitaire_mouvements_stock`
   - `2026_11_09_200000_forme_juridique_affectation_resultat`
   - `2026_11_09_210000_ajouter_origine_annulation_reservations`
   - `2026_11_10_100000_autoriser_chambres_dans_lignes_reservation` (réservations multi-chambres)
4. **Rôles du socle** (comptable = droits du gérant, barman = socle du seeder). D'abord à blanc, relire l'écart, puis appliquer :
   - `php artisan roles:realigner-socle --role=barman --role=comptable --dry-run`
   - `php artisan roles:realigner-socle --role=barman --role=comptable`
5. **Cron cPanel** : `php artisan schedule:run` chaque minute (`LISTE_DES_CRON_JOBS_CPANEL.md`).
6. **`.env` de production** : `SESSION_SECURE_COOKIE=true`, `TRUSTED_PROXIES=*`, `LOG_LEVEL=error` ; changer les mots de passe exposés.
7. **Poste Windows** : installer la version au schéma **v59** (`build_windows.bat`, même AppId : les données sont gardées), puis déclencher UNE descente complète unique depuis le poste.
8. **Vérifications** : feuille `VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md` (synchronisation, droits des rôles, une réservation à deux chambres, une annulation).
