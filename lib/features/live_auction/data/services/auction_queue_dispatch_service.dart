import 'dart:developer';

import 'auction_room_api.dart';
import 'seller_session_service.dart';

/// Outcome of a "send to auction queue" dispatch, so the caller can report
/// exactly what happened without re-deriving it.
class QueueDispatchResult {
  const QueueDispatchResult({
    required this.ok,
    this.sent = 0,
    this.skipped = 0,
    this.error,
  });

  const QueueDispatchResult.failed(String message, {this.skipped = 0})
      : ok = false,
        sent = 0,
        error = message;

  /// The batch was accepted by the server.
  final bool ok;

  /// How many products were actually posted to the queue.
  final int sent;

  /// Products that couldn't be queued because they carry no catalog product id
  /// (unknown-UPC rows the seller added by hand — the auction queue can only
  /// take real catalog products).
  final int skipped;

  /// Server-supplied failure message, verbatim, when [ok] is false.
  final String? error;
}

/// Sends products straight to a stream's auction queue **without opening the
/// auction room**.
///
/// The room's [AuctionRoomController.addCatalogProducts] hits the same endpoint
/// (`POST …/auction-room/queue`, batch form), but reaching it through the
/// controller is not an option from outside the room: its `onInit` runs
/// `enterRoom()`, which asks for camera + microphone permission, starts an
/// Agora RTC preview, logs into RTM, opens the snapshot WebSocket and begins a
/// 20-second session heartbeat. This service performs the same mutation with
/// the same request body and nothing else.
///
/// Every auction mutation must carry a session auth body (`deviceId` +
/// `sessionToken`), so a session is claimed for the one call and released
/// afterwards. Claiming is idempotent per device: if this handset already holds
/// the room session, the claim returns that same session rather than a second
/// one.
class AuctionQueueDispatchService {
  final _sessions = SellerSessionService();
  final _api = AuctionRoomApi();

  /// Adds [productIds] to [streamId]'s queue in one request.
  ///
  /// [skipped] is passed through onto the result so the caller can tell the
  /// seller how many rows were left behind before this was ever called.
  Future<QueueDispatchResult> send({
    required String streamId,
    required List<String> productIds,
    String auctionType = 'NORMAL',
    int skipped = 0,
  }) async {
    if (productIds.isEmpty) {
      return QueueDispatchResult.failed(
        'None of these products can be sent to the auction queue.',
        skipped: skipped,
      );
    }

    try {
      final session = await _sessions.claim(streamId);
      await _api.enqueueBatch(
        streamId: streamId,
        session: session,
        products: [
          for (final id in productIds)
            {
              'productId': id,
              'auctionType': auctionType,
              'sourceType': 'CATALOG',
            },
        ],
      );

      // Deliberately NOT disconnecting afterwards. `claim` is keyed on a stable
      // per-install deviceId, so if the seller has the auction room open on
      // this same handset it hands back *that* session — disconnecting here
      // would tear down their live room. The lease lapses on its own without
      // heartbeats, so leaving it is both safe and cheaper than a call that
      // 403s the moment the session has already gone.
      return QueueDispatchResult(
        ok: true,
        sent: productIds.length,
        skipped: skipped,
      );
    } on AuctionApiException catch (e) {
      // Surface the backend's exact wording — e.g. AUTH_FORBIDDEN "Only the
      // device with auction control may perform this action", which is what a
      // seller hits when another device is hosting the room right now.
      log('sendToAuctionQueue error: $e');
      return QueueDispatchResult.failed(e.message, skipped: skipped);
    } catch (e) {
      log('sendToAuctionQueue error: $e');
      return QueueDispatchResult.failed(
        'Network error. Please try again.',
        skipped: skipped,
      );
    }
  }
}
