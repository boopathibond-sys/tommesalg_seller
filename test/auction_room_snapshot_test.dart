import 'package:flutter_test/flutter_test.dart';
import 'package:tommesalg_seller_app/features/live_auction/data/models/auction_room_snapshot.dart';

AuctionRoomSnapshot _snap(Map<String, dynamic>? active) =>
    AuctionRoomSnapshot.fromJson({
      'stream': {'id': 's1', 'status': 'LIVE'},
      if (active != null) 'activeAuction': active,
    });

void main() {
  test('a lot the server already closed is not a running lot', () {
    for (final status in ['ENDED', 'sold', 'SETTLING', 'CANCELLED']) {
      final snap = _snap({'auctionId': 'a1', 'status': status});
      expect(snap.activeAuction, isNull, reason: status);
      // Still explicit about the lot, so the conclusion is detected.
      expect(snap.raw.containsKey('activeAuction'), isTrue);
    }
    expect(_snap({'auctionId': 'a1', 'status': 'ACTIVE'}).activeAuction,
        isNotNull);
    expect(_snap({'auctionId': 'a1'}).activeAuction, isNotNull);
  });

  test('BID_PLACED auctionId matches whichever id the snapshot used', () {
    final lot = _snap({'id': 'row-1', 'auctionId': 'a1', 'productId': 'p1'})
        .activeAuction!;
    expect(lot.id, 'a1');
    expect(lot.isSameLot('a1'), isTrue);
    expect(lot.isSameLot('row-1'), isTrue);
    expect(lot.isSameLot(null), isTrue);
    expect(lot.isSameLot('other'), isFalse);
    // The product id never identifies a lot: it can run again next.
    expect(lot.isSameLot('p1'), isFalse);
  });

  test('copyWith can clear the running lot and patch endsAt', () {
    final snap = _snap({'auctionId': 'a1', 'endsAt': '2026-10-10T10:00:00Z'});
    expect(snap.copyWith().activeAuction, isNotNull);
    expect(snap.copyWith(clearActiveAuction: true).activeAuction, isNull);

    final extended =
        snap.activeAuction!.copyWith(endsAt: '2026-10-10T10:00:10Z');
    expect(extended.endsAtUtc, DateTime.utc(2026, 10, 10, 10, 0, 10));
  });

  test('an anti-snipe extension lengthens the countdown total', () {
    final lot = _snap({
      'auctionId': 'a1',
      'durationSec': 30,
      'startedAt': '2026-10-10T10:00:00Z',
      'endsAt': '2026-10-10T10:00:40Z',
    }).activeAuction!;
    expect(lot.totalDurationSec, 40);
  });
}
