import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart'; 
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart'; 

import '../chat/chat_page.dart';
import '../profile/seller_profile_page.dart';
import '../common/like_button.dart';
import 'edit_product_page.dart';
import 'leave_review_page.dart'; 

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

  double _avgRating = 0.0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    String rawStatus = widget.productData['status'] ?? 'Tersedia';
    if (rawStatus == 'active') rawStatus = 'Tersedia';
    if (rawStatus == 'sold') rawStatus = 'Terjual';
    _currentStatus = rawStatus;

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
      
      final reviews = await _supabase.from('reviews').select('rating').eq('target_id', sellerId);
      double totalRating = 0;
      if (reviews.isNotEmpty) {
        for (var r in reviews) totalRating += r['rating'];
        _avgRating = totalRating / reviews.length;
        _reviewCount = reviews.length;
      }
      
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

  Future<void> _markAsSoldWithBuyer() async {
    final currentUserId = _supabase.auth.currentUser!.id;
    final roomPattern = "${widget.productData['id']}_${widget.productData['user_id']}_%";

    try {
      final messagesRes = await _supabase
          .from('messages')
          .select('sender_id')
          .like('room_id', roomPattern) 
          .neq('sender_id', currentUserId);

      final Set<String> buyerIds = {};
      for (var msg in messagesRes as List) {
        if (msg['sender_id'] != null) buyerIds.add(msg['sender_id'] as String);
      }

      final List<Map<String, dynamic>> candidates = [];

      if (buyerIds.isNotEmpty) {
        final profilesRes = await _supabase
            .from('profiles')
            .select('id, full_name')
            .filter('id', 'in', buyerIds.toList());
        
        for (var p in profilesRes as List) {
          candidates.add({
            'id': p['id'],
            'name': p['full_name'] ?? 'Tanpa Nama'
          });
        }
      }

      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               const Padding(padding: EdgeInsets.all(16), child: Text("Siapa pembelinya?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
               
               if (candidates.isEmpty)
                 const Padding(padding: EdgeInsets.all(16), child: Text("Belum ada yang chat. Tandai terjual offline?")),

               ...candidates.map((c) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c['name']),
                subtitle: const Text("Pembeli via Chat"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _supabase.from('products').update({
                    'status': 'Terjual', 
                    'buyer_id': c['id']
                  }).eq('id', widget.productData['id']);
                  
                  setState(() => _currentStatus = 'Terjual');
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tandai terjual sukses!")));
                },
              )),
               
               const Divider(),
               ListTile(
                leading: const Icon(Icons.store_mall_directory, color: Colors.grey),
                title: const Text("Terjual di luar aplikasi (Offline)"),
                onTap: () {
                  Navigator.pop(ctx);
                  _updateStatus('Terjual');
                },
               ),
               const SizedBox(height: 20),
            ]
          ),
        )
      );

    } catch (e) {
      debugPrint("Error mark sold: $e");
      _updateStatus('Terjual'); 
    }
  }

  void _showNegoDialog() {
    final negoCtrl = TextEditingController();
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Ajukan Tawaran"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Harga Asli: ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(widget.productData['price'])}"),
          const SizedBox(height: 16),
          TextField(controller: negoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tawar berapa?", prefixText: "Rp ", border: OutlineInputBorder(), filled: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white), onPressed: () { Navigator.pop(ctx); if (negoCtrl.text.isNotEmpty) _startChat(offerAmount: int.tryParse(negoCtrl.text)); }, child: const Text("Kirim Tawaran")),
        ],
      )
    );
  }

  Future<void> _startChat({int? offerAmount}) async {
    if (!_isStoreOpen) { _showDialog("Toko Tutup 🔒", "Penjual sedang tutup sementara."); return; }
    if (_currentStatus == 'Terjual') { _showDialog("Barang Terjual", "Barang ini sudah laku."); return; }

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    
    final roomId = "${widget.productData['id']}_${widget.productData['user_id']}_$myId";
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(roomId: roomId, productTitle: widget.productData['title'], sellerId: widget.productData['user_id'], initialOffer: offerAmount)));
  }

  void _showDialog(String title, String content) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Oke"))])); }

  Color _getStatusColor(String status) {
    switch (status) { case 'Tersedia': return Colors.green; case 'Sedang Diproses': return Colors.orange; case 'Terjual': return Colors.grey; default: return Colors.blue; }
  }

  // --- LOGIKA TEXT KOTA PINTAR (UPDATED) ---
  String _getShortLocation(String fullAddress) {
    // 1. Pecah berdasarkan koma
    List<String> parts = fullAddress.split(',').map((e) => e.trim()).toList();
    
    if (parts.length <= 1) return fullAddress; // Kalau cuma 1 kata, yaudah tampilkan

    // 2. Filter bagian yang BUKAN angka (Kode Pos) dan BUKAN Negara
    List<String> validParts = parts.where((part) {
      // Cek apakah angka (Kode Pos)
      bool isNumeric = int.tryParse(part.replaceAll(' ', '')) != null;
      // Cek apakah Negara
      bool isCountry = part.toLowerCase() == 'indonesia';
      
      return !isNumeric && !isCountry;
    }).toList();

    // 3. Ambil 2 bagian terakhir dari sisa filter (Biasanya Kecamatan, Kota/Kabupaten)
    if (validParts.isEmpty) return fullAddress;
    
    if (validParts.length >= 2) {
      // Ambil 2 terakhir (Kecamatan, Kota)
      return "${validParts[validParts.length - 2]}, ${validParts.last}";
    } else {
      // Ambil 1 terakhir (Kota)
      return validParts.last;
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(widget.productData['price']);
    
    final double? lat = widget.productData['latitude'];
    final double? lng = widget.productData['longitude'];
    final bool hasLocation = (lat != null && lng != null);
    final LatLng productLoc = hasLocation ? LatLng(lat, lng) : const LatLng(-6.200, 106.816);

    final isSold = _currentStatus == 'Terjual';
    final primaryColor = Theme.of(context).primaryColor;

    // Ambil alamat dari data (bisa dari kolom city atau address)
    final String fullAddress = widget.productData['address'] ?? widget.productData['city'] ?? 'Lokasi tidak tersedia';
    // Gunakan fungsi pintar kita
    final String shortLocation = _getShortLocation(fullAddress);

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Produk')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: widget.productData['image_url'] ?? '', 
                  height: 300, width: double.infinity, fit: BoxFit.cover,
                  color: isSold ? Colors.white.withOpacity(0.4) : null,
                  colorBlendMode: isSold ? BlendMode.modulate : null,
                  placeholder: (context, url) => Container(height: 300, color: Colors.grey[200]),
                  errorWidget: (context, url, error) => Container(height: 300, color: Colors.grey[200], child: const Icon(Icons.image_not_supported)),
                ),
                if (_currentStatus != 'Tersedia')
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 8), color: _getStatusColor(_currentStatus).withOpacity(0.9), child: Text(_currentStatus.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                  )
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isMine) ...[
                    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade100)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("📊 Statistik Penjualan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_buildStatItem(FluentIcons.eye_24_regular, "$_viewCount", "Dilihat"), Container(height: 30, width: 1, color: Colors.grey[300]), _buildStatItem(FluentIcons.heart_24_regular, "$_likeCount", "Difavoritkan")]),
                      const Divider(height: 24),
                      const Text("Ubah Status:", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)), child: DropdownButton<String>(value: _currentStatus, isExpanded: true, underline: const SizedBox(), items: ['Tersedia', 'Sedang Diproses', 'Terjual'].map((String value) { return DropdownMenuItem<String>(value: value, child: Row(children: [Icon(Icons.circle, size: 12, color: _getStatusColor(value)), const SizedBox(width: 8), Text(value)])); }).toList(), onChanged: (newValue) { if (newValue == 'Terjual') { _markAsSoldWithBuyer(); } else if (newValue != null) { _updateStatus(newValue); } })),
                    ])).animate().slideY(begin: 0.2, duration: 400.ms),
                    const SizedBox(height: 20),
                  ],

                  Text(widget.productData['title'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(price, style: TextStyle(fontSize: 22, color: primaryColor, fontWeight: FontWeight.bold)),
                      LikeButton(productId: widget.productData['id']),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  const Text("Deskripsi:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(widget.productData['description'] ?? '-'),
                  const Divider(height: 40),

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
                            backgroundImage: _sellerProfile?['avatar_url'] != null ? CachedNetworkImageProvider(_sellerProfile!['avatar_url']) : null,
                            child: _sellerProfile?['avatar_url'] == null ? Text((_sellerProfile?['full_name'] ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                          ),
                          title: Text(_sellerProfile?['full_name'] ?? 'Penjual', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_reviewCount > 0) Padding(padding: const EdgeInsets.only(bottom: 4.0), child: Row(children: [const Icon(Icons.star, size: 14, color: Colors.amber), const SizedBox(width: 4), Text("${_avgRating.toStringAsFixed(1)} ($_reviewCount)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))])),
                              Text(_isStoreOpen ? "Klik untuk lihat profil" : "• Toko Sedang Tutup", style: TextStyle(color: _isStoreOpen ? Colors.black54 : Colors.red, fontWeight: _isStoreOpen ? FontWeight.normal : FontWeight.bold)),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: widget.productData['user_id']))),
                        ),
                      ),
                  const SizedBox(height: 20),

                  // --- MAP RADIUS (OPENSTREETMAP) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       const Text("Perkiraan Lokasi:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // PETA NON-INTERAKTIF
                  Container(
                    height: 200, width: double.infinity,
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: hasLocation 
                        ? FlutterMap(
                            options: MapOptions(
                              initialCenter: productLoc,
                              initialZoom: 13.0,
                              // --- KUNCI INTERAKSI (GESER/ZOOM OFF) ---
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.smart_marketplace'),
                              // RADIUS BIRU
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: productLoc,
                                    color: Colors.blue.withOpacity(0.3),
                                    borderStrokeWidth: 2,
                                    borderColor: Colors.blue,
                                    useRadiusInMeter: true,
                                    radius: 800, 
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Container(color: Colors.grey[200], child: const Center(child: Text("Lokasi tidak disematkan penjual"))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // --- TAMPILKAN ALAMAT PENDEK ---
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.grey), 
                      const SizedBox(width: 4), 
                      Expanded(
                        child: Text(
                          shortLocation, // Nama Kota Saja
                          style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)
                        )
                      )
                    ]
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
              ? ElevatedButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => EditProductPage(product: widget.productData))); }, icon: const Icon(FluentIcons.edit_24_filled), label: const Text('EDIT BARANG'), style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), elevation: 4))
              : (widget.productData['buyer_id'] == _supabase.auth.currentUser?.id)
                  ? ElevatedButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveReviewPage(product: widget.productData))); }, icon: const Icon(Icons.star), label: const Text('BERI ULASAN'), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)))
                  : Row(children: [Expanded(child: OutlinedButton.icon(onPressed: (_loading || isSold || !_isStoreOpen) ? null : _showNegoDialog, icon: const Icon(Icons.handshake), label: const Text("Nego"), style: OutlinedButton.styleFrom(foregroundColor: primaryColor, side: BorderSide(color: primaryColor), minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))), const SizedBox(width: 12), Expanded(flex: 2, child: ElevatedButton.icon(onPressed: (_loading || isSold || !_isStoreOpen) ? null : _startChat, icon: Icon(isSold ? Icons.block : (!_isStoreOpen ? Icons.lock_clock : FluentIcons.chat_24_filled)), label: Text(isSold ? 'TERJUAL' : (!_isStoreOpen ? 'TOKO TUTUP' : 'CHAT PENJUAL')), style: ElevatedButton.styleFrom(backgroundColor: isSold ? Colors.grey : (!_isStoreOpen ? Colors.red[300] : Colors.green), foregroundColor: Colors.white, minimumSize: const Size(0, 50), elevation: isSold ? 0 : 4)))]),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(children: [Row(children: [Icon(icon, size: 16, color: Colors.grey[700]), const SizedBox(width: 4), Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]), Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]);
  }
}