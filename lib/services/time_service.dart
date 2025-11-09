import 'dart:convert';
import 'package:http/http.dart' as http;

/// 🔒 SERVER TIME SERVICE - Telefon saati manipülasyonunu engeller
class TimeService {
  static const String _baseUrl = 'https://admin.funbreakvale.com/api';
  
  static DateTime? _cachedServerTime;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  /// Server time'ı al (5 dk cache ile)
  static Future<DateTime> getServerTime() async {
    // Cache kontrolü
    if (_cachedServerTime != null && _cacheTime != null) {
      final cacheAge = DateTime.now().difference(_cacheTime!);
      if (cacheAge < _cacheDuration) {
        // Cache geçerli - elapsed time ekle
        return _cachedServerTime!.add(cacheAge);
      }
    }
    
    try {
      print('🕐 Server time API çağrısı yapılıyor...');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/get_server_time.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['server_time'] != null) {
          _cachedServerTime = DateTime.parse(data['server_time']);
          _cacheTime = DateTime.now();
          
          print('✅ Server time alındı: ${data['server_time']}');
          print('📱 Phone time: ${DateTime.now()}');
          
          return _cachedServerTime!;
        }
      }
      
      print('⚠️ Server time API hatası, telefon saati kullanılıyor (fallback)');
      return DateTime.now();
      
    } catch (e) {
      print('❌ Server time hatası: $e - Telefon saati kullanılıyor (fallback)');
      return DateTime.now();
    }
  }
  
  /// Cache'i temizle
  static void clearCache() {
    _cachedServerTime = null;
    _cacheTime = null;
    print('🗑️ Server time cache temizlendi');
  }
  
  /// İki zaman arasındaki farkı hesapla (server time kullanarak)
  static Future<Duration> getTimeDifference(DateTime futureTime) async {
    final serverNow = await getServerTime();
    return futureTime.difference(serverNow);
  }
  
  /// Gelecek bir zamana kadar kaç saat var?
  static Future<double> getHoursUntil(DateTime futureTime) async {
    final diff = await getTimeDifference(futureTime);
    return diff.inMinutes / 60.0;
  }
}

