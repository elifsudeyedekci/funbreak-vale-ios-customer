import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/payment_config.dart'; // 🔧 Kart ödemesi aç/kapa flag'i

class RideService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  // Talep oluşturma - BACKEND UYUMLU PARAMETREler!
  static Future<Map<String, dynamic>> createRideRequest({
    required int customerId,
    required String pickupLocation,
    required String destination,
    String serviceType = 'vale',
    String requestType = 'immediate_or_soon',
    String? scheduledDateTime,
    int? selectedDriverId,
    double? estimatedPrice,
    String? discountCode,
    double? pickupLat,
    double? pickupLng,
    double? destinationLat,
    double? destinationLng,
    List<Map<String, dynamic>>? waypoints, // 🔥 ARA DURAKLAR
  }) async {
    try {
      print('🚗 RideService createRideRequest parametreleri:');
      print('   👤 Customer: $customerId');
      print('   📍 Pickup: $pickupLocation ($pickupLat, $pickupLng)');
      print('   🎯 Destination: $destination ($destinationLat, $destinationLng)');
      print('   🛣️  Waypoints: ${waypoints?.length ?? 0} durak');
      print('   💰 Price: $estimatedPrice');
      print('🔗 API URL: $baseUrl/create_ride_request.php');
      
      // ⚠️ scheduledDateTime formatını düzelt - Backend "YYYY-MM-DD HH:MM:SS" bekliyor!
      String? formattedScheduledTime = scheduledDateTime;
      if (scheduledDateTime != null && scheduledDateTime.isNotEmpty) {
        try {
          // ISO8601 formatından ("2025-11-27T04:50:09.000558Z") -> "2025-11-27 04:50:09"
          final dt = DateTime.parse(scheduledDateTime);
          formattedScheduledTime = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
          print('📅 Scheduled time formatted: $scheduledDateTime -> $formattedScheduledTime');
        } catch (e) {
          print('⚠️ Scheduled time format hatası: $e - Orijinal değer kullanılıyor');
        }
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/create_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          // ESKİ SİSTEM PARAMETRELERİ - AKILLI ENTEGRASYONu İÇİNDE
          'customer_id': customerId,
          'pickup_address': pickupLocation,
          'destination_address': destination,  
          'pickup_lat': pickupLat ?? 0.0,
          'pickup_lng': pickupLng ?? 0.0,
          'destination_lat': destinationLat ?? 0.0,
          'destination_lng': destinationLng ?? 0.0,
          'waypoints': waypoints ?? [], // 🔥 ARA DURAKLAR
          'scheduled_time': formattedScheduledTime, // ✅ Backend uyumlu format!
          'estimated_price': estimatedPrice ?? 0.0,
          'payment_method': kDefaultPaymentMethod,
          'request_type': requestType,
          'ride_type': serviceType,
          'selected_driver_id': selectedDriverId,
          'discount_code': discountCode,
          'notes': '',
        }),
      );

      print('🚗 CREATE RIDE REQUEST RESPONSE: ${response.statusCode}');
      print('🚗 RESPONSE BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ TALEP BAŞARIYLA OLUŞTURULDU: ${data['ride_id']} (AKILLI SİSTEM İÇİNDE)');
          
          // AKILLI SİSTEM ARKAPLANDA OTOMATİK BAŞLATILDI!
          // create_ride_request.php içinde 15sn 10km → 15sn 100km otomatik çalışacak
          
          return data;
        } else {
          throw Exception(data['message'] ?? 'Talep oluşturulamadı');
        }
      } else {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ RIDE REQUEST ERROR: $e');
      throw Exception('Talep oluşturma hatası: $e');
    }
  }
  
  // ESKİ BİLDİRİM SİSTEMİ - AKILLI ENTEGRASYON ARKAPLANDA ÇALIŞACAK
  static Future<void> _notifyDrivers(int rideId, String serviceType, String pickupLocation) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notify_drivers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'service_type': serviceType,
          'pickup_location': pickupLocation,
        }),
      );

      print('📨 DRIVER NOTIFICATION RESPONSE: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📨 DRIVERS NOTIFIED: ${data['notified_drivers']} sürücüye bildirim gönderildi');
      }
    } catch (e) {
      print('❌ DRIVER NOTIFICATION ERROR: $e');
    }
  }
  
  // Çevrimiçi sürücüleri getir - GELİŞTİRİLMİŞ VERSİYON!
  static Future<List<Map<String, dynamic>>> getOnlineDrivers({
    double? pickupLat,
    double? pickupLng,
    double maxDistance = 50.0,
  }) async {
    try {
      print('🚗 API çağrısı: Çevrimiçi sürücüler çekiliyor...');
      print('   Pickup konum: ${pickupLat?.toStringAsFixed(6)}, ${pickupLng?.toStringAsFixed(6)}');
      print('   Max mesafe: ${maxDistance}km');
      
      final response = await http.post(
        Uri.parse('$baseUrl/get_online_drivers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng, 
          'max_distance': maxDistance,
        }),
      ).timeout(const Duration(seconds: 15));

      print('🚗 Response status: ${response.statusCode}');
      print('🚗 Response body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final drivers = List<Map<String, dynamic>>.from(data['drivers'] ?? []);
          print('✅ ${drivers.length} çevrimiçi sürücü bulundu!');
          
          // Debug: Her sürücüyü logla
          for (int i = 0; i < drivers.length && i < 3; i++) {
            final driver = drivers[i];
            print('   Sürücü ${i+1}: ${driver['name']} ${driver['surname']} - ${driver['distance']?.toStringAsFixed(1)}km');
          }
          
          return drivers;
        } else {
          print('❌ API yanıt: ${data['message'] ?? 'Bilinmeyen hata'}');
          return [];
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ GET ONLINE DRIVERS ERROR: $e');
      return [];
    }
  }
  
  // Talep durumunu kontrol et
  static Future<Map<String, dynamic>?> checkRideStatus(int rideId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check_ride_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ride_id': rideId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['ride'];
        }
      }
      return null;
    } catch (e) {
      print('❌ CHECK RIDE STATUS ERROR: $e');
      return null;
    }
  }
  
  // Talebi iptal et
  static Future<bool> cancelRideRequest(int rideId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/cancel_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ride_id': rideId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ CANCEL RIDE ERROR: $e');
      return false;
    }
  }
}
