import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/theme_provider.dart';
import '../../services/saved_addresses_service.dart';
import '../../widgets/map_location_picker.dart';
import '../../services/location_search_service.dart';

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({Key? key}) : super(key: key);

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  List<SavedAddress> _addresses = [];
  bool _isLoading = true;
  
  // REAL-TIME SEARCH VARIABLES - TAM AKTİF!
  final TextEditingController _searchController = TextEditingController();
  List<PlaceAutocomplete> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  @override  
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel(); // Timer cleanup!
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final addresses = await SavedAddressesService.getSavedAddresses();
      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Adresler yüklenirken hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // REAL-TIME GOOGLE PLACES SEARCH - HER HARF İLE!
  void _searchAddresses(String query) {
    print('🔍 SavedAddresses real-time arama: "$query"');
    
    // Önceki timer'ı iptal et
    _searchDebounce?.cancel();
    
    // ULTRA RESPONSIVE - İLK HARFTEN İTİBAREN ARAMA!

    setState(() {
      _isSearching = true;
    });

    // 180ms debounce - ULTRA RESPONSIVE real-time search!
    _searchDebounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        if (mounted) { // Widget hala active mi kontrol
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
          
          // FORCED UI UPDATE - SAVED ADDRESSES
          print('🔄 SAVED FORCED UI UPDATE - setState called for ${results.length} results');
          
          // UI refresh için ekstra trigger
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
              print('🔄 SAVED Post-frame setState triggered for UI refresh');
            }
          });
        }
        
        print('🔍 SavedAddresses real-time sonuç: ${results.length} adres bulundu');
      } catch (e) {
        print('❌ SavedAddresses arama hatası: $e');
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  // REAL-TIME SEARCH RESULT - DOKUNARAK KAYDET!
  void _selectSearchResultAndSave(PlaceAutocomplete result) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(result.placeId);
      if (details != null) {
        // Otomatik adres kaydet
        final newAddress = SavedAddress(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.mainText,
          address: details.formattedAddress,
          description: result.secondaryText,
          type: AddressType.other, 
          latitude: details.latitude,
          longitude: details.longitude,
          createdAt: DateTime.now(),
          lastUsedAt: DateTime.now(),
        );
        
        await SavedAddressesService.saveAddress(newAddress);
        
        setState(() {
          _searchController.clear();
          _searchResults = [];
        });
        
        _loadAddresses(); // Liste yenile
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${result.mainText}" kaydedildi'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        print('✅ Real-time search adres kaydedildi: ${details.formattedAddress}');
      }
    } catch (e) {
      print('❌ Adres kaydetme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Adres kaydetme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addNewAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddAddressScreen(),
      ),
    );

    if (result == true) {
      _loadAddresses(); // Yeniden yükle
    }
  }

  Future<void> _editAddress(SavedAddress address) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(address: address),
      ),
    );

    if (result == true) {
      _loadAddresses(); // Yeniden yükle
    }
  }

  Future<void> _deleteAddress(SavedAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adresi Sil'),
        content: Text('${address.name} adresini silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SavedAddressesService.deleteAddress(address.id);
        _loadAddresses();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adres silindi'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adres silinirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Kayıtlı Adreslerim'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _addNewAddress,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? _buildEmptyState(themeProvider)
              : _buildAddressList(themeProvider),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewAddress,
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(ThemeProvider themeProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 64,
            color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Kayıtlı Adres Yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hızlı erişim için adreslerinizi kaydedin',
            style: TextStyle(
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNewAddress,
            icon: const Icon(Icons.add),
            label: const Text('İlk Adresimi Ekle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressList(ThemeProvider themeProvider) {
    return Column(
      children: [
        // GOOGLE PLACES API REAL-TIME SEARCH BAR!
        Container(
          margin: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yeni Adres Ekle',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                onChanged: _searchAddresses, // REAL-TIME SEARCH TAM AKTİF! 🔥🔍
                decoration: InputDecoration(
                  hintText: 'Adres ara... (örn: Zorlu Center, İstinye Park)',
                  prefixIcon: Icon(
                    _isSearching ? Icons.search : Icons.add_location,
                    color: const Color(0xFFFFD700),
                  ),
                  suffixIcon: _isSearching 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                            ),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                  ),
                  filled: true,
                  fillColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
                ),
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              
              // REAL-TIME SEARCH RESULTS - CLEAN!
              if (_searchResults.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Arama Sonuçları - Dokunarak Kaydet',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      ..._searchResults.take(5).map((result) => 
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_location_alt, color: Color(0xFFFFD700), size: 20),
                          ),
                          title: Text(
                            result.mainText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            result.secondaryText,
                            style: TextStyle(
                              fontSize: 12,
                              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          trailing: const Icon(Icons.add_circle_outline, color: Color(0xFFFFD700)),
                          onTap: () async {
                            print('✅ SAVED real-time search selected: ${result.mainText}');
                            
                            // GOOGLE PLACES DETAIL ÇEK VE KAYDET!
                            try {
                              final details = await LocationSearchService.getPlaceDetails(result.placeId);
                              if (details != null) {
                                // Otomatik adres kaydet
                                final newAddress = SavedAddress(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  name: result.mainText,
                                  address: details.formattedAddress,
                                  description: result.secondaryText,
                                  type: AddressType.other, 
                                  latitude: details.latitude,
                                  longitude: details.longitude,
                                  createdAt: DateTime.now(),
                                  lastUsedAt: DateTime.now(),
                                );
                                
                                await SavedAddressesService.saveAddress(newAddress);
                                
                                setState(() {
                                  _searchController.clear();
                                  _searchResults = [];
                                });
                                
                                _loadAddresses(); // Liste yenile
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ "${result.mainText}" kaydedildi'),
                                    backgroundColor: Colors.green,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                
                                print('✅ SAVED search adres kaydedildi: ${details.formattedAddress}');
                              }
                            } catch (e) {
                              print('❌ SAVED adres kaydetme hatası: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Kaydetme hatası: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                        ),
                      ).toList(),
                    ],
                  ),
                ),
              ],
              
              // HARİTADAN SEÇ BUTONU - ANLIK KONUM İLE!
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _addNewAddress, // Şimdilik mevcut metodu kullan
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Color(0xFFFFD700), size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Haritadan Seç (Anlık Konum)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFFFD700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // KAYITLI ADRESLER LİSTESİ
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _addresses.length,
            itemBuilder: (context, index) {
              final address = _addresses[index];
              return _buildAddressCard(address, themeProvider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddressCard(SavedAddress address, ThemeProvider themeProvider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getAddressIcon(address.type.displayName),
            color: const Color(0xFFFFD700),
            size: 24,
          ),
        ),
        title: Text(
          address.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              address.address,
              style: TextStyle(
                fontSize: 14,
                color: themeProvider.isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            if (address.description != null && address.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                address.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _editAddress(address);
            } else if (value == 'delete') {
              _deleteAddress(address);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Düzenle'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Sil', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getAddressIcon(String type) {
    switch (type.toLowerCase()) {
      case 'ev':
        return Icons.home;
      case 'iş':
      case 'is':
        return Icons.business;
      case 'okul':
        return Icons.school;
      case 'hastane':
        return Icons.local_hospital;
      case 'alışveriş':
      case 'alisveris':
        return Icons.shopping_bag;
      default:
        return Icons.location_on;
    }
  }
}

class AddAddressScreen extends StatefulWidget {
  final SavedAddress? address;

  const AddAddressScreen({Key? key, this.address}) : super(key: key);

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedType = 'Ev';
  String _selectedAddress = '';
  LatLng? _selectedLocation;
  bool _isLoading = false;
  List<PlaceAutocomplete> _searchResults = [];
  Timer? _searchDebounce; // EKSİK TIMER EKLENDİ!

  final List<String> _addressTypes = [
    'Ev',
    'İş',
    'Okul',
    'Hastane',
    'Alışveriş',
    'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.address != null) {
      _nameController.text = widget.address!.name;
      _notesController.text = widget.address!.description ?? '';
      _selectedType = widget.address!.type.displayName;
      _selectedAddress = widget.address!.address;
      _selectedLocation = LatLng(widget.address!.latitude, widget.address!.longitude);
    }
  }

  @override  
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _searchDebounce?.cancel(); // Timer temizliği!
    super.dispose();
  }

  Future<void> _selectLocation() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildLocationSelectionSheet(),
    );
  }

  Widget _buildLocationSelectionSheet() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Konum Seçin',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Arama Yap
                _buildLocationOption(
                  icon: Icons.search,
                  title: 'Arama Yap',
                  subtitle: 'Konum adı yazarak arayın',
                  onTap: () {
                    Navigator.pop(context);
                    _searchLocationForAddress();
                  },
                  themeProvider: themeProvider,
                ),
                
                const SizedBox(height: 12),
                
                // Haritadan Seç
                _buildLocationOption(
                  icon: Icons.map,
                  title: 'Haritadan Seç',
                  subtitle: 'Harita üzerinden konum belirleyin',
                  onTap: () {
                    Navigator.pop(context);
                    _selectFromMap();
                  },
                  themeProvider: themeProvider,
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ThemeProvider themeProvider,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
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
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _searchLocationForAddress() {
    // NEREDEN NEREYE GİBİ TAM EKRAN ARAMA!
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildLocationSearchModal(),
    );
  }
  
  Widget _buildLocationSearchModal() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Adres Ara',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // SÜPER HIZLI ARAMA BAR!
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Konum ara... (örn: Watergarden, Zorlu Center)',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                  ),
                  filled: true,
                  fillColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                ),
                onChanged: (value) => _searchAddressesUltraFast(value, setModalState),
                style: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            
            // SÜPER HIZLI ARAMA SONUÇLARI!
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Arama Sonuçları - Dokunarak Seç',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    ...(_searchResults.take(5).map((result) => 
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on, color: Color(0xFFFFD700), size: 20),
                        ),
                        title: Text(
                          result.mainText,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          result.secondaryText,
                          style: TextStyle(
                            fontSize: 12,
                            color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        trailing: const Icon(Icons.add_circle_outline, color: Color(0xFFFFD700)),
                        onTap: () async {
                          await _selectSearchResultForAddress(result, setModalState);
                        },
                      ),
                    )),
                  ],
                ),
              ),
            ],
            
            // Arama modalında "Haritadan Seç" yok - sadece arama sonuçları
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // SÜPER HIZLI ADRES ARAMA FONKSİYONU!
  void _searchAddressesUltraFast(String query, StateSetter setModalState) {
    _searchDebounce?.cancel();
    
    if (query.isEmpty) {
      setModalState(() {
        _searchResults = [];
      });
      return;
    }
    
    // SÜPER HIZLI - 30ms debounce!
    _searchDebounce = Timer(const Duration(milliseconds: 30), () async {
      try {
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        
        if (mounted) {
          setModalState(() {
            _searchResults = results;
          });
        }
      } catch (e) {
        print('❌ Adres arama hatası: $e');
        if (mounted) {
          setModalState(() {
            _searchResults = [];
          });
        }
      }
    });
  }
  
  // Arama sonucunu adres olarak seç
  Future<void> _selectSearchResultForAddress(PlaceAutocomplete result, StateSetter setModalState) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(result.placeId);
      if (details != null) {
        // Modal'ı kapat
        Navigator.pop(context);
        
        // Adres form alanlarını doldur
        setState(() {
          _selectedAddress = details.formattedAddress;
          _selectedLocation = LatLng(details.latitude, details.longitude);
          _nameController.text = result.mainText; // Ana ismi otomatik doldur
        });
        
        print('✅ Arama sonucundan adres seçildi: ${details.formattedAddress}');
      }
    } catch (e) {
      print('❌ Arama sonucu seçme hatası: $e');
    }
  }
  
  // Direkt konum seçimi
  void _selectLocationDirectly(String address, LatLng location) {
    setState(() {
      _selectedLocation = location;
      _selectedAddress = address;
      _nameController.text = address;
    });
    print('✅ Direkt konum seçildi: $address');
  }

  // Adres arama fonksiyonu (ESKİ)
  void _searchPlacesForAddress(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    try {
      final results = await LocationSearchService.getPlaceAutocomplete(query);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      print('Adres arama hatası: $e');
    }
  }

  Widget _buildLocationSearchDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final TextEditingController searchController = TextEditingController();
    
    return AlertDialog(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
      title: Text(
        'Konum Ara',
        style: TextStyle(
          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Konum adı yazın... (örn: Watergarden)',
              prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
              ),
            ),
            onChanged: (value) => _searchPlacesForAddress(value),
          ),
          const SizedBox(height: 16),
          // Örnek sonuçlar - Google Places API ile değiştirilebilir
          Container(
            height: 200,
            child: ListView(
              children: [
                _buildSearchResultItem('Watergarden AVM', 'Barbaros, Kızılbegonya Sok.', () {
                  _selectLocationDirectly('Watergarden AVM', LatLng(41.0082, 28.9784));
                  Navigator.pop(context);
                }),
                _buildSearchResultItem('Water Garden İstanbul', 'Barbaros, Watergarden...', () {
                  _selectLocationDirectly('Water Garden İstanbul', LatLng(41.0082, 28.9784));
                  Navigator.pop(context);
                }),
                _buildSearchResultItem('Wabi Hostels', 'İnönü, Papa Roncalli Cad...', () {
                  _selectLocationDirectly('Wabi Hostels', LatLng(41.0082, 28.9784));
                  Navigator.pop(context);
                }),
                _buildSearchResultItem('Taksim Meydanı', 'Beyoğlu, Taksim', () {
                  _selectLocationDirectly('Taksim Meydanı', LatLng(41.0369, 28.9850));
                  Navigator.pop(context);
                }),
                _buildSearchResultItem('Galata Kulesi', 'Beyoğlu, Galata', () {
                  _selectLocationDirectly('Galata Kulesi', LatLng(41.0256, 28.9744));
                  Navigator.pop(context);
                }),
                _buildSearchResultItem('Kapalıçarşı', 'Fatih, Eminönü', () {
                  _selectLocationDirectly('Kapalıçarşı', LatLng(41.0106, 28.9681));
                  Navigator.pop(context);
                }),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: Color(0xFFFFD700))),
        ),
      ],
    );
  }

  Widget _buildSearchResultItem(String title, String subtitle, VoidCallback onTap) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return ListTile(
      leading: const Icon(Icons.location_on, color: Color(0xFFFFD700)),
      title: Text(
        title,
        style: TextStyle(
          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      onTap: onTap,
    );
  }

  // HARİTADAN SEÇ - ANLIK KONUM İLE BAŞLAT!
  void _selectFromMap() async {
    try {
      // Anlık konumu al
      LatLng? currentLocation;
      
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 5));
        
        currentLocation = LatLng(position.latitude, position.longitude);
        print('📍 Anlık konum alındı: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('⚠️ Anlık konum alınamadı: $e - Varsayılan kullanılacak');
        currentLocation = _selectedLocation ?? const LatLng(41.0082, 28.9784); // İstanbul
      }
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapLocationPicker(
            initialLocation: currentLocation, // ANLIK KONUM İLE BAŞLAT!
            onLocationSelected: (location, address) {
              setState(() {
                _selectedLocation = location;
                _selectedAddress = address;
                _nameController.text = address.split(',').first; // İlk kısmı başlık yap
              });
            },
          ),
        ),
      );
    } catch (e) {
      print('❌ Harita seçme hatası: $e');
    }
  }

  Future<void> _saveAddress() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen adres adını girin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedLocation == null || _selectedAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen konum seçin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    // ✅ BACKEND'E GÜNCELLEME GÖNDER (widget.address varsa)
    if (widget.address != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final customerId = prefs.getString('admin_user_id') ?? prefs.getString('customer_id') ?? '0';
        final addressId = widget.address!['id'];
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/update_saved_address.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'address_id': addressId,
            'customer_id': int.parse(customerId),
            'name': _nameController.text.trim(),
            'address': _selectedAddress,
            'description': _descriptionController.text.trim(),
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
            'type': _selectedType,
            'is_favorite': _isFavorite ? 1 : 0,
          }),
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Adres güncellendi'), backgroundColor: Colors.green),
              );
              Navigator.pop(context, true); // Başarılı, geri dön
            }
            return;
          }
        }
      } catch (e) {
        print('❌ Adres güncelleme hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Güncelleme hatası: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // AddressType enum'unu bul
      AddressType addressType = AddressType.other;
      for (AddressType type in AddressType.values) {
        if (type.displayName == _selectedType) {
          addressType = type;
          break;
        }
      }

      final address = SavedAddress(
        id: widget.address?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        address: _selectedAddress,
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
        description: _notesController.text.trim(),
        type: addressType,
        isFavorite: widget.address?.isFavorite ?? false,
        createdAt: widget.address?.createdAt ?? DateTime.now(),
        lastUsedAt: widget.address?.lastUsedAt ?? DateTime.now(),
        usageCount: widget.address?.usageCount ?? 0,
      );

      if (widget.address != null) {
        await SavedAddressesService.updateAddress(address);
      } else {
        await SavedAddressesService.saveAddress(address);
      }

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Adres kaydedilirken hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.address != null ? 'Adresi Düzenle' : 'Yeni Adres Ekle'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Adres Adı
            Text(
              'Adres Adı',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Örn: Evim, İşyerim, Annemin Evi',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Adres Tipi
            Text(
              'Adres Tipi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _addressTypes.map((type) {
                final isSelected = _selectedType == type;
                return FilterChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedType = type;
                    });
                  },
                  selectedColor: const Color(0xFFFFD700),
                  checkmarkColor: Colors.black,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Konum Seçimi
            Text(
              'Konum',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _selectLocation,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFFFFD700)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedAddress.isEmpty ? 'Haritadan konum seçin' : _selectedAddress,
                        style: TextStyle(
                          color: _selectedAddress.isEmpty 
                              ? (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600])
                              : (themeProvider.isDarkMode ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Notlar
            Text(
              'Notlar (Opsiyonel)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Örn: Apartman kapı kodu: 1234, 2. kat',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Kaydet Butonu
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        widget.address != null ? 'Güncelle' : 'Kaydet',
                        style: const TextStyle(
                          fontSize: 16,
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

  // REAL-TIME SEARCH ITEM WIDGET - DOĞRU CLASS'TA!
  Widget _buildRealtimeSearchItem(PlaceAutocomplete result) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    return GestureDetector(
      onTap: () {
        print('Search result tapped: ${result.mainText}');
        // Method aktif edilecek
      }, // Geçici basit call
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode ? Colors.grey[700]!.withOpacity(0.3) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_location_alt, color: Color(0xFFFFD700), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.mainText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.secondaryText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.secondaryText,
                      style: TextStyle(
                        fontSize: 12,
                        color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline, color: Color(0xFFFFD700), size: 20),
          ],
        ),
      ),
    );
  }

  // REAL-TIME SEARCH RESULT SEÇ VE KAYDET - DOĞRU CLASS'TA!
  void _selectSearchResultAndSave(PlaceAutocomplete result) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(result.placeId);
      if (details != null) {
        // Otomatik adres kaydet
        final newAddress = SavedAddress(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: result.mainText,
          address: details.formattedAddress,
          description: result.secondaryText,
          type: AddressType.other, 
          latitude: details.latitude,
          longitude: details.longitude,
          createdAt: DateTime.now(),
          lastUsedAt: DateTime.now(),
        );
        
        await SavedAddressesService.saveAddress(newAddress);
        
        print('✅ Haritadan adres kaydedildi: ${details.formattedAddress}');
      }
    } catch (e) {
      print('❌ Adres kaydetme hatası: $e');
    }
  }
}
