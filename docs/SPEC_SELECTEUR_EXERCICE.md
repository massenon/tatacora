# Spécification — Sélecteur d'exercice comptable (web + poste)

> Statut : **validé et livré** (web + poste) le 20/10/2026. Décisions du PO :
> les factures, les achats et la paie suivent aussi le sélecteur (Q1 = oui) ;
> il est visible pour tous les rôles qui ouvrent ces écrans (Q3 = oui).
> Suite logique des lots 1 à 4 de la bascule et de la clôture d'exercice
> ([`CLOTURE_EXERCICE_SYSCOHADA.md`](CLOTURE_EXERCICE_SYSCOHADA.md)).

## 1. Problème

Aujourd'hui, l'exercice consulté se choisit **écran par écran**.

- Le hub Comptabilité a son propre sélecteur, et sa navigation N−1 / N+1
  depuis le lot 3.
- Le tableau de bord, le Studio des états et les dépenses ont chacun leur
  filtre de période.
- Rien ne les relie.

**Exemple.** Au 20 janvier, le comptable prépare la clôture de N−1. Il choisit
« 2025 » dans la comptabilité. En passant au tableau de bord ou aux états,
il retombe sur 2026, sans que rien le signale. Il compare alors des chiffres
de deux années différentes, et une erreur de lecture de ce genre ne se voit
pas.

**Le gérant** a le même besoin, celui du PRD de bascule (navigation N /
N+1 / N−1) : consulter l'année passée « d'un seul geste » et savoir à tout
moment quelle année il regarde.

**Qui est concerné, et quand :**
- le comptable, surtout de janvier à la clôture de N−1 ;
- le gérant et la direction, au bilan annuel et aux comparaisons ;
- un administrateur sur chaque poste.

**Coût si on ne fait rien :**
- des chiffres de deux années mélangés dans une même analyse ;
- des clics répétés à chaque écran ;
- une confusion possible avec la saisie (« ai-je écrit dans 2025 ? »).

## 2. Objectifs

1. **Une seule année de référence partout.** L'exercice choisi une fois
   s'applique à tous les écrans de consultation concernés (liste en R2),
   sans le re-choisir.
2. **On sait toujours quelle année on regarde.** L'année consultée et son
   statut (ouvert, en clôture, clôturé) sont visibles en permanence, en
   haut de chaque écran.
3. **Aucune écriture déplacée.** Choisir un exercice ne change jamais
   l'exercice où une opération s'enregistre. C'est toujours la **date** de
   l'opération qui décide (règle actuelle, inchangée).
4. **Même geste sur le web et sur le poste.** Même place, mêmes mots, même
   comportement, dans la limite des données que le poste détient.

## 3. Hors champ

| Hors champ | Pourquoi |
|---|---|
| Saisir « dans » l'exercice choisi (une vente ou une dépense datée par le sélecteur) | Contraire à l'objectif 3 : la date de l'opération fait foi (RG de `PasserEcritureService`). Une écriture d'inventaire de N−1 se passe déjà par « Passer écriture », datée de N−1. |
| Filtrer par exercice les écrans **opérationnels** (planning des chambres, POS, caisse, cuisine) | Ce sont des écrans du jour. Y appliquer 2025 masquerait les clients présents aujourd'hui. |
| Exercices décalés (autre que du 1er janvier au 31 décembre) | Le SYSCOHADA et le Gîte ont un exercice civil. Le schéma le permet (`date_debut`, `date_fin`), mais rien ne le demande. |
| Comptabilité complète de N−1 **sur le poste** (résultat, bilan) | Le poste ne détient que ses propres écritures (décision « Q1 = A »). Le sélecteur y borne ce que le poste sait calculer, rien de plus. |
| Comparatif N / N−1 dans tous les modules | Il existe en comptabilité (lot 3). L'étendre au tableau de bord est une option (R11), pas la base. |

## 4. Récits utilisateurs

### Comptable

- En tant que comptable, je veux **choisir 2025 une seule fois** et que la
  comptabilité, les états et les dépenses suivent, pour préparer la clôture
  sans re-choisir l'année à chaque écran.
- En tant que comptable, je veux **voir en permanence que je consulte un
  exercice en clôture**, pour savoir que les modules n'y écrivent plus.
- En tant que comptable, je veux **revenir à l'exercice en cours en un clic**
  (« Revenir à 2026 »), pour ne pas rester par erreur sur l'année passée.
- En tant que comptable, je veux que **mes écritures d'inventaire datées de
  2025** aillent dans 2025 même si je consulte 2026, et inversement. C'est
  la date qui décide.

### Gérant / Direction

- En tant que gérant, je veux **ouvrir le tableau de bord de l'année
  dernière**, pour comparer la saison à celle de N−1.
- En tant que gérant, je veux **ne voir que les exercices qui existent**,
  pour ne pas choisir une année vide.

### Utilisateur du poste (réception, bar, comptable sur poste)

- En tant qu'utilisateur du poste, je veux **le même sélecteur, au même
  endroit et avec les mêmes mots** que sur le web.
- En tant qu'utilisateur du poste, je veux qu'**un écran que le poste ne sait
  pas calculer pour l'année choisie me le dise**, plutôt que d'afficher un
  zéro (règle du poste : « — » avec sa raison, jamais un chiffre faux).

### Cas limites

- **Exercice supprimé ou introuvable** : je reviens à l'exercice en cours,
  avec un message.
- **Exercice rouvert ou clôturé par un autre utilisateur** : le statut affiché
  se met à jour au prochain affichage.
- **Le 1er janvier** : N+1 s'ouvre de lui-même (lot 1). Le sélecteur le
  propose sans redémarrage, mais je reste sur l'année que j'avais choisie.
- **Aucun exercice** (base vierge) : le sélecteur est grisé, avec le texte
  « Aucun exercice comptable n'a encore été ouvert ».

## 5. Exigences

### P0 — indispensables

**R1. Un sélecteur d'exercice global dans la barre supérieure (web et
poste).**
- [ ] La liste ne contient que les exercices existants, du plus récent au
  plus ancien, chacun avec son statut : « 2026 — ouvert », « 2025 — en
  clôture », « 2024 — clôturé ».
- [ ] Par défaut, l'exercice **ouvert le plus récent** est sélectionné ; s'il
  n'y en a pas, l'exercice le plus récent.
- [ ] Le choix vaut pour **l'utilisateur et sa session** : un autre
  utilisateur, ou un autre poste, n'est pas affecté.
- [ ] Sur le web, l'exercice est gardé dans la session. Sur le poste, il est
  gardé en mémoire pour l'utilisateur connecté et revient à l'exercice par
  défaut à la reconnexion.

**R2. Les écrans de consultation qui suivent le sélecteur.**

| Écran | Web | Poste |
|---|---|---|
| Comptabilité, hub et ses onglets (journal, grand livre, balance, résultat, bilan, analytique, clôtures) | oui (remplace le sélecteur local) | oui (journal, balance) |
| Comptabilité, pages autonomes (balance, bilan, compte de résultat, grand livre, notes annexes, flux de trésorerie, clôture) | oui | — (pas d'écran) |
| Tableau de bord : période « Exercice entier » | oui | oui (indicateurs calculables) |
| Studio des états : période par défaut | oui | oui (aperçus) |
| Dépenses : filtre de période par défaut | oui | oui |
| Factures (registre) : factures émises dans l'exercice | oui | oui |
| Achats : commandes passées dans l'exercice (registre et approvisionnement), réceptions de l'exercice | oui | oui |
| Paie : mois proposé (le mois courant, ou le dernier mois de l'exercice passé) ; choix du mois borné à l'exercice | oui | oui |

- [ ] Un écran qui suit le sélecteur l'indique dans son en-tête : « Exercice
  2025 — en clôture ».
- [ ] Un filtre de période **plus fin** (un mois de 2025, par exemple) reste
  possible dans l'écran. Il est borné à l'exercice choisi.

**R3. L'année et son statut sont toujours visibles.**
- [ ] Quand l'exercice choisi n'est pas l'exercice ouvert le plus récent, la
  barre supérieure affiche une pastille de couleur (ambre pour « en
  clôture », ardoise pour « clôturé ») avec le lien « Revenir à <année> ».
- [ ] Les bandeaux du lot 3 (en clôture, clôturé) restent sur le hub
  Comptabilité.

**R4. Aucune écriture n'est déplacée par le sélecteur.**
- [ ] Une vente, une dépense, un encaissement ou une réservation s'enregistre
  dans l'exercice de **sa date**, quel que soit l'exercice choisi.
- [ ] La date proposée par défaut dans un formulaire de saisie reste
  **aujourd'hui**, sauf dans « Passer écriture » du hub Comptabilité. Là, la
  date par défaut est aujourd'hui si elle tombe dans l'exercice choisi, sinon
  son 31 décembre (comportement actuel du hub).
- [ ] Un test le vérifie : on choisit 2025, on enregistre une vente du jour,
  et la pièce est dans 2026.

**R5. Parité web / poste.**
- [ ] Mêmes mots, même place (barre supérieure, à gauche du bouton de
  synchronisation sur le poste).
- [ ] Le comparateur Blade → Flutter mesure le sélecteur : la dette ne monte
  pas.
- [ ] Sur le poste, tout écran de R2 qui ne détient pas les données de
  l'année choisie l'écrit : « Sur ce poste : … », jamais un zéro.

### P1 — souhaitables

- **R6. Liens profonds.** Le paramètre `?exercice=` garde l'exercice choisi
  dans l'URL du web. Un lien copié ouvre le même exercice.
- **R7. Raccourcis N−1 / N+1** dans la barre, sur le modèle des boutons du
  lot 3.
- **R8. Exports et PDF.** Tout export lancé depuis un écran qui suit le
  sélecteur porte l'exercice dans son en-tête. C'est déjà la règle PA-119 :
  l'export dit son périmètre.
- **R9. Exercice choisi gardé entre deux sessions** (préférence de
  l'utilisateur), avec un retour automatique à l'exercice en cours le
  1er janvier.

### P2 — plus tard (à prévoir dans la conception)

- **R10. Exercices décalés.** Le sélecteur s'appuie sur `date_debut` et
  `date_fin`, jamais sur « l'année civile » : cela suffit pour plus tard.
- **R11. Comparatif N / N−1 au tableau de bord** (CA, occupation,
  trésorerie).
- **R12. Comptabilité de N−1 complète sur le poste**, si la décision Q1 est
  revue (descente des écritures du serveur).

## 6. Indicateurs de réussite

Le Gîte compte une poignée d'utilisateurs. Les indicateurs sont donc des
constats sur le terrain et des contrôles automatiques, pas des statistiques
d'usage.

| Type | Indicateur | Cible | Mesure |
|---|---|---|---|
| Rapide | Écrans de R2 qui suivent le sélecteur | 100 % (web), 100 % des écrans calculables (poste) | Tests de fonctionnalité, un par écran |
| Rapide | Opérations enregistrées dans un autre exercice que celui de leur date | **0** | Test R4 + `GET /sync/coherence` sans écart |
| Rapide | Clics pour passer un dossier de clôture d'un écran à l'autre sur N−1 | 1 choix d'exercice au lieu d'un par écran | Essai guidé avec le comptable |
| Lent | Erreurs « mauvaise année » signalées par le comptable pendant la clôture 2026 | 0 | Retour du comptable après la clôture |
| Lent | Dette du comparateur Blade → Flutter | ne monte pas | `t-blade-flutter.js`, à chaque livraison |

## 7. Questions ouvertes

| # | Question | Qui | Bloquante ? |
|---|---|---|---|
| Q1 | ~~La liste R2 est-elle la bonne ? Faut-il y ajouter les factures, les achats ou la paie ?~~ **Tranché le 20/10/2026 : oui**, ajoutés à R2. | Product Owner | — |
| Q2 | L'exercice choisi doit-il survivre à la déconnexion (R9 en P0) ? | Product Owner | Non |
| Q3 | ~~Les rôles sans accès à M10 voient-ils le sélecteur ?~~ **Tranché le 20/10/2026 : oui**, sur les écrans de R2 qu'ils peuvent ouvrir ; masqué sur les écrans du jour. | Product Owner | — |
| Q4 | Sur le poste, où placer le sélecteur dans la barre supérieure déjà chargée (bouton de synchronisation, cloche) ? | Design / PO | Non |
| Q5 | En janvier, pendant que N−1 est « en clôture », l'exercice par défaut doit-il être N (proposition) ou N−1 pour le comptable ? | Product Owner, comptable | Non |
| Q6 | Le tableau de bord utilise la classe `Periode` (mois, trimestre, année…). Ajoute-t-on une période « exercice » ou fait-on suivre « Exercice entier » à l'exercice choisi ? | Ingénierie | Non |

## 8. Calendrier et découpage

- **Contrainte** : être en service **avant la première clôture réelle**,
  celle de 2026, en janvier ou février 2027. C'est là que le besoin est le
  plus fort.
- **Dépendances** :
  - lots 1 à 4 (exercices descendus aux postes, statuts, clôture) : faits ;
  - réponse à Q1 et Q3 avant de commencer.
- **Découpage proposé** :
  1. **Phase 1 (web)** : R1, R3 et R4. Le hub Comptabilité et ses pages
     autonomes branchés sur le sélecteur global.
  2. **Phase 2 (web)** : R2 complet (tableau de bord, états, dépenses), plus
     R6 et R8.
  3. **Phase 3 (poste)** : R1 à R5 sur le poste, avec le comparateur et une
     mesure de la dette.
  4. **Ensuite** : R7 et R9 selon les retours du comptable après un premier
     usage.

Chaque phase est livrée avec ses tests (serveur et poste), les deux suites
complètes vertes, et le comparateur Blade → Flutter en PASS.

## 9. Livré (20/10/2026)

**Web (PWA).**
- `App\Pwa\Support\ExerciceConsulte` garde l'exercice choisi en session et
  porte la date de référence et les bornes de l'exercice.
- Le composant `SelecteurExercice`, dans la barre supérieure, propose la
  liste « 2026 — ouvert ». Il affiche la pastille « Vous consultez 2025
  (clôturé) » et le lien « Revenir à 2026 ».
- Il n'apparaît que sur les écrans de R2.
- Le sélecteur du hub Comptabilité reste à sa place, synchronisé avec le
  sélecteur global. Un lien `?exercice=` devient le choix global.

**Poste.** `exercice_consulte.dart` et `SelecteurExerciceBarre` reprennent le
même comportement, avec les mêmes mots. Le choix est gardé en mémoire et
revient au défaut à la reconnexion.

Branchements sur le poste :
- hub Comptabilité ;
- horloge du tableau de bord ;
- mois de la paie ;
- dépenses ;
- registre des factures ;
- commandes et réceptions.

**Écarts nommés sur le poste.**
- **États** : les aperçus sont des photographies du jour. Quand un autre
  exercice est consulté, une ligne le dit : « Sur ce poste : aperçu du jour,
  pas de l'exercice choisi. »
- **Dettes fournisseurs** (commandes non clôturées) : elles restent un état
  du jour, toutes années confondues, sur le web comme sur le poste.

**R4 prouvé par un test.** Une dépense saisie pendant qu'un exercice passé
est consulté va dans l'exercice de sa date.

