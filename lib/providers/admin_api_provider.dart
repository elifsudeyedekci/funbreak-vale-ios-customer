import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminApiProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  // Kullanıcı kayıt
  Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'type': 'customer',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Başarılı kayıt
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Kullanıcı giriş
  Future<Map<String, dynamic>> loginCustomer({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'type': 'customer',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Şoför giriş
  Future<Map<String, dynamic>> loginDriver({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'type': 'driver',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Vale talebi oluştur
  Future<Map<String, dynamic>> createRideRequest({
    required String customerId,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String destinationAddress,
    required double destinationLat,
    required double destinationLng,
    required DateTime scheduledTime,
    required double estimatedPrice,
    required String paymentMethod,
  }) async {
    try {
      print('🚗 === CREATE RIDE REQUEST API ÇAĞRISI ===');
      print('🌐 URL: $baseUrl/create_ride_request.php');
      print('👤 Customer ID: ${int.tryParse(customerId) ?? 1}');
      print('📍 Pickup: $pickupAddress ($pickupLat, $pickupLng)');
      print('🎯 Destination: $destinationAddress ($destinationLat, $destinationLng)');
      print('💰 Price: ₺$estimatedPrice');
      print('💳 Payment: $paymentMethod');
      print('⏰ Time: ${scheduledTime.toIso8601String()}');
      
      final requestBody = {
        'customer_id': int.tryParse(customerId) ?? 1, // STRING'İ INTEGER'A ÇEVİR!
        'pickup_address': pickupAddress,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'destination_address': destinationAddress,
        'destination_lat': destinationLat,
        'destination_lng': destinationLng,
        'scheduled_time': scheduledTime.toIso8601String(),
        'estimated_price': estimatedPrice,
        'payment_method': paymentMethod,
        'request_type': 'immediate_or_soon', // REQUEST TYPE EKLENDİ!
      };
      
      print('📤 Request Body: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/create_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('📥 === API RESPONSE ===');
      print('📊 Status Code: ${response.statusCode}');
      print('📋 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ JSON Parse başarılı: ${data['success']}');
        return data;
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        return {'success': false, 'message': 'Sunucu hatası: ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Fiyatlandırma bilgilerini getir
  Future<Map<String, dynamic>> getPricingData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/pricing.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // MÜŞTERİ KAMPANYALARI ÇEK - GÜÇLENDİRİLMİŞ!
  Future<List<Map<String, dynamic>>> getCampaigns() async {
    try {
      print('🎯 Müşteri kampanyaları API çağrısı başlıyor...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_campaigns.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      print('Kampanya API çağrısı: $baseUrl/get_campaigns.php');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['campaigns'] is List) {
          final campaigns = List<Map<String, dynamic>>.from(data['campaigns']);
          // API'den gelen verileri UI formatına çevir
          final formattedCampaigns = campaigns.map((campaign) => {
            'title': campaign['title'] ?? 'Kampanya',
            'subtitle': campaign['description'] ?? campaign['message'] ?? '',
            'date': campaign['created_at'] ?? '',
            'id': campaign['id'],
            'discount_code': campaign['discount_code'] ?? '',
            'discount_percentage': campaign['discount_percentage'] ?? 0,
            'start_date': campaign['start_date'] ?? '',
            'end_date': campaign['end_date'] ?? '',
            'type': 'campaign',
          }).toList();
          
          print('✅ Müşteri kampanyaları: ${formattedCampaigns.length} adet');
          return formattedCampaigns;
        } else {
          print('⚠️ Kampanya API yanıtı: ${data['message']}');
          return [];
        }
      } else {
        print('❌ Kampanya API hatası: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Müşteri kampanya çekme hatası: $e');
      debugPrint('Kampanya getirme hatası: $e');
      return [];
    }
  }

  // MÜŞTERİ DUYURULARI + PUSH NOTIFICATIONS ÇEK - GÜÇLENDİRİLMİŞ!
  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    try {
      print('📢 Müşteri duyuruları + push notifications API çağrısı başlıyor...');
      
      // 1. Customer announcements çek
      final response1 = await http.get(
        Uri.parse('$baseUrl/get_announcements.php?type=customer'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      // 2. Push notifications çek (customers için)
      final response2 = await http.get(
        Uri.parse('$baseUrl/get_push_notifications.php?target=customers'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      List<Map<String, dynamic>> allAnnouncements = [];
      
      // Customer announcements ekle
      if (response1.statusCode == 200) {
        final data1 = jsonDecode(response1.body);
        if (data1['success'] == true && data1['announcements'] is List) {
          final customerAnnouncements = (data1['announcements'] as List)
              .map((item) => {
                'title': item['title'] ?? 'Duyuru',
                'subtitle': item['message'] ?? '',
                'date': item['created_at'] ?? '',
                'id': item['id'],
                'type': 'announcement',
              }).toList();
          allAnnouncements.addAll(customerAnnouncements);
          print('✅ Customer announcements: ${customerAnnouncements.length} adet');
        }
      }
      
      // Push notifications ekle  
      if (response2.statusCode == 200) {
        final data2 = jsonDecode(response2.body);
        if (data2['success'] == true && data2['notifications'] is List) {
          final pushNotifications = (data2['notifications'] as List)
              .map((item) => {
                'title': item['title'] ?? 'Push Notification',
                'subtitle': item['message'] ?? '',
                'date': item['created_at'] ?? '',
                'id': item['id'],
                'type': 'push', // Push notification işareti
              }).toList();
          allAnnouncements.addAll(pushNotifications);
          print('✅ Push notifications: ${pushNotifications.length} adet');
        }
      }
      
      // Tarihe göre sırala (en yeni üstte)
      allAnnouncements.sort((a, b) {
        final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
      
      print('📢 Toplam müşteri duyuru + push: ${allAnnouncements.length} adet');
      return allAnnouncements;
      
    } catch (e) {
      print('❌ Müşteri duyuru çekme hatası: $e');
      debugPrint('Duyuru getirme hatası: $e');
      return [];
    }
  }

  // Kullanıcı oturum bilgilerini kaydet
  Future<void> _saveUserSession(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user['id'].toString());
    await prefs.setString('user_name', user['name']);
    await prefs.setString('user_email', user['email']);
    await prefs.setString('user_phone', user['phone'] ?? '');
    await prefs.setBool('is_logged_in', true);
  }

  // Oturum temizle
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Mevcut kullanıcı bilgilerini getir
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    
    if (!isLoggedIn) return null;
    
    return {
      'id': prefs.getString('user_id'),
      'name': prefs.getString('user_name'),
      'email': prefs.getString('user_email'),
      'phone': prefs.getString('user_phone'),
    };
  }

  // BEKLEYEN ÖDEME KONTROL SİSTEMİ - KRİTİK API!
  Future<Map<String, dynamic>> checkPendingPayments(String customerId) async {
    try {
      print('💳 API çağrısı: Bekleyen ödeme kontrol - müşteri: $customerId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/check_pending_payments.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // DEBUG: Response body kontrol - HTTP 500 debug!
        print('💳 Pending Payment Response Body: ${response.body}');
        
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final pendingAmount = (data['pending_amount'] ?? 0.0).toDouble();
          final rideCount = data['pending_rides_count'] ?? 0;
          
          print('✅ Bekleyen ödeme API başarılı: ₺$pendingAmount ($rideCount yolculuk)');
          
          return {
            'success': true,
            'pending_amount': pendingAmount,
            'pending_rides_count': rideCount,
            'pending_rides': data['pending_rides'] ?? [],
          };
        } else {
          print('⚠️ API yanıtı: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Bekleyen ödeme kontrol edilemedi',
            'pending_amount': 0.0,
          };
        }
      } else {
        print('❌ HTTP Hatası: ${response.statusCode}');
        print('❌ HTTP Error Response Body: ${response.body}');
        return {
          'success': false,
          'message': 'Sunucu hatası (${response.statusCode})',
          'pending_amount': 0.0,
        };
      }
    } catch (e) {
      print('❌ Bekleyen ödeme API hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
        'pending_amount': 0.0,
      };
    }
  }

  // BEKLEYEN ÖDEME LİSTESİ ALMA
  Future<Map<String, dynamic>> getPendingPaymentsList(String customerId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/get_pending_payments.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // ÖDEME TAMAMLAMA
  Future<Map<String, dynamic>> completePayment({
    required String customerId,
    required String rideId,
    required double amount,
    required String paymentMethod,
    String? discountCode,
    double? discountAmount,
  }) async {
    try {
      print('💳 ==========================================');
      print('💳 ÖDEME TAMAMLAMA API ÇAĞRISI');
      print('💳 ==========================================');
      print('👤 Customer ID: $customerId');
      print('🚗 Ride ID: $rideId');
      print('💰 Amount: ₺$amount');
      print('💳 PAYMENT METHOD (ÇOK ÖNEMLİ!): "$paymentMethod"');
      if (discountCode != null && discountAmount != null && discountAmount > 0) {
        print('🎁 DISCOUNT CODE: $discountCode, İndirim: ₺$discountAmount');
      }
      print('🌐 URL: $baseUrl/complete_payment.php');
      print('💳 ==========================================');
      
      final requestBody = {
        'customer_id': customerId,
        'ride_id': rideId,
        'amount': amount,
        'payment_method': paymentMethod,
      };
      
      // 🎁 İndirim varsa ekle
      if (discountCode != null && discountAmount != null && discountAmount > 0) {
        requestBody['discount_code'] = discountCode;
        requestBody['discount_amount'] = discountAmount;
      }
      
      print('📤 Request Body: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/complete_payment.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      print('📥 Response Status: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          print('✅ Ödeme başarıyla tamamlandı: ₺$amount, Method: $paymentMethod');
        } else {
          print('❌ Ödeme başarısız: ${data['message']}');
        }
        
        return data;
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      print('❌ Ödeme API hatası: $e');
      return {'success': false, 'message': 'Ödeme hatası: $e'};
    }
  }

  // ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEK - MANUEL VALE SEÇİMİ İÇİN!
  Future<Map<String, dynamic>> getOnlineDrivers({
    double? pickupLat,
    double? pickupLng,
    double maxDistance = 50.0,
  }) async {
    try {
      print('🚗 API çağrısı: Çevrimiçi sürücüler çekiliyor...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/get_online_drivers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_lat': pickupLat, // BACKEND UYUMLU PARAMETRE!
          'customer_lng': pickupLng, // BACKEND UYUMLU PARAMETRE!
          'pickup_lat': pickupLat, // Eski uyumluluk için
          'pickup_lng': pickupLng, // Eski uyumluluk için
          'max_distance': maxDistance,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // DEBUG: Response body uzunluğunu kontrol et - RangeError çözümü!
        print('📤 Response Body Uzunluk: ${response.body.length} karakter');
        print('📤 Response Body İlk 100 karakter: ${response.body.length > 100 ? response.body.substring(0, 100) : response.body}...');
        
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final drivers = data['drivers'] as List? ?? [];
          print('✅ Çevrimiçi sürücü API başarılı: ${drivers.length} sürücü');
          
          return {
            'success': true,
            'drivers': drivers,
            'total_count': drivers.length,
          };
        } else {
          print('⚠️ API yanıtı: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Çevrimiçi sürücü bulunamadı',
            'drivers': [],
          };
        }
      } else {
        print('❌ getOnlineDrivers HTTP Hatası: ${response.statusCode}');
        print('❌ getOnlineDrivers Error Response Body: ${response.body}');
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
          'drivers': [],
        };
      }
    } catch (e) {
      print('❌ getOnlineDrivers Exception: $e');
      print('❌ Exception Type: ${e.runtimeType}');
      if (e is RangeError) {
        print('❌ RangeError Details: start=${e.start}, end=${e.end}');
        print('❌ RangeError Name: ${e.name}, Message: ${e.message}');
      }
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
        'drivers': [],
      };
    }
  }

  // TALEP İPTAL SİSTEMİ - VALE BULUNAMADI İÇİN!
  Future<Map<String, dynamic>> cancelRideRequest({
    required String customerId,
    String reason = 'no_driver_found',
  }) async {
    try {
      print('🚫 Talep iptal ediliyor - müşteri: $customerId, sebep: $reason');
      
      final response = await http.post(
        Uri.parse('$baseUrl/cancel_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'reason': reason,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final cancelledCount = data['cancelled_count'] ?? 0;
          print('✅ Talep iptal başarılı: $cancelledCount talep cancelled');
          
          return {
            'success': true,
            'cancelled_count': cancelledCount,
            'message': data['message'] ?? 'Talep iptal edildi',
          };
        } else {
          print('⚠️ Talep iptal yanıtı: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Talep iptal edilemedi',
            'cancelled_count': 0,
          };
        }
      } else {
        print('❌ Talep iptal HTTP hatası: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
          'cancelled_count': 0,
        };
      }
    } catch (e) {
      print('❌ Talep iptal API hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
        'cancelled_count': 0,
      };
    }
  }

  // KAPSAMLI PROVİZYON YÖNETİM SİSTEMİ!
  Future<Map<String, dynamic>> processProvision({
    required String customerId,
    required String rideId,
    required double provisionAmount,
    required String action, // 'charge', 'refund', 'cancel'
    String paymentMethod = 'card',
  }) async {
    try {
      print('💳 Provizyon işlemi başlıyor - Action: $action, Tutar: ₺$provisionAmount');
      
      final response = await http.post(
        Uri.parse('$baseUrl/process_provision.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'ride_id': rideId,
          'provision_amount': provisionAmount,
          'payment_method': paymentMethod,
          'action': action,
        }),
      ).timeout(const Duration(seconds: 15));

      print('💳 Provizyon Response Status: ${response.statusCode}');
      print('💳 Provizyon Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final message = data['message'] ?? 'Provizyon işlemi tamamlandı';
          print('✅ Provizyon başarılı: $message');
          
          return {
            'success': true,
            'message': message,
            'provision_id': data['provision_id'],
            'action': data['action'],
            'amount': data['amount'],
            'existing_provision': data['existing_provision'],
          };
        } else {
          print('⚠️ Provizyon API yanıtı: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Provizyon işlemi başarısız',
          };
        }
      } else {
        print('❌ Provizyon HTTP hatası: ${response.statusCode}');
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ Provizyon API hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  // SİSTEM AYARLARI - DESTEK BİLGİLERİ ENTEGRAYSyONU!
  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      );

      print('Sistem ayarları API çağrısı: $baseUrl/get_system_settings.php');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['settings'] ?? {};
        }
      }
      
      // Fallback ayarlar
      return {
        'app_name': 'FunBreak Vale',
        'support_phone': '+90 555 123 4567',
        'support_email': 'destek@funbreakvale.com',
        'support_whatsapp': '+90 555 123 4567',
      };
    } catch (e) {
      debugPrint('Sistem ayarları getirme hatası: $e');
      
      // Fallback ayarlar
      return {
        'app_name': 'FunBreak Vale',
        'support_phone': '+90 555 123 4567',
        'support_email': 'destek@funbreakvale.com',
        'support_whatsapp': '+90 555 123 4567',
      };
    }
  }

  // 🚀 SERVER SAATİ AL - PHONE TIMEZONE BYPASS!
  Future<DateTime> getServerTime() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_server_time.php'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Backend'den gelen format: "2025-11-11 22:54:29" veya ISO8601
          final serverTimeStr = data['iso8601'] ?? data['server_time'];
          debugPrint('✅ Server saati alındı: $serverTimeStr');
          return DateTime.parse(serverTimeStr);
        }
      }
      
      debugPrint('⚠️ Server saati alınamadı, phone saati kullanılıyor');
      return DateTime.now();
    } catch (e) {
      debugPrint('❌ Server saati hatası: $e, phone saati kullanılıyor');
      return DateTime.now();
    }
  }

  // ✅ MÜŞTERİ PROFİL GÜNCELLEME - PANEL SENKRONİZASYONU!
  Future<Map<String, dynamic>> updateCustomerProfile({
    required String customerId,
    required String name,
    required String phone,
    required String email,
    String vehicleMake = '',
    String vehicleModel = '',
    String vehicleColor = '',
    String vehiclePlate = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_customer_profile.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'name': name,
          'phone': phone,
          'email': email,
          'vehicle_make': vehicleMake,
          'vehicle_model': vehicleModel,
          'vehicle_color': vehicleColor,
          'vehicle_plate': vehiclePlate,
        }),
      );

      debugPrint('📝 Profil güncelleme API: ${response.statusCode}');
      debugPrint('📝 Response: ${response.body}');

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
      debugPrint('❌ Profil güncelleme hatası: $e');
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

}
