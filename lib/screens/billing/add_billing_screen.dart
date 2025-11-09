import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';

class AddBillingScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final Map<String, dynamic>? existingBilling;
  
  const AddBillingScreen({
    Key? key,
    required this.onSave,
    this.existingBilling,
  }) : super(key: key);

  @override
  State<AddBillingScreen> createState() => _AddBillingScreenState();
}

class _AddBillingScreenState extends State<AddBillingScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _taxNumberController = TextEditingController();
  final TextEditingController _taxOfficeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  
  String _selectedType = 'bireysel'; // 'bireysel' or 'kurumsal'

  @override
  void initState() {
    super.initState();
    if (widget.existingBilling != null) {
      _titleController.text = widget.existingBilling!['title'] ?? '';
      _nameController.text = widget.existingBilling!['name'] ?? '';
      _addressController.text = widget.existingBilling!['address'] ?? '';
      _idNumberController.text = widget.existingBilling!['idNumber'] ?? '';
      _taxNumberController.text = widget.existingBilling!['taxNumber'] ?? '';
      _taxOfficeController.text = widget.existingBilling!['taxOffice'] ?? '';
      _cityController.text = widget.existingBilling!['city'] ?? '';
      _districtController.text = widget.existingBilling!['district'] ?? '';
      _postalCodeController.text = widget.existingBilling!['postalCode'] ?? '';
      _selectedType = widget.existingBilling!['type'] ?? 'bireysel';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _idNumberController.dispose();
    _taxNumberController.dispose();
    _taxOfficeController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.existingBilling != null ? 'Fatura Bilgisini Düzenle' : 'Yeni Fatura Bilgisi',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD700),
          ),
        ),
        backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(
          color: themeProvider.isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fatura tipi seçimi
            Text(
              'Fatura Tipi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedType = 'bireysel';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedType == 'bireysel' 
                            ? const Color(0xFFFFD700).withOpacity(0.1)
                            : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedType == 'bireysel' 
                              ? const Color(0xFFFFD700)
                              : (themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                          width: _selectedType == 'bireysel' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.person,
                            color: _selectedType == 'bireysel' 
                                ? const Color(0xFFFFD700)
                                : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bireysel',
                            style: TextStyle(
                              color: _selectedType == 'bireysel' 
                                  ? const Color(0xFFFFD700)
                                  : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              fontWeight: _selectedType == 'bireysel' 
                                  ? FontWeight.bold 
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedType = 'kurumsal';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedType == 'kurumsal' 
                            ? const Color(0xFFFFD700).withOpacity(0.1)
                            : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedType == 'kurumsal' 
                              ? const Color(0xFFFFD700)
                              : (themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                          width: _selectedType == 'kurumsal' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.business,
                            color: _selectedType == 'kurumsal' 
                                ? const Color(0xFFFFD700)
                                : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kurumsal',
                            style: TextStyle(
                              color: _selectedType == 'kurumsal' 
                                  ? const Color(0xFFFFD700)
                                  : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              fontWeight: _selectedType == 'kurumsal' 
                                  ? FontWeight.bold 
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 30),
            
            // Fatura başlığı
            _buildInputField(
              'Fatura Başlığı',
              _titleController,
              Icons.title,
              'Ev, İş, vb.',
              themeProvider,
            ),
            
            const SizedBox(height: 20),
            
            // Ad/Soyad veya Şirket Adı
            _buildInputField(
              _selectedType == 'bireysel' ? 'Ad Soyad' : 'Şirket Adı',
              _nameController,
              _selectedType == 'bireysel' ? Icons.person : Icons.business,
              _selectedType == 'bireysel' ? 'Adınız ve soyadınız' : 'Şirket adını girin',
              themeProvider,
            ),
            
            const SizedBox(height: 20),
            
            // TC No veya Vergi No
            if (_selectedType == 'bireysel') ...[
              _buildInputField(
                'TC Kimlik Numarası',
                _idNumberController,
                Icons.badge,
                '11 haneli TC kimlik numaranız',
                themeProvider,
                keyboardType: TextInputType.number,
              ),
            ] else ...[
              _buildInputField(
                'Vergi Numarası',
                _taxNumberController,
                Icons.receipt_long,
                '10 haneli vergi numaranız',
                themeProvider,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              _buildInputField(
                'Vergi Dairesi',
                _taxOfficeController,
                Icons.account_balance,
                'Vergi dairesi adı',
                themeProvider,
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Adres
            _buildInputField(
              'Fatura Adresi',
              _addressController,
              Icons.location_on,
              'Tam fatura adresinizi girin',
              themeProvider,
              maxLines: 3,
            ),
            
            const SizedBox(height: 20),
            
            // İlçe
            _buildInputField(
              'İlçe',
              _districtController,
              Icons.location_city,
              'İlçe adı (örn: Beşiktaş)',
              themeProvider,
            ),
            
            const SizedBox(height: 20),
            
            // Şehir
            _buildInputField(
              'Şehir',
              _cityController,
              Icons.location_city,
              'Şehir adı (örn: İstanbul)',
              themeProvider,
            ),
            
            const SizedBox(height: 20),
            
            // Posta Kodu
            _buildInputField(
              'Posta Kodu',
              _postalCodeController,
              Icons.markunread_mailbox,
              'Posta kodu (opsiyonel)',
              themeProvider,
              keyboardType: TextInputType.number,
            ),
            
            const SizedBox(height: 40),
            
            // Kaydet butonu
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saveBilling,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  widget.existingBilling != null ? 'Güncelle' : 'Kaydet',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint,
    ThemeProvider themeProvider, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(12),
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
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: TextStyle(
              color: themeProvider.isDarkMode ? Colors.white : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[500],
              ),
              prefixIcon: Icon(
                icon,
                color: const Color(0xFFFFD700),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _saveBilling() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('Lütfen fatura başlığı girin');
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      _showError(_selectedType == 'bireysel' 
          ? 'Lütfen ad ve soyadınızı girin'
          : 'Lütfen şirket adını girin');
      return;
    }

    if (_selectedType == 'bireysel') {
      if (_idNumberController.text.trim().isEmpty || _idNumberController.text.length != 11) {
        _showError('Lütfen geçerli bir TC kimlik numarası girin');
        return;
      }
    } else {
      if (_taxNumberController.text.trim().isEmpty || _taxNumberController.text.length != 10) {
        _showError('Lütfen geçerli bir vergi numarası girin');
        return;
      }
      if (_taxOfficeController.text.trim().isEmpty) {
        _showError('Lütfen vergi dairesi adını girin');
        return;
      }
    }

    if (_addressController.text.trim().isEmpty) {
      _showError('Lütfen fatura adresini girin');
      return;
    }
    
    if (_districtController.text.trim().isEmpty) {
      _showError('Lütfen ilçe bilgisini girin');
      return;
    }
    
    if (_cityController.text.trim().isEmpty) {
      _showError('Lütfen şehir bilgisini girin');
      return;
    }

    final billingData = {
      'id': widget.existingBilling?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleController.text.trim(),
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'type': _selectedType,
      'idNumber': _selectedType == 'bireysel' ? _idNumberController.text.trim() : null,
      'taxNumber': _selectedType == 'kurumsal' ? _taxNumberController.text.trim() : null,
      'taxOffice': _selectedType == 'kurumsal' ? _taxOfficeController.text.trim() : null,
      'city': _cityController.text.trim(),
      'district': _districtController.text.trim(),
      'postalCode': _postalCodeController.text.trim(),
      'created_at': widget.existingBilling?['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // ✅ BACKEND'E KAYDET
    await _saveBillingToBackend(billingData);
    
    widget.onSave(billingData);
    Navigator.pop(context);
  }
  
  // BACKEND'E FATURA BİLGİSİ KAYDET
  Future<void> _saveBillingToBackend(Map<String, dynamic> billingData) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;
      
      if (customerId == null) {
        print('⚠️ Customer ID bulunamadı, backend\'e kaydedilemiyor');
        return;
      }
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/save_customer_billing_info.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.parse(customerId),
          'company_name': billingData['name'],
          'tax_office': billingData['taxOffice'] ?? '',
          'tax_number': billingData['taxNumber'] ?? billingData['idNumber'] ?? '',
          'address': billingData['address'],
          'city': billingData['city'] ?? '',
          'district': billingData['district'] ?? '',
          'postal_code': billingData['postalCode'] ?? ''
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          print('✅ Fatura bilgisi backend\'e kaydedildi: ${data['action']}');
        } else {
          print('❌ Backend kayıt hatası: ${data['message']}');
        }
      }
    } catch (e) {
      print('❌ Backend kayıt exception: $e');
      // Hata olsa bile devam et, SharedPreferences'a kaydedilecek
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
