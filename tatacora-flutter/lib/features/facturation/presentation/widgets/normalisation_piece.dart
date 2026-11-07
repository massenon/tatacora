import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../data/service_normalisation.dart';
import '../../domain/client_mecef.dart';
import '../../domain/entities/piece_facturation.dart';
import '../../domain/mode_facturation.dart';
import '../../domain/statut_normalisation.dart';
import '../providers_facturation.dart';

/// Les mots de la normalisation, à l'écran de la facturation. Un AJOUT de ce
/// poste (07/11/2026) : la vue du serveur n'a pas de bouton « Normaliser » — le
/// boîtier n'existe que sur ce poste.
abstract final class TextesNormalisationEcran {
  static const normaliser = 'Normaliser';
  static const reessayer = 'Réessayer';
  static const verifier = 'Vérifier';
  static String normalisee(String numero) => 'Facture normalisée : $numero.';
  static String ignoree(CertifiePar c) => switch (c) {
    CertifiePar.rien =>
      'Ce poste ne certifie pas : réglez « Ce poste certifie par » dans '
          'Paramètres.',
    CertifiePar.serveur =>
      'Ce poste laisse le serveur certifier : la normalisation arrive après la '
          'synchronisation.',
    CertifiePar.boitier => 'Normalisation impossible.',
  };
  static const dejaNormalisee = 'Cette facture est déjà normalisée.';
}

/// L'état de la normalisation d'une pièce, dérivé de ce qui est RÉELLEMENT
/// rangé sur elle : « normalisée » exige un numéro fiscal réel ET le QR.
class IndicateurNormalisation extends StatelessWidget {
  const IndicateurNormalisation({required Key key, required this.piece})
    : super(key: key);

  final PieceFacturation piece;

  @override
  Widget build(BuildContext context) {
    final statut = piece.normalisationStatut;
    if (statut == null) return const SizedBox.shrink();

    final PastilleStatut pastille;
    String? motif = piece.normalisationMotif;
    if (statut == StatutNormalisation.normalisee) {
      if (piece.estNormalisee) {
        pastille = PastilleStatut.succes(statut.libelle.toLowerCase());
        motif = 'MECeF ${piece.numeroMecef}';
      } else {
        // Un statut « normalisée » sans numéro réel ni QR : on ne l'affirme pas.
        pastille = const PastilleStatut.alerte('à vérifier');
        motif = 'Normalisation incomplète : numéro fiscal ou QR absent.';
      }
    } else {
      pastille = switch (statut) {
        StatutNormalisation.refusee => PastilleStatut.refus(
          statut.libelle.toLowerCase(),
        ),
        StatutNormalisation.enAttente => PastilleStatut.alerte(
          statut.libelle.toLowerCase(),
        ),
        StatutNormalisation.aVerifier => PastilleStatut.alerte(
          statut.libelle.toLowerCase(),
        ),
        StatutNormalisation.normalisee => const PastilleStatut.succes(
          'normalisée',
        ),
      };
    }
    return Tooltip(message: motif ?? statut.libelle, child: pastille);
  }
}

/// « Normaliser » / « Réessayer » / « Vérifier » : visible seulement quand ce
/// poste certifie par son boîtier. Une facture annulée ne se normalise pas.
class BoutonNormaliser extends ConsumerStatefulWidget {
  const BoutonNormaliser({required Key cle, required this.piece})
    : super(key: cle);

  final PieceFacturation piece;

  @override
  ConsumerState<BoutonNormaliser> createState() => _BoutonNormaliserState();
}

class _BoutonNormaliserState extends ConsumerState<BoutonNormaliser> {
  bool _occupe = false;

  String get _libelle => switch (widget.piece.normalisationStatut) {
    null => TextesNormalisationEcran.normaliser,
    StatutNormalisation.aVerifier => TextesNormalisationEcran.verifier,
    _ => TextesNormalisationEcran.reessayer,
  };

  Future<void> _normaliser() async {
    final messages = ScaffoldMessenger.of(context);
    setState(() => _occupe = true);
    String message;
    var erreur = false;
    try {
      final r = await ref
          .read(serviceNormalisationProvider)
          .normaliser(widget.piece.id);
      switch (r) {
        case NormalisationIgnoree(:final certifiePar):
          message = TextesNormalisationEcran.ignoree(certifiePar);
          erreur = true;
        case DejaNormalisee():
          message = TextesNormalisationEcran.dejaNormalisee;
        case NormalisationFaite(:final issue):
          switch (issue) {
            case Certifiee(:final resultat):
              message = TextesNormalisationEcran.normalisee(
                resultat.numeroMecef,
              );
            case EnAttente(:final motif):
              message = motif;
              erreur = true;
            case Refusee(:final motif):
              message = motif;
              erreur = true;
            case AVerifier(:final motif):
              message = motif;
              erreur = true;
          }
      }
    } on Object catch (e) {
      message = '$e';
      erreur = true;
    }
    ref
      ..invalidate(registreProvider)
      ..invalidate(boitierActifProvider);
    if (mounted) setState(() => _occupe = false);
    messages.showSnackBar(
      SnackBar(
        key: const Key('facturation-normalisation-message'),
        content: Text(message),
        backgroundColor: erreur ? AppColors.erreur : AppColors.succes,
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final piece = widget.piece;
    if (piece.estAnnulee && !piece.estAvoir) return const SizedBox.shrink();
    final actif = ref.watch(boitierActifProvider).value ?? false;
    if (!actif) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: InkWell(
        onTap: _occupe ? null : _normaliser,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.demi,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.rounded),
            border: Border.all(color: AppColors.navy),
          ),
          child: Text(
            _occupe ? '…' : _libelle,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t11,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}
