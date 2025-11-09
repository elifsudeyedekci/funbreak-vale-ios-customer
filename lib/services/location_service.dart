import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static Position? _lastKnownPosition;
  
  // Konum izinlerini kontrol et ve iste
  static Future<bool> checkAndRequestLocationPermission() async {
    try {
      // Konum servisi aktif mi?
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Konum servisi kapalı');
        return false;
      }
      
      // İzin durumunu kontrol et
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Konum izni reddedildi');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Konum izni kalıcı olarak reddedildi');
        return false;
      }
      
      print('Konum izni verildi');
      return true;
    } catch (e) {
      print('Konum izni kontrol hatası: $e');
      return false;
    }
  }
  
  // Mevcut konumu al
  static Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await checkAndRequestLocationPermission();
      if (!hasPermission) {
        return null;
      }
      
      print('Konum alınıyor...');
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );
      
      _lastKnownPosition = position;
      print('Konum alındı: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Konum alma hatası: $e');
      
      // Hata durumunda son bilinen konumu dön
      if (_lastKnownPosition != null) {
        print('Son bilinen konum kullanılıyor');
        return _lastKnownPosition;
      }
      
      return null;
    }
  }
  
  // Hızlı konum al (önce son bilinen, sonra yeni)
  static Future<Position?> getLocationFast() async {
    try {
      bool hasPermission = await checkAndRequestLocationPermission();
      if (!hasPermission) {
        return null;
      }
      
      // Önce son bilinen konumu al (hızlı)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _lastKnownPosition = lastKnown;
        print('Son bilinen konum: ${lastKnown.latitude}, ${lastKnown.longitude}');
        
        // Arka planda yeni konum al
        _updateLocationInBackground();
        
        return lastKnown;
      }
      
      // Son bilinen konum yoksa yeni al
      return await getCurrentLocation();
    } catch (e) {
      print('Hızlı konum alma hatası: $e');
      return null;
    }
  }
  
  // Arka planda konum güncelle
  static void _updateLocationInBackground() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      _lastKnownPosition = position;
      print('Arka plan konum güncellendi: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Arka plan konum güncelleme hatası: $e');
    }
  }
  
  // Konum stream'i başlat
  static Stream<Position> getLocationStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // 10 metre hareket ettiğinde güncelle
    );
    
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
  
  // İki nokta arası mesafe hesapla (metre)
  static double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
  
  // Son bilinen konum
  static Position? get lastKnownPosition => _lastKnownPosition;
  
  // Konum servisi aktif mi?
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
}
