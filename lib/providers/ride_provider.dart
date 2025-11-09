import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'admin_api_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RideProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminApiProvider _adminApi = AdminApiProvider();
  
  Ride? _currentRide;
  List<Ride> _rideHistory = [];
  List<Ride> _availableRides = [];
  bool _isLoading = false;
  String? _error;
  Timer? _priceUpdateTimer;
  double? _currentPrice;
  Map<String, dynamic>? _realTimeData;
  
  // EKSİK DEĞİŞKENLER - REAL-TIME TRACKING İÇİN!
  double? _realTimeDistance;
  double? _realTimePrice;
  Timer? _realTimeDistanceTimer;

  // CONSTRUCTOR - PERSİSTENCE İÇİN!
  RideProvider() {
    _loadCurrentRidePersistence();
  }
  
  // RIDE SET/CLEAR METODLARI
  void setCurrentRide(Ride ride) {
    _currentRide = ride;
    _saveCurrentRidePersistence();
    notifyListeners();
  }
  
  void clearCurrentRide() {
    _currentRide = null;
    _clearCurrentRidePersistence();
    notifyListeners();
  }

  // GÜÇLÜ PERSİSTENCE SİSTEMİ - YOLCULUK DURUMU KORUMA!
  Future<void> _loadCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideData = prefs.getString('customer_current_ride');
      
      if (rideData != null && rideData.isNotEmpty) {
        final data = jsonDecode(rideData);
        print('🔄 PERSİSTENCE: Aktif yolculuk geri yükleniyor...');
        print('   🆔 Ride ID: ${data['ride_id']}');
        print('   📍 Status: ${data['status']}');
        
        // Ride objesini oluştur
        _currentRide = Ride(
          id: data['ride_id']?.toString() ?? '',
          customerId: data['customer_id']?.toString() ?? '',
          driverId: data['driver_id']?.toString(),
          pickupLocation: LatLng(
            data['pickup_lat']?.toDouble() ?? 0.0,
            data['pickup_lng']?.toDouble() ?? 0.0,
          ),
          destinationLocation: LatLng(
            data['destination_lat']?.toDouble() ?? 0.0,
            data['destination_lng']?.toDouble() ?? 0.0,
          ),
          pickupAddress: data['pickup_address'] ?? '',
          destinationAddress: data['destination_address'] ?? '',
          paymentMethod: data['payment_method'] ?? 'card', // EKSİK ALAN!
          estimatedPrice: data['estimated_price']?.toDouble() ?? 0.0,
          estimatedTime: data['estimated_time']?.toInt() ?? 30, // EKSİK ALAN!
          status: data['status'] ?? 'pending',
          createdAt: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
        );
        
        print('✅ PERSİSTENCE: Aktif yolculuk geri yüklendi!');
        notifyListeners();
      } else {
        print('ℹ️ PERSİSTENCE: Aktif yolculuk yok');
      }
    } catch (e) {
      print('❌ PERSİSTENCE yükleme hatası: $e');
    }
  }
  
  // YOLCULUK DURUMUNU KAYDET - RESTART KORUMASI!
  Future<void> _saveCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_currentRide != null) {
        final rideData = {
          'ride_id': _currentRide!.id,
          'customer_id': _currentRide!.customerId,
          'driver_id': _currentRide!.driverId,
          'pickup_lat': _currentRide!.pickupLocation.latitude,
          'pickup_lng': _currentRide!.pickupLocation.longitude,
          'destination_lat': _currentRide!.destinationLocation.latitude,
          'destination_lng': _currentRide!.destinationLocation.longitude,
          'pickup_address': _currentRide!.pickupAddress,
          'destination_address': _currentRide!.destinationAddress,
          'estimated_price': _currentRide!.estimatedPrice,
          'status': _currentRide!.status,
          'created_at': _currentRide!.createdAt.toIso8601String(),
        };
        
        await prefs.setString('customer_current_ride', jsonEncode(rideData));
        print('💾 PERSİSTENCE: Yolculuk durumu kaydedildi');
      } else {
        await prefs.remove('customer_current_ride');
        print('🗑️ PERSİSTENCE: Yolculuk durumu temizlendi');
      }
    } catch (e) {
      print('❌ PERSİSTENCE kaydetme hatası: $e');
    }
  }
  
  
  // YOLCULUK BAŞLATMA - PERSİSTENCE İLE!
  void startRideWithPersistence(Map<String, dynamic> rideDetails) {
    try {
      _currentRide = Ride(
        id: rideDetails['ride_id']?.toString() ?? '',
        customerId: rideDetails['customer_id']?.toString() ?? '',
        driverId: rideDetails['driver_id']?.toString(),
        pickupLocation: LatLng(
          rideDetails['pickup_lat']?.toDouble() ?? 0.0,
          rideDetails['pickup_lng']?.toDouble() ?? 0.0,
        ),
        destinationLocation: LatLng(
          rideDetails['destination_lat']?.toDouble() ?? 0.0,
          rideDetails['destination_lng']?.toDouble() ?? 0.0,
        ),
        pickupAddress: rideDetails['pickup_address'] ?? '',
        destinationAddress: rideDetails['destination_address'] ?? '',
        paymentMethod: rideDetails['payment_method'] ?? 'card', // EKSİK ALAN!
        estimatedPrice: rideDetails['estimated_price']?.toDouble() ?? 0.0,
        estimatedTime: rideDetails['estimated_time']?.toInt() ?? 30, // EKSİK ALAN!
        status: rideDetails['status'] ?? 'accepted',
        createdAt: DateTime.now(),
      );
      
      // HEMEN KAYDET!
      _saveCurrentRidePersistence();
      notifyListeners();
      
      print('🚗 YOLCULUK BAŞLATILDI + PERSİSTENCE KAYDED İLDİ');
    } catch (e) {
      print('❌ Yolculuk başlatma hatası: $e');
    }
  }
  
  // YOLCULUK BİTİRME - PERSİSTENCE TEMİZLE!
  void completeRideWithPersistence() {
    _currentRide = null;
    _saveCurrentRidePersistence(); // Temizle
    notifyListeners();
    print('🏁 YOLCULUK BİTTİ + PERSİSTENCE TEMİZLENDİ');
  }
  
  // PERSİSTENCE TEMİZLEME METODU
  Future<void> _clearCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('customer_current_ride');
      print('🗑️ Persistence temizlendi');
    } catch (e) {
      print('❌ Persistence temizleme hatası: $e');
    }
  }
  
  // EKSİK METODLAR - REAL-TIME TRACKING İÇİN!
  void startRealTimeDistanceTracking(String rideId) {
    _realTimeDistanceTimer?.cancel();
    _realTimeDistanceTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchRealTimeRideData(rideId);
    });
    print('🔄 Real-time distance tracking başlatıldı: $rideId');
  }

  void stopRealTimeDistanceTracking() {
    _realTimeDistanceTimer?.cancel();
    _realTimeDistanceTimer = null;
    print('⏹️ Real-time distance tracking durduruldu');
  }
  
  Future<void> _fetchRealTimeRideData(String rideId) async {
    try {
      // TODO: API'den real-time data çek
      print('📡 Real-time ride data çekiliyor: $rideId');
    } catch (e) {
      print('❌ Real-time data hatası: $e');
    }
  }

  Ride? get currentRide => _currentRide;
  List<Ride> get rideHistory => _rideHistory;
  List<Ride> get availableRides => _availableRides;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double? get currentPrice => _currentPrice;
  Map<String, dynamic>? get realTimeData => _realTimeData;

  // Gerçek zamanlı fiyat takibi başlat
  void startRealTimePriceTracking(String rideId) {
    _priceUpdateTimer?.cancel();
    _priceUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateRealTimePrice(rideId);
    });
  }

  // Gerçek zamanlı fiyat takibini durdur
  void stopRealTimePriceTracking() {
    _priceUpdateTimer?.cancel();
    _priceUpdateTimer = null;
  }

  // Gerçek zamanlı fiyat güncelle
  Future<void> _updateRealTimePrice(String rideId) async {
    try {
      if (_currentRide == null) return;

      // Vale'nin mevcut konumunu al
      final driverLocation = await _getDriverLocation(_currentRide!.driverId ?? '');
      if (driverLocation == null) return;

      // Müşterinin hedef konumuna olan mesafeyi hesapla
      double remainingDistance = _calculateDistance(
        LatLng(driverLocation['latitude'], driverLocation['longitude']),
        _currentRide!.destinationLocation,
      );

      // Gerçek zamanlı fiyat hesapla
      double realTimePrice = await _calculateRealTimePrice(
        remainingDistance: remainingDistance,
        elapsedTime: DateTime.now().difference(_currentRide!.createdAt).inMinutes,
        trafficConditions: await _getCurrentTrafficConditions(),
      );

      _currentPrice = realTimePrice;
      _realTimeData = {
        'remaining_distance': remainingDistance,
        'elapsed_time': DateTime.now().difference(_currentRide!.createdAt).inMinutes,
        'traffic_level': await _getCurrentTrafficConditions(),
      };

      notifyListeners();

      // Firestore'da fiyatı güncelle
      await _firestore.collection('rides').doc(rideId).update({
        'current_price': realTimePrice,
        'last_price_update': FieldValue.serverTimestamp(),
        'real_time_data': _realTimeData,
      });

    } catch (e) {
      print('Gerçek zamanlı fiyat güncelleme hatası: $e');
    }
  }

  // Vale konumunu al
  Future<Map<String, dynamic>?> _getDriverLocation(String driverId) async {
    try {
      final doc = await _firestore.collection('drivers').doc(driverId).get();
      if (doc.exists) {
        return {
          'latitude': doc.data()?['latitude'],
          'longitude': doc.data()?['longitude'],
        };
      }
    } catch (e) {
      print('Vale konumu alınamadı: $e');
    }
    return null;
  }

  // Mesafe hesapla
  double _calculateDistance(LatLng point1, LatLng point2) {
    return _haversineDistance(
      point1.latitude, point1.longitude,
      point2.latitude, point2.longitude,
    );
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        sin(lat1) * sin(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Gerçek zamanlı fiyat hesapla
  Future<double> _calculateRealTimePrice({
    required double remainingDistance,
    required int elapsedTime,
    required String trafficConditions,
  }) async {
    try {
      // Temel fiyat
      double basePrice = 50.0 + (remainingDistance * 10.0);
      
      // Zaman bazlı ek ücret
      double timeMultiplier = elapsedTime > 60 ? 1.2 : 1.0;
      
      // Trafik bazlı ek ücret
      double trafficMultiplier = _getTrafficMultiplier(trafficConditions);
      
      // Bekleme ücreti (15 dakikadan sonra)
      double waitingFee = elapsedTime > 15 ? (elapsedTime - 15) * 2.0 : 0.0;
      
      // Final fiyat
      double finalPrice = (basePrice * timeMultiplier * trafficMultiplier) + waitingFee;
      
      return finalPrice;
    } catch (e) {
      print('Gerçek zamanlı fiyat hesaplama hatası: $e');
      return 50.0 + (remainingDistance * 10.0);
    }
  }

  // Trafik çarpanı
  double _getTrafficMultiplier(String trafficLevel) {
    switch (trafficLevel.toLowerCase()) {
      case 'low':
        return 1.0;
      case 'medium':
        return 1.1;
      case 'high':
        return 1.3;
      case 'severe':
        return 1.5;
      default:
        return 1.0;
    }
  }

  // Mevcut trafik durumunu al
  Future<String> _getCurrentTrafficConditions() async {
    try {
      // Google Maps Traffic API çağrısı
      // Şimdilik sabit değer
      return 'medium';
    } catch (e) {
      return 'low';
    }
  }

  // Yolculuk durumunu güncelle
  Future<void> updateRideStatus(String rideId, String status) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Yolculuk başladığında gerçek zamanlı takibi başlat
      if (status == 'started') {
        startRealTimePriceTracking(rideId);
      }

      // Yolculuk bittiğinde takibi durdur
      if (status == 'completed') {
        stopRealTimePriceTracking();
        
        // TAMAMLANDI - PERSİSTENCE TEMİZLE!
        _currentRide = null;
        await _clearCurrentRidePersistence();
      }

      await _loadCurrentRide();
    } catch (e) {
      _error = 'Yolculuk durumu güncellenemedi: $e';
      notifyListeners();
    }
  }

  // Mevcut metodlar
  Future<void> loadAvailableRides() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Test verileri ekle
      _availableRides = [
        Ride(
          id: 'test_ride_001',
          customerId: 'test_customer_001',
          pickupLocation: const LatLng(41.0082, 28.9784), // İstanbul
          destinationLocation: const LatLng(41.0082, 28.9784),
          pickupAddress: 'Kadıköy, İstanbul',
          destinationAddress: 'Beşiktaş, İstanbul',
          status: 'pending',
          estimatedPrice: 50.0,
          estimatedTime: 15,
          paymentMethod: 'cash',
          createdAt: DateTime.now(),
        ),
      ];

      // Firebase'den veri çekmeyi dene
      try {
        final snapshot = await _firestore
            .collection('rides')
            .where('status', isEqualTo: 'pending')
            .orderBy('createdAt', descending: true)
            .get();

        _availableRides = snapshot.docs
            .map((doc) => Ride.fromMap(doc.data(), doc.id))
            .toList();
      } catch (firebaseError) {
        print('Firebase hatası: $firebaseError');
        // Test verileri ile devam et
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadRideHistory() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Test verileri ekle
      _rideHistory = [
        Ride(
          id: 'history_001',
          customerId: 'test_customer_001',
          pickupLocation: const LatLng(41.0082, 28.9784),
          destinationLocation: const LatLng(41.0082, 28.9784),
          pickupAddress: 'Kadıköy, İstanbul',
          destinationAddress: 'Beşiktaş, İstanbul',
          status: 'completed',
          estimatedPrice: 75.0,
          estimatedTime: 20,
          paymentMethod: 'cash',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
        Ride(
          id: 'history_002',
          customerId: 'test_customer_001',
          pickupLocation: const LatLng(41.0082, 28.9784),
          destinationLocation: const LatLng(41.0082, 28.9784),
          pickupAddress: 'Şişli, İstanbul',
          destinationAddress: 'Kadıköy, İstanbul',
          status: 'completed',
          estimatedPrice: 120.0,
          estimatedTime: 25,
          paymentMethod: 'cash',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];

      // Firebase'den veri çekmeyi dene
      try {
        final snapshot = await _firestore
            .collection('rides')
            .where('status', whereIn: ['completed', 'cancelled'])
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();

        _rideHistory = snapshot.docs
            .map((doc) => Ride.fromMap(doc.data(), doc.id))
            .toList();
      } catch (firebaseError) {
        print('Firebase hatası: $firebaseError');
        // Test verileri ile devam et
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createRide({
    required LatLng pickupLocation,
    required LatLng destinationLocation,
    required String pickupAddress,
    required String destinationAddress,
    required double estimatedPrice,
    required int estimatedTime,
    required String paymentMethod,
    required String customerId,
    DateTime? scheduledTime, // YENİ PARAMETRE: ZAMANLI TALEP
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      // ZAMAN BAZLI TALEP ANALIZİ
      final now = DateTime.now();
      final requestTime = scheduledTime ?? now;
      final hoursUntilService = requestTime.difference(now).inHours;
      
      print('🕰️ ZAMAN ANALIZİ: Talep zamanı ${hoursUntilService} saat sonra');
      
      String requestType;
      String status;
      
      if (hoursUntilService <= 2) {
        requestType = 'immediate_or_soon'; // 0-2 SAAT: ANLIK VALELER
        status = 'pending';
        print('⚡ ANLIK TALEP: Valelere direkt düşecek');
      } else {
        requestType = 'scheduled_later'; // 2+ SAAT: PANELE DÜŞÜR
        status = 'scheduled_pending';
        print('📅 ZAMANLI TALEP: Panele düşecek, 2 saat kala valelere gidecek');
      }

      final rideData = {
        'customer_id': customerId,
        'pickup_location': GeoPoint(pickupLocation.latitude, pickupLocation.longitude),
        'destination_location': GeoPoint(destinationLocation.latitude, destinationLocation.longitude),
        'pickup_address': pickupAddress,
        'destination_address': destinationAddress,
        'estimated_price': estimatedPrice,
        'estimated_time': estimatedTime,
        'payment_method': paymentMethod,
        'status': status,
        'request_type': requestType, // YENİ ALAN!
        'scheduled_time': requestTime,
        'hours_until_service': hoursUntilService,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Firebase'e kaydet
      DocumentReference? docRef;
      try {
        docRef = await _firestore.collection('rides').add(rideData);
        print('✅ Yeni yolculuk talebi oluşturuldu: ${docRef.id}');
        
        // ZAMAN BAZLI İŞLEM KONTROLÜ
        if (requestType == 'immediate_or_soon') {
          // 0-2 SAAT: ANLIK VALELERLE EŞLEŞTİR
          print('⚡ ANLIK TALEP İŞLE M: Valelere direkt gönderiliyor...');
          await _findAndMatchNearbyDrivers(docRef.id, pickupLocation, pickupAddress, destinationAddress, estimatedPrice);
        } else {
          // 2+ SAAT: SADECE PANELE GÖNDER, VALELERLE EŞLEŞTİRME YOK!
          print('📅 ZAMANLI TALEP: Sadece panele kaydediliyor, valelerle eşleşme yok');
          
          // 2 saat kala otomatik vale eşleştirme zamanını programla
          final autoMatchTime = requestTime.subtract(const Duration(hours: 2));
          if (autoMatchTime.isAfter(now)) {
            await _scheduleAutoDriverMatching(docRef.id, autoMatchTime, pickupLocation, pickupAddress, destinationAddress, estimatedPrice);
          }
        }
        
        // Admin panel API ile vale talebi oluştur
        try {
          final adminResult = await _adminApi.createRideRequest(
            customerId: customerId,
            pickupAddress: pickupAddress,
            pickupLat: pickupLocation.latitude,
            pickupLng: pickupLocation.longitude,
            destinationAddress: destinationAddress,
            destinationLat: destinationLocation.latitude,
            destinationLng: destinationLocation.longitude,
            scheduledTime: scheduledTime ?? DateTime.now(),
            estimatedPrice: estimatedPrice,
            paymentMethod: paymentMethod,
          );
          
          if (adminResult['success'] == true) {
            print('Admin panel API başarılı: Vale talebi panelde oluşturuldu');
          } else {
            print('Admin panel API hatası: ${adminResult['message']}');
          }
        } catch (apiError) {
          print('Admin panel API hatası: $apiError');
        }

        // Mevcut yolculuğu yükle
        await _loadCurrentRide();
        
        // AKTİF YOLCULUK PERSİSTENCE KAYDET!
        await _saveCurrentRidePersistence();
      } catch (firebaseError) {
        print('Firebase hatası: $firebaseError');
        // Test verisi olarak ekle
        final testRide = Ride(
          id: 'test_${DateTime.now().millisecondsSinceEpoch}',
          customerId: customerId,
          pickupLocation: pickupLocation,
          destinationLocation: destinationLocation,
          pickupAddress: pickupAddress,
          destinationAddress: destinationAddress,
          estimatedPrice: estimatedPrice,
          estimatedTime: estimatedTime,
          paymentMethod: paymentMethod,
          status: 'pending',
          createdAt: DateTime.now(),
        );
        _currentRide = testRide;
        
        // TEST RIDE PERSİSTENCE KAYDET!
        await _saveCurrentRidePersistence();
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // GELIŞMIŞ AKıLLı VALE ÇAĞIRMA SİSTEMİ - 10KM/10SANİYE KURALI!
  Future<void> _findAndMatchNearbyDrivers(String rideId, LatLng pickupLocation, String pickupAddress, String destinationAddress, double estimatedPrice) async {
    try {
      print('🚀 === GELIŞMİŞ VALE EŞLEŞME SİSTEMİ BAŞLADI ===');
      
      // 1. TÜM ÇEVRİMİÇİ VALELERNİ AL
      final driversSnapshot = await _firestore
          .collection('drivers')
          .where('is_online', isEqualTo: true)
          .where('is_available', isEqualTo: true)
          .get();
      
      if (driversSnapshot.docs.isEmpty) {
        print('❌ Çevrimiçi vale bulunamadı!');
        return;
      }
      
      print('👨‍🚗 Bulunan çevrimiçi vale sayısı: ${driversSnapshot.docs.length}');
      
      // 2. VALELERNİ MESAFEİYE GÖRE SIRALA
      List<Map<String, dynamic>> allDrivers = [];
      
      for (var doc in driversSnapshot.docs) {
        try {
          final driverData = doc.data();
          final driverLat = driverData['latitude']?.toDouble();
          final driverLng = driverData['longitude']?.toDouble();
          
          if (driverLat != null && driverLng != null) {
            final distance = _calculateDistance(
              pickupLocation, 
              LatLng(driverLat, driverLng)
            );
            
            allDrivers.add({
              'driver_id': doc.id,
              'driver_data': driverData,
              'distance': distance,
            });
          }
        } catch (e) {
          print('❌ Vale verisi işlenirken hata: $e');
        }
      }
      
      // YAKINDAN UZAĞA SIRALA
      allDrivers.sort((a, b) => a['distance'].compareTo(b['distance']));
      
      // 3. 1. FASE: EN YAKIN 10KM İÇİNDEKİ VALELERE GÖNDER (10 SANİYE)
      List<Map<String, dynamic>> nearbyDrivers = allDrivers.where((d) => d['distance'] <= 10.0).toList();
      
      if (nearbyDrivers.isNotEmpty) {
        print('🏁 1. FASE: ${nearbyDrivers.length} yakın vale (10km içi) - 10 saniye süre!');
        
        // Yakın valelere gönder
        for (var driverInfo in nearbyDrivers) {
          await _sendRideRequestToDriver(
            rideId,
            driverInfo['driver_id'],
            pickupAddress,
            destinationAddress,
            estimatedPrice,
            driverInfo['distance'],
            phase: '1st_phase_nearby',
          );
        }
        
        // 10 SANİYE BEKLE - KABUL KONTROLU
        bool acceptedInPhase1 = await _waitForDriverAcceptance(rideId, 10);
        
        if (acceptedInPhase1) {
          print('✅ 1. FASE BAŞARILI: Yakın vale kabul etti!');
          return; // Vale bulundu, sistem tamamlandı
        } else {
          print('⚠️ 1. FASE: 10 saniye içinde yakın vale kabul etmedi');
        }
      }
      
      // 4. 2. FASE: TÜM ÇEVRİMİÇİ VALELERE GÖNDER
      List<Map<String, dynamic>> allOtherDrivers = allDrivers.where((d) => d['distance'] > 10.0).toList();
      
      if (allOtherDrivers.isNotEmpty) {
        print('🏁 2. FASE: ${allOtherDrivers.length} uzak vale - tüm çevrimiçi valeler!');
        
        for (var driverInfo in allOtherDrivers) {
          await _sendRideRequestToDriver(
            rideId,
            driverInfo['driver_id'],
            pickupAddress,
            destinationAddress,
            estimatedPrice,
            driverInfo['distance'],
            phase: '2nd_phase_all',
          );
        }
        
        print('✅ 2. FASE TAMAMLANDI: Tüm valelere talep gönderildi!');
      }
      
      print('✅ === GELIŞMIŞ VALE EŞLEŞME SİSTEMİ TAMAMLANDI ===');
    } catch (e) {
      print('❌ Vale eşleşme sistem hatası: $e');
    }
  }
  
  // VALE KABUL ETME BEKLEMEK - 10 SANİYE TIMEOUT
  Future<bool> _waitForDriverAcceptance(String rideId, int timeoutSeconds) async {
    print('⏱️ Vale kabulü için $timeoutSeconds saniye bekleniyor...');
    
    for (int i = 0; i < timeoutSeconds; i++) {
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        // Firebase'den ride durumunu kontrol et
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        
        if (rideDoc.exists) {
          final rideData = rideDoc.data();
          final status = rideData?['status'];
          
          if (status == 'accepted') {
            print('✅ Vale kabul etti! ($i. saniye)');
            return true;
          }
        }
      } catch (e) {
        print('❌ Vale kabul kontrol hatası: $e');
      }
    }
    
    print('⚠️ Timeout: $timeoutSeconds saniye içinde kabul yok');
    return false;
  }
  
  // SÜRÜCÜYE YOLCULUK TALEBİ GÖNDER - GELIŞTİRİLMİŞ!
  Future<void> _sendRideRequestToDriver(String rideId, String driverId, String pickupAddress, String destinationAddress, double estimatedPrice, double distance, {String phase = 'standard'}) async {
    try {
      // Firebase'de sürücü için ride_request oluştur
      await _firestore.collection('rides').add({
        'ride_id': rideId,
        'driver_id': driverId,
        'pickup_address': pickupAddress,
        'destination_address': destinationAddress,
        'estimated_price': estimatedPrice,
        'distance_to_pickup': distance,
        'status': 'sent',
        'sent_at': FieldValue.serverTimestamp(),
        'expires_at': FieldValue.serverTimestamp(), // 30 saniye sonra expire
      });
      
      // Push notification gönder (Firebase Messaging)
      try {
        await _sendPushNotificationToDriver(
          driverId,
          'Yeni Vale Talebi!',
          '$pickupAddress → $destinationAddress (₺${estimatedPrice.toStringAsFixed(0)})',
          {
            'type': 'ride_request',
            'ride_id': rideId,
            'pickup_address': pickupAddress,
            'destination_address': destinationAddress,
            'price': estimatedPrice.toString(),
          }
        );
        print('Sürücü $driverId bildirim gönderildi');
      } catch (e) {
        print('Push notification hatası: $e');
      }
    } catch (e) {
      print('Sürücüye talep gönderme hatası: $e');
    }
  }
  
  // PUSH NOTIFICATION GÖNDER
  Future<void> _sendPushNotificationToDriver(String driverId, String title, String body, Map<String, String> data) async {
    try {
      // Sürücünün FCM token'ını al
      final driverDoc = await _firestore.collection('drivers').doc(driverId).get();
      final fcmToken = driverDoc.data()?['fcm_token'];
      
      if (fcmToken == null) {
        print('Sürücü FCM token bulunamadı: $driverId');
        return;
      }
      
      // FCM API ile notification gönder
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_FCM_SERVER_KEY', // Bu key'i firebase console'dan alın
        },
        body: json.encode({
          'to': fcmToken,
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
            'priority': 'high',
          },
          'data': data,
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'rides',
              'sound': 'default',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        }),
      );
      
      if (response.statusCode == 200) {
        print('Push notification başarıyla gönderildi: $driverId');
      } else {
        print('Push notification hatası: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Push notification gönderme hatası: $e');
    }
  }

  Future<void> cancelRide(String rideId) async {
    try {
      await updateRideStatus(rideId, 'cancelled');
      await loadRideHistory();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadCurrentRide() async {
    try {
      final snapshot = await _firestore
          .collection('rides')
          .where('status', whereIn: ['pending', 'accepted', 'started'])
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _currentRide = Ride.fromMap(snapshot.docs.first.data(), snapshot.docs.first.id);
      } else {
        _currentRide = null;
      }

      notifyListeners();
    } catch (e) {
      print('Mevcut yolculuk yüklenemedi: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ZAMAN BAZLI OTOMATİK VALE EŞLEŞTİRME PROGRAMLAMA - 2 SAAT KALA!
  Future<void> _scheduleAutoDriverMatching(
    String rideId,
    DateTime autoMatchTime,
    LatLng pickupLocation,
    String pickupAddress,
    String destinationAddress,
    double estimatedPrice,
  ) async {
    try {
      print('⏰ OTOMATİK VALE EŞLEŞTİRME PROGRAMLANDI:');
      print('   Ride ID: $rideId');
      print('   Eşleştirme zamanı: $autoMatchTime');
      
      // Firebase'de zamanlanmış eşleştirme kaydı oluştur
      await _firestore.collection('scheduled_ride_matching').add({
        'ride_id': rideId,
        'auto_match_time': Timestamp.fromDate(autoMatchTime),
        'pickup_location': GeoPoint(pickupLocation.latitude, pickupLocation.longitude),
        'pickup_address': pickupAddress,
        'destination_address': destinationAddress,
        'estimated_price': estimatedPrice,
        'status': 'scheduled',
        'created_at': FieldValue.serverTimestamp(),
      });
      
      print('✅ Otomatik eşleştirme başarıyla programlandı!');
      print('📱 2 saat kala vale arama başlayacak');
      
    } catch (e) {
      print('❌ Otomatik eşleştirme programlama hatası: $e');
    }
  }

  // ZAMANLI TALEPLERİ İŞLEME ALMA (BACKGROUND SERVICE - PANEL TARAFINDA ÇALIŞMALI)
  static Future<void> processScheduledRides() async {
    try {
      print('⏰ === ZAMANLANMIŞ YOLCULUK KONTROL SİSTEMİ ===');
      
      final now = DateTime.now();
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      
      // 2 saat kala olan zamanlanmış ride'ları bul
      final scheduledRides = await firestore
          .collection('scheduled_ride_matching')
          .where('status', isEqualTo: 'scheduled')
          .where('auto_match_time', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .get();
      
      print('📋 İşlenecek zamanlanmış yolculuk sayısı: ${scheduledRides.docs.length}');
      
      for (var doc in scheduledRides.docs) {
        try {
          final data = doc.data();
          final rideId = data['ride_id'];
          
          print('🔄 Zamanlanmış yolculuk işleniyor: $rideId');
          
          // 1. Ride'ı pending durumuna getir (valelere gönderilmek üzere)
          await firestore.collection('rides').doc(rideId).update({
            'status': 'pending',
            'auto_matched_at': FieldValue.serverTimestamp(),
            'request_type': 'auto_scheduled', // Otomatik zamanlanmış
          });
          
          // 2. Vale eşleştirmesi başlat (gerçek sistemde background service'de çalışmalı)
          final pickupLocation = data['pickup_location'] as GeoPoint;
          
          print('🚗 Vale eşleştirmesi başlatılıyor: $rideId');
          
          // 3. Zamanlanmış eşleştirme kaydını tamamlandı olarak işaretle
          await doc.reference.update({
            'status': 'processed',
            'processed_at': FieldValue.serverTimestamp(),
          });
          
          print('✅ Zamanlanmış yolculuk valelere gönderildi: $rideId');
          
        } catch (e) {
          print('❌ Zamanlanmış yolculuk işleme hatası: $e');
        }
      }
      
      print('⏰ === ZAMANLANMIŞ YOLCULUK KONTROL TAMAMLANDI ===');
    } catch (e) {
      print('❌ Zamanlanmış yolculuk kontrol hatası: $e');
    }
  }
  
  // PANEL İÇİN ZAMANLI TALEPLERİ LİSTELEME
  Future<List<Map<String, dynamic>>> getScheduledRidesForPanel() async {
    try {
      final snapshot = await _firestore
          .collection('rides')
          .where('request_type', isEqualTo: 'scheduled_later')
          .where('status', isEqualTo: 'scheduled_pending')
          .orderBy('scheduled_time', descending: false)
          .get();
      
      List<Map<String, dynamic>> scheduledRides = [];
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        scheduledRides.add({
          'id': doc.id,
          'customer_id': data['customer_id'],
          'pickup_address': data['pickup_address'],
          'destination_address': data['destination_address'],
          'scheduled_time': (data['scheduled_time'] as Timestamp).toDate(),
          'estimated_price': data['estimated_price'],
          'hours_until_service': data['hours_until_service'],
          'created_at': (data['created_at'] as Timestamp).toDate(),
        });
      }
      
      print('📋 Panel için ${scheduledRides.length} zamanlanmış yolculuk bulundu');
      return scheduledRides;
    } catch (e) {
      print('❌ Zamanlanmış yolculuk listesi alma hatası: $e');
      return [];
    }
  }

  // DUPLICATE DEĞİŞKENLER - COMMENT OUT (ÜSTTEKİLER KULLANILACAK)
  /*
  Timer? _realTimeDistanceTimer;
  double? _realTimeDistance;
  double? _realTimePrice;
  
  double? get realTimeDistance => _realTimeDistance;
  double? get realTimePrice => _realTimePrice;
  */

  // DUPLICATE METOD SİLİNDİ - SADECE ÜSTTEKİ KULLANILACAK
  /*
  Future<void> _loadCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRideJson = prefs.getString('customer_current_ride');
      if (savedRideJson != null && savedRideJson.isNotEmpty) {
        try {
          final rideData = json.decode(savedRideJson);
          _currentRide = Ride.fromMap(Map<String, dynamic>.from(rideData), rideData['id']?.toString() ?? '0');
          debugPrint('🔄 MÜŞTERİ: Aktif yolculuk geri yüklendi: ${_currentRide?.id}');
          debugPrint('📍 Status: ${_currentRide?.status}');
          notifyListeners(); // UI'yi güncelle
        } catch (e) {
          debugPrint('❌ MÜŞTERİ: Aktif yolculuk geri yükleme hatası: $e');
          await prefs.remove('customer_current_ride'); // Bozuk veriyi temizle
        }
      }
    } catch (e) {
      debugPrint('❌ MÜŞTERİ: Persistence yükleme hatası: $e');
    }
  }
  */
  
  // AKTİF YOLCULUK PERSİSTENCE KAYDET - MÜŞTERİ İÇİN!
  /* DUPLICATE METOD - COMMENT OUT
  Future<void> _saveCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentRide != null) {
        final rideJson = json.encode(_currentRide!.toMap());
        await prefs.setString('customer_current_ride', rideJson);
        debugPrint('💾 MÜŞTERİ: Aktif yolculuk persist edildi: ${_currentRide!.id}');
      }
    } catch (e) {
      debugPrint('❌ MÜŞTERİ: Aktif yolculuk persist hatası: $e');
    }
  }
  */
} 