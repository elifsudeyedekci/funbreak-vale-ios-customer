import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  
  // YASAL SÖZLEŞME ONAYLARI - ZORUNLU!
  bool _kvkkAccepted = false;
  bool _userAgreementAccepted = false;
  bool _commercialCommunicationAccepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müşteri Kaydı'),
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
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 60,
                    color: Colors.black,
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
                  'Vale hizmeti için kayıt olun',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Full Name Field
                TextFormField(
                  controller: _fullNameController,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  enableSuggestions: true,
                  autocorrect: true,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ad soyad gerekli';
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
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'E-posta gerekli';
                    }
                    if (!value.contains('@')) {
                      return 'Geçerli bir e-posta girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Phone Field
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Telefon gerekli';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre gerekli';
                    }
                    if (value.length < 6) {
                      return 'Şifre en az 6 karakter olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Confirm Password Field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre Tekrar',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Şifre tekrarı gerekli';
                    }
                    if (value != _passwordController.text) {
                      return 'Şifreler eşleşmiyor';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // YASAL SÖZLEŞMELER - ZORUNLU!
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.gavel, color: Colors.blue, size: 20),
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
                const SizedBox(height: 20),
                
                // Register Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text(
                            'Kayıt Ol',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Giriş Yap',
                        style: TextStyle(color: Color(0xFFFFD700)),
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // YASAL SÖZLEŞME KONTROL - ZORUNLU!
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

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (success) {
        // KAYIT BAŞARILI - YASAL LOG KAYDET!
        // Customer ID'yi AuthProvider'dan al - register() SUCCESS ise _customerId set edilmiştir!
        final customerId = int.tryParse(authProvider.customerId ?? '0') ?? 0;
        
        print('📋 YASAL LOG: Kayıt başarılı, Customer ID: $customerId');
        print('📊 YASAL LOG DEBUG:');
        print('   authProvider.customerId: ${authProvider.customerId}');
        print('   _kvkkAccepted: $_kvkkAccepted');
        print('   _userAgreementAccepted: $_userAgreementAccepted');
        print('   _commercialCommunicationAccepted: $_commercialCommunicationAccepted');
        
        if (customerId > 0) {
          await _logLegalConsents(customerId);
          print('✅ YASAL LOG: Sözleşmeler loglandı - Customer ID: $customerId');
        } else {
          print('❌ YASAL LOG: Customer ID BULUNAMADI - authProvider.customerId DOLU DEĞİL!');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Kayıt başarılı! Giriş yapabilirsiniz.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? 'Kayıt başarısız'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // YASAL ONAYLARI LOGLA - MAHKEME DELİLİ!
  Future<void> _logLegalConsents(int customerId) async {
    try {
      // Device bilgilerini topla
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
        print('   User ID: $customerId');
        print('   Text Length: ${(consent['text'] as String).length}');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': customerId,
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
  
  // CİHAZ BİLGİLERİNİ TOPLA - BASİT VERSİYON (device_info_plus OLMADAN)
  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    // Platform bilgisi - Flutter yerleşik
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    
    // Benzersiz fingerprint - timestamp bazlı
    final fingerprint = DateTime.now().millisecondsSinceEpoch.toString() + 
                       '_' + 
                       (_emailController.text.hashCode.toString());
    
    return {
      'platform': platform,
      'os_version': Platform.operatingSystemVersion, // Android 13 / iOS 17 gibi
      'app_version': '1.0.0',
      'device_model': 'auto', // Backend'den tespit edilebilir
      'device_manufacturer': 'auto',
      'device_fingerprint': fingerprint,
      'user_agent': 'FunBreak Customer App/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto', // Backend otomatik alacak
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
    return '''FUNBREAK VALE
YOLCULAR İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK AYDINLATMA METNİ

VERİ SORUMLUSU BİLGİLERİ
Ticaret Ünvanı: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Ticaret Sicil No: 1105910
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web Sitesi: www.funbreakvale.com

GİRİŞ
6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında kişisel verilerinizin işlenmesine ilişkin aydınlatma yükümlülüğümüzü yerine getirmekteyiz.

A. İŞLENEN KİŞİSEL VERİ KATEGORİLERİ

1. Kimlik Bilgileri: Ad, soyad, T.C. kimlik numarası, doğum tarihi
2. İletişim Bilgileri: Telefon numarası, e-posta adresi, adres bilgileri
3. Müşteri İşlem Bilgileri: Yolculuk geçmişi, rezervasyon bilgileri, ödeme kayıtları
4. Lokasyon Verileri: GPS konum bilgileri, alış-bırakış noktaları, rota bilgileri
5. Finansal Bilgiler: Ödeme yöntemi, kart bilgileri (maskelenmiş), fatura bilgileri
6. Pazarlama Bilgileri: Tercihler, kampanya katılımları
7. Cihaz/Teknik Veriler: IP adresi, cihaz kimliği, uygulama versiyonu

B. KİŞİSEL VERİLERİN İŞLENME AMAÇLARI

• Vale hizmetinin sunulması ve yolculuk organizasyonu
• Müşteri hesabı oluşturma ve yönetimi
• Ödeme işlemlerinin gerçekleştirilmesi
• Müşteri destek hizmetleri
• Hizmet kalitesinin ölçülmesi ve iyileştirilmesi
• Yasal yükümlülüklerin yerine getirilmesi
• Güvenlik ve dolandırıcılık önleme
• Kampanya ve promosyon bildirimleri (onayınız dahilinde)

C. KİŞİSEL VERİLERİN AKTARIMI

Kişisel verileriniz;
• Vale (sürücü) ile yolculuk eşleştirmesi için
• Ödeme kuruluşları ile ödeme işlemleri için
• Yasal zorunluluklar kapsamında yetkili kurumlarla
• Hizmet sağlayıcılar (SMS, e-posta) ile
paylaşılabilir.

D. VERİ TOPLAMA YÖNTEMİ VE HUKUKİ SEBEBİ

Verileriniz; mobil uygulama, web sitesi ve müşteri hizmetleri kanalları aracılığıyla toplanmaktadır.

Hukuki Sebepler:
• Sözleşmenin ifası (KVKK m.5/2-c)
• Yasal yükümlülük (KVKK m.5/2-ç)
• Meşru menfaat (KVKK m.5/2-f)
• Açık rıza (KVKK m.5/1)

E. KİŞİSEL VERİ SAHİBİNİN HAKLARI (KVKK m.11)

• Kişisel verilerinizin işlenip işlenmediğini öğrenme
• İşlenmişse buna ilişkin bilgi talep etme
• İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme
• Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme
• Eksik veya yanlış işlenmişse düzeltilmesini isteme
• KVKK m.7 kapsamında silinmesini veya yok edilmesini isteme
• Düzeltme, silme, yok etme işlemlerinin aktarıldığı üçüncü kişilere bildirilmesini isteme
• İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme
• Kanuna aykırı işleme sebebiyle zarara uğramanız halinde zararın giderilmesini talep etme

F. BAŞVURU YÖNTEMİ

Haklarınızı kullanmak için info@funbreakvale.com adresine yazılı başvuruda bulunabilirsiniz.

Versiyon: 4.0 | Tarih: 28 Kasım 2025''';
  }
  
  String _getUserAgreementText() {
    return '''FUNBREAK VALE
YOLCU (MÜŞTERİ) KULLANIM KOŞULLARI SÖZLEŞMESİ

1. TARAFLAR
İşbu Sözleşme, Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale") ile mobil uygulama üzerinden hizmet alan Yolcu ("Müşteri") arasındadır.

2. HİZMET TANIMI
FunBreak Vale, Yolcu'nun aracını belirlenen noktadan alıp istenen konuma götüren profesyonel vale (valet) ve özel şoför hizmeti sunan bir mobil uygulama platformudur.

3. KULLANIM ŞARTLARI
• 18 yaşını doldurmuş olmak
• Geçerli bir telefon numarası ve e-posta adresi
• Doğru konum ve kişisel bilgi paylaşımı
• Aracın yasal belgelerinin eksiksiz olması
• Ödeme yükümlülüklerini zamanında yerine getirmek

4. FİYATLANDIRMA VE ÖDEME

4.1. Mesafe Bazlı Fiyatlandırma:
• 0-5 km: 1.500 TL
• 5-10 km: 1.700 TL
• 10-15 km: 1.900 TL
• 15-20 km: 2.100 TL
• 20-25 km: 2.300 TL
• 25-30 km: 2.500 TL
• 30-35 km: 2.700 TL
• 35-40 km: 2.900 TL

4.2. Bekleme Ücreti:
İlk 15 dakika ücretsizdir. Sonraki her 15 dakika veya kesri için 200 TL ücret uygulanır.

4.3. Saatlik Paketler:
• 0-4 saat: 3.000 TL
• 4-8 saat: 4.500 TL
• 8-12 saat: 6.000 TL

4.4. Özel Konum Ücreti:
Havalimanı, marina, özel bölge gibi lokasyonlar için ek ücret uygulanabilir.

5. İPTAL VE İADE KOŞULLARI
• 45 dakika veya daha fazla kala iptal: Ücretsiz
• 45 dakikadan az kala iptal: 1.500 TL iptal ücreti
• Yolculuk başladıktan sonra iptal: Tam ücret tahsil edilir
• Şoför bulunamadan iptal: Ücretsiz

6. YOLCU'NUN YÜKÜMLÜLÜKLERİ
• Doğru ve güncel bilgi vermek
• Araç anahtarlarını teslim etmek
• Araçta yasadışı madde bulundurmamak
• Şoföre saygılı davranmak
• Ödeme yükümlülüklerini yerine getirmek

7. FUNBREAK VALE'NİN SORUMLULUKLARI
• Profesyonel ve güvenilir hizmet sunmak
• Eğitimli sürücüler sağlamak
• Kişisel verileri korumak
• Müşteri desteği sağlamak

8. SORUMLULUK SINIRI
• Araç içinde bırakılan değerli eşyalardan FunBreak Vale sorumlu değildir
• Trafik koşulları ve mücbir sebeplerden kaynaklanan gecikmelerden sorumluluk kabul edilmez
• Yanlış adres bilgisi verilmesinden kaynaklanan sorunlardan Yolcu sorumludur

9. KİŞİSEL VERİLERİN KORUNMASI
Kişisel verileriniz 6698 sayılı KVKK kapsamında korunmaktadır. Detaylı bilgi için KVKK Aydınlatma Metni'ni inceleyiniz.

10. YETKİLİ MAHKEME
İşbu sözleşmeden doğan uyuşmazlıklarda İstanbul (Çağlayan) Mahkemeleri yetkilidir.

11. YÜRÜRLÜK
Bu sözleşme, Yolcu'nun uygulamaya kayıt olması ile yürürlüğe girer.

FunBreak Global Teknoloji Limited Şirketi
Mersis No: 0388195898700001
info@funbreakvale.com | www.funbreakvale.com

Versiyon: 4.0 | Tarih: 28 Kasım 2025''';
  }
  
  String _getCommercialText() {
    return '''TİCARİ ELEKTRONİK İLETİ ONAYI

6563 sayılı Elektronik Ticaretin Düzenlenmesi Hakkında Kanun ve ilgili mevzuat uyarınca:

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale") tarafından;

• Kampanya, indirim ve promosyon bildirimleri
• Yeni özellik ve hizmet duyuruları
• Özel fırsatlar ve kişiselleştirilmiş teklifler
• Anket ve geri bildirim talepleri
• Etkinlik ve organizasyon bildirimleri

konularında SMS, e-posta, push bildirim ve telefon yoluyla ticari elektronik ileti almayı AÇIK RIZAMLA kabul ediyorum.

İZNİN GERİ ALINMASI:
Bu iznimi dilediğim zaman aşağıdaki yöntemlerle geri alabilirim:
• E-posta: info@funbreakvale.com
• Uygulama içi ayarlar
• SMS ile "IPTAL" yazarak

İzin geri alındıktan sonra 3 iş günü içinde ticari ileti gönderimi durdurulacaktır.

VERİ SORUMLUSU:
FunBreak Global Teknoloji Limited Şirketi
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Mersis No: 0388195898700001

Versiyon: 4.0 | Tarih: 28 Kasım 2025''';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
 
