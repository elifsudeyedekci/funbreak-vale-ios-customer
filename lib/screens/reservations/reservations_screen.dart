import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/theme_provider.dart';
import '../../providers/admin_api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride.dart';
import '../ride/ride_payment_screen.dart';

class ReservationsScreen extends StatefulWidget {
  final int initialTabIndex;
  final int? pendingRideId; // 🔥 Borçlu yolculuk ID - otomatik ödeme ekranına yönlendir
  const ReservationsScreen({Key? key, this.initialTabIndex = 0, this.pendingRideId}) : super(key: key);
  
  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  List<Map<String, dynamic>> _pastRides = [];
  List<Map<String, dynamic>> _activeRides = [];
  bool _isLoading = false;
  bool _isLoadingActive = false;
  
  @override
  void initState() {
    super.initState();
    _loadPastRides();
    _loadActiveRides();
  }
  
  // 🔥 Borçlu yolculuğu bul ve ödeme ekranına yönlendir
  void _navigateToPendingRidePayment() {
    if (widget.pendingRideId == null) return;
    
    // Geçmiş yolculuklarda borçlu yolculuğu bul
    final pendingRide = _pastRides.firstWhere(
      (ride) => ride['id']?.toString() == widget.pendingRideId.toString(),
      orElse: () => {},
    );
    
    if (pendingRide.isNotEmpty) {
      // Ödeme ekranına yönlendir
      _navigateToPaymentScreen(pendingRide);
    }
  }
  
  Future<void> _loadPastRides() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('admin_user_id') ?? prefs.getString('user_id') ?? '0';
      
      print('📊 GEÇMİŞ YOLCULUKLAR: Customer ID = $customerId');
      
      if (customerId != '0') {
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/get_customer_past_rides.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customer_id': customerId,
            'include_pending': true,
            'include_scheduled': true,
            'include_completed': true,
            'include_details': true,
          }),
        ).timeout(const Duration(seconds: 5)); // ✅ 5 saniye timeout!
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('📱 GEÇMİŞ RIDES API RESPONSE: ${response.body}');
          if (data['success'] == true) {
        if (mounted) {
          setState(() {
            _pastRides = List<Map<String, dynamic>>.from(data['rides'] ?? []);
          });
        }
            print('✅ Geçmiş yolculuk sayısı: ${_pastRides.length}');
          } else {
            print('⚠️ Geçmiş rides API başarısız: ${data['message']}');
          }
        } else {
          print('❌ Geçmiş rides API hatası: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('❌ Geçmiş yolculuklar yükleme hatası: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // 🔥 Borçlu yolculuk varsa ödeme ekranına yönlendir
        if (widget.pendingRideId != null && _pastRides.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToPendingRidePayment();
          });
        }
      }
    }
  }
  
  Future<void> _loadActiveRides() async {
    setState(() {
      _isLoadingActive = true;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;
      
      if (customerId != null) {
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/get_customer_active_rides.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'customer_id': customerId,
          }),
        ).timeout(const Duration(seconds: 5)); // ✅ 5 saniye timeout!
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('📱 AKTİF RIDES API RESPONSE: ${response.body}');
          if (data['success'] == true) {
            if (mounted) {
              setState(() {
                _activeRides = List<Map<String, dynamic>>.from(data['active_rides'] ?? []);
              });
            }
            print('✅ Aktif yolculuk sayısı: ${_activeRides.length}');
            
            // Aktif yolculuk varsa RideProvider'a kaydet (persistence için)
            if (_activeRides.isNotEmpty) {
              final rideProvider = Provider.of<RideProvider>(context, listen: false);
              final firstActiveRide = _activeRides.first;
              
              // Sadece pending, accepted, in_progress durumlarında kaydet
              if (['pending', 'accepted', 'in_progress'].contains(firstActiveRide['status'])) {
                print('💾 Aktif yolculuk RideProvider\'a kaydediliyor...');
                rideProvider.setCurrentRide(
                  Ride(
                    id: firstActiveRide['id'].toString(),
                    customerId: customerId.toString(),
                    driverId: firstActiveRide['driver_id']?.toString(),
                    pickupLocation: LatLng(
                      firstActiveRide['pickup_lat']?.toDouble() ?? 0.0,
                      firstActiveRide['pickup_lng']?.toDouble() ?? 0.0,
                    ),
                    destinationLocation: LatLng(
                      firstActiveRide['destination_lat']?.toDouble() ?? 0.0,
                      firstActiveRide['destination_lng']?.toDouble() ?? 0.0,
                    ),
                    pickupAddress: firstActiveRide['pickup_address'] ?? '',
                    destinationAddress: firstActiveRide['destination_address'] ?? '',
                    paymentMethod: 'card',
                    estimatedPrice: firstActiveRide['estimated_price']?.toDouble() ?? 0.0,
                    estimatedTime: 30,
                    status: firstActiveRide['status'] ?? 'pending',
                    createdAt: DateTime.tryParse(firstActiveRide['created_at'] ?? '') ?? DateTime.now(),
                  ),
                );
              }
            }
          } else {
            print('⚠️ Aktif rides API başarısız: ${data['message']}');
          }
        } else {
          print('❌ Aktif rides API hatası: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('❌ Aktif yolculuklar yükleme hatası: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingActive = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final int initialIndex = widget.initialTabIndex < 0
        ? 0
        : (widget.initialTabIndex > 1 ? 1 : widget.initialTabIndex);
    
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
        appBar: AppBar(
          automaticallyImplyLeading: false, // ✅ GERİ BUTONU KALDIRILDI!
          title: const Text('Rezervasyonlar'),
          backgroundColor: const Color(0xFFFFD700),
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: Colors.black,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Aktif'),
              Tab(text: 'Geçmiş'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Aktif Tab - AKTİF YOLCULUKLAR
            _buildActiveRidesTab(themeProvider),
            // Geçmiş Tab - DETAYLI GEÇMİŞ YOLCULUKLAR
            _buildPastRidesTab(themeProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRidesTab(ThemeProvider themeProvider) {
    if (_isLoadingActive) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
        ),
      );
    }
    
    if (_activeRides.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 64,
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'Aktif Yolculuk Yok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Şu anda devam eden yolculuğunuz bulunmuyor',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        await _loadActiveRides();
        await _loadPastRides();
      },
      color: const Color(0xFFFFD700),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeRides.length,
        itemBuilder: (context, index) {
          final ride = _activeRides[index];
          return _buildActiveRideCard(ride, themeProvider);
        },
      ),
    );
  }
  
  Widget _buildActiveRideCard(Map<String, dynamic> ride, ThemeProvider themeProvider) {
    final statusColor = _getStatusColor(ride['status']?.toString() ?? 'pending');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Durum ve Zaman
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    ride['status_text'] ?? 'Bilinmeyen',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                if (ride['can_cancel'] == true)
                  TextButton.icon(
                    onPressed: () => _cancelActiveRide(ride),
                    icon: const Icon(Icons.cancel, size: 16, color: Colors.red),
                    label: const Text(
                      'İptal Et',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Rota
            _buildRouteInfo(ride),
            
            const SizedBox(height: 16),
            
            // Şoför Bilgisi (varsa)
            if (ride['driver_name'] != null && ride['driver_name'] != 'Vale')
              _buildDriverInfo(ride, themeProvider),
              
            // ETA ve Fiyat
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (ride['estimated_arrival'] != null)
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Tahmini: ${ride['estimated_arrival']}',
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ],
                  ),
                Text(
                  '₺${double.tryParse(ride['estimated_price']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDriverInfo(Map<String, dynamic> ride, ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFFFD700),
            child: Text(
              (ride['driver_name']?[0] ?? 'V').toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride['driver_name'] ?? 'Vale',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (ride['driver_rating'] != null)
                  Row(
                    children: [
                      ...List.generate(5, (index) => Icon(
                        index < (ride['driver_rating'] ?? 0) ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 14,
                      )),
                      const SizedBox(width: 4),
                      Text(
                        '${ride['driver_rating']}/5',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // ŞİRKET ÜZERIN DEN ARAMA
          IconButton(
            onPressed: () => _callDriver('0543 123 45 67'),
            icon: const Icon(Icons.phone, color: Colors.green),
            tooltip: 'Şirket Üzerinden Ara',
          ),
        ],
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.green;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  void _cancelActiveRide(Map<String, dynamic> ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Yolculuğu İptal Et'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu yolculuğu iptal etmek istediğinizden emin misiniz?',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ ÖNEMLİ BİLGİLENDİRME',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• HEMEN seçeneği: Vale kabul ettikten 5 dakika sonra iptal ederseniz ₺1,500 iptal ücreti alınır.',
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• REZERVASYON: Yolculuğun başlama saatine 45 dakikadan az kalmışsa ₺1,500 iptal ücreti alınır.',
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• İptal ücreti varsa direkt ödeme ekranına yönlendirileceksiniz.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('İptal Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      // İptal API çağrısı
      await _cancelRide(ride);
    }
  }
  
  // YOLCULUK İPTAL FONKSIYONU - İPTAL ÜCRETİ SİSTEMİ İLE
  Future<void> _cancelRide(Map<String, dynamic> ride) async {
    try {
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Yolculuk iptal ediliyor...'),
            ],
          ),
        ),
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/cancel_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': ride['id'],
          'customer_id': customerId,
        }),
      );

      // Loading kapat
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📱 İPTAL API RESPONSE: ${response.body}');
        
        if (data['success'] == true) {
          final cancellationFee = (data['cancellation_fee'] ?? 0.0) is int 
              ? (data['cancellation_fee'] as int).toDouble() 
              : data['cancellation_fee'] ?? 0.0;
          final feeApplied = data['fee_applied'] ?? false;
          
          // RideProvider'dan temizle
          final rideProvider = Provider.of<RideProvider>(context, listen: false);
          rideProvider.clearCurrentRide();
          
          print('✅ Yolculuk iptal edildi: ${ride['id']}, Ücret: ₺$cancellationFee');
          
          // ÜCRETLİ İPTAL İSE DİREKT ÖDEME EKRANINA YÖNLENDİR!
          if (feeApplied && cancellationFee > 0) {
            print('💳 İptal ücreti var (₺$cancellationFee) - Ödeme ekranına yönlendiriliyor...');
            
            // Bilgilendirme dialogu göster
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.payment, color: Color(0xFFFFD700), size: 28),
                    SizedBox(width: 12),
                    Text('İptal Ücreti'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Yolculuğunuz iptal edildi.',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'İptal Ücreti',
                            style: TextStyle(color: Colors.black54, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₺${cancellationFee.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.black,
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
                      style: TextStyle(color: Colors.black54, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
                      // TODO: Ödeme ekranı navigator push yapılacak
                    },
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
          } else {
            // ÜCRETSİZ İPTAL - SnackBar ile bilgi ver
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
                duration: Duration(seconds: 3),
              ),
            );
            
            // Otomatik ana sayfaya dön (1 saniye sonra)
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
              }
            });
          }
          
          // Listeyi yenile
          await _loadActiveRides();
          
        } else {
          // Hata mesajı göster
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('İptal Hatası'),
                ],
              ),
              content: Text(data['message'] ?? 'Bilinmeyen hata oluştu'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
      
    } catch (e) {
      // Loading kapat (hata durumunda)
      if (Navigator.canPop(context)) Navigator.pop(context);
      
      print('❌ Yolculuk iptal hatası: $e');
      
      // Hata mesajı göster
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Bağlantı Hatası'),
            ],
          ),
          content: const Text('İptal işlemi sırasında bir hata oluştu. Lütfen tekrar deneyin.'),
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

  void _callDriver(String phoneNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phone, color: Colors.green),
            SizedBox(width: 8),
            Text('Şirket Üzerinden Arama'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Arama şirket numarası üzerinden gerçekleşecektir:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    '0543 123 45 67',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              print('📞 Müşteri şirket üzerinden arama başlattı');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Ara', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildPastRidesTab(ThemeProvider themeProvider) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
        ),
      );
    }
    
    if (_pastRides.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'Geçmiş Yolculuk Yok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Henüz tamamlanmış yolculuğunuz bulunmuyor',
              style: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadPastRides,
      color: const Color(0xFFFFD700),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pastRides.length,
        itemBuilder: (context, index) {
          final ride = _pastRides[index];
          return _buildRideCard(ride, themeProvider);
        },
      ),
    );
  }
  
  Widget _buildRideCard(Map<String, dynamic> ride, ThemeProvider themeProvider) {
    final rideDate = DateTime.tryParse(ride['created_at'] ?? '') ?? DateTime.now();
    final ridePrice = double.tryParse(ride['final_price']?.toString() ?? ride['estimated_price']?.toString() ?? '0') ?? 0.0;
    final rideStatus = ride['status']?.toString() ?? 'completed';
    
    // 🎁 İndirim bilgisi
    final discountCode = ride['discount_code']?.toString() ?? '';
    final discountAmount = double.tryParse(ride['discount_amount']?.toString() ?? '0') ?? 0.0;
    final hasDiscount = discountCode.isNotEmpty && discountAmount > 0;
    final originalPrice = hasDiscount ? ridePrice + discountAmount : ridePrice;
    
    // 🗺️ Özel konum bilgisi
    final specialLocation = ride['special_location'];
    final hasSpecialLocation = specialLocation != null && specialLocation['fee'] != null && (specialLocation['fee'] as num) > 0;
    final specialLocationFee = hasSpecialLocation ? (specialLocation['fee'] as num).toDouble() : 0.0;
    final specialLocationName = hasSpecialLocation ? (specialLocation['name']?.toString() ?? 'Özel Bölge') : '';
    
    // 🔍 DEBUG
    if (ride['id'].toString() == '487' || ride['id'].toString() == '488') {
      print('🎁 MÜŞTERİ GEÇMİŞ #${ride['id']}: discount_code=$discountCode, discount_amount=$discountAmount, hasDiscount=$hasDiscount');
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showRideDetails(ride),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Tarih ve Durum
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: const Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${rideDate.day}.${rideDate.month}.${rideDate.year}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  _buildStatusChip(rideStatus),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Rota Bilgileri
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 2,
                        height: 20,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['pickup_address']?.toString() ?? 'Alış konumu',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          ride['destination_address']?.toString() ?? 'Varış konumu',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Alt bilgiler
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ride['driver_name']?.toString() ?? 'Vale',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          '₺${originalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          '🎁 -₺${discountAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (hasSpecialLocation) ...[
                        Text(
                          '🗺️ $specialLocationName',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '+₺${specialLocationFee.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[400],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      Text(
                        '₺${ridePrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              
              // FATURA VE ÖDEME BUTONLARI
              Row(
                children: [
                  // FATURA GÖR BUTONU - SADECE FATURA KESİLMİŞSE GÖSTER!
                  if (ride['parasut_invoice_id'] != null || 
                      ride['invoice_number'] != null ||
                      (ride['invoice_id'] != null && ride['invoice_id'] > 0))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showInvoice(ride),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('Fatura Gör'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFD700),
                          side: const BorderSide(color: Color(0xFFFFD700)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  
                  // Boşluk - Fatura varsa
                  if (ride['parasut_invoice_id'] != null || 
                      ride['invoice_number'] != null ||
                      (ride['invoice_id'] != null && ride['invoice_id'] > 0))
                    const SizedBox(width: 8),
                  
                  // BORÇ ÖDE BUTONU - SADECE BORÇ VARSA GÖSTER
                  Builder(
                    builder: (context) {
                      final rideStatus = (ride['status'] ?? '').toString().toLowerCase();
                      final pendingAmount = (ride['pending_payment_amount'] as num?)?.toDouble() ?? 0.0;
                      final isRideFinished = ['completed', 'cancelled'].contains(rideStatus);
                      
                      // DEBUG LOG
                      print('🔍 [BORÇ ÖDE] Ride #${ride['id']}: status=$rideStatus, pending_payment_amount=$pendingAmount, isRideFinished=$isRideFinished');

                      // ✅ SADECE pending_payment_amount > 0 İSE BORÇ ÖDE GÖSTER!
                      if (pendingAmount > 0 && isRideFinished) {
                        final buttonLabel = 'Borç Öde (₺${pendingAmount.toStringAsFixed(2)})';

                        return Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _navigateToPaymentScreen(ride),
                            icon: const Icon(Icons.payment, size: 18),
                            label: Text(buttonLabel),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        );
                      }

                      // BORÇ YOKSA HİÇBİR ŞEY GÖSTERME!
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // FATURA GÖRÜNTÜLEME
  Future<void> _showInvoice(Map<String, dynamic> ride) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;
      final rideId = ride['id'];
      
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_ride_invoice.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'customer_id': int.parse(customerId ?? '0'),
        }),
      ).timeout(const Duration(seconds: 10));
      
      // Loading kapat
      if (Navigator.canPop(context)) Navigator.pop(context);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['has_invoice']) {
          final invoice = data['invoice'];
          final pdfUrl = invoice['pdf_url'];
          
          // PDF varsa direkt göster
          if (pdfUrl != null && pdfUrl.toString().isNotEmpty) {
            await _openInvoicePDF(pdfUrl);
          } else {
            // PDF yoksa detay göster
            _displayInvoiceDialog(invoice);
          }
        } else {
          // FATURA YOK
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu yolculuk için fatura henüz kesilmemiş'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      // Loading kapat
      if (Navigator.canPop(context)) Navigator.pop(context);
      
      print('❌ Fatura yükleme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fatura yüklenemedi: $e')),
      );
    }
  }
  
  // FATURA DIALOG (YEDEK - PDF YOKSA)
  void _displayInvoiceDialog(Map<String, dynamic> invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Color(0xFFFFD700), size: 28),
            const SizedBox(width: 12),
            const Text('Fatura Detayları'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInvoiceRow('Fatura No:', invoice['invoice_number'] ?? '-'),
              _buildInvoiceRow('Tarih:', invoice['invoice_date'] ?? '-'),
              const Divider(height: 24),
              _buildInvoiceRow('Şirket:', invoice['company_name'] ?? '-'),
              _buildInvoiceRow('Vergi Dairesi:', invoice['tax_office'] ?? '-'),
              _buildInvoiceRow('Vergi No:', invoice['tax_number'] ?? '-'),
              const Divider(height: 24),
              _buildInvoiceRow('Hizmet:', 'ŞOFÖR HİZMETİ'),
              const Divider(height: 12),
              _buildInvoiceRow('Ara Toplam:', '₺${double.tryParse(invoice['subtotal'].toString())?.toStringAsFixed(2) ?? '0.00'}'),
              _buildInvoiceRow('KDV (%20):', '₺${double.tryParse(invoice['kdv_amount'].toString())?.toStringAsFixed(2) ?? '0.00'}'),
              const Divider(height: 12),
              _buildInvoiceRow(
                'TOPLAM:', 
                '₺${double.tryParse(invoice['total_amount'].toString())?.toStringAsFixed(2) ?? '0.00'}',
                bold: true,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PDF fatura henüz hazır değil. Lütfen daha sonra tekrar deneyin.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  // PDF GÖRÜNTÜLEME
  Future<void> _openInvoicePDF(String pdfUrl) async {
    try {
      // URL'yi tarayıcıda aç
      final Uri url = Uri.parse(pdfUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('PDF açılamadı');
      }
    } catch (e) {
      print('❌ PDF açma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF açılamadı: $e')),
      );
    }
  }
  
  
  Widget _buildInvoiceRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  
  // ÖDEME EKRANINA YÖNLENDİR
  Future<void> _navigateToPaymentScreen(Map<String, dynamic> ride) async {
    // ✅ SAFE PARSE - Backend String veya num gönderebilir!
    final double estimatedPrice = double.tryParse(ride['estimated_price']?.toString() ?? '0') ?? 0.0;
    final double finalPrice = double.tryParse(ride['final_price']?.toString() ?? '0') ?? 0.0;
    final double pendingAmount = double.tryParse(ride['pending_payment_amount']?.toString() ?? '0') ?? 0.0;
    final double totalDistance = double.tryParse(ride['total_distance']?.toString() ?? '0') ?? 0.0;
    final int waitingMinutes = int.tryParse(ride['waiting_minutes']?.toString() ?? '0') ?? 0;

    final rideDetails = {
      'ride_id': ride['id'],
      'customer_id': ride['customer_id'],
      'driver_id': ride['driver_id'],
      'driver_name': ride['driver_name'] ?? 'Vale',
      'driver_phone': ride['driver_phone'] ?? '',
      'pickup_address': ride['pickup_address'] ?? '',
      'destination_address': ride['destination_address'] ?? '',
      'pickup_lat': ride['pickup_lat'],
      'pickup_lng': ride['pickup_lng'],
      'destination_lat': ride['destination_lat'],
      'destination_lng': ride['destination_lng'],
      'estimated_price': finalPrice > 0 ? finalPrice : estimatedPrice,
      'initial_estimated_price': ride['initial_estimated_price'] ?? estimatedPrice,
      'base_price_only': ride['initial_estimated_price'] ?? estimatedPrice,
      'final_price': finalPrice,
      'payment_status': ride['payment_status'],
      'payment_method': ride['payment_method'],
      'pending_payment_amount': pendingAmount,
      'service_type': ride['service_type'] ?? 'vale',
      'created_at': ride['created_at'],
      'completed_at': ride['completed_at'],
      'waiting_minutes': waitingMinutes,
      'total_distance': totalDistance,
      'discount_code': ride['discount_code'],
      'discount_amount': ride['discount_amount'],
    };

    final rideStatus = {
      'ride_id': ride['id'],
      'status': ride['status'],
      'estimated_price': finalPrice > 0 ? finalPrice : estimatedPrice,
      'waiting_minutes': waitingMinutes,
      'current_km': totalDistance,
      'service_type': ride['service_type'] ?? 'vale',
      'completed_at': ride['completed_at'],
      'payment_status': ride['payment_status'],
    };

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RidePaymentScreen(
          rideDetails: Map<String, dynamic>.from(rideDetails),
          rideStatus: Map<String, dynamic>.from(rideStatus),
        ),
      ),
    );

    if (result == true) {
      await _loadPastRides();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ödeme başarılı! Yolculuk listesi güncellendi.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  // ÖDEME SEÇENEKLERİ (ESKİ - ARTIK KULLANILMIYOR)
  Future<void> _showPaymentOptions(Map<String, dynamic> ride) async {
    // Borç Öde butonuna yönlendirildi
    await _navigateToPaymentScreen(ride);
  }
  
  Widget _buildStatusChip(String status) {
    Color color;
    String text;
    
    switch (status.toLowerCase()) {
      case 'completed':
        color = Colors.green;
        text = 'Tamamlandı';
        break;
      case 'paid':
        color = Colors.blue;
        text = 'Ödendi';
        break;
      case 'cancelled':
        color = Colors.red;
        text = 'İptal';
        break;
      default:
        color = Colors.grey;
        text = status;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
  
  void _showRideDetails(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRideDetailModal(ride),
    );
  }
  
  Widget _buildRideDetailModal(Map<String, dynamic> ride) {
    final rideDate = DateTime.tryParse(ride['created_at'] ?? '') ?? DateTime.now();
    final estimatedPrice = double.tryParse(ride['estimated_price']?.toString() ?? '0') ?? 0.0;
    final finalPrice = double.tryParse(ride['final_price']?.toString() ?? '0') ?? 0.0;
    final actualPrice = finalPrice > 0 ? finalPrice : estimatedPrice;
    final waitingTime = int.tryParse(ride['waiting_minutes']?.toString() ?? '0') ?? 0;
    final distance = double.tryParse(ride['total_distance']?.toString() ?? '0') ?? 0.0;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Yolculuk Detayları',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tarih ve Saat
                  _buildDetailSection(
                    '📅 Tarih ve Saat',
                    [
                      '${rideDate.day}.${rideDate.month}.${rideDate.year} - ${rideDate.hour.toString().padLeft(2, '0')}:${rideDate.minute.toString().padLeft(2, '0')}'
                    ],
                  ),
                  
                  // Rota Detayları
                  _buildDetailSection(
                    '🗺️ Rota Detayları',
                    [
                      'Nereden: ${ride['pickup_address'] ?? 'Belirtilmemiş'}',
                      ..._parseWaypoints(ride['waypoints']),
                      'Nereye: ${ride['destination_address'] ?? 'Belirtilmemiş'}',
                      'Mesafe: ${distance > 0 ? '${distance.toStringAsFixed(1)} km' : 'Bilinmiyor'}',
                    ],
                  ),
                  
                  // Vale Bilgileri
                  _buildDetailSection(
                    '👤 Vale Bilgileri',
                    [
                      'Vale: ${ride['driver_name'] ?? 'Belirtilmemiş'}',
                      'Değerlendirme: ${ride['driver_rating'] != null ? '⭐ ${ride['driver_rating']}' : 'Değerlendirilmemiş'}',
                    ],
                  ),
                  
                  // Ücret Detayları (Breakdown)
                  _buildPriceBreakdown(ride, estimatedPrice, actualPrice, waitingTime),
                  
                  // Yolculuk İstatistikleri
                  _buildDetailSection(
                    '📊 Yolculuk İstatistikleri',
                    [
                      'Bekleme Süresi: ${waitingTime > 0 ? '$waitingTime dakika' : 'Bekleme yok'}',
                      'Yolculuk Süresi: ${ride['trip_duration'] ?? 'Bilinmiyor'}',
                      'Durum: ${_getStatusText(ride['status']?.toString() ?? 'completed')}',
                    ],
                  ),
                  
                  if ((ride['status'] ?? '').toString().toLowerCase() == 'cancelled')
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '45 dakika veya daha öncesinde rezervasyon iptallerinde 1500₺ iptal ücreti yansımaktadır.',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
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
        ],
      ),
    );
  }
  
  Widget _buildDetailSection(String title, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              item,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          )),
        ],
      ),
    );
  }
  
  Widget _buildPriceBreakdown(Map<String, dynamic> ride, double estimatedPrice, double actualPrice, int waitingTime) {
    // ✅ Backend'den bekleme ücreti al (varsa), yoksa hesapla
    final backendWaitingFee = double.tryParse(ride['waiting_fee']?.toString() ?? '0') ?? 0.0;
    final waitingFee = backendWaitingFee > 0 
        ? backendWaitingFee 
        : (waitingTime > 15 ? ((waitingTime - 15) / 15).ceil() * 200.0 : 0.0);
    
    // ✅ YENİ: Alış ve Bırakış Özel Konum Ücretleri AYRI AYRI
    final pickupLocationFee = double.tryParse(ride['pickup_location_fee']?.toString() ?? '0') ?? 0.0;
    final dropoffLocationFee = double.tryParse(ride['dropoff_location_fee']?.toString() ?? '0') ?? 0.0;
    final pickupLocationName = ride['pickup_location_name']?.toString() ?? '';
    final dropoffLocationName = ride['dropoff_location_name']?.toString() ?? '';
    
    // Toplam özel konum ücreti (fallback için)
    final locationExtraFee = (double.tryParse(ride['location_extra_fee']?.toString() ?? '0') ?? 0.0) > 0
        ? double.tryParse(ride['location_extra_fee'].toString()) ?? 0.0
        : double.tryParse(ride['special_location']?['fee']?.toString() ?? '0') ?? 0.0;
    
    // ✅ Backend'den mesafe ücreti al (varsa), yoksa hesapla
    final backendDistancePrice = double.tryParse(ride['distance_price']?.toString() ?? 
                                                   ride['base_price']?.toString() ?? '0') ?? 0.0;
    // Temel ücret = Backend'den gelen veya (Toplam - Bekleme - Özel Konum)
    final baseFare = backendDistancePrice > 0 
        ? backendDistancePrice 
        : actualPrice - waitingFee - locationExtraFee;
    
    // 🎁 İndirim bilgilerini al
    final discountCode = ride['discount_code']?.toString() ?? '';
    final discountAmount = double.tryParse(ride['discount_amount']?.toString() ?? '0') ?? 0.0;
    final hasDiscount = discountCode.isNotEmpty && discountAmount > 0;
    
    // İndirimsiz orijinal tutar
    final originalPrice = hasDiscount ? actualPrice + discountAmount : actualPrice;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.currency_lira, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Ücret Detayları',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Temel Ücret
          _buildPriceRow('Temel Ücret', baseFare),
          
          // Bekleme Ücreti (varsa)
          if (waitingFee > 0)
            _buildPriceRow('Bekleme Ücreti (${waitingTime - 15} dk)', waitingFee),
          
          // ✅ ALIŞ Özel Konum Ücreti (varsa)
          if (pickupLocationFee > 0)
            _buildPriceRow(
              '🗺️ Alış Özel Konum${pickupLocationName.isNotEmpty ? " ($pickupLocationName)" : ""}', 
              pickupLocationFee
            ),
          
          // ✅ BIRAKIŞ Özel Konum Ücreti (varsa)
          if (dropoffLocationFee > 0)
            _buildPriceRow(
              '🗺️ Bırakış Özel Konum${dropoffLocationName.isNotEmpty ? " ($dropoffLocationName)" : ""}', 
              dropoffLocationFee
            ),
          
          // ✅ Fallback: Eski sistemle uyumluluk - toplam özel konum (ayrı yoksa)
          if (pickupLocationFee == 0 && dropoffLocationFee == 0 && locationExtraFee > 0)
            _buildPriceRow(
              '🗺️ Özel Konum Ücreti', 
              locationExtraFee
            ),
          
          // 🎁 İndirim (varsa)
          if (hasDiscount) ...[
            const Divider(color: Color(0xFFFFD700)),
            _buildPriceRow('Ara Toplam', originalPrice),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.discount, color: Colors.orange, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'İndirim ($discountCode)',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '-₺${discountAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const Divider(color: Color(0xFFFFD700)),
          
          // Toplam
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Toplam',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '₺${actualPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPriceRow(String title, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.black87),
          ),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRouteInfo(Map<String, dynamic> ride) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 2,
              height: 30,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 4),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ride['pickup_address']?.toString() ?? 'Alış konumu',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Text(
                ride['destination_address']?.toString() ?? 'Varış konumu',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ARA DURAKLAR PARSE ET
  List<String> _parseWaypoints(dynamic waypointsJson) {
    try {
      if (waypointsJson == null || waypointsJson.toString().isEmpty || waypointsJson.toString() == 'null') {
        return [];
      }
      
      List<dynamic> waypoints = [];
      if (waypointsJson is String) {
        waypoints = jsonDecode(waypointsJson);
      } else if (waypointsJson is List) {
        waypoints = waypointsJson;
      }
      
      if (waypoints.isEmpty) {
        return [];
      }
      
      List<String> result = [];
      for (int i = 0; i < waypoints.length; i++) {
        final waypoint = waypoints[i];
        final address = waypoint['address'] ?? waypoint['adres'] ?? waypoint['name'] ?? 'Ara Durak ${i + 1}';
        result.add('🛣️ Ara Durak ${i + 1}: $address');
      }
      
      return result;
    } catch (e) {
      print('⚠️ Waypoints parse hatası (geçmiş yolculuklar): $e');
      return [];
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Başarıyla Tamamlandı';
      case 'paid':
        return 'Ödeme Tamamlandı';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return status;
    }
  }
}