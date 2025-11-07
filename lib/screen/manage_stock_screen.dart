import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../app_config.dart';
import '/service/flutter_cart_service.dart';
import '/service/stock_cart_service.dart';
import 'stock_cart_screen.dart';

class ManageStockScreen extends StatefulWidget {
  const ManageStockScreen({Key? key}) : super(key: key);

  @override
  State<ManageStockScreen> createState() => _ManageStockScreenState();
}

class _ManageStockScreenState extends State<ManageStockScreen> {
  late Future<List<Product>> _productsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isLoading = false;

  // State untuk panel bawah (seperti di product_list_screen)
  Product? _selectedProduct;
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
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

  Future<void> _refreshProducts() async {
    setState(() {
      _productsFuture = fetchProducts();
    });
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

        final sanitizedList = productListJson.map((json) {
          if (json['nama'] != null) {
            json['nama'] = json['nama'].toString();
          }
          return json;
        }).toList();

        return sanitizedList.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception('Gagal memuat barang (Status: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat barang: $e');
    }
  }

  // --- MODAL UNTUK EDIT DETAIL (TETAP ADA) ---
  void _showEditProductModal(Product product) {
    final _priceController =
        TextEditingController(text: product.harga.toString());
    final _categoryController = TextEditingController(text: product.kategori);
    final _formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit: ${product.nama}'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Harga Baru'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Harga tidak boleh kosong';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Kategori Baru'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Kategori tidak boleh kosong';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (_formKey.currentState!.validate()) {
                        setState(() => _isLoading = true);
                        Navigator.pop(context); // Tutup dialog
                        // Gunakan action 'updateProduct'
                        await _runApiAction(
                          action: 'updateProduct',
                          params: {
                            'nama': product.nama, // Skrip butuh 'nama'
                            'harga':
                                _priceController.text, // Skrip butuh 'harga'
                            'kategori': _categoryController
                                .text, // Skrip butuh 'kategori'
                          },
                          successMessage: 'Produk berhasil diperbarui!',
                        );
                        setState(() => _isLoading = false);
                      }
                    },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  /// Helper untuk menjalankan aksi API (HANYA UNTUK EDIT)
  Future<void> _runApiAction({
    required String action,
    required Map<String, String> params,
    required String successMessage,
  }) async {
    setState(() => _isLoading = true);
    String? errorMessage;

    try {
      final queryParams = {
        'action': action,
        'secret': kSecretKey,
        ...params,
      };

      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);
      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] != true) {
          errorMessage = data['error'] ?? 'Terjadi error yang tidak diketahui';
        }
      } else {
        errorMessage = 'Error Server (Status: ${response.statusCode})';
      }
    } catch (e) {
      errorMessage = 'Error koneksi: $e';
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? successMessage),
        backgroundColor: errorMessage != null ? Colors.red : Colors.green,
      ),
    );

    _refreshProducts();
    setState(() => _isLoading = false);
  }

  // --- WIDGET BARU: Panel Bawah untuk Kuantitas Stok ---
  Widget _buildBottomPanel(StockCartService stockCart) {
    if (_selectedProduct == null) {
      return const SizedBox.shrink();
    }

    // Mengukur tinggi panel
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

    final currentQuantity = stockCart.getProductQuantity(_selectedProduct!);
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedProduct!.nama,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.red.shade700,
                  onPressed: () {
                    stockCart.removeItem(_selectedProduct!);
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
                      stockCart.setItemQuantity(_selectedProduct!, newQty);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.green.shade700,
                  onPressed: () {
                    stockCart.addItem(_selectedProduct!);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET BARU: Tombol FAB Keranjang Stok ---
  Widget _buildStockCartFab(StockCartService stockCart) {
    final totalItems =
        stockCart.items.fold<int>(0, (prev, item) => prev + item.quantity);

    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StockCartScreen()),
        );
      },
      label: const Text('Review Stok'),
      icon: Badge(
        label: Text('${stockCart.items.length}'), // Jumlah item unik
        isLabelVisible: totalItems > 0,
        child: const Icon(Icons.inventory_2_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Gunakan Consumer untuk mendapatkan StockCartService
    return Consumer<StockCartService>(
      builder: (context, stockCart, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Manajemen Stok'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshProducts,
              )
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari barang...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                    ),
                  ),
                  if (_isLoading) const LinearProgressIndicator(),
                  // Product List
                  Expanded(
                    child: FutureBuilder<List<Product>>(
                      future: _productsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                              child: Text('Error: ${snapshot.error}'));
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(child: Text('Tidak ada produk.'));
                        }

                        final allProducts = snapshot.data!;
                        final filteredProducts = allProducts.where((p) {
                          return p.nama.toLowerCase().contains(_searchQuery);
                        }).toList();

                        return ListView.builder(
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            final int quantityInCart =
                                stockCart.getProductQuantity(product);
                            final bool isHighlighted = quantityInCart > 0;

                            return Card(
                              color:
                                  isHighlighted ? Colors.blue.shade100 : null,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8.0, vertical: 4.0),
                              child: ListTile(
                                title: Text(product.nama,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'Stok: ${product.stok} | Harga: ${product.harga}'),
                                // --- LOGIKA ONTAP BARU ---
                                onTap: () {
                                  int currentQty =
                                      stockCart.getProductQuantity(product);
                                  if (currentQty == 0) {
                                    stockCart.setItemQuantity(product, 1);
                                    currentQty = 1;
                                  }
                                  setState(() {
                                    _selectedProduct = product;
                                    _quantityController.text = '$currentQty';
                                  });
                                },
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Tombol Edit (Harga/Kategori)
                                    IconButton(
                                      icon: Icon(Icons.edit,
                                          color: Colors.blue.shade700),
                                      onPressed: () =>
                                          _showEditProductModal(product),
                                      tooltip: 'Edit Harga/Kategori',
                                    ),
                                    // Tampilkan jumlah di keranjang
                                    if (isHighlighted)
                                      Chip(
                                        label: Text('$quantityInCart'),
                                        backgroundColor: Colors.blue.shade700,
                                        labelStyle: const TextStyle(
                                            color: Colors.white),
                                      )
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Panel Bawah
                  _buildBottomPanel(stockCart),
                ],
              ),
              // Tombol FAB
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                right: 16.0,
                bottom: _panelHeight + 16.0,
                child: _buildStockCartFab(stockCart),
              ),
            ],
          ),
        );
      },
    );
  }
}
