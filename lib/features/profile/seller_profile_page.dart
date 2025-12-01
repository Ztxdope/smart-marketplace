import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT
import '../product/product_detail_page.dart';

class SellerProfilePage extends StatefulWidget {
  final String sellerId;
  const SellerProfilePage({super.key, required this.sellerId});

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchSellerInfo();
  }

  Future<void> _fetchSellerInfo() async {
    try {
      final res = await _supabase.from('profiles').select().eq('id', widget.sellerId).single();
      final reviewsRes = await _supabase.from('reviews').select('*, profiles:reviewer_id(full_name, avatar_url)').eq('target_id', widget.sellerId).order('created_at', ascending: false);
      if (mounted) { setState(() { _profile = res; _reviews = List<Map<String, dynamic>>.from(reviewsRes); _loading = false; }); }
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }
  
  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null) return const Scaffold(body: Center(child: Text("Penjual tidak ditemukan")));

    final isStoreOpen = _profile!['is_store_open'] ?? true;
    final primaryColor = Theme.of(context).primaryColor;
    double avgRating = 0;
    if (_reviews.isNotEmpty) { avgRating = _reviews.map((e) => e['rating'] as int).reduce((a, b) => a + b) / _reviews.length; }

    return Scaffold(
      appBar: AppBar(title: Text(_profile!['full_name'] ?? 'Penjual')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20), color: Colors.white,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35, backgroundColor: Colors.grey[200],
                  // --- CACHED AVATAR ---
                  backgroundImage: _profile!['avatar_url'] != null ? CachedNetworkImageProvider(_profile!['avatar_url']) : null,
                  child: _profile!['avatar_url'] == null ? Text((_profile!['full_name']?[0] ?? 'U').toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_profile!['full_name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: isStoreOpen ? Colors.green[100] : Colors.red[100], borderRadius: BorderRadius.circular(4)), child: Text(isStoreOpen ? "• BUKA" : "• TUTUP", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isStoreOpen ? Colors.green[800] : Colors.red[800]))), const SizedBox(width: 8), const Icon(Icons.star, size: 14, color: Colors.amber), Text(" ${avgRating.toStringAsFixed(1)} (${_reviews.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
                  const SizedBox(height: 4), Text("@${_profile!['username']}", style: const TextStyle(color: Colors.grey)),
                ])
              ],
            ),
          ),
          TabBar(controller: _tabController, labelColor: primaryColor, unselectedLabelColor: Colors.grey, indicatorColor: primaryColor, tabs: const [Tab(text: "Barang"), Tab(text: "Ulasan")]),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _supabase.from('products').stream(primaryKey: ['id']).eq('user_id', widget.sellerId).order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final products = snapshot.data!;
                    if (products.isEmpty) return const Center(child: Text("Belum ada barang."));
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, mainAxisSpacing: 10, crossAxisSpacing: 10),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final item = products[index];
                        final isSold = item['status'] == 'Terjual';
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: item))),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Stack(fit: StackFit.expand, children: [
                                  // --- CACHED PRODUCT IMAGE ---
                                  CachedNetworkImage(
                                    imageUrl: item['image_url'] ?? '', 
                                    fit: BoxFit.cover, 
                                    color: isSold ? Colors.white.withOpacity(0.3) : null, 
                                    colorBlendMode: isSold ? BlendMode.modulate : null,
                                    placeholder: (context, url) => Container(color: Colors.grey[200]),
                                    errorWidget: (context, url, error) => Container(color: Colors.grey[200], child: const Icon(Icons.image))
                                  ),
                                  if (isSold) Container(color: Colors.black.withOpacity(0.5), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(border: Border.all(color: Colors.white), borderRadius: BorderRadius.circular(4)), child: const Text("TERJUAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)))))
                                ])),
                                Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(decoration: isSold ? TextDecoration.lineThrough : null, color: isSold ? Colors.grey : Colors.black)), Text(formatRupiah(item['price']), style: TextStyle(fontWeight: FontWeight.bold, color: isSold ? Colors.grey : Colors.green))]))
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                _reviews.isEmpty ? const Center(child: Text("Belum ada ulasan")) : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _reviews.length, separatorBuilder: (_,__) => const Divider(), itemBuilder: (context, index) {
                  final r = _reviews[index];
                  final reviewer = r['profiles'];
                  final bool isAnon = r['is_anonymous'] == true;
                  final String displayName = isAnon ? "Hamba Allah" : (reviewer != null ? reviewer['full_name'] : 'User');
                  // --- CACHED AVATAR REVIEWER ---
                  final ImageProvider? displayImage = (isAnon || reviewer == null || reviewer['avatar_url'] == null) ? null : CachedNetworkImageProvider(reviewer['avatar_url']);
                  return ListTile(leading: CircleAvatar(backgroundColor: Colors.grey[300], backgroundImage: displayImage, child: displayImage == null ? const Icon(Icons.person, color: Colors.white) : null), title: Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, fontStyle: isAnon ? FontStyle.italic : FontStyle.normal, color: isAnon ? Colors.grey[600] : Colors.black)), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RatingBarIndicator(rating: (r['rating'] as int).toDouble(), itemBuilder: (context, index) => const Icon(Icons.star, color: Colors.amber), itemCount: 5, itemSize: 14.0), const SizedBox(height: 4), Text(r['comment'] ?? '', style: const TextStyle(fontStyle: FontStyle.italic))]));
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}