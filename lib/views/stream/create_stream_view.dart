import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../controllers/stream_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../core/widgets/image_pick_crop.dart';
import '../../models/stream_model.dart';
import '../../core/localization/translation_keys.dart';

/// Full-page form to create — or edit — a stream. Mirrors the seller web
/// "New stream" screen: title, note, 9:16 thumbnail, sizes, and a
/// start-now / schedule toggle.
///
/// The note field is the API's `description` — only the label the seller
/// reads changed, so nothing about the request body moved.
///
/// Pass [stream] to open in edit mode: the form prefills from that stream
/// (topped up by `GET /api/v1/seller/streams/:id` for fields the list payload
/// omits) and the submit bar becomes "Update stream", sending the same body to
/// `PATCH /api/v1/seller/streams/:id` instead of `POST /api/v1/seller/streams`.
class CreateStreamView extends StatefulWidget {
  const CreateStreamView({super.key, this.stream});

  /// Non-null → edit mode.
  final StreamModel? stream;

  @override
  State<CreateStreamView> createState() => _CreateStreamViewState();
}

class _CreateStreamViewState extends State<CreateStreamView> {
  final StreamListController _ctrl = getOrPut(() => StreamListController());

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool get _isEdit => widget.stream != null;

  /// Sizes the stream can be tagged with, in the order the chips show them.
  /// Same vocabulary the buyer app filters by, so a stream tagged here is
  /// reachable there.
  // Getter, not a stored field: `.tr` must re-resolve when the seller
  // switches language, and a field initialiser only ever runs once.
  static List<_SizeOption> get _sizes => [
    const _SizeOption('S', 'S'),
    const _SizeOption('M', 'M'),
    const _SizeOption('L', 'L'),
    const _SizeOption('XL', 'XL'),
    const _SizeOption('XXL', 'XXL'),
    const _SizeOption('XXXL', 'XXXL'),
    const _SizeOption('OS', 'OS'),
    _SizeOption('others', TKeys.csOthers.tr),
  ];

  /// Selected sizes held as [_SizeOption.wire] values — what `sizes` carries.
  final Set<String> _selectedSizes = {};
  bool _goLiveNow = false;
  DateTime? _scheduledStartTime;
  int _durationMinutes = 120;

  // Thumbnail state — local preview path + the uploaded S3 key.
  String? _thumbnailLocalPath;
  String? _thumbnailS3Key;

  /// Edit mode only: the thumbnail already on the stream. Shown as the preview
  /// until the seller picks a new image, and never sent back to the API (it's a
  /// display URL, not the S3 key the API expects).
  String? _existingThumbnailUrl;

  bool _submitting = false;

  /// Edit mode only: the detail GET that tops up sizes / duration is in flight.
  bool _loadingDetails = false;

  /// Last failure to show inline above the submit button — the API's own
  /// message when it sends one (e.g. "Stream details can only be edited while
  /// the stream is scheduled."), otherwise a local validation message. A
  /// snackbar alone is too easy to miss on a long form.
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final s = widget.stream;
    if (s == null) return;
    _applyStream(s);
    _hydrateFromServer(s.id);
  }

  /// Prefills every field the form owns from [s]. Called with the stream handed
  /// in by the list, then again with the fuller record from the detail GET.
  void _applyStream(StreamModel s) {
    _titleCtrl.text = s.title;
    _descCtrl.text = s.description ?? '';
    _existingThumbnailUrl = s.thumbnailUrl;
    if (s.sizes.isNotEmpty) {
      _selectedSizes
        ..clear()
        ..addAll(s.sizes.map(_wireFor).whereType<String>());
    }
    if (s.streamDurationMinutes != null) {
      _durationMinutes = s.streamDurationMinutes!;
    }
    _scheduledStartTime = s.scheduledStartTime;
    // A stream with no scheduled time is (or was) an immediate broadcast.
    _goLiveNow = s.scheduledStartTime == null;
  }

  /// The list payload can omit `sizes` / `streamDurationMinutes`, so edit mode
  /// re-reads the stream and re-applies. Failure is silent — the fields already
  /// prefilled from the list stay as they are.
  Future<void> _hydrateFromServer(String streamId) async {
    setState(() => _loadingDetails = true);
    final fresh = await _ctrl.fetchStreamDetails(streamId);
    if (!mounted) return;
    setState(() {
      _loadingDetails = false;
      if (fresh != null) _applyStream(fresh);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _pickThumbnail() async {
    if (_ctrl.isUploadingThumbnail) return;
    // Asks camera vs gallery first, then frames the shot to the 9:16 box the
    // thumbnail is displayed in.
    final path = await pickAndCropImage(
      context,
      title: TKeys.csStreamThumbnail.tr,
      aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
      maxWidth: 1440,
    );
    if (path == null || !mounted) return;

    setState(() => _thumbnailLocalPath = path);
    final key = await _ctrl.uploadStreamThumbnail(path);
    if (!mounted) return;
    if (key != null) {
      setState(() => _thumbnailS3Key = key);
    } else {
      setState(() {
        _thumbnailLocalPath = null;
        _thumbnailS3Key = null;
      });
      Get.snackbar(TKeys.csUploadFailed.tr, _ctrl.createError ?? TKeys.csThumbUploadFailed.tr);
    }
  }

  Future<void> _pickScheduledTime() async {
    final now = DateTime.now();
    final base = _scheduledStartTime ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandNavy,
            onPrimary: AppColors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandNavy,
            onPrimary: AppColors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledStartTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) return TKeys.csEnterTitle.tr;
    // Only create requires a thumbnail. In edit mode it's optional — leaving it
    // untouched keeps whatever the stream already has, and nothing is sent.
    if (!_isEdit && _thumbnailS3Key == null) {
      return TKeys.csUploadThumb.tr;
    }
    if (_selectedSizes.isEmpty) return TKeys.csSelectSize.tr;
    if (!_goLiveNow) {
      if (_scheduledStartTime == null) return TKeys.csChooseStartTime.tr;
      // An existing schedule that has already passed isn't the seller's doing —
      // only block a *newly* picked past time.
      final unchanged = _isEdit &&
          widget.stream!.scheduledStartTime == _scheduledStartTime;
      if (!unchanged && _scheduledStartTime!.isBefore(DateTime.now())) {
        return TKeys.csTimeMustBeFuture.tr;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      Get.snackbar(TKeys.csMissingInformation.tr, error);
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    // Keep the canonical S → Others order rather than tap order.
    final sizes = _sizes
        .map((o) => o.wire)
        .where(_selectedSizes.contains)
        .toList();
    final ok = _isEdit
        ? await _ctrl.updateStream(
            streamId: widget.stream!.id,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text,
            sizes: sizes,
            goLiveNow: _goLiveNow,
            scheduledStartTime: _goLiveNow ? null : _scheduledStartTime,
            // Only a freshly uploaded key goes out; an untouched thumbnail is
            // left alone server-side.
            thumbnailUrl: _thumbnailS3Key,
            streamDurationMinutes: _durationMinutes,
          )
        : await _ctrl.createStream(
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text,
            sizes: sizes,
            goLiveNow: _goLiveNow,
            scheduledStartTime: _goLiveNow ? null : _scheduledStartTime,
            thumbnailUrl: _thumbnailS3Key,
            streamDurationMinutes: _durationMinutes,
          );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop(true);
      Get.snackbar(
        _isEdit ? TKeys.csStreamUpdated.tr : TKeys.csStreamCreated.tr,
        _isEdit
            ? TKeys.csChangesSaved.tr
            : TKeys.csStreamCreatedBody.tr,
      );
    } else {
      // The API's message (e.g. "Stream details can only be edited while the
      // stream is scheduled.") is what the seller needs to read — keep it on
      // screen, not just in a snackbar that fades.
      final message = _ctrl.createError ?? TKeys.pleaseTryAgain.tr;
      setState(() => _errorText = message);
      Get.snackbar(
        _isEdit ? TKeys.csCouldNotUpdate.tr : TKeys.csCouldNotCreate.tr,
        message,
        duration: const Duration(seconds: 5),
      );
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: AppColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brandNavy),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: CustomText(
          _isEdit ? TKeys.csEditStream.tr : TKeys.newStream.tr,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        centerTitle: false,
        bottom: _loadingDetails
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.white,
                  valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
                ),
              )
            : null,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 100),
        children: [
          _infoCard(),
          const SizedBox(height: 16),
          _timeCard(),
        ],
      ),
      bottomSheet: _submitBar(bottom),
    );
  }

  // ── Card 1: Information ────────────────────────────────────────────────────

  Widget _infoCard() {
    return _SectionShell(
      icon: Icons.live_tv_rounded,
      title: TKeys.csShipmentInfo.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(TKeys.csTitle.tr, required: true),
          const SizedBox(height: 8),
          _TextField(
            controller: _titleCtrl,
            hint: TKeys.csTitleHint.tr,
          ),
          const SizedBox(height: 18),
          _FieldLabel(TKeys.csNote.tr),
          const SizedBox(height: 8),
          _TextField(
            controller: _descCtrl,
            hint: TKeys.csDescriptionHint.tr,
            maxLines: 5,
          ),
          const SizedBox(height: 18),
          _FieldLabel(TKeys.csThumbnail.tr, required: !_isEdit),
          const SizedBox(height: 8),
          _thumbnailPicker(),
          if (_isEdit) ...[
            const SizedBox(height: 6),
            CustomText(
              TKeys.csThumbnailHelp.tr,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ],
          const SizedBox(height: 20),
          _FieldLabel(TKeys.csSizes.tr, required: true),
          const SizedBox(height: 10),
          _sizePicker(),
        ],
      ),
    );
  }

  Widget _thumbnailPicker() {
    return Obx(() {
      final uploading = _ctrl.isUploadingThumbnail;
      final hasImage = _thumbnailLocalPath != null || _existingThumbnailUrl != null;
      return GestureDetector(
        onTap: _pickThumbnail,
        child: SizedBox(
          width: 140,
          child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasImage
                    ? AppColors.inputBorder
                    : AppColors.grey.withOpacity(0.4),
                width: 1.4,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_thumbnailLocalPath != null)
                  Image.file(File(_thumbnailLocalPath!), fit: BoxFit.cover)
                else if (_existingThumbnailUrl != null)
                  Image.network(
                    _existingThumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _DashedUploadHint(),
                  )
                else
                  _DashedUploadHint(),
                if (uploading)
                  Container(
                    color: Colors.black.withOpacity(0.35),
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(AppColors.white),
                      ),
                    ),
                  ),
                if (hasImage && !uploading)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.autorenew_rounded, size: 13, color: AppColors.white),
                          const SizedBox(width: 4),
                          CustomText(TKeys.csChange.tr, fontSize: 11.5,
                              fontWeight: FontWeight.w700, color: AppColors.white),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        ),
      );
    });
  }

  /// Multi-select size pills — filled navy when picked, outlined otherwise.
  Widget _sizePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _sizes.map(_sizeChip).toList(),
        ),
        const SizedBox(height: 8),
        CustomText(
          _selectedSizes.isEmpty
              ? TKeys.csSelectSize.tr
              : TKeys.selectedCount
                  .trParams({'count': '${_selectedSizes.length}'}),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
      ],
    );
  }

  Widget _sizeChip(_SizeOption size) {
    final selected = _selectedSizes.contains(size.wire);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedSizes.remove(size.wire);
        } else {
          _selectedSizes.add(size.wire);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.brandNavy
                : AppColors.grey.withOpacity(0.35),
            width: 1.2,
          ),
        ),
        // `widthFactor: 1` shrink-wraps to the label — without it the box
        // stretches to the full row width and the chips stack like a column.
        child: Center(
          widthFactor: 1,
          child: CustomText(
            size.label,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  // ── Card 2: Time of sending ────────────────────────────────────────────────

  Widget _timeCard() {
    return _SectionShell(
      icon: Icons.access_time_rounded,
      title: TKeys.csTimeOfSending.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.bolt_rounded,
                  title: TKeys.csStartNow.tr,
                  subtitle: TKeys.csGoLiveRightAway.tr,
                  selected: _goLiveNow,
                  onTap: () => setState(() => _goLiveNow = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeCard(
                  icon: Icons.schedule_rounded,
                  title: TKeys.csPlan.tr,
                  subtitle: TKeys.csChooseLaterTime.tr,
                  selected: !_goLiveNow,
                  onTap: () => setState(() => _goLiveNow = false),
                ),
              ),
            ],
          ),
          if (!_goLiveNow) ...[
            const SizedBox(height: 20),
            _FieldLabel(TKeys.csScheduledStartTime.tr, required: true),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickScheduledTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F7F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.grey.withOpacity(0.35), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CustomText(
                        _scheduledStartTime == null
                            ? TKeys.csSelectDateTime.tr
                            : _formatDateTime(_scheduledStartTime!),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _scheduledStartTime == null
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _FieldLabel(TKeys.csEstimatedDuration.tr),
          const SizedBox(height: 8),
          _durationPicker(),
        ],
      ),
    );
  }

  /// Duration options in minutes, shortest → longest.
  static const List<int> _durationOptions = [
    30, 60, 90, 120, 180, 240, 300, 360, 480, 720,
  ];

  static String _durationLabel(int m) =>
      m < 60
          ? '$m ${TKeys.csMinUnit.tr}'
          : '${(m / 60).toStringAsFixed(m % 60 == 0 ? 0 : 1)} ${TKeys.csHourUnit.tr}';

  Widget _durationPicker() {
    // A stream saved with a duration outside the list (older record, web app)
    // still has to render — DropdownButton asserts if its value has no item.
    final options = _durationOptions.contains(_durationMinutes)
        ? _durationOptions
        : ([..._durationOptions, _durationMinutes]..sort());

    // Shrink-wrapped pill instead of a full-width field — the longest label is
    // "12 h", so a stretched box was mostly empty space.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey.withOpacity(0.35), width: 1),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _durationMinutes,
            // Drops the 48px interactive floor so the pill hugs its content.
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            dropdownColor: AppColors.white,
            menuMaxHeight: 300,
            icon: const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: AppColors.textMuted),
            ),
            // Closed state carries the clock icon; the open menu doesn't repeat it.
            selectedItemBuilder: (_) => options
                .map((m) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timelapse_rounded,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        CustomText(
                          _durationLabel(m),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ))
                .toList(),
            items: options
                .map((m) => DropdownMenuItem<int>(
                      value: m,
                      child: CustomText(
                        _durationLabel(m),
                        fontSize: 13.5,
                        fontWeight:
                            m == _durationMinutes ? FontWeight.w800 : FontWeight.w600,
                        color: m == _durationMinutes
                            ? AppColors.brandNavy
                            : AppColors.textPrimary,
                      ),
                    ))
                .toList(),
            onChanged: (m) {
              if (m == null) return;
              setState(() => _durationMinutes = m);
            },
          ),
        ),
      ),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────

  Widget _submitBar(double bottom) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 12),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorText != null) ...[
              _ErrorBanner(
                message: _errorText!,
                onDismiss: () => setState(() => _errorText = null),
              ),
              const SizedBox(height: 10),
            ],
            _submitButton(),
          ],
        ),
      ),
    );
  }

  Widget _submitButton() {
    return GestureDetector(
      onTap: _submitting || _ctrl.isUploadingThumbnail ? null : _submit,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _submitting ? 0.7 : 1,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandNavy,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandNavy.withOpacity(0.2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isEdit
                          ? Icons.save_rounded
                          : (_goLiveNow
                              ? Icons.bolt_rounded
                              : Icons.check_rounded),
                      size: 20,
                      color: AppColors.brandYellow,
                    ),
                    const SizedBox(width: 8),
                    CustomText(
                      _isEdit
                          ? TKeys.csUpdateStream.tr
                          : (_goLiveNow
                              ? TKeys.csCreateAndGoLive.tr
                              : TKeys.csCreateStream.tr),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      '', TKeys.monthJanShort.tr, TKeys.monthFebShort.tr, TKeys.monthMarShort.tr,
      TKeys.monthAprShort.tr, TKeys.monthMayShort.tr, TKeys.monthJunShort.tr,
      TKeys.monthJulShort.tr, TKeys.monthAugShort.tr, TKeys.monthSepShort.tr,
      TKeys.monthOctShort.tr, TKeys.monthNovShort.tr, TKeys.monthDecShort.tr,
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}  •  $h:$m';
  }
}

/// One size chip: [wire] is what the API accepts, [label] what the seller
/// reads. They only differ for `others` — the backend spells that one
/// lowercase and rejects any other casing, while every other size is
/// upper-case.
class _SizeOption {
  const _SizeOption(this.wire, this.label);
  final String wire;
  final String label;
}

/// Maps a size the server sent back onto our wire spelling, case-insensitively
/// so a differently-cased payload still ticks the right chip. `YOU` is the
/// legacy name for `OS` and is carried across. Anything we don't recognise is
/// dropped — it has no chip to render and would only fail validation on save.
String? _wireFor(String raw) {
  final v = raw.trim();
  if (v.toUpperCase() == TKeys.csYou.tr) return 'OS';
  for (final o in _CreateStreamViewState._sizes) {
    if (o.wire.toLowerCase() == v.toLowerCase()) return o.wire;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Small building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.grey.withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.grey.withOpacity(0.12), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brandYellow.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.brandNavy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomText(
                    title,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Persistent inline error above the submit button. Carries the API's own
/// message verbatim so rules like "only scheduled streams can be edited" stay
/// readable after the snackbar is gone.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.vipps.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.vipps.withOpacity(0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.vipps),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CustomText(
              message,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: AppColors.vipps,
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(Icons.close_rounded, size: 16, color: AppColors.vipps),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomText(
          label,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const CustomText('*', fontSize: 15, fontWeight: FontWeight.w700,
              color: AppColors.vipps),
        ],
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      cursorColor: AppColors.brandNavy,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      inputFormatters: maxLines == 1
          ? [LengthLimitingTextInputFormatter(120)]
          : [LengthLimitingTextInputFormatter(600)],
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted.withOpacity(0.9),
        ),
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.grey.withOpacity(0.3), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.grey.withOpacity(0.3), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }
}

class _DashedUploadHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F1F3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.photo_camera_rounded,
                size: 20, color: AppColors.textMuted.withOpacity(0.9)),
          ),
          const SizedBox(height: 10),
          CustomText(
            TKeys.csTapToUpload.tr,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: CustomText(
              TKeys.csPortraitHint.tr,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              height: 1.3,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandYellow.withOpacity(0.18) : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.brandYellow : AppColors.grey.withOpacity(0.3),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? AppColors.brandYellow : const Color(0xFFF0F1F3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20,
                  color: selected ? AppColors.brandNavy : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    title,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  CustomText(
                    subtitle,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle_rounded, size: 20, color: AppColors.brandNavy),
              ),
          ],
        ),
      ),
    );
  }
}
