import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/theme_provider.dart';
import '../../services/location_search_service.dart';
import '../../services/saved_addresses_service.dart'; // SavedAddress class için
import '../../widgets/map_location_picker.dart';

class AddAddressScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onSave; // Optional yap
  final Map<String, dynamic>? existingAddress;
  final SavedAddress? address; // saved_addresses_screen uyumlu
  
  const AddAddressScreen({
    Key? key,
    this.onSave,
    this.existingAddress,
    this.address, // Eski sistem uyumluluk
  }) : super(key: key);

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  String _selectedType = 'home';
  
  // GOOGLE PLACES API ARAMA SİSTEMİ - TAM AKTİF REAL-TIME!
  List<PlaceAutocomplete> _searchResults = [];
  bool _isSearching = false;
  LatLng? _selectedLocation;
  Timer? _searchDebounce;

  final List<Map<String, dynamic>> _addressTypes = [
    {'type': 'home', 'label': 'Ev', 'icon': Icons.home},
    {'type': 'work', 'label': 'İş', 'icon': Icons.work},
    {'type': 'other', 'label': 'Diğer', 'icon': Icons.location_on},
  ];

  @override
  void initState() {
    super.initState();
    
    // Eski sistem uyumluluk
    if (widget.existingAddress != null) {
      _titleController.text = widget.existingAddress!['title'] ?? '';
      _addressController.text = widget.existingAddress!['address'] ?? '';
      _detailController.text = widget.existingAddress!['detail'] ?? '';
      _selectedType = widget.existingAddress!['type'] ?? 'home';
    }
    
    // Yeni sistem uyumluluk
    if (widget.address != null) {
      _titleController.text = widget.address!.name;
      _addressController.text = widget.address!.address;
      _detailController.text = widget.address!.details;
      _selectedType = widget.address!.type;
      _selectedLocation = LatLng(widget.address!.latitude, widget.address!.longitude);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _detailController.dispose();
    _searchDebounce?.cancel(); // Timer cleanup!
    super.dispose();
  }

  // GOOGLE PLACES API ARAMA SİSTEMİ - REAL-TIME DEBOUNCED!
  void _searchAddresses(String query) {
    print('🔍 AddAddress real-time arama: "$query"');
    
    // Önceki timer'ı iptal et
    _searchDebounce?.cancel();
    
    // ULTRA RESPONSIVE - İLK HARFTEN İTİBAREN ARAMA!

    setState(() {
      _isSearching = true;
    });

    // 180ms debounce - ULTRA RESPONSIVE AddAddress search!
    _searchDebounce = Timer(const Duration(milliseconds: 180), () async {
      try {
        final results = await LocationSearchService.getPlaceAutocomplete(query);
        if (mounted) { // Widget active kontrolü
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
        
        print('🔍 AddAddress real-time sonuç: ${results.length} adres bulundu');
      } catch (e) {
        print('❌ AddAddress arama hatası: $e');
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  // ARAMA SONUCU SEÇİMİ
  void _selectSearchResult(PlaceAutocomplete result) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(result.placeId);
      if (details != null) {
        setState(() {
          _addressController.text = details.formattedAddress;
          _selectedLocation = LatLng(details.latitude, details.longitude);
          _searchResults = []; // Sonuçları temizle
        });
        
        print('✅ Adres seçildi: ${details.formattedAddress}');
      }
    } catch (e) {
      print('❌ Adres seçme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.grey[900] : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.existingAddress != null ? 'Adresi Düzenle' : 'Yeni Adres Ekle',
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
            // Adres başlığı
            _buildInputField(
              'Adres Başlığı',
              _titleController,
              Icons.title,
              'Ev, İş, vb.',
              themeProvider,
            ),
            
            const SizedBox(height: 20),
            
            // GOOGLE PLACES API ARAMA - GERÇEK API!
            _buildAddressSearchField(themeProvider),
            
            // ARAMA SONUÇLARI DROPDOWN
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Arama Sonuçları',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    ...(_searchResults.take(5).map((result) => _buildSearchResultItem(result))),
                  ],
                ),
              ),
            ],
            
            // HARİTADAN SEÇ BUTONU
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _selectFromMap,
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
                    const Icon(Icons.map, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Haritadan Seç',
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
            
            const SizedBox(height: 20),
            
            // Adres tarifi
            _buildInputField(
              'Adres Tarifi (Opsiyonel)',
              _detailController,
              Icons.description,
              'Daire no, kat, vb.',
              themeProvider,
              maxLines: 2,
            ),
            
            const SizedBox(height: 30),
            
            // Adres tipi seçimi
            Text(
              'Adres Tipi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: _addressTypes.map((type) {
                final isSelected = _selectedType == type['type'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedType = type['type'];
                        if (_titleController.text.isEmpty) {
                          _titleController.text = type['label'];
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? const Color(0xFFFFD700).withOpacity(0.1)
                            : (themeProvider.isDarkMode ? Colors.grey[800] : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected 
                              ? const Color(0xFFFFD700)
                              : (themeProvider.isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            type['icon'],
                            color: isSelected 
                                ? const Color(0xFFFFD700)
                                : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            type['label'],
                            style: TextStyle(
                              color: isSelected 
                                  ? const Color(0xFFFFD700)
                                  : (themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              fontWeight: isSelected 
                                  ? FontWeight.bold 
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 40),
            
            // Kaydet butonu
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saveAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  widget.existingAddress != null ? 'Güncelle' : 'Kaydet',
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

  void _saveAddress() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen adres başlığı girin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen adres bilgisi girin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final addressData = {
      'id': widget.existingAddress?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleController.text.trim(),
      'address': _addressController.text.trim(),
      'detail': _detailController.text.trim(),
      'type': _selectedType,
      'created_at': widget.existingAddress?['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Konum bilgisi de ekle
    if (_selectedLocation != null) {
      addressData['latitude'] = _selectedLocation!.latitude;
      addressData['longitude'] = _selectedLocation!.longitude;
    }

    // Eski sistem uyumluluk
    if (widget.onSave != null) {
      widget.onSave!(addressData);
    } else {
      // Yeni sistem - SavedAddressesService kullan
      try {
        final savedAddress = SavedAddress(
          id: widget.address?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          name: addressData['title'],
          address: addressData['address'],
          description: addressData['detail'], // details → description
          type: AddressType.other, // String → AddressType
          latitude: _selectedLocation?.latitude ?? 41.0082,
          longitude: _selectedLocation?.longitude ?? 28.9784,
          createdAt: DateTime.now(),
          lastUsedAt: DateTime.now(),
        );
        
        await SavedAddressesService.saveAddress(savedAddress);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adres başarıyla kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adres kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return; // Hata durumunda sayfayı kapatma
      }
    }
    
    Navigator.pop(context, true); // Başarı ile geri dön
  }

  // GOOGLE PLACES API ARAMA FIELD - GERÇEK API!
  Widget _buildAddressSearchField(ThemeProvider themeProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adres',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressController,
          onChanged: _searchAddresses, // GERÇEk API ARAMA!
          decoration: InputDecoration(
            hintText: 'Adres ara... (örn: Zorlu Center, İstinye Park)',
            prefixIcon: Icon(
              _isSearching ? Icons.search : Icons.location_on,
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
          maxLines: 2,
        ),
      ],
    );
  }

  // ARAMA SONUCU ITEM - DROPDOWN STYLE
  Widget _buildSearchResultItem(PlaceAutocomplete result) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    return GestureDetector(
      onTap: () => _selectSearchResult(result),
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
              child: const Icon(Icons.place, color: Color(0xFFFFD700), size: 18),
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
          ],
        ),
      ),
    );
  }

  // HARİTADAN SEÇ - ANLIK KONUM İLE BAŞLAT!
  void _selectFromMap() async {
    try {
      // Anlık konumu al
      LatLng? currentLocation;
      
      try {
        // Geolocator kullanarak anlık konum
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        currentLocation = LatLng(position.latitude, position.longitude);
        print('📍 Anlık konum alındı: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('⚠️ Anlık konum alma hatası: $e');
        // Default İstanbul konumu
        currentLocation = const LatLng(41.0082, 28.9784);
      }
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapLocationPicker(
            initialLocation: currentLocation, // ANLIK KONUM İLE BAŞLAT!
            onLocationSelected: (LatLng location, String address) {
              setState(() {
                _addressController.text = address;
                _selectedLocation = location;
                _searchResults = []; // Sonuçları temizle
              });
              print('✅ Haritadan adres seçildi: $address');
            },
          ),
        ),
      );
    } catch (e) {
      print('❌ Harita seçme hatası: $e');
    }
  }
}
