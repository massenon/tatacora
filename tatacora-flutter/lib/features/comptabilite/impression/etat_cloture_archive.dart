import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';
import '../../../core/impression/visas.dart';
import '../domain/cloture_exercice.dart';
import '../domain/entities/comptabilite.dart';
import '../domain/etats_financiers.dart';
import '../domain/messages_cloture.dart';
import '../domain/montant_comptable.dart';

/// Le PDF de l'ARCHIVE LÉGALE d'une clôture d'exercice (`etats-cloture.pdf`) —
/// 26/10/2026, réplique de `pdf/comptabilite-etats-cloture.blade.php` du
/// serveur : la clôture (pièces, résultat), la balance générale, le compte de
/// résultat, le bilan, et les visas.
///
/// Les états sont ceux d'AVANT le solde des comptes de gestion (journal CL
/// exclu, comme `BalanceGeneraleService`) : le compte de résultat de l'exercice,
/// pas un compte de résultat soldé à zéro. Son empreinte SHA-256 est notée dans
/// `manifeste.json` ; il ne la porte pas lui-même.
///
/// ## Écart nommé : le gabarit tabulaire commun du poste
///
/// Le serveur compose ce PDF avec DomPDF et quatre tableaux de largeurs
/// différentes. Le poste le compose avec le gabarit tabulaire commun (en-tête,
/// zone de signatures et pied de rapport du point unique `core/impression`) : un
/// tableau de six colonnes où chaque section s'ouvre par son titre et sa ligne
/// de colonnes. Mêmes sections, mêmes mots (relus du serveur), mêmes montants ;
/// pas la même mise en page. Les chiffres sont ceux des pièces de CE poste.
final class EtatClotureArchive {
  const EtatClotureArchive({
    required this.exercice,
    required this.cloture,
    required this.balance,
    required this.compteResultat,
    required this.bilan,
  });

  final ExerciceComptable exercice;
  final ClotureExercice cloture;
  final BalanceEtat balance;
  final CompteResultatEtat compteResultat;
  final BilanEtat bilan;

  static String _t(String cle, [Map<String, String> v = const {}]) =>
      MessagesCloture.dire('comptabilite_pwa.$cle', v);

  static const String _tiret = '—';

  static String _fcfa(int centimes) =>
      formaterMontantDecimal(chaineDepuisCentimes(centimes), suffixe: 'FCFA') ??
      _tiret;

  static String _fcfaOuTiret(int centimes) =>
      centimes == 0 ? _tiret : _fcfa(centimes);

  /// `d/m/Y H:i` — la date de la clôture, à la minute.
  static String _dateHeure(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} '
        '${deux(d.hour)}:${deux(d.minute)}';
  }

  /// Le titre du document : « Archive de clôture — exercice 2026 ».
  String get titre => _t('archive_titre', {'annee': '${exercice.annee}'});

  /// Le préfixe du fichier écrit (`etats-cloture`).
  static const String nomFichier = 'etats-cloture.pdf';

  EtatTabulaireA4 etatA4() {
    List<String> section(String titre) => [titre, '', '', '', '', ''];
    List<String> legende(List<String> c) => c;

    final lignes = <List<String>>[
      section(_t('archive_section_cloture').toUpperCase()),
      [
        _t('archive_cloturee_le'),
        _dateHeure(cloture.clotureeLe),
        '',
        '',
        '',
        '',
      ],
      [
        _t('archive_piece_cloture'),
        cloture.pieceCloture ?? _tiret,
        '',
        '',
        '',
        '',
      ],
      [
        _t('archive_piece_a_nouveaux'),
        cloture.pieceANouveaux ?? _tiret,
        '',
        '',
        '',
        '',
      ],
      [_t('archive_resultat'), _fcfa(cloture.resultatCentimes), '', '', '', ''],
      section(_t('archive_section_balance').toUpperCase()),
      legende([
        _t('col_compte'),
        _t('col_libelle_ligne'),
        _t('col_debit'),
        _t('col_credit'),
        _t('archive_solde_debiteur'),
        _t('archive_solde_crediteur'),
      ]),
      for (final l in balance.lignes)
        [
          l.numeroCompte,
          l.libelle,
          _fcfaOuTiret(l.debitCentimes),
          _fcfaOuTiret(l.creditCentimes),
          _fcfaOuTiret(
            l.debitCentimes > l.creditCentimes
                ? l.debitCentimes - l.creditCentimes
                : 0,
          ),
          _fcfaOuTiret(
            l.creditCentimes > l.debitCentimes
                ? l.creditCentimes - l.debitCentimes
                : 0,
          ),
        ],
      [
        '',
        _t('totaux'),
        _fcfa(balance.lignes.fold(0, (t, l) => t + l.debitCentimes)),
        _fcfa(balance.lignes.fold(0, (t, l) => t + l.creditCentimes)),
        _fcfa(
          balance.lignes.fold(
            0,
            (t, l) =>
                t +
                (l.debitCentimes > l.creditCentimes
                    ? l.debitCentimes - l.creditCentimes
                    : 0),
          ),
        ),
        _fcfa(
          balance.lignes.fold(
            0,
            (t, l) =>
                t +
                (l.creditCentimes > l.debitCentimes
                    ? l.creditCentimes - l.debitCentimes
                    : 0),
          ),
        ),
      ],
      section(_t('archive_section_resultat').toUpperCase()),
      for (final l in compteResultat.lignes)
        ['', l.rubrique.libelle, '', '', '', _fcfa(l.montantCentimes)],
      [
        '',
        _t('archive_resultat'),
        '',
        '',
        '',
        _fcfa(compteResultat.resultatNetCentimes),
      ],
      section(_t('archive_section_bilan').toUpperCase()),
      legende([
        '',
        _t('archive_poste'),
        _t('archive_brut'),
        _t('archive_amortissement'),
        _t('archive_net'),
        '',
      ]),
      for (final p in [...bilan.actif, ...bilan.passif])
        [
          '',
          p.libelle,
          _fcfaOuTiret(p.brutCentimes),
          _fcfaOuTiret(p.amortissementCentimes),
          _fcfa(p.netCentimes),
          '',
        ],
      [
        '',
        _t('archive_total_actif'),
        '',
        '',
        _fcfa(bilan.totalActifCentimes),
        '',
      ],
      [
        '',
        _t('archive_total_passif'),
        '',
        '',
        _fcfa(bilan.totalPassifCentimes),
        '',
      ],
    ];

    return EtatTabulaireA4(
      titre: titre,
      portee:
          'Exercice ${exercice.annee} · ${_jour(exercice.dateDebut)} — '
          '${_jour(exercice.dateFin)}',
      colonnes: const [
        ColonneEtat('Compte', largeur: 1.2),
        ColonneEtat('Libellé', largeur: 3.4),
        ColonneEtat.nombre('Débit / Brut', largeur: 1.6),
        ColonneEtat.nombre('Crédit / Amort.', largeur: 1.6),
        ColonneEtat.nombre('Solde débiteur / Net', largeur: 1.6),
        ColonneEtat.nombre('Solde créditeur', largeur: 1.6),
      ],
      lignes: lignes,
      visas: Visas.etatsCloture,
      paysage: false,
    );
  }

  /// `d/m/Y` — une date comptable `AAAA-MM-JJ`.
  static String _jour(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }
}
