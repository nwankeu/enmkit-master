// lib/models/relay_consumption_data_point.dart

class RelayConsumptionDataPoint {
  final int? id;
  final String relayIdentificateur; // Pour lier à un relais spécifique
  final DateTime timestamp;
  final double consumption;

  RelayConsumptionDataPoint({
    this.id,
    required this.relayIdentificateur,
    required this.timestamp,
    required this.consumption,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'relayIdentificateur': relayIdentificateur,
      'timestamp': timestamp.toIso8601String(),
      'consumption': consumption,
    };
  }

  factory RelayConsumptionDataPoint.fromMap(Map<String, dynamic> map) {
    return RelayConsumptionDataPoint(
      id: map['id'] as int?,
      relayIdentificateur: map['relayIdentificateur'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      consumption: (map['consumption'] as num).toDouble(),
    );
  }

  @override
  String toString() {
    return 'RelayConsumptionDataPoint{id: $id, relayId: $relayIdentificateur, timestamp: $timestamp, consumption: $consumption}';
  }
}