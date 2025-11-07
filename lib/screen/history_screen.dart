import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';
import '../models/order_models.dart'; // <-- BARU: Impor model

// --- DATA MODEL BARU ---
// ... (SEMUA MODEL DIPINDAHKAN ke order_models.dart) ...
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

        final List<dynamic> ordersJson = data['orders'];
        final List<dynamic> itemsJson = data['order_items'];

        List<OrderItemDetail> allItems =
            itemsJson.map((json) => OrderItemDetail.fromJson(json)).toList();

        // Gabungkan data di sisi Flutter
        List<OrderSummary> fullHistory = ordersJson
            .map((json) => OrderSummary.fromJson(json, allItems))
            .toList();

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

  /// <-- BARU: Widget untuk menampilkan ringkasan Omset dan Margin
  Widget _buildSummaryCard(List<OrderSummary> filteredHistory) {
    // Hanya hitung dari transaksi yang LUNAS
    final lunasHistory = filteredHistory
        .where((h) => h.status == 'Lunas') // <-- PERUBAHAN: Cek status
        .toList();

    int totalOmset =
        lunasHistory.fold(0, (prev, order) => prev + order.totalPrice);
    int totalMargin =
        lunasHistory.fold(0, (prev, order) => prev + order.totalMargin);
    int totalTransaksi = lunasHistory.length;

    String title = "Ringkasan Hari Ini";
    if (widget.selectedDate != null) {
      title =
          "Ringkasan ${DateFormat('d MMM yyyy', 'id_ID').format(widget.selectedDate!)}";
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildSummaryRow(
              "Total Omset (Lunas)",
              _rupiahFormat.format(totalOmset),
              Colors.black,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              "Total Margin (Lunas)",
              _rupiahFormat.format(totalMargin),
              Colors.green.shade800,
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(
              "Total Transaksi (Lunas)",
              totalTransaksi.toString(),
              Colors.black,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
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
        // Filter HANYA berdasarkan tanggal yang dipilih
        final filteredHistory = _filterByDate(allHistory,
            widget.selectedDate ?? DateTime.now()); // Default ke hari ini

        if (filteredHistory.isEmpty) {
          return Column(
            children: [
              _buildSummaryCard(filteredHistory), // Tampilkan card kosong
              Expanded(
                child: Center(
                  child: Text(widget.selectedDate != null
                      ? 'Tidak ada transaksi pada tanggal ${DateFormat('d MMM yyyy', 'id_ID').format(widget.selectedDate!)}.'
                      : 'Tidak ada transaksi hari ini.'),
                ),
              ),
            ],
          );
        }

        final reversedList = filteredHistory.reversed.toList();

        return Column(
          children: [
            // <-- BARU: Tampilkan Card Ringkasan
            _buildSummaryCard(filteredHistory),
            // Daftar Transaksi
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                itemCount: reversedList.length,
                itemBuilder: (context, index) {
                  final history = reversedList[index];

                  // <-- BARU: Beri tanda untuk PayLater/Belum Lunas
                  Color tileColor = Colors.white;
                  IconData leadIcon = Icons.receipt_long;
                  if (history.status == 'Belum Lunas') {
                    tileColor = Colors.orange.shade50;
                    leadIcon = Icons.credit_card_off_rounded;
                  }

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6.0),
                    color: tileColor, // <-- PERUBAHAN
                    child: ExpansionTile(
                      leading: Icon(leadIcon), // <-- PERUBAHAN
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
                      children: [
                        ...history.items.map((item) {
                          return ListTile(
                            title: Text(item.nama),
                            trailing: Text(
                                '${item.qty} x ${_rupiahFormat.format(item.pricePerItem)}'), // Tampilkan harga jual
                            visualDensity: VisualDensity.compact,
                            dense: true,
                          );
                        }).toList(),
                        const Divider(indent: 16, endIndent: 16, height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 12.0),
                          child: Column(
                            children: [
                              _buildSummaryRow(
                                'Metode Bayar:',
                                history.paymentMethod,
                                history.status == 'Belum Lunas' // <-- PERUBAHAN
                                    ? Colors.orange.shade800
                                    : Colors.black,
                              ),
                              const SizedBox(height: 4),
                              _buildSummaryRow(
                                'Status:', // <-- BARU
                                history.status, // <-- BARU
                                history.status == 'Belum Lunas' // <-- BARU
                                    ? Colors.orange.shade800
                                    : Colors.green.shade800,
                              ),
                              const SizedBox(height: 4),
                              _buildSummaryRow(
                                'Total Belanja:',
                                _rupiahFormat.format(history.totalPrice),
                                Colors.black,
                              ),
                              // <-- BARU: Tampilkan Total Margin per transaksi
                              _buildSummaryRow(
                                'Total Margin:',
                                _rupiahFormat.format(history.totalMargin),
                                Colors.green.shade800,
                              ),
                              if (history.status != 'Belum Lunas') ...[
                                // <-- PERUBAHAN
                                const SizedBox(height: 4),
                                _buildSummaryRow(
                                  'Jumlah Bayar:',
                                  _rupiahFormat.format(history.paymentAmount),
                                  Colors.black,
                                ),
                                const SizedBox(height: 4),
                                _buildSummaryRow(
                                  'Kembalian:',
                                  _rupiahFormat.format(history.change),
                                  Colors.black,
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
