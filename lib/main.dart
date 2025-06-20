// lib/main.dart
import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart'; 
import 'package:enmkit_fresh_start/views/login_screen.dart';
import 'package:enmkit_fresh_start/views/admin_dashboard_screen.dart';
import 'package:enmkit_fresh_start/views/user_dashboard_screen.dart';


import 'package:provider/provider.dart'; // DÉCOMMENTEZ CET IMPORT
import 'package:enmkit_fresh_start/services/sms_service.dart'; // DÉCOMMENTEZ CET IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print("--- DÉBUT DE LA FONCTION main() ---");

  print("Initialisation de DatabaseHelper...");
  final dbHelper = DatabaseHelper.instance;
  try {
    await dbHelper.database; 
    print("DatabaseHelper initialisé avec succès dans main().");
  } catch (e) {
    print("ERREUR lors de l'initialisation de DatabaseHelper: $e");
  }

  print("Initialisation de SmsService...");
  final smsService = SmsService(); // DÉCOMMENTEZ ET CRÉEZ L'INSTANCE

  print("Appel de runApp() avec MyApp originale et Provider...");
  runApp(
    ChangeNotifierProvider<SmsService>( // ENGLOBEZ MyApp AVEC LE PROVIDER
      create: (_) => smsService,
      child: const MyApp(), 
    )
  );
}

// VOTRE CLASSE MyApp ORIGINALE RESTE LA MÊME
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print("--- MyApp build() appelé ---");
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
      initialRoute: '/login', 
      routes: {
        '/login': (context) => const LoginScreen(), 
        '/admin_dashboard': (context) => const AdminDashboardScreen(), 
        '/user_dashboard': (context) => const UserDashboardScreen(),
        '/consumtion_history': (context) => const UserDashboardScreen(), // J'ai corrigé le nom de la route ici aussi  
      },
    );
  }
}