import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/ride_persistence_service.dart';
import '../home/home_screen.dart';
import '../reservations/reservations_screen.dart';
import '../profile/profile_screen.dart';
import '../ride/modern_active_ride_screen.dart';
import '../../services/dynamic_contact_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _notificationCount = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ReservationsScreen(), 
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
    
    // ANA SAYFA YERİNE AKTİF YOLCULUK KONTROL! ✅
    _checkForActiveRideInMainScreen();
  }

  Future<void> _loadNotificationCount() async {
    // Bildirim sayısını yükle (placeholder)
    setState(() {
      _notificationCount = 0;
    });
  }
  
  // ANA SAYFA AÇILIRKEN AKTİF YOLCULUK KONTROL - BACKEND + LOCAL PERSISTENCE ✅
  Future<void> _checkForActiveRideInMainScreen() async {
    try {
      // 1. BACKEND'DEN AKTIF YOLCULUK KONTROL ET (YENİ!)
      await _checkBackendActiveRide();
      
      // 2. LOCAL PERSISTENCE KONTROL (MEVCUT)
      final shouldRestore = await RidePersistenceService.shouldRestoreRideScreen();
      
      if (shouldRestore) {
        final rideData = await RidePersistenceService.getActiveRide();
        
        if (rideData != null) {
          final status = rideData['status'];
          
          // SADECE AKTİF DURUMLARDA MODERN EKRAN GÖSTER!
          final activeStatuses = ['accepted', 'in_progress', 'driver_arrived', 'ride_started', 'waiting_customer'];
          
          if (activeStatuses.contains(status)) {
            print('🚗 [MÜŞTERİ ANA SAYFA] Aktif yolculuk var - Modern ekrana geçiliyor');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernActiveRideScreen(rideDetails: rideData),
                ),
              );
            }
          } else {
            // Bitmiş yolculuk persistence temizle
            await RidePersistenceService.clearActiveRide();
            print('🗑️ [MÜŞTERİ ANA SAYFA] Bitmiş yolculuk persistence temizlendi - Normal ana sayfa kalacak');
          }
        }
      }
    } catch (e) {
      print('❌ [MÜŞTERİ ANA SAYFA] Persistence kontrol hatası: $e');
    }
  }
  
  // BACKEND'DEN AKTİF YOLCULUK KONTROL - MANUEL ATAMA DESTEĞİ! ✅
  Future<void> _checkBackendActiveRide() async {
    try {
      final authProvider = mounted ? Provider.of<AuthProvider>(context, listen: false) : null;
      final prefs = await SharedPreferences.getInstance();

      String? customerIdStr = authProvider?.customerId;
      customerIdStr ??= prefs.getString('admin_user_id');
      customerIdStr ??= prefs.getString('user_id');

      final customerId = int.tryParse(customerIdStr ?? '');
      
      if (customerId == null) {
        print('⚠️ Customer ID bulunamadı - persistence temizlenecek, backend kontrol atlandı');
        await RidePersistenceService.clearActiveRide();
        return;
      }
      
      print('🔍 Backend aktif yolculuk kontrol - Customer: $customerId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_active_rides.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'customer_id': customerId}),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] && data['has_active_ride'] && data['active_rides'] != null && data['active_rides'].isNotEmpty) {
          final activeRide = data['active_rides'][0]; // İlk aktif yolculuğu al
          print('✅ Backend aktif yolculuk bulundu: Ride ${activeRide['id']}');
          print('👨‍✈️ Driver: ${activeRide['driver_name']}, Status: ${activeRide['status']}');
          print('🗂️ Source: ${activeRide['source'] ?? 'unknown'}');
          
          // LOCAL PERSISTENCE'I GÜNCELLE
          await RidePersistenceService.saveActiveRide(
            rideId: activeRide['id'],
            status: activeRide['status'],
            pickupAddress: activeRide['pickup_address'],
            destinationAddress: activeRide['destination_address'],
            estimatedPrice: double.tryParse((activeRide['estimated_price'] ?? 0).toString()) ?? 0.0,
            driverName: activeRide['driver_name'],
            driverPhone: activeRide['driver_phone'],
            driverId: activeRide['driver_id'].toString(),
            additionalData: {
              'driver_rating': activeRide['driver_rating'],
              'scheduled_time': activeRide['scheduled_time'],
              'manual_assignment': activeRide['manual_assignment'] ?? false,
              'source': activeRide['source'] ?? 'backend_sync'
            }
          );
          
          print('💾 Backend'den alınan yolculuk local persistence'e kaydedildi');
          
          // YOLCULUK EKRANINA GİT!
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/modern_active_ride', arguments: {
              'ride_id': activeRide['id'],
              'status': activeRide['status'],
              'driver_name': activeRide['driver_name'],
              'driver_phone': activeRide['driver_phone'],
              'driver_rating': activeRide['driver_rating'],
              'pickup_address': activeRide['pickup_address'],
              'destination_address' : activeRide['destination_address'],
              'estimated_price': activeRide['estimated_price'],
              'scheduled_time': activeRide['scheduled_time'],
              'manual_assignment': activeRide['manual_assignment'] ?? false
            });
            print('🎯 Backend aktif yolculuk nedeniyle modern ekrana yönlendirildi');
          }
          
        } else {
          print("ℹ️ Backend'de aktif yolculuk yok veya success=false");
          await RidePersistenceService.clearActiveRide();
        }
      } else {
        print('❌ Backend aktif yolculuk kontrol hatası: HTTP ${response.statusCode}');
        await RidePersistenceService.clearActiveRide();
      }
      
    } catch (e) {
      print('❌ Backend aktif yolculuk kontrol exception: $e');
      await RidePersistenceService.clearActiveRide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              themeProvider.isDarkMode ? Colors.grey[900]! : Colors.white,
              themeProvider.isDarkMode ? Colors.grey[800]! : const Color(0xFFF8F9FA),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          currentIndex: _currentIndex,
          onTap: (index) {
            // ANA SAYFA BASILINCA AKTİF YOLCULUK KONTROL ET! ✅
            if (index == 0) { // Ana sayfa sekmesi
              _checkForActiveRideInMainScreen();
            }
            
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFFD700),
          unselectedItemColor: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home),
              activeIcon: Icon(Icons.home),
              label: 'Ana Sayfa',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  const Icon(Icons.history),
                  if (_notificationCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: Text(
                          _notificationCount > 99 ? '99+' : '$_notificationCount',
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
              activeIcon: const Icon(Icons.history),
              label: 'Geçmiş',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
