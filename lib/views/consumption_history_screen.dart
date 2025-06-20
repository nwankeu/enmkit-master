// lib/views/consumption_history_screen.dart

import 'package:flutter/material.dart';
import 'package:enmkit_fresh_start/services/database_helper.dart'; // Pour ConsumptionDataPoint
import 'package:fl_chart/fl_chart.dart'; // Pour le graphique
import 'package:intl/intl.dart'; // Pour formater les dates


class ConsumptionHistoryScreen extends StatefulWidget {
  const ConsumptionHistoryScreen({super.key});

  @override
  _ConsumptionHistoryScreenState createState() => _ConsumptionHistoryScreenState();
}

class _ConsumptionHistoryScreenState extends State<ConsumptionHistoryScreen> {
  List<ConsumptionDataPoint> _historyData = [];
  List<FlSpot> _spots = [];
  bool _isLoading = true;
  double _minY = 0, _maxY = 10; // Pour l'échelle du graphique

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    try {
      // Récupérer les 30 derniers points par exemple
      final data = await DatabaseHelper.instance.getConsumptionHistory(limit: 30); 
      final List<FlSpot> chartSpots = [];
      if (data.isNotEmpty) {
        for (int i = 0; i < data.length; i++) {
          // Utiliser un index pour l'axe X pour un espacement régulier
          // La valeur Y est la consommation.
          chartSpots.add(FlSpot(i.toDouble(), data[i].consumption));
        }
        // Calculer min/max pour l'échelle Y du graphique
        _minY = data.map((p) => p.consumption).reduce((a, b) => a < b ? a : b);
        _maxY = data.map((p) => p.consumption).reduce((a, b) => a > b ? a : b);
        _minY = (_minY * 0.9).floorToDouble().clamp(0, double.infinity); // Marge et s'assurer non négatif
        _maxY = (_maxY * 1.1).ceilToDouble();
        if (_minY >= _maxY) _maxY = _minY + 5.0; // Assurer un intervalle
        if (_minY == _maxY && _minY == 0) _maxY = 10; // Cas où tout est à 0

      } else {
         _minY = 0; _maxY = 10; // Valeurs par défaut si pas de données
      }

      if (mounted) {
        setState(() {
          _historyData = data; // Stocker les données brutes si besoin pour tooltips etc.
          _spots = chartSpots.isNotEmpty ? chartSpots : [const FlSpot(0,0)]; // Au moins un point pour le graphique
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erreur chargement historique de consommation globale: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur chargement historique: ${e.toString()}")),
        );
      }
    }
  }

  Widget _buildChart(BuildContext context) {
    final theme = Theme.of(context);
    if (_spots.isEmpty || _spots.length < 2) { // Besoin d'au moins 2 points pour une ligne
      return const Center(child: Text("Données insuffisantes pour afficher le graphique."));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_spots.length - 1).toDouble().clamp(0, double.infinity),
        minY: _minY,
        maxY: _maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: (_maxY - _minY > 0) ? ((_maxY - _minY)/5).clamp(1,double.infinity) : 1,
          verticalInterval: (_spots.length > 1) ? ((_spots.length -1)/5).clamp(1, double.infinity) : 1,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white24.withOpacity(0.2), strokeWidth: 0.5),
          getDrawingVerticalLine: (value) => FlLine(color: Colors.white24.withOpacity(0.2), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: (_spots.length > 5) ? (_spots.length / 5).floorToDouble().clamp(1,double.infinity) : 1,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index >= 0 && index < _historyData.length) {
                  return SideTitleWidget(axisSide: meta.axisSide, space: 4, child: Text(DateFormat('dd/MM\nHH:mm').format(_historyData[index].timestamp), style: TextStyle(color: Colors.white70, fontSize: 10)));
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max && meta.min != meta.max) return const Text(''); 
                return Padding(padding: const EdgeInsets.only(left: 4.0) ,child: Text(value.toStringAsFixed(1), style: TextStyle(color: Colors.white70, fontSize: 10)));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: Colors.white30.withOpacity(0.5), width: 1)),
        lineBarsData: [
          LineChartBarData(
            spots: _spots,
            isCurved: true,
            color: theme.colorScheme.secondary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: _spots.length < 20),
            belowBarData: BarAreaData(show: true, color: theme.colorScheme.secondary.withOpacity(0.2)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.blueGrey.shade700.withOpacity(0.9),
            getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
              return touchedBarSpots.map((barSpot) {
                final flSpot = barSpot;
                if (flSpot.spotIndex < 0 || flSpot.spotIndex >= _historyData.length) return null;
                final dataPoint = _historyData[flSpot.spotIndex]; // Utiliser _historyData pour les infos du tooltip
                return LineTooltipItem(
                    '${dataPoint.consumption.toStringAsFixed(2)} kWh\n',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    children: [
                      TextSpan(
                        text: DateFormat('dd/MM/yy HH:mm').format(dataPoint.timestamp),
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.normal),
                      ),
                      TextSpan(
                        text: '\nImp: ${dataPoint.impulses}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.normal),
                      ),
                    ],
                    textAlign: TextAlign.left);
              }).where((element) => element != null).toList().cast<LineTooltipItem>();
            }
          )
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique Consommation Globale'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _historyData.isEmpty 
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        "Aucune donnée d'historique de consommation globale n'est encore disponible.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[400]),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(), // Pour que RefreshIndicator fonctionne
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Évolution de la consommation du kit",
                          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          height: 300,
                          padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10), // Ajuster pour les labels
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color?.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _buildChart(context),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Détails des relevés :",
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _historyData.length, // Afficher dans l'ordre inverse (plus récent en haut)
                          itemBuilder: (context, index) {
                            final dataPoint = _historyData.reversed.toList()[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: Icon(Icons.timeline, color: theme.colorScheme.secondary),
                                title: Text('${dataPoint.consumption.toStringAsFixed(2)} kWh', style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Le ${DateFormat('dd/MM/yyyy HH:mm:ss').format(dataPoint.timestamp)} - Imp: ${dataPoint.impulses}'),
                              ),
                            );
                          },
                        )
                      ],
                    ),
                  ),
      ),
    );
  }
}