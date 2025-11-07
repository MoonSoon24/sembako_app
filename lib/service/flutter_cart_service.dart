import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '/app_config.dart';

// --- MODEL DEFINITIONS ---

/// Represents a single product from your spreadsheet.
class Product {
  final String nama;
  final int stok;
  final int harga;
  final String kategori;

  Product(
      {required this.nama,
      required this.stok,
      required this.harga,
      required this.kategori});

  /// Creates a Product from the JSON provided by your Google Apps Script.
  /// It expects keys that match your *exact* column headers.
  factory Product.fromJson(Map<String, dynamic> json) {
    // We use `int.tryParse()` to safely convert the values.
    // .toString() handles numbers (e.g., 100) and strings (e.g., "100").
    // If the value is null or "abc", it will safely become 0.
    return Product(
      nama: json['nama'] ?? 'Nama Tidak Diketahui',
      stok: int.tryParse(json['stok'].toString()) ?? 0,
      harga: int.tryParse(json['harga'].toString()) ?? 0,
      kategori: json['kategori'] ?? 'kategori Tidak ditemukan',
    );
  }
}

/// A wrapper class that holds a Product and the quantity in the cart.
class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  /// Calculates the subtotal for this item.
  int get subtotal => product.harga * quantity;

  // --- MODIFIED: ADDED THIS METHOD ---
  /// Converts the cart item to a JSON-serializable map.
  Map<String, dynamic> toJson() {
    return {
      'nama': product.nama,
      'qty': quantity,
      'price_per_item': product.harga,
    };
  }
}

// --- SERVICE CLASS (State Management) ---

/// This class manages the app's state (the shopping cart).
/// Other widgets can "listen" to this class for changes.
class CartService extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // Public getter for the items (as a list)
  List<CartItem> get items => _items.values.toList();

  /// Adds a product to the cart or increments its quantity.
  void addItem(Product product) {
    if (_items.containsKey(product.nama)) {
      // If item already exists, increment quantity
      _items[product.nama]!.quantity++;
    } else {
      // Otherwise, add new item to cart
      _items[product.nama] = CartItem(product: product);
    }
    // Tell all listening widgets to rebuild
    notifyListeners();
  }

  void removeItem(Product product) {
    if (_items.containsKey(product.nama)) {
      // If item exists, decrement quantity
      _items[product.nama]!.quantity--;

      // If quantity drops to 0, remove the item from the map
      if (_items[product.nama]!.quantity <= 0) {
        _items.remove(product.nama);
      }

      // Tell all listening widgets to rebuild
      notifyListeners();
    }
  }

  /// --- NEW METHOD ---
  /// Sets the quantity of a product in the cart to a specific amount.
  /// If the quantity is 0 or less, the item is removed.
  void setItemQuantity(Product product, int quantity) {
    if (quantity <= 0) {
      // If quantity is 0 or less, remove it
      if (_items.containsKey(product.nama)) {
        _items.remove(product.nama);
      }
    } else {
      // Otherwise, set it
      if (_items.containsKey(product.nama)) {
        // If item exists, update its quantity
        _items[product.nama]!.quantity = quantity;
      } else {
        // If it doesn't exist (e.g., user types in 5), add it
        _items[product.nama] = CartItem(product: product, quantity: quantity);
      }
    }
    notifyListeners();
  }

  /// --- NEW METHOD ---
  /// Gets the current quantity of a specific product in the cart.
  int getProductQuantity(Product product) {
    if (_items.containsKey(product.nama)) {
      return _items[product.nama]!.quantity;
    }
    return 0; // Not in cart
  }

  /// Clears all items from the cart.
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  /// Calculates the total harga of all items in the cart.
  int get totalPrice {
    // Use fold to sum up the prices of all items.
    return _items.values.fold(0, (total, item) => total + item.subtotal);
  }

  // --- API CALL ---

  /// Submits the order to your Google Apps Script using GET.
  Future<bool> placeOrder(
      {required String userName,
      required int paymentAmount,
      required int change,
      required String paymentMethod}) async {
    // Check if the URL is still the placeholder.
    if (kApiUrl.contains("YOUR_DEPLOYMENT_ID")) {
      print("---------------------------------------------------------");
      print("---         !!! ACTION REQUIRED !!!                   ---");
      print("---   'Order Gagal' because your API URL is not set.  ---");
      print("---   Please replace 'YOUR_DEPLOYMENT_ID' in        ---");
      print("---   flutter_cart_service.dart with your real URL.   ---");
      print("---------------------------------------------------------");
      return false; // Fail fast so you can see this error
    }

    if (items.isEmpty) return false;

    // --- MODIFIED: Use the new toJson() method ---
    final orderItems = items.map((item) => item.toJson()).toList();

    // --- THIS IS THE NEW FIX ---
    // We send all data as URL-encoded parameters in a GET request.

    // 1. Create the query parameters
    // --- MODIFIED: Added .toString() to int values ---
    final queryParams = {
      'action': 'placeOrder',
      'secret': kSecretKey,
      'userName': userName,
      'paymentAmount': paymentAmount.toString(), // <-- FIX
      'change': change.toString(), // <-- FIX
      'paymentMethod': paymentMethod,
      'total': totalPrice.toString(),
      'items': jsonEncode(orderItems), // Send the list as a JSON string
    };

    // 2. Create the full URL with encoded parameters
    // We need to build the query string manually to ensure correct encoding
    final baseUri = Uri.parse(kApiUrl);
    final urlWithParams = baseUri.replace(queryParameters: queryParams);

    try {
      // 3. Make the GET request
      // --- MODIFIED: Added a timeout ---
      final response = await http.get(urlWithParams).timeout(
            const Duration(seconds: 30),
          );

      // Now we can trust the 200 OK response and the JSON body
      if (response.statusCode == 200) {
        // We MUST parse the JSON body to confirm success.
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          // This is the ONLY success path.
          clearCart();
          return true;
        } else {
          // The script reported an error (e.g., "Invalid authentication")
          print(
              'Apps Script Error: ${data['error'] ?? 'Unknown error from script'}');
          return false; // <-- This correctly handles the "wrong key" test.
        }
      } else {
        // The server returned a real error (404, 500, etc.)
        print('HTTP Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      // A network error or JSON parsing error occurred
      print('Network or Parsing Error: $e');
      return false;
    }
  }
}
