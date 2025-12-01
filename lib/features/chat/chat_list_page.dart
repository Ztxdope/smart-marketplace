import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import 'archived_chats_page.dart'; // Pastikan file ini ada (dari tutorial sebelumnya)
import 'package:cached_network_image/cached_network_image.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _myId = Supabase.instance.client.auth.currentUser?.id;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _sellingChats = []; 
  List<Map<String, dynamic>> _buyingChats = [];  
  
  // List ID Room yang sedang di-archive
  List<String> _archivedRoomIds = [];

  late final StreamSubscription<List<Map<String, dynamic>>> _messagesSubscription;
  StreamSubscription? _archiveSubscription;

  @override
  void initState() {
    super.initState();
    _setupArchiveListener(); // Dengar perubahan arsip dulu
    _setupRealtimeSubscription(); // Baru dengar pesan
  }

  @override
  void dispose() {
    _messagesSubscription.cancel();
    _archiveSubscription?.cancel();
    super.dispose();
  }

  // --- 1. LISTENER ARSIP (Supaya realtime hilang dari list) ---
  void _setupArchiveListener() {
    if (_myId == null) return;
    _archiveSubscription = Supabase.instance.client
        .from('chat_archives')
        .stream(primaryKey: ['id'])
        .eq('user_id', _myId!)
        .listen((List<Map<String, dynamic>> data) {
          setState(() {
            _archivedRoomIds = data.map((e) => e['room_id'] as String).toList();
            // Trigger refresh pesan biar yang diarsip hilang dari layar
            // (Sebenarnya listener pesan akan otomatis rebuild jika kita menstruktur ulang, 
            // tapi untuk simpelnya kita biarkan stream pesan berjalan terus)
          });
    });
  }

  // --- 2. FUNGSI ARSIP CHAT (Dipanggil saat Tahan Lama) ---
  Future<void> _archiveChat(String roomId) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("Arsipkan Pesan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            
            ListTile(
              leading: const Icon(Icons.notifications_off, color: Colors.orange),
              title: const Text("Arsip Tetap (Mute)"),
              subtitle: const Text("Chat tetap di arsip meski ada pesan baru."),
              onTap: () async {
                Navigator.pop(ctx);
                await _executeArchive(roomId, 'permanent');
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_unread, color: Colors.green),
              title: const Text("Arsip Sementara"),
              subtitle: const Text("Chat akan muncul kembali jika ada pesan baru."),
              onTap: () async {
                Navigator.pop(ctx);
                await _executeArchive(roomId, 'auto_unarchive');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeArchive(String roomId, String mode) async {
    try {
      await Supabase.instance.client.from('chat_archives').insert({
        'user_id': _myId,
        'room_id': roomId,
        'mode': mode,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pesan diarsipkan")));
      // UI akan otomatis update karena _archiveSubscription
    } catch (e) {
      // Ignore duplicate
    }
  }

  // --- 3. LISTENER PESAN REALTIME ---
  void _setupRealtimeSubscription() {
    if (_myId == null) return;
    final supabase = Supabase.instance.client;

    _messagesSubscription = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((List<Map<String, dynamic>> allMessages) async {
      
      final Map<String, Map<String, dynamic>> sellingMap = {};
      final Map<String, Map<String, dynamic>> buyingMap = {};
      final Map<String, int> unreadCounts = {}; 

      for (var msg in allMessages) {
        final roomId = msg['room_id'] as String;
        if (!roomId.contains(_myId!)) continue; 

        // --- FILTER PENTING: SKIP JIKA ADA DI LIST ARSIP ---
        // (Note: Ini akan bekerja efektif saat stream pertama kali load atau ada pesan baru.
        // Jika arsip baru ditambahkan, _archiveListener yang akan mentrigger rebuild).
        // ---------------------------------------------------

        final parts = roomId.split('_');
        if (parts.length < 3) continue;

        final sellerId = parts[1];
        final buyerId = parts[2];

        bool isSelling = (sellerId == _myId);
        bool isBuying = (buyerId == _myId);

        if (isSelling) {
          if (!sellingMap.containsKey(roomId)) sellingMap[roomId] = Map.from(msg);
        } else if (isBuying) {
          if (!buyingMap.containsKey(roomId)) buyingMap[roomId] = Map.from(msg);
        }

        if (msg['is_read'] == false && msg['sender_id'] != _myId) {
          unreadCounts[roomId] = (unreadCounts[roomId] ?? 0) + 1;
        }
      }

      Future<List<Map<String, dynamic>>> processList(Map<String, Map<String, dynamic>> sourceMap) async {
        List<Map<String, dynamic>> resultList = sourceMap.values.toList();
        // Filter arsip lagi disini untuk memastikan list bersih
        resultList.removeWhere((chat) => _archivedRoomIds.contains(chat['room_id']));

        for (var room in resultList) {
          final roomId = room['room_id'] as String;
          room['unread_count'] = unreadCounts[roomId] ?? 0;

          try {
            final productId = roomId.split('_')[0]; 
            final productRes = await supabase.from('products').select('title, image_url, status').eq('id', productId).maybeSingle();
            
            if (productRes != null) {
              room['product_title'] = productRes['title'];
              room['product_image'] = productRes['image_url']; 
              room['product_status'] = productRes['status'];   
            } else {
              room['product_title'] = 'Produk Dihapus';
              room['product_status'] = 'Terjual';
            }
          } catch (e) {
             room['product_title'] = 'Chat';
          }
        }
        return resultList;
      }

      // Kita panggil processList setiap kali ada data baru
      // Dan kita juga memantau _archivedRoomIds di build() atau listener terpisah
      // Untuk simplifikasi, disini kita proses ulang.
      
      final sellingProcessed = await processList(sellingMap);
      final buyingProcessed = await processList(buyingMap);

      if (mounted) {
        setState(() {
          _sellingChats = sellingProcessed;
          _buyingChats = buyingProcessed;
          _isLoading = false;
        });
      }
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Tersedia': return Colors.green;
      case 'Sedang Diproses': return Colors.orange;
      case 'Terjual': return Colors.grey;
      default: return Colors.blue;
    }
  }

  Widget _buildChatList(List<Map<String, dynamic>> chats, String emptyMessage) {
    // Filter sekali lagi di UI level biar responsif saat _archivedRoomIds berubah
    final activeChats = chats.where((c) => !_archivedRoomIds.contains(c['room_id'])).toList();

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (activeChats.isEmpty) return Center(child: Text(emptyMessage, style: const TextStyle(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
      itemCount: activeChats.length,
      itemBuilder: (context, index) {
        final chat = activeChats[index];
        final unreadCount = chat['unread_count'] as int;
        final isUnread = unreadCount > 0;
        final status = chat['product_status'] ?? 'Tersedia';
        
        final parts = (chat['room_id'] as String).split('_');
        final sellerId = parts.length > 1 ? parts[1] : '';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          
          // --- ICON FOTO PRODUK ---
          leading: Stack(
            children: [
              Container(
                width: 55, height: 55,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                  // --- CACHED IMAGE ---
                  image: chat['product_image'] != null 
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(chat['product_image']), 
                        fit: BoxFit.cover,
                        colorFilter: status == 'Terjual' ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : null
                      )
                    : null,
                  color: Colors.grey[200],
                ),
                child: chat['product_image'] == null 
                    ? Icon(Icons.image_not_supported, size: 20, color: Colors.grey[400]) 
                    : null,
              ),
              if (isUnread)
                Positioned(
                  right: 0, top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2))),
                    child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),

          title: Row(
            children: [
              Expanded(
                child: Text(
                  chat['product_title'] ?? 'Loading...', 
                  style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, fontSize: 16),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status != 'Tersedia') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _getStatusColor(status), width: 0.5)
                  ),
                  child: Text(
                    status == 'Sedang Diproses' ? 'Diproses' : status,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status)),
                  ),
                )
              ]
            ],
          ),
          
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              chat['content'], 
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal, 
                color: isUnread ? Colors.black87 : Colors.grey[600]
              )
            ),
          ),
          
          trailing: Text(
            DateTime.parse(chat['created_at']).toLocal().toString().substring(11, 16),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),

          // --- NAVIGASI KE CHAT ---
          onTap: () async {
            await Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => ChatPage(
                roomId: chat['room_id'],
                productTitle: chat['product_title'] ?? 'Chat',
                sellerId: sellerId, 
              ))
            ).then((_) {
              if (mounted) setState(() {});
            });
          },

          // --- LONG PRESS: ARSIPKAN ---
          onLongPress: () {
            _archiveChat(chat['room_id']);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Daftar Pesan"),
          // TOMBOL LIHAT ARSIP
          actions: [
            IconButton(
              icon: const Icon(Icons.archive, color: Colors.white),
              tooltip: "Lihat Arsip",
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsPage()));
              },
            )
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: "Penjualan", icon: Icon(Icons.store)),
              Tab(text: "Pembelian", icon: Icon(Icons.shopping_bag)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChatList(_sellingChats, "Belum ada chat penjualan"),
            _buildChatList(_buyingChats, "Belum ada chat pembelian"),
          ],
        ),
      ),
    );
  }
}