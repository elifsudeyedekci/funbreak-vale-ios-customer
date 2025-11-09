import 'dart:convert';
import 'package:http/http.dart' as http;

class LocationSearchService {
  static const String _apiKey = 'AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY'; // Google Places API Key
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  // Konum arama (autocomplete) - GELİŞTİRİLMİŞ DEBUG VE FALLBACK!
  static Future<List<PlaceAutocomplete>> getPlaceAutocomplete(String query) async {
    try {
      if (query.isEmpty || query.length < 2) {
        print('🔍 Query çok kısa veya boş: "$query"');
        return [];
      }

      print('🔍 === GOOGLE PLACES API ARAMA BAŞLADI ===');
      print('🔍 Query: "$query"');
      print('🔍 API Key: ${_apiKey.substring(0, 10)}...${_apiKey.substring(_apiKey.length - 5)}');
      print('🔍 API Key uzunluğu: ${_apiKey.length} karakter');
      
      // API KEY GEÇERLİLİK TEST - BASIT QUERY!
      if (query == 'test' || query == 'istanbul') {
        await _testGooglePlacesAPI();
      }

      // Türkiye geneli arama - İstanbul odaklı
      final url = Uri.parse(
        '$_baseUrl/autocomplete/json?'
        'input=${Uri.encodeComponent(query)}&'
        'key=$_apiKey&'
        'language=tr&'
        'components=country:tr&'
        'types=geocode|establishment&'
        'location=41.0082,28.9784&' // İstanbul merkez
        'radius=100000' // 100km radius
      );

      print('🔍 Google Places API URL: ${url.toString().replaceAll(_apiKey, 'API_KEY_HIDDEN')}');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      print('🔍 HTTP Response: ${response.statusCode}');
      print('🔍 Response Body Preview: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('🔍 API Status: ${data['status']}');
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          print('✅ ${predictions.length} Google Places sonuç bulundu');
          
          final apiResults = predictions.map((prediction) => PlaceAutocomplete.fromJson(prediction)).toList();
          
          // Debug: İlk 3 sonucu logla
          for (int i = 0; i < apiResults.length && i < 3; i++) {
            print('   Sonuç ${i+1}: ${apiResults[i].mainText} | ${apiResults[i].secondaryText}');
          }
          
          // API sonuçları varsa onları döndür - FALLBACK KULLANMA!
          if (apiResults.isNotEmpty) {
            print('✅ Google Places API sonuçları döndürülüyor');
            return apiResults;
          } else {
            print('⚠️ Google API sonuç boş - BOŞ LİSTE DÖN (fallback değil)');
            return []; // Fallback yerine boş liste döndür
          }
        } else {
          final errorMessage = data['error_message'] ?? 'Bilinmeyen API hatası';
          print('❌ Google Places API hatası: ${data['status']} - $errorMessage');
          
          // Özel hata durumları için daha iyi handling
          if (data['status'] == 'REQUEST_DENIED') {
            print('❌ API KEY SORUNLU! Places API aktif değil - FALLBACK KULLAN');
            return _getFallbackResults(query); // Sadece bu durumda fallback
          } else if (data['status'] == 'OVER_QUERY_LIMIT') {
            print('❌ API QUOTA AŞILDI! - FALLBACK KULLAN');
            return _getFallbackResults(query); // Sadece bu durumda fallback
          } else if (data['status'] == 'ZERO_RESULTS') {
            print('⚠️ Google API hiç sonuç bulamadı - BOŞ LİSTE DÖN');
            return []; // Sonuç yok ise boş liste
          }
          
          // Diğer API hataları için boş liste döndür
          return [];
        }
      } else {
        print('❌ HTTP hatası: ${response.statusCode}');
        print('❌ Response: ${response.body}');
        
        // HTTP hatası - SADECE 403/401 gibi yetki hatalarında fallback
        if (response.statusCode == 403 || response.statusCode == 401) {
          print('🔑 Yetki hatası - FALLBACK KULLAN');
          return _getFallbackResults(query);
        }
        
        // Diğer HTTP hataları için boş liste
        return [];
      }
    } catch (e) {
      print('❌ Konum arama exception: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      
      // Exception durumu - SADECE network hatası ise fallback
      if (e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
        print('🌐 Network hatası - FALLBACK KULLAN');
        return _getFallbackResults(query);
      }
      
      // Diğer exception'lar için boş liste
      return [];
    }
  }

  // API çalışmadığında İstanbul'a özel örnek sonuçlar döndür
  // AKıLLı KONUM ARAMA SİSTEMİ - ZORLU, İSTİNYE GİBİ ÖZEL ÖNERİLER!
  static List<PlaceAutocomplete> _getFallbackResults(String query) {
    final lowerQuery = query.toLowerCase();
    
    print('🧠 Fallback arama başlatıldı: "$lowerQuery"');
    
    // AKıLLı ÖNERİ SİSTEMİ - KELİME EŞLEŞTIRME
    List<Map<String, dynamic>> smartSuggestions = _getSmartSuggestions(lowerQuery); // AKTİFLEŞTİRİLDİ!
    
    final List<Map<String, dynamic>> fallbackData = [
      {
        'place_id': 'fallback_1',
        'description': 'Watergarden AVM, Ataşehir, İstanbul',
        'structured_formatting': {
          'main_text': 'Watergarden AVM',
          'secondary_text': 'Ataşehir, İstanbul'
        }
      },
      {
        'place_id': 'fallback_2', 
        'description': 'Taksim Meydanı, Beyoğlu, İstanbul',
        'structured_formatting': {
          'main_text': 'Taksim Meydanı',
          'secondary_text': 'Beyoğlu, İstanbul'
        }
      },
      {
        'place_id': 'fallback_3',
        'description': 'Wabi Hostels, Şişli, İstanbul', 
        'structured_formatting': {
          'main_text': 'Wabi Hostels',
          'secondary_text': 'Şişli, İstanbul'
        }
      },
      {
        'place_id': 'fallback_4',
        'description': 'Sultanahmet Camii, Fatih, İstanbul',
        'structured_formatting': {
          'main_text': 'Sultanahmet Camii', 
          'secondary_text': 'Fatih, İstanbul'
        }
      },
      {
        'place_id': 'fallback_5',
        'description': 'Galata Kulesi, Beyoğlu, İstanbul',
        'structured_formatting': {
          'main_text': 'Galata Kulesi',
          'secondary_text': 'Beyoğlu, İstanbul'
        }
      },
      {
        'place_id': 'fallback_6',
        'description': 'Kapalıçarşı, Fatih, İstanbul',
        'structured_formatting': {
          'main_text': 'Kapalıçarşı',
          'secondary_text': 'Fatih, İstanbul'
        }
      },
      {
        'place_id': 'fallback_7',
        'description': 'Bosphorus Bridge, Beşiktaş, İstanbul',
        'structured_formatting': {
          'main_text': 'Bosphorus Bridge',
          'secondary_text': 'Beşiktaş, İstanbul'
        }
      },
      {
        'place_id': 'fallback_8',
        'description': 'Kadıköy İskelesi, Kadıköy, İstanbul',
        'structured_formatting': {
          'main_text': 'Kadıköy İskelesi',
          'secondary_text': 'Kadıköy, İstanbul'
        }
      },
      {
        'place_id': 'fallback_9',
        'description': 'Eminönü, Fatih, İstanbul',
        'structured_formatting': {
          'main_text': 'Eminönü',
          'secondary_text': 'Fatih, İstanbul'
        }
      },
      {
        'place_id': 'fallback_10',
        'description': 'Levent Metro, Beşiktaş, İstanbul',
        'structured_formatting': {
          'main_text': 'Levent Metro',
          'secondary_text': 'Beşiktaş, İstanbul'
        }
      }
    ];

    // AKıLLI ÖNERİLER + FALLBACK DATA BİRLEŞTİR!
    List<Map<String, dynamic>> allResults = [];
    
    // Önce akıllı önerileri ekle (daha öncelikli)
    allResults.addAll(smartSuggestions);
    
    // Sonra fallback data ekle
    allResults.addAll(fallbackData);
    
    print('🧠 Toplam sonuç havuzu: ${allResults.length} (${smartSuggestions.length} akıllı + ${fallbackData.length} fallback)');
    
    // Query'ye göre filtrele - GELIŞMİŞ ARAMA
    final filteredResults = allResults.where((item) {
      final description = item['description'].toString().toLowerCase();
      final mainText = item['structured_formatting']['main_text'].toString().toLowerCase();
      final secondaryText = item['structured_formatting']['secondary_text'].toString().toLowerCase();
      
      // KELİME EŞLEŞTIRME - ZORLU, İSTİNYE GIBI
      return description.contains(lowerQuery) || 
             mainText.contains(lowerQuery) ||
             secondaryText.contains(lowerQuery);
    }).toList();
    
    print('🧠 Akıllı arama sonucu: ${filteredResults.length} öneri');
    
    // EN İLGİLİ SONUCLARI ÖNE GETiR
    filteredResults.sort((a, b) {
      final aMain = a['structured_formatting']['main_text'].toString().toLowerCase();
      final bMain = b['structured_formatting']['main_text'].toString().toLowerCase();
      
      // Tam eşleşme öncelik
      if (aMain.startsWith(lowerQuery) && !bMain.startsWith(lowerQuery)) return -1;
      if (!aMain.startsWith(lowerQuery) && bMain.startsWith(lowerQuery)) return 1;
      
      return 0;
    });

    print('Fallback sonuçlar: ${filteredResults.length} adet');
    
    return filteredResults.map((item) => PlaceAutocomplete.fromJson(item)).toList();
  }

  // Konum detaylarını al
  static Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/details/json?place_id=$placeId&key=$_apiKey&language=tr&fields=place_id,name,formatted_address,geometry'
      );

      print('Google Places Details API çağrısı: $placeId');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          print('Konum detayları alındı: ${data['result']['name']}');
          return PlaceDetails.fromJson(data['result']);
        } else {
          print('Google Places Details API hatası: ${data['status']}');
        }
      }
      
      return _getFallbackPlaceDetails(placeId);
    } catch (e) {
      print('Konum detay hatası: $e');
      return _getFallbackPlaceDetails(placeId);
    }
  }

  // Fallback place details - İstanbul koordinatları
  static PlaceDetails? _getFallbackPlaceDetails(String placeId) {
    final Map<String, Map<String, dynamic>> fallbackDetails = {
      'fallback_1': {
        'place_id': 'fallback_1',
        'formatted_address': 'Watergarden AVM, Ataşehir, İstanbul',
        'geometry': {
          'location': {'lat': 40.9929, 'lng': 29.1244}
        }
      },
      'fallback_2': {
        'place_id': 'fallback_2',
        'formatted_address': 'Taksim Meydanı, Beyoğlu, İstanbul',
        'geometry': {
          'location': {'lat': 41.0370, 'lng': 28.9857}
        }
      },
      'fallback_3': {
        'place_id': 'fallback_3',
        'formatted_address': 'Wabi Hostels, Şişli, İstanbul',
        'geometry': {
          'location': {'lat': 41.0602, 'lng': 28.9878}
        }
      },
      'fallback_4': {
        'place_id': 'fallback_4',
        'formatted_address': 'Sultanahmet Camii, Fatih, İstanbul',
        'geometry': {
          'location': {'lat': 41.0054, 'lng': 28.9768}
        }
      },
      'fallback_5': {
        'place_id': 'fallback_5',
        'formatted_address': 'Galata Kulesi, Beyoğlu, İstanbul',
        'geometry': {
          'location': {'lat': 41.0256, 'lng': 28.9744}
        }
      },
      'fallback_6': {
        'place_id': 'fallback_6',
        'formatted_address': 'Kapalıçarşı, Fatih, İstanbul',
        'geometry': {
          'location': {'lat': 41.0106, 'lng': 28.9681}
        }
      },
      'fallback_7': {
        'place_id': 'fallback_7',
        'formatted_address': 'Bosphorus Bridge, Beşiktaş, İstanbul',
        'geometry': {
          'location': {'lat': 41.0391, 'lng': 29.0350}
        }
      },
      'fallback_8': {
        'place_id': 'fallback_8',
        'formatted_address': 'Kadıköy İskelesi, Kadıköy, İstanbul',
        'geometry': {
          'location': {'lat': 40.9061, 'lng': 29.0210}
        }
      },
      'fallback_9': {
        'place_id': 'fallback_9',
        'formatted_address': 'Eminönü, Fatih, İstanbul',
        'geometry': {
          'location': {'lat': 41.0176, 'lng': 28.9706}
        }
      },
      'fallback_10': {
        'place_id': 'fallback_10',
        'formatted_address': 'Levent Metro, Beşiktaş, İstanbul',
        'geometry': {
          'location': {'lat': 41.0814, 'lng': 29.0092}
        }
      }
    };

    final details = fallbackDetails[placeId];
    if (details != null) {
      return PlaceDetails.fromJson(details);
    }
    return null;
  }

  // Yakındaki yerler (örnek: "Adana'daki restoranlar")
  static Future<List<PlaceAutocomplete>> getNearbyPlaces(String query, double lat, double lng) async {
    try {
      if (query.isEmpty) return [];

      final url = Uri.parse(
        '$_baseUrl/nearbysearch/json?location=$lat,$lng&radius=50000&keyword=${Uri.encodeComponent(query)}&key=$_apiKey&language=tr'
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          return results.map((result) => PlaceAutocomplete.fromNearbyJson(result)).toList();
        }
      }
      
      return [];
    } catch (e) {
      print('Yakındaki yerler hatası: $e');
      return [];
    }
  }

  // AKıLLı ÖNERİ SİSTEMİ - ZORLU, İSTİNYE GİBİ ÖZEL ÖNERİLER! - DOĞRU YER!
  static List<Map<String, dynamic>> _getSmartSuggestions(String query) {
    List<Map<String, dynamic>> suggestions = [];
    
    print('🧠 Akıllı öneri sistemi "$query" için çalışıyor...');
    
    // ZORLU ARAMA ÖNERİLERİ
    if (query.contains('zorlu') || query.contains('zor')) {
      suggestions.addAll([
        {
          'place_id': 'smart_zorlu_1',
          'description': 'Zorlu Center AVM, Beşiktaş, İstanbul',
          'structured_formatting': {
            'main_text': 'Zorlu Center AVM',
            'secondary_text': 'Beşiktaş, İstanbul'
          }
        },
        {
          'place_id': 'smart_zorlu_2', 
          'description': 'Zorlu Center Residence, Beşiktaş, İstanbul',
          'structured_formatting': {
            'main_text': 'Zorlu Center Residence',
            'secondary_text': 'Beşiktaş, İstanbul'
          }
        },
      ]);
    }
    
    // İSTİNYE ARAMA ÖNERİLERİ
    if (query.contains('istinye') || query.contains('istin')) {
      suggestions.addAll([
        {
          'place_id': 'smart_istinye_1',
          'description': 'İstinye Park AVM, Sarıyer, İstanbul',
          'structured_formatting': {
            'main_text': 'İstinye Park AVM',
            'secondary_text': 'Sarıyer, İstanbul'
          }
        },
        {
          'place_id': 'smart_istinye_2',
          'description': 'İstinye Hastanesi, Sarıyer, İstanbul', 
          'structured_formatting': {
            'main_text': 'İstinye Hastanesi',
            'secondary_text': 'Sarıyer, İstanbul'
          }
        },
      ]);
    }
    
    // ORTAKÖY ARAMA ÖNERİLERİ - "ORT" İÇİN!
    if (query.contains('ort') || query.contains('orta')) {
      suggestions.addAll([
        {
          'place_id': 'smart_ortakoy_1',
          'description': 'Ortaköy Meydanı, Beşiktaş, İstanbul',
          'structured_formatting': {
            'main_text': 'Ortaköy Meydanı',
            'secondary_text': 'Beşiktaş, İstanbul'
          }
        },
        {
          'place_id': 'smart_ortakoy_2',
          'description': 'Ortaköy Camii, Beşiktaş, İstanbul',
          'structured_formatting': {
            'main_text': 'Ortaköy Camii',
            'secondary_text': 'Beşiktaş, İstanbul'
          }
        },
        {
          'place_id': 'smart_ortakoy_3',
          'description': 'Ortaköy İskele, Beşiktaş, İstanbul',
          'structured_formatting': {
            'main_text': 'Ortaköy İskele',
            'secondary_text': 'Beşiktaş, İstanbul'
          }
        },
      ]);
    }
    
    // GALATA ARAMA ÖNERİLERİ
    if (query.contains('galata') || query.contains('gala')) {
      suggestions.addAll([
        {
          'place_id': 'smart_galata_1',
          'description': 'Galata Kulesi, Beyoğlu, İstanbul',
          'structured_formatting': {
            'main_text': 'Galata Kulesi',
            'secondary_text': 'Beyoğlu, İstanbul'
          }
        },
      ]);
    }
    
    // FORUM ARAMA ÖNERİLERİ  
    if (query.contains('forum')) {
      suggestions.addAll([
        {
          'place_id': 'smart_forum_1',
          'description': 'Forum İstanbul AVM, Bayrampaşa, İstanbul',
          'structured_formatting': {
            'main_text': 'Forum İstanbul AVM',
            'secondary_text': 'Bayrampaşa, İstanbul'
          }
        },
      ]);
    }
    
    print('✅ ${suggestions.length} akıllı öneri hazırlandı!');
    return suggestions;
  }

  // GOOGLE PLACES API TEST FONKSİYONU
  static Future<void> _testGooglePlacesAPI() async {
    try {
      print('🧪 === GOOGLE PLACES API TEST BAŞLADI ===');
      
      // Basit test query
      final testUrl = Uri.parse(
        '$_baseUrl/autocomplete/json?'
        'input=istanbul&'
        'key=$_apiKey&'
        'language=tr&'
        'components=country:tr'
      );
      
      print('🧪 Test URL: ${testUrl.toString().replaceAll(_apiKey, 'API_KEY_HIDDEN')}');
      
      final response = await http.get(testUrl).timeout(const Duration(seconds: 10));
      
      print('🧪 === TEST RESPONSE ===');
      print('   Status: ${response.statusCode}');
      print('   Headers: ${response.headers}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('   API Status: ${data['status']}');
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          print('   ✅ API ÇALIŞIYOR! ${predictions.length} test sonucu');
          print('   🔑 API Key geçerli');
          print('   🌍 Places API aktif');
        } else if (data['status'] == 'REQUEST_DENIED') {
          print('   ❌ API KEY GEÇERSİZ! Places API aktif değil');
          print('   🔑 Key: ${_apiKey.substring(0, 10)}...${_apiKey.substring(_apiKey.length - 5)}');
        } else if (data['status'] == 'OVER_QUERY_LIMIT') {
          print('   ⚠️ API QUOTA AŞILDI!');
        } else {
          print('   ❌ API Hatası: ${data['status']}');
          if (data['error_message'] != null) {
            print('   💬 Hata: ${data['error_message']}');
          }
        }
      } else {
        print('   ❌ HTTP Hatası: ${response.statusCode}');
        print('   Body: ${response.body}');
      }
      
      print('🧪 === GOOGLE PLACES API TEST TAMAMLANDI ===');
    } catch (e) {
      print('🧪 ❌ Test hatası: $e');
    }
  }
}

class PlaceAutocomplete {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceAutocomplete({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceAutocomplete.fromJson(Map<String, dynamic> json) {
    final structuredFormatting = json['structured_formatting'] ?? {};
    return PlaceAutocomplete(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structuredFormatting['main_text'] ?? json['description'] ?? '',
      secondaryText: structuredFormatting['secondary_text'] ?? '',
    );
  }

  factory PlaceAutocomplete.fromNearbyJson(Map<String, dynamic> json) {
    return PlaceAutocomplete(
      placeId: json['place_id'] ?? '',
      description: json['name'] ?? '',
      mainText: json['name'] ?? '',
      secondaryText: json['vicinity'] ?? '',
    );
  }
}

class PlaceDetails {
  final String placeId;
  final String name;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final location = json['geometry']['location'];
    return PlaceDetails(
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? '',
      formattedAddress: json['formatted_address'] ?? '',
      latitude: location['lat'].toDouble(),
      longitude: location['lng'].toDouble(),
    );
  }
}