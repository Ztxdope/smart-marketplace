import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT
import '../profile/seller_profile_page.dart';

class AllSellersPage extends StatefulWidget {
  const AllSellersPage({super.key});

  @override
  State<AllSellersPage> createState() => _AllSellersPageState();
}

class _AllSellersPageState extends State<AllSellersPage> {
  final _supabase = Supabase.instance.client;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Semua Penjual")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase
            .from('profiles')
            .stream(primaryKey: ['id'])
            .neq('id', _supabase.auth.currentUser!.id)
            .order('full_name', ascending: true),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final sellers = snapshot.data!;
          
          if (sellers.isEmpty) return const Center(child: Text("Belum ada penjual lain."));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sellers.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final seller = sellers[index];
              final bool isOpen = seller['is_store_open'] ?? true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  // --- AVATAR CACHED ---
                  backgroundImage: (seller['avatar_url'] != null) 
                      ? CachedNetworkImageProvider(seller['avatar_url']) 
                      : null,
                  child: (seller['avatar_url'] == null) 
                      ? const Icon(Icons.person, color: Colors.grey) 
                      : null,
                ),
                title: Text(
                  seller['full_name'] ?? 'Tanpa Nama',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(isOpen ? "● Toko Buka" : "● Toko Tutup", 
                    style: TextStyle(color: isOpen ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: seller['id'])));
                },
              );
            },
          );
        },
      ),
    );
  }
}