import 'dart:io';
import 'dart:convert'; // Untuk decode JSON dari Gemini
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:location/location.dart'; 
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_generative_ai/google_generative_ai.dart'; // Pakai Gemini
import '../../core/constants.dart'; // Pastikan API Key ada disini

class UploadProductPage extends StatefulWidget {
  const UploadProductPage({super.key});

  @override
  State<UploadProductPage> createState() => _UploadProductPageState();
}

class _UploadProductPageState extends State<UploadProductPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _categoryController = TextEditingController();
  final _locationCtrl = TextEditingController();
  
  double? _latitude;
  double? _longitude;

  File? _imageFile;
  bool _isUploading = false;
  bool _isAnalyzing = false; // Loading state AI
  bool _isLoadingLocation = false;
  List<String> _aiTags = [];

  // --- FUNGSI AI GEMINI (SCAN FOTO) ---
  Future<void> _analyzeImageWithGemini(File image) async {
    setState(() => _isAnalyzing = true);

    try {
      // 1. Siapkan Model (Pakai gemini-1.5-flash yang cepat & support gambar)
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: AppConstants.geminiApiKey,
      );

      // 2. Baca gambar sebagai bytes
      final imageBytes = await image.readAsBytes();

      // 3. Buat Prompt Super Pintar (Minta format JSON)
      final prompt = TextPart(
        """
        Kamu adalah asisten AI untuk aplikasi marketplace.
        Analisis gambar produk ini dan berikan output HANYA dalam format JSON (tanpa markdown ```json).
        
        Struktur JSON yang diminta:
        {
          "title": "Nama produk yang menarik dan singkat (Max 30 karakter)",
          "price": "Estimasi harga dalam angka rupiah (tanpa titik/koma, contoh: 150000)",
          "category": "Satu kata kategori yang paling cocok (Contoh: Elektronik, Fashion, Otomotif, Makanan, Hobi)",
          "description": "Deskripsi penjualan yang persuasif, menarik, dan menyertakan spesifikasi yang terlihat di gambar (Max 3 paragraf).",
          "tags": ["tag1", "tag2", "tag3", "tag4"]
        }
        """
      );

      // 4. Kirim ke Gemini
      final content = [
        Content.multi([
          prompt,
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await model.generateContent(content);
      final responseText = response.text;

      if (responseText != null) {
        // 5. Bersihkan format JSON (kadang Gemini kasih ```json di awal)
        String cleanJson = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
        
        // 6. Parsing JSON
        final Map<String, dynamic> data = jsonDecode(cleanJson);

        setState(() {
          // Isi Form Otomatis
          _titleController.text = data['title'] ?? '';
          _priceController.text = data['price'].toString();
          _categoryController.text = data['category'] ?? 'Umum';
          _descController.text = data['description'] ?? '';
          
          // Simpan Tags
          _aiTags = List<String>.from(data['tags'] ?? []);
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ AI Berhasil Mengisi Data!"),
          backgroundColor: Colors.green,
        ));
      }

    } catch (e) {
      debugPrint("Gemini Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Gagal analisa AI: $e"), 
        backgroundColor: Colors.red
      ));
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Pilih dari Galeri (atau ganti ImageSource.camera)
    final pickedFile = await picker.pickImage(source: ImageSource.gallery); 
    
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      setState(() => _imageFile = file);
      
      // Langsung panggil Gemini setelah foto dipilih
      _analyzeImageWithGemini(file);
    }
  }

  // --- FUNGSI LOKASI (TETAP SAMA) ---
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    Location location = Location();
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) throw 'GPS tidak aktif';
      }
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) throw 'Izin lokasi ditolak';
      }
      LocationData locationData = await location.getLocation();
      
      if (locationData.latitude == null || locationData.longitude == null) throw 'GPS Error';

      _latitude = locationData.latitude;
      _longitude = locationData.longitude;

      try {
        List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(_latitude!, _longitude!);
        if (placemarks.isNotEmpty) {
          geo.Placemark place = placemarks[0];
          String address = [place.street, place.subLocality, place.locality].where((s) => s != null && s.isNotEmpty).join(', ');
          _locationCtrl.text = address.isEmpty ? "$_latitude, $_longitude" : address;
        } else {
          _locationCtrl.text = "${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}";
        }
      } catch (_) {
        _locationCtrl.text = "${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _uploadProduct() async {
    if (!_formKey.currentState!.validate() || _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto wajib ada!'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isUploading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    try {
      final fileName = '${user!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('product-images').upload(fileName, _imageFile!);
      final imageUrl = supabase.storage.from('product-images').getPublicUrl(fileName);

      await supabase.from('products').insert({
        'user_id': user.id,
        'title': _titleController.text,
        'description': _descController.text,
        'price': int.parse(_priceController.text),
        'category': _categoryController.text,
        'image_url': imageUrl, 
        'city': _locationCtrl.text,
        'address': _locationCtrl.text,
        'latitude': _latitude,
        'longitude': _longitude,
        'status': 'Tersedia',
        'ai_tags': _aiTags, 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk Berhasil Diupload!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jual Barang')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- AREA FOTO ---
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                    image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null
                  ),
                  child: _imageFile == null 
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center, 
                          children: [
                            Icon(Icons.add_a_photo, size: 50, color: Theme.of(context).primaryColor), 
                            const SizedBox(height: 8),
                            const Text("Ketuk untuk Foto", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            const Text("AI akan otomatis mengisi data!", style: TextStyle(fontSize: 10, color: Colors.blue)),
                          ]
                        ) 
                      : null,
                ),
              ),
              
              // Loading Indikator AI
              if (_isAnalyzing)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Expanded(child: Text("Gemini sedang menganalisa foto...", style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic))),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              
              // Form Fields
              TextFormField(controller: _titleController, decoration: const InputDecoration(labelText: 'Nama Produk', border: OutlineInputBorder(), prefixIcon: Icon(Icons.shopping_bag)), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money))),
              const SizedBox(height: 12),
              TextFormField(controller: _categoryController, decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category))),
              const SizedBox(height: 12),
              
              // Lokasi
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _locationCtrl, decoration: const InputDecoration(labelText: 'Lokasi COD', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin_drop)), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null)),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                    child: IconButton(
                      icon: _isLoadingLocation ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location, color: Colors.red),
                      onPressed: _getCurrentLocation,
                    ),
                  )
                ],
              ),
              
              const SizedBox(height: 12),
              TextFormField(controller: _descController, maxLines: 5, decoration: const InputDecoration(labelText: 'Deskripsi Produk', border: OutlineInputBorder(), alignLabelWithHint: true)),
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isUploading || _isAnalyzing) ? null : _uploadProduct,
                  child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('POSTING SEKARANG'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}