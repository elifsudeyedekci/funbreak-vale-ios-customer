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
ÖN BİLGİLENDİRME KOŞULLARI

1. HİZMET TANIMI
FunBreak Vale, müşterilerimize profesyonel şoför hizmeti sunan bir platformdur. Hizmetimiz kapsamında:
- Kişisel şoför hizmeti
- Saatlik paket hizmetleri
- Özel etkinlik transferleri
- Havalimanı transfer hizmetleri

2. FİYATLANDIRMA
- Fiyatlarımız mesafe bazlı hesaplanır
- Trafik yoğunluğu fiyata etki eder
- Bekleme süreleri için ek ücret alınır
- Özel konumlar için ek ücret uygulanabilir

3. ÖDEME KOŞULLARI
- Ödeme hizmet tamamlandıktan sonra yapılır
- Kredi kartı ve nakit ödemeler kabul edilir
- İndirim kodları geçerli olduğu durumlarda uygulanır

4. İPTAL KOŞULLARI
- Hizmet başlamadan 30 dakika öncesine kadar ücretsiz iptal
- Geç iptal durumunda %50 ücret alınır
- Hizmet başladıktan sonra iptal edilemez

5. SORUMLULUKLARIMIZ
- Güvenli ve konforlu ulaşım
- Deneyimli ve güvenilir şoförler
- 7/24 müşteri hizmetleri
- Sigortalı araç ve hizmet

6. MÜŞTERİ SORUMLULUKLARI
- Doğru adres bilgisi verme
- Zamanında hazır olma
- Ödeme yükümlülüğü
- Hizmet kurallarına uyma

Bu koşulları kabul ederek hizmetimizi kullanmayı onaylıyorsunuz.
''';
    } else {
      return '''
MESAFELİ SATIŞ SÖZLEŞMESİ

SATICI FİRMA BİLGİLERİ:
Ticaret Unvanı: FunBreak Vale Hizmetleri Ltd. Şti.
Adres: İstanbul, Türkiye
Telefon: +90 555 123 45 67
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

MÜŞTERİ HAKLARI:
1. Cayma Hakkı: Hizmet başlamadan 30 dakika öncesine kadar cayma hakkınız vardır.
2. Bilgi Alma: Hizmet detayları hakkında bilgi alma hakkınız vardır.
3. Şikayet: Hizmetle ilgili şikayetlerinizi iletme hakkınız vardır.

HİZMET DETAYLARI:
- Hizmet türü: Kişisel şoför/vale hizmeti
- Hizmet süresi: Seçilen paket/mesafeye göre
- Hizmet alanı: İstanbul şehri sınırları içi
- Ödeme: Hizmet sonrası nakit veya kredi kartı

CAYMA HAKKI:
6502 sayılı Tüketicinin Korunması Hakkında Kanun gereğince:
- Hizmet başlamadan önce cayma hakkınız vardır
- Cayma için müşteri hizmetlerini arayın
- Geç cayma durumunda ücret kesintisi yapılabilir

UYUŞMAZLIK ÇÖZÜMÜ:
Hizmetle ilgili uyuşmazlıklar İstanbul Mahkemeleri ve İcra Müdürlüklerinin yetkisindedir.

Bu sözleşmeyi kabul ederek hizmetimizi satın almayı onaylıyorsunuz.
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
