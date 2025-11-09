import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationPricingProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  List<Map<String, dynamic>> _specialLocations = [];
  Map<String, double> _locationPricing = {};
  
  List<Map<String, dynamic>> get specialLocations => _specialLocations;
  Map<String, double> get locationPricing => _locationPricing;

  // Admin panelden özel konumları ve fiyatlarını getir
  Future<void> loadLocationPricing() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/location_pricing.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _specialLocations = List<Map<String, dynamic>>.from(data['locations']);
          
          // Konum fiyatlandırma map'ini oluştur
          _locationPricing.clear();
          for (var location in _specialLocations) {
            _locationPricing[location['name']] = double.parse(location['extra_fee'].toString());
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Konum fiyatlandırma yükleme hatası: $e');
    }
  }

  // Belirli bir konum için ek ücret hesapla
  double calculateLocationExtraFee(String address) {
    double extraFee = 0.0;
    
    for (var location in _specialLocations) {
      if (address.toLowerCase().contains(location['name'].toLowerCase())) {
        extraFee += double.parse(location['extra_fee'].toString());
      }
    }
    
    return extraFee;
  }

  // Koordinatlara göre ek ücret hesapla
  double calculateLocationExtraFeeByCoords(LatLng coords) {
    double extraFee = 0.0;
    
    for (var location in _specialLocations) {
      final locationLat = double.parse(location['latitude'].toString());
      final locationLng = double.parse(location['longitude'].toString());
      final radius = double.parse(location['radius'].toString()); // km cinsinden
      
      final distance = _calculateDistance(
        coords.latitude, coords.longitude,
        locationLat, locationLng,
      );
      
      if (distance <= radius) {
        extraFee += double.parse(location['extra_fee'].toString());
      }
    }
    
    return extraFee;
  }

  // İki nokta arası mesafe hesapla (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = (dLat / 2).sin() * (dLat / 2).sin() +
        lat1.cos() * lat2.cos() * (dLon / 2).sin() * (dLon / 2).sin();
    double c = 2 * (a.sqrt()).atan2((1 - a).sqrt());
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }
}

// Math extension for better readability
extension MathExtension on double {
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double sqrt() => math.sqrt(this);
  double atan2(double x) => math.atan2(this, x);
}
