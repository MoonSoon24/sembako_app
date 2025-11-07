import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';
import '../models/order_models.dart'; // <-- BARU: Impor model

// --- DATA MODEL ---

// Model PayLaterOrder diganti dengan OrderSummary dari order_models.dart

class CustomerDebt {
  final String nama;
  int totalUtang;
  List<OrderSummary> orders; // <-- PERUBAHAN: Gunakan OrderSummary

  CustomerDebt({
    required this.nama,
    required this.totalUtang,
    required this.orders,
  });
}

// --- WIDGET LAYAR ---

class PayLaterScreen extends StatefulWidget {
  const PayLaterScreen({Key? key}) : super(key: key);

  @override
  State<PayLaterScreen> createState() => PayLaterScreenState();
}

class PayLaterScreenState extends State<PayLaterScreen> {
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

  /// Mengambil dan mengelompokkan data utang
  Future<List<CustomerDebt>> fetchPayLaterData() async {
    // PERUBAHAN: Panggil 'getHistory' untuk mendapatkan semua data
    try {
      final queryParams = {
        'action': 'getHistory', // <-- PERUBAHAN: Panggil getHistory
        'secret': kSecretKey,
      };
      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);
      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == false || data['error'] != null) {
          throw Exception('API Error: ${data['error']}');
        }

        // PERUBAHAN: Parse data history lengkap
        final List<dynamic> ordersJson = data['orders'];
        final List<dynamic> itemsJson = data['order_items'];

        List<OrderItemDetail> allItems =
            itemsJson.map((json) => OrderItemDetail.fromJson(json)).toList();

        List<OrderSummary> allHistory = ordersJson
            .map((json) => OrderSummary.fromJson(json, allItems))
            .toList();
        // --- Akhir Parse ---

        // Filter hanya yang belum lunas
        final unpaidOrders =
            allHistory.where((order) => order.status == 'Belum Lunas').toList();

        // Kelompokkan berdasarkan nama
        final Map<String, CustomerDebt> debtMap = {};
        for (var order in unpaidOrders) {
          if (debtMap.containsKey(order.userName)) {
            // <-- PERUBAHAN: userName
            // Tambahkan ke pelanggan yang ada
            debtMap[order.userName]!.orders.add(order);
            debtMap[order.userName]!.totalUtang +=
                order.totalPrice; // <-- PERUBAHAN: totalPrice
          } else {
            // Buat entri pelanggan baru
            debtMap[order.userName] = CustomerDebt(
              nama: order.userName,
              totalUtang: order.totalPrice, // <-- PERUBAHAN: totalPrice
              orders: [order],
            );
          }
        }

        // Urutkan berdasarkan total utang (terbesar di atas)
        final sortedList = debtMap.values.toList();
        sortedList.sort((a, b) => b.totalUtang.compareTo(a.totalUtang));

        return sortedList;
      } else {
        throw Exception(
            'Gagal memuat data piutang (Status: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat data piutang: $e');
    }
  }

  /// Menandai utang sebagai lunas
  Future<void> _markAsPaid(String orderID) async {
    try {
      final queryParams = {
        'action': 'markAsPaid',
        'secret': kSecretKey,
        'orderID': orderID,
      };
      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);
      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Utang berhasil dilunasi'),
              backgroundColor: Colors.green,
            ),
          );
          refreshData(); // Muat ulang data setelah berhasil
        } else {
          throw Exception(data['error'] ?? 'Gagal memperbarui status');
        }
      } else {
        throw Exception(
            'Gagal melunasi utang (Status: ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Menampilkan dialog konfirmasi pelunasan
  Future<void> _showConfirmationDialog(OrderSummary order) async {
    // <-- PERUBAHAN: Model
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Konfirmasi Pelunasan'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Anda yakin ingin menandai utang Sdr/i ${order.userName} sebesar ${_rupiahFormat.format(order.totalPrice)} (ID: ${order.orderID}) sebagai LUNAS?'), // <-- PERUBAHAN
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

          return Column(
            children: [
              // Card Total Piutang
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
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                        Text(
                          // <-- PERBAIKAN: Menghapus 'child:'
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
              // Daftar Piutang per Pelanggan
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
                                'ID: ${order.orderID} - ${_rupiahFormat.format(order.totalPrice)}'), // <-- PERUBAHAN
                            subtitle: Text(
                                DateFormat('d MMM yyyy, HH:mm', 'id_ID')
                                    .format(order.timestamp)),
                            trailing: ElevatedButton(
                              child: const Text('Lunasi'),
                              onPressed: () => _showConfirmationDialog(order),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
