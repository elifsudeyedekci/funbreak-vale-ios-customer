import 'package:flutter/material.dart';
import '../services/saved_addresses_service.dart';
import '../services/location_search_service.dart';

class AddressSelectionWidget extends StatefulWidget {
  final String title;
  final String currentAddress;
  final Function(String address, double lat, double lng) onAddressSelected;
  
  const AddressSelectionWidget({
    Key? key,
    required this.title,
    required this.currentAddress,
    required this.onAddressSelected,
  }) : super(key: key);

  @override
  State<AddressSelectionWidget> createState() => _AddressSelectionWidgetState();
}

class _AddressSelectionWidgetState extends State<AddressSelectionWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<SavedAddress> _savedAddresses = [];
  List<PlaceSearchResult> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  Future<void> _loadSavedAddresses() async {
    final addresses = await SavedAddressesService.getSavedAddresses();
    setState(() {
      _savedAddresses = addresses;
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await LocationSearchService.searchPlaces(query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Arama hatası: $e');
    }
  }

  Future<void> _selectPlace(PlaceSearchResult place) async {
    try {
      final details = await LocationSearchService.getPlaceDetails(place.placeId);
      if (details != null) {
        widget.onAddressSelected(
          details.formattedAddress,
          details.latitude,
          details.longitude,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Yer detayları alma hatası: $e');
    }
  }

  void _selectSavedAddress(SavedAddress address) {
    widget.onAddressSelected(
      address.address,
      address.latitude,
      address.longitude,
    );
    
    // Kullanım sayısını artır
    SavedAddressesService.markAddressAsUsed(address.id);
    
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Arama kutusu
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Adres ara...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            ),
            onChanged: _searchPlaces,
          ),
          
          const SizedBox(height: 16),
          
          Expanded(
            child: _searchController.text.isNotEmpty
                ? _buildSearchResults()
                : _buildSavedAddresses(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty && !_isLoading) {
      return const Center(
        child: Text('Sonuç bulunamadı'),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return ListTile(
          leading: const Icon(Icons.location_on, color: Colors.blue),
          title: Text(result.mainText),
          subtitle: Text(result.secondaryText),
          onTap: () => _selectPlace(result),
        );
      },
    );
  }

  Widget _buildSavedAddresses() {
    if (_savedAddresses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Kayıtlı adres bulunamadı'),
            Text('Yukarıdan arama yapabilirsiniz'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kayıtlı Adresler',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _savedAddresses.length,
            itemBuilder: (context, index) {
              final address = _savedAddresses[index];
              return Card(
                child: ListTile(
                  leading: Text(
                    address.type.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(address.name),
                  subtitle: Text(address.address),
                  trailing: address.isFavorite
                      ? const Icon(Icons.favorite, color: Colors.red)
                      : null,
                  onTap: () => _selectSavedAddress(address),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
