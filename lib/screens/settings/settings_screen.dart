import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../addresses/saved_addresses_screen.dart';
import '../billing/billing_screen.dart';
import '../payment/payment_methods_screen.dart';
import '../profile/profile_screen.dart';
// import '../security/security_center_screen.dart'; // KALDIRILDI - Şifre girişi yok
import '../../providers/language_provider.dart';
import '../../services/dynamic_contact_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'Türkçe';
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _selectedLanguage = prefs.getString('selected_language') ?? 'Türkçe';
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', _notificationsEnabled);
    await prefs.setString('selected_language', _selectedLanguage);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Ayarlar',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD700),
          ),
        ),
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profil kartı
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFFFD700),
                    child: const Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authProvider.customerName ?? 'Kullanıcı',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              authProvider.userEmail ?? 'E-posta yok',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey[400],
                    size: 16,
                  ),
                ],
              ),
            ),
            
            // Hesap ayarları
            _buildSectionTitle('Hesap'),
            _buildSettingTile(
              icon: Icons.person_outline,
              title: 'Profil Bilgileri',
              subtitle: 'Kişisel bilgilerinizi düzenleyin',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
            ),
            _buildSettingTile(
              icon: Icons.location_on_outlined,
              title: 'Adreslerim',
              subtitle: 'Kayıtlı adreslerinizi yönetin',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SavedAddressesScreen(),
                  ),
                );
              },
            ),
            _buildSettingTile(
              icon: Icons.receipt_outlined,
              title: 'Faturalarım',
              subtitle: 'Fatura bilgilerini yönetin',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BillingScreen(),
                  ),
                );
              },
            ),
            _buildSettingTile(
              icon: Icons.credit_card,
              title: 'Ödeme Yöntemleri',
              subtitle: 'Kredi kartları ve ödeme seçenekleri',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PaymentMethodsScreen(),
                  ),
                );
              },
            ),
            
            // Güvenlik Merkezi KALDIRILDI - Şifre girişi olmadığı için gerek yok
            
            // Uygulama ayarları
            _buildSectionTitle('Uygulama'),
            _buildSettingTile(
              icon: Icons.language,
              title: 'Dil',
              subtitle: _selectedLanguage,
              onTap: () => _showLanguageDialog(),
            ),
            _buildSettingTile(
              icon: Icons.dark_mode_outlined,
              title: 'Karanlık Tema',
              subtitle: isDarkMode ? 'Açık' : 'Kapalı',
              trailing: Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (value) {
                      themeProvider.toggleTheme();
                    },
                    activeColor: const Color(0xFFFFD700),
                  );
                },
              ),
            ),
            
            // Destek
            _buildSectionTitle('Destek'),
            _buildSettingTile(
              icon: Icons.help_outline,
              title: 'Yardım Merkezi',
              subtitle: 'SSS ve kullanım kılavuzu',
              onTap: () => _showHelpDialog(),
            ),
            _buildSettingTile(
              icon: Icons.message_outlined,
              title: 'İletişim',
              subtitle: 'Bizimle iletişime geçin',
              onTap: () => _showContactBottomSheet(),
            ),
            
            // Diğer
            _buildSectionTitle('Diğer'),
            _buildSettingTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Gizlilik Politikası',
              onTap: () => _openPrivacyPolicy(),
            ),
            _buildSettingTile(
              icon: Icons.description_outlined,
              title: 'Kullanım Şartları',
              onTap: () => _openTermsOfUse(),
            ),
            
            // Çıkış butonu
            Container(
              margin: const EdgeInsets.all(16),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showLogoutDialog(),
                icon: const Icon(Icons.logout),
                label: const Text('Çıkış Yap'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFD700),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFFD700),
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              )
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey[400],
                    size: 16,
                  )
                : null),
      ),
    );
  }

  void _showProfileDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profil Bilgileri',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Ad Soyad',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Telefon',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profil güncellendi'),
                          backgroundColor: Color(0xFFFFD700),
                        ),
                      );
                    },
                    child: const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showLanguageDialog() {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Dil Seçimi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            RadioListTile<String>(
              title: const Text('Türkçe'),
              value: 'Türkçe',
              groupValue: _selectedLanguage,
              onChanged: (value) async {
                await languageProvider.setLanguage('tr');
                setState(() {
                  _selectedLanguage = value!;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFFFD700),
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'English',
              groupValue: _selectedLanguage,
              onChanged: (value) async {
                await languageProvider.setLanguage('en');
                setState(() {
                  _selectedLanguage = value!;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFFFD700),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Yardım Merkezi',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
            _buildHelpItem(
              'Vale nasıl çağırılır?',
              'Ana sayfada "Nereden" ve "Nereye" konumlarını seçin. Hizmet türünü belirleyin (Normal Vale veya Saatlik Paket). "Vale Çağır" butonuna basın. Sistem otomatik olarak size en yakın valeyi bulacaktır.',
              Icons.local_taxi,
            ),
            _buildHelpItem(
              'Fiyatlandırma nasıl hesaplanır?',
              '• Mesafe bazlı: KM aralığına göre fiyatlandırma\n  - 0-5 km\n  - 6-10 km\n  - 11-15 km\n  - 15+ km\n• Bekleme ücreti: İlk 15 dk ücretsiz, sonrası her 15 dk = ₺200\n• Saatlik paketler: 2 saat geçince otomatik paket\n  - 0-4 saat: ₺3,000\n  - 4-8 saat: ₺4,500\n  - 8-12 saat: ₺6,000',
              Icons.currency_lira,
            ),
            _buildHelpItem(
              'Ödeme yöntemleri nelerdir?',
              '• Kredi/Banka Kartı: Yolculuk sonunda ödeme yapılır\n• Havale/EFT: Banka hesabımıza havale yapabilirsiniz. Havale yapıldıktan sonra sistem tarafından otomatik onaylanır',
              Icons.payment,
            ),
            _buildHelpItem(
              'İptal ve iade koşulları',
              '• Vale bulunamadan önce: Ücretsiz iptal\n• Vale atandıktan sonra yolculuğun başlamasına 45 dakika veya daha az kalmışsa: ₺1500 iptal ücreti tahsil edilir\n• Vale yola çıktıktan sonra: Tam ücret tahsil edilir\n• Sistem tarafından otomatik iptal durumlarında tam iade yapılır',
              Icons.cancel,
            ),
            _buildHelpItem(
              'Rezervasyon nasıl yapılır?',
              'Vale çağırırken "Zamanlanmış" seçeneğini işaretleyin. Tarih ve saat seçin. 2 saat önceden sistem otomatik olarak vale aramaya başlar.',
              Icons.schedule,
            ),
            _buildHelpItem(
              'Aktif yolculuğu nasıl takip ederim?',
              'Valeyi kabul ettikten sonra canlı haritada konumunu görebilirsiniz. Köprü arama sistemi ile vale ile iletişime geçebilirsiniz. Mesajlaşma özelliği ile sesli mesaj ve fotoğraf gönderebilirsiniz.',
              Icons.map,
            ),
            _buildHelpItem(
              'Özel konum ücretleri nelerdir?',
              'Belirli bölgelerde ek ücret uygulanır:\n• Göktürk: +₺200\n• Diğer özel konumlar için güncel fiyat listesi uygulamada gösterilir',
              Icons.location_on,
            ),
            _buildHelpItem(
              'Güvenlik önlemleri nelerdir?',
              'Tüm valelerimiz kimlik doğrulamasından ve üst düzey eğitimlerden geçmiştir. Tüm yolculuklar GPS ile takip edilir. 7/24 destek hattımız aktiftir.',
              Icons.security,
            ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showContactBottomSheet();
                          },
                          icon: const Icon(Icons.support_agent),
                          label: const Text('Destek Ekibiyle İletişime Geç'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpItem(String title, String description, IconData icon) {
    return ExpansionTile(
      leading: Icon(
        icon,
        color: const Color(0xFFFFD700),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  void _showContactBottomSheet() async {
    // Dinamik iletişim bilgilerini çek
    await DynamicContactService.refreshSettings();
    
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'İletişim',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone, color: Colors.green),
              ),
              title: const Text('Telefon'),
              subtitle: Text(DynamicContactService.getSupportPhone()),
              onTap: () => _confirmAndCall(),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.email, color: Colors.blue),
              ),
              title: const Text('E-posta'),
              subtitle: Text(DynamicContactService.getSupportEmail()),
              onTap: () => _confirmAndEmail(),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.message, color: Colors.green),
              ),
              title: const Text('WhatsApp'),
              subtitle: Text(DynamicContactService.getWhatsAppNumber()),
              onTap: () => _confirmAndWhatsApp(),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _confirmAndCall() async {
    final phone = DynamicContactService.getSupportPhone();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phone, color: Colors.green),
            SizedBox(width: 8),
            Text('Arama Yap'),
          ],
        ),
        content: Text('$phone numarasını aramak istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ara'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final phoneUrl = DynamicContactService.getPhoneUrl();
      await launchUrl(Uri.parse(phoneUrl));
    }
  }
  
  Future<void> _confirmAndEmail() async {
    final email = DynamicContactService.getSupportEmail();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: Colors.blue),
            SizedBox(width: 8),
            Text('E-posta Gönder'),
          ],
        ),
        content: Text('$email adresine e-posta göndermek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final emailUrl = DynamicContactService.getEmailUrl(
        subject: 'FunBreak Vale Destek',
        body: 'Merhaba, yardıma ihtiyacım var...',
      );
      await launchUrl(Uri.parse(emailUrl));
    }
  }
  
  Future<void> _confirmAndWhatsApp() async {
    final whatsapp = DynamicContactService.getWhatsAppNumber();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.message, color: Color(0xFF25D366)),
            SizedBox(width: 8),
            Text('WhatsApp Aç'),
          ],
        ),
        content: Text('$whatsapp numarasıyla WhatsApp sohbetini açmak istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            child: const Text('Aç'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final whatsappUrl = DynamicContactService.getWhatsAppUrl(
        message: 'Merhaba, FunBreak Vale ile ilgili yardıma ihtiyacım var.',
      );
      await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
    }
  }

  void _showRatingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Uygulamayı Değerlendir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Deneyiminizi değerlendirin'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  icon: const Icon(
                    Icons.star_outline,
                    color: Color(0xFFFFD700),
                    size: 30,
                  ),
                  onPressed: () {},
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Daha Sonra'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Değerlendirmeniz için teşekkürler!'),
                  backgroundColor: Color(0xFFFFD700),
                ),
              );
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    const url = 'https://funbreakvale.com/gizlilik-politikasi.html';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Gizlilik Politikası'),
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse(url)),
          ),
        ),
      ),
    );
  }

  Future<void> _openTermsOfUse() async {
    const url = 'https://funbreakvale.com/kullanim-sartlari.html';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Kullanım Şartları'),
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse(url)),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_taxi,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'FunBreak Vale',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Versiyon 1.0.0',
                style: TextStyle(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Güvenli ve konforlu vale hizmeti',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // DUPLICATE FONKSİYONLAR KALDIRILDI - WebView versiyonları kullanılıyor (satır 806-848)

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hata'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Anlık çıkış işlemi
              final authProvider = context.read<AuthProvider>();
              await authProvider.logout();
              
              // Ana sayfaya yönlendir ve stack'i temizle
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (Route<dynamic> route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
  }
}