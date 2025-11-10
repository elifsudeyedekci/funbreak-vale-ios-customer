import 'dart:io';  // ⚠️ PLATFORM CHECK İÇİN!
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_options.dart';
import 'services/advanced_notification_service.dart'; // GELİŞMİŞ BİLDİRİM SERVİSİ!
import 'providers/auth_provider.dart';
import 'providers/ride_provider.dart';
import 'providers/pricing_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';
import 'providers/location_pricing_provider.dart';
import 'providers/admin_management_provider.dart';
import 'providers/admin_api_provider.dart';  // KRİTİK IMPORT EKSİK!
import 'providers/waiting_time_provider.dart';
import 'providers/rating_provider.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/sms_login_screen.dart';  // YENİ SMS GİRİŞ
import 'screens/auth/sms_register_screen.dart';  // YENİ SMS KAYIT
import 'screens/auth/sms_verification_screen.dart';  // SMS DOĞRULAMA
import 'services/dynamic_contact_service.dart';
import 'services/session_service.dart';

// GLOBAL NAVIGATOR KEY - BILDIRIM FEEDBACK İÇİN
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// BACKGROUND MESSAGE HANDLER - UYGULAMA KAPALI
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase'i başlat (iOS'te AppDelegate'te zaten yapıldı)
  if (Platform.isAndroid) {
  await Firebase.initializeApp();
  }
  
  print('📱 === MÜŞTERİ BACKGROUND BİLDİRİM ===');
  print('   📋 Title: ${message.notification?.title}');
  print('   💬 Body: ${message.notification?.body}');
  print('   📊 Data: ${message.data}');
  print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
  
  // ⚠️ iOS APNs otomatik gösterir, Android manuel!
  if (Platform.isIOS) {
    print('📱 iOS background notification - APNs tarafından otomatik gösterildi');
    // iOS'te ek işlem gerekmez, APNs notification'ı gösterir
    // Ride started durumunda state güncelleme yapılabilir
    if (message.data['type'] == 'ride_started') {
      print('🚗 === MÜŞTERİ iOS BACKGROUND: YOLCULUK BAŞLATILDI ===');
    }
    return;
  }
  
  // 🔥 ANDROID İÇİN DATA-ONLY notification oluştur!
  RemoteMessage finalMessage = message;
  if (message.notification == null && message.data.isNotEmpty) {
    print('   🔥 DATA-ONLY mesaj - notification oluşturuluyor...');
    final title = message.data['title'] ?? 'FunBreak Vale';
    final body = message.data['body'] ?? 'Yeni bildirim';
    
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
  
  // 🔥 ANDROID BİLDİRİMİ GÖSTER!
  print('🔔 [MÜŞTERİ BACKGROUND] showBackgroundNotification çağrıldı');
  await AdvancedNotificationService.showBackgroundNotification(finalMessage);
  
  // RIDE STARTED - YOLCULUK BAŞLATILDI!
  if (message.data['type'] == 'ride_started') {
    print('🚗 === MÜŞTERİ BACKGROUND: YOLCULUK BAŞLATILDI ===');
    print('   🆔 Ride ID: ${message.data['ride_id']}');
    print('   💬 Mesaj: ${message.data['message']}');
    print('📲 MÜŞTERİ: Bildirim alındı - uygulama açıldığında status güncellenecek!');
  }
  
  print('✅ MÜŞTERİ Background handler tamamlandı');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ⚠️ Firebase initialization - Flutter plugin tüm platformlarda!
  try {
    if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
      print('✅ MÜŞTERİ Firebase başlatıldı (${Platform.isAndroid ? "Android" : "iOS"})');
    } else {
      print('⚠️ MÜŞTERİ Firebase zaten başlatılmış');
    }
  } catch (e) {
    print('⚠️ MÜŞTERİ Firebase init hatası (duplicate normal): $e');
  }
  
  // BACKGROUND MESSAGE HANDLER KAYDET - Firebase başlatıldıktan sonra!
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('✅ Background handler kayıtlı');
  } catch (e) {
    print('❌ Background handler hatası: $e');
  }
  
  // GELİŞMİŞ BİLDİRİM SERVİSİ BAŞLAT - MUTLAKA TAMAMLANSIN!
  print('🔥 [MÜŞTERİ] AdvancedNotificationService başlatılıyor...');
  try {
    await AdvancedNotificationService.initialize();
    print('✅ [MÜŞTERİ] Gelişmiş bildirim sistemi başlatıldı');
  } catch (e, stack) {
    print('❌ [MÜŞTERİ] AdvancedNotificationService HATASI: $e');
    print('📋 Stack: $stack');
  }

  // Session servisini başlat - TIMEOUT İLE HIZLI!
  await SessionService.initializeSession().timeout(
    const Duration(seconds: 2),
    onTimeout: () {
      print('⚡ Session servisi timeout - default session kullanılıyor');
    },
  );
  
  // FCM TOKEN KAYDETME - UYGULAMA AÇILDIĞINDA OTOMATIK!
  try {
    await _initializeFirebaseMessaging().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print('⚡ FCM setup timeout - arka planda devam edecek');
      },
    );
    print('✅ FCM token kaydetme tamamlandı');
  } catch (e) {
    print('⚠️ FCM setup hatası (devam ediliyor): $e');
  }
  
  runApp(const MyApp());
}

Future<void> _initializeFirebaseMessaging() async {
  // ✅ SADECE FCM TOKEN KAYDET - BİLDİRİMLER AdvancedNotificationService TARAFINDAN YÖNETİLİYOR!
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  
  try {
    // ⚠️ iOS'TA ÖNCE PERMİSSİON AL!
    if (Platform.isIOS) {
      print('📱 iOS FCM Token alınmadan önce permission isteniyor...');
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      print('✅ iOS FCM Permission: ${settings.authorizationStatus}');
      print('   Alert: ${settings.alert}');
      print('   Badge: ${settings.badge}');
      print('   Sound: ${settings.sound}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        print('⚠️ iOS bildirim izni verilmedi - Token alınamaz!');
        print('💡 Settings → Notifications → FunBreak Vale → Allow Notifications açık olmalı!');
        return;
      }
    }
    
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? prefs.getString('admin_user_id');
    
    if (userId != null && userId.isNotEmpty) {
      // iOS'ta token alma 10 saniye sürebilir
      final fcmToken = await messaging.getToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⏱️ iOS FCM Token timeout - tekrar denenecek');
          return null;
        },
      );
      
      if (fcmToken != null && fcmToken.isNotEmpty) {
        print('📱 [MÜŞTERİ] FCM Token alındı: ${fcmToken.substring(0, 20)}...');
        await _saveCustomerFCMToken(fcmToken);
      } else {
        print('⚠️ FCM Token boş geldi - APNs izni kontrol et');
      }
    } else {
      print('⚠️ [MÜŞTERİ] User ID yok - FCM token kaydedilmedi (login sonrası yapılacak)');
    }
  } catch (e) {
    print('⚠️ [MÜŞTERİ] FCM token kaydetme hatası: $e');
  }
  
  print('✅ FCM token setup tamamlandı - Bildirimler AdvancedNotificationService tarafından yönetiliyor');
}

// MÜŞTERİ FCM TOKEN KAYDETME - ŞOFÖR GİBİ ÇALIŞIYOR!
Future<void> _saveCustomerFCMToken(String fcmToken) async {
  try {
    print('💾 MÜŞTERİ FCM Token database\'e kaydediliyor...');

    final prefs = await SharedPreferences.getInstance();
    
    // Customer ID'yi farklı formatlardan al - admin_user_id SADECE STRING!
    int? customerId;
    
    // 1. İlk önce STRING olarak dene (admin_user_id STRING olarak kayıtlı!)
    final customerIdStr = prefs.getString('admin_user_id') ??  // ← ASIL KEY (STRING!)
                          prefs.getString('customer_id') ?? 
                          prefs.getString('user_id');
    
    if (customerIdStr != null && customerIdStr.isNotEmpty) {
      customerId = int.tryParse(customerIdStr);
    }
    
    // 2. Bulunamadıysa INT olarak dene (sadece customer_id ve user_id)
    if (customerId == null) {
      customerId = prefs.getInt('customer_id') ?? prefs.getInt('user_id');
    }
    
    print('🔍 MÜŞTERİ FCM: Session keys: ${prefs.getKeys()}');
    print('🔍 MÜŞTERİ FCM: admin_user_id: ${prefs.get('admin_user_id')}');
    print('🔍 MÜŞTERİ FCM: customer_id: ${prefs.get('customer_id')}');
    print('🔍 MÜŞTERİ FCM: Final userId: $customerId');

    if (customerId == null || customerId <= 0) {
      print('❌ MÜŞTERİ FCM: Customer ID bulunamadı - FCM token kaydedilemedi');
      print('⚠️ MÜŞTERİ FCM: Lütfen önce giriş yapın!');
      return;
    }

    print('💾 MÜŞTERİ FCM: Token backend\'e kaydediliyor - Customer ID: $customerId');
    print('📱 Token: ${fcmToken.substring(0, 20)}...');

    final response = await http.post(
      Uri.parse('https://admin.funbreakvale.com/api/update_fcm_token.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': customerId,
        'user_type': 'customer',
        'fcm_token': fcmToken,
      }),
    ).timeout(const Duration(seconds: 10));

    print('📡 MÜŞTERİ FCM Token API Response: ${response.statusCode}');
    print('📋 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('📊 API Success: ${data['success']}');
      print('💬 Message: ${data['message']}');

      if (data['success'] == true) {
        print('✅ MÜŞTERİ FCM Token database\'e başarıyla kaydedildi!');
        print('🔔 Artık bildirimler gelecek!');
      } else {
        print('❌ MÜŞTERİ FCM Token kaydetme hatası: ${data['message']}');
      }
    } else {
      print('❌ MÜŞTERİ FCM Token kaydetme HTTP hatası: ${response.statusCode}');
    }
  } catch (e, stackTrace) {
    print('❌ MÜŞTERİ FCM Token kaydetme hatası: $e');
    print('📚 Stack trace: $stackTrace');
  }
}

// ⚠️ PLATFORM-SPECIFIC İZİN SİSTEMİ
Future<void> requestPermissions() async {
  try {
    if (Platform.isIOS) {
      // iOS için özel izin sistemi
      print('📱 iOS izinleri isteniyor...');
      
      // Bildirim izni (iOS için Firebase üzerinden)
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ iOS bildirim izni verildi');
      } else {
        print('⚠️ iOS bildirim izni reddedildi');
      }
    
    // Konum izni
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
      
    } else if (Platform.isAndroid) {
      // Android için mevcut sistem
      await Permission.notification.request();
    await Permission.location.request();
    }
    
    print('✅ İzinler istendi (${Platform.operatingSystem})');
  } catch (e) {
    print('❌ İzin hatası: $e');
  }
}


class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(create: (_) => PricingProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => LocationPricingProvider()),
        ChangeNotifierProvider(create: (_) => AdminManagementProvider()),
        ChangeNotifierProvider(create: (_) => AdminApiProvider()),  // KRİTİK EKSİK!
        ChangeNotifierProvider(create: (_) => WaitingTimeProvider()),
        ChangeNotifierProvider(create: (_) => RatingProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey, // GLOBAL FEEDBACK İÇİN!
            title: 'FunBreak Vale',
            debugShowCheckedModeBanner: false,
            
            // 🇹🇷 TÜRKÇE KLAVYE VE KARAKTER DESTEĞİ
            locale: languageProvider.currentLocale ?? const Locale('tr', 'TR'),
            supportedLocales: const [
              Locale('tr', 'TR'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            
            theme: ThemeData(
              useMaterial3: true,
              primarySwatch: Colors.amber,
              primaryColor: const Color(0xFFFFD700),
              scaffoldBackgroundColor: const Color(0xFFF5F5F5),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFFFFD700),
                elevation: 0,
                titleTextStyle: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                backgroundColor: Colors.white,
                selectedItemColor: Color(0xFFFFD700),
                unselectedItemColor: Colors.grey,
                type: BottomNavigationBarType.fixed,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              cardTheme: CardThemeData(
                color: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFFD700)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
              ),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFFFD700),
                brightness: Brightness.light,
              ).copyWith(
                primary: const Color(0xFFFFD700),
                secondary: const Color(0xFFFFD700),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              primarySwatch: Colors.amber,
              primaryColor: const Color(0xFFFFD700),
              scaffoldBackgroundColor: Colors.black,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.black,
                foregroundColor: Color(0xFFFFD700),
                elevation: 0,
                titleTextStyle: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                backgroundColor: Colors.black,
                selectedItemColor: Color(0xFFFFD700),
                unselectedItemColor: Colors.grey,
                type: BottomNavigationBarType.fixed,
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              cardTheme: CardThemeData(
                color: Colors.grey[900],
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFFFD700),
                brightness: Brightness.dark,
              ).copyWith(
                primary: const Color(0xFFFFD700),
                secondary: const Color(0xFFFFD700),
              ),
            ),
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const SplashScreen(), // NORMAL SPLASH - PERSİSTENCE KONTROL EKLE!
            routes: {
              '/login': (context) => const SmsLoginScreen(),  // YENİ SMS GİRİŞ
              '/login_old': (context) => const LoginScreen(),  // ESKİ GİRİŞ (Yedek)
              '/register': (context) => const SmsRegisterScreen(),  // YENİ SMS KAYIT
              '/register_old': (context) => const RegisterScreen(),  // ESKİ KAYIT (Yedek)
              '/home': (context) => const MainScreen(),
            },
          );
        },
      ),
    );
  }
  
  // BİLDİRİM ÖNEMİ DIALOG'U
  Future<void> _showNotificationImportanceDialog(int attempt) async {
    print('📱 MÜŞTERİ: Bildirim önemi dialog gösteriliyor - Deneme #$attempt');
    await Future.delayed(Duration(milliseconds: 1000));
  }

  // İZİN DIALOG'U
  Future<void> _showPermissionDialog() async {
    print('⚙️ MÜŞTERİ: İzin ayarları dialog gösteriliyor');
    await openAppSettings();
  }
  
  // PERSİSTENCE KONTROL SPLASH SCREEN'DE YAPILACAK!
}