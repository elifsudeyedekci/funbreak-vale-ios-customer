import 'package:flutter/material.dart';
import '../../widgets/rating_card.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // FIREBASE IMPORT!
import 'package:shared_preferences/shared_preferences.dart'; // SHARED PREFERENCES IMPORT!
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../../providers/admin_api_provider.dart'; // ADMİN API PROVIDER IMPORT!
import '../../providers/ride_provider.dart';
import '../../providers/pricing_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/waiting_time_provider.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/notifications_bottom_sheet.dart';
import '../../services/dynamic_contact_service.dart';
import '../profile/profile_screen.dart';
import '../legal/terms_screen.dart';
import '../ride/modern_active_ride_screen.dart'; // MODERNİ AKTİF YOLCULUK EKRANI!
import '../../services/pricing_service.dart';
import '../../services/location_service.dart';
import '../../services/location_search_service.dart';
import '../../services/saved_addresses_service.dart';
import '../../services/ride_service.dart';
import '../../services/time_service.dart';
import '../../providers/admin_api_provider.dart';
import '../../services/dynamic_contact_service.dart';
import '../payment/payment_methods_screen.dart';
import '../../services/customer_cards_api.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng _currentLocation = const LatLng(41.0082, 28.9784);
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Konumunuzu seçin';
  String _destinationAddress = 'Nereye gitmek istiyorsunuz?';
  
  // 🔥 ARA DURAK SİSTEMİ
  List<Map<String, dynamic>> _waypoints = []; // {address: String, location: LatLng}
  
  bool _isLoading = false;
  bool _showTimeSelection = false;
  DateTime? _selectedDateTime;
  bool _isLongTermTripCache = false; // Server time kontrolü cache
  String _selectedTimeOption = 'Hemen';
  String _selectedServiceType = 'vale'; // 'vale' or 'hourly'
  double? _estimatedPrice;
  List<HourlyPackage> _hourlyPackages = [];
  HourlyPackage? _selectedHourlyPackage;
  double? _originalPrice;
  String? _appliedDiscountCode;
  double _discountAmount = 0.0;
  final TextEditingController _discountCodeController = TextEditingController();
  
  // PROVİZYON SİSTEMİ - TAMAMEN DEAKTİF [[memory:9694916]]
  // Build hatası olmaması için tanımlandı ama tamamen bypass edilecek
  final double _provisionAmount = 0.0; // DEAKTİF - UI'da hiç gözükmez
  bool _provisionProcessed = false; // DEAKTİF - sadece build için
  bool _mapLoading = true;
  List<PlaceAutocomplete> _searchResults = [];
  
  // VALE ARAMA İPTAL SİSTEMİ DEĞİŞKENLERİ
  bool _isSearchingForDriver = false;
  Timer? _driverSearchTimer;
  bool _searchCancelled = false;
  
  // ÇİFT TALEP ENGELLEYİCİ - FRONTEND SİSTEMİ
  bool _isCreatingRideRequest = false;
  
  // REAL-TIME SEARCH DEBOUNCING
  Timer? _searchDebounce;
  
  // BİLDİRİM BADGE SAYISI
  int _unreadNotificationCount = 0;
  bool _badgeLoaded = false;
  
  // 2 AŞAMALI SİSTEM DEĞİŞKENLERİ
  bool _termsAccepted = true; // VARSAYILAN OLARAK KABUL EDİLMİŞ - UX İYİLEŞTİRMESİ!
  String _selectedPaymentMethod = 'card';
  
  // AKILLI SİSTEM DEĞİŞKENLERİ - HAFIZADAN RESTORE [[memory:9695382]]
  int? _currentRideId;
  bool _driverFound = false;
  int _requestStage = 0;
  List<Map<String, dynamic>> _userCards = [];
  final CustomerCardsApi _cardsApi = CustomerCardsApi();
  
  // FİREBASE REFERENCE - EKSİK İMPORT SORUNU ÇÖZÜLDİ
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    
    _getCurrentLocationImproved();
    _loadHourlyPackages();
    _loadUserCards(); // 🔥 KARTLARI BACKEND'DEN YÜK
    
    // FIREBASE BİLDİRİM - ANA SAYFA BADGE REFRESH!
    _setupNotificationBadgeListener();
    
    // MANUEL ATAMA SONRASI OTOMATİK YOLCULUK EKRANI KONTROLÜ
    _checkBackendActiveRide();
    
    // Badge sayısını yükle
    _refreshBadgeCount();
  }
  
  // Customer ID'yi dinamik olarak al
  Future<int?> _getCurrentCustomerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getInt('customer_id');
      print('🔍 Customer ID: $customerId');
      return customerId;
    } catch (e) {
      print('❌ Customer ID alma hatası: $e');
      return null;
    }
  }
  
  // MANUEL ATAMA SONRASI OTOMATİK YOLCULUK EKRANI KONTROLÜ
  void _checkBackendActiveRide() async {
    try {
      print('🔍 Backend aktif yolculuk kontrolü başlıyor...');
      
      // Customer ID'yi dinamik olarak al
      final customerId = await _getCurrentCustomerId();
      if (customerId == null) {
        print('❌ Customer ID alınamadı');
        return;
      }
      
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_active_rides.php?customer_id=$customerId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔍 Backend aktif yolculuk response: $data');
        
        if (data['success'] == true && data['active_rides'] != null && data['active_rides'].length > 0) {
          // SADECE GERÇEK AKTİF YOLCULUKLARI GÖSTER! (completed ve cancelled HARİÇ!)
          final activeRide = data['active_rides'][0];
          final rideStatus = activeRide['status']?.toString() ?? '';
          
          if (rideStatus == 'completed' || rideStatus == 'cancelled') {
            print('⏸️ Yolculuk TAMAMLANMIŞ ($rideStatus) - yönlendirme YAPILMAYACAK!');
            return;
          }
          
          print('✅ Backend aktif yolculuk bulundu - otomatik yolculuk ekranı açılıyor');
          
          // Otomatik yolculuk ekranına git
          Navigator.pushNamed(context, '/modern_active_ride', arguments: {
            'rideDetails': activeRide,
            'isFromBackend': true,
          });
        } else {
          print('ℹ️ Backend aktif yolculuk bulunamadı');
        }
      } else {
        print('❌ Backend aktif yolculuk API hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Backend aktif yolculuk kontrol hatası: $e');
    }
  }
  
  // Badge sayısını yenile
  Future<void> _refreshBadgeCount() async {
    final count = await _getUnreadNotificationCount();
    if (mounted) {
      setState(() {
        _unreadNotificationCount = count;
        _badgeLoaded = true;
      });
      print('🔔 Badge güncellendi: $_unreadNotificationCount');
    }
  }
  
  // ANA SAYFA BİLDİRİM BADGE REFRESH - FIREBASE LISTENER!
  void _setupNotificationBadgeListener() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('🔔 Ana sayfa: Firebase notification alındı');
        final type = message.data['type'];
        
        // Bildirim veya kampanya geldiğinde badge'i refresh et
        if (type == 'announcement' || type == 'campaign') {
          print('🔄 Ana sayfa badge refresh... (Type: $type)');
          _refreshBadgeCount(); // Badge sayısını yenile
        }
      });
      
      print('✅ Ana sayfa Firebase badge listener kuruldu');
    } catch (e) {
      print('❌ Badge refresh listener hatası: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    // TİMER TEMİZLEME - MEMORY LEAK ÖNLEME
    _driverSearchTimer?.cancel();
    _searchDebounce?.cancel(); // SEARCH DEBOUNCE TIMER!
    _driverSearchTimer = null;
    super.dispose();
  }

  Future<void> _getCurrentLocationImproved() async {
    try {
      Position? position = await LocationService.getLocationFast();
      if (position == null) return;
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _pickupLocation = _currentLocation;
      });

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          // MAHALLE EN BAŞTA SİSTEMİ [[memory:9695626]] - RESTORE!
          List<String> addressParts = [];
          
          // 1. MAHALLE EN BAŞTA (subLocality öncelik)
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            addressParts.add(place.subLocality!);
          } else if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
            addressParts.add(place.subAdministrativeArea!);
          }
          
          // 2. SOKAK İSMİ (mahalle sonra)
          if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
            addressParts.add(place.thoroughfare!);
          } else if (place.street != null && place.street!.isNotEmpty) {
            addressParts.add(place.street!);
          }
          
          // 3. APT NUMARASI (en son)
          if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
            addressParts.add('No: ${place.subThoroughfare}');
          }
          
          // İl
          if (place.locality != null && place.locality!.isNotEmpty) {
            addressParts.add(place.locality!);
          }
          
          // Final adres - boş olanları filtrele
          _pickupAddress = addressParts
              .where((part) => part.trim().isNotEmpty)
              .take(3) // Maksimum 3 parça (çok uzun olmasın)
              .join(', ');
          
          // Fallback - hiçbir detay yoksa
          if (_pickupAddress.isEmpty) {
            _pickupAddress = '${place.subLocality ?? ''}, ${place.locality ?? 'Konum'}';
          }
          
          print('📍 Detaylı adres: $_pickupAddress');
        });
      }

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation, 15),
        );
      }
    } catch (e) {
      print('Konum alma hatası: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    await _getCurrentLocationImproved();
  }

  Future<void> _loadHourlyPackages() async {
    try {
      final packages = await PricingService.getHourlyPackages();
      setState(() {
        _hourlyPackages = packages;
      });
    } catch (e) {
      print('Saatlik paket yükleme hatası: $e');
    }
  }

  // 🔥 KARTLARI BACKEND'DEN YÜK
  Future<void> _loadUserCards() async {
    try {
      print('💳 Kullanıcı kartları yükleniyor...');
      final cards = await _cardsApi.getCards();
      setState(() {
        _userCards = cards;
      });
      print('✅ ${cards.length} kart yüklendi');
    } catch (e) {
      print('❌ Kart yükleme hatası: $e');
    }
  }

  // 🔥 ARA DURAK EKLEME
  void _addWaypoint() {
    if (_waypoints.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En fazla 3 ara durak ekleyebilirsiniz'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() {
      _waypoints.add({
        'address': '',
        'location': null,
      });
    });
  }

  // 🔥 ARA DURAK SİLME
  void _removeWaypoint(int index) {
    setState(() {
      _waypoints.removeAt(index);
    });
  }

  Future<void> _calculatePrice() async {
    if (_pickupLocation == null || _destinationLocation == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      double totalDistance = 0.0;
      
      // 🔥 ARA DURAKLAR VAR MI?
      if (_waypoints.isNotEmpty) {
        print('🔄 === ARA DURAKLI ROTA FİYAT HESAPLAMA ===');
        print('📍 Başlangıç: ${_pickupLocation!.latitude}, ${_pickupLocation!.longitude}');
        
        // 1. SEGMENT: Pickup → İlk Ara Durak
        double segment1Distance = await PricingService.calculateRouteDistance(
          originLat: _pickupLocation!.latitude,
          originLng: _pickupLocation!.longitude,
          destLat: _waypoints[0]['location'].latitude,
          destLng: _waypoints[0]['location'].longitude,
        );
        totalDistance += segment1Distance;
        print('📊 Segment 1 (Pickup → Ara Durak 1): $segment1Distance km');
        
        // 2. SEGMENT: Ara Duraklar arası
        for (int i = 0; i < _waypoints.length - 1; i++) {
          double segmentDistance = await PricingService.calculateRouteDistance(
            originLat: _waypoints[i]['location'].latitude,
            originLng: _waypoints[i]['location'].longitude,
            destLat: _waypoints[i + 1]['location'].latitude,
            destLng: _waypoints[i + 1]['location'].longitude,
          );
          totalDistance += segmentDistance;
          print('📊 Segment ${i + 2} (Ara Durak ${i + 1} → Ara Durak ${i + 2}): $segmentDistance km');
        }
        
        // 3. SEGMENT: Son Ara Durak → Destination
        double lastSegmentDistance = await PricingService.calculateRouteDistance(
          originLat: _waypoints.last['location'].latitude,
          originLng: _waypoints.last['location'].longitude,
          destLat: _destinationLocation!.latitude,
          destLng: _destinationLocation!.longitude,
        );
        totalDistance += lastSegmentDistance;
        print('📊 Segment ${_waypoints.length + 1} (Son Ara Durak → Destination): $lastSegmentDistance km');
        
        print('💰 TOPLAM MESAFE (${_waypoints.length} ara durak): $totalDistance km');
        
        // FİYAT HESAPLA (toplam mesafeye göre)
        final pricingData = await PricingService.getPricingData();
        double totalPrice = PricingService.calculateDistancePrice(totalDistance, pricingData?['distance_pricing']);
        
        setState(() {
          _estimatedPrice = totalPrice;
          _originalPrice = totalPrice;
          _isLoading = false;
        });
        
        print('✅ Ara duraklı fiyat: ₺$totalPrice');
      } else {
        // Normal fiyat hesaplama (ara durak yok)
        double totalPrice = await PricingService.calculateTotalPrice(
          originLat: _pickupLocation!.latitude,
          originLng: _pickupLocation!.longitude,
          destinationLat: _destinationLocation!.latitude,
          destinationLng: _destinationLocation!.longitude,
        );

        setState(() {
          _estimatedPrice = totalPrice;
          _originalPrice = totalPrice;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fiyat hesaplama hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateHourlyPrice() async {
    if (_selectedHourlyPackage != null) {
      setState(() {
        _estimatedPrice = _selectedHourlyPackage!.price;
        _originalPrice = _selectedHourlyPackage!.price;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
                          languageProvider.getTranslatedText('funbreak_vale'),
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontWeight: FontWeight.bold,
                            fontSize: 24,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showNotifications(),
            icon: Stack(
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: Color(0xFFFFD700),
                  size: 28,
                ),
                // Badge sadece okunmamış varsa göster
                if (_badgeLoaded && _unreadNotificationCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ), // IconButton kapanışı
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // PUANLAMA KARTI - PENDING RATING VARSA GÖSTER
          FutureBuilder<bool>(
            future: _checkPendingRating(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return FutureBuilder<Map<String, String>>(
                  future: _getPendingRatingData(),
                  builder: (context, dataSnapshot) {
                    if (dataSnapshot.hasData && dataSnapshot.data != null) {
                      final data = dataSnapshot.data!;
                      return RatingCard(
                        rideId: data['ride_id']!,
                        driverId: data['driver_id']!,
                        driverName: data['driver_name']!,
                        customerId: data['customer_id']!,
                        onComplete: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('pending_rating_ride_id');
                          await prefs.remove('pending_rating_driver_id');
                          await prefs.remove('pending_rating_driver_name');
                          await prefs.remove('pending_rating_customer_id');
                          await prefs.setBool('has_pending_rating', false);
                          setState(() {});
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // Harita Kısmı - %25 KÜÇÜLTÜLDÜ!
          Expanded(
            flex: 3, // 2 → 3: Harita küçültüldü (%25 küçük)
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: GoogleMap(
                      onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    setState(() {
                      _mapLoading = false;
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation,
                    zoom: 15,
                  ),
                  markers: {
                    if (_pickupLocation != null)
                      Marker(
                        markerId: const MarkerId('pickup'),
                        position: _pickupLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      ),
                    if (_destinationLocation != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: _destinationLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                  },
                      onTap: (LatLng location) {
                        // HAR İTA TıKLAMA İLE KONUM SEÇİMİ - YENİ ÖZELLİK!
                        print('🗺️ Haritaya tıklandı: ${location.latitude}, ${location.longitude}');
                        _selectLocationFromMap(location);
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                ),
              ),
            ),
                // Konum butonu
          Positioned(
                  bottom: 30,
                  right: 30,
            child: Container(
                decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                  ),
                ],
                ),
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                      onPressed: _getCurrentLocationImproved,
                      child: const Icon(
                        Icons.my_location_rounded,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Alt Menü Kısmı - DENGE AYARI!
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Servis Seçimi
                          Row(
                            children: [
                              Expanded(
                                child: _buildServiceTypeButton(
                                  'vale',
                                  'Vale Çağır',
                                  Icons.directions_car,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildServiceTypeButton(
                                  'hourly',
                                  'Saatlik Paketler',
                                  Icons.access_time,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Konum Seçimi
                          if (_selectedServiceType == 'vale') ...[
                            _buildLocationSelector(
                              'Nereden',
                              _pickupAddress,
                              Icons.location_on,
                              Colors.green,
                              () => _selectLocation('pickup'),
                              showMenu: true, // 3 nokta göster
                              onMenuPressed: () => _showAddWaypointDialog(),
                            ),
                            const SizedBox(height: 6),
                            
                            // 🔥 ARA DURAKLAR
                            ..._waypoints.asMap().entries.map((entry) {
                              final index = entry.key;
                              final waypoint = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _buildWaypointSelector(
                                  'Durak ${index + 1}',
                                  waypoint['address'] ?? 'Ara durak seçin',
                                  Icons.location_on,
                                  Colors.orange,
                                  () => _selectLocation('waypoint_$index'),
                                  () => _removeWaypoint(index),
                                ),
                              );
                            }).toList(),
                            
                            const SizedBox(height: 6),
                            _buildLocationSelector(
                              'Nereye',
                              _destinationAddress,
                              Icons.location_on,
                              Colors.red,
                              () => _selectLocation('destination'),
                            ),

                            const SizedBox(height: 8),
                            _buildTimeSelectionWidget(),
                          ],

                          // Saatlik Paket Seçimi
                          if (_selectedServiceType == 'hourly') ...[
                            _buildCompactHourlyPackages(),
                            const SizedBox(height: 8),
                            _buildTimeSelectionWidget(),
                          ],
                                  
                          // Seçilen Tarih/Saat Gösterimi
                          if (_selectedDateTime != null) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.schedule, color: Color(0xFFFFD700), size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_selectedDateTime!.day}/${_selectedDateTime!.month}/${_selectedDateTime!.year} - ${_selectedDateTime!.hour.toString().padLeft(2, '0')}:${_selectedDateTime!.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // TEK ANA BUTON - VALE SEÇ 2. AŞAMAYA TAŞINDI!
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _callValet,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                      ),
                                    )
                                  : const Text(
                                      'Yolculuğu Onayla',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTypeButton(String type, String title, IconData icon) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSelected = _selectedServiceType == type;
    
    return GestureDetector(
                                onTap: () {
                                  setState(() {
          _selectedServiceType = type;
          _estimatedPrice = null;
                                  });
        
        // ANA SAYFADA FİYAT HESAPLAMA KALD IR I LD I - SADECE 2. AŞAMADA OLACAK!
        // UX İy ileştirme: Kullanıcı 1. aşamada sadece planlamasın, fiyatı 2. aşamada görsün
        
        if (type == 'hourly' && _selectedHourlyPackage != null) {
          _calculateHourlyPrice(); // Saatlik paket fiyatını sadece paket seçiminde hesapla
        }
        // Vale fiyat hesaplama ana sayfada kaldırıldı - 2. aşamaya ertelendi
                                },
                                child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFFFFD700) 
              : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
            color: isSelected 
                ? const Color(0xFFFFD700) 
                : (themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
                                    ),
                                  ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
              icon,
              color: isSelected 
                  ? Colors.black 
                  : (themeProvider.isDarkMode ? Colors.white : Colors.black54),
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                                        style: TextStyle(
                                          fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected 
                      ? Colors.black 
                      : (themeProvider.isDarkMode ? Colors.white : Colors.black54),
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
    );
  }

  Widget _buildLocationSelector(
    String title, 
    String address, 
    IconData icon, 
    Color color, 
    VoidCallback onTap,
    {bool showMenu = false, VoidCallback? onMenuPressed}
  ) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return GestureDetector(
      onTap: onTap,
                                child: Container(
        padding: const EdgeInsets.all(16), // Büyütüldü 12→16
                                  decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
            color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
                            child: Row(
                              children: [
                          Container(
              padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                            ),
              child: Icon(icon, color: color, size: 20), // Büyütüldü 16→20
            ),
            const SizedBox(width: 12),
            Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                  Text(
                    title,
                                  style: TextStyle(
                      fontSize: 14, // Büyütüldü 12→14
                      fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4), // 2→4 daha geniş
                  Text(
                    address.isEmpty ? '$title seçin' : address,
                    style: TextStyle(
                      fontSize: 12, // Büyütüldü 11→12
                      color: address.isEmpty 
                          ? (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[500])
                          : (themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700]),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
            // 🔥 3 NOKTA MENÜ (Sadece "Nereden" için)
            if (showMenu && onMenuPressed != null)
              IconButton(
                onPressed: onMenuPressed,
                icon: const Icon(Icons.more_vert),
                color: const Color(0xFFFFD700),
                iconSize: 24,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 16, // Büyütüldü 14→16
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[400],
              ),
                              ],
                            ),
                          ),
    );
  }
  
  // 🔥 ARA DURAK SEÇİCİ (SİL BUTONU İLE)
  Widget _buildWaypointSelector(String title, String address, IconData icon, Color color, VoidCallback onTap, VoidCallback onDelete) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.isEmpty ? 'Ara durak seçin' : address,
                    style: TextStyle(
                      fontSize: 12,
                      color: address.isEmpty 
                          ? (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[500])
                          : (themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700]),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Sil butonu
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 20),
              color: Colors.red,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelectionWidget() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
        Text(
                                  'Vale Ne Zaman Gelsin?',
                                  style: TextStyle(
                                    fontSize: 14,
            fontWeight: FontWeight.w600,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                                  ),
                                ),
        const SizedBox(height: 8),
                                Row(
                                  children: [
            Expanded(child: _buildModernTimeOption('Hemen\n(Tahmini 30 Dk)')),
            const SizedBox(width: 6),
            Expanded(child: _buildModernTimeOption('1 Saat Sonra')),
            const SizedBox(width: 6),
            Expanded(child: _buildModernTimeOption('Özel Saat')),
                                  ],
                                ),
                              ],
    );
  }

  Widget _buildModernTimeOption(String option) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSelected = _selectedTimeOption == option;
    
    return GestureDetector(
      onTap: () async {
        setState(() {
          _selectedTimeOption = option;
        });
        
        if (option == 'Özel Saat') {
          _showCustomTimePicker();
        } else {
          setState(() {
            _selectedDateTime = null;
          });
          // 🔒 Long-term status temizle (unawaited - arka planda çalışsın)
          _updateLongTermTripStatus();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFFFFD700).withOpacity(0.2)
              : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFFFFD700)
                : (themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          ),
        ),
        child: Text(
          option,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isSelected 
                ? const Color(0xFFFFD700)
                : (themeProvider.isDarkMode ? Colors.white : Colors.black54),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCompactHourlyPackages() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          'Saatlik Paketler',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ..._hourlyPackages.map((package) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedHourlyPackage = package;
                _estimatedPrice = package.price;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _selectedHourlyPackage?.id == package.id
                    ? const Color(0xFFFFD700)
                    : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50]),
              borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedHourlyPackage?.id == package.id
                      ? const Color(0xFFFFD700)
                      : (themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    package.displayText,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selectedHourlyPackage?.id == package.id
                          ? Colors.black
                          : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
                  ),
                ),
                // İndirimli fiyat gösterimi saatlik paketler için
                _buildHourlyPackagePriceDisplay(package),
              ],
            ),
          ),
      ),
        )).toList(),
      ],
    );
  }

  void _selectLocation(String type) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    // 🔥 ARA DURAK İNDEXİ BELİRLE
    int? waypointIndex;
    if (type.startsWith('waypoint_')) {
      waypointIndex = int.tryParse(type.split('_')[1]);
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder( // MODAL İÇİ STATE FIX!
        builder: (BuildContext context, StateSetter setModalState) => Container(
        height: MediaQuery.of(context).size.height * 0.85, // BÜYÜK MODAL - KLAVYE UYUMLU!
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
              children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                type == 'pickup' 
                    ? 'Nereden?' 
                    : type == 'destination' 
                        ? 'Nereye?' 
                        : 'Ara Durak ${(waypointIndex ?? 0) + 1}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Search bar
              Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                      decoration: InputDecoration(
                  hintText: 'Konum ara... (örn: Watergarden, Adana)',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                        border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                  ),
                  filled: true,
                  fillColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                ),
                onChanged: (value) => _searchPlacesModalUltraFast(value, type, setModalState),
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            
            // ARAMA SONUÇLARI - DİREKT TEXTFIELD ALTINDA!
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Arama Sonuçları',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    ...(_searchResults.take(5).map((result) => _buildSearchResultItem(result, type))), // Max 5 sonuç
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Options - HEP GÖSTER (arama sonuçları da olsa)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Map selection option
                  _buildLocationOption(
                    icon: Icons.map,
                    title: 'Haritadan Seç',
                    subtitle: 'Harita üzerinden konum belirleyin',
                    onTap: () {
                      Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
                            initialLocation: _currentLocation, // CURRENT LOCATION İLE BAŞLAT!
                            onLocationSelected: (LatLng location, String address) {
            setState(() {
                                if (type == 'pickup') {
                _pickupLocation = location;
                _pickupAddress = address;
              } else {
                _destinationLocation = location;
                _destinationAddress = address;
              }
            });
                              
            // ANA SAYFADA VALE FİYAT HESAPLAMA KALD IR I LD I - 2. AŞAMAYA ERTELENDİ!
            // Konum seçiminde fiyat hesaplanmasın, sadece 2. aşamada hesaplansın
          },
        ),
      ),
    );
                    },
                    themeProvider: themeProvider,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Saved addresses option
                  _buildLocationOption(
                    icon: Icons.bookmark,
                    title: 'Kayıtlı Adresler',
                    subtitle: 'Kaydettiğiniz adreslerden seçin',
                    onTap: () => _showSavedAddresses(type),
                    themeProvider: themeProvider,
                  ),
                  
                  // Eski arama sonuçları kısmı kaldırıldı - şimdi TextField altında dropdown!
                ],
              ),
            ),
          ],
        ),
      ), // Container sonu
      ), // StatefulBuilder sonu
    );
  }

  // 1. AŞAMA - YOLCULUĞU PLANLA (FİYAT GÖSTERİLMİYOR!)
  void _callValet() async {
    print('🚀 === 2 AŞAMALI VALE SİSTEMİ - 1. AŞAMA BAŞLADI ===');
    
    // ÇİFT TALEP ENGELLEYİCİ - FRONTEND SİSTEMİ
    if (_isCreatingRideRequest) {
      print('❌ ÇİFT TALEP ENGELLENDİ: Zaten talep oluşturuluyor...');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bekleyin, talebiniz işleniyor...'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // KRİTİK: YENİ BORÇ KONTROL SİSTEMİ - HER İKİ SERVİS İÇİN! [[memory:9809153]]
    final canProceed = await checkCustomerDebtBeforeCall();
    if (!canProceed) {
      print('❌ Vale/Saatlik paket çağırma engellendi - bekleyen ödeme var');
      return; // Hem vale hem saatlik paket engellendi!
    }
    
    print('✅ Borç kontrolü başarılı - her iki servis için devam edilebilir');
    
    // VALE SERVİSİ KONTROLÜ
    if (_selectedServiceType == 'vale') {
      if (_pickupLocation == null || _destinationLocation == null) {
        _showValidationError('Lütfen nereden ve nereye konumlarını seçin');
        return;
      }
    } 
    // SAATLİK PAKET KONTROLÜ
    else if (_selectedServiceType == 'hourly') {
      if (_selectedHourlyPackage == null) {
        _showValidationError('Lütfen bir saatlik paket seçin');
        return;
      }
      
      // SAATLİK PAKET İÇİN KONUM ZORUNLU - GÜÇLENDİRİLMİŞ!
      if (_pickupLocation == null) {
        _showValidationError('Saatlik paket için nereden konumunu seçmeniz zorunludur. Lütfen konum seçin.');
        return;
      }
      
      // Saatlik paket seçimi kontrolü daha detaylı
      if (_selectedServiceType == 'hourly' && _selectedHourlyPackage == null) {
        _showValidationError('Lütfen bir saatlik paket seçin');
        return;
      }
    }

    // ZAMAN SEÇİMİ KONTROLÜ
    if (_selectedTimeOption == 'Seçiniz') {
      _showValidationError('Lütfen vale kaçta gelsin seçeneğini belirleyin');
      return;
    }
    
    print('✅ 1. Aşama validasyonları başarılı!');
    
    // 2. AŞAMAYA GEÇİŞ - FİYAT HESAPLAMA ZORUNLU!
    if (_selectedServiceType == 'vale' && _pickupLocation != null && _destinationLocation != null) {
      await _calculatePrice(); // FİYAT HESAPLANMADAN 2. AŞAMA AÇILMASIN!
      print('✅ Vale fiyatı hesaplandı: ₺${_estimatedPrice?.toStringAsFixed(2)}');
    } else if (_selectedServiceType == 'hourly' && _selectedHourlyPackage != null) {
      await _calculateHourlyPrice(); // Saatlik paket fiyatı da hesapla
      print('✅ Saatlik fiyatı hesaplandı: ₺${_estimatedPrice?.toStringAsFixed(2)}');
    }
    
    // Eğer fiyat hala null ise varsayılan değer ata
    if (_estimatedPrice == null) {
      print('⚠️ FİYAT NULL - Varsayılan değer atanıyor!');
      _estimatedPrice = _selectedServiceType == 'vale' ? 50.0 : (_selectedHourlyPackage?.price ?? 100.0);
    }
    
    _showSecondStagePaymentScreen();
  }
  
  // VALIDASYON HATASI GÖSTERME
  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  // 2. AŞAMA - ÖDEME VE ONAYLAMA EKRANI (PROFESYONEL!)
  void _showSecondStagePaymentScreen() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    print('💳 === 2. AŞAMA ÖDEME EKRANI AÇILIYOR ===');
    
    // TERMS ACCEPTED'ı FALSE YAP - KULLANICI ONAYLAMALI!
    setState(() {
      _termsAccepted = false;
    });
    
    // İlk olarak fiyat hesapla
    if (_selectedServiceType == 'vale') {
      _calculatePrice();
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.9, // DAHA YÜKSEK - KAYDIRMA İÇİN!
          decoration: BoxDecoration(
            color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header - KÜÇÜLTÜLMÜŞ!
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.payment,
                      color: const Color(0xFFFFD700),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Yolculuk Detayları',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              
              // KAYDIRILABİLİR İÇERİK!
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // YOLCULUK ÖZETİ - KOMPAKT
                    _buildCompactTripSummaryCard(themeProvider),
                    const SizedBox(height: 12),
                    
                    // TAHMİNİ FİYAT - KOMPAKT
                    _buildCompactPriceCard(themeProvider, setModalState),
                    const SizedBox(height: 12),
                    
                    // ÖDEME YÖNTEMİ VE İNDİRİM KODU KALDIRILDI - ÖDEME EKRANINDA OLACAK!
                    
                    // ÖN BİLGİLENDİRME KOŞULLARI - KOMPAKT
                    _buildCompactTermsCard(themeProvider, setModalState),
                    
                    const SizedBox(height: 20),
                    
                    // 2. AŞAMA BUTONLARI - VALE SEÇ + VALE ÇAĞIR!
                    Column(
                      children: [
                    // 2 SAAT ÜSTÜ UYARI MESAJI!
                    if (_isLongTermTripCache) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info, color: Colors.orange, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '⏰ 2 saat üstü seçimlerde kendi valenizi seçemezsiniz. Talep bekleyen rezervasyonlara gidecektir.',
                                style: TextStyle(
                                  color: Colors.orange[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // VALE SEÇ BUTONU - TAMAMEN GİZLİ!
                    Visibility(
                      visible: false, // KOMPLE GİZLİ - AÇILANA KADAR GÖRÜNMEZ
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: null, 
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.grey[600],
                            side: BorderSide(
                              color: Colors.grey[400]!,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_search, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                'Kendi Valeni Seç',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    // VEYA AYRAÇ - TAMAMEN GİZLİ (TEK BUTON KALDI)
                    Visibility(
                      visible: false, // KOMPLE GİZLİ
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.grey[400],
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'VEYA',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Colors.grey[400],
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    
                    // OTOM TİK VALE ÇAĞIR BUTONU
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canCallValet() ? () {
                          _finalizeValeCall();
                          Navigator.pop(context);
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.flash_auto, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              _selectedServiceType == 'vale' ? 'Vale Çağır' : 'Saatlik Paket Al',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                      ],
                    ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // VALE ÇAĞIRMA EKRANI - EKSİK METOD GERİ GETİRİLDİ!
  void _showValetCallScreen() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false, // İptal butonu ile kapatılsın
      enableDrag: false, // AŞAĞI KAYDIRMA İLE KAPANMASIN!
      builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.9, // 0.8 → 0.9: Daha büyük modal!
          decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
            // Handle bar
              Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
                decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Text(
              _selectedServiceType == 'vale' ? 'Vale Çağırılıyor' : 'Saatlik Paket Alınıyor',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Loading animation
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  strokeWidth: 4,
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Status text
            Text(
              'Yakınınızdaki valeler aranıyor...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            
            const SizedBox(height: 10),
            
            Text(
              'Bu işlem birkaç saniye sürebilir',
              style: TextStyle(
                fontSize: 14,
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Trip details
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
              ),
                child: Column(
                  children: [
                  if (_selectedServiceType == 'vale') ...[
                    _buildTripDetailRow('Nereden', _pickupAddress, Icons.location_on, Colors.green),
                    const SizedBox(height: 12),
                    _buildTripDetailRow('Nereye', _destinationAddress, Icons.location_on, Colors.red),
                    const SizedBox(height: 12),
                  ],
                  if (_selectedServiceType == 'hourly') ...[
                    _buildTripDetailRow('Paket', _selectedHourlyPackage?.displayText ?? '', Icons.access_time, const Color(0xFFFFD700)),
                    const SizedBox(height: 12),
                  ],
                  _buildTripDetailRow('Zaman', _selectedTimeOption, Icons.schedule, Colors.blue),
                  
                  // 🔥 ARA DURAK BİLGİSİ
                  if (_waypoints.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.route, color: Colors.orange, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Rota Detayı',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_waypoints.length} ara durak içeren rota',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '💡 Final fiyat sürücünün gerçek km\'sine göre hesaplanır',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  if (_estimatedPrice != null) ...[
                    const SizedBox(height: 12),
                    _buildTripDetailRow('Tahmini Fiyat', '₺${_estimatedPrice!.toStringAsFixed(2)}', Icons.payment, const Color(0xFFFFD700)),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 40), // Spacer → SizedBox: Daha kontrollü
            
            // Cancel button - TAM GÖZÜKSÜN!
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
              width: double.infinity,
                height: 50,
              child: ElevatedButton(
                  onPressed: () async {
                    // VALE ARAMA İPTAL ET - BACKEND'E DE BİLDİR!
                    print('❌ VALE ARAMA İPTAL EDİLİYOR - Backend iptal...');
                    
                    // 1. Arama durumunu iptal olarak işaretle
                    _searchCancelled = true;
                    
                    // 2. Timer'ı durdur
                    _driverSearchTimer?.cancel();
                    _driverSearchTimer = null;
                    
                    // 3. BACKEND'E İPTAL BİLDİR!
                    await _cancelActiveRideRequest();
                    
                    // 4. Arama durumunu sıfırla
                    setState(() {
                      _isSearchingForDriver = false;
                    });
                    
                    // 5. Ekranı kapat
                    Navigator.pop(context);
                    
                    print('✅ Vale arama + backend iptal başarıyla tamamlandı!');
                  },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'İptal Et',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
                    ),
            ],
          ),
      ),
    );

    // OTOM ATİK VALE ARAMA BAŞLA - MODAL AÇILDIKTAN HEMEN SONRA!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        print('🚀 Vale arama ekranı hazır - otomatik arama başlatılıyor!');
        _simulateValetSearch(context);
      }
    });
  }

  Widget _buildTripDetailRow(String title, String value, IconData icon, Color iconColor) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
              Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ], // Column children kapanışı
          ), // Column kapanışı
        ), // Expanded kapanışı  
      ], // Row children kapanışı
    ); // Row kapanışı
  }

  void _simulateValetSearch(BuildContext modalContext) async {
    try {
      print('🚀 GELİŞMİŞ VALE ARAMA SİSTEMİ BAŞLADI!');
      
      // 1. ARAMA DURUMUNU AKTIFLEŞTİR
      setState(() {
        _isSearchingForDriver = true;
        _searchCancelled = false;
      });
      
      // 2. TALEP ZATEN _finalizeValeCall() İÇİNDE OLUŞTURULDU - DUPLICATE KALDIRILDI!
      print('ℹ️ Ride talebi zaten oluşturuldu - duplicate engellendi');
      
      // 3. 60 SANİYE LİK TIMER BAŞLAT (GERÇEK ARAMA) - UZATILDI!
      _driverSearchTimer = Timer(const Duration(seconds: 60), () async {
        // Eğer arama iptal edilmediyse ve modal hala açıksa
        if (!_searchCancelled && modalContext.mounted) {
          try {
            print('⚠️ 60 saniye doldu - Vale bulunamadı!');
            
            // AKTİF TALEBİ İPTAL ET - MÜŞTERİ TEKRAR ÇAĞIRABLS!
            try {
              final adminApi = AdminApiProvider();
              final prefs = await SharedPreferences.getInstance();
              final customerId = prefs.getString('user_id') ?? '0';
              
              print('🚫 Vale bulunamadı - talep iade ediliyor...');
              
              // PROVİZYON KODLARI GİZLENDİ [[memory:9694916]]
              /*
              if (_provisionProcessed) {
                // Provizyon iade kodları
              }
              */
              
              // SONRA TALEBİ İPTAL ET  
              final cancelResult = await adminApi.cancelRideRequest(
                customerId: customerId,
                reason: 'no_driver_found_30sec_timeout',
              );
              
              if (cancelResult['success'] == true) {
                print('✅ Aktif talep + provizyon başarıyla iptal/iade edildi');
              } else {
                print('⚠️ Talep iptal uyarısı: ${cancelResult['message']}');
              }
            } catch (cancelError) {
              print('❌ Talep iptal hatası: $cancelError');
            }
            
            // Modal'ı kapat
            Navigator.of(modalContext).pop();
            
            // Ana context'te "vale bulunamadı" mesajı göster
            if (mounted) {
              await Future.delayed(const Duration(milliseconds: 500));
              _showDriverNotFoundDialog();
            }
          } catch (e) {
            print('❌ Vale arama timeout hatası: $e');
          }
        }
      });
      
      // 4. GERÇEK ZAMANLI SÜRÜCÜ TAKIP BAŞLAT
      _startRealTimeDriverSearch(modalContext);
      
    } catch (e) {
      print('❌ Vale arama sistem hatası: $e');
      setState(() {
        _isSearchingForDriver = false;
      });
    }
  }
  
  // GERÇEK ZAMANLI SÜRÜCÜ ARAMA VE KABUL TAKİBİ - PANEL API ENTEGRASYONU! (2s interval - HIZLI!)
  void _startRealTimeDriverSearch(BuildContext modalContext) {
    // ÖNCE ESKİ TALEPLERİ TEMİZLE!
    _cleanupExpiredRequestsCustomer();
    
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      // İptal kontrolü
      if (_searchCancelled || !modalContext.mounted) {
        timer.cancel();
        return;
      }
      
      try {
        // PANEL API'SİNDEN MÜŞTERİNİN AKTİF RIDE DURUMUNU KONTROL ET
        final prefs = await SharedPreferences.getInstance();
        final customerId = prefs.getString('user_id') ?? '0';
        
        final response = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/check_ride_status.php?customer_id=$customerId'),
          headers: {'Content-Type': 'application/json'},
        );
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('🔍 Ride durumu API response: $data');
          print('🔍 Success: ${data['success']}, Status: ${data['status']}');
          
          // API SUCCESS VE SÜRÜCÜ KABUL KONTROLÜ!
          if (data['success'] == true && (data['status'] == 'accepted' || data['status'] == 'confirmed')) {
            timer.cancel();
            _driverSearchTimer?.cancel();
            
            print('🎯 Vale bulundu ve KABUL ETTİ! Gerçek veri ile yolculuk ekranına geçiliyor...');
            
            // GERÇEK RIDE VERİLERİNİ ÇEKME!
            final realRideDetails = {
              'ride_id': data['ride_id']?.toString() ?? '0',
              'customer_id': customerId,
              'pickup_address': data['pickup_address'] ?? _pickupAddress,
              'destination_address': data['destination_address'] ?? _destinationAddress,
              'estimated_price': data['estimated_price']?.toString() ?? _estimatedPrice?.toString() ?? '0',
              'scheduled_time': data['scheduled_time'],
              'customer_name': data['customer_name'] ?? 'Müşteri',
              'customer_phone': data['customer_phone'] ?? '',
              'driver_info': data['driver'] != null ? {
                'id': data['driver']['id']?.toString() ?? '0',
                'name': data['driver']['name'] ?? 'Vale',
                'phone': data['driver']['phone'] ?? '',
                'rating': 4.8, // Varsayılan
              } : null,
              'status': data['status'],
              'created_at': data['created_at'],
              'accepted_at': data['accepted_at'],
            };
            
            print('📊 Gerçek ride detayları hazır: ${realRideDetails['ride_id']}');
            
            // VALE KABUL ETTİ - PROVİZYON KODLARI GİZLENDİ [[memory:9694916]]
            try {
              final rideIdFromApi = realRideDetails['ride_id']!;
              
              print('💳 Vale kabul etti - provizyon durumu kontrol ediliyor: Ride ID $rideIdFromApi');
              
              // PROVİZYON KODLARI TAMAMEN GİZLENDİ [[memory:9694916]]
              print('✅ Provizyon sistemi gizli - direkt yolculuk başlatılıyor');
              bool provisionSuccess = true; // PROVİZYON BYPASS
              
              if (provisionSuccess) {
                print('✅ Vale kabul etti + Provizyon çekildi - süreç tamamlandı!');
                
                if (modalContext.mounted) {
                  Navigator.of(modalContext).pop();
                }
                
                if (mounted) {
                  // GERÇEK VERİLER İLE YOLCULUK EKRANINA GİT!
                  _navigateToActiveRideScreenWithRealData(realRideDetails);
                }
              } else {
                print('⚠️ Vale kabul etti ama provizyon çekilemedi - süreç durduruluyor');
                // Provizyon çekilemedi, vale kaybedilecek ama talep iptal
                await _cancelCurrentRideRequest(reason: 'provision_failed_after_acceptance');
                
                if (modalContext.mounted) {
                  Navigator.of(modalContext).pop();
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Vale kabul etti ama provizyon alınamadı - yolculuk iptal edildi'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              }
            } catch (provisionError) {
              print('❌ Vale kabul etti ama provizyon hatası: $provisionError');
              
              if (modalContext.mounted) {
                Navigator.of(modalContext).pop();
              }
            }
          }
        } else {
          print('❌ API Response HTTP Error: ${response.statusCode}');
          print('📄 Response Body: ${response.body}');
        }
      } catch (e) {
        print('❌ Gerçek zamanlı arama hatası: $e');
        print('🔍 Error details: ${e.toString()}');
      }
    });
  }
  
  // SÜRÜCÜ BULUNDU DIALOG
  void _showDriverFoundDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            Text(
              'Vale Bulundu!',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Valeniz talebinizi kabul etti ve size doğru geliyor!',
          style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Yolculuk takip sayfasına yönlendir
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showDriverNotFoundDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.search_off, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text(
                'Vale Bulunamadı',
                style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        content: Text(
          '30 saniye içinde müsait vale bulunamadı. Rezervasyon yaparak daha sonra vale çağırabilirsiniz.',
                style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          // TAMAM BUTONU - SİYAH EKRAN SORUNU ÇÖZÜLDİ!
          TextButton(
            onPressed: () {
              print('🔒 Tamam butonuna basıldı - Siyah ekran engelleniyor');
              try {
                // Sadece dialog'ı kapat, başka hiçbir şey yapma
                Navigator.of(context).pop();
                print('✅ Dialog başarıyla kapatıldı');
              } catch (e) {
                print('❌ Dialog kapatma hatası: $e');
              }
            },
            child: Text(
              'Tamam',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              print('📞 Rezervasyon yap butonuna basıldı - Siyah ekran engelleniyor');
              try {
                // 1. Önce dialog'ı güvenli şekilde kapat
                Navigator.of(context).pop();
                
                // 2. Kısa bekleme sonrası telefon aramayı başlat
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    _makePhoneCallForReservation();
                  }
                });
                
                print('✅ Rezervasyon işlemi başlatıldı');
              } catch (e) {
                print('❌ Rezervasyon butonu hatası: $e');
              }
            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Rezervasyon Yap'),
          ),
        ],
      ),
    );
  }

  void _showReservationDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Text(
          'Rezervasyon',
          style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Rezervasyon sistemi yakında aktif olacak. Şimdilik tekrar deneyebilirsiniz.',
          style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Tamam',
              style: TextStyle(
                color: const Color(0xFFFFD700),
              ),
            ),
              ),
            ],
      ),
    );
  }

  void _createRideRequest() async {
    // Gerçek API çağrısı için AdminApiProvider kullanılabilir
    try {
      // Safe provider access - try-catch ile koru
      AdminApiProvider? adminApi;
      try {
        adminApi = Provider.of<AdminApiProvider>(context, listen: false);
      } catch (e) {
        print('⚠️ Provider context hatası - direkt AdminApiProvider kullanılıyor: $e');
        adminApi = AdminApiProvider();
      }
      
      final user = await adminApi.getCurrentUser();
      
      if (user != null) {
        if (_selectedServiceType == 'vale') {
          // DUPLICATE KALDIRILDI - _createAutomaticRideRequest() ZATEN ÇAĞRILIYOR!
          print('🚗 Normal vale talebi - duplicate kaldırıldı, _createAutomaticRideRequest() kullanılıyor!');
        } else if (_selectedServiceType == 'hourly' && _selectedHourlyPackage != null) {
          // SAATLİK VALE TALEBİ - BORÇ KONTROL + AKILLI SİSTEM! [[memory:9809153]]
          print('⏰ Saatlik vale talebi - borç kontrol + akıllı sistem ile!');
          
          // BORÇ KONTROL ZATEN _callValet() BAŞINDA YAPILDI - DUPLICATE KALDIRILDI
          
          final result = await _createHourlyRideRequest(user['id']);
          
          if (result['success'] == true) {
            print('✅ Saatlik vale talebi + akıllı sistem başarılı: ${result['ride_id']}');
            
            // AKILLI SİSTEM ZATEN create_ride_request.php İÇİNDE - DUPLICATE KALDIRILDI!
            print('🎯 Saatlik paket akıllı sistem backend\'de otomatik başlatıldı!');
          } else {
            print('❌ Saatlik vale talebi oluşturulamadı: ${result['message']}');
          }
        }
      }
    } catch (e) {
      print('Vale talebi oluşturma hatası: $e');
    }
  }

  // Saatlik vale talebi oluştur
  Future<Map<String, dynamic>> _createHourlyRideRequest(String customerId) async {
    try {
      // SAATLİK PAKET İÇİN DE AKILLI SİSTEM ENTEGRASYONU!
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/create_ride_request.php'), // AKILLI SİSTEM API
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.tryParse(customerId) ?? 0,
          'pickup_address': _pickupAddress,
          'destination_address': _pickupAddress, // SAATLİK PAKET - AYNI KONUM
          'pickup_lat': _pickupLocation!.latitude,
          'pickup_lng': _pickupLocation!.longitude,
          'destination_lat': _pickupLocation!.latitude, // SAATLİK PAKET - AYNI KONUM  
          'destination_lng': _pickupLocation!.longitude, // SAATLİK PAKET - AYNI KONUM
          'scheduled_time': (await _getCorrectScheduledTime()).toIso8601String(),
          'estimated_price': (_selectedHourlyPackage!.price) - _discountAmount,
          'payment_method': _selectedPaymentMethod,
          'request_type': 'immediate_or_soon',
          'ride_type': 'hourly', // SAATLİK PAKET BELİRTECİ
          'notes': 'Saatlik paket: ${_selectedHourlyPackage!.displayText}',
          'discount_code': _appliedDiscountCode ?? '',
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
    } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  Future<void> _showNotifications() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const NotificationsBottomSheet(),
    );

    // 🔥 BADGE REFRESH - Modal kapandıktan sonra yenile
    print('🔄 Modal kapandı - Badge sayısı yenileniyor...');
    await _refreshBadgeCount();
    print('✅ Bildirim bottom sheet kapatıldı - badge refresh edildi');
  }

  Future<void> _showCustomTimePicker() async {
    // 🔒 SERVER TIME AL!
    final serverNow = await TimeService.getServerTime();
    print('🕐 DatePicker açılıyor - Server time: $serverNow');
    
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: serverNow.add(const Duration(hours: 1)),
      firstDate: serverNow,
      lastDate: serverNow.add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFFFFD700),
              onPrimary: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (pickedDate != null) {
      // 🔒 SERVER TIME'A GÖRE BAŞLANGIÇ SAATİ
      final currentServerTime = await TimeService.getServerTime();
      final TimeOfDay initialTime = TimeOfDay(
        hour: currentServerTime.hour,
        minute: currentServerTime.minute,
      );
      
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFFFFD700),
                onPrimary: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );
      
      if (pickedTime != null) {
        final selectedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        
        // 🔒 GEÇMİŞ ZAMAN KONTROLÜ - SERVER TIME İLE!
        final checkServerTime = await TimeService.getServerTime();
        final timeDiff = selectedDateTime.difference(checkServerTime);
        
        print('🕐 Seçilen: $selectedDateTime');
        print('🕐 Server: $checkServerTime');
        print('⏱️ Fark: ${timeDiff.inMinutes} dakika');
        
        // GEÇMİŞ ZAMAN SEÇİLDİYSE UYARI VER!
        if (timeDiff.isNegative) {
          print('⚠️ GEÇMİŞ ZAMAN SEÇİLDİ - Uyarı veriliyor!');
          
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 28),
                  SizedBox(width: 12),
                  Text('Geçersiz Zaman'),
                ],
              ),
              content: const Text(
                'Geçmiş bir zaman seçtiniz. Lütfen gelecek bir tarih ve saat seçin.\n\nNot: Telefon saatiniz yanlış olabilir.',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
          
          return; // Geçmiş zamanı kaydetme!
        }
        
        // GEÇERLİ ZAMAN - KAYDET!
        setState(() {
          _selectedDateTime = selectedDateTime;
          _selectedTimeOption = 'Özel Saat\n${pickedDate.day}/${pickedDate.month} ${pickedTime.format(context)}';
        });
        
        // 🔒 Server time ile long-term kontrolü yap
        await _updateLongTermTripStatus();
      }
    }
  }

  void _showSavedAddresses(String type) async {
    Navigator.pop(context); // Bottom sheet'i kapat
    
    try {
      final addresses = await SavedAddressesService.getSavedAddresses();
      
      if (addresses.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Henüz kayıtlı adresiniz yok. Ayarlar > Adreslerim\'den ekleyebilirsiniz.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
        ),
      );
      return;
    }

      // Kayıtlı adresler listesi göster
      showModalBottomSheet(
      context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _buildSavedAddressesSheet(addresses, type),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Adresler yüklenirken hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSavedAddressesSheet(List<SavedAddress> addresses, String type) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
          // Handle bar
            Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 4,
              decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
            
            // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Kayıtlı Adresler',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Addresses list
                    Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final address = addresses[index];
                return _buildSavedAddressItem(address, type);
              },
            ),
                ),
              ],
            ),
    );
  }

  Widget _buildSavedAddressItem(SavedAddress address, String type) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // Sheet'i kapat
        
                        setState(() {
          final location = LatLng(address.latitude, address.longitude);
          if (type == 'pickup') {
            _pickupLocation = location;
            _pickupAddress = address.address;
          } else {
            _destinationLocation = location;
            _destinationAddress = address.address;
          }
        });

        // Haritayı güncelle
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(address.latitude, address.longitude),
              15,
      ),
    );
  }

        // Fiyat hesapla
        if (_selectedServiceType == 'vale' && _pickupLocation != null && _destinationLocation != null) {
          _calculatePrice();
        }

        // Son kullanım tarihini güncelle
        SavedAddressesService.markAddressAsUsed(address.id);
      },
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
            children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getAddressTypeIcon(address.type),
                color: const Color(0xFFFFD700),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.name,
                style: TextStyle(
                  fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
              Text(
                    address.address,
                style: TextStyle(
                      fontSize: 12,
                      color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
            ),
            if (address.isFavorite)
              const Icon(
                Icons.favorite,
                color: Colors.red,
                size: 16,
              ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAddressTypeIcon(AddressType type) {
    switch (type) {
      case AddressType.home:
        return Icons.home;
      case AddressType.work:
        return Icons.work;
      case AddressType.hotel:
        return Icons.hotel;
      case AddressType.airport:
        return Icons.flight;
      case AddressType.hospital:
        return Icons.local_hospital;
      case AddressType.school:
        return Icons.school;
      case AddressType.shopping:
        return Icons.shopping_cart;
      default:
        return Icons.location_on;
    }
  }

  // İndirim kodu girme alanı
  Widget _buildDiscountCodeSection() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
            ),
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
            'İndirim Kodu',
                style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
          const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                  controller: _discountCodeController,
                  scrollPadding: const EdgeInsets.only(bottom: 150), // KLAVYE İÇİN SCROLL PADDING!
                  autofocus: false, // Otomatik focus'u kapat
                  textInputAction: TextInputAction.done, // Done butonu ekle
                  textCapitalization: TextCapitalization.characters, // Büyük harf
                  maxLength: 20, // Maksimum uzunluk
                  decoration: InputDecoration(
                    hintText: 'İndirim kodunu girin',
                    prefixIcon: const Icon(Icons.local_offer, color: Color(0xFFFFD700), size: 20),
                    counterText: '', // Karakter sayacını gizle
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: themeProvider.isDarkMode ? Colors.grey[700] : Colors.white,
                  ),
                  style: TextStyle(
                    color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600, // Yazıları belirginleştir
                  ),
                  onSubmitted: (value) {
                    // Enter'a basıldığında klavyeyi kapat
                    FocusScope.of(context).unfocus();
                  },
                  onTap: () {
                    // Tıklandığında scroll'u ayarla  
                    Future.delayed(const Duration(milliseconds: 300), () {
                      Scrollable.ensureVisible(
                        context,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _applyDiscountCode(setState),
                      style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text(
                  'Uygula',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          // İndirim uygulandıysa göster
            if (_appliedDiscountCode != null) ...[
            const SizedBox(height: 8),
              Container(
              padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                    Expanded(
                    child: Text(
                      '$_appliedDiscountCode kodu uygulandı (₺${_discountAmount.toStringAsFixed(2)} indirim)',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeDiscountCode,
                    child: const Icon(Icons.close, color: Colors.green, size: 16),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // İndirim kodu uygula
  // ESKİ DUPLİCATE METHOD SİLİNDİ

  // İndirim kodunu kaldır
  void _removeDiscountCode() {
    setState(() {
      _appliedDiscountCode = null;
      _discountAmount = 0.0;
    });
  }

  // Fiyat gösterimi (indirimli/normal)
  Widget _buildPriceDisplay() {
    if (_estimatedPrice == null) return const SizedBox();
    
    final double finalPrice = _estimatedPrice! - _discountAmount;
    
    if (_appliedDiscountCode != null && _discountAmount > 0) {
      // İndirimli fiyat gösterimi
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Eski fiyat (üstü çizili)
          Text(
            '₺${_estimatedPrice!.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          // Yeni fiyat
          Text(
            '₺${finalPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD700),
            ),
          ),
        ],
      );
    } else {
      // Normal fiyat gösterimi
      return Text(
        '₺${_estimatedPrice!.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFD700),
        ),
      );
    }
  }

  // Saatlik paket fiyat gösterimi (indirimli/normal)
  Widget _buildHourlyPackagePriceDisplay(HourlyPackage package) {
    final bool isSelected = _selectedHourlyPackage?.id == package.id;
    final double finalPrice = package.price - (_appliedDiscountCode != null ? _discountAmount : 0);
    
    if (_appliedDiscountCode != null && _discountAmount > 0) {
      // İndirimli fiyat gösterimi
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Eski fiyat (üstü çizili)
          Text(
            '₺${package.price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.black54 : Colors.grey,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          // Yeni fiyat
          Text(
            '₺${finalPrice.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.black : const Color(0xFFFFD700),
            ),
          ),
        ],
      );
    } else {
      // Normal fiyat gösterimi
      return Text(
        '₺${package.price.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.black : const Color(0xFFFFD700),
        ),
      );
    }
  }

  // MODAL İÇİ GOOGLE PLACES ARAMA - setModalState İLE!
  void _searchPlacesModal(String query, String type, StateSetter setModalState) {
    print('🔍 Modal real-time arama başlatıldı: "$query" (type: $type)');
    
    // Önceki timer'ı iptal et
    _searchDebounce?.cancel();
    
    if (query.isEmpty) {
      print('🔍 Query boş, modal sonuçlar temizleniyor');
      setModalState(() {
        _searchResults = [];
      });
      return;
    }

    // 150ms debounce - ULTRA RESPONSIVE modal search!
    _searchDebounce = Timer(const Duration(milliseconds: 150), () async {
      try {
        print('🔍 MODAL LocationSearchService.getPlaceAutocomplete çağrılıyor...');
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        print('🔍 MODAL ${results.length} sonuç alındı');
        
        if (mounted) { // Widget hala active mi kontrol
          setModalState(() { // setModalState kullan!
            _searchResults = results;
          });
          
          print('🔍 MODAL UI güncellendi, _searchResults.length: ${_searchResults.length}');
        }
        
      } catch (e) {
        print('❌ MODAL arama hatası: $e');
        if (mounted) {
          setModalState(() {
            _searchResults = [];
          });
        }
      }
    });
  }
  
  // ULTRA HIZLI MODAL ARAMA - YENİ GELİŞMİŞ SİSTEM!
  void _searchPlacesModalUltraFast(String query, String type, StateSetter setModalState) {
    print('⚡ ULTRA HIZLI MODAL arama: "$query" (type: $type)');
    
    // Önceki timer'ı iptal et
    _searchDebounce?.cancel();
    
    if (query.isEmpty) {
      print('🔍 Query boş - arama sonuçları kaybolsun + geçmiş aramalar sabit kalsın');
      setModalState(() {
        _searchResults = []; // Arama sonuçlarını kaybet
      });
      return;
    }

    // SÜPER HIZLI RESPONSE - 30ms debounce! (150ms → 30ms)
    _searchDebounce = Timer(const Duration(milliseconds: 30), () async {
      try {
        print('⚡ SÜPER HIZLI API çağrısı başlatıldı...');
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        print('✅ ${results.length} sonuç SÜPER HIZLI alındı (30ms)');
        
        if (mounted && query.isNotEmpty) { // Query hala dolu mu kontrol
          setModalState(() {
            _searchResults = results;
          });
          
          print('⚡ SÜPER HIZLI UI güncellendi');
        }
        
      } catch (e) {
        print('❌ SÜPER HIZLI arama hatası: $e');
        if (mounted) {
          setModalState(() {
            _searchResults = [];
          });
        }
      }
    });
  }
  
  // Google Places API ile arama - ESKİ SİSTEM
  void _searchPlaces(String query, String type) {
    print('🔍 Real-time arama başlatıldı: "$query" (type: $type)');
    
    // Önceki timer'ı iptal et
    _searchDebounce?.cancel();
    
    if (query.isEmpty) {
      print('🔍 Query boş, sonuçlar temizleniyor');
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // ULTRA RESPONSIVE - İLK HARFTEN İTİBAREN ARAMA!

    // 150ms debounce - ULTRA RESPONSIVE real-time search!
    _searchDebounce = Timer(const Duration(milliseconds: 150), () async {
      try {
        print('🔍 LocationSearchService.getPlaceAutocomplete çağrılıyor...');
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        print('🔍 ${results.length} sonuç alındı');
        
        if (mounted) { // Widget hala active mi kontrol
          setState(() {
            _searchResults = results;
          });
          
          // FORCED UI UPDATE - eğer modal içindeyse  
          print('🔄 FORCED UI UPDATE - setState called for ${results.length} results');
          
          // Modal içi state için ekstra trigger
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
              print('🔄 Post-frame setState triggered for UI refresh');
            }
          });
        }
        
        print('🔍 UI güncellendi, _searchResults.length: ${_searchResults.length}');
      } catch (e) {
        print('❌ Arama hatası: $e');
        if (mounted) {
          setState(() {
            _searchResults = [];
          });
        }
      }
    });
  }

  // Arama sonucu seçildiğinde
  void _selectSearchResult(PlaceAutocomplete result, String type) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(result.placeId);
      if (details != null) {
        Navigator.pop(context); // Bottom sheet'i kapat
        
        setState(() {
          final location = LatLng(details.latitude, details.longitude);
          
          // 🔥 WAYPOINT KONTROLÜ
          if (type.startsWith('waypoint_')) {
            final index = int.tryParse(type.split('_')[1]);
            if (index != null && index >= 0 && index < _waypoints.length) {
              _waypoints[index] = {
                'address': details.formattedAddress,
                'location': location,
              };
              print('✅ Waypoint $index güncellendi: ${details.formattedAddress}');
              print('📍 Toplam waypoint sayısı: ${_waypoints.length}');
              print('📍 Waypoint listesi: $_waypoints');
            } else {
              print('⚠️ Waypoint index hatalı: $index (toplam: ${_waypoints.length})');
            }
          } else if (type == 'pickup') {
            _pickupLocation = location;
            _pickupAddress = details.formattedAddress;
          } else if (type == 'destination') {
            _destinationLocation = location;
            _destinationAddress = details.formattedAddress;
          }
          
          _searchResults = []; // Arama sonuçlarını temizle
        });

        // Haritayı güncelle
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(details.latitude, details.longitude),
              15,
            ),
          );
        }

        // Fiyat hesapla
        if (_selectedServiceType == 'vale' && _pickupLocation != null && _destinationLocation != null) {
          _calculatePrice();
        }
      }
    } catch (e) {
      print('Konum seçme hatası: $e');
    }
  }

  // Arama sonucu widget'ı - DROPDOWN STYLE!
  Widget _buildSearchResultItem(PlaceAutocomplete result, String type) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return GestureDetector(
      onTap: () => _selectSearchResult(result, type),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // Dropdown için kompakt
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Daha rahat tıklama
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[700]!.withOpacity(0.3) : Colors.grey[100], // Hover effect
          borderRadius: BorderRadius.circular(8),
          // Border kaldırıldı - dropdown clean görünüm
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFFFFD700),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
        child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                    result.mainText,
              style: TextStyle(
                      fontSize: 14,
                fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
            ),
                  if (result.secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
            Text(
                      result.secondaryText,
              style: TextStyle(
                        fontSize: 12,
                        color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // Konum seçenek widget'ı
  Widget _buildLocationOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ThemeProvider themeProvider,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFFFFD700), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
            title,
            style: TextStyle(
                      fontSize: 14,
              fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
              fontSize: 12,
                      color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // TELEFON ARAMA FONKSİYONLARI - SİYAH EKRAN SORUNU ÇÖZÜLDİ!
  Future<void> _makePhoneCallForReservation() async {
    try {
      print('📞 Rezervasyon için telefon araması başlatılıyor...');
      
      // DİNAMİK TELEFON NUMARASI - PANEL SİSTEM AYARLARINDAN!
      String phoneNumber = DynamicContactService.getSupportPhone();
      print('📞 Panel ayarlarından telefon: $phoneNumber');
      
      // Telefon arama dialog'u göster
      _showCallConfirmationDialog(phoneNumber);
      
    } catch (e) {
      print('❌ Telefon arama hatası: $e');
    }
  }
  
  // TELEFON ARAMA ONAY DIALOG
  void _showCallConfirmationDialog(String phoneNumber) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.phone, color: Color(0xFFFFD700), size: 28),
            const SizedBox(width: 12),
            Text(
              'Rezervasyon Hattı',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DynamicContactService.getCompanyName()} müşteri hizmetlerini (${DynamicContactService.getSupportPhone()}) arayarak rezervasyon yapabilirsiniz.',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: Color(0xFFFFD700)),
                  const SizedBox(width: 12),
                  Text(
                    phoneNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(
              'İptal',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchPhoneCall(phoneNumber);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Ara'),
          ),
        ],
      ),
    );
  }
  
  // TELEFON ARAMA BAŞLATMA
  Future<void> _launchPhoneCall(String phoneNumber) async {
    try {
      // url_launcher paketini kullanarak telefon araması başlat
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      
      // Burada url_launcher ile telefon araması başlatabilirsiniz
      // await launchUrl(phoneUri);
      
      print('✅ Telefon araması başlatıldı: $phoneNumber');
    } catch (e) {
      print('❌ Telefon arama başlatma hatası: $e');
    }
  }

  // === 2. AŞAMA HELPER FONKSİYONLARI - PROFESYONEL UX ===
  
  // YOLCULUK ÖZETİ KARTI
  Widget _buildTripSummaryCard(ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Yolculuk Özeti',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_selectedServiceType == 'vale') ...[
            _buildTripDetailRow('Nereden', _pickupAddress, Icons.location_on, Colors.green),
            const SizedBox(height: 12),
            _buildTripDetailRow('Nereye', _destinationAddress, Icons.location_on, Colors.red),
            const SizedBox(height: 12),
          ],
          
          if (_selectedServiceType == 'hourly') ...[
            _buildTripDetailRow('Paket', _selectedHourlyPackage?.displayText ?? '', Icons.access_time, const Color(0xFFFFD700)),
            const SizedBox(height: 12),
          ],
          
          _buildTripDetailRow('Zaman', _selectedTimeOption, Icons.schedule, Colors.blue),
          _buildTripDetailRow('Servis Türü', _selectedServiceType == 'vale' ? 'Vale Servisi' : 'Saatlik Paket', Icons.category, Colors.purple),
        ],
      ),
    );
  }
  
  // FİYAT KARTI (2. AŞAMADA GÖSTER!)
  Widget _buildPriceCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Fiyat Detayları',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // ORIJINAL FIYAT
          if (_originalPrice != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tahmini Fiyat:',
                  style: TextStyle(
                    fontSize: 16,
                    color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                Text(
                  '₺${_originalPrice!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    decoration: _discountAmount > 0 ? TextDecoration.lineThrough : null,
                    color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // İNDİRİM
          if (_discountAmount > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'İndirim:',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '-₺${_discountAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          const Divider(),
          
          // TOPLAM FİYAT
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Toplam Fiyat:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₺${(_estimatedPrice ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // ÖDEME YÖNTEMİ KARTI
  Widget _buildPaymentMethodCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.credit_card,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Ödeme Yöntemi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // HAVALE/EFT SEÇENEĞİ - HAFIZADAN RESTORE [[memory:9694916]]
          GestureDetector(
            onTap: () {
              setModalState(() {
                _selectedPaymentMethod = 'havale_eft';
              });
              print('✅ Havale/EFT seçildi');
              _showHavaleEftInfo();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedPaymentMethod == 'havale_eft' 
                  ? const Color(0xFFFFD700).withOpacity(0.1) 
                  : (themeProvider.isDarkMode ? Colors.grey[700] : Colors.white),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedPaymentMethod == 'havale_eft' 
                    ? const Color(0xFFFFD700) 
                    : Colors.grey[300]!
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance, 
                    color: _selectedPaymentMethod == 'havale_eft' 
                      ? const Color(0xFFFFD700) 
                      : Colors.orange
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Havale / EFT',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          'Banka havalesi ile ödeme',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedPaymentMethod == 'havale_eft')
                    Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // KAYITLI KARTLAR (PLACEHOLDER)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: themeProvider.isDarkMode ? Colors.grey[700] : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.credit_card, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kayıtlı Kart (**** 1234)',
                    style: TextStyle(
                      fontSize: 16,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // YENİ KART EKLE
          GestureDetector(
            onTap: () {
              // Yeni kart ekleme sayfasına yönlendir
              print('💳 Yeni kart ekleme sayfası açılacak');
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD700)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_card, color: Color(0xFFFFD700)),
                  const SizedBox(width: 12),
                  Text(
                    'Yeni Kart Ekle',
                    style: TextStyle(
                      fontSize: 16,
                      color: const Color(0xFFFFD700),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // GELIŞTİRİLMİŞ İNDİRİM KODU SİSTEMİ - SİLME/DEĞİŞTİRME/TEK KOD!
  Widget _buildDiscountCodeCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.discount,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'İndirim Kodu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              if (_appliedDiscountCode != null)
                Text(
                  'Tek kod sınırı',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // UYGULANMIŞ İNDİRİM KODU VARSA GÖSTER
          if (_appliedDiscountCode != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uygulanan Kod: $_appliedDiscountCode',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'İndirim: ₺${_discountAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // DEĞİŞTİR BUTONU
                  IconButton(
                    onPressed: () {
                      setModalState(() {
                        _removeDiscountCode();
                        _discountCodeController.clear();
                      });
                    },
                    icon: const Icon(Icons.edit, color: Colors.orange, size: 18),
                    tooltip: 'Değiştir',
                  ),
                  // SİL BUTONU
                  IconButton(
                    onPressed: () => _removeDiscountCode(),
                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                    tooltip: 'Kaldır',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // YENİ KOD EKLEME ENGELİ
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sadece bir indirim kodu kullanılabilir. Değiştirmek için mevcut kodu kaldırın.',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // YENİ İNDİRİM KODU GİRİŞİ - KLAVYE GÖRÜNÜR!
            Container(
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[700] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _discountCodeController,
                decoration: InputDecoration(
                  hintText: 'İndirim kodunuzu girin (örn: WELCOME10)',
                  hintStyle: TextStyle(
                    color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  prefixIcon: const Icon(Icons.local_offer, color: Color(0xFFFFD700)),
                  suffixIcon: IconButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus(); // Klavyeyi kapat
                      _applyDiscountCode(setModalState);
                    },
                    icon: const Icon(Icons.check, color: Color(0xFFFFD700)),
                    tooltip: 'Uygula',
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  counterText: '', // Karakter sayacı gizle
                ),
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16, // 14 → 16 daha görünür
                  fontWeight: FontWeight.w600,
                ),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                maxLength: 20,
                scrollPadding: const EdgeInsets.only(bottom: 400), // 300 → 400 daha fazla scroll
                onSubmitted: (value) {
                  FocusScope.of(context).unfocus(); // Enter'da klavyeyi kapat
                  if (value.isNotEmpty) {
                    _applyDiscountCode(setModalState);
                  }
                },
                onTap: () {
                  // GÜÇLÜ SCROLL SİSTEMİ - KLAVYE AÇILINCA YUARI KAYDIR!
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted) {
                      // Manuel scroll ile TextField'ı görünür yap
                      final renderObject = context.findRenderObject();
                      if (renderObject != null) {
                        renderObject.showOnScreen(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    }
                  });
                  
                  // Ek scroll - daha agresif
                  Future.delayed(const Duration(milliseconds: 500), () {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                    );
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '💡 İpucu: Geçerli kodlar panel tarafından oluşturulur',
              style: TextStyle(
                fontSize: 11,
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // ÖN BİLGİLENDİRME KOŞULLARI KARTI
  
  Widget _buildTermsAndConditionsCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gavel,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Yasal Koşullar (Zorunlu)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // ZORUNLU ONAY KUTUCUĞU
          GestureDetector(
            onTap: () {
              setModalState(() {
                _termsAccepted = !_termsAccepted;
              });
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _termsAccepted ? const Color(0xFFFFD700) : Colors.transparent,
                    border: Border.all(
                      color: _termsAccepted ? const Color(0xFFFFD700) : Colors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _termsAccepted
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque, // TIKLAMA ALANINI GENİŞLET!
                            onTap: () {
                              print('📄 Ön Bilgilendirme Koşullarına tıklandı');
                              _openTermsScreen('conditions');
                            },
                            child: Text(
                              'Ön Bilgilendirme Koşulları',
                              style: TextStyle(
                                color: const Color(0xFFFFD700),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' ve '),
                        WidgetSpan(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque, // TIKLAMA ALANINI GENİŞLET!
                            onTap: () {
                              print('📄 Mesafeli Satış Sözleşmesine tıklandı');
                              _openTermsScreen('contract');
                            },
                            child: Text(
                              'Mesafeli Satış Sözleşmesi',
                              style: TextStyle(
                                color: const Color(0xFFFFD700),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: '\'ni okudum ve onaylıyorum.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (!_termsAccepted) ...[
            const SizedBox(height: 8),
            Text(
              '⚠️ Vale çağırabilmek için koşulları onaylamanız gereklidir.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // VALE ÇAĞIRABILIR MI KONTROLÜ
  bool _canCallValet() {
    // DEBUG BİLGİSİ - BUTON NEDEN ÇALIŞMIYOR?
    bool termsOK = _termsAccepted;
    bool priceOK = _estimatedPrice != null;
    bool notLoading = !_isLoading; // LOADING DURUMU KONTROLÜ!
    
    print('📊 BUTON DURUM KONTROLÜ:');
    print('   Terms kabul edildi: $termsOK');
    print('   Fiyat var: $priceOK (fiyat: ₺${_estimatedPrice?.toStringAsFixed(2)})');
    print('   Loading değil: $notLoading');
    print('   Buton aktif: ${termsOK && priceOK && notLoading}');
    
    return termsOK && priceOK && notLoading;
  }
  
  // FİNAL VALE ÇAĞIRMA - 2. AŞAMA TAMAMLANDIKTAN SONRA
  void _finalizeValeCall() async {
    print('🎉 === 2. AŞAMA TAMAMLANDI - VALE ÇAĞIRMA ===');
    
    // BORÇ KONTROL ZATEn _callValet() BAŞINDA YAPILDI - DUPLICATE KALDIRILDI
    
    // ANLIK LOADING BAŞLAT - ÇOKLU TALEP ENGELLEME!
    setState(() {
      _isLoading = true;
    });
    
    try {
      // ZAMAN KONTROLÜ - 2+ SAAT İLERİ Mİ?
      // 🔒 GÜVENLİK: SERVER TIME KULLAN!
      final selectedTime = _selectedDateTime ?? await TimeService.getServerTime();
      final currentTime = await TimeService.getServerTime(); // ❌ DateTime.now() KULLANMA!
      final timeDifference = selectedTime.difference(currentTime);
      
      print('🕐 [REZERVASYON KONTROLÜ] Server time: $currentTime');
      print('📅 [REZERVASYON KONTROLÜ] Selected time: $selectedTime');
      print('⏱️ [REZERVASYON KONTROLÜ] Fark: ${timeDifference.inHours} saat ${timeDifference.inMinutes % 60} dakika');
      
      if (timeDifference.inHours >= 2) {
        // 2+ SAAT İLERİ - REZERVASYON SİSTEMİ!
        print('⏰ 2+ saat ileri talep (${timeDifference.inHours}h) - rezervasyon sistemine yönlendiriliyor...');
        
        setState(() {
          _isLoading = false; // Loading'i durdur
        });
        
        await _createScheduledRideReservation();
        return;
      } else {
        // 2 SAATTEN AZ - NORMAL VALE ÇAĞIRMA
        print('🚀 Normal vale talebi (<2 saat) - vale arama başlatılıyor...');
      }
      
      // 1. ADIM: VALE TALEBİ OLUŞTUR - AKILLI SİSTEM!
      print('🚀 Vale talebi oluşturuluyor - akıllı sistem ile arama yapılacak!');
      
      // 2. ADIM: RIDE TALEBİ OLUŞTUR - AKILLI ENTEGRASYON!
      await _createAutomaticRideRequest();
    
      // 3. ADIM: VALE ÇAĞIR EKRANI
      _showValetCallScreen();
      
      // LOADING'İ KAPAT - EKRAN AÇILDI!
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Vale çağırma hatası: $e');
      // Hata durumunda loading'i kapat
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // OTOMATİK RIDE TALEBİ OLUŞTURMA
  Future<void> _createAutomaticRideRequest() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // SAATLİK PAKET: Sadece pickup zorunlu, destination isteğe bağlı!
      if (_selectedHourlyPackage != null) {
        // SAATLİK PAKET - SADECE PICKUP KONTROL
        if (_pickupLocation == null) {
          print('❌ SAATLİK PAKET: Başlangıç konumu seçilmedi');
          setState(() {
            _isLoading = false;
          });
          return;
        }
        
        // Destination yoksa pickup ile aynı yap!
        if (_destinationLocation == null) {
          _destinationLocation = _pickupLocation;
          _destinationAddress = _pickupAddress + ' (Saatlik Paket)';
          print('✅ SAATLİK PAKET: Destination = Pickup (aynı konum)');
        }
        print('✅ SAATLİK PAKET: Hazır - Pickup OK');
      } else {
        // NORMAL VALE - HEM PICKUP HEM DESTINATION ZORUNLU!
        if (_pickupLocation == null || _destinationLocation == null) {
          print('❌ Konum bilgileri eksik');
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      
      print('🚗 === OTOMATIK RIDE + AKILLI TALEP SİSTEMİ ===');
      print('📍 Pickup: $_pickupAddress (${_pickupLocation!.latitude}, ${_pickupLocation!.longitude})');
      print('🎯 Destination: $_destinationAddress (${_destinationLocation!.latitude}, ${_destinationLocation!.longitude})');
      print('💰 Estimated Price: ₺${_estimatedPrice ?? 0.0}');
      print('👤 Customer ID: ${authProvider.customerId}');
      print('⏰ Seçilen zaman: $_selectedTimeOption');
      print('🎯 AKILLI SİSTEM: create_ride_request.php içinde 15sn 10km → 15sn 100km otomatik!');
      
      // ZAMAN BAZLI RİDE OLUŞTUR - DETAYLI ZAMAN LOGu!
      DateTime? scheduledDateTime;
      String timeLog = '';
      
      if (_selectedTimeOption != 'Hemen') {
        if (_selectedDateTime != null) {
          // Özel tarih seçilmişse onu kullan
          scheduledDateTime = _selectedDateTime!;
          timeLog = _selectedDateTime!.toIso8601String();
          print('🕰️ Özel tarih talep: $_selectedDateTime ($timeLog)');
        } else {
          // ❌ PHONE TIME KULLANMA! _getCorrectScheduledTime() kullan!
          // Bu kısım artık kullanılmayacak, _getCorrectScheduledTime() server time kullanıyor
          print('⚠️ Otomatik seçenek - _getCorrectScheduledTime() kullanılacak');
          // scheduledDateTime burada boş kalacak, _getCorrectScheduledTime() set edecek
          timeLog = 'AUTO_CALCULATED';
          print('🕰️ Otomatik zaman talep: $_selectedTimeOption → $scheduledDateTime ($timeLog)');
        }
      } else {
        scheduledDateTime = DateTime.now();
        timeLog = 'Hemen talep';
        print('⚡ Hemen talep: $scheduledDateTime');
      }
      
      // MERKEZİ FONKSİYON İLE DOĞRULAMA - SERVER TIME!
      final centralTime = await _getCorrectScheduledTime();
      print('⏰ Final scheduled_time: ${scheduledDateTime?.toIso8601String() ?? 'NULL'}');
      print('⏰ Central validation (SERVER): ${centralTime.toIso8601String()}');
      print('📝 _selectedTimeOption: $_selectedTimeOption');
      
      // Central fonksiyonu kullan - SERVER BAZLI!
      scheduledDateTime = centralTime;
      
      // YENİ RideService ile talep oluştur - AKILLI SİSTEM!
      final result = await RideService.createRideRequest(
        customerId: int.tryParse(authProvider.customerId ?? '1') ?? 1,
        pickupLocation: _pickupAddress,
        destination: _destinationAddress,
        serviceType: _selectedServiceType,
        requestType: _selectedTimeOption == 'Hemen' ? 'immediate_or_soon' : 'scheduled_later',
        scheduledDateTime: scheduledDateTime.toIso8601String(),
        selectedDriverId: 0, // Akıllı sistem - otomatik seçim
        estimatedPrice: _estimatedPrice,
        discountCode: _appliedDiscountCode,
        pickupLat: _pickupLocation?.latitude ?? 0.0,
        pickupLng: _pickupLocation?.longitude ?? 0.0,
        destinationLat: _destinationLocation?.latitude ?? 0.0,
        destinationLng: _destinationLocation?.longitude ?? 0.0,
        waypoints: _waypoints, // 🔥 ARA DURAKLAR GÖNDERİLİYOR
      );
      
      print('📡 === PANEL API RESPONSE ===');
      print('🔄 Success: ${result['success']}');
      print('💬 Message: ${result['message'] ?? 'Mesaj yok'}');
      print('📊 Full Result: $result');
      
      if (result['success'] == true) {
        print('✅ Panel API BAŞARILI!');
        print('🆔 Request ID: ${result['data']?['request_id'] ?? result['ride_id'] ?? 'ID yok'}');
        print('📱 Nearby Drivers: ${result['data']?['nearby_drivers_count'] ?? 0}');
        print('✅ Otomatik ride talebi BAŞARIYLA oluşturuldu!');
        
        // AKILLI SİSTEM ZATEN create_ride_request.php İÇİNDE ÇALIŞIYOR - DUPLICATE KALDIRILDI!
        print('🎯 Akıllı sistem create_ride_request.php içinde otomatik başlatıldı - frontend duplicate yok!');
      } else {
        print('❌ Panel API BAŞARISIZ!');
        print('🚨 Error: ${result['message']}');
        print('🔍 Debug: Bu talep panele ulaşmadı!');
        print('❌ Otomatik ride talebi OLUŞTURULAMADI!');
        
        // Kullanıcıya hata göster
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Talep oluşturulamadı: ${result['message']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('❌ Otomatik ride talebi oluşturma hatası: $e');
      
      // HATA DURUMUNDA LOADING'İ KAPAT VE UYARI GÖSTER
      setState(() {
        _isLoading = false;
      });
      
      // Aktif talep hatası ise özel uyarı göster
      if (e.toString().contains('Zaten aktif bir talebiniz bulunmaktadır')) {
        _showActiveRideWarning();
      } else {
        // Diğer hatalar için genel uyarı
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Talep oluşturulamadı: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  // AKTİF TALEP UYARISI
  void _showActiveRideWarning() {
    // Vale arama ekranını iptal et
    setState(() {
      _isLoading = false;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Aktif Talebiniz Var', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zaten aktif bir talebiniz bulunmaktadır. Yeni talep oluşturmak için önce mevcut talebinizi tamamlamanız veya iptal etmeniz gerekmektedir.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aktif talebinizi "Rezervasyonlarım" bölümünden kontrol edebilirsiniz.',
                        style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Rezervasyonlarım sayfasına yönlendir
                Future.delayed(Duration(milliseconds: 100), () {
                  Navigator.pushNamed(context, '/reservations');
                });
              },
              child: Text('Rezervasyonlarım', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade600,
                foregroundColor: Colors.white,
              ),
              child: Text('Tamam'),
            ),
          ],
        );
      },
    );
  }
  
  // PROVİZYON SİSTEMİ TAMAMEN GİZLENDİ [[memory:9694916]]
  Future<bool> _processProvision({String? rideId, String rideType = 'standard'}) async {
    print('✅ Provizyon sistemi gizli - bypass edildi');
    
    // PROVİZYON DEAKTİF - DİREKT TRUE DÖNDÜR
    return true;
  }
  
  // FATURALAMA SİSTEMİ - HAFIZADAN RESTORE [[memory:9695128]]
  void _autoInvoiceSystem() async {
    try {
      print('🧾 Otomatik fatura sistemi başlatılıyor...');
      // Otomatik fatura kesme API'si çağrılacak
    } catch (e) {
      print('❌ Fatura sistemi hatası: $e');
    }
  }
  
  // 2+ SAAT REZERVASYON SİSTEMİ!
  Future<void> _createScheduledRideReservation() async {
    try {
      final adminApi = AdminApiProvider();
      final prefs = await SharedPreferences.getInstance();
      final user = await adminApi.getCurrentUser();
      
      if (user == null) {
        throw Exception('Kullanıcı bilgisi bulunamadı');
      }
      
      print('📅 2+ saat rezervasyon oluşturuluyor...');
      print('⏰ Seçilen zaman: ${_selectedDateTime?.toIso8601String()}');
      print('🎯 Talep türü: ${_selectedServiceType}');
      
      // BEKLEYEN REZERVASYON - NULL SAFE!
      print('🔍 Rezervasyon konum kontrol:');
      print('   📍 Pickup: $_pickupAddress (${_pickupLocation?.latitude}, ${_pickupLocation?.longitude})');
      print('   🎯 Destination: $_destinationAddress (${_destinationLocation?.latitude}, ${_destinationLocation?.longitude})');
      print('   ⏰ DateTime: ${_selectedDateTime?.toIso8601String()}');
      
      // NULL CHECK - REZERVASYON İÇİN GEREKLİ!
      if (_pickupLocation == null) {
        throw Exception('Alış konumu seçilmemiş');
      }
      if (_destinationLocation == null) {
        throw Exception('Varış konumu seçilmemiş');
      }
      if (_selectedDateTime == null) {
        throw Exception('Rezervasyon zamanı seçilmemiş');
      }
      
      final requestData = {
        'customer_id': int.tryParse(user['id']) ?? 0,
        'pickup_address': _pickupAddress,
        'pickup_lat': _pickupLocation?.latitude ?? 0.0,
        'pickup_lng': _pickupLocation?.longitude ?? 0.0,
        'destination_address': _destinationAddress,
        'destination_lat': _destinationLocation?.latitude ?? 0.0,
        'destination_lng': _destinationLocation?.longitude ?? 0.0,
        'scheduled_time': _selectedDateTime?.toIso8601String() ?? (await TimeService.getServerTime()).add(const Duration(hours: 2)).toIso8601String(),
        'estimated_price': (_estimatedPrice ?? 0.0) - _discountAmount,
        'payment_method': 'card',
        'request_type': 'scheduled_later', // 2+ SAAT İLERİ!
        'ride_type': _selectedServiceType,
        'notes': '2+ saat ileri rezervasyon - otomatik sistem'
      };
      
      print('📅 Rezervasyon API çağrısı: ${jsonEncode(requestData)}');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/create_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestData),
      );
      
      print('📅 Rezervasyon Response: ${response.statusCode} - ${response.body}');
      
      if (response.statusCode == 200) {
        // JSON parse hatası kontrolü
        if (response.body.trim().isEmpty) {
          throw Exception('Sunucudan boş yanıt alındı');
        }
        
        final reservationResult = jsonDecode(response.body);
      
      if (reservationResult['success'] == true) {
        print('✅ 2+ saat rezervasyon başarıyla oluşturuldu');
        
        // REZERVASYON BAŞARILI DIALOG
        _showReservationSuccessDialog();
      } else {
        throw Exception(reservationResult['message'] ?? 'Rezervasyon oluşturulamadı');
      }
    } else {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
    } catch (e) {
      print('❌ 2+ saat rezervasyon hatası: $e');
      
      // HATA DIALOG
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Rezervasyon Hatası'),
            content: Text('Rezervasyon oluşturulurken hata oluştu:\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    }
  }
  
  // REZERVASYON BAŞARILI DIALOG - BASIT VE CLEAN!
  void _showReservationSuccessDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final selectedTime = _selectedDateTime!;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.schedule, color: Color(0xFFFFD700)),
            const SizedBox(width: 8),
            const Expanded(child: Text('📅 Rezervasyon Oluşturuldu')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⏰ Vale talebiniz 2+ saat ileri olduğu için bekleyen rezervasyonlara eklendi.'),
            const SizedBox(height: 12),
            Text('📍 Nereden: $_pickupAddress'),
            const SizedBox(height: 4),
            Text('🎯 Nereye: $_destinationAddress'),
            const SizedBox(height: 4),
            Text('⏰ Zaman: ${selectedTime.day}.${selectedTime.month}.${selectedTime.year} ${selectedTime.hour}:${selectedTime.minute.toString().padLeft(2, '0')}'),
            const SizedBox(height: 4),
            Text('💰 Tahmini Fiyat: ₺${(_estimatedPrice ?? 0).toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🤖 Rezervasyon saatine 2 saat kaldığında otomatik vale atanacaktır.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '📋 Aktif rezervasyonunuzu "Rezervasyonlar → Aktif" kısmında görebilir ve iptal edebilirsiniz.',
                      style: TextStyle(
                        fontSize: 11, 
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('✅ Anladım'),
          ),
        ],
      ),
    );
  }
  
  
  // GERÇEK RIDE VERİLERİ İLE AKTİF YOLCULUK EKRANINA YÖNLENDİRME!
  void _navigateToActiveRideScreenWithRealData(Map<String, dynamic> realRideDetails) {
    try {
      print('🚗 GERÇEK VERİLER ile aktif yolculuk ekranına yönlendiriliyor...');
      print('📊 Ride Detayları: ${realRideDetails['ride_id']} - ${realRideDetails['status']}');
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ModernActiveRideScreen(rideDetails: realRideDetails),
        ),
      );
      
    } catch (e) {
      print('❌ Gerçek veri yolculuk ekranı navigation hatası: $e');
    }
  }
  
  // TALEP İPTAL SİSTEMİ - PROVİZYON YÖNETİMİ İLE!
  Future<void> _cancelCurrentRideRequest({String reason = 'user_cancel'}) async {
    try {
      final adminApi = AdminApiProvider();
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('user_id') ?? '0';
      
      print('🚫 Mevcut ride talebi iptal ediliyor - Sebep: $reason');
      
      // PROVİZYON KODLARI GİZLENDİ [[memory:9694916]]
      /*
      if (_provisionProcessed) {
        print('💳 Provizyon mevcut - iptal işlemi yapılıyor...');
        
        final provisionCancel = await adminApi.processProvision(
          customerId: customerId,
          rideId: DateTime.now().millisecondsSinceEpoch.toString(),
          provisionAmount: _provisionAmount,
          action: 'cancel',
        );
      }
      */
      
      // Ride talebi iptal et
      final cancelResult = await adminApi.cancelRideRequest(
        customerId: customerId,
        reason: reason,
      );
      
      if (cancelResult['success'] == true) {
        print('✅ Ride talebi başarıyla iptal edildi');
        
        // setState(() { _provisionProcessed = false; }); // GİZLENDİ
      }
      
    } catch (e) {
      print('❌ Ride iptal hatası: $e');
    }
  }
  
  // GELIŞMİŞ İNDİRİM KODU SİSTEMİ - PANEL ENTEGRE!
  void _applyDiscountCode(StateSetter setModalState) async {
    final code = _discountCodeController.text.trim().toLowerCase();
    
    if (code.isEmpty) {
      _showDiscountCodeError('Lütfen bir indirim kodu girin');
      return;
    }
    
    // TEK İNDİRİM KODU SINIRI KONTROLÜ - EKSİKSİZ YAPILDI!
    if (_appliedDiscountCode != null) {
      _showDiscountCodeError('Zaten bir indirim kodu uygulandı. Değiştirmek için mevcut kodu kaldırın.');
      return;
    }
    
    print('🏷️ İndirim kodu doğrulanıyor: $code');
    
    try {
      // 1. PANEL API İLE GERÇEK İNDİRİM KODU KONTROLÜ!
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/validate_discount.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'discount_code': code,
          'estimated_price': _estimatedPrice,
          'customer_id': Provider.of<AuthProvider>(context, listen: false).customerId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['valid'] == true) {
          // PANEL'DEN GELEN GERÇEK İNDİRİM BİLGİLERİ
          final discountRate = (data['discount_rate'] ?? 0.0).toDouble();
          final maxDiscountAmount = (data['max_discount_amount'] ?? 0.0).toDouble();
          final minOrderAmount = (data['min_order_amount'] ?? 0.0).toDouble();
          
          print('Panel indirim bilgileri alindi');
          print('Indirim orani: %${(discountRate * 100).toInt()}');
          print('Maksimum indirim: $maxDiscountAmount TL');
          print('Minimum tutar: $minOrderAmount TL');
          
          // MİNİMUM TUTAR KONTROLÜ
          if ((_estimatedPrice ?? 0) < minOrderAmount) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bu indirim kodu minimum ₺${minOrderAmount.toStringAsFixed(0)} için geçerlidir'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          
          // GELIŞTİRİLMİŞ İNDİRİM HESAPLAMA - SAATLİK PAKET DÜZELTMESİ!
          setModalState(() {
            _appliedDiscountCode = code.toUpperCase();
            
            // MEVCUT FİYATI DOĞRU AL
            double currentPrice;
            if (_selectedServiceType == 'hourly' && _selectedHourlyPackage != null) {
              currentPrice = _selectedHourlyPackage!.price; // SAATLİK PAKET FİYATI
              print('🕰️ Saatlik paket fiyatı: ₺$currentPrice');
            } else {
              currentPrice = _estimatedPrice ?? 0; // NORMAL VALE FİYATI
              print('🚗 Normal vale fiyatı: ₺$currentPrice');
            }
            
            _originalPrice = currentPrice; // ORİJİNAL FİYAT KAYDET
            
            // İNDİRİM HESAPLAMA - DOĞRU TUTARDAN!
            double calculatedDiscount = currentPrice * discountRate;
            print('💰 Hesaplanan indirim: ₺$calculatedDiscount (%${(discountRate * 100).toInt()})');
            
            // Maksimum indirim limitini kontrol et
            if (maxDiscountAmount > 0 && calculatedDiscount > maxDiscountAmount) {
              _discountAmount = maxDiscountAmount;
              print('⚠️ Maksimum indirim limiti uygulandı: ₺$maxDiscountAmount');
            } else {
              _discountAmount = calculatedDiscount;
            }
            
            // FINAL FİYAT HESAPLAMA
            _estimatedPrice = currentPrice - _discountAmount;
            
            print('✅ İndirim hesaplama tamamlandı:');
            print('   Orijinal: ₺${_originalPrice!.toStringAsFixed(2)}');
            print('   İndirim: ₺${_discountAmount.toStringAsFixed(2)}');
            print('   Final: ₺${_estimatedPrice!.toStringAsFixed(2)}');
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ İndirim kodu uygulandı! ₺${_discountAmount.toStringAsFixed(2)} indirim'),
              backgroundColor: Colors.green,
            ),
          );
          
          print('✅ İndirim başarıyla uygulandı!');
        } else {
          // GEÇERSİZ VEYA SÜRESİ DOLMUŞ KOD
          final errorMessage = data['message'] ?? 'Geçersiz indirim kodu';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
          
          print('❌ İndirim kodu geçersiz: $errorMessage');
        }
      } else {
        print('❌ İndirim kodu API HTTP hatası: ${response.statusCode}');
        _showDiscountCodeError('Sunucu hatası, lütfen tekrar deneyin');
      }
    } catch (e) {
      print('❌ İndirim kodu API hatası: $e');
      
      // FALLBACK: OFFLINE İNDİRİM KODLARI (PANEL ÇALIŞMIYORSA)
      Map<String, Map<String, dynamic>> fallbackCodes = {
        'welcome10': {'rate': 0.10, 'max': 50.0, 'min': 100.0},
        'save20': {'rate': 0.20, 'max': 100.0, 'min': 200.0},
        'funbreak5': {'rate': 0.05, 'max': 25.0, 'min': 50.0},
      };
      
      if (fallbackCodes.containsKey(code)) {
        final codeInfo = fallbackCodes[code]!;
        
        if ((_estimatedPrice ?? 0) >= codeInfo['min']) {
          setModalState(() {
            _appliedDiscountCode = code.toUpperCase();
            _originalPrice = _estimatedPrice;
            double calculatedDiscount = (_estimatedPrice ?? 0) * codeInfo['rate'];
            _discountAmount = calculatedDiscount > codeInfo['max'] ? codeInfo['max'] : calculatedDiscount;
            _estimatedPrice = (_estimatedPrice ?? 0) - _discountAmount;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İndirim kodu uygulandı! ₺${_discountAmount.toStringAsFixed(2)} indirim (Offline)'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showDiscountCodeError('Bu kod minimum ₺${codeInfo['min'].toStringAsFixed(0)} için geçerlidir');
        }
      } else {
        _showDiscountCodeError('Geçersiz indirim kodu');
      }
    }
  }
  
  // İNDİRİM KODU HATA GÖSTERİMİ
  void _showDiscountCodeError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // DUPLICATE KALDIRILDI - İLK VERSİYON KULLANILIYOR

  // KOMPAKT WİDGET'LAR - KAYDIRMA OLMASIN DİYE KÜÇÜLTÜLMÜŞ VERSİYONLAR!
  
  Widget _buildCompactTripSummaryCard(ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(12), // 16 → 12
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route,
                color: const Color(0xFFFFD700),
                size: 20, // 24 → 20
              ),
              const SizedBox(width: 8),
              Text(
                'Yolculuk Özeti',
                style: TextStyle(
                  fontSize: 16, // 18 → 16
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10), // 16 → 10
          
          if (_selectedServiceType == 'vale') ...[
            _buildCompactTripDetailRow('Nereden', _pickupAddress, Icons.location_on, Colors.green),
            const SizedBox(height: 8), // 12 → 8
            
            // 🔥 ARA DURAKLAR (Yolculuk Detayları Dialog)
            if (_waypoints.isNotEmpty) ...[
              for (int i = 0; i < _waypoints.length; i++) ...[
                _buildCompactTripDetailRow(
                  'Ara Durak ${i + 1}', 
                  _waypoints[i]['address'] ?? 'Adres yok', 
                  Icons.location_on, 
                  Colors.orange
                ),
                const SizedBox(height: 8),
              ],
            ],
            
            _buildCompactTripDetailRow('Nereye', _destinationAddress, Icons.location_on, Colors.red),
            const SizedBox(height: 8),
          ],
          
          if (_selectedServiceType == 'hourly') ...[
            _buildCompactTripDetailRow('Paket', _selectedHourlyPackage?.displayText ?? '', Icons.access_time, const Color(0xFFFFD700)),
            const SizedBox(height: 8),
          ],
          
          _buildCompactTripDetailRow('Zaman', _selectedTimeOption, Icons.schedule, Colors.blue),
        ],
      ),
    );
  }
  
  
  Widget _buildCompactPriceCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(12), // 16 → 12
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long,
                color: const Color(0xFFFFD700),
                size: 20, // 24 → 20
              ),
              const SizedBox(width: 8),
              Text(
                'Fiyat Detayları',
                style: TextStyle(
                  fontSize: 16, // 18 → 16
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10), // 16 → 10
          
          // TAHMİNİ FİYAT KALDIRILDI - SADECE TUTAR GÖZÜKSÜN
          
          // İNDİRİM
          if (_discountAmount > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'İndirim:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '-₺${_discountAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          
          // PROVİZYON YAZILARI KALDIRILDI [[memory:9694916]] - DEAKTİF
          
          const Divider(),
          
          // TOPLAM FİYAT
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tahmini Tutar:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '₺${(_estimatedPrice ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          // ✅ AÇIKLAMA YAZISI EKLENDİ (modern_active_ride_screen'den taşındı)
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'ℹ️ Bekleme Ücreti Hakkında',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '• Yukarıdaki tutara bekleme ücreti dahil değildir\n'
                  '• İlk 15 dakika bekleme ücretsizdir\n'
                  '• Sonraki her 15 dakika için ₺200 eklenir\n'
                  '• Net ödeme tutarınız yolculuk sonunda belirlenecektir',
                  style: TextStyle(
                    fontSize: 11,
                    color: themeProvider.isDarkMode ? Colors.white70 : Colors.black87,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompactPaymentMethodCard(ThemeProvider themeProvider, StateSetter setModalState) {
    // DİNAMİK ÖDEME GÖSTERİMİ - HAVALE/EFT DESTEĞİ [[memory:9694916]]
    final defaultCard = {
      'cardNumber': '**** **** **** 1234',
      'cardType': 'visa',
      'isDefault': true
    };
    
    return GestureDetector(
      onTap: () => _showPaymentMethodSelection(setModalState),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 20,
              decoration: BoxDecoration(
                color: _selectedPaymentMethod == 'havale_eft' ? Colors.orange : _getCardTypeColor(defaultCard['cardType'].toString()),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _selectedPaymentMethod == 'havale_eft' ? Icons.account_balance : Icons.credit_card, 
                color: Colors.white, 
                size: 12
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedPaymentMethod == 'card' ? 'Kredi/Banka Kartı' : 
                    _selectedPaymentMethod == 'havale_eft' ? 'Havale/EFT' : 'Ödeme Türü Seçiniz',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _selectedPaymentMethod != 'none' ? const Color(0xFFFFD700) : Colors.grey[600],
                    ),
                  ),
                  Text(
                    _selectedPaymentMethod != 'none' ? 
                      (_selectedPaymentMethod == 'card' ? 'Güvenli kart ödemesi' : 'Banka havalesi ile ödeme') : 
                      'Ödeme yöntemini seçiniz',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
  
  // ÖDEME YÖNTEMİ SEÇİM EKRANI
  void _showPaymentMethodSelection(StateSetter setModalState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD700),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payment, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Ödeme Yöntemi Seç',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Kart listesi
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // HAVALE/EFT SEÇENEĞİ - HAFIZADAN RESTORE [[memory:9694916]]
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.account_balance, color: Colors.orange),
                      ),
                      title: const Text(
                        'Havale / EFT',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Banka havalesi ile ödeme'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        setModalState(() {
                          _selectedPaymentMethod = 'havale_eft';
                        });
                        print('✅ Havale/EFT seçildi');
                        _showHavaleEftInfo();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // Mevcut kartlar
                  ..._userCards.map((card) => _buildPaymentOptionCard(card)),
                  
                  const SizedBox(height: 12),
                  
                  // Yeni kart ekle
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_card, color: Color(0xFFFFD700)),
                      ),
                      title: const Text(
                        'Yeni Kart Ekle',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Ücretsiz ve güvenli'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PaymentMethodsScreen(),
                          ),
                        );
                        // Geri dönünce kartları yenile
                        _loadUserCards();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ÖDEME SEÇENEĞİ KARTI
  Widget _buildPaymentOptionCard(Map<String, dynamic> card) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getCardTypeColor(card['cardType']),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.credit_card, color: Colors.white, size: 20),
        ),
        title: Text(
          card['cardNumber'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${card['cardHolder']} \u2022 ${card['expiryDate']}'),
        trailing: card['isDefault'] 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Varsayılan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () {
          // Bu kartı seç
          print('💳 Kart seçildi: ${card['cardNumber']}');
          Navigator.pop(context);
        },
      ),
    );
  }
  
  // ÖDEME SEÇENEĞİ KARTI - CALLBACK İLE - HAFIZADAN RESTORE [[memory:9695626]]
  Widget _buildPaymentOptionCardWithCallback(Map<String, dynamic> card, StateSetter setModalState) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getCardTypeColor(card['cardType']),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.credit_card, color: Colors.white, size: 20),
        ),
        title: Text(
          card['cardNumber'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${card['cardHolder']} • ${card['expiryDate']}'),
        trailing: card['isDefault'] 
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Varsayılan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        onTap: () {
          // Bu kartı seç
          print('💳 Kart seçildi: ${card['cardNumber']}');
          setModalState(() {
            _selectedPaymentMethod = 'card';
          });
          Navigator.pop(context);
        },
      ),
    );
  }
  
  // KART TİPİ RENGİ
  Color _getCardTypeColor(String cardType) {
    switch (cardType) {
      case 'visa':
        return Colors.blue;
      case 'mastercard':
        return Colors.red;
      case 'amex':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  
  Widget _buildCompactDiscountCodeCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: _appliedDiscountCode != null
          ? Row(
              children: [
                const Icon(Icons.discount, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'İndirim: $_appliedDiscountCode (-₺${_discountAmount.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeDiscountCode(),
                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.discount, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _discountCodeController,
                    decoration: InputDecoration(
                      hintText: 'İndirim kodu',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 14),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                IconButton(
                  onPressed: () => _applyDiscountCode(setModalState),
                  icon: const Icon(Icons.check, color: Color(0xFFFFD700), size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
    );
  }
  
  Widget _buildCompactTermsCard(ThemeProvider themeProvider, StateSetter setModalState) {
    return GestureDetector(
      onTap: () {
        setModalState(() {
          _termsAccepted = !_termsAccepted;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _termsAccepted 
              ? Colors.green.withOpacity(0.1) 
              : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _termsAccepted ? Colors.green : Colors.red,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20, // 24 → 20
              height: 20,
              decoration: BoxDecoration(
                color: _termsAccepted ? const Color(0xFFFFD700) : Colors.transparent,
                border: Border.all(
                  color: _termsAccepted ? const Color(0xFFFFD700) : Colors.grey,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _termsAccepted
                  ? const Icon(Icons.check, color: Colors.white, size: 12) // 16 → 12
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                  children: [
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () {
                          print('📄 Ön Bilgilendirme Koşullarına tıklandı');
                          _openTermsScreen('conditions');
                        },
                        child: Text(
                          'Ön Bilgilendirme Koşulları',
                          style: TextStyle(
                            color: const Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' ve '),
                    WidgetSpan(
                      child: GestureDetector(
                        onTap: () {
                          print('📄 Mesafeli Satış Sözleşmesine tıklandı');
                          _openTermsScreen('contract');
                        },
                        child: Text(
                          'Mesafeli Satış Sözleşmesi',
                          style: TextStyle(
                            color: const Color(0xFFFFD700),
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '\'ni okudum ve onaylıyorum.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // DUPLICATE _removeDiscountCode SİLİNDİ - SORUN ÇÖZÜLDİ!
  
  // YASAL SAYFA AÇMA - MODAL İLE İÇERİK GÖSTER!
  void _openTermsScreen(String termsType) {
    print('📄 Modal yasal sayfa açılıyor: $termsType');
    
    String title = '';
    String content = '';
    
    // ÖZELLİK GERİ EKLENDİ: Detaylı içerikler!
    switch (termsType) {
      case 'terms':
      case 'conditions':
        title = 'Ön Bilgilendirme Koşulları';
        content = '''
HİZMET TANıMı VE KAPSAMI:
• FunBreak Vale, müşteriler ile profesyonel şoförler arasında aracılık eden bir dijital platform hizmetidir.
• Hizmet kapsamında güvenilir, ehliyet ve sigorta sahibi şoförlerle araç kullanma imkânı sunulmaktadır.
• Şoförlerimiz sürücü kurslarından mezun, temiz sicile sahip ve deneyimli profesyonellerdir.

FİYATLANDıRMA VE ÖDEME:
• Ücretlendirme gerçek mesafe, trafik yoğunluğu ve süreye göre adil şekilde hesaplanmaktadır.
• Bekleme ücreti: İlk 15 dakika ücretsiz, sonraki her 15 dakika için ek ücret alınır.
• Özel konum ücretleri (havalimanı, AVM vb.) önceden bildirilmektedir.
• Ödeme sadece yolculuk tamamlandıktan sonra kredi kartınızdan çekilecektir.
• Yolculuk başlangıcında güvenlik amaçlı provizyon (ön ödeme) alınacak, gerçek tutar hesaplandıktan sonra düzeltilecektir.

GÜVENLİK VE KALİTE GARANTİSİ:
• Tüm şoförlerimiz kimlik doğrulaması, adli sicil kontrolü ve sürücü belgesi doğrulamasından geçmiştir.
• Araçlarımız kasko sigortası, trafik sigortası ve periyodik muayene sertifikasına sahiptir.
• Yolculuk öncesi, sırası ve sonrası 7/24 müşteri hizmetleri desteği sağlanmaktadır.
• Acil durumlarda 24 saat destek hattımızdan yardım alabilirsiniz.

MÜŞTERİ HAKLARı VE SORUMLULUKLARI:
• Yolculuk sırasında emniyet kemeri takma yükümlülüğü müşteriye aittir.
• Alkollü, uyuşturucu etkisi altında olan müşterilere hizmet verilmeyebilir.
• Şoföre saygısız davranış, tehdit veya fiziksel saldırı durumunda hizmet durdurulacaktır.
• Kişisel eşyalarınızın güvenliği müşterinin sorumluluğundadır.
• Araçta sigara içmek ve yemek yemek yasaktır.
        ''';
        break;
      case 'contract':
        title = 'Mesafeli Satış Sözleşmesi';
        content = '''
MESAFELİ SATIŞ SÖZLEŞMESİ
FunBreak Vale Dijital Platform Hizmetleri

TARAFLAR:
Satıcı: FunBreak Vale Dijital Platform Ltd. Şti.
Alıcı: Mobil uygulama kullanıcısı (Müşteri)

HİZMET TANIMI:
Bu sözleşme kapsamında "Dijital Vale Aracılık Hizmeti" satın alınmaktadır. Hizmet, müşteri ile şoför arasında güvenli bağlantı kurma, ödeme işlemlerini kolaylaştırma ve kalite kontrolü yapmayı içermektedir.

HİZMET BEDELİ VE ÖDEME:
• Hizmet bedeli mesafe, süre ve özel konum ücretlerine göre hesaplanmaktadır.
• Ödeme sadece hizmet tamamlandıktan sonra kredi kartınızdan otomatik olarak çekilecektir.
• Yolculuk öncesi güvenlik provizyon alınacak, hizmet sonrası gerçek tutar ile düzeltilecektir.
• İlave ücretler (bekleme, özel konum) şeffaf şekilde bildirilmektedir.

CAYMA HAKKI VE İPTAL KOŞULLARI:
• Henüz şoför atanmadan önce ücretsiz iptal hakkınız bulunmaktadır.
• Şoför atandıktan sonra yapılan iptallerde zaman aralığına göre ücret kesilme hakki saklıdır.
• 45 dakikadan az sürede yapılan iptallerde ücret kesilir, 45 dakika sonra tam iade yapılır.
• Şoför tarafından iptal edilmesi durumunda tam iade yapılacaktır.

ŞOFÖR VE ARAÇ GARANTİLERİ:
• Tüm şoförlerimiz geçerli ehliyet, temiz sicil ve sigorta kontrolünden geçmiştir.
• Araçlar kasko, trafik sigortası ve periyodik muayene sertifikasına sahiptir.
• Şoför davranış standartları ve hizmet kalitesi sürekli denetlenmektedir.

MÜŞTERİ HAK VE SORUMLULUKLARI:
• Güvenliğiniz için emniyet kemeri takma yükümlülüğü müşteriye aittir.
• Kişisel eşyalar müşteri sorumluluğundadır, kayıp durumunda platform sorumlu değildir.
• Alkol, uyuşturucu etkisinde olan müşterilere hizmet verilmeyecektir.
• Şoföre karşı saygısız davranış hizmet durdurma sebebidir.

FORCE MAJEURE VE SORUMLULUK:
• Doğal afetler, trafik kazaları, yol kapanması gibi kontrolümüz dışındaki durumlardan platform sorumlu değildir.
• Şoförün trafik kurallarına uyma yükümlülüğü şahsi sorumluluğundadır.
• Platform aracılık hizmeti vermekte olup, taşıyıcı sorumluluğu bulunmamaktadır.

VERİ GÜVENLİĞİ VE GİZLİLİK:
• Kişisel verileriniz KVKK kapsamında güvence altındadır.
• Konum bilgileriniz sadece hizmet süresince kullanılır, sonrasında silinir.
• Ödeme bilgileriniz şifrelenmiş şekilde güvenli sunucularda tutulur.

SÖZLEŞMENİN GEÇERLİLİĞİ:
Bu sözleşme hizmet talebinizi onayladığınız anda yürürlüğe girer ve hizmet tamamlandığında sona erer.

1. TARAFLAR
• Satıcı: FunBreak Vale Teknoloji Ltd. Şti.
• Alıcı: Platform kullanıcısı

2. HİZMET TANIMI
• Platform üzerinden vale (şoför) hizmeti alımı

3. FİYAT VE ÖDEME
• Hizmet bedeli kilometre ve süre bazında hesaplanır
• Ödeme yolculuk sonunda yapılır
• Kredi kartı, nakit veya diğer ödeme yöntemleri kullanılabilir

4. İPTAL VE İADE KOŞULLARI
• Hizmet başlamadan önce iptal ücretsizdir
• Hizmet başladıktan sonra iptal, tamamlanan kısım için ücretlendirilir

5. SORUMLULUK
• Platform, vale ve müşteri güvenliği için gerekli tedbirleri almıştır
• Vale seçimi müşterinin kendi tercihidir

6. VERİ KORUMA
• Kişisel verileriniz KVKK kapsamında korunmaktadır
• Lokasyon bilgileri sadece hizmet için kullanılır

Kabul etmekle bu şartları onaylamış bulunmaktasınız.
        ''';
        break;
      default:
        title = 'Bilgi';
        content = 'İçerik bulunamadı.';
    }
    
    // MODAL BOTTOM SHEET İLE GÖSTER - YENİ ÖZELLİK!
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
            
            // Close button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Kapat',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // BEKLEYEN ÖDEME UYARISI - VALE ÇAĞIRMA ENGELLEMESİ!
  void _showPendingPaymentWarning() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bekleyen Ödemeniz Var',
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vale çağırabilmek için önce bekleyen ödemenizi tamamlamanız gerekmektedir.',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            
            // BEKLEYEN ÖDEME MİKTARI
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.payment, color: Colors.red),
                  const SizedBox(width: 12),
                  Text(
                    'Bekleyen Tutar: ₺${authProvider.pendingPaymentAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(
              'İptal',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openPaymentScreen();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Ödeme Yap'),
          ),
        ],
      ),
    );
  }
  
  // ÖDEME SAYFASINA YÖNLENDİRME
  void _openPaymentScreen() {
    print('💳 Ödeme sayfasına yönlendiriliyor...');
    
    // Burada rezervasyonlar sayfasına veya özel ödeme sayfasına yönlendirebilirsiniz
    Navigator.pushNamed(context, '/reservations');
  }

  // EKSİK METODLAR - BUILD HATA DÜZELTMESİ!
  
  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371; // km
    
    double lat1Rad = start.latitude * (pi / 180);
    double lat2Rad = end.latitude * (pi / 180);
    double deltaLatRad = (end.latitude - start.latitude) * (pi / 180);
    double deltaLngRad = (end.longitude - start.longitude) * (pi / 180);

    double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // km
  }

  // DUPLİCATE SİLİNDİ - ESKİ İLE CONFLICT
  
  Future<void> createRide({
    required LatLng pickupLocation,
    required LatLng destinationLocation,
    required String pickupAddress,
    required String destinationAddress,
    required double estimatedPrice,
    required int estimatedTime,
    required String paymentMethod,
    required String customerId,
    DateTime? scheduledTime,
  }) async {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    await rideProvider.createRide(
      pickupLocation: pickupLocation,
      destinationLocation: destinationLocation,
      pickupAddress: pickupAddress,
      destinationAddress: destinationAddress,
      estimatedPrice: estimatedPrice,
      estimatedTime: estimatedTime,
      paymentMethod: paymentMethod,
      customerId: customerId,
      scheduledTime: scheduledTime,
    );
  }

  // YENİ ÖZELLİK: MANUEL VALE SEÇİM EKRANI!
  void _showDriverSelectionScreen() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    print('🧑‍🚗 === VALE SEÇİM EKRANI AÇILIYOR ===');
    
    // İlk olarak bekleyen ödeme kontrol et
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkPendingPayments();
    
    if (authProvider.hasPendingPayment) {
      _showPendingPaymentWarning();
      return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.person_search,
                    color: const Color(0xFFFFD700),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Vale Seç',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            // Açıklama
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '100km menzil içindeki çevrimiçi valeler yakından uzağa sıralanmıştır.',
                        style: TextStyle(
                          fontSize: 14,
                          color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Vale Listesi
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getAvailableDriversList(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                      ),
                    );
                  }
                  
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Vale listesi yüklenirken hata oluştu',
                        style: TextStyle(
                          color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    );
                  }
                  
                  final drivers = (snapshot.data as List<Map<String, dynamic>>?) ?? <Map<String, dynamic>>[];
                  
                  if (drivers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: themeProvider.isDarkMode ? Colors.grey[600] : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Şu anda çevrimiçi vale bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: drivers.length,
                    itemBuilder: (context, index) {
                      return _buildDriverCard(drivers[index], themeProvider);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEK - DETAYLI DEBUG!
  Future<List<Map<String, dynamic>>> _getAvailableDriversList() async {
    try {
      print('🚗 === ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEKİMİ BAŞLADI ===');
      print('📍 Müşteri konumu: ${_pickupLocation?.latitude?.toStringAsFixed(6)}, ${_pickupLocation?.longitude?.toStringAsFixed(6)}');
      
      // Safe provider access - try-catch ile koru
      AdminApiProvider? adminApi;
      try {
        adminApi = Provider.of<AdminApiProvider>(context, listen: false);
      } catch (e) {
        print('⚠️ Provider context hatası - direkt AdminApiProvider kullanılıyor: $e');
        adminApi = AdminApiProvider();
      }
      
      // API'den çevrimiçi sürücüleri çek - DETAYLI DEBUG!
      print('🌐 get_online_drivers.php API çağrısı yapılıyor...');
      final result = await adminApi.getOnlineDrivers(
        pickupLat: _pickupLocation?.latitude,
        pickupLng: _pickupLocation?.longitude,
        maxDistance: 100.0, // 100km menzil
      );
      
      print('📊 === SÜRÜCÜ API SONUCU ===');
      print('📱 API Success: ${result['success']}');
      print('👥 Çevrimiçi sürücü sayısı: ${result['drivers']?.length ?? 0}');
      // RANGEERROR FİX - Safe substring!
      final responseStr = result.toString();
      final safeLength = responseStr.length > 200 ? 200 : responseStr.length;
      print('API response data: ${responseStr.substring(0, safeLength)}${responseStr.length > 200 ? '...' : ''}');
      
      print('📡 API Response alındı:');
      print('   ✅ Success: ${result['success']}');
      print('   📊 Driver count: ${result['drivers']?.length ?? 0}');
      print('   💬 Message: ${result['message'] ?? 'Mesaj yok'}');
      
      if (result['success'] == true) {
        final drivers = result['drivers'] as List;
        print('✅ ${drivers.length} çevrimiçi sürücü bulundu');
        
        // Her sürücüyü detaylı logla
        for (int i = 0; i < drivers.length; i++) {
          final driver = drivers[i];
          print('   👨‍🚗 Sürücü ${i+1}: ${driver['name']} ${driver['surname']}');
          print('      📍 Konum: ${driver['latitude']}, ${driver['longitude']}');
          print('      📏 Mesafe: ${driver['distance']} km');
          print('      🔄 Online: ${driver['is_online']}');
          print('      ✅ Available: ${driver['is_available']}');
        }
        
        final processedDrivers = drivers.map<Map<String, dynamic>>((driver) {
          return {
            'id': driver['id'],
            'name': driver['name'] ?? 'Vale',
            'surname': driver['surname'] ?? '',
            'phone': driver['phone'] ?? '',
            'rating': (driver['rating'] ?? 4.5).toDouble(),
            'total_rides': driver['total_rides'] ?? 0,
            'distance': (driver['distance'] ?? 0.0).toDouble(),
            'vehicle_brand': driver['vehicle_brand'] ?? 'Bilinmiyor',
            'vehicle_model': driver['vehicle_model'] ?? '',
            'vehicle_plate': driver['vehicle_plate'] ?? '',
            'photo_url': driver['photo_url'],
            'photo': driver['photo_url'] ?? '',
            'is_online': driver['is_online'] == 1 || driver['is_online'] == true,
            'latitude': (driver['latitude'] ?? 0.0).toDouble(),
            'longitude': (driver['longitude'] ?? 0.0).toDouble(),
          };
        }).toList();
        
        print('✅ ${processedDrivers.length} sürücü başarıyla işlendi');
        print('🚗 === ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEKİMİ TAMAMLANDI ===');
        
        return processedDrivers;
      } else {
        print('❌ API hatası: ${result['message']}');
        print('🚗 === ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEKİMİ BAŞARISIZ ===');
        return [];
      }
    } catch (e) {
      print('❌ Exception: $e');
      print('🚗 === ÇEVRİMİÇİ SÜRÜCÜ LİSTESİ ÇEKİMİ HATA ===');
      return [];
    }
  }

  // VALE KART WİDGETI
  Widget _buildDriverCard(Map<String, dynamic> driver, ThemeProvider themeProvider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () {
            _selectSpecificDriver(driver);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // PROFIL RESMİ
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: driver['photo'].isNotEmpty
                        ? Image.network(
                            driver['photo'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.person,
                                color: const Color(0xFFFFD700),
                                size: 32,
                              );
                            },
                          )
                        : Icon(
                            Icons.person,
                            color: const Color(0xFFFFD700),
                            size: 32,
                          ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // VALE BİLGİLERİ
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İSİM SOYİSİM
                      Text(
                        '${driver['name']} ${driver['surname']}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // YILDIZ PUANI
                      Row(
                        children: [
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                index < driver['rating'].floor()
                                    ? Icons.star
                                    : (index < driver['rating'] ? Icons.star_half : Icons.star_border),
                                color: Colors.amber,
                                size: 16,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${driver['rating'].toStringAsFixed(1)} (${driver['total_rides']} yolculuk)',
                            style: TextStyle(
                              fontSize: 12,
                              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // MESAFE
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getDistanceColor(driver['distance']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getDistanceColor(driver['distance']),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${driver['distance'].toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _getDistanceColor(driver['distance']),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MESAFE RENGİ (YEŞİL: YAKIN, TURUNCU: ORTA, KIRMIZI: UZAK)
  Color _getDistanceColor(double distance) {
    if (distance <= 3.0) return Colors.green;
    if (distance <= 8.0) return Colors.orange;
    return Colors.red;
  }

  // SPESİFİK VALE SEÇİMİ
  void _selectSpecificDriver(Map<String, dynamic> driver) {
    Navigator.pop(context); // Liste sayfasını kapat
    
    print('✅ Seçilen vale: ${driver['name']} ${driver['surname']} (${driver['distance'].toStringAsFixed(1)} km)');
    
    // Seçilen vale ile doğrudan yolculuk başlat
    _callSpecificDriver(driver);
  }

  // SPESİFİK VALE İLE YOLCULUK BAŞLATMA
  void _callSpecificDriver(Map<String, dynamic> driver) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.person_pin_circle,
              color: const Color(0xFFFFD700),
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Vale Seçildi',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seçilen vale bilgileri
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                    border: Border.all(color: const Color(0xFFFFD700)),
                  ),
                  child: Icon(
                    Icons.person,
                    color: const Color(0xFFFFD700),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${driver['name']} ${driver['surname']}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Row(
                        children: [
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                index < driver['rating'].floor()
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 14,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${driver['distance'].toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // MANUEL VALE SEÇİMİNDE SÖZLEŞME KUTUCUĞU KALDIRILDI - ZORUNLU ONAY 2. AŞAMADA YAPILIYOR!
            
            const SizedBox(height: 8),
            Text(
              'Bu valeyi çağırmak istediğinizden emin misiniz?',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showDriverSelectionScreen(); // Listeye geri dön
            },
            child: Text(
              'Geri',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processSpecificDriverCall(driver);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Vale Çağır'),
          ),
        ],
      ),
    );
  }

  // SPESİFİK VALE ÇAĞIRMA İŞLEMİ - AKILLI SİSTEM İLE!
  Future<void> _processSpecificDriverCall(Map<String, dynamic> driver) async {
    print('🎯 Spesifik vale çağırılıyor: ${driver['name']} ${driver['surname']}');
    print('🚀 MANUEL VALE - akıllı sistem ile arama yapılacak!');
    
    try {
      // SADECE VALE ÇAĞIR - AKILLI SİSTEM İLE!
      _createSpecificDriverRide(driver);
    } catch (e) {
      print('❌ Manuel vale çağırma hatası: $e');
    }
  }

  // SEÇİLEN VALE İLE 2. AŞAMA ÖDEME EKRANI
  void _showSecondStagePaymentScreenWithSelectedDriver(Map<String, dynamic> selectedDriver) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    // Direkt vale çağırma işlemini başlat - 3. onay ekranı yok!
    _createSpecificDriverRide(selectedDriver);
  }

  // SPESİFİK VALE İLE YOLCULUK OLUŞTUR
  void _createSpecificDriverRide(Map<String, dynamic> selectedDriver) async {
    print('🎯 Spesifik vale ile yolculuk oluşturuluyor: ${selectedDriver['name']}');
    
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // YENİ RideService ile talep oluştur - ADRES + KOORDİNAT!
      // SERVER TIME KULLAN!
      final correctScheduledTime = await _getCorrectScheduledTime();
      
      final result = await RideService.createRideRequest(
        customerId: int.tryParse(authProvider.customerId ?? '1') ?? 1,
        pickupLocation: _pickupAddress,
        destination: _destinationAddress,
        serviceType: _selectedServiceType,
        requestType: _selectedTimeOption == 'Hemen' ? 'immediate_or_soon' : 'scheduled_later',
        scheduledDateTime: correctScheduledTime.toIso8601String(),
        selectedDriverId: int.tryParse(selectedDriver['id']?.toString() ?? '0') ?? 0,
        estimatedPrice: _estimatedPrice,
        discountCode: _appliedDiscountCode,
        // KOORDİNATLAR EKLENDİ - "ADRES GEREKLİ" HATA ÇÖZÜMÜ!
        pickupLat: _pickupLocation?.latitude ?? 0.0,
        pickupLng: _pickupLocation?.longitude ?? 0.0,
        destinationLat: _destinationLocation?.latitude ?? 0.0,
        destinationLng: _destinationLocation?.longitude ?? 0.0,
      );

      if (result['success'] == true) {
        print('✅ RideService API başarılı: ${result['ride_id']}');
        
        // Vale çağırma ekranını göster
        _showValetCallScreen();
        
        // Talep durumunu kontrol etmeye başla - NULL SAFE!
        final rideId = result['ride_id'];
        if (rideId != null) {
          final safeRideId = int.tryParse(rideId.toString()) ?? 0;
          if (safeRideId > 0) {
            _startRideStatusTracking(safeRideId);
            
            // GERÇEK ZAMANLÍ KM TAKİBİNİ BAŞLAT - YENİ ÖZELLİK!
            final rideProvider = Provider.of<RideProvider>(context, listen: false);
            rideProvider.startRealTimeDistanceTracking(safeRideId.toString());
          }
        }
        
        // Loading durumunu sıfırla
        setState(() {
          _isLoading = false;
        });
      } else {
        print('❌ RideService API hatası: ${result['message']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: ${result['message']}')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Spesifik vale çağırma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Talep oluşturma hatası: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Talep durumu takibi
  void _startRideStatusTracking(int rideId) {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final status = await RideService.checkRideStatus(rideId);
        if (status != null) {
          print('📊 Talep durumu: ${status['status']}');
          
          if (status['status'] == 'accepted') {
            timer.cancel();
            _navigateToModernActiveRideScreen(status);
          } else if (status['status'] == 'rejected' || status['status'] == 'cancelled') {
            timer.cancel();
            _showRideRejectedDialog();
          }
        }
      } catch (e) {
        print('❌ Durum kontrol hatası: $e');
      }
    });
  }
  
  // Sürücü kabul etti dialog
  void _showDriverAcceptedDialog(Map<String, dynamic> rideData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 Vale Bulundu!'),
        content: Text('${rideData['driver_name']} talebinizi kabul etti. Size yaklaşıyor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
  
  // YENİ: AKTİF YOLCULUK EKRANINA GİT - ANA SAYFANIN YERİNİ ALSIN!
  void _navigateToModernActiveRideScreen(Map<String, dynamic> rideData) {
    // Ana sayfa navigation'ını değiştir - yolculuk ekranı ana sayfa olsun
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ModernActiveRideScreen(rideDetails: rideData),
      ),
    );
    
    print('🚗 Yolculuk kabul edildi - ActiveRideScreen ana sayfa oldu');
  }

  // Talep reddedildi dialog
  void _showRideRejectedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('😞 Vale Bulunamadı'),
        content: const Text('Maalesef yakınınızda uygun vale bulunamadı. Tekrar deneyin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  // HARİTA TıKLAMA İLE KONUM SEÇİMİ - YENİ ÖZELLİK!
  void _selectLocationFromMap(LatLng location) async {
    try {
      print('🗺️ Haritaya tıklayarak konum seçimi başlatıldı');
      print('📍 Seçilen konum: ${location.latitude}, ${location.longitude}');
      
      // Reverse geocoding ile adres al
      final placemarks = await placemarkFromCoordinates(
        location.latitude, 
        location.longitude
      );
      
      String address = 'Seçilen Konum';
      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        
        // MAHALLE EN BAŞTA SİSTEMİ [[memory:9695626]] - subLocality ÖNCELİK!
        List<String> addressParts = [];
        
        // 1. MAHALLE EN BAŞTA (subLocality öncelik)
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          addressParts.add(place.subLocality!);
        } else if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
          addressParts.add(place.subAdministrativeArea!);
        }
        
        // 2. SOKAK İSMİ (mahalle sonra)
        if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
          addressParts.add(place.thoroughfare!);
        } else if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        
        // 3. APT NUMARASI (en son)
        if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
          addressParts.add('No: ${place.subThoroughfare}');
        }
        
        // İl
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        
        // Final adres - boş olanları filtrele
        address = addressParts
            .where((part) => part.trim().isNotEmpty)
            .take(3) // Maksimum 3 parça
            .join(', ');
        
        // Fallback - hiçbir detay yoksa
        if (address.isEmpty) {
          address = '${place.subLocality ?? ''}, ${place.locality ?? 'Seçilen Konum'}';
        }
      }
      
      // NEREDEN konumunu güncelle (otomatik pickup olarak ayarla)
      setState(() {
        _pickupLocation = location;
        _pickupAddress = address;
      });
      
      print('✅ Harita tıklama ile seçim tamamlandı');
      print('📍 Yeni pickup konumu: $address');
      
      // Kullanıcıya bildir
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nereden konumu seçildi: ${address.length > 40 ? address.substring(0, 40) + "..." : address}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      print('❌ Harita tıklama hatası: $e');
      
      // Hata durumunda basit konum ayarla
      setState(() {
        _pickupLocation = location;
        _pickupAddress = 'Haritadan Seçilen Konum';
      });
    }
  }

  // PANELDEKİ SAAT EŞİĞİ İLE YOLCULUK KONTROLÜ - REZERVASYON SİSTEMİ!
  // 🔒 GÜVENLİK: SERVER TIME KULLAN!
  Future<void> _updateLongTermTripStatus() async {
    if (_selectedDateTime == null) {
      setState(() {
        _isLongTermTripCache = false;
      });
      return;
    }
    
    // 🔒 SERVER TIME AL - Telefon saati manipülasyonunu engeller
    final now = await TimeService.getServerTime();
    final timeDifference = _selectedDateTime!.difference(now);
    
    // PANELDEKİ GECELIK PAKET EŞİĞİNİ KULLAN (varsayılan 2 saat)
    int hourlyToNightlyThreshold = 2; // Varsayılan
    
    // DynamicContactService'ten sistem ayarlarını çek
    try {
      final settings = DynamicContactService.getCachedSettings();
      if (settings != null && settings['hourly_to_nightly_hours'] != null) {
        hourlyToNightlyThreshold = int.tryParse(settings['hourly_to_nightly_hours'].toString()) ?? 2;
        print('✅ Gecelik paket eşiği panelden alındı: ${hourlyToNightlyThreshold} saat');
      } else {
        print('⚠️ Gecelik paket eşiği panelden alınamadı, varsayılan kullanılıyor: $hourlyToNightlyThreshold saat');
      }
    } catch (e) {
      print('❌ Sistem ayarları çekme hatası: $e');
    }
    
    // Paneldeki eşik değerinden fazla gelecek bir zaman seçilmişse
    bool isLongTerm = timeDifference.inHours >= hourlyToNightlyThreshold;
    
    if (isLongTerm) {
      print('⏰ UZUN YOLCULUK TESPİT EDİLDİ!');
      print('📅 Seçilen zaman: ${_selectedDateTime.toString()}');  
      print('⏱️ Server time (şimdi): ${now.toString()}');
      print('🕐 Saat farkı: ${timeDifference.inHours} saat (Eşik: ${hourlyToNightlyThreshold}h)');
      print('🚫 Kendi vale seçimi DEVRE DIŞI - rezervasyona gidecek!');
    }
    
    setState(() {
      _isLongTermTripCache = isLongTerm;
    });
  }

  // DİNAMİK BİLDİRİM SAYISI - ANA SAYFA BADGE! 
  Future<int> _getUnreadNotificationCount() async {
    try {
      // Context safe olmayabilir - direkt AdminApiProvider kullan
      final adminApi = AdminApiProvider();
      
      print('📱 AdminApiProvider oluşturuldu - bildirim sayısı hesaplanıyor...');
      
      // Kampanyalar ve duyuruları çek
      final campaigns = await adminApi.getCampaigns();
      final announcements = await adminApi.getAnnouncements();
      
      print('📱 API çağrısı tamamlandı: ${campaigns.length} kampanya, ${announcements.length} duyuru');
      
      final prefs = await SharedPreferences.getInstance();
      
      // 🔥 AYRI AYRI OKUNMA TARİHİ KONTROLÜ
      final lastAnnouncementsStr = prefs.getString('last_notifications_opened');
      final lastCampaignsStr = prefs.getString('last_campaigns_opened');
      
      DateTime? lastAnnouncementsOpened;
      DateTime? lastCampaignsOpened;
      
      if (lastAnnouncementsStr != null && lastAnnouncementsStr.isNotEmpty) {
        lastAnnouncementsOpened = DateTime.tryParse(lastAnnouncementsStr);
      }
      if (lastCampaignsStr != null && lastCampaignsStr.isNotEmpty) {
        lastCampaignsOpened = DateTime.tryParse(lastCampaignsStr);
      }

      int count = 0;
      
      // 🔥 DUYURULARI KONTROL ET
      for (final announcement in announcements) {
        final rawDate = announcement['date']?.toString() ?? announcement['created_at']?.toString() ?? '';
        DateTime? itemDate;
        if (rawDate.isNotEmpty) {
          itemDate = DateTime.tryParse(rawDate) ?? DateTime.tryParse(rawDate.replaceAll(' ', 'T'));
        }

        if (lastAnnouncementsOpened == null) {
          count++;
        } else if (itemDate != null && itemDate.isAfter(lastAnnouncementsOpened)) {
          count++;
        }
      }
      
      // 🔥 KAMPANYALARI KONTROL ET (ID BAZLI)
      final readCampaignIds = prefs.getStringList('read_campaign_ids') ?? [];
      print('🎯 Kampanya kontrolü başlıyor - Okunan ID\'ler: $readCampaignIds');
      
      for (final campaign in campaigns) {
        final campaignId = campaign['id'].toString();
        
        // Bu kampanya okunmuş mu?
        if (readCampaignIds.contains(campaignId)) {
          print('✅ Kampanya ${campaign['title']}: OKUNMUŞ (ID: $campaignId)');
        } else {
          count++;
          print('🎯 Kampanya ${campaign['title']}: OKUNMAMIş (ID: $campaignId yeni)');
        }
      }
      
      print('📱 Toplam okunmamış bildirim count: $count');
      return count;
    } catch (e) {
      print('❌ Bildirim sayısı alma hatası: $e');
      return 0; // Hata durumunda 0 döndür
    }
  }

  // DUPLICATE _openTermsScreen KALDIRILDI - İLK VERSİYON KULLANILIYOR!

  // KOMPAKT TRIP DETAIL ROW - MAHALLE + SOKAK FORMATLAMASI!
  Widget _buildCompactTripDetailRow(String label, String value, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatCustomerAddressWithDistrict(value),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // MÜŞTERİ ADRES FORMATLAMASI - MAHALLE + SOKAK!
  String _formatCustomerAddressWithDistrict(String address) {
    if (address.isEmpty || address.contains('Seçin') || address.contains('yükleniyor')) {
      return address;
    }
    
    // Adresi virgüllerle böl ve analiz et
    final parts = address.split(',').map((part) => part.trim()).toList();
    
    if (parts.length >= 2) {
      // Son kısım il/şehir ise onu çıkar
      final filteredParts = parts.where((part) => 
        !part.toLowerCase().contains('türkiye') && 
        !part.toLowerCase().contains('turkey') &&
        part.length > 2
      ).toList();
      
      if (filteredParts.length >= 2) {
        final street = filteredParts[0]; // İlk kısım sokak
        final district = filteredParts.length >= 3 ? filteredParts[1] : filteredParts.last; // Mahalle
        
        return '🏘️ $district\n📍 $street';
      } else if (filteredParts.isNotEmpty) {
        return '📍 ${filteredParts[0]}';
      }
    }
    
    return address; // Orijinal adres
  }
  
  // BORÇ KONTROL SİSTEMİ - HAFIZADAN RESTORE
  Future<bool> checkCustomerDebtBeforeCall() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId ?? '0';
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/check_customer_debt.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'customer_id': int.parse(customerId)}),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['has_debt'] == true) {
          final totalDebt = data['total_debt'] ?? 0.0;
          final pendingRides = List<Map<String, dynamic>>.from(data['pending_rides'] ?? []);
          
          _showDebtWarning(totalDebt, pendingRides);
          return false;
        }
      }
      return true;
    } catch (e) {
      print('❌ Borç kontrol hatası: $e');
      return true;
    }
  }
  
  void _showDebtWarning(double debt, List<Map<String, dynamic>> rides) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Text('Bekleyen Ödeme'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Column(
                children: [
                  const Text('Toplam Borcunuz:', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  Text('₺${debt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.red)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Yeni vale çağırabilmek için önce bekleyen ödemelerinizi tamamlayın.'),
            const SizedBox(height: 12),
            Text('${rides.length} adet bekleyen ödeme', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/reservations');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Ödemelerimi Gör'),
          ),
        ],
      ),
    );
  }

  // HAVALE/EFT BİLGİ MODAL - HAFIZADAN RESTORE
  void _showHavaleEftInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.account_balance, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Havale / EFT'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Şirket Adı:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              const Text('FunBreak Turizm İnşaat Sanayi Ltd. Şti.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Text('IBAN:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('TR94 0006 4000 0011 2340 4911 51', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFFFFD700)),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ IBAN kopyalandı!'), backgroundColor: Colors.green),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Havale/EFT seçildi'), backgroundColor: Colors.green),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Seç'),
          ),
        ],
      ),
    );
  }

  // MERKEZI SCHEDULED TIME HESAPLAMA - HER İKİ SERVİS İÇİN!
  // 🚀 SERVER TIME KULLAN - PHONE TIMEZONE BYPASS!
  Future<DateTime> _getCorrectScheduledTime() async {
    print('🕰️ SCHEDULED TIME HESAPLAMA (SERVER TIME):');
    print('   📝 _selectedTimeOption: $_selectedTimeOption');
    print('   📅 _selectedDateTime: $_selectedDateTime');
    
    // SERVER SAATİNİ AL - PHONE TIMEZONE BAĞIMSIZ!
    final adminApi = AdminApiProvider();
    final serverNow = await adminApi.getServerTime();
    print('   🌐 Server saati: $serverNow');
    
    if (_selectedTimeOption == 'Hemen') {
      print('   ⚡ Hemen seçildi: $serverNow');
      return serverNow;
    }
    
    // Özel tarih seçilmişse onu kullan - AMA SADECE GERÇEK ÖZEL TARİH İÇİN!
    if (_selectedDateTime != null && _selectedTimeOption.startsWith('Özel')) {
      print('   🎯 GERÇEK özel tarih kullanılıyor: $_selectedDateTime');
      return _selectedDateTime!;
    } else if (_selectedDateTime != null) {
      print('   ⚠️ _selectedDateTime mevcut ama _selectedTimeOption özel değil - temizleniyor');
      print('   📝 _selectedTimeOption: $_selectedTimeOption');
      print('   📅 Eski _selectedDateTime: $_selectedDateTime');
    }
    
    // Otomatik seçenekler - SERVER SAATİ KULLAN!
    DateTime calculatedTime;
    if (_selectedTimeOption == '1 Saat Sonra') {
      calculatedTime = serverNow.add(const Duration(hours: 1));
    } else if (_selectedTimeOption == '2 Saat Sonra') {
      calculatedTime = serverNow.add(const Duration(hours: 2));
    } else if (_selectedTimeOption == '30 Dakika Sonra') {
      calculatedTime = serverNow.add(const Duration(minutes: 30));
    } else if (_selectedTimeOption.contains('Saat Sonra')) {
      // "3 Saat Sonra" gibi dynamic seçenekler
      final hourMatch = RegExp(r'(\d+) Saat Sonra').firstMatch(_selectedTimeOption);
      if (hourMatch != null) {
        final hours = int.tryParse(hourMatch.group(1) ?? '1') ?? 1;
        calculatedTime = serverNow.add(Duration(hours: hours));
      } else {
        calculatedTime = serverNow.add(const Duration(minutes: 30));
      }
    } else {
      // Varsayılan 30 dakika
      calculatedTime = serverNow.add(const Duration(minutes: 30));
    }
    
    print('   ✅ Hesaplanan zaman (SERVER BASE): $calculatedTime');
    return calculatedTime;
  }

  // AKTİF RIDE TALEBİNİ İPTAL ET - MÜŞTERİ ARAMA EKRANINDA İPTAL ETTİĞİNDE!
  Future<void> _cancelActiveRideRequest() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId ?? '0';
      
      print('🚫 Aktif ride talebi iptal ediliyor - Customer: $customerId');
      
      // MEVCUT cancel_ride.php KULLAN - HAFIZA PRENSİBİ [[memory:9808840]]
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/cancel_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.tryParse(customerId) ?? 0,
          'cancel_reason': 'user_cancelled_during_search',
          'find_latest': true, // Yeni parametre - son pending ride'ı bul
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Aktif ride başarıyla iptal edildi');
        } else {
          print('⚠️ Ride iptal uyarısı: ${data['message']}');
        }
      } else {
        print('❌ Ride iptal API HTTP hatası: ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Aktif ride iptal hatası: $e');
    }
  }

  // MÜŞTERİ ESKİ TALEP TEMİZLEME!
  void _cleanupExpiredRequestsCustomer() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/cleanup_expired_requests.php?timeout_minutes=1'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final expiredCount = data['expired_count'] ?? 0;
          if (expiredCount > 0) {
            print('🧹 MÜŞTERİ: $expiredCount eski talep temizlendi');
          }
        }
      }
    } catch (e) {
      print('⚠️ MÜŞTERİ cleanup hatası (normal): $e');
    }
  }
  
  // AKILLI TALEP SİSTEMİ - 2 AŞAMALI - HAFIZADAN RESTORE [[memory:9695382]]
  Future<void> startSmartDriverSearch(int rideId) async {
    print('🎯 AKILLI TALEP BAŞLADI - Ride: $rideId');
    setState(() {
      _currentRideId = rideId;
      _driverFound = false;
      _requestStage = 1;
    });
    
    try {
      await _searchDriversStage(rideId, 1);
      await Future.delayed(const Duration(seconds: 15));
      
      final check1 = await _checkRideAccepted(rideId);
      if (check1) return;
      
      print('⏩ Aşama 2 - 100km...');
      await _searchDriversStage(rideId, 2);
      await Future.delayed(const Duration(seconds: 15));
      
      final check2 = await _checkRideAccepted(rideId);
      if (!check2) _handleNoDriverFound(rideId);
    } catch (e) {
      print('❌ Akıllı talep hatası: $e');
    }
  }
  
  Future<void> _searchDriversStage(int rideId, int stage) async {
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/smart_request_system.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'pickup_lat': _pickupLocation?.latitude ?? 0.0,
          'pickup_lng': _pickupLocation?.longitude ?? 0.0,
          'stage': stage,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Aşama $stage: ${data['drivers_found']} sürücüye bildirim');
          if (mounted) setState(() => _requestStage = stage);
        }
      }
    } catch (e) {
      print('❌ Aşama $stage hatası: $e');
    }
  }
  
  Future<bool> _checkRideAccepted(int rideId) async {
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/check_ride_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ride_id': rideId}),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final ride = data['ride'];
          if (ride['status'] == 'accepted' && ride['driver_id'] != null) {
            print('✅ SÜRÜCÜ KABUL ETTİ!');
            if (mounted) {
              setState(() => _driverFound = true);
              
              // MODERN YOLCULUK EKRANINA GİT!
              final rideProvider = Provider.of<RideProvider>(context, listen: false);
              final rideDetails = {
                'ride_id': rideId,
                'customer_id': Provider.of<AuthProvider>(context, listen: false).customerId,
                'driver_id': ride['driver_id'],
                'pickup_lat': _pickupLocation?.latitude ?? 0.0,
                'pickup_lng': _pickupLocation?.longitude ?? 0.0,
                'destination_lat': _destinationLocation?.latitude ?? 0.0,
                'destination_lng': _destinationLocation?.longitude ?? 0.0,
                'pickup_address': _pickupAddress,
                'destination_address': _destinationAddress,
                'payment_method': 'card',
                'estimated_price': ride['estimated_price'] ?? 0.0,
                'estimated_time': 30,
                'status': 'accepted',
              };
              
              // YOLCULUK BAŞLAT + PERSİSTENCE KAYDET!
              rideProvider.startRideWithPersistence(rideDetails);
              
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernActiveRideScreen(
                    rideDetails: {
                      'ride_id': rideId,
                      'pickup_address': _pickupAddress,
                      'destination_address': _destinationAddress,
                      'customer_id': Provider.of<AuthProvider>(context, listen: false).customerId,
                      'driver_id': ride['driver_id'],
                      'estimated_price': ride['estimated_price'],
                      'status': 'accepted',
                    },
                  ),
                ),
              );
            }
            return true;
          }
        }
      }
    } catch (e) {
      print('❌ Durum kontrol hatası: $e');
    }
    return false;
  }
  
  Future<bool> _checkPendingRating() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('has_pending_rating') ?? false;
    } catch (e) {
      return false;
    }
  }
  
  Future<Map<String, String>> _getPendingRatingData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'ride_id': prefs.getString('pending_rating_ride_id') ?? '0',
      'driver_id': prefs.getString('pending_rating_driver_id') ?? '0',
      'driver_name': prefs.getString('pending_rating_driver_name') ?? 'Şoför',
      'customer_id': prefs.getString('pending_rating_customer_id') ?? '0',
    };
  }
  
  void _handleNoDriverFound(int rideId) async {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vale Bulunamadı'),
          content: const Text('30 saniyede sürücü bulunamadı. Rezervasyon yapın.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/reservations');
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
              child: const Text('Rezervasyon'),
            ),
          ],
        ),
      );
    }
  }

  // 🔥 ARA DURAK EKLEME DİALOGU
  void _showAddWaypointDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_location_alt, color: Color(0xFFFFD700)),
            SizedBox(width: 12),
            Text('Ara Durak Ekle'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alış ve varış noktanız arasına ara durak ekleyebilirsiniz.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_waypoints.isEmpty)
              const Text(
                'Henüz ara durak eklenmedi.',
                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              )
            else
              ..._waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final waypoint = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${index + 1}. ${waypoint['address']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        onPressed: () {
                          setState(() {
                            _waypoints.removeAt(index);
                          });
                          Navigator.pop(context);
                          _showAddWaypointDialog(); // Dialogu yenile
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showWaypointSelectionModal();
            },
            icon: const Icon(Icons.add),
            label: const Text('Ara Durak Seç'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 ARA DURAK SEÇİM MODALI (Arama + Harita)
  void _showWaypointSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Ara Durak Seçin',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Arama Yap
                  _buildWaypointOption(
                    icon: Icons.search,
                    title: 'Arama Yap',
                    subtitle: 'Konum adı yazarak arayın',
                    onTap: () {
                      Navigator.pop(context);
                      _searchWaypointLocation();
                    },
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Haritadan Seç
                  _buildWaypointOption(
                    icon: Icons.map,
                    title: 'Haritadan Seç',
                    subtitle: 'Harita üzerinden konum belirleyin',
                    onTap: () {
                      Navigator.pop(context);
                      _selectWaypointFromMap();
                    },
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWaypointOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD700),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
  
  // 🔥 ARA DURAK ARAMA İLE SEÇ
  void _searchWaypointLocation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildWaypointSearchModal(),
    );
  }
  
  Widget _buildWaypointSearchModal() {
    List<PlaceAutocomplete> searchResults = [];
    
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Ara Durak Ara',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Arama çubuğu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Ara durak ara...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                onChanged: (value) async {
                  if (value.length < 2) {
                    setModalState(() => searchResults = []);
                    return;
                  }
                  
                  final results = await LocationSearchService.getPlaceAutocomplete(value);
                  setModalState(() => searchResults = results);
                },
              ),
            ),
            
            // Arama sonuçları
            if (searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final result = searchResults[index];
                    return ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFFFFD700)),
                      title: Text(
                        result.mainText,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        result.secondaryText,
                        style: const TextStyle(
                          color: Colors.black87,
                        ),
                      ),
                      onTap: () async {
                        // Detayları al
                        final details = await LocationSearchService.getPlaceDetails(result.placeId);
                        
                        if (details != null) {
                          setState(() {
                            _waypoints.add({
                              'location': LatLng(details.latitude, details.longitude),
                              'address': details.formattedAddress,
                            });
                          });
                          
                          Navigator.pop(context);
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Ara durak eklendi: ${details.formattedAddress}'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ] else ...[
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'Ara durak aramaya başlayın...',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  // 🔥 ARA DURAK HARİTADAN SEÇ
  void _selectWaypointFromMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialLocation: _pickupLocation ?? _currentLocation,
          onLocationSelected: (location, address) {
            setState(() {
              _waypoints.add({
                'location': location,
                'address': address,
              });
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ara durak eklendi: $address'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}
 

