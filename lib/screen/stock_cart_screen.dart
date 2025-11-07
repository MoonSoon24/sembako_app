import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '/service/stock_cart_service.dart';
import '../app_config.dart';

class StockCartScreen extends StatefulWidget {
  const StockCartScreen({Key? key}) : super(key: key);

  @override
  State<StockCartScreen> createState() => _StockCartScreenState();
}

class _StockCartScreenState extends State<StockCartScreen> {
  bool _isLoading = false;

  /// Mengirim data stok ke Google Apps Script
  Future<void> _submitStock(StockCartService stockCart) async {
    if (stockCart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada item untuk ditambahkan')),
      );
      return;
    }

    setState(() => _isLoading = true);

    String? errorMessage;
    String successMessage = '';

    try {
      // 1. Format data untuk JSON
      final List<Map<String, dynamic>> itemsJson = stockCart.items
          .map((item) => {
                'nama': item.product.nama, // Skrip butuh 'nama'
                'qty': item.quantity,
              })
          .toList();

      // 2. Siapkan parameter
      final queryParams = {
        'action': 'addStockToMultipleItems', // <-- AKSI BARU
        'secret': kSecretKey,
        'items': jsonEncode(itemsJson), // Kirim sebagai JSON string
      };

      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);

      // 3. Panggil API
      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          successMessage = data['message'] ?? 'Stok berhasil diperbarui!';
        } else {
          errorMessage = data['error'] ?? 'Terjadi error yang tidak diketahui';
        }
      } else {
        errorMessage = 'Error Server (Status: ${response.statusCode})';
      }
    } catch (e) {
      errorMessage = 'Error koneksi: $e';
    }

    setState(() => _isLoading = false);

    // 4. Tampilkan hasil
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? successMessage),
        backgroundColor: errorMessage != null ? Colors.red : Colors.green,
      ),
    );

    // 5. Jika sukses, bersihkan keranjang stok dan kembali
    if (errorMessage == null) {
      stockCart.clearCart();
      Navigator.pop(context); // Kembali ke layar manage_stock
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StockCartService>(
      builder: (context, stockCart, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Review Tambah Stok'),
          ),
          body: Column(
            children: [
              Expanded(
                child: stockCart.items.isEmpty
                    ? const Center(
                        child: Text('Tidak ada item di keranjang stok.'),
                      )
                    : ListView.builder(
                        itemCount: stockCart.items.length,
                        itemBuilder: (context, index) {
                          final item = stockCart.items[index];

                          final _quantityController = TextEditingController(
                            text: '${item.quantity}',
                          );
                          // Pindahkan kursor ke akhir teks
                          _quantityController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset: _quantityController.text.length),
                          );

                          return ListTile(
                            title: Text(item.product.nama),
                            subtitle:
                                Text('Stok saat ini: ${item.product.stok}'),

                            // Ganti Chip dengan kontrol interaktif
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Tombol Kurang
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: Colors.red.shade700,
                                  onPressed: () {
                                    stockCart.removeItem(item.product);
                                  },
                                ),
                                // Text Field Kuantitas
                                SizedBox(
                                  width: 45,
                                  height: 35,
                                  child: TextField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    // Update saat selesai mengedit
                                    onSubmitted: (value) {
                                      final newQty = int.tryParse(value) ?? 0;
                                      stockCart.setItemQuantity(
                                          item.product, newQty);
                                    },
                                  ),
                                ),
                                // Tombol Tambah
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: Colors.green.shade700,
                                  onPressed: () {
                                    stockCart.addItem(item.product);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              // Tombol Konfirmasi
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isLoading || stockCart.items.isEmpty)
                        ? null
                        : () => _submitStock(stockCart),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          )
                        : const Text('Konfirmasi Tambah Stok'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
