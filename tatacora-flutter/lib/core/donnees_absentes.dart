/// Ce qu'un écran dit d'une donnée que ce poste ne détient pas.
///
/// ## Pourquoi ce fichier existe (décision du Product Owner, 14/09/2026)
///
/// Le poste est **zéro réseau** : toute la couche de synchronisation a été
/// retirée, et avec elle les onze clients HTTP qui alimentaient M4, M6, M7,
/// M8, M11, M14 et l'écran Paramètres. Ces modules n'ont **aucune table
/// locale** — leur donnée était calculée par le serveur, jamais répliquée.
///
/// ⚠ Phrase du 14/09/2026, PÉRIMÉE pour la plupart de ces modules (revu le
/// 12/10/2026) : M4, M6, M7, M10, M11, M14 et Paramètres sont devenus LOCAUX
/// (09-12/10/2026). Avant d'employer [donneeNonDisponible], vérifiez que la
/// donnée n'a vraiment aucune source sur le poste : la phrase dit « calculée par
/// le serveur … aucun chiffre ne peut être affiché à la place », ce qui est faux
/// dès que les pièces ou les tables sont ici (le pilotage consolidé l'affichait
/// encore pour M10 jusqu'au 12/10/2026 — `PilotageApi.raisonAbsence`).
///
/// Trois façons de le dire étaient possibles, et deux sont des mensonges :
///
///  1. **Un zéro.** « Stock : 0 », « Chiffre d'affaires : 0 F ». Plausible,
///     donc invisible — c'est le défaut PA-59/60/61, appliqué cette fois à
///     l'argent et au stock.
///  2. **« Serveur injoignable. »** C'est ce que les écrans disaient, et ce
///     serait devenu faux le jour même : il n'y a plus de serveur à joindre,
///     donc plus rien à réessayer. La phrase enverrait l'exploitant vérifier
///     un routeur, attendre, recommencer — indéfiniment.
///  3. **Le dire.** La donnée n'existe pas sur ce poste, et ce n'est ni une
///     panne, ni un droit manquant, ni un état passager.
///
/// Une seule formulation, à un seul endroit : deux phrases voisines écrites
/// dans deux écrans finissent par se contredire, et l'exploitant y lit deux
/// causes distinctes pour une seule situation.
library;

/// La phrase unique — [quoi] nomme la donnée, au pluriel ou au singulier.
///
/// Exemples : `donneeNonDisponible('Les mouvements de stock')`,
/// `donneeNonDisponible('Le catalogue des boissons')`.
String donneeNonDisponible(String quoi) =>
    '$quoi : information non disponible.';

/// La même chose pour une ÉCRITURE que le poste ne peut pas porter.
///
/// Distincte de la lecture, et la distinction compte : une lecture absente
/// laisse l'écran vide, une écriture refusée laisse une **saisie** à l'écran.
/// Dire « rien n'a été enregistré » évite que l'exploitant croie son geste
/// pris en compte et le rejoue.
String ecritureNonDisponible(String quoi) =>
    '$quoi ne peut pas être enregistré. Rien n’a été enregistré, et la saisie '
    'reste affichée.';
