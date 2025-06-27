// lib/services/sms_service.dart

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_advanced/sms_advanced.dart';
import 'dart:async'; 

import 'package:enmkit_fresh_start/models/kit.dart';
import 'package:enmkit_fresh_start/models/relay.dart';
import 'package:enmkit_fresh_start/models/relay_consumption_data_point.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart'; 
// ConsumptionDataPoint est déjà défini dans database_helper.dart

class SmsService extends ChangeNotifier {
  final SmsSender _sender = SmsSender();
  final SmsReceiver _receiver = SmsReceiver();
  StreamSubscription<SmsMessage>? _smsEventSubscription; // Pour les événements de réception
  StreamSubscription<SmsMessageState>? _smsSendStateSubscription; // Pour les états d'envoi (si on veut les suivre globalement)



  String? _kitPhoneNumberForListening; // Stocke le numéro du kit à écouter
  
  VoidCallback? onKitDataUpdated; // Callback pour notifier les dashboards

  SmsService() {
    print("SmsService: Instance créée et initialisée.");
  }

  // Getter public pour que les dashboards puissent vérifier (optionnel)
  String? get kitPhoneNumberForListening => _internalKitPhoneNumberForListening;

  // Stockage interne du numéro, pour éviter des appels DB constants si le getter est utilisé
  String? _internalKitPhoneNumberForListening;


  Future<bool> _requestSmsPermissions() async {
    // Demander les permissions SEND, RECEIVE, READ SMS
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms, // Englobe généralement send, read, receive pour la demande initiale
      // On pourrait demander Permission.receiveSms et Permission.readSms spécifiquement
      // mais Permission.sms est souvent suffisant pour la demande initiale.
      // La vérification du statut peut être plus granulaire.
    ].request();

    PermissionStatus? smsStatus = statuses[Permission.sms];

    if (smsStatus != null && smsStatus.isGranted) {
      print("SmsService: Permission SMS (globale) accordée.");
      return true;
    } else {
      print("SmsService: Permission SMS refusée (status: $smsStatus).");
      if (smsStatus != null && smsStatus.isPermanentlyDenied) {
        print("SmsService: Permission SMS refusée de manière permanente. Ouvrir les paramètres.");
        await openAppSettings(); 
      }
      return false;
    }
  }

  Future<void> sendSms(String phoneNumber, String message) async {
    if (phoneNumber.isEmpty || message.isEmpty) {
      print("SmsService: Numéro ou message vide pour sendSms. Annulé.");
      throw Exception("Numéro de téléphone ou message vide.");
    }

    bool permissionGranted = await _requestSmsPermissions();
    if (!permissionGranted) {
      print("SmsService: sendSms - Permission non accordée. Annulé.");
      throw Exception("Permission SMS non accordée pour l'envoi.");
    }

    try {
      SmsMessage sms = SmsMessage(phoneNumber, message);
      // Annuler toute souscription précédente à l'état d'envoi pour ce message spécifique
      // si on ne veut pas accumuler les listeners. Pour un message unique, c'est ok.
      // Si vous voulez un suivi global de tous les envois, il faudrait une autre approche.
      _smsSendStateSubscription?.cancel(); // Annuler si un précédent existait (peu probable ici)
      _smsSendStateSubscription = sms.onStateChanged.listen((SmsMessageState state) {
        print('SmsService: État envoi SMS pour $phoneNumber: $state');
      });

      print("SmsService: Tentative d'envoi du SMS '$message' à '$phoneNumber'...");
      await _sender.sendSms(sms);
      print("SmsService: Commande d'envoi SMS initiée pour '$message' à '$phoneNumber'.");
    } catch (e) {
      print("SmsService: Erreur lors de l'envoi du SMS: $e");
      _smsSendStateSubscription?.cancel(); // Nettoyer en cas d'erreur aussi
      throw Exception("Erreur lors de l'envoi du SMS: ${e.toString()}");
    }
  }

  Future<void> initializeKitPhoneNumberForListening() async {
    print("SmsService: initializeKitPhoneNumberForListening - DÉBUT");
    Kit? kit = await DatabaseHelper.instance.getKit();
    if (kit != null && kit.kitNumber.isNotEmpty) {
      _internalKitPhoneNumberForListening = kit.kitNumber;
      print("SmsService: Numéro du kit pour l'écoute configuré à: $_internalKitPhoneNumberForListening");
    } else {
      _internalKitPhoneNumberForListening = null;
      print("SmsService: Numéro du kit pour l'écoute non trouvé ou vide en DB.");
    }
  }

  void startListeningForMessages() async {
    print("SmsService: startListeningForMessages - DÉBUT");
    if (_internalKitPhoneNumberForListening == null || _internalKitPhoneNumberForListening!.isEmpty) {
      print("SmsService: startListeningForMessages - Numéro du kit non initialisé, tentative...");
      await initializeKitPhoneNumberForListening(); // S'assurer qu'il est chargé
      if (_internalKitPhoneNumberForListening == null || _internalKitPhoneNumberForListening!.isEmpty) {
          print("SmsService: startListeningForMessages - Écoute impossible, numéro de kit toujours non disponible.");
          return;
      }
    }

    bool permGranted = await _requestSmsPermissions();
    if (!permGranted) { 
      print("SmsService: startListeningForMessages - Écoute impossible, permission SMS non accordée.");
      return; 
    }

    await stopListening(); // S'assurer qu'il n'y a pas d'écoute précédente active

    if (_receiver.onSmsReceived == null) {
        print("SmsService ERREUR GRAVE: _receiver.onSmsReceived est null. Le plugin sms_advanced ne fonctionne pas correctement.");
        return;
    }

    print("SmsService: startListeningForMessages - Abonnement à onSmsReceived...");
    _smsEventSubscription = _receiver.onSmsReceived!.listen(
      (SmsMessage message) {
        // Ce print est crucial pour voir si le callback Dart est même atteint
        print("SmsService (DART CALLBACK): SMS reçu de ${message.address} - Corps: ${message.body}");
        
        // Normaliser les numéros de téléphone pour la comparaison (retirer les + indicatifs pays etc. si besoin)
        // Pour l'instant, comparaison directe.
        String? senderAddress = message.address;
        if (senderAddress != null && _internalKitPhoneNumberForListening != null) {
            // Simplification de la comparaison de numéros (peut nécessiter une normalisation plus robuste)
            String normalizedSender = senderAddress.replaceAll(RegExp(r'[^0-9]'), '');
            String normalizedKitNumber = _internalKitPhoneNumberForListening!.replaceAll(RegExp(r'[^0-9]'), '');

            if (normalizedSender.endsWith(normalizedKitNumber) || normalizedKitNumber.endsWith(normalizedSender)) {
                 print("SmsService (DART CALLBACK): SMS pertinent reçu du kit (numéro match: $senderAddress vs $_internalKitPhoneNumberForListening) - Corps: ${message.body}");
                if (message.body != null && message.body!.isNotEmpty) {
                    _processIncomingSms(message.body!);
                } else {
                    print("SmsService (DART CALLBACK): Corps du SMS du kit est vide.");
                }
            } else {
                 print("SmsService (DART CALLBACK): SMS reçu de $senderAddress, mais ne correspond pas au kitNumber $_internalKitPhoneNumberForListening.");
            }
        }
      }, 
      onError: (dynamic error) {
        print("SmsService (DART CALLBACK): Erreur dans le stream de réception SMS: $error");
        // Envisager de redémarrer l'écoute après un délai ?
      },
      onDone: () {
        print("SmsService (DART CALLBACK): Stream de réception SMS terminé (onDone).");
        // L'écoute s'est arrêtée, peut-être la redémarrer si ce n'est pas intentionnel.
      }
    );

    print("SmsService: Écoute des SMS effectivement démarrée pour le numéro (filtré en Dart): $_internalKitPhoneNumberForListening");
  }

  Future<void> _processIncomingSms(String smsBody) async {
    print("SmsService: _processIncomingSms - DÉBUT pour SMS: $smsBody");
    bool dataActuallyUpdated = false;
    Kit? currentKit = await DatabaseHelper.instance.getKit();
    List<String> parts = smsBody.split(';');
    DateTime now = DateTime.now();

    try {
      if (parts.isNotEmpty) {
        String commandType = parts[0].trim().toUpperCase();
        print("SmsService: _processIncomingSms - Type de commande détecté: $commandType");

        if (commandType == "GLOBAL_KIT_DATA" && parts.length >= 5) {
          if (currentKit == null) {
            print("SmsService: _processIncomingSms - Kit non configuré, impossible de traiter GLOBAL_KIT_DATA.");
            return;
          }
          double? newGlobalConsumption = double.tryParse(parts[2].trim());
          int? newGlobalImpulses = int.tryParse(parts[4].trim());
          print("SmsService: _processIncomingSms - GLOBAL_KIT_DATA parsé: Conso=$newGlobalConsumption, Imp=$newGlobalImpulses");

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
            print("SmsService: _processIncomingSms - Données Kit Globales mises à jour en DB.");
            dataActuallyUpdated = true;
          }

          if (newGlobalConsumption != null && newGlobalImpulses != null) {
            await DatabaseHelper.instance.insertConsumptionDataPoint(
              ConsumptionDataPoint(timestamp: now, consumption: newGlobalConsumption, impulses: newGlobalImpulses)
            );
            print("SmsService: _processIncomingSms - Point de consommation globale enregistré.");
            dataActuallyUpdated = true; 
          }
        } 
        else if (commandType == "RELAY_DATA" && parts.length >= 4) {
          String relayIdentifier = parts[1].trim();
          double? newRelayConsumption = double.tryParse(parts[3].trim());
          print("SmsService: _processIncomingSms - RELAY_DATA parsé: Relais=$relayIdentifier, Conso=$newRelayConsumption");

          if (relayIdentifier.isNotEmpty && newRelayConsumption != null) {
            Relay? relayToUpdate = await DatabaseHelper.instance.getRelayByIdentifier(relayIdentifier);
            if (relayToUpdate != null) {
              if (newRelayConsumption != relayToUpdate.currentRelayConsumption) {
                relayToUpdate.currentRelayConsumption = newRelayConsumption;
                await DatabaseHelper.instance.updateRelay(relayToUpdate);
                print("SmsService: _processIncomingSms - Consommation du relais '$relayIdentifier' mise à jour à $newRelayConsumption.");
                dataActuallyUpdated = true;
              }
              await DatabaseHelper.instance.insertRelayConsumptionDataPoint(
                RelayConsumptionDataPoint(relayIdentificateur: relayIdentifier, timestamp: now, consumption: newRelayConsumption)
              );
              print("SmsService: _processIncomingSms - Point de conso pour relais '$relayIdentifier' enregistré.");
              dataActuallyUpdated = true;
            } else {
              print("SmsService: _processIncomingSms - Relais '$relayIdentifier' non trouvé pour MàJ conso.");
            }
          } else {
            print("SmsService: _processIncomingSms - Données pour RELAY_DATA invalides: Identifiant ou Conso manquants.");
          }
        }
        else {
          print("SmsService: _processIncomingSms - Format SMS non reconnu: $smsBody");
        }
      }
    } catch (e, s) {
      print("SmsService: _processIncomingSms - ERREUR: $e");
      print("SmsService: _processIncomingSms - Stacktrace: $s");
    }

    if (dataActuallyUpdated) {
      print("SmsService: _processIncomingSms - Données mises à jour, appel de onKitDataUpdated et notifyListeners.");
      onKitDataUpdated?.call(); 
      notifyListeners(); 
    } else {
      print("SmsService: _processIncomingSms - Aucune donnée pertinente mise à jour pour SMS: $smsBody");
    }
    print("SmsService: _processIncomingSms - FIN");
  }
  
  Future<void> stopListening() async {
    print("SmsService: stopListening - Tentative d'arrêt de l'écoute.");
    if (_smsEventSubscription != null) {
      await _smsEventSubscription!.cancel();
      _smsEventSubscription = null;
      print("SmsService: Écoute des SMS effectivement arrêtée.");
    } else {
      print("SmsService: Pas d'écoute active à arrêter.");
    }
  }

  @override
  void dispose() {
    print("SmsService: dispose - Appel de stopListening.");
    stopListening(); 
    super.dispose();
  }
}