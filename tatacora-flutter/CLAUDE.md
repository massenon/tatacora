# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Client Flutter TATACORA — guide de travail

Ce fichier ne répète pas le `CLAUDE.md` de la racine : lisez-le d'abord, il porte
le contexte projet, les six règles sans exception et l'état des 14 modules. Ici,
seulement ce qui est propre au client Flutter.

## Commandes

```bash
flutter pub get
flutter run -d windows                     # le poste cible du Gîte
flutter analyze                            # `warning` est BLOQUANT, pas seulement `error`
dart format .                              # avant toute livraison
flutter test                               # 2 953 tests + 24 ignorés (mesuré le 12/10/2026), ~6 min : les scripts PHP sur tatacora_test sont SÉRIALISÉS (verrou de fichier, D279)
flutter test test/features/pos/salle_test.dart          # un fichier
flutter test --plain-name 'un chevauchement est refusé' # un cas, par son nom

# Après TOUTE modification d'une table Drift, d'un `@DriftAccessor` ou d'un `part`
dart run build_runner build --delete-conflicting-outputs

# Les tests d'intégration tournent sur la VRAIE fenêtre Windows, pas en VM Dart
flutter test -d windows integration_test/socle_desktop_test.dart
```

Un test d'intégration **s'ignore lui-même** sans la variable `TATACORA_FIXTURE` :
c'est le seul mécanisme de filtrage, `dart_test.yaml` ne fait que déclarer le tag.

**Un fichier verrouillé** (`Flutter failed to delete … sqlite3.dll`) veut dire
qu'un `flutter_tester` d'une exécution précédente tourne encore. Le tuer, puis
relancer.

## Ce que ce client est

Une application **offline-first**, sur un poste de comptoir à Natitingou, dont la
connexion tombe. Trois conséquences qui commandent toute l'architecture :

1. **Toutes les lectures viennent de la base locale Drift.** Le poste est zéro
   réseau : rien ne rafraîchit depuis un serveur. Aucun écran n'a de branche « si connecté ».
2. **L'UUID naît côté client**, à la création de l'objet, jamais à l'envoi :
   c'est lui qui rend le rejeu idempotent quand le réseau coupe entre le
   traitement serveur et la réponse.
3. **La donnée non synchronisée est la seule copie qui existe.** Une migration
   qui recrée une table, un panier perdu à la fermeture de la fenêtre, une file
   qui ne repart jamais : ce sont les trois défauts déjà rencontrés ici.

## Les quatorze pièges de ce dépôt, tous rencontrés pour de vrai

**1. Un indicateur qui affirme un état qu'il n'a pas vérifié.** PA-59/60/61 :
une migration jamais exécutée, une sauvegarde de 802 octets au nom conforme, un
badge « certifié » pendant que tout partait en démonstration. Avant d'écrire
qu'une chose *va* se produire, cherchez l'appelant. **Un commentaire qui décrit
un déclencheur n'est pas un déclencheur** (PA-63 : les deux moitiés du protocole
offline-first n'étaient appelées que par des tests).

**2. `onUpgrade` n'est jamais emprunté par un test en mémoire.** `onCreate`
tourne à chaque test, `onUpgrade` jamais — et c'est pourtant lui, le chemin de la
mise à jour. Toute migration se prouve sur un **fichier réel portant des
données**, y compris en sautant des versions (le poste qui a raté une livraison).

**3. Le piège de `createTable`, rencontré deux fois.** `m.createTable` crée la
définition **courante** de la table : un poste ancien reçoit donc des colonnes
qu'une migration ultérieure voudra ajouter, et l'`addColumn` échoue sur
« duplicate column name ». Côté test, le même piège à l'envers : une fixture
« v3 » fabriquée depuis le schéma courant n'imite pas une v3. Les retraits sont
centralisés dans **`test/core/database/retour_arriere_schema.dart`** — ajouter
une version au schéma, c'est ajouter son entrée là, et rien d'autre.

**4. Un caractère de contrôle invisible vide une garde.** ⚠ **Vu naître le
26/08/2026** (PA-141) : le shell de cet environnement **collapse les antislashs
doublés**, si bien qu'un `\b` de regex écrit par heredoc devient l'octet 0x08.
C'est la troisième occurrence documentée. Après tout heredoc, balayez les octets. Un `\b` écrit par un
script devient l'octet 0x08 et le motif ne correspond plus à rien : le test passe
**à vide**. `test/core/qualite/caracteres_de_controle_test.dart` relit chaque
fichier octet par octet et porte un **plancher de fichiers**, sans quoi un dossier
renommé rendrait le balayage vide, donc vert. Ne jamais écrire un fichier source
par heredoc sans revérifier ses antislashs.

**5. Un test qui n'emprunte pas le chemin ne protège pas le chemin.** Éprouvé le
25/08/2026 : une mutation retirant la fiche de `Reservation.copyWith` laissait la
suite verte, parce que le test passait par `majStatutSync`, qui écrit en SQL
direct. **Mutez ce que vous venez d'écrire** — c'est la seule preuve qu'une
assertion n'est pas vide.

**6. Un défaut de SÉQUENCE de rendu ne se voit pas à la relecture.** Deux fois
en une journée : des boutons calculés avant la donnée qui les active seraient
restés grisés pour toujours (PA-111), et un catalogue demandé avant le
pré-remplissage était calculé sur la période par défaut — une chambre déjà
prise se serait présentée libre (PA-115). Dans les deux cas, tout le reste de
l'écran était juste. Quand un rendu dépend d'un état posé pendant ce même
rendu, demandez-vous dans quel ordre les deux ont lieu.

**7. Une borne ne se teste que sur un contenu plus grand qu'elle.** Retirer
le `maxHeight` d'une modale n'a fait rougir aucun test : celui qui la mesurait
montait une fiche courte. Il a fallu la remplir jusqu'à déborder. Même
famille que le piège 5 — l'assertion existait, elle n'atteignait rien.

Corollaire éprouvé le 25/08/2026 (PA-123) : une mutation qui ne mord pas
accuse parfois le **cas**, pas le code. Remplacer `any` par `every` dans le
filtre d'activité laissait la suite verte — la facture d'essai ne portait
qu'une activité, où les deux disent la même chose.

**11. Une table répliquée a DEUX moitiés : qui l'écrit, qui la descend.**
Les clients montaient depuis PA-116 et ne descendaient pas (PA-127). Comme
`reservations_local.client_id` est une vraie clé étrangère, la première
réservation d'un autre poste violait la contrainte et l'exception emportait
**tout le lot** d'alignement. 726 tests étaient verts. Le défaut n'existe
qu'à deux postes — c'est-à-dire dans le cas normal.

La même question posée à l'autre clé étrangère a donné PA-128 : le **parc**
n'était écrit par personne, et un poste neuf ne pouvait prendre aucune
réservation. Et une troisième fois (PA-129) : **aucun catalogue vendable**
n'était écrit — le point de vente n'avait rien à vendre. Posez-la à **chaque**
table que vous lisez.

**12. Un prédicat dérivé du champ qu'il vérifie ne vérifie RIEN.** `aUnEcran`
se définit par `route != null` ; le test « une destination sans écran n'annonce
aucune route » comparait donc le champ à lui-même (PA-133). Il n'a jamais pu
échouer, et trois écrans livrés sont restés inatteignables par un clic. Quand un
test porte sur une cohérence, ancrez-le sur une source **extérieure** — ici le
routeur, relu dans son code source.

**9. Une colonne qui existe au schéma n'est pas une valeur qui est écrite.**
`clients_local.solde` vaut zéro pour tout le monde : aucune ligne de code ne
l'alimente (PA-126). L'afficher aurait donné un zéro plausible sur la fiche
d'un débiteur. Avant de lire une colonne, cherchez qui l'écrit — et si
personne ne l'écrit, calculez, ou refusez d'afficher.

**10. Une `DataRow.key` n'atteint pas l'arbre de widgets.** Rencontré deux
fois. `find.byKey` ne la trouve jamais : posez la clé sur un widget d'une
cellule. Une clé introuvable est une clé qui ment.

**8. Un commentaire qui affirme une garantie n'est pas une garantie.** Le
graphique du tableau de bord portait « l'axe part de ZÉRO, toujours — c'est le
trucage le plus courant » ; tronquer l'axe ne faisait rougir aucun test
(PA-122). Quand vous écrivez qu'une propriété est tenue, cherchez le cas qui
la tient — ou écrivez-le.

**13. Une phrase de la vue sur de l'argent se vérifie en EXÉCUTANT le serveur,
et se remplace quand elle ment.** Trois phrases de l'écran Approvisionnement
disaient que la réception « a recalculé le coût moyen pondéré » ; le serveur,
exécuté, n'y touche pas (D265). Décision du Lead (D276) : un poste n'affiche pas
une affirmation fausse sur de l'argent — la règle d'honnêteté prévaut sur la
fidélité littérale à la vue. On met la phrase VRAIE, avec le maximum des mots de
la vue ; l'écart est NOMMÉ au code (fichier de la vue, ce qu'elle dit, pourquoi
on s'en écarte) ; un test épingle la fausseté à la source (il rougit le jour où
la vue est corrigée) et un autre refuse la phrase fausse dans le code RENDU ;
l'Architecte est saisi. **Soldé le 09/11/2026 (PO : « corrige les deux »)** : le
web a été corrigé à la source (`achats_pwa.appro.form_avertissement_double`,
`reception_enregistree`, `prix_obligatoire`, `pwa.appro.receptions_detail`) et
dit désormais, au mot, la phrase VRAIE du poste ; l'écart n'existe plus, les
tests (`conformite_achats_test`, `reception_valorisation_contre_serveur_test`,
`calcul_achats_contre_serveur_test`) épinglent la même phrase des deux côtés et
refusent la fausse DANS les deux — il rougit le jour où le web la réintroduit.
Corollaire de mesure : écrire le chemin
`pwa/….blade.php` dans un commentaire fait du fichier un PORTEUR de la vue —
l'écart commenté avait fait baisser la dette (« Point de stockage ») sans qu'un
pixel change. Écrire « la vue d'approvisionnement ».

**14. Un lecteur câblé n'est pas un lecteur DÉCLARÉ, et une sonde qui s'exclut
ne voit rien.** `activation_suppression` était lue (règle d'archivage des
fournisseurs) pendant que Paramètres affichait encore « Aucun module de ce poste
ne lit encore cette valeur » : l'entrée du registre n'avait pas de `lecteur`
(D278). Le test censé le détecter excluait tout `features/parametres/` — là où
vivait le lecteur. Une sonde n'écarte que les fichiers qui DÉFINISSENT les clés,
et se prouve par mutation (retirer le lecteur doit rougir). Même famille :
l'aide du serveur (« tous les modules ») sur-promet quand un seul module lit ;
l'aide, confrontée à la vue, ne se touche pas — l'écart se dit en ligne par la
`correction` (« Sur ce poste : … »).

## Le maître de mise en page est la VUE BLADE de la PWA — et elle seule

**Décisions du Product Owner du 10/09/2026 (PA-182, PA-183).** Le client
Flutter se conforme à la **vue Blade** de la PWA — `tatacora-api/resources/views/pwa/`,
les classes `app/Pwa/` et les libellés `lang/fr/` — écran par écran, onglet par
onglet, aux mêmes emplacements. Elle porte la dernière version de chaque écran,
écarts datés du Product Owner compris (bouton « Vente », pastille « Réseau »,
Journal d'Audit au menu de compte, bascule plein écran, recherche globale,
masquage `gerant`, style d'onglets unique `Onglets.php`). **`prototype_v2/`
est une ANCIENNE version** : ne vous y référez plus, même pour départager.
`docs/DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` et `docs/DIRECTIVE_CONFORMITE_100.md`
Article 0, à lire avant tout écran. Le code Flutter est une **traduction**, pas
une réinterprétation. Trois règles :

- **Quand la spécification écrite et la vue Blade se contredisent sur ce qui se
  voit, la vue gagne.** ⚠ Jusqu'au 10/09/2026, ce fichier disait l'inverse
  (« Une vue Blade ne fait jamais foi ») et faisait de `prototype_v2/` le
  maître : ne rétablissez ni l'un ni l'autre. Les citations
  `prototype_v2/pages/…` et les jetons `maitre-refuse:` qui subsistent dans le
  code sont l'HISTORIQUE de décisions passées, pas une référence.
- **Aucune valeur en dur dans un widget.** Couleurs, tailles, espacements et
  largeurs vivent dans `lib/core/theme/`. **Mesurez sur la vue et sur la
  feuille de style que sert la PWA**, ne supposez pas : la plupart des tailles
  de police sont des valeurs entre crochets (`text-[13px]`), pas l'échelle
  nommée de Tailwind.
- **Tout écart se documente dans le code** : fichier et ligne de la **vue
  Blade**, ce qu'elle fait, pourquoi on s'en écarte.

**La garde tourne avec `flutter test`** : `test/core/qualite/conformite_blade_test.dart` lance `tool/conformite_blade/t-blade-flutter.js`. Node et PHP sont requis — sans eux le test ÉCHOUE, il ne saute pas. Le comparateur résout les clés de langue par PHP, puis confronte le titre, les onglets, les libellés de chaque bloc, les modales et le châssis de chaque vue au code Flutter. **Un écran cite sa vue** — `// Vue Blade maîtresse (PA-183) : pwa/<module>/<vue>.blade.php` — et c'est le SEUL ancrage : un écran qui ne la cite pas n'est pas mesuré, et un `ecran_*.dart` sans vue est signalé comme ajout. Ce qu'on ne rend pas se **nomme avec les mots de la vue** ; un bloc entier refusé se déclare par `blade-refuse:<vue>#<bloc>` ; un écran dont les libellés viennent de l'API déclare `libelles-du-serveur:<vue>`. La dette de départ est figée dans `tool/conformite_blade/dette-blade-flutter.json` et ne peut que décroître : un progrès non resserré (`--figer-dette`) fait aussi échouer.

**Cette garde a été verte À VIDE sur les deux cartes jusqu'au 11/09/2026 (PA-187).** Un commentaire PHP `//` dans les arguments d'un `@include` portait une apostrophe (« qu'elle ») ; le comparateur la prenait pour un guillemet, ne dépliait pas `pwa.carte.corps`, et sept modales des cartes bar et restaurant n'étaient jamais mesurées. Deux leçons. (1) **Un chiffre de dette bas n'est pas une preuve de conformité** : quand une vue affiche peu d'absents, vérifiez que ses modales sont comptées (colonne MODALES à `0/0` sur une vue qui en a = suspect). (2) **Citer `pwa/…blade.php` dans un fichier Flutter en fait un PORTEUR de cette vue** : dans un écran signalé comme ajout, une simple mention en commentaire efface le signalement. Écrivez le chemin sans son préfixe quand vous ne portez pas la vue. (3) **La correspondance se fait par SOUS-CHAÎNE** (PA-189) : l'en-tête « Nouveau » d'une modale non portée est compté présent parce que « Nouveau prix de vente (FCFA) » existe ailleurs dans le code. Un libellé court peut faire baisser la dette d'un bloc que personne n'a porté — une baisse inattendue se vérifie avant d'être figée. (4) **Depuis PA-196, titre, onglets et blocs de page se cherchent dans le CODE QUE L'ÉCRAN ATTEINT** — ses porteurs et tout ce qu'ils importent, transitivement — et non plus dans tout `lib/` : quatre faux positifs en une journée venaient d'un fichier sans rapport avec l'écran. Conséquence pratique : **un widget qui rend un libellé doit être IMPORTÉ par l'écran** (directement ou non) pour compter ; un texte posé dans un fichier que l'écran n'atteint pas ne satisfait plus rien. La sous-chaîne, elle, demeure à l'intérieur de ce périmètre (« Magasin » ⊂ « Magasinier »).

**Le maître écrit l'apostrophe DROITE** — 581 fois contre 39 typographiques. C'est aussi la sûre : les polices intégrées des PDF ne couvrent pas U+2019, qui disparaît du papier sans rien signaler.

**Le maître distingue le PLURIEL du SINGULIER**, et ce n'est pas une négligence : une option de filtre désigne un ENSEMBLE (« Terminées »), un badge qualifie UN objet (« Terminée »). Un champ unique servant aux deux met le singulier dans une liste déroulante.

**Une garde peut aussi relire le SERVEUR** : `conformite_stocks_test.dart`
extrait `CHAMPS_CALCULES` et les types saisissables des `FormRequest` PHP
(PA-136). Une liste recopiée côté Dart ne vérifierait qu'elle-même et resterait
verte le jour où l'API changerait. Prouvez l'extraction **non vide**, sinon le
balayage est vert à vide.

**Les gardes de conformité relisent le maître, elles ne figent pas de
constantes** — `vocabulaire_pos_test.dart`, `conformite_reservation_test.dart`.
Un test qui figerait `'Encaisser'` ne vérifierait que lui-même et resterait vert
le jour où le maître change. Ces tests **échouent** si le prototype est
introuvable ; ils ne sautent pas.

État mesuré du portage : `docs/AUDIT_CONFORMITE_ECRANS_FLUTTER.md`.

## Architecture

```
lib/core/{config,database,dev,di,format,impression,navigation,rbac,responsive,router,theme}
# sync/ et network/ n'existent plus depuis « zéro réseau » (v10) : ne pas les recréer
lib/features/<module>/{domain,data,presentation}
    achats(M7) auth bar(M5) caisse comptabilite(M10) crm(M3) depenses etats(M14)
    facturation(M2) hebergement(M1) notifications(M12) parametres pos restaurant(M4)
    rh(M13) stocks(M6) tableau_de_bord(M11) tourisme(M9) vehicules(M8) ventes
```

- **Riverpod exclusivement**, providers déclarés à la main : `riverpod_generator`
  est retiré (incompatible avec `drift_dev` sur `analyzer`).
- **Un `Repository` n'expose jamais un modèle Drift ni un DTO à
  `presentation/`** — toujours une entité de domaine, sans quoi renommer une
  colonne casse un widget et la bascule offline/online cesse d'être invisible.
- Un DAO ne rend que des entités. Le contrat de dépôt ne dit **pas** d'où vient
  la donnée : c'est ce qui interdit les branches « si connecté » dans les écrans.
- (Historique : `rafraichir()` et `alignementProvider` ont disparu avec « zéro
  réseau » ; vérifié le 12/10/2026.)

## Conventions

- Identifiants en anglais, **contenu visible en français**. Les entités métier
  centrales gardent leur nom français : `Reservation`, `Facture`, jamais
  `Booking`/`Invoice`.
- Montants en **entiers** (le XOF n'a pas de sous-unité en circulation). La
  conversion depuis les `REAL` de Drift se fait au DAO, une fois.
- **Prix ET libellé figés à l'ajout** sur toute ligne (panier, service de
  réservation) : le catalogue dit ce qu'on vend aujourd'hui, la ligne dit ce qui
  a été vendu.
- Un registre fermé (`enum` + `switch` exhaustif) plutôt qu'une chaîne libre —
  un cas ajouté demain ne doit pas obtenir un comportement par omission.
- Tout cas d'usage implémentant une RG porte un `///` avec `@see EF-M#-##` /
  `RG-##`.
- Ce qui est **calculable** s'affiche en lecture seule, jamais dans un champ.

## Règles de synchronisation et de comptabilité à retenir (résumé ; détail par lot : `../docs/JOURNAL_DES_LOTS.md`)

- **Le poste fonctionne SANS le serveur** (décision du PO) : toutes les lectures viennent de Drift, l'interrupteur « Synchronisation activée » (`LecteurConfigurationPoste.synchronisationActivee()`, `poste.json`) coupe TOUT réseau, la file se remplit et repart dans l'ordre. Un nouveau chemin réseau DOIT lire cet interrupteur.
- **Comptes : seules les SUPPRESSIONS se synchronisent, jamais un mot de passe ni un hash** (décision du PO du 03/11/2026, qui remplace « les comptes ne sont pas synchronisés » et « un compte ne se supprime jamais »). Supprimer = suppression LOGIQUE (`supprime_le` + `actif` faux, jamais un DELETE ; l'auteur d'une saisie s'affiche « login (compte supprimé) », `libelleAuteurCompte`). Autorité écrite UNE fois : seul un `super_admin` supprime (`peutSupprimerDesComptes`), seul un compte NON administrateur est supprimable (`compteSupprimable`), jamais soi-même ; un administrateur se désactive. Web → postes : entité de descente `utilisateurs` (`login`, `supprime_le`), l'aligneur marque le compte local de même LOGIN, ne crée JAMAIS de compte et refuse un homonyme administrateur. Poste → web : opération de file `suppression` de la table `utilisateurs` (charge = login + login de l'auteur local) ; le serveur exige que le compte du JETON D'APPAIRAGE soit super_admin (sinon `droit_manquant` lisible dans « À traiter », le compte reste supprimé localement). Preuve : `suppression_compte_test.dart`, `suppression_compte_contre_serveur_test.dart` (script `tool/transverse/rejouer_suppression_compte.php`).
- **Valeur d'achat, CMP et valeur de stock sur TOUS les postes (09/11/2026, bug du PO : « — » sur le poste du gérant)** : un poste ne reçoit AUCUNE valeur calculée, il RECALCULE le CMP en rejouant `mouvements_stock_local` — il faut donc que le COÛT de chaque entrée valorisée descende avec son mouvement. Le serveur le porte sur `mouvements_stock.cout_unitaire` (DECIMAL 15,4, écrit par `MouvementStockService::entree`, seul point d'écriture ; rattrapage de l'existant depuis le journal de réception, jamais déduit du CMP), `CatalogueDescendantService::COLONNES['mouvements_stock']` le livre (`cout_unitaire`, chaîne décimale), l'aligneur (`aligneur_documents.dart`, `_mouvement`) l'écrit en dix-millièmes ET le complète sur une ligne déjà reçue sans coût (jamais réécrit s'il est présent). Piège 11 vécu une troisième fois : l'envoi portait déjà le coût, la DESCENTE non. Preuve : `ValeursDeStockDescendantesTest` (PHP, base privée) et `valeurs_stock_contre_serveur_test.dart` (script `tool/stocks/rejouer_valeurs_stock.php`, base privée `TATACORA_BASE_ESSAI=tatacora_<x>_test` : serveur = poste A = poste B, article sans prix, CMP à décimales, redescente, rôle gérant). Mutation : retirer `cout_unitaire` de `COLONNES` ou de l'aligneur fait rougir les deux. Le gérant n'est masqué nulle part (M6 = C, aucune colonne réservée).
- **Propagation entre postes** : l'ÉPOQUE du serveur (compteur de changements acceptés) est rendue dans la réponse du battement de 30 s (`GET /sync/demande`, `data.epoque`) ; changée, le poste lance une DESCENTE seule (`SyncManager.synchroniserDescenteSeule`, jamais un envoi), l'époque n'étant retenue qu'après une descente « à jour ». Jamais bloquante, interrupteur respecté, le battement tourne aussi en « Manuelle seulement ». Le bouton « Demander la synchronisation des postes » existe déjà (page « Appairage Postes »).
- **File d'envoi** : seul `OperationsSyncDao` écrit `operations_sync_local`, `enfiler` exige une transaction ; chaque écrivain enfile dans SA transaction. Les aligneurs de la descente (`AligneurCatalogue`, `aligneur_documents.dart`) n'enfilent JAMAIS et conservent toute ligne locale encore en attente.
- **Écrivain unique par table** (DAO) ; il rejoue les règles et les PHRASES du serveur, confrontées au vrai PHP par un script `tool/**/rejouer_*.php` (`TATACORA_BASE_ESSAI=tatacora_<x>_test` pour une base privée).
- **Facturation normalisée (07/11/2026, `../docs/SPEC_FACTURATION_NORMALISEE_MECEF.md`)** : trois modes, `facturation_mode` (désactivé / e-MECeF / boîtier CC300), MODIFIABLES au poste comme au web par l'ADMINISTRATEUR seulement (09/11/2026, `reserveAdministrateur` ; mode, adresse de l'API, opérateur ×2, forme juridique) : écriture enfilée, hors ligne possible, et le serveur n'accepte que si le compte du JETON D'APPAIRAGE est administrateur (sinon `droit_manquant` lisible dans « À traiter », valeur conservée localement) ; passer en boîtier / e-MECeF ne normalise jamais seul ; la surcharge locale « ce poste certifie par » et l'adresse du pilote vivent dans `poste.json` (`facturation_surcharge`, `facturation_boitier_adresse`). **LE JETON e-MECeF NE DESCEND JAMAIS AU POSTE** : il est chiffré au serveur (`secrets_configuration`), n'est dans aucun registre ni descente, ce poste ne le saisit ni ne l'affiche, la section reste « Géré au serveur » (garde : `reglage_facturation_poste_test`, qui balaie `lib/` ; côté serveur `ReglageFacturationNormaliseeTest` lit le code de la descente). Le boîtier : `ClientMecefBoitier` parle au pilote `eltrade-cc300-driver` (200 même en cas d'échec : le corps se VALIDE ; montants ENTIERS ≤ 2^24−1 ; jamais deux `POST /bill` ; compteur lu avant/après, noté sur la pièce avant l'envoi : une réponse perdue avec compteur avancé = « à vérifier », JAMAIS rejouée). Aucune requête au pilote si le mode effectif du poste n'est pas « boîtier ». Une facture NORMALISÉE est figée (`FactureDejaNormalisee`) ; sa correction est un AVOIR, normalisé aussi (`rt = FA`, `rn = NIM-TC`). Le serveur RANGE le résultat envoyé (`GestionnaireFactures::normaliser`), il n'appelle jamais le boîtier. QR et mentions sur le papier SEULEMENT si `estNormalisee` (statut + numéro réel + QR) ; sinon AUCUNE mention en mode désactivé (facture SIMPLE : plus de bandeau ni de filigrane DEMO), « Facture en attente de normalisation » en boîtier / e-MECeF. **Lot 4 (décisions du PO du 07/11/2026, spec §10)** : la normalisation est un BOUTON (jamais automatique à l'émission ; case « Normaliser maintenant » décochée, jamais bloquante) ; l'IFU du CLIENT (facultatif, 13 chiffres, `IfuClient`, mêmes phrases que le web) se saisit à la validation (modale de clôture d'un séjour, lien « IFU du client » au comptoir) ; l'avoir d'une facture NORMALISÉE ne se fait QU'EN LIGNE (`ServiceFacturationEnLigne.avoir`, jeton d'appairage, interrupteur respecté ; le DAO lève `AvoirEnLigneRequis` AVANT toute écriture, l'avoir naît au serveur et descend) ; le poste en mode e-MECeF demande la normalisation AU SERVEUR (`normaliserParLeServeur`, jamais la DGI, jamais le jeton) ; `chargeAnnulationFacture` ne porte plus d'`avoir_id`. Preuve des réglages écrits au poste contre le vrai PHP : `reglages_facturation_contre_serveur_test.dart` (`tool/parametres/rejouer_reglages_facturation.php`). Preuve contre le vrai PHP : `facturation_en_ligne_contre_serveur_test.dart` (base privée `tatacora_factonligne_test`, script `tool/facturation/rejouer_facturation_en_ligne.php`).
- **Comptabilité** : `MoteurComptable` est le seul à écrire `ecritures_local` (RG-11 : une pièce validée est immuable). Il n'enfile QUE les comptes du plan et les pièces saisies à la main (D246 rouvert le 28/10/2026) ; les pièces des modules (ventes, dépenses, règlements, clôture) ne partent jamais, le serveur passe les siennes. `ecritures_serveur_local` est un miroir de lecture, jamais mêlé aux pièces du poste.
- **Affectation du résultat selon la FORME JURIDIQUE (09/11/2026, décision du PO : « le Gîte est une entreprise individuelle »)** : paramètre `forme_juridique` (`entreprise_individuelle` par DÉFAUT, `sarl`, `sa`), réglé par un administrateur au web OU au poste (refusé tant qu'une affectation est active, `existeUneActive`), reçu/descendu comme tout paramètre (`reserveAdministrateur`, lecteur `forme_juridique.dart`, schéma INCHANGÉ v53). Entreprise individuelle : ni réserve légale ni dividendes (refus, y compris dans la pièce d'un poste), le reste au compte de l'exploitant (rôle `COMPTE_EXPLOITANT`, **1041** : 104 est une division du plan) ; société : réserve légale obligatoire (10 % de bénéfice − pertes antérieures jusqu'à 20 % du capital 101x), dividendes bornés par les capitaux propres, alerte sous la moitié du capital, ordre d'imputation d'une perte 121 → 1181 → 1291. Contre-passation : date du jour dans N OUVERT, jamais avant la pièce, référence de la décision facultative, refusée si un dividende est réglé. Même logique, mêmes phrases côté Dart (`affectation_resultat.dart`, `affectation_resultat_locale.dart`, `messages_affectation.dart`) ; preuve contre le vrai PHP : `affectation_forme_contre_serveur_test` et `affectation_contre_serveur_test` (`rejouer_affectation.php`, clé d'entrée `forme_juridique`). **Un test de société pose la forme (`poserFormeJuridique`)** : sans elle, c'est l'entreprise individuelle. Détail : `../docs/CLOTURE_EXERCICE_SYSCOHADA.md` §4 ter.
- **Schéma** : migrations ADDITIVES et conditionnelles (`PRAGMA table_info`), jamais déduire de données, fixture de retour arrière dans `test/core/database/retour_arriere_schema.dart`, `build_runner` après tout changement de table. Version courante : **v56, 82 tables** (v56, 09/11/2026 : LE COÛT DES ENTRÉES DE STOCK DESCEND — AUCUNE table ni colonne, `descente.curseur` oublié (`from < 56`), entrée `56: []` dans `retour_arriere_schema.dart`, preuve `migration_v56_cout_stock_test` ; v55 appartient à un autre chantier ; v54, 09/11/2026 : TROIS DROITS TRANSVERSES OUVERTS À TOUS — AUCUNE table ni colonne, `SYNCHRO`/`APPAIRAGE`/`IMPORT_EXPORT` posés dans `roles_local.droits_json` et `utilisateurs_local.droits_json` là où la clé manque (`L`, `C` pour l'administration, jamais réécrits ni retirés), `droits_ouverts_a_tous_migration.dart`, entrée `54: []` dans `retour_arriere_schema.dart` ; v53, 09/11/2026 : AFFECTATIONS DU RÉSULTAT REÇUES du serveur (PO : « une affectation passée au web DOIT apparaître sur le poste ») — UNE table neuve, `affectations_resultat_local` (miroir de lecture : année de l'exercice, résultat signé, ventilation, numéro de pièce du serveur, `piece_origine_id`, login de l'auteur, date, `contrepassee_le`), aucune colonne ajoutée, migration conditionnelle + `_ajoutsParVersion[53]` + `tablesAjouteesEnV53` (à ajouter dans chaque test de migration qui énumère les tables des versions), curseur de descente oublié ; écrivain UNIQUE `AffectationsRecuesDao` (appelé par l'aligneur, qui n'enfile jamais) ; `AffectationResultatLocale.active()` relie la ligne reçue à la pièce de CE poste par l'identifiant d'origine (jamais deux affichages) ; une affectation passée ailleurs se contre-passe là où elle a été passée ; la classe Drift d'une table locale finit par `Local`, sinon la table s'appelle `…_locale`) ; v52, 07/11/2026 : FACTURE PROFORMA (document NON fiscal, `docs/SPEC_FACTURE_PROFORMA.md`) — TROIS tables neuves, `proformas_local`, `lignes_proforma_local`, `sequences_proforma_local` (compteur des numéros PROVISOIRES `PROV-FP-AAAA-NNNNN`), aucune colonne ajoutée, migration conditionnelle + `_ajoutsParVersion[52]` + `tablesAjouteesEnV52` (à ajouter dans chaque test de migration qui énumère les tables des versions), curseur de descente oublié ; écrivain UNIQUE `ProformaDao` (file d'envoi dans la même transaction, jamais de numéro définitif au poste, régularisé à l'accusé par `SyncManager`, conversion par `FactureDao.emettre`, `adopterDescendue` pour les proformas reçues) ; images signature/cachet reçues par `TelechargementImagesDocument` (jamais déposées au poste) ; v51, 07/11/2026 : IFU du client — TROIS colonnes nullables, `pieces_facturation_local.acheteur_ifu` / `.acheteur_nom` (ce qui est saisi pour la facture, figé avec elle) et `clients_local.ifu` (descendu du serveur, lecture seule, préremplit la facture), migration conditionnelle + `_ajoutsParVersion[51]`, curseur de descente oublié ; v50, 07/11/2026 : facturation normalisée — HUIT colonnes nullables sur `pieces_facturation_local` (statut, motif, voie, compteur, compteur avant l'envoi, code MECeF, QR fiscal, date), aucune pièce déduite ni rejouée, une pièce NORMALISÉE n'est jamais écrasée ; v49, 03/11/2026 : `utilisateurs_local.telephone` et `.intitule_de_poste` nullables — « Mon profil » modifiable SOUS DROIT, trois droits `PROFIL_NOM`/`PROFIL_TELEPHONE`/`PROFIL_INTITULE` posés additivement dans les matrices, profil LOCAL jamais synchronisé ; v48, 03/11/2026 : `utilisateurs_local.supprime_le` nullable — suppression LOGIQUE d'un compte, synchronisée par le LOGIN ; v47, 30/10/2026 : `plats_local.description` facultative, synchronisée dans les deux sens ; v46, 29/10/2026 : mot de passe perdu sans e-mail — onze colonnes sur `utilisateurs_local` et `journal_securite_local`, local, jamais synchronisé).
- **Menu ouvert à tous (09/11/2026, décision du PO)** : « Synchronisation » (`/synchronisation`, l'état : file, envoi, réception, échecs ; au web la page des journaux Réception/Envoi, ex-onglets de la page des postes), « Import & Export » et « Appairage Postes » (`/synchronisation-postes`, qui porte aussi, en section « Appairage du poste », l'ex-onglet « Appairage Postes » des Paramètres : adresse du serveur, « Synchronisation activée », fréquence, appairer, dissocier, tester) sont au menu de TOUS les rôles par défaut, le gérant compris (`nomsMasquesParRole` ne les porte plus). Trois droits transverses HORS ÉCRAN comme `ANNULATIONS` (`ModuleTatacora.synchro/appairage/importExport`, serveur : `RolePermissionSeeder::DROITS_OUVERTS_A_TOUS`, `L` pour tous, `C` administration, rôle créé à l'écran = `L`) : ils ne commandent que la VISIBILITÉ ; chaque geste garde sa garde (révoquer, appairer, dissocier, adresse du serveur : administrateurs ; « Renvoyer »/« Débloquer » : administrateurs ; sauvegardes, restauration, export de table : lecture de `PARAM` ; import : écriture sur le module choisi, `PARAM` en C au web). Les routes `/synchronisation-postes` et `/synchronisation` ne sont plus « ouvertes à tout compte » : elles suivent leur droit (garde `garde_routes_test`, qui relit `routes/web.php`). **« Réinitialiser les données de test » est revenue dans Paramètres › Activation & Sécurité** (web `partials/reinitialisation-donnees-test`, poste `section_reinitialisation.dart`), bouton marine, logique et verrous INCHANGÉS ; elle n'est plus dans Import & Export. Preuve : `EntreesMenuOuvertesATousTest` (PHP) et `entrees_ouvertes_a_tous_test` (Dart), mutations par rôle.
- **Gardes à connaître** : comparateur Blade (`node tool/conformite_blade/t-blade-flutter.js`, `--figer-dette` seulement pour un progrès réel), `echelle_contenu_test` (classer tout nouveau fichier qui emploie une taille de texte), `pdf_directive_test` (classer tout nouveau PDF), `PwaActionsReluesTest` + `PwaEcritureAutoriseeTest` côté PHP (toute action Livewire publique y est inscrite).
- **Tout test de mesure fige l'horloge** (emplacement, géométrie, structure) : `test/support/horloge_reference.dart` (26/10/2026 12:00, le jour du relevé Blade) via `surchargesHorlogeDeReference()` ; le générateur PHP `ExtraireStructureBladeTest` fige le même instant (`Carbon::setTestNow`). Le cliquet d'emplacement avait reculé le 03/11/2026 sans changement de code (mois courant ≠ « octobre 2026 » du relevé).
- **Environnement de session** : MySQL s'arrête entre deux tours (`service mysql start`) ; Flutter dans `/home/user/flutter/bin` ; suite complète Flutter ~20 min, PHP ~17 min (à lancer en arrière-plan, lire la dernière ligne et les échecs seulement). Après un `git push`, rafraîchir la référence de suivi : `git fetch origin +refs/heads/<branche>:refs/remotes/origin/<branche>` (sinon le hook annonce de faux « commits non poussés »).
- **Fenêtre du poste (09/11/2026, PO)** : la barre de titre NATIVE est masquée (`ControleFenetreWindows.preparer()`, `window_manager ^0.5.2` — PAS la 0.6.0, réécrite sur `nativeapi`) et la barre supérieure de la coquille porte réduire / agrandir-restaurer / fermer (`core/fenetre/boutons_fenetre.dart`, écart « poste Windows seulement » à `partials/barre-superieure` l.112 : le web n'en a pas) et la zone de déplacement. Tout passe par le seam `ControleFenetre` : `controleFenetreProvider` rend `null` hors Windows et tant que la barre native n'est pas masquée (barre = vue, aucun bouton en double) ; un test fournit un faux. Le runner garde `WS_OVERLAPPEDWINDOW` (le plugin commande par `WM_SYSCOMMAND`, que `DefWindowProc` ignore sans `WS_SYSMENU`/`MINIMIZEBOX`/`MAXIMIZEBOX`) et traite `WM_GETMINMAXINFO` AVANT les greffons (le plugin y répond 0) : les deux sont relus dans le source par `boutons_fenetre_test.dart`. Libellés : `LibellesFenetre`, mesures : `MesuresFenetre` (jamais dans `LibellesCoquille`, confronté aux clés PHP). Barre compacte sous 1160 px (la barre débordait déjà de 800 à 1040 px). Aucune garde de fermeture côté Dart : rien à vider, tout est dans SQLite. Pas de touche F11 (la « bascule plein écran » est celle du menu latéral). Seul Windows prouve le rendu réel.
- **Où est le reste** : historique et pièges de chaque lot dans `../docs/JOURNAL_DES_LOTS.md` ; ce qui reste à faire dans `../docs/RESTE_A_FAIRE.md` ; inventaire poste/web dans `../docs/INVENTAIRE_POSTE_LECTURE_SEULE.md` ; audit hors ligne dans `../docs/AUDIT_POSTE_AUTONOME.md`.
