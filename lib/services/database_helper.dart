// lib/services/database_helper.dart

import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart'; // Assurez-vous qu'il contient currentRelayConsumption
import 'package:enmkit_fresh_start/models/user.dart';
import 'package:enmkit_fresh_start/models/relay_consumption_data_point.dart'; // NOUVEL IMPORT
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
}


class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // MISE À JOUR DU NOM DU FICHIER DB POUR LA VERSION 4 (ou gardez le même et laissez onUpgrade faire le travail)
    _database = await _initDB('enmkit_app_v4.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, // <<<< VERSION MISE À JOUR À 4
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
    await _insertTestUser(db); 

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

    // Table relays - MISE À JOUR AVEC currentRelayConsumption
    await db.execute('''
      CREATE TABLE relays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        identificateur TEXT NOT NULL UNIQUE, 
        name TEXT NOT NULL,
        amperage REAL NOT NULL,
        state INTEGER NOT NULL DEFAULT 0,
        isDefaultRelay INTEGER NOT NULL DEFAULT 0,
        currentRelayConsumption REAL NOT NULL DEFAULT 0.0, -- AJOUTÉ
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

    // NOUVELLE TABLE: relay_consumption_history
    await db.execute('''
      CREATE TABLE relay_consumption_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        relayIdentificateur TEXT NOT NULL, 
        timestamp TEXT NOT NULL,
        consumption REAL NOT NULL
        -- Optionnel: FOREIGN KEY (relayIdentificateur) REFERENCES relays(identificateur)
      )
    ''');
    print("Table 'relay_consumption_history' créée.");
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("Mise à jour de la base de données de la v$oldVersion à la v$newVersion...");
    if (oldVersion < 2) { 
      await db.execute('''
        CREATE TABLE IF NOT EXISTS kits (id INTEGER PRIMARY KEY AUTOINCREMENT, kitNumber TEXT NOT NULL UNIQUE, currentConsumption REAL NOT NULL DEFAULT 0.0, currentImpulses INTEGER NOT NULL DEFAULT 0)
      ''');
      print("Table 'kits' assurée (onUpgrade <2).");
      await db.execute('''
        CREATE TABLE IF NOT EXISTS relays (id INTEGER PRIMARY KEY AUTOINCREMENT, identificateur TEXT NOT NULL UNIQUE, name TEXT NOT NULL, amperage REAL NOT NULL, state INTEGER NOT NULL DEFAULT 0, isDefaultRelay INTEGER NOT NULL DEFAULT 0, test TEXT)
      '''); // Ancienne structure de relays
      print("Table 'relays' (ancienne version) assurée (onUpgrade <2).");
    }
    if (oldVersion < 3) { 
       await db.execute('''
        CREATE TABLE IF NOT EXISTS consumption_history (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, consumption REAL NOT NULL, impulses INTEGER NOT NULL)
      ''');
      print("Table 'consumption_history' (globale) assurée (onUpgrade <3).");
    }
    
    if (oldVersion < 4) {
      // Migration vers v4: ajouter currentRelayConsumption à relays et créer relay_consumption_history
      try {
        var tableInfo = await db.rawQuery('PRAGMA table_info(relays)');
        bool columnExists = tableInfo.any((column) => column['name'] == 'currentRelayConsumption');
        if (!columnExists) {
            await db.execute("ALTER TABLE relays ADD COLUMN currentRelayConsumption REAL NOT NULL DEFAULT 0.0;");
            print("Colonne 'currentRelayConsumption' ajoutée à la table 'relays'.");
        } else {
            print("Colonne 'currentRelayConsumption' existe déjà dans 'relays'.");
        }
      } catch (e) {
        print("Erreur lors de l'ajout de la colonne currentRelayConsumption (peut-être déjà existante): $e");
      }
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS relay_consumption_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          relayIdentificateur TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          consumption REAL NOT NULL
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

  Future<void> _insertTestUser(Database db) async {
    final testUser = User(phoneNumber: '123123123', userId: 'user', isAdmin: false);
    List<Map<String, dynamic>> existingTestUser = await db.query('users', where: 'phoneNumber = ? AND userId = ?', whereArgs: [testUser.phoneNumber, testUser.userId]);
    if (existingTestUser.isEmpty) {
        await db.insert('users', testUser.toMap());
        print("Utilisateur de test '${testUser.phoneNumber}'/'${testUser.userId}' inséré.");
    } else {
        print("Utilisateur de test '${testUser.phoneNumber}'/'${testUser.userId}' existe déjà.");
    }
  }

  Future<User?> getUserByCredentials(String phoneNumber, String userId) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query('users', where: 'phoneNumber = ? AND userId = ?', whereArgs: [phoneNumber, userId], limit: 1);
    if (maps.isNotEmpty) return User.fromMap(maps.first);
    return null;
  }
  
  Future<int> addNewUserByAdmin(User user) async {
    final db = await instance.database;
    List<Map<String, dynamic>> existingUserByPhone = await db.query('users', where: 'phoneNumber = ?', whereArgs: [user.phoneNumber], limit: 1);
    if (existingUserByPhone.isNotEmpty) {
      throw Exception('Ce numéro de téléphone est déjà utilisé.');
    }
    User userToInsert = User(phoneNumber: user.phoneNumber, userId: user.userId, isAdmin: false );
    int id = await db.insert('users', userToInsert.toMap());
    if (id <= 0) {
      throw Exception("Échec de l'insertion du nouvel utilisateur en base de données.");
    }
    print("Nouvel utilisateur ${user.phoneNumber} inséré par admin avec id: $id");
    return id;
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
        print("Mise à jour du kit basée sur kitNumber car ID est null.");
        return await db.update('kits', kit.toMap(), where: 'kitNumber = ?', whereArgs: [kit.kitNumber]);
    }
  }

  Future<void> _insertDefaultRelaysForKit(Database db) async {
    final List<Map<String, dynamic>> existingDefaultRelays = await db.query('relays', where: 'isDefaultRelay = ?', whereArgs: [1], limit: 4);
    
    if (existingDefaultRelays.length >= 4) {
      print("Les 4 Relais par défaut déjà présents, pas de réinsertion.");
      return; 
    }
    
    print("Insertion des relais par défaut (ou des manquants)...");
    final defaultRelaysData = [
      Relay(identificateur: "REL1", name: "Relais 1", amperage: 10.0, isDefaultRelay: true, test: "d1", currentRelayConsumption: 0.0),
      Relay(identificateur: "REL2", name: "Relais 2", amperage: 10.0, isDefaultRelay: true, test: "d2", currentRelayConsumption: 0.0),
      Relay(identificateur: "REL3", name: "Relais 3", amperage: 5.0, isDefaultRelay: true, test: "d3", currentRelayConsumption: 0.0),
      Relay(identificateur: "REL4", name: "Relais 4", amperage: 5.0, isDefaultRelay: true, test: "d4", currentRelayConsumption: 0.0),
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
    // S'assurer que currentRelayConsumption a une valeur par défaut si non fournie
    Map<String, dynamic> relayMap = relay.toMap();
    relayMap['currentRelayConsumption'] ??= 0.0;
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

    final List<Map<String, dynamic>> maps = await db.query(
      'consumption_history',
      orderBy: 'timestamp ASC', 
      limit: limit,
      where: whereClause,
      whereArgs: whereArgs,
    );
    return List.generate(maps.length, (i) { 
      return ConsumptionDataPoint.fromMap(maps[i]);
    });
  }

   Future<void> clearConsumptionHistory() async {
    final db = await instance.database;
    await db.delete('consumption_history');
    print("Historique de consommation vidé.");
  }

  // NOUVELLES MÉTHODES POUR L'HISTORIQUE DE CONSOMMATION PAR RELAIS
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

    final List<Map<String, dynamic>> maps = await db.query(
      'relay_consumption_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC', 
      limit: limit,
    );
    return List.generate(maps.length, (i) { 
      return RelayConsumptionDataPoint.fromMap(maps[i]);
    });
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