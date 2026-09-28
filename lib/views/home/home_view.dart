import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:url_launcher/url_launcher.dart';
// import 'package:mobile_scanner/mobile_scanner.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/inventory_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../controllers/products_nav_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/stock_nav_controller.dart';
import '../../controllers/stream_controller.dart';
import '../../core/config/get_or_put.dart';
import '../../core/localization/translation_keys.dart';
import '../../view_models/view_models/language_view_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/social_links.dart';
import '../../core/widgets/branded_loading_view.dart';
import '../../core/widgets/branded_refresh_indicator.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/custom_text.dart';
import '../../core/widgets/image_pick_crop.dart';
import '../../models/seller_dashboard.dart';
import '../../models/seller_profile.dart';
import '../auth/login_view.dart';
import '../notifications/notifications_view.dart';
import '../orders/orders_view.dart';
import '../products/manage_products/manage_products_view.dart';
import '../profile/edit_profile_view.dart';
// import '../scanner/barcode_scanner_view.dart';
// import '../scan_inventory/scan_inventory_view.dart';
import '../stock/stock_view.dart';
import '../stream/create_stream_view.dart';
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
  final _dashboardCtrl  = getOrPut(() => DashboardController());
  // Permanent: the bell badge has to survive tab switches and the inbox screen
  // being popped, and the same instance backs both.
  final _notificationCtrl =
      getOrPut(() => NotificationController(), permanent: true);
  // late final AuctionController _auctionController =
  // getOrPut(() => AuctionController());
  // Holds translation *keys*, not text: the list is `const`, so `.tr` can't run
  // here. It resolves in `_TabSpec.label` at paint time, which is also what
  // makes the bar re-label itself when the seller switches language.
  static const _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_rounded,        labelKey: TKeys.navHome),
    _TabSpec(icon: Icons.connected_tv_outlined,     labelKey: TKeys.navStreams),
    _TabSpec(icon: Icons.live_tv_outlined, labelKey: TKeys.navProducts),
    _TabSpec(icon: Icons.inventory_2_rounded, labelKey: TKeys.navStock),
    _TabSpec(icon: Icons.person_rounded,      labelKey: TKeys.navProfile),
  ];

  @override
  void initState() {
    super.initState();
    // Badge only — the inbox itself loads its rows when it opens.
    _notificationCtrl.fetchUnreadCount();
  }

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

  /// Home "See products" quick action — opens the Products tab already showing
  /// its "My Products" segment.
  void _goToMyProducts() {
    getOrPut(() => ProductsNavController()).goToMyProducts();
    // Same reload the bottom-nav Products tab does.
    _streamListCtrl.fetchStreamsByStatus(status: 'SCHEDULED');
    setState(() => _index = 2);
  }

  /// Home "Configure streams" quick action — switches to the Streams tab.
  void _goToStreams() {
    _streamListCtrl.fetchStreams(refresh: true);
    setState(() => _index = 1);
  }

  /// Home "Create shipment" quick action — opens the new-stream form. On a
  /// successful create the Streams tab is refreshed and brought forward, so the
  /// seller lands on the stream they just made.
  Future<void> _createShipment() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStreamView()),
    );
    if (!mounted || created != true) return;
    _goToStreams();
  }

  /// Android hardware / gesture back on the home shell. From any other tab we
  /// just fall back to Home; from Home itself there is nowhere left to go, so
  /// confirm before closing the app.
  Future<void> _handleBack() async {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }

    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.exitTitle.tr,
      message: TKeys.exitBody.tr,
      confirmLabel: TKeys.exitConfirm.tr,
      cancelLabel: TKeys.stay.tr,
      icon: Icons.exit_to_app_rounded,
    );
    if (confirmed) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: _index == 0
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  statusBarBrightness: Brightness.dark,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.dark,
                  statusBarBrightness: Brightness.light,
                ),
          // White is the ground the whole shell sits on. The navy is confined
          // to the status-bar strip below — painting it behind the body meant
          // an overscroll at the bottom of Home (bouncing physics) pulled the
          // content up off a near-black backdrop.
          child: ColoredBox(
            color: AppColors.white,
            child: Column(
              children: [
                // The Home hero runs to the top of the screen, so the strip
                // behind the status bar is painted navy (with light icons) on
                // that tab only; every other tab keeps the white shell.
                Container(
                  height: MediaQuery.paddingOf(context).top,
                  color: _index == 0 ? AppColors.brandNavy : AppColors.white,
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: IndexedStack(
            index: _index,
            children: [
              _HomeTab(
                profileCtrl: _profileCtrl,
                notificationCtrl: _notificationCtrl,
                dashboardCtrl: _dashboardCtrl,
                onCreateSku: () => _goToStockSkus(create: true),
                onEditSku: () => _goToStockSkus(),
                onSeeProducts: _goToMyProducts,
                onCreateShipment: _createShipment,
                onConfigureStreams: _goToStreams,
              ),
              const StreamListView(),
              const ManageProductView(),
              const StockView(),
              _ProfileTab(profileCtrl: _profileCtrl),
            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _BottomBar(
          index: _index,
          tabs:  _tabs,
          onTap: (i) {
            if (i == 1) {
              // Streams tab: reload from the API every time it's opened.
              _streamListCtrl.fetchStreams(refresh: true);
            }else if(i==2){
              // Products tab → "Assign to live": re-sync the scheduled streams
              // in the background on every tap, so a stream created or edited
              // elsewhere shows up in the dropdown. Silent on purpose — no
              // spinner over the list the seller is looking at, and a failed
              // sync leaves the last good data in place rather than throwing
              // an error state at them.
              unawaited(_streamListCtrl.fetchStreamsByStatus(
                status: 'SCHEDULED',
                refresh: true,
                silent: true,
              ));
            }else if(i==3){
              // Stock tab: (re)load the warehouse overview stats every time
              // it's opened. Inside the IndexedStack the controller's onInit
              // fires only once at startup, so this retries an earlier
              // failed/missing call. getOrPut returns the same
              // InventoryController the Stock section is already observing.
              getOrPut(() => InventoryController()).fetchStats();
            }
            setState(() => _index = i);
          },
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({required this.icon, required this.labelKey});
  final IconData icon;
  final String   labelKey;

  /// Resolved on read so a language switch re-labels the bar.
  String get label => labelKey.tr;
}

// ─────────────────────────────────────────────────────────────────────────────
// Home tab design tokens
// ─────────────────────────────────────────────────────────────────────────────

/// Page canvas behind the Home tab's cards. A hair off white so the white cards
/// read as raised surfaces instead of dissolving into the background — the same
/// value the create-stream form uses, so the two screens feel related.
const Color _canvas = Color(0xFFF6F7F9);

/// Soft tones for the small icon tile on a card. The brand frame stays navy +
/// yellow (hero, primary CTA, bottom bar); these only tint the square behind an
/// icon, so a wall of cards stays scannable instead of reading as one yellow
/// block. Foreground/background are fixed pairs, each checked for contrast.
class _Tone {
  const _Tone(this.fg, this.bg);
  final Color fg;
  final Color bg;

  static const amber = _Tone(Color(0xFF8A6A00), Color(0xFFFFF3CC));
  static const navy = _Tone(Color(0xFF0A1420), Color(0xFFE7EBF1));
  static const blue = _Tone(Color(0xFF1E63E9), Color(0xFFE3ECFF));
  static const green = _Tone(Color(0xFF1B7F4B), Color(0xFFE0F5EA));
  static const violet = _Tone(Color(0xFF6B3FD4), Color(0xFFEDE6FF));
  static const coral = _Tone(Color(0xFFC94A1E), Color(0xFFFFE8E0));
}

/// The rounded square holding a card's icon, tinted by [tone].
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.tone,
    this.size = 42,
    this.iconSize = 21,
  });
  final IconData icon;
  final _Tone tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      child: Icon(icon, size: iconSize, color: tone.fg),
    );
  }
}

/// Section title with a short yellow rule in front of it, so the eye can find
/// where one block of the Home tab ends and the next begins while scrolling.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: subtitle == null ? 18 : 34,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: AppColors.brandYellow,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                title,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppColors.textPrimary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                CustomText(
                  subtitle!,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: AppColors.textMuted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

/// The soft lift under every card on this tab — one definition so the whole
/// page shares a single light source.
const List<BoxShadow> _cardShadow = [
  BoxShadow(
    color: Color(0x0F0A1420),
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Home tab
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.profileCtrl,
    required this.notificationCtrl,
    required this.dashboardCtrl,
    required this.onCreateSku,
    required this.onEditSku,
    required this.onSeeProducts,
    required this.onCreateShipment,
    required this.onConfigureStreams,
  });
  final ProfileController profileCtrl;
  final NotificationController notificationCtrl;
  final DashboardController dashboardCtrl;
  final VoidCallback onCreateSku;
  final VoidCallback onEditSku;
  final VoidCallback onSeeProducts;
  final VoidCallback onCreateShipment;
  final VoidCallback onConfigureStreams;

  /// Pull-to-refresh reloads the profile and the dashboard together — the two
  /// APIs behind everything on this tab.
  Future<void> _refresh() async {
    await Future.wait([
      profileCtrl.fetchProfile(silent: true),
      dashboardCtrl.fetchDashboard(silent: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (profileCtrl.isLoading) {
        return const BrandedLoadingView();
      }

      if (profileCtrl.errorMessage != null) {
        return _HomeError(profileCtrl: profileCtrl);
      }

      final profile = profileCtrl.profile;
      final name = profile?.displayName ?? TKeys.sellerLabel.tr;
      final avatarUrl = profile?.avatarUrl;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

      return BrandedRefreshIndicator(
        onRefresh: _refresh,
        // The canvas has to cover the viewport even when the content is short,
        // or a white band shows under the last card.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: ColoredBox(
            color: _canvas,
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Navy hero — identity, the day's headline numbers and the one
            // action sellers open this app to take.
            _HomeHero(
              name: name,
              initial: initial,
              avatarUrl: avatarUrl,
              notificationCtrl: notificationCtrl,
              dashboardCtrl: dashboardCtrl,
              onCreateShipment: onCreateShipment,
              onConfigureStreams: onConfigureStreams,
            ),

            const SizedBox(height: 24),

            // Store overview for the selected month, from
            // GET /api/v1/seller/dashboard.
            _DashboardSection(controller: dashboardCtrl),

            const SizedBox(height: 26),

            // Quick actions — shortcuts into products, streams and the
            // warehouse SKU flow.
            _QuickActions(
              onCreateSku: onCreateSku,
              onEditSku: onEditSku,
              onSeeProducts: onSeeProducts,
              onConfigureStreams: onConfigureStreams,
            ),

            const SizedBox(height: 10),

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
            //         border: Border.all(color: AppColors.borderGrey, width: 1),
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

            const SizedBox(height: 16),

            // What you can do — overview of the app's selling features.
            const _FeaturesSection(),

            const SizedBox(height: 26),

            // About the app
            const _AboutCard(),

            const SizedBox(height: 36),
          ],
            ),
          ),
        ),
        ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero — the navy card the Home tab opens on
// ─────────────────────────────────────────────────────────────────────────────

/// Greeting, headline numbers and the primary action, on one navy panel that
/// runs to the top of the screen.
///
/// The three chips repeat figures the dashboard below also shows, deliberately:
/// they answer "is anything live right now?" without the seller scrolling. They
/// appear only once the dashboard has loaded, so the hero never shows zeros
/// that are really "not known yet".
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.name,
    required this.initial,
    required this.avatarUrl,
    required this.notificationCtrl,
    required this.dashboardCtrl,
    required this.onCreateShipment,
    required this.onConfigureStreams,
  });

  final String name;
  final String initial;
  final String? avatarUrl;
  final NotificationController notificationCtrl;
  final DashboardController dashboardCtrl;
  final VoidCallback onCreateShipment;
  final VoidCallback onConfigureStreams;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1420), Color(0xFF17293E)],
          ),
        ),
        child: Stack(
          children: [
            // Two soft yellow washes give the flat navy some depth. Clipped by
            // the ClipRRect above, so they never spill past the panel.
            const Positioned(
              top: -70,
              right: -50,
              child: _HeroGlow(size: 190, color: Color(0x26FFD84D)),
            ),
            const Positioned(
              bottom: -90,
              left: -60,
              child: _HeroGlow(size: 200, color: Color(0x14FFD84D)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                          radius: 21,
                          backgroundColor: const Color(0xFF2A3B52),
                          backgroundImage:
                              avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                          child: avatarUrl == null
                              ? CustomText(
                                  initial,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandYellow,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CustomText(
                              TKeys.welcomeBack.tr,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              color: const Color(0xB3FFFFFF),
                            ),
                            const SizedBox(height: 2),
                            CustomText(
                              name,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: AppColors.white,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _NotificationBell(
                        controller: notificationCtrl,
                        onDark: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  CustomText(
                    TKeys.readyToSell.tr,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.white,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  CustomText(
                    TKeys.readyToSellBody.tr,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: Color(0x99FFFFFF),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroPrimaryButton(
                          icon: Icons.play_circle_fill_rounded,
                          label: TKeys.createShipment.tr,
                          onTap: onCreateShipment,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _HeroGhostButton(
                        icon: Icons.connected_tv_outlined,
                        tooltip: TKeys.myStreams.tr,
                        onTap: onConfigureStreams,
                      ),
                    ],
                  ),
                  Obx(() {
                    final stats = dashboardCtrl.dashboard?.stats;
                    if (stats == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HeroStatChip(
                              label: TKeys.liveNow.tr,
                              value: '${stats.liveStreams}',
                              highlight: stats.liveStreams > 0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HeroStatChip(
                              label: TKeys.planned.tr,
                              value: '${stats.scheduledStreams}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HeroStatChip(
                              label: TKeys.followers.tr,
                              value: '${stats.followers}',
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A blurred-looking circle of colour behind the hero content.
class _HeroGlow extends StatelessWidget {
  const _HeroGlow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, const Color(0x00FFD84D)]),
      ),
    );
  }
}

/// The hero's yellow call to action.
class _HeroPrimaryButton extends StatelessWidget {
  const _HeroPrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandYellow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.brandNavy),
              const SizedBox(width: 8),
              Flexible(
                child: CustomText(
                  label,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square outline button beside the hero CTA — icon only, so it stays out of
/// the primary action's way on narrow screens.
class _HeroGhostButton extends StatelessWidget {
  const _HeroGhostButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x26FFFFFF), width: 1),
            ),
            child: Icon(icon, size: 22, color: AppColors.white),
          ),
        ),
      ),
    );
  }
}

/// One translucent figure inside the hero. [highlight] turns the chip yellow —
/// used for "Live now" when something actually is.
class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: highlight ? const Color(0x33FFD84D) : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? const Color(0x66FFD84D) : const Color(0x1FFFFFFF),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highlight) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.brandYellow,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: CustomText(
                  value,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: highlight ? AppColors.brandYellow : AppColors.white,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          CustomText(
            label.toUpperCase(),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: const Color(0x99FFFFFF),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification bell — home header entry point into the inbox
// ─────────────────────────────────────────────────────────────────────────────

/// The header bell. Unchanged from its static version until there is something
/// unread, at which point it carries a count badge fed by
/// `GET /api/notifications/unread-count`. Tapping opens [NotificationsView] and
/// re-syncs the badge on the way back — the inbox may have marked rows read.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.controller, this.onDark = false});
  final NotificationController controller;

  /// Set on the navy hero: the tile turns translucent-white and the badge's
  /// ring picks up the panel colour instead of the page's white.
  final bool onDark;

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsView()),
    );
    await controller.fetchUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: onDark ? const Color(0x1AFFFFFF) : AppColors.inputFill,
                borderRadius: BorderRadius.circular(13),
                border: onDark
                    ? Border.all(color: const Color(0x26FFFFFF), width: 1)
                    : null,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: onDark ? AppColors.white : AppColors.brandNavy,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Obx(() {
                final unread = controller.unreadCount;
                if (unread <= 0) return const SizedBox.shrink();
                return Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.vipps,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: onDark ? const Color(0xFF13253A) : AppColors.white,
                      width: 1.5,
                    ),
                  ),
                  child: CustomText(
                    unread > 99 ? '99+' : '$unread',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions — shortcuts into products, streams and the warehouse
// ─────────────────────────────────────────────────────────────────────────────

/// Home-screen shortcuts, mirroring the seller web dashboard's quick actions.
///
/// The primary action ("Create shipment") now lives in the hero, so this block
/// is purely the secondary grid: "See products" and "Configure streams" switch
/// bottom-nav tabs, the SKU pair jumps into the Stock tab's SKUs segment, and
/// Orders pushes its own screen.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onCreateSku,
    required this.onEditSku,
    required this.onSeeProducts,
    required this.onConfigureStreams,
  });
  final VoidCallback onCreateSku;
  final VoidCallback onEditSku;
  final VoidCallback onSeeProducts;
  final VoidCallback onConfigureStreams;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: TKeys.quickActions.tr,
            subtitle: TKeys.quickActionsSub.tr,
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.inventory_rounded,
                    tone: _Tone.violet,
                    title: TKeys.seeProducts.tr,
                    subtitle: TKeys.seeProductsSub.tr,
                    onTap: onSeeProducts,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.connected_tv_outlined,
                    tone: _Tone.blue,
                    title: TKeys.configureStreams.tr,
                    subtitle: TKeys.configureStreamsSub.tr,
                    onTap: onConfigureStreams,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.add_business_rounded,
                    tone: _Tone.green,
                    title: TKeys.createNewSku.tr,
                    subtitle: TKeys.createNewSkuSub.tr,
                    onTap: onCreateSku,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.edit_location_alt_rounded,
                    tone: _Tone.amber,
                    title: TKeys.editExistingSku.tr,
                    subtitle: TKeys.editExistingSkuSub.tr,
                    onTap: onEditSku,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Orders — full width under the SKU pair, since it opens its own
          // screen rather than jumping to a bottom-nav tab.
          _QuickActionRow(
            icon: Icons.receipt_long_rounded,
            tone: _Tone.coral,
            title: TKeys.ordersLabel.tr,
            subtitle: TKeys.ordersSub.tr,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrdersView()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared shell for the tappable cards on this tab — white surface, hairline
/// border, soft lift, and a Material ink ripple so a tap is acknowledged.
class _TapCard extends StatelessWidget {
  const _TapCard({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: _cardShadow,

      ),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderGrey, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width quick action — icon tile, title, subtitle and a chevron. Used for
/// shortcuts that push a screen instead of switching bottom-nav tabs.
class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapCard(
      onTap: onTap,
      child: Row(
        children: [
          _IconTile(icon: icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  title,
                  fontSize: 14.5,
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
                  height: 1.3,
                  color: AppColors.textSecondary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// A single tappable quick-action card — icon tile, title, subtitle.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, tone: tone),
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
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard — GET /api/v1/seller/dashboard[?month=YYYY-MM]
// ─────────────────────────────────────────────────────────────────────────────

/// Store overview for one calendar month: headline counters, commission rates,
/// stream analytics, product status and followers — the mobile port of the
/// seller web dashboard.
///
/// The month menu in the top-right is fed by `availableMonths` from the same
/// response, and picking one re-runs the call with `?month=YYYY-MM`. Months are
/// calendar months (API bounds them in UTC, displayed Europe/Oslo).
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Every observable this section reacts to has to be read here, inside the
      // Obx builder — a child widget's build runs outside its tracking scope.
      final data = controller.dashboard;
      final loading = controller.isLoading;
      final error = controller.errorMessage;
      final month = controller.selectedMonth ?? '';
      final monthLong = month.isEmpty ? '' : formatYearMonthLong(month);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              title: TKeys.dashboardTitle.tr,
              subtitle: TKeys.dashboardSub.tr,
              trailing: controller.availableMonths.isEmpty
                  ? null
                  : _MonthPicker(
                      months: controller.availableMonths,
                      selected: month,
                      busy: controller.isSwitchingMonth,
                      onSelected: controller.selectMonth,
                    ),
            ),
            const SizedBox(height: 14),
            if (data == null)
              _DashboardPlaceholder(
                loading: loading,
                error: error,
                onRetry: () => controller.fetchDashboard(),
              )
            else ...[
              // Headline counters — 2×2 on a phone instead of the web's 4-up.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.inventory_2_rounded,
                        tone: _Tone.violet,
                        label: TKeys.productsLabel.tr,
                        value: '${data.stats.totalProducts}',
                        caption:
                            '${data.stats.availableProducts} ${TKeys.availableInStore.tr}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.live_tv_rounded,
                        tone: _Tone.coral,
                        label: TKeys.shipmentsLabel.tr,
                        value: '${data.stats.totalStreams}',
                        caption: '${data.stats.liveStreams} ${TKeys.liveLower.tr} · '
                            '${data.stats.scheduledStreams} ${TKeys.plannedLower.tr}'
                            '${monthLong.isEmpty ? '' : ' ${TKeys.inMonth.tr} $monthLong'}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.shopping_cart_rounded,
                        tone: _Tone.blue,
                        label: TKeys.ordersLabel.tr,
                        value: '${data.stats.totalOrders}',
                        caption: '${data.stats.paidOrders} ${TKeys.completedPayments.tr}'
                            '${monthLong.isEmpty ? '' : ' ${TKeys.inMonth.tr} $monthLong'}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.payments_rounded,
                        tone: _Tone.green,
                        label: TKeys.turnoverLabel.tr,
                        value: _formatMoney(data.stats.revenue),
                        caption: TKeys.paidSalesVolume.tr +
                            (monthLong.isEmpty ? '' : ' ${TKeys.inMonth.tr} $monthLong'),
                      ),
                    ),
                  ],
                ),
              ),
              if (data.commission?.auctionDisplay != null ||
                  data.commission?.offerDisplay != null) ...[
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (data.commission?.auctionDisplay != null)
                        Expanded(
                          child: _StatCard(
                            icon: Icons.trending_up_rounded,
                            tone: _Tone.navy,
                            label: TKeys.auctionCommission.tr,
                            value: data.commission!.auctionDisplay!,
                            caption: TKeys.postedByAdmin.tr,
                          ),
                        ),
                      if (data.commission?.auctionDisplay != null &&
                          data.commission?.offerDisplay != null)
                        const SizedBox(width: 12),
                      if (data.commission?.offerDisplay != null)
                        Expanded(
                          child: _StatCard(
                            icon: Icons.trending_up_rounded,
                            tone: _Tone.navy,
                            label: TKeys.biddingCommittee.tr,
                            value: data.commission!.offerDisplay!,
                            caption: TKeys.postedByAdmin.tr,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _StreamAnalyticsCard(stats: data.stats, monthLong: monthLong),
              const SizedBox(height: 12),
              _ProductStatusCard(stats: data.stats),
              const SizedBox(height: 12),
              _FollowersCard(followers: data.stats.followers),
            ],
          ],
        ),
      );
    });
  }
}

/// `2810.41` → `2 810 kr`. Rounded to whole kroner with space-separated
/// thousands, matching the web dashboard's turnover card.
String _formatMoney(double value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${rounded < 0 ? '-' : ''}$buffer kr';
}

/// Loading / error / empty stand-in for the dashboard cards. Keeps the section
/// header (and its month menu) on screen while the body sorts itself out.
class _DashboardPlaceholder extends StatelessWidget {
  const _DashboardPlaceholder({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderGrey, width: 1),
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : Column(
              children: [
                const Icon(
                  Icons.insights_rounded,
                  size: 28,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 10),
                CustomText(
                  error ?? TKeys.noDashboardData.tr,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  textAlign: TextAlign.center,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomText(
                      TKeys.tryAgain.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The period selector — a chip that opens a menu of the months the API says
/// this seller has data for, newest first.
class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.months,
    required this.selected,
    required this.busy,
    required this.onSelected,
  });

  final List<String> months;
  final String selected;
  final bool busy;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !busy,
      onSelected: onSelected,
      tooltip: TKeys.selectMonth.tr,
      color: AppColors.white,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(maxHeight: 320, minWidth: 150),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => months.map((m) {
        final isSelected = m == selected;
        return PopupMenuItem<String>(
          value: m,
          height: 42,
          child: Row(
            children: [
              Expanded(
                child: CustomText(
                  formatYearMonth(m),
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? AppColors.brandNavy
                      : AppColors.textSecondary,
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.brandNavy,
                ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: AppColors.brandNavy,
              ),
            const SizedBox(width: 7),
            CustomText(
              selected.isEmpty ? TKeys.periodLabel.tr : formatYearMonth(selected),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// One headline counter — icon tile, label, big value and a caption line.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final _Tone tone;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey, width: 1),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, tone: tone, size: 38, iconSize: 19),
          const SizedBox(height: 12),
          CustomText(
            label.toUpperCase(),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          CustomText(
            value,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          CustomText(
            caption,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// "Stream analytics" — average broadcast length and average viewers for the
/// selected month (the web's "Sendeanalyse" panel).
class _StreamAnalyticsCard extends StatelessWidget {
  const _StreamAnalyticsCard({required this.stats, required this.monthLong});

  final DashboardStats stats;
  final String monthLong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey, width: 1),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconTile(
                icon: Icons.trending_up_rounded,
                tone: _Tone.blue,
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomText(
                  monthLong.isEmpty
                      ? TKeys.streamAnalyticsCaps.tr
                      : '${TKeys.streamAnalyticsCaps.tr} ($monthLong)',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.textPrimary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MetricLine(
            label: TKeys.averageDuration.tr,
            value: '${stats.averageStreamDuration.round()}',
            unit: TKeys.minutesUnit.tr,
          ),
          const SizedBox(height: 12),
          _MetricLine(
            label: TKeys.averageViewers.tr,
            value: '${stats.averageViewers.round()}',
            unit: TKeys.perStreamUnit.tr,
          ),
        ],
      ),
    );
  }
}

/// A label above a big number with a small trailing unit.
class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          label.toUpperCase(),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            CustomText(
              value,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 5),
            CustomText(
              unit,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Product status" — the available / sold split as a bar plus the two counts.
class _ProductStatusCard extends StatelessWidget {
  const _ProductStatusCard({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.availableProducts + stats.soldProducts;
    // Nothing to split → an empty track rather than a divide-by-zero.
    final soldShare = total == 0 ? 0.0 : stats.soldProducts / total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey, width: 1),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconTile(
                icon: Icons.check_circle_rounded,
                tone: _Tone.green,
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomText(
                  TKeys.productStatusCaps.tr,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.textPrimary,
                ),
              ),
              // The share the bar is filled to, spelled out — a bar alone
              // leaves the seller estimating.
              CustomText(
                '${(soldShare * 100).round()}% ${TKeys.soldLower.tr}',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              // Grows out from empty on first paint, so the split reads as a
              // measurement rather than a static graphic.
              tween: Tween(begin: 0, end: soldShare),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                backgroundColor: AppColors.inputFill,
                valueColor: const AlwaysStoppedAnimation(AppColors.brandYellow),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricLine(
                  label: TKeys.availableLabel.tr,
                  value: '${stats.availableProducts}',
                  unit: total == 1 ? TKeys.productUnitSingular.tr : TKeys.productUnitPlural.tr,
                ),
              ),
              Expanded(
                child: _MetricLine(
                  label: TKeys.soldLabel.tr,
                  value: '${stats.soldProducts}',
                  unit: TKeys.thisMonthLower.tr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Follower count for the store — the web's followers panel, minus its
/// "View public profile" button (the app has no public storefront screen).
class _FollowersCard extends StatelessWidget {
  const _FollowersCard({required this.followers});

  final int followers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGrey, width: 1),
        boxShadow: _cardShadow,
      ),
      child: Row(
        children: [
          const _IconTile(
            icon: Icons.people_alt_rounded,
            tone: _Tone.amber,
            size: 44,
            iconSize: 21,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  '$followers',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                ),
                CustomText(
                  TKeys.followersCaps.tr,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Features — a quick tour of what Seller Squad lets sellers do
// ─────────────────────────────────────────────────────────────────────────────

/// Static overview of the app's core capabilities, shown on the Home tab so
/// sellers can see at a glance everything Seller Squad offers. Mirrors the
/// bottom-nav destinations (Streams, Live, Stock, Products).
class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  // A getter, not a `static const` list: `.tr` has to re-run whenever the
  // seller switches language.
  static List<_FeatureSpec> get _features => <_FeatureSpec>[
    _FeatureSpec(
      icon: Icons.live_tv_outlined,
      tone: _Tone.coral,
      title: TKeys.goLive.tr,
      subtitle: TKeys.goLiveSub.tr,
    ),
    _FeatureSpec(
      icon: Icons.connected_tv_outlined,
      tone: _Tone.blue,
      title: TKeys.planYourStreams.tr,
      subtitle: TKeys.planYourStreamsSub.tr,
    ),
    _FeatureSpec(
      icon: Icons.inventory_2_rounded,
      tone: _Tone.green,
      title: TKeys.manageYourStock.tr,
      subtitle: TKeys.manageYourStockSub.tr,
    ),
    _FeatureSpec(
      icon: Icons.shopping_bag_rounded,
      tone: _Tone.violet,
      title: TKeys.buildYourCatalog.tr,
      subtitle: TKeys.buildYourCatalogSub.tr,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            title: TKeys.whatYouCanDo.tr,
            subtitle: TKeys.whatYouCanDoSub.tr,
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderGrey, width: 1),
              boxShadow: _cardShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < _features.length; i++) ...[
                  _FeatureTile(spec: _features[i]),
                  if (i != _features.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 68,
                      endIndent: 16,
                      color: AppColors.borderGrey,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureSpec {
  const _FeatureSpec({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final _Tone tone;
  final String title;
  final String subtitle;
}

/// A single row inside the features card — icon tile, title and subtitle.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.spec});
  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: spec.icon, tone: spec.tone, size: 40, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  spec.title,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(height: 3),
                CustomText(
                  spec.subtitle,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// About — short description of the app
// ─────────────────────────────────────────────────────────────────────────────

/// Brief "About Seller Squad" blurb that introduces the app to sellers.
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A1420), Color(0xFF1B3050)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                top: -60,
                right: -40,
                child: _HeroGlow(size: 160, color: Color(0x1FFFD84D)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0x40FFD84D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 20,
                            color: AppColors.brandYellow,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomText(
                            TKeys.aboutSellerSquad.tr,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    CustomText(
                      TKeys.aboutSellerSquadBody.tr,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.55,
                      color: const Color(0xD9FFFFFF),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
            CustomText(
              TKeys.couldNotLoadHome.tr,
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
                child: CustomText(
                  TKeys.tryAgain.tr,
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
        return const BrandedLoadingView();
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
                CustomText(
                  TKeys.couldNotLoadProfile.tr,
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
                    child: CustomText(
                      TKeys.tryAgain.tr,
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
    return BrandedRefreshIndicator(
      onRefresh: () => profileCtrl.fetchProfile(silent: true),
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: Column(
        children: [
          _ProfileHeader(profile: profile, profileCtrl: profileCtrl),
          // The header already ends flush with the bottom of the avatar, so
          // this is pure breathing room — 56 left the name floating a whole
          // avatar's width away from the face it belongs to.
          const SizedBox(height: 14),
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
                Icons.check_circle_rounded,
                TKeys.verifiedLabel.tr,
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
                  title: TKeys.contactInformation.tr,
                  icon: Icons.contact_mail_rounded,
                  children: [
                    _DetailTile(
                      icon: Icons.mail_outline_rounded,
                      title: TKeys.emailLabel.tr,
                      subtitle: profile.email,
                    ),
                    _DetailTile(
                      icon: Icons.phone_outlined,
                      title: TKeys.phoneLabel.tr,
                      subtitle: profile.phone,
                    ),
                  ],
                ),

                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: TKeys.aboutTheStore.tr,
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

                const SizedBox(height: 16),

                // Language — the app follows the device locale on first run,
                // so this row is how a seller overrides that. The choice is
                // persisted, so it survives a cold start.
                _QuickActionRow(
                  icon: Icons.language_rounded,
                  tone: _Tone.violet,
                  title: TKeys.languageRowTitle.tr,
                  subtitle: TKeys.languageRowSubtitle.tr,
                  onTap: () => _showLanguageSheet(context),
                ),

                const SizedBox(height: 16),

                // Orders — seller-wide list (the endpoint takes no product
                // filter), so it lives on the profile rather than on a single
                // product's detail page.
                _QuickActionRow(
                  icon: Icons.receipt_long_rounded,
                  tone: _Tone.coral,
                  title: TKeys.ordersLabel.tr,
                  subtitle: TKeys.seeAllOrders.tr,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OrdersView()),
                  ),
                ),

                const SizedBox(height: 16),

                // Legal + support. App Review guideline 1.2 asks a UGC app to
                // publish the terms its users agreed to and a way to reach a
                // human; 5.1.1 asks for the privacy policy. All three open in
                // the system browser rather than a WebView so the seller can
                // read them signed in to the web account if they want to.
                _QuickActionRow(
                  icon: Icons.description_outlined,
                  tone: _Tone.navy,
                  title: TKeys.legalTerms.tr,
                  subtitle: TKeys.legalTermsSubtitle.tr,
                  onTap: () => _openLegalUrl(LegalUrls.terms),
                ),

                const SizedBox(height: 16),

                _QuickActionRow(
                  icon: Icons.privacy_tip_outlined,
                  tone: _Tone.blue,
                  title: TKeys.legalPrivacy.tr,
                  subtitle: TKeys.legalPrivacySubtitle.tr,
                  onTap: () => _openLegalUrl(LegalUrls.privacy),
                ),

                const SizedBox(height: 16),

                _QuickActionRow(
                  icon: Icons.support_agent_rounded,
                  tone: _Tone.green,
                  title: TKeys.legalSupport.tr,
                  subtitle: TKeys.legalSupportSubtitle.tr,
                  onTap: () => _openLegalUrl(LegalUrls.support),
                ),

                const SizedBox(height: 24),

                // Logout
                _LogoutButton(),

                const SizedBox(height: 18),

                // Delete account. App Review guideline 5.1.1(v) requires this
                // to be reachable from inside the app and easy to find, which
                // is why it sits in the open under Logout instead of behind a
                // submenu.
                const _DeleteAccountButton(),

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

  /// The account-status pill beside Verified.
  ///
  /// Its glyph is deliberately *not* another tick: sat next to the verified
  /// badge, two check marks read as one repeated statement rather than two
  /// separate facts. A bolt says "this account is switched on" on its own.
  Widget _buildStatusBadge(String status) {
    final isActive = status == 'ACTIVE';
    final color = isActive ? const Color(0xFF1565C0) : AppColors.vipps;
    final label = isActive ? TKeys.activeAccount.tr : status;
    return _buildBadge(
      isActive ? Icons.bolt_rounded : Icons.pending_rounded,
      label,
      color,
    );
  }
}

/// Gallery-or-camera → crop → upload, for the given profile image [kind].
///
/// Each kind is cropped to the exact frame it will be displayed in, so the
/// seller decides what stays in shot instead of the picture being squeezed to
/// fit on screen.
Future<void> _pickAndUploadImage(
  BuildContext context,
  ProfileController ctrl,
  ProfileImageKind kind,
) async {
  // Guard against double-taps while an upload is already running.
  if (ctrl.uploadingImage != null) return;

  final (title, ratio, circle) = switch (kind) {
    ProfileImageKind.avatar => (
        TKeys.profilePhoto.tr,
        const CropAspectRatio(ratioX: 1, ratioY: 1),
        true,
      ),
    ProfileImageKind.banner => (
        TKeys.coverPhoto.tr,
        const CropAspectRatio(ratioX: 16, ratioY: 9),
        false,
      ),
    ProfileImageKind.cardThumbnail => (
        TKeys.profileCardThumbnail.tr,
        const CropAspectRatio(ratioX: 16, ratioY: 9),
        false,
      ),
  };

  final path = await pickAndCropImage(
    context,
    title: title,
    aspectRatio: ratio,
    circle: circle,
  );
  if (path == null) return;

  final ok = await ctrl.uploadProfileImage(kind: kind, filePath: path);
  if (ok) {
    Get.snackbar(TKeys.updatedTitle.tr, TKeys.imageUploaded.tr);
  } else {
    Get.snackbar(TKeys.errorTitle.tr, ctrl.errorMessage ?? TKeys.couldNotUploadImage.tr);
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
                            TKeys.addCoverPhoto.tr,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_rounded,
                        size: 15, color: AppColors.brandNavy),
                    const SizedBox(width: 5),
                    CustomText(
                      TKeys.edit.tr,
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
      title: TKeys.profileCardThumbnail.tr,
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
                  border: Border.all(color: AppColors.borderGrey, width: 1),
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
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined,
                                size: 28, color: AppColors.textMuted),
                            const SizedBox(height: 6),
                            CustomText(
                              TKeys.addThumbnail.tr,
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
          _StatItem(icon: Icons.store_rounded, label: TKeys.typeLabel.tr, value: profile.sellerType),
          _verticalDivider(),
          _StatItem(
            icon: Icons.verified_user_rounded,
            label: TKeys.statusLabel.tr,
            value: profile.approvalStatus == 'ACTIVE' ? TKeys.activeLabel.tr : profile.approvalStatus,
          ),
          _verticalDivider(),
          _StatItem(
            icon: Icons.shield_rounded,
            label: TKeys.verifiedLabel.tr,
            value: profile.verified ? TKeys.yes.tr : TKeys.no.tr,
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
      title: TKeys.socialLinksLabel.tr,
      icon: Icons.share_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          // Wrap, not Row: six links overflow a phone width.
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: links.map((entry) {
              // A value we can't turn into a URL (e.g. a bare word in
              // "Website") stays visible but isn't offered as a tap.
              final openable = isOpenableSocialLink(entry.key, entry.value);
              return Tooltip(
                message: entry.value,
                child: Material(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: openable
                        ? () => openSocialLink(entry.key, entry.value)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        _iconFor(entry.key),
                        size: 20,
                        color: openable
                            ? AppColors.brandNavy
                            : AppColors.textMuted,
                      ),
                    ),
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


/// Bottom-sheet language picker opened from the profile tab.
///
/// Switching calls `Get.updateLocale`, which rebuilds every widget under
/// `GetMaterialApp` — so the sheet is closed first, otherwise it would rebuild
/// underneath the seller mid-tap.
Future<void> _showLanguageSheet(BuildContext context) async {
  final lang = Get.find<LanguageViewModel>();
  final picked = await showModalBottomSheet<Locale>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: CustomText(
              TKeys.languageSheetTitle.tr,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          // Obx so the check mark moves the instant the locale changes.
          Obx(
            () => Column(
              children: [
                _LanguageRow(
                  label: TKeys.languageNorwegian.tr,
                  selected: lang.isCurrent('nb'),
                  onTap: () => Navigator.of(sheetCtx).pop(
                    const Locale('nb', 'NO'),
                  ),
                ),
                _LanguageRow(
                  label: TKeys.languageEnglish.tr,
                  selected: lang.isCurrent('en'),
                  onTap: () => Navigator.of(sheetCtx).pop(
                    const Locale('en', 'US'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (picked == null) return;
  await lang.changeLanguage(picked);
  // Resolved after the switch, so the confirmation itself is already in the
  // language the seller just picked.
  Get.snackbar(
    TKeys.languageChanged.tr,
    picked.languageCode == 'nb'
        ? TKeys.languageNorwegian.tr
        : TKeys.languageEnglish.tr,
  );
}

/// One selectable language, with a check mark on the active one.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: CustomText(
                label,
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? AppColors.brandNavy
                    : AppColors.textSecondary,
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 20, color: AppColors.brandNavy),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirmed = await showConfirmDialog(
          context: context,
          title: TKeys.logOutTitle.tr,
          message: TKeys.logOutBody.tr,
          confirmLabel: TKeys.logOut.tr,
          cancelLabel: TKeys.stay.tr,
          icon: Icons.logout_rounded,
        );
        if (!confirmed || !context.mounted) return;

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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, size: 18, color: AppColors.vipps),
            const SizedBox(width: 8),
            CustomText(
              TKeys.logOut.tr,
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

/// The public web pages App Review expects to be reachable from inside the
/// app. Same destinations the buyer app uses — one set of documents covers
/// both, so a change on the web is live in both apps without a release.
class LegalUrls {
  LegalUrls._();

  static const String terms   = 'https://tommesalg.no/terms';
  static const String privacy = 'https://tommesalg.no/privacy';
  static const String support = 'https://tommesalg.no/contact';
}

/// Opens one of [LegalUrls] in the system browser, toasting if nothing on the
/// device can handle it.
Future<void> _openLegalUrl(String url) async {
  var launched = false;
  try {
    launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // url_launcher throws when no handler exists — same outcome as a plain
    // "couldn't launch" as far as the seller is concerned.
    launched = false;
  }
  if (launched) return;
  Get.snackbar(TKeys.legalOpenFailedTitle.tr, TKeys.legalOpenFailed.tr);
}

/// **Slett konto** — the in-app entry point to account deletion.
///
/// The deletion itself never happens here: [ProfileController
/// .requestAccountDeletionHandoff] mints a single-use URL and we open it in
/// the *system browser*, which establishes a web session and lands on
/// `/account/delete` where the seller types their e-mail and confirms. A
/// WebView would not do — the handoff sets cookies the web session needs to
/// survive its redirect chain.
///
/// Styled quieter than Logout on purpose: it has to be easy to *find*, not
/// easy to hit by accident, and the confirm dialog is the real guard.
class _DeleteAccountButton extends StatefulWidget {
  const _DeleteAccountButton();

  @override
  State<_DeleteAccountButton> createState() => _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends State<_DeleteAccountButton> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;

    final confirmed = await showConfirmDialog(
      context: context,
      title: TKeys.accountDeleteTitle.tr,
      message: TKeys.accountDeleteMessage.tr,
      confirmLabel: TKeys.accountDeleteContinue.tr,
      cancelLabel: TKeys.cancel.tr,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final url = await getOrPut(() => ProfileController())
        .requestAccountDeletionHandoff();
    if (!mounted) return;

    var launched = false;
    if (url != null) {
      try {
        launched = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        // url_launcher throws when nothing can open the URL — for the seller
        // that is the same outcome as a plain "couldn't launch".
        launched = false;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (launched) return;

    Get.snackbar(TKeys.accountDelete.tr, TKeys.accountDeleteFailed.tr);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _busy ? null : _onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.textSecondary),
              ),
            )
          else
            const Icon(Icons.delete_outline_rounded,
                size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          CustomText(
            TKeys.accountDelete.tr,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A0A1420),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final t        = tabs[i];
              final selected = i == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The navy chip is the whole selection cue — it grows
                        // in behind the icon, which flips to brand yellow. No
                        // label truncation to worry about at five tabs, unlike
                        // a horizontal pill.
                        //
                        // Both states carry a shadow of the same shape and
                        // differ only in its colour. Animating between a shadow
                        // list and `null` instead makes the framework scale the
                        // blur radius by the curve value, which an overshooting
                        // curve drives negative — dart:ui asserts on that. For
                        // the same reason the curve stays monotonic.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          height: 36,
                          width: selected ? 52 : 40,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.brandNavy
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [
                              BoxShadow(
                                color: selected
                                    ? const Color(0x3D0A1420)
                                    : const Color(0x000A1420),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            t.icon,
                            size: 21,
                            color: selected
                                ? AppColors.brandYellow
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 5),
                        CustomText(
                          t.label,
                          fontSize: 10.5,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.brandNavy
                              : AppColors.textMuted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
