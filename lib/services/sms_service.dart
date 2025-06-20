// lib/services/sms_service.dart

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_advanced/sms_advanced.dart';
import 'dart:async'; 

import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart'; // IMPORT AJOUTÉ/DÉCOMMENTÉ
import 'package:enmkit_fresh_start/models/relay_consumption_data_point.dart'; // IMPORT AJOUTÉ
import 'package:enmkit_fresh_start/services/database_helper.dart';
// ConsumptionDataPoint pour le kit global est défini dans database_helper.dart

class SmsService extends ChangeNotifier {
  final SmsSender _sender = SmsSender();
  final SmsReceiver _receiver = SmsReceiver();
  StreamSubscription<SmsMessage>? _smsSubscription;
  
  String? _internalKitPhoneNumberForListening; 
  
  VoidCallback? onKitDataUpdated;

  SmsService() {
    print("SmsService initialisé.");
  }

  String? get kitPhoneNumberForListening => _internalKitPhoneNumberForListening;

  Future<bool> _requestSmsPermission() async {
    PermissionStatus status = await Permission.sms.request();
    if (status.isGranted) {
      print("SmsService: Permission SMS (globale) accordée.");
      return true;
    } else {
      print("SmsService: Permission SMS (globale) refusée (status: $status).");
      if (status.isPermanentlyDenied) {
        print("SmsService: Permission SMS refusée de manière permanente.");
        await openAppSettings(); 
      }
      return false;
    }
  }

  Future<void> sendSms(String phoneNumber, String message) async {
    if (phoneNumber.isEmpty || message.isEmpty) {
      print("SmsService: Numéro de téléphone ou message vide. Envoi annulé.");
      throw Exception("Numéro de téléphone ou message vide.");
    }
    bool permissionGranted = await _requestSmsPermission();
    if (!permissionGranted) {
      print("SmsService: Envoi SMS annulé, permission non accordée.");
      throw Exception("Permission SMS non accordée.");
    }
    try {
      SmsMessage sms = SmsMessage(phoneNumber, message);
      sms.onStateChanged.listen((SmsMessageState state) {
        switch (state) {
          case SmsMessageState.Sending: print('SmsService: Envoi SMS à $phoneNumber...'); break;
          case SmsMessageState.Sent: print('SmsService: SMS envoyé à $phoneNumber!'); break;
          case SmsMessageState.Delivered: print('SmsService: SMS délivré à $phoneNumber!'); break;
          case SmsMessageState.Fail: print('SmsService: Échec envoi SMS à $phoneNumber.'); break;
          default: print('SmsService: État SMS inconnu pour $phoneNumber: $state'); break;
        }
      });
      print("SmsService: Tentative d'envoi SMS '$message' à '$phoneNumber'...");
      await _sender.sendSms(sms);
      print("SmsService: Commande d'envoi SMS initiée pour '$message' à '$phoneNumber'.");
    } catch (e) {
      print("SmsService: Erreur envoi SMS: $e");
      throw Exception("Erreur envoi SMS: ${e.toString()}");
    }
  }

  Future<void> initializeKitPhoneNumberForListening() async {
    Kit? kit = await DatabaseHelper.instance.getKit();
    if (kit != null && kit.kitNumber.isNotEmpty) {
      _internalKitPhoneNumberForListening = kit.kitNumber;
      print("SmsService: Numéro du kit pour l'écoute initialisé à: $_internalKitPhoneNumberForListening");
    } else {
      _internalKitPhoneNumberForListening = null;
      print("SmsService: Numéro du kit pour l'écoute non trouvé ou vide.");
    }
  }

  void startListeningForMessages() async {
    if (_internalKitPhoneNumberForListening == null || _internalKitPhoneNumberForListening!.isEmpty) {
      print("SmsService: Tentative d'init du numéro de kit pour l'écoute...");
      await initializeKitPhoneNumberForListening();
      if (_internalKitPhoneNumberForListening == null || _internalKitPhoneNumberForListening!.isEmpty) {
          print("SmsService: Écoute impossible, numéro de kit non disponible.");
          return;
      }
    }

    bool permGranted = await _requestSmsPermission();
    if (!permGranted) { print("SmsService: Écoute impossible, permission SMS non accordée."); return; }
    await stopListening(); 
    if (_receiver.onSmsReceived == null) { print("SmsService ERREUR: _receiver.onSmsReceived est null."); return; }

    _smsSubscription = _receiver.onSmsReceived!.listen((SmsMessage message) {
      print("SmsService (Listener): SMS reçu de ${message.address} - Corps: ${message.body}");
      if (message.address == _internalKitPhoneNumberForListening) {
        print("SmsService (Listener): SMS pertinent reçu du kit: ${message.body}");
        if (message.body != null && message.body!.isNotEmpty) {
          _processIncomingSms(message.body!);
        } else { print("SmsService (Listener): Corps du SMS du kit est vide."); }
      }
    }, onError: (dynamic error) { print("SmsService (Listener): Erreur réception SMS: $error"); });

    print("SmsService: Écoute des SMS démarrée pour: $_internalKitPhoneNumberForListening");
  }

  Future<void> _processIncomingSms(String smsBody) async {
    print("SmsService: Traitement du SMS entrant: $smsBody");
    bool dataActuallyUpdated = false;
    Kit? currentKit = await DatabaseHelper.instance.getKit(); // Nécessaire pour GLOBAL_KIT_DATA

    List<String> parts = smsBody.split(';');
    try {
      if (parts.isNotEmpty) {
        String commandType = parts[0].trim().toUpperCase();
        DateTime now = DateTime.now();

        // FORMAT: GLOBAL_KIT_DATA;CONS;[val_conso_globale];IMP;[val_impulsions_globales]
        if (commandType == "GLOBAL_KIT_DATA" && parts.length >= 5) {
          if (currentKit == null) {
            print("SmsService: Kit non configuré, impossible de traiter GLOBAL_KIT_DATA.");
            return; // Ne peut pas mettre à jour le kit s'il n'existe pas
          }
          // parts[0] = GLOBAL_KIT_DATA
          // parts[1] = CONS
          // parts[2] = valeur_consommation
          // parts[3] = IMP
          // parts[4] = valeur_impulsions
          double? newGlobalConsumption = double.tryParse(parts[2].trim());
          int? newGlobalImpulses = int.tryParse(parts[4].trim());
          
          bool kitDataChanged = false;
          if (newGlobalConsumption != null && newGlobalConsumption != currentKit.currentConsumption) {
            currentKit.currentConsumption = newGlobalConsumption;
            kitDataChanged = true;
          }
          if (newGlobalImpulses != null && newGlobalImpulses != currentKit.currentImpulses) {
            currentKit.currentImpulses = newGlobalImpulses;
            kitDataChanged = true;
          }
          
          if (kitDataChanged) {
            await DatabaseHelper.instance.updateKit(currentKit);
            print("SmsService: Données Kit Globales mises à jour: C=${currentKit.currentConsumption}, I=${currentKit.currentImpulses}");
            dataActuallyUpdated = true;
          }

          // Enregistrer dans l'historique de consommation globale du kit
          if (newGlobalConsumption != null && newGlobalImpulses != null) {
            await DatabaseHelper.instance.insertConsumptionDataPoint(
              ConsumptionDataPoint(timestamp: now, consumption: newGlobalConsumption, impulses: newGlobalImpulses)
            );
            print("SmsService: Point de consommation globale (C:$newGlobalConsumption, I:$newGlobalImpulses) enregistré.");
            dataActuallyUpdated = true; 
          }
        } 
        // FORMAT: RELAY_DATA;[identificateur_relais];CONS;[valeur_consommation_relais]
        else if (commandType == "RELAY_DATA" && parts.length >= 4) {
          // parts[0] = RELAY_DATA
          // parts[1] = identificateur_relais
          // parts[2] = CONS
          // parts[3] = valeur_consommation_relais
          String relayIdentifier = parts[1].trim();
          double? newRelayConsumption = double.tryParse(parts[3].trim());

          if (relayIdentifier.isNotEmpty && newRelayConsumption != null) {
            Relay? relayToUpdate = await DatabaseHelper.instance.getRelayByIdentifier(relayIdentifier);
            if (relayToUpdate != null) {
              bool relayConsumptionChanged = false;
              if (newRelayConsumption != relayToUpdate.currentRelayConsumption) {
                relayToUpdate.currentRelayConsumption = newRelayConsumption;
                relayConsumptionChanged = true;
              }

              if (relayConsumptionChanged) {
                await DatabaseHelper.instance.updateRelay(relayToUpdate);
                print("SmsService: Consommation du relais '$relayIdentifier' mise à jour à $newRelayConsumption.");
                dataActuallyUpdated = true;
              }

              // Enregistrer dans l'historique de consommation du relais
              await DatabaseHelper.instance.insertRelayConsumptionDataPoint(
                RelayConsumptionDataPoint(
                  relayIdentificateur: relayIdentifier, 
                  timestamp: now, 
                  consumption: newRelayConsumption
                )
              );
              print("SmsService: Point de consommation pour relais '$relayIdentifier' (C:$newRelayConsumption) enregistré.");
              dataActuallyUpdated = true;

            } else {
              print("SmsService: Relais avec identificateur '$relayIdentifier' non trouvé pour MàJ conso.");
            }
          } else {
            print("SmsService: Données pour RELAY_DATA invalides ou incomplètes: $smsBody");
          }
        }
        else {
          print("SmsService: Format SMS du kit non reconnu ou globalement incomplet: $smsBody");
        }
      }
    } catch (e, s) {
      print("SmsService: Erreur parsing/MàJ DB du SMS: $e");
      print("SmsService: Stacktrace: $s");
    }

    if (dataActuallyUpdated) {
      onKitDataUpdated?.call(); 
      notifyListeners(); 
      print("SmsService: Notification de MàJ des données envoyée.");
    }
  }
  
  Future<void> stopListening() async {
    if (_smsSubscription != null) {
      await _smsSubscription!.cancel();
      _smsSubscription = null;
      print("SmsService: Écoute des SMS arrêtée.");
    }
  }

  @override
  void dispose() {
    stopListening(); 
    super.dispose();
  }
}