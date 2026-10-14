import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
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

/// La modale **« Ajouter un client »** — `reservations.html`,
/// `modale-nouveau-client`.
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
      title: const Text('Ajouter un client'),
      content: SizedBox(
        width: 420,
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
                  labelText: 'Nom *',
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
                  hintText: '+229 …',
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
