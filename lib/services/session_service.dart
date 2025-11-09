import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// MÜŞTERİ OTURUM YÖNETİM SERVİSİ - 45 GÜN KALICI!
class SessionService {
  static const String _sessionKey = 'customer_session';
  static const String _lastActivityKey = 'last_activity';
  static const String _autoLoginKey = 'auto_login_enabled';
  static const String _customerIdKey = 'customer_id';
  static const String _customerNameKey = 'customer_name';
  static const String _customerEmailKey = 'customer_email';
  
  static Timer? _sessionTimer;
  static bool _isSessionActive = false;
  
  // Session süresi (45 gün - optimum süre!)
  static const Duration sessionDuration = Duration(days: 45);
  
  // Otomatik çıkışı engelle - session'ı sürekli aktif tut
  static Future<void> initializeSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Otomatik giriş her zaman aktif - kullanıcı manuel kapatana kadar
      await prefs.setBool(_autoLoginKey, true);
      
      // Session'ı aktif olarak işaretle
      await _updateLastActivity();
      _isSessionActive = true;
      
      // Periyodik activity güncelleme (her 5 dakikada bir - müşteri için daha seyrek)
      _sessionTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
        await _updateLastActivity();
        print('📱 MÜŞTERİ: Session activity güncellendi - 45 gün kalıcı oturum');
      });
      
      print('✅ MÜŞTERİ: Session başlatıldı - 45 gün kalıcı oturum aktif');
    } catch (e) {
      print('❌ MÜŞTERİ: Session başlatma hatası: $e');
    }
  }
  
  // Son aktiviteyi güncelle
  static Future<void> _updateLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('❌ MÜŞTERİ: Last activity güncelleme hatası: $e');
    }
  }
  
  // Session kontrolü
  static Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActivity = prefs.getInt(_lastActivityKey);
      final autoLoginEnabled = prefs.getBool(_autoLoginKey) ?? false;
      
      if (!autoLoginEnabled || lastActivity == null) {
        return false;
      }
      
      final lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActivity);
      final now = DateTime.now();
      final difference = now.difference(lastActivityTime);
      
      // 45 gün kontrolü
      bool isValid = difference < sessionDuration;
      
      print('📊 MÜŞTERİ Session kontrolü:');
      print('   Son aktivite: $lastActivityTime');
      print('   Şu an: $now');
      print('   Fark: ${difference.inDays} gün');
      print('   Geçerli: $isValid');
      
      return isValid;
    } catch (e) {
      print('❌ MÜŞTERİ: Session kontrol hatası: $e');
      return false;
    }
  }
  
  // Kullanıcı bilgilerini kaydet (login sırasında)
  static Future<void> saveUserSession({
    required String customerId,
    required String customerName,
    required String customerEmail,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString(_customerIdKey, customerId);
      await prefs.setString(_customerNameKey, customerName);
      await prefs.setString(_customerEmailKey, customerEmail);
      await prefs.setBool(_autoLoginKey, true);
      await _updateLastActivity();
      
      print('✅ MÜŞTERİ: Kullanıcı session bilgileri kaydedildi');
      print('   ID: $customerId');
      print('   Ad: $customerName');
      print('   Email: $customerEmail');
      
    } catch (e) {
      print('❌ MÜŞTERİ: Session kaydetme hatası: $e');
    }
  }
  
  // Kullanıcı bilgilerini al
  static Future<Map<String, String?>> getUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      return {
        'customer_id': prefs.getString(_customerIdKey),
        'customer_name': prefs.getString(_customerNameKey),
        'customer_email': prefs.getString(_customerEmailKey),
      };
    } catch (e) {
      print('❌ MÜŞTERİ: Session okuma hatası: $e');
      return {};
    }
  }
  
  // Oturumu sonlandır (logout)
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_sessionKey);
      await prefs.remove(_lastActivityKey);
      await prefs.remove(_autoLoginKey);
      await prefs.remove(_customerIdKey);
      await prefs.remove(_customerNameKey);
      await prefs.remove(_customerEmailKey);
      
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _isSessionActive = false;
      
      print('✅ MÜŞTERİ: Session tamamen temizlendi');
    } catch (e) {
      print('❌ MÜŞTERİ: Session temizleme hatası: $e');
    }
  }
  
  // Manuel activity güncelleme (kullanıcı bir şey yaptığında)
  static Future<void> updateActivity() async {
    await _updateLastActivity();
    print('📱 MÜŞTERİ: Manuel activity güncellendi');
  }
  
  // Otomatik login aktif mi?
  static Future<bool> isAutoLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoLoginKey) ?? false;
    } catch (e) {
      print('❌ MÜŞTERİ: Auto login kontrol hatası: $e');
      return false;
    }
  }
  
  // Session istatistikleri
  static Future<Map<String, dynamic>> getSessionStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActivity = prefs.getInt(_lastActivityKey);
      final autoLoginEnabled = prefs.getBool(_autoLoginKey) ?? false;
      
      if (lastActivity == null) {
        return {
          'active': false,
          'message': 'Session bulunamadı'
        };
      }
      
      final lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActivity);
      final now = DateTime.now();
      final difference = now.difference(lastActivityTime);
      final remainingDays = sessionDuration.inDays - difference.inDays;
      
      return {
        'active': _isSessionActive,
        'auto_login_enabled': autoLoginEnabled,
        'last_activity': lastActivityTime.toIso8601String(),
        'days_since_activity': difference.inDays,
        'remaining_days': remainingDays > 0 ? remainingDays : 0,
        'expires_at': lastActivityTime.add(sessionDuration).toIso8601String(),
        'is_valid': difference < sessionDuration,
      };
    } catch (e) {
      print('❌ MÜŞTERİ: Session stats hatası: $e');
      return {'active': false, 'error': e.toString()};
    }
  }
}
