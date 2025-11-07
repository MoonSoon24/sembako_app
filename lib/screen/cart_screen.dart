import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '/service/flutter_cart_service.dart';
import '../app_config.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isPlacingOrder = false;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Menangani tombol "Place Order"
  Future<bool> _onPlaceOrder(CartService cart, int paymentAmount, int change,
      String paymentMethod) async {
    if (cart.items.isEmpty) return false;

    // VALIDASI BARU: Wajib isi nama jika PayLater
    if (paymentMethod == 'PayLater' && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nama Pelanggan wajib diisi untuk PayLater!'),
          backgroundColor: Colors.red,
        ),
      );
      return false; // Hentikan proses
    }

    setState(() {
      _isPlacingOrder = true;
    });

    final userName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Guest';

    String? errorMessage;
    String successMessage = '';

    try {
      // Panggil service placeOrder, sekarang lebih simpel
      // Service akan otomatis mengambil items dari dirinya sendiri
      bool success = await cart.placeOrder(
        userName: userName,
        paymentAmount: paymentAmount,
        change: change,
        paymentMethod: paymentMethod,
      );

      if (success) {
        successMessage = 'Pesanan berhasil disimpan!';
      } else {
        errorMessage = 'Gagal menyimpan pesanan. Cek koneksi atau stok.';
      }
    } catch (e) {
      errorMessage = 'Error koneksi: $e';
    }

    if (!mounted) return false;

    if (errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      cart.clearCart();
      Navigator.of(context).pop(); // Tutup CartScreen
      return true;
    } else {
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

  /// Menampilkan dialog untuk set kuantitas
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

  /// Menampilkan dialog konfirmasi hapus
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

  /// Menampilkan dialog pembayaran
  Future<void> _showPaymentDialog(
      BuildContext context, CartService cart) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: !_isPlacingOrder, // Cegah tutup saat loading
      builder: (BuildContext dialogContext) {
        return _PaymentDialogContent(
          cart: cart,
          // <-- BARU: Kirim nama pelanggan ke dialog
          customerName: _nameController.text.trim(),
          onPlaceOrder: (int paymentAmount, int change, String paymentMethod) {
            return _onPlaceOrder(cart, paymentAmount, change, paymentMethod);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartService>();

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
                                  // PERUBAHAN: Tampilkan harga jual
                                  Text(
                                      '${formatHargaLokal(item.product.hargaJual)} / item'),
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
                    labelText: 'Nama Pelanggan', // <-- Label diubah
                    hintText: 'Wajib diisi jika PayLater',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // <-- BARU: Tampilkan Total Margin -->
                Text(
                  'Total Omset: ${formatHargaLokal(cart.totalPrice)}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Total Margin: ${formatHargaLokal(cart.totalMargin)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.green.shade800),
                  textAlign: TextAlign.center,
                ),
                // <-- Akhir penambahan margin -->
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
  final String customerName; // <-- BARU
  final Future<bool> Function(
    int paymentAmount,
    int change,
    String paymentMethod,
  ) onPlaceOrder;

  const _PaymentDialogContent({
    Key? key,
    required this.cart,
    required this.customerName,
    required this.onPlaceOrder,
  }) : super(key: key);

  @override
  State<_PaymentDialogContent> createState() => _PaymentDialogContentState();
}

class _PaymentDialogContentState extends State<_PaymentDialogContent> {
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
    setState(() {
      if (_paymentMethod == 'Cash') {
        _paymentAmount =
            int.tryParse(_paymentAmountController.text.replaceAll('.', '')) ??
                0;
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
      } else if (_paymentMethod == 'PayLater') {
        _paymentAmount = widget.cart.totalPrice; // Total utang
        _change = 0;
        // VALIDASI BARU: Bisa PayLater HANYA jika nama pelanggan diisi
        _canPlaceOrder = widget.customerName.trim().isNotEmpty;
      }
    });
  }

  String _formatPrice(int harga) {
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
    return AlertDialog(
      title: const Text('Pembayaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: _paymentMethod,
              isExpanded: true,
              items: ['Cash', 'QRIS', 'PayLater'] // <-- BARU: Tambah PayLater
                  .map((method) => DropdownMenuItem(
                        value: method,
                        child: Text(method),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _paymentMethod = value;
                    _updateState();
                  });
                }
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
            // <-- BARU: Tampilan untuk PayLater -->
            if (_paymentMethod == 'PayLater')
              Column(
                children: [
                  Text(
                    '${widget.cart.totalPrice > 0 ? _rupiahFormat.format(widget.cart.totalPrice) : "Rp 0"} akan ditambahkan ke tagihan Sdr/i ${widget.customerName.isNotEmpty ? widget.customerName : '...'}',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.customerName.trim().isEmpty)
                    const Text(
                      'Nama Pelanggan di layar keranjang wajib diisi!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                ],
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

                  // Tentukan paymentAmount dan change untuk PayLater
                  int finalPaymentAmount =
                      _paymentMethod == 'PayLater' ? 0 : _paymentAmount;
                  int finalChange = _paymentMethod == 'PayLater' ? 0 : _change;

                  final success = await widget.onPlaceOrder(
                      finalPaymentAmount, finalChange, _paymentMethod);

                  if (!mounted) return;

                  if (success) {
                    Navigator.of(context).pop();
                  } else {
                    // Jika gagal (cth: nama kosong), dialog tetap terbuka
                    setState(() {
                      _isDialogLoading = false;
                    });
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
