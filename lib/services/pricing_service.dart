import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math';

// Saatlik paket modeli
class HourlyPackage {
  final int id;
  final double minHours;
  final double maxHours;
  final double price;
  final String description;
  
  HourlyPackage({
    required this.id,
    required this.minHours,
    required this.maxHours,
    required this.price,
    required this.description,
  });
  
  String get displayText {
    if (maxHours >= 999) {
      return '${minHours.toInt()}+ saat';
    }
    return '${minHours.toInt()}-${maxHours.toInt()} saat';
  }
  
  @override
  String toString() {
    return 'HourlyPackage(id: $id, hours: $minHours-$maxHours, price: $price)';
  }
}

// Paket yükseltme sonucu
class PackageUpgradeResult {
  final bool upgraded;
  final HourlyPackage? initialPackage;
  final HourlyPackage? currentPackage;
  final double additionalCost;
  
  PackageUpgradeResult({
    required this.upgraded,
    required this.initialPackage,
    required this.currentPackage,
    required this.additionalCost,
  });
  
  @override
  String toString() {
    return 'PackageUpgradeResult(upgraded: $upgraded, additionalCost: $additionalCost)';
  }
}

class PricingService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Map<String, dynamic>? _cachedPricing;
  static Map<String, dynamic>? _cachedSettings;
  static DateTime? _lastFetch;
  
  // Cache süresi (5 dakika)
  static const Duration cacheTimeout = Duration(minutes: 5);
  
  static Future<Map<String, dynamic>?> getPricingData() async {
    try {
      // Cache kontrolü
      if (_cachedPricing != null && _lastFetch != null) {
        if (DateTime.now().difference(_lastFetch!) < cacheTimeout) {
          print('Pricing data cache\'den alındı');
          return _cachedPricing;
        }
      }
      
      print('Pricing data API\'den çekiliyor...');
      final response = await http.get(
        Uri.parse('$baseUrl/get_pricing.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedPricing = data['data'];
          _lastFetch = DateTime.now();
          print('Pricing data başarıyla alındı');
          return _cachedPricing;
        }
      }
      
      print('Pricing data alınamadı: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Pricing data hatası: $e');
      return null;
    }
  }
  
  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      // Cache kontrolü
      if (_cachedSettings != null && _lastFetch != null) {
        if (DateTime.now().difference(_lastFetch!) < cacheTimeout) {
          print('Settings cache\'den alındı');
          return _cachedSettings;
        }
      }
      
      print('Settings API\'den çekiliyor...');
      final response = await http.get(
        Uri.parse('$baseUrl/get_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedSettings = data['data'];
          print('Settings başarıyla alındı');
          return _cachedSettings;
        }
      }
      
      print('Settings alınamadı: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Settings hatası: $e');
      return null;
    }
  }
  
  // Mesafe bazlı fiyat hesaplama
  static double calculateDistancePrice(double distance, List<dynamic>? distancePricing) {
    if (distancePricing == null || distancePricing.isEmpty) {
      print('Distance pricing bulunamadı, varsayılan fiyat: ${distance * 10}');
      return distance * 10; // Varsayılan: km başına 10 TL
    }
    
    for (var pricing in distancePricing) {
      double minValue = (pricing['min_value'] ?? 0).toDouble();
      double maxValue = (pricing['max_value'] ?? 999).toDouble();
      
      if (distance >= minValue && distance <= maxValue) {
        double price = (pricing['price'] ?? 0).toDouble();
        print('Distance pricing bulundu: $distance km = $price TL');
        return price;
      }
    }
    
    // Eğer hiç uygun aralık bulunamazsa, en yüksek aralığın fiyatını kullan
    if (distancePricing.isNotEmpty) {
      var lastPricing = distancePricing.last;
      double price = (lastPricing['price'] ?? 0).toDouble();
      print('Son aralık fiyatı kullanıldı: $price TL');
      return price;
    }
    
    return distance * 10;
  }
  
  // Saatlik fiyat hesaplama
  static double calculateHourlyPrice(double hours, List<dynamic>? hourlyPricing) {
    if (hourlyPricing == null || hourlyPricing.isEmpty) {
      print('Hourly pricing bulunamadı, varsayılan fiyat: ${hours * 200}');
      return hours * 200; // Varsayılan: saat başına 200 TL
    }
    
    for (var pricing in hourlyPricing) {
      double minValue = (pricing['min_value'] ?? 0).toDouble();
      double maxValue = (pricing['max_value'] ?? 999).toDouble();
      
      if (hours >= minValue && hours <= maxValue) {
        double price = (pricing['price'] ?? 0).toDouble();
        print('Hourly pricing bulundu: $hours saat = $price TL');
        return price;
      }
    }
    
    // Eğer hiç uygun aralık bulunamazsa, en yüksek aralığın fiyatını kullan
    if (hourlyPricing.isNotEmpty) {
      var lastPricing = hourlyPricing.last;
      double price = (lastPricing['price'] ?? 0).toDouble();
      print('Son aralık fiyatı kullanıldı: $price TL');
      return price;
    }
    
    return hours * 200;
  }
  
  // Özel konum fiyat kontrolü
  static double checkLocationPricing(double lat, double lng, List<dynamic>? locationPricing) {
    if (locationPricing == null || locationPricing.isEmpty) {
      print('Location pricing bulunamadı');
      return 0;
    }
    
    for (var location in locationPricing) {
      double locationLat = (location['latitude'] ?? 0).toDouble();
      double locationLng = (location['longitude'] ?? 0).toDouble();
      double radius = (location['radius'] ?? 1).toDouble();
      double extraFee = (location['extra_fee'] ?? 0).toDouble();
      String locationName = location['location_name'] ?? '';
      
      // Mesafe hesaplama (Haversine formula)
      double distance = calculateDistance(lat, lng, locationLat, locationLng);
      
      if (distance <= radius) {
        print('Özel konum tespit edildi: $locationName (+$extraFee TL)');
        return extraFee;
      }
    }
    
    print('Özel konum bulunamadı');
    return 0;
  }
  
  // İki nokta arası mesafe hesaplama (km)
  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km
    
    double dLat = _toRadians(lat2 - lat1);
    double dLng = _toRadians(lng2 - lng1);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    
    return distance;
  }
  
  static double _toRadians(double degree) {
    return degree * (pi / 180);
  }
  
  // Google Directions API ile gerçek rota mesafesini hesapla
  static Future<double> calculateRouteDistance({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      const String googleApiKey = 'AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY';
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=$originLat,$originLng&'
        'destination=$destLat,$destLng&'
        'key=$googleApiKey&'
        'language=tr&'
        'units=metric'
      );

      print('Google Directions API çağrısı yapılıyor...');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final leg = route['legs'][0];
          final distanceValue = leg['distance']['value']; // metre cinsinden
          final distanceText = leg['distance']['text'];
          final durationText = leg['duration']['text'];
          
          final distanceKm = distanceValue / 1000.0; // km'ye çevir
          
          print('✅ Rota mesafesi: $distanceText ($distanceKm km)');
          print('✅ Tahmini süre: $durationText');
          
          return distanceKm;
        } else {
          print('❌ Directions API hatası: ${data['status']}');
          // Hata durumunda kuş bakışı mesafe kullan
          return _calculateHaversineDistance(originLat, originLng, destLat, destLng);
        }
      } else {
        print('❌ Directions API HTTP hatası: ${response.statusCode}');
        return _calculateHaversineDistance(originLat, originLng, destLat, destLng);
      }
    } catch (e) {
      print('❌ Rota mesafesi hesaplama hatası: $e');
      // Hata durumunda kuş bakışı mesafe kullan
      return _calculateHaversineDistance(originLat, originLng, destLat, destLng);
    }
  }

  // Kuş bakışı mesafe hesaplama (fallback)
  static double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    print('🔄 Kuş bakışı mesafe: ${distance.toStringAsFixed(2)} km (fallback)');
    return distance;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Toplam fiyat hesaplama (güncellenmiş - rota mesafesi ile)
  // ✅ HEM PICKUP HEM DESTINATION ÖZEL KONUMDAYsa İKİSİNİN TOPLAMI ALINIR!
  static Future<double> calculateTotalPrice({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    double? hours,
    double waitingMinutes = 0,
  }) async {
    try {
      // Önce gerçek rota mesafesini hesapla
      final distance = await calculateRouteDistance(
        originLat: originLat,
        originLng: originLng,
        destLat: destinationLat,
        destLng: destinationLng,
      );
      
      final pricingData = await getPricingData();
      final settings = await getSettings();
      
      if (pricingData == null) {
        print('Pricing data alınamadı, varsayılan hesaplama: ${distance * 15} TL (${distance.toStringAsFixed(2)} km)');
        return distance * 15; // km başına 15 TL varsayılan
      }
      
      print('Pricing data alındı: ${pricingData.keys}');
      
      double totalPrice = 0;
      
      // Mesafe bazlı fiyat
      if (hours == null || hours == 0) {
        totalPrice = calculateDistancePrice(distance, pricingData['distance_pricing']);
      } else {
        // Saatlik fiyat
        totalPrice = calculateHourlyPrice(hours, pricingData['hourly_pricing']);
      }
      
      // ✅ ÖZEL KONUM EK ÜCRETİ - PICKUP + DESTINATION TOPLAMI!
      double pickupLocationFee = checkLocationPricing(
        originLat, 
        originLng, 
        pricingData['location_pricing']
      );
      double destinationLocationFee = checkLocationPricing(
        destinationLat, 
        destinationLng, 
        pricingData['location_pricing']
      );
      double totalLocationFee = pickupLocationFee + destinationLocationFee;
      totalPrice += totalLocationFee;
      
      if (totalLocationFee > 0) {
        print('🗺️ ÖZEL KONUM TOPLAM: +₺$totalLocationFee (Pickup: ₺$pickupLocationFee, Destination: ₺$destinationLocationFee)');
      }
      
      // Bekleme ücreti hesaplama
      if (waitingMinutes > 0 && settings != null) {
        double freeMinutes = double.tryParse(settings['waiting_free_minutes'] ?? '30') ?? 30;
        double feePerInterval = double.tryParse(settings['waiting_fee_per_15min'] ?? '150') ?? 150;
        
        if (waitingMinutes > freeMinutes) {
          double chargeableMinutes = waitingMinutes - freeMinutes;
          double intervals = (chargeableMinutes / 15).ceil().toDouble();
          double waitingFee = intervals * feePerInterval;
          totalPrice += waitingFee;
          
          print('Bekleme ücreti: $waitingFee TL ($chargeableMinutes dk)');
        }
      }
      
      print('Toplam fiyat: $totalPrice TL');
      return totalPrice;
      
    } catch (e) {
      print('Fiyat hesaplama hatası: $e');
      return 50.0; // Varsayılan fiyat
    }
  }
  
  // Saatlik paketleri al
  static Future<List<HourlyPackage>> getHourlyPackages() async {
    try {
      final pricingData = await getPricingData();
      
      if (pricingData == null || pricingData['hourly_pricing'] == null) {
        print('Saatlik paket verisi bulunamadı, varsayılan paketler kullanılıyor');
        return _getDefaultHourlyPackages();
      }
      
      List<HourlyPackage> packages = [];
      
      for (var pricing in pricingData['hourly_pricing']) {
        packages.add(HourlyPackage(
          id: pricing['id'],
          minHours: (pricing['min_value'] ?? 0).toDouble(),
          maxHours: (pricing['max_value'] ?? 999).toDouble(),
          price: (pricing['price'] ?? 0).toDouble(),
          description: pricing['description'] ?? '',
        ));
      }
      
      // Saate göre sırala
      packages.sort((a, b) => a.minHours.compareTo(b.minHours));
      
      print('${packages.length} saatlik paket yüklendi');
      return packages;
      
    } catch (e) {
      print('Saatlik paket yükleme hatası: $e');
      return _getDefaultHourlyPackages();
    }
  }
  
  // Varsayılan saatlik paketler
  static List<HourlyPackage> _getDefaultHourlyPackages() {
    return [
      HourlyPackage(id: 1, minHours: 0, maxHours: 4, price: 2000, description: '0-4 saat vale hizmeti'),
      HourlyPackage(id: 2, minHours: 4, maxHours: 8, price: 4000, description: '4-8 saat vale hizmeti'),
      HourlyPackage(id: 3, minHours: 8, maxHours: 12, price: 6000, description: '8-12 saat vale hizmeti'),
    ];
  }
  
  // Kullanım süresine göre uygun paketi bul
  static HourlyPackage? findPackageForUsage(double usedHours, List<HourlyPackage> packages) {
    for (var package in packages) {
      if (usedHours >= package.minHours && usedHours <= package.maxHours) {
        return package;
      }
    }
    
    // Eğer hiç uygun paket bulunamazsa, en yüksek paketi döndür
    if (packages.isNotEmpty) {
      return packages.last;
    }
    
    return null;
  }
  
  // Otomatik paket yükseltme hesaplama
  static PackageUpgradeResult calculatePackageUpgrade(
    double initialHours, 
    double usedHours, 
    List<HourlyPackage> packages
  ) {
    HourlyPackage? initialPackage = findPackageForUsage(initialHours, packages);
    HourlyPackage? currentPackage = findPackageForUsage(usedHours, packages);
    
    if (initialPackage == null || currentPackage == null) {
      return PackageUpgradeResult(
        upgraded: false,
        initialPackage: null,
        currentPackage: null,
        additionalCost: 0,
      );
    }
    
    bool upgraded = currentPackage.id != initialPackage.id;
    double additionalCost = upgraded ? (currentPackage.price - initialPackage.price) : 0;
    
    return PackageUpgradeResult(
      upgraded: upgraded,
      initialPackage: initialPackage,
      currentPackage: currentPackage,
      additionalCost: additionalCost,
    );
  }

  // Cache temizleme
  static void clearCache() {
    _cachedPricing = null;
    _cachedSettings = null;
    _lastFetch = null;
    print('Pricing cache temizlendi');
  }
}
