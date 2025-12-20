import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_models.dart';
import '../service/history_repository.dart'; // Import Repository

enum LaporanLevel { yearly, monthly, weekly, daily }

class DashboardLaporanScreen extends StatefulWidget {
  const DashboardLaporanScreen({Key? key}) : super(key: key);

  @override
  State<DashboardLaporanScreen> createState() => DashboardLaporanScreenState();
}

class DashboardLaporanScreenState extends State<DashboardLaporanScreen> {
  // Use Repository
  final HistoryRepository _historyRepository = HistoryRepository();
  late Future<List<OrderSummary>> _historyFuture;

  final NumberFormat _rupiahFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  LaporanLevel _currentLevel = LaporanLevel.yearly;
  int? _selectedYear;
  int? _selectedMonth; // 1-12
  DateTime? _selectedWeekStartDate;

  List<OrderSummary>? _allCachedHistory;

  final DateFormat _monthYearFormat = DateFormat('MMMM yyyy', 'id_ID');
  final DateFormat _yearFormat = DateFormat('yyyy');
  final DateFormat _monthFormat = DateFormat('MMMM', 'id_ID');

  @override
  void initState() {
    super.initState();
    _historyFuture = _historyRepository.getHistory();
  }

  void refreshData() {
    setState(() {
      _allCachedHistory = null;
      _currentLevel = LaporanLevel.yearly;
      _selectedYear = null;
      _selectedMonth = null;
      _selectedWeekStartDate = null;

      _historyFuture = _historyRepository.getHistory();
    });
  }

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

          _allCachedHistory ??= snapshot.data!;

          final lunasHistory =
              _allCachedHistory!.where((o) => o.status == 'Lunas').toList();

          final allHistory = _allCachedHistory!;

          return RefreshIndicator(
            onRefresh: () async => refreshData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNavigation(),
                  const SizedBox(height: 16),
                  _buildOmsetChart(lunasHistory),
                  const SizedBox(height: 16),
                  _buildCategoryPieChart(lunasHistory),
                  const SizedBox(height: 16),
                  _buildTopProducts(allHistory),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavigation() {
    String title;
    switch (_currentLevel) {
      case LaporanLevel.yearly:
        title = "Laporan Tahunan";
        break;
      case LaporanLevel.monthly:
        title = "Laporan Bulanan $_selectedYear";
        break;
      case LaporanLevel.weekly:
        title =
            "Laporan Mingguan (${_monthFormat.format(DateTime(_selectedYear!, _selectedMonth!))} $_selectedYear)";
        break;
      case LaporanLevel.daily:
        final tgl = _selectedWeekStartDate!;
        title = "Laporan Harian (Mulai ${tgl.day}/${tgl.month})";
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          if (_currentLevel != LaporanLevel.yearly)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: _navigateBack,
              tooltip: "Kembali",
            ),
          if (_currentLevel == LaporanLevel.yearly) const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateBack() {
    setState(() {
      if (_currentLevel == LaporanLevel.daily) {
        _currentLevel = LaporanLevel.weekly;
        _selectedWeekStartDate = null;
      } else if (_currentLevel == LaporanLevel.weekly) {
        _currentLevel = LaporanLevel.monthly;
        _selectedMonth = null;
      } else if (_currentLevel == LaporanLevel.monthly) {
        _currentLevel = LaporanLevel.yearly;
        _selectedYear = null;
      }
    });
  }

  void _drillDown(LaporanLevel nextLevel, int tappedValue) {
    setState(() {
      _currentLevel = nextLevel;
      if (nextLevel == LaporanLevel.monthly) {
        _selectedYear = tappedValue;
      } else if (nextLevel == LaporanLevel.weekly) {
        _selectedMonth = tappedValue;
      } else if (nextLevel == LaporanLevel.daily) {
        _selectedWeekStartDate = _calculateWeekStartDate(
            _selectedYear!, _selectedMonth!, tappedValue);
      }
    });
  }

  Widget _buildOmsetChart(List<OrderSummary> lunasHistory) {
    BarChartData chartData;
    String titleSuffix = "";

    switch (_currentLevel) {
      case LaporanLevel.yearly:
        chartData = _buildYearlyChart(lunasHistory);
        titleSuffix = "Per Tahun";
        break;
      case LaporanLevel.monthly:
        chartData = _buildMonthlyChart(lunasHistory, _selectedYear!);
        titleSuffix = "Per Bulan $_selectedYear";
        break;
      case LaporanLevel.weekly:
        chartData =
            _buildWeeklyChart(lunasHistory, _selectedYear!, _selectedMonth!);
        titleSuffix =
            "Per Minggu (${_monthFormat.format(DateTime(_selectedYear!, _selectedMonth!))})";
        break;
      case LaporanLevel.daily:
        chartData = _buildDailyChart(lunasHistory, _selectedWeekStartDate!);
        final tgl = _selectedWeekStartDate!;
        titleSuffix = "Per Hari (Mulai ${tgl.day}/${tgl.month})";
        break;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Omset Lunas $titleSuffix",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(chartData),
            ),
          ],
        ),
      ),
    );
  }

  BarChartData _buildYearlyChart(List<OrderSummary> lunasHistory) {
    if (lunasHistory.isEmpty) return BarChartData();

    final Map<int, double> yearlyOmset = {};
    int minYear = lunasHistory.first.timestamp.year;
    int maxYear = lunasHistory.last.timestamp.year;

    for (int y = minYear; y <= maxYear; y++) {
      yearlyOmset[y] = 0.0;
    }
    double maxOmset = 0;

    for (var order in lunasHistory) {
      final year = order.timestamp.year;
      yearlyOmset[year] = (yearlyOmset[year] ?? 0.0) + order.totalPrice;
      if (yearlyOmset[year]! > maxOmset) {
        maxOmset = yearlyOmset[year]!;
      }
    }

    final List<BarChartGroupData> barGroups = [];
    for (int y = minYear; y <= maxYear; y++) {
      barGroups.add(
        BarChartGroupData(
          x: y,
          barRods: [
            BarChartRodData(
              toY: yearlyOmset[y] ?? 0.0,
              color: Colors.red,
              width: 25,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barTouchData: _getTouchData(LaporanLevel.monthly),
      maxY: max(maxOmset * 1.2, 1000000),
      gridData: _omsetGridData(maxOmset),
      titlesData: FlTitlesData(
        leftTitles: _omsetLeftTitles(maxOmset),
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            getTitlesWidget: (value, meta) {
              return Text(value.toInt().toString(),
                  style: const TextStyle(fontSize: 12));
            },
          ),
        ),
      ),
      barGroups: barGroups,
    );
  }

  BarChartData _buildMonthlyChart(List<OrderSummary> lunasHistory, int year) {
    final dataTahunIni =
        lunasHistory.where((o) => o.timestamp.year == year).toList();

    final Map<int, double> monthlyOmset = {};
    for (int i = 1; i <= 12; i++) {
      monthlyOmset[i] = 0.0;
    }
    double maxOmset = 0;

    for (var order in dataTahunIni) {
      final month = order.timestamp.month;
      monthlyOmset[month] = (monthlyOmset[month] ?? 0.0) + order.totalPrice;
      if (monthlyOmset[month]! > maxOmset) {
        maxOmset = monthlyOmset[month]!;
      }
    }

    final List<BarChartGroupData> barGroups = [];
    for (int m = 1; m <= 12; m++) {
      barGroups.add(
        BarChartGroupData(
          x: m,
          barRods: [
            BarChartRodData(
              toY: monthlyOmset[m] ?? 0.0,
              color: Colors.orange,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barTouchData: _getTouchData(LaporanLevel.weekly),
      maxY: max(maxOmset * 1.2, 1000000),
      gridData: _omsetGridData(maxOmset),
      titlesData: FlTitlesData(
        leftTitles: _omsetLeftTitles(maxOmset),
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              String text;
              switch (value.toInt()) {
                case 1:
                  text = 'J';
                  break;
                case 2:
                  text = 'F';
                  break;
                case 3:
                  text = 'M';
                  break;
                case 4:
                  text = 'A';
                  break;
                case 5:
                  text = 'M';
                  break;
                case 6:
                  text = 'J';
                  break;
                case 7:
                  text = 'J';
                  break;
                case 8:
                  text = 'A';
                  break;
                case 9:
                  text = 'S';
                  break;
                case 10:
                  text = 'O';
                  break;
                case 11:
                  text = 'N';
                  break;
                case 12:
                  text = 'D';
                  break;
                default:
                  text = '';
              }
              return Text(text, style: const TextStyle(fontSize: 12));
            },
          ),
        ),
      ),
      barGroups: barGroups,
    );
  }

  BarChartData _buildWeeklyChart(
      List<OrderSummary> lunasHistory, int year, int month) {
    final dataBulanIni = lunasHistory
        .where((o) => o.timestamp.year == year && o.timestamp.month == month)
        .toList();

    final Map<int, double> weeklyOmset = {};
    for (int i = 1; i <= 5; i++) {
      weeklyOmset[i] = 0.0;
    }
    double maxOmset = 0;

    DateTime firstDayOfMonth = DateTime(year, month, 1);
    DateTime startOfWeek1 =
        firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));

    for (var order in dataBulanIni) {
      int daysDifference = order.timestamp.difference(startOfWeek1).inDays;
      int weekNumber = (daysDifference / 7).floor() + 1;

      if (weekNumber >= 1 && weekNumber <= 5) {
        weeklyOmset[weekNumber] =
            (weeklyOmset[weekNumber] ?? 0.0) + order.totalPrice;
        if (weeklyOmset[weekNumber]! > maxOmset) {
          maxOmset = weeklyOmset[weekNumber]!;
        }
      } else if (weekNumber < 1) {
        weeklyOmset[1] = (weeklyOmset[1] ?? 0.0) + order.totalPrice;
        if (weeklyOmset[1]! > maxOmset) {
          maxOmset = weeklyOmset[1]!;
        }
      }
    }

    DateTime lastDayOfMonth = DateTime(year, month + 1, 0);
    int daysDifference = lastDayOfMonth.difference(startOfWeek1).inDays;
    int totalWeeks = (daysDifference / 7).floor() + 1;

    final List<BarChartGroupData> barGroups = [];
    for (int w = 1; w <= totalWeeks; w++) {
      barGroups.add(
        BarChartGroupData(
          x: w,
          barRods: [
            BarChartRodData(
              toY: weeklyOmset[w] ?? 0.0,
              color: Colors.green,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barTouchData: _getTouchData(LaporanLevel.daily),
      maxY: max(maxOmset * 1.2, 500000),
      gridData: _omsetGridData(maxOmset),
      titlesData: FlTitlesData(
        leftTitles: _omsetLeftTitles(maxOmset),
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              return Text("M${value.toInt()}",
                  style: const TextStyle(fontSize: 12));
            },
          ),
        ),
      ),
      barGroups: barGroups,
    );
  }

  BarChartData _buildDailyChart(
      List<OrderSummary> lunasHistory, DateTime weekStartDate) {
    DateTime weekEndDate = weekStartDate.add(const Duration(days: 7));
    final dataMingguIni = lunasHistory
        .where((o) =>
            !o.timestamp.isBefore(weekStartDate) &&
            o.timestamp.isBefore(weekEndDate))
        .toList();

    final Map<int, double> dailyOmset = {};
    for (int i = 1; i <= 7; i++) {
      dailyOmset[i] = 0.0;
    }
    double maxOmset = 0;

    for (var order in dataMingguIni) {
      final weekday = order.timestamp.weekday;
      dailyOmset[weekday] = (dailyOmset[weekday] ?? 0.0) + order.totalPrice;
      if (dailyOmset[weekday]! > maxOmset) {
        maxOmset = dailyOmset[weekday]!;
      }
    }

    final List<BarChartGroupData> barGroups = [];
    for (int d = 1; d <= 7; d++) {
      barGroups.add(
        BarChartGroupData(
          x: d,
          barRods: [
            BarChartRodData(
              toY: dailyOmset[d] ?? 0.0,
              color: Colors.blue,
              width: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChartData(
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            return BarTooltipItem(
              _rupiahFormat.format(rod.toY),
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            );
          },
        ),
      ),
      maxY: max(maxOmset * 1.2, 100000),
      gridData: _omsetGridData(maxOmset),
      titlesData: FlTitlesData(
        leftTitles: _omsetLeftTitles(maxOmset),
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
              return Text(text, style: const TextStyle(fontSize: 12));
            },
          ),
        ),
      ),
      barGroups: barGroups,
    );
  }

  BarTouchData _getTouchData(LaporanLevel nextLevel) {
    return BarTouchData(
      touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
        if (event is FlTapUpEvent &&
            response != null &&
            response.spot != null) {
          final int tappedValue = response.spot!.touchedBarGroup.x;

          _drillDown(nextLevel, tappedValue);
        }
      },
      touchTooltipData: BarTouchTooltipData(
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          return BarTooltipItem(
            _rupiahFormat.format(rod.toY),
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          );
        },
      ),
    );
  }

  DateTime _calculateWeekStartDate(int year, int month, int weekOfMonth) {
    DateTime firstDayOfMonth = DateTime(year, month, 1);
    DateTime startOfWeek1 =
        firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));

    return startOfWeek1.add(Duration(days: (weekOfMonth - 1) * 7));
  }

  FlGridData _omsetGridData(double maxOmset) {
    double interval;
    if (maxOmset > 10000000)
      interval = 5000000;
    else if (maxOmset > 2000000)
      interval = 500000;
    else if (maxOmset > 500000)
      interval = 100000;
    else
      interval = 50000;

    return FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (value) =>
          const FlLine(color: Colors.grey, strokeWidth: 0.5),
      horizontalInterval: interval,
    );
  }

  AxisTitles _omsetLeftTitles(double maxOmset) {
    return AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 60,
        getTitlesWidget: (value, meta) {
          if (value == 0 || value > maxOmset) return const SizedBox();
          String text;
          if (value >= 1000000) {
            text = '${(value / 1000000).toStringAsFixed(0)}jt';
          } else {
            text = '${(value / 1000).toStringAsFixed(0)}k';
          }
          return Text(text,
              style: const TextStyle(fontSize: 10), textAlign: TextAlign.left);
        },
      ),
    );
  }

  Widget _buildCategoryPieChart(List<OrderSummary> allLunasHistory) {
    final List<OrderSummary> filteredHistory =
        _filterHistoryByState(allLunasHistory);

    final Map<String, double> categoryOmset = {};
    double totalOmset = 0;

    for (var order in filteredHistory) {
      for (var item in order.items) {
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
          child: Text("Belum ada data kategori untuk periode ini."),
        ),
      );
    }

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
              "Omset Kategori (Lunas)",
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

  Widget _buildTopProducts(List<OrderSummary> allHistory) {
    final List<OrderSummary> filteredHistory =
        _filterHistoryByState(allHistory);

    final Map<String, int> productQty = {};

    for (var order in filteredHistory) {
      for (var item in order.items) {
        productQty[item.nama] = (productQty[item.nama] ?? 0) + item.qty;
      }
    }

    final sortedProducts = productQty.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top5Products = sortedProducts.take(5).toList();

    if (top5Products.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("Belum ada produk terjual untuk periode ini."),
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
              "5 Produk Terlaris",
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

  List<OrderSummary> _filterHistoryByState(List<OrderSummary> fullHistory) {
    switch (_currentLevel) {
      case LaporanLevel.yearly:
        return fullHistory;

      case LaporanLevel.monthly:
        return fullHistory
            .where((o) => o.timestamp.year == _selectedYear)
            .toList();

      case LaporanLevel.weekly:
        return fullHistory
            .where((o) =>
                o.timestamp.year == _selectedYear &&
                o.timestamp.month == _selectedMonth)
            .toList();

      case LaporanLevel.daily:
        if (_selectedWeekStartDate == null) return [];
        final weekEndDate =
            _selectedWeekStartDate!.add(const Duration(days: 7));
        return fullHistory
            .where((o) =>
                !o.timestamp.isBefore(_selectedWeekStartDate!) &&
                o.timestamp.isBefore(weekEndDate))
            .toList();
    }
  }
}
