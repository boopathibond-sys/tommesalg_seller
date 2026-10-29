import 'dart:developer';

import 'package:flutter/material.dart';

import '../../../views/orders/order_detail_view.dart';
import '../../../views/stock/sku_detail_view.dart';
import '../../../views/stream/stream_analytics_view.dart';
import '../../live_auction/views/auction_room_view.dart';
import 'push_destination.dart';

/// Sends a stored inbox row (or a tapped push) to the same place its
/// notification pointed at.
///
/// The routing table itself lives in [PushDestination.target]; this only
/// performs the navigation for it:
///
///   * [PushTarget.auctionRoom]     → [AuctionRoomView]
///   * [PushTarget.streamAnalytics] → [StreamAnalyticsView] (ended streams)
///   * [PushTarget.streamList]      → Home's Streams tab (rejected streams)
///   * [PushTarget.order]           → [OrderDetailView]
///   * [PushTarget.sku]             → [SkuDetailView]
///
/// Product rows are deliberately **not** routed: [ProductDetailView] needs a
/// fully-loaded `SellerProduct`, not an id, so a payload carrying only a
/// product id is reported as a dead end instead of being sent somewhere
/// approximate. Routing to the wrong screen is worse than not routing at all.
///
/// Push taps only route once [HomeView] has attached itself — i.e. a signed-in
/// seller is on the home shell. Until then (cold start behind the splash, or a
/// tap on the login screen) the tap is held and replayed on attach, so the
/// splash's `pushReplacement` can't swap out the screen the tap opened and
/// nothing is pushed over the login screen.
class NotificationRouter {
  NotificationRouter._();

  static Object? _owner;
  static NavigatorState? _navigator;
  static VoidCallback? _showStreams;
  static PushDestination? _pending;

  /// Called by [HomeView] once it is on screen. Replays a push tap that
  /// arrived before then.
  static void attachHome({
    required Object owner,
    required NavigatorState navigator,
    required VoidCallback showStreams,
  }) {
    _owner = owner;
    _navigator = navigator;
    _showStreams = showStreams;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      log('notifications: replaying queued tap $pending');
      _push(navigator, pending);
    }
  }

  /// Called by [HomeView] when it is disposed (sign-out). Drops any queued tap
  /// so it can't be replayed into the next session.
  ///
  /// Ignored unless [owner] is the Home that attached: when a fresh Home
  /// replaces an old one (leaving the auction room), the old one is disposed
  /// *after* the new one attached.
  static void detachHome(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _navigator = null;
    _showStreams = null;
    _pending = null;
  }

  /// Opens whatever [destination] points at, using [context]'s navigator —
  /// the inbox path, which only exists on top of Home. Returns `true` when
  /// something was actually opened, so the caller can tell the seller when a
  /// row is a dead end.
  static Future<bool> open(
    BuildContext context,
    PushDestination destination,
  ) {
    return _push(Navigator.of(context), destination);
  }

  /// The push tap path, from `main.dart`. Routes now if Home is up, otherwise
  /// queues [destination] for [attachHome].
  static void openFromPush(PushDestination destination) {
    final navigator = _navigator;
    if (navigator == null) {
      log('notifications: home not ready — queued $destination');
      _pending = destination;
      return;
    }
    _push(navigator, destination);
  }

  static Future<bool> _push(
    NavigatorState navigator,
    PushDestination destination,
  ) async {
    log('notifications: routing $destination');

    switch (destination.target) {
      case PushTarget.auctionRoom:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => AuctionRoomView(streamId: destination.streamId!),
          ),
        );
        return true;

      case PushTarget.streamAnalytics:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) =>
                StreamAnalyticsView(streamId: destination.streamId!),
          ),
        );
        return true;

      case PushTarget.streamList:
        final showStreams = _showStreams;
        if (showStreams == null) break;
        // The Streams tab lives inside Home, so close whatever is on top first.
        navigator.popUntil((route) => route.isFirst);
        showStreams();
        return true;

      case PushTarget.order:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => OrderDetailView(orderId: destination.orderId!),
          ),
        );
        return true;

      case PushTarget.sku:
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => SkuDetailView(locationId: destination.locationId!),
          ),
        );
        return true;

      case PushTarget.none:
        break;
    }

    log('notifications: no route mapped — staying put');
    return false;
  }
}
