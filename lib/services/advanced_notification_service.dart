import 'dart:io';  // ⚠️ PLATFORM CHECK!
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data'; // 🔥 Int64List için!
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// GELİŞMİŞ BİLDİRİM SERVİSİ - MÜŞTERİ UYGULAMASI!
class AdvancedNotificationService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static FirebaseMessaging? _messaging;
  static bool _initialized = false; // 🔥 Sadece 1 kez initialize
  static StreamSubscription<RemoteMessage>? _foregroundSubscription; // 🔥 Listener kontrolü
  
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
    // new_campaign kaldırıldı - zaten mevcut kampanya sistemi çalışıyor!
  };
  
  // SERVİS BAŞLATMA - PLATFORM-SPECIFIC!
  static Future<void> initialize() async {
    // 🔥 ZATEN BAŞLATILDIYSA ATLA!
    if (_initialized) {
      print('⏭️ Bildirim servisi zaten başlatıldı - atlanıyor');
      return;
    }
    
    try {
      print('🔔 Gelişmiş bildirim servisi başlatılıyor... (${Platform.operatingSystem})');
      
      // ⚠️ PLATFORM-SPECIFIC INITIALIZATION
      if (Platform.isIOS) {
        // iOS initialization (iOS 10+)
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        
        await _localNotifications.initialize(
          const InitializationSettings(iOS: iosSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        print('✅ iOS bildirim sistemi başlatıldı');
        
      } else {
        // Android initialization
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _localNotifications.initialize(
          const InitializationSettings(android: androidSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        
        // Android notification channels oluştur
        await _createNotificationChannels();
        print('✅ Android bildirim sistemi başlatıldı');
      }
      
      // Firebase Messaging setup (HER İKİ PLATFORM)
      _messaging = FirebaseMessaging.instance;
      
      // Permission iste
      await _requestPermissions();
      
      // Background handler main.dart'ta kayıtlı
      
      // 🔥 ESKİ LISTENER'I İPTAL ET!
      await _foregroundSubscription?.cancel();
      
      // Foreground message handler - SADECE BİR KERE!
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      print('✅ Foreground listener kayıtlı - ID: ${_foregroundSubscription.hashCode}');
      
      // App açılışında notification handler
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      
      // Token güncelleme
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      
      // Topic'lere subscribe
      await _subscribeToTopics();
      
      _initialized = true; // 🔥 BAŞARILDI OLARAK İŞARETLE!
      print('✅ Gelişmiş bildirim servisi hazır!');
      
    } catch (e) {
      print('❌ Bildirim servisi başlatma hatası: $e');
    }
  }
  
  // ANDROID BİLDİRİM KANALLARI - HEADS-UP İÇİN DÜZELTME!
  static Future<void> _createNotificationChannels() async {
    // ⚠️ iOS'te channel sistemi yok, sadece Android!
    if (Platform.isIOS) {
      print('⏭️ iOS - Channel sistemi yok, atlanıyor');
      return;
    }
    
    print('🔔 [MÜŞTERİ] ANDROID CHANNEL OLUŞTURMA BAŞLADI!');
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) {
      print('❌ [MÜŞTERİ] AndroidFlutterLocalNotificationsPlugin NULL!');
      return;
    }
    
    print('🗑️ [MÜŞTERİ] Eski channellar siliniyor...');
    // Önce eski kanalları sil
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
        'location_updates_v3',  // 🔥 V3 - SES CACHE FIX!
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
    
    print('✅ [MÜŞTERİ] ${channels.length} bildirim kanalı OLUŞTURULDU (IMPORTANCE MAX!)');
  }
  
  // İZİN İSTEME VE TOKEN ALMA - iOS KRİTİK!
  static Future<void> _requestPermissions() async {
    try {
      // ✅ ÖNCE İZİN İSTE (iOS için zorunlu)
      final settings = await _messaging!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      print('🔔 Bildirim izni durumu: ${settings.authorizationStatus}');
      
      // iOS için authorizationStatus kontrol
      if (Platform.isIOS) {
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          print('❌ iOS bildirim izni verilmedi: ${settings.authorizationStatus}');
          return;
        }
      }
      
      // ✅ TOKEN AL (10 saniye timeout ile!)
      try {
        final token = await _messaging!.getToken().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ FCM token alma timeout!');
            return null;
          },
        );
        
        if (token != null) {
          print('✅ FCM Token alındı: ${token.substring(0, 30)}...');
          await _updateTokenOnServer(token);
        } else {
          print('⚠️ FCM token null döndü');
        }
      } catch (e) {
        print('❌ FCM token alma hatası: $e');
      }
      
    } catch (e) {
      print('❌ İzin isteme hatası: $e');
    }
  }
  
  // TOPIC SUBSCRIBE
  static Future<void> _subscribeToTopics() async {
    try {
      await _messaging!.subscribeToTopic('funbreak_customers');
      print('✅ Müşteri topic\'ine subscribe oldu');
    } catch (e) {
      print('❌ Topic subscribe hatası: $e');
    }
  }
  
  // BACKGROUND MESSAGE HANDLER
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('🔔 Background mesaj alındı: ${message.messageId}');
    await _showLocalNotification(message);
  }
  
  // PUBLIC BACKGROUND NOTIFICATION - main.dart'tan çağrılabilir!
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    print('🔔 [MÜŞTERİ BACKGROUND] showBackgroundNotification çağrıldı');
    await _showLocalNotification(message);
  }
  
  // FOREGROUND MESSAGE HANDLER
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    print('🔔 [MÜŞTERİ FOREGROUND] Mesaj alındı: ${message.messageId}');
    print('   📊 Data: ${message.data}');
    print('   📋 Notification: ${message.notification?.title ?? "YOK"}');
    
    // 🔥 DATA-ONLY mesajlar için notification oluştur!
    RemoteMessage finalMessage = message;
    if (message.notification == null && message.data.isNotEmpty) {
      print('   🔥 DATA-ONLY mesaj - notification oluşturuluyor...');
      final title = message.data['title'] ?? 'FunBreak Vale';
      final body = message.data['body'] ?? 'Yeni bildirim';
      
      // Fake notification ekle
      finalMessage = RemoteMessage(
        senderId: message.senderId,
        category: message.category,
        collapseKey: message.collapseKey,
        contentAvailable: message.contentAvailable,
        data: message.data,
        from: message.from,
        messageId: message.messageId,
        messageType: message.messageType,
        mutableContent: message.mutableContent,
        notification: RemoteNotification(title: title, body: body),
        sentTime: message.sentTime,
        threadId: message.threadId,
        ttl: message.ttl,
      );
      print('   ✅ Notification eklendi: $title');
    }
    
    await _showLocalNotification(finalMessage);
  }
  
  // NOTIFICATION TAP HANDLER
  static Future<void> _onNotificationTapped(NotificationResponse response) async {
    print('🔔 Bildirime tıklandı: ${response.payload}');
    
    // Payload'a göre sayfa yönlendirme yapılabilir
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      await _handleNotificationAction(data);
    }
  }
  
  // MESSAGE OPENED APP HANDLER
  static Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    print('🔔 Mesajdan uygulama açıldı: ${message.messageId}');
    await _handleNotificationAction(message.data);
  }
  
  // TOKEN REFRESH HANDLER
  static Future<void> _onTokenRefresh(String token) async {
    print('🔔 FCM Token yenilendi: ${token.substring(0, 20)}...');
    // Backend'e token güncelleme gönder
    await _updateTokenOnServer(token);
  }
  
  // LOCAL BİLDİRİM GÖSTER (PLATFORM-AWARE!)
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    
    if (notification == null) {
      print('⚠️ Notification null - data-only mesaj');
      return;
    }
    
    print('✅ [MÜŞTERİ] Local notification gösteriliyor');
    
    // 🔥 PLATFORM-SPECIFIC NOTIFICATION
    if (Platform.isIOS) {
      // iOS - DETAYLI GÖSTER!
      try {
        final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
        print('📱 iOS bildirim gösteriliyor - ID: $notificationId');
        print('   Title: ${notification.title}');
        print('   Body: ${notification.body}');
        
        await _localNotifications.show(
          notificationId,
          notification.title ?? 'FunBreak Vale',
          notification.body ?? '',
          NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: true,  // iOS 13 ve altı için
              presentBanner: true, // iOS 14+ için - EKRAN ÜSTÜNDE BANNER!
              presentList: true,   // Notification Center'da göster
              presentBadge: true,
              presentSound: true,
              sound: 'notification.caf',
              badgeNumber: 1,
              subtitle: message.data['type'] ?? '',
              threadIdentifier: 'funbreak_vale',
            ),
          ),
          payload: jsonEncode(message.data),
        );
        print('✅ iOS notification show() çağrıldı - Banner + List + Sound + Badge');
      } catch (e) {
        print('❌ iOS notification error: $e');
        print('❌ Stack: ${e.toString()}');
      }
      return;
    }
    
    // ANDROID - CHANNEL SİSTEMİ
    final notificationType = message.data['type'] ?? message.data['notification_type'] ?? '';
    String channelId;
    String channelName;
    String channelDesc;
      
      if (notificationType == 'driver_found') {
        channelId = 'ride_updates_v2'; // ✅ YENİ CHANNEL!
        channelName = 'Yolculuk Güncellemeleri';
        channelDesc = 'Vale bulundu bildirimleri';
      } else if (notificationType == 'ride_started') {
        channelId = 'location_updates_v3'; // 🔥 V3 - SES FIX!
        channelName = 'Konum Güncellemeleri';
        channelDesc = 'Yolculuk başlatma bildirimleri';
      } else if (notificationType == 'ride_completed') {
        channelId = 'payment_updates_v2'; // ✅ YENİ CHANNEL!
        channelName = 'Ödeme Bildirimleri';
        channelDesc = 'Yolculuk tamamlanma bildirimleri';
      } else {
        channelId = 'funbreak_rides_v2'; // Diğerleri
        channelName = 'Yolculuk Bildirimleri';
        channelDesc = 'Genel yolculuk bildirimleri';
      }
      
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      
      // 🔥 UNIQUE ID - Milisaniye + microseconds + hash
      final timestamp = DateTime.now();
      final uniqueId = (timestamp.millisecondsSinceEpoch + timestamp.microsecond).hashCode.abs() % 2147483647;
      
      // 🔥 HER BİLDİRİM İÇİN FARKLI TİTREŞİM!
      final vibrationPattern = Int64List.fromList([0, 250 + (uniqueId % 200), 250, 250]);
      
      // 🔥 BigTextStyle ile dikkat çekici bildirim
      // ⚠️ PLATFORM-SPECIFIC NOTIFICATION DETAILS
      NotificationDetails details;
      
      if (Platform.isIOS) {
        // iOS için DarwinNotificationDetails
        details = NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,  // iOS 13 ve altı
            presentBanner: true, // ✅ iOS 14+ EKRAN BANNER!
            presentList: true,   // ✅ Notification Center'da göster
            presentBadge: true,
            presentSound: true,
            sound: 'notification.caf',  // ⚠️ iOS .caf formatı!
            badgeNumber: 1,
            threadIdentifier: 'funbreak_vale',
            subtitle: 'FunBreak Vale',
            interruptionLevel: InterruptionLevel.timeSensitive, // iOS 15+ öncelikli bildirim
          ),
        );
        
      } else {
        // Android için AndroidNotificationDetails (MEVCUT SISTEM)
        final BigTextStyleInformation bigTextStyle = BigTextStyleInformation(
          notification.body ?? '',
          contentTitle: notification.title,
          htmlFormatContentTitle: true,
          htmlFormatBigText: true,
        );
        
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
            showWhen: true,
            when: currentTime,
            ticker: '${notification.title} - $uniqueId', // 🔥 Her bildirim FARKLI ticker
            autoCancel: true, 
            onlyAlertOnce: false, // 🔥 Her seferinde uyar
            enableLights: true,
            ledColor: const Color(0xFFFFD700),
            ledOnMs: 1000,
            ledOffMs: 500,
            category: AndroidNotificationCategory.call, // 🔥 Heads-up için
            groupKey: 'funbreak_$uniqueId', // 🔥 Her bildirim KENDİ GRUBU!
            setAsGroupSummary: false,
            styleInformation: bigTextStyle,
            tag: 'notification_$uniqueId', // 🔥 Her bildirim unique tag!
            channelShowBadge: true,
            vibrationPattern: vibrationPattern, // 🔥 HER BİLDİRİM FARKLI TİTREŞİR!
            timeoutAfter: null, // 🔥 Timeout yok
          ),
        );
      }
      
      // 🔥 UNIQUE ID İLE HER BİLDİRİM AYRI!
      await _localNotifications.show(
        uniqueId,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(message.data),
      );
      
      print('🔔 BİLDİRİM GÖSTERİLDİ:');
      print('   ID: $uniqueId (UNIQUE - timestamp)');
      print('   Kanal: $channelId');
      print('   Başlık: ${notification.title}');
      print('   Type: $notificationType');
      print('   Ses: ✅ Titreşim: ✅ LED: ✅ Importance: MAX');
  }
  
  // BİLDİRİM AKSİYON HANDLER
  static Future<void> _handleNotificationAction(Map<String, dynamic> data) async {
    final type = data['notification_type'] ?? '';
    
    print('🔔 Bildirim aksiyonu: $type');
    
    // Bildirim türüne göre sayfa yönlendirme
    switch (type) {
      case 'driver_found':
      case 'driver_approaching':
      case 'driver_arrived':
        // Ana sayfaya git (harita göster)
        break;
      case 'ride_completed':
        // Geçmiş yolculuklara git  
        break;
      case 'payment_processed':
        // Ödeme geçmişine git
        break;
        // new_campaign kaldırıldı
    }
  }
  
  // SUNUCUYA TOKEN GÜNCELLE
  static Future<void> _updateTokenOnServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '0';
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'customer',
          'fcm_token': token,
        }),
      );
      
      if (response.statusCode == 200) {
        print('✅ FCM Token sunucuya güncellendi');
      }
    } catch (e) {
      print('❌ Token güncelleme hatası: $e');
    }
  }
  
  // MANUEl BİLDİRİM GÖNDER
  static Future<bool> sendNotification({
    required String notificationType,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '0';
      
      final config = _customerNotifications[notificationType];
      if (config == null) {
        print('❌ Bilinmeyen bildirim türü: $notificationType');
        return false;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/send_advanced_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'customer',
          'notification_type': notificationType,
          'title': config.title,
          'message': _formatMessage(config.title, data),
          'data': data,
        }),
      );
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      
      return false;
    } catch (e) {
      print('❌ Manuel bildirim gönderim hatası: $e');
      return false;
    }
  }
  
  // MESAJ FORMATLAMA
  static String _formatMessage(String template, Map<String, dynamic> data) {
    String message = template;
    
    // Template'deki değişkenleri data ile değiştir
    data.forEach((key, value) {
      message = message.replaceAll('{$key}', value.toString());
    });
    
    return message;
  }
  
  // BİLDİRİM GEÇMİŞİ ÇEK
  static Future<List<Map<String, dynamic>>> getNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '0';
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_notification_history.php?user_id=$userId&user_type=customer'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['notifications'] ?? []);
        }
      }
      
      return [];
    } catch (e) {
      print('❌ Bildirim geçmişi çekme hatası: $e');
      return [];
    }
  }
}

// BİLDİRİM KONFİGÜRASYON SINIFI
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
