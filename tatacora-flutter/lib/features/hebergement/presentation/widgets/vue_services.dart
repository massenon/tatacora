// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/service_reservation.dart';

/// La couleur du maître pour chaque service.
///
/// La correspondance vit dans la présentation, pas dans le domaine :
/// `ServiceReservation` doit rester instanciable sans Flutter, sans quoi aucun
/// test de domaine ne pourrait le monter hors d'un binding graphique.
Color couleurService(ServiceReservation s) => switch (s) {
  ServiceReservation.hebergement => AppColors.serviceHebergement,
  ServiceReservation.restauration => AppColors.serviceRestauration,
  ServiceReservation.bar => AppColors.serviceBar,
  ServiceReservation.tourisme => AppColors.serviceTourisme,
  ServiceReservation.vehicule => AppColors.serviceVehicule,
};

/// La grille des cinq cases à cocher.
///
/// Maître : `prototype_v2/pages/reservations.html` l.143-147 — un libellé
/// obligatoire (« Services inclus dans cette réservation * »), le message
/// d'erreur juste dessous, puis une grille à deux colonnes, trois au-delà du
/// seuil `sm`.
class GrilleServices extends StatelessWidget {
  const GrilleServices({
    required this.coches,
    required this.onBascule,
    this.erreur,
    super.key,
  });

  final Set<ServiceReservation> coches;
  final void Function(ServiceReservation) onBascule;

  /// Ce qu'affiche le `#erreur-services` du maître.
  final String? erreur;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Services inclus dans cette réservation '),
              TextSpan(
                text: '*',
                style: textes.labelMedium?.copyWith(color: AppColors.erreur),
              ),
            ],
          ),
          style: textes.labelMedium,
        ),
        if (erreur != null) ...[
          const SizedBox(height: AppSpacing.unit),
          Text(
            erreur!,
            key: const Key('erreur-services'),
            style: textes.labelSmall?.copyWith(color: AppColors.erreur),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, contraintes) {
            // Deux colonnes, trois au-delà du seuil `sm` du maître (640 px).
            final colonnes = contraintes.maxWidth >= 640 ? 3 : 2;
            final largeur =
                (contraintes.maxWidth - AppSpacing.xs * (colonnes - 1)) /
                colonnes;
            return Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final service in ServiceReservation.values)
                  SizedBox(
                    width: largeur,
                    child: _CaseService(
                      service: service,
                      cochee: coches.contains(service),
                      onBascule: () => onBascule(service),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CaseService extends StatelessWidget {
  const _CaseService({
    required this.service,
    required this.cochee,
    required this.onBascule,
  });

  final ServiceReservation service;
  final bool cochee;
  final VoidCallback onBascule;

  @override
  Widget build(BuildContext context) {
    final couleur = couleurService(service);

    return InkWell(
      key: Key('service-${service.cle}'),
      onTap: onBascule,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          // Le maître peint la case cochée à la couleur du service et laisse
          // les autres blanches : c'est ce qui rend la sélection lisible d'un
          // coup d'œil sur cinq entrées.
          color: cochee ? couleur : AppColors.neutre0,
          border: Border.all(color: cochee ? couleur : AppColors.neutre200),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              cochee ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: cochee ? AppColors.neutre0 : AppColors.neutre300,
            ),
            const SizedBox(width: AppSpacing.unit),
            Flexible(
              child: Text(
                service.nom,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cochee ? AppColors.neutre0 : AppColors.neutre700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le bloc de lignes d'un service coché.
///
/// Maître : `reservations-services.js:rendreZoneLignes()` — nom du service à sa
/// couleur, bouton « Ajouter … », le bandeau des nuits pour l'hébergement, les
/// lignes, puis le sous-total du service.
class BlocLignesService extends StatelessWidget {
  const BlocLignesService({
    required this.rayon,
    required this.lignes,
    required this.nuits,
    required this.onAjouter,
    required this.onRetirer,
    required this.onChoisir,
    required this.onQuantite,
    super.key,
  });

  final RayonService rayon;
  final List<LigneService> lignes;

  /// `null` tant que les deux dates ne sont pas saisies — le maître affiche
  /// alors une consigne plutôt qu'un zéro, qui ressemblerait à un calcul juste.
  final int? nuits;

  final VoidCallback onAjouter;
  final void Function(String ligneId) onRetirer;
  final void Function(String ligneId, OptionService option) onChoisir;
  final void Function(String ligneId, int quantite) onQuantite;

  ServiceReservation get _service => rayon.service;

  int get _sousTotal =>
      lignes.fold(0, (somme, ligne) => somme + ligne.sousTotal);

  @override
  Widget build(BuildContext context) {
    final couleur = couleurService(_service);
    final textes = Theme.of(context).textTheme;

    return Container(
      key: Key('bloc-${_service.cle}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      // La bordure gauche de 3 px du maître, à la couleur du service : le seul
      // rappel de couleur dans le bloc.
      //
      // Deux `Container` imbriqués, et chacun évite un piège rencontré :
      // Flutter refuse un `borderRadius` sur une bordure de couleurs NON
      // uniformes, et une bande peinte par un `Row` en
      // `CrossAxisAlignment.stretch` part en relayout infini dans une vue
      // défilante — 6 000 exceptions par test. Le cadre arrondi est donc
      // dehors, la bande colorée dedans.
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: couleur, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _service.nom,
                          style: textes.labelMedium?.copyWith(color: couleur),
                        ),
                        TextButton(
                          key: Key('ajouter-${_service.cle}'),
                          onPressed: onAjouter,
                          // `ligne_ajouter` puis `labelLigne` : « + Ajouter une
                          // chambre ». Le « + » fait partie du libellé de la
                          // vue, pas d'une icône.
                          child: Text('+ Ajouter ${_service.labelLigne}'),
                        ),
                      ],
                    ),

                    // Un rayon vide reste VISIBLE avec sa raison, jamais omis.
                    if (rayon.estVide)
                      Text(
                        rayon.motifIndisponibilite ??
                            'Aucun élément disponible actuellement pour '
                                '${_service.nom.toLowerCase()}.',
                        key: Key('vide-${_service.cle}'),
                        style: textes.labelSmall?.copyWith(
                          color: AppColors.neutre500,
                        ),
                      ),

                    if (_service.quantiteEstCalculee) ...[
                      const SizedBox(height: AppSpacing.unit),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.unit,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.neutre100,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text.rich(
                          nuits == null
                              ? const TextSpan(
                                  text:
                                      'Renseignez les dates d\'arrivée et de départ : le nombre de nuits et les montants s\'en déduiront.',
                                )
                              : TextSpan(
                                  children: [
                                    // `<strong>:nombre nuit(s)</strong>` puis le
                                    // reste de `nuits_banner_connu`.
                                    TextSpan(
                                      text: '$nuits nuit(s)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(
                                      text:
                                          ' — calculées depuis les dates du séjour. Le champ n\'est pas saisissable : allongez ou raccourcissez le séjour et les montants suivent.',
                                    ),
                                  ],
                                ),
                          key: const Key('bandeau-nuits'),
                          style: textes.labelSmall,
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.xs),
                    if (lignes.isEmpty)
                      Text(
                        'Aucune ligne — cliquez sur « Ajouter » ci-dessus.',
                        style: textes.labelSmall?.copyWith(
                          color: AppColors.neutre300,
                        ),
                      ),
                    for (final ligne in lignes)
                      _LigneSaisie(
                        ligne: ligne,
                        options: rayon.options,
                        quantiteCalculee: _service.quantiteEstCalculee,
                        labelQuantite: _service.labelQuantite,
                        onRetirer: () => onRetirer(ligne.id),
                        onChoisir: (o) => onChoisir(ligne.id, o),
                        onQuantite: (q) => onQuantite(ligne.id, q),
                      ),

                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Sous-total ${_service.nom} : '),
                            TextSpan(
                              text: formaterFcfa(_sousTotal),
                              style: AppTextStyles.montant.copyWith(
                                color: couleur,
                              ),
                            ),
                          ],
                        ),
                        key: Key('sous-total-${_service.cle}'),
                        style: textes.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneSaisie extends StatelessWidget {
  const _LigneSaisie({
    required this.ligne,
    required this.options,
    required this.quantiteCalculee,
    required this.labelQuantite,
    required this.onRetirer,
    required this.onChoisir,
    required this.onQuantite,
  });

  final LigneService ligne;
  final List<OptionService> options;
  final bool quantiteCalculee;
  final String labelQuantite;
  final VoidCallback onRetirer;
  final void Function(OptionService) onChoisir;
  final void Function(int) onQuantite;

  @override
  Widget build(BuildContext context) {
    // Une option retenue mais devenue indisponible est SIGNALÉE, jamais
    // masquée : la masquer effacerait une décision déjà prise. Le maître a
    // corrigé exactement ce défaut le 21/08/2026 — la ligne retombait à zéro
    // franc au simple fait de rouvrir la fiche, et un élément indisponible
    // n'est pas un élément inexistant.
    final proposees = <OptionService>[
      for (final o in options)
        if (o.disponible || o.id == ligne.itemId)
          o.disponible
              ? o
              : OptionService(
                  id: o.id,
                  libelle: '${o.libelle} — indisponible, déjà retenu',
                  prix: o.prix,
                ),
    ];
    final choisies = proposees.where((o) => o.id == ligne.itemId);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<OptionService>(
              key: Key('choix-${ligne.id}'),
              initialValue: choisies.isEmpty ? null : choisies.first,
              isExpanded: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                // L'invite de la vue : l'hébergement a son sélecteur d'unité
                // (`champ_unite_invite`), les quatre autres services la ligne de
                // catalogue (`ligne_choisir`).
                hintText: ligne.service == ServiceReservation.hebergement
                    ? 'Choisir une unité…'
                    : 'Choisissez un élément du catalogue',
              ),
              items: [
                for (final o in proposees)
                  DropdownMenuItem(
                    value: o,
                    child: Text(
                      '${o.libelle} — ${formaterFcfa(o.prix)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (o) {
                if (o != null) onChoisir(o);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.unit),
          SizedBox(
            width: 76,
            child: quantiteCalculee
                // Le maître rend le champ en LECTURE SEULE et grisé plutôt que
                // de le masquer : le nombre de nuits doit rester visible,
                // c'est lui qui explique le montant.
                ? TextFormField(
                    key: Key('quantite-${ligne.id}'),
                    readOnly: true,
                    textAlign: TextAlign.center,
                    initialValue: '${ligne.quantite}',
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.neutre100,
                    ),
                  )
                : TextFormField(
                    key: Key('quantite-${ligne.id}'),
                    initialValue: '${ligne.quantite}',
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Plancher à 1, comme le maître : une quantité effacée ne
                    // doit pas devenir zéro en silence, sans quoi la ligne
                    // cesse de compter au total sans disparaître de l'écran.
                    onChanged: (v) {
                      final saisie = int.tryParse(v.trim()) ?? 1;
                      onQuantite(saisie < 1 ? 1 : saisie);
                    },
                  ),
          ),
          const SizedBox(width: AppSpacing.unit),
          SizedBox(
            width: 96,
            child: Text(
              formaterFcfa(ligne.sousTotal),
              key: Key('total-${ligne.id}'),
              textAlign: TextAlign.right,
              style: AppTextStyles.montant,
            ),
          ),
          IconButton(
            key: Key('retirer-${ligne.id}'),
            tooltip: 'Retirer cette ligne',
            onPressed: onRetirer,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
