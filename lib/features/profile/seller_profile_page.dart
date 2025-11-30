import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../product/product_detail_page.dart';

class SellerProfilePage extends StatefulWidget {
  final String sellerId;
  const SellerProfilePage({super.key, required this.sellerId});

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSellerInfo();
  }

  Future<void> _fetchSellerInfo() async {
    try {
      final res = await _supabase
          .from('profiles')
          .select()
          .eq('id', widget.sellerId)
          .single();
      
      setState(() {
        _profile = res;
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error loading seller: $e");
      setState(() => _loading = false);
    }
  }
  
  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null) return const Scaffold(body: Center(child: Text("Penjual tidak ditemukan")));

    final isStoreOpen = _profile!['is_store_open'] ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(_profile!['full_name'] ?? 'Penjual')),
      body: Column(
        children: [
          // --- HEADER PROFIL PENJUAL ---
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundImage: _profile!['avatar_url'] != null ? NetworkImage(_profile!['avatar_url']) : null,
                  child: _profile!['avatar_url'] == null ? Text((_profile!['full_name']?[0] ?? 'U').toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profile!['full_name'],
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    
                    // INDIKATOR STATUS TOKO
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isStoreOpen ? Colors.green[100] : Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isStoreOpen ? "• BUKA" : "• TUTUP",
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.bold,
                          color: isStoreOpen ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),
                    Text("@${_profile!['username']}", style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        Text(" ${_profile!['city'] ?? 'Kota tidak diketahui'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ])
                  ],
                )
              ],
            ),
          ),
          const Divider(thickness: 4, color: Colors.black12),
          
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Align(alignment: Alignment.centerLeft, child: Text("Etalase Toko", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ),

          // --- GRID PRODUK PENJUAL ---
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase.from('products').stream(primaryKey: ['id']).eq('user_id', widget.sellerId).order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final products = snapshot.data!;

                if (products.isEmpty) return const Center(child: Text("Penjual ini belum memiliki barang lain."));

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, mainAxisSpacing: 10, crossAxisSpacing: 10),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final item = products[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: item)));
                      },
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Image.network(item['image_url'] ?? '', fit: BoxFit.cover, width: double.infinity, errorBuilder: (_,__,___) => Container(color: Colors.grey))),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(formatRupiah(item['price']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}