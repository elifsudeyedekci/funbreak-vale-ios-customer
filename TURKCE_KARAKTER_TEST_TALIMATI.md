# 🔍 TÜRKÇE KARAKTER TEST TALİMATI

## ⚠️ SORUN:
Mesajlaşma ve yorum ekranlarında Türkçe karakterler (ş, ğ, ü, ı, ö, ç) yazılmıyor.

## 📱 TEST ADIMLARI:

### 1. USB DEBUGGING AÇ:
- Telefonunuzda **Ayarlar** > **Geliştirici Seçenekleri** > **USB Hata Ayıklama** AÇIK olmalı
- Eğer Geliştirici Seçenekleri görünmüyorsa:
  - Ayarlar > Telefon Hakkında > **Yapı Numarası**'na 7 kez tıklayın

### 2. TELEFONLA BİLGİSAYARI BAĞLAYIN:
- USB kabloyla telefonunuzu bilgisayara bağlayın
- Telefonda "USB Hata Ayıklamaya izin ver" mesajı çıkarsa **İZİN VER**

### 3. ADB KONTROL:
Bilgisayarda PowerShell açın:
```powershell
adb devices
```
Telefonunuz görünmeli!

### 4. LOGCAT BAŞLAT:
```powershell
adb logcat -s flutter
```

### 5. UYGULAMAYI AÇ VE TEST ET:
- FunBreak Vale uygulamasını açın
- Bir yolculuk başlatın (veya test için mesajlaşma ekranını açın)
- Mesaj kutusuna tıklayın
- **"ş"** harfine basın
- **"test"** kelimesini yazın

### 6. LOGCAT ÇIKTISINI KOPYALAYIN:
Terminal'de şunları görmelisiniz:
```
🔍 CONTROLLER İÇERİK: "ş"
🔍 UZUNLUK: 1
🔍 BYTES: [351]
```

Eğer **HİÇBİR ŞEY GÖRMÜYORSANız** - klavye karakteri göndermiyor!

### 7. KLAVYE AYARLARI KONTROL:
- Ayarlar > Sistem > Diller ve Giriş > Sanal Klavye
- Hangi klavyeyi kullanıyorsunuz? (Gboard, Samsung, vs)
- Klavye dili **Türkçe** mi?

### 8. ALTERNATIF TEST:
Başka bir uygulamada (WhatsApp, Notlar) aynı klavye ile Türkçe karakter yazabilir misiniz?

---

## 📋 BANA GÖNDERMENİZ GEREKENLER:

1. **Logcat çıktısı** (yukarıdaki adımlardan)
2. **Telefon modeli ve Android versiyonu**
3. **Klavye uygulaması** (Gboard, Samsung, vs)
4. **Ekran videosu** (opsiyonel ama çok yardımcı olur!)

---

## 🎥 EKRAN VİDEOSU KAYDETME:
```powershell
adb shell screenrecord /sdcard/turkce_test.mp4
# Telefonunuzda testi yapın (max 3 dakika)
# CTRL+C ile durdurun
adb pull /sdcard/turkce_test.mp4 .
```

Video bilgisayarınıza inecek!
