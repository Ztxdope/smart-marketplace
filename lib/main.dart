import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart'; // Import Firebase
import 'core/constants.dart';
import 'features/splash/splash_page.dart';
import 'core/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('id_ID', null);
  
  // --- INISIALISASI FIREBASE ---
  await Firebase.initializeApp(); 
  
  // --- INISIALISASI NOTIFIKASI ---
  await NotificationService.initialize();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Definisi Warna
    const primaryRed = Color(0xFFD32F2F); 
    const secondaryRed = Color(0xFFFF5252); 

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Marketplace',
      
      // --- TEMA MERAH ---
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nexa',
        
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
          primary: primaryRed,
          secondary: secondaryRed,
          surface: Colors.white,
          background: const Color(0xFFF5F5F5),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(fontFamily: 'Nexa', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          iconTheme: IconThemeData(color: Colors.white),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontFamily: 'Nexa', fontWeight: FontWeight.bold),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.grey)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryRed, width: 2)),
        ),

        cardTheme: CardThemeData( // GANTI DARI 'CardTheme' JADI 'CardThemeData'
          color: Colors.white,
          elevation: 3,
          
          // GANTI '.withOpacity(0.1)' JADI '.withValues(alpha: 0.1)'
          // (Ini format baru Flutter 3.27+)
          shadowColor: Colors.black.withValues(alpha: 0.1), 
          
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 12),
        ),
      ),
      
      home: const SplashPage(),
    );
  }
}