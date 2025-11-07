import 'package:flutter/material.dart';
import 'flutter_cart_service.dart'; // Menggunakan ulang Product dan CartItem

class StockCartService with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  int getProductQuantity(Product product) {
    var item = _items[product.nama]; // Asumsi 'nama' adalah ID unik
    return item?.quantity ?? 0;
  }

  /// Menambah 1 item ke keranjang, atau set kuantitas ke 1 jika belum ada
  void addItem(Product product) {
    if (_items.containsKey(product.nama)) {
      _items.update(
        product.nama,
        (existingItem) => CartItem(
          product: existingItem.product,
          quantity: existingItem.quantity + 1,
        ),
      );
    } else {
      _items.putIfAbsent(
        product.nama,
        () => CartItem(product: product, quantity: 1),
      );
    }
    notifyListeners();
  }

  /// Menghapus 1 item dari keranjang
  void removeItem(Product product) {
    if (!_items.containsKey(product.nama)) return;

    if (_items[product.nama]!.quantity > 1) {
      _items.update(
        product.nama,
        (existingItem) => CartItem(
          product: existingItem.product,
          quantity: existingItem.quantity - 1,
        ),
      );
    } else {
      _items.remove(product.nama);
    }
    notifyListeners();
  }

  /// Mengatur kuantitas item secara spesifik
  void setItemQuantity(Product product, int quantity) {
    if (quantity <= 0) {
      _items.remove(product.nama);
    } else {
      _items.update(
        product.nama,
        (existingItem) => CartItem(
          product: existingItem.product,
          quantity: quantity,
        ),
        ifAbsent: () => CartItem(product: product, quantity: quantity),
      );
    }
    notifyListeners();
  }

  /// Menghapus semua item dari keranjang stok
  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
