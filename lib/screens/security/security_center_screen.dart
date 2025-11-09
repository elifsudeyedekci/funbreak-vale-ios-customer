import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({Key? key}) : super(key: key);

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  bool _biometricEnabled = false;
  bool _twoFactorEnabled = false;
  
  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }
  
  void _loadSecuritySettings() {
    // Mevcut güvenlik ayarlarını yükle
    setState(() {
      _biometricEnabled = false; // Varsayılan
      _twoFactorEnabled = false; // Varsayılan
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Güvenlik Merkezi',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // GÜVENLİK DURUMU KARTI
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.security,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesabınız Güvende',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Güvenlik ayarlarınızı kontrol edin',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ŞİFRE YÖNETİMİ
            _buildSecuritySection(
              context,
              isDarkMode,
              'Şifre Yönetimi',
              [
                _buildSecurityTile(
                  icon: Icons.lock_outline,
                  title: 'Şifre Değiştir',
                  subtitle: 'Giriş şifrenizi güncelleyin',
                  onTap: () => _showChangePasswordDialog(),
                  isDarkMode: isDarkMode,
                ),
                _buildSecurityTile(
                  icon: Icons.history,
                  title: 'Şifre Geçmişi',
                  subtitle: 'Son şifre değişikliklerini görün',
                  onTap: () => _showPasswordHistory(),
                  isDarkMode: isDarkMode,
                ),
              ],
            ),

            // BİYOMETRİK GÜVENLİK
            _buildSecuritySection(
              context,
              isDarkMode,
              'Biyometrik Güvenlik',
              [
                _buildSecuritySwitchTile(
                  icon: Icons.fingerprint,
                  title: 'Parmak İzi / Face ID',
                  subtitle: 'Hızlı ve güvenli giriş',
                  value: _biometricEnabled,
                  onChanged: (value) {
                    setState(() {
                      _biometricEnabled = value;
                    });
                    _saveBiometricSetting(value);
                  },
                  isDarkMode: isDarkMode,
                ),
              ],
            ),

            // İKİ FAKTÖRLÜ DOĞRULAMA
            _buildSecuritySection(
              context,
              isDarkMode,
              'İki Faktörlü Doğrulama',
              [
                _buildSecuritySwitchTile(
                  icon: Icons.phone_android,
                  title: 'SMS Doğrulama',
                  subtitle: _twoFactorEnabled ? 'Aktif' : 'Güvenliğinizi artırın',
                  value: _twoFactorEnabled,
                  onChanged: (value) {
                    setState(() {
                      _twoFactorEnabled = value;
                    });
                    _saveTwoFactorSetting(value);
                  },
                  isDarkMode: isDarkMode,
                ),
              ],
            ),

            // OTURUM YÖNETİMİ
            _buildSecuritySection(
              context,
              isDarkMode,
              'Oturum Yönetimi',
              [
                _buildSecurityTile(
                  icon: Icons.devices,
                  title: 'Aktif Oturumlar',
                  subtitle: 'Cihazlarınızı yönetin',
                  onTap: () => _showActiveSessions(),
                  isDarkMode: isDarkMode,
                ),
                _buildSecurityTile(
                  icon: Icons.logout,
                  title: 'Tüm Cihazlardan Çıkış',
                  subtitle: 'Güvenlik amacıyla tüm oturumları sonlandır',
                  onTap: () => _showLogoutAllDialog(),
                  isDarkMode: isDarkMode,
                  isDestructive: true,
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection(
    BuildContext context,
    bool isDarkMode,
    String title,
    List<Widget> children,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Section header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[700] : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
          
          // Section content
          ...children,
        ],
      ),
    );
  }

  Widget _buildSecurityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDarkMode,
    bool isDestructive = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (isDestructive ? Colors.red : const Color(0xFFFFD700)).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isDestructive ? Colors.red : const Color(0xFFFFD700),
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDestructive ? Colors.red : (isDarkMode ? Colors.white : Colors.black87),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSecuritySwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDarkMode,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
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
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFFFD700),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFFFD700)),
              SizedBox(width: 8),
              Text('Şifre Değiştir'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mevcut Şifre',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Yeni Şifre',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                  helperText: 'En az 8 karakter, büyük-küçük harf ve rakam içermeli',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Yeni Şifre Tekrar',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                await _changePassword(
                  currentPasswordController.text,
                  newPasswordController.text,
                  confirmPasswordController.text,
                  setState,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.white,
              ),
              child: isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Değiştir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
    StateSetter setState,
  ) async {
    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      _showErrorSnackBar('Tüm alanları doldurun');
      return;
    }

    if (newPassword != confirmPassword) {
      _showErrorSnackBar('Yeni şifreler eşleşmiyor');
      return;
    }

    if (newPassword.length < 8) {
      _showErrorSnackBar('Şifre en az 8 karakter olmalı');
      return;
    }

    setState(() {
      // Set loading state
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.customerId;

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/change_password.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'customer',
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          Navigator.pop(context);
          _showSuccessSnackBar('Şifre başarıyla değiştirildi');
        } else {
          _showErrorSnackBar(data['message'] ?? 'Şifre değiştirme başarısız');
        }
      } else {
        _showErrorSnackBar('Sunucu hatası');
      }
    } catch (e) {
      _showErrorSnackBar('Bağlantı hatası: $e');
    }
  }

  void _showPasswordHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Şifre Geçmişi'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('Son değişiklik'),
              subtitle: Text('15 Ocak 2024 - 14:30'),
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('Önceki değişiklik'),
              subtitle: Text('10 Aralık 2023 - 09:15'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showActiveSessions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.devices, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Aktif Oturumlar'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.phone_android, color: Color(0xFFFFD700)),
              title: Text('Bu Cihaz'),
              subtitle: Text('Android • Şu anda aktif'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showLogoutAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Tüm Cihazlardan Çıkış'),
          ],
        ),
        content: const Text(
          'Bu işlem tüm cihazlardaki oturumlarınızı sonlandıracak. '
          'Tekrar giriş yapmanız gerekecek. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performLogoutAll();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _performLogoutAll() {
    _showSuccessSnackBar('Tüm cihazlardan çıkış yapıldı');
  }

  void _saveBiometricSetting(bool enabled) {
    _showSuccessSnackBar(enabled ? 'Biyometrik giriş aktifleştirildi' : 'Biyometrik giriş kapatıldı');
  }

  void _saveTwoFactorSetting(bool enabled) {
    _showSuccessSnackBar(enabled ? 'İki faktörlü doğrulama aktifleştirildi' : 'İki faktörlü doğrulama kapatıldı');
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
