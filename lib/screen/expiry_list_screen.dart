import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/service/flutter_cart_service.dart';
import '/service/product_repository.dart'; // Import Repository

class ExpiryListScreen extends StatefulWidget {
  const ExpiryListScreen({Key? key}) : super(key: key);

  @override
  State<ExpiryListScreen> createState() => ExpiryListScreenState();
}

class ExpiryListScreenState extends State<ExpiryListScreen> {
  // Use Repository instead of direct HTTP
  final ProductRepository _productRepository = ProductRepository();
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = _productRepository.getProducts();
  }

  void refreshProducts() {
    setState(() {
      _productsFuture = _productRepository.getProducts();
    });
  }

  /// Helper untuk menghitung sisa hari
  int? _getDaysUntilExpiry(String? expiryDateString) {
    if (expiryDateString == null || expiryDateString.isEmpty) {
      return null;
    }
    try {
      final expiryDate = DateTime.parse(expiryDateString);
      final today = DateTime.now();
      final todayMidnight = DateTime(today.year, today.month, today.day);
      final difference = expiryDate.difference(todayMidnight).inDays;
      return difference;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Tidak ada produk.'));
          }

          final allProducts = snapshot.data!;

          // --- Logika Filter dan Urut ---
          final List<Map<String, dynamic>> expiringProducts = [];
          for (var product in allProducts) {
            final daysLeft = _getDaysUntilExpiry(product.tanggalKadaluwarsa);
            if (daysLeft != null) {
              expiringProducts.add({'product': product, 'daysLeft': daysLeft});
            }
          }

          expiringProducts
              .sort((a, b) => a['daysLeft'].compareTo(b['daysLeft']));
          // --- Selesai Logika ---

          if (expiringProducts.isEmpty) {
            return const Center(
              child: Text('Tidak ada produk dengan tanggal kadaluwarsa.'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => refreshProducts(),
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: expiringProducts.length,
              itemBuilder: (context, index) {
                final item = expiringProducts[index];
                final Product product = item['product'];
                final int daysLeft = item['daysLeft'];

                Color chipColor = Colors.green.shade100;
                Color textColor = Colors.green.shade900;
                String expiryText = '$daysLeft hari lagi';

                if (daysLeft <= 0) {
                  chipColor = Colors.grey.shade300;
                  textColor = Colors.black;
                  expiryText = 'Kadaluwarsa';
                } else if (daysLeft <= 7) {
                  chipColor = Colors.red.shade100;
                  textColor = Colors.red.shade900;
                } else if (daysLeft <= 30) {
                  chipColor = Colors.amber.shade100;
                  textColor = Colors.amber.shade900;
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    title: Text(product.nama,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'Stok: ${product.stok} | Kadaluwarsa: ${DateFormat('d MMM yyyy', 'id_ID').format(DateTime.parse(product.tanggalKadaluwarsa!))}'),
                    trailing: Chip(
                      label: Text(expiryText),
                      backgroundColor: chipColor,
                      labelStyle: TextStyle(
                          color: textColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
