import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  // Semaphore to prevent concurrent syncs
  bool _isSyncing = false;

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
        print("Internet Detected! Triggering sync...");
        syncPendingTransactions();
      }
    });
  }

  Future<void> saveOfflineTransaction(
      Map<String, dynamic> transactionData) async {
    final db = await _dbHelper.database;

    print("Saving Offline Transaction: $transactionData");

    await db.transaction((txn) async {
      int transactionId = await txn.insert(DatabaseHelper.tableTransactions, {
        'transaction_date': transactionData['date'],
        'total_amount': transactionData['total'],
        'payment_method':
            transactionData['paymentMethod'] ?? 'Cash', // Save actual method
        'customer_name': transactionData['customerName'] ?? 'Guest',
        'is_paylater': transactionData['paymentMethod'] == 'PayLater' ? 1 : 0,
        // --- ADDED MISSING DATA ---
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
    if (_isSyncing) {
      print("Sync already in progress. Skipping.");
      return 0;
    }

    _isSyncing = true;
    int syncedCount = 0;

    try {
      final db = await _dbHelper.database;

      // Select transactions where payment_method was saved offline
      // Note: We used to save 'offline_pending' as method, but now we save real method.
      // So we need a way to distinguish.
      // ACTUALLY: The easiest way without changing DB schema again is to query ALL
      // transactions in the local DB because we only store PENDING ones there.
      // Once synced, we delete them. So query all is safe.
      final List<Map<String, dynamic>> pendingHeaders =
          await db.query(DatabaseHelper.tableTransactions);

      if (pendingHeaders.isEmpty) {
        _isSyncing = false;
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

          // Construct Method String
          String originalMethod = header['payment_method'] ?? 'Cash';
          // Ensure we don't double append if it failed before
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
            'paymentMethod': finalMethod, // Use the appended string
            // --- READ CORRECT DATA FROM DB ---
            'paymentAmount': header['payment_amount'] ?? 0,
            'change': header['change_amount'] ?? 0,
          };

          print("Syncing Payload: $payload");

          final response = await http
              .post(
                Uri.parse(_apiUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(payload),
              )
              .timeout(const Duration(seconds: 20));

          print("Sync Response for ID ${header['id']}: ${response.statusCode}");

          if (response.statusCode == 200 || response.statusCode == 302) {
            await db.transaction((txn) async {
              await txn.delete(DatabaseHelper.tableTransactionItems,
                  where: 'transaction_id = ?', whereArgs: [header['id']]);
              await txn.delete(DatabaseHelper.tableTransactions,
                  where: 'id = ?', whereArgs: [header['id']]);
            });
            syncedCount++;
            print("Synced ID ${header['id']} successfully.");
          } else {
            print("Sync failed for ID ${header['id']}: ${response.statusCode}");
          }
        } catch (e) {
          print("Error processing ID ${header['id']}: $e");
        }
      }
    } catch (e) {
      print("General Sync Error: $e");
    } finally {
      _isSyncing = false;
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
