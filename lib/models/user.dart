// lib/models/user.dart

class User {
  final int? id; // Nullable car auto-incrémenté par la base de données
  final String phoneNumber;
  final String userId; // Ce sera l'identifiant/mot de passe local
  final bool isAdmin;

  User({
    this.id,
    required this.phoneNumber,
    required this.userId,
    this.isAdmin = false, // Par défaut, un utilisateur n'est pas admin
  });

  // Méthode pour convertir un User en Map (pour l'insertion/mise à jour en DB)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'userId': userId,
      'isAdmin': isAdmin ? 1 : 0, // Stocker booléen comme entier (0 ou 1) en SQLite
    };
  }

  // Méthode pour créer un User à partir d'une Map (lors de la lecture depuis la DB)
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      phoneNumber: map['phoneNumber'] as String,
      userId: map['userId'] as String,
      isAdmin: (map['isAdmin'] as int) == 1, // Convertir entier en booléen
    );
  }

  // Optionnel: pour faciliter le débogage
  @override
  String toString() {
    return 'User{id: $id, phoneNumber: $phoneNumber, userId: $userId, isAdmin: $isAdmin}';
  }
}