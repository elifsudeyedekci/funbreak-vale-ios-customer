import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AdminManagementProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  // 2. Kullanıcı Yönetimi
  Future<List<Map<String, dynamic>>> getCustomerList() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_customers.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['customers']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Müşteri listesi getirme hatası: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDriverList() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_drivers.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['drivers']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Şoför listesi getirme hatası: $e');
      return [];
    }
  }

  Future<bool> blockUser(String userId, String userType, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/block_user.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': userType,
          'reason': reason,
          'blocked_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Kullanıcı engelleme hatası: $e');
      return false;
    }
  }

  // 3. Vale Talepleri Yönetimi
  Future<List<Map<String, dynamic>>> getActiveRideRequests() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_active_rides.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['rides']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Aktif talepler getirme hatası: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRideHistory({String? dateFrom, String? dateTo}) async {
    try {
      String url = '$baseUrl/get_ride_history.php';
      if (dateFrom != null && dateTo != null) {
        url += '?date_from=$dateFrom&date_to=$dateTo';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['rides']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Yolculuk geçmişi getirme hatası: $e');
      return [];
    }
  }

  Future<bool> cancelRide(String rideId, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancel_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'reason': reason,
          'cancelled_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Yolculuk iptal etme hatası: $e');
      return false;
    }
  }

  // 5. Hizmet Alanları
  Future<List<Map<String, dynamic>>> getServiceCities() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_service_cities.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['cities']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Hizmet şehirleri getirme hatası: $e');
      return [];
    }
  }

  Future<bool> updateServiceCity(Map<String, dynamic> cityData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_service_city.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(cityData),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Hizmet şehri güncelleme hatası: $e');
      return false;
    }
  }

  // 6. Bildirim Yönetimi
  Future<bool> sendPushNotification({
    required String title,
    required String message,
    required String targetType, // 'all', 'customers', 'drivers'
    String? userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'message': message,
          'target_type': targetType,
          'user_id': userId,
          'sent_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Bildirim gönderme hatası: $e');
      return false;
    }
  }

  // 7. Rapor ve İstatistikler
  Future<Map<String, dynamic>> getDailyEarnings(String date) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_daily_earnings.php?date=$date'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['earnings'];
        }
      }
      return {};
    } catch (e) {
      debugPrint('Günlük kazanç getirme hatası: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getDriverPerformance(String driverId, String dateFrom, String dateTo) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_driver_performance.php?driver_id=$driverId&date_from=$dateFrom&date_to=$dateTo'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['performance']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Şoför performans getirme hatası: $e');
      return [];
    }
  }

  // 8. Sistem Ayarları
  Future<Map<String, dynamic>> getAppSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_app_settings.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['settings'];
        }
      }
      return {};
    } catch (e) {
      debugPrint('Uygulama ayarları getirme hatası: $e');
      return {};
    }
  }

  Future<bool> updateAppSettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_app_settings.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settings),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Uygulama ayarları güncelleme hatası: $e');
      return false;
    }
  }

  // 9. İçerik Yönetimi
  Future<Map<String, dynamic>> getAppContent() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_app_content.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['content'];
        }
      }
      return {};
    } catch (e) {
      debugPrint('Uygulama içeriği getirme hatası: $e');
      return {};
    }
  }

  Future<bool> updateAppContent(Map<String, dynamic> content) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_app_content.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(content),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Uygulama içeriği güncelleme hatası: $e');
      return false;
    }
  }

  // 10. Güvenlik ve Denetim
  Future<List<Map<String, dynamic>>> getLoginLogs({String? userId, String? dateFrom}) async {
    try {
      String url = '$baseUrl/get_login_logs.php';
      List<String> params = [];
      
      if (userId != null) params.add('user_id=$userId');
      if (dateFrom != null) params.add('date_from=$dateFrom');
      
      if (params.isNotEmpty) {
        url += '?${params.join('&')}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['logs']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Giriş logları getirme hatası: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getErrorLogs({String? dateFrom}) async {
    try {
      String url = '$baseUrl/get_error_logs.php';
      if (dateFrom != null) {
        url += '?date_from=$dateFrom';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['logs']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Hata logları getirme hatası: $e');
      return [];
    }
  }
}
