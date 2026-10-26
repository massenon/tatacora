// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/entities/client.dart';

/// Ce qu'a saisi l'utilisateur dans la modale « Nouveau client ».
final class SaisieNouveauClient {
  const SaisieNouveauClient({
    required this.nom,
    required this.telephone,
    required this.type,
  });

  final String nom;
  final String telephone;
  final TypeClientReferentiel type;
}

/// La modale **« Ajouter un client »** de la fiche de réservation
/// (`reservations.blade.php` l.745-784, `modale_client_titre`).
///
/// ## Les mots de la vue (21/10/2026)
///
/// Le titre « Ajouter un client » et son sous-titre « Fiche client unique du
/// référentiel — RG-18. », « Nom complet » (invite « Ex. Jean KORA »),
/// « Téléphone » (invite « 01 97 35 59 74 »), « Type de client », la note du
/// droit M3, « Annuler » et « Ajouter le client ». La note dit le droit exigé :
/// créer une fiche client est une écriture M3, en plus du droit M1 — c'est ce que
/// fait la fiche en masquant le bouton sans `C` sur M3.
///
/// ## Trois champs, et le maître a raison de s'y tenir
///
/// Nom, téléphone, type. Pas d'adresse, pas d'e-mail : au comptoir, on ajoute
/// un client **pendant** qu'un client attend. Un formulaire complet ferait
/// renoncer, et le réceptionniste retomberait sur la saisie libre — c'est-à-dire
/// sur le défaut que ce bouton existe pour supprimer.
///
/// Le téléphone est obligatoire, comme au schéma : c'est par lui qu'on rappelle
/// quelqu'un, et c'est lui qui sert à détecter les doublons (RG-18).
Future<SaisieNouveauClient?> demanderNouveauClient(BuildContext context) {
  return showDialog<SaisieNouveauClient>(
    context: context,
    builder: (context) => const _DialogueNouveauClient(),
  );
}

class _DialogueNouveauClient extends StatefulWidget {
  const _DialogueNouveauClient();

  @override
  State<_DialogueNouveauClient> createState() => _DialogueNouveauClientState();
}

class _DialogueNouveauClientState extends State<_DialogueNouveauClient> {
  final _formulaire = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _telephone = TextEditingController();

  TypeClientReferentiel _type = TypeClientReferentiel.particulier;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  void _valider() {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SaisieNouveauClient(
        nom: _nom.text.trim(),
        telephone: _telephone.text.trim(),
        type: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('modale-nouveau-client'),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ajouter un client'),
          Text(
            'Fiche client unique du référentiel.',
            key: Key('nouveau-client-sous-titre'),
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: Tailles.t13,
              fontWeight: FontWeight.normal,
              color: AppColors.neutre500,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: AppLayout.modaleClientReservation,
        child: Form(
          key: _formulaire,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('nouveau-client-nom'),
                controller: _nom,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom complet *',
                  hintText: 'Ex. Jean KORA',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Le nom du client est obligatoire.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('nouveau-client-telephone'),
                controller: _telephone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone *',
                  hintText: '01 97 35 59 74',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    // Obligatoire au schéma, et pour une raison de terrain :
                    // sans numéro, un client qui ne se présente pas est
                    // injoignable, et la chambre reste bloquée.
                    ? 'Le téléphone est obligatoire : c’est par lui qu’on '
                          'rappelle un client.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<TypeClientReferentiel>(
                key: const Key('nouveau-client-type'),
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Type de client',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final t in TypeClientReferentiel.values)
                    DropdownMenuItem(value: t, child: Text(t.libelle)),
                ],
                onChanged: (t) {
                  if (t != null) setState(() => _type = t);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                "Créer une fiche client demande le droit d'écriture sur les clients, en plus de celui sur l'hébergement.",
                key: Key('nouveau-client-droit-m3'),
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: Tailles.t12,
                  color: AppColors.neutre500,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('nouveau-client-annuler'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('nouveau-client-enregistrer'),
          onPressed: _valider,
          child: const Text('Ajouter le client'),
        ),
      ],
    );
  }
}
