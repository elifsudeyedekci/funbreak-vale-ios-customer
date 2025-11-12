import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'admin_api_provider.dart';

class AuthProvider with ChangeNotifier {
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  final AdminApiProvider _adminApi = AdminApiProvider();
  
  FirebaseAuth? get auth => _auth;
  FirebaseFirestore? get firestore => _firestore;
  
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  String? _userEmail;
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  double _pendingPaymentAmount = 0.0; // BEKLEYEN ÖDEME MİKTARI

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
        
        print('Session yüklendi - Name: $_customerName, Email: $_userEmail');
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
        
        // ✅ KAYIT BAŞARILI - FCM TOKEN KAYDET!
        _updateFCMToken();
        
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
        
        // ✅ TEST HESABI LOGİN - FCM TOKEN KAYDET!
        _updateFCMToken();
        
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
        
        // ✅ LOGİN BAŞARILI - FCM TOKEN KAYDET!
        _updateFCMToken();
        
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
  Future<void> _updateFCMToken() async {
    try {
      debugPrint('🔔 FCM Token güncelleme başlatılıyor...');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('admin_user_id') ?? prefs.getString('user_id');
      
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ User ID bulunamadı, token güncellenemedi');
        return;
      }
      
      // FCM Token al
      final messaging = FirebaseMessaging.instance;
      final fcmToken = await messaging.getToken().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ FCM Token timeout');
          return null;
        },
      );
      
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('⚠️ FCM Token alınamadı');
        return;
      }
      
      debugPrint('✅ FCM Token alındı: ${fcmToken.substring(0, 20)}...');
      
      // Backend'e gönder
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'customer',
          'fcm_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        debugPrint('✅ FCM Token backend\'e kaydedildi!');
      } else {
        debugPrint('⚠️ FCM Token backend kayıt hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ FCM Token güncelleme hatası: $e');
    }
  }
}