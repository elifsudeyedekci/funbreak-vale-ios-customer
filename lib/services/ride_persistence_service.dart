import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RidePersistenceService {
  static const String _activeRideKey = 'active_ride_data';
  static const String _rideStateKey = 'ride_state';
  
  // Aktif yolculuk durumunu kaydet
  static Future<void> saveActiveRide({
    required int rideId,
    required String status,
    required String pickupAddress,
    required String destinationAddress,
    required double estimatedPrice,
    required String driverName,
    required String driverPhone,
    required String driverId,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final rideData = {
        'ride_id': rideId,
        'status': status,
        'pickup_address': pickupAddress,
        'destination_address': destinationAddress,
        'estimated_price': estimatedPrice,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'driver_id': driverId,
        'saved_at': DateTime.now().toIso8601String(),
        'additional_data': additionalData ?? {},
      };
      
      await prefs.setString(_activeRideKey, jsonEncode(rideData));
      await prefs.setString(_rideStateKey, 'active');
      
      print('✅ Aktif yolculuk kaydedildi - Ride ID: $rideId, Status: $status');
    } catch (e) {
      print('❌ Yolculuk kaydetme hatası: $e');
    }
  }
  
  // Aktif yolculuk verilerini al
  static Future<Map<String, dynamic>?> getActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      final rideState = prefs.getString(_rideStateKey);
      
      if (rideDataJson != null && rideState == 'active') {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        
        // Kayıt tarihini kontrol et (24 saat eski ise sil)
        final savedAt = DateTime.parse(rideData['saved_at']);
        final now = DateTime.now();
        
        if (now.difference(savedAt).inHours > 24) {
          await clearActiveRide();
          print('⏰ Eski yolculuk verisi temizlendi (24 saat geçmiş)');
          return null;
        }
        
        print('📱 Aktif yolculuk bulundu - Ride ID: ${rideData['ride_id']}');
        return rideData;
      }
      
      return null;
    } catch (e) {
      print('❌ Aktif yolculuk alma hatası: $e');
      return null;
    }
  }
  
  // Yolculuk durumunu güncelle
  static Future<void> updateRideStatus(String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      
      if (rideDataJson != null) {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        rideData['status'] = newStatus;
        rideData['updated_at'] = DateTime.now().toIso8601String();
        
        await prefs.setString(_activeRideKey, jsonEncode(rideData));
        print('🔄 Yolculuk durumu güncellendi: $newStatus');
      }
    } catch (e) {
      print('❌ Durum güncelleme hatası: $e');
    }
  }
  
  // Aktif yolculuğu temizle
  static Future<void> clearActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeRideKey);
      await prefs.remove(_rideStateKey);
      
      print('🗑️ Aktif yolculuk verisi temizlendi');
    } catch (e) {
      print('❌ Yolculuk temizleme hatası: $e');
    }
  }
  
  // Yolculuk aktif mi kontrol et
  static Future<bool> hasActiveRide() async {
    final rideData = await getActiveRide();
    return rideData != null;
  }
  
  // Yolculuk ID'sini al
  static Future<int?> getActiveRideId() async {
    final rideData = await getActiveRide();
    return rideData != null ? rideData['ride_id'] as int : null;
  }
  
  // Crash recovery - uygulama açıldığında çağrılır
  static Future<bool> shouldRestoreRideScreen() async {
    try {
      final rideData = await getActiveRide();
      
      if (rideData != null) {
        final status = rideData['status'] as String;
        
        // Bu durumlarda yolculuk ekranını restore et
        final activeStatuses = [
          'accepted',
          'in_progress', 
          'driver_arrived',
          'ride_started',
          'waiting_customer'
        ];
        
        if (activeStatuses.contains(status)) {
          print('🔄 Yolculuk ekranı restore edilecek - Status: $status');
          return true;
        } else {
          // Tamamlanmış yolculuk varsa temizle
          await clearActiveRide();
          return false;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Restore kontrol hatası: $e');
      return false;
    }
  }
  
  // Ek yolculuk bilgilerini güncelle
  static Future<void> updateRideData(Map<String, dynamic> updates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      
      if (rideDataJson != null) {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        
        // Güncellemeleri uygula
        updates.forEach((key, value) {
          rideData[key] = value;
        });
        
        rideData['updated_at'] = DateTime.now().toIso8601String();
        
        await prefs.setString(_activeRideKey, jsonEncode(rideData));
        print('📝 Yolculuk verileri güncellendi: ${updates.keys.join(", ")}');
      }
    } catch (e) {
      print('❌ Veri güncelleme hatası: $e');
    }
  }
}
