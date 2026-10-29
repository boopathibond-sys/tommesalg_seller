import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/env_config.dart';
import '../../../core/localization/translation_keys.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/branded_refresh_indicator.dart';
import '../../../core/widgets/custom_text.dart';
import '../../../models/seller_product_request_detail.dart';
import '../../../models/seller_product_request_summary.dart';
import 'my_requests_view.dart' show formatRequestDate, requestStatusLabel;

/// Read-only history of one product request — opened for a request whose
/// stream is discontinued (an active one goes back to the Requests tab, where
/// products can still be added). Loads
/// `GET /api/v1/seller/streams/{streamId}/product-requests/{requestId}`.
class RequestDetailView extends StatefulWidget {
  const RequestDetailView({super.key, required this.request});

  final SellerProductRequestSummary request;

  @override
  State<RequestDetailView> createState() => _RequestDetailViewState();
}

class _RequestDetailViewState extends State<RequestDetailView> {
  bool _loading = true;
  bool _failed = false;
  SellerProductRequestDetail? _detail;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = widget.request;
    final url = '${EnvConfig.baseUrl}/api/v1/seller/streams/'
        '${r.liveStreamId}/product-requests/${r.id}';
    SellerProductRequestDetail? detail;
    try {
      final response = await ApiClient.instance.get(
        url,
        headers: AuthService.instance.authHeaders,
      );
      if (kDebugMode) {
        var body = response.body;
        try {
          body = const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
        } catch (_) {
          // Not JSON — print as-is.
        }
        debugPrint('[request-detail] GET $url → ${response.statusCode}');
        debugPrint(body, wrapWidth: 1000);
      }
      if (response.isSuccess) {
        final data = response.json['data'];
        if (data is Map<String, dynamic>) {
          detail = SellerProductRequestDetail.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('[request-detail] GET $url failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = detail ?? _detail;
      _failed = detail == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final detail = _detail;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.textPrimary),
        ),
        title: CustomText(
          r.streamTitle.isEmpty ? TKeys.reqDetailTitle.tr : r.streamTitle,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          color: AppColors.textPrimary,
        ),
      ),
      body: BrandedRefreshIndicator(
        onRefresh: _fetch,
        child: LayoutBuilder(
          builder: (context, c) {
            // Two item columns once there's room; capped width on tablets.
            final wide = c.maxWidth >= 640;
            final items = detail?.items ?? const <RequestLineItem>[];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: c.maxWidth > 900 ? (c.maxWidth - 900) / 2 : 16,
                vertical: 16,
              ),
              children: [
                _SummaryCard(request: r, detail: detail),
                const SizedBox(height: 18),
                Row(
                  children: [
                    CustomText(
                      TKeys.productsLabel.tr,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    if (detail != null)
                      CustomText(
                        '${items.length}',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loading && detail == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.brandNavy),
                        ),
                      ),
                    ),
                  )
                else if (_failed && detail == null)
                  _Message(
                    text: TKeys.reqLoadFailed.tr,
                    onRetry: _fetch,
                  )
                else if (items.isEmpty)
                  _Message(text: TKeys.reqNoItems.tr)
                else
                  for (var i = 0; i < items.length; i += wide ? 2 : 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: wide
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: _ItemCard(item: items[i])),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: i + 1 < items.length
                                        ? _ItemCard(item: items[i + 1])
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            )
                          : _ItemCard(item: items[i]),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.request, this.detail});

  final SellerProductRequestSummary request;
  final SellerProductRequestDetail? detail;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final notes = detail?.adminNotes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderGrey),
            ),
            child: CustomText(
              TKeys.reqDiscontinued.tr.toUpperCase(),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            label: TKeys.reqStatusLabel.tr,
            value: requestStatusLabel(detail?.status ?? r.status),
          ),
          _Row(
            label: TKeys.reqSentLabel.tr,
            value: formatRequestDate(detail?.submittedAt ?? r.sentAt),
          ),
          _Row(
            label: TKeys.productsLabel.tr,
            value: '${detail?.items.length ?? r.itemCount}',
            last: notes == null,
          ),
          if (notes != null) ...[
            Container(height: 1, color: const Color(0xFFF0F1F4)),
            const SizedBox(height: 10),
            CustomText(
              TKeys.reqAdminNotes.tr.toUpperCase(),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 4),
            CustomText(
              notes,
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        children: [
          Expanded(
            child: CustomText(
              label,
              fontSize: 12.5,
              color: AppColors.textMuted,
            ),
          ),
          CustomText(
            value,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Item card
// ─────────────────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final RequestLineItem item;

  String _lineStatus(String s) => switch (s) {
        'PENDING_STOCK' => TKeys.reqLinePendingStock.tr,
        'FULFILLED' => TKeys.reqStatusFulfilled.tr,
        'CANCELLED' => TKeys.reqStatusCancelled.tr,
        '' => '',
        // Anything new from the backend: "SOME_STATE" → "Some state".
        _ => s[0] + s.substring(1).toLowerCase().replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    final it = item;
    final name = it.displayName ?? TKeys.reqUnknownProduct.tr;
    final status = _lineStatus(it.lineStatus);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: it.imageUrl == null
                      ? const _ImageFallback()
                      : Image.network(
                          it.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _ImageFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      name,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      color: AppColors.textPrimary,
                    ),
                    if (it.brand != null) ...[
                      const SizedBox(height: 1),
                      CustomText(
                        it.brand!,
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (it.requestedUpc != null)
                          CustomText(
                            'UPC ${it.requestedUpc}',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        if (it.veilPris != null)
                          CustomText(
                            formatNokOrDash(it.veilPris),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: CustomText(
                    status,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Qty(label: TKeys.reqQtyRequested.tr, value: it.quantityRequested),
              _Qty(label: TKeys.reqQtyReserved.tr, value: it.reservedQuantity),
              _Qty(label: TKeys.reqQtyPending.tr, value: it.pendingQuantity),
              _Qty(
                label: TKeys.reqQtyDefect.tr,
                value: it.defectQuantity,
                warn: it.defectQuantity > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Qty extends StatelessWidget {
  const _Qty({required this.label, required this.value, this.warn = false});

  final String label;
  final int value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: warn ? Colors.red.withOpacity(0.06) : AppColors.inputFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            CustomText(
              '$value',
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: warn ? Colors.red : AppColors.textPrimary,
            ),
            const SizedBox(height: 1),
            CustomText(
              label,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.inputFill,
      child: const Icon(Icons.image_outlined,
          size: 22, color: AppColors.textMuted),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          CustomText(
            text,
            fontSize: 13,
            textAlign: TextAlign.center,
            color: AppColors.textSecondary,
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: CustomText(
                TKeys.retryAction.tr,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
        ],
      ),
    );
  }
}
