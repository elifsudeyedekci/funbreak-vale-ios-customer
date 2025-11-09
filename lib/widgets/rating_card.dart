import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RatingCard extends StatefulWidget {
  final String rideId;
  final String driverId;
  final String driverName;
  final String customerId;
  final VoidCallback onComplete;
  
  const RatingCard({
    Key? key,
    required this.rideId,
    required this.driverId,
    required this.driverName,
    required this.customerId,
    required this.onComplete,
  }) : super(key: key);
  
  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> with SingleTickerProviderStateMixin {
  int _selectedRating = 0;
  final TextEditingController _commentController = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _isSubmitting = false;
  
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }
  
  @override
  void dispose() {
    _animController.dispose();
    _commentController.dispose();
    super.dispose();
  }
  
  Future<void> _submitRating() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen puan seçin'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/rate_driver.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': int.tryParse(widget.driverId) ?? 0,
          'ride_id': int.tryParse(widget.rideId) ?? 0,
          'rating': _selectedRating,
          'customer_id': int.tryParse(widget.customerId) ?? 0,
          'review': _commentController.text.trim(),
          'comment': _commentController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Değerlendirmeniz kaydedildi!'), backgroundColor: Colors.green),
          );
          widget.onComplete();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
    
    setState(() => _isSubmitting = false);
  }
  
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.star, size: 60, color: Colors.white),
              const SizedBox(height: 12),
              const Text(
                'Şoförünüzü Değerlendirin',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                widget.driverName,
                style: const TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              
              // 5 YILDIZ
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRating = index + 1;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.star,
                        size: 50,
                        color: index < _selectedRating ? Colors.white : Colors.white38,
                      ),
                    ),
                  );
                }),
              ),
              
              if (_selectedRating > 0) ...[
                const SizedBox(height: 20),
                Text(
                  _selectedRating == 5 ? '🎉 Harika!' : 
                  _selectedRating == 4 ? '👍 Çok İyi!' : 
                  _selectedRating == 3 ? '😊 İyi' : 
                  _selectedRating == 2 ? '😐 Fena Değil' : '😔 Kötü',
                  style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // YORUM ALANI
              TextField(
                controller: _commentController,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'Yorumunuzu yazın (opsiyonel)',
                  hintStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: const TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              
              const SizedBox(height: 20),
              
              // BUTONLAR
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : widget.onComplete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Atla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitRating,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFFFD700),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

