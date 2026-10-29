import 'package:flutter_test/flutter_test.dart';
import 'package:tommesalg_seller_app/features/live_auction/data/models/catalog_product.dart';
import 'package:tommesalg_seller_app/models/product_request_model.dart';
import 'package:tommesalg_seller_app/models/send_to_live_result.dart';

ProductRequestItem line({
  String id = 'line',
  String productId = 'p1',
  int requested = 1,
  int reserved = 0,
  String status = 'DRAFT',
  bool unknown = false,
  int? stock,
}) =>
    ProductRequestItem.fromJson({
      'id': id,
      'productId': unknown ? null : productId,
      'quantityRequested': requested,
      'reservedQuantity': reserved,
      'pendingQuantity': requested - reserved,
      'lineStatus': status,
      'isUnknownUpc': unknown,
      'requestedUpc': '012345678905',
      'sortOrder': 0,
      if (stock != null || !unknown)
        'product': {'id': productId, 'name': 'Blue jacket', 'stockCount': stock},
    });

CatalogProduct cat(String id, {bool inQueue = false, bool soldOut = false}) =>
    CatalogProduct(productId: id, name: id, inQueue: inQueue, soldOut: soldOut);

/// Assign to live → submit → auction queue, per the managed-stock guide:
/// scans add units to a draft line, submit credits them to stock once
/// (`reservedQuantity`), and each lot sold takes one unit.
void main() {
  group('unsentQuantity (what the Assign-to-live list shows)', () {
    test('draft line: every scanned unit is unsent', () {
      expect(line(requested: 3).unsentQuantity, 3);
    });

    test('submitted line: nothing left to send', () {
      expect(line(requested: 3, reserved: 3, status: 'RESERVED').unsentQuantity,
          0);
    });

    test('same product scanned again after submit: only the new units', () {
      // 3 sent, then scanned twice more → quantityRequested 5.
      expect(line(requested: 5, reserved: 3, status: 'DRAFT').unsentQuantity,
          2);
      expect(
          line(requested: 5, reserved: 3, status: 'RESERVED').unsentQuantity,
          2);
    });

    test('never negative', () {
      expect(line(requested: 1, reserved: 3).unsentQuantity, 0);
    });

    test('unknown UPC: unsent only while DRAFT', () {
      expect(line(unknown: true, requested: 2).unsentQuantity, 2);
      expect(
          line(unknown: true, requested: 2, status: 'PENDING_UNKNOWN')
              .unsentQuantity,
          0);
    });

    test('cancelled line is never shown', () {
      expect(line(requested: 4, status: 'CANCELLED').unsentQuantity, 0);
    });

    test('legacy PENDING_STOCK line still counts its unsent units', () {
      expect(line(requested: 5, status: 'PENDING_STOCK').unsentQuantity, 5);
    });
  });

  group('stockCount on request lines', () {
    test('parsed from product.stockCount, null when absent', () {
      expect(line(stock: 4).product!.stockCount, 4);
      expect(line().product!.stockCount, isNull);
    });

    test('kept through copyWith', () {
      final p = line(stock: 7).product!;
      expect(p.copyWith(shippingPriceNok: 99).stockCount, 7);
    });
  });

  group('SendToLiveResult.summarize', () {
    test('counts units and distinct products; unknown lines apart', () {
      final r = SendToLiveResult.summarize([
        line(id: 'a', productId: 'p1', requested: 3),
        line(id: 'b', productId: 'p2', requested: 5, reserved: 3),
        line(id: 'c', unknown: true, requested: 1),
      ]);
      expect(r.ok, isTrue);
      expect(r.units, 5); // 3 + (5 - 3)
      expect(r.products, 2);
      expect(r.unknown, 1);
      expect(r.notQueued, 0); // no catalog → not checked
    });

    test('flags products the queue catalog does not show as queued', () {
      final r = SendToLiveResult.summarize(
        [
          line(id: 'a', productId: 'p1'),
          line(id: 'b', productId: 'p2'),
          line(id: 'c', productId: 'p3'),
        ],
        catalog: [cat('p1', inQueue: true), cat('p2')],
      );
      expect(r.notQueued, 2); // p2 not queued, p3 missing
    });

    test('a sold-out product is not reported as a failed queue add', () {
      final r = SendToLiveResult.summarize(
        [line(productId: 'p1')],
        catalog: [cat('p1', soldOut: true)],
      );
      expect(r.notQueued, 0);
    });

    test('lines with nothing unsent are ignored', () {
      final r = SendToLiveResult.summarize(
        [line(requested: 2, reserved: 2, status: 'RESERVED')],
        catalog: const [],
      );
      expect(r.units, 0);
      expect(r.products, 0);
      expect(r.notQueued, 0);
    });

    test('failed carries the message', () {
      const r = SendToLiveResult.failed('Request is cancelled');
      expect(r.ok, isFalse);
      expect(r.error, 'Request is cancelled');
    });
  });

  group('queue catalog stock', () {
    test('USUAL: stockCount + soldOut', () {
      final p = CatalogProduct.fromJson({
        'productId': 'p1',
        'name': 'Blue jacket',
        'type': 'USUAL',
        'inQueue': true,
        'randomStock': null,
        'stockCount': 4,
        'soldOut': false,
      });
      expect(p.stockCount, 4);
      expect(p.unitsLeft, 4);
      expect(p.soldOut, isFalse);
    });

    test('RANDOM: units come from randomStock', () {
      final p = CatalogProduct.fromJson({
        'productId': 'r1',
        'name': 'Mystery',
        'type': 'RANDOM',
        'randomStock': 3,
        'stockCount': null,
      });
      expect(p.unitsLeft, 3);
    });

    test('old server without the fields: unknown, not sold out', () {
      final p = CatalogProduct.fromJson({'productId': 'p1', 'name': 'x'});
      expect(p.stockCount, isNull);
      expect(p.unitsLeft, isNull);
      expect(p.soldOut, isFalse);
    });

    test('sold out at zero', () {
      final p = CatalogProduct.fromJson({
        'productId': 'p1',
        'name': 'x',
        'stockCount': 0,
        'soldOut': true,
      });
      expect(p.unitsLeft, 0);
      expect(p.soldOut, isTrue);
    });
  });
}
