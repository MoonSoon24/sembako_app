import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '/service/transaction_sync.dart';

class OfflineTransactionScreen extends StatefulWidget {
  const OfflineTransactionScreen({Key? key}) : super(key: key);

  @override
  State<OfflineTransactionScreen> createState() =>
      _OfflineTransactionScreenState();
}

class _OfflineTransactionScreenState extends State<OfflineTransactionScreen> {
  final TransactionSyncService _syncService = TransactionSyncService();
  late Future<List<Map<String, dynamic>>> _pendingTransactions;
  bool _isSyncing = false;
  final currencyFormatter =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _pendingTransactions = _syncService.getPendingTransactionsList();
    });
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);

    try {
      int count = await _syncService.syncPendingTransactions();
      if (!mounted) return;

      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$count transaksi berhasil diupload ke Server!'),
              backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Belum ada transaksi yang terupload. Cek koneksi.'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _refreshList();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi Offline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshList,
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: const Text(
                    "Data di bawah ini tersimpan di HP karena internet mati saat transaksi. Data akan hilang jika aplikasi di-uninstall.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _pendingTransactions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_done, size: 64, color: Colors.green),
                        SizedBox(height: 16),
                        Text("Semua data sudah tersinkron!"),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final item = snapshot.data![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.priority_high, color: Colors.white),
                        ),
                        title: Text(item['customer_name'] ?? 'Guest'),
                        subtitle: Text(item['transaction_date']),
                        trailing: Text(
                          currencyFormatter.format(item['total_amount']),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black12)],
            ),
            child: ElevatedButton.icon(
              onPressed: _isSyncing ? null : _manualSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(
                  _isSyncing ? "Sedang Upload..." : "Upload Data Sekarang"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
