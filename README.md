# FunBreak Vale - Müşteri Uygulaması (Android)

FunBreak Vale müşteri uygulaması, alkol aldıktan sonra araç kullanmak istemeyen kişilere özel şoför hizmeti sunan premium vale uygulamasıdır.

## 🚀 Özellikler

### 🔐 Güvenlik
- Firebase Authentication ile güvenli giriş
- KVKK uyumlu kayıt süreci
- SSL şifreli veri transferi
- Konum izinleri yönetimi

### 📍 Konum ve Harita
- Google Maps entegrasyonu
- Canlı konum takibi
- Duraklı rota oluşturma
- Harita üzerinden vale takibi

### 💳 Ödeme Sistemi
- Stripe entegrasyonu
- Nakit ödeme seçeneği
- Bakiye sistemi
- Güvenli ödeme işlemleri

### 🚗 Vale Hizmeti
- Vale çağırma
- Canlı vale takibi
- Tahmini fiyat hesaplama
- Yolculuk geçmişi
- Değerlendirme sistemi

## 🛠️ Teknolojiler

- **Framework**: Flutter 3.x
- **Backend**: Firebase
- **Harita**: Google Maps
- **Ödeme**: Stripe
- **State Management**: Provider
- **Veritabanı**: Cloud Firestore

## 📱 Ekran Görüntüleri

### Ana Ekran
- Harita görünümü
- Vale çağırma butonu
- Aktif yolculuk bilgileri
- Konum göstergesi

### Giriş/Kayıt
- Modern tasarım
- Form validasyonu
- Hata yönetimi
- KVKK onayı

### Yolculuk
- Vale talep formu
- Fiyat hesaplama
- Canlı takip
- Değerlendirme

## 🔧 Kurulum

### Gereksinimler
- Flutter SDK 3.0+
- Android Studio / VS Code
- Firebase hesabı
- Google Maps API anahtarı

### Adımlar

1. **Projeyi klonlayın**
```bash
git clone https://github.com/funbreakvale/customer-android.git
cd customer-android
```

2. **Bağımlılıkları yükleyin**
```bash
flutter pub get
```

3. **Firebase yapılandırması**
   - Firebase Console'da yeni proje oluşturun
   - Android uygulaması ekleyin
   - `google-services.json` dosyasını `android/app/` klasörüne kopyalayın
   - `lib/firebase_options.dart` dosyasını güncelleyin

4. **Google Maps API anahtarı**
   - Google Cloud Console'da Maps API'yi etkinleştirin
   - API anahtarını `android/app/src/main/AndroidManifest.xml` dosyasında güncelleyin

5. **Uygulamayı çalıştırın**
```bash
flutter run
```

## 📁 Proje Yapısı

```
lib/
├── main.dart                 # Ana uygulama dosyası
├── firebase_options.dart     # Firebase yapılandırması
├── providers/               # State management
│   ├── auth_provider.dart
│   ├── location_provider.dart
│   └── ride_provider.dart
├── models/                  # Veri modelleri
│   ├── ride.dart
│   └── driver.dart
├── screens/                 # Ekranlar
│   ├── splash_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── main/
│   │   └── home_screen.dart
│   ├── ride/
│   ├── profile/
│   └── history/
├── utils/                   # Yardımcı dosyalar
│   └── theme.dart
└── widgets/                 # Özel widget'lar
```

## 🎨 Tema

Uygulama premium ve elit görünüm için özel tasarlanmış tema kullanır:

- **Ana Renkler**: Altın (#D4AF37) ve Lacivert (#1E3A8A)
- **Vurgu Renkleri**: Zümrüt (#10B981), Yakut (#EF4444)
- **Modern UI**: Material Design 3
- **Responsive**: Tüm ekran boyutlarına uyumlu

## 🔐 Güvenlik

- Firebase Authentication
- SSL/TLS şifreleme
- Konum izinleri kontrolü
- KVKK uyumluluğu
- Güvenli API çağrıları

## 📊 Performans

- Lazy loading
- Image caching
- Optimized state management
- Memory efficient
- Fast startup time

## 🚀 Yayınlama

### Debug APK
```bash
flutter build apk --debug
```

### Release APK
```bash
flutter build apk --release
```

### App Bundle
```bash
flutter build appbundle --release
```

## 📞 Destek

- **E-posta**: support@funbreakvale.com
- **Telefon**: +90 212 XXX XX XX
- **Web**: https://funbreakvale.com

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır. Detaylar için `LICENSE` dosyasına bakın.

## 🤝 Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit edin (`git commit -m 'Add amazing feature'`)
4. Push edin (`git push origin feature/amazing-feature`)
5. Pull Request oluşturun

## 📈 Geliştirme Planı

- [ ] iOS uygulaması
- [ ] Web admin paneli
- [ ] Push notification sistemi
- [ ] Çoklu dil desteği
- [ ] Offline mod
- [ ] Sosyal medya entegrasyonu

---

**FunBreak Vale** - Güvenli ve konforlu yolculuk deneyimi 🚗✨ 