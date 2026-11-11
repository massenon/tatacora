/// Les modales de M13 — fiche employé, établissement, annulation, archivage,
/// bulletin.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Le cadre est celui de `x-pwa.modale`
///
/// Toutes reprennent [CoquilleModaleRestaurant] — en-tête titre et sous-titre,
/// corps borné, pied sur fond `slate-50` — et non un `AlertDialog` : c'est le
/// composant que la vue invoque, avec sa largeur propre (jetons
/// `AppLayout.modalePaie*`).
///
/// ## Ce qui n'est PAS rendu, et pourquoi
///
/// - **Le « + Ajouter un élément »** de la modale d'établissement, et avec lui
///   les primes et retenues du mois : aucune table de primes n'est alimentée
///   dans ce dépôt. Un champ qui n'écrirait nulle part serait un faux écran
///   (PA-126). La vue l'omet aussi (l.971-974).
/// - **« Téléphone » et « Centre analytique »** de la fiche employé : aucune
///   colonne ne les porte, ici comme au serveur (l.859-861).
///
/// Aucun de ces blocs n'est rendu inerte : ils sont omis, et nommés ici.
///
/// ## « Imprimer » et « PDF » du bulletin — PORTÉS (27/10/2026, lot A3)
///
/// La vue : « Imprimer » appelle `window.print()` sur la modale et « PDF »
/// télécharge `pdf.paie-bulletin` (l.1175-1178). Le texte du 09/10/2026 (« ces
/// deux boutons DISENT que le poste ne produit pas le document ») est PÉRIMÉ :
/// `BulletinPaieA4` (`impression/bulletin_paie_a4.dart`) compose le papier, par
/// le gabarit commun (`enTeteA4`, `texteTicket`). « Imprimer » ouvre la boîte
/// d'impression du système ([imprimerBulletinProvider]), « PDF » enregistre
/// `bulletin_<numéro>.pdf` ([exporterBulletinPdfProvider]) : deux actions
/// injectables, en LECTURE (aucun droit d'écriture, comme `exporterPdf`).
///
/// ## L'échelle typographique est celle des MODALES
///
/// Les conteneurs de modales sont hors `<main>` : le remappage de `app.css` ne
/// les atteint pas, et `text-[13px]` y vaut bien 13 px. C'est [Tailles], pas
/// `TaillesContenu`.
library;

// `hide Simulation` — voir `providers_rh.dart` : le type métier garde son nom,
// celui de la physique des animations s'efface, il n'est pas employé ici.
import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/adresse_email_facultative.dart';
import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/entities/bulletin_paie.dart';
import '../../domain/entities/employe.dart';
import '../../domain/refus_rh.dart';
import '../../domain/services/bulletin_paie_service.dart';
import '../../../../shared_widgets/toast_export.dart';
import '../../impression/bulletin_paie_a4.dart';
import '../providers_rh.dart';
import 'panneaux_paie.dart';

/* ====================================================================== */
/* Styles — la vue, classe par classe                                      */
/* ====================================================================== */

abstract final class _Textes {
  /// `text-[13px] font-semibold text-slate-700 mb-1.5` — l'étiquette d'un champ.
  static const TextStyle etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  /// `text-red-500` — l'astérisque des champs obligatoires.
  static const TextStyle asterisque = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: PaletteMaitre.rouge500,
  );

  /// `text-[13px]` d'un champ.
  static const TextStyle champ = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c700,
  );

  /// `text-[13px] text-slate-600`.
  static const TextStyle corps = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c600,
  );

  /// `text-[11px] text-slate-400` — l'aide sous un champ.
  static const TextStyle aide = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t11,
    color: Ardoise.c400,
  );

  /// `text-[12px]` — une ligne de tableau ou d'aperçu.
  static const TextStyle ligne = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c600,
  );

  /// `text-[12px] text-red-600` — une erreur sous un champ.
  static const TextStyle erreur = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: PaletteMaitre.rouge600,
  );

  /// `text-[13px]` d'un bouton de pied.
  static const TextStyle bouton = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
  );

  /// `text-[13px] font-semibold` d'un bouton plein.
  static const TextStyle boutonPlein = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
  );

  /// `px-3 py-2.5` d'un champ plus la bordure, que le navigateur compte dans
  /// la boîte et pas Flutter.
  static const EdgeInsets remplissageChamp = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm + AppLayout.bordureControle,
    vertical: AppSpacing.xsPlus + AppLayout.bordureControle,
  );

  /// `border border-slate-300 rounded-lg`.
  static OutlineInputBorder get bordure => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );

  static InputDecoration decoration({String? invite, TextStyle? styleInvite}) =>
      InputDecoration(
        hintText: invite,
        hintStyle: (styleInvite ?? champ).copyWith(color: Ardoise.c400),
        isDense: true,
        contentPadding: remplissageChamp,
        border: bordure,
        enabledBorder: bordure,
        focusedBorder: bordure,
        errorStyle: erreur,
      );

  /// Le gabarit d'un bouton de pied : `text-[13px] px-4 py-2 rounded-lg`,
  /// bordé en `slate-300` ou plein ([fond]).
  static ButtonStyle styleBouton({Color? fond}) {
    final forme = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    );
    const remplissage = EdgeInsets.symmetric(
      horizontal: AppSpacing.md + AppLayout.bordureControle,
      vertical: AppSpacing.xs + AppLayout.bordureControle,
    );

    return fond == null
        ? OutlinedButton.styleFrom(
            padding: remplissage,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Ardoise.c700,
            side: const BorderSide(color: Ardoise.c300),
            shape: forme,
          )
        : FilledButton.styleFrom(
            padding: remplissage,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: fond,
            foregroundColor: AppColors.neutre0,
            shape: forme,
          );
  }
}

/// Une étiquette de champ, avec l'astérisque des champs obligatoires.
class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte, {this.obligatoire = false});

  final String texte;
  final bool obligatoire;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `mb-1.5`.
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: texte, style: _Textes.etiquette),
            if (obligatoire)
              const TextSpan(text: ' *', style: _Textes.asterisque),
          ],
        ),
      ),
    );
  }
}

/// Le bouton « Annuler » commun aux pieds de modale (`pwa.modale.annuler`).
Widget _boutonAnnuler(BuildContext context, {Key? cle}) => OutlinedButton(
  key: cle,
  style: _Textes.styleBouton(),
  onPressed: () => Navigator.of(context).pop(),
  child: const Text('Annuler', style: _Textes.bouton),
);

/// Une erreur affichée DANS la modale, jamais en `SnackBar` : la saisie est
/// encore là, et le message doit rester lisible pendant qu'on la corrige.
Widget _erreur(String message, Key cle) =>
    Text(message, key: cle, style: _Textes.erreur);

/* ====================================================================== */
/* Fiche employé                                                           */
/* ====================================================================== */

/// « Nouvel employé » / « Modifier [matricule] » (l.862-968).
///
/// ## Les homonymes AVERTISSENT, ils ne bloquent pas
///
/// RG-18 appliquée au personnel : deux homonymes réels existent dans un
/// village. Refuser la saisie ferait contourner le contrôle par une faute
/// d'orthographe volontaire, et le doublon deviendrait indétectable. La
/// confirmation est donc un **second geste explicite**.
Future<void> ouvrirFicheEmploye(
  BuildContext context,
  WidgetRef ref, {
  Employe? employe,
}) async {
  final services = await ref.read(servicesRhProvider.future);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (context) => _FicheEmploye(employe: employe, services: services),
  );
}

class _FicheEmploye extends ConsumerStatefulWidget {
  const _FicheEmploye({required this.employe, required this.services});

  final Employe? employe;
  final List<ServiceRh> services;

  @override
  ConsumerState<_FicheEmploye> createState() => _FicheEmployeState();
}

class _FicheEmployeState extends ConsumerState<_FicheEmploye> {
  final _formulaire = GlobalKey<FormState>();

  late final TextEditingController _nom = TextEditingController(
    text: widget.employe?.nom ?? '',
  );
  late final TextEditingController _prenom = TextEditingController(
    text: widget.employe?.prenom ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.employe?.email ?? '',
  );
  late final TextEditingController _poste = TextEditingController(
    text: widget.employe?.poste ?? '',
  );
  late final TextEditingController _numeroCnss = TextEditingController(
    text: widget.employe?.numeroCnss ?? '',
  );
  late final TextEditingController _salaire = TextEditingController(
    text: widget.employe?.salaireBase.toString() ?? '',
  );

  late String? _serviceId =
      widget.employe?.serviceId ??
      (widget.services.isEmpty ? null : widget.services.first.id);
  late TypeContrat _contrat = widget.employe?.typeContrat ?? TypeContrat.cdi;
  late StatutEmploye _statut = widget.employe?.statut ?? StatutEmploye.actif;
  late DateTime _embauche = widget.employe?.dateEmbauche ?? DateTime.now();
  late DateTime? _finContrat = widget.employe?.dateFinContrat;

  List<Employe> _homonymes = const [];
  bool _doublonConfirme = false;
  String? _erreurFiche;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _email.dispose();
    _poste.dispose();
    _numeroCnss.dispose();
    _salaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titre = widget.employe == null
        ? 'Nouvel employé'
        : 'Modifier ${widget.employe!.matricule}';

    return CoquilleModaleRestaurant(
      cle: const Key('paie-modale-employe'),
      titre: titre,
      largeur: AppLayout.modalePaieEmploye,
      corps: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rangee([
              _champTexte(
                'Nom',
                const Key('paie-champ-nom'),
                _nom,
                onChanged: (_) => _chercherHomonymes(),
                validator: _requis,
              ),
              _champTexte(
                'Prénoms',
                const Key('paie-champ-prenoms'),
                _prenom,
                onChanged: (_) => _chercherHomonymes(),
                validator: _requis,
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            _rangee([
              _champTexte(
                'Poste',
                const Key('paie-champ-poste'),
                _poste,
                validator: _requis,
              ),
              // VRAIE clé étrangère, jamais du texte libre : « Restauration »,
              // « restauration » et « Resto » seraient trois services.
              _champListe<String>(
                'Service',
                const Key('paie-champ-service'),
                valeur: _serviceId,
                options: [
                  for (final service in widget.services)
                    (service.id, service.libelle),
                ],
                onChanged: (valeur) => setState(() => _serviceId = valeur),
                obligatoire: true,
                validator: (valeur) =>
                    valeur == null ? 'Le service est obligatoire.' : null,
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            // E-mail FACULTATIF (v45) : sous Poste / Service, comme la vue. Le
            // validateur ne pose pas l'astérisque (champ non obligatoire) ; sa
            // phrase est celle du serveur.
            _champTexte(
              'Email',
              const Key('paie-champ-email'),
              _email,
              clavier: TextInputType.emailAddress,
              validator: AdresseEmailFacultative.erreur,
              obligatoire: false,
            ),
            const SizedBox(height: AppSpacing.md),
            _rangee([
              _champListe<TypeContrat>(
                'Contrat',
                const Key('paie-champ-contrat'),
                valeur: _contrat,
                options: [for (final t in TypeContrat.values) (t, t.code)],
                onChanged: (valeur) =>
                    setState(() => _contrat = valeur ?? _contrat),
              ),
              _champDate(
                'Embauche',
                const Key('paie-champ-embauche'),
                _embauche,
                (date) => setState(() => _embauche = date),
              ),
              _champDate(
                'Fin de contrat',
                const Key('paie-champ-fin-contrat'),
                _finContrat,
                (date) => setState(() => _finContrat = date),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            _rangee([
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Etiquette('Numéro CNSS'),
                  TextFormField(
                    key: const Key('paie-champ-numero-cnss'),
                    controller: _numeroCnss,
                    style: _Textes.champ.copyWith(
                      fontFamily: AppTextStyles.policeMonospace,
                    ),
                    decoration: _Textes.decoration(invite: 'BJ-CNSS-0000000'),
                  ),
                  // `mt-1`.
                  const SizedBox(height: AppSpacing.unit),
                  const Text(
                    'Facultatif à l’embauche, indispensable pour déclarer.',
                    style: _Textes.aide,
                  ),
                ],
              ),
              _champTexte(
                'Salaire de base (FCFA)',
                const Key('paie-champ-salaire'),
                _salaire,
                clavier: TextInputType.number,
                validator: (valeur) {
                  final montant = int.tryParse((valeur ?? '').trim());
                  if (montant == null || montant < 0) {
                    return 'Un salaire de base positif est requis.';
                  }
                  return null;
                },
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            // Les CODES du maître, tels quels : les habiller donnerait deux
            // vocabulaires pour un même dossier.
            _champListe<StatutEmploye>(
              'Statut',
              const Key('paie-champ-statut'),
              valeur: _statut,
              options: [for (final s in StatutEmploye.values) (s, s.code)],
              onChanged: (valeur) =>
                  setState(() => _statut = valeur ?? _statut),
              obligatoire: false,
            ),
            if (_homonymes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _avertissementHomonymes(),
            ],
            if (_erreurFiche != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _erreur(_erreurFiche!, const Key('paie-fiche-erreur')),
            ],
          ],
        ),
      ),
      actions: [
        _boutonAnnuler(context),
        FilledButton(
          key: const Key('paie-fiche-enregistrer'),
          style: _Textes.styleBouton(fond: AppColors.navy),
          onPressed: _enregistrer,
          child: Text(
            widget.employe == null ? 'Créer' : 'Enregistrer',
            style: _Textes.boutonPlein,
          ),
        ),
      ],
    );
  }

  /// `grid grid-cols-N gap-3` : N colonnes égales.
  Widget _rangee(List<Widget> champs) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < champs.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.sm),
        Expanded(child: champs[i]),
      ],
    ],
  );

  Widget _champTexte(
    String libelle,
    Key cle,
    TextEditingController controleur, {
    TextInputType? clavier,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
    bool? obligatoire,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Etiquette(libelle, obligatoire: obligatoire ?? validator != null),
      TextFormField(
        key: cle,
        controller: controleur,
        keyboardType: clavier,
        style: _Textes.champ,
        decoration: _Textes.decoration(),
        onChanged: onChanged,
        validator: validator,
      ),
    ],
  );

  Widget _champListe<T>(
    String libelle,
    Key cle, {
    required T? valeur,
    required List<(T, String)> options,
    required ValueChanged<T?> onChanged,
    bool obligatoire = false,
    FormFieldValidator<T>? validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Etiquette(libelle, obligatoire: obligatoire),
      DropdownButtonFormField<T>(
        key: cle,
        initialValue: valeur,
        isExpanded: true,
        style: _Textes.champ,
        decoration: _Textes.decoration(),
        items: [
          for (final (v, texte) in options)
            DropdownMenuItem<T>(value: v, child: Text(texte)),
        ],
        onChanged: onChanged,
        validator: validator,
      ),
    ],
  );

  Widget _champDate(
    String libelle,
    Key cle,
    DateTime? valeur,
    void Function(DateTime date) onChoisi,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _Etiquette(libelle),
      InkWell(
        key: cle,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        onTap: () async {
          final choisie = await showDatePicker(
            context: context,
            initialDate: valeur ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (choisie != null) onChoisi(choisie);
        },
        child: Container(
          padding: _Textes.remplissageChamp,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: Border.all(color: Ardoise.c300),
          ),
          child: Text(
            valeur == null ? tiret : formaterDate(valeur),
            style: _Textes.champ,
          ),
        ),
      ),
    ],
  );

  Widget _avertissementHomonymes() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: PaletteMaitre.ambre300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _homonymes.length == 1
                ? 'Un employé existant correspond déjà'
                : '${_homonymes.length} employés existants correspondent',
            key: const Key('paie-homonymes'),
            style: const TextStyle(
              color: PaletteMaitre.ambre900,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Une ligne par homonyme, au gabarit de la vue (l.951-952) :
          // `<strong>matricule</strong> — nom complet · poste · salaire`. Une
          // fois les valeurs retirées, il reste « — · · » : trois séparateurs,
          // dits ici et rendus par la ligne ci-dessous.
          for (final homonyme in _homonymes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.unit),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: PaletteMaitre.ambre900,
                    fontFamily: AppTextStyles.police,
                    fontSize: Tailles.t12,
                  ),
                  children: [
                    TextSpan(
                      text: homonyme.matricule,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text:
                          ' — ${homonyme.nomComplet()} · ${homonyme.poste} · '
                          '${formaterFcfa(homonyme.salaireBase)}',
                    ),
                  ],
                ),
              ),
            ),
          // `flex items-center gap-2 mt-2.5 text-[12px] text-amber-900`.
          InkWell(
            key: const Key('paie-homonymes-confirmer'),
            onTap: () => setState(() => _doublonConfirme = !_doublonConfirme),
            child: Row(
              children: [
                SizedBox(
                  width: AppLayout.casePaie,
                  height: AppLayout.casePaie,
                  child: Checkbox(
                    value: _doublonConfirme,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) =>
                        setState(() => _doublonConfirme = v ?? false),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: PaletteMaitre.ambre900,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t12,
                      ),
                      children: [
                        const TextSpan(text: 'Il s’agit bien d’une '),
                        const TextSpan(
                          text: 'personne différente',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' — enregistrer quand même.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _requis(String? valeur) =>
      (valeur ?? '').trim().isEmpty ? 'Ce champ est obligatoire.' : null;

  Future<void> _chercherHomonymes() async {
    final nom = _nom.text.trim();
    if (nom.isEmpty) {
      if (_homonymes.isNotEmpty) setState(() => _homonymes = const []);
      return;
    }

    final trouves = await ref
        .read(employeDaoProvider)
        .homonymes(nom, _prenom.text, exclureId: widget.employe?.id);

    if (!mounted) return;
    setState(() => _homonymes = trouves);
  }

  Future<void> _enregistrer() async {
    if (!_formulaire.currentState!.validate()) return;

    if (_homonymes.isNotEmpty && !_doublonConfirme) {
      setState(() {
        _erreurFiche =
            'Cet employé existe déjà. Cochez la case pour confirmer qu’il '
            's’agit d’une personne différente.';
      });
      return;
    }

    final dao = ref.read(employeDaoProvider);
    final salaire = int.parse(_salaire.text.trim());

    try {
      if (widget.employe == null) {
        await dao.creer(
          nom: _nom.text,
          prenom: _prenom.text,
          poste: _poste.text,
          serviceId: _serviceId!,
          dateEmbauche: _embauche,
          salaireBase: salaire,
          dateFinContrat: _finContrat,
          numeroCnss: _numeroCnss.text,
          typeContrat: _contrat,
          email: _email.text,
          statut: _statut,
        );
      } else {
        await dao.mettreAJour(
          widget.employe!.id,
          nom: _nom.text,
          prenom: _prenom.text,
          poste: _poste.text,
          serviceId: _serviceId!,
          dateEmbauche: _embauche,
          salaireBase: salaire,
          dateFinContrat: _finContrat,
          numeroCnss: _numeroCnss.text,
          typeContrat: _contrat,
          email: _email.text,
          statut: _statut,
        );
      }
    } on RefusRh catch (refus) {
      setState(() => _erreurFiche = refus.message);
      return;
    }

    if (!mounted) return;
    rafraichirPaie(ref);
    Navigator.of(context).pop();
  }
}

/* ====================================================================== */
/* Établir le bulletin                                                     */
/* ====================================================================== */

/// L'aperçu chiffré **avant** d'établir — calculé par le service, jamais
/// recomposé ici.
///
/// Un refus de barème s'affiche **dans la modale**, avant tout enregistrement :
/// c'est ce qui distingue « ce salarié ne peut pas être calculé » d'un
/// enregistrement qui échoue sans raison visible.
Future<void> ouvrirEtablissement(
  BuildContext context,
  WidgetRef ref,
  Employe employe,
) async {
  final service = ref.read(bulletinPaieServiceProvider);
  final apercu = await service.simuler(employe.salaireBase);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (context) => _Etablissement(employe: employe, apercu: apercu),
  );
}

class _Etablissement extends ConsumerStatefulWidget {
  const _Etablissement({required this.employe, required this.apercu});

  final Employe employe;
  final Simulation apercu;

  @override
  ConsumerState<_Etablissement> createState() => _EtablissementState();
}

class _EtablissementState extends ConsumerState<_Etablissement> {
  String? _erreurEtablissement;

  @override
  Widget build(BuildContext context) {
    final periode = ref.watch(periodeValideProvider);
    final apercu = widget.apercu;

    return CoquilleModaleRestaurant(
      cle: const Key('paie-modale-etablissement'),
      titre: 'Établir le bulletin',
      sousTitre: '${widget.employe.nomComplet()} · ${periode.libelleLong}',
      largeur: AppLayout.modalePaieEtablir,
      corps: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `bg-slate-50 border border-slate-200 rounded-lg p-3 text-[13px]`.
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Ardoise.c50,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: Ardoise.c200),
            ),
            child: Text.rich(
              TextSpan(
                style: _Textes.champ.copyWith(color: null),
                children: [
                  const TextSpan(text: 'Salaire de base '),
                  TextSpan(
                    text: formaterFcfa(widget.employe.salaireBase),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' — repris automatiquement.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (apercu.estRefusee)
            Container(
              key: const Key('paie-etablissement-refus'),
              padding: const EdgeInsets.all(AppSpacing.smPlus),
              decoration: BoxDecoration(
                color: PaletteMaitre.rouge50,
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
                border: Border.all(color: PaletteMaitre.rouge200),
              ),
              child: Text.rich(
                TextSpan(
                  style: _Textes.champ.copyWith(color: PaletteMaitre.rouge900),
                  children: [
                    const TextSpan(
                      text: 'Calcul refusé.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ' ${apercu.refus}'),
                  ],
                ),
              ),
            )
          else
            _apercuChiffre(apercu),
          if (_erreurEtablissement != null) ...[
            const SizedBox(height: AppSpacing.md),
            _erreur(
              _erreurEtablissement!,
              const Key('paie-etablissement-erreur'),
            ),
          ],
        ],
      ),
      actions: [
        _boutonAnnuler(context),
        // Le bouton reste ACTIF quand le calcul est refusé, comme dans la vue
        // (l.1005) : le clic rend alors le refus du service, mot pour mot,
        // plutôt qu'un bouton grisé qui ne dirait rien. Un bouton inerte est
        // un bouton dont on ne sait pas s'il est cassé (Article 3.3).
        FilledButton(
          key: const Key('paie-etablissement-confirmer'),
          style: _Textes.styleBouton(fond: AppColors.navy),
          onPressed: _etablir,
          child: const Text('Établir le bulletin', style: _Textes.boutonPlein),
        ),
      ],
    );
  }

  /// `border border-slate-200 rounded-lg p-3 text-[12px]` (l.988-997).
  Widget _apercuChiffre(Simulation apercu) {
    final retenues = apercu.retenues!;
    final cout = apercu.cout!;

    Widget ligne(
      String libelle,
      String valeur, {
      FontWeight? poids,
      Color? couleur,
      Color? couleurLibelle = Ardoise.c600,
    }) => Row(
      children: [
        Expanded(
          child: Text(
            libelle,
            style: _Textes.ligne.copyWith(
              color: couleurLibelle,
              fontWeight: poids,
            ),
          ),
        ),
        Text(
          valeur,
          style: _Textes.ligne.copyWith(color: couleur, fontWeight: poids),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: Ardoise.c200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ligne(
            'Brut soumis à cotisations',
            formaterFcfa(retenues.brut),
            poids: FontWeight.bold,
          ),
          ligne(
            'CNSS 3,6 %',
            '− ${formaterFcfa(retenues.cnssSalarie)}',
            couleur: PaletteMaitre.rouge600,
          ),
          ligne(
            'ITS',
            '− ${formaterFcfa(retenues.its)}',
            couleur: PaletteMaitre.rouge600,
          ),
          Container(
            // `border-t border-slate-200 mt-1 pt-1`.
            margin: const EdgeInsets.only(top: AppSpacing.unit),
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ardoise.c200)),
            ),
            child: ligne(
              'Net à payer',
              formaterFcfa(retenues.netAPayer),
              poids: FontWeight.bold,
              couleur: AppColors.navy,
              couleurLibelle: AppColors.navy,
            ),
          ),
          // FOURCHETTE, jamais un chiffre unique (PA-53) : `mt-1 text-[11px]
          // text-amber-700`.
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Coût employeur',
                    style: _Textes.aide.copyWith(color: PaletteMaitre.ambre700),
                  ),
                ),
                Text(
                  fourchetteCout(cout),
                  style: _Textes.aide.copyWith(color: PaletteMaitre.ambre700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _etablir() async {
    final periode = ref.read(periodeValideProvider).code;

    try {
      final bulletin = await ref
          .read(bulletinPaieServiceProvider)
          .etablirBulletin(widget.employe, periode);

      if (!mounted) return;
      rafraichirPaie(ref);

      // ⚠ L'ORDRE est la substance : on referme CETTE modale d'abord, puis on
      // pose l'identifiant. La consultation du bulletin s'ouvre sur ce
      // changement (`EcranPaie`), et un `pop()` placé après aurait dépilé la
      // consultation toute neuve au lieu de la modale d'établissement.
      final consultation = ref.read(bulletinAfficheProvider.notifier);
      Navigator.of(context).pop();
      consultation.definir(bulletin.id);
    } on RefusRh catch (refus) {
      // Le message du service est rendu TEL QUEL : c'est lui qui nomme la
      // raison exacte, et la reformuler perdrait la seule information utile.
      if (mounted) setState(() => _erreurEtablissement = refus.message);
    }
  }
}

/* ====================================================================== */
/* Annuler un bulletin                                                     */
/* ====================================================================== */

/// L'annulation — **jamais une suppression**, et le motif est obligatoire.
Future<void> ouvrirAnnulation(
  BuildContext context,
  WidgetRef ref,
  BulletinPaie bulletin,
) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (context) => _Annulation(bulletin: bulletin),
  );
}

class _Annulation extends ConsumerStatefulWidget {
  const _Annulation({required this.bulletin});

  final BulletinPaie bulletin;

  @override
  ConsumerState<_Annulation> createState() => _AnnulationState();
}

class _AnnulationState extends ConsumerState<_Annulation> {
  final _formulaire = GlobalKey<FormState>();
  final _motif = TextEditingController();
  String? _erreurAnnulation;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('paie-modale-annulation'),
      titre: 'Annuler ce bulletin',
      sousTitre: 'Il est conservé et reste traçable : rien n’est effacé.',
      largeur: AppLayout.modalePaieAnnulation,
      corps: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Le bulletin sort du livre de paie.',
              style: _Textes.corps,
            ),
            const SizedBox(height: AppSpacing.md),
            const _Etiquette('Motif de l’annulation', obligatoire: true),
            TextFormField(
              key: const Key('paie-motif-annulation'),
              controller: _motif,
              maxLines: 3,
              style: _Textes.champ,
              decoration: _Textes.decoration(),
              validator: (valeur) => (valeur ?? '').trim().isEmpty
                  ? 'Le motif d’annulation est obligatoire.'
                  : null,
            ),
            if (_erreurAnnulation != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _erreur(_erreurAnnulation!, const Key('paie-annulation-erreur')),
            ],
          ],
        ),
      ),
      actions: [
        _boutonAnnuler(context),
        FilledButton(
          key: const Key('paie-annulation-confirmer'),
          style: _Textes.styleBouton(fond: AppColors.erreur),
          onPressed: _annuler,
          child: const Text('Annuler le bulletin', style: _Textes.boutonPlein),
        ),
      ],
    );
  }

  Future<void> _annuler() async {
    if (!_formulaire.currentState!.validate()) return;

    try {
      await ref
          .read(bulletinPaieServiceProvider)
          .annulerBulletin(widget.bulletin.id, _motif.text);
    } on RefusRh catch (refus) {
      if (mounted) setState(() => _erreurAnnulation = refus.message);
      return;
    }

    if (!mounted) return;
    rafraichirPaie(ref);
    Navigator.of(context).pop();
  }
}

/* ====================================================================== */
/* Archivage                                                               */
/* ====================================================================== */

/// La confirmation d'archivage (l.1030-1068) — pour UNE ligne
/// ([employeId]) ou pour la SÉLECTION affichée (`null`).
///
/// « Supprimer » veut dire archiver : le statut passe à « parti », jamais une
/// suppression (RG-15). La modale NOMME les employés visés et, s'il y en a,
/// ceux qui n'ont pas de bulletin sur la période courante : une fois « partis »,
/// la génération les saute sans un mot — l'avertissement vit ICI, pas en
/// verrou, car un départ sans solde dû est légitime.
///
/// Le droit d'archiver (règle UNIQUE de `regle_archivage.dart`, bascule
/// `activation_suppression` lue en base) est exigé À L'OUVERTURE comme à
/// l'exécution (`exigerArchivage()` du serveur) : l'ouverture ne protège rien
/// par elle-même, mais une modale que la confirmation refuserait serait un faux
/// geste. Refusé, le geste DIT sa phrase du serveur au lieu de se taire.
Future<void> ouvrirArchivage(
  BuildContext context,
  WidgetRef ref, {
  String? employeId,
}) async {
  final messageur = ScaffoldMessenger.of(context);
  try {
    await ref.read(exigerArchivagePaieProvider)();
  } on RefusRh catch (refus) {
    messageur
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('paie-archivage-refuse'),
          content: Text(refus.message),
        ),
      );
    return;
  }
  if (!context.mounted) return;

  final ids = employeId != null
      ? [employeId]
      : await ref.read(selectionAfficheePaieProvider.future);
  if (ids.isEmpty || !context.mounted) return;

  final tous = await ref.read(employeDaoProvider).employes();
  final vises = [
    for (final e in tous)
      if (ids.contains(e.id)) e,
  ];
  if (vises.isEmpty || !context.mounted) return;

  final bulletins = await ref.read(bulletinsParEmployeProvider.future);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (context) => _Archivage(
      vises: vises,
      sansBulletin: [
        for (final e in vises)
          if (!bulletins.containsKey(e.id)) e,
      ],
    ),
  );
}

class _Archivage extends ConsumerStatefulWidget {
  const _Archivage({required this.vises, required this.sansBulletin});

  final List<Employe> vises;
  final List<Employe> sansBulletin;

  @override
  ConsumerState<_Archivage> createState() => _ArchivageState();
}

class _ArchivageState extends ConsumerState<_Archivage> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final nombre = widget.vises.length;
    final periode = ref.watch(periodeValideProvider).libelleLong;
    final sans = widget.sansBulletin;
    final noms = sans.map((e) => e.nomComplet()).join(', ');

    return CoquilleModaleRestaurant(
      cle: const Key('paie-modale-archivage'),
      titre: nombre == 1
          ? 'Archiver cet employé ?'
          : 'Archiver ces $nombre employés ?',
      // Le PO dit « Supprimer », le dépôt archive (RG-15) : l'équivalence est
      // écrite en français simple, sur le seul écran qui décide.
      sousTitre:
          '« Supprimer » veut dire archiver : le statut passe à « parti », le '
          'salarié n\'est pas effacé, sa fiche et ses bulletins restent '
          'lisibles.',
      largeur: AppLayout.modalePaieArchivage,
      corps: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final vise in widget.vises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.unit),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      vise.nomComplet(),
                      style: _Textes.champ.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    vise.matricule,
                    style: _Textes.aide.copyWith(
                      fontFamily: AppTextStyles.policeMonospace,
                    ),
                  ),
                ],
              ),
            ),
          if (sans.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xsPlus,
              ),
              decoration: BoxDecoration(
                color: PaletteMaitre.ambre50,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                border: Border.all(color: PaletteMaitre.ambre200),
              ),
              child: Text(
                key: const Key('paie-archivage-sans-bulletin'),
                sans.length == 1
                    ? "$noms n'a pas de bulletin sur $periode : une fois parti, la génération de bulletins l'ignorera. Établissez d'abord son solde de tout compte s'il est dû."
                    : "$noms n'ont pas de bulletin sur $periode : une fois partis, la génération de bulletins les ignorera. Établissez d'abord leurs soldes de tout compte s'ils sont dus.",
                style: _Textes.ligne.copyWith(color: PaletteMaitre.ambre900),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Réversible : la fiche de l\'employé permet de repasser son statut '
            'à « actif ».',
            style: _Textes.ligne.copyWith(color: Ardoise.c500),
          ),
        ],
      ),
      actions: [
        _boutonAnnuler(context),
        FilledButton(
          key: const Key('paie-archivage-confirmer'),
          style: _Textes.styleBouton(fond: AppColors.erreur),
          // Désactivé pendant l'écriture : un second clic archiverait deux fois.
          onPressed: _enCours ? null : _archiver,
          child: Text(
            nombre == 1 ? 'Archiver' : 'Archiver le lot',
            style: _Textes.boutonPlein,
          ),
        ),
      ],
    );
  }

  /// Archive les employés confirmés — écriture M13.
  ///
  /// Un refus du service (déjà parti) est affiché et n'empêche PAS les autres
  /// archivages du lot : perdre le lot entier pour une ligne déjà traitée
  /// serait le refus d'opération de PA-65 appliqué à l'envers.
  Future<void> _archiver() async {
    setState(() => _enCours = true);

    // `Paie::archiverEmployes` : le droit est exigé de nouveau, puis chaque
    // employé du lot est archivé ; un refus d'une ligne n'arrête pas les autres.
    var archives = 0;
    final refus = <String>[];
    try {
      final bilan = await ref.read(archiverEmployesProvider)([
        for (final vise in widget.vises) vise.id,
      ]);
      archives = bilan.archives;
      refus.addAll(bilan.refus);
    } on RefusRh catch (r) {
      refus.add(r.message);
    }

    if (!mounted) return;
    ref.read(selectionPaieProvider.notifier).vider();
    rafraichirPaie(ref);

    final messageur = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    final lignes = <String>[
      if (archives > 0)
        archives == 1 ? '1 employé archivé.' : '$archives employés archivés.',
      ...refus,
    ];
    messageur.showSnackBar(
      SnackBar(
        content: Text(
          lignes.join('\n'),
          key: const Key('paie-archivage-bilan'),
        ),
      ),
    );
  }
}

/* ====================================================================== */
/* Le bulletin, en consultation                                            */
/* ====================================================================== */

/// Ouvre la consultation du bulletin porté par [bulletinAfficheProvider].
///
/// Elle s'ouvre sur l'identifiant porté par le fournisseur, et non par un
/// appel direct : les deux chemins qui y mènent — la ligne de l'effectif et la
/// ligne du registre — doivent ouvrir **le même** document. À la fermeture
/// (bouton, croix, Échap, voile), l'identifiant est remis à `null`.
Future<void> ouvrirBulletin(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => const _ModaleBulletin(),
  );
  if (context.mounted) {
    ref.read(bulletinAfficheProvider.notifier).definir(null);
  }
}

class _ModaleBulletin extends ConsumerWidget {
  const _ModaleBulletin();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulletin = ref.watch(bulletinCourantProvider).value;
    if (bulletin == null) return const SizedBox.shrink();

    return VueBulletin(
      recapitulatif: ref
          .watch(bulletinPaieServiceProvider)
          .recapitulatif(bulletin),
    );
  }
}

/// La modale de consultation — une **lecture**, sans aucune garde d'écriture.
///
/// Un salarié doit pouvoir voir son bulletin, et le droit de le lire est déjà
/// porté par l'accès au module. Exiger le niveau `C` pour consulter retirerait
/// le document à tous les rôles en consultation.
class VueBulletin extends ConsumerStatefulWidget {
  const VueBulletin({required this.recapitulatif, super.key});

  final RecapitulatifBulletin recapitulatif;

  @override
  ConsumerState<VueBulletin> createState() => _VueBulletinState();
}

class _VueBulletinState extends ConsumerState<VueBulletin> {
  /// Le papier A4 du bulletin (`pdf/paie-bulletin`), composé au geste : l'en-tête
  /// est lu des paramètres à CE moment-là.
  Future<BulletinPaieA4> _papier() =>
      ref.read(bulletinA4Provider(widget.recapitulatif));

  /// « Imprimer » (`window.print()` au web) : la boîte d'impression du système.
  Future<void> _imprimer() async {
    final messageur = ScaffoldMessenger.of(context);
    try {
      await ref.read(imprimerBulletinProvider)(await _papier());
    } on Object catch (erreur) {
      messageur
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('paie-bulletin-impression-echec'),
            content: Text('Impression impossible : $erreur'),
          ),
        );
    }
  }

  /// « PDF » (`exporterPdf`) : `bulletin_<numéro>.pdf`, par « Enregistrer sous ».
  Future<void> _telechargerPdf() async {
    final bulletin = await _papier();
    if (!mounted) return;
    await executerExport(
      context,
      () => ref.read(exporterBulletinPdfProvider)(bulletin),
      cleSucces: const Key('paie-bulletin-pdf-enregistre'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bulletin = widget.recapitulatif.bulletin;
    final cout = widget.recapitulatif.cout;
    final employe = bulletin.employe;
    final periode = ref.watch(periodeValideProvider).libelleLong;

    return CoquilleModaleRestaurant(
      cle: const Key('paie-modale-bulletin'),
      titre: 'Bulletin de paie',
      largeur: AppLayout.modalePaieBulletin,
      corps: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `border-b-2` navy : l'identité de l'établissement et du document.
          Container(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.navy,
                  width: AppSpacing.demi,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TATACORA AFRIQUE — Gîte Chez Noël',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Natitingou, Bénin',
                        style: _Textes.aide.copyWith(color: Ardoise.c500),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'BULLETIN DE PAIE',
                      key: Key('paie-bulletin-entete'),
                      style: TextStyle(
                        color: AppColors.navy,
                        fontFamily: AppTextStyles.police,
                        fontSize: Tailles.t14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(periode, style: _Textes.ligne),
                    Text(
                      bulletin.numero,
                      style: _Textes.aide.copyWith(
                        fontFamily: AppTextStyles.policeMonospace,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _encartSalarie(employe)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _encartAffectation(bulletin, employe)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _tableau(bulletin),
          const SizedBox(height: AppSpacing.md),
          _encartPatronales(bulletin, cout),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Les montants sont calculés, aucun n’est saisi. Document à '
            'conserver sans limitation de durée.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Ardoise.c400,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t10,
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('paie-bulletin-imprimer'),
          style: _Textes.styleBouton(),
          onPressed: _imprimer,
          child: const Text('Imprimer', style: _Textes.bouton),
        ),
        OutlinedButton(
          key: const Key('paie-bulletin-pdf'),
          style: _Textes.styleBouton(),
          onPressed: _telechargerPdf,
          child: const Text('PDF', style: _Textes.bouton),
        ),
        FilledButton(
          key: const Key('paie-bulletin-fermer'),
          style: _Textes.styleBouton(fond: AppColors.navy),
          // Ferme la route de la modale, et elle seule ; `ouvrirBulletin`
          // remet l'identifiant à `null` à la fermeture.
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer', style: _Textes.boutonPlein),
        ),
      ],
    );
  }

  /// Un des deux encarts : `bg-slate-50 rounded-lg p-3 text-[12px]`, étiqueté
  /// en `text-[10px] uppercase tracking-wide text-slate-400`.
  Widget _encart(String etiquette, List<Widget> enfants) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Ardoise.c50,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiquette.toUpperCase(),
          style: const TextStyle(
            color: Ardoise.c400,
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t10,
            fontWeight: FontWeight.w600,
            letterSpacing: Tailles.t10 * AppTextStyles.suiviLarge,
          ),
        ),
        // `mb-1`.
        const SizedBox(height: AppSpacing.unit),
        ...enfants,
      ],
    ),
  );

  Widget _encartSalarie(Employe employe) => _encart('Salarié', [
    Text(
      employe.nomComplet(),
      style: const TextStyle(
        color: Ardoise.c800,
        fontFamily: AppTextStyles.police,
        fontSize: Tailles.t14,
        fontWeight: FontWeight.bold,
      ),
    ),
    Text(employe.poste, style: _Textes.ligne),
    Text(
      'Matricule ${employe.matricule}',
      style: _Textes.ligne.copyWith(color: Ardoise.c500),
    ),
    if (employe.sansNumeroCnss)
      Text.rich(
        TextSpan(
          style: _Textes.ligne.copyWith(color: Ardoise.c500),
          children: const [
            TextSpan(text: 'N° CNSS '),
            TextSpan(
              text: 'non communiqué',
              style: TextStyle(
                color: PaletteMaitre.ambre700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )
    else
      Text(
        'N° CNSS ${employe.numeroCnss}',
        style: _Textes.ligne.copyWith(color: Ardoise.c500),
      ),
  ]);

  Widget _encartAffectation(BulletinPaie bulletin, Employe employe) =>
      _encart('Affectation', [
        Text(
          employe.serviceLibelle ?? tiret,
          style: _Textes.ligne.copyWith(color: Ardoise.c700),
        ),
        Text(
          'Établi le ${formaterDate(bulletin.etabliLe)}',
          style: _Textes.ligne.copyWith(color: Ardoise.c500),
        ),
        if (bulletin.estAnnule)
          Text(
            'Annulé — ${bulletin.motifAnnulation ?? ''}',
            style: _Textes.ligne.copyWith(
              color: PaletteMaitre.rouge600,
              fontWeight: FontWeight.w600,
            ),
          ),
      ]);

  /// Le tableau du bulletin : cinq colonnes, des lignes `colspan` (l.1112-1153).
  Widget _tableau(BulletinPaie bulletin) {
    // Poids des colonnes Désignation / Base / Taux / Gain / Retenue.
    const poids = [5, 2, 1, 2, 2];

    Widget cellule(int colonnes, Widget enfant, {int debut = 0}) => Expanded(
      flex: poids.sublist(debut, debut + colonnes).reduce((a, b) => a + b),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: enfant,
      ),
    );

    Widget texte(
      String valeur, {
      FontWeight? gras,
      Color? couleur,
      TextAlign align = TextAlign.left,
    }) => Text(
      valeur,
      textAlign: align,
      style: _Textes.ligne.copyWith(fontWeight: gras, color: couleur),
    );

    Widget montant(String valeur, {Color? couleur, FontWeight? gras}) =>
        texte(valeur, couleur: couleur, gras: gras, align: TextAlign.right);

    const entete = TextStyle(
      color: AppColors.blanc90,
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t11,
      fontWeight: FontWeight.w600,
      letterSpacing: Tailles.t11 * AppTextStyles.suiviLarge,
    );

    // `uppercase` est une règle CSS : on applique la même au libellé.
    Widget titre(int colonne, String libelle) => Expanded(
      flex: poids[colonne],
      child: Text(
        libelle.toUpperCase(),
        textAlign: colonne == 0 ? TextAlign.left : TextAlign.right,
        style: entete,
      ),
    );

    Widget rangee(
      List<Widget> cellules, {
      Color? fond,
      Border? bordure,
      double vertical = 0,
    }) => Container(
      padding: EdgeInsets.symmetric(vertical: vertical),
      decoration: BoxDecoration(color: fond, border: bordure),
      child: Row(children: cellules),
    );

    const filet = Border(bottom: BorderSide(color: Ardoise.c100));
    final brut = formaterFcfa(bulletin.brut);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.navy,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              titre(0, 'Désignation'),
              titre(1, 'Base'),
              titre(2, 'Taux'),
              titre(3, 'Gain'),
              titre(4, 'Retenue'),
            ],
          ),
        ),
        rangee([
          cellule(
            3,
            texte('Salaire brut soumis à cotisations', gras: FontWeight.bold),
          ),
          cellule(1, montant(brut, gras: FontWeight.bold), debut: 3),
          cellule(1, const SizedBox.shrink(), debut: 4),
        ], fond: Ardoise.c100),
        rangee([
          cellule(
            1,
            texte('CNSS — cotisation salariale', couleur: Ardoise.c700),
          ),
          cellule(1, montant(brut, couleur: Ardoise.c500), debut: 1),
          cellule(1, const SizedBox.shrink(), debut: 2),
          cellule(1, const SizedBox.shrink(), debut: 3),
          cellule(
            1,
            montant(
              formaterFcfa(bulletin.cnssSalarie),
              couleur: PaletteMaitre.rouge600,
            ),
            debut: 4,
          ),
        ], bordure: filet),
        rangee([
          cellule(
            3,
            texte('Revenu imposable (brut − CNSS)', gras: FontWeight.bold),
          ),
          cellule(
            1,
            montant(
              formaterFcfa(bulletin.revenuImposable),
              gras: FontWeight.bold,
            ),
            debut: 3,
          ),
          cellule(1, const SizedBox.shrink(), debut: 4),
        ], fond: Ardoise.c100),
        rangee([
          cellule(
            1,
            texte(
              'ITS — Impôt sur les Traitements et Salaires',
              couleur: Ardoise.c700,
              gras: FontWeight.w600,
            ),
          ),
          cellule(3, const SizedBox.shrink(), debut: 1),
          cellule(
            1,
            montant(
              formaterFcfa(bulletin.its),
              couleur: PaletteMaitre.rouge600,
              gras: FontWeight.w600,
            ),
            debut: 4,
          ),
        ], bordure: filet),
        if (bulletin.autresRetenues > 0)
          rangee([
            cellule(1, texte('Autres retenues', couleur: Ardoise.c700)),
            cellule(3, const SizedBox.shrink(), debut: 1),
            cellule(
              1,
              montant(
                formaterFcfa(bulletin.autresRetenues),
                couleur: PaletteMaitre.rouge600,
              ),
              debut: 4,
            ),
          ], bordure: filet),
        rangee(
          [
            cellule(
              3,
              texte(
                'NET À PAYER',
                gras: FontWeight.bold,
                couleur: AppColors.neutre0,
              ),
            ),
            cellule(
              2,
              montant(
                formaterFcfa(bulletin.netAPayer),
                gras: FontWeight.bold,
                couleur: AppColors.neutre0,
              ),
              debut: 3,
            ),
          ],
          fond: AppColors.navy,
          vertical: AppSpacing.demi,
        ),
      ],
    );
  }

  /// Le pavé ambre : la part patronale CONFIRMÉE, les risques professionnels
  /// en fourchette, le coût total en fourchette (l.1155-1168).
  Widget _encartPatronales(BulletinPaie bulletin, CoutEmployeur cout) {
    const ambre = PaletteMaitre.ambre900;

    Widget ligne(
      String libelle,
      String valeur, {
      Color couleur = ambre,
      FontWeight? gras,
      Border? bordure,
      double haut = 0,
    }) => Container(
      padding: EdgeInsets.only(top: haut, bottom: haut),
      decoration: BoxDecoration(border: bordure),
      child: Row(
        children: [
          Expanded(
            child: Text(
              libelle,
              style: _Textes.ligne.copyWith(color: couleur, fontWeight: gras),
            ),
          ),
          Text(
            valeur,
            style: _Textes.ligne.copyWith(
              color: couleur,
              fontWeight: gras ?? FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: PaletteMaitre.ambre50,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: PaletteMaitre.ambre200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Charges patronales — à la charge de l’employeur, hors bulletin '
                    'salarié'
                .toUpperCase(),
            style: const TextStyle(
              color: ambre,
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t11,
              fontWeight: FontWeight.w600,
              letterSpacing: Tailles.t11 * AppTextStyles.suiviLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ligne(
            'Total charges patronales confirmées',
            formaterFcfa(bulletin.chargesPatronalesConfirmees),
          ),
          // Les deux lignes qui portent PA-53 sur le document lui-même.
          ligne(
            'CNSS — risques professionnels',
            '${formaterFcfa(cout.rpMin)} $tiret ${formaterFcfa(cout.rpMax)}',
            couleur: PaletteMaitre.rouge900,
            bordure: const Border(
              top: BorderSide(color: PaletteMaitre.ambre200),
            ),
            haut: AppSpacing.unit,
          ),
          ligne(
            'Coût total employeur',
            '${formaterFcfa(cout.coutMin)} $tiret ${formaterFcfa(cout.coutMax)}',
            gras: FontWeight.bold,
            bordure: const Border(
              top: BorderSide(color: ambre, width: AppSpacing.demi),
            ),
            haut: AppSpacing.xxs,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            const TextSpan(
              style: TextStyle(
                color: ambre,
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t10,
              ),
              children: [
                TextSpan(
                  text:
                      'Le taux de risques professionnels dépend du niveau de '
                      'risque de l’entreprise et n’est pas confirmé pour '
                      'l’hôtellerie-restauration. Il n’est pas supposé : le '
                      'coût est donné en fourchette. Le VPS et les cotisations '
                      'CNSS ci-dessus sont, eux, confirmés. Le VPS est ',
                ),
                TextSpan(
                  text: 'dû par l’employeur',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: ' — il n’apparaît jamais en retenue sur salaire.',
                ),
              ],
            ),
            key: const Key('paie-bulletin-note-rp'),
          ),
        ],
      ),
    );
  }
}
