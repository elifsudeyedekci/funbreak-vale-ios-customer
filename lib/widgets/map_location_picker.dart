import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;
  final Function(LatLng, String) onLocationSelected;

  const MapLocationPicker({
    Key? key,
    this.initialLocation,
    required this.onLocationSelected,
  }) : super(key: key);

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(41.0082, 28.9784);
  String _selectedAddress = 'Konum seçiliyor...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!;
      _getAddressFromLocation(_selectedLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Konum Seç',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : () {
              widget.onLocationSelected(_selectedLocation, _selectedAddress);
              Navigator.pop(context);
            },
            child: Text(
              'Seç',
              style: TextStyle(
                color: _isLoading ? Colors.grey : const Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: _selectedLocation,
              zoom: 15,
            ),
            onTap: (LatLng location) {
              setState(() {
                _selectedLocation = location;
              });
              _getAddressFromLocation(location);
            },
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _selectedLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              ),
            },
          ),
          
          // Address Info Card
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seçilen Konum',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFFFFD700),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedAddress,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getAddressFromLocation(LatLng location) async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        
        // DETAYLI ADRES FORMATI - SOKAK İSMİ, KAPI NO, BİNA ADI!
        List<String> addressParts = [];
        
        // 1. SOKAK ISMI (önce sokak)
        if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
          addressParts.add(place.thoroughfare!);
        } else if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        
        // 2. APT NUMARASI (sokak sonunda)
        if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
          addressParts.add('No: ${place.subThoroughfare}');
        }
        
        // 3. MAHALLE (MUTLAKA EN BAŞTA OLMALI - DÜZELTİLDİ!) ✅
        String mahalle = '';
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          mahalle = place.subLocality!;
        } else if (place.subAdministrativeArea != null && place.subAdministrativeArea!.isNotEmpty) {
          mahalle = place.subAdministrativeArea!;
        }
        
        // Mahalle varsa en başa ekle
        if (mahalle.isNotEmpty) {
          addressParts.insert(0, mahalle); // EN BAŞA EKLE!
        }
        
        // 4. İl
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        
        // Final adres - boş olanları filtrele, MAHALLE EN BAŞTA! ✅
        String address = addressParts
            .where((part) => part.trim().isNotEmpty)
            .toSet() // Duplicate'leri kaldır
            .take(3) // Maksimum 3 parça
            .join(', ');
        
        // Fallback - hiçbir detay yoksa
        if (address.isEmpty) {
          address = '${place.subLocality ?? place.locality ?? 'Seçilen Konum'}';
        }
        
        print('📍 Reverse geocoding: ${place.thoroughfare}, ${place.subThoroughfare}, ${place.name}');
        print('📍 Final adres: $address');
        
        setState(() {
          _selectedAddress = address;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _selectedAddress = 'Konum bilgisi alınamadı';
        _isLoading = false;
      });
    }
  }
}
