import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // PROVIDER IMPORT!
import 'package:firebase_messaging/firebase_messaging.dart'; // FIREBASE IMPORT!
import 'package:shared_preferences/shared_preferences.dart'; // SHARED PREFERENCES IMPORT!
import '../providers/admin_api_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NotificationsBottomSheet extends StatefulWidget {
  const NotificationsBottomSheet({Key? key}) : super(key: key);

  @override
  State<NotificationsBottomSheet> createState() => _NotificationsBottomSheetState();
}

class _NotificationsBottomSheetState extends State<NotificationsBottomSheet> with TickerProviderStateMixin {
  late TabController _tabController;
  
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;
  
  // 🔥 TAB OKUNMA TRACKING
  bool _announcementsTabOpened = false;
  bool _campaignsTabOpened = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0); // DUYURULAR 0. INDEX!
    _loadData();
    
    // 🔥 TAB DEĞİŞİMİ DİNLE - Hangi tab açıldı takip et
    _tabController.addListener(() {
      print('🔍 Tab listener tetiklendi - Index: ${_tabController.index}, indexIsChanging: ${_tabController.indexIsChanging}');
      
      // indexIsChanging = false olduğunda gerçekten değişmiş demektir
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0 && !_announcementsTabOpened) {
          _announcementsTabOpened = true;
          _markAnnouncementsAsRead();
          print('📢 Duyurular tab\'ı açıldı - okundu olarak işaretlendi');
        } else if (_tabController.index == 1 && !_campaignsTabOpened) {
          _campaignsTabOpened = true;
          _markCampaignsAsRead();
          print('🎯 Kampanyalar tab\'ı açıldı - okundu olarak işaretlendi');
        }
      }
    });
    
    // İlk tab (duyurular) otomatik açık - hemen işaretle
    _announcementsTabOpened = true;
    _markAnnouncementsAsRead();
    
    // FIREBASE MESAJ DİNLEME - UI REFRESH İÇİN!
    _setupFirebaseListener();
  }
  
  // FIREBASE MESSAGE LISTENER - UI REFRESH!
  void _setupFirebaseListener() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('🔔 MÜŞTERİ NotificationsWidget: Firebase message alındı');
        print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
        
        // Bildirim tipindeyse UI'yı refresh et
        if (message.data['type'] == 'announcement') {
          print('🔄 MÜŞTERİ BİLDİRİM WIDGET REFRESH başlatılıyor...');
          
          // 2 saniye bekle (database'e kayıt tamamlansın)
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              print('🔄 Müşteri kampanya/duyuru listesi yenileniyor...');
              _loadData(); // Widget'ı yenile!
            }
          });
        }
      });
      
      print('✅ MÜŞTERİ Notifications Firebase listener kuruldu');
    } catch (e) {
      print('❌ MÜŞTERİ Firebase listener setup hatası: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      // MÜŞTERİ KAMPANYA/DUYURU ÇEK - SAFE PROVIDER ACCESS!
      AdminApiProvider? adminApi;
      try {
        adminApi = Provider.of<AdminApiProvider>(context, listen: false);
        print('✅ Müşteri AdminApiProvider Provider\'dan alındı: ${adminApi.runtimeType}');
      } catch (e) {
        print('⚠️ Provider context hatası - direkt AdminApiProvider kullanılıyor: $e');
        adminApi = AdminApiProvider();
        print('✅ Müşteri AdminApiProvider direkt oluşturuldu: ${adminApi.runtimeType}');
      }
      
      final campaigns = await adminApi.getCampaigns();
      final announcements = await adminApi.getAnnouncements();
      
      print('🔔 === BİLDİRİM VERİ YÜKLENDİ ===');
      print('📢 Kampanya sayısı: ${campaigns.length}');
      print('📢 Duyuru sayısı: ${announcements.length}');
      
      // Detaylı debug
      if (campaigns.isNotEmpty) {
        print('🎯 İlk kampanya: ${campaigns.first}');
      }
      if (announcements.isNotEmpty) {
        print('📢 İlk duyuru: ${announcements.first}');
      }
      
      setState(() {
        _campaigns = campaigns.map((c) {
          final Map<String, dynamic> campaign = Map<String, dynamic>.from(c);
          campaign['icon'] = Icons.local_offer;
          campaign['color'] = Colors.orange;
          print('🎯 Kampanya widget\'a eklendi: ${campaign['title']}');
          return campaign;
        }).toList();
        
        _announcements = announcements.map((a) {
          final Map<String, dynamic> announcement = Map<String, dynamic>.from(a);
          announcement['icon'] = Icons.campaign;
          announcement['color'] = Colors.blue;
          print('📢 Duyuru widget\'a eklendi: ${announcement['title']} (type: ${announcement['type'] ?? 'unknown'})');
          return announcement;
        }).toList();
        
        print('📊 Widget state güncellendi: ${_campaigns.length} kampanya, ${_announcements.length} duyuru');
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // dispose'da artık işaretleme yapmıyoruz - tab değişiminde yapıyoruz
    super.dispose();
  }
  
  // 🔥 DUYURULARI OKUNDU OLARAK İŞARETLE
  Future<void> _markAnnouncementsAsRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Server saatini kullan (timezone problemi önlenir)
      final serverTime = await _getServerTime();
      await prefs.setString('last_notifications_opened', serverTime);
      print('✅ Duyurular okundu olarak işaretlendi: $serverTime');
    } catch (e) {
      print('❌ Duyuru okundu işaretleme hatası: $e');
    }
  }
  
  // 🔥 KAMPANYALARI OKUNDU OLARAK İŞARETLE
  Future<void> _markCampaignsAsRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Mevcut kampanya ID'lerini kaydet
      final campaignIds = _campaigns.map((c) => c['id'].toString()).toList();
      await prefs.setStringList('read_campaign_ids', campaignIds);
      
      // Tarih de kaydet (eski kampanyalar için)
      final serverTime = await _getServerTime();
      await prefs.setString('last_campaigns_opened', serverTime);
      
      print('✅ Kampanyalar okundu olarak işaretlendi: ${campaignIds.length} ID');
      print('   📋 ID\'ler: $campaignIds');
    } catch (e) {
      print('❌ Kampanya okundu işaretleme hatası: $e');
    }
  }
  
  // Server saatini al
  Future<String> _getServerTime() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_server_time.php'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverTime = data['server_time']['iso'];
        print('⏰ Server saati alındı: $serverTime');
        return serverTime;
      }
    } catch (e) {
      print('⚠️ Server saati alınamadı, local kullanılıyor: $e');
    }
    
    // Fallback: Local saat
    return DateTime.now().toIso8601String();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          
          // Header with tabs
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Bildirimler',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey[600],
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Duyurular'), // DUYURULAR ÖNCE!
                      Tab(text: 'Kampanyalar'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Duyurular - ŞİMDİ ÖNCE!
                      _announcements.isEmpty
                          ? _buildEmptyState('Henüz duyuru bulunmuyor', Icons.campaign)
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _announcements.length,
                              itemBuilder: (context, index) {
                                return _buildNotificationCard(_announcements[index]);
                              },
                            ),
                      
                      // Kampanyalar - ŞİMDİ İKİNCİ!
                      _campaigns.isEmpty
                          ? _buildEmptyState('Henüz kampanya bulunmuyor', Icons.local_offer)
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _campaigns.length,
                              itemBuilder: (context, index) {
                                return _buildNotificationCard(_campaigns[index]);
                              },
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: notification['color'].withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: notification['color'].withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: notification['color'],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              notification['icon'],
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification['title'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification['subtitle'],
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  notification['date'],
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

