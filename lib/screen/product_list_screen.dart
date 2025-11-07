import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '/service/flutter_cart_service.dart';
import 'cart_screen.dart';
import 'add_product_screen.dart';
import '../app_config.dart';
import 'manage_stock_screen.dart';


class ProductListScreen extends StatefulWidget {
  const ProductListScreen({Key? key}) : super(key: key);

  @override
  State<ProductListScreen> createState() => ProductListScreenState();
}

class ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> _productsFuture;

  // --- STATE VARIABLES ---
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Product? _selectedProduct;
  final TextEditingController _quantityController =
      TextEditingController(text: '1');

  // --- NEW STATE FOR FAB ---
  final GlobalKey _panelKey = GlobalKey();
  double _panelHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _productsFuture = fetchProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  /// Memuat ulang data produk dari server.
  void refreshProducts() {
    setState(() {
      _productsFuture = fetchProducts();
    });
  }

  /// Fetches the list of products from your Google Apps Script API
  Future<List<Product>> fetchProducts() async {
    try {
      final queryParams = {
        'action': 'getProducts',
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

        final List<dynamic> productListJson = data['products'];

        final sanitizedList = productListJson.map((json) {
          if (json['nama'] != null) {
            json['nama'] = json['nama'].toString();
          }
          return json;
        }).toList();

        return sanitizedList.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception(
            'Gagal memuat barang (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat barang: $e');
    }
  }

  /// Checks the cart for the quantity of a specific product.
  int _getCartQuantity(CartService cart, Product product) {
    return cart.getProductQuantity(product);
  }

  /// (Feature 3) Builds the search bar
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Cari barang...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = "";
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide(color: Theme.of(context).primaryColor),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  /// (Feature 2) Builds the bottom panel for quantity control
  Widget _buildBottomPanel() {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }

    // --- Measure the panel height after it's built ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _panelKey.currentContext;
      if (context != null) {
        final newHeight = context.size?.height ?? 0;
        if (newHeight != _panelHeight) {
          setState(() {
            _panelHeight = newHeight;
          });
        }
      }
    });

    final cart = context.watch<CartService>();

    final currentQuantity = cart.getProductQuantity(_selectedProduct!);
    if (currentQuantity == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedProduct = null;
          _panelHeight = 0.0;
        });
      });
      return const SizedBox.shrink();
    }

    _quantityController.text = '$currentQuantity';

    return Card(
      key: _panelKey,
      elevation: 12.0,
      margin: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Title and Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedProduct!.nama,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedProduct = null;
                      _panelHeight = 0.0;
                    });
                  },
                )
              ],
            ),
            const SizedBox(height: 12),
            // Row 2: Quantity Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.red.shade700,
                  onPressed: () {
                    cart.removeItem(_selectedProduct!);
                    int newQty = cart.getProductQuantity(_selectedProduct!);
                    if (newQty == 0) {
                      setState(() {
                        _selectedProduct = null;
                        _panelHeight = 0.0;
                      });
                    }
                  },
                ),
                SizedBox(
                  width: 50,
                  height: 35,
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (value) {
                      final newQty = int.tryParse(value) ?? 0;
                      cart.setItemQuantity(_selectedProduct!, newQty);
                      int finalQty = cart.getProductQuantity(_selectedProduct!);
                      setState(() {
                        finalQty = 1;
                        _quantityController.text = '$finalQty';
                        if (finalQty == 0) {
                          _selectedProduct = null;
                          _panelHeight = 0.0;
                        }
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.green.shade700,
                  onPressed: () {
                    cart.addItem(_selectedProduct!);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the Floating Action Button for the cart
  Widget _buildCartFab() {
    return Consumer<CartService>(
      builder: (context, cart, child) {
        final totalItems =
            cart.items.fold<int>(0, (prev, item) => prev + item.quantity);

        return FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CartScreen()),
            );
          },
          label: const Text('Keranjang  \u2192'), // \u2192 is the right arrow
          icon: Badge(
            label: Text('$totalItems'),
            isLabelVisible: totalItems > 0,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
        );
      },
    );
  }

  /// Menampilkan modal untuk memilih aksi admin
  void _showAdminMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        // Gunakan AlertDialog untuk tampilan di tengah
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: const Text(
            'Menu Admin',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Agar tinggi modal pas
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Tombol 1: Tambah Barang Baru
              ElevatedButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Tambah Barang Baru'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  Navigator.pop(ctx); // Tutup dialog
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddProductScreen(),
                    ),
                  );
                  if (result == true) {
                    refreshProducts(); // Panggil fungsi refresh
                  }
                },
              ),
              const SizedBox(height: 12), // Jarak antar tombol

              // Tombol 2: Tambah Stok / Update Harga
              ElevatedButton.icon(
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Manajemen Stok'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
                  Navigator.pop(ctx); // Tutup dialog
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageStockScreen(),
                    ),
                  ).then((_) {
                    // Refresh data setelah kembali dari layar manajemen
                    refreshProducts();
                  });
                },
              ),
            ],
          ),
          actions: [
            // Tombol Tutup
            TextButton(
              child: const Text('Tutup'),
              onPressed: () {
                Navigator.pop(ctx);
              },
            )
          ],
        );
      },
    );
  }

  /// Membangun FAB Admin (+)
  Widget _buildAdminFab() {
    return FloatingActionButton(
      onPressed: () => _showAdminMenu(context),
      backgroundColor: Colors.green.shade700,
      child: const Icon(Icons.add),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Layar ini TIDAK memiliki Scaffold sendiri
    return Stack(
      children: [
        // 1. The main content (your old column)
        Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  // ... (Loading, Error, Empty states are unchanged)
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('Error: ${snapshot.error}'),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                        child: Text('Tidak ada barang yang ditemukan.'));
                  }

                  // ... (Filtering logic is unchanged)
                  final allProducts = snapshot.data!;
                  final filteredProducts = allProducts.where((product) {
                    final nameLower = product.nama.toLowerCase();
                    final queryLower = _searchQuery.toLowerCase();
                    return nameLower.contains(queryLower);
                  }).toList();
                  if (filteredProducts.isEmpty) {
                    return const Center(
                      child: Text('Tidak ada hasil untuk pencarian ini.'),
                    );
                  }

                  return Consumer<CartService>(
                    builder: (context, cart, child) {
                      // --- NEW SORTING LOGIC ---
                      filteredProducts.sort((a, b) {
                        final bool isAInCart = cart.getProductQuantity(a) > 0;
                        final bool isBInCart = cart.getProductQuantity(b) > 0;

                        if (isAInCart && !isBInCart) {
                          return -1;
                        } else if (!isAInCart && isBInCart) {
                          return 1;
                        } else {
                          return a.nama
                              .toLowerCase()
                              .compareTo(b.nama.toLowerCase());
                        }
                      });
                      // --- END NEW SORTING LOGIC ---

                      return ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          final bool isHighlighted =
                              cart.getProductQuantity(product) > 0;

                          return Card(
                            color: isHighlighted ? Colors.blue.shade100 : null,
                            elevation: isHighlighted ? 4.0 : 1.0,
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(product.nama,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Stok: ${product.stok} | Rp ${product.harga}'),
                              onTap: () {
                                final cart = context.read<CartService>();
                                int currentQty =
                                    cart.getProductQuantity(product);
                                if (currentQty == 0) {
                                  cart.addItem(product);
                                  currentQty = 1;
                                }
                                setState(() {
                                  _selectedProduct = product;
                                  currentQty = 1;
                                  _quantityController.text = '$currentQty';
                                  // Panel height will be calculated automatically
                                });

                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${product.nama} dipilih.'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            // (Feature 2) The bottom panel
            _buildBottomPanel(),
          ],
        ),

        // 2. Tombol FAB Keranjang (Kanan Bawah)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: 16.0,
          bottom: _panelHeight + 16.0,
          child: _buildCartFab(),
        ),

        // 3. Tombol FAB Admin (Kiri Bawah)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          left: 16.0,
          bottom: _panelHeight + 16.0,
          child: _buildAdminFab(),
        ),
      ],
    );
  }
}
