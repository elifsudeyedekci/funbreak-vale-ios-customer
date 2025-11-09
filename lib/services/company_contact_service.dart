import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CompanyContactService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Map<String, dynamic>? _cachedContacts;
  static DateTime? _lastFetch;
  static const Duration cacheTimeout = Duration(minutes: 5);
  
  // Panel'den şirket iletişim bilgilerini çek
  static Future<Map<String, dynamic>?> getCompanyContacts() async {
    try {
      // Cache kontrol
      if (_cachedContacts != null && _lastFetch != null) {
        if (DateTime.now().difference(_lastFetch!) < cacheTimeout) {
          print('📞 Company contacts cache\'den alındı');
          return _cachedContacts;
        }
      }
      
      print('📞 Company contacts API\'den çekiliyor...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedContacts = {
            'support_phone': data['settings']['support_phone'] ?? '+90 555 123 45 67',
            'contact_phone': data['settings']['contact_phone'] ?? '+90 555 123 45 67',
            'emergency_phone': data['settings']['emergency_phone'] ?? '+90 555 123 45 67',
            'company_name': data['settings']['app_name'] ?? 'FunBreak Vale',
            'support_email': data['settings']['support_email'] ?? 'destek@funbreakvale.com',
          };
          _lastFetch = DateTime.now();
          
          print('✅ Company contacts başarıyla alındı: ${_cachedContacts!['support_phone']}');
          return _cachedContacts;
        }
      }
      
      print('❌ Company contacts alınamadı: ${response.statusCode}');
      return null;
      
    } catch (e) {
      print('❌ Company contacts hatası: $e');
      return null;
    }
  }
  
  // Müşteri için şirket arama seçenekleri
  static Future<List<Map<String, String>>> getCustomerCallOptions() async {
    final contacts = await getCompanyContacts();
    
    if (contacts == null) {
      // Fallback değerler
      return [
        {
          'title': '🏢 Şirket Destek',
          'subtitle': 'Genel destek hattı',
          'phone': '+90 555 123 45 67',
          'type': 'company_support',
        },
        {
          'title': '🚨 Acil Durum',
          'subtitle': '7/24 acil destek',
          'phone': '+90 555 123 45 67',
          'type': 'emergency',
        },
      ];
    }
    
    return [
      {
        'title': '🏢 ${contacts['company_name']} Destek',
        'subtitle': 'Şirket destek hattı',
        'phone': contacts['support_phone'],
        'type': 'company_support',
      },
      {
        'title': '📞 İletişim Merkezi',
        'subtitle': 'Müşteri hizmetleri',
        'phone': contacts['contact_phone'],
        'type': 'customer_service',
      },
      {
        'title': '🚨 Acil Durum',
        'subtitle': '7/24 acil destek',
        'phone': contacts['emergency_phone'] ?? contacts['support_phone'],
        'type': 'emergency',
      },
    ];
  }
  
  // Şoför için şirket arama seçenekleri
  static Future<List<Map<String, String>>> getDriverCallOptions() async {
    final contacts = await getCompanyContacts();
    
    if (contacts == null) {
      // Fallback değerler
      return [
        {
          'title': '🏢 Şirket Merkezi',
          'subtitle': 'Şoför destek hattı',
          'phone': '+90 555 123 45 67',
          'type': 'driver_support',
        },
        {
          'title': '🚨 Acil Durum',
          'subtitle': '7/24 acil destek',
          'phone': '+90 555 123 45 67',
          'type': 'emergency',
        },
      ];
    }
    
    return [
      {
        'title': '🏢 ${contacts['company_name']} Merkezi',
        'subtitle': 'Şoför destek hattı',
        'phone': contacts['support_phone'],
        'type': 'driver_support',
      },
      {
        'title': '📞 Operasyon Merkezi',
        'subtitle': 'Yolculuk desteği',
        'phone': contacts['contact_phone'],
        'type': 'operations',
      },
      {
        'title': '🚨 Acil Durum',
        'subtitle': '7/24 acil yardım',
        'phone': contacts['emergency_phone'] ?? contacts['support_phone'],
        'type': 'emergency',
      },
    ];
  }
  
  // Cache temizle
  static void clearCache() {
    _cachedContacts = null;
    _lastFetch = null;
    print('📞 Company contacts cache temizlendi');
  }
}
