import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../product/product_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String productTitle;
  final String sellerId;
  final int? initialOffer;

  const ChatPage({
    super.key, 
    required this.roomId, 
    required this.productTitle,
    required this.sellerId,
    this.initialOffer,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  late final String _myId;
  
  late final Stream<List<Map<String, dynamic>>> _messagesStream;
  late final RealtimeChannel _roomChannel;
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;

  String? _partnerAvatarUrl;
  String _partnerNameInitials = "?";
  Map<String, dynamic>? _productInfo;
  Map<String, dynamic>? _replyMessage;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser!.id;
    _fetchPartnerProfile();
    _fetchProductInfo(); 

    // SETUP STREAM REALTIME
    _messagesStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: false);

    _setupTypingChannel();

    // Auto Kirim Nego (Hanya sekali saat dibuka pertama dari halaman produk)
    if (widget.initialOffer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendOfferMessage(widget.initialOffer!);
      });
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _typingTimer?.cancel();
    try { _supabase.removeChannel(_roomChannel); } catch (_) {}
    super.dispose();
  }

  Future<void> _fetchProductInfo() async {
    try {
      final productId = widget.roomId.split('_')[0];
      final data = await _supabase.from('products').select().eq('id', productId).single();
      if (mounted) setState(() => _productInfo = data);
    } catch (e) { debugPrint("Gagal load info produk: $e"); }
  }

  Future<void> _fetchPartnerProfile() async {
    try {
      final parts = widget.roomId.split('_');
      if (parts.length < 3) return;
      final sellerId = parts[1];
      final buyerId = parts[2];
      final partnerId = (_myId == sellerId) ? buyerId : sellerId;

      final data = await _supabase.from('profiles').select('avatar_url, full_name').eq('id', partnerId).single();
      if (mounted) {
        setState(() {
          _partnerAvatarUrl = data['avatar_url'];
          final String name = data['full_name'] ?? '?';
          _partnerNameInitials = name.isNotEmpty ? name[0].toUpperCase() : '?';
        });
      }
    } catch (e) {}
  }

  // --- LOGIC NEGO STABIL ---
  Future<void> _sendOfferMessage(int amount) async {
    // Cek dulu apakah sudah ada tawaran pending yang sama biar ga double
    final existing = await _supabase.from('messages')
        .select()
        .eq('room_id', widget.roomId)
        .eq('type', 'offer')
        .eq('offer_amount', amount)
        .eq('offer_status', 'pending')
        .limit(1);
        
    if (existing.isNotEmpty) return; // Jangan kirim lagi kalau sudah ada

    try {
      final amountStr = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(amount);
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _myId,
        'content': "Mengajukan tawaran: $amountStr",
        'is_read': false,
        'type': 'offer',
        'offer_amount': amount,
        'offer_status': 'pending',
      });
      // Tidak perlu setState manual, Stream akan otomatis menampilkan pesan baru
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal kirim tawaran')));
    }
  }

  Future<void> _respondToOffer(String messageId, String status) async {
    try {
      // Update status di database
      await _supabase.from('messages').update({'offer_status': status}).eq('id', messageId);
      // Stream akan otomatis mendeteksi perubahan ini dan me-rebuild UI
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal update status')));
    }
  }

  // --- LOGIC LAINNYA ---
  Future<void> _softDeleteMessage(String id) async { await _supabase.from('messages').update({'is_deleted': true, 'content': '🚫 Pesan telah dihapus', 'reply_text': null}).eq('id', id); }
  Future<void> _editMessage(String id, String oldText) async { 
    final ctrl = TextEditingController(text: oldText);
    await showDialog(context: context, builder: (_) => AlertDialog(title: const Text("Edit"), content: TextField(controller: ctrl), actions: [ElevatedButton(onPressed: () async { await _supabase.from('messages').update({'content': ctrl.text.trim(), 'is_edited': true}).eq('id', id); if (mounted) Navigator.pop(context); }, child: const Text("Simpan"))]));
  }
  Future<void> _markAsRead() async { await _supabase.from('messages').update({'is_read': true}).eq('room_id', widget.roomId).neq('sender_id', _myId).eq('is_read', false); }
  void _setupTypingChannel() { _roomChannel = _supabase.channel('room_${widget.roomId}'); _roomChannel.onBroadcast(event: 'typing', callback: (payload) { if (payload['user_id'] != _myId) { if (mounted) setState(() => _isOtherUserTyping = true); _typingTimer?.cancel(); _typingTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _isOtherUserTyping = false); }); } }).subscribe(); }
  Future<void> _onTyping() async { await _roomChannel.sendBroadcastMessage(event: 'typing', payload: {'user_id': _myId}); }

  Future<void> _sendMessage({String? customText}) async {
    final text = customText ?? _messageCtrl.text.trim();
    if (text.isEmpty) return;
    
    final replyId = _replyMessage?['id'];
    final replyText = _replyMessage?['content'];
    final replySenderId = _replyMessage?['sender_id'];

    if (customText == null) { _messageCtrl.clear(); setState(() => _replyMessage = null); }

    try {
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _myId,
        'content': text,
        'is_read': false,
        'type': 'text',
        'reply_to_id': replyId,
        'reply_text': replyText,
        'reply_sender_id': replySenderId,
      });
    } catch (e) {}
  }

  void _activateReply(Map<String, dynamic> msg) { setState(() { _replyMessage = msg; }); }
  void _showOptions(Map<String, dynamic> msg, bool isMe) { 
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: Icon(Icons.reply, color: Theme.of(context).primaryColor), title: const Text('Balas'), onTap: () { Navigator.pop(context); _activateReply(msg); }),
      if (isMe && msg['type'] != 'offer') ...[ 
        const Divider(),
        ListTile(leading: const Icon(Icons.edit, color: Colors.blue), title: const Text('Edit Pesan'), onTap: () => _editMessage(msg['id'], msg['content'])),
        ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Hapus Pesan'), onTap: () => _softDeleteMessage(msg['id'])),
      ]
    ])));
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);
    if (checkDate == today) return "HARI INI";
    try { return DateFormat('d MMMM yyyy', 'id').format(date).toUpperCase(); } 
    catch (e) { return DateFormat('d MMM yyyy').format(date).toUpperCase(); }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () { if (_productInfo != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: _productInfo!))); },
          child: Row(children: [
            Container(
                margin: const EdgeInsets.only(right: 10),
                width: 40, height: 40,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: ClipOval(
                  // --- CACHED IMAGE ---
                  child: (_productInfo != null && _productInfo!['image_url'] != null)
                      ? CachedNetworkImage(
                          imageUrl: _productInfo!['image_url'], 
                          fit: BoxFit.cover, 
                          errorWidget: (_,__,___)=>const Icon(Icons.image, color: Colors.grey)
                        )
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.productTitle, style: const TextStyle(fontSize: 16, color: Colors.white, overflow: TextOverflow.ellipsis)), const Text("Klik untuk lihat barang", style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: Colors.white70))])),
          ]),
        ),
      ),
      
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!;
                
                if (messages.any((m) => m['sender_id'] != _myId && m['is_read'] == false)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
                }

                if (messages.isEmpty) return const Center(child: Text("Mulai percakapan..."));

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == _myId;
                    final isDeleted = msg['is_deleted'] == true;
                    final type = msg['type'] ?? 'text';
                    
                    bool showDate = false;
                    final DateTime msgDate = DateTime.parse(msg['created_at']).toLocal();
                    if (index == messages.length - 1) { showDate = true; } 
                    else {
                      final nextMsg = messages[index + 1];
                      final DateTime nextDate = DateTime.parse(nextMsg['created_at']).toLocal();
                      if (msgDate.day != nextDate.day) showDate = true;
                    }

                    // --- PISAHKAN LOGIKA BUBBLE DI SINI ---
                    Widget bubbleContent;

                    if (type == 'offer' && !isDeleted) {
                      // A. BUBBLE NEGO
                      final amount = msg['offer_amount'] ?? 0;
                      final status = msg['offer_status'] ?? 'pending';
                      final amountStr = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(amount);
                      
                      bubbleContent = Container(
                        width: 260,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: primaryColor.withOpacity(0.5), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [const Icon(Icons.handshake, color: Colors.orange, size: 18), const SizedBox(width: 8), Text("Tawaran Harga", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]))]),
                            const Divider(),
                            Center(child: Text(amountStr, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryColor))),
                            const SizedBox(height: 10),
                            
                            if (status == 'pending') ...[
                              if (!isMe) 
                                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                                  ElevatedButton(onPressed: () => _respondToOffer(msg['id'], 'rejected'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(80, 35), padding: EdgeInsets.zero), child: const Text("Tolak", style: TextStyle(fontSize: 12))),
                                  ElevatedButton(onPressed: () => _respondToOffer(msg['id'], 'accepted'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(80, 35), padding: EdgeInsets.zero), child: const Text("Terima", style: TextStyle(fontSize: 12))),
                                ])
                              else 
                                Container(padding: const EdgeInsets.all(6), width: double.infinity, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)), child: const Center(child: Text("Menunggu respon...", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))))
                            ] else if (status == 'accepted') ...[
                              Container(padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green)), child: const Center(child: Text("✅ DITERIMA", style: TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold))))
                            ] else ...[
                              Container(padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red)), child: const Center(child: Text("❌ DITOLAK", style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold))))
                            ]
                          ],
                        ),
                      );
                    } else {
                      // B. BUBBLE TEXT BIASA (Dengan Fix Lebar & Layout)
                      Widget? replyWidget;
                      if (msg['reply_text'] != null && !isDeleted) {
                        replyWidget = Container(
                          margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: isMe ? Colors.white : primaryColor, width: 4))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(msg['reply_sender_id'] == _myId ? "Anda" : "Balasan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Colors.white.withOpacity(0.9) : primaryColor)), const SizedBox(height: 2), Text(msg['reply_text'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: isMe ? Colors.white.withOpacity(0.8) : Colors.black54))]),
                        );
                      }

                      bubbleContent = Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isDeleted ? Colors.grey[200] : (isMe ? primaryColor : Colors.white),
                          borderRadius: BorderRadius.only(topLeft: const Radius.circular(12), topRight: const Radius.circular(12), bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0), bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12)),
                          boxShadow: isDeleted ? null : [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (replyWidget != null) replyWidget,
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0, right: 8.0),
                                child: Text(isDeleted ? "🚫 Pesan telah dihapus" : msg['content'], style: TextStyle(color: isDeleted ? Colors.grey[600] : (isMe ? Colors.white : Colors.black87), fontSize: 15, fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal), textAlign: isMe ? TextAlign.right : TextAlign.left),
                              ),
                              Align(alignment: Alignment.bottomRight, child: Row(mainAxisSize: MainAxisSize.min, children: [if (msg['is_edited'] == true && !isDeleted) Text("diedit ", style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: isMe ? Colors.white70 : Colors.grey)), Text(DateFormat.Hm().format(msgDate), style: TextStyle(fontSize: 10, color: isDeleted ? Colors.transparent : (isMe ? Colors.white70 : Colors.grey))), if (isMe && !isDeleted) ...[const SizedBox(width: 4), Icon(Icons.done_all, size: 14, color: msg['is_read'] == true ? Colors.lightBlueAccent : Colors.white60)]]))
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        if (showDate) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), child: Text(_formatDateSeparator(msgDate), style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold)))),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Row(
                            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[CircleAvatar(radius: 14, backgroundColor: Colors.grey[300], backgroundImage: (_partnerAvatarUrl != null && _partnerAvatarUrl!.isNotEmpty) ? NetworkImage(_partnerAvatarUrl!) : null, child: (_partnerAvatarUrl == null || _partnerAvatarUrl!.isEmpty) ? Text(_partnerNameInitials, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)) : null), const SizedBox(width: 6)],
                              Flexible(
                                child: GestureDetector(
                                  onLongPress: () { if (!isDeleted) _showOptions(msg, isMe); },
                                  child: bubbleContent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          
          if (_isOtherUserTyping) const Padding(padding: EdgeInsets.only(left: 20, bottom: 8), child: Text("Sedang mengetik...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
          if (_replyMessage != null) Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border(left: BorderSide(color: primaryColor, width: 4))), child: Row(children: [Icon(Icons.reply, color: primaryColor), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Membalas pesan...", style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 12)), Text(_replyMessage!['content'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87))])), IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _replyMessage = null))])),
          Padding(padding: const EdgeInsets.all(16.0), child: Row(children: [Expanded(child: TextField(controller: _messageCtrl, onChanged: (_) => _onTyping(), decoration: InputDecoration(hintText: 'Ketik pesan...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.grey))))), const SizedBox(width: 8), CircleAvatar(backgroundColor: primaryColor, child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage))])),
        ],
      ),
    );
  }
}