import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT

class EditProductPage extends StatefulWidget {
  final Map<String, dynamic> product;
  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _descCtrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.product['title']);
    _priceCtrl = TextEditingController(text: widget.product['price'].toString());
    _descCtrl = TextEditingController(text: widget.product['description']);
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.from('products').update({
        'title': _titleCtrl.text,
        'price': int.parse(_priceCtrl.text),
        'description': _descCtrl.text,
      }).eq('id', widget.product['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Data berhasil diperbarui!"),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal update: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Edit Produk")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (widget.product['image_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  // --- CACHED IMAGE ---
                  child: CachedNetworkImage(
                    imageUrl: widget.product['image_url'],
                    height: 200, 
                    width: double.infinity, 
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(height: 200, color: Colors.grey[200]),
                    errorWidget: (context, url, error) => Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                  ),
                ),
              const SizedBox(height: 20),
              
              TextFormField(
                controller: _titleCtrl, 
                decoration: const InputDecoration(labelText: 'Nama Produk', prefixIcon: Icon(Icons.shopping_bag))
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _priceCtrl, 
                keyboardType: TextInputType.number, 
                decoration: const InputDecoration(labelText: 'Harga', prefixIcon: Icon(Icons.attach_money))
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descCtrl, 
                maxLines: 5, 
                decoration: const InputDecoration(labelText: 'Deskripsi')
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("SIMPAN PERUBAHAN"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}