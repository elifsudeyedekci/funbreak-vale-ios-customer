import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import 'add_billing_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({Key? key}) : super(key: key);

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  List<Map<String, dynamic>> _billingAddresses = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadBillingAddresses();
  }

  Future<void> _loadBillingAddresses() async {
    try {
      // ✅ ÖNCE BACKEND'DEN ÇEKMEYE ÇALIŞ
      await _loadFromBackend();
      
      // SharedPreferences'tan yedek olarak yükle
      final prefs = await SharedPreferences.getInstance();
      final billingJson = prefs.getString('billing_addresses');
      
      // Backend'den gelmediyse SharedPreferences kullan
      if (_billingAddresses.isEmpty && billingJson != null) {
        final List<dynamic> billingList = jsonDecode(billingJson);
        setState(() {
          _billingAddresses = billingList.cast<Map<String, dynamic>>();
        });
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Fatura bilgisi yükleme hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // BACKEND'DEN FATURA BİLGİSİ YÜKLE
  Future<void> _loadFromBackend() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final customerId = authProvider.customerId;
      
      if (customerId == null) return;
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_billing_info.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'customer_id': int.parse(customerId)}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['has_billing']) {
          final billingInfo = data['billing_info'];
          
          // Backend'den gelen veriyi SharedPreferences formatına çevir
          final billingData = {
            'id': billingInfo['id'].toString(),
            'title': 'Fatura Bilgilerim',
            'name': billingInfo['company_name'] ?? '',
            'address': billingInfo['address'] ?? '',
            'type': billingInfo['tax_number'] != null && billingInfo['tax_number'].toString().length == 10 ? 'kurumsal' : 'bireysel',
            'idNumber': billingInfo['tax_number']?.toString().length == 11 ? billingInfo['tax_number'] : null,
            'taxNumber': billingInfo['tax_number']?.toString().length == 10 ? billingInfo['tax_number'] : null,
            'taxOffice': billingInfo['tax_office'],
            'city': billingInfo['city'] ?? '',
            'district': billingInfo['district'] ?? '',
            'postalCode': billingInfo['postal_code'] ?? '',
            'created_at': billingInfo['created_at'],
            'updated_at': DateTime.now().toIso8601String(),
          };
          
          setState(() {
            _billingAddresses = [billingData]; // Sadece 1 tane
          });
          
          // SharedPreferences'a da kaydet
          _saveBillingAddresses();
          
          print('✅ Backend\'den fatura bilgisi yüklendi');
        }
      }
    } catch (e) {
      print('❌ Backend fatura bilgisi yükleme hatası: $e');
    }
  }

  Future<void> _saveBillingAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final billingJson = jsonEncode(_billingAddresses);
      await prefs.setString('billing_addresses', billingJson);
    } catch (e) {
      print('Fatura kaydetme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Fatura Bilgilerim',
          style: TextStyle(
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
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _billingAddresses.isEmpty 
              ? _buildEmptyState(themeProvider)
              : _buildBillingList(themeProvider),
      floatingActionButton: _billingAddresses.isEmpty
          ? FloatingActionButton(
              onPressed: _showAddBillingScreen,
              backgroundColor: const Color(0xFFFFD700),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null, // Zaten 1 fatura varsa + butonu gizle
    );
  }
  
  Widget _buildEmptyState(ThemeProvider themeProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: themeProvider.isDarkMode ? Colors.grey[700] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.description_outlined,
              size: 50,
              color: const Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Fatura Bilgisi Ekle',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: themeProvider.isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Henüz bir fatura adresiniz bulunmamaktadır.\nİlk fatura bilginizi ekleyin.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showAddBillingScreen,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Fatura Bilgisi Ekle',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBillingList(ThemeProvider themeProvider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _billingAddresses.length,
      itemBuilder: (context, index) {
        final billing = _billingAddresses[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                billing['type'] == 'kurumsal' ? Icons.business : Icons.person,
                color: const Color(0xFFFFD700),
                size: 24,
              ),
            ),
            title: Text(
              billing['title'] ?? 'Fatura Adresi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  billing['type'] == 'kurumsal' 
                      ? 'Vergi No: ${billing['taxNumber'] ?? ''}'
                      : 'TC No: ${billing['idNumber'] ?? ''}',
                  style: TextStyle(
                    color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                if (billing['address'] != null && billing['address'].isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    billing['address'],
                    style: TextStyle(
                      color: themeProvider.isDarkMode ? Colors.grey[500] : Colors.grey[500],
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _editBilling(index);
                } else if (value == 'delete') {
                  _deleteBilling(index);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Color(0xFFFFD700)),
                      SizedBox(width: 8),
                      Text('Düzenle'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sil'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddBillingScreen() {
    // ⚠️ SADECE 1 FATURA BİLGİSİ EKLENEBİLİR!
    if (_billingAddresses.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Sadece 1 adet fatura bilgisi kaydedebilirsiniz. Mevcut fatura bilginizi düzenleyebilirsiniz.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddBillingScreen(
          onSave: (billingData) {
            setState(() {
              _billingAddresses.add(billingData);
            });
            _saveBillingAddresses();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Fatura bilgisi başarıyla kaydedildi'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  void _editBilling(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddBillingScreen(
          existingBilling: _billingAddresses[index],
          onSave: (billingData) {
            setState(() {
              _billingAddresses[index] = billingData;
            });
            _saveBillingAddresses();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fatura bilgisi başarıyla güncellendi'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  void _deleteBilling(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fatura Bilgisini Sil'),
        content: const Text('Bu fatura bilgisini silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _billingAddresses.removeAt(index);
              });
              _saveBillingAddresses();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Fatura bilgisi silindi'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}