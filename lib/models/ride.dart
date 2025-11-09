import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Ride {
  final String id;
  final String customerId;
  final String? driverId;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final String pickupAddress;
  final String destinationAddress;
  final String? specialInstructions;
  final String paymentMethod;
  final double estimatedPrice;
  final int estimatedTime;
  final double? actualPrice;
  final int? actualTime;
  final String status;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final DateTime? completedAt;
  final double? rating;
  final String? review;
  final DateTime? ratedAt;

  Ride({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.pickupAddress,
    required this.destinationAddress,
    this.specialInstructions,
    required this.paymentMethod,
    required this.estimatedPrice,
    required this.estimatedTime,
    this.actualPrice,
    this.actualTime,
    required this.status,
    required this.createdAt,
    this.cancelledAt,
    this.completedAt,
    this.rating,
    this.review,
    this.ratedAt,
  });

  factory Ride.fromMap(Map<String, dynamic> map, String id) {
    // Firebase GeoPoint yerine normal lat/lng kullan
    double pickupLat = 0.0, pickupLng = 0.0;
    double destLat = 0.0, destLng = 0.0;
    
    if (map['pickupLocation'] != null) {
      if (map['pickupLocation'] is GeoPoint) {
        pickupLat = (map['pickupLocation'] as GeoPoint).latitude;
        pickupLng = (map['pickupLocation'] as GeoPoint).longitude;
      } else if (map['pickupLocation'] is Map) {
        pickupLat = (map['pickupLocation']['latitude'] ?? 0.0).toDouble();
        pickupLng = (map['pickupLocation']['longitude'] ?? 0.0).toDouble();
      }
    }
    
    if (map['destinationLocation'] != null) {
      if (map['destinationLocation'] is GeoPoint) {
        destLat = (map['destinationLocation'] as GeoPoint).latitude;
        destLng = (map['destinationLocation'] as GeoPoint).longitude;
      } else if (map['destinationLocation'] is Map) {
        destLat = (map['destinationLocation']['latitude'] ?? 0.0).toDouble();
        destLng = (map['destinationLocation']['longitude'] ?? 0.0).toDouble();
      }
    }

    return Ride(
      id: id,
      customerId: map['customerId'] ?? '',
      driverId: map['driverId'],
      pickupLocation: LatLng(pickupLat, pickupLng),
      destinationLocation: LatLng(destLat, destLng),
      pickupAddress: map['pickupAddress'] ?? '',
      destinationAddress: map['destinationAddress'] ?? '',
      specialInstructions: map['specialInstructions'],
      paymentMethod: map['paymentMethod'] ?? 'cash',
      estimatedPrice: (map['estimatedPrice'] ?? 0.0).toDouble(),
      estimatedTime: map['estimatedTime'] ?? 0,
      actualPrice: map['actualPrice']?.toDouble(),
      actualTime: map['actualTime'],
      status: map['status'] ?? 'pending',
      createdAt: map['createdAt'] is Timestamp 
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      cancelledAt: map['cancelledAt'] is Timestamp ? (map['cancelledAt'] as Timestamp).toDate() : null,
      completedAt: map['completedAt'] is Timestamp ? (map['completedAt'] as Timestamp).toDate() : null,
      rating: map['rating']?.toDouble(),
      review: map['review'],
      ratedAt: map['ratedAt'] is Timestamp ? (map['ratedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'pickupLocation': GeoPoint(pickupLocation.latitude, pickupLocation.longitude),
      'destinationLocation': GeoPoint(destinationLocation.latitude, destinationLocation.longitude),
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'specialInstructions': specialInstructions,
      'paymentMethod': paymentMethod,
      'estimatedPrice': estimatedPrice,
      'estimatedTime': estimatedTime,
      'actualPrice': actualPrice,
      'actualTime': actualTime,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'rating': rating,
      'review': review,
      'ratedAt': ratedAt != null ? Timestamp.fromDate(ratedAt!) : null,
    };
  }

  Ride copyWith({
    String? id,
    String? customerId,
    String? driverId,
    LatLng? pickupLocation,
    LatLng? destinationLocation,
    String? pickupAddress,
    String? destinationAddress,
    String? specialInstructions,
    String? paymentMethod,
    double? estimatedPrice,
    int? estimatedTime,
    double? actualPrice,
    int? actualTime,
    String? status,
    DateTime? createdAt,
    DateTime? cancelledAt,
    DateTime? completedAt,
    double? rating,
    String? review,
    DateTime? ratedAt,
  }) {
    return Ride(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      actualPrice: actualPrice ?? this.actualPrice,
      actualTime: actualTime ?? this.actualTime,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      completedAt: completedAt ?? this.completedAt,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      ratedAt: ratedAt ?? this.ratedAt,
    );
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'accepted':
        return 'Kabul Edildi';
      case 'arrived':
        return 'Geldi';
      case 'started':
        return 'Yolculuk Başladı';
      case 'completed':
        return 'Tamamlandı';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return 'Bilinmiyor';
    }
  }

  bool get isActive => status == 'pending' || status == 'accepted' || status == 'arrived' || status == 'started';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get canBeRated => isCompleted && rating == null;
} 