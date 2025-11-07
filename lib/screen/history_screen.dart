import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';

// --- DATA MODEL BARU ---

/// Mewakili satu item dalam 'order_items'
class OrderItemDetail {
  final String orderID;
  final String nama;
  final int qty;
  final int pricePerItem;

  OrderItemDetail({
    required this.orderID,
    required this.nama,
    required this.qty,
    required this.pricePerItem,
  });

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) {
    return OrderItemDetail(
      orderID: json['OrderID'] ?? '',
      nama: json['nama']?.toString() ?? 'Nama tidak diketahui', // Sesuai 'nama'
      qty: json['qty'] ?? 0,
      pricePerItem: json['price_per_item'] ?? 0,
    );
  }
}

/// Mewakili satu baris 'orders' (ringkasan)
class OrderSummary {
  final String orderID;
  final DateTime timestamp;
  final String userName;
  final int totalPrice;
  final int paymentAmount;
  final String paymentMethod;
  final int change;
  final List<OrderItemDetail> items;

  OrderSummary({
    required this.orderID,
    required this.timestamp,
    required this.userName,
    required this.totalPrice,
    required this.paymentAmount,
    required this.paymentMethod,
    required this.change,
    this.items = const [],
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    String tsString = json['Timestamp'] ?? '';
    DateTime parsedTimestamp;
    try {
      parsedTimestamp = DateTime.parse(tsString).toLocal();
    } catch (e) {
      parsedTimestamp = DateTime.now();
    }

    return OrderSummary(
      orderID: json['OrderID'] ?? '', // Ini berisi formula hyperlink
      timestamp: parsedTimestamp,
      userName: json['Nama Pembeli'] ?? 'Guest', // Sesuai 'Nama Pembeli'
      totalPrice: json['Total Harga'] ?? 0, // Sesuai 'Total Harga'
      paymentAmount: json['Payment Amount'] ?? 0,
      paymentMethod: json['Payment Method'] ?? 'Cash',
      change: json['Change'] ?? 0,
    );
  }
}

// --- WIDGET LAYAR RIWAYAT ---

class HistoryScreen extends StatefulWidget {
  final DateTime? selectedDate;
  const HistoryScreen({Key? key, this.selectedDate}) : super(key: key);

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  late Future<List<OrderSummary>> _historyFuture;
  final NumberFormat _rupiahFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _historyFuture = fetchHistory();
  }

  void refreshHistory() {
    setState(() {
      _historyFuture = fetchHistory();
    });
  }

  /// Mengambil data riwayat dari Google Apps Script (struktur baru)
  Future<List<OrderSummary>> fetchHistory() async {
    try {
      final queryParams = {
        'action': 'getHistory',
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

        // 1. Parse kedua array
        final List<dynamic> ordersJson = data['orders'];
        final List<dynamic> itemsJson = data['order_items'];

        List<OrderSummary> summaries =
            ordersJson.map((json) => OrderSummary.fromJson(json)).toList();
        List<OrderItemDetail> allItems =
            itemsJson.map((json) => OrderItemDetail.fromJson(json)).toList();

        // 2. Gabungkan data di sisi Flutter
        List<OrderSummary> fullHistory = [];
        for (var summary in summaries) {
          var parts = summary.orderID.split('"');
          String cleanOrderID = '';
          if (parts.length > 3) {
            // ID adalah bagian kedua dari belakang (indeks ke-3 dari 5)
            cleanOrderID = parts[parts.length - 2];
          } else {
            // Fallback jika data lama tidak mengandung hyperlink
            cleanOrderID = summary.orderID;
          }
          // Cari semua item yang cocok
          final matchingItems =
              allItems.where((item) => item.orderID == cleanOrderID).toList();

          fullHistory.add(OrderSummary(
            orderID: cleanOrderID,
            timestamp: summary.timestamp,
            userName: summary.userName,
            totalPrice: summary.totalPrice,
            paymentAmount: summary.paymentAmount,
            paymentMethod: summary.paymentMethod,
            change: summary.change,
            items: matchingItems,
          ));
        }

        return fullHistory;
      } else {
        throw Exception(
            'Gagal memuat riwayat (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat riwayat: $e');
    }
  }

  List<OrderSummary> _filterByDate(
      List<OrderSummary> historyList, DateTime? selectedDate) {
    if (selectedDate == null) {
      return historyList;
    }
    return historyList.where((history) {
      final t = history.timestamp;
      return t.year == selectedDate.year &&
          t.month == selectedDate.month &&
          t.day == selectedDate.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat tileDateFormat = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    return FutureBuilder<List<OrderSummary>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
              child: Text('Tidak ada riwayat transaksi ditemukan.'));
        }

        final allHistory = snapshot.data!;
        final filteredHistory = _filterByDate(allHistory, widget.selectedDate);

        if (filteredHistory.isEmpty) {
          return Center(
            child: Text(widget.selectedDate != null
                ? 'Tidak ada transaksi pada tanggal ${DateFormat('d MMM yyyy', 'id_ID').format(widget.selectedDate!)}.'
                : 'Tidak ada riwayat.'),
          );
        }

        final reversedList = filteredHistory.reversed.toList();

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: reversedList.length,
          itemBuilder: (context, index) {
            final history = reversedList[index];

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              child: ExpansionTile(
                // Ini adalah UI yang Anda minta:
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  tileDateFormat.format(history.timestamp),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                    '${history.userName} | Total: ${_rupiahFormat.format(history.totalPrice)}'),
                trailing: Chip(
                  label: Text(history.orderID,
                      style: const TextStyle(fontSize: 10)),
                  backgroundColor: Colors.grey.shade200,
                ),
                // Saat ditekan, ini akan membangun daftar item yang dibeli:
                children: [
                  // --- Detail Transaksi (di dalam) ---
                  // Ini akan menampilkan item jika list 'history.items' tidak kosong
                  ...history.items.map((item) {
                    return ListTile(
                      title: Text(item.nama), // Sesuai 'nama'
                      trailing: Text(
                          '${item.qty} x ${_rupiahFormat.format(item.pricePerItem)}'),
                      visualDensity: VisualDensity.compact,
                      dense: true,
                    );
                  }).toList(),
                  // Garis pemisah
                  const Divider(indent: 16, endIndent: 16, height: 1),
                  // Info Pembayaran
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Metode Bayar:',
                                style: TextStyle(color: Colors.grey)),
                            Text(history.paymentMethod,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Belanja:'),
                            Text(_rupiahFormat.format(history.totalPrice)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Jumlah Bayar:'),
                            Text(_rupiahFormat.format(history.paymentAmount)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Kembalian:'),
                            Text(
                              _rupiahFormat.format(history.change),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
