import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'placement.dart';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

const String googleApiKey = "AIzaSyCHaP9sj9RqhaRVxa2DCHEDRymDVrpIUV0";
const String csvAssetFile = 'assets/EVCS_INDIA_NEW.csv';

const double maxSourceToStationKm = 30.0;
const double routeCorridorDetourKm = 25.0;
const int topKStations = 5;

const List<double> markerHues = <double>[
  BitmapDescriptor.hueGreen,
  BitmapDescriptor.hueGreen,
  BitmapDescriptor.hueGreen,
  BitmapDescriptor.hueGreen,
  BitmapDescriptor.hueGreen,
];

const double maxRoadDetourKm = 20.0;
const double maxPolylineCorridorKm = 10.0;
const double onRoutePolylineKm = 4.0;
const double onRouteRoadDetourKm = 8.0;
const double distinctAlgoMinSeparationKm = 6.0;

const Map<String, Map<String, Map<String, double>>> vehicleSpecs = {
  "Bike": {
    "Ather 450X": {"battery_kwh": 3.7, "consumption_kwh_per_km": 0.04},
    "Ola S1 Pro": {"battery_kwh": 4.0, "consumption_kwh_per_km": 0.045},
    "TVS iQube": {"battery_kwh": 3.4, "consumption_kwh_per_km": 0.04},
    "Bajaj Chetak EV": {"battery_kwh": 3.2, "consumption_kwh_per_km": 0.04},
  },
  "Car": {
    "Tata Nexon EV": {"battery_kwh": 30.2, "consumption_kwh_per_km": 0.14},
    "MG ZS EV": {"battery_kwh": 50.3, "consumption_kwh_per_km": 0.17},
    "Hyundai Kona EV": {"battery_kwh": 39.2, "consumption_kwh_per_km": 0.15},
    "Mahindra XUV400": {"battery_kwh": 39.4, "consumption_kwh_per_km": 0.16},
  },
};

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EV Charging Station Finder',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D6EFD),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF0D6EFD), width: 1.4),
          ),
          labelStyle: const TextStyle(color: Colors.black54),
          hintStyle: const TextStyle(color: Colors.black45),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D6EFD),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0D6EFD),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF0D6EFD),
          thumbColor: Color(0xFF0D6EFD),
          inactiveTrackColor: Color(0xFFD9E5FF),
          overlayColor: Color(0x290D6EFD),
          valueIndicatorColor: Color(0xFF0D6EFD),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFE8F0FF),
          disabledColor: Colors.grey.shade200,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          labelStyle: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF0D6EFD),
          unselectedLabelColor: Colors.black54,
          indicatorColor: Color(0xFF0D6EFD),
          dividerColor: Colors.transparent,
          labelStyle: TextStyle(fontWeight: FontWeight.w600),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8F0FF),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Color(0xFF0D6EFD),
                fontWeight: FontWeight.w600,
              );
            }
            return const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            );
          }),
        ),
      ),
      home: const EVMetaComparisonPage(),
    );
  }
}

class StationData {
  final int? stationId;
  final String name;
  final String address;
  final String city;
  final String state;
  final String chargerType;
  final double latitude;
  final double longitude;

  const StationData({
    required this.stationId,
    required this.name,
    required this.address,
    required this.city,
    required this.state,
    required this.chargerType,
    required this.latitude,
    required this.longitude,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  String get dedupeKey =>
      '${stationId ?? -1}|$name|$address|$city|$state|$chargerType|$latitude|$longitude';
}

class RouteResult {
  final bool ok;
  final String message;
  final double? distanceKm;
  final double? durationMin;
  final List<LatLng> geometry;

  const RouteResult({
    required this.ok,
    required this.message,
    required this.distanceKm,
    required this.durationMin,
    required this.geometry,
  });
}

class GeocodeResult {
  final bool ok;
  final LatLng? coords;
  final String message;

  const GeocodeResult({
    required this.ok,
    required this.coords,
    required this.message,
  });
}

class CandidateStation {
  final int? stationId;
  final String stationName;
  final String address;
  final String city;
  final String state;
  final double latitude;
  final double longitude;
  final String chargerType;
  final double chargerPowerKw;
  final double sourceConstraintLimitKm;
  final double maxReachableBeforeChargeKm;
  final double distanceSourceToStationKm;
  final double distanceStationToDestinationKm;
  final double totalRouteViaStationKm;
  final double detourDistanceKm;
  final double corridorDetourAirKm;
  final String routePreference;
  final double energyUsedToReachEvcsKwh;
  final double arrivalEnergyAtEvcsKwh;
  final double arrivalSocAtEvcsPercent;
  final double targetChargingLevelPercent;
  final double targetEnergyAtEvcsKwh;
  final double energyNeededToChargeKwh;
  final double chargingTimeMin;
  final double totalTripDurationMin;
  final double postChargeEnergyKwh;
  final double postChargeSocPercent;
  final double postChargeReachKm;
  final String canReachDestinationAfterCharge;
  final RouteResult route1;
  final RouteResult route2;
  final String explanation;
  final double fitnessScore;

  const CandidateStation({
    required this.stationId,
    required this.stationName,
    required this.address,
    required this.city,
    required this.state,
    required this.latitude,
    required this.longitude,
    required this.chargerType,
    required this.chargerPowerKw,
    required this.sourceConstraintLimitKm,
    required this.maxReachableBeforeChargeKm,
    required this.distanceSourceToStationKm,
    required this.distanceStationToDestinationKm,
    required this.totalRouteViaStationKm,
    required this.detourDistanceKm,
    required this.corridorDetourAirKm,
    required this.routePreference,
    required this.energyUsedToReachEvcsKwh,
    required this.arrivalEnergyAtEvcsKwh,
    required this.arrivalSocAtEvcsPercent,
    required this.targetChargingLevelPercent,
    required this.targetEnergyAtEvcsKwh,
    required this.energyNeededToChargeKwh,
    required this.chargingTimeMin,
    required this.totalTripDurationMin,
    required this.postChargeEnergyKwh,
    required this.postChargeSocPercent,
    required this.postChargeReachKm,
    required this.canReachDestinationAfterCharge,
    required this.route1,
    required this.route2,
    required this.explanation,
    required this.fitnessScore,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  CandidateStation copyWith({
    String? stationName,
    double? distanceSourceToStationKm,
    double? totalRouteViaStationKm,
    double? chargingTimeMin,
    double? totalTripDurationMin,
    String? explanation,
    double? fitnessScore,
  }) {
    return CandidateStation(
      stationId: stationId,
      stationName: stationName ?? this.stationName,
      address: address,
      city: city,
      state: state,
      latitude: latitude,
      longitude: longitude,
      chargerType: chargerType,
      chargerPowerKw: chargerPowerKw,
      sourceConstraintLimitKm: sourceConstraintLimitKm,
      maxReachableBeforeChargeKm: maxReachableBeforeChargeKm,
      distanceSourceToStationKm: distanceSourceToStationKm ?? this.distanceSourceToStationKm,
      distanceStationToDestinationKm: distanceStationToDestinationKm,
      totalRouteViaStationKm: totalRouteViaStationKm ?? this.totalRouteViaStationKm,
      detourDistanceKm: detourDistanceKm,
      corridorDetourAirKm: corridorDetourAirKm,
      routePreference: routePreference,
      energyUsedToReachEvcsKwh: energyUsedToReachEvcsKwh,
      arrivalEnergyAtEvcsKwh: arrivalEnergyAtEvcsKwh,
      arrivalSocAtEvcsPercent: arrivalSocAtEvcsPercent,
      targetChargingLevelPercent: targetChargingLevelPercent,
      targetEnergyAtEvcsKwh: targetEnergyAtEvcsKwh,
      energyNeededToChargeKwh: energyNeededToChargeKwh,
      chargingTimeMin: chargingTimeMin ?? this.chargingTimeMin,
      totalTripDurationMin: totalTripDurationMin ?? this.totalTripDurationMin,
      postChargeEnergyKwh: postChargeEnergyKwh,
      postChargeSocPercent: postChargeSocPercent,
      postChargeReachKm: postChargeReachKm,
      canReachDestinationAfterCharge: canReachDestinationAfterCharge,
      route1: route1,
      route2: route2,
      explanation: explanation ?? this.explanation,
      fitnessScore: fitnessScore ?? this.fitnessScore,
    );
  }

  Map<String, dynamic> toDisplayMap() {
    return {
      'Station ID': stationId,
      'Station Name': stationName,
      'Address': address,
      'City': city,
      'State': state,
      'Latitude': latitude,
      'Longitude': longitude,
      'Charger Type': chargerType,
      'Charger Power (kW)': chargerPowerKw,
      'Source Constraint Limit (km)': sourceConstraintLimitKm,
      'Max Reachable Before Charge (km)': maxReachableBeforeChargeKm,
      'Distance Source -> Station (km)': distanceSourceToStationKm,
      'Distance Station -> Destination (km)': distanceStationToDestinationKm,
      'Total Route via Station (km)': totalRouteViaStationKm,
      'Detour Distance (km)': detourDistanceKm,
      'Corridor Detour Air (km)': corridorDetourAirKm,
      'Route Preference': routePreference,
      'Energy Used to Reach EVCS (kWh)': energyUsedToReachEvcsKwh,
      'Arrival Energy at EVCS (kWh)': arrivalEnergyAtEvcsKwh,
      'Arrival SOC at EVCS (%)': arrivalSocAtEvcsPercent,
      'Target Charging Level (%)': targetChargingLevelPercent,
      'Target Energy at EVCS (kWh)': targetEnergyAtEvcsKwh,
      'Energy Needed to Charge (kWh)': energyNeededToChargeKwh,
      'Charging Time (min)': chargingTimeMin,
      'Total Trip Duration (min)': totalTripDurationMin,
      'Post-Charge Energy (kWh)': postChargeEnergyKwh,
      'Post-Charge SOC (%)': postChargeSocPercent,
      'Post-Charge Reach (km)': postChargeReachKm,
      'Can Reach Destination After Charge': canReachDestinationAfterCharge,
      'Fitness Score': fitnessScore,
    };
  }
}

class AlgorithmResult {
  final String algorithm;
  final int? stationId;
  final String stationName;
  final String routePreference;
  final double sourceToStationKm;
  final double stationToDestinationKm;
  final double totalDistanceKm;
  final double detourKm;
  final double energySourceToStationKwh;
  final double chargingTimeMin;
  final double totalTripDurationMin;
  final double postChargeReachKm;
  final String canReachDestinationAfterCharge;
  final String explanation;
  final double fitnessScore;
  final CandidateStation bestCandidate;
  final List<double> convergenceHistory;
  final double executionTimeMs;
  final double detourEfficiencyRatio;

  const AlgorithmResult({
    required this.algorithm,
    required this.stationId,
    required this.stationName,
    required this.routePreference,
    required this.sourceToStationKm,
    required this.stationToDestinationKm,
    required this.totalDistanceKm,
    required this.detourKm,
    required this.energySourceToStationKwh,
    required this.chargingTimeMin,
    required this.totalTripDurationMin,
    required this.postChargeReachKm,
    required this.canReachDestinationAfterCharge,
    required this.explanation,
    required this.fitnessScore,
    required this.bestCandidate,
    this.convergenceHistory = const [],
    this.executionTimeMs = 0,
    this.detourEfficiencyRatio = 0,
  });

  AlgorithmResult copyWith({
    String? algorithm,
    int? stationId,
    String? stationName,
    String? routePreference,
    double? sourceToStationKm,
    double? stationToDestinationKm,
    double? totalDistanceKm,
    double? detourKm,
    double? energySourceToStationKwh,
    double? chargingTimeMin,
    double? totalTripDurationMin,
    double? postChargeReachKm,
    String? canReachDestinationAfterCharge,
    String? explanation,
    double? fitnessScore,
    CandidateStation? bestCandidate,
    List<double>? convergenceHistory,
    double? executionTimeMs,
    double? detourEfficiencyRatio,
  }) {
    return AlgorithmResult(
      algorithm: algorithm ?? this.algorithm,
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      routePreference: routePreference ?? this.routePreference,
      sourceToStationKm: sourceToStationKm ?? this.sourceToStationKm,
      stationToDestinationKm: stationToDestinationKm ?? this.stationToDestinationKm,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      detourKm: detourKm ?? this.detourKm,
      energySourceToStationKwh: energySourceToStationKwh ?? this.energySourceToStationKwh,
      chargingTimeMin: chargingTimeMin ?? this.chargingTimeMin,
      totalTripDurationMin: totalTripDurationMin ?? this.totalTripDurationMin,
      postChargeReachKm: postChargeReachKm ?? this.postChargeReachKm,
      canReachDestinationAfterCharge: canReachDestinationAfterCharge ?? this.canReachDestinationAfterCharge,
      explanation: explanation ?? this.explanation,
      fitnessScore: fitnessScore ?? this.fitnessScore,
      bestCandidate: bestCandidate ?? this.bestCandidate,
      convergenceHistory: convergenceHistory ?? this.convergenceHistory,
      executionTimeMs: executionTimeMs ?? this.executionTimeMs,
      detourEfficiencyRatio: detourEfficiencyRatio ?? this.detourEfficiencyRatio,
    );
  }
}

class MetaComparisonResult {
  final String? error;
  final LatLng sourceCoords;
  final LatLng destCoords;
  final String sourceGeocodeMessage;
  final String destGeocodeMessage;
  final double batteryKwh;
  final double consumption;
  final double availableEnergy;
  final double reserveEnergy;
  final double maxReachableKm;
  final double sourceStationLimitKm;
  final double targetSocPercent;
  final List<CandidateStation> candidates;
  final List<CandidateStation> top5;
  final List<AlgorithmResult> comparisonRows;
  final Map<String, CandidateStation> algoBest;
  final RouteResult routeDirect;
  final int tp;
  final int fp;
  final int fn;
  final int tn;
  final double accuracy;
  final double precision;
  final double recall;

  const MetaComparisonResult({
    required this.error,
    required this.sourceCoords,
    required this.destCoords,
    required this.sourceGeocodeMessage,
    required this.destGeocodeMessage,
    required this.batteryKwh,
    required this.consumption,
    required this.availableEnergy,
    required this.reserveEnergy,
    required this.maxReachableKm,
    required this.sourceStationLimitKm,
    required this.targetSocPercent,
    required this.candidates,
    required this.top5,
    required this.comparisonRows,
    required this.algoBest,
    required this.routeDirect,
    this.tp = 0,
    this.fp = 0,
    this.fn = 0,
    this.tn = 0,
    this.accuracy = 0,
    this.precision = 0,
    this.recall = 0,
  });
}

class EVMetaComparisonPage extends StatefulWidget {
  const EVMetaComparisonPage({super.key});

  @override
  State<EVMetaComparisonPage> createState() => _EVMetaComparisonPageState();
}

class _EVMetaComparisonPageState extends State<EVMetaComparisonPage>
    with TickerProviderStateMixin {
  final TextEditingController sourceController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  double targetSocPercent = 80.0;

  String selectedVehicleType = vehicleSpecs.keys.first;
  String selectedVehicleName =
      vehicleSpecs[vehicleSpecs.keys.first]!.keys.first;
  double? batteryPercent;

  bool isLoading = true;
  bool isRunning = false;
  String? loadingError;
  List<StationData> stations = const <StationData>[];
  MetaComparisonResult? result;
  PlacementResult? placementResult;
  String selectedPlacementAlgo = 'PSO-DS';

  GoogleMapController? mapController;
  late final TabController tabController;
  final Map<String, RouteResult> routeCache = <String, RouteResult>{};
  List<double> _latestHistory = [];
  final Map<String, GeocodeResult> geocodeCache = <String, GeocodeResult>{};
  final math.Random random = math.Random();
  final ScrollController tableScrollController1 = ScrollController();
  final ScrollController tableScrollController2 = ScrollController();

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 8, vsync: this);
    unawaited(loadData());
  }

  @override
  void dispose() {
    sourceController.dispose();
    destinationController.dispose();
    tabController.dispose();
    tableScrollController1.dispose();
    tableScrollController2.dispose();
    mapController?.dispose();
    super.dispose();
  }

  String capitalizeWords(String text) {
    if (text.isEmpty) return text;

    return text
        .toLowerCase()
        .split(' ')
        .map(
          (word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '',
        )
        .join(' ');
  }

  bool isSameOrNearbyStation(CandidateStation a, CandidateStation b) {
    if (a.stationId != null &&
        b.stationId != null &&
        a.stationId == b.stationId) {
      return true;
    }

    final d = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
    return d <= distinctAlgoMinSeparationKm;
  }

  CandidateStation? pickDistinctBest(
    List<CandidateStation> candidates,
    List<CandidateStation> alreadyPicked,
    int? Function(List<CandidateStation>) selector,
  ) {
    final filtered =
        candidates.where((c) {
          for (final used in alreadyPicked) {
            if (isSameOrNearbyStation(c, used)) return false;
          }
          return true;
        }).toList();

    if (filtered.isEmpty) return null;

    final idx = selector(filtered);
    if (idx == null) return null;
    return filtered[idx];
  }

  AlgorithmResult algoResultFromCandidate(String name, CandidateStation c) {
    return AlgorithmResult(
      algorithm: name,
      stationId: c.stationId,
      stationName: c.stationName,
      routePreference: c.routePreference,
      sourceToStationKm: c.distanceSourceToStationKm,
      stationToDestinationKm: c.distanceStationToDestinationKm,
      totalDistanceKm: c.totalRouteViaStationKm,
      detourKm: c.detourDistanceKm,
      energySourceToStationKwh: c.energyUsedToReachEvcsKwh,
      chargingTimeMin: c.chargingTimeMin, totalTripDurationMin: c.totalTripDurationMin,
      explanation: c.explanation,
      postChargeReachKm: c.postChargeReachKm,
      canReachDestinationAfterCharge: c.canReachDestinationAfterCharge,
      fitnessScore: c.fitnessScore,
      bestCandidate: c,
    );
  }

  double minDistanceToRouteKm(LatLng point, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return double.infinity;

    double best = double.infinity;
    for (final p in routePoints) {
      final d = haversineKm(
        point.latitude,
        point.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < best) best = d;
    }
    return best;
  }

  String stationAddressText(CandidateStation c) {
    final parts =
        <String>[
          c.address.trim(),
          c.city.trim(),
          c.state.trim(),
        ].where((e) => e.isNotEmpty).toList();

    if (parts.isEmpty) return 'Address not available';
    return parts.join(', ');
  }

  String stationNameText(CandidateStation c) {
    if (c.stationName.trim().isNotEmpty) return c.stationName.trim();
    if (c.address.trim().isNotEmpty) return c.address.trim();
    if (c.city.trim().isNotEmpty) return c.city.trim();
    if (c.stationId != null) return 'Station ID ${c.stationId}';
    return 'Unnamed Station';
  }


  List<PlacementStationInput> _allStationsForPlacement() {
    return stations
        .map(
          (s) => PlacementStationInput(
            id: (s.stationId ?? -1).toString(),
            name: s.name,
            address: s.address,
            position: LatLng(s.latitude, s.longitude),
          ),
        )
        .toList();
  }

  Future<void> loadData() async {
    try {
      final rawData = await rootBundle.loadString(csvAssetFile);
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(rawData);

      if (rows.isEmpty) {
        setState(() {
          loadingError = 'CSV file is empty.';
          isLoading = false;
        });
        return;
      }

      final header = rows.first.map((e) => e.toString().trim()).toList();
      final indexMap = <String, int>{};
      for (int i = 0; i < header.length; i++) {
        indexMap[header[i]] = i;
      }

      String readCell(List<dynamic> row, String key) {
        final normalizedKey = key.trim().toLowerCase();

        for (final entry in indexMap.entries) {
          if (entry.key.trim().toLowerCase() == normalizedKey) {
            final idx = entry.value;
            if (idx >= row.length) return '';
            return row[idx].toString().trim();
          }
        }

        return '';
      }

      final Set<String> seen = <String>{};
      final List<StationData> loaded = <StationData>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        final String nameRaw =
            readCell(row, 'Name').isNotEmpty
                ? readCell(row, 'Name')
                : readCell(row, 'Station Name').isNotEmpty
                ? readCell(row, 'Station Name')
                : readCell(row, 'Charging Station Name');

        final String name = normalizeText(nameRaw);
        final String address = normalizeText(readCell(row, 'Address'));
        final String city = capitalizeWords(
          normalizeText(readCell(row, 'City')),
        );
        final String state = normalizeText(readCell(row, 'State'));
        final String chargerType = normalizeText(readCell(row, 'Charger Type'));
        final double? latitude = double.tryParse(readCell(row, 'Latitude'));
        final double? longitude = double.tryParse(readCell(row, 'Longitude'));
        final int? stationId = int.tryParse(
          readCell(row, 'Charging Station ID').split('.').first,
        );

        if (latitude == null || longitude == null) {
          continue;
        }

        if (latitude < 6 || latitude > 38 || longitude < 68 || longitude > 98) {
          continue;
        }

        final station = StationData(
          stationId: stationId,
          name: name,
          address: address,
          city: city,
          state: state,
          chargerType: chargerType,
          latitude: latitude,
          longitude: longitude,
        );

        if (seen.add(station.dedupeKey)) {
          loaded.add(station);
        }
      }

      setState(() {
        stations = loaded;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        loadingError = 'Failed to load CSV: $e';
        isLoading = false;
      });
    }
  }

  String normalizeText(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty) return '';
    return text
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  double haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double degree) => degree * math.pi / 180.0;

  List<LatLng> decodePolyline(String encoded) {
    int index = 0;
    int lat = 0;
    int lng = 0;
    final List<LatLng> coordinates = <LatLng>[];

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      while (true) {
        final int b = encoded.codeUnitAt(index) - 63;
        index += 1;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) {
          break;
        }
      }
      final int dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      while (true) {
        final int b = encoded.codeUnitAt(index) - 63;
        index += 1;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) {
          break;
        }
      }
      final int dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      coordinates.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return coordinates;
  }

  double inferChargerPower(String chargerType) {
    final text = chargerType.trim().toLowerCase();
    if (text.contains('ultra')) return 100.0;
    if (text.contains('fast') ||
        text.contains('dc') ||
        text.contains('level 3')) {
      return 50.0;
    }
    if (text.contains('level 2')) return 7.4;
    if (text.contains('level 1')) return 3.3;
    // Default to 22.0kW for typical semi-fast urban/public chargers if unknown
    return 22.0;
  }

  List<double> normalize(List<double> values) {
    if (values.isEmpty) return <double>[];
    final vMin = values.reduce(math.min);
    final vMax = values.reduce(math.max);
    if ((vMax - vMin).abs() < 1e-9) {
      return List<double>.filled(values.length, 0.5);
    }
    return values.map((v) => (v - vMin) / (vMax - vMin)).toList();
  }

  Map<String, double>? getVehicleSpec(String vehicleType, String vehicleName) {
    return vehicleSpecs[vehicleType]?[vehicleName];
  }

  Future<GeocodeResult> googleGeocode(String placeName) async {
    final trimmed = placeName.trim();
    if (trimmed.isEmpty) {
      return const GeocodeResult(
        ok: false,
        coords: null,
        message: 'Empty place name',
      );
    }
    if (geocodeCache.containsKey(trimmed)) {
      return geocodeCache[trimmed]!;
    }

    final queries = <String>[
      trimmed,
      '$trimmed, India',
      '$trimmed, Tamil Nadu, India',
    ];

    for (final q in queries) {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': q,
        'key': googleApiKey,
        'components': 'country:IN',
      });

      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 25));
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] ?? 'UNKNOWN').toString();

        if (status == 'OK' &&
            data['results'] is List &&
            (data['results'] as List).isNotEmpty) {
          final first = (data['results'] as List).first as Map<String, dynamic>;
          final loc =
              (first['geometry'] as Map<String, dynamic>)['location']
                  as Map<String, dynamic>;
          final result = GeocodeResult(
            ok: true,
            coords: LatLng(
              (loc['lat'] as num).toDouble(),
              (loc['lng'] as num).toDouble(),
            ),
            message: 'Matched: ${first['formatted_address'] ?? q}',
          );
          geocodeCache[trimmed] = result;
          return result;
        }

        if (status == 'REQUEST_DENIED' ||
            status == 'OVER_DAILY_LIMIT' ||
            status == 'INVALID_REQUEST') {
          final result = GeocodeResult(
            ok: false,
            coords: null,
            message:
                'Google Geocoding API error: ${data['error_message'] ?? status}',
          );
          geocodeCache[trimmed] = result;
          return result;
        }
      } catch (e) {
        final result = GeocodeResult(
          ok: false,
          coords: null,
          message: 'Geocoding request failed: $e',
        );
        geocodeCache[trimmed] = result;
        return result;
      }
    }

    final result = GeocodeResult(
      ok: false,
      coords: null,
      message: 'Could not geocode location: $trimmed',
    );
    geocodeCache[trimmed] = result;
    return result;
  }

  Future<RouteResult> getGoogleRoute(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) async {
    final key = '$lat1,$lon1|$lat2,$lon2';
    if (routeCache.containsKey(key)) {
      return routeCache[key]!;
    }

    if (kIsWeb) {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$lon1,$lat1;$lon2,$lat2'
        '?overview=full&geometries=geojson&steps=false',
      );

      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 30));
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        if (data['code'] != 'Ok' ||
            data['routes'] == null ||
            (data['routes'] as List).isEmpty) {
          final result = RouteResult(
            ok: false,
            message: data['message']?.toString() ?? 'OSRM route failed',
            distanceKm: null,
            durationMin: null,
            geometry: const <LatLng>[],
          );
          routeCache[key] = result;
          return result;
        }

        final route = (data['routes'] as List).first as Map<String, dynamic>;
        final geometryMap = route['geometry'] as Map<String, dynamic>;
        final coords = geometryMap['coordinates'] as List;

        final points =
            coords.map((c) {
              final pair = c as List;
              return LatLng(
                (pair[1] as num).toDouble(),
                (pair[0] as num).toDouble(),
              );
            }).toList();

        final result = RouteResult(
          ok: points.isNotEmpty,
          message: points.isNotEmpty ? 'OK' : 'OSRM returned empty geometry',
          distanceKm: (route['distance'] as num).toDouble() / 1000.0,
          durationMin: (route['duration'] as num).toDouble() / 60.0,
          geometry: points,
        );

        routeCache[key] = result;
        return result;
      } catch (e) {
        final result = RouteResult(
          ok: false,
          message: 'OSRM error: $e',
          distanceKm: null,
          durationMin: null,
          geometry: const <LatLng>[],
        );
        routeCache[key] = result;
        return result;
      }
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '$lat1,$lon1',
      'destination': '$lat2,$lon2',
      'mode': 'driving',
      'key': googleApiKey,
      'alternatives': 'false',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['status'] != 'OK' ||
          data['routes'] == null ||
          (data['routes'] as List).isEmpty) {
        final result = RouteResult(
          ok: false,
          message:
              '${data['status'] ?? 'Directions API failed'} - ${data['error_message'] ?? ''}',
          distanceKm: null,
          durationMin: null,
          geometry: const <LatLng>[],
        );
        routeCache[key] = result;
        return result;
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final poly =
          ((route['overview_polyline'] as Map<String, dynamic>)['points'])
              .toString();

      final result = RouteResult(
        ok: true,
        message: 'OK',
        distanceKm:
            ((leg['distance'] as Map<String, dynamic>)['value'] as num)
                .toDouble() /
            1000.0,
        durationMin:
            ((leg['duration'] as Map<String, dynamic>)['value'] as num)
                .toDouble() /
            60.0,
        geometry: decodePolyline(poly),
      );

      routeCache[key] = result;
      return result;
    } catch (e) {
      final result = RouteResult(
        ok: false,
        message: e.toString(),
        distanceKm: null,
        durationMin: null,
        geometry: const <LatLng>[],
      );
      routeCache[key] = result;
      return result;
    }
  }

  Future<List<CandidateStation>> buildCandidateStations({
    required double sourceLat,
    required double sourceLon,
    required double destinationLat,
    required double destinationLon,
    required double batteryKwh,
    required double availableEnergy,
    required double reserveEnergy,
    required double consumption,
    required double targetSocPercent,
    required List<StationData> stationsData,
    int limitCandidates = 50,
  }) async {
    final maxReachableKm = math.max(
      0.0,
      (availableEnergy - reserveEnergy) / consumption,
    );

    final sourceLimitKm = math.min(maxSourceToStationKm, maxReachableKm);

    final targetEnergyAtStation = batteryKwh * (targetSocPercent / 100.0);

    final directAirKm = haversineKm(
      sourceLat,
      sourceLon,
      destinationLat,
      destinationLon,
    );

    final directRoute = await getGoogleRoute(
      sourceLat,
      sourceLon,
      destinationLat,
      destinationLon,
    );

    final List<LatLng> directGeometry = directRoute.geometry;
    final List<_AirCandidate> filtered = <_AirCandidate>[];

    for (final row in stationsData) {
      final airSourceStation = haversineKm(
        sourceLat,
        sourceLon,
        row.latitude,
        row.longitude,
      );

      final airStationDest = haversineKm(
        row.latitude,
        row.longitude,
        destinationLat,
        destinationLon,
      );

      if (airSourceStation > sourceLimitKm) continue;

      final corridorDetourAir = airSourceStation + airStationDest - directAirKm;

      final polylineDistanceKm =
          directGeometry.isNotEmpty
              ? minDistanceToRouteKm(row.latLng, directGeometry)
              : corridorDetourAir;

      final onCorridor = polylineDistanceKm <= maxPolylineCorridorKm;

      if (!onCorridor) continue;

      filtered.add(
        _AirCandidate(
          row: row,
          airDistSourceStation: airSourceStation,
          airDistStationDest: airStationDest,
          corridorDetourAirKm: corridorDetourAir,
          polylineDistanceKm: polylineDistanceKm,
          onCorridor: onCorridor,
        ),
      );
    }

    filtered.sort((a, b) {
      if (a.onCorridor != b.onCorridor) {
        return a.onCorridor ? -1 : 1;
      }

      final bySource = a.airDistSourceStation.compareTo(b.airDistSourceStation);
      if (bySource != 0) return bySource;

      return a.corridorDetourAirKm.compareTo(b.corridorDetourAirKm);
    });

    final limited = filtered.take(limitCandidates).toList();
    if (limited.isEmpty) return <CandidateStation>[];

    final directSourceDestKm =
        directRoute.ok && directRoute.distanceKm != null
            ? directRoute.distanceKm!
            : directAirKm;

    final avgSpeedKmH = 45.0;

    final List<CandidateStation> candidates = <CandidateStation>[];

    for (final item in limited) {
      final route1 = await getGoogleRoute(
        sourceLat,
        sourceLon,
        item.row.latitude,
        item.row.longitude,
      );

      if (!route1.ok || route1.geometry.isEmpty) {
        continue;
      }

      final sourceToStationKm = route1.distanceKm ?? item.airDistSourceStation;

      final route2 = await getGoogleRoute(
        item.row.latitude,
        item.row.longitude,
        destinationLat,
        destinationLon,
      );

      if (!route2.ok || route2.geometry.isEmpty) {
        continue;
      }

      final stationToDestKm = route2.distanceKm ?? item.airDistStationDest;

      final chargerPower = inferChargerPower(item.row.chargerType);

      final energyUsedToStation = sourceToStationKm * consumption;

      final arrivalEnergy = math.max(
        0.0,
        availableEnergy - energyUsedToStation,
      );

      final arrivalSocPercent =
          batteryKwh > 0 ? (arrivalEnergy / batteryKwh) * 100.0 : 0.0;

      final energyNeededToTarget = math.max(
        0.0,
        targetEnergyAtStation - arrivalEnergy,
      );

      final chargingTimeHr =
          chargerPower > 0 ? energyNeededToTarget / chargerPower : 0.0;

      final chargingTimeMin = chargingTimeHr * 60.0;

      final postChargeEnergy = arrivalEnergy + energyNeededToTarget;

      final postChargeSocPercent =
          batteryKwh > 0 ? (postChargeEnergy / batteryKwh) * 100.0 : 0.0;

      final usablePostChargeEnergy = math.max(
        0.0,
        postChargeEnergy - reserveEnergy,
      );

      final postChargeReachKm =
          consumption > 0 ? usablePostChargeEnergy / consumption : 0.0;

      final viaStationKm = sourceToStationKm + stationToDestKm;
      final driveTimeMin = (viaStationKm / avgSpeedKmH) * 60.0;
      final totalTripDurationMin = driveTimeMin + chargingTimeMin;
      final detourKm = math.max(0.0, viaStationKm - directSourceDestKm);

      if (detourKm > maxRoadDetourKm) {
        continue;
      }

      final isActuallyOnRoute =
          item.polylineDistanceKm <= onRoutePolylineKm &&
          detourKm <= onRouteRoadDetourKm;

      final canReachDestinationAfterCharge =
          postChargeReachKm >= stationToDestKm;

      candidates.add(
        CandidateStation(
          stationId: item.row.stationId,
          stationName: item.row.name,
          address: item.row.address,
          city: item.row.city,
          state: item.row.state,
          latitude: item.row.latitude,
          longitude: item.row.longitude,
          chargerType: item.row.chargerType,
          chargerPowerKw: _r2(chargerPower),
          sourceConstraintLimitKm: _r2(maxSourceToStationKm),
          maxReachableBeforeChargeKm: _r2(maxReachableKm),
          distanceSourceToStationKm: _r2(sourceToStationKm),
          distanceStationToDestinationKm: _r2(stationToDestKm),
          totalRouteViaStationKm: _r2(viaStationKm),
          detourDistanceKm: _r2(detourKm),
          corridorDetourAirKm: _r2(item.corridorDetourAirKm),
          routePreference:
              isActuallyOnRoute ? 'On Route' : 'Nearby Route Deviation',
          energyUsedToReachEvcsKwh: _r2(energyUsedToStation),
          arrivalEnergyAtEvcsKwh: _r2(arrivalEnergy),
          arrivalSocAtEvcsPercent: _r2(arrivalSocPercent),
          targetChargingLevelPercent: _r2(targetSocPercent),
          targetEnergyAtEvcsKwh: _r2(targetEnergyAtStation),
          energyNeededToChargeKwh: _r2(energyNeededToTarget),
          chargingTimeMin: _r2(chargingTimeMin),
          totalTripDurationMin: _r2(totalTripDurationMin),
          postChargeEnergyKwh: _r2(postChargeEnergy),
          postChargeSocPercent: _r2(postChargeSocPercent),
          postChargeReachKm: _r2(postChargeReachKm),
          canReachDestinationAfterCharge:
              canReachDestinationAfterCharge ? 'Yes' : 'No',
          route1: route1,
          route2: route2,
          explanation: '', // Will be populated in attachFitness
          fitnessScore: 0.0,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    return candidates;
  }

  List<double> fitnessValues(List<CandidateStation> candidates) {
    final d1 = normalize(
      candidates.map((c) => c.distanceSourceToStationKm).toList(),
    );
    final d2 = normalize(
      candidates.map((c) => c.distanceStationToDestinationKm).toList(),
    );
    final det = normalize(candidates.map((c) => c.detourDistanceKm).toList());
    final energy = normalize(candidates.map((c) => c.energyNeededToChargeKwh).toList());
    final time = normalize(candidates.map((c) => c.chargingTimeMin).toList());
    final routeBonus =
        candidates
            .map((c) => c.routePreference == 'On Route' ? 0.0 : 0.15)
            .toList();

    final List<double> fits = <double>[];
    for (int i = 0; i < candidates.length; i++) {
      double score =
          0.30 * d1[i] +
          0.25 * d2[i] +
          0.20 * det[i] +
          0.10 * energy[i] +
          0.10 * time[i] +
          routeBonus[i];
      if (candidates[i].canReachDestinationAfterCharge != 'Yes') {
        score += 10.0;
      }
      fits.add(score);
    }
    return fits;
  }

  List<CandidateStation> attachFitness(List<CandidateStation> candidates) {
    if (candidates.isEmpty) return [];

    final fits = fitnessValues(candidates);
    final List<CandidateStation> out = <CandidateStation>[];

    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final f = fits[i];

      // Generate a detailed explanation based on the candidate's profile
      final List<String> reasons = [];
      if (c.routePreference == 'On Route') {
        reasons.add('Conveniently located directly on the main route');
      }
      if (c.chargerPowerKw >= 25) {
        reasons.add('Equipped with a fast ${c.chargerPowerKw}kW charger, drastically reducing waiting time');
      } else {
        reasons.add('Uses a standard ${c.chargerPowerKw}kW charger');
      }

      if (c.detourDistanceKm <= 2.0) {
        reasons.add('minimal detour required');
      }

      final explanation = 'Selected as a top choice because it is ${reasons.join(", ")}. It offers a balanced fitness score of ${f.toStringAsFixed(3)} by optimizing both travel distance and charging efficiency.';

      out.add(c.copyWith(explanation: explanation, fitnessScore: _r6(f)));
    }
    return out;
  }

  int? psoDsSelectIndex(
    List<CandidateStation> candidates, {
    int swarmSize = 20,
    int iterations = 35,
    double w = 0.7,
    double c1 = 1.5,
    double c2 = 1.5,
  }) {
    final n = candidates.length;
    if (n == 0) return null;
    if (n == 1) return 0;

    final fits = fitnessValues(candidates);
    final particles = List<double>.generate(
      swarmSize,
      (_) => random.nextDouble() * (n - 1),
    );
    final velocities = List<double>.generate(
      swarmSize,
      (_) => (random.nextDouble() * 2) - 1,
    );

    final pbestPos = List<double>.from(particles);
    final List<double> pbestFit = <double>[];
    for (final p in particles) {
      final idx = _clampIndex(p.round(), n);
      pbestFit.add(fits[idx]);
    }

    int gbestIdx = 0;
    for (int i = 1; i < swarmSize; i++) {
      if (pbestFit[i] < pbestFit[gbestIdx]) {
        gbestIdx = i;
      }
    }
    double gbestPos = pbestPos[gbestIdx];
    double gbestFit = pbestFit[gbestIdx];

    _latestHistory = [];
    for (int iter = 0; iter < iterations; iter++) {
      for (int i = 0; i < swarmSize; i++) {
        final r1 = random.nextDouble();
        final r2 = random.nextDouble();
        velocities[i] =
            w * velocities[i] +
            c1 * r1 * (pbestPos[i] - particles[i]) +
            c2 * r2 * (gbestPos - particles[i]);

        final s =
            velocities[i].abs() < 60
                ? 1.0 / (1.0 + math.exp(-velocities[i]))
                : (velocities[i] > 0 ? 1.0 : 0.0);

        if (random.nextDouble() < s) {
          particles[i] += 1;
        } else {
          particles[i] -= 1;
        }

        particles[i] = particles[i].clamp(0.0, (n - 1).toDouble());
        final idx = _clampIndex(particles[i].round(), n);
        final currentFit = fits[idx];

        if (currentFit < pbestFit[i]) {
          pbestFit[i] = currentFit;
          pbestPos[i] = particles[i];
        }
        if (currentFit < gbestFit) {
          gbestFit = currentFit;
          gbestPos = particles[i];
        }
      }
      _latestHistory.add(gbestFit);
    }
    return _clampIndex(gbestPos.round(), n);
  }

  int? gaSelectIndex(
    List<CandidateStation> candidates, {
    int populationSize = 20,
    int generations = 40,
    double mutationRate = 0.15,
  }) {
    final n = candidates.length;
    if (n == 0) return null;
    if (n == 1) return 0;

    final fits = fitnessValues(candidates);

    int tournament() {
      final a = random.nextInt(n);
      int b = random.nextInt(n);
      while (b == a && n > 1) {
        b = random.nextInt(n);
      }
      return fits[a] < fits[b] ? a : b;
    }

    List<int> population = List<int>.generate(
      populationSize,
      (_) => random.nextInt(n),
    );

    _latestHistory = [];
    for (int gen = 0; gen < generations; gen++) {
      final List<int> newPopulation = <int>[];
      int elite = population.first;
      for (final idx in population) {
        if (fits[idx] < fits[elite]) {
          elite = idx;
        }
      }
      newPopulation.add(elite);
      _latestHistory.add(fits[elite]);

      while (newPopulation.length < populationSize) {
        final p1 = tournament();
        final p2 = tournament();
        int child = random.nextDouble() < 0.5 ? p1 : p2;
        if (random.nextDouble() < mutationRate) {
          child = random.nextInt(n);
        }
        newPopulation.add(child);
      }
      population = newPopulation;
    }

    int bestIdx = population.first;
    for (final idx in population) {
      if (fits[idx] < fits[bestIdx]) {
        bestIdx = idx;
      }
    }
    return bestIdx;
  }

  int? saSelectIndex(
    List<CandidateStation> candidates, {
    double initialTemp = 10.0,
    double cooling = 0.95,
    int iterations = 120,
  }) {
    final n = candidates.length;
    if (n == 0) return null;
    if (n == 1) return 0;

    final fits = fitnessValues(candidates);
    int current = random.nextInt(n);
    int best = current;
    double temp = initialTemp;
    _latestHistory = [];

    for (int i = 0; i < iterations; i++) {
      final neighbor = random.nextInt(n);
      final delta = fits[neighbor] - fits[current];
      if (delta < 0 ||
          random.nextDouble() < math.exp(-delta / math.max(temp, 1e-9))) {
        current = neighbor;
      }
      if (fits[current] < fits[best]) {
        best = current;
      }
      _latestHistory.add(fits[best]);
      temp *= cooling;
      if (temp < 1e-4) break;
    }
    return best;
  }

  AlgorithmResult? algoResult(
    String name,
    List<CandidateStation> candidates,
    int? idx,
  ) {
    if (idx == null) return null;
    final c = candidates[idx];
    return AlgorithmResult(
      algorithm: name,
      stationId: c.stationId,
      stationName: c.stationName,
      routePreference: c.routePreference,
      sourceToStationKm: c.distanceSourceToStationKm,
      stationToDestinationKm: c.distanceStationToDestinationKm,
      totalDistanceKm: c.totalRouteViaStationKm,
      detourKm: c.detourDistanceKm,
      energySourceToStationKwh: c.energyUsedToReachEvcsKwh,
      chargingTimeMin: c.chargingTimeMin, totalTripDurationMin: c.totalTripDurationMin,
      explanation: c.explanation,
      postChargeReachKm: c.postChargeReachKm,
      canReachDestinationAfterCharge: c.canReachDestinationAfterCharge,
      fitnessScore: c.fitnessScore,
      bestCandidate: c,
    );
  }

  Future<MetaComparisonResult> runMetaComparison({
    required String sourcePlace,
    required String destinationPlace,
    required String vehicleName,
    required String vehicleType,
    required double batteryPercent,
    required double targetSocPercent,
  }) async {
    final sourceGeo = await googleGeocode(sourcePlace);
    final destGeo = await googleGeocode(destinationPlace);

    if (!sourceGeo.ok) {
      return MetaComparisonResult(
        error: sourceGeo.message,
        sourceCoords: const LatLng(0, 0),
        destCoords: const LatLng(0, 0),
        sourceGeocodeMessage: sourceGeo.message,
        destGeocodeMessage: destGeo.message,
        batteryKwh: 0,
        consumption: 0,
        availableEnergy: 0,
        reserveEnergy: 0,
        maxReachableKm: 0,
        sourceStationLimitKm: 0,
        targetSocPercent: 0,
        candidates: const <CandidateStation>[],
        top5: const <CandidateStation>[],
        comparisonRows: const <AlgorithmResult>[],
        algoBest: const <String, CandidateStation>{},
        routeDirect: const RouteResult(
          ok: false,
          message: '',
          distanceKm: null,
          durationMin: null,
          geometry: <LatLng>[],
        ),
      );
    }

    if (!destGeo.ok) {
      return MetaComparisonResult(
        error: destGeo.message,
        sourceCoords: sourceGeo.coords!,
        destCoords: const LatLng(0, 0),
        sourceGeocodeMessage: sourceGeo.message,
        destGeocodeMessage: destGeo.message,
        batteryKwh: 0,
        consumption: 0,
        availableEnergy: 0,
        reserveEnergy: 0,
        maxReachableKm: 0,
        sourceStationLimitKm: 0,
        targetSocPercent: 0,
        candidates: const <CandidateStation>[],
        top5: const <CandidateStation>[],
        comparisonRows: const <AlgorithmResult>[],
        algoBest: const <String, CandidateStation>{},
        routeDirect: const RouteResult(
          ok: false,
          message: '',
          distanceKm: null,
          durationMin: null,
          geometry: <LatLng>[],
        ),
      );
    }

    final sourceCoords = sourceGeo.coords!;
    final destCoords = destGeo.coords!;
    final vehicle = getVehicleSpec(vehicleType, vehicleName);

    if (vehicle == null) {
      return MetaComparisonResult(
        error: 'No fixed vehicle spec found for $vehicleName / $vehicleType',
        sourceCoords: sourceCoords,
        destCoords: destCoords,
        sourceGeocodeMessage: sourceGeo.message,
        destGeocodeMessage: destGeo.message,
        batteryKwh: 0,
        consumption: 0,
        availableEnergy: 0,
        reserveEnergy: 0,
        maxReachableKm: 0,
        sourceStationLimitKm: 0,
        targetSocPercent: 0,
        candidates: const <CandidateStation>[],
        top5: const <CandidateStation>[],
        comparisonRows: const <AlgorithmResult>[],
        algoBest: const <String, CandidateStation>{},
        routeDirect: const RouteResult(
          ok: false,
          message: '',
          distanceKm: null,
          durationMin: null,
          geometry: <LatLng>[],
        ),
      );
    }

    final batteryKwh = vehicle['battery_kwh']!;
    final consumption = vehicle['consumption_kwh_per_km']!;
    final availableEnergy = batteryKwh * (batteryPercent / 100.0);
    final reserveEnergy = 0.0;
    final maxReachableKm = math.max(0.0, availableEnergy / consumption);

    final directRoute = await getGoogleRoute(
      sourceCoords.latitude,
      sourceCoords.longitude,
      destCoords.latitude,
      destCoords.longitude,
    );

    List<CandidateStation> candidates = await buildCandidateStations(
      sourceLat: sourceCoords.latitude,
      sourceLon: sourceCoords.longitude,
      destinationLat: destCoords.latitude,
      destinationLon: destCoords.longitude,
      batteryKwh: batteryKwh,
      availableEnergy: availableEnergy,
      reserveEnergy: reserveEnergy,
      consumption: consumption,
      targetSocPercent: targetSocPercent,
      stationsData: stations,
      limitCandidates: 50,
    );

    if (candidates.isEmpty) {
      return MetaComparisonResult(
        error: null,
        sourceCoords: sourceCoords,
        destCoords: destCoords,
        sourceGeocodeMessage: sourceGeo.message,
        destGeocodeMessage: destGeo.message,
        batteryKwh: batteryKwh,
        consumption: consumption,
        availableEnergy: availableEnergy,
        reserveEnergy: reserveEnergy,
        maxReachableKm: maxReachableKm,
        sourceStationLimitKm: 0,
        targetSocPercent: targetSocPercent,
        candidates: const <CandidateStation>[],
        top5: const <CandidateStation>[],
        comparisonRows: const <AlgorithmResult>[],
        algoBest: const <String, CandidateStation>{},
        routeDirect: directRoute,
      );
    }

    candidates = attachFitness(candidates);
    candidates.sort((a, b) => a.fitnessScore.compareTo(b.fitnessScore));
    final top5 = candidates.take(topKStations).toList();

    final List<CandidateStation> alreadyPicked = <CandidateStation>[];
    final sw = Stopwatch();

    sw.start();
    final psoBest = pickDistinctBest(
      candidates,
      alreadyPicked,
      (list) => psoDsSelectIndex(list),
    );
    sw.stop();
    final psoTime = sw.elapsedMicroseconds / 1000.0;
    final psoHistory = List<double>.from(_latestHistory);
    if (psoBest != null) {
      alreadyPicked.add(psoBest);
    }

    sw.reset();
    sw.start();
    final gaBest = pickDistinctBest(
      candidates,
      alreadyPicked,
      (list) => gaSelectIndex(list),
    );
    sw.stop();
    final gaTime = sw.elapsedMicroseconds / 1000.0;
    final gaHistory = List<double>.from(_latestHistory);
    if (gaBest != null) {
      alreadyPicked.add(gaBest);
    }

    sw.reset();
    sw.start();
    final saBest = pickDistinctBest(
      candidates,
      alreadyPicked,
      (list) => saSelectIndex(list),
    );
    sw.stop();
    final saTime = sw.elapsedMicroseconds / 1000.0;
    final saHistory = List<double>.from(_latestHistory);

    final List<AlgorithmResult> comparisonRows = <AlgorithmResult>[];

    // Add Direct Route Baseline
    if (directRoute.ok && directRoute.distanceKm != null) {
      final directDist = directRoute.distanceKm!;
      final directEnergy = directDist * consumption;
      final canReach = availableEnergy >= directEnergy;
      
      comparisonRows.add(AlgorithmResult(
        algorithm: 'Direct Trip (No Stop)',
        stationId: null,
        stationName: 'None',
        routePreference: 'Shortest',
        sourceToStationKm: directDist,
        stationToDestinationKm: 0,
        totalDistanceKm: directDist,
        detourKm: 0,
        energySourceToStationKwh: directEnergy,
        chargingTimeMin: 0,
        totalTripDurationMin: directRoute.durationMin ?? (directDist / 45.0 * 60.0),
        postChargeReachKm: (availableEnergy - directEnergy) / consumption,
        canReachDestinationAfterCharge: canReach ? 'YES' : 'NO (Out of Range)',
        explanation: canReach 
          ? 'You can reach your destination directly without stopping to charge.'
          : 'Warning: Your current battery is insufficient to reach the destination directly. A charging stop is REQUIRED.',
        fitnessScore: 0,
        bestCandidate: candidates.first.copyWith(
          stationName: 'No Station',
          distanceSourceToStationKm: directDist,
          totalRouteViaStationKm: directDist,
          chargingTimeMin: 0,
          totalTripDurationMin: directRoute.durationMin ?? (directDist / 45.0 * 60.0),
        ),
        convergenceHistory: [],
        executionTimeMs: 0,
        detourEfficiencyRatio: 0,
      ));
    }

    final Map<String, CandidateStation> algoBest = <String, CandidateStation>{};

    if (psoBest != null) {
      final der = psoBest.chargerPowerKw / (psoBest.detourDistanceKm + 0.1);
      final r = algoResultFromCandidate('PSO-DS', psoBest).copyWith(
        convergenceHistory: psoHistory,
        executionTimeMs: psoTime,
        detourEfficiencyRatio: der,
      );
      comparisonRows.add(r);
      algoBest[r.algorithm] = r.bestCandidate;
    }

    if (gaBest != null) {
      final der = gaBest.chargerPowerKw / (gaBest.detourDistanceKm + 0.1);
      final r = algoResultFromCandidate('Genetic Algorithm', gaBest).copyWith(
        convergenceHistory: gaHistory,
        executionTimeMs: gaTime,
        detourEfficiencyRatio: der,
      );
      comparisonRows.add(r);
      algoBest[r.algorithm] = r.bestCandidate;
    }

    if (saBest != null) {
      final der = saBest.chargerPowerKw / (saBest.detourDistanceKm + 0.1);
      final r = algoResultFromCandidate('Simulated Annealing', saBest).copyWith(
        convergenceHistory: saHistory,
        executionTimeMs: saTime,
        detourEfficiencyRatio: der,
      );
      comparisonRows.add(r);
      algoBest[r.algorithm] = r.bestCandidate;
    }

    // Advanced Stats: Confusion Matrix
    int tp = 0, fp = 0, fn = 0, tn = 0;
    for (final c in candidates) {
      final isActuallyReachable = c.canReachDestinationAfterCharge == 'Yes';
      final predictedReachable = c.fitnessScore < 4.0; 
      
      if (predictedReachable && isActuallyReachable) tp++;
      else if (predictedReachable && !isActuallyReachable) fp++;
      else if (!predictedReachable && isActuallyReachable) fn++;
      else tn++;
    }

    final total = candidates.length;
    final accuracy = total > 0 ? (tp + tn) / total : 0.0;
    final precision = (tp + fp) > 0 ? tp / (tp + fp) : 0.0;
    final recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0;

    return MetaComparisonResult(
      error: null,
      sourceCoords: sourceCoords,
      destCoords: destCoords,
      sourceGeocodeMessage: sourceGeo.message,
      destGeocodeMessage: destGeo.message,
      batteryKwh: batteryKwh,
      consumption: consumption,
      availableEnergy: availableEnergy,
      reserveEnergy: reserveEnergy,
      maxReachableKm: maxReachableKm,
      sourceStationLimitKm: maxSourceToStationKm,
      targetSocPercent: targetSocPercent,
      candidates: candidates,
      top5: top5,
      comparisonRows: comparisonRows,
      algoBest: algoBest,
      routeDirect: directRoute,
      tp: tp, fp: fp, fn: fn, tn: tn,
      accuracy: accuracy,
      precision: precision,
      recall: recall,
    );
  }

  Future<void> onRun() async {
    routeCache.clear();
    try {
      setState(() {
      isRunning = true;
      result = null;
      placementResult = null;
    });

    final res = await runMetaComparison(
      sourcePlace: sourceController.text,
      destinationPlace: destinationController.text,
      vehicleName: selectedVehicleName,
      vehicleType: selectedVehicleType,
      batteryPercent: batteryPercent!,
      targetSocPercent: targetSocPercent,
    );

    PlacementResult? placement;
    if (res.error == null && res.routeDirect.geometry.isNotEmpty) {
      placement = const PlacementService().runPlacementAnalysis(
        routePoints: res.routeDirect.geometry,
        existingStations: _allStationsForPlacement(),
        safeRangeKm: res.maxReachableKm,
        maxProposedStations: 3,
      );
    }

    setState(() {
      result = res;
      placementResult = placement;
      isRunning = false;
    });

    } catch (e, stack) {
      debugPrint("Error in onRun: $e");
      debugPrint(stack.toString());
      if (mounted) {
        setState(() => isRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<ui.Image> _createMarkerImage(Color color, double size) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    
    // Adjust canvas size to allow for the pin point and shadow
    final double canvasWidth = size;
    final double canvasHeight = size * 1.3;
    
    final ui.Paint paint = ui.Paint()..color = color;
    final ui.Paint shadowPaint = ui.Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final double centerX = canvasWidth / 2;
    final double radius = canvasWidth * 0.4;
    
    // 1. Draw Shadow
    final Path shadowPath = Path();
    shadowPath.moveTo(centerX + 1, canvasHeight - 2);
    shadowPath.quadraticBezierTo(centerX + radius + 1, radius + 1, centerX + radius + 1, radius + 1);
    shadowPath.arcToPoint(Offset(centerX - radius + 1, radius + 1), radius: Radius.circular(radius));
    shadowPath.quadraticBezierTo(centerX + 1, canvasHeight - 2, centerX + 1, canvasHeight - 2);
    canvas.drawPath(shadowPath, shadowPaint);

    // 2. Draw Teardrop Pin Shape
    final Path pinPath = Path();
    // Bottom point
    pinPath.moveTo(centerX, canvasHeight - 4);
    // Right side curve up to the top circle
    pinPath.quadraticBezierTo(centerX + radius, radius, centerX + radius, radius);
    // Top circle arc
    pinPath.arcToPoint(Offset(centerX - radius, radius), radius: Radius.circular(radius), clockwise: false);
    // Left side curve back down to the point
    pinPath.quadraticBezierTo(centerX, canvasHeight - 4, centerX, canvasHeight - 4);
    
    canvas.drawPath(pinPath, paint);

    // 3. Add a darker border for definition
    final ui.Paint borderPaint = ui.Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(pinPath, borderPaint);

    // 4. White inner dot
    canvas.drawCircle(Offset(centerX, radius), radius * 0.4, ui.Paint()..color = Colors.white.withOpacity(0.9));

    return await pictureRecorder.endRecording().toImage(canvasWidth.toInt(), canvasHeight.toInt());
  }

  Future<BitmapDescriptor> _getMarkerIcon(Color color, {double size = 45}) async {
    final img = await _createMarkerImage(color, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<Set<Marker>> createTop5Markers(MetaComparisonResult result) async {
    final Set<Marker> markers = <Marker>{};

    final sourceIcon = await _getMarkerIcon(Colors.green, size: 50);
    final destIcon = await _getMarkerIcon(Colors.red, size: 50);
    final rank1Icon = await _getMarkerIcon(Colors.purple, size: 45); // Magenta/Purple for preference 1
    final otherTopIcon = await _getMarkerIcon(Colors.cyan, size: 45); // Cyan for others

    markers.add(
      Marker(
        markerId: const MarkerId('source'),
        position: result.sourceCoords,
        infoWindow: const InfoWindow(title: 'Source'),
        icon: sourceIcon,
      ),
    );

    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: result.destCoords,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: destIcon,
      ),
    );

    for (int i = 0; i < result.top5.length; i++) {
      final cand = result.top5[i];

      markers.add(
        Marker(
          markerId: MarkerId('top_$i'),
          position: cand.latLng,
          infoWindow: InfoWindow(
            title: 'Rank ${i + 1}: ${stationNameText(cand)}',
            snippet:
                '${stationAddressText(cand)} | ${cand.routePreference} | '
                'Source→Station: ${cand.distanceSourceToStationKm} km | '
                'Req. Energy: ${cand.energyNeededToChargeKwh.toStringAsFixed(2)} kWh',
          ),
          icon: i == 0 ? rank1Icon : otherTopIcon,
        ),
      );
    }

    return markers;
  }

  Set<Polyline> createTop5Polylines(MetaComparisonResult result) {
    final Set<Polyline> polylines = <Polyline>{};

    if (result.routeDirect.geometry.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('direct_route_real'),
          points: result.routeDirect.geometry,
          width: 5,
          color: const Color(0xFF1A237E), // Navy Blue
        ),
      );
    } else {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('direct_route_fallback'),
          points: [result.sourceCoords, result.destCoords],
          width: 4,
          color: Colors.black54,
        ),
      );
    }

    for (int i = 0; i < result.top5.length; i++) {
      final cand = result.top5[i];
      final color = const Color(0xFF1A237E); // Consistent Navy Blue

      if (cand.route1.geometry.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('top_${i}_r1_real'),
            points: cand.route1.geometry,
            width: 5,
            color: color,
          ),
        );
      } else {
        polylines.add(
          Polyline(
            polylineId: PolylineId('top_${i}_r1_fallback'),
            points: [
              result.sourceCoords,
              LatLng(cand.latitude, cand.longitude),
            ],
            width: 3,
            color: color,
          ),
        );
      }

      if (cand.route2.geometry.isNotEmpty) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('top_${i}_r2_real'),
            points: cand.route2.geometry,
            width: 5,
            color: color,
          ),
        );
      } else {
        polylines.add(
          Polyline(
            polylineId: PolylineId('top_${i}_r2_fallback'),
            points: [LatLng(cand.latitude, cand.longitude), result.destCoords],
            width: 3,
            color: color,
          ),
        );
      }
    }

    return polylines;
  }

  Future<Set<Marker>> createPlacementMarkers(
    MetaComparisonResult result,
    PlacementResult placement,
  ) async {
    final Set<Marker> markers = <Marker>{};

    final sourceIcon = await _getMarkerIcon(Colors.green, size: 50);
    final destIcon = await _getMarkerIcon(Colors.red, size: 50);
    final existingIcon = await _getMarkerIcon(Colors.blue, size: 35);
    
    Color proposedColor = Colors.cyan;
    if (selectedPlacementAlgo == 'GA') proposedColor = Colors.purple;
    if (selectedPlacementAlgo == 'SA') proposedColor = Colors.orange;
    if (selectedPlacementAlgo == 'Greedy') proposedColor = Colors.yellow;
    final proposedIcon = await _getMarkerIcon(proposedColor, size: 48);

    markers.add(
      Marker(
        markerId: const MarkerId('source'),
        position: result.sourceCoords,
        infoWindow: const InfoWindow(title: 'Source'),
        icon: sourceIcon,
      ),
    );

    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: result.destCoords,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: destIcon,
      ),
    );

    for (final s in placement.usableExistingStationsOnRoute) {
      markers.add(
        Marker(
          markerId: MarkerId('usable_${s.id}'),
          position: s.position,
          icon: existingIcon,
          alpha: 0.6,
        ),
      );
    }

    final activeStations =
        placement.resultsByAlgorithm[selectedPlacementAlgo]?.stations ??
        placement.selectedStations;

    for (final s in activeStations) {
      markers.add(
        Marker(
          markerId: MarkerId('proposed_${s.id}'),
          position: s.position,
          infoWindow: InfoWindow(
            title: 'Found by $selectedPlacementAlgo: Spot ${s.rank}',
            snippet: s.reason,
          ),
          icon: proposedIcon,
        ),
      );
    }

    return markers;
  }

  Set<Polyline> createPlacementPolylines(
    MetaComparisonResult result,
    PlacementResult placement,
  ) {
    final Set<Polyline> polylines = <Polyline>{};

    if (result.routeDirect.geometry.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('placement_direct_route'),
          points: result.routeDirect.geometry,
          width: 5,
          color: const Color(0xFF1A237E), // Navy Blue
        ),
      );
    } else {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('placement_direct_route_fallback'),
          points: [result.sourceCoords, result.destCoords],
          width: 4,
          color: Colors.black54,
        ),
      );
    }

    for (int i = 0; i < placement.uncoveredGaps.length; i++) {
      final gap = placement.uncoveredGaps[i];
      polylines.add(
        Polyline(
          polylineId: PolylineId('gap_$i'),
          points: [gap.startPoint, gap.endPoint],
          width: 6,
          color: Colors.orange,
        ),
      );
    }

    return polylines;
  }

  Future<Set<Marker>> createSingleAlgoMarkers(
    MetaComparisonResult result,
    CandidateStation best,
    String title,
  ) async {
    final sourceIcon = await _getMarkerIcon(Colors.green, size: 50);
    final destIcon = await _getMarkerIcon(Colors.red, size: 50);
    
    Color proposedColor = Colors.cyan;
    if (title.contains('GA')) proposedColor = Colors.purple;
    if (title.contains('SA')) proposedColor = Colors.orange;
    final proposedIcon = await _getMarkerIcon(proposedColor, size: 50);

    return {
      Marker(
        markerId: const MarkerId('source'),
        position: result.sourceCoords,
        infoWindow: const InfoWindow(title: 'Source'),
        icon: sourceIcon,
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: result.destCoords,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: destIcon,
      ),
      Marker(
        markerId: MarkerId('${title}_station'),
        position: best.latLng,
        infoWindow: InfoWindow(
          title: '$title: ${stationNameText(best)}',
          snippet:
              '${stationAddressText(best)} | ${best.routePreference} | '
              'Total: ${best.totalRouteViaStationKm} km | '
              'Req. Energy: ${best.energyNeededToChargeKwh.toStringAsFixed(2)} kWh',
        ),
        icon: proposedIcon,
      ),
    };
  }

  Set<Polyline> createSingleAlgoPolylines(
    MetaComparisonResult result,
    CandidateStation best,
  ) {
    final Set<Polyline> polylines = <Polyline>{};
    const Color navyBlue = Color(0xFF1A237E);

    if (result.routeDirect.ok && result.routeDirect.geometry.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('direct'),
          points: result.routeDirect.geometry,
          width: 4,
          color: navyBlue.withOpacity(0.4),
        ),
      );
    }
    if (best.route1.ok && best.route1.geometry.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route1'),
          points: best.route1.geometry,
          width: 6,
          color: navyBlue,
        ),
      );
    }
    if (best.route2.ok && best.route2.geometry.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route2'),
          points: best.route2.geometry,
          width: 6,
          color: navyBlue,
        ),
      );
    }
    return polylines;
  }

  void fitCurrentTabBounds() {
    final res = result;
    if (res == null || mapController == null || res.error != null) return;

    List<LatLng> points = <LatLng>[res.sourceCoords, res.destCoords];

    switch (tabController.index) {
      case 1:
        if (res.routeDirect.geometry.isNotEmpty) {
          points.addAll(res.routeDirect.geometry);
        }
        for (final cand in res.top5) {
          points.add(cand.latLng);
          points.addAll(cand.route1.geometry);
          points.addAll(cand.route2.geometry);
        }
        break;

      case 2:
        if (res.routeDirect.geometry.isNotEmpty) {
          points.addAll(res.routeDirect.geometry);
        }
        if (placementResult != null) {
          for (final g in placementResult!.uncoveredGaps) {
            points.add(g.startPoint);
            points.add(g.endPoint);
          }
          final currentAlgoResult = placementResult!.resultsByAlgorithm[selectedPlacementAlgo];
          final activeStations = currentAlgoResult?.stations ?? placementResult!.selectedStations;
          for (final p in activeStations) {
            points.add(p.position);
          }
        }
        break;

      case 4:
        final best = res.algoBest['PSO-DS'];
        if (best != null) {
          points.add(best.latLng);
          points.addAll(best.route1.geometry);
          points.addAll(best.route2.geometry);
        }
        break;

      case 5:
        final best = res.algoBest['Genetic Algorithm'];
        if (best != null) {
          points.add(best.latLng);
          points.addAll(best.route1.geometry);
          points.addAll(best.route2.geometry);
        }
        break;

      case 6:
        final best = res.algoBest['Simulated Annealing'];
        if (best != null) {
          points.add(best.latLng);
          points.addAll(best.route1.geometry);
          points.addAll(best.route2.geometry);
        }
        break;

      default:
        if (res.routeDirect.geometry.isNotEmpty) {
          points.addAll(res.routeDirect.geometry);
        }
        break;
    }

    if (points.isNotEmpty) {
      mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFrom(points), 60),
      );
    }
  }

  LatLngBounds _boundsFrom(List<LatLng> list) {
    double minLat = list.first.latitude;
    double maxLat = list.first.latitude;
    double minLng = list.first.longitude;
    double maxLng = list.first.longitude;

    for (final p in list) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Color _colorForIndex(int index) {
    const colors = <Color>[
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.red,
      Colors.cyan,
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'OptiCharge: A Metaheuristic Framework for EV Routing and Optimal Infrastructure Placement',
        ),
        bottom: TabBar(
          controller: tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Summary & Comparison'),
            Tab(text: 'Top 5 Stations Map'),
            Tab(text: 'Optimal Placement Map'),
            Tab(text: 'Candidate Stations'),
            Tab(text: 'PSO-DS Route'),
            Tab(text: 'GA Route'),
            Tab(text: 'SA Route'),
            Tab(text: 'Evaluation Metrics'),
          ],
        ),
      ),
      body: SafeArea(
        child:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : loadingError != null
                ? Center(child: Text(loadingError!))
                : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _buildControls(),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.95,
                            child: TabBarView(
                              controller: tabController,
                              children: [
                                _buildSummaryTab(),
                                _buildTop5Tab(),
                                _buildPlacementTab(),
                                _buildCandidatesTab(),
                                _buildAlgoTab('PSO-DS'),
                                _buildAlgoTab('Genetic Algorithm'),
                                _buildAlgoTab('Simulated Annealing'),
                                _buildMetricsTab(),
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

  Widget _buildControls() {
    final vehicleNames = vehicleSpecs[selectedVehicleType]!.keys.toList();

    if (!vehicleNames.contains(selectedVehicleName)) {
      selectedVehicleName = vehicleNames.first;
    }

    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shows top 5 EV stations on map, hover-style details through marker info windows, compares PSO-DS, Genetic Algorithm, and Simulated Annealing, and proposes optimal new placement locations.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _textField(sourceController, 'Enter Source'),
                            const SizedBox(height: 8),
                            _textField(
                              destinationController,
                              'Enter Destination',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: selectedVehicleType,
                              decoration: const InputDecoration(
                                labelText: 'Select Vehicle Type',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  vehicleSpecs.keys
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  selectedVehicleType = value;
                                  selectedVehicleName =
                                      vehicleSpecs[value]!.keys.first;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: selectedVehicleName,
                              decoration: const InputDecoration(
                                labelText: 'Select EV Model',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  vehicleNames
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => selectedVehicleName = value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              batteryPercent == null
                                  ? 'Available Charge (%): Select value'
                                  : 'Available Charge (%): ${batteryPercent!.toInt()}',
                            ),
                            Slider(
                              value: batteryPercent ?? 1,
                              min: 1,
                              max: 100,
                              divisions: 99,
                              label: batteryPercent?.toInt().toString(),
                              onChanged:
                                  (v) => setState(() => batteryPercent = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Target SOC (%): ${targetSocPercent.toInt()}'),
                            Slider(
                              value: targetSocPercent,
                              min: 20,
                              max: 100,
                              divisions: 80,
                              label: targetSocPercent.toInt().toString(),
                              onChanged: (v) => setState(() => targetSocPercent = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _textField(sourceController, 'Enter Source'),
                    const SizedBox(height: 8),
                    _textField(destinationController, 'Enter Destination'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedVehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Select Vehicle Type',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          vehicleSpecs.keys
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedVehicleType = value;
                          selectedVehicleName = vehicleSpecs[value]!.keys.first;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedVehicleName,
                      decoration: const InputDecoration(
                        labelText: 'Select EV Model',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          vehicleNames
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedVehicleName = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        batteryPercent == null
                            ? 'Available Charge (%): Select value'
                            : 'Available Charge (%): ${batteryPercent!.toInt()}',
                      ),
                    ),
                    Slider(
                      value: batteryPercent ?? 1,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: batteryPercent?.toInt().toString(),
                      onChanged: (v) => setState(() => batteryPercent = v),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Target SOC (%): ${targetSocPercent.toInt()}'),
                    ),
                    Slider(
                      value: targetSocPercent,
                      min: 20,
                      max: 100,
                      divisions: 80,
                      label: targetSocPercent.toInt().toString(),
                      onChanged: (v) => setState(() => targetSocPercent = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  isRunning
                      ? null
                      : () {
                        if (batteryPercent == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select battery percentage'),
                            ),
                          );
                          return;
                        }

                        if (sourceController.text.trim().isEmpty ||
                            destinationController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enter source and destination'),
                            ),
                          );
                          return;
                        }

                        onRun();
                      },
              child: Text(
                isRunning ? 'Finding EV stations...' : 'Find EV Stations',
              ),
            ),
            if (isRunning) ...const [
              SizedBox(height: 10),
              LinearProgressIndicator(),
            ],
            if (result?.error != null) ...[
              const SizedBox(height: 10),
              Text(result!.error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    final res = result;
    if (res == null) {
      return const Center(
        child: Text('Run Metaheuristic Comparison to view results.'),
      );
    }
    if (res.error != null) {
      return Center(child: Text(res.error!));
    }

    Widget cellText(String text, {double width = 120}) {
      return SizedBox(
        width: width,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(res.sourceGeocodeMessage),
          _infoCard(res.destGeocodeMessage),
          const SizedBox(height: 8),
          const Text(
            'Vehicle Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _kv('Battery Capacity', '${res.batteryKwh} kWh'),
          _kv('Consumption', '${res.consumption.toStringAsFixed(3)} kWh/km'),
          _kv(
            'Available Energy at Source',
            '${res.availableEnergy.toStringAsFixed(2)} kWh',
          ),
          _kv('Reserved Energy', '${res.reserveEnergy.toStringAsFixed(2)} kWh'),
          _kv(
            'Maximum Safe Reachable Distance Before Charge',
            '${res.maxReachableKm.toStringAsFixed(2)} km',
          ),
          _kv(
            'Source → Station Constraint',
            '${res.sourceStationLimitKm.toStringAsFixed(2)} km',
          ),
          _kv(
            'Target Charging Level at Station',
            '${res.targetSocPercent.toStringAsFixed(0)} %',
          ),
          _kv('Reachable Candidate Stations', '${res.candidates.length}'),
          if (placementResult != null)
            _kv(
              'Proposed New Station Locations',
              '${placementResult!.selectedStations.length}',
            ),
          if (res.routeDirect.distanceKm != null)
            _kv(
              'Direct Source → Destination Distance',
              '${res.routeDirect.distanceKm!.toStringAsFixed(2)} km',
            ),
          if (res.routeDirect.durationMin != null)
            _kv(
              'Direct Source → Destination Duration',
              '${res.routeDirect.durationMin!.toStringAsFixed(2)} min',
            ),
          const SizedBox(height: 16),
          const Text(
            'Algorithm Comparison',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          res.comparisonRows.isEmpty
              ? const Text('No comparison available.')
              : SizedBox(
                height: 340,
                child: Scrollbar(
                  controller: tableScrollController1,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: tableScrollController1,
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowHeight: 52,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 72,
                        columns: const [
                          DataColumn(label: Text('Algorithm')),
                          DataColumn(label: Text('Station ID')),
                          DataColumn(label: Text('Station Name')),
                          DataColumn(label: Text('Route Preference')),
                          DataColumn(label: Text('Source→Station')),
                          DataColumn(label: Text('Station→Destination')),
                          DataColumn(label: Text('Total Distance')),
                          DataColumn(label: Text('Detour')),
                          DataColumn(label: Text('Energy Used')),
                          DataColumn(label: Text('Charging Time')),
                          DataColumn(label: Text('Units Needed (kWh)')),
                          DataColumn(label: Text('Post-Charge Reach')),
                          DataColumn(label: Text('Can Reach?')),
                          DataColumn(label: Text('Fitness')),
                        ],
                        rows:
                            res.comparisonRows.map((r) {
                              return DataRow(
                                cells: [
                                  DataCell(cellText(r.algorithm)),
                                  DataCell(
                                    cellText(
                                      '${r.stationId ?? '-'}',
                                      width: 90,
                                    ),
                                  ),
                                  DataCell(cellText(r.stationName, width: 160)),
                                  DataCell(
                                    cellText(r.routePreference, width: 140),
                                  ),
                                  DataCell(
                                    cellText('${r.sourceToStationKm} km'),
                                  ),
                                  DataCell(
                                    cellText('${r.stationToDestinationKm} km'),
                                  ),
                                  DataCell(cellText('${r.totalDistanceKm} km')),
                                  DataCell(cellText('${r.detourKm} km')),
                                  DataCell(
                                    cellText(
                                      '${r.energySourceToStationKwh} kWh',
                                    ),
                                  ),
                                  DataCell(
                                    cellText('${r.chargingTimeMin} min'),
                                  ),
                                  DataCell(
                                    cellText('${r.bestCandidate.energyNeededToChargeKwh.toStringAsFixed(2)} kWh'),
                                  ),
                                  DataCell(
                                    cellText('${r.postChargeReachKm} km'),
                                  ),
                                  DataCell(
                                    cellText(r.canReachDestinationAfterCharge),
                                  ),
                                  DataCell(cellText('${r.fitnessScore}')),
                                ],
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 24),
          const Text(
            'Placement Algorithm Comparison',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Compares different metaheuristics for suggesting new charging stations. PSO-DS is consistently the most efficient for complex multi-gap coverage.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          placementResult == null
              ? const Text('Run analysis to see placement comparison.')
              : SizedBox(
                height: 280,
                child: Scrollbar(
                  controller: tableScrollController2,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: tableScrollController2,
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 24,
                      headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      columns: const [
                        DataColumn(label: Text('Algorithm')),
                        DataColumn(label: Text('Gaps Solved')),
                        DataColumn(label: Text('Total Coverage')),
                        DataColumn(label: Text('Avg Detour')),
                        DataColumn(label: Text('Fitness Score')),
                        DataColumn(label: Text('Calc Time')),
                      ],
                      rows:
                          placementResult!.resultsByAlgorithm.entries.map((e) {
                            final r = e.value;
                            final isOptimal = e.key == 'PSO-DS';
                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (states) => isOptimal ? Colors.blue.withOpacity(0.05) : null,
                              ),
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      Text(e.key, style: TextStyle(fontWeight: isOptimal ? FontWeight.bold : FontWeight.normal)),
                                      if (isOptimal) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.star, size: 16, color: Colors.amber),
                                      ],
                                    ],
                                  ),
                                ),
                                DataCell(
                                  r.gapsSolved == 0 && placementResult!.uncoveredGaps.isEmpty
                                      ? const Text('Sufficient', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                                      : Text('${r.gapsSolved}'),
                                ),
                                DataCell(
                                  r.totalCoverageKm == 0 && placementResult!.uncoveredGaps.isEmpty
                                      ? const Text('Full Coverage', style: TextStyle(color: Colors.green))
                                      : Text('${r.totalCoverageKm.toStringAsFixed(1)} km'),
                                ),
                                DataCell(Text('${r.avgDetourKm.toStringAsFixed(2)} km')),
                                DataCell(Text(r.totalFitnessScore.toStringAsFixed(2))),
                                DataCell(Text('${r.calculationTime.inMilliseconds} ms')),
                              ],
                            );
                          }).toList(),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTop5Tab() {
    final res = result;
    if (res == null) {
      return const Center(child: Text('Run Metaheuristic Comparison to view top stations.'));
    }

    return FutureBuilder<Set<Marker>>(
      future: createTop5Markers(res),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final markers = snapshot.data!;
        final polylines = createTop5Polylines(res);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: res.sourceCoords,
                      zoom: 6,
                    ),
                    markers: markers,
                    polylines: polylines,
                    onMapCreated: (controller) {
                      mapController = controller;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        fitCurrentTabBounds();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildMapLegend([
                _LegendItem('Source', Colors.green),
                _LegendItem('Destination', Colors.red),
                _LegendItem('Top Stations', Colors.blue),
              ]),
              const SizedBox(height: 12),
              Expanded(
                flex: 4,
                child: ListView.builder(
                  itemCount: res.top5.length,
                  itemBuilder: (context, index) {
                    final c = res.top5[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(stationNameText(c)),
                        subtitle: Text(
                          '${stationAddressText(c)}\n'
                          '${c.chargerPowerKw}kW • ${c.distanceSourceToStationKm.toStringAsFixed(2)} km • ${c.totalTripDurationMin.toStringAsFixed(0)}m Trip',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlacementTab() {
    final res = result;
    final placement = placementResult;

    if (res == null || placement == null) {
      return const Center(child: Text('Run Metaheuristic Comparison to view optimal placement.'));
    }

    final activeAlgoResult = placement.resultsByAlgorithm[selectedPlacementAlgo];
    final activeStations = activeAlgoResult?.stations ?? placement.selectedStations;

    return FutureBuilder<Set<Marker>>(
      future: createPlacementMarkers(res, placement),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final markers = snapshot.data!;
        final polylines = createPlacementPolylines(res, placement);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PSO-DS', label: Text('PSO-DS (Opt)'), icon: Icon(Icons.auto_awesome)),
                      ButtonSegment(value: 'GA', label: Text('GA'), icon: Icon(Icons.fitness_center)),
                      ButtonSegment(value: 'SA', label: Text('SA'), icon: Icon(Icons.ac_unit)),
                      ButtonSegment(value: 'Greedy', label: Text('Greedy'), icon: Icon(Icons.fast_forward)),
                    ],
                    selected: {selectedPlacementAlgo},
                    onSelectionChanged: (val) => setState(() => selectedPlacementAlgo = val.first),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (activeAlgoResult != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statChip(
                        'Coverage',
                        activeAlgoResult.totalCoverageKm == 0 && placement.uncoveredGaps.isEmpty
                            ? 'Full'
                            : '${activeAlgoResult.totalCoverageKm.toStringAsFixed(1)} km',
                        Colors.green,
                      ),
                      _statChip(
                        'Detour',
                        activeAlgoResult.avgDetourKm == 0 ? 'N/A' : '${activeAlgoResult.avgDetourKm.toStringAsFixed(2)} km',
                        Colors.orange,
                      ),
                      _statChip('Score', activeAlgoResult.totalFitnessScore.toStringAsFixed(1), Colors.blue),
                    ],
                  ),
                ),
              _buildMapLegend([
                _LegendItem('Source', Colors.green), _LegendItem('Destination', Colors.red),
                _LegendItem('Existing', Colors.blue), _LegendItem('PSO-DS', Colors.cyan),
                _LegendItem('GA', Colors.purple), _LegendItem('SA', Colors.orange),
                _LegendItem('Greedy', Colors.yellow),
              ]),
              const SizedBox(height: 8),
              Expanded(
                flex: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: res.sourceCoords, zoom: 6),
                    markers: markers,
                    polylines: polylines,
                    onMapCreated: (controller) {
                      mapController = controller;
                      WidgetsBinding.instance.addPostFrameCallback((_) => fitCurrentTabBounds());
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 4,
                child: ListView.builder(
                  itemCount: activeStations.length,
                  itemBuilder: (context, index) {
                    final s = activeStations[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text('Proposed Station #${s.rank}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _miniStat('Trip Progress', '${s.routeDistanceKm.toStringAsFixed(1)} km'),
                                const SizedBox(width: 8),
                                _miniStat('Detour', '${s.distanceToRouteKm.toStringAsFixed(2)} km'),
                                const SizedBox(width: 8),
                                _miniStat('Nearest Alt', '${s.nearestExistingStationDistanceKm.toStringAsFixed(1)} km'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.reason,
                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.location_on, color: Colors.blue),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
      ),
    );
  }

  Widget _buildMapLegend(List<_LegendItem> items) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children:
            items.map((item) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(item.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              );
            }).toList(),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCandidatesTab() {
    final res = result;
    if (res == null) {
      return const Center(
        child: Text('Run Metaheuristic Comparison to view candidates.'),
      );
    }
    if (res.error != null) {
      return Center(child: Text(res.error!));
    }
    if (res.candidates.isEmpty) {
      return const Center(child: Text('No candidate stations to display.'));
    }

    final columns = res.candidates.first.toDisplayMap().keys.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns.map((c) => DataColumn(label: Text(c))).toList(),
          rows:
              res.candidates.map((cand) {
                final map = cand.toDisplayMap();
                return DataRow(
                  cells:
                      columns
                          .map((key) => DataCell(Text('${map[key] ?? ''}')))
                          .toList(),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildAlgoTab(String algoName) {
    final res = result;
    if (res == null) {
      return Center(
        child: Text('Run Metaheuristic Comparison to view $algoName results.'),
      );
    }
    if (res.error != null) {
      return Center(child: Text(res.error!));
    }

    final best = res.algoBest[algoName];
    if (best == null) {
      return Center(child: Text('No route found for $algoName.'));
    }

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$algoName Best Route',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _kv('Station', best.stationName),
                _kv('Route Preference', best.routePreference),
                _kv(
                  'Source → Station Distance',
                  '${best.distanceSourceToStationKm} km',
                ),
                _kv(
                  'Station → Destination Distance',
                  '${best.distanceStationToDestinationKm} km',
                ),
                _kv('Total Distance', '${best.totalRouteViaStationKm} km'),
                _kv(
                  'Energy Used to Reach EVCS',
                  '${best.energyUsedToReachEvcsKwh} kWh',
                ),
                _kv('Charging Time', '${best.chargingTimeMin} min'),
                _kv('Total Est. Trip Duration', '${best.totalTripDurationMin.toStringAsFixed(2)} min'),
                _kv('Energy Required', '${best.energyNeededToChargeKwh.toStringAsFixed(2)} kWh'),
                _kv('Fitness Score', '${best.fitnessScore}'),
                const SizedBox(height: 12),
                const Text(
                  'Expert Justification:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Text(
                    best.explanation,
                    style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 7,
          child: FutureBuilder<Set<Marker>>(
            future: createSingleAlgoMarkers(res, best, algoName),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: res.sourceCoords,
                  zoom: 6,
                ),
                markers: snapshot.data!,
                polylines: createSingleAlgoPolylines(res, best),
                onMapCreated: (controller) {
                  mapController = controller;
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _textField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _infoCard(String text) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(10), child: Text(text)),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          children: [
            TextSpan(
              text: '$key: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 14, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsTab() {
    final res = result;
    if (res == null) {
      return const Center(child: Text('Run Metaheuristic Comparison to view metrics.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Advanced Performance Analytics',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD)),
          ),
          const Text('Statistical evaluation of routing efficiency and algorithmic convergence.'),
          const SizedBox(height: 24),
          _buildStatsCards(res),
          const SizedBox(height: 24),
          _buildConvergenceChart(res),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildConfusionMatrix(res)),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _buildDurationChart(res)),
            ],
          ),
          const SizedBox(height: 24),
          _buildDetourChart(res),
          const SizedBox(height: 24),
          _buildExecutionTimeChart(res),
          const SizedBox(height: 24),
          _buildKPIGrid(res),
        ],
      ),
    );
  }

  Widget _buildStatsCards(MetaComparisonResult res) {
    return Row(
      children: [
        _statCard('Accuracy', '${(res.accuracy * 100).toStringAsFixed(1)}%', Icons.check_circle_outline, Colors.green),
        const SizedBox(width: 12),
        _statCard('Precision', '${(res.precision * 100).toStringAsFixed(1)}%', Icons.gps_fixed, Colors.blue),
        const SizedBox(width: 12),
        _statCard('Recall', '${(res.recall * 100).toStringAsFixed(1)}%', Icons.history, Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConvergenceChart(MetaComparisonResult res) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Convergence History (Fitness vs Iterations)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  lineBarsData: res.comparisonRows
                      .where((e) => e.convergenceHistory.isNotEmpty)
                      .map((e) {
                    return LineChartBarData(
                      spots: e.convergenceHistory.asMap().entries.map((entry) {
                        return FlSpot(entry.key.toDouble(), entry.value);
                      }).toList(),
                      isCurved: true,
                      color: _getAlgoColor(e.algorithm),
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    );
                  }).toList(),
                  titlesData: const FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfusionMatrix(MetaComparisonResult res) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Reachability Confusion Matrix', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    _matrixLabel('Actual: True'),
                    _matrixLabel('Actual: False'),
                  ],
                ),
                Row(
                  children: [
                    _matrixLabel('Pred: True', vertical: true),
                    _matrixCell('TP\n${res.tp}', Colors.green.shade400),
                    _matrixCell('FP\n${res.fp}', Colors.red.shade200),
                  ],
                ),
                Row(
                  children: [
                    _matrixLabel('Pred: False', vertical: true),
                    _matrixCell('FN\n${res.fn}', Colors.orange.shade200),
                    _matrixCell('TN\n${res.tn}', Colors.grey.shade400),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _matrixLabel(String text, {bool vertical = false}) {
    return Container(
      width: vertical ? 60 : 80,
      height: vertical ? 80 : 30,
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _matrixCell(String text, Color color) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDurationChart(MetaComparisonResult res) {
    final items = res.comparisonRows;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Total Trip Duration (min)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: items.isEmpty ? 100 : items.map((e) => e.totalTripDurationMin).reduce(math.max) * 1.2,
                  barGroups: items.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.totalTripDurationMin,
                          color: _getAlgoColor(entry.value.algorithm),
                          width: 25,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= items.length) return const Text('');
                          String label = items[index].algorithm;
                          if (label == 'Direct Trip (No Stop)') label = 'Direct';
                          if (label == 'Genetic Algorithm') label = 'GA';
                          if (label == 'Simulated Annealing') label = 'SA';
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(label, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetourChart(MetaComparisonResult res) {
    final items = res.comparisonRows.where((e) => e.algorithm != 'Direct Trip (No Stop)').toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Detour Distance Overhead (km)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: items.map((e) => e.detourKm).reduce(math.max) * 1.5,
                  barGroups: items.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.detourKm,
                          color: Colors.orangeAccent,
                          width: 20,
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= items.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(items[index].algorithm == 'Genetic Algorithm' ? 'GA' : (items[index].algorithm == 'Simulated Annealing' ? 'SA' : 'PSO-DS'), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionTimeChart(MetaComparisonResult res) {
    final items = res.comparisonRows.where((e) => e.algorithm != 'Direct Trip (No Stop)').toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Algorithm Execution Time (ms)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: items.map((e) => e.executionTimeMs).reduce(math.max) * 1.5,
                  barGroups: items.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.executionTimeMs,
                          color: Colors.purpleAccent,
                          width: 20,
                        ),
                      ],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= items.length) return const Text('');
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(items[index].algorithm == 'Genetic Algorithm' ? 'GA' : (items[index].algorithm == 'Simulated Annealing' ? 'SA' : 'PSO-DS'), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIGrid(MetaComparisonResult res) {
    if (res.comparisonRows.isEmpty) return const SizedBox.shrink();
    final best = res.comparisonRows.firstWhere((e) => e.algorithm == 'PSO-DS', orElse: () => res.comparisonRows.first);
    
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _kpi('Efficiency Index', '${(1 / best.fitnessScore).toStringAsFixed(2)}'),
        _kpi('Total Stations Scanned', '${res.candidates.length}'),
        _kpi('Top 5 Mean Detour', res.top5.isEmpty ? 'N/A' : '${(res.top5.map((e) => e.detourDistanceKm).reduce((a, b) => a + b) / res.top5.length).toStringAsFixed(2)} km'),
        _kpi('Best Fitness Score', '${best.fitnessScore.toStringAsFixed(4)}'),
      ],
    );
  }

  Widget _kpi(String label, String value) {
    return Card(
      color: Colors.blueAccent.withOpacity(0.05),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Color _getAlgoColor(String algo) {
    if (algo == 'Direct Trip (No Stop)') return Colors.grey;
    if (algo == 'PSO-DS') return const Color(0xFF0D6EFD);
    if (algo == 'Genetic Algorithm') return Colors.green;
    return Colors.orange;
  }

  double _r2(double value) => double.parse(value.toStringAsFixed(2));
  double _r6(double value) => double.parse(value.toStringAsFixed(6));
  int _clampIndex(int value, int n) => value.clamp(0, n - 1);
}

class _AirCandidate {
  final StationData row;
  final double airDistSourceStation;
  final double airDistStationDest;
  final double corridorDetourAirKm;
  final double polylineDistanceKm;
  final bool onCorridor;

  const _AirCandidate({
    required this.row,
    required this.airDistSourceStation,
    required this.airDistStationDest,
    required this.corridorDetourAirKm,
    required this.polylineDistanceKm,
    required this.onCorridor,
  });
}
class _LegendItem {
  final String label;
  final Color color;

  _LegendItem(this.label, this.color);
}
