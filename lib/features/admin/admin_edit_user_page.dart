import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT

class AdminEditUserPage extends StatefulWidget {
  final String userId;
  final String currentName;
  final String currentUsername;
  final String currentEmail;
  final String? currentAvatar;

  const AdminEditUserPage({
    super.key,
    required this.userId,
    required this.currentName,
    required this.currentUsername,
    required this.currentEmail,
    this.currentAvatar,
  });

  @override
  State<AdminEditUserPage> createState() => _AdminEditUserPageState();
}

class _AdminEditUserPageState extends State<AdminEditUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  
  late TextEditingController _nameCtrl;
  late TextEditingController _usernameCtrl;
  
  File? _imageFile; 
  String? _currentAvatarUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentName);
    _usernameCtrl = TextEditingController(text: widget.currentUsername);
    _currentAvatarUrl = widget.currentAvatar;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _deleteOldAvatar() async {
    if (_currentAvatarUrl == null) return;
    try {
      final uri = Uri.parse(_currentAvatarUrl!);
      final fileName = uri.pathSegments.last;
      await _supabase.storage.from('avatars').remove([fileName]);
    } catch (e) {}
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String? newAvatarUrl = _currentAvatarUrl;

      if (_imageFile != null) {
        await _deleteOldAvatar(); 
        final fileName = 'avatar_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _supabase.storage.from('avatars').upload(fileName, _imageFile!, fileOptions: const FileOptions(upsert: true));
        newAvatarUrl = _supabase.storage.from('avatars').getPublicUrl(fileName);
      }

      await _supabase.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'avatar_url': newAvatarUrl,
      }).eq('id', widget.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data user berhasil diubah admin!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e (Username mungkin duplikat)")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetAvatar() async {
    final confirm = await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Foto Profil?"),
        content: const Text("Foto profil user ini akan dihapus permanen."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text("Hapus")),
        ],
      )
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _deleteOldAvatar();
        await _supabase.from('profiles').update({'avatar_url': null}).eq('id', widget.userId);
        
        setState(() {
          _currentAvatarUrl = null;
          _imageFile = null;
        });
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto profil user dihapus")));
      } catch (e) {
        // Error
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit User (Admin Mode)"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage, 
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.red, width: 3)),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey[300],
                        // --- CACHED IMAGE LOGIC ---
                        backgroundImage: _imageFile != null 
                            ? FileImage(_imageFile!) 
                            : (_currentAvatarUrl != null ? CachedNetworkImageProvider(_currentAvatarUrl!) : null) as ImageProvider?,
                        child: (_imageFile == null && _currentAvatarUrl == null) 
                            ? const Icon(Icons.person, size: 60, color: Colors.grey) 
                            : null,
                      ),
                    ),
                    Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20)),
                  ],
                ),
              ),
              
              if (_currentAvatarUrl != null || _imageFile != null)
                TextButton.icon(onPressed: _resetAvatar, icon: const Icon(Icons.delete, color: Colors.red), label: const Text("Hapus Foto", style: TextStyle(color: Colors.red))),

              const SizedBox(height: 20),
              TextFormField(initialValue: widget.currentEmail, readOnly: true, decoration: const InputDecoration(labelText: "Email (Tidak bisa diubah)", prefixIcon: Icon(Icons.email), filled: true)),
              const SizedBox(height: 16),
              TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Nama Lengkap", prefixIcon: Icon(Icons.badge)), validator: (v) => v!.isEmpty ? "Wajib diisi" : null),
              const SizedBox(height: 16),
              TextFormField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.alternate_email), helperText: "Admin bisa mengubah username user lain"), validator: (v) => v!.isEmpty ? "Wajib diisi" : null),
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _saveChanges, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SIMPAN PERUBAHAN (ADMIN)"))),
            ],
          ),
        ),
      ),
    );
  }
}