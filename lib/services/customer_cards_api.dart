import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// CUSTOMER CARDS API - YENİ VakıfBank Entegreli Kayıtlı Kart Yönetimi
/// 
/// Özellikler:
/// - 0.01 TL doğrulama ile kart kaydetme
/// - VakıfBank 3D Secure entegrasyonu
/// - Kayıtlı kartla ödeme yapma
/// 
/// @version 2.0.0
/// @date 2025-11-27
class CustomerCardsApi {
  static const String baseUrl = 'https://admin.funbreakvale.com/api/payment';
  
  // Customer ID'yi SharedPreferences'tan al
  Future<int?> _getCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    int? customerId;
    
    // 1. İlk önce STRING olarak dene (admin_user_id STRING olarak kayıtlı!)
    final customerIdStr = prefs.getString('admin_user_id') ??  
                          prefs.getString('customer_id') ?? 
                          prefs.getString('user_id');
    
    if (customerIdStr != null && customerIdStr.isNotEmpty) {
      customerId = int.tryParse(customerIdStr);
    }
    
    // 2. Bulunamadıysa INT olarak dene
    if (customerId == null) {
      customerId = prefs.getInt('customer_id') ?? prefs.getInt('user_id');
    }
    
    return customerId;
  }
  
  // ==================== GET CARDS - YENİ API ====================
  Future<List<Map<String, dynamic>>> getCards() async {
    try {
      final customerId = await _getCustomerId();
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return [];
      }
      
      print('📋 Kartlar çekiliyor - Customer ID: $customerId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_saved_cards.php?customer_id=$customerId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> cardsJson = data['cards'] ?? [];
          
          // Yeni formatı eski formata dönüştür (geriye uyumluluk)
          final List<Map<String, dynamic>> cards = cardsJson.map((card) {
            return {
              'id': card['id'],
              'cardNumber': card['masked_card_number'] ?? '**** **** **** ${card['card_last_four']}',
              'cardHolder': card['card_holder'],
              'expiryDate': card['expiry_formatted'] ?? '${card['expiry_month']}/${card['expiry_year']?.toString().substring(2)}',
              'cardType': card['card_brand']?.toString().toLowerCase() ?? 'unknown',
              'isDefault': card['is_default'] == true,
              'isVerified': card['is_verified'] == true,
              'isExpired': card['is_expired'] == true,
              'cardAlias': card['card_alias'],
              'lastUsedAt': card['last_used_at'],
              'addedDate': card['created_at'],
              // Yeni alanlar
              'card_id': card['id'], // Yeni sistem için
              'card_last_four': card['card_last_four'],
              'card_first_six': card['card_first_six'],
            };
          }).toList();
          
          print('✅ ${cards.length} kart çekildi');
          return cards;
        } else {
          print('❌ API hatası: ${data['message']}');
          return [];
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Kartlar çekilirken hata: $e');
      return [];
    }
  }
  
  // ==================== ADD CARD - YENİ 3D SECURE DOĞRULAMA ====================
  /// Kart doğrulama başlatır (0.01 TL çekip iade eder)
  /// 
  /// Returns:
  /// - success: true/false
  /// - requires_3d: true ise 3D Secure gerekli
  /// - acs_html: 3D Secure HTML (WebView'da gösterilecek)
  /// - verification_id: Doğrulama ID
  /// - message: Mesaj
  Future<Map<String, dynamic>?> addCard({
    required String cardNumber,
    required String cardHolder,
    required String expiryDate,
    required String cvv,
    String cardAlias = '',
  }) async {
    try {
      final customerId = await _getCustomerId();
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return null;
      }
      
      print('💳 Yeni kart doğrulama başlatılıyor - Customer ID: $customerId');
      
      // Expiry formatını ayır (MM/YY -> month, year)
      String expiryMonth = '';
      String expiryYear = '';
      
      if (expiryDate.contains('/')) {
        final parts = expiryDate.split('/');
        expiryMonth = parts[0].padLeft(2, '0');
        expiryYear = parts.length > 1 ? '20${parts[1]}' : '';
      }
      
      final requestBody = {
        'customer_id': customerId,
        'card_number': cardNumber.replaceAll(' ', ''),
        'card_holder': cardHolder.toUpperCase(),
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'cvv': cvv,
        'card_alias': cardAlias,
      };
      
      print('📤 Request body: ${json.encode({...requestBody, 'card_number': '****', 'cvv': '***'})}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/verify_and_save_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 60));
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          print('✅ Kart doğrulama başlatıldı');
          
          return {
            'success': true,
            'requires_3d': data['requires_3d'] ?? false,
            'acs_html': data['acs_html'],
            'verification_id': data['verification_id'],
            'transaction_id': data['transaction_id'],
            'message': data['message'] ?? 'Doğrulama başlatıldı',
          };
        } else {
          print('❌ API hatası: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Kart doğrulanamadı',
          };
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Kart eklenirken hata: $e');
      return null;
    }
  }
  
  // ==================== UPDATE CARD (VARSAYILAN YAPMA) ====================
  Future<bool> updateCard({
    required int cardId,
    String? cardHolder,
    bool? setDefault,
  }) async {
    try {
      final customerId = await _getCustomerId();
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return false;
      }
      
      print('🔄 Kart güncelleniyor - Card ID: $cardId');
      
      if (setDefault == true) {
        // Varsayılan kartı ayarla
        final response = await http.post(
          Uri.parse('$baseUrl/set_default_card.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'customer_id': customerId,
            'card_id': cardId,
          }),
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['success'] == true) {
            print('✅ Varsayılan kart ayarlandı');
            return true;
          } else {
            print('❌ API hatası: ${data['message']}');
            return false;
          }
        } else {
          print('❌ HTTP hatası: ${response.statusCode}');
          return false;
        }
      }
      
      // Kart bilgisi güncelleme (şimdilik desteklenmiyor)
      print('⚠️ Kart bilgisi güncelleme desteklenmiyor');
      return false;
    } catch (e) {
      print('❌ Kart güncellenirken hata: $e');
      return false;
    }
  }
  
  // ==================== DELETE CARD ====================
  Future<bool> deleteCard(int cardId) async {
    try {
      final customerId = await _getCustomerId();
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return false;
      }
      
      print('🗑️ Kart siliniyor - Card ID: $cardId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/delete_saved_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customer_id': customerId,
          'card_id': cardId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          print('✅ Kart silindi');
          return true;
        } else {
          print('❌ API hatası: ${data['message']}');
          return false;
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Kart silinirken hata: $e');
      return false;
    }
  }
  
  // ==================== KAYITLI KARTLA ÖDEME ====================
  /// Kayıtlı kartla ödeme yapar
  /// 
  /// Returns:
  /// - success: true/false
  /// - requires_3d: true ise 3D Secure gerekli
  /// - acs_html: 3D Secure HTML
  /// - payment_id: Ödeme ID
  Future<Map<String, dynamic>?> payWithSavedCard({
    required int cardId,
    required String cvv,
    required double amount,
    required int rideId,
    String paymentType = 'ride_payment',
  }) async {
    try {
      final customerId = await _getCustomerId();
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return null;
      }
      
      print('💳 Kayıtlı kartla ödeme - Card ID: $cardId, Amount: $amount');
      
      final response = await http.post(
        Uri.parse('$baseUrl/pay_with_saved_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customer_id': customerId,
          'saved_card_id': cardId,
          'cvv': cvv,
          'amount': amount,
          'ride_id': rideId,
          'payment_type': paymentType,
        }),
      ).timeout(const Duration(seconds: 60));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('📥 Ödeme yanıtı: ${data['success']} - ${data['message']}');
        
        return {
          'success': data['success'] ?? false,
          'requires_3d': data['requires_3d'] ?? false,
          'acs_html': data['acs_html'],
          'payment_id': data['payment_id'],
          'transaction_id': data['transaction_id'],
          'message': data['message'] ?? 'Ödeme işlemi',
        };
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Ödeme hatası: $e');
      return null;
    }
  }
}
