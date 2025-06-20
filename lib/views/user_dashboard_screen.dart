// lib/views/user_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart';
import 'package:enmkit_fresh_start/services/sms_service.dart';
import 'package:provider/provider.dart';
import 'package:enmkit_fresh_start/views/relay_consumption_history_screen.dart'; 

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  _UserDashboardScreenState createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  Kit? _currentKit;
  bool _isLoadingKit = true;

  List<Relay> _relaysList = [];
  bool _isLoadingRelays = true;

  SmsService? _smsServiceInstance;

  @override
  void initState() {
    super.initState();
    print("UserDashboard: initState - Appel de _loadInitialDataAndInitializeServices");
    _loadInitialDataAndInitializeServices();
  }

  Future<void> _loadInitialDataAndInitializeServices() async {
    print("UserDashboard: _loadInitialDataAndInitializeServices - DÉBUT");
    await _loadKitInfo(); 
    if (mounted && context.mounted) {
      _smsServiceInstance = Provider.of<SmsService>(context, listen: false);
      print("UserDashboard: _loadInitialDataAndInitializeServices - SmsService instance obtained: ${_smsServiceInstance != null}");
      await _initializeSmsRelatedLogic(); 
    } else {
      print("UserDashboard: _loadInitialDataAndInitializeServices - Widget non monté ou context non monté après _loadKitInfo. Fin.");
    }
    print("UserDashboard: _loadInitialDataAndInitializeServices - FIN");
  }
  
  Future<void> _initializeSmsRelatedLogic() async {
    print("UserDashboard: _initializeSmsRelatedLogic - DÉBUT");
    if (!mounted || _smsServiceInstance == null) {
      print("UserDashboard: _initializeSmsRelatedLogic - Abandon: mounted=$mounted, smsService is null? ${_smsServiceInstance == null}");
      return;
    }

    print("UserDashboard: _initializeSmsRelatedLogic - Appel de initializeKitPhoneNumberForListening");
    await _smsServiceInstance!.initializeKitPhoneNumberForListening();
    print("UserDashboard: _initializeSmsRelatedLogic - Numéro pour écoute SMS Service: ${_smsServiceInstance!.kitPhoneNumberForListening}");
    print("UserDashboard: _initializeSmsRelatedLogic - _currentKit: ${_currentKit?.kitNumber}");


    if (_currentKit != null && _currentKit!.kitNumber.isNotEmpty && 
        _smsServiceInstance!.kitPhoneNumberForListening != null &&  
        _smsServiceInstance!.kitPhoneNumberForListening!.isNotEmpty) { 
      
      print("UserDashboard: _initializeSmsRelatedLogic - Conditions remplies pour démarrer l'écoute et charger les relais.");
      await _loadRelays(); // Mettre await ici pour s'assurer que les relais sont chargés avant de continuer si besoin
      
      _smsServiceInstance!.onKitDataUpdated = () {
        if (mounted) {
          print("UserDashboard: -------- Callback onKitDataUpdated REÇU ! Appel de _loadKitInfo --------");
          _loadKitInfo(); 
        } else {
           print("UserDashboard: -------- Callback onKitDataUpdated REÇU (widget non monté) ! --------");
        }
      };
      
      _smsServiceInstance!.startListeningForMessages();
      // Le log de démarrage de l'écoute est déjà dans SmsService
    } else { 
        print("UserDashboard: _initializeSmsRelatedLogic - Conditions NON remplies pour démarrer l'écoute. Arrêt de l'écoute.");
        _smsServiceInstance!.stopListening();
        if (mounted) {
            print("UserDashboard: _initializeSmsRelatedLogic - setState pour vider les relais (kit non configuré).");
            setState(() {
                _isLoadingRelays = false;
                _relaysList = [];
            });
            if (context.mounted && (_currentKit == null || _currentKit!.kitNumber.isEmpty) && !_isLoadingKit ) { 
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if(context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Le kit n\'est pas encore configuré par un administrateur.')),
                    );
                  }
                });
                print("UserDashboard: _initializeSmsRelatedLogic - SnackBar 'kit non configuré' devrait s'afficher.");
            }
        }
    }
    print("UserDashboard: _initializeSmsRelatedLogic - FIN");
  }

  Future<void> _loadKitInfo() async {
    if (!mounted) { print("UserDashboard: _loadKitInfo - Abandon car widget non monté au début."); return; }
    
    print("UserDashboard: _loadKitInfo - DÉBUT. Avant setState: _isLoadingKit: $_isLoadingKit, _currentKit: ${_currentKit?.kitNumber}");
    
    bool wasInitiallyLoadingPage = _currentKit == null && _isLoadingKit;
    if (wasInitiallyLoadingPage) {
        // setState(() { _isLoadingKit = true; }); // Déjà true par défaut
    }

    try {
      Kit? kitFromDb = await DatabaseHelper.instance.getKit();
      print("UserDashboard: _loadKitInfo - Kit depuis DB: ${kitFromDb?.kitNumber}");
      if (mounted) {
        bool kitNumberChanged = _currentKit?.kitNumber != kitFromDb?.kitNumber;
        bool kitDataItselfChanged = _currentKit?.currentConsumption != kitFromDb?.currentConsumption ||
                                    _currentKit?.currentImpulses != kitFromDb?.currentImpulses;
        bool kitAppearanceChanged = _currentKit == null && kitFromDb != null;
        bool kitDisappearanceChanged = _currentKit != null && kitFromDb == null;

        print("UserDashboard: _loadKitInfo - Détection changements: numChanged: $kitNumberChanged, dataChanged: $kitDataItselfChanged, appeared: $kitAppearanceChanged, disappeared: $kitDisappearanceChanged, wasInitiallyLoadingPage: $wasInitiallyLoadingPage");

        if (kitNumberChanged || kitDataItselfChanged || kitAppearanceChanged || kitDisappearanceChanged || wasInitiallyLoadingPage ) {
           print("UserDashboard: _loadKitInfo - Changement détecté ou premier chargement, APPEL SETSTATE pour _currentKit.");
           setState(() {
            _currentKit = kitFromDb;
            if (wasInitiallyLoadingPage && _currentKit != null) _isLoadingKit = false;
            else if (_currentKit == null) _isLoadingKit = false;
          });
           print("UserDashboard: _loadKitInfo - Après setState, _currentKit: ${_currentKit?.kitNumber}, _isLoadingKit: $_isLoadingKit");
        } else {
            print("UserDashboard: _loadKitInfo - Pas de changement détecté pour _currentKit, pas de setState pour le kit (sauf si _isLoadingKit était true).");
            if (_isLoadingKit) { 
                setState(() { _isLoadingKit = false; });
                 print("UserDashboard: _loadKitInfo - isLoadingKit était true, mis à false.");
            }
        }
        
        if (_smsServiceInstance != null) {
            if (kitNumberChanged || kitAppearanceChanged || kitDisappearanceChanged) {
                print("UserDashboard: _loadKitInfo - Le numéro/statut du Kit a changé, APPEL _initializeSmsRelatedLogic.");
                await _initializeSmsRelatedLogic();
            } else {
                print("UserDashboard: _loadKitInfo - Kit global OK ou callback reçu, APPEL _loadRelays.");
                await _loadRelays();
            }
        } else {
            print("UserDashboard: _loadKitInfo terminé, SmsService pas encore prêt pour _initializeSmsRelatedLogic/loadRelays.");
        }
      } else {
        print("UserDashboard: _loadKitInfo - Widget non monté après récupération de la DB.");
      }
    } catch (e) {
      print("UserDashboard: Erreur dans _loadKitInfo: $e");
      if (mounted) {
        setState(() { _isLoadingKit = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur chargement infos kit: ${e.toString()}")),
        );
      }
    }
    print("UserDashboard: _loadKitInfo - FIN");
  }

  Future<void> _loadRelays() async {
    if (!mounted) { print("UserDashboard: _loadRelays - Abandon car widget non monté."); return; }
    print("UserDashboard: _loadRelays - DÉBUT. _currentKit: ${_currentKit?.kitNumber}");
    if (_currentKit == null || _currentKit!.kitNumber.isEmpty) { 
      if (mounted) {
        print("UserDashboard: _loadRelays - Pas de kit, setState pour vider _relaysList.");
        setState(() { _relaysList = []; _isLoadingRelays = false; });
      }
      return;
    }
    
    if (mounted) {
        if (_relaysList.isEmpty || !_isLoadingRelays) { 
             print("UserDashboard: _loadRelays - Passage de _isLoadingRelays à true.");
            setState(() { _isLoadingRelays = true; });
        }
    }

    try {
      List<Relay> relaysFromDb = await DatabaseHelper.instance.getRelays();
      print("UserDashboard: _loadRelays - Relais récupérés de DB: ${relaysFromDb.length} éléments.");
      if (mounted) {
        print("UserDashboard: _loadRelays - Appel de setState pour _relaysList.");
        setState(() {
          _relaysList = relaysFromDb;
          _isLoadingRelays = false;
        });
        print("UserDashboard: _loadRelays - Après setState, _relaysList.length: ${_relaysList.length}, _isLoadingRelays: $_isLoadingRelays");
      } else {
         print("UserDashboard: _loadRelays - Widget non monté après récupération des relais.");
      }
    } catch (e) {
      print("UserDashboard: Erreur chargement relais: $e");
      if (mounted) {
        setState(() { _isLoadingRelays = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur chargement relais: ${e.toString()}")),
        );
      }
    }
    print("UserDashboard: _loadRelays - FIN");
  }

  Future<void> _toggleRelayState(Relay relay, bool newState) async {
    if (!mounted) return; 
    print("UserDashboard: _toggleRelayState - Relais: ${relay.name}, Nouvel état: $newState");
    if (_currentKit == null || _currentKit!.kitNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kit non configuré.')));
      return;
    }
    if (_smsServiceInstance == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service SMS non disponible.')));
      return;
    }
    String action = newState ? "ON" : "OFF";
    String command = "${action}#${relay.identificateur}";
    
    print("UserDashboard: _toggleRelayState - Avant setState optimiste pour ${relay.name}. État actuel UI: ${relay.state}");
    setState(() {
      relay.state = newState;
      int index = _relaysList.indexWhere((r) => r.id == relay.id);
      if (index != -1) _relaysList[index] = relay;
    });
    Relay? updatedRelayInList = _relaysList.firstWhere((r)=>r.id == relay.id, orElse: () => relay); // Pour le log
    print("UserDashboard: _toggleRelayState - Après setState optimiste pour ${relay.name}. Nouvel état UI: ${updatedRelayInList.state}");
    
    try {
      await _smsServiceInstance!.sendSms(_currentKit!.kitNumber, command);
      await DatabaseHelper.instance.updateRelay(relay); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Commande "$action" envoyée pour ${relay.name}.')));
      }
    } catch (e) {
      print("Erreur envoi SMS ou MàJ DB pour relais (UserDashboard): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur commande relais: ${e.toString()}')));
        print("UserDashboard: _toggleRelayState - ERREUR, rollback UI pour ${relay.name}. Ancien état: ${!newState}");
        setState(() {
          relay.state = !newState; 
          int index = _relaysList.indexWhere((r) => r.id == relay.id);
          if (index != -1) _relaysList[index] = relay;
        });
      }
    }
  }

  @override
  void dispose() {
    print("UserDashboard: dispose - Nettoyage des listeners et arrêt de l'écoute SMS.");
    if (_smsServiceInstance != null) {
      _smsServiceInstance!.onKitDataUpdated = null; 
      _smsServiceInstance!.stopListening(); 
    }
    super.dispose();
  }

  Widget _buildKitInfoCard() {
    print("UserDashboard: _buildKitInfoCard - _isLoadingKit: $_isLoadingKit, _currentKit: ${_currentKit?.kitNumber}");
    if (_isLoadingKit && _currentKit == null) return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
    if (_currentKit == null) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Le kit n'est pas encore configuré par un administrateur.",
            style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Informations de Mon Kit", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _infoRow(Icons.settings_remote_outlined, "Numéro du Kit:", _currentKit!.kitNumber),
            const SizedBox(height: 8),
            _infoRow(Icons.flash_on_outlined, "Conso. Globale Kit:", "${_currentKit!.currentConsumption.toStringAsFixed(2)} kWh"),
            const SizedBox(height: 8),
            _infoRow(Icons.speed_outlined, "Impulsions Globales Kit:", _currentKit!.currentImpulses.toString()),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8))),
        const SizedBox(width: 5),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _buildRelaysListForUser() {
    final theme = Theme.of(context);
    print("UserDashboard: _buildRelaysListForUser - _isLoadingRelays: $_isLoadingRelays, _relaysList.length: ${_relaysList.length}");
    if (_isLoadingRelays) return const Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator()));
    if (_currentKit == null) return Container(); 
    if (_relaysList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text("Aucun relais disponible pour ce kit.", style: TextStyle(fontStyle: FontStyle.italic))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _relaysList.length,
      itemBuilder: (context, index) {
        final relay = _relaysList[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          child: ListTile(
            leading: Icon(
              relay.state ? Icons.power : Icons.power_off,
              color: relay.state ? theme.colorScheme.secondary : Colors.grey[600],
              size: 30,
            ),
            title: Text(relay.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("ID: ${relay.identificateur}"),
                Text("Dernière Conso: ${relay.currentRelayConsumption.toStringAsFixed(2)} kWh"),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.history, color: theme.colorScheme.primary.withOpacity(0.8)),
                  tooltip: 'Voir l\'historique de ${relay.name}',
                  onPressed: () {
                    if (_currentKit == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RelayConsumptionHistoryScreen(
                          relayIdentifier: relay.identificateur,
                          relayName: relay.name,
                        ),
                      ),
                    );
                  },
                ),
                Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: relay.state,
                    onChanged: (bool newValue) {
                      _toggleRelayState(relay, newValue);
                    },
                    activeColor: theme.colorScheme.secondary,
                    inactiveThumbColor: Colors.grey[400],
                    inactiveTrackColor: Colors.grey[700],
                  ),
                ),
              ],
            ),
            isThreeLine: true, 
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print("UserDashboard: build - _isLoadingKit: $_isLoadingKit, _currentKit: ${_currentKit?.kitNumber}, _isLoadingRelays: $_isLoadingRelays, _relaysList.length: ${_relaysList.length}");
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Tableau de Bord EnMKIT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () {
              _smsServiceInstance?.stopListening(); 
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialDataAndInitializeServices, 
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), 
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKitInfoCard(),
              const SizedBox(height: 24),
              const Divider(thickness: 0.5),
              const SizedBox(height: 16),
              Text(
                "Contrôle et Consommation des Relais",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              _buildRelaysListForUser(),
              const SizedBox(height: 30), 
            ],
          ),
        ),
      ),
    );
  }
}