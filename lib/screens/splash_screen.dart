import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../providers/auth_provider.dart';
import '../services/dynamic_contact_service.dart';
import 'main_screen.dart';
import 'auth/sms_login_screen.dart';
import 'legal/contract_update_screen.dart';  // SÖZLEŞME GÜNCELLEME EKRANI
import '../main.dart' show navigatorKey; // MAIN.DART'DAN IMPORT

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // ⚠️ İzinler ve Servisler main.dart'ta başlatılıyor!
    // Burada sadece auth kontrolü yapıyoruz.
    // await _requestPermissionsAndInitializeServices(); // 🔥 KALDIRILDI
    
    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = await authProvider.checkAuthStatus();
    
    if (!mounted) return;
    
    if (isLoggedIn) {
      // ✅ SÖZLEŞME GÜNCELLEME KONTROLÜ
      final contractCheck = await _checkContractUpdates();
      
      if (!mounted) return;
      
      if (contractCheck['needs_update'] == true) {
        // Sözleşme güncelleme ekranına yönlendir
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ContractUpdateScreen(
              customerId: contractCheck['customer_id'] as int,
              pendingContracts: List<Map<String, dynamic>>.from(contractCheck['pending_contracts']),
              onAllAccepted: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const MainScreen()),
                );
              },
            ),
          ),
        );
      } else {
        // Normal akışa devam
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const SmsLoginScreen()),
      );
    }
  }
  
  /// SÖZLEŞME GÜNCELLEME KONTROLÜ
  /// Backend'den güncel sözleşme versiyonlarını kontrol eder
  Future<Map<String, dynamic>> _checkContractUpdates() async {
    try {
      print('📜 SÖZLEŞME GÜNCELLEME KONTROLÜ YAPILIYOR...');
      
      final prefs = await SharedPreferences.getInstance();
      final customerIdStr = prefs.getString('admin_user_id') ?? 
                            prefs.getString('customer_id') ?? 
                            prefs.getString('user_id');
      
      if (customerIdStr == null || customerIdStr.isEmpty) {
        print('⚠️ Customer ID bulunamadı - sözleşme kontrolü atlanıyor');
        return {'needs_update': false};
      }
      
      final customerId = int.tryParse(customerIdStr) ?? 0;
      if (customerId <= 0) {
        print('⚠️ Geçersiz Customer ID - sözleşme kontrolü atlanıyor');
        return {'needs_update': false};
      }
      
      print('🔍 Customer ID: $customerId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/check_contract_updates.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': customerId,
          'user_type': 'customer',
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final needsUpdate = data['needs_update'] == true;
          final pendingContracts = data['pending_contracts'] ?? [];
          
          print('📜 Sözleşme kontrolü sonucu:');
          print('   - Güncelleme gerekiyor: $needsUpdate');
          print('   - Bekleyen sözleşme sayısı: ${pendingContracts.length}');
          
          if (needsUpdate) {
            for (var contract in pendingContracts) {
              print('   📄 ${contract['title']} v${contract['latest_version']} (kabul edilen: v${contract['accepted_version']})');
            }
          }
          
          return {
            'needs_update': needsUpdate,
            'customer_id': customerId,
            'pending_contracts': pendingContracts,
          };
        }
      }
      
      print('⚠️ Sözleşme kontrolü API hatası - varsayılan olarak devam');
      return {'needs_update': false};
      
    } catch (e) {
      print('❌ Sözleşme kontrolü hatası: $e');
      return {'needs_update': false};
    }
  }
  
  Future<void> _requestPermissionsAndInitializeServices() async {
    try {
      // 🔥 BİLDİRİM İZNİ BURADA İSTENMİYOR!
      // AdvancedNotificationService.registerFcmToken() içinde isteniyor (login sonrası)
      // Bu sayede izin 2 kere istenmez
      
      // Konum izni kontrol et
      var locationStatus = await Permission.location.status;
      if (locationStatus.isDenied) {
        await _requestPermissionWithDialog('Konum', Permission.location);
      }
      
      // Firebase messaging ve diğer servisleri başlat
      await _initializeServices();
      
    } catch (e) {
      print('İzin kontrol hatası: $e');
    }
  }
  
  Future<void> _requestPermissionWithDialog(String permissionName, Permission permission) async {
    // İlk kez iste
    var result = await permission.request();
    
    // Eğer reddedilirse bir kez daha iste
    if (result.isDenied) {
      result = await permission.request();
    }
    
    // Hala reddedilirse ayarlara yönlendir
    if (result.isDenied || result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$permissionName İzni Gerekli'),
            content: Text('$permissionName izni uygulama için gereklidir. Lütfen ayarlardan izin verin.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Ayarlara Git'),
              ),
            ],
          ),
        );
      }
    }
  }
  
  Future<void> _initializeServices() async {
    try {
      // Firebase messaging - timeout ile güvenli
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      
      // Topic subscription'ları timeout ile koru
      await Future.wait([
        messaging.subscribeToTopic('funbreak_customers'),
        messaging.subscribeToTopic('funbreak_all'),
      ]).timeout(
        const Duration(seconds: 2), // 5 → 2: Hızlandırıldı
        onTimeout: () {
          print('⚠️ Firebase topic subscription timeout (2s) - hızlı devam');
          return [];
        },
      );
      
      // BİLDİRİM SERVİSİ main.dart'ta başlatılıyor - burada tekrar etme!
      
      // DynamicContactService - ARKA PLANDA BAŞLAT (blocking etmesin)
      DynamicContactService.initialize().catchError((e) {
        print('⚠️ DynamicContactService arka planda başlatılacak: $e');
      });
      
      print('✅ Servisler başlatıldı (HIZLI BAŞLATMA MODU - 2s timeout)');
    } catch (e) {
      print('⚠️ Servis başlatma hatası (devam ediliyor): $e');
    }
  }
  
  // ANDROID NOTIFICATION CHANNEL OLUŞTURMA - KRİTİK EKSİK!
  Future<void> _createNotificationChannel() async {
    try {
      // Android platform check
      if (Theme.of(context).platform == TargetPlatform.android) {
        // Android notification channel oluştur (basitleştirilmiş)
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'funbreak_vale_channel', // ID (AndroidManifest ile eşleşmeli)
          'FunBreak Vale Notifications', // Name
          description: 'FunBreak Vale bildirim kanalı',
          importance: Importance.high,
        );

        // FlutterLocalNotificationsPlugin başlat
        FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
            FlutterLocalNotificationsPlugin();

        // Channel'ı sistem'e kaydet
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
            
        print('✅ MÜŞTERİ: Android notification channel oluşturuldu');
      }
    } catch (e) {
      print('⚠️ MÜŞTERİ: Notification channel oluşturma hatası: $e');
    }
  }
  
  // PUSH NOTIFICATION HANDLER'LARI - YENİ FONKSİYON!
  void _setupPushNotificationHandlers(FirebaseMessaging messaging) {
    try {
      // Uygulama açıkken gelen bildirimler (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📱 === MÜŞTERİ BİLDİRİM ALINDI (FOREGROUND) ===');
        print('   📋 Title: ${message.notification?.title}');
        print('   💬 Body: ${message.notification?.body}');
        print('   📊 Data: ${message.data}');
        print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
        
        if (message.notification != null) {
          // Local notification göster
          _showLocalNotification(
            message.notification!.title ?? 'FunBreak Vale',
            message.notification!.body ?? 'Yeni bildiriminiz var',
          );
          
          print('✅ MÜŞTERİ: Local notification gösterildi');
          
          // UI'DA GÖRSEL FEEDBACK - TELEFONDA GÖREBİLİRSİNİZ!
          try {
            // Global context varsa SnackBar göster
            if (navigatorKey.currentContext != null) {
              ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
                SnackBar(
                  content: Text('🔔 Panel Bildirimi: ${message.notification!.title}'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } catch (e) {
            print('UI feedback hatası: $e');
          }
        } else {
          print('⚠️ MÜŞTERİ: notification null, sadece data var');
        }
      });
      
      // Uygulama kapalıyken gelen bildirime tıklanınca (Background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 Bildirime tıklandı (uygulama kapalı): ${message.notification?.title}');
        
        // Bildirim tipine göre sayfa yönlendirme
        _handleNotificationTap(message);
      });
      
      // ✅ FCM TOKEN ALMAK BURADA YAPMIYORUZ!
      // Token alma işlemi SADECE AdvancedNotificationService tarafından yapılıyor
      // "Too many server requests" hatasını önlemek için getToken() çağrısı kaldırıldı
      print('✅ Push notification handler\'ları kuruldu (Token: AdvancedNotificationService)');
    } catch (e) {
      print('❌ Push notification setup hatası: $e');
    }
  }
  
  // LOCAL NOTIFICATION GÖSTER
  void _showLocalNotification(String title, String body) {
    // Basit SnackBar notification (gerçek projede flutter_local_notifications kullanın)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      body,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFFFD700),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  // BILDIRIME TIKLAMA YÖNLENDİRME
  void _handleNotificationTap(RemoteMessage message) {
    try {
      final data = message.data;
      final notificationType = data['type'] ?? 'general';
      
      print('🔗 Bildirim yönlendirme: $notificationType');
      
      switch (notificationType) {
        case 'campaign':
          // Kampanya sayfasına git
          break;
        case 'announcement':
          // Duyuru sayfasına git
          break;
        case 'ride':
          // Yolculuk detayına git
          break;
        default:
          // Ana sayfaya git
          break;
      }
    } catch (e) {
      print('❌ Bildirim yönlendirme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFD700),
              Color(0xFFFFA500),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              TweenAnimationBuilder<double>(
                duration: const Duration(seconds: 1),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_taxi,
                        size: 70,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
              // Animated Title
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1500),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: const Text(
                      'FunBreak Vale',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              // Animated Subtitle
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 2000),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: const Text(
                      'Güvenli ve Hızlı Vale Hizmeti',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 60),
              
              // Modern Loading Indicator
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 3,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              const Text(
                'Yükleniyor...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
