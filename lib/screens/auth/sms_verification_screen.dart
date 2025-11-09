import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../main_screen.dart';

class SmsVerificationScreen extends StatefulWidget {
  final String phone;
  final int userId;
  final String userType;
  final bool isLogin; // true: Giriş, false: Kayıt doğrulama
  final String? userName; // Kayıt için
  final String? userEmail; // Kayıt için

  const SmsVerificationScreen({
    Key? key,
    required this.phone,
    required this.userId,
    required this.userType,
    this.isLogin = false,
    this.userName,
    this.userEmail,
  }) : super(key: key);

  @override
  State<SmsVerificationScreen> createState() => _SmsVerificationScreenState();
}

class _SmsVerificationScreenState extends State<SmsVerificationScreen> {
  final List<TextEditingController> _codeControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _canResend = false;
  int _remainingSeconds = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _canResend = false;
    _remainingSeconds = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeControllers.map((c) => c.text).join();
    
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen 6 haneli kodu girin'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiUrl = widget.isLogin
          ? 'https://admin.funbreakvale.com/api/login_verify_code.php'
          : 'https://admin.funbreakvale.com/api/verify_phone.php';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': widget.phone,
          'code': code,
          'type': widget.userType,
          'user_id': widget.userId,
        }),
      );

      final data = json.decode(response.body);

      print('🔍 VERIFY RESPONSE: $data');

      if (data['success'] == true) {
        // Doğrulama başarılı - Kullanıcı ID'sini al
        final userId = (data['user_id'] ?? widget.userId).toString();
        
        print('✅ Doğrulama başarılı - User ID: $userId');
        
        if (widget.isLogin && mounted) {
          // GİRİŞ - Kullanıcı bilgilerini backend'den çek
          print('📥 Giriş için kullanıcı bilgileri çekiliyor...');
          
          try {
            final userResponse = await http.get(
              Uri.parse('https://admin.funbreakvale.com/api/get_customer.php?id=$userId'),
            ).timeout(const Duration(seconds: 10));
            
            final userData = json.decode(userResponse.body);
            print('📊 Kullanıcı verisi: $userData');
            
            if (userData['success'] != true || userData['customer'] == null) {
              throw Exception('Kullanıcı bilgileri alınamadı');
            }
            
            final user = userData['customer'];
            final prefs = await SharedPreferences.getInstance();
            
            print('💾 Giriş bilgileri kaydediliyor...');
            
            await prefs.setString('user_id', userId);
            await prefs.setString('admin_user_id', userId);
            await prefs.setInt('customer_id', int.parse(userId));
            await prefs.setString('user_name', user['name'].toString());
            await prefs.setString('user_email', user['email'].toString());
            await prefs.setString('user_phone', user['phone'].toString());
            await prefs.setString('user_type', 'customer');
            await prefs.setBool('phone_verified', true);
            await prefs.setBool('isLoggedIn', true);
            await prefs.setBool('is_logged_in', true);
            await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
            
            // AuthProvider'ı güncelle
            if (mounted) {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.checkAuthStatus();
            }
            
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const MainScreen()),
              (route) => false,
            );
            
          } catch (e) {
            print('❌ Kullanıcı bilgileri çekilemedi: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Giriş tamamlanamadı: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          
        } else if (!widget.isLogin && mounted) {
          // KAYIT - Widget'tan gelen bilgileri kullan (API çağrısı yok!)
          print('💾 KAYIT SONRASI OTOMATİK GİRİŞ - user_id: $userId');
          print('   İsim: ${widget.userName}');
          print('   Email: ${widget.userEmail}');
          print('   Telefon: ${widget.phone}');
          
          final prefs = await SharedPreferences.getInstance();
          
          await prefs.setString('user_id', userId);
          await prefs.setString('admin_user_id', userId);
          await prefs.setInt('customer_id', int.parse(userId));
          await prefs.setString('user_name', widget.userName ?? 'Kullanıcı');
          await prefs.setString('user_email', widget.userEmail ?? '');
          await prefs.setString('user_phone', widget.phone);
          await prefs.setString('user_type', 'customer');
          await prefs.setBool('phone_verified', true);
          await prefs.setBool('isLoggedIn', true);
          await prefs.setBool('is_logged_in', true);
          await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
          
          // 🔒 45 GÜNLÜK SESSION İÇİN TİMESTAMP KAYDET
          await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
          
          print('✅ Kaydedildi! user_id: ${prefs.getString('user_id')}');
          print('✅ Kaydedildi! user_name: ${prefs.getString('user_name')}');
          print('✅ Kaydedildi! user_email: ${prefs.getString('user_email')}');
          
          // 🔄 AUTHPROVIDER'I GÜNCELLE (Profil bilgileri hemen yüklensin)
          if (mounted) {
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            await authProvider.checkAuthStatus(); // Session'ı yeniden yükle
          }
          
          // 📱 FCM TOKEN KAYDET (Bildirimler için!)
          await _saveFCMToken(userId);
          
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          String errorMessage = data['message'] ?? 'Doğrulama başarısız';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Kodu temizle
          for (var controller in _codeControllers) {
            controller.clear();
          }
          _focusNodes[0].requestFocus();
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

  /// 📱 FCM TOKEN KAYDETME FONKSİYONU
  /// Push notification alabilmek için kullanıcının FCM token'ını backend'e kaydeder
  Future<void> _saveFCMToken(String userId) async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      if (fcmToken == null || fcmToken.isEmpty) {
        print('⚠️ FCM Token alınamadı (izin verilmemiş olabilir)');
        return; // Token yoksa sessizce devam et, giriş/kayıt başarısını engelleme
      }
      
      print('📱 FCM Token kaydediliyor: ${fcmToken.substring(0, 30)}...');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': int.parse(userId),
          'user_type': 'customer',
          'fcm_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 5));
      
      final data = json.decode(response.body);
      
      if (data['success'] == true) {
        print('✅ FCM Token başarıyla kaydedildi!');
      } else {
        print('⚠️ FCM Token kaydedilemedi: ${data['message']}');
      }
    } catch (e) {
      // FCM token kaydetme hatası kritik değil, kullanıcı girişi engellenmemeli
      print('⚠️ FCM Token kaydetme hatası (devam ediliyor): $e');
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() => _isLoading = true);

    try {
      final apiUrl = widget.isLogin
          ? 'https://admin.funbreakvale.com/api/login_send_code.php'
          : 'https://admin.funbreakvale.com/api/send_verification_code.php';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phone': widget.phone,
          'user_id': widget.userId,
          'type': widget.userType,
        }),
      );

      final data = json.decode(response.body);

      if (data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Yeni kod gönderildi'),
              backgroundColor: Colors.green,
            ),
          );
          _startTimer();
          
          // Kodu temizle
          for (var controller in _codeControllers) {
            controller.clear();
          }
          _focusNodes[0].requestFocus();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Kod gönderilemedi'),
              backgroundColor: Colors.red,
            ),
          );
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

  Widget _buildCodeInput(int index) {
    return SizedBox(
      width: 50,
      child: TextField(
        controller: _codeControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: Color(0xFFFFD700),
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          
          // Tüm kutular doluysa otomatik doğrula
          if (index == 5 && value.isNotEmpty) {
            _verifyCode();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isLogin ? 'Giriş Doğrulama' : 'Telefon Doğrulama'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              
              // Icon
              const Icon(
                Icons.sms,
                size: 80,
                color: Color(0xFFFFD700),
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                widget.isLogin ? 'Giriş Kodu' : 'Doğrulama Kodu',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Phone Number
              Text(
                '${widget.phone} numaralı telefona\ngönderilen 6 haneli kodu girin',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // Code Inputs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  6,
                  (index) => _buildCodeInput(index),
                ),
              ),
              const SizedBox(height: 32),
              
              // Verify Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
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
                          'Doğrula',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Resend Code
              Center(
                child: _canResend
                    ? TextButton(
                        onPressed: _resendCode,
                        child: const Text(
                          'Kodu Tekrar Gönder',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Text(
                        'Yeni kod: $_remainingSeconds saniye',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
