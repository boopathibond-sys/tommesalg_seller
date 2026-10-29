import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text.dart';

/// Square product image for the stock quick views. With more than one image
/// it becomes a swipeable carousel with a `n/N` counter and page dots.
class ProductImageCarousel extends StatefulWidget {
  const ProductImageCarousel({
    super.key,
    required this.images,
    this.loading = false,
  });

  /// Image URLs, in display order. Empty shows a placeholder.
  final List<String> images;

  /// Shows a spinner instead of the placeholder while the product loads.
  final bool loading;

  @override
  State<ProductImageCarousel> createState() => _ProductImageCarouselState();
}

class _ProductImageCarouselState extends State<ProductImageCarousel> {
  final PageController _pageCtrl = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(ProductImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The gallery can grow when the full product lands after the fallback.
    if (_index >= widget.images.length && widget.images.isNotEmpty) {
      _index = 0;
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              color: AppColors.inputFill,
              child: images.isEmpty
                  ? _placeholder()
                  : Stack(
                      children: [
                        PageView.builder(
                          controller: _pageCtrl,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (_, i) => Image.network(
                            images[i],
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _brokenImage(),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: CustomText(
                                '${_index + 1}/${images.length}',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? AppColors.brandNavy
                        : AppColors.borderGrey,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _placeholder() {
    return Center(
      child: widget.loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
    );
  }

  Widget _brokenImage() {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 40,
        color: AppColors.textMuted,
      ),
    );
  }
}
