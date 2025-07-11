// lib/main.dart
import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart'; 
import 'package:enmkit_fresh_start/views/login_screen.dart';
import 'package:enmkit_fresh_start/views/admin_dashboard_screen.dart';
import 'package:enmkit_fresh_start/views/user_dashboard_screen.dart';
import 'package:enmkit_fresh_start/views/welcome_screen.dart'; // IMPORT POUR WELCOME SCREEN
// Import pour RelayConsumptionHistoryScreen si vous définissez une route nommée, sinon pas nécessaire ici
// import 'package:enmkit_fresh_start/views/relay_consumption_history_screen.dart'; 

import 'package:provider/provider.dart'; 
import 'package:enmkit_fresh_start/services/sms_service.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; // IMPORT POUR SHARED_PREFERENCES

// Variable globale pour stocker l'état de l'écran de bienvenue
// Elle sera initialisée dans main() avant runApp()
bool _initialHasSeenWelcomeScreen = false;

Future<void> main() async { // main() doit être async pour await SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();
  
  print("--- DÉBUT DE LA FONCTION main() ---");

  // Vérifier si l'écran de bienvenue a déjà été vu
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Lire la valeur. Si elle n'existe pas (premier lancement), ?? false sera utilisé.
    _initialHasSeenWelcomeScreen = prefs.getBool('hasSeenWelcomeScreen') ?? false;
    print("Main: 'hasSeenWelcomeScreen' lu: $_initialHasSeenWelcomeScreen");
  } catch (e) {
    print("Erreur lors de la lecture de SharedPreferences dans main: $e");
    _initialHasSeenWelcomeScreen = false; // Afficher WelcomeScreen par défaut en cas d'erreur
  }

  print("Initialisation de DatabaseHelper...");
  final dbHelper = DatabaseHelper.instance;
  try {
    await dbHelper.database; 
    print("DatabaseHelper initialisé avec succès dans main().");
  } catch (e) {
    print("ERREUR lors de l'initialisation de DatabaseHelper: $e");
  }

  print("Initialisation de SmsService...");
  final smsService = SmsService(); 

  print("Appel de runApp() avec MyApp et Provider...");
  runApp(
    ChangeNotifierProvider<SmsService>( 
      create: (_) => smsService,
      child: const MyApp(), // MyApp n'a plus besoin de hasSeenWelcome en paramètre
    )
  );
}

class MyApp extends StatelessWidget {
  // const MyApp({super.key, required this.hasSeenWelcome}); // Ancien constructeur
  const MyApp({super.key}); // Nouveau constructeur

  @override
  Widget build(BuildContext context) {
    print("--- MyApp build() appelé --- _initialHasSeenWelcomeScreen: $_initialHasSeenWelcomeScreen");
    return MaterialApp(
      title: 'EnMKIT Control',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData( 
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Colors.blueGrey[700]!, 
          onPrimary: Colors.white,          
          secondary: Colors.cyanAccent,     
          onSecondary: Colors.black,        
          surface: Colors.grey[800]!,       
          onSurface: Colors.white,          
          background: Colors.grey[850]!,    
          onBackground: Colors.white,       
          error: Colors.redAccent[200]!,
          onError: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.grey[850], 
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          elevation: 4,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          color: Colors.grey[800], 
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent, 
            foregroundColor: Colors.black,    
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[700],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white54),
        ),
        useMaterial3: true,
      ),
      // Définir la route initiale en fonction de la variable globale lue dans main()
      initialRoute: _initialHasSeenWelcomeScreen ? '/login' : '/welcome', 
      routes: {
        '/welcome': (context) => const WelcomeScreen(), // NOUVELLE ROUTE
        '/login': (context) => const LoginScreen(), 
        '/admin_dashboard': (context) => const AdminDashboardScreen(), 
        '/user_dashboard': (context) => const UserDashboardScreen(),
        // La route pour RelayConsumptionHistoryScreen n'est pas nécessaire ici
        // si la navigation se fait par MaterialPageRoute.
      },
    );
  }
}