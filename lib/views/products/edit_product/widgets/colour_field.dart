import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import 'edit_inputs.dart';

/// Free-text `colour` input that suggests values from the platform's colour
/// vocabulary as the seller types, so the common spellings get reused without
/// locking out a colour the list doesn't have.
class ColourField extends StatefulWidget {
  const ColourField({super.key, required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  /// The colour vocabulary, as supplied by the product team. Kept verbatim
  /// (near-duplicates included) so values match what the platform stores.
  static const List<String> vocabulary = [
    'Beige', 'Without', 'Blueberry Stripe', 'Blue', 'Blue/Navy', 'Brown',
    'Burgundy', 'coastal beige', 'Creme', 'Grey', 'Green', 'Gray', 'Gul',
    'Gull', 'White', 'White,Silver', 'Khaki/Navy blue', 'Navy blue',
    'Midnight blue sapphire', 'Midnight Sapphire', 'Multi', 'Nude', 'Orange',
    'Red', 'Rosa', 'Black', 'Black / Grey', 'Silver', 'Wine red',
  ];

  @override
  State<ColourField> createState() => _ColourFieldState();
}

class _ColourFieldState extends State<ColourField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditFieldLabel(widget.label),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => RawAutocomplete<String>(
              textEditingController: widget.controller,
              focusNode: _focus,
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return const Iterable<String>.empty();
                return ColourField.vocabulary.where(
                    (c) => c.toLowerCase().contains(q) && c.toLowerCase() != q);
              },
              fieldViewBuilder: (context, controller, focus, onSubmit) =>
                  TextField(
                controller: controller,
                focusNode: focus,
                onSubmitted: (_) => onSubmit(),
                cursorColor: AppColors.brandNavy,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                decoration: editInputDecoration(),
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 220,
                      maxWidth: constraints.maxWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              child: CustomText(option,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
