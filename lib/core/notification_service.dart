import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// Handler untuk notifikasi saat aplikasi dimatikan (Background)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Pastikan Firebase diinisialisasi jika perlu logic khusus
  print("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // 1. Inisialisasi Service
  static Future<void> initialize() async {
    // Request Izin (Penting untuk Android 13+ dan iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true, badge: true, sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Izin notifikasi diberikan');
    }

    // Setup Local Notification (Untuk menampilkan notif saat aplikasi dibuka)
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    
    await _localNotifications.initialize(initSettings);

    // Listener Pesan saat aplikasi dibuka (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showLocalNotification(message);
      }
    });

    // Listener Background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // 2. Tampilkan Notifikasi Lokal (Heads-up)
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel', // Id Channel
      'Notifikasi Penting', // Nama Channel
      importance: Importance.max,
      priority: Priority.high,
    );
    
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      platformDetails,
    );
  }

  // 3. Dapatkan Token & Simpan ke Supabase
  static Future<void> uploadFcmToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (token != null && userId != null) {
        print("FCM Token: $token");
        await Supabase.instance.client
            .from('profiles')
            .update({'fcm_token': token})
            .eq('id', userId);
      }
    } catch (e) {
      print("Gagal upload token: $e");
    }
  }
}