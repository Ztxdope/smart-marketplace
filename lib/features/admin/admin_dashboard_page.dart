import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'admin_edit_user_page.dart';        
import 'admin_seller_products_page.dart';  
import '../profile/seller_profile_page.dart'; 

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  
  // Variabel untuk menyimpan Future (Agar tidak loading ulang saat rebuild)
  late Future<List<Map<String, dynamic>>> _productGroupsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _productGroupsFuture = _fetchProductGroups(); // Panggil sekali di awal
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), 
            child: const Text("Hapus Paksa")
          ),
        ],
      )
    ) ?? false;
  }

  Future<void> _adminDeleteUser(String userId) async {
    final confirm = await _showConfirmDialog("Hapus User ini?", "Semua data user ini akan hilang permanen.");
    if (confirm) {
      try {
        // Coba panggil RPC dulu (lebih bersih)
        try {
           await _supabase.rpc('admin_delete_user', params: {'target_user_id': userId});
        } catch (_) {
           // Fallback delete manual
           await _supabase.from('profiles').delete().eq('id', userId);
        }

        if (mounted) {
          setState(() {
            // Refresh List setelah delete
            _productGroupsFuture = _fetchProductGroups();
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User berhasil dihapus")));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
      }
    }
  }

  // --- QUERY MANUAL YANG LEBIH STABIL ---
  Future<List<Map<String, dynamic>>> _fetchProductGroups() async {
    try {
      // 1. Ambil Semua Profil
      final profiles = await _supabase.from('profiles').select();
      
      // 2. Ambil Semua Produk (ID & UserID saja biar ringan)
      final products = await _supabase.from('products').select('id, user_id');

      // 3. Gabungkan di Flutter (Client Side Join)
      List<Map<String, dynamic>> results = [];
      
      for (var p in profiles) {
        final String userId = p['id'];
        // Hitung barang milik user ini
        final userProducts = products.where((prod) => prod['user_id'] == userId).toList();
        
        Map<String, dynamic> data = Map.from(p);
        data['product_count'] = userProducts.length;
        results.add(data);
      }

      // Sort: Yang punya barang paling banyak di atas
      results.sort((a, b) => (b['product_count'] as int).compareTo(a['product_count'] as int));
      
      return results;
    } catch (e) {
      debugPrint("Error fetching groups: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ADMIN PANEL 🛠️"),
        backgroundColor: Colors.black87, 
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.red,
          tabs: const [
            Tab(text: "Manajemen User", icon: Icon(Icons.people)),
            Tab(text: "Grup Barang", icon: Icon(Icons.inventory_2)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllUsersList(),
          _buildProductGroups(),
        ],
      ),
    );
  }

  Widget _buildAllUsersList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      // Query Sederhana: Ambil semua profil tanpa filter aneh-aneh
      stream: _supabase
          .from('profiles')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false), // User baru di atas
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("Belum ada user lain."));
        }
        
        final users = snapshot.data!;
        
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          separatorBuilder: (_,__) => const Divider(),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final isMe = user['id'] == _supabase.auth.currentUser?.id;
            
            // Cek role dengan aman (gunakan string kosong jika null)
            final role = user['role'] ?? 'user';
            final isAdmin = role == 'admin';

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[300],
                // Gunakan CachedNetworkImageProvider jika url ada
                backgroundImage: user['avatar_url'] != null 
                    ? CachedNetworkImageProvider(user['avatar_url']) 
                    : null,
                child: user['avatar_url'] == null ? const Icon(Icons.person, color: Colors.white) : null,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      user['full_name'] ?? 'No Name', 
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        // Tandai Admin dengan warna merah
                        color: isAdmin ? Colors.red : Colors.black
                      ),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis
                    )
                  ),
                  if (isAdmin) 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), 
                      child: const Text("ADMIN", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))
                    )
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("@${user['username'] ?? '-'}"),
                  Text(user['email'] ?? 'Email hidden', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              
              // TOMBOL HAPUS (Kanan)
              trailing: isMe 
                ? const Chip(label: Text("Anda", style: TextStyle(fontSize: 10))) 
                : IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: "Hapus User",
                    onPressed: () => _adminDeleteUser(user['id']),
                  ),
              
              // KLIK -> EDIT USER
              onTap: () {
                 Navigator.push(context, MaterialPageRoute(
                   builder: (_) => AdminEditUserPage(
                     userId: user['id'],
                     currentName: user['full_name'] ?? '',
                     currentUsername: user['username'] ?? '',
                     currentEmail: user['email'] ?? '-',
                     currentAvatar: user['avatar_url'],
                   )
                 ));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProductGroups() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productGroupsFuture, // Menggunakan variabel state yang stabil
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Belum ada data user/barang."));
        
        final sellers = snapshot.data!;

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: sellers.length,
          separatorBuilder: (_,__) => const Divider(),
          itemBuilder: (context, index) {
            final seller = sellers[index];
            final productCount = seller['product_count'] as int;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey[200],
                backgroundImage: seller['avatar_url'] != null 
                    ? CachedNetworkImageProvider(seller['avatar_url']) 
                    : null,
                child: seller['avatar_url'] == null ? const Icon(Icons.store, color: Colors.grey) : null,
              ),
              title: Text(seller['full_name'] ?? 'Tanpa Nama', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("@${seller['username']}"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: productCount > 0 ? Colors.blue[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20)
                ),
                child: Text(
                  "$productCount Barang", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: productCount > 0 ? Colors.blue[900] : Colors.grey)
                ),
              ),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminSellerProductsPage(
                    sellerId: seller['id'], 
                    sellerName: seller['full_name'] ?? 'Penjual'
                  )
                )).then((_) {
                  // Refresh data saat kembali
                  setState(() {
                    _productGroupsFuture = _fetchProductGroups();
                  });
                });
              },
            );
          },
        );
      },
    );
  }
}