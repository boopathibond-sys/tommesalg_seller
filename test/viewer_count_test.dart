import 'package:flutter_test/flutter_test.dart';
import 'package:tommesalg_seller_app/features/live_auction/data/models/auction_room_snapshot.dart';

/// The room's viewer pill trusts the backend's `viewerCount`; a frame that
/// doesn't report one must read as "unknown", never as zero viewers.
void main() {
  test('reads viewerCount under each spelling the API uses', () {
    expect(StreamSnapshot.readViewerCount({'viewerCount': 7}), 7);
    expect(StreamSnapshot.readViewerCount({'currentViewerCount': 3.0}), 3);
    expect(StreamSnapshot.readViewerCount({'viewers': '12'}), 12);
    expect(StreamSnapshot.readViewerCount({'viewer_count': 0}), 0);
  });

  test('a frame without a count is null, not zero', () {
    expect(StreamSnapshot.readViewerCount({'status': 'LIVE'}), isNull);
    expect(StreamSnapshot.readViewerCount({'viewerCount': 'n/a'}), isNull);
  });

  test('stream snapshot carries the count and keeps it through copyWith', () {
    final s = StreamSnapshot.fromJson({
      'id': 'stream_1',
      'status': 'LIVE',
      'viewerCount': 42,
    });
    expect(s.viewerCount, 42);
    expect(s.copyWith(bidsPaused: true).viewerCount, 42);
  });
}
