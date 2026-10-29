import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../controllers/products_nav_controller.dart';
import '../../../controllers/seller_products_controller.dart';
import '../../../controllers/stream_controller.dart';
import '../../../core/config/get_or_put.dart';
import '../../../core/services/shipping_options_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auto_quick_view_toggle.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/product_request_model.dart';
import '../../../models/seller_product.dart';
import '../../../models/stream_model.dart';
import '../../measurements/measurement_goals_section.dart';
import '../../scanner/barcode_scanner_view.dart';
import '../../stream/create_stream_view.dart';
import '../../stream/stream_list_view.dart' show EnterRoomButton;
import 'my_products_tab.dart';
import 'product_detail_view.dart';
import '../../stock/shared/product_image_carousel.dart';
import '../my_requests/my_requests_view.dart';
import '../../../models/seller_product_request_summary.dart';
import '../../../core/localization/translation_keys.dart';
import '../../../core/widgets/image_source_picker.dart';
import 'package:tommesalg_seller_app/core/utils/app_snackbar.dart';
import 'package:tommesalg_seller_app/core/utils/s3_key.dart';
import '../../../core/utils/currency.dart';
import '../../../core/services/product_defect_service.dart';

/// The two halves of the Products screen. Each has its own bottom-nav tab
/// now (Requests / Products), so [ManageProductView] can show just one of them.
enum ProductsSection { assignToLive, myProducts }

class ManageProductView extends StatefulWidget {
  const ManageProductView({super.key, this.section});

  /// Shows only this section, without the segmented tabs on top. Null keeps
  /// the original two-tab layout.
  final ProductsSection? section;

  @override
  State<ManageProductView> createState() => _ManageProductViewState();
}

class _ManageProductViewState extends State<ManageProductView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();

  /// Inline "enter UPC" field shown under the scan card.
  final TextEditingController _upcFieldCtrl = TextEditingController();

  final List<XFile> _selectedImages = [];
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
    ctrl.fetchStreamsByStatus();

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
    final List<XFile> images = await ImageSourcePicker.pick(context);
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
    await ctrl.fetchStreamsByStatus(refresh: true);
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
    await ctrl.fetchStreamsByStatus(refresh: true);
  }

  /// Cross-stream history of everything the seller has sent. Picking an
  /// active request comes back here with its stream selected, so the seller
  /// can keep adding products and sees the added list below.
  Future<void> _openMyRequests() async {
    final picked = await Navigator.of(context).push<SellerProductRequestSummary>(
      MaterialPageRoute(builder: (_) => const MyRequestsView()),
    );
    if (!mounted || picked == null) return;

    StreamModel? find() => ctrl.scheduledStreams
        .firstWhereOrNull((s) => s.id == picked.liveStreamId);
    var stream = find();
    if (stream == null) {
      // Not in the cached list (created elsewhere, or the list is stale).
      await ctrl.fetchStreamsByStatus(refresh: true);
      if (!mounted) return;
      stream = find();
    }
    if (stream == null) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.reqStreamNotFound.tr);
      return;
    }
    await ctrl.selectStream(stream);
  }

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<Barcode>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
    if (!mounted || result == null) return;
    final upc = result.rawValue;
    if (upc == null || upc.isEmpty) return;

    final added = await ctrl.addScannedProductByStream(upc: upc);
    if (!mounted) return;
    if (!added) {
      // Unknown UPC → the inline "add unknown product" form takes over.
      // Anything else (stream ended, network…) shows the server's message.
      if (!ctrl.isProductNotFoundByScan) {
        AppSnackbar.show(TKeys.errorTitle.tr,
            ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr);
      }
      return;
    }

    _afterScanAdded(upc);
  }

  /// After a scan landed: tells the seller the quantity went up when the same
  /// product was scanned again, then (if the auto quick-view toggle is on)
  /// opens the product's quick view.
  void _afterScanAdded(String upc) {
    final item = ctrl.lastScanItem;
    if (ctrl.lastScanIncremented && item != null) {
      AppSnackbar.show(
        item.displayName,
        TKeys.scanQuantityNow.trParams({'qty': '${item.unsentQuantity}'}),
      );
    }
    if (AutoQuickViewPref.enabled) _openQuickViewForUpc(upc);
  }

  /// Finds the request item the scan just created and opens its quick view.
  /// `addScannedProductByStream` re-fetches the list before returning, so the
  /// row is already there. Leading zeros are ignored when matching, since the
  /// scanner and the backend can disagree on them (e.g. 05673080 / 5673080).
  /// Unknown products are skipped: there's no catalogue entry to preview.
  void _openQuickViewForUpc(String upc) {
    String normalize(String value) {
      final stripped = value.trim().replaceFirst(RegExp(r'^0+'), '');
      return stripped.isEmpty ? value.trim() : stripped;
    }

    // Prefer the exact line the scan touched; fall back to matching the UPC.
    final scanned = ctrl.lastScanItem;
    if (scanned != null) {
      for (final item in ctrl.visibleRequestItems) {
        if (item.id == scanned.id) {
          if (!item.isUnknownUpc) _openQuickView(item);
          return;
        }
      }
    }

    final target = normalize(upc);
    for (final item in ctrl.visibleRequestItems) {
      final requested = item.requestedUpc;
      if (requested != null && normalize(requested) == target) {
        if (!item.isUnknownUpc) _openQuickView(item);
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
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _throwing = true);

    final added = await ctrl.addScannedProductByStream(upc: trimmed);
    if (!mounted) return;
    setState(() => _throwing = false);

    if (added) {
      _upcFieldCtrl.clear();
      _afterScanAdded(trimmed);
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

    AppSnackbar.show(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr);
  }


  Future<void> _addUnknownProduct() async {
    if (_addingUnknown) return;

    if (_nameController.text.trim().isEmpty) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.enterProductName.tr);
      return;
    }
    if (_selectedImages.isEmpty) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.productImageRequired.tr);
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
      AppSnackbar.show(TKeys.successTitle.tr, TKeys.productAdded.tr);
    } else {
      AppSnackbar.show(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotAddProduct.tr);
    }
  }

  void _dismissUnknownForm() {
    _nameController.clear();
    setState(() => _selectedImages.clear());
    ctrl.clearProductNotFound();
  }

  /// "Send to live": submits the stream's product request. The server adds
  /// the scanned units to each product's stock and queues the products, so a
  /// product scanned twice can be auctioned twice. Confirms first — the queue
  /// is what the seller auctions off live, so this shouldn't fire on a stray
  /// tap.
  Future<void> _sendToAuctionQueue() async {
    final stream = ctrl.selectedStream.value;
    if (stream == null) return;

    final lines = ctrl.productRequestItems.length;
    if (lines == 0) {
      AppSnackbar.show(TKeys.nothingToSend.tr, TKeys.addProductFirst.tr);
      return;
    }
    final units = ctrl.unsentUnits;
    final unknown = ctrl.unsentUnknownCount;

    final body = TKeys.sendToLiveBody.trParams({
      'units': '$units',
      'stream': stream.title,
    });
    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.sendToQueueTitle.tr,
      message: unknown > 0
          ? '$body ${TKeys.sendToLiveUnknownNote.trParams({'unknown': '$unknown'})}'
          : body,
      confirmLabel: TKeys.sendAction.tr,
      cancelLabel: TKeys.cancelAction.tr,
      icon: Icons.playlist_add_rounded,
      // Queuing products is what the seller came here to do, so Cancel is the
      // quiet option and Send is the CTA.
      destructive: false,
    );
    if (!confirmed || !mounted) return;

    final result = await ctrl.submitToLive();
    if (!mounted) return;

    if (!result.ok) {
      AppSnackbar.show(
        TKeys.couldNotSendProducts.tr,
        result.error ?? TKeys.pleaseTryAgain.tr,
      );
      return;
    }

    final parts = <String>[
      if (result.units > 0)
        TKeys.sentToLiveUnits.trParams({
          'units': '${result.units}',
          'stream': stream.title,
        }),
      if (result.unknown > 0)
        TKeys.sentToLiveUnknown.trParams({'unknown': '${result.unknown}'}),
      if (result.notQueued > 0)
        TKeys.sentToLiveNotQueued.trParams({'count': '${result.notQueued}'}),
    ];
    AppSnackbar.show(
      result.notQueued > 0 ? TKeys.couldNotSendProducts.tr : TKeys.sentToQueue.tr,
      parts.join(' '),
      duration: Duration(seconds: result.notQueued > 0 ? 6 : 3),
    );
  }

  /// Removes one assigned product from the selected stream. Confirms first —
  /// the seller may have scanned it minutes ago and there's no undo.
  Future<void> _deleteProductRequestItem(ProductRequestItem item) async {
    if (ctrl.isDeletingItem(item.id)) return;

    // Deleting a line also takes the product out of the auction queue, while
    // units already sent to live stay in stock — say so before it happens.
    final message = item.reservedQuantity > 0
        ? TKeys.removeSentProductBody.trParams({
            'name': item.displayName,
            'sent': '${item.reservedQuantity}',
          })
        : TKeys.removeProductBody.trParams({'name': item.displayName});
    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.removeProductTitle.tr,
      message: message,
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
      AppSnackbar.show(TKeys.removedTitle.tr,
          TKeys.removedFromStream.trParams({'name': item.displayName}));
    } else {
      AppSnackbar.show(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotDeleteProduct.tr);
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
    switch (widget.section) {
      case ProductsSection.assignToLive:
        return Scaffold(body: _buildScheduledLiveTab());
      case ProductsSection.myProducts:
        return const Scaffold(body: MyProductsTab());
      case null:
        break;
    }
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

  /// Scan / type a UPC and attach the product to a live or scheduled stream.
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
          // History stays reachable with no streams to assign to.
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _MyRequestsButton(onTap: _openMyRequests),
              ),
              Expanded(child: _EmptyStreamsState(
            isError: hasError,
            message: hasError
                ? ctrl.scheduledError!
                : TKeys.noScheduledStreams.tr,
            onRefresh: () =>
                ctrl.fetchStreamsByStatus(refresh: true),
            // A failed load isn't a missing stream — offering "New stream"
            // there would push the seller into creating a duplicate of one
            // they may already have.
            onCreate: hasError ? null : _openCreateStream,
          )),
            ],
          );
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MyRequestsButton(onTap: _openMyRequests),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderGrey),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandNavy.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StreamCardHeader(count: ctrl.scheduledStreams.length),
                    const SizedBox(height: 10),
                    _StreamPickerField(
                      selected: ctrl.scheduledStreams
                              .contains(ctrl.selectedStream.value)
                          ? ctrl.selectedStream.value
                          : null,
                      streams: ctrl.scheduledStreams,
                      formatDate: formatDate,
                      onSelected: ctrl.selectStream,
                    ),
                  if (ctrl.selectedStream.value != null) ...[
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
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
              const SizedBox(height: 18,),
              //start here
              if (ctrl.selectedStream.value != null) ...[
                if (ctrl.isLoadingProductRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ctrl.visibleRequestItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Center(
                          child: CustomText(
                            ctrl.allProductRequestsSent
                                ? TKeys.allSentToLive.tr
                                : TKeys.noProductsAddedYet.tr,
                            textAlign: TextAlign.center,
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        // Everything's queued — take the seller straight into
                        // the stream's auction room to sell it.
                        if (ctrl.allProductRequestsSent) ...[
                          const SizedBox(height: 16),
                          EnterRoomButton(
                            stream: ctrl.selectedStream.value!,
                            ctrl: ctrl,
                            label: TKeys.viewAuction.tr,
                          ),
                        ],
                      ],
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
                  ...ctrl.visibleRequestItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ScannedProductCard(
                        id: item.id,
                        upc: item.requestedUpc??'',
                        name: item.displayName,
                        // Only the units not sent to live yet.
                        quantity: item.unsentQuantity,
                        lineStatus: item.lineStatus,
                        reservedQuantity: item.reservedQuantity,
                        pendingQuantity: item.pendingQuantity,
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
      final count = ctrl.productRequestItems.length;
      final busy = ctrl.isSendingToQueue;
      final enabled = count > 0 && !busy;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderGrey),
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
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
                              AlwaysStoppedAnimation(AppColors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.queue_play_next_rounded,
                            size: 17,
                            color: AppColors.white,
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
                    size: 20, color: AppColors.white),
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
    required this.lineStatus,
    required this.reservedQuantity,
    required this.pendingQuantity,
    this.deleting = false,
  });

  final String id;
  final String name;
  final String upc;
  final int quantity;
  final String imageUrl;

  /// Backend `lineStatus` — DRAFT | RESERVED | PENDING_STOCK |
  /// PENDING_UNKNOWN | CANCELLED.
  final String lineStatus;

  /// Units already credited to stock for this line.
  final int reservedQuantity;

  /// Units still waiting on stock.
  final int pendingQuantity;

  /// True while this row's delete call is in flight — swaps the button for a
  /// spinner and swallows further taps.
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onQuickView;

  int get _reserved => reservedQuantity;

  /// A draft line hasn't been submitted yet, so the backend may not have
  /// split it into reserved / pending — treat all scanned units as waiting.
  int get _waiting => lineStatus == 'DRAFT' && pendingQuantity == 0
      ? quantity
      : pendingQuantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey),
      ),
      // IntrinsicHeight + stretch lets the button column span the card's
      // full height, so the buttons can sit vertically centred on the right.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Total (reserved + waiting) tucked into the image's bottom-right corner.
            Align(
              alignment: Alignment.topCenter,
              child: Stack(
                clipBehavior: Clip.none,
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
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.brandYellow,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: CustomText(
                        'x${_reserved + _waiting}',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
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
                  _LineStatusPill(lineStatus: lineStatus),
                  const SizedBox(height: 4),
                  CustomText(
                    TKeys.reqReservedWaiting.trParams({
                      'reserved': '$_reserved',
                      'waiting': '$_waiting',
                    }),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Unknown products waiting on admin have no catalogue entry
                // to preview yet.
                if (lineStatus != 'PENDING_UNKNOWN') ...[
                  GestureDetector(
                    onTap: onQuickView,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      width: 108,
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.remove_red_eye_outlined,
                            size: 18,
                            color: AppColors.brandNavy,
                          ),
                          const SizedBox(width: 4),
                          CustomText(
                            TKeys.quickView.tr,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: deleting ? null : onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 5,
                    ),
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
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              CustomText(
                                TKeys.deleteAction2.tr,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Coloured tag for a request line's backend `lineStatus`.
class _LineStatusPill extends StatelessWidget {
  const _LineStatusPill({required this.lineStatus});

  final String lineStatus;

  @override
  Widget build(BuildContext context) {
    final (label, fg) = switch (lineStatus) {
      'RESERVED' => (TKeys.reqQtyReserved.tr, Colors.green.shade700),
      'PENDING_STOCK' => (TKeys.reqLinePendingStock.tr, Colors.orange.shade800),
      'PENDING_UNKNOWN' => (TKeys.reqLinePendingUnknown.tr, Colors.orange.shade800),
      'CANCELLED' => (TKeys.reqStatusCancelled.tr, Colors.red),
      'FULFILLED' => (TKeys.reqStatusFulfilled.tr, Colors.green.shade700),
      'DRAFT' || '' => (TKeys.reqStatusDraft.tr, AppColors.brandNavy),
      // Anything new from the backend: "SOME_STATE" → "Some state".
      _ => (
          lineStatus[0] +
              lineStatus.substring(1).toLowerCase().replaceAll('_', ' '),
          AppColors.textSecondary,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: CustomText(
        label,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: fg,
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

  final _ctrl = getOrPut(() => StreamListController());
  bool _loadingIssue = true;
  bool _submitting = false;

  /// The discrepancy report is read-only until its pencil is tapped.
  bool _editingReport = false;

  // ---------- Defect state ----------
  ProductDefect? _defect;
  bool _loadingDefect = true;
  bool _editingDefect = false;
  bool _savingDefect = false;
  final TextEditingController _defectCtrl = TextEditingController();
  final List<String> _defectExisting = <String>[];
  final List<XFile> _defectNew = <XFile>[];
  int _defectQty = 1;

  int get _defectImageCount => _defectExisting.length + _defectNew.length;

  /// Defect units can't exceed what the line requests.
  int get _maxDefectQty =>
      _item.quantityRequested < 1 ? 1 : _item.quantityRequested;

  /// Shipping amounts the backend accepts, from
  /// `GET /seller/shipping-options`; the fixed fallback until it answers.
  ShippingOptions _shippingOptions = ShippingOptionsService.instance.current;
  List<num> get _shippingTiers => _shippingOptions.amountsNok;
  num get _standardShipping => _shippingOptions.defaultNok;

  /// Tier last confirmed by the server, and the one currently picked in the
  /// dropdown. Save is only enabled while they differ.
  late num _savedShipping;
  late num _shipping;
  bool _savingShipping = false;

  /// Whether the server holds a shipping tier for this product (null / 0 is
  /// "never set") — the "Saved: … NOK" line only shows when it does.
  late bool _shippingConfigured;

  ProductRequestItem get _item => widget.item;
  ProductRequestProduct? get _product => widget.item.product;

  String get _brand => _product?.brand ?? '';
  String get _imageUrl => _item.displayImageUrl;

  /// `product.images` from the measurement bundle — preferred for the slider.
  List<String> _bundleImages = const [];

  /// Every product image for the slider: the bundle's list, then the request
  /// item's own, then the single display image.
  List<String> get _images {
    if (_bundleImages.isNotEmpty) return _bundleImages;
    final own = _item.product?.images ?? const <String>[];
    if (own.isNotEmpty) return own;
    return _imageUrl.isEmpty ? const [] : [_imageUrl];
  }
  String get _productName => _item.displayName;
  String get _suggestedPrice =>
      formatNokOrDash(_product?.originalPrice);

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

  /// Shipping can only be set on a real catalog product — unknown-UPC items
  /// have nothing for the endpoint to update.
  bool get _canEditShipping =>
      _item.productId.isNotEmpty && !_item.isUnknownUpc;

  @override
  void initState() {
    super.initState();
    // Null / 0 means "never configured", which the backend treats as the
    // standard tier. An off-tier legacy value also falls back to standard so
    // the dropdown always has a matching item.
    final raw = _product?.shippingPriceNok;
    _savedShipping = raw != null && _shippingTiers.contains(raw)
        ? raw
        : _standardShipping;
    _shipping = _savedShipping;
    _shippingConfigured = raw != null && raw > 0;
    ShippingOptionsService.instance.load().then(_applyShippingOptions);
    _loadIssue();
    if (_canEditShipping) {
      _loadDefect();
    } else {
      _loadingDefect = false;
    }
  }

  /// Swaps in the fetched amounts. The saved value is re-matched against the
  /// new list; an unsaved pick survives only if the list still offers it.
  void _applyShippingOptions(ShippingOptions options) {
    if (!mounted) return;
    setState(() {
      final dirty = _shipping != _savedShipping;
      _shippingOptions = options;
      final raw = _product?.shippingPriceNok;
      _savedShipping = raw != null && _shippingTiers.contains(raw)
          ? raw
          : _standardShipping;
      if (!dirty || !_shippingTiers.contains(_shipping)) {
        _shipping = _savedShipping;
      }
    });
  }

  Future<void> _saveShipping() async {
    if (_savingShipping || _shipping == _savedShipping) return;
    setState(() => _savingShipping = true);

    final picked = _shipping;
    final ok = await _ctrl.updateProductShipping(
      productId: _item.productId,
      shippingPriceNok: picked,
    );

    if (!mounted) return;
    setState(() {
      _savingShipping = false;
      if (ok) {
        _savedShipping = picked;
        _shippingConfigured = true;
      }
    });

    if (ok) {
      AppSnackbar.show(
        TKeys.shippingUpdated.tr,
        TKeys.shippingUpdatedBody.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } else {
      AppSnackbar.show(
        TKeys.errorTitle.tr,
        _ctrl.errorMessage ?? TKeys.couldNotUpdateShipping.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
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
    _defectCtrl.dispose();
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

  /// Camera (in-app pro camera) or gallery, via the shared chooser.
  Future<void> _addReportImages() async {
    final picked = await _pickImages(_maxImages - _totalImages);
    if (picked.isEmpty) return;
    setState(() => _reportImages.addAll(picked));
  }

  Future<void> _addDefectImages() async {
    final picked =
        await _pickImages(ProductDefectService.maxImages - _defectImageCount);
    if (picked.isEmpty) return;
    setState(() => _defectNew.addAll(picked));
  }

  /// Picks up to [room] images, dropping (and flagging) unsupported types.
  Future<List<XFile>> _pickImages(int room) async {
    if (room <= 0) return const [];
    final picked = await ImageSourcePicker.pick(context, maxImages: room);
    if (picked.isEmpty || !mounted) return const [];

    final allowed = picked.where(_isAllowedImage).toList();
    final rejected = picked.length - allowed.length;

    if (rejected > 0) {
      AppSnackbar.show(
        TKeys.unsupportedFile.tr,
        TKeys.onlyImageTypes.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }

    return allowed.take(room).toList();
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

    // Reason and photos are each optional (sent as `""` / `[]`), but a
    // report needs at least one of them.
    final message = _reportCtrl.text.trim();
    if (message.isEmpty && _totalImages == 0) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.reportReasonOrImage.tr);
      return;
    }

    setState(() => _submitting = true);

    final ok = await _ctrl.submitProductRequestItemIssue(
      itemId: _item.id,
      message: message,
      // Sent back so editing only the reason keeps the saved photos.
      existingImageKeys: _existingImageUrls.map(s3KeyOf).toList(),
      imagePaths: _reportImages.map((e) => e.path).toList(),
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (ok) {
        _editingReport = false;
        _reportImages.clear();
      }
    });

    if (ok) {
      // Re-read so the saved photos come back as server URLs.
      _loadIssue();
      AppSnackbar.show(
        TKeys.successTitle.tr,
        TKeys.reportUpdated.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } else {
      AppSnackbar.show(
        TKeys.errorTitle.tr,
        _ctrl.errorMessage ?? TKeys.couldNotUpdateReport.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _startEditingReport() => setState(() => _editingReport = true);

  // ---------- Defect ----------

  Future<void> _loadDefect() async {
    final defect = await ProductDefectService.instance.fetch(_item.productId);
    if (!mounted) return;
    setState(() {
      _defect = defect;
      _loadingDefect = false;
    });
  }

  /// Seeds the edit form from the saved defect.
  void _startEditingDefect() {
    final d = _defect ?? const ProductDefect();
    setState(() {
      _defectCtrl.text = d.description;
      _defectExisting
        ..clear()
        ..addAll(d.images);
      _defectNew.clear();
      _defectQty = d.quantity.clamp(1, _maxDefectQty);
      _editingDefect = true;
    });
  }

  /// Uploads new photos, then PUTs the full defect. The note is optional and
  /// goes as `""` when empty; an empty form (no photos, no note) clears the
  /// defect with `defectQuantity: 0`.
  Future<void> _saveDefect() async {
    if (_savingDefect) return;
    final description = _defectCtrl.text.trim();
    final clearing = description.isEmpty && _defectImageCount == 0;

    setState(() => _savingDefect = true);
    final service = ProductDefectService.instance;
    try {
      final keys = <String>[..._defectExisting.map(s3KeyOf)];
      for (final img in _defectNew) {
        keys.add(await service.uploadImage(_item.productId, img.path));
      }
      final saved = await service.save(
        productId: _item.productId,
        requestItemId: _item.id,
        imageKeys: keys,
        description: description,
        defectQuantity: clearing ? 0 : _defectQty,
      );
      if (!mounted) return;
      setState(() {
        _defect = saved;
        _defectNew.clear();
        _editingDefect = false;
        _savingDefect = false;
      });
      AppSnackbar.show(
        TKeys.successTitle.tr,
        clearing ? TKeys.defectCleared.tr : TKeys.defectSaved.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingDefect = false);
      AppSnackbar.show(
        TKeys.errorTitle.tr,
        e is String ? e : TKeys.defectCouldNotSave.tr,
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

                    // ── Shipping ──────────────────────────────────────────
                    if (_canEditShipping) ...[
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: AppColors.inputBorder),
                      const SizedBox(height: 18),
                      _buildSectionLabel(TKeys.shippingCaps.tr),
                      const SizedBox(height: 6),
                      CustomText(
                        TKeys.shippingQuickViewBody.tr,
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                      if (_shippingConfigured) ...[
                        const SizedBox(height: 8),
                        CustomText(
                          TKeys.shippingSaved.trParams({
                            'amount': _savedShipping % 1 == 0
                                ? '${_savedShipping.toInt()}'
                                : '$_savedShipping',
                          }),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildShippingDropdown(),
                      const SizedBox(height: 12),
                      _buildSaveShippingButton(),
                    ],

                    // ── Measurements ──────────────────────────────────────
                    // Product-level scope — a product request has no placement
                    // to measure against. Unknown-UPC items have no catalog
                    // product id, so the section is skipped for them.
                    if (_item.productId.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: AppColors.inputBorder),
                      const SizedBox(height: 18),
                      MeasurementGoalsSection(
                        key: ValueKey('measurements-${_item.productId}'),
                        productId: _item.productId,
                        onProductImages: (images) {
                          if (mounted) setState(() => _bundleImages = images);
                        },
                      ),
                    ],

                    // ── Defect ────────────────────────────────────────────
                    if (_canEditShipping) ...[
                      const SizedBox(height: 12),
                      _buildBorderedSection([
                        _buildSectionHeader(
                          TKeys.defectCaps.tr,
                          onEdit: _editingDefect || _loadingDefect
                              ? null
                              : _startEditingDefect,
                        ),
                        CustomText(
                          TKeys.defectBody.tr,
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        if (_loadingDefect)
                          _buildSectionSpinner()
                        else if (_editingDefect)
                          _buildDefectEditor()
                        else
                          _buildDefectSummary(),
                      ]),
                    ],

                    // ── Report a discrepancy ──────────────────────────────
                    const SizedBox(height: 12),
                    _buildBorderedSection([
                      _buildSectionHeader(
                        TKeys.reportDiscrepancyCaps.tr,
                        onEdit: _editingReport || _loadingIssue
                            ? null
                            : _startEditingReport,
                      ),
                      CustomText(
                        TKeys.reportDiscrepancyBody.tr,
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      if (_loadingIssue)
                        _buildSectionSpinner()
                      else if (_editingReport)
                        _buildReportEditor()
                      else
                        _buildReportSummary(),
                    ]),
                    const SizedBox(height: 22),
                    // Unknown-UPC items have no catalog product to open.
                    if (_canEditShipping) _buildSeeFullProductButton(),
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
    return ProductImageCarousel(images: _images);
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
        Expanded(child: _priceColumn(TKeys.stSuggestedRetail.tr, _suggestedPrice)),
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

  /// Bordered card for the defect and discrepancy sections — the same look
  /// as the measurement cards above them.
  Widget _buildBorderedSection(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
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

  /// Section label with a pencil on the right; [onEdit] null hides it.
  Widget _buildSectionHeader(String label, {VoidCallback? onEdit}) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: _buildSectionLabel(label)),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              tooltip: TKeys.edit.tr,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.brandNavy),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionSpinner() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildMutedNote(String text) {
    return CustomText(
      text,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );
  }

  /// Saved text (or "No text message"), then "Attached images" and the
  /// photos — the read-only body of the defect and discrepancy sections.
  Widget _buildSavedTextAndImages(String text, List<String> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isEmpty)
          _buildMutedNote(TKeys.noTextMessage.tr)
        else
          CustomText(text, fontSize: 13.5, height: 1.4,
              color: AppColors.textPrimary),
        const SizedBox(height: 14),
        _buildSectionLabel(TKeys.attachedImagesCaps.tr),
        const SizedBox(height: 8),
        if (images.isEmpty)
          _buildMutedNote(TKeys.msNoPhotos.tr)
        else
          _buildThumbStrip(urls: images),
      ],
    );
  }

  /// "Wrong product image?" with its upload hint — heads the discrepancy
  /// photos in both view and edit mode.
  Widget _buildWrongImageHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(TKeys.wrongProductImageCaps.tr),
        const SizedBox(height: 6),
        CustomText(
          TKeys.uploadPhysicalImages.trParams({'max': '$_maxImages'}),
          fontSize: 12.5,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildReportSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWrongImageHeading(),
        const SizedBox(height: 14),
        _buildSavedTextAndImages(
            _reportCtrl.text.trim(), _existingImageUrls),
      ],
    );
  }

  Widget _buildReportEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReportField(),
        const SizedBox(height: 14),
        _buildTagChips(),
        const SizedBox(height: 22),
        _buildWrongImageHeading(),
        const SizedBox(height: 12),
        if (_totalImages > 0) ...[
          _buildThumbStrip(
            urls: _existingImageUrls,
            files: _reportImages,
            onRemoveUrl: _removeExistingImage,
            onRemoveFile: _removeReportImage,
          ),
          const SizedBox(height: 12),
        ],
        _buildUploadRow(
          count: _totalImages,
          max: _maxImages,
          onPressed: _submitting ? null : _addReportImages,
        ),
        const SizedBox(height: 16),
        _buildSaveAction(
          busy: _submitting,
          label: TKeys.updateReport.tr,
          onSave: _submitReport,
        ),
      ],
    );
  }

  /// Saved defect: description, photos and unit count, read-only.
  Widget _buildDefectSummary() {
    final d = _defect ?? const ProductDefect();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSavedTextAndImages(d.description, d.images),
        if (d.quantity > 0) ...[
          const SizedBox(height: 10),
          _buildSpecLine(
            '${TKeys.defectUnitsLabel.tr}:',
            TKeys.defectUnitsValue.trParams({
              'count': '${d.quantity}',
              'total': '${_item.quantityRequested}',
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildDefectEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_defectImageCount > 0) ...[
          _buildThumbStrip(
            urls: _defectExisting,
            files: _defectNew,
            onRemoveUrl: (i) => setState(() => _defectExisting.removeAt(i)),
            onRemoveFile: (i) => setState(() => _defectNew.removeAt(i)),
          ),
          const SizedBox(height: 12),
        ],
        _buildUploadRow(
          count: _defectImageCount,
          max: ProductDefectService.maxImages,
          onPressed: _savingDefect ? null : _addDefectImages,
        ),
        const SizedBox(height: 14),
        _buildTextArea(_defectCtrl, TKeys.defectDescribeHint.tr),
        const SizedBox(height: 12),
        _buildDefectQtyStepper(),
        const SizedBox(height: 16),
        _buildSaveAction(
          busy: _savingDefect,
          label: TKeys.save.tr,
          onSave: _saveDefect,
        ),
      ],
    );
  }

  Widget _buildDefectQtyStepper() {
    Widget step(IconData icon, VoidCallback? onTap) => IconButton(
          onPressed: _savingDefect ? null : onTap,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20, color: AppColors.brandNavy),
        );
    return Row(
      children: [
        Expanded(
          child: CustomText(
            TKeys.defectUnitsLabel.tr,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        step(Icons.remove_circle_outline_rounded,
            _defectQty > 1 ? () => setState(() => _defectQty--) : null),
        CustomText(
          '$_defectQty / $_maxDefectQty',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        step(
            Icons.add_circle_outline_rounded,
            _defectQty < _maxDefectQty
                ? () => setState(() => _defectQty++)
                : null),
      ],
    );
  }

  /// Full-width save at the bottom of a section in edit mode.
  Widget _buildSaveAction({
    required bool busy,
    required String label,
    required VoidCallback onSave,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: busy ? null : onSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : CustomText(
                label,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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

  String _nok(num v) => formatNok(v);

  String _shippingLabel(num v) => v == _standardShipping
      ? TKeys.shippingStandardSuffix.trParams({'price': _nok(v)})
      : _nok(v);

  Widget _buildShippingDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<num>(
          value: _shipping,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          items: [
            for (final tier in _shippingTiers)
              DropdownMenuItem<num>(
                value: tier,
                child: Text(_shippingLabel(tier)),
              ),
          ],
          onChanged: _savingShipping
              ? null
              : (v) {
                  if (v != null) setState(() => _shipping = v);
                },
        ),
      ),
    );
  }

  Widget _buildSaveShippingButton() {
    final dirty = _shipping != _savedShipping;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: dirty && !_savingShipping ? _saveShipping : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.inputBorder,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _savingShipping
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : CustomText(
                TKeys.saveShipping.tr,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: dirty ? Colors.white : AppColors.textSecondary,
              ),
      ),
    );
  }

  Widget _buildReportField() =>
      _buildTextArea(_reportCtrl, TKeys.describeDiscrepancy.tr);

  Widget _buildTextArea(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      maxLines: 3,
      minLines: 3,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
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

  /// Saved photos ([urls]) then newly picked ones ([files]). Remove buttons
  /// show only when their callbacks are given.
  Widget _buildThumbStrip({
    required List<String> urls,
    List<XFile> files = const [],
    ValueChanged<int>? onRemoveUrl,
    ValueChanged<int>? onRemoveFile,
  }) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length + files.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isUrl = index < urls.length;
          final Widget thumb = isUrl
              ? Image.network(
                  urls[index],
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
                  File(files[index - urls.length].path),
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                );
          final onRemove = isUrl ? onRemoveUrl : onRemoveFile;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumb,
              ),
              if (onRemove != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () =>
                        onRemove(isUrl ? index : index - urls.length),
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

  Widget _buildUploadRow({
    required int count,
    required int max,
    required VoidCallback? onPressed,
  }) {
    final atLimit = count >= max;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: atLimit ? null : onPressed,
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
          TKeys.imageCount.trParams({'current': '$count', 'max': '$max'}),
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ],
    );
  }

  /// Closes the quick view and opens the full product page.
  void _openFullProduct() {
    final navigator = Navigator.of(context);
    final product = _item.product;
    final images = _images;
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProductDetailView(
          // The page reloads everything by id; this row only fills the header
          // until `GET /seller/products/{id}` lands.
          product: SellerProduct(
            id: _item.productId,
            name: _productName,
            status: '',
            isVisible: true,
            originalPrice: product?.originalPrice,
            images: images,
          ),
          ctrl: getOrPut(() => SellerProductsController()),
          initialImages: images,
        ),
      ),
    );
  }

  Widget _buildSeeFullProductButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: _openFullProduct,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryYellow,
          foregroundColor: AppColors.brandNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: CustomText(
          TKeys.seeFullProduct.tr,
          fontSize: 14,
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
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: TKeys.enterUpcLabel.tr,
              hintStyle: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.qr_code_2_rounded,
                  size: 18, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.inputFill,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: busy ? null : onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandNavy,
              disabledBackgroundColor: AppColors.brandNavy.withOpacity(0.4),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    TKeys.addAction.tr,
                    fontSize: 13,
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
    final images = await ImageSourcePicker.pick(context);
    if (images.isNotEmpty && mounted) {
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
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.enterUpc.tr);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.enterProductName.tr);
      return;
    }
    if (_selectedImages.isEmpty) {
      AppSnackbar.show(TKeys.errorTitle.tr, TKeys.productImageRequired.tr);
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
      AppSnackbar.show(TKeys.successTitle.tr, TKeys.productAdded.tr);
    } else {
      AppSnackbar.show(
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
    return Material(
      color: AppColors.brandNavy,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      TKeys.scanAndAddProduct.tr,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 2),
                    CustomText(
                      TKeys.useCameraToScan.tr,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: Colors.white.withOpacity(0.65),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.6),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stream selector for the Assign-to-live tab.
///
/// A tap target that opens a modal sheet, not a [DropdownButton]. The dropdown
/// it replaced painted its menu in an overlay anchored to the button, so on a
/// short screen — or with the tab scrolled down past its rest position, which
/// is where a pull-to-refresh leaves it — the list ran off the bottom of the
/// window and the last streams were unreachable. A sheet is laid out against
/// the window instead of the button, so it can never be clipped by the bottom
/// of the screen or by the nav bar, and it has room for the two-line rows the
/// old cramped menu was squeezing.
class _StreamPickerField extends StatelessWidget {
  const _StreamPickerField({
    required this.selected,
    required this.streams,
    required this.formatDate,
    required this.onSelected,
  });

  final StreamModel? selected;
  final List<StreamModel> streams;
  final String Function(DateTime?) formatDate;
  final ValueChanged<StreamModel> onSelected;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<StreamModel>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _StreamPickerSheet(
        selected: selected,
        streams: streams,
        formatDate: formatDate,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final stream = selected;
    return stream == null
        ? _buildEmpty(context)
        : _buildSelected(context, stream);
  }

  /// Nothing picked yet: a quiet neutral row.
  Widget _buildEmpty(BuildContext context) {
    return Material(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.borderGrey),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 18, color: AppColors.brandNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomText(
                  TKeys.selectStream.tr,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// A stream is picked: compact row with its cover, status and start time.
  Widget _buildSelected(BuildContext context, StreamModel stream) {
    final thumb = stream.thumbnailUrl;
    return Material(
      color: AppColors.brandNavy.withOpacity(0.03),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.brandNavy.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: thumb == null || thumb.isEmpty
                      ? const _ThumbFallback()
                      : Image.network(
                          thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _ThumbFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CustomText(
                            stream.title,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StatusPill(stream: stream),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: CustomText(
                            formatDate(stream.scheduledStartTime),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // "Change stream" affordance.
              const Icon(Icons.unfold_more_rounded,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small icon + "Select stream" + how many streams there are to pick from.
class _StreamCardHeader extends StatelessWidget {
  const _StreamCardHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.brandNavy.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.live_tv_rounded,
              size: 15, color: AppColors.brandNavy),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CustomText(
            TKeys.selectStream.tr,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        CustomText(
          '$count',
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ],
    );
  }
}

/// Stand-in cover for a stream without a thumbnail.
class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brandNavy.withOpacity(0.07),
      child: const Icon(Icons.live_tv_rounded,
          size: 20, color: AppColors.brandNavy),
    );
  }
}

/// Tiny "● LIVE" / "SCHEDULED" tag beside the selected stream's title.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.stream});

  final StreamModel stream;

  @override
  Widget build(BuildContext context) {
    final live = stream.isLive;
    final label = live
        ? TKeys.statusLive.tr
        : stream.isScheduled
            ? TKeys.statusScheduled.tr
            : stream.status;
    final fg = live ? Colors.red : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          CustomText(
            label.toUpperCase(),
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: fg,
          ),
        ],
      ),
    );
  }
}

/// Small "My requests" pill, right-aligned at the top of the Requests tab.
class _MyRequestsButton extends StatelessWidget {
  const _MyRequestsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_rounded,
                    size: 15, color: AppColors.brandNavy),
                const SizedBox(width: 5),
                CustomText(
                  TKeys.myRequests.tr,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet the picker opens: every live and scheduled stream as a full-width row,
/// scrollable, capped at 70% of the window so the handle stays visible and the
/// list is obviously more than what fits.
class _StreamPickerSheet extends StatelessWidget {
  const _StreamPickerSheet({
    required this.selected,
    required this.streams,
    required this.formatDate,
  });

  final StreamModel? selected;
  final List<StreamModel> streams;
  final String Function(DateTime?) formatDate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.live_tv_rounded,
                      size: 19, color: AppColors.brandNavy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomText(
                      TKeys.selectStream.tr,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: streams.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final stream = streams[i];
                  final isSelected = stream == selected;
                  return Material(
                    color: isSelected
                        ? AppColors.brandNavy.withOpacity(0.04)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(stream),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.brandNavy
                                : AppColors.borderGrey,
                            width: isSelected ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            _StatusDot(stream: stream),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CustomText(
                                    stream.title,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    color: AppColors.textPrimary,
                                  ),
                                  const SizedBox(height: 3),
                                  _StreamSubtitle(
                                    stream: stream,
                                    formatDate: formatDate,
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check_circle_rounded,
                                    size: 20, color: AppColors.brandNavy),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live / scheduled / other, as the coloured dot both the field and the sheet
/// show beside a stream.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.stream});

  final StreamModel stream;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: stream.isLive
            ? Colors.red
            : stream.isScheduled
                ? AppColors.primaryBlue
                : Colors.grey,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// "Live · 10/10/2026 • 18:00" under a stream's title, so the seller can tell
/// a stream that is on air right now from one planned for later.
class _StreamSubtitle extends StatelessWidget {
  const _StreamSubtitle({required this.stream, required this.formatDate});

  final StreamModel stream;
  final String Function(DateTime?) formatDate;

  @override
  Widget build(BuildContext context) {
    final label = stream.isLive
        ? TKeys.statusLive.tr
        : stream.isScheduled
            ? TKeys.statusScheduled.tr
            : null;

    return Row(
      children: [
        if (label != null) ...[
          CustomText(
            label,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: stream.isLive ? Colors.red : AppColors.brandNavy,
          ),
          const CustomText(
            '  ·  ',
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ],
        Flexible(
          child: CustomText(
            formatDate(stream.scheduledStartTime),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
