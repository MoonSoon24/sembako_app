import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert'; // <-- IMPORT BARU
import 'package:http/http.dart' as http; // <-- IMPORT BARU
import 'package:intl/intl.dart'; // <-- IMPORT BARU
import '/service/flutter_cart_service.dart';
import '../app_config.dart'; // <-- IMPORT BARU

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isPlacingOrder = false;
  final _nameController = TextEditingController();
  // Format Rupiah dari dialog pembayaran
 
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Handles the "Place Order" button press
  Future<bool> _onPlaceOrder(CartService cart, int paymentAmount, int change,
      String paymentMethod) async {
    if (cart.items.isEmpty) return false;

    setState(() {
      _isPlacingOrder = true;
    });

    final userName =
        _nameController.text.isNotEmpty ? _nameController.text : 'Guest';

    // --- Logika API baru (dari v7) dimulai di sini ---
    String? errorMessage;
    String successMessage = '';
    final int totalPrice = cart.totalPrice; // Ambil total dari keranjang

    try {
      // 1. Format data item
      final List<Map<String, dynamic>> itemsJson = cart.items
          .map((item) => {
                'nama': item.product.nama,
                'qty': item.quantity,
                'price_per_item': item.product.harga,
              })
          .toList();

      // 2. Siapkan parameter
      final queryParams = {
        'action': 'placeOrder',
        'secret': kSecretKey,
        'userName': userName, // Dari _nameController
        'paymentMethod': paymentMethod, // Dari dialog
        'total': totalPrice.toString(),
        'paymentAmount': paymentAmount.toString(),
        'change': change.toString(),
        'items': jsonEncode(itemsJson), // Kirim JSON
      };

      final baseUri = Uri.parse(kApiUrl);
      final urlWithParams = baseUri.replace(queryParameters: queryParams);

      // 3. Panggil API
      final response = await http.get(urlWithParams);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          successMessage = data['message'] ?? 'Pesanan berhasil disimpan!';
        } else {
          errorMessage = data['error'] ?? 'Gagal menyimpan pesanan';
        }
      } else {
        errorMessage = 'Error Server (Status: ${response.statusCode})';
      }
    } catch (e) {
      errorMessage = 'Error koneksi: $e';
    }

    // --- Akhir logika API baru ---

    if (!mounted) return false; // Widget was removed

    if (errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      cart.clearCart(); // Bersihkan keranjang
      Navigator.of(context).pop(); // Pop the CartScreen
      return true;
    } else {
      // Jika gagal, set state kembali agar pengguna bisa mencoba lagi
      setState(() {
        _isPlacingOrder = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  /// Shows a dialog to set the quantity for an item
  Future<void> _showQuantityDialog(
      BuildContext context, CartService cart, Product product) async {
    final quantityController = TextEditingController(
        text: cart.getProductQuantity(product).toString());

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Set Kuantitas - ${product.nama}'),
          content: TextField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Masukkan kuantitas'),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly
            ], // Hanya angka
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                final newQty = int.tryParse(quantityController.text) ?? 0;
                cart.setItemQuantity(product, newQty);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows a confirmation dialog before deleting an item
  Future<void> _showDeleteConfirmationDialog(
      BuildContext context, CartService cart, Product product) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Hapus Item'),
          content: Text('Anda yakin ingin menghapus ${product.nama}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Hapus'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                cart.setItemQuantity(product, 0);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows the payment dialog
  Future<void> _showPaymentDialog(
      BuildContext context, CartService cart) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _PaymentDialogContent(
          cart: cart,
          onPlaceOrder: (int paymentAmount, int change, String paymentMethod) {
            // Teruskan panggilan ke fungsi _onPlaceOrder yang sudah diperbarui
            return _onPlaceOrder(cart, paymentAmount, change, paymentMethod);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartService>();

    // Gunakan NumberFormat lokal untuk harga di UI
    String formatHargaLokal(int harga) {
      return 'Rp ${harga.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.')}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keranjang Anda'),
      ),
      body: Column(
        children: [
          Expanded(
            child: cart.items.isEmpty
                ? const Center(child: Text('Keranjang masih kosong.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 8.0),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.product.nama,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                  ),
                                  Text(
                                    formatHargaLokal(item.subtotal),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(
                                      '${formatHargaLokal(item.product.harga)} / item'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.delete_forever_outlined,
                                        color: Colors.red.shade700),
                                    onPressed: () {
                                      _showDeleteConfirmationDialog(
                                          context, cart, item.product);
                                    },
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        color: Colors.red.shade700,
                                        onPressed: () {
                                          context
                                              .read<CartService>()
                                              .removeItem(item.product);
                                        },
                                      ),
                                      InkWell(
                                        onTap: () {
                                          _showQuantityDialog(
                                              context, cart, item.product);
                                        },
                                        child: Container(
                                          width: 40,
                                          height: 30,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            border:
                                                Border.all(color: Colors.grey),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        color: Colors.green.shade700,
                                        onPressed: () {
                                          context
                                              .read<CartService>()
                                              .addItem(item.product);
                                        },
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nama Pelanggan (Opsional)',
                    hintText: 'Guest',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Total: ${formatHargaLokal(cart.totalPrice)}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: (cart.items.isEmpty || _isPlacingOrder)
                      ? null
                      : () => _showPaymentDialog(context, cart),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  child: _isPlacingOrder
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text('Bayar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget ini mengelola state internal dialog pembayaran

class _PaymentDialogContent extends StatefulWidget {
  final CartService cart;
  final Future<bool> Function(
    int paymentAmount,
    int change,
    String paymentMethod,
  ) onPlaceOrder;

  const _PaymentDialogContent({
    Key? key,
    required this.cart,
    required this.onPlaceOrder,
  }) : super(key: key);

  @override
  State<_PaymentDialogContent> createState() => _PaymentDialogContentState();
}

class _PaymentDialogContentState extends State<_PaymentDialogContent> {
  // Semua state dialog dikelola di sini
  late final TextEditingController _paymentAmountController;
  String _paymentMethod = 'Cash';
  int _change = 0;
  int _paymentAmount = 0;
  bool _canPlaceOrder = false;
  bool _isDialogLoading = false;
  final NumberFormat _rupiahFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _paymentAmountController = TextEditingController(text: '0');
    _paymentAmountController.addListener(_updateState);
    _updateState();
  }

  @override
  void dispose() {
    _paymentAmountController.removeListener(_updateState);
    _paymentAmountController.dispose();
    super.dispose();
  }

  void _updateState() {
    if (_paymentMethod == 'Cash') {
      _paymentAmount =
          int.tryParse(_paymentAmountController.text.replaceAll('.', '')) ?? 0;
      if (_paymentAmount >= widget.cart.totalPrice) {
        _change = _paymentAmount - widget.cart.totalPrice;
        _canPlaceOrder = true;
      } else {
        _change = 0;
        _canPlaceOrder = false;
      }
    } else if (_paymentMethod == 'QRIS') {
      _paymentAmount = widget.cart.totalPrice;
      _change = 0;
      _canPlaceOrder = true;
    }
    // Rebuild dialog
    setState(() {});
  }

  // --- Helper functions dipindahkan ke sini ---
  String _formatPrice(int harga) {
    // Format untuk keypad, tanpa "Rp"
    return harga
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.');
  }

  Widget _buildKeypadButton(String text, {required VoidCallback onPressed}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: text == '<-' || text == 'C'
                ? Colors.grey.shade200
                : Colors.white,
            foregroundColor: Colors.black,
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          onPressed: onPressed,
          child: Text(text),
        ),
      ),
    );
  }

  void _onKeypadTap(String value) {
    String currentText = _paymentAmountController.text.replaceAll('.', '');
    String newUnformattedText;
    if (currentText == '0') {
      newUnformattedText = (value == '00' || value == '000') ? '0' : value;
    } else {
      newUnformattedText = currentText + value;
    }
    final intValue = int.tryParse(newUnformattedText) ?? 0;
    _paymentAmountController.text = _formatPrice(intValue);
  }

  void _onKeypadClear() {
    _paymentAmountController.text = '0';
  }

  void _onKeypadBackspace() {
    String currentText = _paymentAmountController.text.replaceAll('.', '');
    if (currentText.isNotEmpty && currentText != '0') {
      String newUnformattedText =
          currentText.substring(0, currentText.length - 1);
      final intValue =
          int.tryParse(newUnformattedText.isEmpty ? '0' : newUnformattedText) ??
              0;
      _paymentAmountController.text = _formatPrice(intValue);
    } else {
      _paymentAmountController.text = '0';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build method untuk konten dialog
    return AlertDialog(
      title: const Text('Pembayaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: _paymentMethod,
              isExpanded: true,
              items: ['Cash', 'QRIS']
                  .map((method) => DropdownMenuItem(
                        value: method,
                        child: Text(method),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _paymentMethod = value!;
                  _updateState(); // Panggil update manual
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Total: ${_rupiahFormat.format(widget.cart.totalPrice)}',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_paymentMethod == 'Cash') ...[
              TextField(
                controller: _paymentAmountController,
                readOnly: true,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Jumlah Bayar (Cash)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Kembalian: ${_rupiahFormat.format(_change)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color:
                        _canPlaceOrder ? Colors.green.shade800 : Colors.black),
              ),
              const SizedBox(height: 16),
              Row(children: [
                _buildKeypadButton('1', onPressed: () => _onKeypadTap('1')),
                _buildKeypadButton('2', onPressed: () => _onKeypadTap('2')),
                _buildKeypadButton('3', onPressed: () => _onKeypadTap('3')),
              ]),
              Row(children: [
                _buildKeypadButton('4', onPressed: () => _onKeypadTap('4')),
                _buildKeypadButton('5', onPressed: () => _onKeypadTap('5')),
                _buildKeypadButton('6', onPressed: () => _onKeypadTap('6')),
              ]),
              Row(children: [
                _buildKeypadButton('7', onPressed: () => _onKeypadTap('7')),
                _buildKeypadButton('8', onPressed: () => _onKeypadTap('8')),
                _buildKeypadButton('9', onPressed: () => _onKeypadTap('9')),
              ]),
              Row(children: [
                _buildKeypadButton('00', onPressed: () => _onKeypadTap('00')),
                _buildKeypadButton('0', onPressed: () => _onKeypadTap('0')),
                _buildKeypadButton('000', onPressed: () => _onKeypadTap('000')),
              ]),
              Row(children: [
                _buildKeypadButton('C', onPressed: _onKeypadClear),
                _buildKeypadButton('<-', onPressed: _onKeypadBackspace),
              ]),
            ],
            if (_paymentMethod == 'QRIS')
              Text(
                'Silakan scan QRIS untuk membayar ${_rupiahFormat.format(widget.cart.totalPrice)}',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Batal'),
          onPressed: _isDialogLoading
              ? null
              : () {
                  Navigator.of(context).pop();
                },
        ),
        ElevatedButton(
          onPressed: (_canPlaceOrder && !_isDialogLoading)
              ? () async {
                  setState(() {
                    _isDialogLoading = true;
                  });

                  // Panggil fungsi dari parent
                  final success = await widget.onPlaceOrder(
                      _paymentAmount, _change, _paymentMethod);

                  if (!success) {
                    setState(() {
                      _isDialogLoading = false;
                    });
                  }

                  if (success) {
                    if (mounted) Navigator.of(context).pop();
                  }
                }
              : null,
          child: _isDialogLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white),
                )
              : const Text('Simpan Pesanan'),
        ),
      ],
    );
  }
}
