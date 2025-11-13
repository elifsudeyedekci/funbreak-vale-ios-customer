import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard için!
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/theme_provider.dart';
import '../../providers/admin_api_provider.dart';
import '../../providers/ride_provider.dart'; // 🔥 RideProvider temizliği için!
import '../../services/customer_cards_api.dart'; // Kart yönetimi için

// MÜŞTERİ ÖDEME VE PUANLAMA EKRANI!
class RidePaymentScreen extends StatefulWidget {
  final Map<String, dynamic> rideDetails;
  final Map<String, dynamic> rideStatus;
  
  const RidePaymentScreen({
    Key? key, 
    required this.rideDetails,
    required this.rideStatus,
  }) : super(key: key);
  
  @override
  State<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends State<RidePaymentScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  
  // PUANLAMA KALDIRILDI - ANA EKRANDA YAPILACAK!
  bool _isProcessingPayment = false;
  bool _paymentCompleted = false;
  
  // Trip calculations - HEPSİ DEFAULT VALUE İLE BAŞLASIN!
  double _basePrice = 0.0;
  double _waitingFee = 0.0;
  double _totalPrice = 0.0;
  int _waitingMinutes = 0;
  double _distance = 0.0;
  
  // Panel pricing settings
  double _waitingFeePerInterval = 200.0; // Varsayılan: Her 15 dakika ₺200
  int _waitingFreeMinutes = 15; // İlk 15 dakika ücretsiz
  int _waitingIntervalMinutes = 15; // 15 dakikalık aralıklar
  
  // ÖDEME YÖNTEMİ VE İNDİRİM KODU - ÖDEME EKRANINA EKLENDİ!
  String _selectedPaymentMethod = ''; // Başlangıçta boş - kullanıcı seçecek
  String? _selectedCardId; // Seçilen kayıtlı kart ID'si
  List<Map<String, dynamic>> _savedCards = []; // Kayıtlı kartlar
  final TextEditingController _discountCodeController = TextEditingController();
  double _discountAmount = 0.0;
  bool _discountApplied = false;
  
  // SAATLİK PAKET BİLGİSİ
  String _hourlyPackageLabel = '';
  
  @override
  void initState() {
    super.initState();
    
    // ÖNCELİKLE ride status'tan verileri al
    _waitingMinutes = widget.rideStatus['waiting_minutes'] ?? 0;
    // ✅ MESAFE - Backend'den total_distance, current_km veya total_distance_km gelebilir
    _distance = double.tryParse(
      widget.rideStatus['total_distance']?.toString() ??
      widget.rideStatus['current_km']?.toString() ??
      widget.rideStatus['total_distance_km']?.toString() ??
      widget.rideDetails['total_distance']?.toString() ?? '0'
    ) ?? 0.0;
    
    // BASE PRICE (bekleme hariç!) - Backend'den base_price_only gelecek
    final basePriceOnly = widget.rideDetails['base_price_only'] ?? widget.rideDetails['estimated_price'];
    if (basePriceOnly != null) {
      _basePrice = double.tryParse(basePriceOnly.toString()) ?? 0.0; // ✅ SAFE PARSE
    }
    
    _initializeAnimation();
    
    // Panel'den ayarları çek ve HESAPLA - async ama UI beklemeden gösterilsin
    _fetchPanelPricingAndCalculate();
    
    // İlk hesaplama (varsayılan değerlerle - panel gelince güncellenecek)
    _calculateTripDetails();
    
    // Kayıtlı kartları yükle
    _loadSavedCards();
  }
  
  Future<void> _loadSavedCards() async {
    try {
      final cardsApi = CustomerCardsApi();
      final cards = await cardsApi.getCards();
      
      setState(() {
        _savedCards = cards;
        // İlk kartı otomatik seç (varsa)
        if (_savedCards.isNotEmpty && _selectedCardId == null) {
          _selectedCardId = _savedCards.first['id'];
        }
      });
      
      print('✅ ${_savedCards.length} kart yüklendi');
    } catch (e) {
      print('⚠️ Kart yükleme hatası: $e');
    }
  }
  
  void _initializeAnimation() {
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.elasticOut));
    
    _animController.forward();
  }
  
  // YENİ: PANEL'DEN FİYATLANDIRMA AYARLARINI ÇEK VE HESAPLA!
  Future<void> _fetchPanelPricingAndCalculate() async {
    try {
      // Panel'den fiyatlandırma ayarlarını çek
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_pricing_settings.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['pricing'] != null) {
          final pricing = data['pricing'];
          
          setState(() {
            _waitingFeePerInterval = double.tryParse(pricing['waiting_fee_per_interval']?.toString() ?? '200') ?? 200.0;
            _waitingFreeMinutes = int.tryParse(pricing['waiting_fee_free_minutes']?.toString() ?? '15') ?? 15;
            _waitingIntervalMinutes = int.tryParse(pricing['waiting_interval_minutes']?.toString() ?? '15') ?? 15;
          });
          
          print('✅ MÜŞTERİ ÖDEME: Panel ayarları çekildi - İlk $_waitingFreeMinutes dk ücretsiz, sonra her $_waitingIntervalMinutes dk ₺$_waitingFeePerInterval');
        }
      }
    } catch (e) {
      print('⚠️ MÜŞTERİ ÖDEME: Panel ayar çekme hatası, varsayılan kullanılıyor: $e');
      // Varsayılan değerler zaten set edildi
    }
    
    // Hesaplamayı yap
    _calculateTripDetails();
  }
  
  void _calculateTripDetails() {
    // İPTAL ÜCRETİ KONTROLÜ - ÖNCE BU!
    final isCancellationFee = widget.rideStatus['is_cancellation_fee'] == true;
    
    if (isCancellationFee) {
      // İPTAL ÜCRETİ - rideStatus'tan final_price kullan!
      final cancellationFee = widget.rideStatus['final_price'] ?? 1500;
      _basePrice = 0.0;
      _waitingFee = 0.0;
      _totalPrice = (cancellationFee as num).toDouble();
      _waitingMinutes = 0;
      _distance = 0.0;
      
      print('💳 İPTAL ÜCRETİ ÖDEME: ₺${_totalPrice.toStringAsFixed(0)}');
      return; // Hesaplama bitir!
    }
    
    // ✅ NORMAL YOLCULUK - estimated_price (bekleme dahil olabilir), waiting hesapla, base = estimated - waiting
    final estimatedPrice = double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0;
    _waitingMinutes = widget.rideStatus['waiting_minutes'] ?? 0;
    
    // ✅ MESAFE HESAPLAMA - Backend'den total_distance gelir (current_km veya total_distance_km da olabilir)
    _distance = double.tryParse(
      widget.rideStatus['total_distance']?.toString() ??
      widget.rideStatus['current_km']?.toString() ??
      widget.rideStatus['total_distance_km']?.toString() ??
      widget.rideDetails['total_distance']?.toString() ??
      widget.rideDetails['current_km']?.toString() ?? '0'
    ) ?? 0.0;
    
    print('📏 MÜŞTERİ ÖDEME: Toplam mesafe = ${_distance.toStringAsFixed(2)} km');
    
    // SAATLİK PAKET KONTROLÜ - GECELİKTE BEKLEME YOK!
    final serviceType = widget.rideStatus['service_type'] ?? widget.rideDetails['service_type'] ?? 'vale';
    final isHourlyPackage = (serviceType == 'hourly');
    
    // SAATLİK PAKET BİLGİSİNİ BELİRLE
    if (isHourlyPackage) {
      final rideDurationHours = widget.rideStatus['ride_duration_hours'];
      if (rideDurationHours != null) {
        final hours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
        final estimatedPrice = double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0;
        
        // Fiyata göre paket belirle
        if (estimatedPrice == 3000) {
          _hourlyPackageLabel = '0-4 Saat Paketi';
        } else if (estimatedPrice == 4500) {
          _hourlyPackageLabel = '4-8 Saat Paketi';
        } else if (estimatedPrice == 6000) {
          _hourlyPackageLabel = '8-12 Saat Paketi';
        } else if (estimatedPrice == 18000) {
          _hourlyPackageLabel = '12-20 Saat Paketi';
        } else if (estimatedPrice == 26000) {
          _hourlyPackageLabel = '20-50 Saat Paketi';
        } else {
          _hourlyPackageLabel = 'Saatlik Paket (${hours.toStringAsFixed(1)} saat)';
        }
      } else {
        _hourlyPackageLabel = 'Saatlik Paket';
      }
    }
    
    // ✅ NORMAL YOLCULUK - Backend'den gelen estimated_price kullan (zaten bekleme dahil!)
    // ⚠️ Backend'den gelen estimated_price ZATEN bekleme dahil!
    final finalPrice = widget.rideStatus['final_price'];
    final backendEstimatedPrice = widget.rideStatus['estimated_price'] ?? 
                                   widget.rideDetails['estimated_price'] ?? 
                                   estimatedPrice;
    
    // final_price varsa onu kullan (tamamlanmış yolculuk)
    if (finalPrice != null && finalPrice > 0) {
      _totalPrice = double.tryParse(finalPrice.toString()) ?? 0.0;
      _basePrice = _totalPrice; // Tam tutar
      _waitingFee = 0.0; // Backend'de zaten hesaplanmış
      print('💳 ÖDEME: final_price kullanılıyor (completed): ₺${_totalPrice.toStringAsFixed(2)}');
    } else {
      // Backend'den gelen estimated_price kullan
      _totalPrice = double.tryParse(backendEstimatedPrice.toString()) ?? 0.0;
      _basePrice = _totalPrice; // Backend zaten toplam hesaplamış
      _waitingFee = 0.0; // Backend'de zaten dahil
      print('💳 ÖDEME: Backend estimated_price (bekleme dahil): ₺${_totalPrice.toStringAsFixed(2)}');
    }
    
    // setState ile UI güncelle
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        title: const Text(
          '💳 Ödeme Sayfası',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // "Yolculuk Tamamlandı" barı KALDIRILDI - Gereksiz alan kaplıyordu
            
            // Trip summary
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🗺️ Yolculuk Özeti',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  _buildSummaryRow('📍 Nereden', widget.rideDetails['pickup_address'] ?? ''),
                  const SizedBox(height: 8),
                  _buildSummaryRow('🎯 Nereye', widget.rideDetails['destination_address'] ?? ''),
                  const SizedBox(height: 8),
                  _buildSummaryRow('📏 Mesafe', '${_distance.toStringAsFixed(1)} km'),
                  const SizedBox(height: 8),
                  _buildSummaryRow('⏱️ Süre', _getRideDuration()),
                  const SizedBox(height: 8),
                  _buildSummaryRow('🕐 Tamamlama', _getCompletionTime()),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Payment breakdown
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💳 Ödeme Detayları',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  
                  _buildPaymentRow('🚗 Yolculuk Ücreti', '₺${_basePrice.toStringAsFixed(2)}'),
                  if (_waitingMinutes > _waitingFreeMinutes && _hourlyPackageLabel.isEmpty)
                    _buildPaymentRow('⏰ Bekleme Ücreti', '₺${_waitingFee.toStringAsFixed(2)} ($_waitingMinutes dk)', subtitle: 'İlk $_waitingFreeMinutes dk ücretsiz, sonrası her $_waitingIntervalMinutes dk ₺${_waitingFeePerInterval.toStringAsFixed(0)}'),
                  if (_waitingMinutes <= _waitingFreeMinutes && _waitingMinutes > 0 && _hourlyPackageLabel.isEmpty)
                    _buildPaymentRow('⏰ Bekleme (Ücretsiz)', '$_waitingMinutes dakika', isFree: true),
                  if (_hourlyPackageLabel.isNotEmpty)
                    _buildPaymentRow('📦 $_hourlyPackageLabel', 'Paket fiyatına dahil', subtitle: 'Saatlik pakette bekleme ücreti alınmaz'),
                  if (_discountApplied && _discountAmount > 0)
                    _buildPaymentRow('🎁 İndirim', '-₺${_discountAmount.toStringAsFixed(2)}', subtitle: 'Kod: ${_discountCodeController.text}'),
                  const Divider(thickness: 2),
                  _buildPaymentRow('TOPLAM', '₺${(_totalPrice - _discountAmount).toStringAsFixed(2)}', isTotal: true),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // ÖDEME YÖNTEMİ SEÇİMİ!
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💳 Ödeme Yöntemi',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  
                  // Ödeme yöntemi seçici (tıklanabilir)
                  InkWell(
                    onTap: () => _showPaymentMethodModal(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: themeProvider.isDarkMode ? Colors.grey[700] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedPaymentMethod == 'card' ? Icons.credit_card : Icons.account_balance,
                            color: _selectedPaymentMethod == 'card' ? Colors.blue : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _selectedPaymentMethod == 'card' && _selectedCardId != null
                                ? _buildSelectedCardDetails()
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getPaymentMethodName(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  
                  // HAVALE SEÇİLDİYSE IBAN GÖSTER!
                  if (_selectedPaymentMethod == 'havale_eft') ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.5), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.account_balance, color: Colors.orange, size: 16),
                              SizedBox(width: 6),
                              Text(
                                '🏦 Havale/EFT Bilgileri',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '⚠️ Gönderici adınız hesap sahibi ile aynı olmalıdır',
                            style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          _buildIBANRow('Banka', 'VAKIFBANK'),
                          _buildIBANCopyRow('Hesap Sahibi', 'FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ'),
                          _buildIBANCopyRow('IBAN', 'TR49 0001 5001 5800 7364 9820 80'),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ℹ️ Sistem otomatik kontrol eder, ödemeniz geldiğinde onaylanır',
                              style: TextStyle(fontSize: 10, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // İNDİRİM KODU!
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.discount, color: Colors.green, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '🎁 İndirim Kodu',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountCodeController,
                          enabled: !_discountApplied, // 🔥 İndirim uygulandıysa YAZMA ENGELLE!
                          readOnly: _discountApplied, // 🔥 Uygulandıysa sadece oku
                          style: TextStyle(
                            fontSize: 13,
                            color: _discountApplied ? Colors.grey : Colors.black,
                          ),
                          decoration: InputDecoration(
                            hintText: 'İndirim kodu',
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                            filled: _discountApplied,
                            fillColor: _discountApplied ? Colors.grey[200] : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            prefixIcon: Icon(
                              Icons.confirmation_number,
                              size: 18,
                              color: _discountApplied ? Colors.grey : Colors.green,
                            ),
                            suffixIcon: _discountCodeController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _discountCodeController.clear();
                                        _discountAmount = 0.0;
                                        _discountApplied = false;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('🗑️ İndirim kodu kaldırıldı'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                  )
                                : null,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (value) {
                            setState(() {}); // X ikonunu göstermek için
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: _discountApplied ? null : _applyDiscountCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Uygula', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                  
                  if (_discountApplied) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '✅ İndirim uygulandı: ₺${_discountAmount.toStringAsFixed(2)} indirim!',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Payment button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessingPayment ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _paymentCompleted 
                    ? Colors.green[600] 
                    : const Color(0xFFFFD700),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                child: _isProcessingPayment 
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('💳 Ödeme işleniyor...'),
                      ],
                    )
                  : _paymentCompleted
                    ? const Text(
                        '✅ ÖDEME TAMAMLANDI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      )
                    : Text(
                        '💳 ₺${(_totalPrice - _discountAmount).toStringAsFixed(2)} ÖDE',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPaymentRow(String label, String value, {bool isTotal = false, bool isFree = false, String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isTotal ? const Color(0xFFFFD700) : Colors.black87,
                ),
              ),
              Text(
                isFree ? 'Ücretsiz' : value,
                style: TextStyle(
                  fontSize: isTotal ? 18 : 14,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                  color: isTotal 
                    ? const Color(0xFFFFD700)
                    : isFree 
                      ? Colors.green[600]
                      : Colors.black87,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
  
  // İNDİRİM KODU UYGULA
  Future<void> _applyDiscountCode() async {
    final code = _discountCodeController.text.trim().toUpperCase();
    
    print('🎁 === İNDİRİM KODU UYGULA BAŞLADI ===');
    print('🎁 Girilen kod: "$code"');
    print('💰 Toplam tutar: ₺$_totalPrice');
    
    if (code.isEmpty) {
      print('❌ Kod boş');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Lütfen bir indirim kodu girin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      print('📡 API çağrısı başlıyor: validate_discount.php');
      
      // Backend'den indirim kodu doğrula
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/validate_discount.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'total_amount': _totalPrice,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('📥 API Status: ${response.statusCode}');
      print('📥 API Response: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print('📊 Parsed Data: $data');
        print('✅ Success: ${data['success']}');
        print('💰 Discount Amount: ${data['discount_amount']}');
        
        if (data['success'] == true && data['discount_amount'] != null) {
          final discountAmount = double.tryParse(data['discount_amount'].toString()) ?? 0.0;
          
          print('✅ İndirim uygulandı: ₺$discountAmount');
          
          setState(() {
            _discountAmount = discountAmount;
            _discountApplied = true;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ İndirim kodu uygulandı: ₺${_discountAmount.toStringAsFixed(2)} indirim!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          print('❌ Kod geçersiz: ${data['message']}');
          throw Exception(data['message'] ?? 'Geçersiz indirim kodu');
        }
      }
    } catch (e) {
      print('❌ İndirim kodu hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ İndirim kodu hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // PUANLAMA FONKSİYONLARI KALDIRILDI!
  
  Future<void> _processPayment() async {
    // Ödeme yöntemi seçilmiş mi kontrol et
    if (_selectedPaymentMethod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Lütfen önce ödeme yöntemi seçiniz'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() {
      _isProcessingPayment = true;
    });
    
    try {
      final adminApi = AdminApiProvider();
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('user_id') ?? '0';
      
      // 1. Ödeme işle
      final finalAmount = _totalPrice - _discountAmount; // İndirim düşülmüş tutar!
      
      print('💳 === ÖDEME İŞLEMİ BAŞLIYOR ===');
      print('👤 Customer ID: $customerId');
      print('🚗 Ride ID: ${widget.rideDetails['ride_id']}');
      print('💰 Final Amount: ₺$finalAmount');
      print('💳 SELECTED PAYMENT METHOD: $_selectedPaymentMethod');
      print('================================');
      
      final paymentResult = await adminApi.completePayment(
        customerId: customerId,
        rideId: widget.rideDetails['ride_id'].toString(),
        amount: finalAmount,
        paymentMethod: _selectedPaymentMethod,
        discountCode: _discountCodeController.text.trim().isNotEmpty ? _discountCodeController.text.trim() : null,
        discountAmount: _discountAmount > 0 ? _discountAmount : null,
      );
      
      if (paymentResult['success'] != true) {
        throw Exception(paymentResult['message'] ?? 'Ödeme hatası');
      }
      
      // 2. ✅ YOLCULUK PERSISTENCE'INI TEMİZLE - ÖDEME DÖNGÜSÜNÜ ENGELLE!
      // Backend'den customer_active_rides tablosunu temizle (ayrı endpoint gerekebilir)
      // Şimdilik app-side temizlik yeterli
      await prefs.remove('customer_current_ride');
      await prefs.remove('active_ride_id');
      await prefs.remove('active_ride_status');
      await prefs.remove('pending_payment_ride_id');
      print('✅ Müşteri aktif yolculuk persistence temizlendi - Ödeme döngüsü engellendi!');
      
      setState(() {
        _paymentCompleted = true;
        _isProcessingPayment = false;
      });
      
      // ÖNCE PUANLAMA EKRANI AÇ!
      // Puanlama ana ekranda yapılacak - burada atlandı
      
      // Sonra başarı mesajı ve ana ekrana git
      _showPaymentSuccessAndGoHome();
      
      print('✅ Ödeme ve puanlama tamamlandı');
      
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ödeme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
      
      print('❌ Ödeme hatası: $e');
    }
  }
  
  // MODERN PUANLAMA DİALOGU - ANA EKRANDA KULLANILACAK!
  // NOT: Bu fonksiyon artık kullanılmıyor, ana ekranda modern kart gösterilecek
  
  void _showPaymentSuccessAndGoHome() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.payment, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('💳 Ödeme Başarılı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 50),
            const SizedBox(height: 16),
            // İndirim varsa detaylı göster
            if (_discountAmount > 0) ...[
              Text(
                'Orijinal Tutar: ₺${_totalPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  decoration: TextDecoration.lineThrough,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '🎁 İndirim (${_discountCodeController.text}): -₺${_discountAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '₺${(_totalPrice - _discountAmount).toStringAsFixed(2)} başarıyla tahsil edildi.',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
            ] else
              Text(
                '₺${_totalPrice.toStringAsFixed(2)} başarıyla tahsil edildi.',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            const Text(
              '✨ Ana ekranda şoförünüzü puanlayabilirsiniz.',
              style: TextStyle(fontSize: 14, color: Colors.blue),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Güvenli yolculuklar dileriz! 🚗✨',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Dialog kapat
                _saveRatingReminderAndGoHome();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Ana Sayfaya Dön ve Puanla', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
  
  // PUANLAMA HATIRLATMASI KAYDET VE ANA EKRANA GİT
  Future<void> _saveRatingReminderAndGoHome() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 🔥 ÖNEMLİ: RideProvider'ı temizle - Memory'deki currentRide'ı null yap!
      if (mounted) {
        final rideProvider = Provider.of<RideProvider>(context, listen: false);
        rideProvider.clearCurrentRide(); // Memory'den sil!
        print('✅ RideProvider temizlendi - Memory\'deki currentRide null yapıldı!');
      }
      
      // ✅ ÖNCE TÜM PERSISTENCE'I TEMİZLE - ÖDEME DÖNGÜSÜNÜ ENGELLE!
      await prefs.remove('customer_current_ride');
      await prefs.remove('active_ride_id');
      await prefs.remove('active_ride_status');
      await prefs.remove('pending_payment_ride_id');
      await prefs.remove('current_ride_persistence');
      await prefs.remove('has_active_ride');
      print('✅ ÖDEME SONRASI: Tüm ride persistence temizlendi - Döngü engellendi!');
      
      // Puanlama bilgisini kaydet - Ana ekranda kart gösterilecek
      await prefs.setString('pending_rating_ride_id', widget.rideDetails['ride_id'].toString());
      await prefs.setString('pending_rating_driver_id', widget.rideDetails['driver_id'].toString());
      await prefs.setString('pending_rating_driver_name', widget.rideDetails['driver_name'] ?? 'Şoförünüz');
      await prefs.setString('pending_rating_customer_id', widget.rideDetails['customer_id'].toString());
      await prefs.setBool('has_pending_rating', true);
      
      print('✅ Puanlama hatırlatması kaydedildi - Ana ekranda kart gösterilecek');
    } catch (e) {
      print('⚠️ Puanlama hatırlatma kaydetme hatası: $e');
    }
    
    // Ana sayfaya git - TÜM STACK'İ TEMİZLE!
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }
  
  // IBAN SATIRI - KOPYALAMA İLE!
  Widget _buildIBANCopyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.blue),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ $label kopyalandı'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // NORMAL IBAN SATIRI (Kopyasız)
  Widget _buildIBANRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ✅ BACKEND'DEN SÜRE HESAPLA (Sunucu saatine göre)
  String _getRideDuration() {
    final rideDurationHours = widget.rideStatus['ride_duration_hours'];
    if (rideDurationHours != null) {
      final hours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
      final totalMinutes = (hours * 60).round();
      
      if (totalMinutes >= 60) {
        final h = totalMinutes ~/ 60;
        final m = totalMinutes % 60;
        return '$h saat ${m > 0 ? "$m dakika" : ""}';
      } else {
        return '$totalMinutes dakika';
      }
    }
    
    // Fallback: Bekleme süresine +20 dakika ekle (eski yöntem)
    return '${(_waitingMinutes + 20).toString()} dakika';
  }
  
  // ✅ BACKEND'DEN TAMAMLANMA SAATİNİ AL (Sunucu saatine göre)
  String _getCompletionTime() {
    // 🔥 ÖNCELİK: Backend sunucu saatini kullan (completed_at)
    final completedAt = widget.rideStatus['completed_at'] ?? widget.rideDetails['completed_at'];
    if (completedAt != null && completedAt.toString().isNotEmpty) {
      // Backend'den gelen format: '2025-01-31 14:25:30' -> '2025-01-31 14:25'
      final timeStr = completedAt.toString();
      if (timeStr.length >= 16) {
        return timeStr.substring(0, 16);
      }
      return timeStr;
    }
    
    // Fallback: Şu anki saat (SADECE backend verisi yoksa)
    print('⚠️ Backend completed_at verisi yok - telefon saati kullanılıyor (istenmeyen durum)');
    return DateTime.now().toString().substring(0, 16);
  }

  Widget _buildSelectedCardDetails() {
    if (_selectedCardId == null || _savedCards.isEmpty) {
      return const SizedBox.shrink();
    }
    
    try {
      final card = _savedCards.firstWhere(
        (c) => c['id']?.toString() == _selectedCardId,
        orElse: () => {},
      );
      
      if (card.isEmpty) return const SizedBox.shrink();
      
      // Kart bilgilerini çıkar
      final cardNumber = card['cardNumber']?.toString() ?? '**** **** **** ****';
      final cardHolder = (card['cardHolder'] ?? card['name'])?.toString() ?? 'Kart Sahibi';
      final expiryDate = card['expiryDate']?.toString() ?? '--/--';
      final isDefault = card['isDefault'] == true || card['isDefault'] == 'true';
      
      return Row(
        children: [
          // Kart ikonu
          Container(
            width: 32,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.credit_card, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          // Kart bilgileri
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cardHolder.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Son kullanma ve varsayılan badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Son Kullanma: $expiryDate',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
              if (isDefault) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Varsayılan',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    } catch (e) {
      print('⚠️ Kart detayı gösterilemedi: $e');
      return const SizedBox.shrink();
    }
  }

  String _getPaymentMethodName() {
    if (_selectedPaymentMethod == 'card') {
      return 'Kredi/Banka Kartı';
    } else if (_selectedPaymentMethod == 'havale_eft') {
      return 'Havale/EFT';
    }
    return 'Lütfen Ödeme Yöntemi Seçiniz';
  }
  
  void _showPaymentMethodModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (modalContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Ödeme Yöntemi Seçin',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Kredi Kartı
            ListTile(
              leading: const Icon(Icons.credit_card, color: Colors.blue),
              title: const Text('Kredi/Banka Kartı', style: TextStyle(color: Colors.black)),
              subtitle: const Text('Kayıtlı kartlarınız', style: TextStyle(color: Colors.black87)),
              trailing: _selectedPaymentMethod == 'card' 
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.of(modalContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (mounted) {
                        _showCardSelectionModal();
                      }
                    });
                  }
                });
              },
            ),
            
            const Divider(height: 1),
            
            // Havale/EFT
            ListTile(
              leading: const Icon(Icons.account_balance, color: Colors.orange),
              title: const Text('Havale/EFT', style: TextStyle(color: Colors.black)),
              subtitle: const Text('Banka havalesi ile öde', style: TextStyle(color: Colors.black87)),
              trailing: _selectedPaymentMethod == 'havale_eft' 
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              onTap: () {
                setState(() {
                  _selectedPaymentMethod = 'havale_eft';
                  _selectedCardId = null;
                });
                Navigator.of(modalContext).pop();
              },
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  void _showCardSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Kart Seçin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Kayıtlı kartlar
              if (_savedCards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Kayıtlı kart bulunmamaktadır',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ..._savedCards.map((card) {
                  final cardId = card['id']?.toString() ?? '';
                  final isSelected = _selectedCardId == cardId;
                  
                  // Kart bilgileri
                  final cardType = (card['cardType'] ?? card['type'])?.toString().toLowerCase() ?? 'unknown';
                  final cardHolder = (card['cardHolder'] ?? card['name'])?.toString() ?? 'Kart Sahibi';
                  final cardNumber = card['cardNumber']?.toString() ?? '**** **** **** ****';
                  final expiryDate = card['expiryDate']?.toString() ?? '--/--';
                  final isDefault = card['isDefault'] == true || card['isDefault'] == 'true';
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.withOpacity(0.05) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (mounted) {
                          setState(() {
                            _selectedPaymentMethod = 'card';
                            _selectedCardId = cardId;
                          });
                        }
                      },
                      child: Row(
                        children: [
                          // Kart ikonu
                          Container(
                            width: 40,
                            height: 30,
                            decoration: BoxDecoration(
                              color: cardType.contains('visa') ? Colors.blue : 
                                     cardType.contains('master') ? Colors.orange : 
                                     Colors.grey,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.credit_card, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          // Kart bilgileri
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cardNumber,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cardHolder.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Son kullanma ve seçim
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Son Kullanma',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                expiryDate,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: Colors.green, size: 24)
                              else if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Varsayılan',
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              
              const Divider(height: 1),
              
              // Yeni kart ekle
              ListTile(
                leading: const Icon(Icons.add_card, color: Color(0xFFFFD700)),
                title: const Text('Yeni Kart Ekle', style: TextStyle(color: Colors.black)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (mounted) {
                    setState(() {
                      _selectedPaymentMethod = 'card';
                      _selectedCardId = null;
                    });
                  }
                  Future.delayed(const Duration(milliseconds: 250), () {
                    if (mounted) {
                      _showAddCardDialog();
                    }
                  });
                },
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showAddCardDialog() {
    final cardHolderController = TextEditingController();
    final cardNumberController = TextEditingController();
    final expiryController = TextEditingController();
    final cvvController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Kart Ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cardHolderController,
                decoration: const InputDecoration(
                  labelText: 'Kart Sahibi',
                  hintText: 'Ad Soyad',
                  prefixIcon: Icon(Icons.person),
                ),
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cardNumberController,
                decoration: const InputDecoration(
                  labelText: 'Kart Numarası',
                  hintText: '1234 5678 9012 3456',
                  prefixIcon: Icon(Icons.credit_card),
                ),
                keyboardType: TextInputType.number,
                maxLength: 19,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: expiryController,
                      decoration: const InputDecoration(
                        labelText: 'AA/YY',
                        hintText: '12/25',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      onChanged: (value) {
                        // Otomatik / ekle
                        if (value.length == 2 && !value.contains('/')) {
                          expiryController.text = '$value/';
                          expiryController.selection = TextSelection.fromPosition(
                            TextPosition(offset: expiryController.text.length),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: cvvController,
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        hintText: '123',
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      obscureText: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              cardHolderController.dispose();
              cardNumberController.dispose();
              expiryController.dispose();
              cvvController.dispose();
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Validasyon
              if (cardHolderController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen kart sahibi adını giriniz'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              if (cardNumberController.text.length < 16) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Kart numarası eksik'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // Kartı backend'e kaydet
              final fullCardNumber = cardNumberController.text.replaceAll(' ', '');
              final cardHolder = cardHolderController.text.trim();
              
              Navigator.pop(context);
              
              // Backend'e kaydet
              setState(() => _isProcessingPayment = true);
              
              try {
                final cardsApi = CustomerCardsApi();
                final result = await cardsApi.addCard(
                  cardNumber: fullCardNumber,
                  cardHolder: cardHolder,
                  expiryDate: expiryController.text,
                  cvv: cvvController.text,
                );
                
                if (result != null && result['success'] == true) {
                  // Kartları yeniden yükle
                  await _loadSavedCards();
                  
                  // Backend'den dönen kart ID'si
                  final newCardId = result['card']?['id']?.toString() ?? result['card_id']?.toString();
                  
                  setState(() {
                    _selectedPaymentMethod = 'card';
                    _selectedCardId = newCardId;
                  });
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Kart başarıyla kaydedildi!'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  throw Exception(result?['message'] ?? 'Kart kaydedilemedi');
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Kart kaydetme hatası: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                setState(() => _isProcessingPayment = false);
              }
              
              cardHolderController.dispose();
              cardNumberController.dispose();
              expiryController.dispose();
              cvvController.dispose();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _discountCodeController.dispose();
    super.dispose();
  }
}

