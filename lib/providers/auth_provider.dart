import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // ✅ Platform.isIOS için gerekli!
import 'dart:math'; // ✅ Random için!
import 'admin_api_provider.dart';
import '../services/advanced_notification_service.dart'; // ✅ FCM TOKEN İÇİN!

class AuthProvider with ChangeNotifier {
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  final AdminApiProvider _adminApi = AdminApiProvider();
  
  FirebaseAuth? get auth => _auth;
  FirebaseFirestore? get firestore => _firestore;
  
  // ✅ iOS DEBUG LOG - BACKEND'E GÖNDER!
  Future<void> _logToBackend(String message, {String level = 'INFO'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('admin_user_id') ?? prefs.getString('customer_id') ?? prefs.getString('user_id') ?? 'UNKNOWN';
      
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/log_ios_debug.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_name': 'CUSTOMER',
          'log_level': level,
          'message': message,
          'driver_id': '',
          'customer_id': customerId,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      // Sessiz başarısız - log gönderme hatası ana işlemi durdurmasın!
    }
  }
  
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  String? _userEmail;
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  double _pendingPaymentAmount = 0.0; // BEKLEYEN ÖDEME MİKTARI
  String? _deviceId; // ✅ ÇOKLU OTURUM İÇİN DEVICE ID

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isAuthenticated;
  String? get error => _error;
  String? get userEmail => _userEmail;
  String? get customerId => _customerId;
  String? get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  double get pendingPaymentAmount => _pendingPaymentAmount; // BEKLEYEN ÖDEME GETTERı
  bool get hasPendingPayment => _pendingPaymentAmount > 0; // BEKLEYEN ÖDEME KONTROL
  String? get deviceId => _deviceId; // DEVICE ID GETTER
  
  // ✅ DEVICE ID OLUŞTUR VEYA AL (UUID benzeri benzersiz kimlik)
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    
    if (deviceId == null || deviceId.isEmpty) {
      // Yeni device ID oluştur (timestamp + random)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(999999);
      deviceId = 'device_${timestamp}_$random';
      await prefs.setString('device_id', deviceId);
      print('✅ Yeni device ID oluşturuldu: $deviceId');
    } else {
      print('✅ Mevcut device ID: $deviceId');
    }
    
    _deviceId = deviceId;
    return deviceId;
  }

  // Session persistence için constructor
  AuthProvider() {
    initializeProvider();
  }
  
  Future<void> initializeProvider() async {
    try {
      // Firebase başlatmayı timeout ile güvenli hale getir
      await Future.wait([
        Future(() => _auth = FirebaseAuth.instance),
        Future(() => _firestore = FirebaseFirestore.instance),
      ]).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Firebase timeout - offline modda devam');
          return [];
        },
      );
    } catch (e) {
      debugPrint('⚠️ Firebase başlatma hatası (devam ediliyor): $e');
      // Firebase olmadan da çalışabilsin
    }
    
    // Session yüklemeyi hızlı yap
    await _loadSavedSession();
    notifyListeners(); // UI'yi güncelle
  }

  // Kayıtlı oturum bilgilerini yükle
  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      
      print('Session yükleniyor - isLoggedIn: $isLoggedIn');
      
      if (isLoggedIn) {
        // 🔒 45 GÜNLÜK SESSION KONTROLÜ
        final loginTimestamp = prefs.getInt('login_timestamp') ?? 0;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        final daysSinceLogin = (currentTime - loginTimestamp) / (1000 * 60 * 60 * 24);
        
        if (daysSinceLogin > 45) {
          // 45 gün geçmiş, oturumu kapat
          print('⏰ Session süresi doldu (${daysSinceLogin.toStringAsFixed(1)} gün). Çıkış yapılıyor...');
          await logout();
          return;
        }
        
        print('✅ Session aktif (${daysSinceLogin.toStringAsFixed(1)} / 45 gün)');
        
        _userEmail = prefs.getString('user_email');
        _customerName = prefs.getString('user_name');
        _customerPhone = prefs.getString('user_phone');
        _customerId = prefs.getString('admin_user_id');
        _isAuthenticated = true;
        
        print('✅ Session yüklendi - Name: $_customerName, Email: $_userEmail');
        
        // ✅ FCM main.dart'ta çalışacak - burada uğraşma!
        notifyListeners();
      }
    } catch (e) {
      print('Session yükleme hatası: $e');
    }
  }

  // Oturum durumunu kontrol et
  Future<bool> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    
    if (isLoggedIn) {
      // 🔒 45 GÜNLÜK SESSION KONTROLÜ
      final loginTimestamp = prefs.getInt('login_timestamp') ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLogin = (currentTime - loginTimestamp) / (1000 * 60 * 60 * 24);
      
      if (daysSinceLogin > 45) {
        // 45 gün geçmiş, oturumu kapat
        print('⏰ Session süresi doldu. Çıkış yapılıyor...');
        await logout();
        return false;
      }
      
      _userEmail = prefs.getString('user_email');
      _customerName = prefs.getString('user_name');
      _customerPhone = prefs.getString('user_phone');
      _customerId = prefs.getString('admin_user_id');
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    
    return false;
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Kullanıcı kaydı (Admin Panel + Firebase)
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      // Admin panel API ile kayıt
      final adminResult = await _adminApi.registerCustomer(
        name: name,
        email: email,
        phone: phone,
        password: password,
      );

      if (adminResult['success'] == true) {
        // Firebase ile de kayıt yap
        try {
          if (_auth != null) {
            UserCredential result = await _auth!.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );

            if (result.user != null && _firestore != null) {
              // Firestore'a kullanıcı bilgilerini kaydet
              await _firestore!.collection('customers').doc(result.user!.uid).set({
                'name': name,
                'email': email,
                'phone': phone,
                'admin_id': adminResult['user']['id'],
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        } catch (firebaseError) {
          debugPrint('Firebase kayıt hatası: $firebaseError');
          // Admin panel kaydı başarılı olduğu için devam et
        }

        // Session bilgilerini kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_user_id', adminResult['user']['id'].toString());
        await prefs.setString('customer_id', adminResult['user']['id'].toString()); // FCM için!
        await prefs.setInt('customer_id', int.parse(adminResult['user']['id'].toString())); // Int!
        await prefs.setString('user_email', email);
        await prefs.setString('user_name', name);
        await prefs.setString('user_phone', phone);
        await prefs.setBool('is_logged_in', true);

        _isAuthenticated = true;
        _userEmail = email;
        _customerName = name;
        _customerPhone = phone;
        _customerId = adminResult['user']['id'].toString();
        
        // KRİTİK: notifyListeners() ÇAĞIR - register_screen.dart customerId'yi alabilsin!
        notifyListeners();
        debugPrint('✅ REGISTER: Customer ID set edildi: $_customerId');
        
        // ✅ KAYIT BAŞARILI - FCM TOKEN KAYDET (ARKA PLANDA - BEKLEMEDEN!)
        print('🔔🔔🔔 REGISTER: _updateFCMToken() ARKA PLANDA ÇAĞRILACAK! 🔔🔔🔔');
        _updateFCMToken().then((_) {
          print('✅ REGISTER: _updateFCMToken() TAMAMLANDI!');
        }).catchError((fcmError) {
          print('❌❌❌ REGISTER: _updateFCMToken() EXCEPTION: $fcmError ❌❌❌');
        });
        
        _setLoading(false);
        return true;
      } else {
        _error = adminResult['message'] ?? 'Kayıt başarısız';
      }
    } catch (e) {
      _error = 'Kayıt hatası: ${e.toString()}';
      debugPrint(_error);
    }

    _setLoading(false);
    return false;
  }

  // Kullanıcı girişi (Admin Panel + Firebase)
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      // ✅ ÇOKLU OTURUM: Device ID al veya oluştur
      final deviceId = await _getOrCreateDeviceId();
      print('🔐 LOGIN: Device ID = $deviceId');
      
      // Test hesapları için direkt giriş
      if (email == "test@customer.com" && password == "123456") {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_user_id', '1');
        await prefs.setString('user_email', email);
        await prefs.setString('user_name', 'Test Müşteri');
        await prefs.setString('user_phone', '05555555555');
        await prefs.setBool('is_logged_in', true);

        _isAuthenticated = true;
        _userEmail = email;
        _customerName = 'Test Müşteri';
        _customerPhone = '05555555555';
        _customerId = '1';
        
        // ✅ TEST HESABI LOGİN - FCM TOKEN KAYDET (ARKA PLANDA - BEKLEMEDEN!)
        print('🔔🔔🔔 TEST LOGİN: _updateFCMToken() ARKA PLANDA ÇAĞRILACAK! 🔔🔔🔔');
        _updateFCMToken().then((_) {
          print('✅ TEST LOGİN: _updateFCMToken() TAMAMLANDI!');
        }).catchError((fcmError) {
          print('❌❌❌ TEST LOGİN: _updateFCMToken() EXCEPTION: $fcmError ❌❌❌');
        });
        
        _setLoading(false);
        return true;
      }

      // Admin panel API ile giriş
      final adminResult = await _adminApi.loginCustomer(
        email: email,
        password: password,
      );

      if (adminResult['success'] == true) {
        final user = adminResult['user'];
        
        // Session bilgilerini kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_user_id', user['id'].toString());
        await prefs.setString('customer_id', user['id'].toString()); // FCM için!
        await prefs.setInt('customer_id', int.parse(user['id'].toString())); // Int!
        await prefs.setString('user_email', user['email']);
        await prefs.setString('user_name', user['name']);
        await prefs.setString('user_phone', user['phone'] ?? '');
        await prefs.setBool('is_logged_in', true);

        _isAuthenticated = true;
        _userEmail = user['email'];
        _customerName = user['name'];
        _customerPhone = user['phone'];
        _customerId = user['id'].toString();

        // Firebase ile de giriş yapmayı dene
        try {
          if (_auth != null) {
            await _auth!.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
          }
        } catch (firebaseError) {
          debugPrint('Firebase giriş hatası: $firebaseError');
          // Admin panel girişi başarılı olduğu için devam et
        }
        
        // ✅ ÇOKLU OTURUM: Eski cihazları logout yap
        try {
          await http.post(
            Uri.parse('https://admin.funbreakvale.com/api/logout_other_devices.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': _customerId,
              'device_id': deviceId,
              'user_type': 'customer',
            }),
          ).timeout(const Duration(seconds: 5));
          print('✅ Çoklu oturum: Eski cihazlar logout yapıldı');
        } catch (e) {
          print('⚠️ Çoklu oturum hatası (devam ediliyor): $e');
        }
        
        // ✅ LOGİN BAŞARILI - FCM TOKEN KAYDET (ARKA PLANDA - BEKLEMEDEN!)
        print('🔔🔔🔔 LOGİN (CUSTOMER): _updateFCMToken() ARKA PLANDA ÇAĞRILACAK! 🔔🔔🔔');
        _updateFCMToken().then((_) {
          print('✅ LOGİN (CUSTOMER): _updateFCMToken() TAMAMLANDI!');
        }).catchError((fcmError) {
          print('❌❌❌ LOGİN (CUSTOMER): _updateFCMToken() EXCEPTION: $fcmError ❌❌❌');
        });
        
        _setLoading(false);
        return true;
      } else {
        _error = adminResult['message'] ?? 'Giriş başarısız';
      }
    } catch (e) {
      _error = 'Giriş hatası: ${e.toString()}';
      debugPrint(_error);
    }

    _setLoading(false);
    return false;
  }

  // Şoför girişi (sadece admin panel)
  Future<bool> loginDriver({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final adminResult = await _adminApi.loginDriver(
        email: email,
        password: password,
      );

      if (adminResult['success'] == true) {
        final user = adminResult['user'];
        
        // Session bilgilerini kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_user_id', user['id'].toString());
        await prefs.setString('user_email', user['email']);
        await prefs.setString('user_name', user['name']);
        await prefs.setString('user_phone', user['phone'] ?? '');
        await prefs.setString('user_type', 'driver');
        await prefs.setBool('is_logged_in', true);

        _isAuthenticated = true;
        _userEmail = user['email'];
        _customerName = user['name'];
        _customerPhone = user['phone'];
        _customerId = user['id'].toString();
        
        _setLoading(false);
        return true;
      } else {
        _error = adminResult['message'] ?? 'Şoför girişi başarısız';
      }
    } catch (e) {
      _error = 'Şoför giriş hatası: ${e.toString()}';
      debugPrint(_error);
    }

    _setLoading(false);
    return false;
  }

  // Kullanıcı bilgilerini güncelle
  void updateUserInfo({String? name, String? phone, String? email}) {
    if (name != null) _customerName = name;
    if (phone != null) _customerPhone = phone;
    if (email != null) _userEmail = email;
    notifyListeners();
  }

  // Çıkış yap
  Future<void> logout() async {
    try {
      if (_auth != null) {
        await _auth!.signOut();
      }
      await _adminApi.clearSession();
      
      // SharedPreferences'i de temizle
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      _isAuthenticated = false;
      _userEmail = null;
      _customerId = null;
      _customerName = null;
      _customerPhone = null;
      _error = null;
      
      notifyListeners();
    } catch (e) {
      _error = 'Çıkış hatası: ${e.toString()}';
      debugPrint(_error);
      notifyListeners();
    }
  }

  // Hata temizle
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // BEKLEYEN ÖDEME KONTROL SİSTEMİ - KRİTİK ÖZELLİK!
  Future<void> checkPendingPayments() async {
    try {
      if (_customerId == null) {
        _pendingPaymentAmount = 0.0;
        return;
      }
      
      print('💳 Bekleyen ödeme kontrol ediliyor: $_customerId');
      
      // Admin panel API ile bekleyen ödemeleri kontrol et
      final result = await _adminApi.checkPendingPayments(_customerId!);
      
      if (result['success'] == true) {
        _pendingPaymentAmount = (result['pending_amount'] ?? 0.0).toDouble();
        print('💰 Bekleyen ödeme miktarı: ₺${_pendingPaymentAmount.toStringAsFixed(2)}');
      } else {
        _pendingPaymentAmount = 0.0;
        print('✅ Bekleyen ödeme yok');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ Bekleyen ödeme kontrol hatası: $e');
      _pendingPaymentAmount = 0.0;
      notifyListeners();
    }
  }
  
  // BEKLEYEN ÖDEME TEMİZLEME (ÖDEME YAPILDIKTAN SONRA)
  void clearPendingPayment() {
    _pendingPaymentAmount = 0.0;
    notifyListeners();
    print('✅ Bekleyen ödeme temizlendi');
  }
  
  // ✅ FCM TOKEN GÜNCELLEME - LOGIN/REGISTER SONRASI OTOMATIK ÇAĞRILIR!
  // 🔥 V2.0 - RATE LIMIT SORUNU ÇÖZÜLDÜ!
  Future<void> _updateFCMToken() async {
    print('🔔 iOS CUSTOMER: _updateFCMToken() - V2.0 (Rate Limit Fix)');
    
    try {
      // Customer ID'yi al
      final prefs = await SharedPreferences.getInstance();
      final customerIdStr = prefs.getString('admin_user_id') ?? 
                            prefs.getString('customer_id') ?? 
                            prefs.getString('user_id');
      
      if (customerIdStr == null || customerIdStr.isEmpty) {
        print('❌ FCM: Customer ID bulunamadı - token kaydedilemedi');
        return;
      }
      
      final customerId = int.tryParse(customerIdStr);
      if (customerId == null || customerId <= 0) {
        print('❌ FCM: Geçersiz Customer ID: $customerIdStr');
        return;
      }
      
      print('🔔 FCM: Token kaydediliyor - Customer ID: $customerId');
      
      // 🔥 YENİ: registerFcmToken() kullan - TEK DENEME, RATE LIMIT YOK!
      final success = await AdvancedNotificationService.registerFcmToken(
        customerId, 
        userType: 'customer',
      );
      
      if (success) {
        print('✅ FCM Token başarıyla kaydedildi!');
      } else {
        print('⚠️ FCM Token kaydedilemedi (ama uygulama çalışmaya devam edecek)');
      }
    } catch (e) {
      print('⚠️ FCM Token güncelleme hatası: $e');
    }
  }
}