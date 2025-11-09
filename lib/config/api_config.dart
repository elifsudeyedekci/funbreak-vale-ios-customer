// 🔥 MERKEZİ API KONFİGÜRASYONU
// Tüm API URL'leri buradan yönetilir
class ApiConfig {
  // ⚠️ SERVER URL DEĞİŞTİRMEK İÇİN SADECE BU SABİTİ GÜNCELLE!
  static const String baseUrl = 'https://admin.funbreakvale.com';
  
  // API endpoint'leri
  static const String apiPath = '/api';
  static String get apiUrl => '$baseUrl$apiPath';
  
  // Yaygın API endpoint'leri
  static String get getRideMessages => '$apiUrl/get_ride_messages.php';
  static String get sendRideMessage => '$apiUrl/send_ride_message.php';
  static String get getCustomerActiveRides => '$apiUrl/get_customer_active_rides.php';
  static String get checkRideStatus => '$apiUrl/check_ride_status.php';
  static String get createRideRequest => '$apiUrl/create_ride_request.php';
  static String get validateDiscount => '$apiUrl/validate_discount.php';
  static String get checkCustomerDebt => '$apiUrl/check_customer_debt.php';
  static String get cancelRide => '$apiUrl/cancel_ride.php';
  static String get cleanupExpiredRequests => '$apiUrl/cleanup_expired_requests.php';
  static String get smartRequestSystem => '$apiUrl/smart_request_system.php';
  static String get logLegalConsent => '$apiUrl/log_legal_consent.php';
  static String get getHourlyPackages => '$apiUrl/get_hourly_packages.php';
  static String get bridgeCall => '$apiUrl/bridge_call.php';
  static String get rateDriver => '$apiUrl/rate_driver.php';
  static String get updateFcmToken => '$apiUrl/update_fcm_token.php';
  static String get sendAdvancedNotification => '$apiUrl/send_advanced_notification.php';
  static String get getNotificationHistory => '$apiUrl/get_notification_history.php';
  
  // Panel base URL
  static String get panelUrl => baseUrl;
  
  // Debug/logging
  static void printConfig() {
    print('🌐 === API KONFİGÜRASYONU ===');
    print('   Base URL: $baseUrl');
    print('   API URL: $apiUrl');
    print('   Panel URL: $panelUrl');
  }
}
