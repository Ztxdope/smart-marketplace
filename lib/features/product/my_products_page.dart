import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT
import 'edit_product_page.dart';

class MyProductsPage extends StatefulWidget {
  const MyProductsPage({super.key});

  @override
  State<MyProductsPage> createState() => _MyProductsPageState();
}

class _MyProductsPageState extends State<MyProductsPage> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  final _supabase = Supabase.instance.client;

  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  Future<void> _updateStatus(String productId, String newStatus) async {
    try {
      await _supabase.from('products').update({'status': newStatus}).eq('id', productId);
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (newStatus == 'Terjual') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang ditandai terjual")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    }
  }

  Future<void> _markAsSoldWithBuyer(String productId) async {
    // (Logika sama seperti sebelumnya, disingkat agar muat)
    Navigator.pop(context); 
    try {
      final roomPattern = "${productId}_${_myId}_%";
      final res = await _supabase.from('messages').select('sender_id, profiles:sender_id(full_name)').like('room_id', roomPattern).neq('sender_id', _myId); 
      final List<Map<String, dynamic>> candidates = [];
      final seenIds = <String>{};
      for (var msg in res as List) {
        final id = msg['sender_id'];
        if (id != null && !seenIds.contains(id)) {
          seenIds.add(id);
          candidates.add({'id': id, 'name': msg['profiles'] != null ? msg['profiles']['full_name'] : 'User Tanpa Nama'});
        }
      }
      if (!mounted) return;
      if (candidates.isEmpty) {
        showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const Padding(padding: EdgeInsets.all(16), child: Text("Konfirmasi Terjual", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))), const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("Belum ada riwayat chat. Tandai terjual offline?")), const SizedBox(height: 10), ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: const Text("Ya, Tandai Terjual"), onTap: () { Navigator.pop(ctx); _updateStatus(productId, 'Terjual'); }), const SizedBox(height: 20)])));
      } else {
        showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const Padding(padding: EdgeInsets.all(16), child: Text("Siapa pembelinya?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))), ...candidates.map((c) => ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(c['name']), subtitle: const Text("Pembeli via Chat"), onTap: () async { Navigator.pop(ctx); await _supabase.from('products').update({'status': 'Terjual', 'buyer_id': c['id']}).eq('id', productId); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang terjual!"))); })), const Divider(), ListTile(leading: const Icon(Icons.store_mall_directory, color: Colors.grey), title: const Text("Terjual di luar aplikasi"), onTap: () { Navigator.pop(ctx); _updateStatus(productId, 'Terjual'); }), const SizedBox(height: 20)])));
      }
    } catch (e) { _updateStatus(productId, 'Terjual'); }
  }

  Future<void> _deleteProduct(String id) async {
    try {
      await _supabase.from('products').delete().eq('id', id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Produk dihapus")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showStatusMenu(String productId, String currentStatus) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              const Padding(padding: EdgeInsets.all(16.0), child: Center(child: Text("Ubah Status Barang", style: TextStyle(fontWeight: FontWeight.bold)))),
              const Divider(),
              ListTile(leading: const Icon(Icons.check_circle_outline, color: Colors.green), title: const Text("Tandai Tersedia"), trailing: currentStatus == 'Tersedia' ? const Icon(Icons.check, color: Colors.blue) : null, onTap: () => _updateStatus(productId, 'Tersedia')),
              ListTile(leading: const Icon(Icons.timelapse, color: Colors.orange), title: const Text("Tandai Sedang Diproses"), trailing: currentStatus == 'Sedang Diproses' ? const Icon(Icons.check, color: Colors.blue) : null, onTap: () => _updateStatus(productId, 'Sedang Diproses')),
              ListTile(leading: const Icon(Icons.monetization_on, color: Colors.grey), title: const Text("Tandai Terjual"), trailing: currentStatus == 'Terjual' ? const Icon(Icons.check, color: Colors.blue) : null, onTap: () => _markAsSoldWithBuyer(productId)),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) { case 'Tersedia': return Colors.green; case 'Sedang Diproses': return Colors.orange; case 'Terjual': return Colors.grey; default: return Colors.blue; }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Kelola Barang")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('products').stream(primaryKey: ['id']).eq('user_id', _myId).order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final products = snapshot.data!;

          if (products.isEmpty) return const Center(child: Text("Tidak ada barang"));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            separatorBuilder: (_,__) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = products[index];
              String status = item['status'] ?? 'Tersedia';
              if (status == 'active') status = 'Tersedia';
              if (status == 'sold') status = 'Terjual';

              return Slidable(
                key: ValueKey(item['id']),
                startActionPane: ActionPane(motion: const ScrollMotion(), children: [SlidableAction(onPressed: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductPage(product: item))), backgroundColor: Colors.blue, foregroundColor: Colors.white, icon: FluentIcons.edit_24_regular, label: 'Edit', borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)))]),
                endActionPane: ActionPane(motion: const ScrollMotion(), children: [SlidableAction(onPressed: (_) => _deleteProduct(item['id']), backgroundColor: Colors.red, foregroundColor: Colors.white, icon: FluentIcons.delete_24_regular, label: 'Hapus', borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)))]),
                
                child: Card(
                  elevation: 2,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          // --- CACHED IMAGE ---
                          child: CachedNetworkImage(
                            imageUrl: item['image_url'] ?? '', 
                            width: 80, height: 80, 
                            fit: BoxFit.cover,
                            color: status == 'Terjual' ? Colors.white.withOpacity(0.5) : null,
                            colorBlendMode: status == 'Terjual' ? BlendMode.modulate : null,
                            placeholder: (context, url) => Container(width: 80, height: 80, color: Colors.grey[200]),
                            errorWidget: (context, url, error) => Container(width: 80, height: 80, color: Colors.grey[200], child: const Icon(Icons.image)),
                          )
                        ),
                        const SizedBox(width: 12),
                        
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AutoSizeText(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1),
                              const SizedBox(height: 4),
                              Text(formatRupiah(item['price']), style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              
                              GestureDetector(
                                onTap: () => _showStatusMenu(item['id'], status),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _getStatusColor(status))),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit, size: 12, color: _getStatusColor(status)), const SizedBox(width: 4), Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _getStatusColor(status)))]),
                                ),
                              )
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}