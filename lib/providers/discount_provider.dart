import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DiscountProvider with ChangeNotifier {
  String? _appliedCode;
  double _discountPercent = 0.0;
  String? _discountName;
  bool _isLoading = false;
  String? _error;

  String? get appliedCode => _appliedCode;
  double get discountPercent => _discountPercent;
  String? get discountName => _discountName;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasDiscount => _appliedCode != null;

  Future<bool> validateDiscountCode(String code) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('http://localhost/vale-management-web/api/validate_discount.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _appliedCode = code;
          _discountPercent = data['discount_percent'].toDouble();
          _discountName = data['name'];
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _error = data['message'];
        }
      } else {
        _error = 'Sunucu hatası';
      }
    } catch (e) {
      _error = 'Bağlantı hatası: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  double calculateDiscountedPrice(double originalPrice) {
    if (!hasDiscount) return originalPrice;
    return originalPrice * (1 - (_discountPercent / 100));
  }

  void clearDiscount() {
    _appliedCode = null;
    _discountPercent = 0.0;
    _discountName = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
