import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({super.key});

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> {
  final _myId = Supabase.instance.client.auth.currentUser?.id;
  List<Map<String, dynamic>> _archivedChats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchArchivedChats();
  }

  Future<void> _fetchArchivedChats() async {
    final supabase = Supabase.instance.client;
    
    // 1. Ambil daftar arsip
    final archives = await supabase.from('chat_archives').select().eq('user_id', _myId!);
    
    List<Map<String, dynamic>> results = [];

    for (var item in archives) {
      final roomId = item['room_id'];
      final mode = item['mode'];

      // 2. Coba ambil salah satu pesan (untuk preview)
      final msgRes = await supabase.from('messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      // Kalau pesan sudah kosong (terhapus semua), kita buat data dummy biar tetap bisa dihapus dari arsip
      Map<String, dynamic> chatData = msgRes != null 
          ? Map.from(msgRes) 
          : {'room_id': roomId, 'content': 'Percakapan kosong', 'created_at': item['created_at']};
      
      try {
        final productId = roomId.split('_')[0];
        final productRes = await supabase.from('products').select('title').eq('id', productId).maybeSingle();
        chatData['product_title'] = productRes != null ? productRes['title'] : 'Produk';
      } catch (e) {
        chatData['product_title'] = 'Chat';
      }

      chatData['archive_mode'] = mode;
      results.add(chatData);
    }

    if (mounted) {
      setState(() {
        _archivedChats = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _unarchiveChat(String roomId) async {
    await Supabase.instance.client.from('chat_archives').delete().eq('room_id', roomId).eq('user_id', _myId!);
    _fetchArchivedChats(); 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chat dikembalikan ke Inbox")));
  }

  // --- FUNGSI HAPUS PERMANEN (UPDATED) ---
  Future<void> _deleteChatPermanently(String roomId) async {
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Permanen?"),
        content: const Text("Seluruh riwayat percakapan akan dihapus untuk kedua belah pihak."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Hapus Semuanya"),
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        // 1. Hapus dari Tabel Arsip (Supaya tidak nyangkut di list arsip)
        await Supabase.instance.client.from('chat_archives').delete().eq('room_id', roomId).eq('user_id', _myId!);

        // 2. Hapus SEMUA pesan di room tersebut (Tabel Messages)
        // (Berkat SQL di Langkah 1, sekarang ini akan menghapus pesan lawan bicara juga)
        await Supabase.instance.client.from('messages').delete().eq('room_id', roomId);

        if (mounted) {
          _fetchArchivedChats(); // Refresh list UI
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Percakapan berhasil dihapus total")));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal hapus: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Arsip Pesan")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : _archivedChats.isEmpty 
          ? const Center(child: Text("Tidak ada pesan diarsip"))
          : ListView.separated(
              itemCount: _archivedChats.length,
              separatorBuilder: (_,__) => const Divider(),
              itemBuilder: (context, index) {
                final chat = _archivedChats[index];
                final parts = (chat['room_id'] as String).split('_');
                final sellerId = parts.length > 1 ? parts[1] : '';
                final isPermanent = chat['archive_mode'] == 'permanent';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPermanent ? Colors.orange[100] : Colors.green[100],
                    child: Icon(isPermanent ? Icons.notifications_off : Icons.history, color: isPermanent ? Colors.orange : Colors.green),
                  ),
                  title: Text(chat['product_title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(chat['content'] ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                  
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive, color: Colors.blue),
                        onPressed: () => _unarchiveChat(chat['room_id']),
                        tooltip: "Kembalikan",
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteChatPermanently(chat['room_id']),
                        tooltip: "Hapus Permanen",
                      ),
                    ],
                  ),

                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(roomId: chat['room_id'], productTitle: chat['product_title'], sellerId: sellerId)));
                  },
                );
              },
            ),
    );
  }
}