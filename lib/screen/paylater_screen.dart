import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';
import '../models/order_models.dart';
import '../service/history_repository.dart'; // Import History Repo
import '../service/transaction_sync.dart'; // Import Sync Service
import '../service/database_helper.dart'; // Import DB Helper for local update

class CustomerDebt {
  final String nama;
  int totalUtang;
  List<OrderSummary> orders;

  CustomerDebt({
    required this.nama,
    required this.totalUtang,
    required this.orders,
  });
}

class PayLaterScreen extends StatefulWidget {
  const PayLaterScreen({Key? key}) : super(key: key);

  @override
  State<PayLaterScreen> createState() => PayLaterScreenState();
}

class PayLaterScreenState extends State<PayLaterScreen> {
  // Use Repository
  final HistoryRepository _historyRepository = HistoryRepository();
  late Future<List<CustomerDebt>> _payLaterFuture;

  final NumberFormat _rupiahFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _payLaterFuture = fetchPayLaterData();
  }

  void refreshData() {
    setState(() {
      _payLaterFuture = fetchPayLaterData();
    });
  }

  Future<List<CustomerDebt>> fetchPayLaterData() async {
    try {
      // 1. Get All History (Online or Offline)
      final allHistory = await _historyRepository.getHistory();

      // 2. Filter only 'Belum Lunas'
      final unpaidOrders =
          allHistory.where((order) => order.status == 'Belum Lunas').toList();

      // 3. Group by Customer
      final Map<String, CustomerDebt> debtMap = {};
      for (var order in unpaidOrders) {
        if (debtMap.containsKey(order.userName)) {
          debtMap[order.userName]!.orders.add(order);
          debtMap[order.userName]!.totalUtang += order.totalPrice;
        } else {
          debtMap[order.userName] = CustomerDebt(
            nama: order.userName,
            totalUtang: order.totalPrice,
            orders: [order],
          );
        }
      }

      final sortedList = debtMap.values.toList();
      sortedList.sort((a, b) => b.totalUtang.compareTo(a.totalUtang));

      return sortedList;
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat data piutang: $e');
    }
  }

  /// Mark as Paid (Online + Offline Fallback)
  Future<void> _markAsPaid(String orderID) async {
    try {
      // 1. Try Online Request
      final queryParams = {
        'action': 'markAsPaid',
        'secret': kSecretKey,
        'orderID': orderID,
      };
      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);

      final response =
          await http.get(urlWithParams).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Utang berhasil dilunasi'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh will re-fetch and update UI
          refreshData();
        } else {
          throw Exception(data['error'] ?? 'Gagal memperbarui status');
        }
      } else {
        throw Exception('Status Server: ${response.statusCode}');
      }
    } catch (e) {
      // 2. Offline Fallback
      print("Offline 'Mark as Paid' triggered for $orderID. Error: $e");

      // Save to Pending Queue
      await TransactionSyncService().saveOfflinePayLaterPayment(orderID);

      // Update Local Cache immediately (Optimistic UI)
      final db = await DatabaseHelper().database;
      await db.update(
        DatabaseHelper.tableCachedOrders,
        {'status': 'Lunas'}, // Set status to Lunas locally
        where: 'orderID = ?',
        whereArgs: [orderID],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline: Status disimpan. Akan dikirim saat online.'),
          backgroundColor: Colors.orange,
        ),
      );

      refreshData();
    }
  }

  Future<void> _showConfirmationDialog(OrderSummary order) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Konfirmasi Pelunasan'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Anda yakin ingin menandai utang Sdr/i ${order.userName} (ID: ${order.orderID}) sebagai LUNAS?',
                ),
                const SizedBox(height: 16),
                const Text(
                  'DETAIL ITEM:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(thickness: 1),
                ...order.items.map((item) {
                  return ListTile(
                    title: Text(item.nama),
                    trailing: Text(
                        '${item.qty} x ${_rupiahFormat.format(item.pricePerItem)}'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
                const Divider(thickness: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Utang:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        _rupiahFormat.format(order.totalPrice),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Ya, Lunas'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _markAsPaid(order.orderID);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<CustomerDebt>>(
        future: _payLaterFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Tidak ada piutang (utang).'));
          }

          final List<CustomerDebt> debts = snapshot.data!;
          final int totalSemuaUtang =
              debts.fold(0, (sum, item) => sum + item.totalUtang);

          return RefreshIndicator(
            onRefresh: () async => refreshData(),
            child: Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(8.0),
                  elevation: 4,
                  color: Colors.orange.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Column(
                        children: [
                          const Text(
                            'Total Piutang (Belum Lunas)',
                            style:
                                TextStyle(fontSize: 16, color: Colors.black54),
                          ),
                          Text(
                            _rupiahFormat.format(totalSemuaUtang),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: debts.length,
                    itemBuilder: (context, index) {
                      final customerDebt = debts[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ExpansionTile(
                          leading: const Icon(Icons.person),
                          title: Text(
                            customerDebt.nama,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Total Utang: ${_rupiahFormat.format(customerDebt.totalUtang)}',
                            style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold),
                          ),
                          trailing: Chip(
                            label:
                                Text('${customerDebt.orders.length} transaksi'),
                          ),
                          children: customerDebt.orders.map((order) {
                            return ListTile(
                              title: Text(
                                  'ID: ${order.orderID} - ${_rupiahFormat.format(order.totalPrice)}'),
                              subtitle: Text(
                                  DateFormat('d MMM yyyy, HH:mm', 'id_ID')
                                      .format(order.timestamp)),
                              onTap: () => _showConfirmationDialog(order),
                              trailing: Icon(Icons.info_outline,
                                  color: Colors.blue.shade700),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
