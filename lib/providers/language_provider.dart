import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  static const String _languageKey = 'selected_language';
  
  Locale _currentLocale = const Locale('tr', 'TR');
  
  Locale get currentLocale => _currentLocale;
  
  String get currentLanguage {
    switch (_currentLocale.languageCode) {
      case 'tr':
        return 'Türkçe';
      case 'en':
        return 'English';
      default:
        return 'Türkçe';
    }
  }
  
  LanguageProvider() {
    _loadLanguage();
  }
  
  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_languageKey) ?? 'tr';
    _currentLocale = Locale(languageCode, languageCode == 'tr' ? 'TR' : 'US');
    notifyListeners();
  }
  
  Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    
    _currentLocale = Locale(languageCode, languageCode == 'tr' ? 'TR' : 'US');
    notifyListeners();
  }
  
  String getTranslatedText(String key) {
    switch (_currentLocale.languageCode) {
      case 'en':
        return _getEnglishText(key);
      default:
        return _getTurkishText(key);
    }
  }
  
  String _getTurkishText(String key) {
    switch (key) {
      case 'welcome':
        return 'Hoş Geldiniz';
      case 'home':
        return 'Ana Sayfa';
      case 'services':
        return 'Hizmetler';
      case 'reservations':
        return 'Rezervasyonlar';
      case 'settings':
        return 'Ayarlar';
      case 'where_to':
        return 'Nereye gitmek istiyorsunuz?';
      case 'call_vale':
        return 'Vale Çağır';
      case 'immediately':
        return 'Hemen';
      case 'special_time':
        return 'Özel Saat';
      case 'profile':
        return 'Profil Bilgileri';
      case 'addresses':
        return 'Adreslerim';
      case 'billing':
        return 'Faturalarım';
      case 'wallet':
        return 'Cüzdan';
      case 'language':
        return 'Dil';
      case 'dark_theme':
        return 'Karanlık Tema';
      case 'help':
        return 'Yardım';
      case 'contact':
        return 'İletişim';
      case 'about':
        return 'Hakkında';
      case 'logout':
        return 'Çıkış Yap';
      case 'where_from':
        return 'Nereden';
      case 'where_to_question':
        return 'Nereye gitmek istiyorsunuz?';
      case 'select_from_map':
        return 'Haritadan seç';
      case 'current_location':
        return 'Mevcut konumum';
      case 'search_location':
        return 'Konum ara...';
      case 'estimated_price':
        return 'Tahmini Fiyat';
      case 'now':
        return 'Hemen';
      case 'hour_1':
        return '1 Saat';
      case 'hour_2':
        return '2 Saat';
      case 'hour_3':
        return '3 Saat';
      case 'hour_4':
        return '4 Saat';
      case 'custom_time':
        return 'Özel Saat';
      case 'campaigns':
        return 'Kampanyalar';
      case 'announcements':
        return 'Duyurular';
      case 'call_vale':
        return 'Vale Çağır';
      case 'vale_service':
        return 'Vale';
      case 'vip_transfer':
        return 'VİP Transfer';
      case 'car_service':
        return 'Araç Servisi';
      case 'courier':
        return 'Kurye';
      case 'active':
        return 'Aktif';
      case 'history':
        return 'Geçmiş';
      case 'waiting':
        return 'Bekleme';
      case 'completed':
        return 'Tamamlandı';
      case 'cancelled':
        return 'İptal';
      case 'start_waiting':
        return 'Bekleme Başlat';
      case 'stop_waiting':
        return 'Beklemeyi Durdur';
      case 'complete_ride':
        return 'Yolculuğu Tamamla';
      case 'accept_ride':
        return 'Kabul Et';
      case 'online':
        return 'Çevrimiçi';
      case 'offline':
        return 'Çevrimdışı';
      case 'daily_earnings':
        return 'Günlük Kazanç';
      case 'completed_rides':
        return 'Tamamlanan';
      case 'available_requests':
        return 'Mevcut Talepler';
      case 'waiting_for_requests':
        return 'Yeni talep bekleniyor...';
      case 'you_are_offline':
        return 'Çevrimdışısınız';
      case 'go_online_message':
        return 'Vale talepleri almak için çevrimiçi olun';
      case 'funbreak_vale':
        return 'FunBreak Vale';
      default:
        return key;
    }
  }
  
  String _getEnglishText(String key) {
    switch (key) {
      case 'welcome':
        return 'Welcome';
      case 'home':
        return 'Home';
      case 'services':
        return 'Services';
      case 'reservations':
        return 'Reservations';
      case 'settings':
        return 'Settings';
      case 'where_to':
        return 'Where do you want to go?';
      case 'call_vale':
        return 'Call Vale';
      case 'immediately':
        return 'Immediately';
      case 'special_time':
        return 'Special Time';
      case 'profile':
        return 'Profile Information';
      case 'addresses':
        return 'My Addresses';
      case 'billing':
        return 'My Bills';
      case 'wallet':
        return 'Wallet';
      case 'language':
        return 'Language';
      case 'dark_theme':
        return 'Dark Theme';
      case 'help':
        return 'Help';
      case 'contact':
        return 'Contact';
      case 'about':
        return 'About';
      case 'logout':
        return 'Logout';
      case 'where_from':
        return 'From';
      case 'where_to_question':
        return 'Where do you want to go?';
      case 'select_from_map':
        return 'Select from map';
      case 'current_location':
        return 'Current location';
      case 'search_location':
        return 'Search location...';
      case 'estimated_price':
        return 'Estimated Price';
      case 'now':
        return 'Now';
      case 'hour_1':
        return '1 Hour';
      case 'hour_2':
        return '2 Hours';
      case 'hour_3':
        return '3 Hours';
      case 'hour_4':
        return '4 Hours';
      case 'custom_time':
        return 'Custom Time';
      case 'campaigns':
        return 'Campaigns';
      case 'announcements':
        return 'Announcements';
      case 'call_vale':
        return 'Call Vale';
      case 'vale_service':
        return 'Vale';
      case 'vip_transfer':
        return 'VIP Transfer';
      case 'car_service':
        return 'Car Service';
      case 'courier':
        return 'Courier';
      case 'active':
        return 'Active';
      case 'history':
        return 'History';
      case 'waiting':
        return 'Waiting';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'start_waiting':
        return 'Start Waiting';
      case 'stop_waiting':
        return 'Stop Waiting';
      case 'complete_ride':
        return 'Complete Ride';
      case 'accept_ride':
        return 'Accept';
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'daily_earnings':
        return 'Daily Earnings';
      case 'completed_rides':
        return 'Completed';
      case 'available_requests':
        return 'Available Requests';
      case 'waiting_for_requests':
        return 'Waiting for new requests...';
      case 'you_are_offline':
        return 'You are offline';
      case 'go_online_message':
        return 'Go online to receive vale requests';
      case 'valet_searching':
        return 'Searching Valet';
      case 'valet_not_found':
        return 'Valet Not Found';
      case 'cancel':
        return 'Cancel';
      case 'ok':
        return 'OK';
      case 'call':
        return 'Call';
      case 'try_again_later':
        return 'Please try again later or call for reservation.';
      case 'nearest_valet_searching':
        return 'Finding nearest valet...';
      case 'will_be_accepted_in_30_seconds':
        return 'Will be accepted within 30 seconds';
      case 'account':
        return 'Account';
      case 'application':
        return 'Application';
      case 'notifications':
        return 'Notifications';
      case 'support':
        return 'Support';
      case 'privacy_policy':
        return 'Privacy Policy';
      case 'terms_of_use':
        return 'Terms of Use';
      case 'rate_app':
        return 'Rate App';
      case 'help_center':
        return 'Help Center';
      case 'how_to_call_valet':
        return 'How to Call Valet';
      case 'payment_methods':
        return 'Payment Methods';
      case 'pricing_info':
        return 'Pricing Information';
      case 'safety_tips':
        return 'Safety Tips';
      case 'frequently_asked_questions':
        return 'Frequently Asked Questions';
      case 'contact_support':
        return 'Contact Support';
      case 'turkish':
        return 'Türkçe';
      case 'english':
        return 'English';
      case 'select_language':
        return 'Select Language';
      case 'premium_valet_service':
        return 'Premium valet service';
      case 'funbreak_vale':
        return 'FunBreak Vale';
      case 'saved_addresses':
        return 'Saved Addresses';
      case 'billing_information':
        return 'Billing Information';
      case 'add_new_address':
        return 'Add New Address';
      case 'add_billing_info':
        return 'Add Billing Info';
      case 'edit_address':
        return 'Edit Address';
      case 'edit_billing':
        return 'Edit Billing';
      case 'delete':
        return 'Delete';
      case 'edit':
        return 'Edit';
      case 'save':
        return 'Save';
      case 'update':
        return 'Update';
      default:
        return key;
    }
  }
}
