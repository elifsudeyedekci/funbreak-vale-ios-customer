import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart'; // 🆕 Profil resmi kalıcılığı için
import 'package:http/http.dart' as http; // 🆕 Backend'e fotoğraf yüklemek için
import 'dart:io';
import 'dart:convert'; // 🆕 JSON decode için
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/admin_api_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _vehicleMakeController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  final TextEditingController _vehiclePlateController = TextEditingController();
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    print('🔍 PROFIL: _loadUserData başladı');
    
    final prefs = await SharedPreferences.getInstance();
    print('🔍 PROFIL: user_id = ${prefs.getString('user_id')}');
    print('🔍 PROFIL: user_name = ${prefs.getString('user_name')}');
    print('🔍 PROFIL: user_email = ${prefs.getString('user_email')}');
    print('🔍 PROFIL: user_phone = ${prefs.getString('user_phone')}');
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    print('🔍 PROFIL: authProvider.customerName = ${authProvider.customerName}');
    print('🔍 PROFIL: authProvider.customerPhone = ${authProvider.customerPhone}');
    
    _nameController.text = authProvider.customerName ?? '';
    _phoneController.text = authProvider.customerPhone ?? '';
    _emailController.text = authProvider.userEmail ?? '';
    
    // Araç bilgilerini SharedPreferences'tan yükle
    _vehicleMakeController.text = prefs.getString('vehicle_make') ?? '';
    _vehicleModelController.text = prefs.getString('vehicle_model') ?? '';
    _vehicleColorController.text = prefs.getString('vehicle_color') ?? '';
    _vehiclePlateController.text = prefs.getString('vehicle_plate') ?? '';
    
    // 🆕 PROFIL RESMİNİ YÜKLE (kalıcı storage'dan)
    final savedImagePath = prefs.getString('profile_image_path');
    if (savedImagePath != null && savedImagePath.isNotEmpty) {
      final savedFile = File(savedImagePath);
      if (await savedFile.exists()) {
        setState(() {
          _profileImage = savedFile;
        });
        print('✅ PROFIL: Kayıtlı profil resmi yüklendi: $savedImagePath');
      } else {
        print('⚠️ PROFIL: Kayıtlı dosya bulunamadı: $savedImagePath');
      }
    }
    
    print('✅ PROFIL: Bilgiler yüklendi');
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      
      if (image != null) {
        // 🆕 RESMİ KALICI STORAGE'A KOPYALA
        final directory = await getApplicationDocumentsDirectory();
        final String savedPath = '${directory.path}/profile_image.jpg';
        
        // Dosyayı kopyala
        final File newImage = await File(image.path).copy(savedPath);
        
        // SharedPreferences'a path'i kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profile_image_path', savedPath);
        
        setState(() {
          _profileImage = newImage;
        });
        
        print('✅ PROFIL: Resim yerel olarak kaydedildi: $savedPath');
        
        // 🆕 BACKEND'E YÜKLE (sürücü de görebilsin!)
        await _uploadPhotoToBackend(newImage);
      }
    } catch (e) {
      print('❌ PROFIL: Resim seçme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resim seçilemedi: $e')),
      );
    }
  }
  
  // 🆕 Fotoğrafı backend'e yükle
  Future<void> _uploadPhotoToBackend(File imageFile) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;
      
      if (customerId == null || customerId.isEmpty) {
        print('⚠️ PROFIL: Customer ID bulunamadı, backend yüklemesi atlanıyor');
        return;
      }
      
      print('📤 PROFIL: Backend\'e fotoğraf yükleniyor... (Customer: $customerId)');
      
      final uri = Uri.parse('https://admin.funbreakvale.com/api/upload_customer_photo.php');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['customer_id'] = customerId;
      request.files.add(await http.MultipartFile.fromPath('photo', imageFile.path));
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('📥 PROFIL: Backend yanıtı: $responseBody');
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(responseBody);
        if (jsonResponse['success'] == true) {
          print('✅ PROFIL: Fotoğraf backend\'e yüklendi! URL: ${jsonResponse['photo_url']}');
          
          // SharedPreferences'a backend URL'i de kaydet
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_photo_url', jsonResponse['photo_url'] ?? '');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profil fotoğrafı güncellendi'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          print('⚠️ PROFIL: Backend hatası: ${jsonResponse['message']}');
        }
      } else {
        print('❌ PROFIL: HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ PROFIL: Backend yükleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          languageProvider.getTranslatedText('profile'),
          style: TextStyle(
            color: themeProvider.isDarkMode ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profil Fotoğrafı
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFD700),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _profileImage != null
                          ? Image.file(
                              _profileImage!,
                              fit: BoxFit.cover,
                              width: 120,
                              height: 120,
                            )
                          : Container(
                              color: const Color(0xFFFFD700),
                              child: const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Profil Bilgileri
            _buildProfileField(
              'Tam isminiz',
              _nameController,
              Icons.person_outline,
              themeProvider,
            ),
            
            const SizedBox(height: 16),
            
            _buildProfileField(
              'Telefon',
              _phoneController,
              Icons.phone_outlined,
              themeProvider,
            ),
            
            const SizedBox(height: 16),
            
            _buildProfileField(
              'E-posta',
              _emailController,
              Icons.email_outlined,
              themeProvider,
            ),
            
            // Araç Bilgileri KALDIRILDI - Müşteri talebi ile
            
            const SizedBox(height: 40),
            
            // Kaydet Butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0xFFFFD700).withOpacity(0.3),
                ),
                child: const Text(
                  'Kaydet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField(
    String label,
    TextEditingController controller,
    IconData icon,
    ThemeProvider themeProvider,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.text,
        textCapitalization: label.contains('İsim') || label.contains('Ad') 
            ? TextCapitalization.words 
            : TextCapitalization.none,
        enableSuggestions: true,
        autocorrect: true,
        style: TextStyle(
          color: themeProvider.isDarkMode ? Colors.white : Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: const Color(0xFFFFD700),
              size: 24,
            ),
          ),
          suffixIcon: Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Colors.grey[400],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  Widget _buildLegalLink(String title, IconData icon, VoidCallback onTap, ThemeProvider themeProvider) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _openPrivacyPolicy() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gizlilik Politikası açılıyor...'),
        backgroundColor: Colors.blue,
      ),
    );
    // TODO: url_launcher ile https://funbreakvale.com/privacy-policy açma
  }

  void _openTermsOfService() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kullanım Şartları açılıyor...'),
        backgroundColor: Colors.blue,
      ),
    );
    // TODO: url_launcher ile https://funbreakvale.com/terms-of-service açma
  }

  Future<void> _saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString('user_id') ?? '0';
      
      // ✅ BACKEND'E GÜNCELLEME GÖNDER - PANELİ SENKRONIZE ET!
      final adminApi = AdminApiProvider();
      
      final response = await adminApi.updateCustomerProfile(
        customerId: customerId,
        name: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        vehicleMake: _vehicleMakeController.text,
        vehicleModel: _vehicleModelController.text,
        vehicleColor: _vehicleColorController.text,
        vehiclePlate: _vehiclePlateController.text,
      );
      
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Profil güncellenemedi');
      }
      
      // Kişisel bilgileri kaydet (SharedPreferences)
      await prefs.setString('user_name', _nameController.text);
      await prefs.setString('user_phone', _phoneController.text);
      await prefs.setString('user_email', _emailController.text);
      
      // AuthProvider'ı da güncelle
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.updateUserInfo(
        name: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text,
      );
      
      // Araç bilgilerini kaydet
      await prefs.setString('vehicle_make', _vehicleMakeController.text);
      await prefs.setString('vehicle_model', _vehicleModelController.text);
      await prefs.setString('vehicle_color', _vehicleColorController.text);
      await prefs.setString('vehicle_plate', _vehiclePlateController.text);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profil güncellendi ve panele senkronize edildi'),
          backgroundColor: Colors.green,
        ),
      );
      
      print('✅ Profil backend\'e kaydedildi ve panele senkronize edildi!');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Profil güncellenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
      
      print('❌ Profil güncelleme hatası: $e');
    }
  }
}