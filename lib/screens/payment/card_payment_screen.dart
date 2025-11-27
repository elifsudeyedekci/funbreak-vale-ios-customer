import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/payment_service.dart';

/// Kart ile Ödeme Ekranı
/// FunBreak Vale - Müşteri Uygulaması
///
/// @version 1.0.0
/// @date 2025-11-27

class CardPaymentScreen extends StatefulWidget {
  final int rideId;
  final int customerId;
  final double amount;
  final String paymentType; // ride_payment, cancellation_fee

  const CardPaymentScreen({
    Key? key,
    required this.rideId,
    required this.customerId,
    required this.amount,
    this.paymentType = 'ride_payment',
  }) : super(key: key);

  @override
  State<CardPaymentScreen> createState() => _CardPaymentScreenState();
}

class _CardPaymentScreenState extends State<CardPaymentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  bool _isLoading = false;
  bool _showWebView = false;
  String _acsHtml = '';
  String _cardType = 'unknown';

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  void _onCardNumberChanged(String value) {
    // Kart tipini belirle
    setState(() {
      _cardType = PaymentService.detectCardType(value);
    });
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Kart bilgilerini parse et
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final expiry = _expiryController.text.split('/');
      final expiryMonth = expiry[0];
      final expiryYear = expiry.length > 1 ? expiry[1] : '';
      final cvv = _cvvController.text;
      final cardHolder = _cardHolderController.text.toUpperCase();

      print('💳 Ödeme başlatılıyor...');
      print('   Ride ID: ${widget.rideId}');
      print('   Amount: ${widget.amount}');

      final result = await PaymentService.initiate3DPayment(
        rideId: widget.rideId,
        customerId: widget.customerId,
        amount: widget.amount,
        cardNumber: cardNumber,
        expiryMonth: expiryMonth,
        expiryYear: expiryYear,
        cvv: cvv,
        cardHolder: cardHolder,
        paymentType: widget.paymentType,
      );

      print('📦 Ödeme sonucu: ${result['success']}');

      if (result['success'] == true) {
        if (result['requires_3d'] == true && result['acs_html'] != null) {
          // 3D Secure sayfasını göster
          setState(() {
            _showWebView = true;
            _acsHtml = result['acs_html'];
          });
        } else {
          // Ödeme tamamlandı (3D gerektirmeyen durum - normalde olmaz)
          _showSuccessDialog();
        }
      } else {
        // Hata mesajını göster
        _showErrorDialog(result['message'] ?? 'Ödeme başlatılamadı');
      }
    } catch (e) {
      print('❌ Ödeme hatası: $e');
      _showErrorDialog('Bir hata oluştu: $e');
    } finally {
      if (mounted && !_showWebView) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleWebViewNavigation(String url) {
    print('🌐 WebView URL: $url');

    // Deep link kontrolü
    if (url.startsWith('funbreakvale://payment/success')) {
      _showSuccessDialog();
    } else if (url.startsWith('funbreakvale://payment/failed')) {
      final uri = Uri.parse(url);
      final error = uri.queryParameters['error'] ?? 'Ödeme başarısız';
      _showErrorDialog(Uri.decodeComponent(error));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ödeme Başarılı!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.amount.toStringAsFixed(2)} TL tutarındaki ödemeniz başarıyla tamamlandı.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(); // Dialog kapat
                Navigator.of(context).pop(true); // Ekranı kapat, başarılı dön
              },
              child: const Text(
                'Tamam',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    setState(() {
      _showWebView = false;
      _isLoading = false;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ödeme Başarısız',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Tekrar Dene',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTypeIcon() {
    IconData icon;
    Color color;

    switch (_cardType) {
      case 'visa':
        icon = Icons.credit_card;
        color = const Color(0xFF1A1F71);
        break;
      case 'mastercard':
        icon = Icons.credit_card;
        color = const Color(0xFFEB001B);
        break;
      case 'troy':
        icon = Icons.credit_card;
        color = const Color(0xFF00A9E0);
        break;
      default:
        icon = Icons.credit_card;
        color = Colors.grey;
    }

    return Icon(icon, color: color, size: 28);
  }

  @override
  Widget build(BuildContext context) {
    // 3D Secure WebView göster
    if (_showWebView && _acsHtml.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF111827),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('3D Secure Doğrulama'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _showWebView = false;
                _isLoading = false;
              });
            },
          ),
        ),
        body: WebViewWidget(
          controller: WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(
              NavigationDelegate(
                onNavigationRequest: (request) {
                  _handleWebViewNavigation(request.url);
                  return NavigationDecision.navigate;
                },
              ),
            )
            ..loadHtmlString(_acsHtml),
        ),
      );
    }

    // Kart bilgi formu
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Kart ile Ödeme'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tutar kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Ödenecek Tutar',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₺${widget.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.paymentType == 'cancellation_fee')
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'İptal Ücreti',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Kart Numarası
              Text(
                'Kart Numarası',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cardNumberController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                  _CardNumberFormatter(),
                ],
                decoration: InputDecoration(
                  hintText: '0000 0000 0000 0000',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1F2937),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildCardTypeIcon(),
                  ),
                ),
                onChanged: _onCardNumberChanged,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Kart numarası gerekli';
                  }
                  if (!PaymentService.isValidCardNumber(value)) {
                    return 'Geçersiz kart numarası';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Kart Sahibi
              Text(
                'Kart Sahibi',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cardHolderController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'AD SOYAD',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1F2937),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Kart sahibi adı gerekli';
                  }
                  if (value.length < 3) {
                    return 'Geçersiz isim';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Son Kullanma ve CVV
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Son Kullanma',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _expiryController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                            _ExpiryDateFormatter(),
                          ],
                          decoration: InputDecoration(
                            hintText: 'AA/YY',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF1F2937),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Gerekli';
                            }
                            final parts = value.split('/');
                            if (parts.length != 2) {
                              return 'AA/YY formatında girin';
                            }
                            if (!PaymentService.isValidExpiry(parts[0], parts[1])) {
                              return 'Geçersiz tarih';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CVV',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cvvController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: InputDecoration(
                            hintText: '***',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF1F2937),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Gerekli';
                            }
                            if (!PaymentService.isValidCvv(value)) {
                              return 'Geçersiz';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Güvenlik notu
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '3D Secure ile Güvenli Ödeme',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kart bilgileriniz güvenli şekilde işlenir ve saklanmaz.',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Ödeme butonu
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isLoading ? null : _processPayment,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          '₺${widget.amount.toStringAsFixed(2)} Öde',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // VakıfBank logosu
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user, color: Colors.grey[600], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'VakıfBank Sanal POS ile güvende',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kart numarası formatlayıcı (4'lü gruplar)
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Son kullanma tarihi formatlayıcı (AA/YY)
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      if (i == 2) {
        buffer.write('/');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

