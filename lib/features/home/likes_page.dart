import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT
import '../product/product_detail_page.dart';
import '../common/like_button.dart'; 

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
        stream: _supabase.from('favorites').stream(primaryKey: ['id']).eq('user_id', _myId).order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final favorites = snapshot.data!;

          if (favorites.isEmpty) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.favorite_border, size: 60, color: Colors.grey), SizedBox(height: 16), Text("Belum ada produk favorit")]));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final favItem = favorites[index];
              final productId = favItem['product_id'];

              return FutureBuilder(
                future: _supabase.from('products').select().eq('id', productId).single(),
                builder: (context, productSnap) {
                  if (!productSnap.hasData) return const SizedBox();
                  final product = productSnap.data as Map<String, dynamic>;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        // --- CACHED IMAGE ---
                        child: CachedNetworkImage(
                          imageUrl: product['image_url'] ?? '', 
                          width: 60, height: 60, fit: BoxFit.cover,
                          placeholder: (context, url) => Container(width: 60, color: Colors.grey[200]),
                          errorWidget: (context, url, error) => Container(width: 60, color: Colors.grey[200], child: const Icon(Icons.error)),
                        ),
                      ),
                      title: Text(product['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(formatRupiah(product['price']), style: const TextStyle(color: Colors.green)),
                      trailing: LikeButton(productId: productId), 
                      onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: product))); },
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