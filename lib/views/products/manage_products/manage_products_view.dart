import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../controllers/products_nav_controller.dart';
import '../../../controllers/stream_controller.dart';
import '../../../core/config/get_or_put.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auto_quick_view_toggle.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/product_request_model.dart';
import '../../../models/stream_model.dart';
import '../../measurements/measurement_goals_section.dart';
import '../../scanner/barcode_scanner_view.dart';
import '../../stream/create_stream_view.dart';
import 'my_products_tab.dart';
import '../../../core/localization/translation_keys.dart';

class ManageProductView extends StatefulWidget {
  const ManageProductView({super.key});

  @override
  State<ManageProductView> createState() => _ManageProductViewState();
}

class _ManageProductViewState extends State<ManageProductView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();

  /// Inline "enter UPC" field shown under the scan card.
  final TextEditingController _upcFieldCtrl = TextEditingController();

  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _addingUnknown = false;

  /// True while a typed UPC is being run through the scan endpoint.
  bool _throwing = false;

  /// Drives both the segmented tab pills and the swipeable [TabBarView].
  late final TabController _tabController;

  /// Cross-tab requests (e.g. the Home "See products" quick action) asking us
  /// to open a specific segment.
  final _nav = getOrPut(() => ProductsNavController());
  Worker? _navWorker;

  @override
  void initState() {
    super.initState();
    // No listener needed — the pill strip repaints off the controller's
    // animation, so the page itself doesn't rebuild on every tab change.
    _tabController = TabController(length: 2, vsync: this);

    // Load the streams this tab needs ourselves instead of relying on the home
    // bottom bar having called it. A one-shot fetch: it no-ops once the list is
    // already there, so switching tabs doesn't re-request.
    ctrl.fetchStreamsByStatus(status: 'SCHEDULED');

    _navWorker = ever<int?>(_nav.requestedTab, _handleNavRequest);
    // Handle a request that may have been queued before this worker attached.
    if (_nav.requestedTab.value != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleNavRequest(_nav.requestedTab.value),
      );
    }
  }

  /// Moves to the requested segment and marks the request handled.
  void _handleNavRequest(int? index) {
    if (index == null || !mounted) return;
    _nav.consume();
    if (index < 0 || index >= _tabController.length) return;
    _tabController.animateTo(index);
  }

  @override
  void dispose() {
    _navWorker?.dispose();
    _tabController.dispose();
    _nameController.dispose();
    _upcFieldCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImageAt(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  String formatDate(DateTime? date) {
    if (date == null) return TKeys.noSchedule.tr;

    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} • "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  final ctrl = getOrPut(() => StreamListController());

  /// Pull-to-refresh: force-reloads the scheduled streams, then (if a stream is
  /// still selected) its product requests / pending products.
  Future<void> _onRefresh() async {
    await ctrl.fetchStreamsByStatus(status: 'SCHEDULED', refresh: true);
    final stream = ctrl.selectedStream.value;
    if (stream != null) {
      await ctrl.fetchProductRequests(stream.id);
    }
  }

  /// Opens the same create-stream form the Streams tab uses, so a seller with
  /// nothing to assign to can make a stream without leaving this tab. On the
  /// way back the scheduled list is force-reloaded — a stream planned for later
  /// lands in the dropdown right away.
  Future<void> _openCreateStream() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStreamView()),
    );
    if (!mounted || created != true) return;
    await ctrl.fetchStreamsByStatus(status: 'SCHEDULED', refresh: true);
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (!mounted || result == null) return;
    final upc = result.rawValue;
    if (upc == null || upc.isEmpty) return;

    final added = await ctrl.addScannedProductByStream(upc: upc);
    if (!mounted || !added) return;

    // Known product → open its quick view (product info + the report-a-
    // discrepancy functions) now that the request item exists, but only if the
    // seller left the auto quick-view toggle on.
    if (AutoQuickViewPref.enabled) _openQuickViewForUpc(upc);
  }

  /// Finds the request item the scan just created and opens its quick view.
  /// `addScannedProductByStream` re-fetches the list before returning, so the
  /// row is already there. Leading zeros are ignored when matching, since the
  /// scanner and the backend can disagree on them (e.g. 05673080 / 5673080).
  void _openQuickViewForUpc(String upc) {
    String normalize(String value) {
      final stripped = value.trim().replaceFirst(RegExp(r'^0+'), '');
      return stripped.isEmpty ? value.trim() : stripped;
    }

    final target = normalize(upc);
    for (final item in ctrl.productRequestItems) {
      final requested = item.requestedUpc;
      if (requested != null && normalize(requested) == target) {
        _openQuickView(item);
        return;
      }
    }
  }

  Future<void> _openManualUpcSheet({String? initialUpc}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualUpcSheet(ctrl: ctrl, initialUpc: initialUpc),
    );
  }

  /// Runs a typed UPC through the same scan endpoint the camera uses. A known
  /// UPC is added to the stream (and its quick view opens, if the toggle is on);
  /// an unknown one falls through to the manual sheet with the UPC pre-filled,
  /// mirroring the Assign-to-SKU flow.
  Future<void> _processUpc(String upc) async {
    if (_throwing) return;
    final trimmed = upc.trim();
    if (trimmed.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _throwing = true);

    final added = await ctrl.addScannedProductByStream(upc: trimmed);
    if (!mounted) return;
    setState(() => _throwing = false);

    if (added) {
      _upcFieldCtrl.clear();
      if (AutoQuickViewPref.enabled) _openQuickViewForUpc(trimmed);
      return;
    }

    // Not in the catalog → collect name + images in the manual sheet instead of
    // the inline form, so the typed UPC carries straight through. Clearing the
    // controller flag keeps the inline form from also appearing behind it.
    if (ctrl.isProductNotFoundByScan) {
      ctrl.clearProductNotFound();
      _upcFieldCtrl.clear();
      await _openManualUpcSheet(initialUpc: trimmed);
      return;
    }

    Get.snackbar(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr);
  }


  Future<void> _addUnknownProduct() async {
    if (_addingUnknown) return;

    if (_nameController.text.trim().isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterProductName.tr);
      return;
    }

    setState(() => _addingUnknown = true);

    final ok = await ctrl.addUnknownProduct(
      name: _nameController.text.trim(),
      imagePaths: _selectedImages.map((e) => e.path).toList(),
    );

    if (!mounted) return;
    setState(() => _addingUnknown = false);

    if (ok) {
      _nameController.clear();
      setState(() => _selectedImages.clear());
      Get.snackbar(TKeys.successTitle.tr, TKeys.productAdded.tr);
    } else {
      Get.snackbar(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr);
    }
  }

  void _dismissUnknownForm() {
    _nameController.clear();
    setState(() => _selectedImages.clear());
    ctrl.clearProductNotFound();
  }

  /// Pushes every queueable assigned product into the selected stream's auction
  /// queue (`POST …/auction-room/queue`, batch). Confirms first — the queue is
  /// what the seller auctions off live, so this shouldn't fire on a stray tap.
  Future<void> _sendToAuctionQueue() async {
    final stream = ctrl.selectedStream.value;
    if (stream == null) return;

    final count = ctrl.queueableProductIds.length;
    final skipped = ctrl.unqueueableCount;
    if (count == 0) {
      Get.snackbar(
        TKeys.nothingToSend.tr,
        skipped > 0
            ? TKeys.awaitingApproval.tr
            : TKeys.addProductFirst.tr,
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.sendToQueueTitle.tr,
      message: skipped > 0
          ? TKeys.sendToQueueBodySkipped.trParams({
              'count': '$count',
              'products': count == 1
                  ? TKeys.productUnitSingular.tr
                  : TKeys.productUnitPlural.tr,
              'stream': stream.title,
              'skipped': '$skipped',
              'skippedProducts':
                  skipped == 1 ? TKeys.productIs.tr : TKeys.productsAre.tr,
            })
          : TKeys.sendToQueueBody.trParams({
              'count': '$count',
              'products': count == 1
                  ? TKeys.productUnitSingular.tr
                  : TKeys.productUnitPlural.tr,
              'stream': stream.title,
            }),
      confirmLabel: TKeys.sendAction.tr,
      cancelLabel: TKeys.cancelAction.tr,
      icon: Icons.playlist_add_rounded,
      // Queuing products is what the seller came here to do, so Cancel is the
      // quiet option and Send is the CTA.
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    final result = await ctrl.sendProductsToAuctionQueue();
    if (!mounted) return;

    if (!result.ok) {
      Get.snackbar(
        TKeys.couldNotSendProducts.tr,
        result.error ?? TKeys.pleaseTryAgain.tr,
      );
      return;
    }

    Get.snackbar(
      TKeys.sentToQueue.tr,
      result.skipped > 0
          ? TKeys.queuedForSkipped.trParams({
              'sent': '${result.sent}',
              'products': result.sent == 1
                  ? TKeys.productUnitSingular.tr
                  : TKeys.productUnitPlural.tr,
              'stream': stream.title,
              'skipped': '${result.skipped}',
            })
          : TKeys.queuedFor.trParams({
              'sent': '${result.sent}',
              'products': result.sent == 1
                  ? TKeys.productUnitSingular.tr
                  : TKeys.productUnitPlural.tr,
              'stream': stream.title,
            }),
    );
  }

  /// Removes one assigned product from the selected stream. Confirms first —
  /// the seller may have scanned it minutes ago and there's no undo.
  Future<void> _deleteProductRequestItem(ProductRequestItem item) async {
    if (ctrl.isDeletingItem(item.id)) return;

    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.removeProductTitle.tr,
      message: TKeys.removeProductBody.trParams({'name': item.displayName}),
      confirmLabel: TKeys.removeAction.tr,
      cancelLabel: TKeys.cancelAction.tr,
      icon: Icons.delete_outline_rounded,
      // Removing a scanned product is routine and easily redone, so this uses
      // the CTA layout — Cancel quiet on the left, Remove as the blue button on
      // the right — rather than the safety-first one meant for real data loss.
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    final ok = await ctrl.deleteProductRequestItem(item.id);
    if (!mounted) return;

    if (ok) {
      Get.snackbar(TKeys.removedTitle.tr,
          TKeys.removedFromStream.trParams({'name': item.displayName}));
    } else {
      Get.snackbar(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotDeleteProduct.tr);
    }
  }

  void _openQuickView(ProductRequestItem item) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => _ProductDiscrepancyDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text("Manage Products"),
      //   elevation: 0,
      // ),
      body: Column(
        children: [
          _SegmentedTabs(
            controller: _tabController,
            tabs: [
              _SegmentSpec(
                icon: Icons.live_tv_rounded,
                label: TKeys.assignToLive.tr,
              ),
              _SegmentSpec(
                icon: Icons.grid_view_rounded,
                label: TKeys.myProducts.tr,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScheduledLiveTab(),
                const MyProductsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Scan / type a UPC and attach the product to a scheduled stream.
  Widget _buildScheduledLiveTab() {
    return BrandedRefreshIndicator(
        onRefresh: _onRefresh,
        child: Obx(() {
        // Spinner while the scheduled fetch runs *and* before the first one has
        // finished — this tab is built inside the home IndexedStack at startup,
        // so without the second condition it renders "no streams yet" on the
        // very first frame, before any load has been attempted.
        if (ctrl.scheduledStreams.isEmpty &&
            (ctrl.isLoadingScheduled || !ctrl.scheduledLoaded)) {
          return const BrandedLoadingView();
        }
        if (ctrl.scheduledStreams.isEmpty) {
          final hasError = ctrl.scheduledError != null;
          return _EmptyStreamsState(
            isError: hasError,
            message: hasError
                ? ctrl.scheduledError!
                : TKeys.noScheduledStreams.tr,
            onRefresh: () =>
                ctrl.fetchStreamsByStatus(status: 'SCHEDULED', refresh: true),
            // A failed load isn't a missing stream — offering "New stream"
            // there would push the seller into creating a duplicate of one
            // they may already have.
            onCreate: hasError ? null : _openCreateStream,
          );
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.grey),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      TKeys.selectStream.tr,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.grey,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                      child: DropdownButton<StreamModel>(
                        // Only ever hand the dropdown a value it actually
                        // lists. StreamModel compares by identity, so a
                        // selection left over from a previous load (or patched
                        // into a new instance elsewhere) would otherwise trip
                        // DropdownButton's "exactly one item with this value"
                        // assertion and take the whole tab down. Falling back
                        // to null just shows the "Select Stream" hint.
                        value: ctrl.scheduledStreams
                                .contains(ctrl.selectedStream.value)
                            ? ctrl.selectedStream.value
                            : null,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        selectedItemBuilder: (context) {
                          return ctrl.scheduledStreams.map((stream) {
                            return Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: stream.isLive
                                        ? Colors.red
                                        : stream.isScheduled
                                            ? AppColors.brandYellow
                                            : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stream.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formatDate(
                                          stream.scheduledStartTime,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList();
                        },
                        hint: Row(
                          children: [
                            const Icon(
                              Icons.live_tv_rounded,
                              color: AppColors.brandNavy,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              TKeys.selectStream.tr,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        items: ctrl.scheduledStreams.map((stream) {
                          return DropdownMenuItem<StreamModel>(
                            value: stream,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: stream.isLive
                                        ? Colors.red
                                        : stream.isScheduled
                                            ? AppColors.brandYellow
                                            : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stream.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        formatDate(
                                          stream.scheduledStartTime,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          ctrl.selectStream(value);
                        },
                      ),
                    ),
                  ),
                  if (ctrl.selectedStream.value != null) ...[
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AutoQuickViewToggle(
                        value: AutoQuickViewPref.enabled,
                        onChanged: (v) =>
                            setState(() => AutoQuickViewPref.enabled = v),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ScanCard(onTap: _openScanner),
                    const SizedBox(height: 12),
                    _UpcEntryRow(
                      controller: _upcFieldCtrl,
                      busy: _throwing,
                      onAdd: () => _processUpc(_upcFieldCtrl.text),
                    ),
                  ],
                  if (ctrl.isProductNotFoundByScan) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomText(
                                      TKeys.productNotFound.tr,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandNavy,
                                    ),
                                    const SizedBox(height: 4),
                                    CustomText(
                                      TKeys.enterDetailsToAdd.tr,
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    _addingUnknown ? null : _dismissUnknownForm,
                                icon: const Icon(Icons.close_rounded),
                                color: AppColors.textSecondary,
                                splashRadius: 20,
                                tooltip: TKeys.scanAgain.tr,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: TKeys.productNameLabel.tr,
                              hintText: TKeys.enterNameHint.tr,
                              filled: true,
                              fillColor: AppColors.inputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 110,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                if (index == _selectedImages.length) {
                                  return GestureDetector(
                                    onTap: _pickImage,
                                    child: Container(
                                      width: 110,
                                      decoration: BoxDecoration(
                                        color: AppColors.inputFill,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.inputBorder,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.add_a_photo_outlined,
                                              color: AppColors.textMuted),
                                          const SizedBox(height: 8),
                                          CustomText(
                                            TKeys.addImage.tr,
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                final image = _selectedImages[index];
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(image.path),
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _removeImageAt(index),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  _addingUnknown ? null : _addUnknownProduct,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandNavy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _addingUnknown
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : CustomText(
                                      TKeys.addUnknownProduct.tr,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                ),
              ),
              const SizedBox(height: 20,),
              //start here
              if (ctrl.selectedStream.value != null) ...[
                if (ctrl.isLoadingProductRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ctrl.productRequestItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CustomText(
                        TKeys.noProductsAddedYet.tr,
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else ...[
                  // Sits above the list so the seller can push everything they
                  // just assigned into the stream's auction queue in one tap.
                  _SendToQueueBar(
                    ctrl: ctrl,
                    onSend: _sendToAuctionQueue,
                  ),
                  const SizedBox(height: 14),
                  ...ctrl.productRequestItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ScannedProductCard(
                        id: item.id,
                        upc: item.requestedUpc??'',
                        name: item.displayName,
                        quantity: item.quantityRequested,
                        imageUrl: item.displayImageUrl,
                        deleting: ctrl.isDeletingItem(item.id),
                        onDelete: () => _deleteProductRequestItem(item),
                        onQuickView: () => _openQuickView(item),
                      ),
                    );
                  }),
                ],
              ],
            ],
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Send to auction queue" bar — header for the assigned-products list.
//
// Shown only once at least one product is assigned to the selected stream. The
// count reflects what the queue will actually accept (catalog products), with a
// note when unknown-UPC rows are being left behind, so the number on the button
// always matches the number that gets queued.
// ─────────────────────────────────────────────────────────────────────────────
class _SendToQueueBar extends StatelessWidget {
  const _SendToQueueBar({required this.ctrl, required this.onSend});

  final StreamListController ctrl;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = ctrl.queueableProductIds.length;
      final busy = ctrl.isSendingToQueue;
      final enabled = count > 0 && !busy;

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.grey),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomText(
              TKeys.submitQueueNote.tr,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: enabled ? onSend : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandNavy,
                  disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandYellow),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.queue_play_next_rounded,
                            size: 18,
                            color: AppColors.brandYellow,
                          ),
                          const SizedBox(width: 8),
                          CustomText(
                            count > 0
                                ? TKeys.sendToQueueCtaCount
                                    .trParams({'count': '$count'})
                                : TKeys.sendToQueueCta.tr,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// One pill in [_SegmentedTabs].
class _SegmentSpec {
  const _SegmentSpec({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Segmented pill switcher used instead of a Material [TabBar] — matches the
/// auction room's tab strip. The navy pill slides with the [TabController]'s
/// animation, so it tracks a swipe between tabs rather than snapping at the
/// end of it, and the label / icon colours cross-fade along the way.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.controller, required this.tabs});

  final TabController controller;
  final List<_SegmentSpec> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0x14000000)),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / tabs.length;
            return AnimatedBuilder(
              animation: controller.animation!,
              builder: (context, _) {
                // 0 → first tab, 1 → second, fractional mid-swipe.
                final position = controller.animation!.value;
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: position * segmentWidth,
                      width: segmentWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.brandNavy,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.buttonShadow,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(tabs.length, (i) {
                        // 1 when this pill is fully selected, 0 when it isn't.
                        final t = (1 - (position - i).abs()).clamp(0.0, 1.0);
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => controller.animateTo(i),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    tabs[i].icon,
                                    size: 16,
                                    color: Color.lerp(
                                      AppColors.textMuted,
                                      AppColors.brandYellow,
                                      t,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: CustomText(
                                      tabs[i].label,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      color: Color.lerp(
                                        AppColors.textSecondary,
                                        Colors.white,
                                        t,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Friendly placeholder shown when there are no scheduled streams to pick
/// from — either because none exist yet or because the load failed. Offers a
/// Refresh action so the seller can retry without leaving the screen, plus
/// (when there's simply nothing to assign to) a "New stream" shortcut into the
/// create form via [onCreate].
class _EmptyStreamsState extends StatelessWidget {
  const _EmptyStreamsState({
    required this.isError,
    required this.message,
    required this.onRefresh,
    this.onCreate,
  });

  final bool isError;
  final String message;
  final VoidCallback onRefresh;

  /// Null on the error variant — retrying is the action there, not creating.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Always scrollable so the surrounding pull-to-refresh still triggers
      // even though this placeholder is shorter than the viewport.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: (isError ? Colors.red : AppColors.brandNavy)
                    .withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError
                    ? Icons.wifi_off_rounded
                    : Icons.live_tv_outlined,
                size: 42,
                color: isError ? Colors.red : AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 20),
            CustomText(
              isError ? TKeys.couldNotLoadStreams.tr : TKeys.noStreamsYet.tr,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 8),
            CustomText(
              message,
              fontSize: 13.5,
              height: 1.45,
              textAlign: TextAlign.center,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            if (onCreate != null) ...[
              ElevatedButton.icon(
                onPressed: onCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandNavy,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add_rounded,
                    size: 20, color: AppColors.brandYellow),
                label: CustomText(
                  TKeys.newStream.tr,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
                side: const BorderSide(color: AppColors.brandNavy),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: CustomText(
                TKeys.refreshAction.tr,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannedProductCard extends StatelessWidget {
  const _ScannedProductCard({
    required this.id,
    required this.upc,
    required this.name,
    required this.quantity,
    required this.imageUrl,
    required this.onDelete,
    required this.onQuickView,
    this.deleting = false,
  });

  final String id;
  final String name;
  final String upc;
  final int quantity;
  final String imageUrl;

  /// True while this row's delete call is in flight — swaps the button for a
  /// spinner and swallows further taps.
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onQuickView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 70,
                height: 70,
                color: AppColors.grey,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  name,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                CustomText(
                  'UPC: $upc',
                  fontSize: 11,
                  color: Colors.grey,
                  maxLines: 1,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandYellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CustomText(
                    'Qty: $quantity',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: onQuickView,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 5),
                  width: 108,
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       const Icon(
                        Icons.remove_red_eye_outlined,
                        size: 18,
                        color: AppColors.brandNavy,
                      ),
                      const SizedBox(width: 4,),
                      CustomText(TKeys.quickView.tr,fontSize: 12,fontWeight: FontWeight.w600,),

                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: deleting ? null : onDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 5),
                  width: 108,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: deleting
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.red),
                            ),
                          ),
                        )
                      : Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 4,),
                      CustomText(TKeys.deleteAction2.tr,fontSize: 12,fontWeight: FontWeight.w600,),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _DiscrepancyTag { size, color, picture, other }

class _ProductDiscrepancyDialog extends StatefulWidget {
  const _ProductDiscrepancyDialog({required this.item});

  final ProductRequestItem item;

  @override
  State<_ProductDiscrepancyDialog> createState() =>
      _ProductDiscrepancyDialogState();
}

class _ProductDiscrepancyDialogState extends State<_ProductDiscrepancyDialog> {
  static const int _maxImages = 10;

  final TextEditingController _reportCtrl = TextEditingController();
  final List<XFile> _reportImages = <XFile>[];
  final List<String> _existingImageUrls = <String>[];
  final ImagePicker _picker = ImagePicker();

  final _ctrl = getOrPut(() => StreamListController());
  bool _loadingIssue = true;
  bool _submitting = false;

  ProductRequestItem get _item => widget.item;
  ProductRequestProduct? get _product => widget.item.product;

  String get _brand => _product?.brand ?? '';
  String get _imageUrl => _item.displayImageUrl;
  String get _productName => _item.displayName;
  String get _suggestedPrice =>
      _product?.originalPrice != null ? '${_product!.originalPrice} NOK' : '-';

  /// MSRP is the manufacturer's suggested price as it comes from the vendor
  /// feed — a USD figure, so it carries a `$` rather than the NOK the rest of
  /// the app trades in. The symbol trails the amount (`800 $`), matching how
  /// the other prices in this dialog read.
  String get _regularPrice =>
      _product?.regularPrice != null ? '${_product!.regularPrice} \$' : '-';
  String get _color =>
      _product?.colour ??
      ((_product?.colorsAvailable.isNotEmpty ?? false)
          ? _product!.colorsAvailable.join(', ')
          : '-');
  String get _sizes => (_product?.sizesAvailable.isNotEmpty ?? false)
      ? _product!.sizesAvailable.join(', ')
      : '-';
  String get _description =>
      (_product?.shortDescription?.trim().isNotEmpty ?? false)
          ? _product!.shortDescription!
          : TKeys.noDescription.tr;

  int get _totalImages => _existingImageUrls.length + _reportImages.length;

  @override
  void initState() {
    super.initState();
    _loadIssue();
  }

  Future<void> _loadIssue() async {
    final issue = await _ctrl.fetchProductRequestItemIssue(_item.id);
    if (!mounted) return;
    setState(() {
      if (issue != null) {
        _reportCtrl.text = issue.message;
        _existingImageUrls
          ..clear()
          ..addAll(issue.imageUrls);
      }
      _loadingIssue = false;
    });
  }

  @override
  void dispose() {
    _reportCtrl.dispose();
    super.dispose();
  }

  static const Set<String> _allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };


  bool _isAllowedImage(XFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _allowedImageExtensions.contains(name.substring(dot + 1));
  }

  /// Asks the user to pick an image source, then captures / picks from it.
  Future<void> _addReportImages() async {
    if (_totalImages >= _maxImages) return;

    final source = await _chooseImageSource();
    if (source == null || !mounted) return;

    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: ImageSource.camera);
      _ingestPicked(shot == null ? const [] : [shot]);
    } else {
      final picked = await _picker.pickMultiImage();
      _ingestPicked(picked);
    }
  }

  /// Bottom sheet offering Camera or Gallery.
  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
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

  /// Validates + appends picked images, respecting the max + allowed types.
  void _ingestPicked(List<XFile> picked) {
    if (picked.isEmpty || !mounted) return;
    final remaining = _maxImages - _totalImages;
    if (remaining <= 0) return;

    final allowed = picked.where(_isAllowedImage).toList();
    final rejected = picked.length - allowed.length;

    if (rejected > 0) {
      Get.snackbar(
        TKeys.unsupportedFile.tr,
        TKeys.onlyImageTypes.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }

    if (allowed.isEmpty) return;
    setState(() {
      _reportImages.addAll(allowed.take(remaining));
    });
  }

  void _removeReportImage(int index) {
    setState(() => _reportImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  /// Short word appended to the report field when a chip is tapped.
  String _presetFor(_DiscrepancyTag tag) {
    switch (tag) {
      case _DiscrepancyTag.size:
        return TKeys.sizeLabel.tr;
      case _DiscrepancyTag.color:
        return TKeys.colorLabel.tr;
      case _DiscrepancyTag.picture:
        return TKeys.pictureLabel.tr;
      case _DiscrepancyTag.other:
        return TKeys.otherLabel.tr;
    }
  }

  /// Appends [snippet] to the report field (with a separating space) and keeps
  /// the caret at the end. Chips are not "selected" — they just insert text.
  void _appendReportText(String snippet) {
    final current = _reportCtrl.text;
    final needsSpace = current.isNotEmpty &&
        !current.endsWith(' ') &&
        !current.endsWith('\n');
    final next = '$current${needsSpace ? ' ' : ''}$snippet ';
    _reportCtrl
      ..text = next
      ..selection = TextSelection.collapsed(offset: next.length);
  }

  Future<void> _submitReport() async {
    if (_submitting) return;

    final message = _reportCtrl.text.trim();
    if (message.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.describeDiscrepancyError.tr);
      return;
    }

    setState(() => _submitting = true);

    final ok = await _ctrl.submitProductRequestItemIssue(
      itemId: _item.id,
      message: message,
      imagePaths: _reportImages.map((e) => e.path).toList(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop();
      Get.snackbar(
        TKeys.successTitle.tr,
        TKeys.reportUpdated.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } else {
      Get.snackbar(
        TKeys.errorTitle.tr,
        _ctrl.errorMessage ?? TKeys.couldNotUpdateReport.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxHeight = size.height * 0.86;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCloseRow(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroImage(),
                    const SizedBox(height: 18),
                    _buildBrandAndTitle(),
                    const SizedBox(height: 14),
                    _buildPriceRow(),
                    const SizedBox(height: 14),
                    _buildSpecLine(TKeys.colorColon.tr, _color),
                    const SizedBox(height: 6),
                    _buildSpecLine(TKeys.sizesColon.tr, _sizes),
                    const SizedBox(height: 12),
                    CustomText(
                      _description,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),

                    // ── Measurements ──────────────────────────────────────
                    // Product-level scope — a product request has no placement
                    // to measure against. Unknown-UPC items have no catalog
                    // product id, so the section is skipped for them.
                    if (_item.productId.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: AppColors.inputBorder),
                      const SizedBox(height: 18),
                      MeasurementGoalsSection(productId: _item.productId),
                    ],

                    const SizedBox(height: 18),
                    const Divider(height: 1, color: AppColors.inputBorder),
                    const SizedBox(height: 18),
                    _buildSectionLabel(TKeys.reportDiscrepancyCaps.tr),
                    const SizedBox(height: 8),
                    CustomText(
                      TKeys.reportDiscrepancyBody.tr,
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    if (_loadingIssue)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      _buildReportField(),
                      const SizedBox(height: 14),
                      _buildTagChips(),
                    ],
                    const SizedBox(height: 22),
                    _buildSectionLabel(TKeys.wrongProductImageCaps.tr),
                    const SizedBox(height: 6),
                    CustomText(
                      TKeys.uploadPhysicalImages
                          .trParams({'max': '$_maxImages'}),
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    if (_totalImages > 0) ...[
                      _buildImageStrip(),
                      const SizedBox(height: 12),
                    ],
                    _buildUploadRow(),
                    const SizedBox(height: 22),
                    _buildUpdateButton(),
                    const SizedBox(height: 12),
                    _buildSeeFullProductButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textSecondary,
            splashRadius: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: AppColors.inputFill,
            child: Image.network(
              _imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 40,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandAndTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          _brand.toUpperCase(),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 4),
        CustomText(
          _productName,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }

  Widget _buildPriceRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _priceColumn(TKeys.suggestedPrice.tr, _suggestedPrice)),
        Expanded(child: _priceColumn('MSRP', _regularPrice)),
      ],
    );
  }

  Widget _priceColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          label,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 4),
        CustomText(
          value,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ],
    );
  }

  Widget _buildSpecLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return CustomText(
      label,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: AppColors.textPrimary,
    );
  }

  Widget _buildReportField() {
    return TextField(
      controller: _reportCtrl,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: TKeys.describeDiscrepancy.tr,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _DiscrepancyTag.values.map((tag) {
        return GestureDetector(
          onTap: () => _appendReportText(_presetFor(tag)),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded,
                    size: 14, color: AppColors.brandNavy),
                const SizedBox(width: 5),
                CustomText(
                  tag.name.toUpperCase(),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageStrip() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _totalImages,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isExisting = index < _existingImageUrls.length;
          final Widget thumb = isExisting
              ? Image.network(
                  _existingImageUrls[index],
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 76,
                    height: 76,
                    color: AppColors.inputFill,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              : Image.file(
                  File(_reportImages[index - _existingImageUrls.length].path),
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                );
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumb,
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => isExisting
                      ? _removeExistingImage(index)
                      : _removeReportImage(index - _existingImageUrls.length),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadRow() {
    final atLimit = _totalImages >= _maxImages;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: atLimit ? null : _addReportImages,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.inputBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: CustomText(
              TKeys.uploadImagesCaps.tr,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        CustomText(
          TKeys.imageCount.trParams(
              {'current': '$_totalImages', 'max': '$_maxImages'}),
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ],
    );
  }

  Widget _buildUpdateButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : CustomText(
                TKeys.updateReport.tr,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
      ),
    );
  }

  Widget _buildSeeFullProductButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: CustomText(
          TKeys.seeFullProduct.tr,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.brandNavy,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline "enter UPC" row — a number field plus a Thrown button, shown under the
// scan card for UPCs the scanner can't read. Submitting or tapping Thrown runs
// the UPC through the same scan endpoint the camera uses.
// ─────────────────────────────────────────────────────────────────────────────
class _UpcEntryRow extends StatelessWidget {
  const _UpcEntryRow({
    required this.controller,
    required this.busy,
    required this.onAdd,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: busy ? null : (_) => onAdd(),
            decoration: InputDecoration(
              hintText: TKeys.enterUpcLabel.tr,
              prefixIcon: const Icon(Icons.qr_code_2_rounded,
                  size: 20, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: busy ? null : onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandNavy,
              disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(AppColors.white),
                    ),
                  )
                : CustomText(
                    TKeys.thrownLabel.tr,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manual UPC entry sheet — a numeric UPC field plus the same name + image
// inputs as the "unknown product" form. Submits through the same
// addUnknownProduct API, passing the typed UPC explicitly.
// ─────────────────────────────────────────────────────────────────────────────
class _ManualUpcSheet extends StatefulWidget {
  const _ManualUpcSheet({required this.ctrl, this.initialUpc});
  final StreamListController ctrl;

  /// Pre-fills the UPC field — set when the sheet opens because a scanned or
  /// typed UPC wasn't in the catalog.
  final String? initialUpc;

  @override
  State<_ManualUpcSheet> createState() => _ManualUpcSheetState();
}

class _ManualUpcSheetState extends State<_ManualUpcSheet> {
  final TextEditingController _upcController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _upcController.text = widget.initialUpc ?? '';
  }

  @override
  void dispose() {
    _upcController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() => _selectedImages.addAll(images));
    }
  }

  void _removeImageAt(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final upc = _upcController.text.trim();
    if (upc.isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      Get.snackbar(TKeys.errorTitle.tr, TKeys.enterProductName.tr);
      return;
    }

    setState(() => _submitting = true);

    final ok = await widget.ctrl.addUnknownProduct(
      name: _nameController.text.trim(),
      imagePaths: _selectedImages.map((e) => e.path).toList(),
      upc: upc,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop();
      Get.snackbar(TKeys.successTitle.tr, TKeys.productAdded.tr);
    } else {
      Get.snackbar(
        TKeys.errorTitle.tr,
        widget.ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inputBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomText(
                          TKeys.addUpcManually.tr,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                        const SizedBox(height: 4),
                        CustomText(
                          TKeys.addUpcManuallyBody.tr,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _upcController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "UPC",
                  hintText: TKeys.enterUpcNumber.tr,
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: TKeys.productNameLabel.tr,
                  hintText: TKeys.enterNameHint.tr,
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == _selectedImages.length) {
                      return GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 110,
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.inputBorder),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo_outlined,
                                  color: AppColors.textMuted),
                              const SizedBox(height: 8),
                              CustomText(
                                TKeys.addImage.tr,
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final image = _selectedImages[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(image.path),
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImageAt(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : CustomText(
                          TKeys.addUnknownProduct.tr,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryYellow, AppColors.primaryOrange],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: AppColors.buttonShadow,
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brandNavy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    TKeys.scanAndAddProduct.tr,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(height: 4),
                  CustomText(
                    TKeys.useCameraToScan.tr,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.brandNavy,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

