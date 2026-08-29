import 'dart:developer';

import 'package:flutter/material.dart';

import '../../../views/stock/sku_detail_view.dart';
import '../../live_auction/views/auction_room_view.dart';
import 'push_destination.dart';

/// Sends a stored inbox row (or a tapped push) to the same place its
/// notification pointed at.
///
/// The routing table itself lives in [PushDestination]; this only performs the
/// navigation for it. Only the two destinations the seller app can open from
/// an id alone are wired up:
///
///   * `streamId`   → [AuctionRoomView] — the seller's live auction room
///   * `locationId` → [SkuDetailView]   — one warehouse SKU
///
/// Product rows are deliberately **not** routed: [ProductDetailView] needs a
/// fully-loaded `SellerProduct`, not an id, so a payload carrying only a
/// product id is reported as a dead end instead of being sent somewhere
/// approximate. Routing to the wrong screen is worse than not routing at all.
///
/// Every branch is best-effort: an unroutable payload leaves the seller on the
/// notification list rather than throwing.
class NotificationRouter {
  NotificationRouter._();

  /// Opens whatever [destination] points at, using [context]'s navigator.
  /// Returns `true` when something was actually opened, so the caller can tell
  /// the seller when a row is a dead end.
  static Future<bool> open(
    BuildContext context,
    PushDestination destination,
  ) {
    return _push(Navigator.of(context), destination);
  }

  /// Same routing decision, driven from a [NavigatorState] instead of a
  /// [BuildContext] — used by the push tap handler in `main.dart`, which has
  /// the app-level navigator key but no screen context of its own.
  static Future<bool> openWith(
    NavigatorState? navigator,
    PushDestination destination,
  ) {
    if (navigator == null) return Future.value(false);
    return _push(navigator, destination);
  }

  static Future<bool> _push(
    NavigatorState navigator,
    PushDestination destination,
  ) async {
    log('notifications: routing $destination');

    if (destination.opensAuctionRoom) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => AuctionRoomView(streamId: destination.streamId!),
        ),
      );
      return true;
    }

    if (destination.opensSku) {
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => SkuDetailView(locationId: destination.locationId!),
        ),
      );
      return true;
    }

    log('notifications: no route mapped — staying put');
    return false;
  }
}
