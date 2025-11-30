import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:fluentui_system_icons/fluentui_system_icons.dart'; 
import 'package:flutter_animate/flutter_animate.dart';

import '../chat/chat_page.dart';
import '../profile/seller_profile_page.dart';
import '../common/like_button.dart';
import 'edit_product_page.dart'; 

class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> productData;
  const ProductDetailPage({super.key, required this.productData});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _sellerProfile;
  bool _loading = true;
  bool _isStoreOpen = true;
  
  bool _isMine = false;
  int _viewCount = 0;
  int _likeCount = 0;
  String _currentStatus = 'Tersedia';

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.productData['status'] ?? 'Tersedia';
    _checkOwnership();
    _fetchData();
  }

  void _checkOwnership() {
    final myId = _supabase.auth.currentUser?.id;
    setState(() {
      _isMine = (myId == widget.productData['user_id']);
    });
  }

  Future<void> _fetchData() async {
    try {
      final sellerId = widget.productData['user_id'];
      final profileRes = await _supabase.from('profiles').select().eq('id', sellerId).single();
      
      int views = 0;
      int likes = 0;
      
      if (_isMine) {
        final viewsRes = await _supabase.from('interaction_logs').count(CountOption.exact).eq('product_id', widget.productData['id']).eq('action_type', 'view');
        final likesRes = await _supabase.from('favorites').count(CountOption.exact).eq('product_id', widget.productData['id']);
        views = viewsRes;
        likes = likesRes;
      }

      if (mounted) {
        setState(() {
          _sellerProfile = profileRes;
          _isStoreOpen = profileRes['is_store_open'] ?? true;
          _viewCount = views;
          _likeCount = likes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await _supabase.from('products').update({'status': newStatus}).eq('id', widget.productData['id']);
      setState(() => _currentStatus = newStatus);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Status diubah ke $newStatus")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    }
  }

  Future<void> _openMap() async {
    final lat = widget.productData['latitude'];
    final lng = widget.productData['longitude'];
    
    Uri googleUrl;
    
    if (lat != null && lng != null) {
      // Jika ada koordinat, buka titiknya
      googleUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      // --- PERBAIKAN DI SINI ---
      // Kita definisikan dulu variabel 'query' dari data kota/alamat
      final query = widget.productData['city'] ?? widget.productData['address'] ?? 'Indonesia';
      
      googleUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }

    try {
      if (await canLaunchUrl(googleUrl)) {
        await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch maps';
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak bisa membuka aplikasi Maps')));
    }
  }

  Future<void> _startChat() async {
    if (!_isStoreOpen) {
      _showDialog("Toko Tutup 🔒", "Penjual sedang tutup sementara.");
      return;
    }
    if (_currentStatus == 'Terjual') {
      _showDialog("Barang Terjual", "Barang ini sudah laku.");
      return;
    }

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    
    final roomId = "${widget.productData['id']}_${widget.productData['user_id']}_$myId";
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatPage(roomId: roomId, productTitle: widget.productData['title'], sellerId: widget.productData['user_id']),
    ));
  }

  void _showDialog(String title, String content) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Oke"))]));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Tersedia': return Colors.green;
      case 'Sedang Diproses': return Colors.orange;
      case 'Terjual': return Colors.grey;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(widget.productData['price']);
    final locationName = widget.productData['city'] ?? 'Lokasi tidak tersedia';
    final isSold = _currentStatus == 'Terjual';
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      // APP BAR TANPA ICON LIKE
      appBar: AppBar(
        title: const Text('Detail Produk'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.network(
                  widget.productData['image_url'] ?? '', 
                  height: 300, width: double.infinity, fit: BoxFit.cover,
                  color: isSold ? Colors.white.withOpacity(0.4) : null,
                  colorBlendMode: isSold ? BlendMode.modulate : null,
                  errorBuilder: (_,__,___) => Container(height: 300, color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
                ),
                if (_currentStatus != 'Tersedia')
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      color: _getStatusColor(_currentStatus).withOpacity(0.9),
                      child: Text(_currentStatus.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  )
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isMine) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50], 
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("📊 Statistik Penjualan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(FluentIcons.eye_24_regular, "$_viewCount", "Dilihat"),
                              Container(height: 30, width: 1, color: Colors.grey[300]),
                              _buildStatItem(FluentIcons.heart_24_regular, "$_likeCount", "Difavoritkan"),
                            ],
                          ),
                          const Divider(height: 24),
                          const Text("Ubah Status:", style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                            child: DropdownButton<String>(
                              value: _currentStatus,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: ['Tersedia', 'Sedang Diproses', 'Terjual'].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Row(
                                    children: [
                                      Icon(Icons.circle, size: 12, color: _getStatusColor(value)),
                                      const SizedBox(width: 8),
                                      Text(value),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (newValue) { if (newValue != null) _updateStatus(newValue); },
                            ),
                          ),
                        ],
                      ),
                    ).animate().slideY(begin: 0.2, duration: 400.ms),
                    const SizedBox(height: 20),
                  ],

                  Text(widget.productData['title'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  // --- HARGA & LIKE BUTTON DI BAWAH ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        price, 
                        style: TextStyle(fontSize: 22, color: primaryColor, fontWeight: FontWeight.bold)
                      ),
                      // LIKE BUTTON DISINI (TIDAK ADA PENGECEKAN isMine)
                      LikeButton(productId: widget.productData['id']),
                    ],
                  ),
                  // ------------------------------------
                  
                  const SizedBox(height: 16),
                  const Text("Deskripsi:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(widget.productData['description'] ?? '-'),
                  const Divider(height: 40),

                  // Info Penjual (SELALU MUNCUL)
                  const Text("Informasi Penjual:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  _loading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : Card(
                        elevation: 0, color: Colors.grey[50],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          leading: CircleAvatar(
                            radius: 25, backgroundColor: primaryColor,
                            backgroundImage: _sellerProfile?['avatar_url'] != null ? NetworkImage(_sellerProfile!['avatar_url']) : null,
                            child: _sellerProfile?['avatar_url'] == null ? Text((_sellerProfile?['full_name'] ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                          ),
                          title: Text(_sellerProfile?['full_name'] ?? 'Penjual', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            _isStoreOpen ? "Klik untuk lihat profil" : "• Toko Sedang Tutup",
                            style: TextStyle(color: _isStoreOpen ? Colors.black54 : Colors.red, fontWeight: _isStoreOpen ? FontWeight.normal : FontWeight.bold)
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: widget.productData['user_id']))),
                        ),
                      ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Lokasi COD:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton.icon(onPressed: _openMap, icon: Icon(Icons.map_outlined, size: 18, color: primaryColor), label: Text("Buka Maps", style: TextStyle(color: primaryColor)), style: TextButton.styleFrom(padding: EdgeInsets.zero))
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openMap,
                    child: Container(
                      height: 150, width: double.infinity,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400), image: const DecorationImage(image: NetworkImage("https://images.unsplash.com/photo-1524661135-423995f22d0b?q=80&w=600&auto=format&fit=crop"), fit: BoxFit.cover, opacity: 0.6)),
                      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.location_on, color: Colors.red, size: 40),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text(locationName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ])),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isMine
              ? ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductPage(product: widget.productData)));
                  },
                  icon: const Icon(FluentIcons.edit_24_filled),
                  label: const Text('EDIT BARANG (HALAMAN PENUH)'),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), elevation: 4),
                )
              : ElevatedButton.icon(
                  onPressed: (_loading || isSold || !_isStoreOpen) ? null : _startChat,
                  icon: Icon(isSold ? Icons.block : (!_isStoreOpen ? Icons.lock_clock : FluentIcons.chat_24_filled)),
                  label: Text(isSold ? 'BARANG TERJUAL' : (!_isStoreOpen ? 'TOKO TUTUP' : 'CHAT PENJUAL')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSold ? Colors.grey : (!_isStoreOpen ? Colors.red[300] : Colors.green), 
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    elevation: isSold ? 0 : 4,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(children: [Icon(icon, size: 16, color: Colors.grey[700]), const SizedBox(width: 4), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}