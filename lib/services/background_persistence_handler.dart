import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'ride_persistence_service.dart';

class BackgroundPersistenceHandler {
  // Firebase background message ile persistence güncelleme
  static Future<void> handleBackgroundPersistence(RemoteMessage message) async {
    try {
      print('💾 [MÜŞTERİ] Background persistence handler tetiklendi');
      
      if (message.data['type'] == 'persistence_save') {
        // Backend'den persistence save komutu geldi
        await _savePersistenceFromMessage(message);
        
      } else if (message.data['type'] == 'ride_status_change') {
        // Yolculuk durumu değişti
        final newStatus = message.data['new_status'] ?? '';
        if (newStatus.isNotEmpty) {
          await RidePersistenceService.updateRideStatus(newStatus);
          print('🔄 [MÜŞTERİ] Background persistence status güncellendi: $newStatus');
        }
        
        // Yolculuk bittiyse temizle
        if (newStatus == 'completed' || newStatus == 'cancelled') {
          await RidePersistenceService.clearActiveRide();
          print('🗑️ [MÜŞTERİ] Background persistence temizlendi');
        }
      }
      
    } catch (e) {
      print('❌ [MÜŞTERİ] Background persistence handler hatası: $e');
    }
  }
  
  static Future<void> _savePersistenceFromMessage(RemoteMessage message) async {
    try {
      final data = message.data;
      
      await RidePersistenceService.saveActiveRide(
        rideId: int.tryParse(data['ride_id'] ?? '0') ?? 0,
        status: data['ride_status'] ?? 'accepted',
        pickupAddress: data['pickup_address'] ?? '',
        destinationAddress: data['destination_address'] ?? '',
        estimatedPrice: double.tryParse(data['estimated_price'] ?? '0') ?? 0.0,
        driverName: data['driver_name'] ?? 'Şoför',
        driverPhone: data['driver_phone'] ?? '',
        driverId: data['driver_id'] ?? '0',
      );
      
      print('💾 [MÜŞTERİ] Background persistence Firebase'den kaydedildi');
      
    } catch (e) {
      print('❌ [MÜŞTERİ] Background persistence save hatası: $e');
    }
  }
}
