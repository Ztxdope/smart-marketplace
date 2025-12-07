import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Pastikan import ini ada

class AboutCreatorsPage extends StatelessWidget {
  const AboutCreatorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    
    // --- DATA PEMBUAT (EDIT DISINI) ---
    // Masukkan Link Public URL dari Supabase ke bagian 'image'
    final List<Map<String, String>> creators = [
      {
        "name": "Maulana Dzulqairil Cahya",
        "nim": "NIM: 2303421005",
        "role": "Fullstack Dev & AI Specialist",
        // CONTOH URL SUPABASE (GANTI DENGAN PUNYA ANDA):
        "image": "https://ucbdvvxjjptvfuoferhg.supabase.co/storage/v1/object/public/avatars/Maulana.jpg", 
      },
      {
        "name": "Dwi Rama Satya Wikana",
        "nim": "NIM: 2303421018",
        "role": "Frontend Dev",
        // CONTOH URL SUPABASE (GANTI DENGAN PUNYA ANDA):
        "image": "https://ucbdvvxjjptvfuoferhg.supabase.co/storage/v1/object/public/avatars/Dwi.jpg",
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tentang Pembuat"),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: creators.length,
        itemBuilder: (context, index) {
          final creator = creators[index];
          return _buildCreatorCard(context, creator);
        },
      ),
    );
  }

  Widget _buildCreatorCard(BuildContext context, Map<String, String> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // Header Warna Merah dengan Pattern Cached
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              image: const DecorationImage(
                // Pattern background (bisa diganti url supabase juga kalau mau)
                image: CachedNetworkImageProvider("https://www.transparenttextures.com/patterns/cubes.png"),
                fit: BoxFit.cover,
                opacity: 0.1,
              ),
            ),
          ),
          
          // Avatar & Info
          Transform.translate(
            offset: const Offset(0, -40), // Geser avatar ke atas
            child: Column(
              children: [
                // FOTO PROFIL (CACHED)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    // Menggunakan CachedNetworkImageProvider untuk URL Supabase
                    backgroundImage: CachedNetworkImageProvider(data['image']!),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Nama
                Text(
                  data['name']!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                // NIM
                Text(
                  data['nim']!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Badge Role / Job
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    data['role']!,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}