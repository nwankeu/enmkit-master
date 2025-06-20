// lib/views/relay_consumption_history_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart'; // Pour RelayConsumptionDataPoint
import 'package:intl/intl.dart'; // Pour formater les dates
import 'package:enmkit_fresh_start/models/relay_consumption_data_point.dart';

class RelayConsumptionHistoryScreen extends StatefulWidget {
  final String relayIdentifier;
  final String relayName;

  const RelayConsumptionHistoryScreen({
    super.key,
    required this.relayIdentifier,
    required this.relayName,
  });

  @override
  _RelayConsumptionHistoryScreenState createState() => _RelayConsumptionHistoryScreenState();
}

class _RelayConsumptionHistoryScreenState extends State<RelayConsumptionHistoryScreen> {
  List<RelayConsumptionDataPoint> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRelayHistory();
  }

  Future<void> _loadRelayHistory() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      // Charger un nombre significatif de points, par exemple les 100 derniers
      final data = await DatabaseHelper.instance.getRelayConsumptionHistory(widget.relayIdentifier, limit: 100); 
      if (mounted) {
        setState(() {
          _history = data.reversed.toList(); // Afficher le plus récent en premier dans la liste
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erreur chargement historique relais ${widget.relayIdentifier}: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur chargement historique: ${e.toString()}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Historique: ${widget.relayName}'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRelayHistory,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        "Aucune donnée d'historique de consommation pour le relais ${widget.relayName}.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[400]),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final dataPoint = _history[index]; // Déjà inversé dans _loadRelayHistory
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: Icon(Icons.show_chart_outlined, color: theme.colorScheme.secondary),
                          title: Text(
                            'Consommation: ${dataPoint.consumption.toStringAsFixed(2)} kWh',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Le ${DateFormat('dd/MM/yyyy HH:mm:ss').format(dataPoint.timestamp)}',
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}