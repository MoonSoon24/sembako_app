import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // <-- DIPERLUKAN UNTUK TANGGAL
import '../app_config.dart';
import '/service/flutter_cart_service.dart';
import '/service/stock_cart_service.dart';
import 'stock_cart_screen.dart';

// --- PERUBAHAN NAMA CLASS ---
class ManageProductScreen extends StatefulWidget {
  const ManageProductScreen({Key? key}) : super(key: key);

  @override
  State<ManageProductScreen> createState() => _ManageProductScreenState();
}

class _ManageProductScreenState extends State<ManageProductScreen> {
  late Future<List<Product>> _productsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isLoading = false;

  // State untuk panel bawah (add stock)
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

        // --- PERBAIKAN: Tidak perlu sanitasi manual lagi ---
        return productListJson.map((json) => Product.fromJson(json)).toList();
      } else {
        throw Exception('Gagal memuat barang (Status: ${response.statusCode})');
      }
    } catch (e) {
      print(e);
      throw Exception('Gagal memuat barang: $e');
    }
  }

  // --- MODAL DIPERBARUI UNTUK EDIT SEMUA DETAIL ---
  void _showEditProductModal(Product product) {
    // Inisialisasi controller dengan data produk
    final _hargaJualController =
        TextEditingController(text: product.hargaJual.toString());
    final _hargaBeliController =
        TextEditingController(text: product.hargaBeli.toString());
    final _categoryController = TextEditingController(text: product.kategori);
    final _tanggalExpireController =
        TextEditingController(text: product.tanggalKadaluwarsa ?? '');
    DateTime? _selectedDate = product.tanggalKadaluwarsa != null
        ? DateTime.tryParse(product.tanggalKadaluwarsa!)
        : null;

    final _formKey = GlobalKey<FormState>();

    // Helper untuk date picker di dalam modal
    Future<void> _selectDate(
        BuildContext context, Function(void Function()) modalSetState) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2101),
      );
      if (picked != null && picked != _selectedDate) {
        modalSetState(() {
          _selectedDate = picked;
          _tanggalExpireController.text =
              DateFormat('yyyy-MM-dd').format(picked);
        });
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Gunakan StatefulBuilder agar modal bisa update statenya sendiri (untuk date picker)
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return AlertDialog(
              title: Text('Edit: ${product.nama}'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          "Nama barang tidak bisa diubah. Hapus dan buat baru jika perlu.",
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hargaJualController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Harga Jual'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Harga Jual tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hargaBeliController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Harga Beli (Modal)'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Harga Beli tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _categoryController,
                        decoration:
                            const InputDecoration(labelText: 'Kategori'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Kategori tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tanggalExpireController,
                        decoration: InputDecoration(
                          labelText: 'Tanggal Kadaluwarsa (Opsional)',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              modalSetState(() {
                                _selectedDate = null;
                                _tanggalExpireController.text = '';
                              });
                            },
                          ),
                        ),
                        readOnly: true,
                        onTap: () => _selectDate(context, modalSetState),
                      ),
                    ],
                  ),
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
                                'nama': product.nama, // Kunci pencarian
                                'harga_jual': _hargaJualController.text,
                                'harga_beli': _hargaBeliController.text,
                                'kategori': _categoryController.text,
                                'tanggal_kadaluwarsa':
                                    _tanggalExpireController.text,
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
      },
    );
  }

  /// Helper untuk menjalankan aksi API
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

  // --- Widget Panel Bawah untuk Tambah Stok (Tidak Berubah) ---
  Widget _buildBottomPanel(StockCartService stockCart) {
    if (_selectedProduct == null) {
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
                    "Tambah Stok: ${_selectedProduct!.nama}", // <-- Judul diubah
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    // --- PERBAIKAN: Set kuantitas ke 0 di keranjang stok ---
                    stockCart.setItemQuantity(_selectedProduct!, 0);
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

  // --- Tombol FAB Keranjang Stok (Tidak Berubah) ---
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
        label: Text('${stockCart.items.length}'),
        isLabelVisible: totalItems > 0,
        child: const Icon(Icons.inventory_2_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StockCartService>(
      builder: (context, stockCart, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Manajemen Produk & Stok'), // <-- JUDUL BARU
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
                          // Padding di bawah agar FAB tidak menutupi item terakhir
                          padding: const EdgeInsets.only(bottom: 80.0),
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
                                // --- PERUBAHAN SUBTITLE ---
                                subtitle: Text(
                                    'Stok: ${product.stok} | Jual: ${product.hargaJual} | Beli: ${product.hargaBeli}'),

                                // OnTap: Pilih produk untuk DITAMBAH STOKNYA
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
                                    // Tombol Edit (Harga/Kategori/Dll)
                                    IconButton(
                                      icon: Icon(Icons.edit,
                                          color: Colors.blue.shade700),
                                      onPressed: () =>
                                          _showEditProductModal(product),
                                      tooltip:
                                          'Edit Detail Produk', // <-- Teks baru
                                    ),
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
                  _buildBottomPanel(stockCart),
                ],
              ),
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
