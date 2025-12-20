import 'dart:convert';
import 'package:http/http.dart' as http;
import '/service/flutter_cart_service.dart';
import '/service/database_helper.dart';
import '/app_config.dart';

class ProductRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final String _apiUrl = kApiUrl;

  Future<List<Product>> getProducts() async {
    try {
      // 1. Try Fetching from API (Online)
      final queryParams = {
        'action': 'getProducts',
        'secret': kSecretKey,
      };

      final uri = Uri.parse(_apiUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map && data['error'] != null) {
          throw Exception(data['error']);
        }

        List<dynamic> jsonList;
        // Handle if response is wrapped in 'products' key or is direct list
        if (data is Map && data.containsKey('products')) {
          jsonList = data['products'];
        } else if (data is List) {
          jsonList = data;
        } else {
          throw Exception("Invalid JSON format");
        }

        List<Product> products =
            jsonList.map((json) => Product.fromJson(json)).toList();

        // 2. Save to Local DB (Cache)
        await _saveProductsToLocal(products);
        return products;
      } else {
        throw Exception('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      print("Offline/Error Mode: Fetching from Local DB... ($e)");
      // 3. Fallback to Local DB (Offline)
      return await _getLocalProducts();
    }
  }

  Future<void> _saveProductsToLocal(List<Product> products) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(DatabaseHelper.tableProducts); // Clear old cache
      for (var product in products) {
        await txn.insert(DatabaseHelper.tableProducts, {
          'nama': product.nama,
          'stok': product.stok,
          'hargaJual': product.hargaJual,
          'hargaBeli': product.hargaBeli,
          'kategori': product.kategori,
          'tanggalKadaluwarsa': product.tanggalKadaluwarsa,
        });
      }
    });
  }

  Future<List<Product>> _getLocalProducts() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps =
        await db.query(DatabaseHelper.tableProducts);

    return maps.map((map) {
      return Product.fromJson({
        'nama': map['nama'],
        'stok': map['stok'],
        'harga_jual': map['hargaJual'],
        'harga_beli': map['hargaBeli'],
        'kategori': map['kategori'],
        'tanggal_kadaluwarsa': map['tanggalKadaluwarsa'],
      });
    }).toList();
  }

  // Helper for Categories (Unique list from products)
  Future<List<String>> getCategories() async {
    final products = await getProducts(); // This gets from Online or Offline
    final categories = products.map((p) => p.kategori).toSet().toList();
    categories.sort();
    return categories;
  }

  Future<List<Map<String, dynamic>>> fetchTransactions() async {
    try {
      final response =
          await http.get(Uri.parse("$kApiUrl?action=getTransactions"));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      throw Exception('Gagal memuat transaksi');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // 3. Fetch Paylater
  Future<List<Map<String, dynamic>>> fetchPaylater() async {
    try {
      final response = await http.get(Uri.parse("$kApiUrl?action=getPaylater"));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      throw Exception('Gagal memuat piutang');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}
