import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Import Gemini
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants.dart'; // Import API Key

class BotPage extends StatefulWidget {
  const BotPage({super.key});

  @override
  State<BotPage> createState() => _BotPageState();
}

class _BotPageState extends State<BotPage> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isLoading = false;

  // Inisialisasi Model Gemini
  late final GenerativeModel _model;
  late final ChatSession _chatSession;

  // List Pesan (UI)
  final List<Map<String, String>> _messages = [
    {
      'role': 'model', 
      'text': 'Halo! Saya Asisten Pintar Smart Marketplace. 🤖\n\nSaya bisa bantu kamu cari ide jualan, tips aman bertransaksi, atau sekadar ngobrol. Ada yang bisa dibantu?'
    }
  ];

  @override
  void initState() {
    super.initState();
    _initGemini();
  }

  void _initGemini() {
    // Setup Model
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Model cepat & ringan
      apiKey: AppConstants.geminiApiKey,
      // Instruksi agar AI berperan sebagai Asisten Marketplace
      systemInstruction: Content.system(
        'Kamu adalah asisten AI yang ramah dan membantu untuk aplikasi bernama "Smart Marketplace". '
        'Tugasmu adalah membantu pengguna (pembeli dan penjual). '
        'Berikan jawaban yang singkat, padat, dan menggunakan Emoji agar menarik. '
        'Jika ditanya tentang coding, tolak dengan sopan dan bilang kamu hanya fokus pada jual beli.'
      ),
    );

    // Mulai sesi chat (agar dia ingat konteks percakapan sebelumnya)
    _chatSession = _model.startChat();
  }

Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
    });
    _textCtrl.clear();
    _scrollToBottom();

    try {
      // Kirim ke Gemini
      final response = await _chatSession.sendMessage(Content.text(text));

      setState(() {
        if (response.text != null) {
          _messages.add({'role': 'model', 'text': response.text!});
        } else {
          _messages.add({'role': 'model', 'text': 'AI tidak memberikan respons teks.'});
        }
      });
    } catch (e) {
      // --- MODIFIKASI DISINI UNTUK DEBUGGING ---
      debugPrint("ERROR GEMINI: $e"); // Cek di Terminal VSCode
      setState(() {
        // Tampilkan error asli ke layar HP biar ketahuan penyebabnya
        _messages.add({'role': 'model', 'text': 'Error System: $e'}); 
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(FluentIcons.bot_24_filled, color: Colors.white),
            SizedBox(width: 8),
            Text("Asisten AI"),
          ],
        ),
      ),
      body: Column(
        children: [
          // --- LIST PESAN ---
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? Theme.of(context).primaryColor : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    child: Text(
                      msg['text']!,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ).animate().fade().slideY(begin: 0.2, end: 0), // Animasi muncul
                );
              },
            ),
          ),

          // --- INDIKATOR LOADING ---
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16, height: 16, 
                      child: CircularProgressIndicator(strokeWidth: 2)
                    ),
                    const SizedBox(width: 8),
                    Text("AI sedang mengetik...", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ),
            ),

          // --- INPUT BAR ---
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Tanya sesuatu...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  mini: true,
                  elevation: 2,
                  child: _isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Icon(FluentIcons.send_24_filled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}