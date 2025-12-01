import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart'; 
import 'package:fluentui_system_icons/fluentui_system_icons.dart'; 
import 'package:auto_size_text/auto_size_text.dart'; 
import 'package:flutter_animate/flutter_animate.dart'; 
import 'package:google_generative_ai/google_generative_ai.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT

// Import Pages & Core
import '../../core/constants.dart'; 
import '../product/upload_product_page.dart';
import '../product/product_detail_page.dart';
import '../product/edit_product_page.dart';
import '../chatbot/bot_page.dart';
import '../chat/chat_list_page.dart';
import '../profile/profile_page.dart';
import 'search_page.dart';
import 'likes_page.dart';
import '../common/like_button.dart';
import 'all_sellers_page.dart';
import '../profile/seller_profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  int _selectedIndex = 0; 
  
  List<Map<String, dynamic>> _recommendations = [];
  bool _isLoadingRecs = true;
  
  @override
  void initState() {
    super.initState();
    _fetchSmartRecommendations();
  }

  Future<void> _fetchSmartRecommendations() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final historyRes = await _supabase
          .from('interaction_logs')
          .select('products(title, category)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(8);

      if (historyRes.isEmpty) {
        _fetchLatestProducts();
        return;
      }

      List<String> historyItems = [];
      for (var log in historyRes) {
        if (log['products'] != null) {
          historyItems.add("${log['products']['title']} (${log['products']['category']})");
        }
      }
      String historyText = historyItems.join(", ");

      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: AppConstants.geminiApiKey);
      
      final prompt = """
      User history: [$historyText].
      Based on this history, suggest 1 specific broad keyword (in Indonesian) to find other relevant products.
      Output ONLY the keyword, nothing else. Example: Laptop
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      String keyword = response.text?.trim() ?? "";
      
      if (keyword.isNotEmpty) {
        final recRes = await _supabase
            .from('products')
            .select()
            .ilike('title', '%$keyword%')
            .neq('user_id', user.id)
            .neq('status', 'Terjual')
            .limit(10);

        if (recRes.isEmpty) {
           _fetchLatestProducts();
        } else {
           if (mounted) setState(() {
             _recommendations = List<Map<String, dynamic>>.from(recRes);
             _isLoadingRecs = false;
           });
        }
      } else {
        _fetchLatestProducts();
      }
    } catch (e) { 
      _fetchLatestProducts();
    }
  }

  Future<void> _fetchLatestProducts() async {
    final user = _supabase.auth.currentUser;
    try {
      final res = await _supabase
          .from('products')
          .select()
          .neq('user_id', user!.id)
          .neq('status', 'Terjual')
          .order('created_at', ascending: false)
          .limit(10);
      
      if (mounted) setState(() {
        _recommendations = List<Map<String, dynamic>>.from(res);
        _isLoadingRecs = false;
      });
    } catch (_) {}
  }

  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  Future<void> _logInteraction(String productId) async {
    final user = _supabase.auth.currentUser;
    if (user != null) await _supabase.from('interaction_logs').insert({'user_id': user.id, 'product_id': productId, 'action_type': 'view'});
  }

  Future<void> _updateStatus(String productId, String newStatus) async {
    try {
      await _supabase.from('products').update({'status': newStatus}).eq('id', productId);
      if (mounted) Navigator.pop(context);
      if (newStatus == 'Terjual') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang ditandai terjual (Disembunyikan dari Beranda)")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    }
  }

  void _showOwnerMenu(Map<String, dynamic> product) {
    final status = product['status'] ?? 'Tersedia';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Kelola Barang Anda: ${product['title']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Edit Barang"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductPage(product: product)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text("Tandai Tersedia"),
                trailing: status == 'Tersedia' ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () => _updateStatus(product['id'], 'Tersedia'),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse, color: Colors.orange),
                title: const Text("Tandai Sedang Diproses"),
                trailing: status == 'Sedang Diproses' ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () => _updateStatus(product['id'], 'Sedang Diproses'),
              ),
              ListTile(
                leading: const Icon(Icons.monetization_on, color: Colors.grey),
                title: const Text("Tandai Terjual (Hapus dari Feed)"),
                trailing: status == 'Terjual' ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () => _updateStatus(product['id'], 'Terjual'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeedView() {
    return RefreshIndicator(
      onRefresh: () async { setState((){ _isLoadingRecs = true; }); await _fetchSmartRecommendations(); },
      child: CustomScrollView(
        slivers: [
          // 1. PENJUAL AKTIF (HORIZONTAL)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Penjual Aktif", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Color.fromRGBO(211, 47, 47, 1)),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllSellersPage())),
                      )
                    ],
                  ),
                ),
                SizedBox(
                  height: 110,
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _supabase.from('profiles').stream(primaryKey: ['id']).eq('is_store_open', true).limit(10),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                      final currentUserId = _supabase.auth.currentUser?.id;
                      final activeSellers = snapshot.data!.where((seller) => seller['id'] != currentUserId).toList();
                      if (activeSellers.isEmpty) return const Center(child: Text("Tidak ada toko yang buka", style: TextStyle(color: Colors.grey, fontSize: 12)));

                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: activeSellers.length,
                        itemBuilder: (context, index) {
                          final seller = activeSellers[index];
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: seller['id']))),
                            child: Container(
                              width: 70,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                children: [
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 30,
                                        backgroundColor: Colors.grey[200],
                                        // --- CACHED AVATAR ---
                                        backgroundImage: (seller['avatar_url'] != null) 
                                            ? CachedNetworkImageProvider(seller['avatar_url']) 
                                            : null,
                                        child: (seller['avatar_url'] == null) ? Text((seller['full_name']?[0] ?? 'U').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                                      ),
                                      Positioned(
                                        bottom: 0, right: 0,
                                        child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(seller['full_name'] ?? 'User', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(thickness: 1, height: 10),
              ],
            ),
          ),

          // 2. REKOMENDASI AI (HORIZONTAL)
          if (_recommendations.isNotEmpty || _isLoadingRecs)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(FluentIcons.sparkle_24_filled, color: Theme.of(context).primaryColor).animate(onPlay: (c) => c.repeat(reverse: true)).scale(duration: 1000.ms, begin: const Offset(1,1), end: const Offset(1.2, 1.2)), 
                        const SizedBox(width: 8),
                        Text("Pilihan Untukmu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey[800])),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: _isLoadingRecs 
                    ? const Center(child: CircularProgressIndicator()) 
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _recommendations.length,
                        itemBuilder: (context, index) {
                          final item = _recommendations[index];
                          if (item['status'] == 'Terjual') return const SizedBox();
                          return GestureDetector(
                            onTap: () {
                              _logInteraction(item['id']);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: item)));
                            },
                            child: Container(
                              width: 150,
                              margin: const EdgeInsets.only(right: 12, bottom: 8),
                              child: Card(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), 
                                        // --- CACHED IMAGE ---
                                        child: CachedNetworkImage(
                                          imageUrl: item['image_url'] ?? '', 
                                          fit: BoxFit.cover, 
                                          width: double.infinity,
                                          placeholder: (context, url) => Container(color: Colors.grey[200]),
                                          errorWidget: (context, url, error) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                                        )
                                      )
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          AutoSizeText(item['title'], maxLines: 1, minFontSize: 10, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text(formatRupiah(item['price']), style: TextStyle(fontSize: 11, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ).animate().fadeIn(duration: 500.ms).slideX(begin: 0.2),
                            ),
                          );
                        },
                      ),
                  ),
                ],
              ),
            ),
          
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text("Terbaru", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))),

          // 3. GRID UTAMA
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('products').stream(primaryKey: ['id']).limit(20).order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: LinearProgressIndicator()));
              final allProducts = snapshot.data!;
              final activeProducts = allProducts.where((p) => p['status'] != 'Terjual').toList();

              if (activeProducts.isEmpty) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Text("Belum ada produk tersedia.")));

              return SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.72, mainAxisSpacing: 12, crossAxisSpacing: 12),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = activeProducts[index];
                      final myId = _supabase.auth.currentUser?.id;
                      final isMine = (product['user_id'] == myId);
                      final status = product['status'] ?? 'Tersedia';

                      return GestureDetector(
                        onTap: () {
                          _logInteraction(product['id']);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: product)));
                        },
                        child: Card(
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3, 
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), 
                                      // --- CACHED IMAGE ---
                                      child: CachedNetworkImage(
                                        imageUrl: product['image_url'] ?? '', 
                                        fit: BoxFit.cover, 
                                        width: double.infinity,
                                        placeholder: (context, url) => Container(color: Colors.grey[200]),
                                        errorWidget: (context, url, error) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                                      )
                                    )
                                  ),
                                  Expanded(flex: 2, child: Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [AutoSizeText(product['title'], maxLines: 2, minFontSize: 12, style: const TextStyle(fontWeight: FontWeight.w600)), const Spacer(), Text(formatRupiah(product['price']), style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)), Row(children: [const Icon(FluentIcons.location_12_regular, size: 12, color: Colors.grey), const SizedBox(width: 2), Expanded(child: Text(product['city'] ?? 'Jakarta', style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis))])])))
                                ],
                              ),
                              if (!isMine) Positioned(bottom: 8, right: 8, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]), child: Center(child: LikeButton(productId: product['id'], size: 18)))),
                              if (isMine) Positioned(top: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(4)), child: const Text("Milik Anda", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                              if (status == 'Sedang Diproses') Positioned(bottom: 0, left: 0, right: 0, child: Container(color: Colors.orange.withOpacity(0.8), padding: const EdgeInsets.symmetric(vertical: 2), child: const Text("DIPROSES", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                            ],
                          ),
                        ).animate().scale(delay: (50 * index).ms, duration: 300.ms),
                      );
                    },
                    childCount: activeProducts.length,
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [ _buildFeedView(), const LikesPage(), const SizedBox(), const ChatListPage(), const ProfilePage() ];
    return Scaffold(
      appBar: _selectedIndex == 0 ? AppBar(title: const Text('Smart Market'), elevation: 0, actions: [IconButton(icon: const Icon(FluentIcons.search_24_regular), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()))), IconButton(icon: const Icon(FluentIcons.bot_24_regular), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BotPage()))),]) : null,
      body: pages[_selectedIndex],
      bottomNavigationBar: ConvexAppBar(style: TabStyle.fixedCircle, backgroundColor: Theme.of(context).primaryColor, color: Colors.white70, activeColor: Colors.white, elevation: 5, items: const [TabItem(icon: FluentIcons.home_24_regular, title: 'Home'), TabItem(icon: FluentIcons.heart_24_regular, title: 'Likes'), TabItem(icon: Icons.add, title: 'Jual'), TabItem(icon: FluentIcons.chat_24_regular, title: 'Chat'), TabItem(icon: FluentIcons.person_24_regular, title: 'Akun')], initialActiveIndex: _selectedIndex, onTap: (int i) { if (i == 2) { Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadProductPage())); } else { setState(() => _selectedIndex = i); } }),
    );
  }
}