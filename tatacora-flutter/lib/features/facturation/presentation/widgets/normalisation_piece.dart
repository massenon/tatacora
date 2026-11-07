import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/tableau_tatacora.dart';
import '../../data/service_facturation_en_ligne.dart';
import '../../data/service_normalisation.dart';
import '../../domain/client_mecef.dart';
import '../../domain/entities/piece_facturation.dart';
import '../../domain/ifu_client.dart';
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
    CertifiePar.serveur => TextesFacturationModes.normalisationEnLigne,
    CertifiePar.boitier => 'Normalisation impossible.',
  };
  static const dejaNormalisee = 'Cette facture est déjà normalisée.';
}

/// L'état de la normalisation d'une pièce, dérivé de ce qui est RÉELLEMENT
/// rangé sur elle : « normalisée » exige un numéro fiscal réel ET le QR.
class IndicateurNormalisation extends ConsumerWidget {
  const IndicateurNormalisation({required Key key, required this.piece})
    : super(key: key);

  final PieceFacturation piece;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statut = piece.normalisationStatut;
    if (statut == null) {
      // Une facture SIMPLE (mode désactivé) ne porte AUCUNE mention. Dans les modes boîtier et
      // e-MECeF, une facture émise pas encore normalisée dit qu'elle ATTEND (décision du PO du
      // 07/11/2026) ; un avoir ou une facture annulée n'a rien à normaliser ici.
      final par = ref.watch(certifieParProvider).value ?? CertifiePar.rien;
      if (par == CertifiePar.rien || piece.estAvoir || piece.estAnnulee) {
        return const SizedBox.shrink();
      }
      return Tooltip(
        message: TextesFacturationModes.enAttenteDeNormalisation,
        child: PastilleStatut.alerte('en attente de normalisation'),
      );
    }

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
      // e-MECeF depuis le poste (décision du PO du 07/11/2026) : EN LIGNE seulement — le serveur
      // normalise avec SON jeton (qui ne descend jamais ici) et rend le résultat. Hors ligne :
      // refusé avec la phrase, rien d'écrit de faux, la facture reste « en attente ».
      if (await ref.read(certifieParProvider.future) == CertifiePar.serveur) {
        final en = await ref
            .read(serviceFacturationEnLigneProvider)
            .normaliserParLeServeur(widget.piece.id);
        switch (en) {
          case NormalisationServeur(:final piece) when piece.estNormalisee:
            message = TextesNormalisationEcran.normalisee(
              piece.numeroMecef ?? piece.numero,
            );
          case NormalisationServeur(:final motif):
            message = motif ?? TextesFacturationModes.enAttenteDeNormalisation;
            erreur = true;
          case RefusEnLigne(:final phrase):
            message = phrase;
            erreur = true;
          case AvoirCree():
            message = TextesNormalisationEcran.dejaNormalisee;
        }
        ref
          ..invalidate(registreProvider)
          ..invalidate(certifieParProvider);
        if (mounted) setState(() => _occupe = false);
        messages.showSnackBar(
          SnackBar(
            key: const Key('facturation-normalisation-message'),
            content: Text(message),
            backgroundColor: erreur ? AppColors.erreur : AppColors.succes,
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
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
    // Mode désactivé = facture SIMPLE : AUCUN bouton. Boîtier ou e-MECeF : « Normaliser ».
    final par = ref.watch(certifieParProvider).value ?? CertifiePar.rien;
    if (par == CertifiePar.rien) return const SizedBox.shrink();
    // Un avoir d'une facture normalisée se normalise par le boîtier OU par le serveur à sa
    // création : le bouton n'a de sens que pour le boîtier (voie e-MECeF : déjà faite).
    if (piece.estAvoir && par == CertifiePar.serveur) {
      return const SizedBox.shrink();
    }

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
