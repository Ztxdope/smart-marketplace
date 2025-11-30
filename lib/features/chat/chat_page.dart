import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
// Hapus import flutter_slidable karena kita pakai Long Press
import '../product/product_detail_page.dart';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String productTitle;
  final String sellerId;

  const ChatPage({
    super.key, 
    required this.roomId, 
    required this.productTitle,
    required this.sellerId,
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
  
  // State Reply
  Map<String, dynamic>? _replyMessage;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser!.id;
    _fetchPartnerProfile();
    _fetchProductInfo(); 

    _messagesStream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('created_at', ascending: false);

    _setupTypingChannel();
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
    } catch (e) { debugPrint("Gagal load partner: $e"); }
  }

  Future<void> _softDeleteMessage(String id) async {
    try {
      await _supabase.from('messages').update({'is_deleted': true, 'content': '🚫 Pesan telah dihapus', 'reply_text': null}).eq('id', id);
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal hapus'))); }
  }

  Future<void> _editMessage(String id, String oldText) async {
    final ctrl = TextEditingController(text: oldText);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Pesan"),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(onPressed: () async {
            if (ctrl.text.trim().isNotEmpty) {
              await _supabase.from('messages').update({'content': ctrl.text.trim(), 'is_edited': true}).eq('id', id);
              if (mounted) Navigator.pop(context); // Tutup Dialog
              if (mounted) Navigator.pop(context); // Tutup Menu
            }
          }, child: const Text("Simpan"))
        ],
      )
    );
  }

  Future<void> _markAsRead() async {
    await _supabase.from('messages').update({'is_read': true}).eq('room_id', widget.roomId).neq('sender_id', _myId).eq('is_read', false);
  }

  void _setupTypingChannel() {
    _roomChannel = _supabase.channel('room_${widget.roomId}');
    _roomChannel.onBroadcast(event: 'typing', callback: (payload) {
      if (payload['user_id'] != _myId) {
        if (mounted) setState(() => _isOtherUserTyping = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _isOtherUserTyping = false); });
      }
    }).subscribe();
  }

  Future<void> _onTyping() async { await _roomChannel.sendBroadcastMessage(event: 'typing', payload: {'user_id': _myId}); }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    
    final replyId = _replyMessage?['id'];
    final replyText = _replyMessage?['content'];
    final replySenderId = _replyMessage?['sender_id'];

    _messageCtrl.clear();
    setState(() => _replyMessage = null);

    try {
      await _supabase.from('messages').insert({
        'room_id': widget.roomId,
        'sender_id': _myId,
        'content': text,
        'is_read': false,
        'is_edited': false,
        'is_deleted': false,
        'reply_to_id': replyId,
        'reply_text': replyText,
        'reply_sender_id': replySenderId,
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'))); }
  }

  void _activateReply(Map<String, dynamic> msg) {
    setState(() { _replyMessage = msg; });
  }

  // --- MENU OPSI (MUNCUL SAAT TEKAN LAMA) ---
  void _showOptions(Map<String, dynamic> msg, bool isMe) {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            // 1. BALAS (Semua bisa)
            ListTile(
              leading: Icon(Icons.reply, color: Theme.of(context).primaryColor), 
              title: const Text('Balas'), 
              onTap: () {
                Navigator.pop(context);
                _activateReply(msg);
              }
            ),
            
            // 2. EDIT & HAPUS (Hanya Pesan Sendiri)
            if (isMe) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue), 
                title: const Text('Edit Pesan'), 
                onTap: () => _editMessage(msg['id'], msg['content'])
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red), 
                title: const Text('Hapus Pesan'), 
                onTap: () => _softDeleteMessage(msg['id'])
              ),
            ]
          ]
        )
      )
    );
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
          onTap: () {
            if (_productInfo != null) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(productData: _productInfo!)));
            }
          },
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 10),
                width: 40, height: 40,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: ClipOval(child: (_productInfo != null && _productInfo!['image_url'] != null) ? Image.network(_productInfo!['image_url'], fit: BoxFit.cover, errorBuilder: (_,__,___)=>const Icon(Icons.image, color: Colors.grey)) : const Icon(Icons.image, color: Colors.grey)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.productTitle, style: const TextStyle(fontSize: 16, color: Colors.white, overflow: TextOverflow.ellipsis)),
                    const Text("Klik untuk lihat barang", style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
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
                    final isRead = msg['is_read'] == true;
                    final isEdited = msg['is_edited'] == true;
                    final isDeleted = msg['is_deleted'] == true;
                    
                    bool showDate = false;
                    final DateTime msgDate = DateTime.parse(msg['created_at']).toLocal();
                    if (index == messages.length - 1) { showDate = true; } 
                    else {
                      final nextMsg = messages[index + 1];
                      final DateTime nextDate = DateTime.parse(nextMsg['created_at']).toLocal();
                      if (msgDate.day != nextDate.day) showDate = true;
                    }

                    // --- 1. WIDGET REPLY ---
                    Widget? replyWidget;
                    if (msg['reply_text'] != null && !isDeleted) {
                      replyWidget = Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        // Hapus width: double.infinity
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(color: isMe ? Colors.white : Theme.of(context).primaryColor, width: 4)
                          )
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['reply_sender_id'] == _myId ? "Anda" : "Balasan",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Colors.white.withOpacity(0.9) : Theme.of(context).primaryColor)
                            ),
                            const SizedBox(height: 2),
                            Text(
                              msg['reply_text'],
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: isMe ? Colors.white.withOpacity(0.8) : Colors.black54)
                            ),
                          ],
                        ),
                      );
                    }

                    // --- 2. BUBBLE CHAT (DENGAN FIX INTRINSIC WIDTH) ---
                    Widget bubble = GestureDetector(
                      onLongPress: () { if (!isDeleted) _showOptions(msg, isMe); },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isDeleted 
                              ? Colors.grey[300] 
                              : (isMe ? Theme.of(context).primaryColor : Colors.white),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                          ),
                          boxShadow: isDeleted ? null : [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 2, offset: const Offset(0, 1))],
                        ),
                        // FIX: IntrinsicWidth memaksa Container mengecil sesuai konten
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (replyWidget != null) replyWidget,
                              
                              // Teks Pesan
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4.0, right: 8.0), // Right padding biar jam ga nempel
                                child: Text(
                                  isDeleted ? "🚫 Pesan telah dihapus" : msg['content'], 
                                  style: TextStyle(
                                    color: isDeleted ? Colors.grey[600] : (isMe ? Colors.white : Colors.black87),
                                    fontSize: 15,
                                    fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                                  )
                                ),
                              ),
                              
                              // Jam & Centang (Pojok Kanan)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isEdited && !isDeleted) Text("diedit ", style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: isMe ? Colors.white70 : Colors.grey)),
                                    Text(DateFormat.Hm().format(msgDate), style: TextStyle(fontSize: 10, color: isDeleted ? Colors.transparent : (isMe ? Colors.white70 : Colors.grey))),
                                    if (isMe && !isDeleted) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.done_all, size: 14, color: isRead ? Colors.lightBlueAccent : Colors.white60)
                                    ]
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    );

                    return Column(
                      children: [
                        if (showDate) 
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12), 
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), 
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)), 
                              child: Text(_formatDateSeparator(msgDate), style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold))
                            )
                          ),
                        
                        // ROW UTAMA (Posisi Kiri/Kanan)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Row(
                            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                CircleAvatar(
                                  radius: 14, backgroundColor: Colors.grey[300],
                                  backgroundImage: (_partnerAvatarUrl != null && _partnerAvatarUrl!.isNotEmpty) ? NetworkImage(_partnerAvatarUrl!) : null,
                                  child: (_partnerAvatarUrl == null || _partnerAvatarUrl!.isEmpty) ? Text(_partnerNameInitials, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)) : null,
                                ),
                                const SizedBox(width: 6),
                              ],
                              
                              // Flexible agar bubble bisa mengecil/membesar tapi tetap dibatasi max-width
                              Flexible(child: bubble),
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
          
          // PREVIEW REPLY
          if (_replyMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), border: Border(left: BorderSide(color: primaryColor, width: 4))),
              child: Row(
                children: [
                  Icon(Icons.reply, color: primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Membalas pesan...", style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 12)),
                        Text(_replyMessage!['content'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _replyMessage = null))
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(children: [
                Expanded(child: TextField(controller: _messageCtrl, onChanged: (_) => _onTyping(), decoration: InputDecoration(hintText: 'Ketik pesan...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.grey))))),
                const SizedBox(width: 8),
                CircleAvatar(backgroundColor: primaryColor, child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage))
            ]),
          )
        ],
      ),
    );
  }
}