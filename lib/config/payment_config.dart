// ÖDEME YÖNTEMİ FEATURE FLAG
// Kredi/banka kartı ile ödeme şu an KAPALI - sadece Havale/EFT aktif.
// İleride kart ödemesini tekrar açmak için bu değeri true yapmak yeterli
// (ilgili UI bloklarının hepsi bu sabite bağlı).
const bool kCardPaymentEnabled = false;

// Kart ödemesi kapalıyken kullanılacak varsayılan/tek ödeme yöntemi kodu.
const String kDefaultPaymentMethod = 'havale_eft';
