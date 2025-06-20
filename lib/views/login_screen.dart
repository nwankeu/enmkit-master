// lib/views/login_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart';
import 'package:enmkit_fresh_start/models/user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      String phoneNumber = _phoneNumberController.text;
      String userId = _userIdController.text;

      try {
        User? user = await DatabaseHelper.instance.getUserByCredentials(phoneNumber, userId);

        if (user != null) {
          if (mounted) { 
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connexion réussie ! Bienvenue ${user.isAdmin ? "Admin" : "Utilisateur"}.')),
            );
            
            // ----- CORRECTION ICI -----
            if (user.isAdmin) {
              Navigator.pushReplacementNamed(context, '/admin_dashboard'); 
            } else {
              Navigator.pushReplacementNamed(context, '/user_dashboard'); // UTILISER LA BONNE ROUTE
            }
            // ----- FIN CORRECTION -----

            print("Utilisateur connecté: ${user.toString()}");
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Numéro de téléphone ou ID utilisateur incorrect.')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur de connexion: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _phoneNumberController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center( 
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.power_settings_new, 
                  size: 80,
                  color: theme.colorScheme.secondary, 
                ),
                const SizedBox(height: 20),
                Text(
                  'Bienvenue sur EnMKIT',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous pour contrôler votre kit',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _phoneNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre numéro de téléphone';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _userIdController,
                  decoration: const InputDecoration(
                    labelText: 'ID Utilisateur',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true, 
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer votre ID utilisateur';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Se connecter'),
                        onPressed: _login,
                        style: theme.elevatedButtonTheme.style?.copyWith(
                          padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 15)),
                        )
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}