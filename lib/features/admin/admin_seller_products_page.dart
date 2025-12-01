import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT

import '../product/edit_product_page.dart';
import '../product/product_detail_page.dart';

class AdminSellerProductsPage extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const AdminSellerProductsPage({
    super.key, 
    required this.sellerId,
    required this.sellerName,
  });

  @override
  State<AdminSellerProductsPage> createState() => _AdminSellerProductsPageState();
}

class _AdminSellerProductsPageState extends State<AdminSellerProductsPage> {
  final _supabase = Supabase.instance.client;

  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  Future<void> _adminDeleteProduct(String productId) async {
    final confirm = await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Paksa Barang?"),
        content: const Text("Barang ini akan dihapus permanen dari database."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text("Hapus")),
        ],
      )
    );

    if (confirm == true) {
      await _supabase.from('products').delete().eq('id', productId);
      setState(() {}); 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang berhasil dihapus")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("List Barang", style: TextStyle(fontSize: 14)),
            Text(widget.sellerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.black87, 
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('products')
            .stream(primaryKey: ['id'])
            .eq('user_id', widget.sellerId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final products = snapshot.data!;

          if (products.isEmpty) {
            return const Center(child: Text("User ini belum menjual barang apapun."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final item = products[index];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // --- CACHED IMAGE ---
                  child: CachedNetworkImage(
                    imageUrl: item['image_url'] ?? '', 
                    width: 50, height: 50, fit: BoxFit.cover, 
                    errorWidget: (_,__,___)=>const Icon(Icons.image)
                  ),
                ),
                title: Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatRupiah(item['price']), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    Text("Status: ${item['status']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductPage(product: item))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _adminDeleteProduct(item['id']),
                    ),
                  ],
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: item))),
              );
            },
          );
        },
      ),
    );
  }
}