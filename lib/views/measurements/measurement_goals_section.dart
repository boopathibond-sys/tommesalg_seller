import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/measurement_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/measurement.dart';
import '../../core/localization/translation_keys.dart';

/// The "Measurements" block embedded in the product quick views — optional
/// clothing measurements and size / spec photos the seller records per
/// product.
///
/// Loads `GET /products/{id}/measurement-bundle` on open (recorded values +
/// the measurement-type catalog) together with
/// `GET /products/{id}/size-spec-images`, lets the seller add a numeric field
/// per target type and attach photos, and saves both with
/// `POST /measurements/{id}` and `PUT /products/{id}/size-spec-images`.
///
/// Pass [placementId] to scope the measurements to one SKU placement; omit it
/// for product-level scope (Manage Products, which has no placement).
class MeasurementGoalsSection extends StatefulWidget {
  const MeasurementGoalsSection({
    super.key,
    required this.productId,
    this.placementId,
    this.skuCode,
  });

  final String productId;

  /// Placement this product sits in, when opened from a SKU.
  final String? placementId;

  /// SKU code, shown in the section's subtitle when known.
  final String? skuCode;

  @override
  State<MeasurementGoalsSection> createState() =>
      _MeasurementGoalsSectionState();
}

/// One size / spec photo on the form. [key] is the `s3Key` the save sends;
/// [localPath] is set for a photo picked in this session so the thumb can be
/// rendered before the server ever hands back a URL.
class _SpecPhoto {
  _SpecPhoto({required this.key, this.url, this.localPath});

  final String key;
  final String? url;
  final String? localPath;

  /// Last path segment of the key — what the placeholder tile shows.
  String get fileName {
    final path = key.split('?').first;
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// One measurement row in the form — its target type and the field the seller
/// types into. [measurementId] is set only for rows loaded from the server, so
/// removing them can be pushed through the delete endpoint.
class _GoalRow {
  _GoalRow({required this.type, required this.controller, this.measurementId});

  final MeasurementType type;
  final TextEditingController controller;
  final String? measurementId;
}

class _MeasurementGoalsSectionState extends State<MeasurementGoalsSection> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  List<MeasurementType> _types = const [];
  final List<_GoalRow> _rows = <_GoalRow>[];

  /// Ids of saved measurements the seller removed — deleted on save.
  final Set<String> _removedIds = <String>{};

  /// Size / spec photos currently on the form: what the product had, minus
  /// anything removed here, plus anything uploaded here. Saving PUTs exactly
  /// this list, because the endpoint replaces the whole set.
  final List<_SpecPhoto> _photos = <_SpecPhoto>[];

  /// The keys the product had when the section opened, so the save only fires
  /// when the set actually changed.
  List<String> _initialPhotoKeys = const [];

  bool _uploadingPhotos = false;

  final ImagePicker _picker = ImagePicker();

  /// Ceiling on attached photos, and the API's own file rules.
  static const int _maxPhotos = 10;
  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const Set<String> _allowedPhotoExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  /// Controllers detached from [_rows]; disposed with the widget so a removal
  /// can never leave a live TextField pointing at a disposed controller.
  final List<TextEditingController> _retired = <TextEditingController>[];

  /// Types not already on the form — the pickable options.
  List<MeasurementType> get _available {
    final used = _rows.map((r) => r.type.key).toSet();
    return _types.where((t) => !used.contains(t.key)).toList();
  }

  bool get _hasChangesToSave =>
      _rows.isNotEmpty || _removedIds.isNotEmpty || _photosChanged;

  /// The photo keys as they'd be saved, in order.
  List<String> get _photoKeys => _photos.map((p) => p.key).toList();

  bool get _photosChanged {
    final keys = _photoKeys;
    if (keys.length != _initialPhotoKeys.length) return true;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != _initialPhotoKeys[i]) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _retired) {
      c.dispose();
    }
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  /// Moves the current rows' controllers to the retired list so they stay
  /// alive until the widget is disposed.
  void _retireRows() {
    _retired.addAll(_rows.map((r) => r.controller));
    _rows.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final bundle = await MeasurementService.instance.fetchBundle(
      productId: widget.productId,
    );

    if (!mounted) return;

    if (bundle == null) {
      setState(() {
        _loading = false;
        _loadError = TKeys.msCouldNotLoad.tr;
      });
      return;
    }

    // The server's catalog wins — it is what the save endpoint validates
    // fieldKeys against. The static list only fills in when it sends none.
    final types = bundle.measurementTypes.isNotEmpty
        ? bundle.measurementTypes
        : kDefaultMeasurementTypes;

    setState(() {
      _types = types;
      _applyMeasurements(bundle.measurements);
      _applyPhotos(bundle.sizeSpecImages);
      _loading = false;
    });
  }

  /// Rebuilds the form from a server-authoritative set of measurements. Call
  /// inside [setState].
  void _applyMeasurements(List<Measurement> measurements) {
    _removedIds.clear();
    _retireRows();

    for (final m in measurements) {
      if (m.fieldKey.isEmpty) continue;
      _rows.add(
        _GoalRow(
          type: _typeFor(m, _types),
          controller: TextEditingController(text: _formatValue(m.valueCm)),
          measurementId: m.id,
        ),
      );
    }
  }

  /// Seeds the photo strip from the bundle's `product.sizeSpecImages`. Call
  /// inside [setState].
  void _applyPhotos(List<SizeSpecImage> images) {
    _photos
      ..clear()
      ..addAll(
        images.map((image) => _SpecPhoto(key: image.key, url: image.url)),
      );
    _initialPhotoKeys = _photoKeys;
  }

  /// Matches a saved measurement to its type, synthesising one when the server
  /// returns a value whose fieldKey is not in the catalog — so the row still
  /// renders rather than silently disappearing.
  MeasurementType _typeFor(Measurement m, List<MeasurementType> types) {
    for (final t in types) {
      if (t.key == m.fieldKey ||
          (m.measurementTypeId != null && t.id == m.measurementTypeId)) {
        return t;
      }
    }
    return MeasurementType(
      key: m.fieldKey,
      label: m.label ?? _prettify(m.fieldKey),
    );
  }

  /// `sleeve_length` → `Sleeve Length`.
  String _prettify(String key) => key
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  /// Trims the trailing `.0` so a whole number reads as "58", not "58.0".
  String _formatValue(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  void _addRow(MeasurementType type) {
    setState(() {
      _rows.add(_GoalRow(type: type, controller: TextEditingController()));
    });
  }

  void _removeRow(_GoalRow row) {
    setState(() {
      _rows.remove(row);
      final id = row.measurementId;
      if (id != null) _removedIds.add(id);
    });
    _retired.add(row.controller);
  }

  // ---------- Size / spec photos ----------

  /// Picks one or more photos and uploads each straight away — the POST only
  /// returns an `s3Key`; nothing lands on the product until Save.
  Future<void> _addPhotos() async {
    if (_uploadingPhotos || _photos.length >= _maxPhotos) return;

    final source = await _choosePhotoSource();
    if (source == null || !mounted) return;

    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      picked = shot == null ? const [] : [shot];
    } else {
      picked = await _picker.pickMultiImage();
    }
    if (picked.isEmpty || !mounted) return;

    final room = _maxPhotos - _photos.length;
    final queue = <XFile>[];
    var rejectedType = 0;
    var rejectedSize = 0;

    for (final file in picked) {
      if (queue.length >= room) break;
      if (!_isAllowedPhoto(file)) {
        rejectedType += 1;
        continue;
      }
      if (await File(file.path).length() > _maxPhotoBytes) {
        rejectedSize += 1;
        continue;
      }
      queue.add(file);
    }

    if (!mounted) return;
    if (rejectedType > 0) {
      _snack(TKeys.unsupportedFile.tr, TKeys.msOnlyImageTypes.tr, ok: false);
    }
    if (rejectedSize > 0) {
      _snack(TKeys.msTooLarge.tr, TKeys.msMaxFiveMb.tr, ok: false);
    }
    if (queue.isEmpty) return;

    setState(() => _uploadingPhotos = true);

    for (final file in queue) {
      final result = await MeasurementService.instance.uploadSizeSpecImage(
        productId: widget.productId,
        filePath: file.path,
      );
      if (!mounted) return;

      if (!result.ok) {
        setState(() => _uploadingPhotos = false);
        _snack(TKeys.csUploadFailed.tr, result.error!, ok: false);
        return;
      }

      setState(() {
        _photos.add(
          _SpecPhoto(
            key: result.image!.key,
            url: result.image!.url,
            localPath: file.path,
          ),
        );
      });
    }

    if (!mounted) return;
    setState(() => _uploadingPhotos = false);
  }

  bool _isAllowedPhoto(XFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _allowedPhotoExtensions.contains(name.substring(dot + 1));
  }

  /// Bottom sheet offering Camera or Gallery.
  Future<ImageSource?> _choosePhotoSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.cameraSource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.brandNavy),
              title: CustomText(TKeys.gallerySource.tr,
                  fontSize: 15, fontWeight: FontWeight.w700),
              onTap: () => Navigator.of(sheetCtx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Drops a thumb locally. There is no remove endpoint — Save sends the
  /// remaining keys, and the server keeps exactly those.
  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _snack(String title, String message, {required bool ok}) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: ok ? Colors.green.shade600 : Colors.red.shade600,
      colorText: Colors.white,
    );
  }

  /// Deletes any removed rows, saves the remaining ones as the full set, then
  /// replaces the size / spec photo set when it changed.
  Future<void> _save() async {
    if (_saving) return;

    final inputs = <MeasurementInput>[];
    for (final row in _rows) {
      final raw = row.controller.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) {
        _snack(TKeys.errorTitle.tr, TKeys.msEnterValueFor.trParams({'field': row.type.label}), ok: false);
        return;
      }
      final value = double.tryParse(raw);
      if (value == null || value <= 0) {
        _snack(TKeys.errorTitle.tr, TKeys.msEnterValidCm.trParams({'field': row.type.label}), ok: false);
        return;
      }
      inputs.add(MeasurementInput(fieldKey: row.type.key, valueCm: value));
    }

    setState(() => _saving = true);

    for (final id in _removedIds) {
      final error = await MeasurementService.instance.deleteMeasurement(id);
      if (error != null) {
        if (!mounted) return;
        setState(() => _saving = false);
        _snack(TKeys.errorTitle.tr, error, ok: false);
        return;
      }
    }

    // Nothing left to send when the seller only removed rows.
    var saved = const <Measurement>[];
    if (inputs.isNotEmpty) {
      final result = await MeasurementService.instance.saveMeasurements(
        productId: widget.productId,
        measurements: inputs,
      );
      if (!mounted) return;
      if (!result.ok) {
        setState(() => _saving = false);
        _snack(TKeys.errorTitle.tr, result.error!, ok: false);
        return;
      }
      saved = result.measurements;
    }

    // The photo set is a separate endpoint, and a replace rather than a
    // patch — send it only when this session actually changed it.
    if (_photosChanged) {
      final error = await MeasurementService.instance.saveSizeSpecImages(
        productId: widget.productId,
        imageKeys: _photoKeys,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() => _saving = false);
        _snack(TKeys.errorTitle.tr, error, ok: false);
        return;
      }
      _initialPhotoKeys = _photoKeys;
    }

    if (!mounted) return;
    _snack(TKeys.successTitle.tr, TKeys.msMeasurementsSaved.tr, ok: true);

    // Prefer the set the save echoed back; only re-read when it returned none.
    if (saved.isNotEmpty) {
      setState(() {
        _applyMeasurements(saved);
        _saving = false;
      });
      return;
    }
    setState(() => _saving = false);
    await _load();
  }

  // ---------- Presentation ----------

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          CustomText(
            _subtitle,
            fontSize: 12,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          if (_loading)
            _buildLoading()
          else if (_loadError != null)
            _buildLoadError()
          else ...[
            if (_rows.isEmpty) _buildEmptyState() else _buildGoalList(),
            const SizedBox(height: 10),
            _buildTypePicker(),
            const SizedBox(height: 16),
            _buildPhotosBlock(),
            const SizedBox(height: 14),
            _buildSaveButton(),
          ],
        ],
      ),
    );
  }

  String get _subtitle {
    final sku = widget.skuCode;
    final scope = (sku != null && sku.isNotEmpty)
        ? ' ${TKeys.msSkuScope.trParams({'sku': sku})}'
        : '';
    return TKeys.msOptionalMeasurements.trParams({'scope': scope});
  }

  /// Ruler icon + title, with a count pill once anything is on the form.
  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.straighten_rounded,
            size: 17, color: AppColors.brandNavy),
        const SizedBox(width: 7),
        CustomText(
          TKeys.msMeasurements.tr,
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        const Spacer(),
        if (!_loading && _loadError == null && _rows.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.brandYellow.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: CustomText(
              TKeys.msAddedCount.trParams({'count': '${_rows.length}'}),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildLoadError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.vipps),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              _loadError!,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.grey),
              ),
              child: CustomText(
                TKeys.retryAction.tr,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        children: [
          Icon(
            Icons.straighten_rounded,
            size: 26,
            color: AppColors.textMuted.withOpacity(0.7),
          ),
          const SizedBox(height: 8),
          CustomText(
            TKeys.msNoMeasurements.tr,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 3),
          CustomText(
            TKeys.msPickTargetType.tr,
            fontSize: 11.5,
            textAlign: TextAlign.center,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }

  /// The added measurements as one divided card — reads like a spec sheet
  /// rather than a stack of loose form fields.
  Widget _buildGoalList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.grey),
            _buildGoalRow(_rows[i]),
          ],
        ],
      ),
    );
  }

  /// One target: label on the left, a tight numeric chip and its unit on the
  /// right, then remove. Units sit in their own column so they line up down
  /// the card.
  Widget _buildGoalRow(_GoalRow row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              row.type.label,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 72, child: _buildValueField(row)),
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: CustomText(
              row.type.unit,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 2),
          _buildRemoveButton(row),
        ],
      ),
    );
  }

  Widget _buildValueField(_GoalRow row) {
    return TextField(
      controller: row.controller,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: AppColors.inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.grey),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildRemoveButton(_GoalRow row) {
    final enabled = !_saving;
    return GestureDetector(
      onTap: enabled ? () => _removeRow(row) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.vipps.withOpacity(0.1)
              : AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 15,
          color: enabled ? AppColors.vipps : AppColors.textMuted,
        ),
      ),
    );
  }

  /// Target-type dropdown. Its value stays null so it always reads
  /// "Select target type" — picking an option adds a row instead of becoming
  /// the selection. Types already on the form drop out of the list.
  Widget _buildTypePicker() {
    final available = _available;
    final enabled = available.isNotEmpty && !_saving;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MeasurementType>(
          value: null,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: enabled ? AppColors.textSecondary : AppColors.textMuted,
          ),
          hint: _pickerLabel(
            icon: Icons.add_rounded,
            text: TKeys.msSelectTargetType.tr,
            muted: false,
          ),
          disabledHint: _pickerLabel(
            icon: Icons.check_rounded,
            text: TKeys.msAllTargetTypes.tr,
            muted: true,
          ),
          items: available.map((type) {
            return DropdownMenuItem<MeasurementType>(
              value: type,
              child: CustomText(
                type.label,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            );
          }).toList(),
          onChanged: enabled
              ? (type) {
                  if (type != null) _addRow(type);
                }
              : null,
        ),
      ),
    );
  }

  /// Leading badge + text used by both the picker's hint and disabled hint.
  Widget _pickerLabel({
    required IconData icon,
    required String text,
    required bool muted,
  }) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: muted
                ? AppColors.inputFill
                : AppColors.brandYellow.withOpacity(0.35),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 15,
            color: muted ? AppColors.textMuted : AppColors.brandNavy,
          ),
        ),
        const SizedBox(width: 10),
        CustomText(
          text,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: muted ? AppColors.textMuted : AppColors.textSecondary,
        ),
      ],
    );
  }

  /// Size / spec photo strip: what's on the product, plus anything added
  /// here, with an Add tile at the end.
  Widget _buildPhotosBlock() {
    final atLimit = _photos.length >= _maxPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 15, color: AppColors.brandNavy),
            const SizedBox(width: 7),
            CustomText(
              TKeys.msMeasurementPhotos.tr,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const Spacer(),
            CustomText(
              '${_photos.length} / $_maxPhotos',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 4),
        CustomText(
          TKeys.msPhotoHint.tr,
          fontSize: 11.5,
          height: 1.4,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _photos.length) {
                return _buildAddPhotoTile(atLimit);
              }
              return _buildPhotoThumb(index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddPhotoTile(bool atLimit) {
    final enabled = !atLimit && !_uploadingPhotos && !_saving;

    return GestureDetector(
      onTap: enabled ? _addPhotos : null,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? AppColors.inputBorder : AppColors.grey,
          ),
        ),
        child: _uploadingPhotos
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    atLimit
                        ? Icons.check_rounded
                        : Icons.add_a_photo_outlined,
                    size: 20,
                    color: enabled ? AppColors.brandNavy : AppColors.textMuted,
                  ),
                  const SizedBox(height: 6),
                  CustomText(
                    atLimit ? TKeys.msLimit.tr : TKeys.msAddPhoto.tr,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: enabled ? AppColors.textSecondary
                        : AppColors.textMuted,
                  ),
                ],
              ),
      ),
    );
  }

  /// One thumb — the local file while the seller is still on this dialog, the
  /// signed URL once it comes back from the server, and a named placeholder
  /// when all we hold is an S3 key.
  Widget _buildPhotoThumb(int index) {
    final photo = _photos[index];
    final url = photo.url != null && photo.url!.startsWith('http')
        ? photo.url
        : (photo.key.startsWith('http') ? photo.key : null);

    Widget image;
    if (photo.localPath != null) {
      image = Image.file(
        File(photo.localPath!),
        width: 84,
        height: 84,
        fit: BoxFit.cover,
      );
    } else if (url != null) {
      image = Image.network(
        url,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _photoPlaceholder(photo),
      );
    } else {
      image = _photoPlaceholder(photo);
    }

    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _saving ? null : () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// Stand-in for a photo we only have the key of.
  Widget _photoPlaceholder(_SpecPhoto photo) {
    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(6),
      color: AppColors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_outlined, size: 18,
              color: AppColors.textMuted),
          const SizedBox(height: 6),
          CustomText(
            photo.fileName,
            fontSize: 9,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final enabled = !_saving && _hasChangesToSave;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: enabled ? _save : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.3),
          disabledForegroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : CustomText(
                TKeys.msSaveMeasurements.tr,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
      ),
    );
  }
}
