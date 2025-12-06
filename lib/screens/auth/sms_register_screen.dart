import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:io';
import 'sms_verification_screen.dart';

class SmsRegisterScreen extends StatefulWidget {
  final String? prefilledPhone;
  
  const SmsRegisterScreen({Key? key, this.prefilledPhone}) : super(key: key);

  @override
  State<SmsRegisterScreen> createState() => _SmsRegisterScreenState();
}

class _SmsRegisterScreenState extends State<SmsRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  // 📋 YASAL SÖZLEŞME ONAYLARI
  bool _kvkkAccepted = false;
  bool _userAgreementAccepted = false;
  bool _commercialCommunicationAccepted = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledPhone != null) {
      String phone = widget.prefilledPhone!;
      // Sadece rakamları al
      phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      // 90 ile başlıyorsa kaldır (ülke kodu)
      if (phone.startsWith('90') && phone.length >= 12) {
        phone = phone.substring(2);
      }
      // Başındaki 0'ı kaldır (prefixText zaten 0 gösteriyor)
      if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }
      _phoneController.text = phone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Telefon numarası formatla
  String _formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleaned.startsWith('90') && cleaned.length == 12) {
      cleaned = '0' + cleaned.substring(2);
    }
    
    // 5 ile başlıyorsa başına 0 ekle
    if (cleaned.startsWith('5') && cleaned.length == 10) {
      cleaned = '0' + cleaned;
    }
    
    return cleaned;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    // ✅ YASAL SÖZLEŞME KONTROL - ZORUNLU!
    if (!_kvkkAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ KVKK Aydınlatma Metni\'ni kabul etmelisiniz!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    if (!_userAgreementAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Kullanıcı Sözleşmesi\'ni kabul etmelisiniz!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final phone = _formatPhone(_phoneController.text.trim());
      
      print('📝 KAYIT API ÇAĞRILIYOR...');
      print('   İsim: ${_nameController.text.trim()}');
      print('   Telefon: $phone');
      print('   Email: ${_emailController.text.trim()}');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': _nameController.text.trim(),
          'phone': phone,
          'email': _emailController.text.trim(),
          'type': 'customer',
        }),
      ).timeout(const Duration(seconds: 15));

      print('📡 KAYIT API RESPONSE:');
      print('   Status: ${response.statusCode}');
      print('   Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      // Response boş mu kontrol et
      if (response.body.isEmpty) {
        throw Exception('Sunucudan yanıt alınamadı');
      }

      final data = json.decode(response.body);
      
      // Data null mı kontrol et
      if (data == null) {
        throw Exception('Geçersiz sunucu yanıtı');
      }

      print('✅ API Yanıt alındı: $data');

      if (data['success'] == true) {
        // ✅ Kayıt başarılı - YASAL LOGLARI KAYDET
        if (data['user'] == null || data['user']['id'] == null) {
          throw Exception('Kullanıcı bilgisi alınamadı');
        }
        
        final userId = int.parse(data['user']['id'].toString());
        
        print('✅ Kullanıcı oluşturuldu - ID: $userId');
        
        // 📝 SÖZLEŞME LOGLARINI KAYDET (Mahkeme delili)
        await _logLegalConsents(userId, phone);
        
        // SMS doğrulama kodunu gönder
        print('📱 SMS kodu gönderiliyor...');
        final smsResponse = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/send_verification_code.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'phone': phone,
            'user_id': userId,
            'type': 'customer',
          }),
        );

        final smsData = json.decode(smsResponse.body);
        
        print('📡 SMS API Yanıt: $smsData');

        if (smsData['success'] == true) {
          if (mounted) {
            print('✅ SMS gönderildi, doğrulama ekranına yönlendiriliyor...');
            // Doğrulama ekranına git - İsim ve Email'i de gönder
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => SmsVerificationScreen(
                  phone: phone,
                  userId: userId,
                  userType: 'customer',
                  isLogin: false,
                  userName: _nameController.text.trim(), // ✅ İsim ekle
                  userEmail: _emailController.text.trim(), // ✅ Email ekle
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(smsData['message'] ?? 'SMS gönderilemedi'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          String errorMsg = 'Kayıt başarısız';
          if (data['message'] != null) {
            errorMsg = data['message'].toString();
          }
          
          print('❌ Kayıt hatası: $errorMsg');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ KAYIT HATASI: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        String errorMessage = 'Bağlantı hatası';
        
        if (e.toString().contains('SocketException')) {
          errorMessage = 'İnternet bağlantınızı kontrol edin';
        } else if (e.toString().contains('TimeoutException')) {
          errorMessage = 'İşlem zaman aşımına uğradı, tekrar deneyin';
        } else if (e.toString().contains('FormatException')) {
          errorMessage = 'Sunucudan geçersiz yanıt alındı';
        } else if (e is Exception) {
          errorMessage = e.toString().replaceAll('Exception: ', '');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Tekrar Dene',
              textColor: Colors.white,
              onPressed: () {
                _register();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 📝 YASAL SÖZLEŞME LOGLARINI KAYDET
  Future<void> _logLegalConsents(int userId, String phone) async {
    try {
      print('📝 YASAL LOGLAR KAYDEDILIYOR...');
      
      // Cihaz bilgilerini topla
      final deviceInfo = await _collectDeviceInfo();
      
      // Konum bilgisi topla (izin varsa)
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print('⚠️ Konum alınamadı: $e');
      }
      
      // Her sözleşme için ayrı log kaydet
      final consentsToLog = [
        if (_kvkkAccepted) {
          'type': 'kvkk',
          'text': _getKVKKText(),
          'summary': 'KVKK Aydınlatma Metni - Kişisel verilerin işlenmesi',
        },
        if (_userAgreementAccepted) {
          'type': 'user_agreement',
          'text': _getUserAgreementText(),
          'summary': 'Kullanıcı Sözleşmesi - Hizmet kullanım şartları',
        },
        if (_commercialCommunicationAccepted) {
          'type': 'commercial_communication',
          'text': _getCommercialText(),
          'summary': 'Ticari Elektronik İleti İzni - Kampanya ve duyurular',
        },
      ];
      
      for (var consent in consentsToLog) {
        print('📝 SÖZLEŞME LOG API ÇAĞRILIYOR:');
        print('   Type: ${consent['type']}');
        print('   User ID: $userId');
        print('   Text Length: ${(consent['text'] as String).length}');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'user_type': 'customer',
            'consent_type': consent['type'],
            'consent_text': consent['text'],
            'consent_summary': consent['summary'],
            'consent_version': '1.0',
            'ip_address': deviceInfo['ip_address'],
            'user_agent': deviceInfo['user_agent'],
            'device_fingerprint': deviceInfo['device_fingerprint'],
            'platform': deviceInfo['platform'],
            'os_version': deviceInfo['os_version'],
            'app_version': deviceInfo['app_version'],
            'device_model': deviceInfo['device_model'],
            'device_manufacturer': deviceInfo['device_manufacturer'],
            'latitude': position?.latitude,
            'longitude': position?.longitude,
            'location_accuracy': position?.accuracy,
            'location_timestamp': position != null ? DateTime.now().toIso8601String() : null,
            'language': 'tr',
          }),
        ).timeout(const Duration(seconds: 10));
        
        print('📡 SÖZLEŞME LOG API RESPONSE:');
        print('   Status: ${response.statusCode}');
        print('   Body: ${response.body}');
        
        final apiData = jsonDecode(response.body);
        if (apiData['success'] == true) {
          print('✅ Sözleşme ${consent['type']} loglandı - Log ID: ${apiData['log_id']}');
        } else {
          print('❌ Sözleşme ${consent['type']} log hatası: ${apiData['message']}');
        }
      }
      
      print('✅ ${consentsToLog.length} sözleşme YASAL OLARAK loglandı - Mahkeme delili kaydedildi!');
    } catch (e) {
      print('⚠️ Yasal log hatası: $e (Kayıt tamamlandı ama log kaydedilemedi)');
    }
  }
  
  // CİHAZ BİLGİLERİNİ TOPLA
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    
    final fingerprint = DateTime.now().millisecondsSinceEpoch.toString() + 
                       '_' + 
                       (_emailController.text.hashCode.toString());
    
    return {
      'platform': platform,
      'os_version': Platform.operatingSystemVersion,
      'app_version': '1.0.0',
      'device_model': 'auto',
      'device_manufacturer': 'auto',
      'device_fingerprint': fingerprint,
      'user_agent': 'FunBreak Customer App/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto',
    };
  }

  // SÖZLEŞME DIALOG'LARI
  void _showKVKKDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('KVKK Aydınlatma Metni'),
        content: SingleChildScrollView(
          child: Text(_getKVKKText(), style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _kvkkAccepted = true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Kabul Ediyorum', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
  
  void _showUserAgreementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullanıcı Sözleşmesi'),
        content: SingleChildScrollView(
          child: Text(_getUserAgreementText(), style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _userAgreementAccepted = true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Kabul Ediyorum', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
  
  void _showCommercialDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ticari Elektronik İleti İzni'),
        content: SingleChildScrollView(
          child: Text(_getCommercialText(), style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _commercialCommunicationAccepted = true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Kabul Ediyorum', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
  
  // SÖZLEŞME METİNLERİ - YASAL GEÇERLİLİK İÇİN TAM METİN!
  String _getKVKKText() {
    return '''===============================================================================

FUNBREAK VALE
YOLCULAR İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK 
AYDINLATMA METNİ

===============================================================================

VERİ SORUMLUSU BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sitesi        : www.funbreakvale.com

===============================================================================

GİRİŞ

Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul 
adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJİ 
LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") olarak işbu Aydınlatma Metni 
("Aydınlatma Metni") aracılığı ile 6698 sayılı Kişisel Verilerin Korunması 
Kanunu ("KVKK") 10. madde ve Kişisel Verileri Koruma Kurumu'nun Aydınlatma 
Yükümlülüğünün Yerine Getirilmesinde Uyulacak Usul ve Esaslar Hakkında Tebliği 
kapsamında kişisel verilerinizin hangi amaçla işleneceğini; hangi amaçlarla 
kimlere aktarılacağını, toplama yöntemini ve hukuki sebebi, kişisel 
verilerinize ilişkin haklarınızı ve bu hakları nasıl kullanabileceğinizi 
bildirmekle yükümlüyüz.

===============================================================================

A. KİŞİSEL VERİLERİN KORUNMASI KANUNU ÇERÇEVESİNDE TANIMLAR

İşbu Aydınlatma Metni'nde geçen:

Yolcu / Yolcular: FunBreak Vale'nin mobil uygulama üzerinden özel şoför ve 
vale hizmeti sağladığı kullanıcıları ifade eder.

Kişisel Veri: Kimliği belirli veya belirlenebilir gerçek kişiye ilişkin her 
türlü bilgiyi ifade eder.

Özel Nitelikli Kişisel Veri: Kişilerin ırkı, etnik kökeni, siyasi düşüncesi, 
felsefi inancı, dini, mezhebi veya diğer inançları, kılık ve kıyafeti, dernek, 
vakıf ya da sendika üyeliği, sağlığı, cinsel hayatı, ceza mahkûmiyeti ve 
güvenlik tedbirleriyle ilgili verileri ile biyometrik ve genetik verileri 
ifade eder.

Kişisel Verilerin İşlenmesi: Kişisel verilerin tamamen veya kısmen otomatik 
olan ya da herhangi bir veri kayıt sisteminin parçası olmak kaydıyla otomatik 
olmayan yollarla elde edilmesi, kaydedilmesi, depolanması, muhafaza edilmesi, 
değiştirilmesi, yeniden düzenlenmesi, açıklanması, aktarılması, devralınması, 
elde edilebilir hâle getirilmesi, sınıflandırılması ya da kullanılmasının 
engellenmesi gibi veriler üzerinde gerçekleştirilen her türlü işlemi ifade 
eder.

Veri Sorumlusu: Kişisel verilerin işleme amaçlarını ve vasıtalarını 
belirleyen, veri kayıt sisteminin kurulmasından ve yönetilmesinden sorumlu 
olan gerçek veya tüzel kişiyi ifade eder. FunBreak Vale, işbu Aydınlatma 
Metni kapsamında Veri Sorumlusu sıfatına sahiptir.

Veri İşleyen: Veri sorumlusunun verdiği yetkiye dayanarak onun adına kişisel 
verileri işleyen gerçek veya tüzel kişiyi ifade eder.

İlgili Kişi: Kişisel verisi işlenen gerçek kişiyi (Yolcu) ifade eder.

===============================================================================

B. VERİ SORUMLUSU

Veri Sorumlusu; kişisel verilerin işleme amaçlarını ve vasıtalarını 
belirleyen, veri kayıt sisteminin kurulmasından ve yönetilmesinden sorumlu 
olan gerçek veya tüzel kişidir.

FunBreak Vale, veri sorumlusu sıfatıyla gerekli tüm teknik ve idari 
tedbirleri almak suretiyle kişisel verilerinizi; Türkiye Cumhuriyeti 
Anayasası, uluslararası sözleşmeler ve 6698 sayılı Kişisel Verilerin Korunması 
Kanunu çerçevesinde aşağıdaki ilkelere uygun olarak işler:

• Hukuka ve dürüstlük kurallarına uygun olma,
• Doğru ve gerektiğinde güncel olma,
• Belirli, açık ve meşru amaçlar için işlenme,
• İşleme amaçlarıyla bağlantılı, sınırlı ve ölçülü olma,
• İlgili mevzuatta öngörülen veya işlendikleri amaç için gerekli olan süre 
  kadar muhafaza edilme.

===============================================================================

C. KİŞİSEL VERİLERİN HANGİ AMAÇLA İŞLENDİĞİ VE İŞLENEN KİŞİSEL VERİ 
   KATEGORİLERİ

FunBreak Vale, Yolcu'lara ait kişisel verileri aşağıdaki amaçlarla ve 
kategorilerde işlemektedir:

-------------------------------------------------------------------------------
1. KİMLİK BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- T.C. Kimlik Numarası
- Ad, Soyad
- Doğum Tarihi
- Cinsiyet
- Fotoğraf (profil resmi - isteğe bağlı)

İşlenme Amacı:
- Yolcu'nun kimliğinin tespiti ve doğrulanması
- Hukuki sözleşmelerin tarafı olabilmesi
- Yasal yükümlülüklerin yerine getirilmesi
- Platform güvenliğinin sağlanması
- Profil oluşturulması
- Vale ile güvenli eşleştirme

Hukuki Sebep:
- Sözleşmenin kurulması ve ifası
- Kanuni yükümlülük
- Meşru menfaat

-------------------------------------------------------------------------------
2. İLETİŞİM BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Cep Telefonu Numarası
- E-posta Adresi
- İkametgah Adresi (isteğe bağlı)
- Kayıtlı Adresler (sık kullanılan yerler)

İşlenme Amacı:
- Yolcu ile iletişim kurulması
- SMS ve e-posta bildirimleri gönderimi
- Yolculuk durumu bilgilendirmeleri
- Kampanya ve duyuru gönderimi
- Ödeme ve fatura süreçleri
- Sözleşme tebligatları
- Acil durum iletişimi

Hukuki Sebep:
- Sözleşmenin kurulması ve ifası
- Meşru menfaat
- Açık rıza (ticari elektronik ileti için)

-------------------------------------------------------------------------------
3. FİNANSAL BİLGİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Kredi Kartı Bilgisi (ilk 6 hane + son 2 hane)
- IBAN Bilgisi (havale ödemesi için)
- Ödeme Geçmişi
- Yolculuk Ücretleri
- İndirim Kodları ve İndirim Tutarları
- Bekleyen Ödeme Tutarları
- İptal Ücretleri (varsa)

İşlenme Amacı:
- Yolculuk bedellerinin tahsili
- Mali süreçlerin yürütülmesi
- Muhasebe ve finans işlemleri
- Fatura düzenleme
- İndirim kodlarının uygulanması
- Ödeme takibi ve raporlama
- İade süreçlerinin yönetimi

Hukuki Sebep:
- Sözleşmenin ifası
- Kanuni yükümlülük
- Meşru menfaat

-------------------------------------------------------------------------------
4. MÜŞTERİ İŞLEM BİLGİSİ (YOLCULUK VERİLERİ)
-------------------------------------------------------------------------------
İşlenen Veriler:
- Yolculuk Geçmişi
- Toplam Yolculuk Sayısı
- Alış Noktası (Pickup Location)
- Varış Noktası (Destination)
- Bırakış Noktası (Dropoff Location - gerçekleşen)
- Yolculuk Rotası (Route Tracking)
- Bekleme Noktaları (Waiting Points)
- GPS Konum Verileri (Yolcu'nun konumu - seçim sırasında)
- Yolculuk Mesafesi (KM)
- Yolculuk Süreleri
- Bekleme Süreleri
- Hizmet Türü (Anında Vale, Saatlik Paket, Rezervasyon)
- Yolculuk Durumu (pending, accepted, in_progress, completed, cancelled)

İşlenme Amacı:
- Yolculuk takibi ve yönetimi
- Vale ile Yolcu eşleştirmesi
- Hizmet kalitesinin izlenmesi
- Mesafe bazlı ücretlendirme hesaplamaları
- Güvenlik ve izleme
- Rota optimizasyonu
- Olası uyuşmazlıklarda delil
- Hizmet geliştirme ve iyileştirme

Hukuki Sebep:
- Sözleşmenin ifası
- Meşru menfaat
- Hukuki yükümlülük

-------------------------------------------------------------------------------
5. ARAÇ BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Araç Plakası
- Araç Markası ve Modeli
- Araç Rengi
- Araç Yılı
- Araç Ruhsat Bilgisi (isteğe bağlı)
- Sigorta Bilgisi (varsa)

İşlenme Amacı:
- Vale'nin doğru aracı tanıması
- Hizmetin güvenli sunulması
- Araç uygunluğunun kontrolü
- Sigorta durumunun tespiti

Hukuki Sebep:
- Sözleşmenin ifası
- Meşru menfaat

-------------------------------------------------------------------------------
6. DEĞERLENDIRME VE YORUM BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Vale'ye Verilen Puanlar (1-5 yıldız)
- Yorum Metinleri
- Değerlendirme Tarihi
- Şikayet ve İtiraz Kayıtları
- Memnuniyet Anketi Cevapları (varsa)

İşlenme Amacı:
- Hizmet kalitesinin izlenmesi
- Vale performansının değerlendirilmesi
- Müşteri memnuniyetinin artırılması
- Şikayetlerin çözülmesi
- Platform iyileştirmesi

Hukuki Sebep:
- Sözleşmenin ifası
- Meşru menfaat
- Açık rıza

-------------------------------------------------------------------------------
7. LOKASYON / KONUM BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Canlı GPS Konumu (Vale çağrılırken)
- Alış ve Varış Adresleri
- Kayıtlı Adresler (Ev, İş, Sık Kullanılanlar)
- Yer İşaretleri
- Konum Geçmişi

İşlenme Amacı:
- Vale ile Yolcu eşleştirmesi
- En yakın Vale'nin bulunması
- Yolculuk rotasının belirlenmesi
- Mesafe hesaplaması
- Hızlı adres seçimi (kayıtlı adresler)
- Kullanıcı deneyiminin iyileştirilmesi

Hukuki Sebep:
- Açık rıza
- Sözleşmenin ifası
- Meşru menfaat

NOT: Yolcu'nun canlı konumu sadece Vale çağırma sırasında alınır. Yolculuk 
sırasında Vale'nin konumu takip edilir, Yolcu'nun konumu değil.

-------------------------------------------------------------------------------
8. CİHAZ BİLGİSİ
-------------------------------------------------------------------------------
İşlenen Veriler:
- Cihaz Kimliği (Device ID)
- İşletim Sistemi (Android/iOS)
- Uygulama Versiyonu
- IP Adresi
- Tarayıcı Bilgisi (web kullanımında)
- Cihaz Modeli
- Ekran Çözünürlüğü
- Dil Tercihi

İşlenme Amacı:
- Teknik destek sağlanması
- Uygulama performansının izlenmesi
- Güvenlik kontrolü
- Çoklu oturum yönetimi
- Hata ayıklama
- Kullanıcı deneyimi optimizasyonu

Hukuki Sebep:
- Sözleşmenin ifası
- Meşru menfaat

-------------------------------------------------------------------------------
9. MESAJLAŞMA VE İLETİŞİM KAYITLARI
-------------------------------------------------------------------------------
İşlenen Veriler:
- Vale ile Mesajlaşma İçeriği
- Destek Talebi Kayıtları
- Şikayet ve İtiraz Metinleri
- Müşteri Hizmetleri Görüşme Kayıtları
- Köprü Arama Sistemi Ses Kayıtları
- SMS İçerikleri (doğrulama kodları vb.)

İşlenme Amacı:
- Hizmet kalitesinin izlenmesi
- Uyuşmazlık çözümü
- Delil oluşturma
- Müşteri memnuniyeti takibi
- Destek taleplerinin yanıtlanması

Hukuki Sebep:
- Sözleşmenin ifası
- Hukuki yükümlülük
- Meşru menfaat

-------------------------------------------------------------------------------
10. ÇEREZ VERİLERİ
-------------------------------------------------------------------------------
İşlenen Veriler:

a) ZORUNLU ÇEREZLER
   - Oturum yönetimi
   - Kimlik doğrulama
   - Güvenlik token'ları
   - Yük dengeleme

b) FONKSİYONEL ÇEREZLER
   - Kullanıcı tercihleri
   - Dil seçimi
   - Konum ayarları
   - Tema tercihleri
   - Kayıtlı adresler

c) ANALİTİK ÇEREZLER
   - Google Analytics
   - Kullanıcı davranış analizi
   - Sayfa performans ölçümü
   - Hata takibi

d) REKLAM VE PAZARLAMA ÇEREZLERİ
   - Hedefli reklamlar
   - Yeniden pazarlama
   - Sosyal medya entegrasyonları
   - Kampanya takibi

İşlenme Amacı:
- Web ve mobil uygulama işlevselliği
- Kullanıcı deneyimi iyileştirme
- Performans ölçümü
- Pazarlama ve reklam optimizasyonu

Hukuki Sebep:
- Zorunlu çerezler için: Sözleşmenin ifası, Meşru menfaat
- Diğer çerezler için: Açık rıza

ÇEREZ YÖNETİMİ:
Kullanıcı, tarayıcı ayarları üzerinden çerezleri yönetebilir, silebilir veya 
engelleyebilir. Mobil uygulamada: Ayarlar > Gizlilik > Çerez Ayarları

NOT: Zorunlu çerezlerin engellenmesi durumunda uygulamanın bazı işlevleri 
çalışmayabilir.

===============================================================================

D. KİŞİSEL VERİLERİN TOPLANMA YÖNTEMİ

Kişisel verileriniz, aşağıdaki yöntemlerle toplanmaktadır:

1. KAYIT VE ÜYELİK FORMLARI
   - Web sitesi üzerinden kayıt formu
   - Mobil uygulama kayıt ekranı
   - Sosyal medya üzerinden kayıt (Google, Apple, Facebook girişi)

2. MOBİL UYGULAMA KULLANIMI
   - GPS konum verileri (izin verilen durumlarda)
   - Yolculuk kayıtları (otomatik)
   - Mesajlaşma içerikleri
   - Uygulama içi işlemler
   - Arama kayıtları

3. WEB SİTESİ KULLANIMI
   - Form doldurma
   - Çerez verileri
   - Sayfa ziyaretleri

4. SİSTEM KAYITLARI
   - Sunucu log kayıtları
   - Veritabanı kayıtları
   - API çağrı kayıtları

5. MÜŞTERİ HİZMETLERİ
   - Telefon görüşmeleri
   - E-posta iletişimi
   - Canlı destek yazışmaları
   - Şikayet ve öneri formları

6. ÜÇÜNCÜ TARAF ENTEGRASYONLAR
   - Ödeme sistemleri (kart bilgisi doğrulama)
   - SMS servisleri (doğrulama kodları)
   - Harita ve navigasyon servisleri (Google Maps, Yandex Maps)
   - Sosyal medya entegrasyonları

===============================================================================

E. KİŞİSEL VERİLERİN İŞLENME AMAÇLARI

FunBreak Vale, Yolcu'lara ait kişisel verileri aşağıdaki amaçlarla işler:

1. HİZMET SUNUMU
   - Mobil uygulama aracılığıyla kullanıcılara hizmet sunmak
   - Vale ile Yolcu eşleştirmesi yapmak
   - Yolculuk takibi sağlamak
   - Rezervasyon yönetimi

2. İLETİŞİM
   - Kullanıcılar ile iletişime geçmek
   - Yolculuk durumu hakkında bilgilendirme
   - SMS ve e-posta bildirimleri göndermek

3. ÖDEME VE FİNANS
   - Ödemelere ilişkin finans ve muhasebe süreçlerini yürütmek
   - Fatura düzenleme
   - İndirim kodlarının uygulanması
   - İade işlemlerinin yönetimi

4. PAZARLAMA VE REKLAM
   - Hizmetlerin tanıtımını sağlamak
   - Reklam ve kampanya süreçlerini yürütmek
   - Kişiselleştirilmiş öneriler sunmak
   - Promosyon ve indirim kodları göndermek

5. HİZMET GELİŞTİRME
   - Kullanıcı geri bildirimlerine göre ürün ve hizmetleri iyileştirmek
   - Kullanıcı deneyimini geliştirmek
   - Yeni özellikler eklemek

6. KİŞİSELLEŞTİRME
   - Hizmetleri kullanıcıların tercih, kullanım alışkanlıkları ve ilgi 
     alanlarına göre özelleştirmek
   - Sık kullanılan adresler önerme
   - Favori Vale'leri gösterme

7. GÜVENLİK VE TEKNİK
   - Mobil uygulamadaki sistemsel sorunları tanımlamak ve gidermek
   - Bilgi güvenliği süreçlerini yürütmek
   - Dolandırıcılık tespiti ve önleme
   - Hesap güvenliği sağlama

8. PERFORMANS İZLEME
   - Tanımlama teknolojileri vasıtasıyla kullanıcı deneyimlerini ölçümlemek
   - Mobil uygulama performansını geliştirmek
   - Hata takibi ve raporlama

9. YASAL YÜKÜMLÜLÜKLER
   - Yasal düzenlemelere uyum
   - Yetkili mercilere bilgi verme
   - Mahkeme kararlarının yerine getirilmesi
   - Vergi mevzuatına uyum

10. MÜŞTERİ MEMNUNİYETİ
    - Talep ve şikayetleri sonuçlandırmak
    - Geri bildirimleri değerlendirmek
    - Hizmet kalitesini artırmak

===============================================================================

F. KİŞİSEL VERİLERİN AKTARILMASI

Kişisel verileriniz, aşağıdaki amaçlarla ve alıcılara aktarılabilir:

-------------------------------------------------------------------------------
1. VALE'LERE (SÜRÜCÜLERE) AKTARIM
-------------------------------------------------------------------------------
Aktarılan Veriler:
- Ad, Soyad
- Profil Fotoğrafı (varsa)
- Cep Telefonu Numarası (köprü arama sistemi için gizli)
- Alış ve Varış Adresleri
- Yolcu Puanı (ortalama)

Aktarım Amacı:
- Vale ile Yolcu eşleştirmesi
- Hizmetin güvenli sunumu
- İletişim kurulması
- Adres bilgisi paylaşımı

-------------------------------------------------------------------------------
2. GRUP ŞİRKETLERİ VE İŞTİRAKLERE AKTARIM
-------------------------------------------------------------------------------
Aktarılabilecek Tüm Veriler:
- Kimlik, iletişim, finansal, işlem bilgileri

Aktarım Amacı:
- Ortak hizmetlerin yürütülmesi
- Teknik destek
- Veri analitiği
- Raporlama

-------------------------------------------------------------------------------
3. HİZMET SAĞLAYICILARA AKTARIM
-------------------------------------------------------------------------------
Alıcılar:
- Bulut sunucu sağlayıcıları (AWS, Google Cloud vb.)
- SMS servis sağlayıcıları
- Ödeme altyapısı sağlayıcıları
- Harita ve konum servisleri (Google Maps, Yandex Maps)
- Çağrı merkezi ve köprü arama servisleri (NetGSM)
- E-posta gönderim servisleri
- Analitik araçlar (Google Analytics)

Aktarılan Veriler:
- Hizmet gerektirdiği ölçüde ilgili veriler

Aktarım Amacı:
- Teknik altyapı sağlanması
- Hizmet sürdürülebilirliği
- İletişim altyapısı
- Ödeme işlemleri

-------------------------------------------------------------------------------
4. HUKUK MÜŞAVİRLERİ VE DANIŞMANLARA AKTARIM
-------------------------------------------------------------------------------
Alıcılar:
- Avukatlar
- Mali müşavirler
- Bağımsız denetim firmaları

Aktarılan Veriler:
- Yasal süreç gerektirdiği veriler

Aktarım Amacı:
- Hukuki danışmanlık
- Dava süreçleri
- Mali denetim
- Yasal yükümlülükler

-------------------------------------------------------------------------------
5. KAMU KURUM VE KURULUŞLARINA AKTARIM
-------------------------------------------------------------------------------
Alıcılar:
- Emniyet Genel Müdürlüğü
- Mahkemeler
- Savcılıklar
- Vergi Dairesi
- İçişleri Bakanlığı
- Tüketici Hakem Heyetleri
- Kişisel Verileri Koruma Kurumu

Aktarılan Veriler:
- Yasal talep kapsamındaki tüm veriler

Aktarım Amacı:
- Kanuni yükümlülük
- Mahkeme kararları
- Resmi talep ve soruşturmalar
- Tüketici şikayetleri

-------------------------------------------------------------------------------
6. YURT DIŞINA AKTARIM
-------------------------------------------------------------------------------
FunBreak Vale, kişisel verilerinizi yurt dışına aktarabilir.

YURT DIŞINA AKTARILABİLECEK VERİLER:
• Kimlik bilgileri
• İletişim bilgileri
• Konum verileri
• İşlem geçmişi
• Cihaz bilgileri

YURT DIŞINA AKTARIM NEDENLERİ:
• Bulut sunucu hizmetlerinin kullanılması (AWS, Google Cloud vb.)
• Teknik altyapı sağlanması
• Veri yedekleme ve saklama
• Analitik hizmetler (Google Analytics, Firebase)
• Harita ve navigasyon servisleri

YURT DIŞINA AKTARIM KOŞULLARI:
Yurt dışına aktarım, KVKK'nın 9. maddesi uyarınca aşağıdaki koşullardan 
birinin varlığı halinde gerçekleştirilir:

a) İlgili kişinin (Yolcu'nun) açık rızası
b) Yeterli korumanın bulunduğu ülkelere aktarım
c) Yeterli koruma bulunmayan ülkelerde, Türkiye'deki ve ilgili yabancı 
   ülkedeki veri sorumlularının yeterli bir korumayı yazılı olarak taahhüt 
   ettiği ve Kurul'un izninin bulunması

===============================================================================

G. KİŞİSEL VERİ SAHİBİNİN HAKLARI (KVKK MADDE 11)

KVKK'nın 11. maddesi uyarınca, kişisel veri sahibi olarak aşağıdaki haklara 
sahipsiniz:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme,

b) Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme,

c) Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp 
   kullanılmadığını öğrenme,

d) Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü 
   kişileri bilme,

e) Kişisel verilerinizin eksik veya yanlış işlenmiş olması hâlinde bunların 
   düzeltilmesini isteme,

f) KVKK'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel 
   verilerinizin silinmesini veya yok edilmesini isteme,

g) (d) ve (e) bentleri uyarınca yapılan işlemlerin, kişisel verilerin 
   aktarıldığı üçüncü kişilere bildirilmesini isteme,

h) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz 
   edilmesi suretiyle kişinin kendisi aleyhine bir sonucun ortaya çıkmasına 
   itiraz etme,

ı) Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara 
   uğramanız hâlinde zararın giderilmesini talep etme.

===============================================================================

H. HAKLARIN KULLANILMASI - BAŞVURU YÖNTEMİ

Yukarıda belirtilen haklarınızı kullanmak için aşağıdaki yöntemlerle 
başvurabilirsiniz:

1. YAZILI BAŞVURU (KİMLİK TESPİTİ İLE)

Adres:
FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22
Ümraniye/İstanbul

Başvurunuzda:
- Ad, Soyad
- T.C. Kimlik No
- Tebligata esas açık adres
- Telefon ve e-posta
- Talep konusu

bilgilerini belirtiniz ve kimliğinizi ispatlayıcı belge (nüfus cüzdanı 
fotokopisi vb.) ekleyiniz.

2. GÜVENLİ ELEKTRONİK İMZA İLE

E-posta: info@funbreakvale.com
(Güvenli elektronik imza veya mobil imza ile)

3. BAŞVURU FORMU İLE

Web sitesi: www.funbreakvale.com/kvkk-basvuru
Mobil Uygulama: Ayarlar > KVKK > Başvuru Yap

4. NOTER ARACILIĞI İLE

Noter kanalıyla yapılacak başvurular kabul edilir.

-------------------------------------------------------------------------------
BAŞVURU SÜRECİ
-------------------------------------------------------------------------------

1. Başvurunuz en geç 30 (otuz) gün içinde değerlendirilir.

2. Başvurunun reddedilmesi halinde red gerekçesi yazılı olarak bildirilir.

3. Başvurunun kabul edilmesi halinde gereği yerine getirilir.

4. İşlemin maliyet gerektirmesi halinde, Kişisel Verileri Koruma Kurulu 
   tarafından belirlenen tarifedeki ücret talep edilebilir (2025 yılı için 
   maksimum 200 TL).

5. Başvurunuzun FunBreak Vale'ye ulaşmasından itibaren 30 gün içinde 
   cevaplandırılacaktır.

===============================================================================

I. KİŞİSEL VERİLERİN SAKLANMA SÜRESİ

Kişisel verileriniz, işleme amacının gerektirdiği süre boyunca ve yasal 
saklama yükümlülükleri çerçevesinde saklanır:

- Kimlik ve İletişim Bilgileri: Üyelik süresi + 10 yıl
- Finansal Bilgiler: 10 yıl (Vergi Usul Kanunu)
- Yolculuk Kayıtları: 5 yıl
- GPS/Konum Verileri: 2 yıl
- Mesajlaşma Kayıtları: 2 yıl
- Değerlendirme ve Yorumlar: 3 yıl
- Araç Bilgileri: Üyelik süresi + 3 yıl
- Şikayet ve İtiraz Kayıtları: 5 yıl
- Çerez Verileri: 6 ay - 2 yıl arası (türüne göre)

Saklama sürelerinin sona ermesi halinde kişisel verileriniz:
- Silinir
- Yok edilir
- Anonim hale getirilir

===============================================================================

J. VERİ GÜVENLİĞİ

FunBreak Vale, kişisel verilerinizin güvenliğini sağlamak için gerekli teknik 
ve idari tedbirleri almaktadır:

TEKNİK TEDBİRLER:
- SSL/TLS şifreleme (256-bit)
- Güvenlik duvarı (Firewall)
- Veri yedekleme sistemleri (günlük)
- Erişim loglarının tutulması
- Şifreli veri saklama
- DDoS koruma
- Güvenlik güncellemeleri
- Penetrasyon testleri

İDARİ TEDBİRLER:
- Personel eğitimleri
- Gizlilik sözleşmeleri
- Erişim yetkilendirmesi
- Veri işleme politikaları
- Düzenli güvenlik denetimleri
- Veri ihlali müdahale planı

ÖDEME GÜVENLİĞİ:
- PCI DSS standartlarına uyum
- Kart bilgilerinin şifreli saklanması (sadece ilk 6 + son 2 hane)
- 3D Secure doğrulama
- Güvenli ödeme altyapısı

===============================================================================

K. ÜÇÜNCÜ TARAF WEB SİTELERİ VE UYGULAMALAR

FunBreak Vale üzerinden 3. kişi internet siteleri veya mobil uygulamalara 
verilen linkler ile ilgili olarak kullanıcılar, bu sitelerin gizlilik 
politikalarının farklı olabileceğini bilmelidir.

FunBreak Vale, üçüncü taraf sitelerin gizlilik uygulamalarından veya 
içeriklerinden sorumlu değildir.

Üçüncü taraf entegrasyonlar:
- Google Maps / Yandex Maps (navigasyon)
- SMS servis sağlayıcıları
- Ödeme altyapı sağlayıcıları (kart işlemleri)
- Bulut sunucu hizmetleri
- Analitik araçlar (Google Analytics, Firebase)
- Sosyal medya platformları (Facebook, Instagram, Twitter)

Bu platformların kendi gizlilik politikaları geçerlidir.

===============================================================================

L. GÜNCELLEMELER

FunBreak Vale, işbu Aydınlatma Metni'ni yasal değişiklikler veya iş 
süreçlerindeki gelişmeler doğrultusunda güncelleme hakkını saklı tutar.

Güncellemeler:
- Web sitesinde yayınlanır (www.funbreakvale.com/kvkk)
- Mobil uygulamada bildirim gönderilir
- E-posta ile bildirim yapılabilir

Güncelleme takibi kullanıcının sorumluluğundadır.

===============================================================================

M. İLETİŞİM

Kişisel verilerinizle ilgili sorularınız ve talepleriniz için:

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

Çalışma Saatleri: Pazartesi-Cuma 09:00-18:00
Müşteri Hizmetleri: 7/24 (mobil uygulama canlı destek)

===============================================================================

Versiyon: 4.0''';
  }
  
  String _getUserAgreementText() {
    return '''===============================================================================

FUNBREAK VALE
YOLCU (MÜŞTERİ) KULLANIM KOŞULLARI SÖZLEŞMESİ

===============================================================================

1. TARAFLAR

İşbu Mobil Uygulama Kullanım Sözleşmesi (Bundan böyle "Sözleşme" olarak 
anılacaktır.) Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı 
FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI (Bundan böyle "FunBreak Vale" veya 
"Şirket" olarak anılacaktır.) ile FunBreak Vale mobil uygulaması üzerinden 
özel şoför ve vale hizmeti alan (Bundan böyle "Yolcu" veya "Müşteri" olarak 
anılacaktır) arasındadır.

===============================================================================

2. SÖZLEŞME'NİN AMACI VE KONUSU

2.1. İşbu Sözleşme'nin konusu, Yolcu için özel şoför ve vale bulma hizmetini 
sunan FunBreak Vale ile Yolcu arasındaki mobil uygulama ("Mobil Uygulama") 
ve web platformu kullanımına ilişkin hak ve yükümlülükleri belirtmektir.

2.2. FunBreak Vale, Yolcu ile Vale (sürücü) arasında aracılık hizmeti sunan 
bir teknoloji platformudur. FunBreak Vale, Yolcu ile herhangi bir taşıma 
sözleşmesi yapmamakta olup, aracılık hizmeti sağlamaktadır.

===============================================================================

3. FUNBREAK VALE'NİN KULLANIMI VE TAAHHÜTLER

3.1. GENEL KULLANIM KOŞULLARI

3.1.1. Yolcu, Mobil Uygulama üzerinden alacağı kullanıcı adı ve kullanıcı 
şifresi vasıtasıyla FunBreak Vale'yi etkin olarak kullanabilecek, mobil 
uygulamaya erişim sağlayabilecek, lokasyonuna, uzmanlığına ve yoğunluk 
dengesine göre FunBreak Vale'nin yazılımının belirleyeceği algoritma 
kapsamında belirlenecek Vale'yi (sürücüyü) yetkili kılabilecektir.

3.1.2. FunBreak Vale tarafından belirlenen Vale, Yolcu'nun talep ettiği 
lokasyona gidecek ve Yolcu'nun aracı ile Yolcu'yu belirttiği lokasyona 
transfer edecektir. Yolcu'nun aracı Vale tarafından kullanılacaktır.

3.1.3. FunBreak Vale veya FunBreak Vale'nin vermiş olduğu hizmetlerle 
bağlantılı iştirakleri veya uygulamaları veya altyapıları üzerinde her tür 
kullanım ve tasarruf yetkisi FunBreak Vale'ye aittir.

3.1.4. FunBreak Vale, Sözleşme şartları da dahil olmak üzere, mobil 
uygulamasında mevcut her tür koşulu ve bilgiyi önceden herhangi bir ihtara 
gerek olmaksızın değiştirme hakkını saklı tutar.

3.2. GÜVENLİK VE GİZLİLİK

3.2.1. Yolcu, FunBreak Vale'nin kullanımında tersine mühendislik 
yapmayacağını ya da bunların kaynak kodunu bulmak veya elde etmek amacına 
yönelik herhangi bir başka işlemde bulunmayacağını, aksi halde FunBreak 
Vale, Vale ve 3. kişiler nezdinde doğacak zararlardan sorumlu olacağını, 
hakkında hukuki ve cezai işlem yapılacağını peşinen kabul eder.

3.2.2. Yolcu, FunBreak Vale içindeki faaliyetlerinde, FunBreak Vale'nin 
herhangi bir bölümünde veya iletişimlerinde genel ahlaka ve adaba aykırı, 
kanuna aykırı, 3. kişilerin haklarını zedeleyen, yanıltıcı, saldırgan, 
müstehcen, pornografik, kişilik haklarını zedeleyen, telif haklarına aykırı, 
yasa dışı faaliyetleri teşvik eden içerikler üretmeyeceğini, 
paylaşmayacağını kabul eder.

3.2.3. Aksi halde oluşacak zarardan sorumlu olan Yolcu'nun hesabı geçici 
olarak askıya alınabilir, sona erdirilebilir, yasal süreç başlatılabilir. 
FunBreak Vale takdir hakkı yalnızca kendisine ait olmak üzere başka herhangi 
bir sebeple de Yolcu'nun FunBreak Vale'ye erişimini ve FunBreak Vale'ye 
ilişkin işlevleri kullanmasını engelleme ya da sınırlama hakkını saklı tutar.

3.3. KİŞİSEL VERİLERİN KORUNMASI

3.3.1. Kayıt sırasında FunBreak Vale'ye vermiş olduğunuz veriler, 6698 Sayılı 
Kişisel Verilerin Korunması Kanunu ("KVKK") çerçevesince hazırlanan kişisel 
verilerin korunması ve işlenmesi politikası kapsamında işlenir ve bu veriler; 
metin, kimlik bilgileri, iletişim bilgileri, lokasyon, adres, fotoğraf, 
grafik, ses kayıtları vb. den oluşur.

3.3.2. Bilgilerin sorumluluğu Yolcu'ya aittir. FunBreak Vale bilgilerin 
online dağıtımında rol oynar. Yargı mercilerinden Yolcu'nun hesapları ile 
ilgili bilgi talepleri gelirse paylaşma hakkını saklı tutar.

3.3.3. FunBreak Vale, Yolcu'ya ait kişisel verilerin Vale'ye aktarılmasından 
veya Vale'ye aktarıldıktan sonra KVKK'ya aykırı olabilecek fiillerden ve 
ihlallerden sorumlu değildir.

3.3.4. Yolcu'nun paylaşmış olduğu bütün veriler Kişisel Veriler Politikası 
ve sair düzenlemeler kapsamında değerlendirilir. Bu kapsamda Yolcu'nun 
FunBreak Vale ile paylaştığı her veri için açık bir şekilde rıza verdiği 
kabul olunur.

3.3.5. FunBreak Vale'nin bu hususta sorumluluğu olmayacağını Yolcu peşinen 
kabul eder. Verilerin FunBreak Vale veya Vale'ye veya Yolcu'ya herhangi bir 
zarar veya yük getirdiğine inanıldığı takdirde FunBreak Vale, bilgilerinizi 
veya hesabınızı tamamen veya kısmen yayından kaldırabilir.

3.3.6. FunBreak Vale ile paylaşılan bilgiler diğer Vale'nin veya Yolcu'nun 
kullanımına kısmen ya da tamamen açılabilir, referans gösterilebilir (Vale 
seçimi için profil bilgileri).

3.4. KAYIT ŞARTLARI

3.4.1. FunBreak Vale'ye kaydolmanız halinde kayıt formunu doldururken 
şahsınız hakkında doğru, kesin, güncel bilgiler vereceğinizi, işbu 
Sözleşme'nin tarafı olan Yolcu olarak üye bilgilerinizi doğru ve güncel 
tutacağınızı kabul etmiş olursunuz.

3.4.2. FunBreak Vale bilgilerinizin eksik/yanlış olduğunu tespit ederse 
kaydınızı dondurabilir veya silebilir.

3.4.3. Yolcu, en az 18 yaşında ve medeni hakları kullanma ehliyetine sahip 
olmalıdır. Reşit olmayan kişilerin kayıt yapması durumunda, yasal vasi veya 
velinin onayı gereklidir.

3.4.4. Kayıt sırasında aşağıdaki bilgiler talep edilir:
- Ad, Soyad
- T.C. Kimlik Numarası
- Cep Telefonu Numarası
- E-posta Adresi
- Ödeme Bilgisi (Kart veya Havale için IBAN)

3.5. TELİF VE FİKRİ HAKLAR

3.5.1. Yolcu, FunBreak Vale tarafından verilen hizmetlerin ve sağlanan 
içeriklerin kopyalanmaması, hiçbir şekilde çoğaltılmaması, mobil 
uygulamasının veya üçüncü bir tarafın hiçbir tescil hakkı, telif hakkı vb 
haklarının çiğnenmemesi ilkelerini kabul etmiştir.

3.5.2. Yolcu, FunBreak Vale nezdinde paylaşmış oldukları içerikleri, 
FunBreak Vale dışında paylaşmayacağını, bu hususta telif haklarına ilişkin 
tüm düzenlemeleri kabul ettiğini beyan eder.

3.5.3. Yolcu telif hakları konusunda tek sahibin FunBreak Vale olduğunu 
kabul, beyan ve taahhüt eder.

3.5.4. FunBreak Vale'nin web sayfasında veya mobil uygulamasında yer alan 
veya FunBreak Vale tarafından paylaşılan bilgiler hiçbir şekilde 
çoğaltılamaz, yayınlanamaz, kopyalanamaz, sunulamaz ve/veya aktarılamaz, 
bütünü veya bir kısmı diğer web sayfalarında veya mobil uygulamalarda 
izinsiz olarak kullanılamaz.

3.5.5. Kullanılması halinde FunBreak Vale'nin hukuki yollara başvuru hakları 
ve fikri haklarda kabul edilen 3 katına kadar maddi tazminatı isteme hakkı 
saklıdır.

3.6. HESAP GÜVENLİĞİ VE SORUMLULUK

3.6.1. İşbu Sözleşme'nin tarafı olan Yolcu, FunBreak Vale ve üçüncü taraf 
web sayfalarındaki şifre ve hesap güvenliğinden kendisi sorumlu olduğunu 
kabul, beyan ve taahhüt eder. Aksi halde oluşacak veri kayıplarından ve 
güvenlik ihlallerinden veya donanım ve cihazların zarar görmesinden 
FunBreak Vale sorumlu tutulamaz.

3.6.2. Yolcu, kullanıcı adı ve kullanıcı şifrelerinin yetkili olmayan kişiler 
tarafından kullanılmasını veya yetki verdiği kişilerin bunları yetkilerini 
aşacak şekilde kullanmalarını önlemekle ve gerekli denetimleri yapmakla 
yükümlüdür.

3.6.3. Yolcu, oluşturduğu kullanıcı adı ve şifresini üçüncü kişiler ile 
paylaşmayacağını; kullanıcı adı ve şifrenin seçimi, gizliliği ve korunmasının 
tamamı ile kendi sorumluluğunda olduğunu; FunBreak Vale'nin kullanıcı adı ve 
şifre kullanımından doğacak problemlerden kesinlikle sorumlu olmadığını 
kabul, beyan ve taahhüt eder.

3.6.4. Yolcu, kendisi hakkında vermiş olduğu kişisel bilgiler ile 
FunBreak Vale'ye giriş ve bağlantı ile kullanım kayıt ve bilgilerinin, 
bunlara ait verilerin FunBreak Vale tarafından saklanmasını, depolanmasını, 
yedeklenmesini, silinmesini, kayıt altına alınmasını, kontrol edilmesini 
kabul etmektedir.

3.6.5. Yolcu, kendilerine ait iletişim bilgileri ve sair verilerin 
FunBreak Vale ve/veya bağlantılı kurum, kuruluş ve kişiler tarafından 
başkaca hizmet veya çalışmalar veya ticari amaçlı faaliyetler için tekrar 
izin almaksızın veya kendisine bildirim yapılmaksızın kullanılabileceğini ve 
bunun için FunBreak Vale'ye veya kullanımı gerçekleştirecek kişilerden 
hiçbir talepte bulunmayacağını kabul, beyan ve taahhüt etmektedir.

3.6.6. FunBreak Vale'de, Yolcu'ya ait kullanıcı adı, kullanıcı şifresi ile 
yapılan her işlem ve her eylem işbu Sözleşme'nin tarafı olan Yolcu 
tarafından yapılmış sayılır.

3.6.7. FunBreak Vale'de işbu Sözleşme'nin tarafı olan Yolcu tarafından 
yapılan veya yapıldığı var sayılan her bir işlem, komut, bilgi girişi ve her 
türlü elektronik müdahale işbu Sözleşme'nin tarafı olan Yolcu'ya ait bir 
irade açıklaması olarak geçerli sayılır ve buna ilişkin hukuki sonuçları 
doğurur.

3.6.8. Yolcu'nun FunBreak Vale tarafından sunulan hizmetlerden 
yararlanabilmek amacıyla kullandıkları sisteme erişim araçlarının 
(kullanıcı ismi, şifre v.b) güvenliği, saklanması, üçüncü kişilerin 
bilgisinden uzak tutulması, kullanılması durumlarıyla ilgili hususlar 
tamamen Yolcu'nun sorumluluğundadır.

3.6.9. Yolcu'nun kendi cihazlarında yaratacağı arızalar, bilgi kaybı ve diğer 
kayıplarda sorumluluğunun tamamıyla kendisine ait olduğu işbu Sözleşme'nin 
tarafı olan Yolcu tarafından kabul edilmiştir.

3.6.10. Yolcu, aynı anda birden fazla cihazdan oturum açması durumunda 
FunBreak Vale'nin güvenlik politikası gereği eski oturumları sonlandırma 
hakkına sahip olduğunu kabul eder. Her cihaz için benzersiz cihaz kimliği 
(Device ID) oluşturulur ve kayıt altına alınır.

3.7. ÜYELİK VE HESAP YÖNETİMİ

3.7.1. Yolcu, FunBreak Vale'nin yazılı veya elektronik ortamlarla 
gönderilebilecek onayı olmadan işbu Sözleşme'yi veya bu Sözleşme'nin 
kapsamındaki hak ve yükümlülüklerini, üye profillerini, üye bilgilerini 
kısmen veya tamamen herhangi bir üçüncü kişiye devredemez; üyelik üyenin 
kendisinden başka kişilerin kullanımına açılamaz.

3.7.2. Üyeliğini başkasına kullandırttığı veya devrettiği tespit edilen 
üyenin üyeliği iptal edilir ve ihlalde bulunan işbu Sözleşme'nin tarafı olan 
Yolcu hakkında TCK 243-244 hükümleri kapsamında (hileli davranış ve 
dolandırıcılık) savcılığa suç duyurusunda bulunulur.

3.7.3. FunBreak Vale, işbu Sözleşme'nin tarafı olan Yolcu'nun başvurularını 
reddetme hakkını saklı tutacağı gibi, herhangi bir sebeple Yolcu'nun daha 
sonrasında hesabını durdurma veya silme hakkını da saklı tutmaktadır.

3.7.4. İşbu Sözleşme'nin tarafı olan Yolcu reşit olmamasına rağmen Sözleşme 
ilişkisi kurulduğunun tespit edilmesi durumunda, işbu Sözleşme'nin tarafı 
olan Yolcu üyelik kaydında ödemenin kimin tarafından yapıldığı göz önünde 
bulundurulacaktır. Bu durumlarda Sözleşme ilişkisi FunBreak Vale'ye veya 
mobil uygulamasına üye olan kişilerle değil ödeme ilişkisi kurulan kişi veya 
kişilerle kurulmuş olacaktır.

3.7.5. Reşit olmayan, üyeliği daha önce iptal edilmiş olan kişilerin işbu 
Sözleşme'yi onaylamaları, üyelik sonucunu doğurmayacaktır. Üyeliğinin daha 
önce iptal edilmiş olduğu tespit edilen üyenin üyeliği iptal edilir.

3.8. ÜCRET VE ÖDEME POLİTİKASI

3.8.1. FunBreak Vale'ye kayıt olan Yolcu, işbu Sözleşme'de belirtilen 
veyahut ek protokolle FunBreak Vale tarafından düzenlenecek genel, mobil 
uygulamaya özgü olan ücret ve ödeme politikasını, dönemsel kampanyaları ve 
fiyatlandırma sistemini kabul ettiğini beyan eder.

3.8.2. Yolcu, ücret ve ödeme politikasına karşı itirazda bulunmayacağını ve 
bunu bir ihtilaf konusu halinde getirmeyeceğini, getirilmesi durumunda 
100.000,00 TL cezai şartı ödemeyi peşinen geriye dönülmez şekilde beyan, 
kabul ve taahhüt eder.

3.8.3. Yolcu, FunBreak Vale ile paylaşmış olduğu ödeme bilgilerinin 
doğruluğunu, aksi durumda hak talep edemeyeceğini kabul, beyan ve taahhüt 
eder.

3.8.4. Yolcu, yolculuk öncesinde tahmini fiyat bilgisini göreceğini, ancak 
yolculuk sırasında oluşan bekleme süreleri ve mesafe değişikliklerinin 
ücrete yansıyabileceğini kabul eder.

===============================================================================

4. YOLCU'NUN HAK VE YÜKÜMLÜLÜKLERİ

4.1. GENEL YÜKÜMLÜLÜKLER

4.1.1. Yolcu, mobil uygulamada yer alan tüm sözleşme hükümlerine uygun 
hareket edeceğini, FunBreak Vale tarafından belirlenen usule uyacağını 
kabul, beyan ve taahhüt eder.

4.1.2. Yolcu, FunBreak Vale üzerinden Vale çağırma hizmeti alabilmektedir. 
Bu hizmet dışındaki taleplerde bulunan Yolcu'nun üyeliği askıya alınabilir 
veya silinebilir.

4.1.3. Yolcu, FunBreak Vale kullanılmadan Vale ile doğrudan iletişime geçmeye 
çalışırsa (sistem dışı telefon numarası paylaşımı, özel anlaşma vb.) her 
işlem başına 100.000,00 TL cezai şart uygulanır.

4.1.4. Yolcu, yetkisi dışında bulunan veya yerine getirme gücü olmayan 
işlemlere tevessül etmeyeceğini, bu tür teklif ve kabullerde 
bulunmayacağını ve yaptığı her işlemde dürüst, iyi niyetli ve tedbirli 
davranacağını, sistemi kullanırken, sistemin işleyişini engelleyici veya 
zorlaştırıcı şekilde davranmayacağını beyan, kabul ve taahhüt eder.

4.1.5. Yolcu, beklenmeyen hizmet kesintilerinden, planlara uyulamamasından, 
değerlendirmelere yetkisiz erişim veya ifşasından, değerlendirmelerin 
bütünlüğünün bozulmasından, ücret yönetiminin bütünlüğünün bozulmasından, 
raporların bütünlüğünün bozulmasından, sürecin gizliliğinin ve bütünlüğünün 
bozulmasından sorumludur.

4.2. YASAK FAALİYETLER

Yolcu, FunBreak Vale'yi kullanırken veyahut FunBreak Vale vasıtasıyla 
hizmet alırken;

a) Eylemlerinin suç unsuru oluşturmayacağını, kamuyu engellemeyeceğini ve 
uygulamada olan herhangi bir yasayı çiğnemeyeceğini;

b) Virüs, bozulmuş dosya, Truva atı (Trojan horse), kurt, iptal programcığı, 
"fare kapanı" (mouse trap) adı verilen birçok pencere açılmasını sağlayarak 
siteden çıkılmasını engelleyen girişim ya da yazılım gibi bir başkasının 
bilgisayarının işlevini engelleyici yazılım ve girişimlerde bulunmayacağını;

c) Herhangi bir şahsın mahremiyet hakkına tecavüz edici yanlış, yanıltıcı, 
onur kırıcı, iftira atıcı, leke sürücü, müstehcen, kaba ya da saldırgan 
girişimde bulunmayacağını;

d) FunBreak Vale'nin veya üçüncü tarafların dünya çapındaki telif hakkı, 
tescilli marka, patent ve diğer entellektüel haklarını ihlal etmeyeceğini, 
ticari itibarını zedeleyecek faaliyetlerde bulunmayacağını, işbu Sözleşme 
hükümlerine aykırı davranmayacağını;

kabul, beyan ve taahhüt eder.

4.2.2. Yolcu, yukarıdaki yasak fiillerde bulunma durumunda FunBreak Vale'ye 
yönelik olabilecek tüm yasal başvurulardan doğabilecek zararlardan sorumlu 
olduğunu ve aksi fiillerde bulunma durumunda 200.000,00 TL'den az olmamak 
kaydıyla bu zararlar kadar cezai şart bedelini ödeyeceğini beyan, kabul ve 
taahhüt eder.

4.3. VERİ KORUMA YÜKÜMLÜLÜKLERİ

4.3.1. Yolcu işbu Sözleşme'de ve FunBreak Vale'de belirtilen diğer 
sözleşmelere uygun olarak 6698 Sayılı Kişisel Verilerin Korunması Kanunu 
kapsamında gerekli teknik ve idari yükümlülükleri yerine getireceğini, 
kişisel verileri veya ticari bilgileri üçüncü kişilerle paylaşmayacağını, 
sözleşmede gizli bilgi olarak belirtilen bilgileri sözleşmeye aykırı olarak 
üçüncü kişilerle paylaşmayacağını kabul eder.

4.3.2. Yolcu, FunBreak Vale'nin veya Vale'nin datalarını dışarı 
kaçırmayacağını, yetkisiz erişim, yetkisiz bilgi ifşa yapmayacağını, 
Raporlara yetkisiz erişim veya ifşalarda bulunmayacağını, programın 
bütünlüğünün bozulmasına veya erişilebilirliğinin bozulmasına sebebiyet 
vermeyeceğini, aksi durumda FunBreak Vale'nin veya Vale'nin uğrayacağı tüm 
doğrudan veya dolaylı zararları tazmin etmeyi kabul beyan ve taahhüt eder.

4.4. HİZMET ALMA SÜRECİ

4.4.1. Yolcu, FunBreak Vale tarafından belirlenen sistemin işleyişine uyum 
sağlamayı kabul, beyan ve taahhüt eder. İşleyiş aşağıdaki gibi olacaktır:

a. Yolcu, mobil uygulama üzerinden alış (pickup) ve varış (destination) 
   lokasyonunu seçerek Vale çağırır. Sistem tahmini fiyat gösterir.

b. Yolcu, belirlenen tahmini ücreti önceden görebilir. Ancak transfer işlemi 
   içerisindeki bekleme süreleri ve mesafe değişikliklerinde ek ücret (bekleme 
   ücreti: ilk 15 dakika ücretsiz, sonrası 200 TL/15 dakika) uygulanabilir.

c. Sistem Vale ararken Yolcu bekler. Vale bulunduğunda bildirim gelir ve 
   Vale bilgileri (ad, soyad, puan) gösterilir.

d. Yolcu, çağırdığı Vale'yi uygulama içerisindeki harita üzerinden canlı 
   olarak takip edebilir (real-time GPS tracking). Vale'nin gelişini görebilir.

e. Yolcu, mobil uygulama üzerinden Vale'yü köprü arama sistemi ile arayarak 
   iletişime geçebilir. Vale'nin kişisel telefon numarası Yolcu ile paylaşılmaz.

f. Yolcu, sistem içi mesajlaşma özelliğini kullanarak Vale ile yazışabilir.

g. Yolcu, mobil uygulama üzerinden yolculuğunu canlı olarak takip edebilir. 
   Yolculuk rotası (route tracking) ve bekleme noktaları (waiting points) 
   otomatik olarak kaydedilir.

h. Yolcu, yolculuk bitiminde mobil uygulama üzerinden kart veya havale ile 
   ödeme yapar. Ödeme yapılana kadar yeni yolculuk başlatılamaz.

i. Yolcu, yolculuk sonunda Vale'yi 1-5 yıldız arası puanlayabilir ve yorum 
   yazabilir.

j. Yolcu, geçmiş yolculuklarını görüntüleyebilir, fatura talep edebilir.

4.4.2. Yolcu, hizmet sırasında gerekli olan tüm belgeleri (kimlik, araç 
ruhsatı, trafik sigortası vb.) taşıma yükümlülüğüne sahiptir. Yolcu, bu 
belgeleri taşımamasından dolayı doğacak tüm sonuçların kendi sorumluluğunda 
olduğunu kabul eder.

===============================================================================

5. YOLCU'YA DAİR ÖZEL YÜKÜMLÜLÜKLER

5.1. SORUMLULUK BEYANLARI

5.1.1. Yolcu, aracı hizmet sağlayıcı olması kapsamında FunBreak Vale'nin 
herhangi bir sorumluluğu olmadığını ve FunBreak Vale'ye karşı Vale'nin 
sürüşünden kaynaklanan durumlar için hak ve tazmin talebinde 
bulunamayacağını kabul, beyan ve taahhüt eder.

FunBreak Vale'den şoför hizmeti alan Müşteri, aracını 3. bir şahsa kendi 
isteği ile kullandırdığını ve araç sahibi veya kullanıcısı olarak buna bağlı 
hukuki sorumluluğunun farkında olduğunu ve bu sorumluluğu bizzat kendisinin 
aldığını beyan ve kabul eder.

Hizmet talep edilen aracın kasko ve zorunlu trafik sigortası yok ise 
FunBreak hizmet vermeme hakkına sahiptir.

Hizmet esnasında oluşacak yangın, kaza veya hasarda Müşteri hasarın 
giderilmesi için kendi araç sigortalarını kullanacağını, meydana gelen maddi 
veya manevi tüm zararlar ve tazminatlardan bizzat sorumlu olduğunu bunlar 
için FunBreak Vale'den hiçbir maddi/manevi tazminat talebinde 
bulunmayacağını, bu haklardan feragat ettiğini beyan ve taahhüt eder.

Müşteri; FunBreak Vale'nin ikame araç temin edilmesinden ve/veya hasarlı 
aracın değer kaybının karşılanmasından sorumlu olmadığını, aracın boyasında 
ön ve arka tamponlar ve çamurluklarda bulunan çiziklerden veya araç içindeki 
herhangi bir hasardan FunBreak Vale'nin sorumlu olmadığını, bunlara ilişkin 
FunBreak Vale'den hiçbir maddi/manevi tazminat talebinde bulunmayacağını, 
bu haklardan feragat ettiğini beyan ve taahhüt eder.

Aracınızın herhangi bir kazaya karışması durumunda aracınıza ait kasko ve 
trafik poliçesi devreye girecektir. Araçlarda veya kişilerde oluşan sigorta 
kapsamı üstündeki hasarlar dahil tüm sorumluluk size aittir. Bu durumda 
FunBreak Vale ikame araç ve değer kaybı dahil herhangi bir sorumluluk 
kabul etmez.

Müşteri; FunBreak Vale tarafından sunulan diğer hizmetlerinin ifası sırasında 
FunBreak Vale'in asıl tedarikçiler, şoför ile Müşteri arasında sadece bir 
aracı olarak hizmet sunduğunu bu nedenle meydana gelebilecek maddi manevi 
zararlar ve hasarlar ile ilgili olarak FunBreak Vale'in herhangi bir 
sorumluluğu olmadığını kabul ile ilgili her türlü haklarından feragat 
ettiğini beyan ve taahhüt eder.

5.1.2. Yolcu, transferi ile ilgili aracından veya sair herhangi bir husustan 
kaynaklanan durumların kendi sorumluluğunda olduğunu, zarar ve ziyanın 
tazminine ilişkin taleplerinizin reddedileceğini kabul, beyan ve taahhüt eder.

5.1.3. Yolcu, seyahatiyle alakalı memnuniyetsizliğini öncelikle 
FunBreak Vale'ye (info@funbreakvale.com veya 0533 448 82 53) bildirmeyi, 
sonrasında gerekirse Tüketici Hakem Heyetlerine iletmeyi kabul eder.

5.1.4. Yolcu, herhangi bir sosyal medya platformunda veya şikayet 
portalındaki paylaşımının FunBreak Vale'nin ticari itibarını zedelemeye 
ilişkin olabileceğinin farkında olarak, önce şirket içi çözüm mekanizmalarını 
kullanmadan böyle bir eylemde bulunmaması gerektiğini, aksi durumda yasal 
süreçlerle karşı karşıya kalacağını bildiğini kabul, beyan ve taahhüt eder.

5.1.5. İşbu Sözleşme'nin tarafı olan Yolcu, işbu Sözleşme'den doğan 
yükümlülüklerini ihlal etmesi veya işbu Sözleşme hükümlerine aykırı hareket 
etmesi durumunda, FunBreak Vale'nin, Vale'nin veya üçüncü kişilerin doğan 
zararlarını doğrudan karşılamaktan sorumludur.

5.2. ARAÇ VE EŞYA SORUMLULUĞU

5.2.1. Yolcu, aracında bulunan kişisel eşyalarından kendisinin sorumlu 
olduğunu, Vale'nin hizmet sırasında bu eşyalara zarar vermesi veya kaybolması 
durumunda Vale'nin sorumlu olacağını ancak Yolcu'nun aracında bıraktığı ve 
Vale'ye bildirmediği değerli eşyalardan (mücevher, nakit para, elektronik 
cihaz, önemli belgeler vb.) Vale'nin sorumlu olmayacağını kabul eder.

5.2.2. Yolcu, aracının teknik durumunun ve bakımının uygun olmasından 
kendisinin sorumlu olduğunu, aracın arızalanması veya teknik sorun yaşaması 
durumunda Vale'nin sorumlu olmayacağını kabul eder.

5.2.3. Yolcu, aracının güncel trafik sigortasına sahip olduğunu, sigorta 
eksikliğinden kaynaklanan sorunlardan Vale ve FunBreak Vale'nin sorumlu 
olmayacağını kabul eder.

5.2.4. Yolcu, aracının temiz ve kullanılabilir durumda Vale'ye teslim 
edileceğini, araçta yasak madde veya yasal olmayan eşya bulunmayacağını 
kabul ve taahhüt eder.

5.3. VALE İLE İLİŞKİLER

5.3.1. Yolcu, Vale'ye karşı saygılı ve nazik davranacağını, Vale'yi rahatsız 
edici davranışlardan kaçınacağını kabul eder.

5.3.2. Yolcu, Vale'den sistem dışında ek hizmet talep etmeyeceğini, Vale'yi 
başka yerlere götürme veya ek işler yaptırma gibi taleplerde bulunmayacağını 
kabul eder.

5.3.3. Yolcu, Vale ile sistem içi iletişim kanallarını (köprü arama, 
mesajlaşma) kullanacağını, Vale'nin kişisel bilgilerini talep etmeyeceğini 
kabul eder.

===============================================================================

6. FUNBREAK VALE'NİN HAK VE YÜKÜMLÜLÜKLERİ

6.1. FunBreak Vale, Vale'nin denetimini yapmakla sorumlu olmasa da 
Yolcu'nun siparişlerini onaylamamakta serbesttir.

6.2. FunBreak Vale, web sayfasında ve mobil uygulamasında bulunan yazılı, 
görsel veya videolu içerikler üzerinde hak sahibidir. Bu haklardan 
yararlanmanın belli bir süre için Yolcu'ya verilmiş olması, FunBreak Vale'nin 
ilgili içerikler üzerindeki hakkını zedeleyemeyeceği gibi Yolcu'ya da FSEK 
ve SMK kapsamında herhangi bir hak vermez.

6.3. FunBreak Vale, sistemin amaçlarına ters düşmemek üzere, web sayfasının 
veya mobil uygulamasının kullanım amacını, özelliklerini, yapısını, 
fonksiyonlarını, içeriğini değiştirebilir. Teknik sebeplerden veya üçüncü 
kişilerin eylem ve işlemlerinden kaynaklanan sorunlar, hacking saldırıları 
veya zorunlu sebeplerden dolayı da FunBreak Vale mesul tutulamaz.

6.4. FunBreak Vale, Yolcu'dan ek bilgi ve belgeler talep edebilir, web 
sayfasını veya mobil uygulamasını iptal edebilir, işletilmesini askıya 
alabilir.

6.5. FunBreak Vale, Yolcu tarafından paylaşılan içeriklere ilişkin telif ve 
her nevi haklarının korunmasına dair tüm yetkileri ve takip ile teşhir 
haklarını saklı tutar.

6.6. FunBreak Vale, Vale performansını izleme, değerlendirme ve Yolcu'ya 
önerme hakkına sahiptir. Vale seçiminde algoritma kullanılır (konum, 
yoğunluk, müsaitlik, performans skoru).

6.7. FunBreak Vale, platformda güvenlik ve kalite standartlarını korumak 
amacıyla yolculukları rastgele veya şüpheli durumlarda inceleme hakkına 
sahiptir.

6.8. FunBreak Vale, Yolcu şikayetlerini değerlendirme ve gerekirse Vale ile 
olan iş ilişkisini sonlandırma hakkına sahiptir.

===============================================================================

7. GİZLİLİK VE REKABET YASAĞI

7.1. İşbu Sözleşme'de açıkça aksi belirtilen haller hariç olmak üzere, 
Yolcu işbu Sözleşme çerçevesinde öğrendikleri gizli bilgileri, verileri veya 
belgeleri bunlara ait tüm bilgileri, verileri ve belgeleri, fikri ve sınai 
hakları, varlıkları ve sair her türlü maddi ve manevi nitelikte varlıkları, 
FunBreak Vale'nin yazılı izni olmaksızın üçüncü kişilere açıklayamaz, 
paylaşamaz ve ifşa edemez.

7.2. İşbu Sözleşme bağlamında, "Gizli Bilgiler"; FunBreak Vale'nin, 
FunBreak Vale'nin iştirakleri, yöneticileri, yetkilileri, çalışanları ve 
profesyonel danışmanları ve Vale veya Yolcu'ya herhangi birine sözlü, 
yazılı, manyetik, elektronik, dijital veya sair şekillerde doğrudan doğruya 
veya dolaylı olarak FunBreak Vale veya onun adına ifşa edilen veya sunulan; 
ticari, teknolojik, ekonomik, teknik, mali, hukuki, işletmesel, idari, 
pazarlama ve/veya örgütsel bilgiler; mallar, hizmetler, teknolojiler, 
projeler, operasyonlar, işletme planları ve ticari işler, iş ve ürün 
araştırma ve geliştirme faaliyetleri, know-how, tasarım hakları, ticari 
sırlar, pazar fırsatları, Vale bilgileri, kullanıcı bilgileri, reklam 
kampanyaları, kişisel verileri, reklam stratejileri, şirket gelirleri, şirket 
yatırımları, Yolcu'ya ilişkin bilgiler, uygulamalardaki içerikler, 
uygulamanın yazılım altyapısı, FunBreak Vale'ye ilişkin tüm detaylar, 
bilumum raporlar, notlar, analizler, derlemeler, tahminler, veriler, 
bilirkişi raporları, özetler, çalışmalar ve bunlara ilişkin sunduğu tüm 
bilgiler ve sair dokümanlardır.

7.3. İşbu Sözleşme'nin tarafı olan Yolcu, kendisi ve/veya temsilcilerinin 
işbu Sözleşme'den doğan yükümlülüklerini ihlal etmesi veya işbu Sözleşme 
hükümlerine aykırı hareket etmesi durumunda, FunBreak Vale veya 
temsilcilerinin doğrudan zararlarına karşı sorumludur.

7.4. Yolcu, FunBreak Vale ve/veya başka bir üçüncü şahsın ayni veya şahsi 
haklarına, malvarlığına tecavüz teşkil edecek nitelikteki FunBreak Vale 
dâhilinde bulunan resimleri, metinleri, videoları, içerikleri, kişisel 
verileri, görsel ve işitsel imgeleri, video klipleri, dosyaları, 
veritabanları, katalogları ve listeleri çoğaltmayacağını, kopyalamayacağını, 
dağıtmayacağını, işlemeyeceğini, gerek bu eylemleri ile gerekse de başka 
yollarla FunBreak Vale ile doğrudan ve/veya dolaylı olarak rekabete 
girmeyeceğini kabul eder.

7.5. Yolcu, yukarıdaki yükümlülüklere aykırı davranması durumunda 
FunBreak Vale'ye yönelik olabilecek tüm yasal başvurulardan doğabilecek 
zararlardan sorumlu olduğunu ve en az 100.000,00 TL olmak üzere bu zararlar 
kadar cezai şart bedelini ödeyeceğini kabul ve taahhüt etmektedir.

===============================================================================

8. KİŞİSEL VERİLERİN KORUNMASI

8.1. Yolcu, kayıt esnasında kabul ettikleri FunBreak Vale'de yer alan 
Kişisel Verilerin Korunması ve İşlenmesi Politikası ve KVKK Aydınlatma metni 
kapsamında FunBreak Vale'nin Kişisel Verileri; Türkiye Cumhuriyeti 
Anayasası, ülkemizin taraf olduğu uluslararası sözleşmeler ve 6698 sayılı 
Kişisel Verilerin Korunması Kanunu ("KVKK") başta olmak üzere, Kişisel 
Verilerin korunması ile ilgili tüm mevzuatın öngördüğü sınırlar çerçevesinde, 
KVKK'nın 4. maddesinde yer alan;

a) Hukuka ve dürüstlük kurallarına uygun olma,
b) Doğru ve gerektiğinde güncel olma,
c) Belirli, açık ve meşru amaçlar için işlenme,
d) İşleme amaçlarıyla bağlantılı, sınırlı ve ölçülü olma,
e) İlgili mevzuatta öngörülen veya işlendikleri amaç için gerekli olan süre 
   kadar muhafaza edilme

ilkelerine uygun olarak toplayabileceğini ve işleyebileceğini kabul etmiştir.

8.2. FunBreak Vale, detaylı hazırlamış olduğu Kişisel Verilerin Korunması ve 
İşlenmesi Politikası ve KVKK Aydınlatma metni kapsamında KVKK'ya tam 
uyumluluğu amaçlamaktadır. Bu kapsamda FunBreak Vale mobil uygulamasında yer 
alan kişisel verilerin aynı hassasiyetle Yolcu tarafından korunması 
gerekmektedir.

8.3. İşbu Sözleşme'nin tarafı olan Yolcu ihlalleri ölçüsünde, Kişisel 
Verilerin Korunması Kanunu kapsamındaki yükümlülüklerinin ihlali ya da 
hukuka aykırı eylemleri nedeniyle tahakkuk edilecek idari para cezalarının, 
gerekse savcılık tarafından yürütülecek cezai soruşturmaların muhatabı 
olduğunu, mevzubahis yükümlülüklerin yerine getirilmemesi nedeniyle 
FunBreak Vale'nin, diğer Yolcu'nun, Vale'nin veya üçüncü kişilerin uğrayacağı 
her türlü maddi ve manevi zararı tazmin etmekle yükümlü olduğunu kabul, 
beyan ve taahhüt eder.

===============================================================================

9. SÖZLEŞME'NİN SÜRESİ VE FESİH HAKKI

9.1. İşbu Sözleşme süresiz olarak düzenlenmiştir.

9.2. FunBreak Vale e-posta yoluyla veya yazılı bir bildirimde bulunarak ve 
bir süre tayinine gerek olmaksızın önceden bildirmeksizin istediği zaman 
sözleşmeyi fesih hakkına sahiptir.

9.3. Yolcu, üyeliğini tek taraflı olarak istediği zaman iptal edebilir. 
Ancak üyeliği sırasında gerçekleştirdiği eylem ve fiillerden, borçlarından 
gerek FunBreak Vale'ye karşı gerekse diğer üçüncü kişi, kurum ve kuruluşlara 
karşı şahsen sorumlu olacaktır.

9.4. Üyeliğini iptal eden veya 90 (doksan) gün boyunca FunBreak Vale'ye 
giriş yapmayan veya işbu sözleşmedeki yükümlülüklerini yerine getirmeyen 
Yolcu tüm haklarından feragat etmiş sayılır.

9.5. Yolcu'nun Sözleşme kapsamındaki yükümlülüklerinden herhangi birinin 
ihlali sözleşmenin haklı sebeple feshi için dayanak teşkil edecek olup, 
Sözleşmenin haklı bir şekilde feshi halinde FunBreak Vale'nin Yolcu'nun 
hesabını silme hakkı ve münferiden her tespit edilen ihlal başına (ayrıca 
düzenlenen cezai şartlar hariç olmak üzere) 150.000,00 TL cezai şart talep 
etme hakkı mevcuttur.

9.6. Yolcu, ihlal halinde münferiden her ihlal başına 150.000,00 TL cezai 
şartı ödemeyi kabul, beyan ve taahhüt eder. Kendisine gelecek cezai şart 
talebini tebliğden itibaren 5 (beş) iş günü içerisinde FunBreak Vale'ye 
ödemekle yükümlüdür.

9.7. Yolcu, üyeliği iptal etmeden önce sistemde bekleyen ödemelerini 
tamamlamalıdır. Tamamlanmamış ödemeleri olan Yolcu'ların hesapları 
kapatılamaz.

9.8. Yolcu, aşağıdaki durumlarda FunBreak Vale tarafından derhal ve tek 
taraflı olarak hesabı kapatılabilir:
a) Sahte bilgi veya belge sunması
b) Ödeme borcu bulunması ve 30 gün içinde ödememesi
c) Vale'ye karşı suç teşkil eden bir eylemde bulunması
d) Mükerrer şikayet alması
e) Gizlilik kurallarını ihlal etmesi
f) Yasaklı faaliyetlerde bulunması

===============================================================================

10. MÜCBİR SEBEPLER VE SORUMSUZLUK BEYANLARI

10.1. FunBreak Vale'nin kontrolü ve iradesi dışında gelişen ve makul denetim 
gücü dışında kalan ve Taraflar'ın işbu Sözleşme ile yüklendiği borçlarını 
yerine getirmelerini engelleyici ve/veya geciktirici önceden tahmin 
edilmesi mümkün olmayan, sayılanlarla sınırlı olmamak kaydı ile; hizmeti 
sağlamada aracı olan kişinin veya Yolcu'nun sağlık probleminin ortaya 
çıkması, hastalanması, kaza yapması, iletişim kanallarına ulaşılamaması,
iletişim cihazlarına dair hırsızlık faaliyeti nedeniyle hizmeti ifa edememe 
gibi savaş, iç savaş, terör eylemleri, deprem, yangın, sel benzeri tabi 
afetlerin meydana gelmesi, yazılımda meydana gelen hatalar, siber saldırılar 
ve hacking saldırıları, server çökmesi gibi işbu madde kapsamında belirtilen 
mücbir sebeplerin Vale'de veya FunBreak Vale'de meydana gelmesi mücbir sebep 
olarak değerlendirilecektir.

10.2. FunBreak Vale, mücbir sebep yüzünden yükümlülüklerini tam veya 
zamanında yerine getirememekten dolayı sorumlu tutulmayacaktır. 
FunBreak Vale'nin mücbir sebebin ortaya çıkmasından önce tahakkuk eden hak 
ve alacakları saklı kalacaktır.

10.3. Yolcu, FunBreak Vale üzerinde tamamlanan ya da tamamlanmayan transfer 
veya sipariş işlemlerinden dolayı oluşabilecek kayıp, zarar, iddia veya 
ziyan ile

a) FunBreak Vale'nin kontrolü dışındaki sebeplerden dolayı teknik 
   problemlerin yaşanması;

b) İnternet altyapılarının Vale veya Yolcu'nun siteye giremeyecek şekilde 
   sorun yaşatması;

c) FunBreak Vale tarafından uygulamanın işlevinin geçici olarak ya da 
   tamamen durdurulması, işlevinde değişiklikler yapılması

durumları ile sınırlı kalmaksızın oluşabilecek her türlü kayıp için 
FunBreak Vale'nin herhangi bir sorumluluğu ya da yükümlülüğü olmadığını 
beyan, kabul ve taahhüt eder.

10.4. Yolcu, FunBreak Vale'den mücbir sebeplere göre veya herhangi bir 
nedenden kaynaklanan gecikmelere ilişkin tazmin talebinde bulunmayacağını 
peşinen kabul, beyan ve taahhüt eder.

10.5. Yolcu, FunBreak Vale'nin aracı platform hizmeti verdiğini, kendisinden, 
Vale'den veya üçüncü bir kişiden kaynaklanabilecek zararlarda ve benzeri 
eylemlerde hukuki ve cezai sorumluluğun FunBreak Vale'de olmadığını kabul, 
beyan ve taahhüt eder.

10.6. Yolcu, FunBreak Vale'de Vale'ler tarafından Yolcular hakkında verilen 
puanlarda FunBreak Vale'nin herhangi bir kontrolü olmadığını ve diğer üyeler 
tarafından verilen olumsuz puanlar ya da görüşler yüzünden oluşabilecek 
durumlarında FunBreak Vale'yi sorumlu tutmadığını beyan, kabul ve taahhüt 
eder.

10.7. FunBreak Vale, yararlı olacağını düşündüğü haber, ilan, makale ve 
benzeri hususlara web sayfasında veya mobil uygulamasında yer verebilir, 
diğer web siteleriyle veya mobil uygulamalarla linkler oluşturabilir. 
FunBreak Vale, bunlarda yer alan bilgi ve yorumların doğruluğunu, amaca 
uygunluğunu, isabetli olmasını garanti etmez.

===============================================================================

11. SÖZLEŞME'NİN BÜTÜNLÜĞÜ VE UYGULANABİLİRLİK

11.1. İşbu Sözleşme şartlarından biri, kısmen veya tamamen geçersiz hale 
gelirse, sözleşmenin geri kalanı geçerliliğini korumaya devam edecektir.

===============================================================================

12. SÖZLEŞME'DE YAPILACAK DEĞİŞİKLİKLER

12.1. FunBreak Vale dilediği zaman mobil uygulamasında veya web sayfasında 
sunulan hizmetleri ve işbu sözleşme şartlarını kısmen veya tamamen 
değiştirebilir. Değişiklikler web sayfasında ve mobil uygulamada 
yayınlandığı tarihten itibaren geçerli olacaktır. Değişiklikleri takip etmek 
Yolcu'nun sorumluluğundadır.

12.2. İşbu Sözleşme'nin tarafı olan Yolcu, Sözleşme'nin güncel halini her 
zaman FunBreak Vale'de bulabilir ve meydana getirilen güncellemeleri 
okuyabilir.

12.3. Yolcu, Sözleşme koşullarında yapılan değişiklikleri takip etmek 
zorundadır ve değişiklikleri bilmediğini ileri sürerek taraflar arasındaki 
Sözleşme iradesinin son bulduğunu, Sözleşme'nin yürürlükten kalktığını ileri 
süremez.

===============================================================================

13. TEBLİGAT

13.1. İşbu Sözleşme ile ilgili taraflara gönderilecek olan tüm bildirimler, 
FunBreak Vale'nin bilinen e-posta adresi (info@funbreakvale.com) ve 
Yolcu'nun üyelik formlarında belirttiği e-posta adresi vasıtasıyla 
yapılacaktır.

13.2. Yolcu, üye olurken belirttiği adresin geçerli tebligat adresi 
olduğunu, değişmesi durumunda 5 (beş) gün içinde yazılı olarak diğer tarafa 
bildireceğini, aksi halde bu adrese yapılacak tebligatların geçerli 
sayılacağını kabul eder.

13.3. E-posta yoluyla yapılan tebligatlar, gönderim tarihinden itibaren 1 
(bir) gün sonra tebliğ edilmiş sayılır.

===============================================================================

14. DELİL SÖZLEŞMESİ

14.1. Yolcu ile FunBreak Vale arasında işbu sözleşme ile ilgili işlemler için 
çıkabilecek her türlü uyuşmazlıklarda FunBreak Vale'nin defter, kayıt ve 
belgeleri, e-posta, mobil uygulama veya web sayfası içerisindeki 
mesajlaşma, SMS ve bilgisayar kayıtları, veritabanı kayıtları, sistem 
logları 6100 sayılı Hukuk Muhakemeleri Kanunu uyarınca delil olarak kabul 
edilecek olup, Yolcu bu kayıtlara itiraz etmeyeceğini kabul eder.

14.2. GPS konum kayıtları, rota takip verileri (route tracking), bekleme 
noktası kayıtları (waiting points), bırakma konum kayıtları (dropoff 
location) ve sistem timestamp'leri FunBreak Vale'nin sunucu kayıtlarında 
saklanır ve delil niteliğindedir.

===============================================================================

15. YETKİLİ MAHKEME VE İCRA DAİRELERİ

15.1. İşbu Sözleşme'nin uygulanmasından ve/veya FunBreak Vale tarafından 
Yolcu'ya verilecek hizmetin kullanımından doğabilecek her türlü 
uyuşmazlıkların çözümünde İstanbul (Çağlayan) Mahkemeleri ile İcra 
Müdürlükleri yetkili olacaktır.

15.2. Taraflar, yukarıda belirtilen mahkemelerin yetkisini kabul ettiklerini 
ve başka bir yargı merciine başvurmayacaklarını beyan ederler.

===============================================================================

16. SÖZLEŞME EKLERİNİN KABULÜ

16.1. Yolcu, işbu sözleşmeyi onaylamakla birlikte sözleşmenin eklerini de 
kabul etmeyi beyan eder. Sözleşmenin genel ekleri:

a. Kişisel Verilerin Korunmasına Dair Aydınlatma Metni
b. Açık Rıza Beyanı
c. Ticari Elektronik İleti Onayı
d. Gizlilik Politikası
e. İptal ve İade Koşulları
f. Verilerin Gizliliğine Dair Gizlilik Taahhütleri
g. Sorumsuzluk Beyanı
h. FunBreak Vale tarafından hazırlanan rehberler, kurallar ve şartlar

16.2. Bu ekler zamanla FunBreak Vale tarafından arttırılabilir, 
değiştirilebilir. Yolcu, sözleşme değişikliklerini, eklerin düzenlemelerini 
takip etmekle yükümlü olduğu gibi düzenlemelere ilişkin yükümlülükleri de 
yerine getirmeyi kabul, beyan ve taahhüt eder.

===============================================================================

17. YÜRÜRLÜK

17.1. Yolcu, tüm bu maddeleri daha sonra hiçbir itiraza mahal vermeyecek 
şekilde okuduğunu, anladığını, Sözleşme koşularına uygun davranacağını ve 
Sözleşme'yi FunBreak Vale'nin kurduğu sistem ile dijital ortamda elektronik 
olarak onayladığını kabul, beyan ve taahhüt eder.

17.2. Sözleşme koşullarını kabul ederek üyeliğini gerçekleştiren kişiler 
daha sonra koşulların geçersiz olduğunu, Sözleşme'yi kabul etmediklerini 
iddia edemezler.

17.3. Yolcu, kullanıcı adı ve şifresini aldıktan sonra veya alma sırasında 
"Yolcu Mobil Uygulama Kullanım Şartları Sözleşmesi'ni okudum ve kabul 
ediyorum" yazılı kutuyu işaretleyip, onaylaması ile birlikte kabul beyanı 
FunBreak Vale kayıtlarına geçmiş olup, bu anda Sözleşme kurulmuş ve herhangi 
bir süre ile sınırlı olmaksızın yürürlüğe girmiş sayılacaktır.

17.4. İşbu Sözleşme, Yolcu'nun mobil uygulama veya web platformu üzerinden 
elektronik onay vermesi ile yürürlüğe girer.

17.5. Sözleşme, Türkiye Cumhuriyeti yasalarına tabidir ve bu yasalara göre 
yorumlanacaktır.

===============================================================================

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI

Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web               : www.funbreakvale.com

===============================================================================

Versiyon: 4.0''';
  }
  
  String _getCommercialText() {
    return '''===============================================================================

FUNBREAK VALE
TİCARİ ELEKTRONİK İLETİ ONAYI

===============================================================================

YASAL DAYANAK

6698 sayılı Kişisel Verilerin Korunması Kanunu, 6563 Sayılı Elektronik 
Ticaretin Düzenlenmesi Hakkında Kanun ve 15 Temmuz 2015 tarihli Resmi 
Gazete'de yayınlanan 29417 sayılı Ticari İletişim ve Ticari Elektronik 
İletiler Hakkında Yönetmelik ve sair mevzuatlar kapsamında Armağanevler Mah. 
Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 
0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI 
olarak siz değerli kullanıcılarımızı ticari elektronik iletiler hakkında 
bilgilendirmek ve ticari elektronik ileti onayınızı alarak size daha iyi bir 
hizmet sunmak istemekteyiz.

===============================================================================

BİLGİLENDİRME METNİ

TİCARİ ELEKTRONİK İLETİ NEDİR?

Ticari elektronik ileti; telefon, çağrı merkezleri, faks, otomatik arama 
makineleri, akıllı ses kaydedici sistemler, elektronik posta (e-posta), kısa 
mesaj hizmeti (SMS), anlık bildirimler (push notification) gibi vasıtalar 
kullanılarak elektronik ortamda gerçekleştirilen ve ticari amaçlarla 
gönderilen veri, ses ve görüntü içerikli iletileri ifade etmektedir.

TİCARİ ELEKTRONİK İLETİ TÜRLERİ:

a) KAMPANYA VE PROMOSYON İLETİLERİ
   - İndirim kodları
   - Özel kampanyalar
   - Fırsat duyuruları
   - Sezonluk promosyonlar

b) BİLGİLENDİRME İLETİLERİ
   - Yeni özellik duyuruları
   - Uygulama güncellemeleri
   - Hizmet geliştirmeleri
   - Genel duyurular

c) KUTLAMA VE TEMENNİ İLETİLERİ
   - Resmi bayram kutlamaları
   - Dini bayram kutlamaları
   - Doğum günü kutlamaları
   - Özel gün tebrikler

d) HATIRLATMA İLETİLERİ
   - Rezervasyon hatırlatmaları
   - Ödeme hatırlatmaları
   - Kullanılmayan hesap bildirimleri

e) KİŞİSELLEŞTİRİLMİŞ ÖNERİLER
   - Kullanım alışkanlıklarınıza göre öneriler
   - Size özel fırsatlar
   - Tavsiye edilen hizmetler

ONAY ŞARTI:

Ticari elektronik iletiler, alıcılara ancak önceden onayları alınmak kaydıyla 
gönderilebilir. Bu onay, yazılı olarak veya her türlü elektronik iletişim 
araçlarıyla alınabilir.

RED VE GERİ ÇEKME HAKKI:

Kullanıcılar diledikleri zaman, hiçbir gerekçe belirtmeksizin ticari 
elektronik iletileri almayı reddedebilir veya verdiği onayı geri çekebilir.

Bu kapsamda ticari elektronik ileti gönderimine dair onay verseniz dahi 
dilediğiniz zaman, hiçbir gerekçe belirtmeksizin ticari elektronik iletileri 
almayı aşağıdaki yöntemlerle ücretsiz bir şekilde reddedebilirsiniz:

1. Mobil Uygulama:
   Ayarlar > Hesabım > Bildirim Tercihleri > Ticari İletiler (Kapat)

2. E-posta:
   Gelen iletilerdeki "Abonelikten Çık" linkine tıklama

3. SMS:
   SMS içeriğinde belirtilen "RET" veya "IPTAL" kodunu gönderme

4. Müşteri Hizmetleri:
   info@funbreakvale.com veya 0533 448 82 53

===============================================================================

ONAY METNİ

6698 sayılı Kişisel Verilerin Korunması Kanunu, 6563 Sayılı Elektronik 
Ticaretin Düzenlenmesi Hakkında Kanun ve 15 Temmuz 2015 tarihli Resmi 
Gazete'de yayınlanan 29417 sayılı Ticari İletişim ve Ticari Elektronik 
İletiler Hakkında Yönetmelik ve sair mevzuatlar gereğince gerekli 
bilgilendirmenin tarafıma yapıldığını, işbu bilgilendirme ve onay metnini 
okuyup anladığımı ve bu şekilde alınan aşağıdaki beyanımın geçerli olduğunu 
kabul ediyorum.

FunBreak Vale web sayfası ve mobil uygulama kayıtları, üyelik kayıtları, 
dijital pazarlama ve çağrı merkezi, sosyal medya, organizatörler, 
tedarikçiler, iş ortakları ve bunlarla sınırlı olmamak üzere her türlü 
kanallar aracılığıyla, sözlü, yazılı veya elektronik ortam aracılığı ile; 
kişisel ve/veya özel nitelikli kişisel verilerimin; tamamen veya kısmen elde 
edilmesi, kaydedilmesi, depolanması, değiştirilmesi, güncellenmesi, periyodik 
olarak kontrol edilmesi, yeniden düzenlenmesi, sınıflandırılması, 
işlendikleri amaç için gerekli olan ya da ilgili kanunda öngörülen süre kadar 
muhafaza edilmesi, kanuni ya da hizmete bağlı fiili gereklilikler halinde 
FunBreak Vale'nin çalışmış olduğu şirketler ile faaliyetlerin yürütmek üzere 
hizmet aldığı, işbirliği yaptığı, program/hizmet ortağı kuruluşlarla, aracı 
hizmet sağlayıcılarla, sosyal medya kuruluşları, sosyal ağ kuruluşları 
(Facebook, Instagram, Twitter ve diğer), yurt içi / yurt dışı kuruluşları, 
kanunen yükümlü olduğumuz kamu kurum ve kuruluşlarıyla paylaşılmasına bu 
suretle işlenmesine ve Kişisel Verilerin Korunması ve İşlenmesi Aydınlatma 
Metni kapsamında kişisel verilerimin işlenmesine, tereddüde yer vermeyecek 
şekilde bilgi sahibi olarak açık rızam ile onay veriyorum.

Kişisel verilerimin, ihtiyaçlarım doğrultusunda bana uygun ürün, uygulama, 
avantaj veya kampanyadan yararlanabilmem, genel bilgilendirme yapılması, 
tanıtım, reklam, promosyon, satış ve pazarlama, kutlama, temenni ve tarafımla 
her türlü iletişim sağlanması amacıyla işlenmesi ve bu doğrultuda iletişim 
adreslerime Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı 
FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI adına veya hizmet veren 3. kişiler 
tarafından telefon, çağrı merkezleri, faks, reklam hizmetleri, otomatik 
arama makineleri, akıllı ses kaydedici sistemler, elektronik posta 
(e-posta), kısa mesaj hizmeti (SMS), mobil uygulama anlık bildirimleri 
(push notification) gibi vasıtalar kullanılarak elektronik ortamda 
kanallarından iletilecek veri, ses ve görüntü içerikli bilgilendirme, 
tanıtım ve pazarlama iletilerinin gönderilmesine muvafakat ediyorum.

===============================================================================

GÖNDERİLEBİLECEK İLETİ İÇERİKLERİ

Onay vermeniz halinde aşağıdaki içerikler gönderilebilir:

1. KAMPANYA VE İNDİRİMLER
   - İndirim kodları ve kuponu
   - Yeni kullanıcı indirimleri
   - Özel gün indirimleri
   - Sadakat programı avantajları

2. HİZMET BİLGİLENDİRMELERİ
   - Yeni özellik duyuruları
   - Uygulama güncellemeleri
   - Hizmet alanı genişlemeleri
   - Fiyat değişiklikleri

3. KUTLAMA MESAJLARI
   - Resmi bayramlar (29 Ekim, 23 Nisan, 19 Mayıs, 30 Ağustos vb.)
   - Dini bayramlar (Ramazan, Kurban Bayramı)
   - Yeni yıl kutlamaları
   - Doğum günü kutlamaları (kayıtlıysa)

4. HATIRLATMALAR
   - Yaklaşan rezervasyon hatırlatması
   - Bekleyen ödeme bildirimi
   - Uzun süredir kullanılmayan hesap bildirimi

5. KİŞİSELLEŞTİRİLMİŞ ÖNERİLER
   - Sık kullanılan güzergahlar için özel fiyatlar
   - Tercih edilen saatlerde kampanyalar
   - İlgi alanlarınıza göre öneriler

===============================================================================

ONAY TERCİHLERİ (BİRBİRİNDEN BAĞIMSIZ)

Aşağıdaki onayları birbirinden bağımsız olarak verebilirsiniz:

☐ SMS bildirimleri almak istiyorum
☐ E-posta bildirimleri almak istiyorum
☐ Push notification (anlık bildirim) almak istiyorum
☐ Telefon araması almak istiyorum
☐ Kampanya ve indirim bildirimleri almak istiyorum
☐ Bayram kutlama mesajları almak istiyorum

NOT: İşlemsel bildirimler (yolculuk durumu, ödeme onayı, güvenlik uyarıları) 
onay gerektirmez ve her durumda gönderilir.

===============================================================================

ŞİRKET BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Mersis No         : 0388195898700001
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sayfası       : www.funbreakvale.com

===============================================================================

Versiyon: 4.0''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıt Ol'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.person_add,
                      size: 50,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Title
                const Text(
                  'Müşteri Kaydı',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bilgilerinizi girin',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Name Field
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.text,
                  enableSuggestions: true,
                  autocorrect: true,
                  decoration: const InputDecoration(
                    labelText: 'İsim Soyisim',
                    hintText: 'Ahmet Yılmaz',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'İsim soyisim gerekli';
                    }
                    if (value.trim().split(' ').length < 2) {
                      return 'Lütfen ad ve soyadınızı girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Phone Field
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10), // 10 haneli (5XXXXXXXXX)
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Telefon Numarası',
                    hintText: '5XX XXX XX XX',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    prefixText: '0',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Telefon numarası gerekli';
                    }
                    String cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
                    if (cleaned.length != 10) {
                      return 'Telefon numarası 10 haneli olmalı';
                    }
                    if (!cleaned.startsWith('5')) {
                      return 'Telefon numarası 5 ile başlamalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.text,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    hintText: 'ornek@email.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'E-posta gerekli';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Geçerli bir e-posta girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                
                // 📋 YASAL SÖZLEŞMELER BÖLÜMÜ
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.policy, size: 20, color: Colors.black87),
                          SizedBox(width: 8),
                          Text(
                            'Yasal Sözleşmeler',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // 1. KVKK AYDINLATMA METNİ - ZORUNLU!
                      CheckboxListTile(
                        value: _kvkkAccepted,
                        onChanged: (value) => setState(() => _kvkkAccepted = value ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.black87, fontSize: 13),
                            children: [
                              TextSpan(
                                text: 'KVKK Aydınlatma Metni',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _showKVKKDialog(),
                              ),
                              const TextSpan(text: '\'ni okudum, kabul ediyorum. '),
                              const TextSpan(
                                text: '*ZORUNLU',
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // 2. KULLANICI SÖZLEŞMESİ - ZORUNLU!
                      CheckboxListTile(
                        value: _userAgreementAccepted,
                        onChanged: (value) => setState(() => _userAgreementAccepted = value ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.black87, fontSize: 13),
                            children: [
                              TextSpan(
                                text: 'Kullanıcı Sözleşmesi',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _showUserAgreementDialog(),
                              ),
                              const TextSpan(text: '\'ni okudum, kabul ediyorum. '),
                              const TextSpan(
                                text: '*ZORUNLU',
                                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // 3. TİCARİ ELEKTRONİK İLETİ İZNİ - OPSİYONEL!
                      CheckboxListTile(
                        value: _commercialCommunicationAccepted,
                        onChanged: (value) => setState(() => _commercialCommunicationAccepted = value ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.black87, fontSize: 13),
                            children: [
                              TextSpan(
                                text: 'Ticari Elektronik İleti Onayı',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _showCommercialDialog(),
                              ),
                              const TextSpan(text: '\'ni kabul ediyorum. '),
                              const TextSpan(
                                text: '(Opsiyonel - Kampanya bildirimleri)',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Info Box - SMS bilgisi
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Kayıt sonrası telefonunuza SMS ile doğrulama kodu gönderilecektir.',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Register Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Kayıt Ol',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Zaten hesabınız var mı? '),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Giriş Yap',
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
