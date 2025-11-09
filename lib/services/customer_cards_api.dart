import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// CUSTOMER CARDS API - Kayıtlı Kart Yönetimi
class CustomerCardsApi {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  // ==================== GET CARDS ====================
  Future<List<Map<String, dynamic>>> getCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Customer ID'yi farklı kaynaklardan al - STRING ÖNCE!
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
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        print('🔍 Session keys: ${prefs.getKeys()}');
        return [];
      }
      
      print('📋 Kartlar çekiliyor - Customer ID: $customerId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/customer_cards.php?customer_id=$customerId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> cardsJson = data['cards'] ?? [];
          final List<Map<String, dynamic>> cards = cardsJson
              .map((card) => Map<String, dynamic>.from(card))
              .toList();
          
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
  
  // ==================== ADD CARD ====================
  Future<Map<String, dynamic>?> addCard({
    required String cardNumber,
    required String cardHolder,
    required String expiryDate,
    required String cvv,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Customer ID'yi farklı kaynaklardan al - STRING ÖNCE!
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
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        print('🔍 Session keys: ${prefs.getKeys()}');
        return null;
      }
      
      print('💳 Yeni kart ekleniyor - Customer ID: $customerId');
      
      final requestBody = {
        'customer_id': customerId,
        'cardNumber': cardNumber,
        'cardHolder': cardHolder,
        'expiryDate': expiryDate,
        'cvv': cvv,
      };
      
      print('📤 Request body: ${json.encode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/customer_cards.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 10));
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          print('✅ Kart eklendi: ${data['card']['cardNumber']}');
          // Tüm response'u döndür (success dahil)
          return {
            'success': true,
            'card': data['card'],
            'message': data['message'],
          };
        } else {
          print('❌ API hatası: ${data['message']}');
          return null;
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
  
  // ==================== UPDATE CARD ====================
  Future<bool> updateCard({
    required int cardId,
    String? cardHolder,
    bool? setDefault,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Customer ID'yi farklı kaynaklardan al - STRING ÖNCE!
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
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return false;
      }
      
      print('🔄 Kart güncelleniyor - Card ID: $cardId');
      
      final body = <String, dynamic>{
        'customer_id': customerId,
        'cardId': cardId,
      };
      
      if (setDefault == true) {
        body['action'] = 'set_default';
      } else if (cardHolder != null) {
        body['action'] = 'update';
        body['cardHolder'] = cardHolder;
      }
      
      final response = await http.put(
        Uri.parse('$baseUrl/customer_cards.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          print('✅ Kart güncellendi');
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
      print('❌ Kart güncellenirken hata: $e');
      return false;
    }
  }
  
  // ==================== DELETE CARD ====================
  Future<bool> deleteCard(int cardId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Customer ID'yi farklı kaynaklardan al - STRING ÖNCE!
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
      
      if (customerId == null) {
        print('❌ Customer ID bulunamadı');
        return false;
      }
      
      print('🗑️ Kart siliniyor - Card ID: $cardId');
      
      final request = http.Request(
        'DELETE',
        Uri.parse('$baseUrl/customer_cards.php'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({
        'customer_id': customerId,
        'cardId': cardId,
      });
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);
      
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
}
