// lib/models/relay.dart

class Relay {
  final int? id; // Nullable pour l'auto-incrémentation par la DB
  final String identificateur; // Ex: "REL1", "REL2", utilisé dans les commandes SMS
  String name;
  double amperage;
  bool state; // true pour ON, false pour OFF
  final bool isDefaultRelay; // Pour savoir si c'est un des 4 relais initiaux
  
  // NOUVEAU CHAMP pour la consommation spécifique à ce relais
  double currentRelayConsumption; 
  
  String? test; // Champ 'test' que vous aviez, gardé pour l'instant

  Relay({
    this.id,
    required this.identificateur,
    required this.name,
    required this.amperage,
    this.state = false, // Par défaut, un relais est éteint
    this.isDefaultRelay = false,
    this.currentRelayConsumption = 0.0, // NOUVEAU: Initialisation par défaut
    this.test,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'identificateur': identificateur,
      'name': name,
      'amperage': amperage,
      'state': state ? 1 : 0, // Conversion booléen en entier pour SQLite
      'isDefaultRelay': isDefaultRelay ? 1 : 0, // Conversion booléen en entier
      'currentRelayConsumption': currentRelayConsumption, // NOUVEAU CHAMP
      'test': test,
    };
  }

  factory Relay.fromMap(Map<String, dynamic> map) {
    return Relay(
      id: map['id'] as int?,
      identificateur: map['identificateur'] as String,
      name: map['name'] as String,
      amperage: (map['amperage'] as num).toDouble(), // Assurer la conversion en double
      state: (map['state'] as int) == 1, // Conversion entier en booléen
      isDefaultRelay: (map['isDefaultRelay'] as int) == 1, // Conversion entier en booléen
      // NOUVEAU CHAMP: Gérer le cas où la colonne pourrait être absente d'anciennes DB
      // ou si la valeur est null (bien que notre schéma ait un DEFAULT 0.0)
      currentRelayConsumption: (map['currentRelayConsumption'] as num?)?.toDouble() ?? 0.0, 
      test: map['test'] as String?,
    );
  }

   @override
  String toString() {
    return 'Relay{id: $id, identificateur: $identificateur, name: $name, amperage: $amperage, state: $state, isDefault: $isDefaultRelay, consumption: $currentRelayConsumption}';
  }
}