import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../product/product_detail_page.dart';
import '../common/like_button.dart'; // Import tombol yang kita buat tadi

class LikesPage extends StatefulWidget {
  const LikesPage({super.key});

  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  final _myId = Supabase.instance.client.auth.currentUser!.id;
  final _supabase = Supabase.instance.client;

  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Favorit Saya")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        // 1. STREAM TABEL FAVORITES
        stream: _supabase
            .from('favorites')
            .stream(primaryKey: ['id'])
            .eq('user_id', _myId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final favorites = snapshot.data!;

          if (favorites.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Belum ada produk favorit"),
                ],
              ),
            );
          }

          // 2. TAMPILKAN LIST
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final favItem = favorites[index];
              final productId = favItem['product_id'];

              // 3. FETCH DETAIL PRODUK (FutureBuilder di dalam Item)
              // Teknik ini memastikan kita dapat data produk terbaru
              return FutureBuilder(
                future: _supabase.from('products').select().eq('id', productId).single(),
                builder: (context, productSnap) {
                  if (!productSnap.hasData) return const SizedBox(); // Loading diam
                  
                  final product = productSnap.data as Map<String, dynamic>;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          product['image_url'] ?? '', 
                          width: 60, height: 60, fit: BoxFit.cover,
                          errorBuilder: (_,__,___) => Container(width: 60, color: Colors.grey),
                        ),
                      ),
                      title: Text(product['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(formatRupiah(product['price']), style: const TextStyle(color: Colors.green)),
                      trailing: LikeButton(productId: productId), // Tombol Unlike Realtime
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ProductDetailPage(productData: product)
                        ));
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}