import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController(); // Readonly
  
  File? _imageFile; // File foto dari galeri
  String? _currentAvatarUrl; // URL foto lama dari database
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await _supabase.from('profiles').select().eq('id', user.id).single();
      
      if (mounted) {
        setState(() {
          _nameCtrl.text = data['full_name'] ?? '';
          _usernameCtrl.text = data['username'] ?? '';
          _currentAvatarUrl = data['avatar_url'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FUNGSI AMBIL FOTO DARI GALERI ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  // --- FUNGSI SIMPAN & UPLOAD ---
  Future<void> _saveProfile() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nama tidak boleh kosong")));
      return;
    }
    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser!;
      String? avatarUrl = _currentAvatarUrl;

      // 1. Jika ada foto baru, upload ke Storage 'avatars'
      if (_imageFile != null) {
        final fileName = 'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        // Upload file
        await _supabase.storage.from('avatars').upload(fileName, _imageFile!, fileOptions: const FileOptions(upsert: true)); 
        // Ambil URL Publik
        avatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      // 2. Update Data Profil di Database
      await _supabase.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'avatar_url': avatarUrl,
      }).eq('id', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Profil berhasil diperbarui!"), 
          backgroundColor: Colors.green
        ));
        Navigator.pop(context, true); // Kembali & Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Gagal: $e. Pastikan bucket 'avatars' sudah dibuat."),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ambil warna utama dari tema (Merah)
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Profil")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // --- AVATAR PICKER (GANTI TEXT URL JADI INI) ---
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          border: Border.all(color: primaryColor, width: 2)
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[200],
                          // Prioritas Tampilan: 
                          // 1. File Baru (jika baru pilih)
                          // 2. URL Lama (jika ada di DB)
                          // 3. Icon Orang (default)
                          backgroundImage: _imageFile != null 
                              ? FileImage(_imageFile!) 
                              : (_currentAvatarUrl != null ? NetworkImage(_currentAvatarUrl!) : null) as ImageProvider?,
                          child: (_imageFile == null && _currentAvatarUrl == null) 
                              ? const Icon(Icons.person, size: 60, color: Colors.grey) 
                              : null,
                        ),
                      ),
                      // Ikon Kamera Kecil
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      )
                    ],
                  ),
                ),
                
                const SizedBox(height: 10),
                const Text("Ketuk foto untuk mengganti", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 30),

                // Input Nama
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: "Nama Lengkap", prefixIcon: Icon(Icons.badge)),
                ),
                const SizedBox(height: 16),
                
                // Input Username (Readonly)
                TextFormField(
                  controller: _usernameCtrl,
                  enabled: false, 
                  decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.alternate_email), filled: true),
                ),
                
                const SizedBox(height: 40),

                // --- TOMBOL SIMPAN (WARNA MERAH) ---
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor, // Merah
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : const Text("SIMPAN PERUBAHAN"),
                  ),
                )
              ],
            ),
          ),
    );
  }
}