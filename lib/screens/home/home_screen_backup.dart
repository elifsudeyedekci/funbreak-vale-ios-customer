import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/pricing_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/waiting_time_provider.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/notifications_bottom_sheet.dart';
import '../profile/profile_screen.dart';

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
  bool _isLoading = false;
  bool _showTimeSelection = false;
  DateTime _selectedDateTime = DateTime.now();
  String _selectedTimeOption = 'Hemen';
  String _selectedServiceType = 'vale'; // 'vale' or 'hourly'
  double? _estimatedPrice;
  double? _originalPrice;
  String? _appliedDiscountCode;
  double _discountAmount = 0.0;
  bool _mapLoading = true;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  final TextEditingController _searchController = TextEditingController();
  List<String> _locationSuggestions = [];
  
  Timer? _searchTimer;
  bool _isSearching = false;
  
  static const String _darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#212121"}]
    },
    {
      "elementType": "labels.icon",
      "stylers": [{"visibility": "off"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#757575"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#212121"}]
    }
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _requestLocationPermission();
    _loadPricingData();
  }

  Future<void> _loadPricingData() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/pricing.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Pricing verilerini kaydet
          print('Pricing data yüklendi: ${data['pricing']}');
        }
      }
    } catch (e) {
      print('Pricing data yükleme hatası: $e');
    }
  }

  Future<void> _calculatePrice() async {
    if (_pickupLocation == null || _destinationLocation == null) return;
    
    try {
      if (_selectedServiceType == 'vale') {
        // Mesafe bazlı fiyat hesaplama - panelden çek
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/calculate_price.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'pickup_lat': _pickupLocation!.latitude,
            'pickup_lng': _pickupLocation!.longitude,
            'destination_lat': _destinationLocation!.latitude,
            'destination_lng': _destinationLocation!.longitude,
            'service_type': 'distance'
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _estimatedPrice = data['estimated_price'].toDouble();
            });
          }
        }
      }
    } catch (e) {
      print('Fiyat hesaplama hatası: $e');
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum izni gerekli. Lütfen ayarlardan izin verin.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        await _getCurrentLocation();
      }
    } catch (e) {
      print('Konum izni hatası: $e');
      _getCurrentLocation(); // Yine de dene
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          // Modern Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 15, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: themeProvider.isDarkMode 
                      ? [Colors.grey[900]!, Colors.grey[800]!]
                      : [Colors.white, const Color(0xFFFAFAFA)],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(
                          languageProvider.getTranslatedText('funbreak_vale'),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFFFD700),
                            letterSpacing: -0.5,
                          ),
                        ),
        ],
      ),
                  Row(
          children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () => _showNotificationsDialog(),
                          icon: const Icon(
                            Icons.notifications_rounded,
                            color: Color(0xFFFFD700),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _navigateToProfile(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Büyük Harita - Sayfanın Yarısı
          Positioned(
            top: 120,
            left: 16,
            right: 16,
            bottom: 200,
            child: Container(
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
                  onMapCreated: (controller) {
                    _mapController = controller;
                    setState(() {
                      _mapLoading = false;
                    });
                    // Mevcut konuma git
                    controller.animateCamera(
                      CameraUpdate.newLatLngZoom(_currentLocation, 15.0),
                    );
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation,
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  style: themeProvider.isDarkMode ? _darkMapStyle : null,
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
                ),
              ),
            ),
          ),
          
          // Bottom Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
                decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, -8),
                  ),
                ],
                ),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                  children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Location Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                            ),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () => _showPickupLocationDialog(),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                                                                  Text(
                                          languageProvider.getTranslatedText('where_from'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                          Text(
                                            _pickupAddress,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: themeProvider.isDarkMode ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            languageProvider.getTranslatedText('select_from_map'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: const Color(0xFFFFD700),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 24),
                              InkWell(
                                onTap: () => _showLocationSearchDialog(),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                        Text(
                                          languageProvider.getTranslatedText('where_to'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                    Text(
                                            _destinationAddress == 'Nereye gitmek istiyorsunuz?' 
                                                ? languageProvider.getTranslatedText('where_to_question')
                                                : _destinationAddress,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _destinationAddress == 'Nereye gitmek istiyorsunuz?' 
                                                  ? Colors.grey[500]
                                                  : (themeProvider.isDarkMode ? Colors.white : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                                            languageProvider.getTranslatedText('select_from_map'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: const Color(0xFFFFD700),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Price Display
                        if (_estimatedPrice != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Tahmini Fiyat',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (_appliedDiscountCode != null && _discountAmount > 0) ...[
                                          Text(
                                            '₺${_originalPrice!.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.white70,
                                              decoration: TextDecoration.lineThrough,
                                            ),
                                          ),
                                          Text(
                                            '₺${_estimatedPrice!.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ] else ...[
                                          Text(
                                            '₺${_estimatedPrice!.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                if (_appliedDiscountCode != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'İndirim Kodu: $_appliedDiscountCode',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      Text(
                                        '-₺${_discountAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _showDiscountCodeDialog,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.local_offer,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _appliedDiscountCode != null ? 'İndirim Kodu Değiştir' : 'İndirim Kodu Gir',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if (_estimatedPrice != null) const SizedBox(height: 20),
                        
                        // Service Type Selection
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedServiceType = 'vale';
                                  });
                                  _calculatePrice();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedServiceType == 'vale' ? const Color(0xFFFFD700) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedServiceType == 'vale' ? const Color(0xFFFFD700) : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        color: _selectedServiceType == 'vale' ? Colors.white : Colors.grey[600],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Mesafe Bazlı',
                                        style: TextStyle(
                                          color: _selectedServiceType == 'vale' ? Colors.white : Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedServiceType = 'hourly';
                                  });
                                  _calculatePrice();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _selectedServiceType == 'hourly' ? const Color(0xFFFFD700) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedServiceType == 'hourly' ? const Color(0xFFFFD700) : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        color: _selectedServiceType == 'hourly' ? Colors.white : Colors.grey[600],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Saatlik Paket',
                                        style: TextStyle(
                                          color: _selectedServiceType == 'hourly' ? Colors.white : Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Time Selection
                        if (_selectedServiceType == 'vale') ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildModernTimeOption('Hemen'),
                                const SizedBox(width: 12),
                                _buildModernTimeOption('1 Saat'),
                                const SizedBox(width: 12),
                                _buildModernTimeOption('2 Saat'),
                                const SizedBox(width: 12),
                                _buildModernTimeOption('3 Saat'),
                                const SizedBox(width: 12),
                                _buildModernTimeOption('4 Saat'),
                                const SizedBox(width: 12),
                                _buildModernTimeOption('Özel Saat'),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Saatlik Paket Fiyatları
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Saatlik Paket Fiyatları:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('1-2 Saat: ₺600', style: TextStyle(color: Colors.grey[700])),
                                    Text('3-4 Saat: ₺1200', style: TextStyle(color: Colors.grey[700])),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('5-8 Saat: ₺1800', style: TextStyle(color: Colors.grey[700])),
                                    Text('Gecelik: ₺2400', style: TextStyle(color: Colors.grey[700])),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Saatlik Paket Seçimi
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildHourlyPackageOption('1-2 Saat', '₺600'),
                                const SizedBox(width: 12),
                                _buildHourlyPackageOption('3-4 Saat', '₺1200'),
                                const SizedBox(width: 12),
                                _buildHourlyPackageOption('5-8 Saat', '₺1800'),
                                const SizedBox(width: 12),
                                _buildHourlyPackageOption('Gecelik (9-24 Saat)', '₺2400'),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Saat Seçimi
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vale Kaçta Gelsin?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTimePickerOption('Hemen'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTimePickerOption('1 Saat Sonra'),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTimePickerOption('Özel Saat'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        
              const SizedBox(height: 24),
            
                        // Call Vale Button
            SizedBox(
              width: double.infinity,
                          height: 60,
              child: ElevatedButton(
                            onPressed: _isLoading ? null : _requestVale,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 12,
                              shadowColor: const Color(0xFFFFD700).withOpacity(0.4),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.directions_car_rounded, size: 28),
                                      const SizedBox(width: 12),
                                      Text(
                                        languageProvider.getTranslatedText('call_vale'),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Floating Location Button
          Positioned(
            right: 20,
            bottom: 440,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: FloatingActionButton(
                mini: true,
                backgroundColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                onPressed: _getCurrentLocation,
                child: Icon(
                  Icons.my_location_rounded,
                  color: const Color(0xFFFFD700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTimeOption(String option) {
    final isSelected = _selectedTimeOption == option;
    return InkWell(
      onTap: () {
        if (option == 'Özel Saat') {
          _showTimePicker();
        } else {
          setState(() {
            _selectedTimeOption = option;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          option,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Notification Dialog with Tabs
  void _showNotificationsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationsBottomSheet(),
    );
  }
  
  Widget _buildNotificationCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Pickup Location Dialog
  void _showPickupLocationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Nereden',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
                Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location, color: Color(0xFFFFD700)),
                    title: const Text('Mevcut Konumum'),
                    onTap: () {
                      Navigator.pop(context);
                      _getCurrentLocation();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.map, color: Color(0xFFFFD700)),
                    title: const Text('Haritadan Seç'),
                    onTap: () {
                      Navigator.pop(context);
                      _showMapLocationPicker(true);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Location Search Dialog
  void _showLocationSearchDialog() {
    _searchController.clear();
    _locationSuggestions = [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Konum ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) async {
                        if (value.length > 2) {
                          await _generateLocationSuggestions(value);
                          setBottomState(() {});
                        } else {
                          setBottomState(() {
                            _locationSuggestions = [];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.map, color: Color(0xFFFFD700)),
                      title: const Text('Haritadan Seç'),
                      onTap: () {
                        Navigator.pop(context);
                        _showMapLocationPicker(false);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _locationSuggestions.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFFFFD700)),
                      title: Text(_locationSuggestions[index]),
                      onTap: () async {
                        Navigator.pop(context);
                        setState(() {
                          _destinationAddress = _locationSuggestions[index];
                        });
                        
                        // Adres için koordinat al
                        try {
                          List<Location> locations = await locationFromAddress(_locationSuggestions[index]);
                          if (locations.isNotEmpty) {
                            setState(() {
                              _destinationLocation = LatLng(locations.first.latitude, locations.first.longitude);
                            });
                            await _calculatePrice();
                          }
                        } catch (e) {
                          print('Koordinat alınamadı: $e');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _generateLocationSuggestions(String query) async {
    if (query.length < 3) return;
    
    try {
      const String apiKey = 'AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY';
      final String url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$apiKey&language=tr&components=country:tr';
      
      final response = await http.get(Uri.parse(url));
      
      print('Places API Response: ${response.statusCode}');
      print('Places API Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK' && data['predictions'] != null) {
          final predictions = data['predictions'] as List;
          
          setState(() {
            _locationSuggestions = predictions
                .map((prediction) => prediction['description'] as String)
                .take(6)
                .toList();
          });
          
          print('Bulunan öneriler: ${_locationSuggestions.length}');
        } else {
          print('Places API hatası: ${data['status']} - ${data['error_message'] ?? 'Bilinmeyen hata'}');
          _generateFallbackSuggestions(query);
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
        _generateFallbackSuggestions(query);
      }
    } catch (e) {
      print('Places API Exception: $e');
      _generateFallbackSuggestions(query);
    }
  }

  void _generateFallbackSuggestions(String query) {
    setState(() {
      _locationSuggestions = [
        '$query, İstanbul',
        '$query Mahallesi, İstanbul',
        '$query Caddesi, İstanbul',
        '$query Sokak, İstanbul',
        '$query Metro İstasyonu, İstanbul',
        '$query AVM, İstanbul',
        '$query Hastanesi, İstanbul',
        '$query Üniversitesi, İstanbul',
      ];
    });
    print('Fallback öneriler oluşturuldu: ${_locationSuggestions.length}');
  }

  // Time Picker
  void _showTimePicker() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFFD700),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFFFFD700),
              ),
            ),
            child: child!,
          );
        },
      );
      
      if (time != null) {
        setState(() {
          _selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          final months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 
                         'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
          _selectedTimeOption = '${date.day} ${months[date.month - 1]} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        });
      }
    }
  }

  void _showMapLocationPicker(bool isPickup) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialLocation: isPickup ? _pickupLocation : _destinationLocation,
          onLocationSelected: (location, address) {
            setState(() {
              if (isPickup) {
                _pickupLocation = location;
                _pickupAddress = address;
              } else {
                _destinationLocation = location;
                _destinationAddress = address;
              }
            });
            // Her iki konum da seçildiyse fiyat hesapla
            if (_pickupLocation != null && _destinationLocation != null) {
              _calculatePrice();
            }
          },
        ),
      ),
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _pickupLocation = _currentLocation;
      });
      
      // Mevcut konum için gerçek adres al
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude
        );
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          setState(() {
            _pickupAddress = '${place.street ?? ''} ${place.subLocality ?? ''} ${place.locality ?? 'İstanbul'}'.trim();
          });
        } else {
          setState(() {
            _pickupAddress = 'Mevcut konumunuz';
          });
        }
      } catch (e) {
        setState(() {
          _pickupAddress = 'Mevcut konumunuz';
        });
      }
    } catch (e) {
      print('Konum alınamadı: $e');
      setState(() {
        _pickupAddress = 'Konum alınamadı';
      });
    }
  }

  Future<void> _calculatePrice() async {
    if (_pickupLocation != null && _destinationLocation != null) {
      final pricingProvider = Provider.of<PricingProvider>(context, listen: false);
      
      try {
        // Her konum değişikliğinde fiyatı yeniden hesapla
        final price = await pricingProvider.calculateAIPrice(
          pickup: _pickupLocation!,
          destination: _destinationLocation!,
          serviceType: 'vale',
          time: _selectedDateTime,
        );
        
        setState(() {
          _estimatedPrice = price;
        });
        
        print('Fiyat hesaplandı: ₺$price');
      } catch (e) {
        print('Fiyat hesaplama hatası: $e');
        // Fallback fiyat - mesafe bazlı
        double distance = _calculateDistance(_pickupLocation!, _destinationLocation!);
        double fallbackPrice = _calculateFallbackPrice(distance);
        
        setState(() {
          _estimatedPrice = fallbackPrice;
        });
      }
    } else {
      // Konum seçilmemişse fiyatı sıfırla
      setState(() {
        _estimatedPrice = null;
      });
    }
  }

  // Fallback fiyat hesaplama
  double _calculateFallbackPrice(double distance) {
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

  // Mesafe hesaplama helper
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(point2.latitude - point1.latitude);
    double dLon = _degreesToRadians(point2.longitude - point1.longitude);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(point1.latitude)) * 
        cos(_degreesToRadians(point2.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }


  Future<void> _requestVale() async {
    if (_pickupLocation == null || _destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen nereden ve nereye konumlarını seçin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Ödeme kontrolü
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.customerId != null) {
      try {
        final response = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/check_payment_status.php?customer_id=${authProvider.customerId}'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['has_unpaid_rides'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Önce bekleyen ödemenizi tamamlayın: ₺${data['total_debt']}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Öde',
                  textColor: Colors.white,
                  onPressed: () {
                    // Ödeme sayfasına yönlendir
                  },
                ),
              ),
            );
            return;
          }
        }
      } catch (e) {
        print('Ödeme kontrolü hatası: $e');
      }
    }

    // Zaman ayrımı yap
    DateTime requestTime = _selectedTimeOption == 'Hemen' 
        ? DateTime.now()
        : _selectedTimeOption == '1 Saat'
            ? DateTime.now().add(const Duration(hours: 1))
            : _selectedDateTime;
    
    final now = DateTime.now();
    final timeDifference = requestTime.difference(now).inMinutes;
    
    // 1 saat içindeyse anlık, değilse rezervasyon havuzu
    if (timeDifference <= 60) {
      // Anlık talep
      await _processImmediateRequest();
    } else {
      // Rezervasyon havuzu
      await _processReservationRequest(requestTime);
    }
  }

  Future<void> _processImmediateRequest() async {
    setState(() {
      _isSearching = true;
    });

    // Vale arama dialog'unu göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildModernValeSearchDialog(),
    );

    // Admin API'ye anlık talep gönder
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/create_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': authProvider.customerId ?? '1',
          'pickup_address': _pickupAddress,
          'pickup_lat': _pickupLocation!.latitude,
          'pickup_lng': _pickupLocation!.longitude,
          'destination_address': _destinationAddress,
          'destination_lat': _destinationLocation!.latitude,
          'destination_lng': _destinationLocation!.longitude,
          'scheduled_time': DateTime.now().toIso8601String(),
          'estimated_price': _estimatedPrice ?? 50.0,
          'payment_method': 'cash',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('Anlık talep başarıyla gönderildi: ${data['ride']['id']}');
        }
      }
    } catch (e) {
      print('Anlık talep gönderme hatası: $e');
    }

    // 30 saniye timeout simülasyonu
    _searchTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isSearching) {
        Navigator.of(context).pop(); // Dialog'u kapat
        _showTimeoutDialog();
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _processReservationRequest(DateTime requestTime) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/create_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': authProvider.customerId ?? '1',
          'pickup_address': _pickupAddress,
          'pickup_lat': _pickupLocation!.latitude,
          'pickup_lng': _pickupLocation!.longitude,
          'destination_address': _destinationAddress,
          'destination_lat': _destinationLocation!.latitude,
          'destination_lng': _destinationLocation!.longitude,
          'scheduled_time': requestTime.toIso8601String(),
          'estimated_price': _estimatedPrice ?? 50.0,
          'payment_method': 'cash',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rezervasyon başarıyla oluşturuldu! Talep ID: ${data['ride']['id']}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          print('Rezervasyon başarıyla oluşturuldu: ${data['ride']['id']}');
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rezervasyon oluşturulamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _cancelValeSearch() {
    _searchTimer?.cancel();
    setState(() {
      _isSearching = false;
    });
    Navigator.of(context).pop();
  }

  Widget _buildModernValeSearchDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 16,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF8F9FA)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated taxi icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_taxi,
                size: 40,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            const Text(
              'Vale Aranıyor',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Subtitle
            Text(
              'Size en yakın vale bulunuyor...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            // Modern loading indicator
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                const Icon(
                  Icons.search,
                  color: Color(0xFFFFD700),
                  size: 24,
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Timer info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '30 saniye içinde kabul edilecektir',
                style: TextStyle(
                  color: Color(0xFF2C3E50),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Cancel button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cancelValeSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
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
          ],
        ),
      ),
    );
  }

  void _showTimeoutDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF8F9FA)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF5252)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Title
              const Text(
                'Vale Bulunamadı',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Message
              Text(
                'Şu anda uygun vale bulunamamaktadır.\nLütfen daha sonra tekrar deneyiniz veya arayarak rezervasyon yapınız.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // Telefon arama özelliği eklenebilir
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.phone, size: 20),
                      label: const Text('Ara'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // Dialog kapandığında state'i sıfırla
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  void _showDiscountCodeDialog() {
    final TextEditingController discountController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'İndirim Kodu',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_appliedDiscountCode != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Uygulanan Kod: $_appliedDiscountCode',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'İndirim: ₺${_discountAmount.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _appliedDiscountCode = null;
                          _discountAmount = 0.0;
                          _estimatedPrice = _originalPrice;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Kaldır'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: discountController,
              decoration: const InputDecoration(
                labelText: 'İndirim Kodu',
                hintText: 'Kodunuzu girin',
                prefixIcon: Icon(Icons.local_offer),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _applyDiscountCode(discountController.text.trim());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
            ),
            child: const Text('Uygula', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _applyDiscountCode(String code) async {
    if (code.isEmpty) return;
    
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/validate_discount.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'order_amount': _estimatedPrice ?? 0,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _originalPrice = _estimatedPrice;
            _appliedDiscountCode = code;
            _discountAmount = data['discount_amount'].toDouble();
            _estimatedPrice = (_originalPrice! - _discountAmount).clamp(0.0, double.infinity);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İndirim kodu uygulandı! ₺${_discountAmount.toStringAsFixed(2)} indirim'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Geçersiz indirim kodu'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İndirim kodu kontrol edilemedi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _pickupLocation = _currentLocation;
      });

      // Haritayı mevcut konuma yönlendir
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation, 15.0),
        );
      }

      // Adresi güncelle
      _updatePickupAddress();
    } catch (e) {
      print('Konum alma hatası: $e');
    }
  }

  Future<void> _updatePickupAddress() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _pickupAddress = '${place.street ?? ''} ${place.subLocality ?? ''} ${place.locality ?? ''}';
        });
      }
    } catch (e) {
      print('Adres güncelleme hatası: $e');
    }
  }

  Widget _buildHourlyPackageOption(String title, String price) {
    bool isSelected = _selectedTimeOption == title;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTimeOption = title;
          // Saatlik paket fiyatını ayarla
          switch (title) {
            case '1-2 Saat':
              _estimatedPrice = 600.0;
              break;
            case '3-4 Saat':
              _estimatedPrice = 1200.0;
              break;
            case '5-8 Saat':
              _estimatedPrice = 1800.0;
              break;
            case 'Gecelik (9-24 Saat)':
              _estimatedPrice = 2400.0;
              break;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey[300]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerOption(String title) {
    bool isSelected = _selectedTimeOption == title;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTimeOption = title;
        });
        
        if (title == 'Özel Saat') {
          _showTimePicker();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey[300]!,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  void _showTimePicker() {
    showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    ).then((time) {
      if (time != null) {
        setState(() {
          _selectedTimeOption = 'Saat ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        });
      }
    });
  }
} 