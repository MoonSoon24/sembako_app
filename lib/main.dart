import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '/service/flutter_cart_service.dart'; // Layanan keranjang Anda
import '/screen/product_list_screen.dart';
import '/screen/cart_screen.dart';
import '/screen/history_screen.dart';
import '/screen/expiry_list_screen.dart';
import '/screen/paylater_screen.dart'; // <-- BARU: Layar Piutang
import '/screen/dashboard_laporan_screen.dart'; // <-- BARU: Layar Laporan
import '/service/stock_cart_service.dart';
import '/service/theme_service.dart';
import '/service/transaction_sync.dart';
import '/widget/offline_indicator.dart';
import '/screen/offline_transaction_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  TransactionSyncService().startAutoSync();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => CartService()),
        ChangeNotifierProvider(create: (context) => StockCartService()),
        ChangeNotifierProvider(create: (context) => ThemeService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    return MaterialApp(
      title: 'Toko Sembako',
      themeMode: themeService.themeMode,

      // --- Light Theme ---
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue.shade800,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // --- Dark Theme ---
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),

      debugShowCheckedModeBanner: false,

      // --- Implementasi Offline Indicator ---
      home: const OfflineIndicator(
        child: MainScreen(),
      ),

      locale: const Locale('id', 'ID'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedScreenIndex = 0;
  DateTime? _selectedDate;

  final GlobalKey<ProductListScreenState> _productListKey =
      GlobalKey<ProductListScreenState>();
  final GlobalKey<HistoryScreenState> _historyKey =
      GlobalKey<HistoryScreenState>();
  final GlobalKey<ExpiryListScreenState> _expiryListKey =
      GlobalKey<ExpiryListScreenState>();
  final GlobalKey<PayLaterScreenState> _payLaterKey =
      GlobalKey<PayLaterScreenState>();
  final GlobalKey<DashboardLaporanScreenState> _dashboardKey =
      GlobalKey<DashboardLaporanScreenState>();

  late final List<Widget> _screens;

  final List<String> _titles = [
    'Daftar Barang',
    'Riwayat Transaksi',
    'Monitoring Kadaluwarsa',
    'Daftar Piutang (PayLater)',
    'Dashboard Laporan',
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      ProductListScreen(key: _productListKey),
      HistoryScreen(key: _historyKey, selectedDate: _selectedDate),
      ExpiryListScreen(key: _expiryListKey),
      PayLaterScreen(key: _payLaterKey),
      DashboardLaporanScreen(key: _dashboardKey),
    ];
  }

  void _updateHistoryScreen() {
    setState(() {
      _screens[1] =
          HistoryScreen(key: _historyKey, selectedDate: _selectedDate);
    });
  }

  void _selectScreen(int index) {
    setState(() {
      _selectedScreenIndex = index;
    });
    Navigator.pop(context);
  }

  Future<void> _showHistoryDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _updateHistoryScreen();
      // Perbarui juga dashboard jika sedang aktif
      if (_selectedScreenIndex == 4) {
        _dashboardKey.currentState?.refreshData();
      }
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
    _updateHistoryScreen();
    // Perbarui juga dashboard jika sedang aktif
    if (_selectedScreenIndex == 4) {
      _dashboardKey.currentState?.refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedScreenIndex]),
        actions: [
          // Logika refresh
          if ([0, 1, 2, 3, 4].contains(_selectedScreenIndex))
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (_selectedScreenIndex == 0) {
                  _productListKey.currentState?.refreshProducts();
                } else if (_selectedScreenIndex == 1) {
                  _historyKey.currentState?.refreshHistory();
                } else if (_selectedScreenIndex == 2) {
                  _expiryListKey.currentState?.refreshProducts();
                } else if (_selectedScreenIndex == 3) {
                  _payLaterKey.currentState?.refreshData();
                } else if (_selectedScreenIndex == 4) {
                  _dashboardKey.currentState?.refreshData();
                }
              },
              tooltip: 'Muat Ulang Data',
            ),

          // Filter tanggal hanya muncul di Riwayat Transaksi
          if (_selectedScreenIndex == 1) ...[
            if (_selectedDate != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Hapus Filter Tanggal',
                onPressed: _clearDateFilter,
              ),
            TextButton(
              onPressed: _showHistoryDatePicker,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(
                _selectedDate == null
                    ? 'Pilih Tanggal'
                    : DateFormat('d MMM yyyy', 'id_ID').format(_selectedDate!),
              ),
            ),
          ] else
            const SizedBox(width: 10),

          // Menu Pengaturan (3 Dots)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Pengaturan',
            onSelected: (value) {
              if (value == 'theme') {
                context.read<ThemeService>().toggleTheme();
              }
            },
            itemBuilder: (BuildContext context) {
              final isDark = context.read<ThemeService>().isDarkMode;
              return [
                PopupMenuItem<String>(
                  value: 'theme',
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.light_mode : Icons.dark_mode,
                        color: isDark ? Colors.amber : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 12),
                      Text(isDark ? 'Mode Terang' : 'Mode Gelap'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue.shade800,
              ),
              child: const Text(
                'Menu Kios',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Daftar Barang'),
              selected: _selectedScreenIndex == 0,
              onTap: () => _selectScreen(0),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Riwayat Transaksi'),
              selected: _selectedScreenIndex == 1,
              onTap: () => _selectScreen(1),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Monitoring Kadaluwarsa'),
              selected: _selectedScreenIndex == 2,
              onTap: () => _selectScreen(2),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card_off_rounded),
              title: const Text('Daftar Piutang (PayLater)'),
              selected: _selectedScreenIndex == 3,
              onTap: () => _selectScreen(3),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text('Dashboard Laporan'),
              selected: _selectedScreenIndex == 4,
              onTap: () => _selectScreen(4),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sync_problem, color: Colors.orange),
              title: const Text('Transaksi Offline'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const OfflineTransactionScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Keranjang'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CartScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: _screens[_selectedScreenIndex],
    );
  }
}
