import 'dart:io';  // ⚠️ PLATFORM CHECK!
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data'; // 🔥 Int64List için!
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart'; // 🔥 RATE LIMIT RESET İÇİN!
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart'; // 🔥 MethodChannel için!
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// GELİŞMİŞ BİLDİRİM SERVİSİ - MÜŞTERİ UYGULAMASI!
// 🔥 V2.0 - RATE LIMIT SORUNU ÇÖZÜLDÜ!
class AdvancedNotificationService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static FirebaseMessaging? _messaging;
  static bool _initialized = false;
  static bool _isInitializing = false;
  static String? _cachedFcmToken;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  
  // 🔥 YENİ: FCM token sadece 1 kez alınsın - COMPLETER PATTERN!
  static Completer<bool>? _fcmCompleter; // Tek istek için kilit
  static bool _fcmTokenSentToServer = false;
  
  // MÜŞTERİ BİLDİRİM TÜRLERİ
  static const Map<String, NotificationConfig> _customerNotifications = {
    'driver_found': NotificationConfig(
      title: '🎯 Vale Bulundu!',
      channelId: 'ride_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'driver_departed': NotificationConfig(
      title: '🚗 Vale Yola Çıktı',
      channelId: 'ride_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'driver_approaching_5km': NotificationConfig(
      title: '📍 Vale Yaklaşıyor',
      channelId: 'location_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'driver_approaching_2km': NotificationConfig(
      title: '📍 Vale Çok Yakın',
      channelId: 'location_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'driver_approaching_500m': NotificationConfig(
      title: '🏃‍♂️ Vale Neredeyse Geldi',
      channelId: 'location_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'driver_arrived': NotificationConfig(
      title: '✋ Vale Geldi!',
      channelId: 'ride_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'ride_started': NotificationConfig(
      title: '🚗 Yolculuğunuz Başladı!',
      channelId: 'funbreak_rides',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'ride_completed': NotificationConfig(
      title: '✅ Yolculuk Tamamlandı',
      channelId: 'ride_updates',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'payment_processed': NotificationConfig(
      title: '💳 Ödeme İşlendi',
      channelId: 'payment_updates',
      priority: 'normal',
      sound: 'default',
    ),
  };
  
  // 🔥 SERVİS BAŞLATMA - FCM TOKEN ALMADAN!
  // FCM token sadece registerFcmToken() ile alınacak (login sonrası)
  static Future<void> initialize() async {
    if (_initialized) {
      print('⏭️ Bildirim servisi zaten başlatıldı - atlanıyor');
      return;
    }
    
    if (_isInitializing) {
      print('⏳ Bildirim servisi şu an başlatılıyor - bekleniyor...');
      return;
    }
    
    _isInitializing = true;
    
    try {
      print('🔔 Bildirim servisi başlatılıyor (V2.0 - Rate Limit Fix)...');
      
      // Platform-specific initialization
      if (Platform.isIOS) {
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: false, // 🔥 İZİN İSTEME - Login sonrası yapılacak!
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        
        await _localNotifications.initialize(
          const InitializationSettings(iOS: iosSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        print('✅ iOS bildirim sistemi başlatıldı (izin sonra istenecek)');
        
      } else {
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _localNotifications.initialize(
          const InitializationSettings(android: androidSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        await _createNotificationChannels();
        print('✅ Android bildirim sistemi başlatıldı');
      }
      
      // Firebase Messaging referansı al (token ALMADAN!)
      _messaging = FirebaseMessaging.instance;
      
      // 🔥 ESKİ LISTENER'I İPTAL ET!
      await _foregroundSubscription?.cancel();
      
      // Foreground message handler
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      print('✅ Foreground listener kayıtlı');
      
      // App açılışında notification handler
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      
      // Token güncelleme listener (sadece dinle, istek yapma)
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      
      _initialized = true;
      print('✅ Bildirim servisi hazır! (FCM token login sonrası alınacak)');

    } catch (e) {
      print('❌ Bildirim servisi başlatma hatası: $e');
    } finally {
      _isInitializing = false;
    }
  }
  
  // 🔥 YENİ: FCM TOKEN KAYDETME - SADECE LOGIN SONRASI ÇAĞRILMALI!
  // Bu fonksiyon auth_provider.dart'tan login başarılı olduktan sonra çağrılacak
  static Future<bool> registerFcmToken(int userId, {String userType = 'customer'}) async {
    // 🔥 COMPLETER PATTERN: Aynı anda gelen tüm çağrılar aynı sonucu bekler!
    if (_fcmCompleter != null) {
      print('⏳ [FCM] Token zaten isteniyor - SONUÇ BEKLENİYOR (User: $userId)');
      return await _fcmCompleter!.future; // Aynı sonucu bekle
    }
    
    // İlk çağrı: Completer oluştur ve işlemi başlat
    _fcmCompleter = Completer<bool>();
    print('🔔 [FCM] registerFcmToken BAŞLADI - User: $userId, Type: $userType');
    
    // Zaten backend'e gönderildiyse tekrar gönderme
    if (_fcmTokenSentToServer && _cachedFcmToken != null) {
      print('✅ [FCM] Token zaten backend\'e gönderildi - atlanıyor');
      _fcmCompleter!.complete(true);
      _fcmCompleter = null;
      return true;
    }
    
    // Önce cache'e bak (SharedPreferences)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('fcm_token_cached');
      if (cachedToken != null && cachedToken.isNotEmpty) {
        print('✅ [FCM] Cache\'den token bulundu - backend\'e gönderiliyor');
        final success = await _sendTokenToBackend(cachedToken, userId, userType);
        _fcmCompleter!.complete(success);
        _fcmCompleter = null;
        return success;
      }
    } catch (e) {
      print('⚠️ [FCM] Cache okuma hatası: $e');
    }
    
    try {
      // 1. Önce izin iste
      print('📱 [FCM] Bildirim izni isteniyor...');
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      print('📱 [FCM] İzin durumu: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        print('❌ [FCM] Bildirim izni reddedildi');
        _fcmCompleter!.complete(false);
        _fcmCompleter = null;
        return false;
      }
      
      // 2. iOS için foreground presentation ayarla
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      
      // 3. iOS'ta APNs token bekle (max 10 saniye)
      if (Platform.isIOS) {
        print('📱 [FCM] iOS - APNs token bekleniyor...');
        String? apnsToken;
        for (int i = 0; i < 10; i++) {
          apnsToken = await _messaging!.getAPNSToken();
          if (apnsToken != null) {
            print('✅ [FCM] APNs token alındı (${i+1}. deneme)');
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }
        
        if (apnsToken == null) {
          print('⚠️ [FCM] APNs token 10 saniyede alınamadı');
          // Devam et, FCM token deneyelim
        }
      }
      
      // 4. 🔥 GPT FIX: APNs → Firebase senkronizasyonu için 2sn bekle!
      print('⏳ [FCM] APNs → Firebase senkronizasyonu için 2sn bekleniyor...');
      await Future.delayed(const Duration(seconds: 2));
      
      // 5. FCM Token al (5 DENEME + ARTAN BEKLEME!)
      print('🔑 [FCM] Token alınıyor (5 deneme)...');
      String? token;
      
      for (int i = 0; i < 5; i++) {
        try {
          print('🔑 [FCM] Deneme ${i + 1}/5...');
          token = await _messaging!.getToken().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏱️ [FCM] Deneme ${i + 1} timeout');
              return null;
            },
          );
          
          if (token != null && token.isNotEmpty) {
            print('✅ [FCM] Token ${i + 1}. denemede alındı!');
            break;
          }
        } catch (tokenError) {
          print('⚠️ [FCM] Deneme ${i + 1} başarısız: $tokenError');
        }
        
        // Her denemede artan bekleme (2s, 4s, 6s, 8s, 10s)
        if (i < 4) {
          final waitSeconds = 2 * (i + 1);
          print('⏳ [FCM] ${waitSeconds}sn bekleniyor...');
          await Future.delayed(Duration(seconds: waitSeconds));
        }
      }
      
      if (token == null || token.isEmpty) {
        print('❌ [FCM] 5 denemede de token alınamadı - NATIVE FALLBACK deneniyor...');
        
        // 🔥 GPT DEBUG: Native MethodChannel ile dene!
        if (Platform.isIOS) {
          try {
            const nativeFcm = MethodChannel('debug_fcm');
            final nativeToken = await nativeFcm.invokeMethod<String>('getNativeFcmToken');
            print('🔥 [NATIVE FALLBACK] Sonuç: $nativeToken');
            
            if (nativeToken != null && nativeToken.isNotEmpty) {
              token = nativeToken;
              print('✅ [NATIVE FALLBACK] Token alındı!');
            }
          } catch (nativeError) {
            print('❌ [NATIVE FALLBACK] HATA: $nativeError');
            // Bu hata gerçek iOS hatasını gösterecek!
          }
        }
        
        if (token == null || token.isEmpty) {
          print('❌ [FCM] Tüm yöntemler başarısız');
          _fcmCompleter!.complete(false);
          _fcmCompleter = null;
          return false;
        }
      }
      
      print('✅ [FCM] Token alındı: ${token.substring(0, 30)}...');
      _cachedFcmToken = token;
      
      // Token'ı cache'e kaydet
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token_cached', token);
        print('💾 [FCM] Token cache\'e kaydedildi');
      } catch (e) {
        print('⚠️ [FCM] Cache kaydetme hatası: $e');
      }
      
      // Backend'e gönder
      final success = await _sendTokenToBackend(token, userId, userType);
      _fcmCompleter!.complete(success);
      _fcmCompleter = null;
      return success;
      
    } catch (e) {
      print('❌ [FCM] registerFcmToken hatası: $e');
      
      // Rate limit hatası varsa kaydet
      if (e.toString().contains('Too many') || e.toString().contains('server requests')) {
        print('🛑 [FCM] RATE LIMIT! 5 dakika bekleyin.');
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('fcm_rate_limit_time', DateTime.now().toIso8601String());
        } catch (_) {}
      }
      
      _fcmCompleter?.complete(false);
      _fcmCompleter = null;
      return false;
    }
  }
  
  // 🔥 Backend'e token gönderme helper fonksiyonu
  static Future<bool> _sendTokenToBackend(String token, int userId, String userType) async {
    try {
      print('📡 [FCM] Token backend\'e gönderiliyor...');
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': userType,
          'fcm_token': token,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ [FCM] Token backend\'e kaydedildi!');
          _fcmTokenSentToServer = true;
          _cachedFcmToken = token;
          
          // Topic'lere subscribe
          await _subscribeToTopics();
          
          return true;
        } else {
          print('❌ [FCM] Backend hatası: ${data['message']}');
        }
      } else {
        print('❌ [FCM] HTTP hatası: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      print('❌ [FCM] Backend gönderme hatası: $e');
      return false;
    }
  }
  
  // 🔥 Cache'li token'ı al (varsa)
  static String? getCachedToken() => _cachedFcmToken;
  
  // 🔥 Token durumunu sıfırla (logout için)
  static void resetTokenState() {
    _cachedFcmToken = null;
    _fcmCompleter = null;
    _fcmTokenSentToServer = false;
    print('🔄 [FCM] Token durumu sıfırlandı');
  }
  
  // ANDROID BİLDİRİM KANALLARI
  static Future<void> _createNotificationChannels() async {
    if (Platform.isIOS) return;
    
    print('🔔 [MÜŞTERİ] ANDROID CHANNEL OLUŞTURMA BAŞLADI!');
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) {
      print('❌ [MÜŞTERİ] AndroidFlutterLocalNotificationsPlugin NULL!');
      return;
    }
    
    print('🗑️ [MÜŞTERİ] Eski channellar siliniyor...');
    await androidPlugin.deleteNotificationChannel('funbreak_rides');
    await androidPlugin.deleteNotificationChannel('ride_updates');
    await androidPlugin.deleteNotificationChannel('location_updates');
    await androidPlugin.deleteNotificationChannel('payment_updates');
    
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'funbreak_rides_v2',
        'Yolculuk Bildirimleri',
        description: 'Yolculuk başlatma ve durum bildirimleri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'ride_updates_v2',
        'Yolculuk Güncellemeleri',
        description: 'Vale durumu ve yolculuk güncellemeleri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'location_updates_v3',
        'Konum Güncellemeleri',
        description: 'Vale konum ve mesafe bildirimleri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'payment_updates_v2',
        'Ödeme Bildirimleri', 
        description: 'Ödeme ve fatura bilgileri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
      ),
    ];
    
    print('🔨 [MÜŞTERİ] ${channels.length} channel oluşturuluyor...');
    for (final channel in channels) {
      await androidPlugin.createNotificationChannel(channel);
      print('  ✅ Channel: ${channel.id} (Importance: ${channel.importance})');
    }
    
    print('✅ [MÜŞTERİ] ${channels.length} bildirim kanalı OLUŞTURULDU');
  }
  
  // Token refresh listener
  static void _onTokenRefresh(String token) async {
    print('🔄 [FCM] Token yenilendi: ${token.substring(0, 30)}...');
    _cachedFcmToken = token;
    
    // Eğer daha önce sunucuya gönderilmişse, yeni token'ı da gönder
    if (_fcmTokenSentToServer) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userIdStr = prefs.getString('admin_user_id') ?? 
                          prefs.getString('customer_id') ?? 
                          prefs.getString('user_id');
        
        if (userIdStr != null) {
          final userId = int.tryParse(userIdStr);
          if (userId != null && userId > 0) {
            await _updateTokenOnServerDirect(token, userId, 'customer');
          }
        }
      } catch (e) {
        print('❌ [FCM] Token refresh sırasında sunucu güncelleme hatası: $e');
      }
    }
  }
  
  // Direkt sunucu güncelleme (token refresh için)
  static Future<void> _updateTokenOnServerDirect(String token, int userId, String userType) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': userType,
          'fcm_token': token,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        print('✅ [FCM] Token refresh - sunucu güncellendi');
      }
    } catch (e) {
      print('❌ [FCM] Token refresh sunucu hatası: $e');
    }
  }
  
  // Topic'lere abone ol
  static Future<void> _subscribeToTopics() async {
    try {
      await _messaging!.subscribeToTopic('customers');
      await _messaging!.subscribeToTopic('all_users');
      print('✅ [FCM] Topic\'lere abone olundu: customers, all_users');
    } catch (e) {
      print('❌ [FCM] Topic abonelik hatası: $e');
    }
  }
  
  // FOREGROUND MESSAGE HANDLER
  static void _onForegroundMessage(RemoteMessage message) async {
    print('📱 === MÜŞTERİ FOREGROUND BİLDİRİM ===');
    print('   📋 Title: ${message.notification?.title}');
    print('   💬 Body: ${message.notification?.body}');
    print('   📊 Data: ${message.data}');
    print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
    
    // iOS'ta foreground notification otomatik gösterilir (setForegroundNotificationPresentationOptions)
    // Android'de manuel göster
    if (Platform.isAndroid) {
      await _showNotification(message);
    }
  }
  
  // MESSAGE OPENED APP HANDLER
  static void _onMessageOpenedApp(RemoteMessage message) {
    print('📱 [MÜŞTERİ] Notification tap: ${message.data}');
    // Navigation işlemleri burada yapılabilir
  }
  
  // NOTIFICATION TAP HANDLER
  static void _onNotificationTapped(NotificationResponse response) {
    print('🔔 [MÜŞTERİ] Local notification tapped: ${response.payload}');
  }
  
  // ANDROID LOCAL NOTIFICATION GÖSTER
  static Future<void> _showNotification(RemoteMessage message) async {
    if (Platform.isIOS) return; // iOS'ta APNs gösterir
    
    final notification = message.notification;
    if (notification == null) return;
    
    final type = message.data['type'] ?? 'default';
    final config = _customerNotifications[type] ?? _customerNotifications['driver_found']!;
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? config.title,
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          '${config.channelId}_v2',
          config.title,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          enableVibration: true,
          enableLights: true,
          ledColor: const Color(0xFFFFD700),
          ledOnMs: 1000,
          ledOffMs: 500,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    
    print('✅ [MÜŞTERİ] Local notification gösterildi: ${notification.title}');
  }
  
  // BACKGROUND NOTIFICATION GÖSTER (main.dart'tan çağrılır)
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    if (Platform.isIOS) return; // iOS'ta APNs gösterir
    
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'FunBreak Vale';
    final body = notification?.body ?? message.data['body'] ?? '';
    
    final type = message.data['type'] ?? 'default';
    final config = _customerNotifications[type] ?? _customerNotifications['driver_found']!;
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          '${config.channelId}_v2',
          config.title,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          fullScreenIntent: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    
    print('✅ [MÜŞTERİ] Background notification gösterildi: $title');
  }
}

// NOTIFICATION CONFIG CLASS
class NotificationConfig {
  final String title;
  final String channelId;
  final String priority;
  final String sound;

  const NotificationConfig({
    required this.title,
    required this.channelId,
    required this.priority,
    required this.sound,
  });
}
