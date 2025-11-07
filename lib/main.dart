import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '/service/flutter_cart_service.dart'; // Layanan keranjang Anda
import '/screen/product_list_screen.dart';
import '/screen/cart_screen.dart';
import '/screen/history_screen.dart';
import '/service/stock_cart_service.dart'; // <-- IMPORT BARU

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  runApp(
    // --- PERUBAHAN DI SINI ---
    // Gunakan MultiProvider untuk menyediakan CartService dan StockCartService
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => CartService()),
        ChangeNotifierProvider(
            create: (context) => StockCartService()), // <-- PROVIDER BARU
      ],
      child: const MyApp(),
    ),
    // --- AKHIR PERUBAHAN ---
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Toko Sembako',
      theme: ThemeData(
        // ... (Tema Anda tetap sama)
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
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
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

// ... (Sisa file main.dart (class MainScreen dan MainScreenState)
// ... tidak perlu diubah dan tetap sama seperti sebelumnya)

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

  late final List<Widget> _screens;

  final List<String> _titles = [
    'Daftar Barang',
    'Riwayat Transaksi',
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      ProductListScreen(key: _productListKey),
      HistoryScreen(key: _historyKey, selectedDate: _selectedDate),
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
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
    _updateHistoryScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedScreenIndex]),
        actions: [
          if (_selectedScreenIndex == 0 || _selectedScreenIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (_selectedScreenIndex == 0) {
                  _productListKey.currentState?.refreshProducts();
                } else if (_selectedScreenIndex == 1) {
                  _historyKey.currentState?.refreshHistory();
                }
              },
              tooltip: 'Muat Ulang Data',
            ),
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
