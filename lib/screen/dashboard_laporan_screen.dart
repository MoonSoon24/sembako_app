import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';
import '../models/order_models.dart'; // <-- PERUBAHAN

// --- WIDGET LAYAR ---

class DashboardLaporanScreen extends StatefulWidget {
  const DashboardLaporanScreen({Key? key}) : super(key: key);

  @override
  State<DashboardLaporanScreen> createState() => DashboardLaporanScreenState();
}

class DashboardLaporanScreenState extends State<DashboardLaporanScreen> {
  late Future<List<OrderSummary>> _historyFuture;
  final NumberFormat _rupiahFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _historyFuture = fetchHistory();
  }

  void refreshData() {
    setState(() {
      _historyFuture = fetchHistory();
    });
  }

  /// Mengambil data riwayat (logika sama seperti history_screen)
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

  /// Widget utama
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<OrderSummary>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Tidak ada data untuk laporan.'));
          }

          // Filter transaksi lunas (bukan PayLater) untuk laporan keuangan
          final lunasHistory = snapshot.data!
              .where((order) => order.status == 'Lunas') // <-- PERUBAHAN
              .toList();

          // Gunakan SEMUA history (termasuk PayLater) untuk produk terlaris
          final allHistory = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOmsetChart(lunasHistory),
                const SizedBox(height: 16),
                _buildCategoryPieChart(lunasHistory),
                const SizedBox(height: 16),
                _buildTopProducts(allHistory),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 1. GRAFIK OMSET MINGGUAN
  Widget _buildOmsetChart(List<OrderSummary> lunasHistory) {
    final Map<int, double> dailyOmset = {};
    final today = DateTime.now();
    final todayWeekday = today.weekday; // Senin=1, Minggu=7

    // Inisialisasi 7 hari ke belakang
    for (int i = 0; i < 7; i++) {
      final day = today.subtract(Duration(days: i));
      // Gunakan weekday sebagai key (1-7)
      dailyOmset[day.weekday] = 0.0;
    }

    double maxOmset = 0;

    // Akumulasi data
    for (var order in lunasHistory) {
      final daysAgo = today.difference(order.timestamp).inDays;
      if (daysAgo < 7) {
        final weekday = order.timestamp.weekday;
        dailyOmset[weekday] = (dailyOmset[weekday] ?? 0.0) + order.totalPrice;
        if (dailyOmset[weekday]! > maxOmset) {
          maxOmset = dailyOmset[weekday]!;
        }
      }
    }

    // Buat data untuk grafik (diurutkan dari 6 hari lalu ke hari ini)
    final List<BarChartGroupData> barGroups = [];
    for (int i = 6; i >= 0; i--) {
      // Urutkan dari Senin (1) ke Minggu (7), lalu putar
      int weekday = todayWeekday - i;
      if (weekday <= 0) weekday += 7; // 1-7

      barGroups.add(
        BarChartGroupData(
          x: weekday,
          barRods: [
            BarChartRodData(
              toY: dailyOmset[weekday] ?? 0.0,
              color: Colors.blue,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    // Tentukan interval Y (kelipatan 50rb, 100rb, 500rb, dst.)
    double yInterval = maxOmset > 1000000 ? 500000 : 100000;
    if (maxOmset <= 100000) yInterval = 25000;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Omset 7 Hari Terakhir (Lunas)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxOmset * 1.2, // Beri sedikit ruang di atas
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return const FlLine(color: Colors.grey, strokeWidth: 0.5);
                    },
                    horizontalInterval: yInterval,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value > maxOmset)
                            return const SizedBox();
                          return Text(
                            '${(value / 1000).toStringAsFixed(0)}k',
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.left,
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          String text;
                          switch (value.toInt()) {
                            case 1:
                              text = 'Sen';
                              break;
                            case 2:
                              text = 'Sel';
                              break;
                            case 3:
                              text = 'Rab';
                              break;
                            case 4:
                              text = 'Kam';
                              break;
                            case 5:
                              text = 'Jum';
                              break;
                            case 6:
                              text = 'Sab';
                              break;
                            case 7:
                              text = 'Min';
                              break;
                            default:
                              text = '';
                          }
                          return Text(text,
                              style: const TextStyle(fontSize: 12));
                        },
                      ),
                    ),
                  ),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2. GRAFIK KATEGORI
  Widget _buildCategoryPieChart(List<OrderSummary> lunasHistory) {
    final Map<String, double> categoryOmset = {};
    double totalOmset = 0;

    for (var order in lunasHistory) {
      for (var item in order.items) {
        // PERBAIKAN: Ambil kategori dari item (yang berasal dari produk)
        // Kita perlu data produk lengkap untuk ini, tapi 'item' tidak punya.
        // Kita gunakan logika placeholder sederhana berdasarkan nama/harga
        // TODO: Untuk akurasi, `order_items` di Apps Script idealnya juga menyimpan 'kategori'
        final kategori = item.nama.toLowerCase().contains('rokok')
            ? 'Rokok'
            : (item.pricePerItem > 10000
                ? 'Sembako'
                : (item.pricePerItem > 3000 ? 'Minuman' : 'Snack'));

        final omset = item.totalOmset.toDouble();
        categoryOmset[kategori] = (categoryOmset[kategori] ?? 0.0) + omset;
        totalOmset += omset;
      }
    }

    if (totalOmset == 0) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("Belum ada data untuk ringkasan kategori."),
        ),
      );
    }

    // Hasilkan warna acak
    final List<Color> colors = List.generate(
      categoryOmset.length,
      (index) =>
          Color((Random().nextDouble() * 0xFFFFFF).toInt()).withOpacity(1.0),
    );

    int colorIndex = 0;
    final List<PieChartSectionData> sections =
        categoryOmset.entries.map((entry) {
      final percentage = (entry.value / totalOmset) * 100;
      return PieChartSectionData(
        color: colors[colorIndex++],
        value: percentage,
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 80,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      );
    }).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Omset (Lunas) Berdasarkan Kategori",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: List.generate(categoryOmset.length, (index) {
                return Chip(
                  avatar: CircleAvatar(backgroundColor: colors[index]),
                  label: Text(categoryOmset.keys.elementAt(index)),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. DAFTAR PRODUK TERLARIS
  Widget _buildTopProducts(List<OrderSummary> allHistory) {
    final Map<String, int> productQty = {};

    for (var order in allHistory) {
      for (var item in order.items) {
        productQty[item.nama] = (productQty[item.nama] ?? 0) + item.qty;
      }
    }

    // Urutkan map berdasarkan value (qty)
    final sortedProducts = productQty.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Ambil 5 teratas
    final top5Products = sortedProducts.take(5).toList();

    if (top5Products.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("Belum ada produk terjual."),
        ),
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "5 Produk Terlaris (Semua Transaksi)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...top5Products.map((product) {
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    (top5Products.indexOf(product) + 1).toString(),
                  ),
                ),
                title: Text(product.key),
                trailing: Text(
                  '${product.value}x Terjual',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
