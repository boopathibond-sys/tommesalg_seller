import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/measurement_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/widgets/custom_text.dart';
import '../../core/widgets/image_source_picker.dart';
import '../../models/measurement.dart';
import '../../core/localization/translation_keys.dart';
import 'package:tommesalg_seller_app/core/utils/app_snackbar.dart';

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
    this.onProductImages,
  });

  final String productId;

  /// Placement this product sits in, when opened from a SKU.
  final String? placementId;

  /// SKU code, shown in the section's subtitle when known.
  final String? skuCode;

  /// Called with the bundle's `product.images` each time it loads, so the
  /// host quick view can feed its image slider.
  final ValueChanged<List<String>>? onProductImages;

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

  /// The photo card is read-only until its pencil is tapped; editing shows
  /// the add tile, remove buttons and Cancel / Save.
  bool _editingPhotos = false;

  /// [_photos] as they were when editing began, restored by Cancel.
  List<_SpecPhoto> _photosBeforeEdit = const [];

  /// Bumped on every [_load]; a response whose token is no longer current
  /// belongs to an older request (or an older product) and is dropped.
  int _loadToken = 0;

  /// Per-photo retry count, folded into the thumb's key so a tap on a failed
  /// thumb builds a fresh [Image.network] instead of reusing the error.
  final Map<String, int> _photoAttempts = <String, int>{};

  /// Ceiling on attached photos, and the API's own file rules.
  static const int _maxPhotos = 5;

  /// Adding measurement types (the dropdown + Add) is switched off for now;
  /// rows already saved still show and can be edited or removed.
  static const bool _typePickerEnabled = false;
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

  /// Type chosen in the picker. Falls back to the first available type, so a
  /// default is always pre-selected and one tap on Add is enough.
  MeasurementType? _pickedType;

  MeasurementType? get _selectedType {
    final available = _available;
    if (available.isEmpty) return null;
    final picked = _pickedType;
    if (picked != null && available.any((t) => t.key == picked.key)) {
      return available.firstWhere((t) => t.key == picked.key);
    }
    return available.first;
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
  void didUpdateWidget(covariant MeasurementGoalsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same State handed a different product — reload rather than keep
    // showing the previous product's values and photos.
    if (oldWidget.productId != widget.productId ||
        oldWidget.placementId != widget.placementId) {
      _pickedType = null;
      _photoAttempts.clear();
      _load();
    }
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

  /// Reads the bundle and rebuilds the form. With [keepPhotos] only the
  /// measurements are refreshed — used right after a save, when the bundle
  /// may not reflect the photo set just written yet.
  Future<void> _load({bool keepPhotos = false}) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    // One quiet retry — a single dropped request otherwise leaves the
    // section on its error state with no photos.
    var bundle = await MeasurementService.instance.fetchBundle(
      productId: widget.productId,
    );
    if (bundle == null && mounted && token == _loadToken) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted || token != _loadToken) return;
      bundle = await MeasurementService.instance.fetchBundle(
        productId: widget.productId,
      );
    }

    if (!mounted || token != _loadToken) return;

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
      _applyMeasurements(bundle!.measurements);
      if (!keepPhotos) _applyPhotos(bundle.sizeSpecImages);
      _loading = false;
    });
    widget.onProductImages?.call(bundle.productImages);
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
      // Next default is whatever is first among the remaining types.
      _pickedType = null;
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

    final room = _maxPhotos - _photos.length;
    // Camera opens the in-app pro camera (lenses, flash, exposure, focus
    // lock, zoom, timer …); gallery re-encodes HEIC to JPEG.
    final picked = await ImageSourcePicker.pick(context, maxImages: room);
    if (picked.isEmpty || !mounted) return;

    setState(() => _uploadingPhotos = true);

    // Compress first so the 5 MB check applies to what is actually sent.
    final queue = <String>[];
    var rejectedType = 0;
    var rejectedSize = 0;

    for (final file in picked) {
      if (queue.length >= room) break;
      if (!_isAllowedPhoto(file)) {
        rejectedType += 1;
        continue;
      }
      final path = await ImageCompressor.compress(file.path);
      if (await File(path).length() > _maxPhotoBytes) {
        rejectedSize += 1;
        continue;
      }
      queue.add(path);
    }

    if (!mounted) return;
    if (rejectedType > 0) {
      _snack(TKeys.unsupportedFile.tr, TKeys.msOnlyImageTypes.tr, ok: false);
    }
    if (rejectedSize > 0) {
      _snack(TKeys.msTooLarge.tr, TKeys.msMaxFiveMb.tr, ok: false);
    }
    if (queue.isEmpty) {
      setState(() => _uploadingPhotos = false);
      return;
    }

    for (final path in queue) {
      final result = await MeasurementService.instance.uploadSizeSpecImage(
        productId: widget.productId,
        filePath: path,
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
            localPath: path,
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

  /// Drops a thumb locally. There is no remove endpoint — Save sends the
  /// remaining keys, and the server keeps exactly those.
  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  void _startEditingPhotos() {
    setState(() {
      _photosBeforeEdit = List.of(_photos);
      _editingPhotos = true;
    });
  }

  /// Drops this session's photo changes. Photos already uploaded stay in S3
  /// unattached — the API has no delete, and nothing references them.
  void _cancelEditingPhotos() {
    setState(() {
      _photos
        ..clear()
        ..addAll(_photosBeforeEdit);
      _editingPhotos = false;
    });
  }

  void _snack(String title, String message, {required bool ok}) {
    AppSnackbar.show(
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

    // Measurements are optional — a row left blank is skipped rather than
    // blocking the save, so photos can be saved without any values. A saved
    // row the seller cleared is deleted.
    final inputs = <MeasurementInput>[];
    final clearedIds = <String>{};
    for (final row in _rows) {
      final raw = row.controller.text.trim().replaceAll(',', '.');
      if (raw.isEmpty) {
        final id = row.measurementId;
        if (id != null) clearedIds.add(id);
        continue;
      }
      final value = double.tryParse(raw);
      if (value == null || value <= 0) {
        _snack(TKeys.errorTitle.tr,
            TKeys.msEnterValidCm.trParams({'field': row.type.label}),
            ok: false);
        return;
      }
      inputs.add(MeasurementInput(fieldKey: row.type.key, valueCm: value));
    }

    setState(() => _saving = true);

    for (final id in {..._removedIds, ...clearedIds}) {
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
        _editingPhotos = false;
      });
      return;
    }
    setState(() {
      _saving = false;
      _editingPhotos = false;
    });
    await _load(keepPhotos: true);
  }

  // ---------- Presentation ----------

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _loadError == null;
    // Two cards: the measurement values, then the size / spec photos. One
    // Save below covers both.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCard(
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
              // Saved values stay editable; while the photo card is being
              // edited its own Save covers them too.
              if ((_rows.isNotEmpty || _removedIds.isNotEmpty) &&
                  !_editingPhotos) ...[
                const SizedBox(height: 12),
                _buildSaveButton(TKeys.msSaveMeasurements.tr),
              ],
            ],
          ],
        ),
        if (ready) ...[
          const SizedBox(height: 12),
          _buildCard(children: [_buildPhotosBlock()]),
        ],
      ],
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
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
          if (_typePickerEnabled) ...[
            const SizedBox(height: 3),
            CustomText(
              TKeys.msPickTargetType.tr,
              fontSize: 11.5,
              textAlign: TextAlign.center,
              color: AppColors.textMuted,
            ),
          ],
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
          color:
              enabled ? AppColors.vipps.withOpacity(0.1) : AppColors.inputFill,
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

  /// Target-type dropdown with a default type pre-selected (the first one not
  /// yet on the form), plus an Add button that puts it on the form. Types
  /// already added drop out of the list.
  Widget _buildTypePicker() {
    final available = _available;
    final selected = _selectedType;
    final enabled = _typePickerEnabled && selected != null && !_saving;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.grey),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MeasurementType>(
                value: selected,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color:
                      enabled ? AppColors.textSecondary : AppColors.textMuted,
                ),
                hint: _pickerLabel(
                  icon: Icons.add_rounded,
                  text: TKeys.msSelectTargetType.tr,
                  muted: false,
                ),
                // A disabled dropdown always shows this, so while saving keep
                // the selected type on screen.
                disabledHint: selected == null
                    ? _pickerLabel(
                        icon: Icons.check_rounded,
                        text: TKeys.msAllTargetTypes.tr,
                        muted: true,
                      )
                    : CustomText(
                        selected.label,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
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
                    ? (type) => setState(() => _pickedType = type)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: enabled ? () => _addRow(selected) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandNavy,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.3),
              disabledForegroundColor: AppColors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: CustomText(
              TKeys.addAction.tr,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
        ),
      ],
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

  /// Size / spec photo card. Read-only by default — the photos on the product
  /// (or an empty note) and a pencil; editing adds the Add tile, remove
  /// buttons and Cancel / Save.
  Widget _buildPhotosBlock() {
    final atLimit = _photos.length >= _maxPhotos;
    final editing = _editingPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 17, color: AppColors.brandNavy),
            const SizedBox(width: 7),
            CustomText(
              TKeys.msMeasurementPhotos.tr,
              fontSize: 14.5,
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
            if (!editing)
              IconButton(
                onPressed: _saving ? null : _startEditingPhotos,
                tooltip: TKeys.edit.tr,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.brandNavy),
              ),
          ],
        ),
        const SizedBox(height: 4),
        CustomText(
          TKeys.msPhotoHint.tr,
          fontSize: 12,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 10),
        if (!editing && _photos.isEmpty)
          CustomText(
            TKeys.msNoPhotos.tr,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          )
        else
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + (editing ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == _photos.length) {
                  return _buildAddPhotoTile(atLimit);
                }
                return _buildPhotoThumb(index, removable: editing);
              },
            ),
          ),
        if (editing) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _saving || _uploadingPhotos
                        ? null
                        : _cancelEditingPhotos,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: CustomText(
                      TKeys.cancelAction.tr,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildSaveButton(TKeys.save.tr)),
            ],
          ),
        ],
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
                    atLimit ? Icons.check_rounded : Icons.add_a_photo_outlined,
                    size: 20,
                    color: enabled ? AppColors.brandNavy : AppColors.textMuted,
                  ),
                  const SizedBox(height: 6),
                  CustomText(
                    atLimit ? TKeys.msLimit.tr : TKeys.msAddPhoto.tr,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color:
                        enabled ? AppColors.textSecondary : AppColors.textMuted,
                  ),
                ],
              ),
      ),
    );
  }

  /// One thumb — the local file while the seller is still on this dialog, the
  /// signed URL once it comes back from the server, and a named placeholder
  /// when all we hold is an S3 key.
  Widget _buildPhotoThumb(int index, {required bool removable}) {
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
        cacheWidth: (84 * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => _photoPlaceholder(photo),
      );
    } else if (url != null) {
      final attempt = _photoAttempts[photo.key] ?? 0;
      final cacheSize = (84 * MediaQuery.devicePixelRatioOf(context)).round();
      image = Image.network(
        url,
        key: ValueKey('${photo.key}#$attempt'),
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        // Decode at thumb size — full-resolution phone photos made the strip
        // slow to appear and heavy on memory.
        cacheWidth: cacheSize,
        gaplessPlayback: true,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _photoLoading(),
        errorBuilder: (_, __, ___) => GestureDetector(
          onTap: () => setState(
            () => _photoAttempts[photo.key] = attempt + 1,
          ),
          child: _photoPlaceholder(photo, retry: true),
        ),
      );
    } else {
      image = _photoPlaceholder(photo);
    }

    return Stack(
      key: ValueKey(photo.key),
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: image),
        if (removable)
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

  /// Shown while a thumb's URL is still downloading.
  Widget _photoLoading() {
    return Container(
      width: 84,
      height: 84,
      color: AppColors.white,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  /// Stand-in for a photo we only have the key of, or whose URL failed to
  /// load ([retry] adds a tap-to-retry hint).
  Widget _photoPlaceholder(_SpecPhoto photo, {bool retry = false}) {
    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(6),
      color: AppColors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(retry ? Icons.refresh_rounded : Icons.image_outlined,
              size: 18, color: AppColors.textMuted),
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

  Widget _buildSaveButton(String label) {
    final enabled = !_saving && !_uploadingPhotos && _hasChangesToSave;
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
                label,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
      ),
    );
  }
}
