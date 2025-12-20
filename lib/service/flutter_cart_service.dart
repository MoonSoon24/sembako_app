import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '/app_config.dart';

// --- MODEL DEFINITIONS ---

/// Mewakili satu produk dari sheet 'barang' Anda.
class Product {
  final String nama;
  final int stok;
  final int hargaJual;
  final int hargaBeli;
  final String kategori;
  final String? tanggalKadaluwarsa; // <-- PERUBAHAN NAMA

  Product({
    required this.nama,
    required this.stok,
    required this.hargaJual,
    required this.hargaBeli,
    required this.kategori,
    this.tanggalKadaluwarsa, // <-- PERUBAHAN NAMA
  });

  /// Membuat Produk dari JSON yang diberikan oleh Google Apps Script Anda.
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      nama: json['nama'] ?? 'Nama Tidak Diketahui',
      stok: int.tryParse(json['stok'].toString()) ?? 0,
      hargaJual: int.tryParse(json['harga_jual'].toString()) ?? 0,
      hargaBeli: int.tryParse(json['harga_beli'].toString()) ?? 0,
      kategori: json['kategori'] ?? 'Lainnya',
      tanggalKadaluwarsa: json['tanggal_kadaluwarsa'], // <-- PERUBAHAN NAMA
    );
  }
}

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  // Updated subtotal logic
  int get subtotal {
    if (product.kategori == 'Top Up') {
      // (Nominal * Multiplier) + Admin Fee
      return (quantity * product.hargaJual) + product.hargaBeli;
    }
    return product.hargaJual * quantity;
  }

  // Updated modal (cost) logic
  int get totalModal {
    if (product.kategori == 'Top Up') {
      // The "cost" to the shop is just the nominal amount sent to the user
      return quantity * product.hargaJual;
    }
    return product.hargaBeli * quantity;
  }

  int get subtotalMargin => subtotal - totalModal;

  Map<String, dynamic> toJson() {
    return {
      'nama': product.nama,
      'kuantitas': quantity,
      'harga_jual': product.hargaJual,
      'harga_beli': product.hargaBeli,
      'kategori': product.kategori, // Added to help report identification
    };
  }
}

// --- SERVICE CLASS (State Management) ---

class CartService extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  void addItem(Product product) {
    if (_items.containsKey(product.nama)) {
      _items[product.nama]!.quantity++;
    } else {
      _items[product.nama] = CartItem(product: product);
    }
    notifyListeners();
  }

  void removeItem(Product product) {
    if (_items.containsKey(product.nama)) {
      _items[product.nama]!.quantity--;
      if (_items[product.nama]!.quantity <= 0) {
        _items.remove(product.nama);
      }
      notifyListeners();
    }
  }

  void setItemQuantity(Product product, int quantity) {
    if (quantity <= 0) {
      if (_items.containsKey(product.nama)) {
        _items.remove(product.nama);
      }
    } else {
      if (_items.containsKey(product.nama)) {
        _items[product.nama]!.quantity = quantity;
      } else {
        _items[product.nama] = CartItem(product: product, quantity: quantity);
      }
    }
    notifyListeners();
  }

  int getProductQuantity(Product product) {
    return _items[product.nama]?.quantity ?? 0;
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  /// Kalkulasi total harga jual (omset) dari keranjang.
  int get totalPrice {
    return _items.values.fold(0, (total, item) => total + item.subtotal);
  }

  /// <-- BARU: Kalkulasi total margin (profit) dari keranjang.
  int get totalMargin {
    return _items.values.fold(0, (total, item) => total + item.subtotalMargin);
  }

  /// Mengirim pesanan ke Google Apps Script.
  Future<bool> placeOrder({
    required String userName,
    required int paymentAmount,
    required int change,
    required String paymentMethod,
  }) async {
    if (kApiUrl.contains("YOUR_DEPLOYMENT_ID")) {
      print("--- ERROR: API URL belum diatur ---");
      return false;
    }

    if (items.isEmpty) return false;

    // Gunakan method toJson() yang sudah diperbarui
    final orderItems = items.map((item) => item.toJson()).toList();

    final queryParams = {
      'action': 'placeOrder',
      'secret': kSecretKey,
      'userName': userName,
      'paymentAmount': paymentAmount.toString(),
      'change': change.toString(),
      'paymentMethod': paymentMethod,
      'total': totalPrice.toString(), // Ini adalah 'Total Belanja'
      'items': jsonEncode(
          orderItems), // Mengirim JSON (nama, kuantitas, harga_jual, harga_beli)
    };

    final baseUri = Uri.parse(kApiUrl);
    final urlWithParams = baseUri.replace(queryParameters: queryParams);

    try {
      final response = await http.get(urlWithParams).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          clearCart();
          return true;
        } else {
          print('Apps Script Error: ${data['error'] ?? 'Unknown error'}');
          return false;
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Network or Parsing Error: $e');
      return false;
    }
  }
}
