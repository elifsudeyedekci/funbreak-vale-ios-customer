import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'sms_verification_screen.dart';
import 'sms_register_screen.dart';

class SmsLoginScreen extends StatefulWidget {
  const SmsLoginScreen({Key? key}) : super(key: key);

  @override
  State<SmsLoginScreen> createState() => _SmsLoginScreenState();
}

class _SmsLoginScreenState extends State<SmsLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // Telefon numarası formatla (0 ile başlayacak şekilde)
  String _formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // +90 ile başlıyorsa kaldır
    if (cleaned.startsWith('90') && cleaned.length == 12) {
      cleaned = '0' + cleaned.substring(2);
    }
    
    // 5 ile başlıyorsa başına 0 ekle
    if (cleaned.startsWith('5') && cleaned.length == 10) {
      cleaned = '0' + cleaned;
    }
    
    // Zaten 0 ile başlıyorsa olduğu gibi bırak
    
    return cleaned;
  }

  Future<void> _sendLoginCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final phone = _formatPhone(_phoneController.text.trim());
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/login_send_code.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': phone,
          'type': 'customer',
        }),
      );

      final data = json.decode(response.body);

      if (data['success'] == true) {
        // SMS gönderildi, doğrulama ekranına git
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SmsVerificationScreen(
                phone: phone,
                userId: int.parse(data['user_id'].toString()),
                userType: 'customer',
                isLogin: true,
              ),
            ),
          );
        }
      } else {
        // Hata durumları
        if (mounted) {
          String errorMessage = data['message'] ?? 'Bir hata oluştu';
          
          if (data['user_not_found'] == true) {
            // Kullanıcı bulunamadı, kayıt ekranına yönlendir
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Kullanıcı Bulunamadı'),
                content: const Text('Bu telefon numarası ile kayıtlı kullanıcı bulunamadı. Kayıt olmak ister misiniz?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SmsRegisterScreen(prefilledPhone: phone),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Kayıt Ol'),
                  ),
                ],
              ),
            );
          } else if (data['phone_not_verified'] == true) {
            // Telefon doğrulanmamış
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: 'Doğrula',
                  textColor: Colors.white,
                  onPressed: () {
                    // Doğrulama kodunu gönder
                    int userId = int.parse(data['user_id'].toString());
                    _sendVerificationCode(phone, userId);
                  },
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bağlantı hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendVerificationCode(String phone, int userId) async {
    try {
      print('📤 SMS gönderiliyor: Phone=$phone, UserId=$userId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/send_verification_code.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': phone,
          'user_id': userId,
          'type': 'customer',
        }),
      );

      print('📥 SMS API Response: ${response.body}');
      final data = json.decode(response.body);
      print('📊 SMS API Data: $data');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SmsVerificationScreen(
              phone: phone,
              userId: userId,
              userType: 'customer',
              isLogin: false,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ SMS gönderim hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kod gönderilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                  'FunBreak Vale',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Telefon numaranızı girin',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),
                
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
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendLoginCode,
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
                            'Kod Gönder',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Hesabınız yok mu? '),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SmsRegisterScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Kayıt Ol',
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
