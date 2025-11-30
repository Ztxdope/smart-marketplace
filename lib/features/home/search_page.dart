import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart'; // Animasi Mic
import 'package:speech_to_text/speech_to_text.dart' as stt; // Voice
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Gemini
import '../../core/constants.dart';
import '../product/product_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _isListening = false; // Status Mic

  // Objek Speech to Text
  late stt.SpeechToText _speech;
  
  // Objek Gemini
  late final GenerativeModel _geminiModel;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // Init Gemini (Pakai flash biar cepet)
    _geminiModel = GenerativeModel(
      model: 'gemini-2.5-flash', 
      apiKey: AppConstants.geminiApiKey,
    );
  }

  // --- 1. FUNGSI PENCARIAN DB ---
  Future<void> _doSearch(String keyword) async {
    if (keyword.isEmpty) return;
    setState(() => _isLoading = true);
    
    try {
      // Gunakan RPC 'search_products' yang sudah kita buat di SQL sebelumnya
      // Atau query manual dengan ilike
      final response = await _supabase
          .from('products')
          .select()
          .ilike('title', '%$keyword%'); // Mencari yang mirip

      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Search Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. GEMINI: RAJIN MERAPIKAN KATA KUNCI ---
  // Mengubah "Cariin sepatu warna merah dong" -> "Sepatu Merah"
  Future<String> _refineQueryWithAI(String rawVoiceText) async {
    try {
      final prompt = "Ekstrak kata kunci produk inti dari kalimat ini untuk pencarian database. "
          "Hanya berikan kata kuncinya saja, tanpa tanda baca. "
          "Kalimat: '$rawVoiceText'";
      
      final response = await _geminiModel.generateContent([Content.text(prompt)]);
      final refined = response.text?.trim() ?? rawVoiceText;
      
      debugPrint("Voice Asli: $rawVoiceText -> AI: $refined");
      return refined;
    } catch (e) {
      return rawVoiceText; // Kalau AI error, pakai teks asli
    }
  }

  // --- 3. FUNGSI VOICE LISTENER ---
  Future<void> _listen() async {
    if (!_isListening) {
      // A. Cek Izin
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        await Permission.microphone.request();
      }

      // B. Mulai Dengar
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening') {
             setState(() => _isListening = false);
          }
        },
        onError: (val) => print('onErrors: $val'),
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) async {
            // Tampilkan teks sementara saat ngomong
            setState(() {
              _searchCtrl.text = val.recognizedWords;
            });

            // Jika user selesai ngomong (Final Result)
            if (val.finalResult) {
              setState(() => _isListening = false);
              
              // Panggil AI untuk rapikan teks
              _searchCtrl.text = "Memproses AI...";
              String smartKeyword = await _refineQueryWithAI(val.recognizedWords);
              
              _searchCtrl.text = smartKeyword;
              _doSearch(smartKeyword); // Cari otomatis
            }
          },
        );
      }
    } else {
      // Stop manual
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  String formatRupiah(num price) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(price);

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        // Custom Search Bar di AppBar
        title: Container(
          height: 45,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _doSearch,
            autofocus: false,
            decoration: InputDecoration(
              hintText: _isListening ? 'Mendengarkan...' : 'Cari barang...',
              hintStyle: TextStyle(color: _isListening ? primaryColor : Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              
              // --- TOMBOL MIC ---
              suffixIcon: GestureDetector(
                onTap: _listen,
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? primaryColor : Colors.grey,
                )
                .animate(target: _isListening ? 1 : 0) // Animasi saat aktif
                .scale(duration: 200.ms, begin: const Offset(1,1), end: const Offset(1.2, 1.2))
                .then().shake(hz: 4), // Efek getar saat mendengar
              ),
            ),
          ),
        ),
      ),
      
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _results.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  const Text("Ketik atau gunakan suara\nuntuk mencari barang", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final product = _results[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProductDetailPage(productData: product)
                    ));
                  },
                  child: Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              product['image_url'] ?? '', 
                              width: 80, height: 80, fit: BoxFit.cover,
                              errorBuilder: (_,__,___) => Container(color: Colors.grey[200], width: 80, height: 80),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(formatRupiah(product['price']), style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(product['city'] ?? 'Indonesia', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}