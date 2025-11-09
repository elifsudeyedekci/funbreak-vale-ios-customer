import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const Color primaryGold = Color(0xFFFFD700);
  static const Color primaryNavy = Color(0xFF1E3A8A);
  static const Color primaryWhite = Color(0xFFFFFFFF);
  static const Color primaryGray = Color(0xFFF8FAFC);
  
  // Secondary Colors
  static const Color secondaryGold = Color(0xFFFFB800);
  static const Color secondaryNavy = Color(0xFF0F172A);
  static const Color secondaryGray = Color(0xFF64748B);
  
  // Accent Colors
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentYellow = Color(0xFFF59E0B);
  static const Color accentBlue = Color(0xFF3B82F6);
  
  // Background Colors
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E293B);
  
  // Text Colors
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
}

class AppThemes {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryGold,
        secondary: AppColors.primaryNavy,
        surface: AppColors.surfaceLight,
        background: AppColors.backgroundLight,
        onPrimary: AppColors.textDark,
        onSecondary: AppColors.textLight,
        onSurface: AppColors.textPrimary,
        onBackground: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: AppColors.textLight,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGold,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: AppColors.surfaceLight,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryGold,
        secondary: AppColors.primaryNavy,
        surface: AppColors.surfaceDark,
        background: AppColors.backgroundDark,
        onPrimary: AppColors.textDark,
        onSecondary: AppColors.textLight,
        onSurface: AppColors.textLight,
        onBackground: AppColors.textLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textLight,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGold,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: AppColors.surfaceDark,
      ),
    );
  }
}

class AppSizes {
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;
  
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 24.0;
  
  static const double iconS = 16.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 48.0;
}

class AppStrings {
  // App
  static const String appName = 'FunBreak Vale';
  static const String appVersion = '1.0.0';
  
  // Auth
  static const String login = 'Giriş Yap';
  static const String register = 'Kayıt Ol';
  static const String email = 'E-posta';
  static const String password = 'Şifre';
  static const String forgotPassword = 'Şifremi Unuttum';
  
  // Home
  static const String callVale = 'Vale Çağır';
  static const String myTrips = 'Yolculuklarım';
  static const String profile = 'Profil';
  static const String settings = 'Ayarlar';
  
  // Vale
  static const String valeArriving = 'Vale Yolda';
  static const String valeArrived = 'Vale Geldi';
  static const String tripCompleted = 'Yolculuk Tamamlandı';
  
  // Payment
  static const String payment = 'Ödeme';
  static const String cash = 'Nakit';
  static const String card = 'Kart';
  static const String balance = 'Bakiye';
  
  // Errors
  static const String errorOccurred = 'Bir hata oluştu';
  static const String networkError = 'İnternet bağlantısı hatası';
  static const String tryAgain = 'Tekrar deneyin';
}

class AppAssets {
  static const String logo = 'assets/images/logo.png';
  static const String logoDark = 'assets/images/logo_dark.png';
  static const String placeholder = 'assets/images/placeholder.png';
  
  // Icons
  static const String iconHome = 'assets/icons/home.svg';
  static const String iconMap = 'assets/icons/map.svg';
  static const String iconProfile = 'assets/icons/profile.svg';
  static const String iconSettings = 'assets/icons/settings.svg';
  static const String iconVale = 'assets/icons/vale.svg';
  static const String iconPayment = 'assets/icons/payment.svg';
  
  // Animations
  static const String animationLoading = 'assets/animations/loading.json';
  static const String animationSuccess = 'assets/animations/success.json';
  static const String animationError = 'assets/animations/error.json';
} 

class AppConstants {
  // Colors
  static const int primaryColor = 0xFFFFD700; // Golden yellow
  static const int secondaryColor = 0xFF000000; // Black
  
  // Firebase Collections
  static const String customersCollection = 'customers';
  static const String driversCollection = 'drivers';
  static const String ridesCollection = 'rides';
  static const String pricingPackagesCollection = 'pricing_packages';
  static const String settingsCollection = 'settings';
  
  // Ride Status
  static const String rideStatusPending = 'pending';
  static const String rideStatusAccepted = 'accepted';
  static const String rideStatusArrived = 'arrived';
  static const String rideStatusStarted = 'started';
  static const String rideStatusWaiting = 'waiting';
  static const String rideStatusCompleted = 'completed';
  static const String rideStatusCancelled = 'cancelled';
  
  // Pricing
  static const double defaultBaseFare = 15.0;
  static const double defaultPerKmRate = 2.5;
  static const double defaultPerHourRate = 30.0;
  static const double defaultCommissionRate = 0.15; // 15%
  
  // Waiting Fees
  static const double defaultFreeMinutes = 15.0;
  static const double defaultFeePer15Minutes = 100.0;
  
  // Night Package
  static const int defaultMinHoursForNightPackage = 2;
  static const double defaultNightPackageMultiplier = 1.5;
  
  // UI
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 8.0;
  static const double defaultIconSize = 24.0;
  
  // Validation
  static const int minPasswordLength = 6;
  static const int maxPhoneLength = 15;
  static const int maxNameLength = 50;
  
  // Error Messages
  static const String errorInvalidEmail = 'Geçerli bir e-posta girin';
  static const String errorInvalidPassword = 'Şifre en az 6 karakter olmalı';
  static const String errorInvalidPhone = 'Geçerli bir telefon numarası girin';
  static const String errorInvalidName = 'Geçerli bir ad soyad girin';
  static const String errorNetworkConnection = 'İnternet bağlantısı hatası';
  static const String errorUnknown = 'Bilinmeyen bir hata oluştu';
  
  // Success Messages
  static const String successLogin = 'Giriş başarılı';
  static const String successRegister = 'Kayıt başarılı';
  static const String successRideRequest = 'Yolculuk talebi gönderildi';
  static const String successRideCancelled = 'Yolculuk iptal edildi';
  
  // Loading Messages
  static const String loadingLogin = 'Giriş yapılıyor...';
  static const String loadingRegister = 'Kayıt yapılıyor...';
  static const String loadingRideRequest = 'Yolculuk talebi gönderiliyor...';
  static const String loadingRideCancellation = 'Yolculuk iptal ediliyor...';
} 