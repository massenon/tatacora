# Essais en production, puis réinitialisation (web + postes)

> Décision du Product Owner du 19/10/2026. Procédure à suivre UNE fois, entre
> l'installation en production et la mise en service réelle du Gîte.
> Les vérifications techniques sont dans
> [`VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md`](VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md).

## Comment ça marche (en deux phrases)

Pendant la **phase d'essais**, on saisit de vraies opérations sur le vrai
serveur et les vrais postes ; ensuite on vide tout (« Réinitialiser comme
neuf ») d'abord sur le **serveur**, puis sur **chaque poste**. Le serveur
ouvre alors une nouvelle **génération des données** : un poste qui n'a pas
encore été réinitialisé est **refusé** (il ne renvoie pas ses essais) et
affiche en rouge « Le serveur a été réinitialisé… », jusqu'à sa propre
réinitialisation.

## Ce qui est vidé, ce qui est gardé

| Vidé (serveur ET postes) | Gardé |
|---|---|
| Clients, réservations, séjours, ventes, factures, avoirs, encaissements, caisses, dépenses, commandes et réceptions, mouvements de stock, écritures comptables, paie et employés, fournisseurs, guides, tourisme (réservations), contrats de location, **tout le catalogue** (plats, menus, recettes et ingrédients, articles de stock, inventaires, carte des boissons, retraits de la carte, historique des prix), files de synchronisation | Comptes et rôles, paramètres (y compris le mot de passe SMTP chiffré), appairage des postes, journal d'audit, chambres (catégories et unités), canaux, points de stockage (les lieux), tables de salle, véhicules, circuits, plan comptable, journaux, exercices, centres de coût, services RH, modèles de notification |

- Les numéros (factures `F-AAAA-NNNNN`, ventes, dépenses, pièces) se
  calculent sur les documents existants : ils **repartent à 00001**.
- Un référentiel créé sur un poste pendant les essais (article, chambre…)
  n'est gardé que s'il **était déjà au serveur** au moment de la
  réinitialisation : synchronisez avant si vous voulez le garder.
- Un exercice **démarré en clôture ou clôturé pendant les essais** redevient
  **ouvert**, et les archives de clôture d'essai
  (`storage/app/private/archives/exercices/`) sont **effacées** : aucune
  « archive légale » d'un exercice d'essai ne survit.

## Avant les essais

1. Déployer, `php artisan migrate --force`, puis
   `php artisan tatacora:verifier-production` : aucun **ÉCHEC**.
2. Dans le `.env` du serveur : `TATACORA_PHASE_ESSAIS=true`, puis
   `php artisan config:clear` (si la configuration est en cache).
   La commande de vérification affiche alors « phase_essais : ATTENTION »,
   c'est normal.
3. **MECeF ne doit PAS être en mode réel pendant les essais** : une facture
   d'essai certifiée par la DGI ne s'efface pas avec la base. Le contrôle
   « mecef » de `verifier-production` doit dire autre chose que « actif ».
4. Installer **la version courante** sur chaque poste (`build_windows.bat`),
   puis l'appairer (Paramètres → Synchronisation). ⚠ Un poste resté sur une
   version d'avant le 19/10/2026 ne connaît pas la génération des données :
   mettez-le à jour AVANT la réinitialisation du serveur.

## Pendant les essais — scénarios conseillés

| # | Où | Scénario | Ce qu'on vérifie |
|---|---|---|---|
| 1 | Poste A | Réservation, check-in, check-out, facture, encaissement | La réservation apparaît sur le poste B et sur le web |
| 2 | Poste B | Même chambre, mêmes dates, hors réseau, puis reconnexion | Conflit RG-01 dans « À traiter » |
| 3 | Bar / restaurant | Ouverture de caisse, ventes, clôture | Synchronisation déclenchée à la clôture ; vente visible au web |
| 4 | Web | Dépense, commande fournisseur, réception | Descendue sur les postes au passage suivant |
| 5 | Web | Bouton « Synchroniser les postes » | Les postes passent dans la minute |
| 6 | Poste | Débrancher le réseau 10 min, saisir, rebrancher | Rien de perdu, rien de doublé ; voyant orange puis vert |
| 7 | Poste | Écran de synchronisation → « Contrôler maintenant » | Aucun écart de cohérence |
| 8 | Web + poste | Envoi d'un courriel de test (Paramètres → Email (SMTP)) | Le courriel arrive |
| 9 | Poste | Impression ticket, facture provisoire, export CSV | Documents lisibles |

## Réinitialiser — dans cet ordre

### 1. Le serveur (web)

1. Connecté en **Administrateur** : Paramètres → **Activation & Sécurité** →
   ouvrir « Réinitialisation des données de test ».
2. **Import & Export → onglet « Réinitialiser les données de test »** : le bandeau jaune « Phase d'essais
   en Production » est affiché. Vérifier les deux listes (vidé / conservé),
   cliquer **Réinitialiser comme neuf**, taper `VIDER`, confirmer.
   Une sauvegarde complète est faite juste avant
   (`storage/app/sauvegardes/`), et le geste est écrit au journal d'audit.
3. Refermer la bascule (Paramètres → Activation & Sécurité).

### 2. Chaque poste

1. Ouvrir TATACORA, cliquer le bouton de synchronisation (barre du haut) →
   « Synchroniser maintenant ». Le voyant passe au **rouge** : « Le serveur a
   été réinitialisé… ». Rien n'est parti.
2. Connecté en **Administrateur** du poste : **Import & Export → onglet
   « Réinitialiser les données de test »**. Le bandeau rouge rappelle la date de la réinitialisation
   du serveur ; le bouton est disponible même sur la version de production
   et sans ouvrir la bascule locale. **Réinitialiser comme neuf**, taper
   `VIDER`, confirmer.
3. Synchroniser maintenant : le poste reçoit le catalogue du serveur remis à
   neuf ; le voyant passe au **vert**.
4. Recommencer sur le poste suivant.

### 3. Fin de la phase d'essais

1. Retirer `TATACORA_PHASE_ESSAIS` du `.env` (ou la mettre à `false`), puis
   `php artisan config:clear`.
2. `php artisan tatacora:verifier-production` : « phase_essais : OK »,
   « bascule_reinitialisation : OK ». Désormais la réinitialisation est
   **impossible en production**, quel que soit le rôle.
3. Saisir le stock d'ouverture réel (inventaire), les vrais clients, puis
   suivre la liste de vérifications.

## En cas de problème

| Symptôme | Cause | Remède |
|---|---|---|
| « Réinitialisation refusée : cet environnement est la Production » | `TATACORA_PHASE_ESSAIS` absente, ou configuration en cache | La poser, `php artisan config:clear` |
| « La fonction est désactivée dans Paramètres › Activation & Sécurité » (serveur) | Bascule fermée | L'ouvrir, puis la refermer après |
| Un poste reste vert après la réinitialisation du serveur | Il n'a pas encore tenté de synchroniser | « Synchroniser maintenant » |
| Le poste n'offre pas la réinitialisation | Compte non Administrateur, ou poste pas encore refusé par le serveur | Se connecter en Administrateur ; synchroniser d'abord |
| `mysqldump` introuvable (serveur) | Sauvegarde préalable impossible : rien n'est vidé | Voir avec l'hébergeur ; la sauvegarde est obligatoire |
