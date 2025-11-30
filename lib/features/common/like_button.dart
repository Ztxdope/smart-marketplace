import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class LikeButton extends StatefulWidget {
  final String productId;
  final double size;
  
  const LikeButton({
    super.key, 
    required this.productId, 
    this.size = 24
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  final _supabase = Supabase.instance.client;
  bool _isLiked = false;
  String? _favoriteId; // Simpan ID favorite untuk delete nanti

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  // Cek apakah user sudah like produk ini sebelumnya
  Future<void> _checkStatus() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('product_id', widget.productId)
          .maybeSingle();

      if (mounted && data != null) {
        setState(() {
          _isLiked = true;
          _favoriteId = data['id'];
        });
      }
    } catch (e) {
      // Silent error
    }
  }

  // Logic Toggle Like
  Future<void> _toggleLike() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLiked = !_isLiked); // Optimistic Update (UI berubah dulu biar cepat)

    try {
      if (_isLiked) {
        // --- PROSES LIKE ---
        final res = await _supabase.from('favorites').insert({
          'user_id': userId,
          'product_id': widget.productId,
        }).select().single();
        _favoriteId = res['id'];
      } else {
        // --- PROSES UNLIKE ---
        if (_favoriteId != null) {
          await _supabase.from('favorites').delete().eq('id', _favoriteId!);
        } else {
          // Fallback jika ID hilang (cari berdasarkan product & user)
          await _supabase.from('favorites').delete()
              .eq('user_id', userId)
              .eq('product_id', widget.productId);
        }
      }
    } catch (e) {
      // Jika gagal, kembalikan status UI
      if (mounted) {
        setState(() => _isLiked = !_isLiked);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal update like")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isLiked ? FluentIcons.heart_24_filled : FluentIcons.heart_24_regular,
        color: _isLiked ? Colors.red : Colors.grey,
        size: widget.size,
      ),
      onPressed: _toggleLike,
    );
  }
}