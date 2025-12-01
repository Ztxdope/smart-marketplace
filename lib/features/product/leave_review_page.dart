import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaveReviewPage extends StatefulWidget {
  final Map<String, dynamic> product;
  const LeaveReviewPage({super.key, required this.product});

  @override
  State<LeaveReviewPage> createState() => _LeaveReviewPageState();
}

class _LeaveReviewPageState extends State<LeaveReviewPage> {
  final _commentCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  
  double _rating = 5.0;
  bool _isSubmitting = false;
  bool _isAnonymous = false; // State untuk checkbox
  bool _hasReviewed = false; // Cek apakah sudah pernah review

  @override
  void initState() {
    super.initState();
    _checkIfReviewed();
  }

  // Cek apakah user sudah pernah review produk ini
  Future<void> _checkIfReviewed() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final res = await _supabase
        .from('reviews')
        .select('id')
        .eq('product_id', widget.product['id'])
        .eq('reviewer_id', userId)
        .maybeSingle();

    if (res != null && mounted) {
      setState(() => _hasReviewed = true);
    }
  }

  Future<void> _submitReview() async {
    setState(() => _isSubmitting = true);
    final user = _supabase.auth.currentUser;

    try {
      await _supabase.from('reviews').insert({
        'product_id': widget.product['id'],
        'reviewer_id': user!.id,
        'target_id': widget.product['user_id'], 
        'rating': _rating.toInt(),
        'comment': _commentCtrl.text.trim(),
        'is_anonymous': _isAnonymous, // Simpan status anonim
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ulasan terkirim! Terima kasih."), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      // Error code 23505 adalah duplicate key (sudah pernah review)
      if (e.toString().contains('23505') || e.toString().contains('unique constraint')) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Anda sudah mengulas produk ini sebelumnya.")));
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    // Jika sudah pernah review, tampilkan pesan saja
    if (_hasReviewed) {
      return Scaffold(
        appBar: AppBar(title: const Text("Beri Ulasan")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 60, color: Colors.green),
              const SizedBox(height: 16),
              const Text("Anda sudah mengulas produk ini.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Kembali"))
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Beri Ulasan")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text("Bagaimana pesananmu?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryColor)),
            const SizedBox(height: 8),
            Text(widget.product['title'], style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            
            RatingBar.builder(
              initialRating: 5,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: false,
              itemCount: 5,
              itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
              itemBuilder: (context, _) => const Icon(Icons.star, color: Colors.amber),
              onRatingUpdate: (rating) {
                setState(() => _rating = rating);
              },
            ),
            
            const SizedBox(height: 24),
            
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Ceritakan pengalamanmu beli barang ini...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[100]
              ),
            ),
            
            const SizedBox(height: 16),

            // --- CHECKBOX ANONIM ---
            CheckboxListTile(
              title: const Text("Kirim sebagai Anonim"),
              subtitle: const Text("Nama Anda akan disembunyikan di profil penjual"),
              value: _isAnonymous,
              activeColor: primaryColor,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading, // Checkbox di kiri
              onChanged: (val) {
                setState(() => _isAnonymous = val ?? false);
              },
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white
                ),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("KIRIM ULASAN"),
              ),
            )
          ],
        ),
      ),
    );
  }
}