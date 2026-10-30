import 'package:flutter/material.dart';

/// Shared front-end spacing and labels; does not own input values or validation.
class FormFieldBlock extends StatelessWidget {
  final String label;
  final Widget child;
  const FormFieldBlock({super.key, required this.label, required this.child});
  String get caption => label
      .replaceAll(' YYYY-MM-DD', '')
      .replaceAll(' sintetis', '')
      .replaceAll('Asupan energi 24 jam', 'Energi harian')
      .replaceAll('Asupan protein 24 jam', 'Protein harian')
      .replaceAll(' / wajib jika tolak', '')
      .replaceAll('Lingkar lengan atas (LiLA) cm', 'LiLA (cm)')
      .replaceAll('Lingkar kepala (LK) cm', 'Lingkar kepala (cm)')
      .replaceAll(' — opsional', ' (opsional)');
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            caption,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(label: label, child: child),
      ],
    ),
  );
}
