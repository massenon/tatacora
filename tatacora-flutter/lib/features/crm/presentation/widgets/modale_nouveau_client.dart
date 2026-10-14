// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';
import '../../domain/detection_doublons.dart';
import '../../domain/entities/client.dart';

/// Ce qu'a saisi l'utilisateur dans la modale « Nouveau client » du registre.
final class SaisieClientRegistre {
  const SaisieClientRegistre({
    required this.nom,
    required this.telephone,
    required this.type,
  });

  final String nom;
  final String telephone;
  final TypeClientReferentiel type;
}

/// La modale **« Nouveau client »** du registre — `prototype_v2/pages/m3-clients-creances.html`,
/// balisage en `prototype_v2/pages/m3-clients-creances.js` l.609-650
/// (`ouvrirNouveauClient`), declenchee par le bouton « + Nouveau client » de
/// l'en-tete de page.
///
/// ## Ce n'est PAS la modale de la fiche de reservation, et les confondre
/// serait une derive de libelles
///
/// `dialogue_nouveau_client.dart` porte celle de `reservations.html`
/// (`modale-nouveau-client`) : elle s'intitule « Ajouter un client », son
/// champ dit « Nom », son bouton dit « Ajouter le client ». Le maitre du
/// registre ecrit trois mots differents — « Nouveau client », « Nom / Raison
/// sociale », « Creer le client » — et pose deux champs de plus.
/// L'Article 1 interdit de changer un libelle, meme pour un synonyme : les
/// deux modales coexistent donc, chacune fidele a sa page.
///
/// Jusqu'au 26/08/2026 l'ecran du registre ouvrait celle de la reservation.
/// Le bouton existait, la fonction marchait, et les mots affiches n'etaient
/// ceux d'aucune des deux pages a la fois.
///
/// ## RG-18 : la detection de doublon avait ete ECRITE et n'etait APPELEE par
/// personne
///
/// `doublonsPotentiels` (`domain/detection_doublons.dart`) transcrit la regle
/// du maitre — nom normalise identique, ou telephone identique au-dela de huit
/// chiffres — et **aucun code ne l'appelait**, pas meme un test. C'est le
/// piege 1 de ce depot : une regle ecrite n'est pas une regle appliquee, et un
/// referentiel unique (RG-18) qui ne previent d'aucun doublon ne protege rien.
/// Cette modale est son premier appelant reel.
///
/// Comme au maitre (l.660-663), c'est un **avertissement, jamais un blocage** :
/// deux homonymes existent, et refuser le second ferait saisir « KORA Jean 2 ».
/// Le libelle du bouton bascule alors sur « Creer malgre le doublon », mot pour
/// mot celui du maitre (l.688).
///
/// ## ECART DELIBERE — `prototype_v2/pages/m3-clients-creances.js` l.637-640
/// Le prototype : un champ texte « Ville », d'invite « Natitingou ».
/// Ici : le champ n'est pas offert ; son absence est affichee a sa place, avec
/// son motif.
/// Raison : element decoratif de la maquette — **aucune colonne `ville`
/// n'existe**, ni dans `clients_local` (Drift, `tables/clients_table.dart`),
/// ni dans la table serveur `clients`
/// (`tatacora-api/database/migrations/2026_08_01_000030_create_clients.php`,
/// verifiee le 26/08/2026). Offrir le champ collecterait une saisie **ignoree
/// a la validation**, ce que l'Article 6 exclut nommement. Et `clients` est au
/// registre `TABLES_SYNCHRONISABLES` : une colonne ajoutee au seul poste
/// serait perdue au premier aller-retour serveur, sans que rien ne le signale.
/// L'ajouter des deux cotes est un arbitrage de schema, ouvert a l'Architecte.
Future<SaisieClientRegistre?> demanderClientRegistre(BuildContext context) {
  return showDialog<SaisieClientRegistre>(
    context: context,
    // Le voile du maitre ferme la modale (`data-fermer` sur l'overlay) ;
    // `barrierDismissible` porte AUSSI la touche d'echappement en Flutter.
    // Article 4.6 exige les deux.
    barrierDismissible: true,
    builder: (context) => const _ModaleNouveauClient(),
  );
}

class _ModaleNouveauClient extends ConsumerStatefulWidget {
  const _ModaleNouveauClient();

  @override
  ConsumerState<_ModaleNouveauClient> createState() =>
      _ModaleNouveauClientState();
}

class _ModaleNouveauClientState extends ConsumerState<_ModaleNouveauClient> {
  final _formulaire = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _telephone = TextEditingController();

  TypeClientReferentiel _type = TypeClientReferentiel.particulier;

  /// La case du maitre (l.691-694). Elle retombe a `false` des que la saisie
  /// change : quelqu'un qui coche puis corrige le nom aurait sinon une
  /// confirmation acquise sur un doublon qu'il n'a jamais relu.
  bool _doublonConfirme = false;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  /// Les clients deja au referentiel. Le referentiel vient de la base locale :
  /// hors ligne, la detection fonctionne quand meme — c'est precisement au
  /// comptoir, sans reseau, qu'on cree un doublon.
  List<Client> get _referentiel =>
      ref.watch(clientsProvider).asData?.value ?? const [];

  List<Client> get _doublons => doublonsPotentiels(
    referentiel: _referentiel,
    nom: _nom.text,
    telephone: _telephone.text,
  );

  void _saisieAChange() => setState(() => _doublonConfirme = false);

  void _valider() {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SaisieClientRegistre(
        nom: _nom.text.trim(),
        telephone: _telephone.text.trim(),
        type: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final doublons = _doublons;

    return AlertDialog(
      key: const Key('modale-client-registre'),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      // L'en-tete du maitre (l.613-616) : titre a gauche, croix a droite.
      title: Row(
        children: [
          Expanded(child: Text('Nouveau client', style: textes.titleMedium)),
          IconButton(
            key: const Key('client-registre-fermer'),
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        key: const Key('client-registre-colonne'),
        width: AppLayout.modaleClientCrm,
        child: Form(
          key: _formulaire,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Champ 1 du maitre (l.619-624).
                TextFormField(
                  key: const Key('client-registre-nom'),
                  controller: _nom,
                  autofocus: true,
                  onChanged: (_) => _saisieAChange(),
                  decoration: const InputDecoration(
                    labelText: 'Nom / Raison sociale *',
                    hintText: 'Ex. Jean KORA ou Agence Bénin Tour',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Le nom du client est obligatoire.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                // La rangee a deux colonnes du maitre (l.625-636) :
                // « Téléphone » puis « Type », dans cet ordre.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('client-registre-telephone'),
                        controller: _telephone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => _saisieAChange(),
                        decoration: const InputDecoration(
                          labelText: 'Téléphone *',
                          hintText: '01 90 12 34 56',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            // Obligatoire au schema, et pour une raison de
                            // terrain : sans numero, un client qui ne se
                            // presente pas est injoignable.
                            ? 'Le téléphone est obligatoire : c’est par lui '
                                  'qu’on rappelle un client.'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<TypeClientReferentiel>(
                        key: const Key('client-registre-type'),
                        initialValue: _type,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        // Les quatre options du maitre (l.632-634), dans son
                        // ordre. ⚠ « Entreprise » s'ecrit `structure` au
                        // schema : c'est `TypeClientReferentiel` qui porte la
                        // correspondance, jamais l'ecran.
                        items: [
                          for (final t in TypeClientReferentiel.values)
                            DropdownMenuItem(value: t, child: Text(t.libelle)),
                        ],
                        onChanged: (t) {
                          if (t != null) setState(() => _type = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // A la place du champ « Ville » du maitre (l.637-640) — voir
                // l'ECART DELIBERE de l'en-tete de fichier.
                Container(
                  key: const Key('client-registre-ville-absente'),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.neutre100,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    'Ville — non saisissable. Ni la base de ce poste ni la '
                    'table « clients » du serveur ne portent cette colonne : '
                    'la valeur serait ignorée à l’enregistrement, puis perdue '
                    'au premier échange avec le serveur.',
                    style: textes.labelMedium?.copyWith(
                      color: AppColors.neutre500,
                    ),
                  ),
                ),
                // La zone `#zone-doublon` du maitre (l.642), RG-18.
                if (doublons.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _AvertissementDoublon(
                    doublons: doublons,
                    confirme: _doublonConfirme,
                    onConfirme: (v) => setState(() => _doublonConfirme = v),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      // Le pied du maitre (l.644-647) : « Annuler » puis le bouton principal,
      // alignes a droite, dans cet ordre.
      actions: [
        TextButton(
          key: const Key('client-registre-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('client-registre-creer'),
          // Le maitre n'exige la confirmation que s'il y a un doublon
          // (l.700-703) : sans doublon, le bouton n'est jamais desactive.
          onPressed: (doublons.isEmpty || _doublonConfirme) ? _valider : null,
          child: Text(
            // Les deux libelles du maitre (l.665 et l.688), mot pour mot.
            doublons.isNotEmpty && _doublonConfirme
                ? 'Créer malgré le doublon'
                : 'Créer le client',
          ),
        ),
      ],
    );
  }
}

/// L'avertissement de doublon — `m3-clients-creances.js` l.673-696.
class _AvertissementDoublon extends StatelessWidget {
  const _AvertissementDoublon({
    required this.doublons,
    required this.confirme,
    required this.onConfirme,
  });

  final List<Client> doublons;
  final bool confirme;
  final ValueChanged<bool> onConfirme;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Container(
      key: const Key('client-registre-doublon'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        // Le maitre ecrit `bg-amber-50 border border-amber-300` et
        // `text-amber-900` (`m3-clients-creances.js` l.673 et l.675) — de
        // l'AMBRE, pas le dore de la charte. Les deux se ressemblent a l'oeil
        // et ne sont pas la meme couleur : c'est l'interdit n° 09 de
        // l'Article 1, « approximer une couleur a l'oeil ».
        //
        // `amber-300` manquait a la palette parce que le comptage d'origine
        // portait sur les `.html` du maitre, et que ce pave est construit en
        // JavaScript. Il a ete releve le 27/08/2026 avec sa ligne.
        color: PaletteMaitre.ambre50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: PaletteMaitre.ambre300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Les deux formulations du maitre (l.679-681) — le singulier et le
            // pluriel sont distincts chez lui, et ce n'est pas une negligence.
            doublons.length == 1
                ? 'Un client existant correspond déjà'
                : '${doublons.length} clients existants correspondent déjà',
            style: textes.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.unit),
          for (final c in doublons)
            Text(
              // Le maitre affiche a cote le montant du : il vient de son
              // `CreancesEngine`. Ici le solde se compose des lignes
              // (`composerRegistre`, PA-126) et la colonne `solde` vaut zero
              // pour tout le monde — l'afficher donnerait un zero plausible
              // sur la fiche d'un debiteur. Seul le numero est repris.
              '${c.nomComplet} — ${c.telephone}',
              key: Key('client-registre-doublon-${c.id}'),
              style: textes.labelMedium,
            ),
          const SizedBox(height: AppSpacing.xs),
          // La case du maitre (l.691-694). Un `Row` plutot qu'un
          // `CheckboxListTile` : ce dernier peint son fond et ses ondes sur le
          // `Material` le plus proche, que le cadre dore ci-dessus masquerait —
          // le framework le signale, et la case paraitrait inerte au clic.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                key: const Key('client-registre-confirmer-doublon'),
                value: confirme,
                onChanged: (v) => onConfirme(v ?? false),
              ),
              Expanded(
                child: Text(
                  'Il s\'agit bien d\'une personne différente — créer quand '
                  'même.',
                  style: textes.labelMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
