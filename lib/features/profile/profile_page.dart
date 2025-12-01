import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toggle_switch/toggle_switch.dart'; 
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; 

// Import Halaman Lain
import '../auth/login_page.dart';
import '../chat/chat_list_page.dart';
import '../product/my_products_page.dart';
import '../admin/admin_dashboard_page.dart'; // <--- Import Admin Page
import 'edit_profile_page.dart';
//import '../settings/settings_page.dart'; // Import Settings jika ada
import 'package:cached_network_image/cached_network_image.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  
  Map<String, dynamic>? _profileData;
  bool _isLoadingProfile = true;
  bool _isStoreOpen = true; 
  bool _isAdmin = false; // State untuk menyimpan status Admin

  @override
  void initState() {
    super.initState();
    _getProfile();
  }

  // Ambil data profil & cek role
  Future<void> _getProfile() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final data = await _supabase.from('profiles').select().eq('id', userId).single();
      
      if (mounted) {
        setState(() {
          _profileData = data;
          _isStoreOpen = data['is_store_open'] ?? true;
          
          // --- CEK APAKAH USER ADALAH ADMIN ---
          // Pastikan kolom 'role' sudah ada di database (lihat SQL sebelumnya)
          _isAdmin = (data['role'] == 'admin');
          
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint("Error load profile: $e");
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  // Update status toko Buka/Tutup
  Future<void> _updateStoreStatus(int index) async {
    final isOpen = (index == 0);
    try {
      final userId = _supabase.auth.currentUser!.id;
      await _supabase.from('profiles').update({'is_store_open': isOpen}).eq('id', userId);
      setState(() => _isStoreOpen = isOpen);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isOpen ? "Toko DIBUKA ✅" : "Toko DITUTUP ⛔"), backgroundColor: isOpen ? Colors.green : Colors.red));
    } catch (e) { debugPrint("Gagal update status: $e"); }
  }

  Future<void> _handleLogout() async {
    await _supabase.auth.signOut();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final String fullName = _profileData?['full_name'] ?? user?.userMetadata?['full_name'] ?? 'User';
    final String username = _profileData?['username'] ?? 'username';
    final String? avatarUrl = _profileData?['avatar_url'];
    
    // Warna Tema
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil Saya'), centerTitle: true),
      body: _isLoadingProfile 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // --- AVATAR & NAMA ---
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor, width: 2)),
                  child: CircleAvatar(
                    radius: 50, backgroundColor: Colors.grey[200],
                    // --- CACHED PROVIDER ---
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) 
                        ? CachedNetworkImageProvider(avatarUrl) 
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(fullName[0].toUpperCase(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold))
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text("@$username", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                
                // Label Admin Keren
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                    child: const Text("ADMINISTRATOR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                  )
                ],

                const SizedBox(height: 24),
                
                // --- STATUS TOKO ---
                const Text("Status Toko", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ToggleSwitch(
                  minWidth: 110.0,
                  initialLabelIndex: _isStoreOpen ? 0 : 1,
                  cornerRadius: 20.0,
                  activeFgColor: Colors.white,
                  inactiveBgColor: Colors.grey[200],
                  inactiveFgColor: Colors.black87,
                  totalSwitches: 2,
                  labels: const ['Buka', 'Tutup'],
                  icons: const [FontAwesomeIcons.shop, FontAwesomeIcons.shopLock],
                  activeBgColors: const [[Colors.green], [Colors.red]],
                  onToggle: (index) { if (index != null) _updateStoreStatus(index); },
                ),

                const SizedBox(height: 30),
                
                // --- MENU LIST ---
                
                // 1. ADMIN PANEL (Hanya muncul jika _isAdmin == true)
                if (_isAdmin) ...[
                  _buildMenuTile(
                    icon: Icons.admin_panel_settings, 
                    color: Colors.black, 
                    title: 'Admin Panel', 
                    subtitle: 'Hapus User, Edit Barang, Moderasi',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardPage()))
                  ),
                  const Divider(),
                ],

                // 2. Menu User Biasa
                _buildMenuTile(icon: FontAwesomeIcons.solidComments, color: Colors.blue, title: 'Pesan / Chat', subtitle: 'Riwayat percakapan', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListPage()))),
                _buildMenuTile(icon: FontAwesomeIcons.boxOpen, color: Colors.purple, title: 'Barang Jualan Saya', subtitle: 'Kelola produk anda', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyProductsPage()))),
                _buildMenuTile(icon: FontAwesomeIcons.userPen, color: Colors.orange, title: 'Edit Profil', subtitle: 'Ubah nama & foto', onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())); _getProfile(); }),
                
                // 3. Settings
                //_buildMenuTile(icon: Icons.settings, color: Colors.grey, title: 'Pengaturan', subtitle: 'Tema & Bahasa', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),

                const Divider(height: 40),
                
                // 4. Logout
                _buildMenuTile(icon: FontAwesomeIcons.rightFromBracket, color: Colors.red, title: 'Keluar', subtitle: 'Logout akun', onTap: _handleLogout),
              ],
            ),
          ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required Color color, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}