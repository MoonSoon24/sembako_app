import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '/service/flutter_cart_service.dart';
import 'cart_screen.dart';
import 'add_product_screen.dart';
import '../app_config.dart';
import 'manage_product_screen.dart';
import '/service/product_repository.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({Key? key}) : super(key: key);

  @override
  State<ProductListScreen> createState() => ProductListScreenState();
}

class ProductListScreenState extends State<ProductListScreen> {
  final ProductRepository _repository = ProductRepository();

  late Future<List<Product>> _productsFuture;
  List<String> _allCategories = ["Semua Kategori"];
  String _selectedCategory = "Semua Kategori";
  bool _isLoadingCategories = true;
  // <-- Akhir state baru -->

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Product? _selectedProduct;
  final TextEditingController _quantityController =
      TextEditingController(text: '1');

  final GlobalKey _panelKey = GlobalKey();
  double _panelHeight = 0.0;

  @override
  void initState() {
    super.initState();
    // <-- PERUBAHAN: Muat produk dan kategori secara bersamaan -->
    refreshProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // Optimized refresh: Fetch data once via Repository
  void refreshProducts() {
    setState(() {
      _productsFuture = _loadData();
    });
  }

  Future<List<Product>> _loadData() async {
    // 1. Fetch Products (Online -> Offline Fallback handled by Repo)
    final products = await _repository.getProducts();

    // 2. Extract Categories from the fetched products dynamically
    // This saves an extra API call and ensures categories match actual available products
    final categories = products.map((p) => p.kategori).toSet().toList();
    categories.sort();

    if (mounted) {
      setState(() {
        _allCategories = ["Semua Kategori", ...categories];
        _isLoadingCategories = false;
      });
    }

    return products;
  }

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
        return productListJson.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception(
            'Gagal memuat barang (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat barang: $e');
    }
  }

  // <-- BARU: Fungsi untuk mengambil daftar kategori -->
  Future<List<String>> fetchCategories() async {
    try {
      final queryParams = {
        'action': 'getCategories', // Asumsi action ini ada di Apps Script
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
        // Asumsi API mengembalikan {'categories': ['Sembako', 'Minuman', ...]}
        final List<dynamic> categoryListJson = data['categories'];
        return categoryListJson.cast<String>().toList();
      } else {
        throw Exception(
            'Gagal memuat kategori (Status: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat kategori: $e');
    }
  }

  // <-- BARU: Fungsi untuk memuat dan mengatur state kategori -->
  Future<void> _loadCategories() async {
    // Jangan set state jika widget sudah di-dispose
    if (!mounted) return;

    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final categories = await fetchCategories();
      if (mounted) {
        setState(() {
          _allCategories = ["Semua Kategori"]; // Reset
          _allCategories.addAll(categories);
          _isLoadingCategories = false;
        });
      }
    } catch (e) {
      print("Gagal memuat kategori: $e");
      if (mounted) {
        setState(() {
          _isLoadingCategories = false; // Stop loading meski gagal
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat daftar kategori: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  // <-- Akhir fungsi baru -->

  int _getCartQuantity(CartService cart, Product product) {
    return cart.getProductQuantity(product);
  }

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

  // <-- BARU: Widget untuk dropdown filter kategori -->
  Widget _buildCategoryFilter() {
    if (_isLoadingCategories) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: LinearProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.grey),
          color: Colors.white,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedCategory,
            isExpanded: true,
            icon: const Icon(Icons.filter_list_alt),
            items: _allCategories.map((String category) {
              return DropdownMenuItem<String>(
                value: category,
                child: Text(category),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCategory = newValue;
                });
              }
            },
          ),
        ),
      ),
    );
  }
  // <-- Akhir widget baru -->

  Widget _buildBottomPanel() {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }

    final cart = context.watch<CartService>();
    final isTopUp = _selectedProduct!.kategori == 'Top Up';
    final currentQuantity = cart.getProductQuantity(_selectedProduct!);

    if (currentQuantity == 0 && !isTopUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedProduct != null) {
          setState(() {
            _selectedProduct = null;
            _panelHeight = 0.0;
          });
        }
      });
      return const SizedBox.shrink();
    }

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

    // Only update the controller text if the user isn't actively typing
    // (to avoid cursor jumps), or if it's a regular item.
    if (!isTopUp) {
      _quantityController.text = '$currentQuantity';
    }

    return Card(
      key: _panelKey,
      elevation: 12.0,
      margin: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER: Nama Produk & Tombol Close (Selalu muncul)
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

            if (isTopUp)
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nominal Top Up',
                  hintText: 'Masukkan nominal...',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final nominal = value.isEmpty ? 0 : int.tryParse(value) ?? 0;
                  cart.setItemQuantity(_selectedProduct!, nominal);
                },
              )
            else
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
                        int finalQty =
                            cart.getProductQuantity(_selectedProduct!);
                        setState(() {
                          if (finalQty == 0) {
                            _selectedProduct = null;
                            _panelHeight = 0.0;
                          } else {
                            _quantityController.text = '$finalQty';
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

  Widget _buildCartFab() {
    return Consumer<CartService>(
      builder: (context, cart, child) {
        final totalItems = cart.items.fold<int>(0, (prev, item) {
          if (item.product.kategori == 'Top Up') {
            return prev + 1; //
          }
          return prev + item.quantity; //
        });

        return FloatingActionButton.extended(
          heroTag: "cart_fab",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CartScreen()),
            );
          },
          label: const Text('Keranjang  →'),
          icon: Badge(
            label: Text('$totalItems'),
            isLabelVisible: totalItems > 0,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
        );
      },
    );
  }

  void _showAdminMenu(BuildContext context) {
    // ... (Fungsi ini tidak berubah, tapi refreshProducts() kini lebih kuat) ...
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: const Text(
            'Menu Admin',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Tambah Barang Baru'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddProductScreen(),
                    ),
                  );
                  if (result == true) {
                    refreshProducts(); // <-- Ini sekarang refresh produk & kategori
                  }
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Manajemen Barang'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageProductScreen(),
                    ),
                  ).then((_) {
                    refreshProducts(); // <-- Ini sekarang refresh produk & kategori
                  });
                },
              ),
            ],
          ),
          actions: [
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

  Widget _buildAdminFab() {
    return FloatingActionButton(
      heroTag: "admin_fab",
      onPressed: () => _showAdminMenu(context),
      backgroundColor: Colors.green.shade700,
      child: const Icon(Icons.add),
    );
  }

  int? _getDaysUntilExpiry(String? expiryDateString) {
    // ... (Fungsi ini tidak berubah) ...
    if (expiryDateString == null || expiryDateString.isEmpty) {
      return null;
    }
    try {
      final expiryDate = DateTime.parse(expiryDateString);
      final today = DateTime.now();
      final difference = expiryDate
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
      return difference;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildSearchBar(),
            _buildCategoryFilter(), // <-- BARU: Tambahkan widget filter di sini
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
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

                  final allProducts = snapshot.data!;

                  final filteredProducts = allProducts.where((product) {
                    final nameLower = product.nama.toLowerCase();
                    final queryLower = _searchQuery.toLowerCase();

                    final bool nameMatch = nameLower.contains(queryLower);

                    final bool categoryMatch =
                        _selectedCategory == "Semua Kategori" ||
                            product.kategori == _selectedCategory;

                    return nameMatch && categoryMatch;
                  }).toList();

                  if (filteredProducts.isEmpty) {
                    return const Center(
                      child: Text('Tidak ada hasil untuk pencarian ini.'),
                    );
                  }

                  return Consumer<CartService>(
                    builder: (context, cart, child) {
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

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 80.0),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          final bool isHighlighted =
                              cart.getProductQuantity(product) > 0;

                          final bool lowStock = product.stok <= 5;
                          final int? daysUntilExpiry =
                              _getDaysUntilExpiry(product.tanggalKadaluwarsa);
                          final bool expiringSoon =
                              (daysUntilExpiry != null && daysUntilExpiry <= 7);

                          return Card(
                            color: isHighlighted ? Colors.blue.shade100 : null,
                            elevation: isHighlighted ? 4.0 : 1.0,
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              leading: expiringSoon
                                  ? Icon(Icons.warning_amber_rounded,
                                      color: Colors.red.shade700)
                                  : (lowStock
                                      ? Icon(Icons.inventory_2_outlined,
                                          color: Colors.orange.shade700)
                                      : null),
                              title: Text(product.nama,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${product.kategori} | Stok: ${product.stok} | Rp ${product.hargaJual}'),
                              trailing: (daysUntilExpiry != null &&
                                      daysUntilExpiry <= 30)
                                  ? Chip(
                                      label: Text('$daysUntilExpiry hari lagi'),
                                      backgroundColor: expiringSoon
                                          ? Colors.red.shade100
                                          : Colors.amber.shade100,
                                      labelStyle: TextStyle(
                                          color: expiringSoon
                                              ? Colors.red.shade900
                                              : Colors.amber.shade900,
                                          fontSize: 12),
                                      padding: EdgeInsets.zero,
                                    )
                                  : null,
                              onTap: () {
                                final cart = context.read<CartService>();
                                final isTopUp = product.kategori ==
                                    'Top Up'; // Add this check

                                int currentQty =
                                    cart.getProductQuantity(product);

                                if (currentQty == 0) {
                                  if (isTopUp) {
                                    // For Top Up, we don't auto-add 1. We keep it 0 until user inputs.
                                    cart.setItemQuantity(product, 0);
                                  } else {
                                    // Regular items still start at 1
                                    cart.addItem(product);
                                    currentQty = 1;
                                  }
                                }

                                setState(() {
                                  _selectedProduct = product;
                                  // If it's a Top Up and quantity is 0, show empty/zero. Otherwise show current.
                                  _quantityController.text =
                                      (isTopUp && currentQty == 0)
                                          ? ''
                                          : '$currentQty';
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
            _buildBottomPanel(),
          ],
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: 16.0,
          bottom: _panelHeight + 16.0,
          child: _buildCartFab(),
        ),
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
