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

  // Unarchive (Kembalikan ke Inbox)
  Future<void> _unarchiveChat(String roomId) async {
    await Supabase.instance.client.from('chat_archives').delete().eq('room_id', roomId).eq('user_id', _myId!);
    _fetchArchivedChats(); // Refresh
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chat dikembalikan ke Inbox")));
  }

  Future<void> _fetchArchivedChats() async {
    final supabase = Supabase.instance.client;
    
    // 1. Ambil daftar room_id dari tabel archives
    final archives = await supabase.from('chat_archives').select().eq('user_id', _myId!);
    
    List<Map<String, dynamic>> results = [];

    for (var item in archives) {
      final roomId = item['room_id'];
      final mode = item['mode'];

      // 2. Ambil pesan terakhir untuk preview
      final msgRes = await supabase.from('messages').select().eq('room_id', roomId).order('created_at', ascending: false).limit(1).maybeSingle();
      
      if (msgRes != null) {
        // 3. Ambil Info Produk
        final productId = roomId.split('_')[0];
        final productRes = await supabase.from('products').select('title').eq('id', productId).maybeSingle();
        
        Map<String, dynamic> chatData = Map.from(msgRes);
        chatData['product_title'] = productRes != null ? productRes['title'] : 'Produk';
        chatData['archive_mode'] = mode;
        results.add(chatData);
      }
    }

    if (mounted) {
      setState(() {
        _archivedChats = results;
        _isLoading = false;
      });
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
                    backgroundColor: Colors.grey[300],
                    child: Icon(isPermanent ? Icons.notifications_off : Icons.history, color: Colors.grey[700]),
                  ),
                  title: Text(chat['product_title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(chat['content'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.unarchive, color: Colors.blue),
                    onPressed: () => _unarchiveChat(chat['room_id']),
                    tooltip: "Kembalikan ke Inbox",
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