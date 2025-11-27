import 'dart:convert';
import 'package:http/http.dart' as http;

/// VakıfBank Sanal POS Ödeme Servisi
/// FunBreak Vale - Müşteri Uygulaması
///
/// @version 1.0.0
/// @date 2025-11-27

class PaymentService {
  static const String _baseUrl = 'https://admin.funbreakvale.com/api/payment';

  /// 3D Secure ödeme başlatır
  /// 
  /// Returns: {success, requires_3d, acs_html, payment_id, transaction_id, message}
  static Future<Map<String, dynamic>> initiate3DPayment({
    required int rideId,
    required int customerId,
    required double amount,
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    required String cardHolder,
    String paymentType = 'ride_payment', // ride_payment, cancellation_fee
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/initiate_3d_payment.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'customer_id': customerId,
          'amount': amount,
          'card_number': cardNumber.replaceAll(' ', ''),
          'expiry_month': expiryMonth,
          'expiry_year': expiryYear,
          'cvv': cvv,
          'card_holder': cardHolder,
          'payment_type': paymentType,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.initiate3DPayment hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Ödeme durumunu sorgular
  static Future<Map<String, dynamic>> getPaymentStatus({
    int? paymentId,
    String? transactionId,
    int? rideId,
  }) async {
    try {
      final params = <String, String>{};
      if (paymentId != null) params['payment_id'] = paymentId.toString();
      if (transactionId != null) params['transaction_id'] = transactionId;
      if (rideId != null) params['ride_id'] = rideId.toString();

      final uri = Uri.parse('$_baseUrl/get_payment_status.php')
          .replace(queryParameters: params);

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.getPaymentStatus hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Kart numarasını formatlar (4'lü gruplar)
  static String formatCardNumber(String cardNumber) {
    cardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < cardNumber.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(cardNumber[i]);
    }
    return buffer.toString();
  }

  /// Kart tipini belirler
  static String detectCardType(String cardNumber) {
    cardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    
    if (cardNumber.isEmpty) return 'unknown';
    
    // TROY (9792 ile başlar)
    if (cardNumber.startsWith('9792')) {
      return 'troy';
    }
    
    // Visa (4 ile başlar)
    if (cardNumber.startsWith('4')) {
      return 'visa';
    }
    
    // MasterCard (51-55 veya 2221-2720 ile başlar)
    if (cardNumber.length >= 2) {
      final firstTwo = int.tryParse(cardNumber.substring(0, 2)) ?? 0;
      if (firstTwo >= 51 && firstTwo <= 55) {
        return 'mastercard';
      }
    }
    
    if (cardNumber.length >= 4) {
      final firstFour = int.tryParse(cardNumber.substring(0, 4)) ?? 0;
      if (firstFour >= 2221 && firstFour <= 2720) {
        return 'mastercard';
      }
    }
    
    return 'unknown';
  }

  /// Kart numarası geçerli mi kontrol eder (Luhn algoritması)
  static bool isValidCardNumber(String cardNumber) {
    cardNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    
    if (cardNumber.length < 13 || cardNumber.length > 19) {
      return false;
    }
    
    // Luhn algoritması
    int sum = 0;
    bool alternate = false;
    
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  /// CVV geçerli mi kontrol eder
  static bool isValidCvv(String cvv) {
    cvv = cvv.replaceAll(RegExp(r'\D'), '');
    return cvv.length >= 3 && cvv.length <= 4;
  }

  /// Son kullanma tarihi geçerli mi kontrol eder
  static bool isValidExpiry(String month, String year) {
    try {
      final now = DateTime.now();
      int m = int.parse(month);
      int y = int.parse(year);
      
      if (y < 100) {
        y += 2000; // 25 -> 2025
      }
      
      if (m < 1 || m > 12) {
        return false;
      }
      
      // Son gün hesapla
      final expiry = DateTime(y, m + 1, 0); // Ayın son günü
      
      return expiry.isAfter(now);
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // KAYITLI KART İŞLEMLERİ
  // ═══════════════════════════════════════════════════════════════

  /// Yeni kart doğrulama ve kaydetme (0.01 TL çekip iade eder)
  /// 
  /// Returns: {success, requires_3d, verification_id, acs_html, message}
  static Future<Map<String, dynamic>> verifyAndSaveCard({
    required int customerId,
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
    required String cardHolder,
    String cardAlias = '',
  }) async {
    try {
      print('💳 [KART DOĞRULAMA] Başlatılıyor - Customer: $customerId');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/verify_and_save_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'card_number': cardNumber.replaceAll(' ', ''),
          'expiry_month': expiryMonth,
          'expiry_year': expiryYear,
          'cvv': cvv,
          'card_holder': cardHolder,
          'card_alias': cardAlias,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('💳 [KART DOĞRULAMA] Yanıt: ${data['success']} - ${data['message']}');
        return data;
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.verifyAndSaveCard hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Kayıtlı kartlarla ödeme yapar
  /// 
  /// Returns: {success, requires_3d, payment_id, acs_html, message}
  static Future<Map<String, dynamic>> payWithSavedCard({
    required int customerId,
    required int savedCardId,
    required String cvv,
    required double amount,
    required int rideId,
    String paymentType = 'ride_payment',
  }) async {
    try {
      print('💳 [KAYITLI KART ÖDEME] Başlatılıyor - Card: $savedCardId, Ride: $rideId, Amount: $amount');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/pay_with_saved_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'saved_card_id': savedCardId,
          'cvv': cvv,
          'amount': amount,
          'ride_id': rideId,
          'payment_type': paymentType,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('💳 [KAYITLI KART ÖDEME] Yanıt: ${data['success']} - ${data['message']}');
        return data;
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.payWithSavedCard hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Müşterinin kayıtlı kartlarını getirir
  static Future<Map<String, dynamic>> getSavedCards({
    required int customerId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/get_saved_cards.php?customer_id=$customerId'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'cards': [],
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.getSavedCards hatası: $e');
      return {
        'success': false,
        'cards': [],
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Kayıtlı kartı siler
  static Future<Map<String, dynamic>> deleteSavedCard({
    required int customerId,
    required int cardId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/delete_saved_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'card_id': cardId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.deleteSavedCard hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Varsayılan kartı ayarlar
  static Future<Map<String, dynamic>> setDefaultCard({
    required int customerId,
    required int cardId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/set_default_card.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'card_id': cardId,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ PaymentService.setDefaultCard hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }
}

