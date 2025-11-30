import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart'; // Package Animasi
import 'package:animated_text_kit/animated_text_kit.dart'; // Package Teks
import '../auth/login_page.dart';
import '../home/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  
  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    await Future.delayed(const Duration(seconds: 4)); // Tunggu animasi selesai

    final session = Supabase.instance.client.auth.currentSession;
    if (mounted) {
      if (session != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, 
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- ICON ANIMASI (Berdenyut & Goyang) ---
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_bag_rounded,
                size: 80,
                color: Theme.of(context).primaryColor,
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(duration: 1000.ms, begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1)) // Denyut
              .then(delay: 500.ms)
              .shake(hz: 4, curve: Curves.easeInOutCubic), // Goyang
            ),
            
            const SizedBox(height: 30),
            
            // --- TEKS MENGETIK ---
            DefaultTextStyle(
              style: TextStyle(
                fontSize: 28.0,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
                fontFamily: 'Roboto',
              ),
              child: AnimatedTextKit(
                animatedTexts: [
                  TypewriterAnimatedText('Smart Marketplace', speed: const Duration(milliseconds: 100)),
                  TypewriterAnimatedText('Jual Beli Cerdas', speed: const Duration(milliseconds: 100)),
                  TypewriterAnimatedText('Aman & Terpercaya', speed: const Duration(milliseconds: 100)),
                ],
                isRepeatingAnimation: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}