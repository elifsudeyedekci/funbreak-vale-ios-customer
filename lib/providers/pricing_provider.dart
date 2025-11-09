import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PricingProvider with ChangeNotifier {
  List<Map<String, dynamic>> _pricing = [];
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _currentTrafficData;
  Map<String, dynamic>? _weatherData;

  List<Map<String, dynamic>> get pricing => _pricing;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get currentTrafficData => _currentTrafficData;
  Map<String, dynamic>? get weatherData => _weatherData;

  // Yapay Zeka Destekli Fiyat Hesaplama
  Future<double> calculateAIPrice({
    required LatLng pickup,
    required LatLng destination,
    required String serviceType,
    required DateTime time,
  }) async {
    try {
      // 1. Gerçek rota mesafesi ve süresi al
      final routeData = await _getRouteData(pickup, destination);
      
      // 2. Trafik durumu analizi
      await _analyzeTrafficConditions(pickup, destination);
      
      // 3. Hava durumu etkisi
      await _getWeatherImpact(pickup);
      
      // 4. Zaman bazlı dinamik fiyatlandırma
      double timeMultiplier = _calculateTimeMultiplier(time);
      
      // 5. Trafik yoğunluğu etkisi
      double trafficMultiplier = _calculateTrafficMultiplier();
      
      // 6. Hava durumu etkisi
      double weatherMultiplier = _calculateWeatherMultiplier();
      
      // 7. Hizmet tipi etkisi
      double serviceMultiplier = _getServiceMultiplier(serviceType);
      
      // 8. Temel fiyat hesapla
      double basePrice = _calculateBasePrice(routeData['distance']);
      
      // 9. Yapay zeka ile optimize edilmiş fiyat
      double aiPrice = basePrice * timeMultiplier * trafficMultiplier * weatherMultiplier * serviceMultiplier;
      
      // 10. Piyasa analizi ve rekabet fiyatı
      double marketPrice = await _getMarketPrice(pickup, destination);
      
      // 11. Konum bazlı ek ücretler hesapla
      double locationExtraFee = 0.0;
      try {
        // Admin panelden özel konumları getir
        final response = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/location_pricing.php'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final locations = List<Map<String, dynamic>>.from(data['locations']);
            
            // Pickup ve destination için ek ücret kontrol et
            for (var location in locations) {
              final locationLat = double.parse(location['latitude'].toString());
              final locationLng = double.parse(location['longitude'].toString());
              final radius = double.parse(location['radius'].toString());
              
              // Pickup için kontrol
              double pickupDistance = _calculateDistance(pickup, LatLng(locationLat, locationLng));
              if (pickupDistance <= radius) {
                locationExtraFee += double.parse(location['extra_fee'].toString());
              }
              
              // Destination için kontrol
              double destDistance = _calculateDistance(destination, LatLng(locationLat, locationLng));
              if (destDistance <= radius) {
                locationExtraFee += double.parse(location['extra_fee'].toString());
              }
            }
          }
        }
      } catch (e) {
        print('Konum ek ücreti hesaplama hatası: $e');
      }

      // 12. Final fiyat (Sadece AI fiyatı + Konum ek ücretleri) - PİYASA ANALİZİ DEAKTİF!
      double finalPrice = aiPrice + locationExtraFee;
      
      return finalPrice;
    } catch (e) {
      print('AI fiyat hesaplama hatası: $e');
      return _calculateFallbackPrice(pickup, destination);
    }
  }

  // Gerçek rota verisi al
  // GELIŞMİŞ GOOGLE MAPS NAVİGASYON BAZLI FİYAT HESAPLAMA!
  Future<Map<String, dynamic>> _getRouteData(LatLng pickup, LatLng destination) async {
    try {
      print('🗺️ GERÇEK NAVİGASYON MESAFESİ HESAPLANIYOR...');
      
      // GELIŞMİŞ DİRECTİONS API - TRAFİK DAHİL GERÇEK ROTA!
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${pickup.latitude},${pickup.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&departure_time=now'  // GERÇEK ZAMANLI TRAFİK!
          '&traffic_model=best_guess'
          '&optimize=true'
          '&alternatives=true'  // ALTERNATİF ROTALAR
          '&avoid=tolls'  // ÖCRETLİ YOLLARİ ATLA
          '&language=tr'
          '&key=AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY'
        ),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          // EN İYİ ROTAYI SEÇ (trafik dahil en kısa süre)
          final routes = data['routes'] as List;
          Map<String, dynamic> bestRoute = routes[0];
          
          // Eğer birden fazla rota varsa, trafik dahil en hızlısını seç
          if (routes.length > 1) {
            bestRoute = routes.reduce((a, b) {
              final aDuration = a['legs'][0]['duration_in_traffic']?['value'] ?? a['legs'][0]['duration']['value'];
              final bDuration = b['legs'][0]['duration_in_traffic']?['value'] ?? b['legs'][0]['duration']['value'];
              return aDuration < bDuration ? a : b;
            });
          }
          
          final legs = bestRoute['legs'][0];
          final distance = legs['distance']['value'] / 1000.0; // km
          final normalDuration = legs['duration']['value'] / 60.0; // dakika
          final trafficDuration = (legs['duration_in_traffic']?['value'] ?? legs['duration']['value']) / 60.0;
          
          print('✅ GERÇEK NAVİGASYON MESAFESİ: ${distance.toStringAsFixed(2)} km');
          print('✅ NORMAL SÜRE: ${normalDuration.toStringAsFixed(0)} dk');
          print('✅ TRAFİK DAHİL SÜRE: ${trafficDuration.toStringAsFixed(0)} dk');
          
          return {
            'distance': distance, // GERÇEK NAVİGASYON MESAFESİ!
            'duration': normalDuration,
            'traffic_duration': trafficDuration,
            'polyline': bestRoute['overview_polyline']['points'],
            'route_summary': legs['summary'] ?? 'Optimum Rota',
            'traffic_factor': trafficDuration / normalDuration, // Trafik çarpanı
            'alternative_routes': routes.length,
          };
        } else {
          print('⚠️ Google Directions API hatası: ${data['status']}');
          if (data['error_message'] != null) {
            print('⚠️ Hata mesajı: ${data['error_message']}');
          }
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Rota verisi alınamadı: $e');
    }
    
    // FALLBACK: KUŞ UÇUŞU MESAFESİ (GERÇEK ROTA ALINAMAZSA)
    double fallbackDistance = _calculateDistance(pickup, destination);
    print('⚠️ Fallback mesafe kullanılıyor: ${fallbackDistance.toStringAsFixed(2)} km');
    
    return {
      'distance': fallbackDistance * 1.4, // Gerçek yol mesafesi tahmini (%40 fazla)
      'duration': fallbackDistance * 3, // Ortalama 3 dk/km
      'traffic_duration': fallbackDistance * 4.5, // Trafikli 4.5 dk/km
      'polyline': null,
      'route_summary': 'Tahmini Rota',
      'traffic_factor': 1.5,
      'alternative_routes': 0,
    };
  }

  // Trafik durumu analizi
  Future<void> _analyzeTrafficConditions(LatLng pickup, LatLng destination) async {
    try {
      // Google Maps Traffic API
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${pickup.latitude},${pickup.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&departure_time=now'
          '&traffic_model=best_guess'
          '&key=AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final legs = route['legs'][0];
          
          _currentTrafficData = {
            'traffic_level': _analyzeTrafficLevel(legs['duration_in_traffic']?['value'] ?? legs['duration']['value']),
            'congestion_level': _calculateCongestionLevel(route),
            'peak_hours': _isPeakHours(),
          };
        }
      }
    } catch (e) {
      print('Trafik analizi hatası: $e');
    }
  }

  // Hava durumu etkisi
  Future<void> _getWeatherImpact(LatLng location) async {
    try {
      // OpenWeatherMap API
      final response = await http.get(
        Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?'
          'lat=${location.latitude}&lon=${location.longitude}'
          '&appid=YOUR_OPENWEATHER_API_KEY&units=metric'
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _weatherData = {
          'condition': data['weather'][0]['main'],
          'temperature': data['main']['temp'],
          'humidity': data['main']['humidity'],
          'visibility': data['visibility'],
        };
      }
    } catch (e) {
      print('Hava durumu hatası: $e');
    }
  }

  // Zaman bazlı çarpan - TÜM ÇARPANLAR KALICI DEAKTİF! ❌
  double _calculateTimeMultiplier(DateTime time) {
    int hour = time.hour;
    
    // GECE ÜCRETİ (22:00 - 06:00) - ŞİMDİLİK DEVREDİŞI
    /*
    if (hour >= 22 || hour < 6) {
      return 1.3; // +%30 gece ücreti
    }
    */
    
    // SABAH YOĞUNLUĞU (07:00 - 09:00) - ŞİMDİLİK DEVREDİŞI
    /*
    if (hour >= 7 && hour <= 9) {
      return 1.2; // +%20 sabah ücreti
    }
    */
    
    // AKŞAM YOĞUNLUĞU (17:00 - 19:00) - ŞİMDİLİK DEVREDİŞI
    /*
    if (hour >= 17 && hour <= 19) {
      return 1.25; // +%25 akşam ücreti
    }
    */
    
    // HAFTA SONU ÜCRETİ - ŞİMDİLİK DEVREDİŞI
    /*
    if (time.weekday >= 6) {
      return 1.1; // +%10 hafta sonu ücreti
    }
    */
    
    // KULLANICI TALEBİYLE TÜM ZAMAN ÇARPANLARI DEAKTİF - SABİT FİYAT!
    return 1.0;
  }

  // Trafik çarpanı
  double _calculateTrafficMultiplier() {
    if (_currentTrafficData == null) return 1.0;
    
    String trafficLevel = _currentTrafficData!['traffic_level'];
    bool isPeakHours = _currentTrafficData!['peak_hours'];
    
    switch (trafficLevel) {
      case 'low':
        return isPeakHours ? 1.1 : 1.0;
      case 'medium':
        return isPeakHours ? 1.2 : 1.1;
      case 'high':
        return isPeakHours ? 1.4 : 1.3;
      case 'severe':
        return isPeakHours ? 1.6 : 1.5;
      default:
        return 1.0;
    }
  }

  // Hava durumu çarpanı
  double _calculateWeatherMultiplier() {
    if (_weatherData == null) return 1.0;
    
    String condition = _weatherData!['condition'];
    double visibility = _weatherData!['visibility'] / 1000; // km
    
    switch (condition.toLowerCase()) {
      case 'rain':
        return 1.15;
      case 'snow':
        return 1.3;
      case 'fog':
        return 1.2;
      case 'storm':
        return 1.4;
      default:
        if (visibility < 5) return 1.1;
        return 1.0;
    }
  }

  // Hizmet tipi çarpanı
  double _getServiceMultiplier(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'vale':
        return 1.0;
      case 'transfer':
        return 1.2;
      case 'araç muayenesi':
        return 1.5;
      case 'araç yıkama':
        return 0.8;
      case 'kurye':
        return 0.9;
      default:
        return 1.0;
    }
  }

  // Admin panelden aralık bazlı fiyat hesaplama
  double _calculateBasePrice(double distance) {
    // Her hesaplamada panelden fresh veri çek
    if (_pricing.isEmpty) {
      loadPricing(); // Anlık veri çek
    }
    
    // Admin panelden yüklenen aralık fiyatlarını kullan
    if (_pricing.isNotEmpty) {
      for (var priceRange in _pricing) {
        double minKm = double.tryParse(priceRange['min_km'].toString()) ?? 0.0;
        double maxKm = double.tryParse(priceRange['max_km'].toString()) ?? 0.0;
        
        if (distance >= minKm && distance <= maxKm) {
          // Direkt paneldeki aralık fiyatını döndür
          double basePrice = double.tryParse(priceRange['price'].toString()) ?? 500.0;
          print('Panel fiyatı kullanıldı: $distance km için ₺$basePrice (Aralık: $minKm-$maxKm km)');
          return basePrice;
        }
      }
    }
    
    // Panel verisi yoksa veya aralık bulunamazsa fallback
    print('Panel verisi bulunamadı, fallback fiyat kullanılıyor');
    if (distance <= 5) {
      return 500.0; // 0-5 km: 500 TL
    } else if (distance <= 10) {
      return 1000.0; // 6-10 km: 1000 TL  
    } else if (distance <= 15) {
      return 1500.0; // 11-15 km: 1500 TL
    } else if (distance <= 20) {
      return 2000.0; // 16-20 km: 2000 TL
    } else if (distance <= 25) {
      return 2500.0; // 21-25 km: 2500 TL
    } else if (distance <= 30) {
      return 3000.0; // 26-30 km: 3000 TL
    } else {
      return 3000.0 + ((distance - 30) * 100.0); // 30+ km: 3000 + (fazla_km × 100)
    }
  }

  // Piyasa fiyatı analizi - ŞİMDİLİK DEAKTİF!
  Future<double> _getMarketPrice(LatLng pickup, LatLng destination) async {
    try {
      // RAKİP ANALİZİ ŞİMDİLİK KULLANILMIYOR - SABİT DEĞER DÖNER
      // double distance = _calculateDistance(pickup, destination);
      // return 40.0 + (distance * 12.0);
      
      // Sadece sıfır döndür - piyasa etkisi yok
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // Fallback aralık bazlı fiyat hesaplama
  double _calculateFallbackPrice(LatLng pickup, LatLng destination) {
    double distance = _calculateDistance(pickup, destination);
    
    // Aralık bazlı fiyatlandırma
    if (distance <= 5) {
      return 500.0; // 0-5 km: 500 TL
    } else if (distance <= 10) {
      return 1000.0; // 6-10 km: 1000 TL
    } else if (distance <= 15) {
      return 1500.0; // 11-15 km: 1500 TL
    } else if (distance <= 20) {
      return 2000.0; // 16-20 km: 2000 TL
    } else {
      return 2000.0 + ((distance - 20) * 100.0); // 20+ km: 2000 + (fazla_km × 100)
    }
  }

  // Yardımcı fonksiyonlar
  double _calculateDistance(LatLng pickup, LatLng destination) {
    return _haversineDistance(pickup.latitude, pickup.longitude, destination.latitude, destination.longitude);
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

  String _analyzeTrafficLevel(int durationInTraffic) {
    if (durationInTraffic < 300) return 'low'; // 5 dk
    if (durationInTraffic < 600) return 'medium'; // 10 dk
    if (durationInTraffic < 900) return 'high'; // 15 dk
    return 'severe';
  }

  double _calculateCongestionLevel(Map<String, dynamic> route) {
    // Rota üzerindeki trafik yoğunluğunu hesapla
    return 0.5; // Örnek değer
  }

  bool _isPeakHours() {
    int hour = DateTime.now().hour;
    return (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19);
  }

  // Gerçek zamanlı fiyat güncelleme
  Future<double> getRealTimePrice({
    required LatLng currentLocation,
    required LatLng destination,
    required String serviceType,
  }) async {
    return await calculateAIPrice(
      pickup: currentLocation,
      destination: destination,
      serviceType: serviceType,
      time: DateTime.now(),
    );
  }

  // Mevcut metodlar
  Future<void> loadPricing() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/pricing.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      print('Pricing API çağrısı yapıldı: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _pricing = List<Map<String, dynamic>>.from(data['pricing']);
        } else {
          _error = data['message'] ?? 'Fiyatlandırma yüklenemedi';
        }
      } else {
        _error = 'Sunucu hatası: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'Bağlantı hatası: $e';
      _pricing = [
        {'min_km': 0, 'max_km': 5, 'price': 500.0},
        {'min_km': 6, 'max_km': 10, 'price': 1000.0},
        {'min_km': 11, 'max_km': 15, 'price': 1500.0},
        {'min_km': 16, 'max_km': 20, 'price': 2000.0},
        {'min_km': 21, 'max_km': 25, 'price': 2500.0},
        {'min_km': 26, 'max_km': 30, 'price': 3000.0},
        {'min_km': 31, 'max_km': 35, 'price': 3500.0},
        {'min_km': 36, 'max_km': 40, 'price': 4000.0},
        {'min_km': 41, 'max_km': 45, 'price': 4500.0},
        {'min_km': 46, 'max_km': 50, 'price': 5000.0},
        {'min_km': 51, 'max_km': 55, 'price': 5500.0},
        {'min_km': 56, 'max_km': 60, 'price': 6000.0},
        {'min_km': 61, 'max_km': 65, 'price': 6500.0},
        {'min_km': 66, 'max_km': 70, 'price': 7000.0},
        {'min_km': 71, 'max_km': 75, 'price': 7500.0},
      ];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double calculatePrice(double distance) {
    if (_pricing.isEmpty) return 50.0;

    for (var tier in _pricing) {
      if (tier['type'] == 'distance') {
        double minValue = tier['min_value'].toDouble();
        double maxValue = tier['max_value'].toDouble();
        
        if (distance >= minValue && distance <= maxValue) {
          return tier['price'].toDouble();
        }
      }
    }

    double basePrice = 50.0;
    return basePrice + (distance * 10.0);
  }

  double calculateHourlyPrice(int hours) {
    if (_pricing.isEmpty) return 300.0;

    for (var tier in _pricing) {
      if (tier['type'] == 'hourly') {
        double minValue = tier['min_value'].toDouble();
        double maxValue = tier['max_value'].toDouble();
        
        if (hours >= minValue && hours <= maxValue) {
          return tier['price'].toDouble();
        }
      }
    }

    double basePrice = 300.0;
    return basePrice + (hours * 50.0);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
} 