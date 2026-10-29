import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../controllers/seller_products_controller.dart';
import '../../../../core/localization/translation_keys.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/custom_text.dart';
import '../../../../models/product_edit_log.dart';
import '../../my_requests/my_requests_view.dart' show formatRequestDate;
import '../widgets/edit_inputs.dart';

/// The product's edit log (`GET …/edit-logs`): one card per save, listing each
/// field that changed with its old → new value, who did it and why.
///
/// The API returns one row per field, so rows sharing an editor, reason and
/// timestamp are folded back into the save they came from.
class HistorySection extends StatefulWidget {
  const HistorySection({super.key, required this.productId, required this.ctrl});

  final String productId;
  final SellerProductsController ctrl;

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  List<ProductEditLog>? _logs;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final logs =
        await widget.ctrl.loadEditLogs(widget.productId, force: force);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _failed = logs == null;
      _loading = false;
    });
  }

  /// Folds per-field rows into saves (same editor, reason and minute).
  List<List<ProductEditLog>> _group(List<ProductEditLog> logs) {
    final groups = <List<ProductEditLog>>[];
    for (final log in logs) {
      final last = groups.isEmpty ? null : groups.last.first;
      final same = last != null &&
          last.editedBy == log.editedBy &&
          last.reason == log.reason &&
          last.createdAt != null &&
          log.createdAt != null &&
          last.createdAt!.difference(log.createdAt!).inSeconds.abs() < 60;
      if (same) {
        groups.last.add(log);
      } else {
        groups.add([log]);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _logs == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_failed) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        text: TKeys.editHistoryFailed.tr,
        action: TextButton(
          onPressed: () => _load(force: true),
          child: CustomText(TKeys.retry.tr,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy),
        ),
      );
    }
    final logs = _logs ?? const <ProductEditLog>[];
    if (logs.isEmpty) {
      return _Empty(icon: Icons.history_rounded, text: TKeys.editHistoryEmpty.tr);
    }
    return Column(
      children: [
        for (final save in _group(logs)) _SaveCard(entries: save),
      ],
    );
  }
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.entries});

  final List<ProductEditLog> entries;

  @override
  Widget build(BuildContext context) {
    final head = entries.first;
    final who = head.editorDisplayName ?? head.editedBy;
    return EditGroup(
      title: formatRequestDate(head.createdAt),
      icon: Icons.history_rounded,
      subtitle: who == null ? null : TKeys.editHistoryBy.trParams({'name': who}),
      children: [
        if (head.reason != null && head.reason!.trim().isNotEmpty) ...[
          EditFieldLabel(TKeys.reasonForChange.tr),
          const SizedBox(height: 4),
          CustomText(head.reason!,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: AppColors.textPrimary),
          const SizedBox(height: 12),
        ],
        for (final e in entries) _FieldChange(entry: e),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _FieldChange extends StatelessWidget {
  const _FieldChange({required this.entry});

  final ProductEditLog entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The API's own field name — the same identifier the web log shows.
          CustomText(entry.field,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary),
          const SizedBox(height: 6),
          CustomText(entry.oldValue ?? '—',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
              decoration: TextDecoration.lineThrough),
          const SizedBox(height: 2),
          CustomText(entry.newValue ?? '—',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            CustomText(text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                textAlign: TextAlign.center,
                color: AppColors.textSecondary),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
