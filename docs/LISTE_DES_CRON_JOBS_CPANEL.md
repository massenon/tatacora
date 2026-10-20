# Tâches planifiées (cron) — serveur TATACORA sur cPanel

> Source de vérité du planning : `tatacora-api/routes/console.php`.
> **Règle de revue** : une tâche ajoutée là DOIT être ajoutée ici dans la
> même Pull Request. Le test `tests/Feature/Planification/ListeCronDocumenteeTest.php`
> échoue sinon.

## 1. La seule ligne à poser dans cPanel

cPanel → **Tâches Cron** (*Cron Jobs*) → « Ajouter une nouvelle tâche cron » :

| Champ | Valeur |
|---|---|
| Paramètre commun | **Une fois par minute** (`* * * * *`) |
| Commande | `cd /home/<COMPTE>/<CHEMIN>/tatacora-api && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1` |

- `<COMPTE>` / `<CHEMIN>` : le dossier où le dépôt est déployé (celui qui
  contient `artisan`).
- Le PHP doit être **8.2 ou plus**. Sur cPanel (EasyApache), le binaire est
  souvent `/usr/local/bin/php` ou `/opt/cpanel/ea-php83/root/usr/bin/php` ;
  le vérifier avec `which php` puis `php -v` dans le Terminal cPanel.
- **Une seule** ligne : c'est Laravel qui distribue ensuite les tâches
  ci-dessous. Ne créez pas une ligne cron par tâche.
- Pas de *worker* permanent sur un hébergement mutualisé : la file de tâches
  est vidée chaque minute par `queue:work --stop-when-empty`.

**Preuve que le cron tourne** : `php artisan tatacora:verifier-production`
lit le battement du planificateur (`storage/framework/battement-planificateur`,
réécrit chaque minute). Le contrôle « planificateur » doit dire
`OK — dernier passage il y a moins de 3 minutes`. Sinon, la ligne cron est
absente, fausse, ou son PHP n'est pas le bon.

## 2. Les tâches, une par ligne

Heures en **UTC** (`config/app.php` → `timezone = UTC`) : ajouter 1 h pour
l'heure du Bénin (02:00 UTC = 03:00 à Natitingou).

| Tâche (`routes/console.php`) | Quand | Ce qu'elle fait | Si elle ne tourne pas |
|---|---|---|---|
| `tatacora:battement-planificateur` | chaque minute | Pose l'heure du dernier passage (preuve du cron). | `verifier-production` signale « planificateur : ÉCHEC ». |
| `queue:work --stop-when-empty --max-time=50` | chaque minute, sans chevauchement | Vide la file de tâches (courriels, notifications, certifications) par salves de 50 s. | Les courriels et notifications restent en attente (`jobs`). |
| `tatacora:ouvrir-exercices` | chaque jour à 00:05 UTC | Ouvre l'exercice comptable de l'année en cours s'il manque, et celui de l'année suivante dès le 1er décembre. | Le 1er janvier, ventes, dépenses et encaissements refusés jusqu'à la première pièce (qui l'ouvre à la volée) ; `verifier-production` le signale. |
| `VerifierSeuilsStockJob` (RG-07) | toutes les 15 min | Filet de sécurité des alertes de stock bas (un seuil relevé sans mouvement). | Pas d'alerte de seuil hors mouvement. |
| `RejouerCertificationsMecefEnEchecJob` (RG-03) | toutes les 30 min | Rejoue la certification DGI des factures dont l'envoi MECeF a échoué. | Factures restées non certifiées. |
| `SauvegardeBaseQuotidienneJob` | chaque jour à 02:00 UTC | Sauvegarde complète (`mysqldump`) dans `storage/app/sauvegardes/`, rétention appliquée. Échoue bruyamment. | Aucune sauvegarde : `verifier-production` le dit après 26 h. |
| `NettoyerDeduplicationSyncJob` | chaque jour à 03:00 UTC | Purge la mémoire d'idempotence de la synchronisation (7 jours). | La table `deduplication_synchronisation` grossit. |
| `PurgerJournalAuditJob` (RG-15) | le 1er du mois à 04:00 UTC | Purge du journal d'audit — **inerte** tant que la durée de rétention n'est pas fixée (PA-08). | Rien (inerte par conception). |
| `contact-editeur:rejouer` | chaque heure | Renvoie les messages « Contactez l'éditeur » restés en attente après un échec SMTP. | Messages restés « en attente d'envoi ». |

Lister le planning réel sur le serveur : `php artisan schedule:list`.
Exécuter une passe à la main (diagnostic) : `php artisan schedule:run`.

## 3. Ce qui n'est PAS planifié, et pourquoi

| Tâche | Raison |
|---|---|
| Synthèse quotidienne, états planifiés, couverture des congés | Domaine non implémenté : une tâche qui ne fait rien rendrait le planning faussement complet (`TachesPlanifieesTest`). |
| Synchronisation des postes | Ce sont les **postes** qui appellent le serveur (toutes les 5 min, et toutes les 30 s pour suivre le bouton « Synchroniser ») ; le serveur ne pousse rien. |
