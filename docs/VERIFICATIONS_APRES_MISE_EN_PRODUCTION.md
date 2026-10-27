# Vérifications après chaque mise en production

> Décision du Product Owner du 19/10/2026. À dérouler **après chaque
> déploiement** du serveur et **après chaque nouvelle version** installée sur
> les postes. Cocher, dater, signer ; garder la feuille avec le bon de
> livraison.

Date : ____ / ____ / ______  Version (commit) : ____________  Par : ______________

## A. Serveur — automatique (5 minutes)

Dans le Terminal cPanel, depuis le dossier `tatacora-api` :

```bash
php artisan down                       # facultatif : page de maintenance
git pull                               # ou le dépôt des fichiers
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache && php artisan view:cache
php artisan up
php artisan tatacora:verifier-production
```

- [ ] `tatacora:verifier-production` se termine **sans ÉCHEC** (code de
      sortie 0). Chaque ligne « ATTENTION » est lue et acceptée en conscience.

| Contrôle | Attendu en production |
|---|---|
| environnement | `APP_ENV=production` |
| debogage | `APP_DEBUG=false` (ÉCHEC sinon) |
| cle_application | présente — **ne jamais la changer** |
| adresse | `https://…` |
| base_de_donnees, migrations | connexion OK, toutes les migrations jouées |
| ecriture_disque | `storage/` et `bootstrap/cache/` inscriptibles |
| planificateur | dernier passage il y a moins de 3 min (sinon : la tâche cron, voir [`LISTE_DES_CRON_JOBS_CPANEL.md`](LISTE_DES_CRON_JOBS_CPANEL.md)) |
| file_d_attente | aucune tâche en échec |
| sauvegarde | moins de 26 h, plus de 10 Ko |
| courriel, secret_smtp | transport configuré, mot de passe déchiffrable |
| administrateur | au moins un compte d'administration actif |
| phase_essais, bascule_reinitialisation | OK (sauf pendant la phase d'essais) |
| exercice_comptable | l'exercice de l'année en cours est ouvert (en décembre : aussi l'année suivante) |
| archives_cloture | chaque exercice clôturé a son archive légale, et elle rend encore son empreinte SHA-256 (ÉCHEC si un fichier a changé) |
| mecef | « actif » une fois la certification DGI branchée |

## B. Serveur — à la main (10 minutes)

- [ ] `https://<site>/up` répond (page « Application up »).
- [ ] Connexion à la PWA avec un compte Administrateur ; le tableau de bord
      s'affiche sans erreur.
- [ ] Paramètres → Email (SMTP) → **Envoyer un email de test** : le courriel
      **arrive** (le contrôle automatique ne prouve que la configuration).
- [ ] Import & Export → Sauvegardes : **générer** une sauvegarde, la
      **télécharger**, vérifier que le fichier n'est pas vide.
- [ ] Menu de compte → **Synchroniser les postes** : chaque poste attendu est
      listé « Appairé », dernier envoi et dernière réception récents.
- [ ] Journal d'Audit : la connexion de l'instant est tracée.
- [ ] `storage/logs/laravel.log` : aucune erreur depuis le déploiement.
- [ ] Le fichier `.env` n'est **pas** accessible depuis le web
      (`https://<site>/.env` → 403 ou 404).

## C. Chaque poste Windows (5 minutes par poste)

- [ ] La version installée est la nouvelle : Paramètres Windows →
      Applications → TATACORA, version = celle de `pubspec.yaml` (l'installateur
      s'appelle `LogiReStock_Setup_<version>.exe`). « Aide → À propos » ne
      l'affiche pas.
- [ ] Connexion avec un compte du poste.
- [ ] La base est au bon endroit :
      `%LOCALAPPDATA%\TATACORA\donnees\tatacora.sqlite` (pas dans Documents).
- [ ] Paramètres → Synchronisation → **Tester la connexion** : « Connexion
      établie ».
- [ ] Bouton de synchronisation (barre du haut) → **Synchroniser
      maintenant** : voyant **vert**, aucune opération « À traiter ».
- [ ] Écran de synchronisation → **Contrôler maintenant** : aucun écart.
- [ ] Une vente d'essai au comptant **n'est PAS** faite en production réelle ;
      à la place : ouvrir la caisse, vérifier le fond, la refermer à zéro.
- [ ] Impression : un ticket de test sort sur l'imprimante du comptoir.
- [ ] Paramètres → Email (SMTP) : « Mot de passe SMTP — Renseigné le … »
      (sinon « Contactez l'éditeur » ne peut rien envoyer).

## D. Après la première nuit

- [ ] Une sauvegarde automatique datée de la nuit existe (02:00 UTC =
      03:00 à Natitingou) et pèse plus de 10 Ko.
- [ ] `tatacora:verifier-production` : toujours sans ÉCHEC.

## En cas d'ÉCHEC

Ne pas ouvrir l'exploitation. Le détail de la ligne dit quoi faire ; sinon,
revenir à la version précédente (`git checkout <commit précédent>`,
`composer install`, `php artisan config:cache`) — les migrations de TATACORA
sont additives, la base n'a pas à être restaurée pour un retour de code.
