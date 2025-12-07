import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:location/location.dart'; 
import 'package:geocoding/geocoding.dart' as geo;
import 'package:google_generative_ai/google_generative_ai.dart'; 
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart';      
import 'package:http/http.dart' as http; 
import '../../core/constants.dart'; 

class UploadProductPage extends StatefulWidget {
  const UploadProductPage({super.key});

  @override
  State<UploadProductPage> createState() => _UploadProductPageState();
}

class _UploadProductPageState extends State<UploadProductPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  
  String? _selectedCategory;
  double? _latitude;
  double? _longitude;

  File? _imageFile;
  bool _isUploading = false;
  bool _isAnalyzing = false; 
  bool _isLoadingLocation = false;
  
  bool _isAddressValid = false; 

  List<String> _aiTags = [];
  final MapController _mapController = MapController();
  LatLng _pickedLocation = const LatLng(-6.200000, 106.816666);
  
  List<dynamic> _addressSuggestions = [];
  Timer? _debounce;
  bool _isSearchingAddress = false;

  final List<String> _validCategories = [
    'Kendaraan', 'Sewa Properti', 'Alat Kantor', 'Alat Musik', 
    'Barang Rumah Tangga', 'Elektronik', 'Hiburan', 'Hobi', 
    'Jual Rumah', 'Kebutuhan Hewan Peliharaan', 'Keluarga', 
    'Mainan & Game', 'Pakaian', 'Perlengkapan Renovasi Rumah', 
    'Taman & Outdoor'
  ];

  // --- 1. CARI ALAMAT (NOMINATIM API) ---
  void _onSearchChanged(String query) {
    if (_isAddressValid) setState(() => _isAddressValid = false); 

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (query.length > 3) {
        _fetchAddressSuggestions(query);
      } else {
        setState(() => _addressSuggestions = []);
      }
    });
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    setState(() => _isSearchingAddress = true);
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5&countrycodes=id');
      
      // PERBAIKAN: Tambahkan Header User-Agent agar tidak diblokir OSM
      final response = await http.get(url, headers: {
        'User-Agent': 'com.example.smart_marketplace', 
      });
      
      if (response.statusCode == 200) {
        setState(() {
          _addressSuggestions = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Gagal cari alamat: $e");
    } finally {
      setState(() => _isSearchingAddress = false);
    }
  }

  void _selectSuggestion(Map<String, dynamic> place) {
    final lat = double.parse(place['lat']);
    final lon = double.parse(place['lon']);
    final displayName = place['display_name'];

    setState(() {
      _locationCtrl.text = displayName;
      _addressSuggestions = [];
      _pickedLocation = LatLng(lat, lon);
      _latitude = lat;
      _longitude = lon;
      _isAddressValid = true;
    });

    _mapController.move(_pickedLocation, 15);
    FocusScope.of(context).unfocus();
  }

  // --- 2. AMBIL ALAMAT DARI KOORDINAT (REVERSE GEOCODING) ---
  // Fungsi ini dipanggil saat Peta di-tap atau GPS aktif
  Future<void> _getAddressFromLatLng(LatLng point) async {
    setState(() {
      _isLoadingLocation = true;
      _pickedLocation = point; // Update marker dulu biar responsif
    });

    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(point.latitude, point.longitude);
      if (placemarks.isNotEmpty) {
        geo.Placemark place = placemarks[0];
        // Format Alamat yang rapi
        String address = [place.street, place.subLocality, place.locality, place.administrativeArea]
            .where((s) => s != null && s.isNotEmpty).join(', ');
        
        // Fallback jika kosong
        if (address.isEmpty) address = "${place.subAdministrativeArea}, ${place.country}";

        setState(() {
          _locationCtrl.text = address; // Isi textfield dengan Nama Jalan
          _latitude = point.latitude;
          _longitude = point.longitude;
          _isAddressValid = true;
        });
      }
    } catch (e) {
      // Jika gagal, baru pakai koordinat (daripada kosong)
      setState(() {
         _locationCtrl.text = "${point.latitude}, ${point.longitude}";
         _latitude = point.latitude;
         _longitude = point.longitude;
         _isAddressValid = true;
      });
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  // --- 3. GPS OTOMATIS ---
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    Location location = Location();
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) { serviceEnabled = await location.requestService(); if (!serviceEnabled) throw 'GPS mati'; }
      if (await location.hasPermission() == PermissionStatus.denied) await location.requestPermission();
      
      LocationData locData = await location.getLocation();
      if (locData.latitude != null && locData.longitude != null) {
        final point = LatLng(locData.latitude!, locData.longitude!);
        _mapController.move(point, 15);
        // Panggil fungsi konversi alamat
        _getAddressFromLatLng(point);
      }
    } catch (e) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal GPS: $e"))); 
      setState(() => _isLoadingLocation = false); 
    } 
  }

  // --- 4. AI GEMINI ---
  Future<void> _analyzeImageWithGemini(File image) async {
    setState(() => _isAnalyzing = true);
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: AppConstants.geminiApiKey);
      final imageBytes = await image.readAsBytes();
      
      final prompt = TextPart("""
        Analisis gambar produk ini. Output WAJIB JSON murni tanpa markdown.
        Aturan:
        1. 'price': HARUS angka integer murni (contoh: 150000).
        2. 'category': Pilih satu dari: ${_validCategories.join(', ')}.
        3. 'title': Nama produk singkat (Max 40 huruf).
        JSON: { "title": "...", "price": 100000, "category": "...", "description": "...", "tags": [] }
      """);

      final response = await model.generateContent([Content.multi([prompt, DataPart('image/jpeg', imageBytes)])]);
      
      if (response.text != null) {
        String cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> data = jsonDecode(cleanJson);

        setState(() {
          _titleCtrl.text = data['title'] ?? '';
          _priceCtrl.text = (data['price'] ?? 0).toString().replaceAll(RegExp(r'[^0-9]'), ''); 
          String aiCat = data['category'] ?? '';
          if (_validCategories.contains(aiCat)) { _selectedCategory = aiCat; } else { _selectedCategory = null; }
          _descCtrl.text = data['description'] ?? '';
          _aiTags = List<String>.from(data['tags'] ?? []);
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ AI Selesai!"), backgroundColor: Colors.green));
      }
    } catch (e) { 
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("AI Gagal: $e")));
    } 
    finally { setState(() => _isAnalyzing = false); }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery); 
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      setState(() => _imageFile = file);
      _analyzeImageWithGemini(file);
    }
  }

  Future<void> _uploadProduct() async {
    if (!_formKey.currentState!.validate() || _imageFile == null || _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lengkapi data & foto!'), backgroundColor: Colors.red));
      return;
    }
    if (!_isAddressValid) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih alamat valid dari saran/peta!'), backgroundColor: Colors.orange));
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
        'title': _titleCtrl.text,
        'description': _descCtrl.text,
        'price': int.parse(_priceCtrl.text),
        'category': _selectedCategory,
        'image_url': imageUrl, 
        'city': _locationCtrl.text,
        'address': _locationCtrl.text,
        'latitude': _latitude ?? _pickedLocation.latitude,
        'longitude': _longitude ?? _pickedLocation.longitude,
        'status': 'Tersedia',
        'ai_tags': _aiTags, 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk Berhasil Diupload!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal Upload: $e')));
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 180, width: double.infinity,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null),
                  child: _imageFile == null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 50, color: Colors.grey), Text("Foto & Scan AI")]) : null,
                ),
              ),
              
              if (_isAnalyzing)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Expanded(child: Text("Gemini sedang menganalisa foto...", style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic)))]),
                ),

              const SizedBox(height: 16),
              TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Nama Produk', border: OutlineInputBorder(), prefixIcon: Icon(Icons.shopping_bag)), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga (Rp)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)), validator: (v) => v!.isEmpty ? 'Wajib diisi' : null),
              const SizedBox(height: 12),
              
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
                hint: const Text("Pilih Kategori"),
                items: _validCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
                validator: (v) => v == null ? 'Pilih kategori' : null,
              ),

              const SizedBox(height: 20),
              
              const Text("Lokasi COD (Wajib Valid)", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              TextField(
                controller: _locationCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Ketik Nama Jalan / Tempat...',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearchingAddress || _isLoadingLocation 
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) 
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () { _locationCtrl.clear(); setState(() { _addressSuggestions = []; _isAddressValid = false; }); }),
                  helperText: _isAddressValid ? "✅ Alamat Valid" : "Ketik lalu PILIH dari saran atau KLIK PETA",
                  helperStyle: TextStyle(color: _isAddressValid ? Colors.green : Colors.red),
                ),
              ),

              if (_addressSuggestions.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _addressSuggestions.length,
                    separatorBuilder: (_,__) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _addressSuggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, size: 16, color: Colors.red),
                        title: Text(place['display_name']),
                        onTap: () => _selectSuggestion(place),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 12),
              
              Container(
                height: 250,
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _pickedLocation,
                          initialZoom: 15.0,
                          // PERBAIKAN: Panggil fungsi alamat saat tap
                          onTap: (_, point) {
                             _getAddressFromLatLng(point); 
                          }
                        ),
                        children: [
                          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.smart_marketplace'),
                          MarkerLayer(markers: [Marker(point: _pickedLocation, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40))]),
                        ],
                      ),
                      Positioned(bottom: 10, right: 10, child: FloatingActionButton.small(onPressed: _getCurrentLocation, backgroundColor: Colors.white, child: _isLoadingLocation ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Icon(Icons.my_location, color: Colors.blue)))
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              TextFormField(controller: _descCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Deskripsi Produk', border: OutlineInputBorder(), alignLabelWithHint: true)),
              
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: (_isUploading) ? null : _uploadProduct, child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('POSTING SEKARANG'))),
            ],
          ),
        ),
      ),
    );
  }
}