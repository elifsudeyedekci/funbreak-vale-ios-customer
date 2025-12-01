import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/language_provider.dart';

class TermsScreen extends StatelessWidget {
  final String termsType; // 'conditions' veya 'contract'
  
  const TermsScreen({
    Key? key,
    required this.termsType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text(
          _getTitle(languageProvider.currentLanguage),
          style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.gavel,
                    color: const Color(0xFFFFD700),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getTitle(languageProvider.currentLanguage),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // İçerik
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getContent(languageProvider.currentLanguage),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Şirket Bilgileri
            _buildCompanyInfo(themeProvider, languageProvider),
            
            const SizedBox(height: 30),
            
            // Son Güncelleme
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                languageProvider.currentLanguage == 'en' 
                    ? 'Last Updated: September 2025'
                    : 'Son Güncelleme: Eylül 2025',
                style: TextStyle(
                  fontSize: 12,
                  color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getTitle(String language) {
    if (termsType == 'conditions') {
      return language == 'en' ? 'Pre-Information Terms' : 'Ön Bilgilendirme Koşulları';
    } else {
      return language == 'en' ? 'Distance Sales Contract' : 'Mesafeli Satış Sözleşmesi';
    }
  }
  
  String _getContent(String language) {
    if (language == 'en') {
      return _getEnglishContent();
    } else {
      return _getTurkishContent();
    }
  }
  
  String _getTurkishContent() {
    if (termsType == 'conditions') {
      return '''
ÖN BİLGİLENDİRME FORMU

SATICI BİLGİLERİ
Ticaret Unvanı: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Ticaret Sicil No: 1105910
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web Sitesi: www.funbreakvale.com

1. HİZMETİN TEMEL NİTELİKLERİ
FunBreak Vale, profesyonel vale ve özel şoför hizmeti sunan bir mobil uygulama platformudur.

Hizmet Türleri:
• Anında Vale Hizmeti: Bulunduğunuz konumdan aracınızı belirlediğiniz noktaya götürme
• Saatlik Paket: Belirli süreler için özel şoför hizmeti
• Rezervasyon: İleri tarihli hizmet planlama

2. HİZMET BEDELİ VE ÖDEME KOŞULLARI

Mesafe Bazlı Fiyatlandırma:
• 0-5 km: 1.500 TL
• 5-10 km: 1.700 TL
• 10-15 km: 1.900 TL
• 15-20 km: 2.100 TL
• 20-25 km: 2.300 TL
• 25-30 km: 2.500 TL
• 30-35 km: 2.700 TL
• 35-40 km: 2.900 TL

Saatlik Paketler:
• 0-4 Saat: 3.000 TL
• 4-8 Saat: 4.500 TL
• 8-12 Saat: 6.000 TL

Bekleme Ücreti:
• İlk 15 dakika: Ücretsiz
• Sonraki her 15 dakika: 200 TL

Özel Konum Ücreti:
Havalimanı, marina ve benzeri lokasyonlarda ek ücret uygulanabilir.

Ödeme Yöntemleri: Kredi kartı, banka kartı, havale/EFT

3. TESLİMAT VE İFA KOŞULLARI
• Hizmet, müşterinin belirttiği adresten başlar
• Vale, müşterinin aracını teslim alarak hedef konuma götürür
• Hizmet tamamlandığında araç müşteriye teslim edilir
• Konum takibi uygulama üzerinden yapılabilir

4. CAYMA HAKKI
6502 sayılı Tüketicinin Korunması Hakkında Kanun uyarınca:
• 45 dakika veya daha fazla kala iptal: Ücretsiz
• 45 dakikadan az kala iptal: 1.500 TL iptal ücreti
• Hizmet başladıktan sonra cayma hakkı kullanılamaz

5. ŞİKAYET VE İTİRAZ
Şikayetleriniz için:
• E-posta: info@funbreakvale.com
• Telefon: 0533 448 82 53
• Uygulama içi destek

6. YETKİLİ MAHKEME
Uyuşmazlıklarda İstanbul (Çağlayan) Mahkemeleri ve İcra Müdürlükleri yetkilidir.

Son Güncelleme: 28 Kasım 2025 | Versiyon: 2.0
''';
    } else {
      return '''
MESAFELİ SATIŞ SÖZLEŞMESİ

1. TARAFLAR

SATICI:
Ticaret Unvanı: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Ticaret Sicil No: 1105910
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

ALICI (MÜŞTERİ):
Ad Soyad: [Uygulama kaydındaki bilgiler]
Telefon: [Kayıtlı telefon numarası]
E-posta: [Kayıtlı e-posta adresi]

2. SÖZLEŞMENİN KONUSU
İşbu sözleşme, 6502 sayılı Tüketicinin Korunması Hakkında Kanun ve Mesafeli Sözleşmeler Yönetmeliği hükümleri uyarınca tarafların hak ve yükümlülüklerini düzenler.

3. HİZMETİN TEMEL NİTELİKLERİ
FunBreak Vale, profesyonel vale ve özel şoför hizmeti sunan bir mobil uygulama platformudur.

Sunulan Hizmetler:
• Anında Vale Hizmeti
• Saatlik Paket Hizmeti
• Rezervasyon Hizmeti
• Havalimanı Transfer Hizmeti

4. HİZMET BEDELİ

4.1. Mesafe Bazlı Fiyatlandırma:
• 0-5 km: 1.500 TL
• 5-10 km: 1.700 TL
• 10-15 km: 1.900 TL
• 15-20 km: 2.100 TL
• 20-25 km: 2.300 TL
• 25-30 km: 2.500 TL
• 30-35 km: 2.700 TL
• 35-40 km: 2.900 TL

4.2. Saatlik Paketler:
• 0-4 Saat: 3.000 TL
• 4-8 Saat: 4.500 TL
• 8-12 Saat: 6.000 TL

4.3. Bekleme Ücreti:
İlk 15 dakika ücretsiz, sonraki her 15 dakika 200 TL

4.4. Tüm fiyatlar Türk Lirası cinsinden ve KDV dahildir.

5. ÖDEME ŞEKLİ
• Kredi Kartı / Banka Kartı
• Havale / EFT
• Ödeme, hizmet tamamlandıktan sonra tahsil edilir

6. TESLİMAT
• Hizmet, müşterinin belirttiği adreste başlar
• Vale, aracı teslim alır ve belirlenen konuma götürür
• Hizmet tamamlanma süresi trafik koşullarına göre değişebilir

7. CAYMA HAKKI

7.1. Tüketici, hizmet başlamadan önce cayma hakkına sahiptir.

7.2. Cayma Koşulları:
• 45 dakika veya daha fazla kala: Ücretsiz iptal
• 45 dakikadan az kala: 1.500 TL iptal ücreti uygulanır

7.3. Hizmet başladıktan sonra cayma hakkı kullanılamaz (6502 sayılı Kanun m.15/ğ).

7.4. Cayma bildirimi için:
• E-posta: info@funbreakvale.com
• Telefon: 0533 448 82 53
• Uygulama içi iptal butonu

8. GENEL HÜKÜMLER

8.1. Satıcı, hizmet kalitesi için azami özeni gösterir.

8.2. Mücbir sebep hallerinde (doğal afet, savaş, grev vb.) satıcı sorumlu tutulamaz.

8.3. Araç içinde bırakılan değerli eşyalardan satıcı sorumlu değildir.

9. UYUŞMAZLIK ÇÖZÜMÜ
İşbu sözleşmeden doğan uyuşmazlıklarda İstanbul (Çağlayan) Mahkemeleri ve İcra Müdürlükleri yetkilidir.

10. YÜRÜRLÜK
Bu sözleşme, müşterinin elektronik ortamda onay vermesiyle yürürlüğe girer.

İşbu sözleşme, Ön Bilgilendirme Formu ile birlikte geçerlidir.

Son Güncelleme: 28 Kasım 2025 | Versiyon: 2.0
''';
    }
  }
  
  String _getEnglishContent() {
    if (termsType == 'conditions') {
      return '''
PRE-INFORMATION TERMS

1. SERVICE DEFINITION
FunBreak Vale provides professional driver services including:
- Personal driver service
- Hourly package services  
- Special event transfers
- Airport transfer services

2. PRICING
- Distance-based pricing calculation
- Traffic conditions affect pricing
- Additional fees for waiting time
- Special location surcharges may apply

3. PAYMENT TERMS
- Payment after service completion
- Credit card and cash payments accepted
- Discount codes applied when valid

4. CANCELLATION TERMS
- Free cancellation until 30 minutes before service
- Late cancellation incurs 50% fee
- No cancellation after service starts

5. OUR RESPONSIBILITIES
- Safe and comfortable transportation
- Experienced and reliable drivers
- 24/7 customer service
- Insured vehicles and service

6. CUSTOMER RESPONSIBILITIES
- Provide accurate address information
- Be ready on time
- Payment obligation
- Comply with service rules

By accepting these terms, you agree to use our service.
''';
    } else {
      return '''
DISTANCE SALES CONTRACT

SELLER INFORMATION:
Trade Name: FunBreak Vale Services Ltd.
Address: Istanbul, Turkey
Phone: +90 555 123 45 67
Email: info@funbreakvale.com
Web: www.funbreakvale.com

CUSTOMER RIGHTS:
1. Right of Withdrawal: Until 30 minutes before service starts
2. Right to Information: About service details
3. Right to Complaint: Regarding service issues

SERVICE DETAILS:
- Service type: Personal driver/valet service
- Service duration: According to selected package/distance
- Service area: Within Istanbul city limits
- Payment: Cash or credit card after service

RIGHT OF WITHDRAWAL:
According to Consumer Protection Law:
- You have withdrawal rights before service starts
- Contact customer service for withdrawal
- Late withdrawal may incur fees

DISPUTE RESOLUTION:
Service disputes are under Istanbul Courts jurisdiction.

By accepting this contract, you agree to purchase our service.
''';
    }
  }
  
  Widget _buildCompanyInfo(ThemeProvider themeProvider, LanguageProvider languageProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.business,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                languageProvider.currentLanguage == 'en' ? 'Company Information' : 'Şirket Bilgileri',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildInfoRow('📍', 'Adres', 'İstanbul, Türkiye', themeProvider),
          _buildInfoRow('📞', 'Telefon', '+90 555 123 45 67', themeProvider),
          _buildInfoRow('📧', 'E-posta', 'info@funbreakvale.com', themeProvider),
          _buildInfoRow('🌐', 'Website', 'www.funbreakvale.com', themeProvider),
          _buildInfoRow('⏰', 'Çalışma Saati', '7/24 Hizmet', themeProvider),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String icon, String label, String value, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
