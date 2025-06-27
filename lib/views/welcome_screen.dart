// lib/views/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Définissez ici le contenu de vos slides
  final List<Map<String, String>> _slideData = [
    {
      "title": "Bienvenue sur EnMKIT",
      "description": "Votre solution intelligente pour la gestion et le contrôle de votre kit électrique à distance.",
      // "image": "assets/images/welcome_slide_1.png", // Exemple de chemin d'image
    },
    {
      "title": "Contrôle Facile des Relais",
      "description": "Allumez et éteignez vos appareils connectés en un clic, où que vous soyez, via SMS.",
      // "image": "assets/images/welcome_slide_2.png",
    },
    {
      "title": "Suivi de Consommation",
      "description": "Recevez des informations sur la consommation globale de votre kit et de chaque relais.",
      // "image": "assets/images/welcome_slide_3.png",
    },
    {
      "title": "Prêt à Commencer ?",
      "description": "Configurez votre kit et commencez à gérer votre installation dès maintenant !",
      // "image": "assets/images/welcome_slide_4.png",
    }
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    if (mounted) {
      setState(() {
        _currentPage = page;
      });
    }
  }

  Future<void> _finishWelcomeAndNavigate() async {
    if (!mounted) return;
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenWelcomeScreen', true);
      print("WelcomeScreen: 'hasSeenWelcomeScreen' mis à true.");
      if (mounted) { // Double vérification car l'await peut prendre du temps
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print("Erreur lors de la sauvegarde de SharedPreferences: $e");
      // Même en cas d'erreur, naviguer pour ne pas bloquer l'utilisateur
      if (mounted) {
         Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  List<Widget> _buildPageIndicator() {
    List<Widget> list = [];
    for (int i = 0; i < _slideData.length; i++) {
      list.add(i == _currentPage ? _indicator(true) : _indicator(false));
    }
    return list;
  }

  Widget _indicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 6.0),
      height: isActive ? 12.0 : 8.0,
      width: isActive ? 12.0 : 8.0,
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Bouton "Passer" en haut à droite, sauf sur la dernière slide
            Container(
              height: 50, // Hauteur fixe pour le bouton ou l'espace vide
              alignment: Alignment.centerRight,
              child: _currentPage != _slideData.length - 1
                  ? Padding(
                      padding: const EdgeInsets.only(right: 16.0, top:8.0),
                      child: TextButton(
                        onPressed: _finishWelcomeAndNavigate,
                        child: Text(
                          'Passer',
                          style: TextStyle(color: theme.colorScheme.secondary, fontSize: 16),
                        ),
                      ),
                    )
                  : null, // Pas de bouton "Passer" sur la dernière slide
            ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _slideData.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        // Placeholder pour l'image - remplacez par Image.asset si vous en avez
                        Icon(
                          index == 0 ? Icons.home_work_outlined : 
                          index == 1 ? Icons.settings_remote_outlined : 
                          index == 2 ? Icons.bar_chart_outlined :
                          Icons.rocket_launch_outlined,
                          size: 120, 
                          color: theme.colorScheme.secondary.withOpacity(0.8)
                        ),
                        const SizedBox(height: 50),
                        Text(
                          _slideData[index]['title']!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _slideData[index]['description']!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                            height: 1.5, // Interligne
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicateurs et boutons Suivant/Terminé
            Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 40.0, top: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: _buildPageIndicator(),
                  ),
                  _currentPage == _slideData.length - 1
                      ? ElevatedButton(
                          onPressed: _finishWelcomeAndNavigate,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('Commencer', style: TextStyle(fontSize: 16)),
                        )
                      : TextButton(
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.ease,
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Suivant',
                                style: TextStyle(fontSize: 16, color: theme.colorScheme.secondary),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.secondary),
                            ],
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}