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
      _phoneController.text = widget.prefilledPhone!;
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
  
  // SÖZLEŞME METİNLERİ
  String _getKVKKText() {
    // Kullanıcı bilgileri otomatik doldurulacak (backend log_legal_consent.php'de)
    return '''FUNBREAK VALE - YOLCULAR İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK AYDINLATMA METNİ

VERİ SORUMLUSU BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sitesi        : www.funbreakvale.com

════════════════════════════════════════════════════════════════════════════════

GİRİŞ

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") uyarınca, FunBreak Vale olarak kişisel verilerinizin hangi amaçla işleneceğini, kimlere aktarılacağını, toplama yöntemini ve haklarınızı aşağıda açıklamaktayız.

════════════════════════════════════════════════════════════════════════════════

A. KİŞİSEL VERİ KATEGORİLERİ VE İŞLENME AMAÇLARI

1. KİMLİK BİLGİSİ
   • Ad, Soyad, T.C. Kimlik No, Doğum Tarihi, Profil Fotoğrafı
   • Amaç: Kimlik tespiti, platform güvenliği, vale eşleştirme

2. İLETİŞİM BİLGİSİ
   • Telefon, E-posta, İkametgah, Kayıtlı Adresler
   • Amaç: İletişim, bilgilendirme, tebligat, acil durum

3. FİNANSAL BİLGİ
   • Kart bilgisi (ilk 6+son 2 hane), IBAN, Ödeme geçmişi, İndirim kodları
   • Amaç: Ödeme tahsili, fatura düzenleme, muhasebe

4. YOLCULUK VERİLERİ
   • Alış/Varış noktaları, Rota, GPS konumu, Mesafe, Süre, Bekleme
   • Amaç: Hizmet sunumu, ücretlendirme, takip, güvenlik

5. ARAÇ BİLGİSİ
   • Plaka, Marka/Model, Renk, Yıl, Ruhsat
   • Amaç: Vale'nin doğru aracı tanıması, güvenlik

6. DEĞERLENDİRME BİLGİSİ
   • Puanlar, Yorumlar, Şikayetler
   • Amaç: Hizmet kalitesi, performans değerlendirme

7. LOKASYON BİLGİSİ
   • Canlı GPS konumu (vale çağırırken), Kayıtlı adresler
   • Amaç: Vale eşleştirme, mesafe hesaplama
   • NOT: Yolculuk sırasında Vale'nin konumu takip edilir, Yolcu'nun değil

8. CİHAZ BİLGİSİ
   • Device ID, İşletim sistemi, IP adresi, Tarayıcı
   • Amaç: Teknik destek, güvenlik, uygulama performansı

9. MESAJLAŞMA KAYITLARI
   • Vale ile mesajlar, Destek talepleri, Şikayetler, Köprü arama kayıtları
   • Amaç: Hizmet kalitesi, uyuşmazlık çözümü, delil

10. ÇEREZ VERİLERİ
    • Zorunlu/Fonksiyonel/Analitik/Reklam çerezleri
    • Amaç: Uygulama işlevselliği, kullanıcı deneyimi, pazarlama

════════════════════════════════════════════════════════════════════════════════

B. VERİLERİN TOPLANMA YÖNTEMİ

• Kayıt/Üyelik formları
• Mobil uygulama kullanımı (GPS, mesajlaşma, işlemler)
• Web sitesi (form, çerez)
• Sistem kayıtları (sunucu log, API)
• Müşteri hizmetleri (telefon, e-posta, canlı destek)
• Üçüncü taraf entegrasyonlar (ödeme, SMS, harita)

════════════════════════════════════════════════════════════════════════════════

C. VERİLERİN AKTARILMASI

1. VALE'LERE: Ad-Soyad, Profil Fotoğrafı, Telefon (gizli), Adresler, Puan
2. GRUP ŞİRKETLERİ: Tüm veriler (ortak hizmet, teknik destek, raporlama)
3. HİZMET SAĞLAYICILARA: AWS, SMS, Ödeme, Google Maps, NetGSM, Analytics
4. HUKUK MÜŞAVİRLERİ: Yasal süreç gerektiren veriler
5. KAMU KURUMLARINA: Emniyet, Mahkeme, Vergi Dairesi (kanuni yükümlülük)
6. YURT DIŞINA: Bulut sunucu, analitik hizmetler (açık rıza ile)

════════════════════════════════════════════════════════════════════════════════

D. HAKLARINIZ (KVKK Madde 11)

• Kişisel verilerinizin işlenip işlenmediğini öğrenme
• İşlenmişse bilgi talep etme
• İşlenme amacını ve uygunluğunu öğrenme
• Aktarıldığı üçüncü kişileri bilme
• Eksik/yanlış verilerin düzeltilmesini isteme
• Verilerin silinmesini/yok edilmesini isteme
• İşlemlerin üçüncü kişilere bildirilmesini isteme
• Otomatik sistemlerle analiz sonucuna itiraz etme
• Kanuna aykırı işlemeden zarar görürse tazminat talep etme

BAŞVURU YÖNTEMİ:
• Yazılı: Armağanevler Mah. Ortanca Sk. No:69/22 Ümraniye/İstanbul
• E-posta: info@funbreakvale.com (güvenli e-imza ile)
• Web: www.funbreakvale.com/kvkk-basvuru
• Mobil: Ayarlar > KVKK > Başvuru Yap

Başvurular 30 gün içinde cevaplanır.

════════════════════════════════════════════════════════════════════════════════

E. SAKLAMA SÜRESİ

• Kimlik/İletişim: Üyelik + 10 yıl
• Finansal: 10 yıl (Vergi Usul Kanunu)
• Yolculuk Kayıtları: 5 yıl
• GPS/Konum: 2 yıl
• Mesajlaşma: 2 yıl
• Değerlendirme: 3 yıl
• Çerezler: 6 ay - 2 yıl

════════════════════════════════════════════════════════════════════════════════

F. VERİ GÜVENLİĞİ

• SSL/TLS şifreleme (256-bit)
• Güvenlik duvarı, yedekleme
• Erişim logları, şifreli saklama
• PCI DSS uyum, 3D Secure
• Personel eğitimi, gizlilik sözleşmeleri

════════════════════════════════════════════════════════════════════════════════

İLETİŞİM

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Armağanevler Mah. Ortanca Sk. No: 69/22 Ümraniye/İstanbul
Tel: 0533 448 82 53 | E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

════════════════════════════════════════════════════════════════════════════════

AÇIK RIZA BEYANI

Bu Aydınlatma Metni'ni okuyup anladığımı, özgür irademle kabul ettiğimi ve kişisel verilerimin işlenmesine ve yurt dışına aktarılmasına izin verdiğimi beyan ederim.

YOLCU BİLGİLERİ (Otomatik Doldurulacak):
• Ad Soyad: [Sisteme kayıtlı bilgi]
• Telefon: [Sisteme kayıtlı bilgi]
• E-posta: [Sisteme kayıtlı bilgi]
• IP Adresi: [Otomatik]
• Cihaz ID: [Otomatik]
• GPS Konum: [Otomatik]
• Tarih/Saat: [Otomatik]

Son Güncelleme: 28 Kasım 2025 | Versiyon: 2.0''';
  }
  
  String _getUserAgreementText() {
    // Kullanıcı bilgileri otomatik doldurulacak (backend log_legal_consent.php'de)
    return '''FUNBREAK VALE - YOLCU (MÜŞTERİ) KULLANIM KOŞULLARI SÖZLEŞMESİ

════════════════════════════════════════════════════════════════════════════════

1. TARAFLAR

İşbu Sözleşme, Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI ("FunBreak Vale") ile mobil uygulama üzerinden özel şoför ve vale hizmeti alan ("Yolcu" veya "Müşteri") arasındadır.

════════════════════════════════════════════════════════════════════════════════

2. SÖZLEŞMENİN AMACI VE KONUSU

2.1. Bu Sözleşme, Yolcu için özel şoför ve vale bulma hizmetini sunan FunBreak Vale ile Yolcu arasındaki mobil uygulama kullanımına ilişkin hak ve yükümlülükleri belirtir.

2.2. FunBreak Vale, Yolcu ile Vale (sürücü) arasında aracılık hizmeti sunan bir teknoloji platformudur.

════════════════════════════════════════════════════════════════════════════════

3. KULLANIM KOŞULLARI

3.1. GENEL ŞARTLAR
• Yolcu, mobil uygulama üzerinden kullanıcı adı ve şifresi ile hizmet alabilir
• Vale (sürücü), algoritma ile belirlenir (konum, yoğunluk, performans)
• Vale, Yolcunun aracı ile Yolcuyu belirttiği lokasyona transfer eder

3.2. KAYIT ŞARTLARI
• En az 18 yaşında ve medeni hakları kullanma ehliyetine sahip olmak
• Doğru, kesin ve güncel bilgi vermek
• Gerekli bilgiler: Ad-Soyad, T.C. Kimlik No, Telefon, E-posta, Ödeme Bilgisi

════════════════════════════════════════════════════════════════════════════════

4. HİZMET ALMA SÜRECİ

a) Yolcu, mobil uygulama üzerinden alış ve varış lokasyonunu seçerek Vale çağırır
b) Sistem tahmini fiyat gösterir
c) Vale bulunduğunda bildirim gelir
d) Yolcu, harita üzerinden Vale'yi canlı takip edebilir
e) Yolcu, köprü arama sistemi ile iletişime geçebilir
f) Yolculuk rotası ve bekleme noktaları otomatik kaydedilir
g) Ödeme yapılana kadar yeni yolculuk başlatılamaz
h) Yolcu, yolculuk sonunda Vale'yi 1-5 yıldız puanlayabilir

════════════════════════════════════════════════════════════════════════════════

5. FİYATLANDIRMA VE ÖDEME

• Mesafe bazlı fiyatlandırma
• Bekleme ücreti: İlk 15 dakika ücretsiz, sonrası 200 TL/15 dakika
• Saatlik paketler mevcut
• Ödeme: Kredi/Banka Kartı (3D Secure), Havale/EFT

════════════════════════════════════════════════════════════════════════════════

6. İPTAL VE İADE

• Vale atanmadan iptal: ÜCRETSİZ
• Vale atandıktan sonra (45 dakikadan fazla kala): ÜCRETSİZ
• Vale atandıktan sonra (45 dakikadan az kala): Sabit iptal ücreti
• Yolculuk başladıktan sonra: Tam ücret tahsil edilir

════════════════════════════════════════════════════════════════════════════════

7. KİŞİSEL VERİLERİN KORUNMASI

Yolcu, KVKK Aydınlatma Metni kapsamında kişisel verilerinin işleneceğini kabul eder.

════════════════════════════════════════════════════════════════════════════════

8. YETKİLİ MAHKEME

İşbu Sözleşmeden doğan uyuşmazlıklarda İstanbul (Çağlayan) Mahkemeleri yetkilidir.

════════════════════════════════════════════════════════════════════════════════

ŞİRKET BİLGİLERİ

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Mersis No: 0388195898700001 | Ticaret Sicil: 1105910
Adres: Armağanevler Mah. Ortanca Sk. No: 69/22 Ümraniye/İstanbul
Tel: 0533 448 82 53 | E-posta: info@funbreakvale.com

════════════════════════════════════════════════════════════════════════════════

YOLCU BİLGİLERİ (Otomatik Doldurulacak):
• Ad Soyad: [Sisteme kayıtlı bilgi]
• Telefon: [Sisteme kayıtlı bilgi]
• E-posta: [Sisteme kayıtlı bilgi]
• IP Adresi: [Otomatik]
• Cihaz ID: [Otomatik]
• Tarih/Saat: [Otomatik]

Son Güncelleme: 28 Kasım 2025 | Versiyon: 2.0''';
  }
  
  String _getCommercialText() {
    // Kullanıcı bilgileri otomatik doldurulacak (backend log_legal_consent.php'de)
    return '''FUNBREAK VALE - TİCARİ ELEKTRONİK İLETİ ONAYI

════════════════════════════════════════════════════════════════════════════════

YASAL DAYANAK

6698 sayılı KVKK, 6563 sayılı Elektronik Ticaret Kanunu ve 29417 sayılı Yönetmelik kapsamında FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI olarak ticari elektronik ileti onayınızı almak istiyoruz.

════════════════════════════════════════════════════════════════════════════════

GÖNDERİLEBİLECEK İLETİ TÜRLERİ

1. KAMPANYA VE PROMOSYON
   • İndirim kodları ve kuponlar
   • Özel kampanyalar ve fırsatlar

2. BİLGİLENDİRME
   • Yeni özellik duyuruları
   • Uygulama güncellemeleri

3. KUTLAMA VE TEMENNİ
   • Resmi ve dini bayramlar
   • Doğum günü kutlamaları

4. HATIRLATMA
   • Rezervasyon ve ödeme hatırlatmaları

════════════════════════════════════════════════════════════════════════════════

RED VE GERİ ÇEKME HAKKI

Dilediğiniz zaman ÜCRETSİZ olarak reddedebilirsiniz:
• Mobil Uygulama: Ayarlar > Bildirim Tercihleri
• E-posta: "Abonelikten Çık" linki
• Müşteri Hizmetleri: info@funbreakvale.com

════════════════════════════════════════════════════════════════════════════════

ÖNEMLİ NOTLAR

⚠️ Bu onay OPSİYONELDİR. Onay vermemeniz hizmetlerden yararlanmanızı engellemez.
⚠️ İŞLEMSEL BİLDİRİMLER (yolculuk durumu, ödeme onayı) bu onaydan bağımsızdır.

════════════════════════════════════════════════════════════════════════════════

ŞİRKET BİLGİLERİ

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Tel: 0533 448 82 53 | E-posta: info@funbreakvale.com

════════════════════════════════════════════════════════════════════════════════

YOLCU BİLGİLERİ (Otomatik Doldurulacak):
• Ad Soyad: [Sisteme kayıtlı bilgi]
• Telefon: [Sisteme kayıtlı bilgi]
• E-posta: [Sisteme kayıtlı bilgi]
• IP Adresi: [Otomatik]
• Tarih/Saat: [Otomatik]

Son Güncelleme: 28 Kasım 2025 | Versiyon: 2.0''';
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
                
                // Register Button - ZORUNLU SÖZLEŞMELER KABUL EDİLMEDEN AKTİF OLMAZ!
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_kvkkAccepted || !_userAgreementAccepted) ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_kvkkAccepted && _userAgreementAccepted) 
                          ? const Color(0xFFFFD700) 
                          : Colors.grey[400],
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[600],
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
                        : Text(
                            (_kvkkAccepted && _userAgreementAccepted) 
                                ? 'Kayıt Ol' 
                                : 'Zorunlu Sözleşmeleri Kabul Edin',
                            style: const TextStyle(
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
