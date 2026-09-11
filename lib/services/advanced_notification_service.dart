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
  
  // 🔥 GPT FIX: Hard Guard + Cooldown!
  static bool _inProgress = false;
  static DateTime? _lastAttemptAt;
  static bool _fcmTokenSentToServer = false;
  
  // 🔄 OTOMATİK RETRY: Başarısız olunca 2dk sonra tekrar dene
  static Timer? _retryTimer;
  static int? _pendingUserId;
  static String? _pendingUserType;
  
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
    'new_message': NotificationConfig(
      title: '💬 Yeni Mesaj',
      channelId: 'funbreak_messages',
      priority: 'high',
      sound: 'notification.wav',
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

      // Uygulama tamamen kapalıyken bildirime tıklanıp açıldıysa
      // (onMessageOpenedApp bu durumda TETİKLENMEZ, ayrıca kontrol etmek gerekir)
      _messaging!.getInitialMessage().then((message) {
        if (message != null) {
          print('🔔 Uygulama bildirimle (kapalıyken) açıldı: ${message.messageId}');
          _reportNotificationOpenedFromData(message.data);
        }
      });

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
  
  // 🔥 GPT FIX: HARD GUARD + COOLDOWN - TEK ÇAĞRI GARANTİSİ!
  static Future<bool> registerFcmToken(int userId, {String userType = 'customer'}) async {
    // 1️⃣ HARD GUARD: Aynı anda ikinci girişimi kes
    if (_inProgress) {
      print('⛔️ [FCM] Guard: inProgress, SKIP');
      return false;
    }
    
    // 2️⃣ COOLDOWN: 2 dakika içinde tekrar deneme (rate-limit önleme)
    final now = DateTime.now();
    if (_lastAttemptAt != null && now.difference(_lastAttemptAt!).inSeconds < 120) {
      print('⛔️ [FCM] Guard: cooldown (${120 - now.difference(_lastAttemptAt!).inSeconds}sn kaldı), SKIP');
      return false;
    }
    
    // 3️⃣ Zaten backend'e gönderildiyse tekrar gönderme
    if (_fcmTokenSentToServer && _cachedFcmToken != null) {
      print('✅ [FCM] Token zaten backend\'e gönderildi - atlanıyor');
      return true;
    }
    
    // 🔐 KİLİTLE!
    _inProgress = true;
    _lastAttemptAt = now;
    
    print('🔔 [FCM] registerFcmToken BAŞLADI - User: $userId, Type: $userType');
    
    try {
      // Önce cache'e bak (SharedPreferences) - iOS/Android ayrı
      try {
        final prefs = await SharedPreferences.getInstance();
        
        if (Platform.isIOS) {
          // iOS: APNs token cache'i kontrol et
          final cachedApnsToken = prefs.getString('apns_token_cached');
          if (cachedApnsToken != null && cachedApnsToken.isNotEmpty) {
            print('✅ [APNs] Cache\'den token bulundu - backend\'e gönderiliyor');
            final success = await _sendApnsTokenToBackend(cachedApnsToken, userId, userType);
            return success;
          }
        } else {
          // Android: FCM token cache'i kontrol et
          final cachedToken = prefs.getString('fcm_token_cached');
          if (cachedToken != null && cachedToken.isNotEmpty) {
            print('✅ [FCM] Cache\'den token bulundu - backend\'e gönderiliyor');
            final success = await _sendTokenToBackend(cachedToken, userId, userType);
            return success;
          }
        }
      } catch (e) {
        print('⚠️ Cache okuma hatası: $e');
      }
      
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
      
      // 🍎 iOS: DOĞRUDAN APNs TOKEN KULLAN (Firebase bypass!)
      if (Platform.isIOS) {
        print('🍎 [APNs] iOS - APNs token alınıyor (Firebase bypass)...');
        String? apnsToken;
        
        for (int i = 0; i < 10; i++) {
          apnsToken = await _messaging!.getAPNSToken();
          if (apnsToken != null) {
            print('✅ [APNs] Token alındı (${i+1}. deneme)');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        if (apnsToken != null && apnsToken.isNotEmpty) {
          print('🍎 [APNs] Token: ${apnsToken.substring(0, 20)}...');
          _cachedFcmToken = apnsToken; // APNs token'ı cache'e kaydet
          
          // APNs token'ı cache'e kaydet
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('apns_token_cached', apnsToken);
            print('💾 [APNs] Token cache\'e kaydedildi');
          } catch (e) {
            print('⚠️ [APNs] Cache kaydetme hatası: $e');
          }
          
          // Backend'e APNs token gönder
          final success = await _sendApnsTokenToBackend(apnsToken, userId, userType);
          return success;
        } else {
          print('❌ [APNs] Token alınamadı - 2 dakika sonra tekrar denenecek');
          _scheduleRetry(userId, userType);
          return false;
        }
      }
      
      // 🤖 Android: FCM token kullan
      print('🤖 [FCM] Android - FCM token alınıyor...');
      String? token;
      
      try {
        token = await _messaging!.getToken().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print('⏱️ [FCM] Token alma timeout (15sn)');
            return null;
          },
        );
        
        if (token != null && token.isNotEmpty) {
          print('✅ [FCM] Token alındı!');
        }
      } catch (tokenError) {
        print('⚠️ [FCM] Token alma başarısız: $tokenError');
      }
      
      // Token alınamadıysa - 2 DAKİKA SONRA OTOMATİK TEKRAR DENE!
      if (token == null || token.isEmpty) {
        print('❌ [FCM] Token alınamadı - 2 dakika sonra OTOMATİK tekrar denenecek');
        _scheduleRetry(userId, userType);
        return false;
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
      
      // Backend'e gönder (Android - FCM)
      final success = await _sendTokenToBackend(token, userId, userType);
      return success;
      
    } catch (e) {
      print('❌ [FCM] registerFcmToken hatası: $e');
      return false;
    } finally {
      // 🔓 KİLİDİ AÇ!
      _inProgress = false;
    }
  }
  
  // 🔥 Backend'e token gönderme helper fonksiyonu (Android FCM)
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
          'device_type': 'android',
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
  
  // 🍎 APNs token'ı backend'e gönder (iOS için)
  static Future<bool> _sendApnsTokenToBackend(String apnsToken, int userId, String userType) async {
    try {
      print('📡 [APNs] Token backend\'e gönderiliyor...');
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': userType,
          'apns_token': apnsToken,
          'device_type': 'ios',
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ [APNs] Token backend\'e kaydedildi!');
          _fcmTokenSentToServer = true;
          _cachedFcmToken = apnsToken;
          
          // Topic'lere subscribe (APNs için de gerekli olabilir)
          await _subscribeToTopics();
          
          return true;
        } else {
          print('❌ [APNs] Backend hatası: ${data['message']}');
        }
      } else {
        print('❌ [APNs] HTTP hatası: ${response.statusCode}');
      }
      return false;
    } catch (e) {
      print('❌ [APNs] Backend gönderme hatası: $e');
      return false;
    }
  }
  
  // 🔥 Cache'li token'ı al (varsa)
  static String? getCachedToken() => _cachedFcmToken;
  
  // 🔥 Token durumunu sıfırla (logout için)
  static void resetTokenState() {
    _cachedFcmToken = null;
    _inProgress = false;
    _lastAttemptAt = null;
    _fcmTokenSentToServer = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingUserId = null;
    _pendingUserType = null;
    print('🔄 [FCM] Token durumu sıfırlandı');
  }
  
  // 🔄 OTOMATİK RETRY: 2 dakika sonra tekrar dene
  static void _scheduleRetry(int userId, String userType) {
    // Önceki timer'ı iptal et
    _retryTimer?.cancel();
    
    // Bilgileri sakla
    _pendingUserId = userId;
    _pendingUserType = userType;
    
    // 2 dakika sonra tekrar dene
    print('⏰ [FCM] 2 dakika sonra otomatik retry planlandı...');
    _retryTimer = Timer(const Duration(minutes: 2), () async {
      print('🔄 [FCM] OTOMATİK RETRY başlıyor...');
      
      // Cooldown'ı sıfırla (retry için)
      _lastAttemptAt = null;
      
      // Tekrar dene
      if (_pendingUserId != null && _pendingUserType != null) {
        final success = await registerFcmToken(_pendingUserId!, userType: _pendingUserType!);
        if (success) {
          print('✅ [FCM] OTOMATİK RETRY başarılı!');
          _pendingUserId = null;
          _pendingUserType = null;
        } else {
          print('❌ [FCM] OTOMATİK RETRY başarısız - tekrar planlanıyor...');
          // Başarısız olursa tekrar 2dk sonra dene (registerFcmToken zaten _scheduleRetry çağırır)
        }
      }
    });
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
      AndroidNotificationChannel(
        'funbreak_messages_v2',
        'Mesaj Bildirimleri',
        description: 'Şoförden gelen sohbet mesajı bildirimleri',
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
          'device_type': 'android',
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
    _reportNotificationOpenedFromData(message.data);
  }

  // NOTIFICATION TAP HANDLER
  static void _onNotificationTapped(NotificationResponse response) {
    print('🔔 [MÜŞTERİ] Local notification tapped: ${response.payload}');
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _reportNotificationOpenedFromData(data);
      } catch (e) {
        print('⚠️ Notification payload parse hatası: $e');
      }
    }
  }

  // ADMİN PANELE "BİLDİRİM AÇILDI" BİLGİSİNİ GÖNDER
  static void _reportNotificationOpenedFromData(Map<String, dynamic> data) {
    final notificationId = data['notification_id'];
    if (notificationId == null) return;

    unawaited(() async {
      try {
        await http.post(
          Uri.parse('$baseUrl/mark_notification_opened.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'notification_id': notificationId.toString()}),
        ).timeout(const Duration(seconds: 10));
        print('📊 Bildirim açılma bilgisi gönderildi: $notificationId');
      } catch (e) {
        print('⚠️ Bildirim açılma bilgisi gönderilemedi: $e');
      }
    }());
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
