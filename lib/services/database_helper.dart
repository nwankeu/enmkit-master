// lib/services/database_helper.dart

import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart'; 
import 'package:enmkit_fresh_start/models/user.dart';
import 'package:enmkit_fresh_start/models/relay_consumption_data_point.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Modèle pour un point de consommation globale du kit
class ConsumptionDataPoint {
  final int? id;
  final DateTime timestamp;
  final double consumption;
  final int impulses;

  ConsumptionDataPoint({
    this.id,
    required this.timestamp,
    required this.consumption,
    required this.impulses,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'consumption': consumption,
      'impulses': impulses,
    };
  }

  factory ConsumptionDataPoint.fromMap(Map<String, dynamic> map) {
    return ConsumptionDataPoint(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      consumption: (map['consumption'] as num).toDouble(),
      impulses: map['impulses'] as int,
    );
  }

  @override
  String toString() {
    return 'ConsumptionDataPoint{id: $id, timestamp: $timestamp, consumption: $consumption, impulses: $impulses}';
  }
}


class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // Nom de fichier pour la version 4 avec la logique d'utilisateur standard unique
    _database = await _initDB('enmkit_app_v4_single_std_user.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, // Garder v4 car le schéma des tables kit/relay/history est le même que la v4 précédente
                   // La logique utilisateur est un changement de méthode, pas de schéma direct de la table users.
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Table users
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phoneNumber TEXT NOT NULL UNIQUE,
        userId TEXT NOT NULL,
        isAdmin INTEGER NOT NULL DEFAULT 0 
      )
    ''');
    print("Table 'users' créée.");
    await _insertDefaultAdmin(db);
    // L'utilisateur de test est retiré, l'utilisateur standard sera configuré par l'admin.

    // Table kits
    await db.execute('''
      CREATE TABLE kits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kitNumber TEXT NOT NULL UNIQUE,
        currentConsumption REAL NOT NULL DEFAULT 0.0,
        currentImpulses INTEGER NOT NULL DEFAULT 0
      )
    ''');
    print("Table 'kits' créée.");

    // Table relays
    await db.execute('''
      CREATE TABLE relays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        identificateur TEXT NOT NULL UNIQUE, 
        name TEXT NOT NULL,
        amperage REAL NOT NULL,
        state INTEGER NOT NULL DEFAULT 0,
        isDefaultRelay INTEGER NOT NULL DEFAULT 0,
        currentRelayConsumption REAL NOT NULL DEFAULT 0.0,
        test TEXT
      )
    ''');
    print("Table 'relays' créée (avec currentRelayConsumption).");

    // Table consumption_history (pour le kit global)
    await db.execute('''
      CREATE TABLE consumption_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        consumption REAL NOT NULL,
        impulses INTEGER NOT NULL
      )
    ''');
    print("Table 'consumption_history' (globale) créée.");

    // Table relay_consumption_history
    await db.execute('''
      CREATE TABLE relay_consumption_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        relayIdentificateur TEXT NOT NULL, 
        timestamp TEXT NOT NULL,
        consumption REAL NOT NULL
      )
    ''');
    print("Table 'relay_consumption_history' créée.");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("Mise à jour DB de v$oldVersion à v$newVersion...");
    if (oldVersion < 2) { 
      await db.execute('CREATE TABLE IF NOT EXISTS kits (id INTEGER PRIMARY KEY AUTOINCREMENT, kitNumber TEXT NOT NULL UNIQUE, currentConsumption REAL NOT NULL DEFAULT 0.0, currentImpulses INTEGER NOT NULL DEFAULT 0)');
      print("Table 'kits' assurée (onUpgrade <2).");
      await db.execute('CREATE TABLE IF NOT EXISTS relays (id INTEGER PRIMARY KEY AUTOINCREMENT, identificateur TEXT NOT NULL UNIQUE, name TEXT NOT NULL, amperage REAL NOT NULL, state INTEGER NOT NULL DEFAULT 0, isDefaultRelay INTEGER NOT NULL DEFAULT 0, test TEXT)');
      print("Table 'relays' (v1 structure) assurée (onUpgrade <2).");
    }
    if (oldVersion < 3) { 
       await db.execute('CREATE TABLE IF NOT EXISTS consumption_history (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, consumption REAL NOT NULL, impulses INTEGER NOT NULL)');
      print("Table 'consumption_history' (globale) assurée (onUpgrade <3).");
    }
    if (oldVersion < 4) {
      try {
        var tableInfo = await db.rawQuery('PRAGMA table_info(relays)');
        bool columnExists = tableInfo.any((column) => column['name'] == 'currentRelayConsumption');
        if (!columnExists) {
            await db.execute("ALTER TABLE relays ADD COLUMN currentRelayConsumption REAL NOT NULL DEFAULT 0.0;");
            print("Colonne 'currentRelayConsumption' ajoutée à 'relays'.");
        } else { print("Colonne 'currentRelayConsumption' existe déjà dans 'relays'."); }
      } catch (e) { print("Erreur ajout colonne currentRelayConsumption: $e"); }
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS relay_consumption_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT, relayIdentificateur TEXT NOT NULL,
          timestamp TEXT NOT NULL, consumption REAL NOT NULL
        )
      ''');
      print("Table 'relay_consumption_history' assurée (onUpgrade <4).");
    }
  }

  Future<void> _insertDefaultAdmin(Database db) async {
    List<Map<String, dynamic>> existingAdmins = await db.query('users', where: 'phoneNumber = ? AND isAdmin = ?', whereArgs: ['000000000', 1]);
    if (existingAdmins.isEmpty) {
      final adminUser = User(phoneNumber: '000000000', userId: '0', isAdmin: true);
      await db.insert('users', adminUser.toMap());
      print("Utilisateur administrateur par défaut inséré.");
    } else {
      print("Utilisateur administrateur par défaut existe déjà.");
    }
  }

  Future<User?> getUserByCredentials(String phoneNumber, String userId) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'phoneNumber = ? AND userId = ?',
      whereArgs: [phoneNumber, userId],
      limit: 1,
    );
    if (maps.isNotEmpty) return User.fromMap(maps.first);
    return null;
  }
  
  Future<int> setOrUpdateStandardUser(String newPhoneNumber, String newUserId) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> adminCheck = await db.query('users', where: 'phoneNumber = ? AND isAdmin = ?', whereArgs: [newPhoneNumber, 1]);
    if (adminCheck.isNotEmpty) {
      throw Exception('Ce numéro de téléphone est déjà utilisé par l\'administrateur.');
    }
    List<Map<String, dynamic>> standardUsers = await db.query('users', where: 'isAdmin = ?', whereArgs: [0]);
    User userToProcess = User(phoneNumber: newPhoneNumber, userId: newUserId, isAdmin: false);

    if (standardUsers.isEmpty) {
      print("Insertion du nouvel utilisateur standard: $newPhoneNumber / $newUserId");
      int id = await db.insert('users', userToProcess.toMap());
      if (id <=0) throw Exception("Échec de l'insertion du nouvel utilisateur standard.");
      return id;
    } else {
      int existingStandardUserId = User.fromMap(standardUsers.first).id!;
      print("Mise à jour de l'utilisateur standard existant (ID: $existingStandardUserId) avec $newPhoneNumber / $newUserId");
      Map<String, dynamic> updateData = userToProcess.toMapForUpdate(); // Utilise la méthode toMapForUpdate du modèle User
      int count = await db.update('users', updateData, where: 'id = ? AND isAdmin = ?', whereArgs: [existingStandardUserId, 0]);
      if (count == 0) throw Exception("Échec de la mise à jour de l'utilisateur standard.");
      return existingStandardUserId; 
    }
  }

  Future<User?> getStandardUser() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('users', where: 'isAdmin = ?', whereArgs: [0], limit: 1);
    if (maps.isNotEmpty) return User.fromMap(maps.first);
    return null;
  }

  Future<int> insertOrReplaceKit(Kit kit) async {
    final db = await instance.database;
    await db.delete('kits'); 
    int id = await db.insert('kits', kit.toMap()); 
    print("Kit inséré/remplacé avec id: $id, numéro: ${kit.kitNumber}");
    if (id > 0) {
      await _insertDefaultRelaysForKit(db);
    }
    return id;
  }

  Future<Kit?> getKit() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('kits', limit: 1);
    if (maps.isNotEmpty) return Kit.fromMap(maps.first);
    return null;
  }

  Future<int> updateKit(Kit kit) async {
    final db = await instance.database;
    if (kit.id != null) {
        return await db.update('kits', kit.toMap(), where: 'id = ?', whereArgs: [kit.id]);
    } else {
        // Si l'ID n'est pas connu (ne devrait pas arriver pour un kit existant chargé de la DB),
        // on pourrait se baser sur kitNumber, mais c'est moins sûr si kitNumber peut changer.
        // Privilégier la mise à jour par ID.
        print("AVERTISSEMENT: Tentative de mise à jour du kit sans ID. Mise à jour basée sur kitNumber.");
        return await db.update('kits', kit.toMap(), where: 'kitNumber = ?', whereArgs: [kit.kitNumber]);
    }
  }

  Future<void> _insertDefaultRelaysForKit(Database db) async {
    final List<Map<String, dynamic>> existingDefaultRelays = await db.query('relays', where: 'isDefaultRelay = ?', whereArgs: [1]);
    
    // S'assurer qu'on n'insère pas plus de 4 relais par défaut au total.
    // Et pour chaque relais par défaut, vérifier s'il existe par son identificateur avant d'insérer.
    if (existingDefaultRelays.length >= 4 && existingDefaultRelays.every((r) => Relay.fromMap(r).identificateur.startsWith("REL"))) {
      print("Les 4 Relais par défaut semblent déjà présents, pas de réinsertion globale.");
      // On pourrait quand même vérifier s'il manque un spécifique des 4 et l'ajouter.
      // Pour l'instant, cette logique suffit si on part d'une DB propre.
    }
    
    print("Vérification/Insertion des relais par défaut...");
    final defaultRelaysData = [
      Relay(identificateur: "REL1", name: "Relais 1", amperage: 10.0, isDefaultRelay: true, currentRelayConsumption: 0.0, test: "d1"),
      Relay(identificateur: "REL2", name: "Relais 2", amperage: 10.0, isDefaultRelay: true, currentRelayConsumption: 0.0, test: "d2"),
      Relay(identificateur: "REL3", name: "Relais 3", amperage: 5.0, isDefaultRelay: true, currentRelayConsumption: 0.0, test: "d3"),
      Relay(identificateur: "REL4", name: "Relais 4", amperage: 5.0, isDefaultRelay: true, currentRelayConsumption: 0.0, test: "d4"),
    ];

    for (var relay in defaultRelaysData) {
      final existingByIdentifier = await db.query('relays', where: 'identificateur = ?', whereArgs: [relay.identificateur]);
      if (existingByIdentifier.isEmpty) {
          await db.insert('relays', relay.toMap());
          print("Relais par défaut '${relay.identificateur}' inséré.");
      } else {
          print("Relais par défaut '${relay.identificateur}' existe déjà.");
      }
    }
  }

  Future<int> insertRelay(Relay relay) async {
    final db = await instance.database;
    Map<String, dynamic> relayMap = relay.toMap();
    relayMap['currentRelayConsumption'] ??= 0.0; // Assurer une valeur par défaut
    relayMap['isDefaultRelay'] ??= 0; // Assurer une valeur par défaut pour les relais non-par-défaut
    return await db.insert('relays', relayMap);
  }

  Future<List<Relay>> getRelays() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('relays', orderBy: 'identificateur ASC');
    return List.generate(maps.length, (i) { return Relay.fromMap(maps[i]); });
  }
  
  Future<Relay?> getRelayByIdentifier(String identifier) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('relays', where: 'identificateur = ?', whereArgs: [identifier], limit: 1);
    if (maps.isNotEmpty) return Relay.fromMap(maps.first);
    return null;
  }

  Future<int> updateRelay(Relay relay) async {
    final db = await instance.database;
    return await db.update('relays', relay.toMap(), where: 'id = ?', whereArgs: [relay.id]);
  }

  Future<int> deleteRelay(int relayId) async {
    final db = await instance.database;
    return await db.delete('relays', where: 'id = ?', whereArgs: [relayId]);
  }

  Future<int> insertConsumptionDataPoint(ConsumptionDataPoint dataPoint) async {
    final db = await instance.database;
    return await db.insert('consumption_history', dataPoint.toMap());
  }

  Future<List<ConsumptionDataPoint>> getConsumptionHistory({int? limit = 30, DateTime? since}) async {
    final db = await instance.database;
    String? whereClause;
    List<dynamic>? whereArgs;
    if (since != null) {
        whereClause = 'timestamp >= ?';
        whereArgs = [since.toIso8601String()];
    }
    final List<Map<String, dynamic>> maps = await db.query('consumption_history', orderBy: 'timestamp ASC', limit: limit, where: whereClause, whereArgs: whereArgs);
    return List.generate(maps.length, (i) { return ConsumptionDataPoint.fromMap(maps[i]); });
  }

   Future<void> clearConsumptionHistory() async {
    final db = await instance.database;
    await db.delete('consumption_history');
    print("Historique de consommation globale vidé.");
  }

  Future<int> insertRelayConsumptionDataPoint(RelayConsumptionDataPoint dataPoint) async {
    final db = await instance.database;
    return await db.insert('relay_consumption_history', dataPoint.toMap());
  }

  Future<List<RelayConsumptionDataPoint>> getRelayConsumptionHistory(String relayIdentifier, {int? limit = 30, DateTime? since}) async {
    final db = await instance.database;
    String whereClause = 'relayIdentificateur = ?';
    List<dynamic> whereArgs = [relayIdentifier];
    if (since != null) {
        whereClause += ' AND timestamp >= ?';
        whereArgs.add(since.toIso8601String());
    }
    final List<Map<String, dynamic>> maps = await db.query('relay_consumption_history', where: whereClause, whereArgs: whereArgs, orderBy: 'timestamp ASC', limit: limit);
    return List.generate(maps.length, (i) { return RelayConsumptionDataPoint.fromMap(maps[i]); });
  }

   Future<void> clearRelayConsumptionHistory(String relayIdentifier) async {
    final db = await instance.database;
    await db.delete('relay_consumption_history', where: 'relayIdentificateur = ?', whereArgs: [relayIdentifier]);
    print("Historique de consommation vidé pour le relais $relayIdentifier.");
  }

   Future<void> clearAllRelayConsumptionHistories() async {
    final db = await instance.database;
    await db.delete('relay_consumption_history');
    print("Tous les historiques de consommation des relais ont été vidés.");
  }
}