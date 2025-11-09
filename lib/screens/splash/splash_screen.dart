import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/ride_persistence_service.dart';
import '../main/main_screen.dart';
import '../auth/login_screen.dart';
import '../ride/modern_active_ride_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(seconds: 3));
    
    // PERSİSTENCE KONTROL - AKTİF YOLCULUK VAR MI? ✅
    await _checkForActiveRide();
  }
  
  Future<void> _checkForActiveRide() async {
    try {
      print('🔄 [MÜŞTERİ SPLASH] Aktif yolculuk kontrol ediliyor...');
      
      final shouldRestore = await RidePersistenceService.shouldRestoreRideScreen();
      
      if (shouldRestore) {
        final rideData = await RidePersistenceService.getActiveRide();
        
        if (rideData != null) {
          final status = rideData['status'];
          
          // 🔥 ÖDEME TAMAMLANMIŞ YOLCULUKLARI TEMİZLE - ÖDEME EKRANI DÖNGÜSÜNÜ ENGELLE!
          if (status == 'completed' || status == 'cancelled') {
            print('✅ [MÜŞTERİ SPLASH] Tamamlanmış/iptal yolculuk - Persistence temizleniyor');
            await RidePersistenceService.clearActiveRide();
            _navigateToHome();
            return;
          }
          
          final activeStatuses = ['accepted', 'in_progress', 'driver_arrived', 'ride_started', 'waiting_customer'];
          
          if (activeStatuses.contains(status)) {
            print('🚗 [MÜŞTERİ SPLASH] Aktif yolculuk bulundu - Modern ekrana yönlendiriliyor');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernActiveRideScreen(rideDetails: rideData),
                ),
              );
              return; // Normal akışa gitmesin
            }
          } else {
            // Bilinmeyen status varsa temizle
            await RidePersistenceService.clearActiveRide();
            print('🗑️ [MÜŞTERİ SPLASH] Bilinmeyen status persistence temizlendi: $status');
          }
        }
      }
      
      print('ℹ️ [MÜŞTERİ SPLASH] Aktif yolculuk yok - Normal ana sayfaya yönlendiriliyor');
      
      // Normal ana sayfa akışı
      _navigateToHome();
      
    } catch (e) {
      print('❌ [MÜŞTERİ SPLASH] Persistence kontrol hatası: $e');
      _navigateToHome(); // Hata durumunda normal akış
    }
  }

  void _navigateToHome() {
    if (mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFFD700),
                        Color(0xFFFF8C00),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 60,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'FunBreak Vale',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Premium Vale Hizmetleri',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Yükleniyor...',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
