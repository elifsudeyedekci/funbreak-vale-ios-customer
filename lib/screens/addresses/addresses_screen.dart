import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import 'add_address_screen.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({Key? key}) : super(key: key);

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getString('saved_addresses');
      
      if (addressesJson != null) {
        final List<dynamic> addressList = jsonDecode(addressesJson);
        setState(() {
          _addresses = addressList.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = jsonEncode(_addresses);
      await prefs.setString('saved_addresses', addressesJson);
    } catch (e) {
      print('Adres kaydetme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Kayıtlı Adresler',
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
          : _addresses.isEmpty 
              ? _buildEmptyState(themeProvider)
              : _buildAddressList(themeProvider),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAddressScreen,
        backgroundColor: const Color(0xFFFFD700),
        child: const Icon(Icons.add, color: Colors.white),
      ),
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
              Icons.location_on_outlined,
              size: 50,
              color: const Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Kayıtlı Adres Oluştur',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: themeProvider.isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Henüz bir kayıtlı adresiniz bulunmamaktadır.\nİlk kayıtlı adresinizi oluşturun.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showAddAddressScreen,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Yeni Adres Ekle',
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
  
  Widget _buildAddressList(ThemeProvider themeProvider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _addresses.length,
      itemBuilder: (context, index) {
        final address = _addresses[index];
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
                _getAddressIcon(address['type']),
                color: const Color(0xFFFFD700),
                size: 24,
              ),
            ),
            title: Text(
              address['title'] ?? 'Adres',
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
                  address['address'] ?? '',
                  style: TextStyle(
                    color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                if (address['detail'] != null && address['detail'].isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    address['detail'],
                    style: TextStyle(
                      color: themeProvider.isDarkMode ? Colors.grey[500] : Colors.grey[500],
                      fontSize: 12,
                    ),
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
                  _editAddress(index);
                } else if (value == 'delete') {
                  _deleteAddress(index);
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

  IconData _getAddressIcon(String? type) {
    switch (type) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      default:
        return Icons.location_on;
    }
  }

  void _showAddAddressScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(
          onSave: (addressData) {
            setState(() {
              _addresses.add(addressData);
            });
            _saveAddresses();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Adres başarıyla kaydedildi'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  void _editAddress(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(
          existingAddress: _addresses[index],
          onSave: (addressData) {
            setState(() {
              _addresses[index] = addressData;
            });
            _saveAddresses();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Adres başarıyla güncellendi'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  void _deleteAddress(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: const Text('Bu adresi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _addresses.removeAt(index);
              });
              _saveAddresses();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Adres silindi'),
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