// lib/views/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart';
import 'package:enmkit_fresh_start/models/user.dart'; 
import 'package:enmkit_fresh_start/services/database_helper.dart'; // Contient ConsumptionDataPoint
import 'package:enmkit_fresh_start/services/sms_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; 
import 'package:fl_chart/fl_chart.dart'; 

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Kit? _currentKit;
  bool _isLoadingKit = true;
  
  final TextEditingController _kitNumberController = TextEditingController();
  final _formKeyKitDialog = GlobalKey<FormState>();

  List<Relay> _relaysList = [];
  bool _isLoadingRelays = true;
  final TextEditingController _relayNameController = TextEditingController();
  final TextEditingController _relayAmperageController = TextEditingController();
  final _formKeyRelayDialog = GlobalKey<FormState>();

  SmsService? _smsServiceInstance;

  List<ConsumptionDataPoint> _rawConsumptionHistoryData = [];
  List<FlSpot> _consumptionSpots = [const FlSpot(0,0)]; 
  bool _isLoadingHistory = true; 
  double _chartMinY = 0;
  double _chartMaxY = 10;

  // Contrôleurs pour le dialogue d'ajout d'utilisateur (maintenant pour l'utilisateur standard unique)
  final TextEditingController _standardUserNumberController = TextEditingController();
  final TextEditingController _standardUserIdController = TextEditingController();
  User? _standardUser; // Pour stocker l'utilisateur standard configuré
  bool _isLoadingStandardUser = true; // État de chargement pour l'utilisateur standard


  @override
  void initState() {
    super.initState();
    _loadInitialDataAndInitializeServices();
  }
  
  Future<void> _loadInitialDataAndInitializeServices() async {
    await _loadKitInfo(); 
    await _loadStandardUserInfo(); // Charger l'utilisateur standard

    if (mounted && context.mounted) {
      _smsServiceInstance = Provider.of<SmsService>(context, listen: false);
      print("AdminDashboard: SmsService instance obtained.");
      await _initializeSmsRelatedLogic(); 
    }
    if (_currentKit == null && !_isLoadingKit && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showKitConfigurationDialog(); 
      });
    }
  }
  
  Future<void> _initializeSmsRelatedLogic() async {
    if (!mounted || _smsServiceInstance == null) {
      print("AdminDashboard: Cannot initialize SMS logic, service instance is null or widget not mounted.");
      return;
    }
    
    await _smsServiceInstance!.initializeKitPhoneNumberForListening();

    if (_currentKit != null && _currentKit!.kitNumber.isNotEmpty && 
        _smsServiceInstance!.kitPhoneNumberForListening != null &&  
        _smsServiceInstance!.kitPhoneNumberForListening!.isNotEmpty) { 
      
      _loadRelays();
      _loadConsumptionHistory(); 

      _smsServiceInstance!.onKitDataUpdated = () { 
        if (mounted) {
          print("AdminDashboard: Callback onKitDataUpdated reçu, rechargement des données...");
          _loadKitInfo(); 
        }
      };
      
      _smsServiceInstance!.startListeningForMessages();
      print("AdminDashboard: SmsService, listeners et ÉCOUTE SMS configurés pour le kit ${_currentKit!.kitNumber}.");
    } else { 
      _smsServiceInstance!.stopListening();
      if (mounted) {
        setState(() {
          _isLoadingRelays = false; _relaysList = [];
          _isLoadingHistory = false; _consumptionSpots = [const FlSpot(0,0)]; _rawConsumptionHistoryData = [];
        });
        print("AdminDashboard: Pas de kit configuré ou numéro manquant dans SmsService, écoute SMS arrêtée.");
      }
    }
  }

  Future<void> _loadKitInfo() async {
    if (!mounted) return;
     if (_currentKit == null && !_isLoadingKit ) {
        // Ne rien faire, le dialogue de config sera affiché via _loadInitialDataAndInitializeServices
     } else if (_currentKit == null) { // Premier chargement
        setState(() { _isLoadingKit = true; });
     }

    try {
      Kit? kitFromDb = await DatabaseHelper.instance.getKit();
      if (mounted) {
        bool kitNumberMightHaveChanged = (_currentKit?.kitNumber != kitFromDb?.kitNumber) ||
                                       (_currentKit == null && kitFromDb != null) ||
                                       (_currentKit != null && kitFromDb == null) ;
        bool kitDataMightHaveChanged = _currentKit?.currentConsumption != kitFromDb?.currentConsumption ||
                                       _currentKit?.currentImpulses != kitFromDb?.currentImpulses;

        if (kitNumberMightHaveChanged || kitDataMightHaveChanged || (_isLoadingKit && _currentKit == null) ) {
            setState(() {
              _currentKit = kitFromDb;
              if (_currentKit != null) {
                _kitNumberController.text = _currentKit!.kitNumber;
              } else {
                _kitNumberController.clear();
              }
              if (_isLoadingKit) _isLoadingKit = false;
            });
        } else if (_isLoadingKit) { 
            setState(() { _isLoadingKit = false; });
        }
        
        if (kitNumberMightHaveChanged && _smsServiceInstance != null) {
             print("AdminDashboard: Le statut/numéro du Kit a changé, réinitialisation de la logique SMS.");
            await _initializeSmsRelatedLogic();
        } else if ((kitDataMightHaveChanged || !kitNumberMightHaveChanged) && _smsServiceInstance != null && _currentKit != null) {
            print("AdminDashboard: Kit global potentiellement mis à jour ou callback reçu, rechargement des relais et de l'historique.");
            await _loadRelays();
            await _loadConsumptionHistory();
        }
      }
    } catch (e) { 
      print("Erreur chargement infos kit (Admin): $e");
      if (mounted) {
        setState(() { _isLoadingKit = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur chargement infos kit: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _showKitConfigurationDialog() async {
    final bool isEditingKit = _currentKit != null && _currentKit!.kitNumber.isNotEmpty;
    if (isEditingKit) _kitNumberController.text = _currentKit!.kitNumber;
    else _kitNumberController.clear();

    return showDialog<void>(
      context: context, 
      barrierDismissible: isEditingKit,
      builder: (BuildContext dialogContext) { 
        bool _isSavingInDialog = false; 
        return StatefulBuilder(
          builder: (BuildContext sbfDialogContext, StateSetter setDialogStateInDialog) { 
            return AlertDialog(
              title: Text(isEditingKit ? 'Modifier le Numéro du Kit' : 'Configurer le Kit EnMKIT'),
              content: Form(
                key: _formKeyKitDialog, 
                child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  TextFormField(
                    controller: _kitNumberController,
                    decoration: const InputDecoration(labelText: 'Numéro de téléphone de la SIM du Kit', prefixIcon: Icon(Icons.phone_iphone), border: OutlineInputBorder(), hintText: 'Ex: 0612345678'),
                    keyboardType: TextInputType.phone,
                    validator: (value) { if (value == null || value.trim().isEmpty) return 'Veuillez entrer le numéro de téléphone du kit.'; if (!RegExp(r'^[0-9+]+$').hasMatch(value.trim()) || value.trim().length < 9) return 'Veuillez entrer un numéro de téléphone valide.'; return null; },
                  ),
                ]))
              ),
              actions: <Widget>[
                if (isEditingKit) TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(dialogContext).pop()),
                ElevatedButton(
                  child: _isSavingInDialog ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(sbfDialogContext).colorScheme.onPrimary)) : Text(isEditingKit ? 'Mettre à jour' : 'Enregistrer'),
                  onPressed: _isSavingInDialog ? null : () async {
                    if (_formKeyKitDialog.currentState!.validate()) {
                      setDialogStateInDialog(() => _isSavingInDialog = true );
                      String kitNumber = _kitNumberController.text.trim();
                      Kit kitToSave = isEditingKit 
                                      ? Kit(id: _currentKit!.id, kitNumber: kitNumber, currentConsumption: _currentKit!.currentConsumption, currentImpulses: _currentKit!.currentImpulses) 
                                      : Kit(kitNumber: kitNumber);
                      String successMessage = isEditingKit ? 'Numéro du kit mis à jour !' : 'Kit configuré ! Relais par défaut créés.';
                      try {
                        await DatabaseHelper.instance.insertOrReplaceKit(kitToSave);
                        Navigator.of(dialogContext).pop(); 
                        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage))); await _loadKitInfo(); }
                      } catch (e) {
                        if (sbfDialogContext.mounted) ScaffoldMessenger.of(sbfDialogContext).showSnackBar(SnackBar(content: Text("Erreur sauvegarde kit: ${e.toString()}")));
                      } finally {
                        if (sbfDialogContext.mounted) setDialogStateInDialog(() => _isSavingInDialog = false );
                      }
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _loadRelays() async {
    if (!mounted) return;
    if (_currentKit == null) { 
      if (mounted) setState(() { _relaysList = []; _isLoadingRelays = false; });
      return;
    }
    if (mounted && _relaysList.isEmpty) setState(() { _isLoadingRelays = true; });
    try {
      List<Relay> relaysFromDb = await DatabaseHelper.instance.getRelays();
      if (mounted) { setState(() { _relaysList = relaysFromDb; _isLoadingRelays = false; });}
    } catch (e) {
      print("Erreur chargement relais (Admin): $e");
      if (mounted) { setState(() { _isLoadingRelays = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: ${e.toString()}"))); }
    }
  }

  Future<void> _loadConsumptionHistory() async {
    if (!mounted) return;
    if (_currentKit == null || _currentKit!.kitNumber.isEmpty) {
      if (mounted) { setState(() { _isLoadingHistory = false; _consumptionSpots = [const FlSpot(0,0)]; _rawConsumptionHistoryData = []; _chartMinY = 0; _chartMaxY = 10; });}
      print("AdminDashboard: _loadConsumptionHistory - Pas de kit, historique non chargé.");
      return;
    }
    if (mounted) setState(() { _isLoadingHistory = true; });
    try {
      final List<ConsumptionDataPoint> history = await DatabaseHelper.instance.getConsumptionHistory(limit: 60); 
      final List<FlSpot> spots = [];
      if (history.isNotEmpty) {
        for (int i = 0; i < history.length; i++) {
          spots.add(FlSpot(i.toDouble(), history[i].consumption));
        }
        double minYValue = spots.map((s) => s.y).reduce((a,b) => a < b ? a : b);
        double maxYValue = spots.map((s) => s.y).reduce((a,b) => a > b ? a : b);
        double range = maxYValue - minYValue;
        _chartMinY = (minYValue - range * 0.1).floorToDouble().clamp(0, double.infinity);
        _chartMaxY = (maxYValue + range * 0.1).ceilToDouble();
        if(_chartMinY >= _chartMaxY) _chartMaxY = _chartMinY + 5.0; 
        if (spots.length == 1) {
             _chartMinY = (spots.first.y * 0.8).floorToDouble().clamp(0, double.infinity);
             _chartMaxY = (spots.first.y * 1.2).ceilToDouble().clamp(_chartMinY + 1, double.infinity);
             if (_chartMinY == 0 && _chartMaxY <= 1) _chartMaxY = 5;
        }
      } else {
        _chartMinY = 0; _chartMaxY = 10; 
        spots.add(const FlSpot(0,0)); 
      }
      if (mounted) {
        setState(() {
          _rawConsumptionHistoryData = history; 
          _consumptionSpots = spots;
          _isLoadingHistory = false; 
        });
      }
      print("AdminDashboard: _loadConsumptionHistory - ${history.length} points chargés. _isLoadingHistory: $_isLoadingHistory");
    } catch (e, s) {
      print("AdminDashboard: Erreur chargement _loadConsumptionHistory: $e\n$s");
      if (mounted) { setState(() { _isLoadingHistory = false; _consumptionSpots = [const FlSpot(0,0)]; _rawConsumptionHistoryData = []; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur chargement historique: ${e.toString()}")));
      }
    }
  }

  Future<void> _showAddOrEditRelayDialog({Relay? existingRelay}) async {
    bool isEditing = existingRelay != null;
    _relayNameController.text = isEditing ? existingRelay.name : '';
    _relayAmperageController.text = isEditing ? existingRelay.amperage.toString() : '';
    return showDialog<void>(context: context, barrierDismissible: false, builder: (BuildContext dialogContext) {
        bool _isDialogSavingRelay = false; return StatefulBuilder(builder: (BuildContext sbfDialogContext, StateSetter setDialogStateInDialog) {
        return AlertDialog(title: Text(isEditing ? 'Modifier Relais' : 'Ajouter Relais'), content: Form(key: _formKeyRelayDialog, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:_relayNameController,decoration:InputDecoration(labelText:'Nom'),validator:(v){if(v==null||v.trim().isEmpty)return 'Nom?';return null;}),SizedBox(height:16),
        TextFormField(controller:_relayAmperageController,decoration:InputDecoration(labelText:'Amp (A)'),keyboardType:TextInputType.numberWithOptions(decimal:true),validator:(v){if(v==null||v.trim().isEmpty)return 'Amp?';if(double.tryParse(v.trim())==null)return 'Nombre?';return null;}),
        ]))),actions:<Widget>[TextButton(child:Text('Annuler'),onPressed:()=>Navigator.of(dialogContext).pop()),ElevatedButton(child:_isDialogSavingRelay?SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2,color:Theme.of(sbfDialogContext).colorScheme.onPrimary)):Text(isEditing?'MàJ':'Add'),onPressed:_isDialogSavingRelay?null:()async{
        if(_formKeyRelayDialog.currentState!.validate()){setDialogStateInDialog(()=>_isDialogSavingRelay=true);String name=_relayNameController.text.trim();double amperage=double.parse(_relayAmperageController.text.trim());
        try{if(isEditing){Relay uR=Relay(id:existingRelay.id,identificateur:existingRelay.identificateur,name:name,amperage:amperage,state:existingRelay.state,isDefaultRelay:existingRelay.isDefaultRelay,test:existingRelay.test);await DatabaseHelper.instance.updateRelay(uR);Navigator.of(dialogContext).pop();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais MàJ!')));}else{
        int count=(await DatabaseHelper.instance.getRelays()).length;String idf="REL${count+1}";while(await DatabaseHelper.instance.getRelayByIdentifier(idf)!=null){count++;idf="REL${count+1}";}
        Relay nR=Relay(identificateur:idf,name:name,amperage:amperage);await DatabaseHelper.instance.insertRelay(nR);Navigator.of(dialogContext).pop();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais Add!')));}
        _loadRelays();}catch(e){if(sbfDialogContext.mounted)ScaffoldMessenger.of(sbfDialogContext).showSnackBar(SnackBar(content:Text("Err:${e.toString()}")));}finally{if(sbfDialogContext.mounted)setDialogStateInDialog(()=>_isDialogSavingRelay=false);}}})]);});});}

  Future<void> _deleteRelay(int relayId, String relayName) async {
    bool? conf = await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(title:Text('Supprimer?'),content:Text('Supprimer "$relayName"?'),actions:[TextButton(child:Text('Non'),onPressed:()=>Navigator.of(dialogContext).pop(false)),ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor:Colors.redAccent),child:Text('Oui'),onPressed:()=>Navigator.of(dialogContext).pop(true))]));
    if(conf==true){try{await DatabaseHelper.instance.deleteRelay(relayId);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais "$relayName" del.')));_loadRelays();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("Err:${e.toString()}")));}}}

  Future<void> _toggleRelayState(Relay relay, bool newState) async {
    if(!mounted)return;if(_currentKit==null||_currentKit!.kitNumber.isEmpty){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Kit?')));return;}if(_smsServiceInstance==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('SMS Svc?')));return;}
    String act=newState?"ON":"OFF";String cmd="${act}#${relay.identificateur}";setState((){relay.state=newState;int i=_relaysList.indexWhere((r)=>r.id==relay.id);if(i!=-1)_relaysList[i]=relay;});
    try{await _smsServiceInstance!.sendSms(_currentKit!.kitNumber,cmd);await DatabaseHelper.instance.updateRelay(relay);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Cmd "$act" pour ${relay.name} sent.')));}
    catch(e){if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Err cmd:${e.toString()}')));setState((){relay.state=!newState;int i=_relaysList.indexWhere((r)=>r.id==relay.id);if(i!=-1)_relaysList[i]=relay;});}}}

  Future<void> _loadStandardUserInfo() async {
    if (!mounted) return;
    setState(() { _isLoadingStandardUser = true; });
    try {
      User? userFromDb = await DatabaseHelper.instance.getStandardUser();
      if (mounted) {
        setState(() {
          _standardUser = userFromDb;
          if (_standardUser != null) {
            _standardUserNumberController.text = _standardUser!.phoneNumber;
            _standardUserIdController.text = _standardUser!.userId;
          } else {
            _standardUserNumberController.clear();
            _standardUserIdController.clear();
          }
          _isLoadingStandardUser = false;
        });
      }
    } catch (e) {
      print("Erreur chargement utilisateur standard: $e");
      if (mounted) {
        setState(() { _isLoadingStandardUser = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur infos utilisateur: ${e.toString()}")));
      }
    }
  }
  
  void _showSetStandardUserDialog(BuildContext ownerContext) { 
    if (_standardUser != null) {
      _standardUserNumberController.text = _standardUser!.phoneNumber;
      _standardUserIdController.text = _standardUser!.userId;
    } else {
      _standardUserNumberController.clear();
      _standardUserIdController.clear();
    }
    final formKeySetUser = GlobalKey<FormState>();

    showDialog(
        context: ownerContext,
        barrierDismissible: true,
        builder: (dialogContext) {
          bool _isDialogSaving = false;
          return StatefulBuilder(
            builder: (BuildContext sbfDialogContext, StateSetter setDialogStateInDialog) {
              return AlertDialog(
                title: Text(_standardUser == null ? "Configurer l'Utilisateur Standard" : "Modifier l'Utilisateur Standard"),
                content: Form(
                  key: formKeySetUser,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: _standardUserNumberController,
                        decoration: const InputDecoration(labelText: 'Numéro de téléphone Utilisateur', prefixIcon: Icon(Icons.phone_android_outlined)),
                        keyboardType: TextInputType.phone,
                        validator: (value) { if (value == null || value.trim().isEmpty) return 'Numéro requis.'; if (!RegExp(r'^[0-9+]+$').hasMatch(value.trim()) || value.trim().length < 9) return 'Numéro invalide.'; return null; }
                      ),
                      const SizedBox(height: 10),
                    TextFormField(
                        controller: _standardUserIdController,
                        decoration: const InputDecoration(labelText: 'ID Utilisateur (PIN local)', prefixIcon: Icon(Icons.pin_outlined)),
                        keyboardType: TextInputType.number,
                         validator: (value) { if (value == null || value.trim().isEmpty) return 'ID requis.'; if (value.trim().length < 4) return 'PIN doit avoir >= 4 chiffres.'; if (!RegExp(r'^[0-9]+$').hasMatch(value.trim())) return 'PIN doit être numérique.'; return null; }
                      ),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Annuler")),
                  ElevatedButton(
                    child: _isDialogSaving 
                           ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(sbfDialogContext).colorScheme.onPrimary))
                           : Text(_standardUser == null ? "Enregistrer" : "Mettre à jour"),
                    onPressed: _isDialogSaving ? null : () async {
                      if (formKeySetUser.currentState!.validate()) {
                        setDialogStateInDialog(() { _isDialogSaving = true; });
                        try {
                            await DatabaseHelper.instance.setOrUpdateStandardUser(
                                _standardUserNumberController.text.trim(), 
                                _standardUserIdController.text.trim()
                            );
                            Navigator.pop(dialogContext); 
                            if (mounted) { 
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Utilisateur standard ${ _standardUser == null ? "configuré" : "mis à jour"}!'))
                                );
                                _loadStandardUserInfo(); 
                            }
                        } catch (e) {
                            if (sbfDialogContext.mounted) { 
                                ScaffoldMessenger.of(sbfDialogContext).showSnackBar(
                                    SnackBar(content: Text('Erreur: ${e.toString().replaceFirst("Exception: ", "")}'))
                                );
                            }
                        } finally {
                           if (sbfDialogContext.mounted) { 
                             setDialogStateInDialog(() { _isDialogSaving = false; });
                           }
                        }
                      }
                    },
                  ),
                ],
              );
            }
          );
        });
  }

  @override
  void dispose() {
    _kitNumberController.dispose(); _relayNameController.dispose(); _relayAmperageController.dispose(); 
    _standardUserNumberController.dispose(); _standardUserIdController.dispose();    
    _smsServiceInstance?.onKitDataUpdated=null; 
    _smsServiceInstance?.stopListening(); 
    super.dispose();
  }

  Widget _buildKitConfigurationCard() {
    final List<Widget> cC=[Text('Gérer Kit',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold),textAlign:TextAlign.center),SizedBox(height:12)];
    if(_isLoadingKit&&_currentKit==null){cC.add(Center(child:Padding(padding:EdgeInsets.all(8.0),child:Text("Loading..."))));}
    else if(_currentKit!=null&&_currentKit!.kitNumber.isNotEmpty){cC.add(Column(mainAxisSize:MainAxisSize.min,children:[Text("Kit#: ${_currentKit!.kitNumber}",style:Theme.of(context).textTheme.titleMedium,textAlign:TextAlign.center),SizedBox(height:12),ElevatedButton.icon(icon:Icon(Icons.edit_note_outlined),label:Text('Mod Num Kit'),onPressed:()=>_showKitConfigurationDialog())]));}
    else{cC.add(ElevatedButton.icon(icon:Icon(Icons.settings_applications_outlined),label:Text('Setup Kit'),onPressed:()=>_showKitConfigurationDialog()));}
    return Card(elevation:4,child:Padding(padding:EdgeInsets.all(16.0),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:cC)));
  }

  Widget _buildRelaysList() {
    final theme=Theme.of(context);if(_isLoadingRelays)return Center(child:CircularProgressIndicator());if(_currentKit==null)return Padding(padding:EdgeInsets.all(16.0),child:Center(child:Text("Setup kit first.",style:TextStyle(fontStyle:FontStyle.italic,color:Colors.grey[400]))));
    if(_relaysList.isEmpty)return Padding(padding:EdgeInsets.all(16.0),child:Center(child:Text("No relays. Click 'Add Relay'.",style:TextStyle(fontStyle:FontStyle.italic,color:Colors.grey[400]))));
    return ListView.builder(shrinkWrap:true,physics:NeverScrollableScrollPhysics(),itemCount:_relaysList.length,itemBuilder:(itemBuilderContext,idx){final relay=_relaysList[idx];return Card(margin:EdgeInsets.symmetric(vertical:6.0),child:ListTile(
    leading:Icon(relay.state?Icons.power:Icons.power_off,color:relay.state?theme.colorScheme.secondary:Colors.grey[600],size:30),title:Text(relay.name,style:TextStyle(fontWeight:FontWeight.bold)),
    subtitle:Text("ID:${relay.identificateur}|Amp:${relay.amperage.toStringAsFixed(1)}A|Conso: ${relay.currentRelayConsumption.toStringAsFixed(2)}kWh"),
    trailing:Row(mainAxisSize:MainAxisSize.min,children:[
    Transform.scale(scale:0.9,child:Switch(value:relay.state,onChanged:(val)=>_toggleRelayState(relay,val),activeColor:theme.colorScheme.secondary,inactiveThumbColor:Colors.grey[400],inactiveTrackColor:Colors.grey[700])),
    IconButton(icon:Icon(Icons.edit_outlined),color:Colors.amberAccent[100],tooltip:'Edit',onPressed:()=>_showAddOrEditRelayDialog(existingRelay:relay)),
    if(!relay.isDefaultRelay)IconButton(icon:Icon(Icons.delete_outline),color:Colors.redAccent[100],tooltip:'Del',onPressed:()=>_deleteRelay(relay.id!,relay.name))])));});
  }
  
  @override
  Widget build(BuildContext context) { 
    final theme = Theme.of(context); 
    return Scaffold(
      appBar: AppBar(title:Text('Admin Dashboard'),actions:[
          IconButton(icon:Icon(_standardUser == null && !_isLoadingStandardUser ? Icons.person_add_alt_1 : Icons.manage_accounts),onPressed:()=>_showSetStandardUserDialog(context),tooltip:_standardUser == null && !_isLoadingStandardUser ? 'Configurer Utilisateur Standard' : 'Modifier Utilisateur Standard'),
          IconButton(icon:Icon(Icons.delete_sweep_outlined),onPressed:()async{
            bool? confirmClear = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(title: const Text('Vider l\'historique'), content: const Text('Vider tout l\'historique des consommations ? Action irréversible.'), actions: <Widget>[TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(dialogContext).pop(false)), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent), child: const Text('Vider'), onPressed: () => Navigator.of(dialogContext).pop(true))]));
            if (confirmClear == true) { await DatabaseHelper.instance.clearConsumptionHistory(); await DatabaseHelper.instance.clearAllRelayConsumptionHistories(); _loadConsumptionHistory(); if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les historiques de consommation vidés.')));}
          },tooltip:'Vider tous les historiques'),
          IconButton(icon:Icon(Icons.logout),tooltip:'Déconnexion',onPressed:(){_smsServiceInstance?.stopListening();Navigator.pushReplacementNamed(context,'/login');})]),
      body: (_isLoadingKit && _currentKit == null) || _isLoadingStandardUser
          ? Center(child:CircularProgressIndicator())
          : SingleChildScrollView(padding:EdgeInsets.all(16.0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _buildKitConfigurationCard(),
            const SizedBox(height: 12),
            Card(elevation:2,child:Padding(padding:const EdgeInsets.all(16.0),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Text("Gestion de l'Utilisateur Standard",style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold),textAlign:TextAlign.center),
              const SizedBox(height:10),
              if(_isLoadingStandardUser)const Center(child:SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2)))
              else if(_standardUser!=null)Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text("Numéro Actuel: ${_standardUser!.phoneNumber}"),Text("ID (PIN) Actuel: ${_standardUser!.userId}"),const SizedBox(height:10),Center(child:ElevatedButton.icon(icon:const Icon(Icons.edit_outlined,size:16),label:const Text("Modifier l'Utilisateur Standard"),style:ElevatedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:8)),onPressed:()=>_showSetStandardUserDialog(context)))])
              else Column(children:[const Text("Aucun utilisateur standard n'est configuré.",textAlign:TextAlign.center,style:TextStyle(fontStyle:FontStyle.italic)),const SizedBox(height:10),Center(child:ElevatedButton.icon(icon:const Icon(Icons.person_add_outlined,size:16),label:const Text("Configurer l'Utilisateur Standard"),style:ElevatedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:8)),onPressed:()=>_showSetStandardUserDialog(context)))])
            ]))),
            SizedBox(height:24),Divider(thickness:0.5,color:Colors.grey),SizedBox(height:16),
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Expanded(child:Text("Gestion des Relais",style:theme.textTheme.titleLarge)),if(_currentKit!=null)ElevatedButton.icon(icon:Icon(Icons.add_circle_outline,size:18),label:Text("Ajouter"),onPressed:()=>_showAddOrEditRelayDialog(),style:ElevatedButton.styleFrom(padding:EdgeInsets.symmetric(horizontal:12,vertical:8)))]),
            SizedBox(height:10),_buildRelaysList(),SizedBox(height:24),Divider(thickness:0.5,color:Colors.grey),SizedBox(height:16),
            Text("Historique de Consommation Globale",style:theme.textTheme.titleLarge?.copyWith(color: Colors.white)),SizedBox(height:10),
            Container(height:250,padding:EdgeInsets.fromLTRB(0,16,16,12),decoration:BoxDecoration(color:theme.cardTheme.color?.withOpacity(0.7),borderRadius:BorderRadius.circular(12)),
            child:_isLoadingHistory?Center(child:CircularProgressIndicator()):_consumptionSpots.isEmpty||(_consumptionSpots.length==1 && _consumptionSpots[0].x == 0 && _consumptionSpots[0].y ==0 )
                ?Center(child:Text("Pas de données d'historique global à afficher.",style:TextStyle(fontStyle:FontStyle.italic,color:theme.textTheme.bodySmall?.color)))
                :LineChart(LineChartData(
            minX:0,maxX:(_consumptionSpots.length-1).toDouble().clamp(0,double.infinity),minY:_chartMinY,maxY:_chartMaxY,
            gridData:FlGridData(show:true,drawVerticalLine:true,horizontalInterval:(_chartMaxY-_chartMinY>0)?((_chartMaxY-_chartMinY)/5).clamp(1,double.infinity):1,verticalInterval:(_consumptionSpots.length>1)?((_consumptionSpots.length-1)/5).clamp(1,double.infinity):1,getDrawingHorizontalLine:(v)=>FlLine(color:Colors.white24.withOpacity(0.2),strokeWidth:0.5),getDrawingVerticalLine:(v)=>FlLine(color:Colors.white24.withOpacity(0.2),strokeWidth:0.5)),
            titlesData:FlTitlesData(show:true,rightTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),topTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),
            bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:35,interval:(_consumptionSpots.length>5)?((_consumptionSpots.length-1)/5).floorToDouble().clamp(1,double.infinity):1,getTitlesWidget:(val,meta){
                int index = val.toInt();
                if (index >= 0 && index < _rawConsumptionHistoryData.length) {
                  return SideTitleWidget(axisSide:meta.axisSide,space:4,child:Text(DateFormat('dd/MM\nHH:mm').format(_rawConsumptionHistoryData[index].timestamp),style:TextStyle(color:Colors.white70,fontSize:10)));
                }
                return Text('');
            })),
            leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(val,meta)=>Text(val.toStringAsFixed(1),style:TextStyle(color:Colors.white70,fontSize:10))))),
            borderData:FlBorderData(show:true,border:Border.all(color:Colors.white30.withOpacity(0.5),width:1)),
            lineBarsData:[LineChartBarData(spots:_consumptionSpots,isCurved:true,color:theme.colorScheme.secondary,barWidth:3,dotData:FlDotData(show:_consumptionSpots.length<20),belowBarData:BarAreaData(show:true,color:theme.colorScheme.secondary.withOpacity(0.2)))]))),
            ]))
    );
  }
}