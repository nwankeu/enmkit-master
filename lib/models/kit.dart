// lib/models/kit.dart

class Kit {
  final int? id; // Nullable car auto-incrémenté, et il n'y aura qu'un seul kit
  final String kitNumber; // Numéro de téléphone de la SIM du kit
  double currentConsumption; // Consommation actuelle (pourrait être initialConsumption au début)
  int currentImpulses;    // Nombre d'impulsions actuel

  Kit({
    this.id,
    required this.kitNumber,
    this.currentConsumption = 0.0,
    this.currentImpulses = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kitNumber': kitNumber,
      'currentConsumption': currentConsumption,
      'currentImpulses': currentImpulses,
    };
  }

  factory Kit.fromMap(Map<String, dynamic> map) {
    return Kit(
      id: map['id'] as int?,
      kitNumber: map['kitNumber'] as String,
      currentConsumption: (map['currentConsumption'] as num).toDouble(), // Gérer num puis convertir
      currentImpulses: map['currentImpulses'] as int,
    );
  }

  @override
  String toString() {
    return 'Kit{id: $id, kitNumber: $kitNumber, currentConsumption: $currentConsumption, currentImpulses: $currentImpulses}';
  }
}