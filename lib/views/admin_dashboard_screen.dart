// lib/views/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart';
import 'package:enmkit_fresh_start/models/user.dart'; 
import 'package:enmkit_fresh_start/services/database_helper.dart';
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
  // bool _isSmsServiceInitialized = false; // Remplacé par la logique d'init directe

  List<FlSpot> _consumptionSpots = [const FlSpot(0,0)]; 
  bool _isLoadingHistory = true; 
  double _chartMinY = 0;
  double _chartMaxY = 10;

  final TextEditingController _userNumberController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialDataAndInitializeServices();
  }

  Future<void> _loadInitialDataAndInitializeServices() async {
    await _loadKitInfo(); 
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

    // Utiliser le getter public pour vérifier (bien que SmsService.startListening fasse sa propre vérif)
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
      
      _smsServiceInstance!.startListeningForMessages(); // DÉMARRER L'ÉCOUTE
      print("AdminDashboard: SmsService, listeners et ÉCOUTE SMS configurés pour le kit ${_currentKit!.kitNumber}.");
    } else { 
      _smsServiceInstance!.stopListening(); // ARRÊTER L'ÉCOUTE SI PAS DE KIT OU NUMÉRO MANQUANT
      if (mounted) {
        setState(() {
          _isLoadingRelays = false; 
          _relaysList = [];
          _isLoadingHistory = false; 
          _consumptionSpots = [const FlSpot(0,0)]; 
        });
        print("AdminDashboard: Pas de kit configuré ou numéro manquant dans SmsService, écoute SMS arrêtée.");
      }
    }
  }

  Future<void> _loadKitInfo() async {
    if (!mounted) return;
    setState(() { _isLoadingKit = true; });
    try {
      Kit? kitFromDb = await DatabaseHelper.instance.getKit();
      if (mounted) {
        bool kitNumberMightHaveChanged = (_currentKit?.kitNumber != kitFromDb?.kitNumber) ||
                                       (_currentKit == null && kitFromDb != null) ||
                                       (_currentKit != null && kitFromDb == null) ;
        setState(() {
          _currentKit = kitFromDb;
          if (_currentKit != null) {
            _kitNumberController.text = _currentKit!.kitNumber;
          } else {
            _kitNumberController.clear();
          }
          _isLoadingKit = false;
        });
        
        if (kitNumberMightHaveChanged && _smsServiceInstance != null) {
             print("AdminDashboard: Le statut/numéro du Kit a changé, réinitialisation de la logique SMS.");
            await _initializeSmsRelatedLogic();
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
          builder: (stfContext, setDialogStateInDialog) {
            return AlertDialog(
              title: Text(isEditingKit ? 'Modifier le Numéro du Kit' : 'Configurer le Kit EnMKIT'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKeyKitDialog,
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    TextFormField(
                      controller: _kitNumberController,
                      decoration: const InputDecoration(labelText: 'Numéro de téléphone de la SIM du Kit', prefixIcon: Icon(Icons.phone_iphone), border: OutlineInputBorder(), hintText: 'Ex: 0612345678'),
                      keyboardType: TextInputType.phone,
                      validator: (value) { if (value == null || value.trim().isEmpty) return 'Veuillez entrer le numéro de téléphone du kit.'; if (!RegExp(r'^[0-9+]+$').hasMatch(value.trim()) || value.trim().length < 9) return 'Veuillez entrer un numéro de téléphone valide.'; return null; },
                    ),
                  ]),
                ),
              ),
              actions: <Widget>[
                if (isEditingKit) TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(dialogContext).pop()),
                ElevatedButton(
                  child: _isSavingInDialog ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(dialogContext).colorScheme.onPrimary)) : Text(isEditingKit ? 'Mettre à jour' : 'Enregistrer'),
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
                        if (stfContext.mounted) ScaffoldMessenger.of(stfContext).showSnackBar(SnackBar(content: Text("Erreur sauvegarde kit: ${e.toString()}")));
                      } finally {
                        if (stfContext.mounted) setDialogStateInDialog(() => _isSavingInDialog = false );
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
    if (_currentKit == null) { if (mounted) setState(() { _relaysList = []; _isLoadingRelays = false; }); return; }
    if (mounted) setState(() { _isLoadingRelays = true; });
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
    if (_currentKit == null) { if (mounted) { setState(() { _isLoadingHistory = false; _consumptionSpots = [const FlSpot(0,0)]; });} print("AdminDashboard: _loadConsumptionHistory - Pas de kit"); return; }
    if (mounted) setState(() { _isLoadingHistory = true; });
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {
        _consumptionSpots = [ const FlSpot(0, 1.5), const FlSpot(1, 2.8), const FlSpot(2, 2.0), const FlSpot(3, 3.5), const FlSpot(4, 3.0), const FlSpot(5, 4.5)];
        if (_consumptionSpots.isNotEmpty && _consumptionSpots.length >=2) {
             _chartMinY = _consumptionSpots.map((s) => s.y).reduce((a,b) => a < b ? a : b);
             _chartMaxY = _consumptionSpots.map((s) => s.y).reduce((a,b) => a > b ? a : b);
             _chartMinY = (_chartMinY * 0.9).floorToDouble().clamp(0, double.infinity);
             _chartMaxY = (_chartMaxY * 1.1).ceilToDouble();
             if(_chartMinY >= _chartMaxY) _chartMaxY = _chartMinY + 5.0;
        } else { _chartMinY = 0; _chartMaxY = 10; }
        _isLoadingHistory = false; 
      });
      print("AdminDashboard: _loadConsumptionHistory (factice) exécuté, _isLoadingHistory: $_isLoadingHistory");
    }
  }

  Future<void> _showAddOrEditRelayDialog({Relay? existingRelay}) async {
    bool isEditing = existingRelay != null;
    _relayNameController.text = isEditing ? existingRelay.name : '';
    _relayAmperageController.text = isEditing ? existingRelay.amperage.toString() : '';
    return showDialog<void>(context: context, barrierDismissible: false, builder: (BuildContext dialogContext) {
        bool _isDialogSavingRelay = false; return StatefulBuilder(builder: (stfContext, setDialogStateInDialog) {
        return AlertDialog(title: Text(isEditing ? 'Modifier Relais' : 'Ajouter Relais'), content: Form(key: _formKeyRelayDialog, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:_relayNameController,decoration:InputDecoration(labelText:'Nom'),validator:(v){if(v==null||v.trim().isEmpty)return 'Nom?';return null;}),SizedBox(height:16),
        TextFormField(controller:_relayAmperageController,decoration:InputDecoration(labelText:'Amp (A)'),keyboardType:TextInputType.numberWithOptions(decimal:true),validator:(v){if(v==null||v.trim().isEmpty)return 'Amp?';if(double.tryParse(v.trim())==null)return 'Nombre?';return null;}),
        ]))),actions:<Widget>[TextButton(child:Text('Annuler'),onPressed:()=>Navigator.of(dialogContext).pop()),ElevatedButton(child:_isDialogSavingRelay?SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2,color:Theme.of(dialogContext).colorScheme.onPrimary)):Text(isEditing?'MàJ':'Add'),onPressed:_isDialogSavingRelay?null:()async{
        if(_formKeyRelayDialog.currentState!.validate()){setDialogStateInDialog(()=>_isDialogSavingRelay=true);String name=_relayNameController.text.trim();double amperage=double.parse(_relayAmperageController.text.trim());
        try{if(isEditing){Relay uR=Relay(id:existingRelay.id,identificateur:existingRelay.identificateur,name:name,amperage:amperage,state:existingRelay.state,isDefaultRelay:existingRelay.isDefaultRelay,test:existingRelay.test);await DatabaseHelper.instance.updateRelay(uR);Navigator.of(dialogContext).pop();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais MàJ!')));}else{
        int count=(await DatabaseHelper.instance.getRelays()).length;String idf="REL${count+1}";while(await DatabaseHelper.instance.getRelayByIdentifier(idf)!=null){count++;idf="REL${count+1}";}
        Relay nR=Relay(identificateur:idf,name:name,amperage:amperage);await DatabaseHelper.instance.insertRelay(nR);Navigator.of(dialogContext).pop();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais Add!')));}
        _loadRelays();}catch(e){if(stfContext.mounted)ScaffoldMessenger.of(stfContext).showSnackBar(SnackBar(content:Text("Err:${e.toString()}")));}finally{if(stfContext.mounted)setDialogStateInDialog(()=>_isDialogSavingRelay=false);}}})]);});});}

  Future<void> _deleteRelay(int relayId, String relayName) async {
    bool? conf = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Supprimer?'),content:Text('Supprimer "$relayName"?'),actions:[TextButton(child:Text('Non'),onPressed:()=>Navigator.of(ctx).pop(false)),ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor:Colors.redAccent),child:Text('Oui'),onPressed:()=>Navigator.of(ctx).pop(true))]));
    if(conf==true){try{await DatabaseHelper.instance.deleteRelay(relayId);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Relais "$relayName" del.')));_loadRelays();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text("Err:${e.toString()}")));}}}

  Future<void> _toggleRelayState(Relay relay, bool newState) async {
    if(!mounted)return;if(_currentKit==null||_currentKit!.kitNumber.isEmpty){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Kit?')));return;}if(_smsServiceInstance==null){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('SMS Svc?')));return;}
    String act=newState?"ON":"OFF";String cmd="${act}#${relay.identificateur}";setState((){relay.state=newState;int i=_relaysList.indexWhere((r)=>r.id==relay.id);if(i!=-1)_relaysList[i]=relay;});
    try{await _smsServiceInstance!.sendSms(_currentKit!.kitNumber,cmd);await DatabaseHelper.instance.updateRelay(relay);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Cmd "$act" pour ${relay.name} sent.')));}
    catch(e){if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Err cmd:${e.toString()}')));setState((){relay.state=!newState;int i=_relaysList.indexWhere((r)=>r.id==relay.id);if(i!=-1)_relaysList[i]=relay;});}}}

  @override
  void dispose() {
    _kitNumberController.dispose(); _relayNameController.dispose(); _relayAmperageController.dispose(); 
    _userNumberController.dispose(); _userIdController.dispose();    
    _smsServiceInstance?.onKitDataUpdated=null; 
    _smsServiceInstance?.stopListening(); // APPEL À STOPLISTENING
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
    subtitle:Text("ID:${relay.identificateur}|Amp:${relay.amperage.toStringAsFixed(1)}A"),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
    Transform.scale(scale:0.9,child:Switch(value:relay.state,onChanged:(val)=>_toggleRelayState(relay,val),activeColor:theme.colorScheme.secondary,inactiveThumbColor:Colors.grey[400],inactiveTrackColor:Colors.grey[700])),
    IconButton(icon:Icon(Icons.edit_outlined),color:Colors.amberAccent[100],tooltip:'Edit',onPressed:()=>_showAddOrEditRelayDialog(existingRelay:relay)),
    if(!relay.isDefaultRelay)IconButton(icon:Icon(Icons.delete_outline),color:Colors.redAccent[100],tooltip:'Del',onPressed:()=>_deleteRelay(relay.id!,relay.name))])));});
  }
  
  void _showAddUserDialog(BuildContext ownerContext) { 
    _userNumberController.clear();_userIdController.clear();final formKeyAddUser=GlobalKey<FormState>();showDialog(context:ownerContext,builder:(dialogCtx){
    bool _isDialogSavingUser=false;return StatefulBuilder(builder:(stfContext,setDialogStateInDialog){return AlertDialog(title:Text("Add User"),content:Form(key:formKeyAddUser,child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextFormField(controller:_userNumberController,decoration:InputDecoration(labelText:'Phone'),keyboardType:TextInputType.phone,validator:(v){if(v==null||v.trim().isEmpty)return'Num?';if(!RegExp(r'^[0-9+]+$').hasMatch(v.trim())||v.trim().length<9)return'Invalid';return null;}),SizedBox(height:10),
    TextFormField(controller:_userIdController,decoration:InputDecoration(labelText:'User ID (PIN)'),validator:(v){if(v==null||v.trim().isEmpty)return'ID?';if(v.trim().length<4)return'PIN <4';if(!RegExp(r'^[0-9]+$').hasMatch(v.trim()))return'PIN numeric';return null;})])),
    actions:[TextButton(onPressed:()=>Navigator.pop(dialogCtx),child:Text("Cancel")),ElevatedButton(child:_isDialogSavingUser?SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2, color: Theme.of(dialogCtx).colorScheme.onPrimary)):Text("Add"),onPressed:_isDialogSavingUser?null:()async{
    if(formKeyAddUser.currentState!.validate()){setDialogStateInDialog(()=>_isDialogSavingUser=true);try{User nU=User(phoneNumber:_userNumberController.text.trim(),userId:_userIdController.text.trim(),isAdmin:false);await DatabaseHelper.instance.addNewUserByAdmin(nU);
    Navigator.pop(dialogCtx);if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('User ${_userNumberController.text.trim()} added!')));_userNumberController.clear();_userIdController.clear();}}
    catch(e){if(stfContext.mounted)ScaffoldMessenger.of(stfContext).showSnackBar(SnackBar(content:Text('Err:${e.toString().replaceFirst("Exception: ","")}')));}
    finally{if(stfContext.mounted)setDialogStateInDialog(()=>_isDialogSavingUser=false);}}})]);});});}

  @override
  Widget build(BuildContext context) { 
    final theme = Theme.of(context); 
    return Scaffold(
      appBar: AppBar(title:Text('Admin Dashboard'),actions:[
          IconButton(icon:Icon(Icons.person_add_alt_1),onPressed:()=>_showAddUserDialog(context),tooltip:'Ajouter un utilisateur'),
          IconButton(icon:Icon(Icons.delete_sweep_outlined),onPressed:()async{
            bool? confirmClear = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(title: const Text('Vider l\'historique'), content: const Text('Vider tout l\'historique des consommations ? Action irréversible.'), actions: <Widget>[TextButton(child: const Text('Annuler'), onPressed: () => Navigator.of(dialogContext).pop(false)), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent), child: const Text('Vider'), onPressed: () => Navigator.of(dialogContext).pop(true))]));
            if (confirmClear == true) { await DatabaseHelper.instance.clearConsumptionHistory(); await DatabaseHelper.instance.clearAllRelayConsumptionHistories(); _loadConsumptionHistory(); if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tous les historiques de consommation vidés.')));}
          },tooltip:'Vider tous les historiques'),
          IconButton(icon:Icon(Icons.logout),tooltip:'Déconnexion',onPressed:(){_smsServiceInstance?.stopListening();Navigator.pushReplacementNamed(context,'/login');})]),
      body: (_isLoadingKit && _currentKit == null) 
          ? Center(child:CircularProgressIndicator())
          : SingleChildScrollView(padding:EdgeInsets.all(16.0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _buildKitConfigurationCard(),SizedBox(height:24),Divider(thickness:0.5,color:Colors.grey),SizedBox(height:16),
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Expanded(child:Text("Gestion des Relais",style:theme.textTheme.titleLarge)),if(_currentKit!=null)ElevatedButton.icon(icon:Icon(Icons.add_circle_outline,size:18),label:Text("Ajouter"),onPressed:()=>_showAddOrEditRelayDialog(),style:ElevatedButton.styleFrom(padding:EdgeInsets.symmetric(horizontal:12,vertical:8)))]),
            SizedBox(height:10),_buildRelaysList(),SizedBox(height:24),Divider(thickness:0.5,color:Colors.grey),SizedBox(height:16),
            Text("Historique de Consommation",style:theme.textTheme.titleLarge?.copyWith(color: Colors.white)),SizedBox(height:10),
            Container(height:250,padding:EdgeInsets.fromLTRB(0,16,16,12),decoration:BoxDecoration(color:theme.cardTheme.color?.withOpacity(0.7),borderRadius:BorderRadius.circular(12)),
            child:_isLoadingHistory?Center(child:CircularProgressIndicator()):_consumptionSpots.isEmpty||_consumptionSpots.length<2?Center(child:Text("Données d'historique insuffisantes.",style:TextStyle(fontStyle:FontStyle.italic,color:theme.textTheme.bodySmall?.color))):LineChart(LineChartData(
            minX:0,maxX:(_consumptionSpots.length-1).toDouble().clamp(0,double.infinity),minY:_chartMinY,maxY:_chartMaxY,
            gridData:FlGridData(show:true,drawVerticalLine:true,horizontalInterval:(_chartMaxY-_chartMinY>0)?((_chartMaxY-_chartMinY)/5).clamp(1,double.infinity):1,verticalInterval:(_consumptionSpots.length>1)?((_consumptionSpots.length-1)/5).clamp(1,double.infinity):1,getDrawingHorizontalLine:(v)=>FlLine(color:Colors.white24.withOpacity(0.2),strokeWidth:0.5),getDrawingVerticalLine:(v)=>FlLine(color:Colors.white24.withOpacity(0.2),strokeWidth:0.5)),
            titlesData:FlTitlesData(show:true,rightTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),topTitles:AxisTitles(sideTitles:SideTitles(showTitles:false)),
            bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:30,interval:(_consumptionSpots.length>5)?(_consumptionSpots.length/5).floorToDouble().clamp(1,double.infinity):1,getTitlesWidget:(val,meta){
                // Pour afficher l'heure des points de _consumptionHistory si disponible
                // if (val.toInt() >= 0 && val.toInt() < _rawConsumptionHistoryData.length) {
                //   return SideTitleWidget(axisSide:meta.axisSide,space:4,child:Text(DateFormat('HH:mm').format(_rawConsumptionHistoryData[val.toInt()].timestamp),style:TextStyle(color:Colors.white70,fontSize:10)));
                // }
                return SideTitleWidget(axisSide:meta.axisSide,space:4,child:Text(val.toInt().toString(),style:TextStyle(color:Colors.white70,fontSize:10)));
            })),
            leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(val,meta)=>Text(val.toStringAsFixed(1),style:TextStyle(color:Colors.white70,fontSize:10))))),
            borderData:FlBorderData(show:true,border:Border.all(color:Colors.white30.withOpacity(0.5),width:1)),
            lineBarsData:[LineChartBarData(spots:_consumptionSpots,isCurved:true,color:theme.colorScheme.secondary,barWidth:3,dotData:FlDotData(show:_consumptionSpots.length<20),belowBarData:BarAreaData(show:true,color:theme.colorScheme.secondary.withOpacity(0.2)))]))),
            ]))
    );
  }
}