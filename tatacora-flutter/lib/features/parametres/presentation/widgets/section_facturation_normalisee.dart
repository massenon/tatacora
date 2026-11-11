// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/impression/entete_etablissement.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../facturation/data/lecteur_mode_facturation.dart';
import '../../../facturation/data/pilote_boitier.dart';
import '../../../facturation/domain/adresse_boitier.dart';
import '../../../facturation/domain/erreur_boitier.dart';
import '../../../facturation/domain/mode_facturation.dart';
import '../../../transverse/data/configuration_poste.dart';
import '../../../transverse/domain/comptes_utilisateurs.dart';
import '../../data/parametres_dao.dart';
import '../../../synchronisation/presentation/providers_synchronisation.dart';

/// Les mots de la section « Facturation normalisée (MECeF) » de ce poste.
///
/// Les libellés du serveur (Mode, adresse de l'API, opérateur, jeton) sont
/// repris de `lang/fr/pwa.php` (`parametres.mecef_*`) ; ce qui n'existe que sur
/// ce poste — le réglage LOCAL « ce poste certifie par » et le pilote du
/// boîtier — est un AJOUT du poste, nommé comme tel.
abstract final class TextesFacturationPoste {
  // Repris du serveur.
  static const titreSection = 'Facturation normalisée (MECeF)';
  static const jetonLibelle = 'Jeton JWT e-MECeF';
  static const jetonReserve =
      'Seul un Administrateur peut saisir ou effacer le jeton.';
  static const jetonMention =
      'Le jeton est rangé chiffré sur le serveur : il n’est jamais réaffiché '
      'ni envoyé aux postes. Pour le remplacer, saisissez-en un nouveau.';

  // Propre à ce poste : le jeton se saisit AU SERVEUR.
  static const jetonGereAuServeur =
      'Ce poste ne reçoit jamais le jeton : il se saisit au serveur '
      '(Paramètres → Identité & Légal).';
  static const jetonEnregistre = 'Géré au serveur.';

  // Propres à ce poste.
  static const certifiePar = 'Ce poste certifie par';
  static const commeLeServeur = 'Comme le réglage du serveur';
  static const reserve =
      'Le réglage local et l’adresse du pilote sont réservés aux '
      'Administrateurs.';
  static const modeServeur = 'Mode reçu du serveur';
  static const adresseChamp = 'Adresse du pilote du boîtier';
  static const adresseAide =
      'Le pilote du boîtier CC300, installé sur ce poste '
      '(http://localhost:38917 par défaut).';
  static String actuelle(String adresse) => 'Actuelle : $adresse';
  static const enregistrer = 'Enregistrer';
  static const tester = 'Tester le boîtier';
  static const reinitialiser = 'Adresse par défaut';
  static const surchargeEnregistree = 'Réglage de ce poste enregistré.';
  static String adresseEnregistree(String a) =>
      'Adresse du pilote enregistrée : $a.';
  static const adresseDefaut = 'Adresse par défaut rétablie.';
  static const essaiEnCours =
      'Essai en cours : le boîtier met environ 4 secondes à répondre…';
  static String ifuDifferent(String boitier, String entreprise) =>
      ' Attention : l’IFU du boîtier ($boitier) n’est pas celui de '
      'l’entreprise ($entreprise).';
}

/// L'état de la facturation de ce poste, relu à chaque ouverture de l'écran.
final etatFacturationPosteProvider =
    FutureProvider.autoDispose<EtatFacturationPoste>(
      (ref) => LecteurModeFacturation(
        ref.watch(baseLocaleProvider),
        lecteur: LecteurConfigurationPoste(
          chemin: ref.watch(cheminConfigurationPosteProvider),
        ),
      ).lire(),
    );

/// Le pilote testé : remplaçable par un test (faux pilote HTTP local).
final fabriquePiloteBoitierProvider = Provider<PiloteBoitier Function(String)>(
  (ref) =>
      (racine) => PiloteBoitier(racine: racine),
);

/// Le jeton e-MECeF vu de CE poste : jamais reçu, jamais saisi ici.
class MentionJetonMecef extends StatelessWidget {
  const MentionJetonMecef({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('param-mecef-jeton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesFacturationPoste.jetonLibelle,
          style: _style(TaillesContenu.t15, poids: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesFacturationPoste.jetonEnregistre,
          style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesFacturationPoste.jetonGereAuServeur,
          style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesFacturationPoste.jetonReserve,
          style: _style(TaillesContenu.t12, couleur: AppColors.neutre400),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          TextesFacturationPoste.jetonMention,
          style: _style(TaillesContenu.t12, couleur: AppColors.neutre400),
        ),
      ],
    );
  }
}

/// « Ce poste certifie par », l'adresse du pilote et « Tester le boîtier ».
class CarteBoitierPoste extends ConsumerStatefulWidget {
  const CarteBoitierPoste({super.key});

  @override
  ConsumerState<CarteBoitierPoste> createState() => _CarteBoitierPosteState();
}

class _CarteBoitierPosteState extends ConsumerState<CarteBoitierPoste> {
  final _champ = TextEditingController();
  bool _touche = false;
  bool _occupe = false;
  String? _message;
  bool _erreur = false;

  @override
  void initState() {
    super.initState();
    ref.read(etatFacturationPosteProvider.future).then((e) {
      if (mounted && !_touche) _champ.text = e.adresseBoitier;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  EcrivainConfigurationPoste get _ecrivain => EcrivainConfigurationPoste(
    chemin: ref.read(cheminConfigurationPosteProvider),
  );

  void _dire(String message, {required bool erreur}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _erreur = erreur;
    });
  }

  Future<void> _surcharger(SurchargeFacturation? choix) async {
    try {
      await _ecrivain.enregistrerSurchargeFacturation(choix?.code);
      ref.invalidate(etatFacturationPosteProvider);
      _dire(TextesFacturationPoste.surchargeEnregistree, erreur: false);
    } on Object catch (e) {
      _dire('Opération impossible sur ce poste : $e', erreur: true);
    }
  }

  Future<void> _enregistrer({bool pardefaut = false}) async {
    if (!peutAdministrerComptes(ref.read(sessionProvider)?.role)) {
      _dire(TextesFacturationPoste.reserve, erreur: true);
      return;
    }
    if (pardefaut) {
      try {
        await _ecrivain.enregistrerAdresseBoitier(null);
        _champ.text = adresseBoitierParDefaut;
        _touche = false;
        ref.invalidate(etatFacturationPosteProvider);
        _dire(TextesFacturationPoste.adresseDefaut, erreur: false);
      } on Object catch (e) {
        _dire('Opération impossible sur ce poste : $e', erreur: true);
      }
      return;
    }
    final r = validerAdresseBoitier(_champ.text);
    if (r is AdresseBoitierInvalide) {
      _dire(r.message, erreur: true);
      return;
    }
    final racine = (r as AdresseBoitierValide).racine;
    try {
      // L'adresse par défaut n'est pas un « choix » : la clé est retirée.
      await _ecrivain.enregistrerAdresseBoitier(
        racine == adresseBoitierParDefaut ? null : racine,
      );
      _champ.text = racine;
      ref.invalidate(etatFacturationPosteProvider);
      _dire(TextesFacturationPoste.adresseEnregistree(racine), erreur: false);
    } on Object catch (e) {
      _dire('Opération impossible sur ce poste : $e', erreur: true);
    }
  }

  /// `GET /check` puis `GET /info` : NIM, IFU, taux, dernière connexion DGI.
  /// Aucune écriture ; jamais de facture.
  Future<void> _tester() async {
    final r = validerAdresseBoitier(_champ.text);
    if (r is AdresseBoitierInvalide) {
      _dire(r.message, erreur: true);
      return;
    }
    final racine = (r as AdresseBoitierValide).racine;
    setState(() {
      _occupe = true;
      _message = TextesFacturationPoste.essaiEnCours;
      _erreur = false;
    });
    try {
      final pilote = ref.read(fabriquePiloteBoitierProvider)(racine);
      await pilote.verifier();
      final info = await pilote.info();
      final valeurs = await ParametresDao(
        ref.read(baseLocaleProvider),
      ).lireTout();
      // L'IFU se lit par le lecteur déclaré de la clé (l'en-tête des états).
      final ifu = (EnteteEtablissement.depuisParametres(valeurs).ifu ?? '')
          .trim();
      final alerte = ifu.isNotEmpty && ifu != info.ifu;
      _dire(
        info.resume +
            (alerte ? TextesFacturationPoste.ifuDifferent(info.ifu, ifu) : ''),
        erreur: alerte,
      );
    } on ErreurBoitier catch (e) {
      _dire(e.message, erreur: true);
    } on Object catch (e) {
      _dire('Opération impossible sur ce poste : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = peutAdministrerComptes(ref.watch(sessionProvider)?.role);
    final etat = ref.watch(etatFacturationPosteProvider).value;

    return Column(
      key: const Key('param-mecef-boitier'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TextesFacturationPoste.certifiePar,
          style: _style(TaillesContenu.t15, poids: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xxs),
        InputDecorator(
          decoration: const InputDecoration(isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SurchargeFacturation?>(
              key: const Key('param-mecef-surcharge'),
              value: etat?.surcharge,
              isExpanded: true,
              isDense: true,
              items: [
                DropdownMenuItem<SurchargeFacturation?>(
                  value: null,
                  child: Text(
                    TextesFacturationPoste.commeLeServeur,
                    overflow: TextOverflow.ellipsis,
                    style: _style(TaillesContenu.t13),
                  ),
                ),
                for (final s in SurchargeFacturation.values)
                  DropdownMenuItem<SurchargeFacturation?>(
                    value: s,
                    child: Text(
                      s.libelle,
                      overflow: TextOverflow.ellipsis,
                      style: _style(TaillesContenu.t13),
                    ),
                  ),
              ],
              onChanged: admin ? _surcharger : null,
            ),
          ),
        ),
        if (etat != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${TextesFacturationPoste.modeServeur} : ${etat.modeServeur.libelle}. '
            '${phraseCertifiePar(etat.certifiePar, surchargeLocale: etat.surcharge != null)}',
            key: const Key('param-mecef-phrase'),
            style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
          ),
        ],
        if (!admin) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            TextesFacturationPoste.reserve,
            style: _style(TaillesContenu.t12, couleur: AppColors.neutre400),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('param-mecef-adresse'),
          controller: _champ,
          enabled: !_occupe && admin,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: longueurMaxAdresseBoitier,
          onChanged: (_) => _touche = true,
          decoration: const InputDecoration(
            labelText: TextesFacturationPoste.adresseChamp,
            helperText: TextesFacturationPoste.adresseAide,
            helperMaxLines: 2,
            counterText: '',
            isDense: true,
          ),
        ),
        if (etat != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            TextesFacturationPoste.actuelle(etat.adresseBoitier),
            key: const Key('param-mecef-adresse-actuelle'),
            style: _style(TaillesContenu.t13, couleur: AppColors.neutre700),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (admin)
              BoutonStandard(
                key: const Key('param-mecef-enregistrer'),
                libelle: TextesFacturationPoste.enregistrer,
                variante: VarianteBouton.primaire,
                onPressed: _occupe ? null : _enregistrer,
              ),
            if (admin && (etat?.adresseBoitierChoisie ?? false))
              BoutonStandard(
                key: const Key('param-mecef-defaut'),
                libelle: TextesFacturationPoste.reinitialiser,
                onPressed: _occupe ? null : () => _enregistrer(pardefaut: true),
              ),
            BoutonStandard(
              key: const Key('param-mecef-tester'),
              libelle: TextesFacturationPoste.tester,
              onPressed: _occupe ? null : _tester,
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _message!,
            key: const Key('param-mecef-message'),
            style: _style(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: _erreur ? AppColors.erreur : AppColors.succes,
            ),
          ),
        ],
      ],
    );
  }
}

TextStyle _style(
  double taille, {
  FontWeight poids = FontWeight.normal,
  Color couleur = AppColors.neutre900,
}) => TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: taille,
  fontWeight: poids,
  color: couleur,
);
