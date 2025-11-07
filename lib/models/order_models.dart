import 'dart:convert';
import 'package:flutter/material.dart';

// --- DATA MODEL BARU ---

/// Mewakili satu item dalam 'order_items'
class OrderItemDetail {
  final String orderID;
  final String nama;
  final int qty;
  final int pricePerItem; // Ini adalah harga_jual
  final int hargaBeli;

  OrderItemDetail({
    required this.orderID,
    required this.nama,
    required this.qty,
    required this.pricePerItem,
    required this.hargaBeli,
  });

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) {
    return OrderItemDetail(
      orderID: json['OrderID'] ?? '',
      nama: json['nama']?.toString() ?? 'Nama tidak diketahui',
      qty: json['kuantitas'] ?? 0, // <-- PERUBAHAN: dari 'qty' ke 'kuantitas'
      pricePerItem: json['harga_jual'] ??
          0, // <-- PERUBAHAN: dari 'price_per_item' ke 'harga_jual'
      hargaBeli: json['harga_beli'] ?? 0,
    );
  }

  // Kalkulasi margin untuk item ini
  int get totalMargin => (pricePerItem - hargaBeli) * qty;
  int get totalOmset => pricePerItem * qty;
}

/// Mewakili satu baris 'orders' (ringkasan)
class OrderSummary {
  final String orderID;
  final DateTime timestamp;
  final String userName;
  final int totalPrice; // <-- PERUBAHAN: Ini adalah 'Total Belanja'
  final int paymentAmount; // <-- PERUBAHAN: Ini adalah 'Jumlah Pembayaran'
  final String paymentMethod; // <-- PERUBAHAN: Ini adalah 'Metode Bayar'
  final int change; // <-- PERUBAHAN: Ini adalah 'Kembalian'
  final String status; // <-- BARU
  final List<OrderItemDetail> items;
  final int totalMargin;

  OrderSummary({
    required this.orderID,
    required this.timestamp,
    required this.userName,
    required this.totalPrice,
    required this.paymentAmount,
    required this.paymentMethod,
    required this.change,
    required this.status, // <-- BARU
    this.items = const [],
    this.totalMargin = 0,
  });

  factory OrderSummary.fromJson(
      Map<String, dynamic> json, List<OrderItemDetail> allItems) {
    String tsString = json['Timestamp'] ?? '';
    DateTime parsedTimestamp;
    try {
      parsedTimestamp = DateTime.parse(tsString).toLocal();
    } catch (e) {
      parsedTimestamp = DateTime.now();
    }

    // Ekstrak OrderID bersih dari formula HYPERLINK
    String cleanOrderID = '';
    String rawOrderID = json['OrderID'] ?? '';
    if (rawOrderID.startsWith('=')) {
      var parts = rawOrderID.split('"');
      if (parts.length > 3) {
        cleanOrderID = parts[parts.length - 2];
      } else {
        cleanOrderID = rawOrderID; // fallback
      }
    } else {
      cleanOrderID = rawOrderID; // Data lama
    }

    // Cari semua item yang cocok
    final matchingItems =
        allItems.where((item) => item.orderID == cleanOrderID).toList();

    // Hitung total margin untuk pesanan ini
    final int calculatedTotalMargin = matchingItems.fold(
      0,
      (previousValue, item) => previousValue + item.totalMargin,
    );

    return OrderSummary(
      orderID: cleanOrderID,
      timestamp: parsedTimestamp,
      userName: json['Nama Pembeli'] ?? 'Guest',
      totalPrice: json['Total Belanja'] ?? 0, // <-- PERUBAHAN
      paymentAmount: json['Jumlah Pembayaran'] ?? 0, // <-- PERUBAHAN
      paymentMethod: json['Metode Bayar'] ?? 'Cash', // <-- PERUBAHAN
      change: json['Kembalian'] ?? 0, // <-- PERUBAHAN
      status: json['Status'] ?? 'Lunas', // <-- BARU
      items: matchingItems,
      totalMargin: calculatedTotalMargin,
    );
  }
}
