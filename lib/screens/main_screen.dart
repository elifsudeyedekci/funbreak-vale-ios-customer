import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'home/home_screen.dart';
import 'services/services_screen.dart';
import 'reservations/reservations_screen.dart';
import 'settings/settings_screen.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/ride_provider.dart';
import '../screens/ride/modern_active_ride_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _hasCheckedPersistence = false;
  Timer? _persistenceTimer;
  
  // Global tab controller için
  static final GlobalKey<_MainScreenState> _mainScreenKey = GlobalKey<_MainScreenState>();
  
  // Static method to change tab from anywhere
  static void changeTab(int index) {
    _mainScreenKey.currentState?._changeTab(index);
  }
  
  void _changeTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const ServicesScreen(),
    const ReservationsScreen(),
    const SettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    // BACKEND'DEN AKTİF YOLCULUK KONTROL - ŞOFÖR GİBİ!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBackendActiveRide();
      _setupRideProviderListener();
    });
  }
  
  // BACKEND'DEN AKTİF YOLCULUK KONTROL - OTOMATİK RESTORE!
  Future<void> _checkBackendActiveRide() async {
    try {
      print('🔍 [MÜŞTERİ MAIN] Backend aktif yolculuk kontrolü başlıyor...');
      
      final prefs = await SharedPreferences.getInstance();
      final customerIdStr = prefs.getString('admin_user_id') ?? prefs.getString('customer_id') ?? prefs.getString('user_id');
      
      if (customerIdStr == null) {
        print('❌ [MÜŞTERİ MAIN] Customer ID bulunamadı');
        return;
      }
      
      final customerId = int.tryParse(customerIdStr);
      if (customerId == null || customerId <= 0) {
        print('❌ [MÜŞTERİ MAIN] Geçersiz customer ID: $customerIdStr');
        return;
      }
      
      print('🔍 [MÜŞTERİ MAIN] Backend kontrolü - Customer ID: $customerId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_active_rides.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'include_driver_location': true,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['active_rides'] != null) {
          final activeRides = data['active_rides'] as List;
          
          if (activeRides.isNotEmpty) {
            final ride = activeRides.first;
            final rideStatus = ride['status']?.toString() ?? '';
            
            print('✅ [MÜŞTERİ MAIN] AKTİF YOLCULUK BULUNDU!');
            print('   🆔 Ride ID: ${ride['id']}');
            print('   📊 Status: $rideStatus');
            
            // ❌ pending, scheduled, completed, cancelled → YOLCULUK EKRANI AÇILMAMALI!
            // ✅ SADECE accepted veya in_progress → YOLCULUK EKRANI AÇILMALI!
            if (rideStatus != 'accepted' && rideStatus != 'in_progress') {
              print('📅 [MÜŞTERİ MAIN] Bekleyen/Tamamlanmış yolculuk ($rideStatus) - Yolculuk ekranı AÇILMAYACAK!');
              return;
            }
            
            print('   🚗 Vale KABUL ETTİ - Yolculuk ekranına YÖNLENDİRİLİYOR...');
            
            // Otomatik yolculuk ekranına git
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ModernActiveRideScreen(
                    rideDetails: {
                      'ride_id': ride['id'],
                      'pickup_address': ride['pickup_address'],
                      'destination_address': ride['destination_address'],
                      'estimated_price': ride['estimated_price'],
                      'status': ride['status'],
                      'driver_name': ride['driver_name'] ?? 'Şoför',
                      'driver_phone': ride['driver_phone'] ?? '',
                      'driver_id': ride['driver_id'] ?? 0,
                      'pickup_lat': ride['pickup_lat'],
                      'pickup_lng': ride['pickup_lng'],
                      'destination_lat': ride['destination_lat'],
                      'destination_lng': ride['destination_lng'],
                    },
                  ),
                ),
              );
            }
            return;
          }
        }
      }
      
      print('ℹ️ [MÜŞTERİ MAIN] Backendde aktif yolculuk yok - ana sayfada kalıyor');
      print('ℹ️ PERSISTENCE: Aktif yolculuk yok');
      
    } catch (e) {
      print('❌ [MÜŞTERİ MAIN] Backend kontrol hatası: $e');
    }
  }
  
  // RIDEPROVİDER LİSTENER KURULUM
  void _setupRideProviderListener() {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    
    // Her 200ms kontrol et - persistence yüklenince hemen yakalayacak
    _persistenceTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // Eğer daha önce kontrol etmediyse ve currentRide varsa
      if (!_hasCheckedPersistence && rideProvider.currentRide != null) {
        print('⚡ PERSISTENCE YÜKLENDİ - Aktif yolculuk algılandı!');
        timer.cancel();
        _hasCheckedPersistence = true;
        _checkActiveRidePersistence();
      }
      
      // 5 saniye sonra timer'ı durdur (persistence yüklenmediyse)
      if (timer.tick > 25) { // 25 * 200ms = 5 saniye
        print('⏱️ 5 saniye doldu - persistence timer durduruldu');
        timer.cancel();
        _hasCheckedPersistence = true;
      }
    });
  }
  
  @override
  void dispose() {
    _persistenceTimer?.cancel();
    super.dispose();
  }
  
  // AKTIF YOLCULUK PERSİSTENCE KONTROL
  Future<void> _checkActiveRidePersistence() async {
    try {
      print('🔍 PERSISTENCE KONTROL BAŞLIYOR...');
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      
      print('🔍 RideProvider alındı, currentRide: ${rideProvider.currentRide?.id}');
      
      if (rideProvider.currentRide != null) {
        print('🔄 AKTIF YOLCULUK BULUNDU - ID: ${rideProvider.currentRide!.id}');
        print('🔄 Status: ${rideProvider.currentRide!.status}');
        print('🔄 Yolculuk ekranına yönlendiriliyor...');
        
        // Aktif yolculuk ekranına geç (MODERNİ)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ModernActiveRideScreen(
              rideDetails: {
                'ride_id': rideProvider.currentRide!.id,
                'pickup_address': rideProvider.currentRide!.pickupAddress,
                'destination_address': rideProvider.currentRide!.destinationAddress,
                'customer_id': rideProvider.currentRide!.customerId,
                'driver_id': rideProvider.currentRide!.driverId,
                'estimated_price': rideProvider.currentRide!.estimatedPrice,
                'status': rideProvider.currentRide!.status,
                // GERÇEK ŞOFÖR BİLGİLERİ API'DEN ÇEKILECEK
                'pickup_lat': rideProvider.currentRide!.pickupLocation.latitude,
                'pickup_lng': rideProvider.currentRide!.pickupLocation.longitude,
                'destination_lat': rideProvider.currentRide!.destinationLocation.latitude,
                'destination_lng': rideProvider.currentRide!.destinationLocation.longitude,
              },
            ),
          ),
        );
      } else {
        print('ℹ️ Aktif yolculuk yok - ana sayfada kalıyor');
        print('ℹ️ PERSİSTENCE: Aktif yolculuk yok');
      }
    } catch (e) {
      print('❌ Persistence kontrol hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, languageProvider.getTranslatedText('home')),
                _buildNavItem(1, Icons.apps_rounded, languageProvider.getTranslatedText('services')),
                _buildNavItem(2, Icons.access_time_rounded, languageProvider.getTranslatedText('reservations')),
                _buildNavItem(3, Icons.settings_rounded, languageProvider.getTranslatedText('settings')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    bool isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), // Azaltıldı - sarı alan yazının içine girmemesin
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFFFFD700) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20), // Daha küçük border radius
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                color: isSelected 
                    ? Colors.white 
                    : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                size: isSelected ? 26 : 22,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isSelected 
                    ? Colors.white 
                    : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                fontSize: isSelected ? 11 : 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(
                label,
                overflow: TextOverflow.clip,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
