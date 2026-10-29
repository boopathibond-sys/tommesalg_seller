import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart' show CameraDevice, ImagePicker, ImageSource;

import '../localization/translation_keys.dart';
import '../services/media_permission_service.dart';
import '../theme/app_colors.dart';
import 'confirm_dialog.dart';
import 'custom_text.dart';

/// Full-screen in-app camera with the controls a seller expects from the
/// phone's own Camera app: every physical lens the OS exposes (ultra-wide /
/// wide / tele on iPhone), pinch + preset zoom, flash (off / auto / on /
/// torch), exposure compensation, tap-to-focus/expose, press-and-hold AE/AF
/// lock, rule-of-thirds grid and a 3 s / 10 s self-timer.
///
/// Shoots several photos in one session and returns them all on "Done". The
/// phone's own camera UI stays one tap away ("Phone camera") for anything the
/// plugin can't drive — on Android that is the OEM camera app with its modes.
///
/// Photos come back as 4K JPEGs at quality 90, which keeps them under the
/// 5 MB the upload endpoints accept.
class ProCameraScreen extends StatefulWidget {
  const ProCameraScreen({super.key, required this.maxPhotos});

  /// How many more photos the caller can take; the session ends by itself
  /// once this many are captured.
  final int maxPhotos;

  /// Opens the camera and resolves with the captured photos — empty when the
  /// seller backs out.
  static Future<List<XFile>> capture(
    BuildContext context, {
    required int maxPhotos,
  }) async {
    if (maxPhotos <= 0) return const [];
    final shots = await Navigator.of(context, rootNavigator: true).push<List<XFile>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProCameraScreen(maxPhotos: maxPhotos),
      ),
    );
    return shots ?? const [];
  }

  @override
  State<ProCameraScreen> createState() => _ProCameraScreenState();
}

enum _CamStatus { starting, ready, denied, noCamera, failed }

class _ProCameraScreenState extends State<ProCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const List<FlashMode> _flashCycle = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.always,
    FlashMode.torch,
  ];
  static const List<int> _timerCycle = [0, 3, 10];

  List<CameraDescription> _cameras = const [];
  CameraDescription? _active;
  CameraDescription? _lastBack;
  CameraController? _ctrl;
  _CamStatus _status = _CamStatus.starting;

  /// Bumped on every [_open]; a slower open that lost the race to a newer one
  /// disposes its controller instead of installing it.
  int _openSeq = 0;

  /// True while the native camera UI is up — lifecycle events then belong to
  /// [_openPhoneCamera], not to the pause / resume handling.
  bool _externalCamera = false;

  FlashMode _flash = FlashMode.off;
  bool _grid = false;
  int _timer = 0;
  int? _countdown;
  Timer? _countdownTimer;
  bool _showExposure = false;

  double _minExposure = 0;
  double _maxExposure = 0;
  double _exposure = 0;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _pinchBase = 1;
  bool _aeAfLocked = false;

  /// Where the focus square sits, in preview-box coordinates.
  Offset? _focusMark;
  Timer? _focusMarkTimer;

  String? _hint;
  Timer? _hintTimer;

  bool _capturing = false;
  final List<XFile> _shots = <XFile>[];

  late final AnimationController _shutterFlash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  bool get _isFront => _active?.lensDirection == CameraLensDirection.front;

  /// Back lenses ordered the way the Camera app lays them out.
  List<CameraDescription> get _backLenses {
    final back = _cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();
    back.sort((a, b) => _lensRank(a.lensType).compareTo(_lensRank(b.lensType)));
    return back;
  }

  CameraDescription? get _frontLens => _cameras
      .where((c) => c.lensDirection == CameraLensDirection.front)
      .firstOrNull;

  static int _lensRank(CameraLensType type) => switch (type) {
        CameraLensType.ultraWide => 0,
        CameraLensType.wide => 1,
        CameraLensType.telephoto => 2,
        CameraLensType.unknown => 3,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _focusMarkTimer?.cancel();
    _hintTimer?.cancel();
    _shutterFlash.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_externalCamera) return;
    final ctrl = _ctrl;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Skip while initialising: the iOS permission alert itself makes the
      // app inactive, and tearing down then would kill the pending prompt.
      if (ctrl == null || !ctrl.value.isInitialized) return;
      _cancelCountdown();
      setState(() => _ctrl = null);
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_status == _CamStatus.denied) {
        // The seller may have just switched access on in Settings.
        _boot();
      } else if (ctrl == null && _active != null) {
        _open(_active!);
      }
    }
  }

  // ---------- Camera lifecycle ----------

  Future<void> _boot() async {
    setState(() => _status = _CamStatus.starting);
    try {
      final cams = await availableCameras();
      if (!mounted) return;
      if (cams.isEmpty) {
        setState(() => _status = _CamStatus.noCamera);
        return;
      }
      _cameras = cams;
      final back = _backLenses;
      final start =
          back.where((c) => c.lensType == CameraLensType.wide).firstOrNull ??
              back.firstOrNull ??
              cams.first;
      await _open(start);
    } on CameraException catch (e) {
      if (mounted) _fail(e);
    }
  }

  Future<void> _open(CameraDescription desc) async {
    final seq = ++_openSeq;
    final old = _ctrl;
    setState(() {
      _ctrl = null;
      _active = desc;
      if (desc.lensDirection == CameraLensDirection.back) _lastBack = desc;
      if (_status != _CamStatus.ready) _status = _CamStatus.starting;
      _focusMark = null;
      _aeAfLocked = false;
    });
    await old?.dispose();

    final ctrl = CameraController(
      desc,
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    double minE = 0, maxE = 0, minZ = 1, maxZ = 1;
    try {
      await ctrl.initialize();
      await _quietly(() => ctrl.setJpegImageQuality(90));
      minE = await _readQuietly(ctrl.getMinExposureOffset) ?? 0;
      maxE = await _readQuietly(ctrl.getMaxExposureOffset) ?? 0;
      minZ = await _readQuietly(ctrl.getMinZoomLevel) ?? 1;
      maxZ = await _readQuietly(ctrl.getMaxZoomLevel) ?? 1;
    } on CameraException catch (e) {
      await ctrl.dispose();
      if (mounted && seq == _openSeq) _fail(e);
      return;
    }

    if (!mounted || seq != _openSeq) {
      await ctrl.dispose();
      return;
    }

    // Keep the chosen flash where the lens has one; front cameras usually
    // don't, so fall back to off.
    final flashOk = await _quietly(() => ctrl.setFlashMode(_flash));
    if (!flashOk) _flash = FlashMode.off;

    // Start at 1× like the Camera app, even on Android lenses whose range
    // dips below 1 (the ultra-wide behind a logical camera).
    final zoom = 1.0.clamp(minZ, maxZ).toDouble();
    if (zoom != minZ) await _quietly(() => ctrl.setZoomLevel(zoom));
    if (!mounted || seq != _openSeq) {
      await ctrl.dispose();
      return;
    }

    setState(() {
      _ctrl = ctrl;
      _status = _CamStatus.ready;
      _minExposure = minE;
      _maxExposure = maxE;
      _exposure = 0;
      _minZoom = minZ;
      _maxZoom = maxZ;
      _zoom = zoom;
    });
  }

  void _fail(CameraException e) {
    final code = e.code.toLowerCase();
    final denied = code.contains('denied') ||
        code.contains('restricted') ||
        code.contains('permission');
    setState(() {
      _ctrl = null;
      _status = denied ? _CamStatus.denied : _CamStatus.failed;
    });
  }

  /// Runs a best-effort camera setting; `false` when the lens doesn't
  /// support it.
  Future<bool> _quietly(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads a best-effort camera value; `null` when the lens can't report it.
  Future<double?> _readQuietly(Future<double> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  // ---------- Controls ----------

  Future<void> _cycleFlash() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    var i = _flashCycle.indexOf(_flash);
    for (var tries = 0; tries < _flashCycle.length; tries++) {
      i = (i + 1) % _flashCycle.length;
      final mode = _flashCycle[i];
      if (await _quietly(() => ctrl.setFlashMode(mode))) {
        if (!mounted) return;
        setState(() => _flash = mode);
        _showHint(_flashLabel(mode));
        return;
      }
    }
  }

  void _cycleTimer() {
    final i = (_timerCycle.indexOf(_timer) + 1) % _timerCycle.length;
    setState(() => _timer = _timerCycle[i]);
    _showHint(_timer == 0
        ? TKeys.pcTimerOff.tr
        : TKeys.pcTimerSeconds.trParams({'seconds': '$_timer'}));
  }

  void _toggleGrid() {
    setState(() => _grid = !_grid);
    _showHint(_grid ? TKeys.pcGridOn.tr : TKeys.pcGridOff.tr);
  }

  Future<void> _setExposure(double value) async {
    setState(() => _exposure = value);
    final ctrl = _ctrl;
    if (ctrl == null) return;
    await _quietly(() => ctrl.setExposureOffset(value));
  }

  Future<void> _setZoom(double value) async {
    final z = value.clamp(_minZoom, _maxZoom).toDouble();
    if (z == _zoom) return;
    setState(() => _zoom = z);
    final ctrl = _ctrl;
    if (ctrl == null) return;
    await _quietly(() => ctrl.setZoomLevel(z));
  }

  Future<void> _switchLens(CameraDescription desc) async {
    if (desc == _active || _capturing) return;
    HapticFeedback.selectionClick();
    await _open(desc);
  }

  Future<void> _flip() async {
    if (_capturing) return;
    final target = _isFront
        ? (_lastBack ?? _backLenses.firstOrNull)
        : _frontLens;
    if (target == null) return;
    HapticFeedback.selectionClick();
    await _open(target);
  }

  Offset _normalise(Offset local, Size box) => Offset(
        (local.dx / box.width).clamp(0.0, 1.0),
        (local.dy / box.height).clamp(0.0, 1.0),
      );

  /// Tap: focus + meter on that spot, releasing any AE/AF lock.
  Future<void> _focusAt(Offset local, Size box) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final point = _normalise(local, box);

    if (_aeAfLocked) {
      await _quietly(() => ctrl.setExposureMode(ExposureMode.auto));
      await _quietly(() => ctrl.setFocusMode(FocusMode.auto));
      if (!mounted) return;
      setState(() => _aeAfLocked = false);
    }
    _markFocus(local, sticky: false);
    if (ctrl.value.exposurePointSupported) {
      await _quietly(() => ctrl.setExposurePoint(point));
    }
    if (ctrl.value.focusPointSupported) {
      await _quietly(() => ctrl.setFocusPoint(point));
    }
  }

  /// Press and hold: focus + meter on that spot, then lock both.
  Future<void> _lockAt(Offset local, Size box) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final point = _normalise(local, box);
    HapticFeedback.mediumImpact();
    _markFocus(local, sticky: true);

    if (ctrl.value.exposurePointSupported) {
      await _quietly(() => ctrl.setExposurePoint(point));
    }
    if (ctrl.value.focusPointSupported) {
      await _quietly(() => ctrl.setFocusPoint(point));
    }
    // Give AF/AE a beat to settle on the new point before freezing it.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || _ctrl != ctrl) return;
    await _quietly(() => ctrl.setExposureMode(ExposureMode.locked));
    await _quietly(() => ctrl.setFocusMode(FocusMode.locked));
    if (!mounted) return;
    setState(() => _aeAfLocked = true);
  }

  void _markFocus(Offset local, {required bool sticky}) {
    _focusMarkTimer?.cancel();
    setState(() => _focusMark = local);
    if (!sticky) {
      _focusMarkTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted && !_aeAfLocked) setState(() => _focusMark = null);
      });
    }
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  // ---------- Capture ----------

  void _onShutter() {
    if (_countdown != null) {
      _cancelCountdown();
      return;
    }
    final ctrl = _ctrl;
    if (_capturing || ctrl == null || ctrl.value.isTakingPicture) return;
    if (_shots.length >= widget.maxPhotos) {
      _showHint(TKeys.pcLimitReached.trParams({'count': '${widget.maxPhotos}'}));
      return;
    }
    if (_timer == 0) {
      _shoot();
      return;
    }
    setState(() => _countdown = _timer);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final next = (_countdown ?? 1) - 1;
      if (next <= 0) {
        t.cancel();
        setState(() => _countdown = null);
        _shoot();
      } else {
        HapticFeedback.selectionClick();
        setState(() => _countdown = next);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != null && mounted) setState(() => _countdown = null);
  }

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.lightImpact();
    try {
      final file = await ctrl.takePicture();
      if (!mounted) return;
      _shutterFlash.forward(from: 0);
      setState(() => _shots.add(file));
      if (_shots.length >= widget.maxPhotos) _finish();
    } on CameraException {
      if (mounted) _showHint(TKeys.pcCaptureFailed.tr);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Hands over to the phone's own camera UI for one shot, then comes back.
  Future<void> _openPhoneCamera() async {
    if (_shots.length >= widget.maxPhotos) {
      _showHint(TKeys.pcLimitReached.trParams({'count': '${widget.maxPhotos}'}));
      return;
    }
    _cancelCountdown();
    _externalCamera = true;
    // Release the device so the native camera can claim it.
    final ctrl = _ctrl;
    _openSeq++;
    setState(() => _ctrl = null);
    await ctrl?.dispose();

    XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 4000,
        maxHeight: 4000,
        imageQuality: 90,
        preferredCameraDevice:
            _isFront ? CameraDevice.front : CameraDevice.rear,
      );
    } catch (_) {
      shot = null;
    } finally {
      _externalCamera = false;
    }
    if (!mounted) return;
    if (shot != null) {
      setState(() => _shots.add(shot!));
      if (_shots.length >= widget.maxPhotos) {
        _finish();
        return;
      }
    }
    final active = _active;
    if (active != null) {
      await _open(active);
    } else {
      await _boot();
    }
  }

  void _finish() {
    _cancelCountdown();
    Navigator.of(context).pop(List<XFile>.of(_shots));
  }

  /// Close without adding — asks first when photos would be thrown away.
  Future<void> _close() async {
    if (_shots.isEmpty) {
      Navigator.of(context).pop(const <XFile>[]);
      return;
    }
    final discard = await showConfirmDialog(
      context: context,
      title: TKeys.pcDiscardTitle.tr,
      message: TKeys.pcDiscardBody.trParams({'count': '${_shots.length}'}),
      confirmLabel: TKeys.pcDiscard.tr,
      cancelLabel: TKeys.pcKeepShooting.tr,
      icon: Icons.delete_outline_rounded,
    );
    if (!discard || !mounted) return;
    for (final shot in _shots) {
      File(shot.path).delete().ignore();
    }
    Navigator.of(context).pop(const <XFile>[]);
  }

  Future<void> _review() async {
    if (_shots.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          if (_shots.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(sheetCtx).canPop()) Navigator.of(sheetCtx).pop();
            });
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    TKeys.pcPhotosCount.trParams({'count': '${_shots.length}'}),
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _shots.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_shots[i].path),
                              height: 280,
                              width: 210,
                              fit: BoxFit.cover,
                              cacheWidth: 420,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _RoundIconButton(
                              icon: Icons.delete_outline_rounded,
                              onTap: () {
                                final removed = _shots[i];
                                setState(() => _shots.removeAt(i));
                                setSheet(() {});
                                File(removed.path).delete().ignore();
                              },
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
        },
      ),
    );
  }

  // ---------- Labels ----------

  String _flashLabel(FlashMode mode) => switch (mode) {
        FlashMode.off => TKeys.pcFlashOff.tr,
        FlashMode.auto => TKeys.pcFlashAuto.tr,
        FlashMode.always => TKeys.pcFlashOn.tr,
        FlashMode.torch => TKeys.pcFlashTorch.tr,
      };

  IconData get _flashIcon => switch (_flash) {
        FlashMode.off => Icons.flash_off_rounded,
        FlashMode.auto => Icons.flash_auto_rounded,
        FlashMode.always => Icons.flash_on_rounded,
        FlashMode.torch => Icons.highlight_rounded,
      };

  IconData get _timerIcon => switch (_timer) {
        3 => Icons.timer_3_rounded,
        10 => Icons.timer_10_rounded,
        _ => Icons.timer_off_outlined,
      };

  String _lensLabel(CameraDescription lens, int index) =>
      switch (lens.lensType) {
        CameraLensType.ultraWide => '0.5×',
        CameraLensType.wide => '1×',
        CameraLensType.telephoto => TKeys.pcTele.tr,
        CameraLensType.unknown => '${index + 1}',
      };

  static String _zoomLabel(double z) =>
      z < 1 || z != z.roundToDouble() ? '${z.toStringAsFixed(1)}×' : '${z.round()}×';

  List<double> get _zoomStops {
    final stops = <double>{if (_minZoom < 1) _minZoom};
    for (final z in const [1.0, 2.0, 5.0, 10.0]) {
      if (z >= _minZoom && z <= _maxZoom) stops.add(z);
    }
    return stops.toList()..sort();
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildViewport()),
                if (_status == _CamStatus.ready) ...[
                  const SizedBox(height: 8),
                  _buildLensRow(),
                  const SizedBox(height: 12),
                  _buildBottomBar(),
                  _buildPhoneCameraLink(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final ready = _status == _CamStatus.ready;
    final hasExposure = _maxExposure > _minExposure;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          ),
          if (ready) ...[
            IconButton(
              onPressed: _cycleFlash,
              icon: Icon(_flashIcon,
                  color: _flash == FlashMode.off
                      ? Colors.white
                      : AppColors.brandYellow),
            ),
            IconButton(
              onPressed: _cycleTimer,
              icon: Icon(_timerIcon,
                  color: _timer == 0 ? Colors.white : AppColors.brandYellow),
            ),
            IconButton(
              onPressed: _toggleGrid,
              icon: Icon(_grid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
                  color: _grid ? AppColors.brandYellow : Colors.white),
            ),
            if (hasExposure)
              IconButton(
                onPressed: () => setState(() => _showExposure = !_showExposure),
                icon: Icon(Icons.exposure_rounded,
                    color: _showExposure || _exposure != 0
                        ? AppColors.brandYellow
                        : Colors.white),
              ),
          ],
          const Spacer(),
          if (_shots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _finish,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: CustomText(
                      TKeys.pcDoneCount.trParams({'count': '${_shots.length}'}),
                      color: AppColors.brandNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    switch (_status) {
      case _CamStatus.starting:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandYellow),
        );
      case _CamStatus.denied:
        return _StatusMessage(
          icon: Icons.no_photography_outlined,
          title: TKeys.pcAccessTitle.tr,
          body: TKeys.pcAccessBody.tr,
          actionLabel: TKeys.pcOpenSettings.tr,
          onAction: MediaPermissionService.openSettings,
        );
      case _CamStatus.noCamera:
        return _StatusMessage(
          icon: Icons.no_photography_outlined,
          title: TKeys.pcNoCamera.tr,
        );
      case _CamStatus.failed:
        return _StatusMessage(
          icon: Icons.error_outline_rounded,
          title: TKeys.pcCameraError.tr,
          actionLabel: TKeys.tryAgain.tr,
          onAction: _boot,
        );
      case _CamStatus.ready:
        break;
    }

    final ctrl = _ctrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (ctrl == null || !ctrl.value.isInitialized)
          const Center(
            child: CircularProgressIndicator(color: AppColors.brandYellow),
          )
        else
          Center(child: _buildPreview(ctrl)),
        if (_hint != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _Pill(text: _hint!)),
          )
        else if (_aeAfLocked)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: _Pill(
                text: TKeys.pcAeAfLock.tr,
                background: AppColors.brandYellow,
                foreground: AppColors.brandNavy,
              ),
            ),
          ),
        if (_countdown != null)
          Center(
            child: CustomText(
              '$_countdown',
              color: Colors.white,
              fontSize: 96,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (_showExposure && _maxExposure > _minExposure)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: _buildExposurePanel(),
          ),
      ],
    );
  }

  Widget _buildPreview(CameraController ctrl) {
    return CameraPreview(
      ctrl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _focusAt(d.localPosition, box),
            onLongPressStart: (d) => _lockAt(d.localPosition, box),
            onScaleStart: (_) => _pinchBase = _zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              _setZoom(_pinchBase * d.scale);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_grid) CustomPaint(painter: _GridPainter()),
                if (_focusMark != null)
                  Positioned(
                    left: _focusMark!.dx - 36,
                    top: _focusMark!.dy - 36,
                    child: IgnorePointer(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.brandYellow, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                // White blink on capture, like the Camera app.
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _shutterFlash,
                    builder: (_, __) => _shutterFlash.isAnimating
                        ? ColoredBox(
                            color: Colors.white.withOpacity(
                                0.8 * (1 - _shutterFlash.value)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExposurePanel() {
    final label = _exposure == 0
        ? '0.0'
        : '${_exposure > 0 ? '+' : ''}${_exposure.toStringAsFixed(1)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny_outlined,
              color: AppColors.brandYellow, size: 20),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.brandYellow,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppColors.brandYellow,
                overlayColor: AppColors.brandYellow.withOpacity(0.2),
                trackHeight: 2,
              ),
              child: Slider(
                min: _minExposure,
                max: _maxExposure,
                value: _exposure.clamp(_minExposure, _maxExposure),
                onChanged: _setExposure,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: CustomText(label,
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                textAlign: TextAlign.center),
          ),
          TextButton(
            onPressed: _exposure == 0 ? null : () => _setExposure(0),
            child: CustomText(
              TKeys.pcReset.tr,
              color: _exposure == 0 ? Colors.white38 : AppColors.brandYellow,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Physical lens picker when the OS exposes several back lenses (iPhone),
  /// zoom presets otherwise. A zoom readout sits beside either while zoomed.
  Widget _buildLensRow() {
    final back = _backLenses;
    final distinctBack = back.map((c) => c.lensType).toSet().length > 1 ||
        (back.length > 1 && back.every((c) => c.lensType == CameraLensType.unknown));
    final showLenses = !_isFront && distinctBack;

    final chips = <Widget>[];
    if (showLenses) {
      for (var i = 0; i < back.length; i++) {
        final lens = back[i];
        chips.add(_ZoomChip(
          label: _lensLabel(lens, i),
          selected: lens == _active,
          onTap: () => _switchLens(lens),
        ));
      }
    } else {
      for (final z in _zoomStops) {
        chips.add(_ZoomChip(
          label: _zoomLabel(z),
          selected: (_zoom - z).abs() < 0.05,
          onTap: () => _setZoom(z),
        ));
      }
    }

    final zoomed = (_zoom - 1).abs() >= 0.05;
    final onStop = !showLenses && _zoomStops.any((z) => (_zoom - z).abs() < 0.05);
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...chips,
          if (zoomed && !onStop)
            _ZoomChip(
              label: _zoomLabel(double.parse(_zoom.toStringAsFixed(1))),
              selected: true,
              onTap: () => _setZoom(1.0.clamp(_minZoom, _maxZoom).toDouble()),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canFlip = _frontLens != null && _backLenses.isNotEmpty;
    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Thumbnail(
            shot: _shots.lastOrNull,
            count: _shots.length,
            onTap: _review,
          ),
          _ShutterButton(
            busy: _capturing,
            counting: _countdown != null,
            onTap: _onShutter,
          ),
          SizedBox(
            width: 56,
            height: 56,
            child: canFlip
                ? _RoundIconButton(
                    icon: Icons.flip_camera_ios_rounded,
                    size: 56,
                    onTap: _flip,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneCameraLink() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        children: [
          TextButton.icon(
            onPressed: _openPhoneCamera,
            icon: const Icon(Icons.photo_camera_outlined,
                color: Colors.white70, size: 18),
            label: CustomText(TKeys.pcPhoneCamera.tr,
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          CustomText(TKeys.pcTapToFocusHint.tr,
              color: Colors.white38, fontSize: 11),
        ],
      ),
    );
  }
}

// ---------- Pieces ----------

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    this.background = const Color(0x99000000),
    this.foreground = Colors.white,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomText(text,
          color: foreground, fontSize: 12.5, fontWeight: FontWeight.w700),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
          ),
          child: CustomText(
            label,
            color: selected ? AppColors.brandYellow : Colors.white,
            fontSize: selected ? 13.5 : 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.busy,
    required this.counting,
    required this.onTap,
  });

  final bool busy;
  final bool counting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.all(busy ? 6 : 0),
          decoration: BoxDecoration(
            shape: counting ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: counting ? BorderRadius.circular(8) : null,
            color: counting ? Colors.red : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.shot,
    required this.count,
    required this.onTap,
  });

  final XFile? shot;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        height: 56,
        child: shot == null
            ? const SizedBox.shrink()
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(shot!.path),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      cacheWidth: 168,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandYellow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CustomText('$count',
                          color: AppColors.brandNavy,
                          fontSize: 11,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 34,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.52),
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            CustomText(title,
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              CustomText(body,
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.4,
                  textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandYellow,
                  foregroundColor: AppColors.brandNavy,
                ),
                onPressed: onAction,
                child: CustomText(actionLabel,
                    color: AppColors.brandNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
