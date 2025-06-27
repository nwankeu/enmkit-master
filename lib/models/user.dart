// lib/models/user.dart

class User {
  final int? id; 
  final String phoneNumber;
  final String userId; 
  final bool isAdmin;

  User({
    this.id,
    required this.phoneNumber,
    required this.userId,
    this.isAdmin = false, 
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id, // Sera null pour une nouvelle insertion, la DB l'auto-incrémentera
      'phoneNumber': phoneNumber,
      'userId': userId,
      'isAdmin': isAdmin ? 1 : 0, 
    };
  }

  // Méthode pour la mise à jour, n'inclut pas l'ID car on ne met pas à jour la clé primaire.
  // L'ID sera utilisé dans la clause WHERE de la requête UPDATE.
  // Elle n'inclut pas non plus isAdmin car on ne change pas le statut d'admin d'un utilisateur standard ici.
  Map<String, dynamic> toMapForUpdate() {
    return {
      'phoneNumber': phoneNumber,
      'userId': userId,
      // 'isAdmin': isAdmin ? 1 : 0, // On ne modifie pas le statut admin ici
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      phoneNumber: map['phoneNumber'] as String,
      userId: map['userId'] as String,
      isAdmin: (map['isAdmin'] as int) == 1, 
    );
  }

  @override
  String toString() {
    return 'User{id: $id, phoneNumber: $phoneNumber, userId: $userId, isAdmin: $isAdmin}';
  }
}