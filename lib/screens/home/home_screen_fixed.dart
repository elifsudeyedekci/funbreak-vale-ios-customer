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
import '../../services/pricing_service.dart';
import '../../services/location_service.dart';

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
  List<HourlyPackage> _hourlyPackages = [];
  HourlyPackage? _selectedHourlyPackage;
  double? _originalPrice;
  String? _appliedDiscountCode;
  double _discountAmount = 0.0;
  bool _mapLoading = true;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();
    
    _getCurrentLocationImproved();
    _loadHourlyPackages();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocationImproved() async {
    try {
      Position? position = await LocationService.getLocationFast();
      if (position != null) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _pickupLocation = _currentLocation;
          _mapLoading = false;
        });
        
        // Adres bilgisini al
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, 
            position.longitude
          );
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            setState(() {
              _pickupAddress = '${place.street ?? ''} ${place.subLocality ?? ''} ${place.locality ?? ''}'.trim();
              if (_pickupAddress.isEmpty) _pickupAddress = 'Mevcut konumunuz';
            });
          }
        } catch (e) {
          print('Adres alınamadı: $e');
        }
        
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_currentLocation, 15),
        );
      }
    } catch (e) {
      print('Konum alınamadı: $e');
      setState(() {
        _mapLoading = false;
      });
    }
  }

  Future<void> _loadHourlyPackages() async {
    try {
      List<HourlyPackage> packages = await PricingService.getHourlyPackages();
      setState(() {
        _hourlyPackages = packages;
      });
    } catch (e) {
      print('Saatlik paketler yüklenemedi: $e');
    }
  }

  Future<void> _calculatePrice() async {
    if (_pickupLocation == null || _destinationLocation == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      double distance = _calculateDistance(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );

      double totalPrice = await PricingService.calculateTotalPrice(
        distance: distance,
        destinationLat: _destinationLocation!.latitude,
        destinationLng: _destinationLocation!.longitude,
      );

      setState(() {
        _estimatedPrice = totalPrice;
        _originalPrice = totalPrice;
        _isLoading = false;
      });
    } catch (e) {
      print('Fiyat hesaplama hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateHourlyPrice() async {
    if (_selectedHourlyPackage == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      double totalPrice = _selectedHourlyPackage!.price;
      
      setState(() {
        _estimatedPrice = totalPrice;
        _originalPrice = totalPrice;
        _isLoading = false;
      });
    } catch (e) {
      print('Saatlik fiyat hesaplama hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation, 15),
      );
    } catch (e) {
      print('Konum alınamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      body: Column(
        children: [
          // Üst Kısım - Header
          Container(
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
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          languageProvider.getText('welcome'),
                          style: TextStyle(
                            fontSize: 16,
                            color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          languageProvider.getText('funbreak_vale'),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.notifications_outlined,
                              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                              size: 24,
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => const NotificationsBottomSheet(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ProfileScreen()),
                            );
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Harita Kısmı
          Expanded(
            flex: 3,
            child: Container(
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
                child: _mapLoading
                    ? Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                          ),
                        ),
                      )
                    : GoogleMap(
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
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
                          // Harita tıklama işlemleri
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
              ),
            ),
          ),
          
          // Alt Menü Kısmı
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(20),
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
                          'Saatlik Paket',
                          Icons.access_time,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Konum Seçimi
                  if (_selectedServiceType == 'vale') ...[
                    _buildLocationSelector(
                      'Nereden',
                      _pickupAddress,
                      Icons.location_on,
                      Colors.green,
                      () => _selectLocation('pickup'),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationSelector(
                      'Nereye',
                      _destinationAddress,
                      Icons.location_on,
                      Colors.red,
                      () => _selectLocation('destination'),
                    ),
                    
                    // Vale Kaçta Gelsin Seçimi
                    const SizedBox(height: 16),
                    _buildTimeSelectionWidget(),
                  ],
                  
                  // Saatlik Paket Seçimi
                  if (_selectedServiceType == 'hourly') ...[
                    _buildDynamicHourlyPackages(),
                  ],
                  
                  const Spacer(),
                  
                  // Fiyat ve Çağır Butonu
                  if (_estimatedPrice != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tahmini Fiyat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            '₺${_estimatedPrice!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Çağır Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _callValet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        elevation: 8,
                        shadowColor: const Color(0xFFFFD700).withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
                          : Text(
                              _selectedServiceType == 'vale' ? 'Vale Çağır' : 'Saatlik Paket Al',
                              style: const TextStyle(
                                fontSize: 18,
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
      floatingActionButton: Positioned(
        bottom: 200,
        right: 20,
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
            onPressed: _getCurrentLocation,
            child: const Icon(
              Icons.my_location_rounded,
              color: Color(0xFFFFD700),
            ),
          ),
        ),
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
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                )
              : null,
          color: isSelected
              ? null
              : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Colors.white
                  : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSelector(String title, String address, IconData icon, Color color, VoidCallback onTap) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
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
                      fontSize: 12,
                      color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 14,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelectionWidget() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
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
            'Vale Kaçta Gelsin?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildModernTimeOption('Hemen')),
              const SizedBox(width: 8),
              Expanded(child: _buildModernTimeOption('15 dk')),
              const SizedBox(width: 8),
              Expanded(child: _buildModernTimeOption('30 dk')),
              const SizedBox(width: 8),
              Expanded(child: _buildModernTimeOption('1 saat')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernTimeOption(String option) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSelected = _selectedTimeOption == option;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTimeOption = option;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                )
              : null,
          color: isSelected
              ? null
              : (themeProvider.isDarkMode ? Colors.grey[700] : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
          ),
        ),
        child: Text(
          option,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicHourlyPackages() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    if (_hourlyPackages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saatlik Paket Seçin',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ...(_hourlyPackages.map((package) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedHourlyPackage = package;
              });
              _calculateHourlyPrice();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: _selectedHourlyPackage?.id == package.id
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      )
                    : null,
                color: _selectedHourlyPackage?.id == package.id
                    ? null
                    : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedHourlyPackage?.id == package.id
                      ? Colors.transparent
                      : (themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.displayText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _selectedHourlyPackage?.id == package.id
                              ? Colors.white
                              : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
                        ),
                      ),
                      if (package.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          package.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: _selectedHourlyPackage?.id == package.id
                                ? Colors.white70
                                : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '₺${package.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _selectedHourlyPackage?.id == package.id
                          ? Colors.white
                          : const Color(0xFFFFD700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )).toList()),
      ],
    );
  }

  void _selectLocation(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
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
            
            if (_selectedServiceType == 'vale' && _pickupLocation != null && _destinationLocation != null) {
              _calculatePrice();
            }
          },
        ),
      ),
    );
  }

  void _callValet() {
    if (_selectedServiceType == 'vale') {
      if (_pickupLocation == null || _destinationLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen nereden ve nereye konumlarını seçin'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else if (_selectedServiceType == 'hourly') {
      if (_selectedHourlyPackage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen bir saatlik paket seçin'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Vale çağırma işlemi
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_selectedServiceType == 'vale' ? 'Vale çağrılıyor...' : 'Saatlik paket alınıyor...'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
