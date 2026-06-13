import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:mobile_scanner/mobile_scanner.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/inventory_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/stock_nav_controller.dart';
import '../../controllers/stream_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/custom_text.dart';
import '../../models/seller_profile.dart';
import '../auth/login_view.dart';
import '../products/manage_products/manage_products_view.dart';
import '../profile/edit_profile_view.dart';
// import '../scanner/barcode_scanner_view.dart';
// import '../scan_inventory/scan_inventory_view.dart';
import '../stock/stock_view.dart';
import '../stream/stream_list_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _index = 0;
  // final List<Barcode> _scanned = [];

  final _profileCtrl    = getOrPut(() => ProfileController());
  final _streamListCtrl = getOrPut(() => StreamListController());
  bool _streamLoaded = false;
  // late final AuctionController _auctionController =
  // getOrPut(() => AuctionController());
  static const _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_rounded,        label: 'Home'),
    _TabSpec(icon: Icons.connected_tv_outlined,     label: 'Streams'),
    _TabSpec(icon: Icons.live_tv_outlined, label: 'Live'),
    _TabSpec(icon: Icons.inventory_2_rounded, label: 'Stock'),
    _TabSpec(icon: Icons.person_rounded,      label: 'Profile'),
  ];

  // Future<void> _openScanner() async {
  //   final result = await Navigator.of(context).push<Barcode>(
  //     MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
  //   );
  //   if (!mounted || result == null) return;
  //
  //   setState(() => _scanned.add(result));
  // }

  // void _removeAt(int i) {
  //   setState(() => _scanned.removeAt(i));
  // }

  /// Switches the bottom nav to the Stock tab and asks it (via the shared
  /// [StockNavController]) to show the SKUs segment — optionally opening the
  /// New SKU dialog. Drives the Home "Quick actions" cards.
  void _goToStockSkus({bool create = false}) {
    getOrPut(() => StockNavController()).goToSkus(create: create);
    // Mirror the bottom-nav Stock behaviour: (re)load the overview stats.
    getOrPut(() => InventoryController()).fetchStats();
    setState(() => _index = 3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            _HomeTab(
              profileCtrl: _profileCtrl,
              onCreateSku: () => _goToStockSkus(create: true),
              onEditSku: () => _goToStockSkus(),
            ),
            const StreamListView(),
            const ManageProductView(),
            const StockView(),
            _ProfileTab(profileCtrl: _profileCtrl),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        tabs:  _tabs,
        onTap: (i) {
          if (i == 1 && !_streamLoaded) {
            _streamLoaded = true;
            _streamListCtrl.fetchStreams(refresh: true);
          }else if(i==2){
            _streamListCtrl.fetchStreamsByStatus(status: 'SCHEDULED');
          }else if(i==3){
            // Stock tab: (re)load the warehouse overview stats every time it's
            // opened. Inside the IndexedStack the controller's onInit fires
            // only once at startup, so this retries an earlier failed/missing
            // call. getOrPut returns the same InventoryController the Stock
            // section is already observing.
            getOrPut(() => InventoryController()).fetchStats();
          }
          setState(() => _index = i);
        },
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({required this.icon, required this.label});
  final IconData icon;
  final String   label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Home tab
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.profileCtrl,
    required this.onCreateSku,
    required this.onEditSku,
  });
  final ProfileController profileCtrl;
  final VoidCallback onCreateSku;
  final VoidCallback onEditSku;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (profileCtrl.isLoading) {
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
          ),
        );
      }

      if (profileCtrl.errorMessage != null) {
        return _HomeError(profileCtrl: profileCtrl);
      }

      final profile = profileCtrl.profile;
      final name = profile?.displayName ?? 'Seller';
      final avatarUrl = profile?.avatarUrl;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

      return RefreshIndicator(
        onRefresh: () => profileCtrl.fetchProfile(silent: true),
        color: AppColors.brandNavy,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandYellow,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.brandYellow.withOpacity(0.3),
                      backgroundImage:
                          avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null
                          ? CustomText(
                              initial,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandNavy,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Greeting
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CustomText(
                          'Welcome back',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 2),
                        CustomText(
                          name,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppColors.textPrimary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Notification bell
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      size: 22,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Welcome banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.brandYellow,
                      AppColors.brandYellow.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomText(
                            'Hi, $name!',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.brandNavy,
                          ),
                          const SizedBox(height: 4),
                          CustomText(
                            'Ready to sell today?',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: AppColors.brandNavy.withOpacity(0.6),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 26,
                        color: AppColors.brandNavy.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Quick actions — jump to the Stock tab to create a new SKU or
            // find & edit an existing one.
            _QuickActions(
              onCreateSku: onCreateSku,
              onEditSku: onEditSku,
            ),

            const SizedBox(height: 16),

            // Scan inventory entry point
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 20),
            //   child: GestureDetector(
            //     onTap: () => Navigator.of(context).push(
            //       MaterialPageRoute(
            //         builder: (_) => const ScanInventoryView(),
            //       ),
            //     ),
            //     child: Container(
            //       width: double.infinity,
            //       padding: const EdgeInsets.all(16),
            //       decoration: BoxDecoration(
            //         color: AppColors.white,
            //         borderRadius: BorderRadius.circular(16),
            //         border: Border.all(color: AppColors.inputBorder, width: 1),
            //         boxShadow: [
            //           BoxShadow(
            //             color: AppColors.brandNavy.withOpacity(0.04),
            //             blurRadius: 16,
            //             offset: const Offset(0, 4),
            //           ),
            //         ],
            //       ),
            //       child: Row(
            //         children: [
            //           Container(
            //             width: 44,
            //             height: 44,
            //             decoration: BoxDecoration(
            //               color: AppColors.accent.withOpacity(0.18),
            //               borderRadius: BorderRadius.circular(12),
            //             ),
            //             child: const Icon(
            //               Icons.qr_code_scanner_rounded,
            //               size: 22,
            //               color: AppColors.brandNavy,
            //             ),
            //           ),
            //           const SizedBox(width: 12),
            //           const Expanded(
            //             child: Column(
            //               crossAxisAlignment: CrossAxisAlignment.start,
            //               children: [
            //                 CustomText(
            //                   'Scan inventory',
            //                   fontSize: 15,
            //                   fontWeight: FontWeight.w800,
            //                   color: AppColors.textPrimary,
            //                 ),
            //                 SizedBox(height: 2),
            //                 CustomText(
            //                   'Scan barcodes to build your product list',
            //                   fontSize: 12,
            //                   fontWeight: FontWeight.w500,
            //                   color: AppColors.textSecondary,
            //                 ),
            //               ],
            //             ),
            //           ),
            //           const Icon(
            //             Icons.chevron_right_rounded,
            //             color: AppColors.textMuted,
            //           ),
            //         ],
            //       ),
            //     ),
            //   ),
            // ),

            const SizedBox(height: 32),
          ],
        ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions — Create new SKU / Edit existing SKU
// ─────────────────────────────────────────────────────────────────────────────

/// Two home-screen shortcuts into the warehouse SKU flow. Both jump to the
/// Stock tab's SKUs segment; "Create new SKU" also opens the New SKU dialog
/// there.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onCreateSku, required this.onEditSku});
  final VoidCallback onCreateSku;
  final VoidCallback onEditSku;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CustomText(
            'Quick actions',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.add_business_rounded,
                    title: 'Create new SKU',
                    subtitle: 'Add a warehouse SKU',
                    onTap: onCreateSku,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.edit_location_alt_rounded,
                    title: 'Edit existing SKU',
                    subtitle: 'Find & update a SKU',
                    onTap: onEditSku,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single tappable quick-action card — icon tile, title, subtitle.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.inputBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandNavy.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.brandYellow.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.brandNavy),
            ),
            const SizedBox(height: 12),
            CustomText(
              title,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            CustomText(
              subtitle,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: AppColors.textSecondary,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared error state for the Home tab — mirrors the Profile tab's error
/// card with a retry that re-fetches the seller profile.
class _HomeError extends StatelessWidget {
  const _HomeError({required this.profileCtrl});
  final ProfileController profileCtrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.vipps.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded, size: 28, color: AppColors.vipps),
            ),
            const SizedBox(height: 16),
            const CustomText(
              'Could not load home',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 6),
            CustomText(
              profileCtrl.errorMessage ?? '',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              textAlign: TextAlign.center,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => profileCtrl.fetchProfile(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.brandNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const CustomText(
                  'Try again',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile tab
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.profileCtrl});
  final ProfileController profileCtrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (profileCtrl.isLoading) {
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(AppColors.brandNavy),
          ),
        );
      }

      if (profileCtrl.errorMessage != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.vipps.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.wifi_off_rounded, size: 28, color: AppColors.vipps),
                ),
                const SizedBox(height: 16),
                const CustomText(
                  'Could not load profile',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 6),
                CustomText(
                  profileCtrl.errorMessage ?? '',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  textAlign: TextAlign.center,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => profileCtrl.fetchProfile(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const CustomText(
                      'Try again',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final profile = profileCtrl.profile;
      if (profile == null) return const SizedBox.shrink();

      return _ProfileContent(profile: profile, profileCtrl: profileCtrl);
    });
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.profile, required this.profileCtrl});
  final SellerProfile profile;
  final ProfileController profileCtrl;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: () => profileCtrl.fetchProfile(silent: true),
      color: AppColors.brandNavy,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: Column(
        children: [
          _ProfileHeader(profile: profile, profileCtrl: profileCtrl),
          const SizedBox(height: 56),
          // Name + business
          CustomText(
            profile.displayName,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 3),
          CustomText(
            profile.businessName,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 10),
          // Badges row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile.verified) _buildBadge(
                Icons.verified_rounded,
                'Verified',
                const Color(0xFF2E7D32),
              ),
              if (profile.verified) const SizedBox(width: 8),
              _buildStatusBadge(profile.approvalStatus),
            ],
          ),
          const SizedBox(height: 24),

          // Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Quick stats row
                _QuickStats(profile: profile),
                const SizedBox(height: 16),

                // Profile card thumbnail (editable)
                _CardThumbnailSection(
                  profile: profile,
                  profileCtrl: profileCtrl,
                ),
                const SizedBox(height: 16),

                // Contact details
                _SectionCard(
                  title: 'Contact Information',
                  icon: Icons.contact_mail_rounded,
                  children: [
                    _DetailTile(
                      icon: Icons.mail_outline_rounded,
                      title: 'Email',
                      subtitle: profile.email,
                    ),
                    _DetailTile(
                      icon: Icons.phone_outlined,
                      title: 'Phone',
                      subtitle: profile.phone,
                    ),
                  ],
                ),

                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'About the store',
                    icon: Icons.info_outline_rounded,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: CustomText(
                          profile.bio!,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.55,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],

                if (profile.socialLinks.activeLinks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SocialLinksSection(links: profile.socialLinks.activeLinks),
                ],

                const SizedBox(height: 24),

                // Logout
                _LogoutButton(),

                SizedBox(height: bottom + 16),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          CustomText(label, fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'ACTIVE';
    final color = isActive ? const Color(0xFF1565C0) : AppColors.vipps;
    final label = isActive ? 'Active account' : status;
    return _buildBadge(
      isActive ? Icons.check_circle_outline_rounded : Icons.pending_rounded,
      label,
      color,
    );
  }
}

/// Picks an image from the gallery and uploads it as the given profile
/// image [kind], surfacing the result through a snackbar.
Future<void> _pickAndUploadImage(
  BuildContext context,
  ProfileController ctrl,
  ProfileImageKind kind,
) async {
  // Guard against double-taps while an upload is already running.
  if (ctrl.uploadingImage != null) return;

  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 90,
  );
  if (picked == null) return;

  final ok = await ctrl.uploadProfileImage(kind: kind, filePath: picked.path);
  if (ok) {
    Get.snackbar('Updated', 'Image uploaded successfully');
  } else {
    Get.snackbar('Error', ctrl.errorMessage ?? 'Could not upload image');
  }
}

/// Small circular camera badge used to mark an image as editable.
class _CameraBadge extends StatelessWidget {
  const _CameraBadge({this.size = 30, this.iconSize = 16});
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white, width: 2),
      ),
      child: Icon(Icons.camera_alt_rounded, size: iconSize, color: AppColors.white),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.profileCtrl});
  final SellerProfile profile;
  final ProfileController profileCtrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Banner / cover (tap to change)
          GestureDetector(
            onTap: () => _pickAndUploadImage(
              context,
              profileCtrl,
              ProfileImageKind.banner,
            ),
            child: Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                image: profile.bannerUrl != null
                    ? DecorationImage(
                        image: NetworkImage(profile.bannerUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  // Gradient overlay for legibility
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.0),
                            Colors.black.withOpacity(0.25),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Empty hint when no cover photo
                  if (profile.bannerUrl == null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 26, color: AppColors.brandNavy.withOpacity(0.7)),
                          const SizedBox(height: 4),
                          CustomText(
                            'Add cover photo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandNavy.withOpacity(0.7),
                          ),
                        ],
                      ),
                    ),
                  // Cover camera badge (top-left)
                  const Positioned(top: 12, left: 16, child: _CameraBadge()),
                  // Uploading overlay
                  Obx(
                    () => profileCtrl.isUploading(ProfileImageKind.banner)
                        ? Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.35),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation(AppColors.white),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          // Edit details button (top-right)
          Positioned(
            top: 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditProfileView(profile: profile),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandNavy.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded,
                        size: 15, color: AppColors.brandNavy),
                    SizedBox(width: 5),
                    CustomText(
                      'Edit',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Avatar (tap to change)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _pickAndUploadImage(
                  context,
                  profileCtrl,
                  ProfileImageKind.avatar,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.white,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandNavy.withOpacity(0.12),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.brandYellow.withOpacity(0.3),
                        backgroundImage: profile.avatarUrl != null
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: profile.avatarUrl == null
                            ? CustomText(
                                profile.displayName.isNotEmpty
                                    ? profile.displayName[0].toUpperCase()
                                    : 'S',
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandNavy,
                              )
                            : null,
                      ),
                    ),
                    // Camera badge on avatar corner
                    const Positioned(
                      bottom: 2,
                      right: 2,
                      child: _CameraBadge(size: 28, iconSize: 14),
                    ),
                    // Uploading overlay
                    Positioned.fill(
                      child: Obx(
                        () => profileCtrl.isUploading(ProfileImageKind.avatar)
                            ? Container(
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withOpacity(0.35),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor:
                                          AlwaysStoppedAnimation(AppColors.white),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable "Profile card thumbnail" block. Shows the current thumbnail or
/// an empty upload placeholder, and uploads a new one on tap.
class _CardThumbnailSection extends StatelessWidget {
  const _CardThumbnailSection({
    required this.profile,
    required this.profileCtrl,
  });
  final SellerProfile profile;
  final ProfileController profileCtrl;

  @override
  Widget build(BuildContext context) {
    final url = profile.profileCardThumbnailUrl;
    return _SectionCard(
      title: 'Profile card thumbnail',
      icon: Icons.image_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GestureDetector(
            onTap: () => _pickAndUploadImage(
              context,
              profileCtrl,
              ProfileImageKind.cardThumbnail,
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.inputBorder, width: 1),
                  image: url != null
                      ? DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    if (url == null)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 28, color: AppColors.textMuted),
                            SizedBox(height: 6),
                            CustomText(
                              'Add thumbnail',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    const Positioned(
                      bottom: 10,
                      right: 10,
                      child: _CameraBadge(),
                    ),
                    Positioned.fill(
                      child: Obx(
                        () => profileCtrl
                                .isUploading(ProfileImageKind.cardThumbnail)
                            ? Container(
                                color: Colors.black.withOpacity(0.35),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor:
                                        AlwaysStoppedAnimation(AppColors.white),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.profile});
  final SellerProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.brandYellow.withOpacity(0.35),
            AppColors.brandYellow.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandYellow.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          _StatItem(icon: Icons.store_rounded, label: 'Type', value: profile.sellerType),
          _verticalDivider(),
          _StatItem(
            icon: Icons.verified_user_rounded,
            label: 'Status',
            value: profile.approvalStatus == 'ACTIVE' ? 'Active' : profile.approvalStatus,
          ),
          _verticalDivider(),
          _StatItem(
            icon: Icons.shield_rounded,
            label: 'Verified',
            value: profile.verified ? 'Yes' : 'No',
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      height: 32,
      width: 1,
      color: AppColors.brandNavy.withOpacity(0.1),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.brandNavy.withOpacity(0.6)),
          const SizedBox(height: 6),
          CustomText(
            value,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 2),
          CustomText(
            label,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.brandYellow.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: AppColors.brandNavy),
                ),
                const SizedBox(width: 10),
                CustomText(
                  title,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  title,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 1),
                CustomText(
                  subtitle,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialLinksSection extends StatelessWidget {
  const _SocialLinksSection({required this.links});
  final List<MapEntry<String, String>> links;

  IconData _iconFor(String name) {
    switch (name) {
      case 'Website':   return Icons.language_rounded;
      case 'Instagram': return Icons.camera_alt_rounded;
      case 'Facebook':  return Icons.facebook_rounded;
      case 'YouTube':   return Icons.play_circle_rounded;
      case 'LinkedIn':  return Icons.work_outline_rounded;
      case 'TikTok':    return Icons.music_note_rounded;
      default:          return Icons.link_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Social links',
      icon: Icons.share_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: links.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.inputFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _iconFor(entry.key),
                    size: 20,
                    color: AppColors.brandNavy,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final authCtrl = getOrPut(() => AuthController());
        await authCtrl.logout();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginView()),
            (route) => false,
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.vipps.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.vipps.withOpacity(0.18), width: 1),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 18, color: AppColors.vipps),
            SizedBox(width: 8),
            CustomText(
              'Log out',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.vipps,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.tabs,
    required this.onTap,
  });

  final int                index;
  final List<_TabSpec>     tabs;
  final ValueChanged<int>  onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(
          top: BorderSide(color: AppColors.inputBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final t        = tabs[i];
              final selected = i == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          t.icon,
                          size: 22,
                          color: selected
                              ? AppColors.brandNavy
                              : AppColors.textMuted,
                        ),
                        const SizedBox(height: 4),
                        CustomText(
                          t.label,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.brandNavy
                              : AppColors.textMuted,
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 3,
                          width: selected ? 22 : 0,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
