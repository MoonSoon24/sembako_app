import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../app_config.dart';
import '../models/order_models.dart';
import 'database_helper.dart';

class HistoryRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final String _apiUrl = kApiUrl;

  /// Fetches history. Tries Online first, falls back to Offline cache.
  Future<List<OrderSummary>> getHistory() async {
    try {
      // 1. Try Online
      final queryParams = {
        'action': 'getHistory',
        'secret': kSecretKey,
      };

      final uri = Uri.parse(_apiUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == false || data['error'] != null) {
          throw Exception('API Error: ${data['error']}');
        }

        // Parse JSON
        final List<dynamic> ordersJson = data['orders'];
        final List<dynamic> itemsJson = data['order_items'];

        List<OrderItemDetail> allItems =
            itemsJson.map((json) => OrderItemDetail.fromJson(json)).toList();

        List<OrderSummary> fullHistory = ordersJson
            .map((json) => OrderSummary.fromJson(json, allItems))
            .toList();

        // 2. Save to Local Cache
        await _saveHistoryToCache(fullHistory);

        return fullHistory;
      } else {
        throw Exception('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      print("Offline/Error Mode (History): Fetching from Local DB... ($e)");
      // 3. Fallback to Local Cache
      return await _getLocalHistory();
    }
  }

  /// Saves the fetched list to SQLite, replacing old data.
  Future<void> _saveHistoryToCache(List<OrderSummary> historyList) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // Clear old cache to ensure we match the Spreadsheet exactly
      await txn.delete(DatabaseHelper.tableCachedOrderItems);
      await txn.delete(DatabaseHelper.tableCachedOrders);

      for (var order in historyList) {
        // Insert Header
        await txn.insert(DatabaseHelper.tableCachedOrders, {
          'orderID': order.orderID,
          'timestamp': order.timestamp.toIso8601String(),
          'userName': order.userName,
          'totalPrice': order.totalPrice,
          'paymentAmount': order.paymentAmount,
          'paymentMethod': order.paymentMethod,
          'change': order.change,
          'status': order.status,
          'totalMargin': order.totalMargin,
        });

        // Insert Items
        for (var item in order.items) {
          await txn.insert(DatabaseHelper.tableCachedOrderItems, {
            'orderID': order.orderID, // Foreign Key
            'nama': item.nama,
            'qty': item.qty,
            'pricePerItem': item.pricePerItem,
            'hargaBeli': item.hargaBeli,
            'kategori': item.kategori,
          });
        }
      }
    });
    print("History Cache Updated: ${historyList.length} orders.");
  }

  /// Retrieves history from SQLite.
  Future<List<OrderSummary>> _getLocalHistory() async {
    final db = await _dbHelper.database;

    // 1. Get All Orders
    final List<Map<String, dynamic>> orderRows = await db
        .query(DatabaseHelper.tableCachedOrders, orderBy: "timestamp DESC");

    List<OrderSummary> results = [];

    for (var row in orderRows) {
      String orderID = row['orderID'];

      // 2. Get Items for this Order
      final List<Map<String, dynamic>> itemRows = await db.query(
        DatabaseHelper.tableCachedOrderItems,
        where: 'orderID = ?',
        whereArgs: [orderID],
      );

      // Map DB Rows back to Objects
      List<OrderItemDetail> items = itemRows.map((itemRow) {
        return OrderItemDetail(
          orderID: orderID,
          nama: itemRow['nama'],
          qty: itemRow['qty'],
          pricePerItem: itemRow['pricePerItem'],
          hargaBeli: itemRow['hargaBeli'],
          kategori: itemRow['kategori'],
        );
      }).toList();

      // Construct OrderSummary
      results.add(OrderSummary(
        orderID: orderID,
        timestamp: DateTime.parse(row['timestamp']),
        userName: row['userName'],
        totalPrice: row['totalPrice'],
        paymentAmount: row['paymentAmount'],
        paymentMethod: row['paymentMethod'],
        change: row['change'],
        status: row['status'],
        items: items,
        totalMargin: row['totalMargin'],
      ));
    }

    return results;
  }
}
