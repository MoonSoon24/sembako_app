import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // <-- BARU: Untuk format tanggal
import '../app_config.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({Key? key}) : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controller untuk field
  final _nameController = TextEditingController();
  final _stockController = TextEditingController();
  final _hargaJualController = TextEditingController(); // <-- PERUBAHAN NAMA
  final _hargaBeliController = TextEditingController(); // <-- BARU
  final _tanggalExpireController = TextEditingController(); // <-- BARU

  String? _selectedCategory;
  DateTime? _selectedDate; // <-- BARU

  final List<String> _categories = [
    'Sembako',
    'Minuman',
    'Rokok',
    'Bumbu Dapur',
    'Snack',
    'Obat',
    'Lainnya'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _hargaJualController.dispose();
    _hargaBeliController.dispose();
    _tanggalExpireController.dispose();
    super.dispose();
  }

  String? _validateNotEmpty(String? value) {
    if (value == null || value.isEmpty) {
      return 'Field ini tidak boleh kosong';
    }
    return null;
  }

  /// <-- BARU: Fungsi untuk menampilkan pemilih tanggal
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _tanggalExpireController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Siapkan parameter untuk GET request
      final queryParams = {
        'action': 'addProduct',
        'secret': kSecretKey,
        'nama': _nameController.text,
        'stok': _stockController.text,
        'harga_jual': _hargaJualController.text,
        'harga_beli': _hargaBeliController.text,
        'kategori': _selectedCategory ?? '',
        'tanggal_kadaluwarsa': _tanggalExpireController.text, // <-- PERUBAHAN NAMA
      };

      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);

      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Produk berhasil ditambahkan!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else {
          // Tampilkan error dari Apps Script (cth: 'Produk sudah ada')
          throw Exception(data['error'] ?? 'Gagal menambahkan produk');
        }
      } else {
        throw Exception('Error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah Barang Baru'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Nama Barang ---
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Barang',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 16),

              // --- Kategori ---
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                hint: const Text('Pilih Kategori'),
                items: _categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCategory = newValue;
                  });
                },
                validator: (value) =>
                    value == null ? 'Pilih satu kategori' : null,
              ),
              const SizedBox(height: 16),

              // --- Stok Awal ---
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(
                  labelText: 'Stok Awal',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 16),

              // --- Harga Beli (Modal) ---
              TextFormField(
                controller: _hargaBeliController,
                decoration: const InputDecoration(
                  labelText: 'Harga Beli (Modal)', // <-- BARU
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money_rounded),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 16),

              // --- Harga Jual ---
              TextFormField(
                controller: _hargaJualController,
                decoration: const InputDecoration(
                  labelText: 'Harga Jual', // <-- PERUBAHAN
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.price_change_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly
                ],
                validator: _validateNotEmpty,
              ),
              const SizedBox(height: 16),

              // --- Tanggal Expire ---
              TextFormField(
                controller: _tanggalExpireController,
                decoration: const InputDecoration(
                  labelText: 'Tanggal Kadaluwarsa (Opsional)', // <-- PERUBAHAN NAMA
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () => _selectDate(context),
                // Tidak perlu validator karena opsional
              ),
              const SizedBox(height: 32),

              // --- Tombol Simpan ---
              ElevatedButton(
                onPressed: _isLoading ? null : _submitProduct,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text('Simpan Barang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}