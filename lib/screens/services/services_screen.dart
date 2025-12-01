import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Hizmetler'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            _buildServiceCard(
              context,
              'Mesafe Bazlı Vale',
              'KM\'ye göre ücretlendirme',
              Icons.route,
              const Color(0xFFFFD700),
              themeProvider,
            ),
            _buildServiceCard(
              context,
              'Saatlik Vale',
              'Saatlik paket hizmeti',
              Icons.access_time,
              const Color(0xFFFFA500),
              themeProvider,
            ),
            _buildServiceCard(
              context,
              'Araç Muayenesi',
              'Periyodik muayene hizmeti',
              Icons.verified_user,
              const Color(0xFF4CAF50),
              themeProvider,
            ),
            _buildServiceCard(
              context,
              'Araç Yıkama',
              'İç ve dış temizlik',
              Icons.local_car_wash,
              const Color(0xFF2196F3),
              themeProvider,
            ),
            _buildServiceCard(
              context,
              'Araç Bakımı',
              'Periyodik bakım hizmeti',
              Icons.build,
              const Color(0xFF9C27B0),
              themeProvider,
            ),
            _buildServiceCard(
              context,
              'Lastik Değişimi',
              'Yaz/kış lastik değişimi',
              Icons.tire_repair,
              const Color(0xFFFF5722),
              themeProvider,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
    ThemeProvider themeProvider,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
