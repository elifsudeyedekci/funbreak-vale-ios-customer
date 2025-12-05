import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:io';

/// SÖZLEŞME GÜNCELLEME EKRANI
/// 
/// Bu ekran, kullanıcının kabul etmediği veya eski versiyonunu kabul ettiği
/// sözleşmeleri gösterir ve onay alır.
/// 
/// Kullanım:
/// Navigator.pushReplacement(context, MaterialPageRoute(
///   builder: (context) => ContractUpdateScreen(
///     customerId: 123,
///     pendingContracts: [...],
///     onAllAccepted: () => Navigator.pushReplacementNamed(context, '/home'),
///   ),
/// ));

class ContractUpdateScreen extends StatefulWidget {
  final int customerId;
  final List<Map<String, dynamic>> pendingContracts;
  final VoidCallback onAllAccepted;

  const ContractUpdateScreen({
    Key? key,
    required this.customerId,
    required this.pendingContracts,
    required this.onAllAccepted,
  }) : super(key: key);

  @override
  State<ContractUpdateScreen> createState() => _ContractUpdateScreenState();
}

class _ContractUpdateScreenState extends State<ContractUpdateScreen> {
  final Map<String, bool> _acceptedContracts = {};
  bool _isLoading = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Tüm sözleşmeleri onaylanmamış olarak başlat
    for (var contract in widget.pendingContracts) {
      _acceptedContracts[contract['type']] = false;
    }
  }

  bool get _allAccepted => _acceptedContracts.values.every((v) => v);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Geri tuşunu engelle - sözleşmeleri kabul etmeden çıkamaz
        _showExitWarning();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Sözleşme Güncelleme',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: _showExitWarning,
              child: const Text(
                'Çıkış',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // Progress Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Güncellenmiş Sözleşmeler',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      Text(
                        '${_acceptedContracts.values.where((v) => v).length}/${widget.pendingContracts.length}',
                        style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _acceptedContracts.values.where((v) => v).length / widget.pendingContracts.length,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  ),
                ],
              ),
            ),

            // Bilgi Banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sözleşmelerimiz güncellenmiştir. Devam etmek için yeni sözleşmeleri okumanız ve kabul etmeniz gerekmektedir.',
                      style: TextStyle(color: Colors.amber[200], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            // Sözleşme Listesi
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.pendingContracts.length,
                itemBuilder: (context, index) {
                  final contract = widget.pendingContracts[index];
                  final isAccepted = _acceptedContracts[contract['type']] ?? false;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isAccepted 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAccepted 
                          ? Colors.green.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isAccepted 
                            ? Colors.green.withOpacity(0.2)
                            : const Color(0xFFFFD700).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isAccepted ? Icons.check_circle : Icons.description,
                          color: isAccepted ? Colors.green : const Color(0xFFFFD700),
                        ),
                      ),
                      title: Text(
                        contract['title'] ?? 'Sözleşme',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'Versiyon: ${contract['latest_version']}',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                          if (contract['accepted_version'] != '0.0')
                            Text(
                              'Önceki: ${contract['accepted_version']}',
                              style: TextStyle(color: Colors.orange[300], fontSize: 11),
                            ),
                        ],
                      ),
                      trailing: isAccepted
                        ? const Icon(Icons.check, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () => _showContractDialog(contract),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Oku'),
                          ),
                      onTap: () => _showContractDialog(contract),
                    ),
                  );
                },
              ),
            ),

            // Alt Buton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _allAccepted && !_isLoading ? _submitAllContracts : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _allAccepted 
                        ? const Color(0xFFFFD700) 
                        : Colors.grey[700],
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                          _allAccepted 
                            ? 'Devam Et' 
                            : 'Tüm Sözleşmeleri Kabul Edin',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContractDialog(Map<String, dynamic> contract) {
    final type = contract['type'] as String;
    final title = contract['title'] as String;
    final content = _getContractContent(type);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: MediaQuery.of(context).size.width * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel, color: Colors.black),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Versiyon: ${contract['latest_version']}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // İçerik
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              // Butonlar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Kapat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _acceptedContracts[type] = true;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Okudum, Kabul Ediyorum',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
    );
  }

  void _showExitWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 12),
            Text('Dikkat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Sözleşmeleri kabul etmeden uygulamayı kullanamazsınız.\n\nÇıkmak istediğinize emin misiniz?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Uygulamadan çıkış
              exit(0);
            },
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAllContracts() async {
    if (!_allAccepted) return;

    setState(() => _isLoading = true);

    try {
      // Cihaz bilgilerini topla
      final deviceInfo = await _collectDeviceInfo();
      
      // Konum bilgisi topla
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print('⚠️ Konum alınamadı: $e');
      }

      // Her sözleşme için log kaydet
      for (var contract in widget.pendingContracts) {
        final type = contract['type'] as String;
        final version = contract['latest_version'] as String;
        final title = contract['title'] as String;

        print('📝 SÖZLEŞME LOG: $type v$version');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': widget.customerId,
            'user_type': 'customer',
            'consent_type': type,
            'consent_text': _getContractContent(type),
            'consent_summary': title,
            'consent_version': version,
            'ip_address': deviceInfo['ip_address'],
            'user_agent': deviceInfo['user_agent'],
            'device_fingerprint': deviceInfo['device_fingerprint'],
            'platform': deviceInfo['platform'],
            'os_version': deviceInfo['os_version'],
            'app_version': deviceInfo['app_version'],
            'latitude': position?.latitude,
            'longitude': position?.longitude,
            'location_accuracy': position?.accuracy,
            'language': 'tr',
          }),
        ).timeout(const Duration(seconds: 10));

        final apiData = jsonDecode(response.body);
        if (apiData['success'] == true) {
          print('✅ Sözleşme $type v$version loglandı - Log ID: ${apiData['log_id']}');
        } else {
          print('❌ Sözleşme $type log hatası: ${apiData['message']}');
        }
      }

      print('✅ TÜM SÖZLEŞMELER ONAYLANDI!');

      // Ana sayfaya yönlendir
      widget.onAllAccepted();

    } catch (e) {
      print('❌ Sözleşme kayıt hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    final fingerprint = DateTime.now().millisecondsSinceEpoch.toString() + 
                       '_customer_' + 
                       widget.customerId.toString();
    
    return {
      'platform': platform,
      'os_version': Platform.operatingSystemVersion,
      'app_version': '2.0.0',
      'device_fingerprint': fingerprint,
      'user_agent': 'FunBreak Vale Customer/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto',
    };
  }

  String _getContractContent(String type) {
    switch (type) {
      case 'kvkk':
        return _getKVKKText();
      case 'user_agreement':
        return _getUserAgreementText();
      case 'commercial_communication':
        return _getCommercialText();
      default:
        return 'Sözleşme içeriği yüklenemedi.';
    }
  }

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

Versiyon: 2.0 | Tarih: 28 Kasım 2025''';
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

Versiyon: 2.0 | Tarih: 28 Kasım 2025''';
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

Versiyon: 2.0 | Tarih: 28 Kasım 2025''';
  }
}

