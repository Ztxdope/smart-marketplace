class AppConstants {
  // --- KONFIGURASI SUPABASE ---
  // Dapatkan ini dari Dashboard Supabase -> Project Settings -> API
  static const String supabaseUrl = 'MASUKKAN_URL_PROJECT_SUPABASE_DISINI';
  static const String supabaseAnonKey = 'MASUKKAN_ANON_KEY_SUPABASE_DISINI';
  
  // Nama Bucket yang Anda buat di menu Storage
  // (Pastikan bucket ini sudah dibuat dan diset 'Public')
  static const String imageBucket = 'product-images'; 
  static const String avatarBucket = 'avatars'; // Tambahan untuk Foto Profil

  // --- KONFIGURASI GOOGLE GEMINI AI ---
  // Dapatkan ini dari https://aistudio.google.com/
  static const String geminiApiKey = 'MASUKKAN_API_KEY_GEMINI_DISINI';
}