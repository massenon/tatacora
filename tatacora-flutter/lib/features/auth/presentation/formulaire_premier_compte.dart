import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../parametres/data/parametres_depot_local.dart';
import '../../transverse/presentation/widgets/modale_secret_unique.dart';
import '../impression/feuille_code_secours.dart';
import '../domain/mot_de_passe_perdu.dart';
import '../domain/session_repository.dart';

/// La création du **premier compte**, sur un poste vierge.
///
/// ## Pourquoi cet écran existe, et pourquoi il n'a pas d'équivalent au maître
///
/// L'authentification étant locale (décision du Product Owner, 21/08/2026), un
/// poste neuf n'a **aucun compte**. Le maître HTML n'a pas ce problème : il
/// fabrique une session de démonstration.
///
/// **Il fallait donc choisir entre trois options, et deux étaient mauvaises :**
///
///  1. **poser un compte par défaut dans une migration ou un seeder** — son
///     mot de passe serait écrit dans le code, donc connu de quiconque lit le
///     dépôt, et personne ne le changerait jamais. C'est le mode d'entrée le
///     plus courant sur un logiciel de gestion, et `SECURITY_STRICT.md` §12
///     interdit déjà l'esprit de cette facilité ;
///  2. **laisser le formulaire de connexion refuser en boucle** — l'exploitant
///     ne saurait pas que le poste est vierge et croirait avoir mal saisi ;
///  3. **demander à l'exploitant de poser son mot de passe**, une fois, au
///     premier démarrage. C'est ce qui est fait.
///
/// **Aucun mot de passe par défaut n'existe nulle part dans ce dépôt.**
///
/// ## Le rôle attribué
///
/// `administrateur`, avec `C` sur les **seize** modules. Le premier compte doit
/// pouvoir créer les suivants ; sans accès à `ROLES`, le poste resterait à un
/// seul utilisateur pour toujours.
///
/// La matrice est écrite **module par module**, jamais par une boucle sur
/// l'énumération : le jour où un module s'ajoute, il n'obtiendra pas un droit
/// d'écriture par simple effet de bord. Un droit ne s'obtient jamais par
/// omission — même règle que les 16 clés de `droits` renvoyées par l'API
/// (PA-54).
class FormulairePremierCompte extends ConsumerStatefulWidget {
  const FormulairePremierCompte({super.key});

  @override
  ConsumerState<FormulairePremierCompte> createState() =>
      _EtatFormulairePremierCompte();
}

class _EtatFormulairePremierCompte
    extends ConsumerState<FormulairePremierCompte> {
  final _formulaire = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _nom = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _login.dispose();
    _nom.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// `C` sur les seize modules — écrits un par un, volontairement.
  static const Map<String, String> _droitsAdministrateur = {
    'M1': 'C',
    'M2': 'C',
    'M3': 'C',
    'M4': 'C',
    'M5': 'C',
    'M6': 'C',
    'M7': 'C',
    'M8': 'C',
    'M9': 'C',
    'M10': 'C',
    'M11': 'C',
    'M12': 'C',
    'M13': 'C',
    'M14': 'C',
    'ROLES': 'C',
    'PARAM': 'C',
  };

  Future<void> _creer() async {
    if (!_formulaire.currentState!.validate()) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final depot = ref.read(depotSessionProvider);
      await depot.creerCompte(
        login: _login.text,
        nom: _nom.text,
        motDePasse: _motDePasse.text,
        role: 'administrateur',
        droits: _droitsAdministrateur,
      );
      // POSTE VIERGE (Lot J2, directive du PO du 14/10/2026) : les vingt
      // paramètres d'établissement du serveur (`ParametresEtablissementSeeder`)
      // — paie, TVA, en-tête des documents — sont posés ICI, au seul moment où
      // le poste n'a encore aucun compte. Chaque clé absente seulement : rien
      // de déjà saisi n'est réécrit. Un échec n'empêche pas d'entrer : les
      // paramètres restent « — » et se saisissent à l'écran Paramètres.
      try {
        await ParametresDepotLocal(
          ref.read(baseLocaleProvider),
        ).installerParametresInitiaux();
      } on Object catch (e, pile) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: pile,
            library: 'tatacora',
            context: ErrorDescription(
              'en posant les paramètres initiaux du poste vierge',
            ),
          ),
        );
      }
      // LE CODE DE SECOURS (29/10/2026, option A du PO) : le premier compte est
      // l'administrateur ; s'il perd son mot de passe, personne d'autre ne peut le
      // réinitialiser. Le code à usage unique est affiché UNE seule fois — copier,
      // imprimer, ranger au coffre —, seul son dérivé est stocké. Un échec n'empêche
      // pas d'entrer : l'administrateur en génère un depuis « Mon profil → Code de
      // secours ».
      String? codeSecours;
      try {
        codeSecours = await ref
            .read(codeSecoursProvider)
            .poser(login: _login.text);
      } on Object catch (e, pile) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: pile,
            library: 'tatacora',
            context: ErrorDescription(
              'en posant le code de secours du premier compte',
            ),
          ),
        );
      }
      if (codeSecours != null && mounted) {
        final code = codeSecours;
        final login = _login.text.trim().toLowerCase();
        await ouvrirModaleSecretUnique(
          context,
          titre: MessagesMotDePassePerdu.codeSecoursAfficheTitre,
          secret: code,
          consigne: MessagesMotDePassePerdu.codeSecoursConsigne,
          libelleFermer: MessagesMotDePassePerdu.codeSecoursFermer,
          surImprimer: () => ref.read(imprimerCodeSecoursProvider)(code, login),
          prefixeCle: 'premier-compte-code',
        );
      }
      // On enchaîne sur la connexion : demander de ressaisir ce qu'on vient de
      // taper serait une friction gratuite au premier contact avec le logiciel.
      await ref
          .read(sessionProvider.notifier)
          .connecter(_login.text, _motDePasse.text);
    } on EchecConnexion catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formulaire,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Premier démarrage',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.navy,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Ce poste ne contient aucun compte. Créez celui de '
            'l’administrateur pour commencer.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.neutre500,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t15,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),
          _champ(
            controleur: _login,
            etiquette: 'Identifiant',
            indication: 'ex. n.nabogou',
            valider: (v) => (v == null || v.trim().isEmpty)
                ? 'Veuillez saisir un identifiant.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _champ(
            controleur: _nom,
            etiquette: 'Nom complet',
            indication: 'ex. NABOGOU Winribasse Noël',
            valider: (v) => (v == null || v.trim().isEmpty)
                ? 'Veuillez saisir un nom.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _champ(
            controleur: _motDePasse,
            etiquette: 'Mot de passe',
            indication: '8 caractères au minimum',
            masque: true,
            valider: (v) => (v == null || v.length < 8)
                ? 'Le mot de passe doit compter au moins 8 caractères.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _champ(
            controleur: _confirmation,
            etiquette: 'Confirmer le mot de passe',
            indication: 'à l’identique',
            masque: true,
            // La confirmation n'est pas une politesse : un mot de passe posé
            // avec une faute de frappe verrouillerait le poste, et il n'y a
            // aucun serveur pour le réinitialiser.
            valider: (v) => (v != _motDePasse.text)
                ? 'Les deux saisies ne correspondent pas.'
                : null,
          ),

          if (_erreur != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.erreurFondLeger,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.erreurBordure),
              ),
              child: Text(
                '⚠ $_erreur',
                style: TextStyle(
                  color: AppColors.erreur,
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t15,
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: _enCours ? null : _creer,
            child: _enCours
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.neutre0,
                    ),
                  )
                : const Text('Créer le compte administrateur'),
          ),

          const SizedBox(height: AppSpacing.md),
          Text(
            'Ce mot de passe n’est enregistré nulle part en clair et ne peut '
            'pas être récupéré. Conservez-le.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.neutre500,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _champ({
    required TextEditingController controleur,
    required String etiquette,
    required String indication,
    required String? Function(String?) valider,
    bool masque = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: etiquette),
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.erreur),
              ),
            ],
          ),
          style: TextStyle(
            color: AppColors.neutre700,
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controleur,
          obscureText: masque,
          decoration: InputDecoration(hintText: indication),
          validator: valider,
        ),
      ],
    );
  }
}

/// Y a-t-il au moins un compte sur ce poste ?
final aucunCompteProvider = FutureProvider<bool>((ref) async {
  return ref.watch(depotSessionProvider).aucunCompteExiste();
});

/// Garde-fou de lecture : la matrice ci-dessus couvre-t-elle bien TOUS les
/// modules connus ? Employée par les tests.
bool matriceComplete(Map<String, String> matrice) =>
    ModuleTatacora.values.every((m) => matrice.containsKey(m.code));
