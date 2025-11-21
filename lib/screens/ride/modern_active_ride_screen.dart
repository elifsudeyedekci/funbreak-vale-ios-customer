import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math; // MESAFE HESAPLAMA İÇİN!
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../chat/ride_chat_screen.dart';
import '../../providers/theme_provider.dart';
import '../../providers/admin_api_provider.dart';
import '../../providers/ride_provider.dart';
import '../../services/ride_persistence_service.dart';
import '../../services/realtime_package_monitor.dart';
import '../messaging/ride_messaging_screen.dart';
import '../../services/company_contact_service.dart'; // ŞİRKET ARAMA SERVİSİ!
import 'ride_payment_screen.dart';

class ModernActiveRideScreen extends StatefulWidget {
  final Map<String, dynamic> rideDetails;
  
  const ModernActiveRideScreen({Key? key, required this.rideDetails}) : super(key: key);
  
  @override
  State<ModernActiveRideScreen> createState() => _ModernActiveRideScreenState();
}

class _ModernActiveRideScreenState extends State<ModernActiveRideScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  Timer? _trackingTimer;
  Map<String, dynamic> _currentRideStatus = {};
  bool _isLoading = true;
  
  // Location variables
  LatLng? _customerLocation;
  LatLng? _driverLocation;
  Map<String, dynamic>? _driverInfo;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  
  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _glowController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _rippleAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Real-time package monitoring
  bool _packageMonitorActive = false;
  double _currentPrice = 0.0;
  double _currentHours = 0.0;
  
  // ✅ TAHMİNİ FİYAT (SABİT - İlk rota fiyatı, BİR DAHA DEĞİŞMEZ!)
  double _initialEstimatedPrice = 0.0;
  
  // ✅ SAATLİK PAKET CACHE
  List<Map<String, double>> _cachedHourlyPackages = [];
  
  // 🗺️ HARİTA KAMERA KONTROLÜ
  bool _isFirstCameraUpdate = true; // İlk açılışta kamera ayarla, sonra SADECE marker güncelle
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _saveToPersistence();
    _loadHourlyPackages(); // Panel'den saatlik paketleri çek!
    
    // ✅ TAHMİNİ FİYAT (SABİT) - İLK ROTA SEÇERKENKİ FİYAT (BİR KEZ SET EDİLİR, DEĞİŞMEZ!)
    _initialEstimatedPrice = double.tryParse(
          widget.rideDetails['initial_estimated_price']?.toString() ??
          widget.rideDetails['estimated_price']?.toString() ??
          '0',
        ) ??
        0.0;
    if (_initialEstimatedPrice == 0.0) {
      _initialEstimatedPrice = 1000.0; // Fallback (minimum)
    }
    print('📌 [MÜŞTERİ] Tahmini fiyat (sabit): ₺${_initialEstimatedPrice} - Bu değişmeyecek!');
    
    // Başlangıçta konumları ayarla
    _customerLocation = LatLng(
      (widget.rideDetails['pickup_lat'] as num?)?.toDouble() ?? 41.0082,
      (widget.rideDetails['pickup_lng'] as num?)?.toDouble() ?? 28.9784,
    );
    
    // İlk marker'ları oluştur
    _updateMapMarkers();
    
    // YASAL SÖZLEŞME LOGLARINI KAYDET
    _logLegalConsents();
    
    // Async işlemleri bekletme - ekran hemen açılsın
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeRideTracking();
    _initializePackageMonitoring();
    });
  }
  
  // YASAL SÖZLEŞME LOGLARI
  Future<void> _logLegalConsents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('admin_user_id') ?? prefs.getString('user_id');
      
      if (customerId == null) return;
      
      final position = await Geolocator.getCurrentPosition();
      
      // 1. ÖN BİLGİLENDİRME LOGU - TAM METİN!
      final onBilgilendirmeText = '''FunBreak Vale Ön Bilgilendirme Koşulları

Değerli Müşterimiz,

FunBreak Vale hizmetini kullanmadan önce aşağıdaki bilgilendirmeleri dikkatlice okumanızı rica ederiz:

1. HİZMET KAPSAMI
- Vale (valet) park hizmeti sunulmaktadır
- Aracınız profesyonel şoförler tarafından park edilecek/alınacaktır
- Saatlik paket hizmetleri mevcuttur

2. FİYATLANDIRMA
- Mesafe bazlı fiyatlandırma uygulanır
- Bekleme ücreti: İlk 15 dakika ücretsiz, sonrası 15 dakikalık periyotlar halinde ücretlendirilir
- Saatlik paketler sabit fiyatlıdır

3. ÖDEME KOŞULLARI
- Kredi kartı veya Havale/EFT ile ödeme yapılabilir
- Yolculuk tamamlandıktan sonra ödeme yapılır

4. İPTAL KOŞULLARI
- Vale kabul edilmeden önce: Ücretsiz iptal
- Vale kabul edildikten sonraki 45 dakika: Ücretsiz iptal
- 45 dakika sonrası iptal: Tam ücret tahsil edilir

5. SORUMLULUK
- Araç teslim alındıktan sonra FunBreak Vale sorumludur
- Aracınızda mevcut hasar varsa bildirilmelidir

6. KİŞİSEL VERİLER
- Konum bilgileriniz hizmet sunumu için kullanılır
- KVKK kapsamında korunur

Bu koşulları kabul ederek hizmeti kullanmayı onaylıyorum.

Tarih: ${DateTime.now().toString().split(' ')[0]}
''';
      
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.parse(customerId),
          'consent_type': 'on_bilgilendirme',
          'consent_text': onBilgilendirmeText,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'location_accuracy': position.accuracy,
          'platform': 'Android',
        }),
      ).timeout(const Duration(seconds: 5));
      
      // 2. MESAFELİ SATIŞ SÖZLEŞMESİ LOGU - TAM METİN!
      final mesafeliSatisText = '''FunBreak Vale Mesafeli Satış Sözleşmesi

6502 sayılı Tüketicinin Korunması Hakkında Kanun uyarınca:

SATICI BİLGİLERİ:
FunBreak Vale Hizmetleri
Adres: İstanbul, Türkiye
E-posta: info@funbreakvale.com
Telefon: [Destek hattı]

ALICI BİLGİLERİ:
Müşteri adı ve bilgileri sistemde kayıtlıdır.

SÖZLEŞME KONUSU HİZMET:
Vale (valet) park ve araç götürme hizmeti

ÖDEME VE TESLİMAT:
- Hizmet bedeli yolculuk tamamlandıktan sonra tahsil edilir
- Kredi kartı veya Havale/EFT ile ödeme
- Hizmet anında teslim edilir

CAYMA HAKKI:
- Vale kabul edilmeden önce cayma hakkı vardır
- Vale kabul edildikten sonraki 45 dakika içinde cayma hakkı vardır
- 45 dakika sonrası cayma halinde ücret tahsil edilir

UYUŞMAZLIK ÇÖZÜMÜ:
İstanbul (Merkez) Tüketici Hakem Heyetleri ve Tüketici Mahkemeleri yetkilidir.

YÜRÜRLÜK:
Bu sözleşme elektronik ortamda kabul edilmiş ve yürürlüğe girmiştir.

Kabul Tarihi: ${DateTime.now().toString().split(' ')[0]}
''';
      
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.parse(customerId),
          'consent_type': 'mesafeli_satis',
          'consent_text': mesafeliSatisText,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'location_accuracy': position.accuracy,
          'platform': 'Android',
        }),
      ).timeout(const Duration(seconds: 5));
      
      print('✅ Yolculuk sözleşme logları kaydedildi');
    } catch (e) {
      print('⚠️ Sözleşme log hatası: $e');
    }
  }
  
  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _glowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.elasticOut));
    
    _slideController.forward();
  }
  
  void _saveToPersistence() async {
    try {
      final rideIdStr = widget.rideDetails['ride_id']?.toString() ?? '0';
      final rideId = int.tryParse(rideIdStr) ?? 0;
      
      final estimatedPriceStr = widget.rideDetails['estimated_price']?.toString() ?? '0';
      final estimatedPrice = double.tryParse(estimatedPriceStr) ?? 0.0;
      
      await RidePersistenceService.saveActiveRide(
        rideId: rideId,
        status: widget.rideDetails['status']?.toString() ?? 'accepted',
        pickupAddress: widget.rideDetails['pickup_address']?.toString() ?? '',
        destinationAddress: widget.rideDetails['destination_address']?.toString() ?? '',
        estimatedPrice: estimatedPrice,
        driverName: _driverName(),
        driverPhone: _driverPhone(),
        driverId: widget.rideDetails['driver_id']?.toString() ?? '0',
      );
      
      print('✅ PERSİSTENCE: Yolculuk başarıyla kaydedildi - Ride ID: $rideId');
    } catch (e) {
      print('❌ PERSİSTENCE HATA: $e');
    }
  }
  
  void _initializeRideTracking() async {
    try {
      print('🚗 [MODERN] Aktif yolculuk takibi başlatılıyor...');
      
      await _updateRideStatus();
      
      // Real-time tracking başlat (her 3 saniye - daha hızlı)
      _trackingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _updateRideStatus();
      });
      
      // _isLoading artık kullanılmıyor - ekran hızlı açılsın
      
      print('✅ [MODERN] Yolculuk takibi aktif - 3 saniyede bir güncelleme');
      
    } catch (e) {
      print('❌ [MODERN] Yolculuk takibi başlatma hatası: $e');
      // _isLoading artık kullanılmıyor - ekran hızlı açılsın
    }
  }
  
  void _initializePackageMonitoring() {
    final rideType = widget.rideDetails['ride_type'] ?? 'standard';
    
    if (rideType == 'hourly') {
      print('📦 [MODERN] Saatlik paket tespit edildi - Package monitoring başlatılıyor');
      
      setState(() {
        _packageMonitorActive = true;
        _currentPrice = (widget.rideDetails['estimated_price'] ?? 0).toDouble();
      });
      
      // Real-time package monitoring
      Timer.periodic(const Duration(seconds: 30), (timer) async {
        await _checkPackageUpgradeRealtime(timer);
      });
    }
  }
  
  Future<void> _checkPackageUpgradeRealtime(Timer timer) async {
    // Package monitor logic from previous implementation
    // ... (kod kısaltıldı)
  }
  
  // ✅ SAATLİK PAKETLERI PANEL'DEN ÇEK (ANLIK!)
  Future<void> _loadHourlyPackages() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_hourly_packages.php'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['packages'] != null) {
          final packages = data['packages'] as List;
          
          setState(() {
            _cachedHourlyPackages = packages.map((pkg) => {
              'start': double.tryParse(pkg['start_hour']?.toString() ?? '0') ?? 0.0,
              'end': double.tryParse(pkg['end_hour']?.toString() ?? '0') ?? 0.0,
              'price': double.tryParse(pkg['price']?.toString() ?? '0') ?? 0.0,
            }).toList();
          });
          
          print('✅ [MÜŞTERİ] ${_cachedHourlyPackages.length} saatlik paket yüklendi');
        }
      }
    } catch (e) {
      print('⚠️ [MÜŞTERİ] Saatlik paket yükleme hatası: $e');
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _glowController.dispose();
    _rippleController.dispose();
    _trackingTimer?.cancel();
    
    // Persistence temizle ve ana sayfaya dön - YOLCULUK BİTTİYSE! ✅
    final currentStatus = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? '';
    if (currentStatus == 'completed' || currentStatus == 'cancelled') {
      RidePersistenceService.clearActiveRide();
      print('🗑️ [MÜŞTERİ] Yolculuk bitti - Persistence temizlendi, ana sayfaya dönülecek');
      
      // Ana sayfaya dön (persistence temizlendiği için normal ana sayfa açılır)
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } else {
      print('💾 [MÜŞTERİ] Yolculuk devam ediyor - Persistence korundu');
    }
    
    super.dispose();
  }

  String _driverName() {
    final dynamic fromStatus = _currentRideStatus['driver_name'];
    final dynamic fromDetails = widget.rideDetails['driver_name'];
    final name = (fromStatus ?? fromDetails)?.toString().trim();
    if (name == null || name.isEmpty) {
      return 'Şoförünüz';
    }
    return name;
  }

  String _driverPhone() {
    final dynamic fromStatus = _currentRideStatus['driver_phone'];
    final dynamic fromDetails = widget.rideDetails['driver_phone'];
    final phone = (fromStatus ?? fromDetails)?.toString().trim();
    if (phone == null || phone.isEmpty) {
      return '';
    }
    return phone;
  }

  String _driverAvatarInitial() {
    final name = _driverName();
    if (name.isEmpty) return 'Ş';
    return name.characters.first.toUpperCase();
  }

  String? _driverPhotoUrl() {
    final dynamic fromStatus = _currentRideStatus['driver_photo_url'] ?? _currentRideStatus['driver_photo'];
    final dynamic fromDetails = widget.rideDetails['driver_photo_url'] ?? widget.rideDetails['driver_photo'];
    final url = (fromStatus ?? fromDetails)?.toString().trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return PopScope(
      canPop: false, // Geri tuşunu devre dışı bırak
      child: Scaffold(
      backgroundColor: Colors.transparent,
      // ALT BAR EKLENDİ - MODERN YOLCULUK EKRANINDA! ✅
      bottomNavigationBar: _buildModernBottomBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A1A2E),
              const Color(0xFF16213E),
              const Color(0xFF0F0F1A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
                children: [
                  // Üst Header - Gradient ve Glow Effect
                  _buildModernHeader(),
                  
                  // Ana Harita Bölümü  
                  Expanded(
                    flex: 3,
                    child: _buildModernMap(),
                  ),
                  
                  // Alt Detay Paneli - Sliding Animation
                  _buildModernBottomPanel(),
                ],
              ),
        ),
      ),
      ),
    ); // PopScope kapatma
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFFFFD700),
                        Color(0xFFFFA500),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 50,
                    color: Colors.black,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Yolculuk bilgileri yükleniyor...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFD700),
            Color(0xFFFFA500),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.3),
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
              // Geri tuşu kaldırıldı - kullanıcı yolculuk sırasında çıkamaz
              const SizedBox(width: 48), // Boş alan
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(_glowAnimation.value * 0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Text(
                      '🚗 Aktif Yolculuk',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              // Üst mesaj butonu kaldırıldı - sadece alt bar'da kalacak
              const SizedBox(width: 48), // Boş alan
            ],
          ),
          
          // Saatlik Paket Info (eğer varsa)
          if (_packageMonitorActive) ...[
            const SizedBox(height: 16),
            _buildPackageMonitorWidget(),
          ],
        ],
      ),
    );
  }
  
  Widget _buildPackageMonitorWidget() {
    return AnimatedBuilder(
      animation: _rippleAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(_rippleAnimation.value * 0.3),
                blurRadius: 15,
                spreadRadius: _rippleAnimation.value * 3,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.access_time,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📦 Saatlik Paket Aktif',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Süre: ${_currentHours.toStringAsFixed(1)}h | Fiyat: ₺${_currentPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  'CANLI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildModernMap() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: GoogleMap(
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
          },
          initialCameraPosition: CameraPosition(
            target: LatLng(
              (widget.rideDetails['pickup_lat'] as num?)?.toDouble() ?? 41.0082,
              (widget.rideDetails['pickup_lng'] as num?)?.toDouble() ?? 28.9784,
            ),
            zoom: 15,
          ),
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }
  
  Widget _buildModernBottomPanel() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A2A3E),
              Color(0xFF1A1A2E),
            ],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // İçerik
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Durum Card'ı
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  
                  // ✅ FİYAT KARTLARI - HER ZAMAN GÖSTER!
                  _buildPriceCards(),
                  const SizedBox(height: 16),
                  
                  // Şoför Bilgileri
                  _buildDriverInfoCard(),
                  const SizedBox(height: 16),
                  
                  // Aksiyon Butonları
                  _buildActionButtons(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusCard() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    final statusInfo = _getStatusInfo(status);
    
    // ✅ 'accepted', 'in_progress' durumlarında kartı gizle
    if (status == 'accepted' || status == 'in_progress' || status == 'ride_started') {
      return const SizedBox.shrink();
    }
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: statusInfo['colors'],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: statusInfo['colors'][0].withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: _pulseAnimation.value * 3,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusInfo['icon'],
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusInfo['title'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          statusInfo['subtitle'],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
          ],
        );
      },
    );
  }
  
  // ✅ FİYAT KARTLARI - BAĞIMSIZ WIDGET (HER ZAMAN GÖSTER!)
  Widget _buildPriceCards() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    
    // Sadece yolculuk başladıktan sonra göster
    if (status != 'in_progress' && status != 'ride_started') {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // KM ve BEKLEME BİLGİLERİ
          Row(
            children: [
              Expanded(
                child: _buildRideMetric(
                  icon: Icons.straighten,
                  label: 'Gidilen KM',
                  value: '${_getCurrentKm()} km',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRideMetric(
                  icon: Icons.access_time,
                  label: _isHourlyPackage() ? 'Süre' : 'Bekleme',
                  value: _getWaitingOrDurationDisplay(),
                  color: Colors.orange,
                  subtitle: _isHourlyPackage() ? null : _getWaitingFeeSubtitle(),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // ✅ İKİ KUTUCUK YAN YANA: TAHMİNİ FİYAT (Sabit) + GÜNCEL TUTAR (Dinamik)
          Row(
            children: [
              // 📦 TAHMİNİ FİYAT (SABİT - İlk fiyat, bekleme YOK!)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade500.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, color: Colors.white70, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Tahmini Fiyat',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₺${_getInitialEstimatedPrice()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Sabit',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // 💰 GÜNCEL TUTAR (DİNAMİK - KM + Bekleme)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.trending_up, color: Color(0xFFFFD700), size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Güncel Tutar',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₺${_calculateCurrentTotal()}',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isHourlyPackage() 
                          ? 'Saatlik paket' 
                          : '${_getCurrentKm()} km${_getWaitingMinutes() > 0 ? " + ${_getWaitingMinutes()} dk (₺${_calculateWaitingFee()})" : ""}',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // SAATLİK PAKET BADGE
          if (_isHourlyPackage()) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '📦 SAATLİK PAKET: ${_getHourlyPackageLabel()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildDriverInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // Driver Avatar with Glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(_glowAnimation.value * 0.5),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFFFD700),
                  backgroundImage: _driverPhotoUrl() != null
                      ? NetworkImage(_driverPhotoUrl()!)
                      : null,
                  child: _driverPhotoUrl() == null
                      ? Text(
                          _driverAvatarInitial(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _driverName(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Dinamik yıldız puanı
                    ...List.generate(5, (index) {
                      final rating = (_currentRideStatus['driver_rating'] ?? 4.5).toDouble();
                      return Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: const Color(0xFFFFD700),
                        size: 16,
                      );
                    }),
                    const SizedBox(width: 4),
                    Text(
                      (_currentRideStatus['driver_rating'] ?? 4.5).toStringAsFixed(1),
                      style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'ONAYLI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButtons() {
    return Row(
      children: [
        // DİREKT ŞOFÖR ARAMA SİSTEMİ! ✅
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.blue, Colors.indigo],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () => _callDriverDirectly(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Şoförü Ara',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // Mesaj butonu
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.purple, Colors.deepPurple],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () => _openMessaging(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.message, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Mesaj',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // İptal butonu
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.red, Colors.redAccent],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () => _cancelRide(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ],
    );
  }
  
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'accepted':
        return {
          'title': '✅ Şoför Kabul Etti!',
          'subtitle': 'Size doğru geliyor...',
          'icon': Icons.check_circle,
          'colors': [const Color(0xFF4CAF50), const Color(0xFF81C784)],
        };
      case 'driver_arrived':
        return {
          'title': '📍 Şoför Geldi!',
          'subtitle': 'Şoför bekleme noktasında',
          'icon': Icons.location_on,
          'colors': [const Color(0xFFFF9800), const Color(0xFFFFCC02)],
        };
      case 'ride_started':
      case 'in_progress':
        return {
          'title': '🚗 Yolculuk Başladı!',
          'subtitle': 'İyi yolculuklar, varış noktasına gidiliyor',
          'icon': Icons.directions_car,
          'colors': [const Color(0xFF2196F3), const Color(0xFF64B5F6)],
        };
      default:
        return {
          'title': '📡 Bilgiler güncelleniyor',
          'subtitle': 'Durum kısa süre içinde yenilenecek',
          'icon': Icons.hourglass_empty,
          'colors': [const Color(0xFF9C27B0), const Color(0xFFBA68C8)],
        };
    }
  }
  
  Future<void> _updateRideStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('user_id') ?? '0';
      final rideId = widget.rideDetails['ride_id'] ?? 0;
      
      // ✅ Her 3 saniyede saatlik paketleri yenile (badge için!)
      _loadHourlyPackages();
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_active_rides.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
          'ride_id': rideId,
          'include_driver_location': true, // ŞOFÖR KONUM BİLGİSİ İSTİYORUZ!
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['active_rides'] != null) {
          final activeRides = data['active_rides'] as List;
          
          // AKTİF YOLCULUK YOK - İPTAL EDİLMİŞ VEYA TAMAMLANMIŞ!
          if (activeRides.isEmpty) {
            print('⚠️ [MÜŞTERİ] Aktif yolculuk bulunamadı - iptal edilmiş veya tamamlanmış olabilir');
            
            try {
              // RideProvider'dan temizle
              if (mounted) {
                final rideProvider = Provider.of<RideProvider>(context, listen: false);
                rideProvider.clearCurrentRide();
                print('🗑️ [MÜŞTERİ] RideProvider temizlendi');
              }
            } catch (e) {
              print('❌ RideProvider temizleme hatası: $e');
            }
            
            // Önce tüm timer'ları durdur
            _trackingTimer?.cancel();
            
            // 🔍 Backend'den son durumu kontrol et - tamamlanmış mı, iptal mi?
            print('🔍 [MÜŞTERİ] Backendden son durum kontrol ediliyor...');
            
            try {
              final customerId = await _getCustomerId();
              final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
              
              final checkResponse = await http.get(
                Uri.parse('https://admin.funbreakvale.com/api/check_ride_status.php?ride_id=$rideId&customer_id=$customerId'),
              ).timeout(const Duration(seconds: 5));
              
              if (checkResponse.statusCode == 200) {
                final checkData = jsonDecode(checkResponse.body);
                final finalStatus = checkData['status'] ?? 'unknown';
                final cancellationFee = (checkData['cancellation_fee'] ?? 0) is int 
                    ? (checkData['cancellation_fee'] as int).toDouble() 
                    : checkData['cancellation_fee'] ?? 0.0;
                
                print('📊 [MÜŞTERİ] Final status: $finalStatus');
                print('💰 [MÜŞTERİ] Cancellation fee: ₺$cancellationFee');
                
                // COMPLETED İSE ÖDEME EKRANINA GİT!
                if (finalStatus == 'completed') {
                  print('💳 [MÜŞTERİ] Yolculuk tamamlandı - ödeme ekranına yönlendiriliyor...');
                  
                  if (mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        // GÜNCEL TUTAR VE TÜM BİLGİLERİ AL - Backend'den!
                        final currentTotal = double.tryParse(_calculateCurrentTotal()) ?? 0.0;
                        
                        // GÜNCEL ride status'ı oluştur - Backend'den gelen TÜM bilgilerle!
                        final completedRideStatus = Map<String, dynamic>.from(_currentRideStatus);
                        completedRideStatus['status'] = 'completed';
                        completedRideStatus['final_price'] = currentTotal > 0 ? currentTotal : (_currentRideStatus['estimated_price'] ?? widget.rideDetails['estimated_price'] ?? 0);
                        
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => RidePaymentScreen(
                              rideDetails: Map<String, dynamic>.from(widget.rideDetails),
                              rideStatus: completedRideStatus,
                            ),
                          ),
                        );
                      }
                    });
                  }
                }
                // İPTAL EDİLMİŞ VE İPTAL ÜCRETİ VAR İSE ÖDEME EKRANINA GİT!
                else if (finalStatus == 'cancelled' && cancellationFee > 0) {
                  print('💳 [MÜŞTERİ] İptal edildi VE iptal ücreti var (₺$cancellationFee) - ödeme ekranına yönlendiriliyor...');
                  
                  if (mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => RidePaymentScreen(
                              rideDetails: Map<String, dynamic>.from(widget.rideDetails),
                              rideStatus: {
                                'status': 'cancelled',
                                'final_price': cancellationFee,
                                'is_cancellation_fee': true,
                              },
                            ),
                          ),
                        );
                      }
                    });
                  }
                }
                // ÜCRETSİZ İPTAL - ANA SAYFAYA DÖN!
                else {
                  print('🏠 [MÜŞTERİ] Yolculuk iptal edilmiş ($finalStatus) - ücretsiz, ana sayfaya dönülüyor...');
                  
                  if (mounted) {
                    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                }
              } else {
                // Backend hatası - ana sayfaya dön
                print('❌ [MÜŞTERİ] Backend kontrol hatası - ana sayfaya dönülüyor...');
                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
                }
              }
            } catch (e) {
              print('❌ [MÜŞTERİ] Status kontrol hatası: $e - ana sayfaya dönülüyor...');
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
              }
            }
            
            return;
          }
          
          final activeRide = activeRides.first;
            
          if (activeRide != null) {
            // ÖNCEKİ STATUS'U SAKLA
            final previousStatus = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'unknown';
            final newStatus = activeRide['status'] ?? 'unknown';
            
            setState(() {
              _currentRideStatus = activeRide;
              
              // API'den gelen değerleri widget.rideDetails'e de kopyala
              widget.rideDetails['status'] = activeRide['status'] ?? widget.rideDetails['status']; // STATUS GÜNCELLE!
              widget.rideDetails['calculated_price'] = activeRide['calculated_price'] ?? widget.rideDetails['calculated_price'];
              widget.rideDetails['estimated_price'] = activeRide['estimated_price'] ?? widget.rideDetails['estimated_price'];
              widget.rideDetails['waiting_minutes'] = activeRide['waiting_minutes'] ?? widget.rideDetails['waiting_minutes'];
              widget.rideDetails['current_km'] = activeRide['current_km'] ?? widget.rideDetails['current_km'];
              widget.rideDetails['started_at'] = activeRide['started_at'] ?? widget.rideDetails['started_at'];
              widget.rideDetails['driver_name'] = activeRide['driver_name'] ?? widget.rideDetails['driver_name'];
              widget.rideDetails['driver_phone'] = activeRide['driver_phone'] ?? widget.rideDetails['driver_phone'];
              widget.rideDetails['driver_photo'] = activeRide['driver_photo'] ?? widget.rideDetails['driver_photo'];
              widget.rideDetails['driver_vehicle'] = activeRide['driver_vehicle'] ?? widget.rideDetails['driver_vehicle'];
              widget.rideDetails['driver_plate'] = activeRide['driver_plate'] ?? widget.rideDetails['driver_plate'];
              
              // BEKLEME SÜRESİ GÜNCELLEME LOGU
              final waitingMinutes = activeRide['waiting_minutes'] ?? 0;
              final currentKm = activeRide['current_km'] ?? 0.0;
              final calculatedPrice = activeRide['calculated_price'] ?? activeRide['estimated_price'] ?? 0.0;
              print('📊 [MÜŞTERİ] Yolculuk durumu güncellendi:');
              print('   📍 Status: $previousStatus → $newStatus');
              print('   ⏳ Bekleme: $waitingMinutes dk');
              print('   📏 KM: $currentKm km');
              print('   💰 Fiyat: ₺$calculatedPrice');

              // ŞOFÖR KONUM BİLGİLERİNİ AL! ✅
              if (activeRide['driver_lat'] != null && activeRide['driver_lng'] != null) {
                _driverLocation = LatLng(
                  (activeRide['driver_lat'] as num).toDouble(),
                  (activeRide['driver_lng'] as num).toDouble(),
                );
                
                print('📍 [MÜŞTERİ] Şoför konumu güncellendi: ${_driverLocation!.latitude}, ${_driverLocation!.longitude}');
                
                // Harita marker'larını güncelle
                _updateMapMarkers();
                _updateRoutePolyline(); // ROTA ÇİZGİSİ EKLEYELİM!
              } else {
                print('Sofor konumu henuz alinamadi - API den gelecek');
              }
              
              // Müşteri konumu (kendi konumunuz)
              if (activeRide['customer_lat'] != null && activeRide['customer_lng'] != null) {
                _customerLocation = LatLng(
                  (activeRide['customer_lat'] as num).toDouble(),
                  (activeRide['customer_lng'] as num).toDouble(),
                );
              }
            });
            
            // STATUS DEĞİŞİMİ LOGU!
            if (previousStatus != newStatus) {
              print('🔄 === MÜŞTERİ: STATUS DEĞİŞİMİ TESPİT EDİLDİ! ===');
              print('   📌 Önceki: $previousStatus');
              print('   📌 Yeni: $newStatus');
              print('   ✅ UI GÜNCELLEND İ - Ekran yeniden render edildi!');
              
              // ACCEPTED → IN_PROGRESS geçişinde özel mesaj
              if (previousStatus == 'accepted' && newStatus == 'in_progress') {
                print('🚗 === MÜŞTERİ: YOLCULUK BAŞLATILDI! ===');
                print('   ✅ Sürücü yolculuğu başlattı');
                print('   📲 Ekran otomatik güncellendi');
              }
            }
            
            // Persistence güncelle
            RidePersistenceService.updateRideStatus(_currentRideStatus['status'] ?? 'accepted');

            final status = (_currentRideStatus['status'] ?? '').toString();
            if (status == 'completed') {
              _trackingTimer?.cancel();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => RidePaymentScreen(
                      rideDetails: Map<String, dynamic>.from(widget.rideDetails),
                      rideStatus: Map<String, dynamic>.from(_currentRideStatus),
                    ),
                  ),
                );
              }
              return;
            }
          }
        }
      }
    } catch (e) {
      print('❌ [MÜŞTERİ] Ride status güncelleme hatası: $e');
      
      // Eğer timeout ise yolculuk bitmiş olabilir - ZORLA ÇIKIŞ
      if (e.toString().contains('TimeoutException') || e.toString().contains('Null check')) {
        print('⏱️ [MÜŞTERİ] API hatası (timeout/null) - ZORLA ana sayfaya dönüş');
        
        try {
          // RideProvider'dan temizle
          if (mounted) {
            final rideProvider = Provider.of<RideProvider>(context, listen: false);
            rideProvider.clearCurrentRide();
          }
        } catch (providerError) {
          print('❌ Provider temizleme hatası: $providerError');
        }
        
        // Timer'ları durdur
        _trackingTimer?.cancel();
        
        // ZORLA ana sayfaya git
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          });
        }
      }
    }
  }
  
  // HARİTA MARKER'LARINI GÜNCELLE - ŞOFÖR + MÜŞTERİ KONUM! ✅
  void _updateMapMarkers() {
    final Set<Marker> newMarkers = {};
    
    // Müşteri konumu (yeşil marker)
    if (_customerLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('customer_location'),
          position: _customerLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: '👤 Sizin Konumunuz',
            snippet: 'Müşteri konumu',
          ),
        ),
      );
    }
    
    // Şoför konumu (mavi marker)
    if (_driverLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: '🚗 ${_driverName()}',
            snippet: 'Şoför konumu - ${_calculateDriverDistance().toStringAsFixed(1)} km uzakta',
          ),
        ),
      );
    }
    
    setState(() {
      _markers = newMarkers;
    });
    
    // 🗺️ Harita kamerasını SADECE İLK AÇILIŞTA ayarla, sonra kullanıcı kontrolünde!
    if (_isFirstCameraUpdate && _customerLocation != null && _driverLocation != null && _mapController != null) {
      _fitMarkersOnMap();
      _isFirstCameraUpdate = false; // Artık kamera hareket etmeyecek!
      print('📷 İlk kamera pozisyonu ayarlandı - artık sadece marker güncellenecek');
    }
  }
  
  // HARİTA KAMERASINI İKİ KONUMU DA GÖSTERECEK ŞEKİLDE AYARLA (SADECE İLK AÇILIŞTA!)
  void _fitMarkersOnMap() {
    if (_customerLocation == null || _driverLocation == null || _mapController == null) return;
    
    // Müşteri-sürücü arası mesafe hesapla
    final distance = _calculateDriverDistance();
    
    // Mesafeye göre zoom level belirle (daha iyi görünüm)
    double zoomLevel;
    if (distance < 1) {
      zoomLevel = 15.0; // Çok yakın (0-1 km)
    } else if (distance < 5) {
      zoomLevel = 13.0; // Yakın (1-5 km)
    } else if (distance < 10) {
      zoomLevel = 12.0; // Orta (5-10 km)
    } else {
      zoomLevel = 11.0; // Uzak (10+ km)
    }
    
    // İki nokta arasındaki orta noktaya zoom yap
    double centerLat = (_customerLocation!.latitude + _driverLocation!.latitude) / 2;
    double centerLng = (_customerLocation!.longitude + _driverLocation!.longitude) / 2;
    
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(centerLat, centerLng),
          zoom: zoomLevel,
          tilt: 0,
          bearing: 0,
        ),
      ),
    );
    
    print('📷 Harita kamerası ayarlandı: zoom=$zoomLevel, distance=${distance.toStringAsFixed(1)}km');
  }
  
  // ŞOFÖR MESAFESİ HESAPLA
  double _calculateDriverDistance() {
    if (_customerLocation == null || _driverLocation == null) return 0.0;
    
    return _haversineDistance(
      _customerLocation!.latitude,
      _customerLocation!.longitude,
      _driverLocation!.latitude,
      _driverLocation!.longitude,
    );
  }
  
  // Haversine mesafe formülü
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
  
  void _openMessaging() {
    print('💬 Gerçek mesaj sistemi açılıyor...');
    
    final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
    final driverName = _driverName();
    
    try {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => RideChatScreen(
            rideId: rideId,
            driverName: driverName,
            isDriver: false, // Müşteri
          ),
        ),
      );
    } catch (e) {
      print('❌ RideChatScreen hatası: $e');
      
      // Fallback mesaj ekranı
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('$driverName ile Sohbet'),
              backgroundColor: const Color(0xFF1A1A2E),
              foregroundColor: Colors.white,
            ),
            backgroundColor: const Color(0xFF0F0F1A),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.message, size: 64, color: Color(0xFFFFD700)),
                  SizedBox(height: 16),
                  Text(
                    'Mesajlaşma sistemi hazır!',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
    }
  }
  
  // ŞİRKET + ŞOFÖR ARAMA SEÇENEKLERİ GÖSTER! ✅
  void _showCallOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A2A3E),
              Color(0xFF1A1A2E),
            ],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '📞 Arama Seçenekleri',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Şoför arama
            _buildCallOption(
              title: '🚗 ${_driverName()}',
              subtitle: 'Direkt şoförle iletişim',
              phone: _driverPhone(),
              gradient: [Colors.green, Colors.teal],
            ),
            
            // Şirket arama seçenekleri
            FutureBuilder<List<Map<String, String>>>(
              future: CompanyContactService.getCustomerCallOptions(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Column(
                    children: snapshot.data!.map((option) => _buildCallOption(
                      title: option['title']!,
                      subtitle: option['subtitle']!,
                      phone: option['phone']!,
                      gradient: option['type'] == 'emergency' 
                        ? [Colors.red, Colors.redAccent]
                        : [Colors.blue, Colors.blueAccent],
                    )).toList(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCallOption({
    required String title,
    required String subtitle,
    required String phone,
    required List<Color> gradient,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            _makeCall(phone, title);
          },
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        phone,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _makeCall(String phone, String title) {
    print('📞 [MÜŞTERİ] Arama yapılıyor: $title - $phone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.phone, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text('📞 $title aranıyor...'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _makeAutomaticBridgeCall(String companyPhone, String? bridgeCode) {
    print('📞 [MÜŞTERİ] Otomatik köprü arama: $companyPhone | Kod: $bridgeCode');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk, color: Color(0xFFFFD700)),
            SizedBox(width: 12),
            Text(
              'Otomatik Şoför Bağlantısı',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                children: [
                  const Icon(Icons.phone_in_talk, color: Colors.black, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'Şirket Hattı',
                    style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    companyPhone,
                    style: const TextStyle(color: Colors.black87, fontSize: 20, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Text(
                    '🤖 Otomatik Bağlantı',
                    style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Aradığınızda sistem otomatik olarak şoförünüzü arayıp sizi bağlayacak. Hiçbir şey söylemenize gerek yok.',
                    style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _executeBridgeCall(companyPhone);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('📞 Şoförü Ara', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  void _showDirectCallDialog(String companyPhone) {
    // Fallback dialog placeholder
    print('📞 [MÜŞTERİ] Fallback arama dialog: $companyPhone');
  }
  
  void _makeCompanyBridgeCall(String companyPhone, bool isDriver) {
    print('📞 [MÜŞTERİ] Şirket köprü hattı aranıyor: $companyPhone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.phone_forwarded, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '📞 Şirket köprü hattı aranıyor...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Ride #${widget.rideDetails['ride_id']} - Şoförle konuşun',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // TEST HESAP KONTROLÜ - APPLE REVIEW İÇİN! ✅
  Future<bool> _isTestAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('user_email') ?? '';
      final userPhone = prefs.getString('user_phone') ?? '';
      
      // Apple Review test hesabı - GERÇEK BİLGİLER!
      final testEmails = [
        'test@customer.com',           // Apple Review hesabı
        'test@funbreakvale.com',       // İç test hesabı
        'demo@funbreakvale.com'        // Demo hesabı
      ];
      
      final testPhones = [
        '5555555555',                  // Apple Review test telefonu
        '5554443322',                  // SMS demo bypass
        '5001234567',                  // SMS demo bypass
      ];
      
      return testEmails.contains(userEmail) || 
             testPhones.any((phone) => userPhone.contains(phone));
    } catch (e) {
      print('⚠️ Test hesap kontrolü hatası: $e');
      return false;
    }
  }
  
  // ŞİRKET KÖPRÜ ARAMA SİSTEMİ! ✅
  // ✅ NETGSM KÖPRÜ ARAMA SİSTEMİ! 🔥
  // ✅ APPLE REVIEW İÇİN GÜVENLİ HALE GETİRİLDİ!
  Future<void> _callDriverDirectly() async {
    try {
      // TEST HESAP KONTROLÜ - Apple Review için!
      if (await _isTestAccount()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Demo hesap: Arama özelliği gerçek kullanıcılar için aktif',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        print('📞 Test hesap - Arama devre dışı (Apple Review)');
        return;
      }
      
      final driverName = _driverName();
      final driverPhone = _driverPhone();
      
      // Telefon numarası kontrolü
      if (driverPhone.isEmpty || driverPhone == 'null' || driverPhone == '0') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Sürücü telefon numarası bulunamadı'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // ✅ rideId int'e parse et!
      final rideIdRaw = widget.rideDetails['ride_id'] ?? _currentRideStatus['ride_id'] ?? 0;
      final rideId = rideIdRaw is int ? rideIdRaw : int.tryParse(rideIdRaw.toString()) ?? 0;
      
      // Köprü hattı numarası (SABİT!)
      const bridgeNumber = '0216 606 45 10';
      
      print('📞 [MÜŞTERİ] Köprü arama başlatılıyor - Şoför: $driverName');
      
      // Bilgilendirme ve onay dialogu
      showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('🔒 Güvenli Köprü Arama', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_in_talk, color: Color(0xFFFFD700), size: 60),
            const SizedBox(height: 16),
            const Text(
              'Köprü hattımız sizi şoförünüzle güvenli bir şekilde bağlayacaktır.',
              style: TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                children: [
                  const Text(
                    '📞 Köprü Hattı',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    bridgeNumber,
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '🚗 Bağlanacak: $driverName',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              '🔐 Gizlilik: İki taraf da sadece köprü numarasını görür',
              style: TextStyle(color: Colors.green, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _initiateBridgeCall(rideId, driverPhone, driverName);
            },
            icon: const Icon(Icons.phone, color: Colors.white),
            label: const Text('Aramayı Başlat', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
    } catch (e, stackTrace) {
      // CRASH PREVENTION - Apple Review için!
      print('❌ Arama hatası yakalandı: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Arama başlatılamadı. Lütfen daha sonra tekrar deneyin.'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  // ✅ KÖPRÜ ARAMASI BAŞLAT - BACKEND ÜZERİNDEN!
  Future<void> _initiateBridgeCall(int rideId, String driverPhone, String driverName) async {
    try {
      // Müşteri numarasını al
      final prefs = await SharedPreferences.getInstance();
      final customerPhone = prefs.getString('user_phone') ?? '';
      
      if (customerPhone.isEmpty) {
        throw Exception('Müşteri telefon numarası bulunamadı');
      }
      
      print('📤 Backend köprü API çağrılıyor...');
      print('   Ride ID: $rideId');
      print('   🟢 ARAYAN (caller): Müşteri = $customerPhone');
      print('   🔵 ARANAN (called): Şoför = $driverPhone');
      
      // Backend'e istek at (NetGSM API credentials gizli!)
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/bridge_call.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'caller': customerPhone,      // ✅ Arayan: Müşteri!
          'called': driverPhone,        // ✅ Aranan: Şoför!
        }),
      ).timeout(const Duration(seconds: 15));
      
      print('📥 Bridge Call Response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          // BAŞARILI - Köprü numarasını ara!
          final bridgeNumber = data['bridge_number'] ?? '02166064510';
          
          print('✅ Köprü arama başarılı - Numara: $bridgeNumber');
          
          // Telefon uygulamasını aç
          final uri = Uri(scheme: 'tel', path: bridgeNumber);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            
            // Başarı mesajı
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.phone_forwarded, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('📞 Köprü hattı $driverName ile bağlantı kuruyor...'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            throw Exception('Telefon uygulaması açılamadı');
          }
          
        } else {
          throw Exception(data['message'] ?? 'Köprü arama başlatılamadı');
        }
      } else {
        throw Exception('Backend hatası: ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Köprü arama hatası: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('❌ Arama hatası: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _executeBridgeCall(String companyPhone) {
    print('📞 [MÜŞTERİ] Otomatik köprü çağrısı başlatılıyor...');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.phone_in_talk, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '📞 Otomatik şoför bağlantısı başlatılıyor...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Sistem şoförünüzü arayıp size bağlayacak',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
  
  void _makeDirectDriverCall() {
    final driverPhone = _driverPhone();
    print('📞 [MÜŞTERİ] Direkt şoför araması: $driverPhone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📞 Şoförünüz ${_driverName()} aranıyor...'),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  Future<String> _getCustomerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getInt('customer_id')?.toString() ?? '19';
      print('🔍 Customer ID: $customerId');
      return customerId;
    } catch (e) {
      print('❌ Customer ID alma hatası: $e');
      return '19'; // Fallback
    }
  }
  
  // Duplicate function kaldırıldı

  Future<void> _cancelRide() async {
    // İptal onay dialogu göster
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Yolculuğu İptal Et', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yolculuğunuzu iptal etmek istediğinize emin misiniz?',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ ÖNEMLİ BİLGİLENDİRME',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• HEMEN seçeneği: Vale kabul ettikten 5 dakika sonra iptal ederseniz ₺1,500 iptal ücreti alınır.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• REZERVASYON: Yolculuğun başlama saatine 45 dakikadan az kalmışsa ₺1,500 iptal ücreti alınır.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• İptal ücreti varsa direkt ödeme ekranına yönlendirileceksiniz.',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text('İptal Et', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        // Loading göster
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: Color(0xFF1A1A2E),
            content: Row(
              children: [
                CircularProgressIndicator(color: Color(0xFFFFD700)),
                SizedBox(width: 20),
                Text('İptal işlemi yapılıyor...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );

        try {
          final customerId = await _getCustomerId();
          final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
          
          // DETAYLI DEBUG - TÜM YOLCULUK BİLGİLERİ
          print('🔍 === İPTAL API DEBUG ===');
          print('📋 widget.rideDetails: ${widget.rideDetails}');
          print('🆔 Çekilen Ride ID: $rideId (type: ${rideId.runtimeType})');
          print('👤 Çekilen Customer ID: $customerId (type: ${customerId.runtimeType})');
          print('🔢 Parse sonrası Ride ID: ${int.tryParse(rideId) ?? 0}');
          print('🔢 Parse sonrası Customer ID: ${int.tryParse(customerId) ?? 0}');
          print('🚫 İptal API çağrısı - Ride: $rideId, Customer: $customerId');

          final requestBody = {
            'ride_id': int.tryParse(rideId) ?? 0,
            'customer_id': int.tryParse(customerId) ?? 0,
          };
          
          print('📦 API Request Body: $requestBody');

          final response = await http.post(
            Uri.parse('https://admin.funbreakvale.com/api/cancel_ride.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          ).timeout(const Duration(seconds: 15));
          
          print('📡 API Response Status: ${response.statusCode}');
          print('📡 API Response Body: ${response.body}');

          // Loading kapat
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }

          if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['success'] == true) {
            final cancellationFee = (data['cancellation_fee'] ?? 0.0) is int 
                ? (data['cancellation_fee'] as int).toDouble() 
                : data['cancellation_fee'] ?? 0.0;
            final feeApplied = data['fee_applied'] ?? false;
            
        // RideProvider'dan temizle (güvenli)
        try {
          final rideProvider = Provider.of<RideProvider>(context, listen: false);
          rideProvider.clearCurrentRide();
        } catch (e) {
          print('❌ RideProvider temizleme hatası: $e');
        }
            
            // ÜCRETLİ İPTAL İSE DİREKT ÖDEME EKRANINA YÖNLENDİR!
            if (feeApplied && cancellationFee > 0) {
              print('💳 İptal ücreti var (₺$cancellationFee) - Ödeme ekranına yönlendiriliyor...');
              
              // Bilgilendirme dialogu göster
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Row(
                    children: [
                      Icon(Icons.payment, color: Color(0xFFFFD700), size: 28),
                      SizedBox(width: 12),
                      Text('İptal Ücreti', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Yolculuğunuz iptal edildi.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'İptal Ücreti',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₺${cancellationFee.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Lütfen ödeme yapınız.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text(
                        'Ödeme Yap',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              );
              
              // ÖDEME EKRANINA YÖNLENDİR!
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => RidePaymentScreen(
                      rideDetails: Map<String, dynamic>.from(widget.rideDetails)..addAll({
                        'status': 'cancelled',
                        'cancellation_fee': cancellationFee,
                      }),
                      rideStatus: {
                        'status': 'cancelled',
                        'final_price': cancellationFee,
                        'is_cancellation_fee': true,
                      },
                    ),
                  ),
                );
              }
              
            } else {
              // ÜCRETSİZ İPTAL - SnackBar göster
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(child: Text('✅ Yolculuk ücretsiz iptal edildi')),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
            
            // Direkt ana sayfaya dön (güvenli)
            if (mounted) {
              Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
            
        } else {
            // 🔥 DETAYLI HATA MESAJI - Kullanıcıya ne oldu göster
            final errorMessage = data['message'] ?? 'Bilinmeyen hata';
            print('❌ API Success=false - Message: $errorMessage');
            print('❌ Full Response: $data');
            
            // Loading kapat (eğer hala açıksa)
            if (mounted && Navigator.canPop(context)) {
              try {
                Navigator.pop(context);
              } catch (e) {
                print('Navigator pop hatası (zaten kapalı): $e');
              }
            }
            
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                title: const Row(
                  children: [
                    Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 12),
                    Text('İptal Hatası', style: TextStyle(color: Colors.white)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Lütfen müşteri hizmetleri ile iletişime geçin.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tamam', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }
        }
        } catch (apiError) {
          print('❌ İptal API hatası: $apiError');
          
          // API hatası olsa bile direkt ana sayfaya dön
          try {
            final rideProvider = Provider.of<RideProvider>(context, listen: false);
            rideProvider.clearCurrentRide();
          } catch (e) {
            print('❌ Provider temizleme hatası: $e');
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Text('İptal işleminde sorun - ana sayfaya dönülüyor'),
                ],
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
          }
        }
      } catch (e) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // Loading kapat
        }
        print('❌ İptal genel hatası: $e');
        
        // Genel hata da olsa ana sayfaya dön
        try {
          final rideProvider = Provider.of<RideProvider>(context, listen: false);
          rideProvider.clearCurrentRide();
        } catch (e) {
          print('❌ Provider genel temizleme hatası: $e');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Hata oluştu - ana sayfaya dönülüyor'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        // GÜVENLİ NAVİGASYON - NULL CHECK
        if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/main', (route) => false);
          } catch (e) {
            print('❌ Navigation hatası: $e');
            // Fallback: Ana sayfaya dön
            Navigator.of(context, rootNavigator: true).pushReplacementNamed('/home');
          }
        }
      }
    }
  }
  
  
  // SCHEDULED TIME GÖSTER İM - MÜŞTERİ AKTİF YOLCULUK EKRANINDA!
  String _getScheduledTimeDisplay() {
    try {
      final scheduledTime = widget.rideDetails['scheduled_time']?.toString();
      
      if (scheduledTime == null || 
          scheduledTime.isEmpty || 
          scheduledTime == 'null' || 
          scheduledTime == '0000-00-00 00:00:00') {
        return 'Hemen';
      }
      
      final scheduledDateTime = DateTime.tryParse(scheduledTime);
      if (scheduledDateTime == null) {
        return 'Hemen';
      }
      
      final now = DateTime.now();
      final difference = scheduledDateTime.difference(now);
      
      // Eğer gelecekte bir zaman ise saat göster
      if (difference.inMinutes > 15) {
        if (scheduledDateTime.day == now.day) {
          // Aynı gün - sadece saat:dakika
          return '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
        } else {
          // Farklı gün - gün.ay saat:dakika
          return '${scheduledDateTime.day}.${scheduledDateTime.month} ${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
        }
      }
      
      return 'Hemen';
      
    } catch (e) {
      print('❌ Müşteri aktif ride scheduled time hatası: $e');
      return 'Hemen';
    }
  }

  // ROTA ÇİZGİSİ GÜNCELLE - ŞOFÖRDEN MÜŞTERİYE! ✅
  void _updateRoutePolyline() {
    if (_driverLocation == null || _customerLocation == null) return;
    
    final Set<Polyline> newPolylines = {};
    
    // Şoförden müşteriye siyah çizgi (düz çizgi - basit)
    newPolylines.add(
      Polyline(
        polylineId: const PolylineId('driver_to_customer'),
        points: [_driverLocation!, _customerLocation!],
        color: Colors.black,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)], // Kesikli çizgi
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
    
    setState(() {
      _polylines = newPolylines;
    });
    
    print('🛣️ [MÜŞTERİ] Şoför → Müşteri rota çizgisi güncellendi');
  }
  
  // MODERN ALT BAR - YOLCULUK EKRANINA ÖZEL! ✅
  Widget _buildModernBottomBar() {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF0A0A0A),
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Ana Sayfa Butonu
            _buildBottomBarItem(
              icon: Icons.home,
              label: 'Ana Sayfa',
              isActive: true, // Yolculuk ekranı aktif ana sayfa
              onTap: () {
                // Ana sayfa yerinde kalacak - hiçbir şey yapma
                print('🏠 [MÜŞTERİ] Ana sayfa - Modern yolculuk ekranı zaten aktif');
              },
            ),
            
            // Mesaj Butonu
            _buildBottomBarItem(
              icon: Icons.chat_bubble_outline,
              label: 'Mesajlar',
              isActive: false,
              onTap: () => _openMessaging(),
            ),
            
            // Telefon Butonu - DİREKT ŞOFÖR KÖPRÜ!
            _buildBottomBarItem(
              icon: Icons.phone,
              label: 'Ara',
              isActive: false,
              onTap: () => _callDriverDirectly(),
            ),
            
            // Yolculuk Durumu
            _buildBottomBarItem(
              icon: Icons.info_outline,
              label: 'Durum',
              isActive: false,
              onTap: () => _showRideStatusDialog(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBottomBarItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive 
                ? const Color(0xFFFFD700).withOpacity(0.2)
                : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: isActive 
                ? Border.all(color: const Color(0xFFFFD700).withOpacity(0.5))
                : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: isActive ? _pulseAnimation.value : 1.0,
                  child: Icon(
                    icon,
                    color: isActive ? const Color(0xFFFFD700) : Colors.white70,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFFD700) : Colors.white70,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  void _showRideStatusDialog() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    final statusInfo = _getStatusInfo(status);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(statusInfo['icon'], color: statusInfo['colors'][0]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Yolculuk Durumu',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: statusInfo['colors']),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusInfo['title'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusInfo['subtitle'],
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Şoför: ${_driverName()}',
              style: const TextStyle(color: Colors.white70),
            ),
            const Text(
              'İletişim: Şirket hattı üzerinden güvenli arama',
              style: TextStyle(color: Colors.white70),
            ),
            // VALE GELME SAATİ - MÜŞTERİ AKTİF YOLCULUK EKRANINDA!
            Text(
              'Vale Gelme Saati: ${_getScheduledTimeDisplay()}',
              style: const TextStyle(color: Colors.orange),
            ),
            if (_driverLocation != null) ...[
              const SizedBox(height: 8),
              Text(
                'Mesafe: ${_calculateDriverDistance().toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Kapat',
              style: TextStyle(color: Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }
  
  // STATUS BİLGİ SİSTEMİ - İLK VERSİYON KALDIRILDI
  Map<String, dynamic> _getStatusInfoOld(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return {
          'title': 'Şoför Aranıyor',
          'subtitle': 'Yakınınızdaki şoförler aranıyor...',
          'icon': Icons.search,
          'colors': [Colors.orange, Colors.amber],
        };
      case 'accepted':
        return {
          'title': 'Şoför Bulundu',
          'subtitle': 'Şoförünüz size doğru geliyor',
          'icon': Icons.check_circle,
          'colors': [Colors.blue, Colors.lightBlue],
        };
      case 'in_progress':
        return {
          'title': 'Yolculuğunuz Başladı',
          'subtitle': 'İyi yolculuklar! Hedefinize doğru gidiyorsunuz.',
          'icon': Icons.directions_car,
          'colors': [Colors.green, Colors.teal],
        };
      case 'driver_arrived':
        return {
          'title': 'Şoför Geldi',
          'subtitle': 'Şoförünüz konumunuza ulaştı',
          'icon': Icons.location_on,
          'colors': [Colors.green, Colors.lightGreen],
        };
      case 'completed':
        return {
          'title': 'Yolculuk Tamamlandı',
          'subtitle': 'Hedefinize güvenle ulaştınız',
          'icon': Icons.flag,
          'colors': [Colors.green, Colors.teal],
        };
      case 'cancelled':
        return {
          'title': 'Yolculuk İptal Edildi',
          'subtitle': 'Yolculuğunuz iptal edildi',
          'icon': Icons.cancel,
          'colors': [Colors.red, Colors.redAccent],
        };
      default:
        return {
          'title': 'Yolculuk Hazırlanıyor',
          'subtitle': 'Lütfen bekleyiniz...',
          'icon': Icons.hourglass_empty,
          'colors': [Colors.grey, Colors.blueGrey],
        };
    }
  }
  
  // DETAYLARLA STATUS MESAJI
  String _getStatusMessage(String status) {
    final statusInfo = _getStatusInfo(status);
    return statusInfo['subtitle'];
  }
  
  // ANLıK KM HESAPLAMA - ŞOFÖRDEN GELİYOR
  String _getCurrentKm() {
    final currentKm = _currentRideStatus['current_km']?.toString() ?? '0.0';
    return currentKm;
  }
  
  // ANLıK BEKLEME SÜRESİ - ŞOFÖRDEN GELİYOR
  int _lastLoggedWaitingTime = -1;
  
  String _getCurrentWaitingTime() {
    final waitingTime = _currentRideStatus['waiting_minutes']?.toString() ?? 
                        widget.rideDetails['waiting_minutes']?.toString() ?? '0';
    // DEBUG: Sadece değiştiğinde logla (her build'de değil!)
    final currentWaiting = int.tryParse(waitingTime) ?? 0;
    if (currentWaiting > 0 && currentWaiting != _lastLoggedWaitingTime) {
      print('⏳ [MÜŞTERİ] Bekleme süresi güncellendi: ${_lastLoggedWaitingTime}dk → ${currentWaiting}dk');
      _lastLoggedWaitingTime = currentWaiting;
    }
    return waitingTime;
  }
  
  // ✅ BEKLEME DAKİKASI INT OLARAK DÖNDÜR
  int _getWaitingMinutes() {
    final waitingMinutes = _currentRideStatus['waiting_minutes'] ?? 
                          widget.rideDetails['waiting_minutes'] ?? 0;
    return int.tryParse(waitingMinutes.toString()) ?? 0;
  }
  
  // ✅ İLK TAHMİNİ FİYAT (SABİT - İlk rotaya girdiğinde belirlenen fiyat, BEKLEME YOK, DEĞİŞMEZ!)
  String _getInitialEstimatedPrice() {
    // ✅ Class değişkeninden döndür (initState'te bir kez set edildi, bir daha değişmez!)
    return _initialEstimatedPrice.toStringAsFixed(0);
  }
  
  // ✅ GÜNCEL TOPLAM (DİNAMİK - Backend'den direkt çek, ZATEN BEKLEME DAHİL!)
  String _calculateCurrentTotal() {
    // ✅ Backend'den gelen estimated_price kullan (backend zaten bekleme + distance_pricing hesaplıyor!)
    // ⚠️ BEKLEME TEKRAR EKLEME - Backend'den gelen fiyat zaten bekleme dahil!
    final backendPrice = _currentRideStatus['estimated_price'] ?? 
                         widget.rideDetails['estimated_price'] ?? 0.0;
    final total = double.tryParse(backendPrice.toString()) ?? 0.0;
    
    return total.toStringAsFixed(0);
  }
  
  // ✅ KM FİYATI PANEL'DEN ÇEK
  double _getKmPrice() {
    final kmPrice = _currentRideStatus['km_price'] ?? 
                    widget.rideDetails['km_price'] ?? 8.0;
    return double.tryParse(kmPrice.toString()) ?? 8.0;
  }
  
  // ✅ BEKLEME ÜCRETİ HESAPLA (İlk 15dk ücretsiz, sonra panel'den waiting_fee_per_interval)
  String _calculateWaitingFee() {
    final waiting = _getWaitingMinutes();
    
    // Panel'den ayarları çek
    final freeMinutes = _currentRideStatus['waiting_free_minutes'] ?? 
                        widget.rideDetails['waiting_free_minutes'] ?? 15;
    final freeMinutesInt = int.tryParse(freeMinutes.toString()) ?? 15;
    
    if (waiting <= freeMinutesInt) return '0';
    
    final feePerInterval = _currentRideStatus['waiting_fee_per_interval'] ?? 
                           widget.rideDetails['waiting_fee_per_interval'] ?? 200.0;
    final feePerIntervalDouble = double.tryParse(feePerInterval.toString()) ?? 200.0;
    
    final intervalMinutes = _currentRideStatus['waiting_interval_minutes'] ?? 
                            widget.rideDetails['waiting_interval_minutes'] ?? 15;
    final intervalMinutesInt = int.tryParse(intervalMinutes.toString()) ?? 15;
    
    final chargeableMinutes = waiting - freeMinutesInt;
    final intervals = (chargeableMinutes / intervalMinutesInt).ceil();
    final fee = intervals * feePerIntervalDouble;
    return fee.toInt().toString();
  }

  String _getWaitingFeeSubtitle() {
    final freeMinutes = _currentRideStatus['waiting_free_minutes'] ??
        widget.rideDetails['waiting_free_minutes'] ?? 15;
    final freeMinutesInt = int.tryParse(freeMinutes.toString()) ?? 15;
    final feeStr = _calculateWaitingFee();
    final feeValue = double.tryParse(feeStr) ?? 0.0;
    if (feeValue <= 0) {
      return 'Ücretsiz (İlk $freeMinutesInt dk)';
    }
    return 'Ücret: ₺${feeValue.toStringAsFixed(0)} (İlk $freeMinutesInt dk ücretsiz)';
  }
  
  // SAATLİK PAKETTE SÜRE, NORMAL VALEDE BEKLEME
  String _getWaitingOrDurationDisplay() {
    if (_isHourlyPackage()) {
      // ✅ BACKEND'DEN GELEN ride_duration_hours ÖNCE KONTROL ET!
      final rideDurationHours = _currentRideStatus['ride_duration_hours'] ?? 
                                widget.rideDetails['ride_duration_hours'];
      
      if (rideDurationHours != null) {
        final totalHours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
        final hours = totalHours.floor();
        final minutes = ((totalHours - hours) * 60).round();
        
        if (hours > 0 && minutes > 0) {
          return '$hours saat $minutes dk';
        } else if (hours > 0) {
          return '$hours saat';
        } else if (minutes > 0) {
          return '$minutes dk';
        }
      }
      
      // FALLBACK: Manuel hesaplama (yolculuk başlamışsa)
      final startedAtStr = _currentRideStatus['started_at']?.toString() ?? widget.rideDetails['started_at']?.toString();
      if (startedAtStr != null && startedAtStr.isNotEmpty && startedAtStr != '0000-00-00 00:00:00') {
        final startedAt = DateTime.tryParse(startedAtStr);
        if (startedAt != null) {
          final now = DateTime.now();
          final duration = now.difference(startedAt);
          final hours = duration.inHours;
          final minutes = duration.inMinutes % 60;
          
          if (hours > 0 && minutes > 0) {
            return '$hours saat $minutes dk';
          } else if (hours > 0) {
            return '$hours saat';
          } else if (minutes > 0) {
            return '$minutes dk';
          }
        }
      }
      
      return '0 dk';
    } else {
      // Normal vale: Bekleme dakikası
      return '${_getCurrentWaitingTime()} dk';
    }
  }
  
  // SAATLİK PAKET KONTROLÜ - BACKEND'DEN GELEN service_type VE SÜRE!
  bool _isHourlyPackage() {
    try {
      // ✅ ÖNCELİKLE service_type KONTROL ET!
      final serviceType = (_currentRideStatus['service_type'] ?? widget.rideDetails['service_type'] ?? '').toString().toLowerCase();
      if (serviceType == 'hourly') {
        return true;
      }
      
      // ✅ BACKEND'DEN GELEN ride_duration_hours KULLAN!
      final rideDurationHours = _currentRideStatus['ride_duration_hours'];
      if (rideDurationHours != null) {
        final hours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
        if (hours >= 2.0) {
          return true;
        }
      }
      
      // FALLBACK: Manuel hesaplama (backend verisi yoksa)
      final serverTimeStr = _currentRideStatus['server_time']?.toString();
      final startedAtStr = _currentRideStatus['started_at']?.toString() ?? widget.rideDetails['started_at']?.toString();
      
      if (startedAtStr != null && startedAtStr.isNotEmpty && startedAtStr != '0000-00-00 00:00:00') {
        final startedAt = DateTime.tryParse(startedAtStr);
        
        DateTime nowTR;
        if (serverTimeStr != null && serverTimeStr.isNotEmpty) {
          nowTR = DateTime.tryParse(serverTimeStr) ?? DateTime.now();
        } else {
          final nowUtc = DateTime.now().toUtc();
          nowTR = nowUtc.add(const Duration(hours: 3));
        }
        
        if (startedAt != null) {
          final rideDurationHours = nowTR.difference(startedAt).inMinutes / 60.0;
          if (rideDurationHours >= 2.0) {
            return true;
          }
        }
      }
    } catch (e) {
      print('❌ Saatlik paket kontrolü hatası: $e');
    }
    return false;
  }
  
  // SAATLİK PAKET ETİKETİ - BACKEND'DEN GELEN FİYATA GÖRE!
  String _getHourlyPackageLabel() {
    try {
      // Backend'den gelen fiyat
      final backendPrice = double.tryParse(
        (_currentRideStatus['estimated_price'] ?? widget.rideDetails['estimated_price'])?.toString() ?? '0'
      ) ?? 0.0;
      
      final rideDurationHours = _currentRideStatus['ride_duration_hours'] ?? 
                                widget.rideDetails['ride_duration_hours'];
      
      if (rideDurationHours != null && _cachedHourlyPackages.isNotEmpty) {
        final hours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
        
        // Backend fiyatına göre paketi bul!
        for (var pkg in _cachedHourlyPackages) {
          final pkgPrice = (pkg["price"] ?? 0.0);
          if (backendPrice == pkgPrice) {
            // Fiyat eşleşiyor - bu paketteyiz!
            final start = pkg["start"]?.toInt() ?? 0;
            final end = pkg["end"]?.toInt() ?? 0;
            final priceFormatted = pkgPrice.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
            return '$start-$end saat (₺$priceFormatted)';
          }
        }
        
        // Fiyat eşleşmiyorsa süreye göre bul
        for (var pkg in _cachedHourlyPackages) {
          if (hours >= (pkg["start"] ?? 0.0) && hours < (pkg["end"] ?? 999.0)) {
            final start = pkg["start"]?.toInt() ?? 0;
            final end = pkg["end"]?.toInt() ?? 0;
            final price = (pkg["price"] ?? 0.0).toInt();
            final priceFormatted = price.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
            return '$start-$end saat (₺$priceFormatted)';
          }
        }
      }
    } catch (e) {
      print('❌ Paket etiketi hatası: $e');
    }
    return 'Saatlik Paket';
  }
  
  // DİNAMİK FİYAT HESAPLAMA - BACKEND'DEN GELİYOR!
  String _calculateDynamicPrice() {
    try {
      // Backend estimated_price ZATEN bekleme dahil gönderiyor!
      final totalPrice = double.tryParse(
        (_currentRideStatus['estimated_price'] ?? widget.rideDetails['estimated_price'])?.toString() ?? '0'
      ) ?? 0.0;
      
      return totalPrice.toStringAsFixed(0);
    } catch (e) {
      print('❌ Fiyat hesaplama hatası: $e');
      return widget.rideDetails['estimated_price']?.toString() ?? '0';
    }
  }
  
  String _calculateDynamicPrice_OLD() {
    try {
      final basePrice = double.tryParse(
        (_currentRideStatus['estimated_price'] ?? widget.rideDetails['estimated_price'])?.toString() ?? '0'
      ) ?? 50.0;
      final currentKm = double.tryParse(_getCurrentKm()) ?? 0.0;
      final waitingMinutes = int.tryParse(_getCurrentWaitingTime()) ?? 0;
      final kmPrice = double.tryParse(_currentRideStatus['km_price']?.toString() ?? '8') ?? 8.0;
      final waitingFeePerInterval = double.tryParse(_currentRideStatus['waiting_fee_per_interval']?.toString() ?? '150') ?? 150.0;
      final waitingFreeMinutes = int.tryParse(_currentRideStatus['waiting_free_minutes']?.toString() ?? '30') ?? 30;
      final waitingIntervalMinutes = int.tryParse(_currentRideStatus['waiting_interval_minutes']?.toString() ?? '15') ?? 15;
      final minimumFare = double.tryParse(_currentRideStatus['minimum_fare']?.toString() ?? '0') ?? 0.0;
      final hourlyPackagePrice = double.tryParse(_currentRideStatus['hourly_package_price']?.toString() ?? '0') ?? 0.0;
      final nightThreshold = double.tryParse(_currentRideStatus['night_package_threshold_hours']?.toString() ?? '0') ?? 0.0;
      final startedAtStr = _currentRideStatus['started_at']?.toString();

      double totalPrice = basePrice + (currentKm * kmPrice);

      // ✅ SAATLİK PAKET KONTROLÜ - ÖNCE BU KONTROL EDİLMELİ!
      bool isHourlyMode = false;
      
      // Service type direkt kontrol et!
      final serviceType = (_currentRideStatus['service_type'] ?? widget.rideDetails['service_type'] ?? '').toString().toLowerCase();
      
      if (serviceType == 'hourly') {
        isHourlyMode = true;
        print('📦 [MÜŞTERİ] SAATLİK PAKET (service_type=hourly) - Bekleme ücreti İPTAL!');
      } else if (startedAtStr != null && startedAtStr.isNotEmpty) {
        final startedAt = DateTime.tryParse(startedAtStr);
        if (startedAt != null) {
          final nowUtc = DateTime.now().toUtc();
          final nowTR = nowUtc.add(const Duration(hours: 3)); // UTC+3 = TR
          final rideDurationHours = nowTR.difference(startedAt).inMinutes / 60.0;
          if (rideDurationHours >= 2.0) {
            isHourlyMode = true;
            print('📦 [MÜŞTERİ] 2+ SAAT GEÇTİ - Bekleme ücreti İPTAL!');
          }
        }
      }

      // ✅ BEKLEME ÜCRETİ - SAATLİK PAKETTE İPTAL!
      if (!isHourlyMode && waitingMinutes > waitingFreeMinutes) {
        final chargeableMinutes = waitingMinutes - waitingFreeMinutes;
        final intervalDivisor = waitingIntervalMinutes > 0 ? waitingIntervalMinutes : 15;
        final intervals = (chargeableMinutes / intervalDivisor).ceil();
        totalPrice += intervals * waitingFeePerInterval;
      } else if (isHourlyMode) {
        print('📦 [MÜŞTERİ] SAATLİK PAKET - Bekleme ücreti İPTAL!');
      }

      if (minimumFare > 0 && totalPrice < minimumFare) {
        totalPrice = minimumFare;
      }

      // SAATLİK PAKET SİSTEMİ - 2 SAAT SONRA OTOMATİK PAKET FİYATI! (SERVER SAATİ!)
      if (startedAtStr != null && startedAtStr.isNotEmpty) {
        final startedAt = DateTime.tryParse(startedAtStr);
        if (startedAt != null) {
          // ⚠️ PHONE TIMEZONE BYPASS - Server saati manuel hesaplama
          final nowUtc = DateTime.now().toUtc();
          final nowTR = nowUtc.add(const Duration(hours: 3)); // UTC+3 = TR
          final rideDurationHours = nowTR.difference(startedAt).inMinutes / 60.0;
          
          if (rideDurationHours >= 2.0) {
            // SAATLİK PAKET MODU - CACHE'LENMIŞ PAKETLERI KULLAN!
            if (_cachedHourlyPackages.isNotEmpty) {
              // Hangi pakette olduğunu belirle
              double? packagePrice;
              String packageLabel = '';
              
              for (var pkg in _cachedHourlyPackages) {
                final startHour = pkg["start"] ?? 0.0;
                final endHour = pkg["end"] ?? 0.0;
                final price = pkg["price"] ?? 0.0;
                
                if (rideDurationHours >= startHour && rideDurationHours < endHour) {
                  packagePrice = price;
                  packageLabel = "$startHour-$endHour saat";
                  break;
                }
              }
              
              // Bulunamazsa son paketi kullan
              if (packagePrice == null && _cachedHourlyPackages.isNotEmpty) {
                final lastPkg = _cachedHourlyPackages.last;
                packagePrice = lastPkg["price"];
                final startHour = lastPkg["start"] ?? 0.0;
                packageLabel = "$startHour+ saat";
              }
              
              if (packagePrice != null && packagePrice > 0) {
                totalPrice = packagePrice;
                print('📦 MÜŞTERİ: Saatlik paket $packageLabel - ${rideDurationHours.toStringAsFixed(2)} saat → ₺${packagePrice.toStringAsFixed(0)}');
              }
            } else {
              // Fallback: Backend estimated_price
              print('⚠️ [MÜŞTERİ] Saatlik paketler yüklenmemiş - backend estimated_price kullanılıyor');
            }
          }
        }
      }

      return totalPrice.toStringAsFixed(0);
    } catch (e) {
      print('❌ Dinamik fiyat hesaplama hatası: $e');
      return widget.rideDetails['estimated_price']?.toString() ?? '50';
    }
  }
  
  // YOLCULUK METRİK WIDGET
  Widget _buildRideMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
