import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import '/service/database_helper.dart';
import '/app_config.dart';

class TransactionSyncService {
  static final TransactionSyncService _instance =
      TransactionSyncService._internal();
  factory TransactionSyncService() => _instance;
  TransactionSyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final String _apiUrl = kApiUrl;
  StreamSubscription? _connectivitySubscription;

  // Semaphores to prevent concurrent syncs
  bool _isSyncingTransactions = false;
  bool _isSyncingPayLater = false;

  void startAutoSync() {
    _connectivitySubscription?.cancel();
    print("Auto-Sync Service Started...");

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      bool isConnected = false;
      if (result is List<ConnectivityResult>) {
        isConnected = !result.contains(ConnectivityResult.none);
      } else {
        isConnected = result != ConnectivityResult.none;
      }

      if (isConnected) {
        print("Internet Detected! Triggering syncs...");
        // Trigger both syncs independently
        syncPendingTransactions();
        syncPendingPayLaterPayments();
      }
    });
  }

  // --- PART 1: NORMAL TRANSACTIONS (EXISTING LOGIC) ---

  Future<void> saveOfflineTransaction(
      Map<String, dynamic> transactionData) async {
    final db = await _dbHelper.database;
    print("Saving Offline Transaction: $transactionData");

    await db.transaction((txn) async {
      int transactionId = await txn.insert(DatabaseHelper.tableTransactions, {
        'transaction_date': transactionData['date'],
        'total_amount': transactionData['total'],
        'payment_method': transactionData['paymentMethod'] ?? 'Cash',
        'customer_name': transactionData['customerName'] ?? 'Guest',
        'is_paylater': transactionData['paymentMethod'] == 'PayLater' ? 1 : 0,
        'payment_amount': transactionData['paymentAmount'] ?? 0,
        'change_amount': transactionData['change'] ?? 0,
      });

      List<dynamic> items = transactionData['items'];
      for (var item in items) {
        await txn.insert(DatabaseHelper.tableTransactionItems, {
          'transaction_id': transactionId,
          'product_name': item['nama'],
          'quantity': item['qty'],
          'price_at_transaction': item['harga'],
          'subtotal': item['subtotal'],
        });
      }
    });
    print("Transaction saved locally (Offline).");
  }

  Future<int> syncPendingTransactions() async {
    if (_isSyncingTransactions) return 0;
    _isSyncingTransactions = true;
    int syncedCount = 0;

    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> pendingHeaders =
          await db.query(DatabaseHelper.tableTransactions);

      if (pendingHeaders.isEmpty) {
        _isSyncingTransactions = false;
        return 0;
      }

      print("Found ${pendingHeaders.length} pending transactions.");

      for (var header in pendingHeaders) {
        try {
          final List<Map<String, dynamic>> itemsRows = await db.query(
            DatabaseHelper.tableTransactionItems,
            where: 'transaction_id = ?',
            whereArgs: [header['id']],
          );

          List<Map<String, dynamic>> itemsPayload = itemsRows.map((row) {
            return {
              'nama': row['product_name'],
              'qty': row['quantity'],
              'harga': row['price_at_transaction'],
              'subtotal': row['subtotal'],
            };
          }).toList();

          String originalMethod = header['payment_method'] ?? 'Cash';
          String finalMethod = originalMethod.contains('(Synced)')
              ? originalMethod
              : '$originalMethod (Synced)';

          var payload = {
            'action': 'add_transaction',
            'secret': kSecretKey,
            'date': header['transaction_date'],
            'total': header['total_amount'],
            'items': itemsPayload,
            'customerName': header['customer_name'],
            'paymentMethod': finalMethod,
            'paymentAmount': header['payment_amount'] ?? 0,
            'change': header['change_amount'] ?? 0,
          };

          final response = await http
              .post(
                Uri.parse(_apiUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(payload),
              )
              .timeout(const Duration(seconds: 20));

          if (response.statusCode == 200 || response.statusCode == 302) {
            await db.transaction((txn) async {
              await txn.delete(DatabaseHelper.tableTransactionItems,
                  where: 'transaction_id = ?', whereArgs: [header['id']]);
              await txn.delete(DatabaseHelper.tableTransactions,
                  where: 'id = ?', whereArgs: [header['id']]);
            });
            syncedCount++;
            print("Synced Transaction ID ${header['id']} successfully.");
          }
        } catch (e) {
          print("Error processing Transaction ID ${header['id']}: $e");
        }
      }
    } catch (e) {
      print("General Transaction Sync Error: $e");
    } finally {
      _isSyncingTransactions = false;
    }
    return syncedCount;
  }

  // --- PART 2: PAYLATER PAYMENTS (NEW LOGIC) ---

  // Called when user clicks "Lunas" while offline
  Future<void> saveOfflinePayLaterPayment(String orderID) async {
    final db = await _dbHelper.database;
    try {
      await db.insert(
        DatabaseHelper.tablePendingPayLater,
        {
          'orderID': orderID,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print("Saved Offline PayLater Payment for OrderID: $orderID");
    } catch (e) {
      print("Error saving offline paylater: $e");
    }
  }

  // Called automatically when internet returns
  Future<int> syncPendingPayLaterPayments() async {
    if (_isSyncingPayLater) return 0;
    _isSyncingPayLater = true;
    int syncedCount = 0;

    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> pendingPayments =
          await db.query(DatabaseHelper.tablePendingPayLater);

      if (pendingPayments.isEmpty) {
        _isSyncingPayLater = false;
        return 0;
      }

      print("Found ${pendingPayments.length} pending PayLater payments.");

      for (var row in pendingPayments) {
        String orderID = row['orderID'];
        int rowId = row['id'];

        try {
          final queryParams = {
            'action': 'markAsPaid',
            'secret': kSecretKey,
            'orderID': orderID,
          };

          final uri = Uri.parse(_apiUrl).replace(queryParameters: queryParams);

          // Use GET as per your original code in PayLaterScreen
          final response =
              await http.get(uri).timeout(const Duration(seconds: 20));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true) {
              // Success! Delete from local queue
              await db.delete(
                DatabaseHelper.tablePendingPayLater,
                where: 'id = ?',
                whereArgs: [rowId],
              );
              syncedCount++;
              print("Synced PayLater Payment for $orderID successfully.");
            } else {
              print("API Error for PayLater $orderID: ${data['error']}");
            }
          } else {
            print("HTTP Error for PayLater $orderID: ${response.statusCode}");
          }
        } catch (e) {
          print("Error syncing PayLater $orderID: $e");
        }
      }
    } catch (e) {
      print("General PayLater Sync Error: $e");
    } finally {
      _isSyncingPayLater = false;
    }
    return syncedCount;
  }

  Future<List<Map<String, dynamic>>> getPendingTransactionsList() async {
    final db = await _dbHelper.database;
    return await db.query(DatabaseHelper.tableTransactions,
        orderBy: 'transaction_date DESC');
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
