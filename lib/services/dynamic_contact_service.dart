import 'dart:convert';
import 'package:http/http.dart' as http;

// DİNAMİK İLETİŞİM BİLGİLERİ SERVİSİ - PANEL ENTEGRE!
class DynamicContactService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static Map<String, dynamic>? _cachedSettings;
  static DateTime? _lastFetchTime;
  static const Duration cacheDuration = Duration(seconds: 30); // 30 saniye cache - anlık çekme

  // SİSTEM AYARLARINI ÇEK (CACHE İLE)
  static Future<Map<String, dynamic>> getSystemSettings() async {
    // Cache kontrol
    if (_cachedSettings != null && 
        _lastFetchTime != null && 
        DateTime.now().difference(_lastFetchTime!) < cacheDuration) {
      print('📱 Cached sistem ayarları kullanılıyor');
      return _cachedSettings!;
    }

    try {
      print('🔄 Panel sistem ayarları çekiliyor...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // DEBUG: Response body kontrol - String->int error fix!
        print('🔍 API Response Body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}...');
        
        final data = json.decode(response.body);
        
        print('🔍 Parsed Data Type: ${data.runtimeType}');
        print('🔍 Data Keys: ${data is Map ? data.keys.toList() : 'Not a Map'}');
        
        if (data['success'] == true && data['settings'] != null) {
          // Settings type kontrolü - String->int error fix!
          final settings = data['settings'];
          print('🔍 Settings Type: ${settings.runtimeType}');
          
          if (settings is Map<String, dynamic>) {
            _cachedSettings = settings;
            _lastFetchTime = DateTime.now();
            
            print('✅ Sistem ayarları başarıyla çekildi:');
            print('   📞 Telefon: ${getSupportPhone()}');
            print('   📧 Email: ${getSupportEmail()}');
            print('   💬 WhatsApp: ${getWhatsAppNumber()}');
            
            return _cachedSettings!;
          } else {
            print('⚠️ Settings format hatası - Map değil: ${settings.runtimeType}');
            return _getDefaultSettings();
          }
        }
      }
      
      print('⚠️ Panel ayarları çekilemedi - varsayılan değerler kullanılıyor');
      return _getDefaultSettings();
      
    } catch (e) {
      print('❌ Panel ayarları çekme hatası: $e');
      return _getDefaultSettings();
    }
  }

  // DESTEK TELEFON NUMARASI
  static String getSupportPhone() {
    if (_cachedSettings != null && 
        _cachedSettings!['support_phone'] != null) {
      final phone = _cachedSettings!['support_phone'].toString();
      print('✅ Destek telefonu panelden alındı: $phone');
      return phone;
    }
    print('⚠️ Destek telefonu panelden alınamadı, varsayılan kullanılıyor: 05555555555');
    return '05555555555'; // Varsayılan
  }

  // DESTEK EMAIL
  static String getSupportEmail() {
    if (_cachedSettings != null && 
        _cachedSettings!['support_email'] != null) {
      return _cachedSettings!['support_email'].toString();
    }
    return 'destek@funbreakvale.com'; // Varsayılan
  }

  // WHATSAPP NUMARASI - DESTEK TELEFONU İLE AYNI
  static String getWhatsAppNumber() {
    if (_cachedSettings != null) {
      // Önce destek telefonunu kullan (aynı numara olsun)
      final supportPhone = _cachedSettings!['support_phone']?.toString();
      final whatsappNum = _cachedSettings!['whatsapp_number']?.toString();
      
      if (supportPhone != null && supportPhone.isNotEmpty) {
        print('✅ MÜŞTERİ WhatsApp destek telefonu ile aynı: $supportPhone');
        return supportPhone;
      } else if (whatsappNum != null && whatsappNum.isNotEmpty) {
        print('✅ WhatsApp panelden alındı: $whatsappNum');
        return whatsappNum;
      }
    }
    print('⚠️ WhatsApp panelden alınamadı, varsayılan kullanılıyor');
    return '05555555555'; // Son çare varsayılan
  }

  // ŞİRKET ADI
  static String getCompanyName() {
    if (_cachedSettings != null && 
        _cachedSettings!['company_name'] != null) {
      return _cachedSettings!['company_name'].toString();
    }
    return 'FunBreak Vale'; // Varsayılan
  }

  // ŞİRKET ADRESİ
  static String getCompanyAddress() {
    if (_cachedSettings != null && 
        _cachedSettings!['company_address'] != null) {
      return _cachedSettings!['company_address'].toString();
    }
    return 'İstanbul, Türkiye'; // Varsayılan
  }

  // VARSAYILAN AYARLAR
  static Map<String, dynamic> _getDefaultSettings() {
    return {
      'support_phone': {'value': '05334488253'},
      'support_email': {'value': 'info@funbreakvale.com'},
      'whatsapp_number': {'value': '05334488253'},
      'company_name': {'value': 'FunBreak Vale'},
      'company_address': {'value': 'İstanbul, Türkiye'},
    };
  }

  // CACHE TEMİZLE (Güncelleme için)
  static void clearCache() {
    _cachedSettings = null;
    _lastFetchTime = null;
    print('🗑️ İletişim cache temizlendi - yeni veriler çekilecek');
  }

  // TELEFON ARAMA
  static String getPhoneUrl() {
    return 'tel:${getSupportPhone()}';
  }

  // EMAIL GÖNDERME
  static String getEmailUrl({String? subject, String? body}) {
    String url = 'mailto:${getSupportEmail()}';
    
    List<String> params = [];
    if (subject != null) params.add('subject=${Uri.encodeComponent(subject)}');
    if (body != null) params.add('body=${Uri.encodeComponent(body)}');
    
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    
    return url;
  }

  // WHATSAPP MESAJ - TYPE SAFE!
  static String getWhatsAppUrl({String? message}) {
    try {
      String phone = getWhatsAppNumber().replaceAll(RegExp(r'[^\d]'), '');
      
      // TYPE SAFE substring - String->int error fix!
      if (phone.isNotEmpty && phone.startsWith('0') && phone.length > 1) {
        phone = '90${phone.substring(1)}'; // Türkiye kodu ekle
      }
      
      String url = 'https://wa.me/$phone';
      if (message != null && message.isNotEmpty) {
        url += '?text=${Uri.encodeComponent(message)}';
      }
      
      return url;
    } catch (e) {
      print('❌ WhatsApp URL oluşturma hatası: $e');
      return 'https://wa.me/905555555555'; // Fallback
    }
  }

  // CACHE'DEN AYARLARI AL (HIZLI ERİŞİM)
  static Map<String, dynamic>? getCachedSettings() {
    if (_cachedSettings != null && 
        _lastFetchTime != null && 
        DateTime.now().difference(_lastFetchTime!) < cacheDuration) {
      return _cachedSettings;
    }
    return null; // Cache boş veya süresi dolmuş
  }

  // AYARLARI YENILE
  static Future<void> refreshSettings() async {
    clearCache();
    await getSystemSettings();
    print('🔄 Sistem ayarları yenilendi');
  }

  // INIT - UYGULAMA BAŞLATILDIĞINDA ÇAĞIR
  static Future<void> initialize() async {
    print('🚀 Dinamik iletişim servisi başlatılıyor...');
    await getSystemSettings();
    print('✅ Dinamik iletişim servisi hazır!');
  }
}
