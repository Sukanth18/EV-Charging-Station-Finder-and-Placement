import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ===============================================================
/// placement.dart
/// Logic-only module for:
/// 1) Detecting uncovered route gaps
/// 2) Generating candidate station placement points
/// 3) Scoring candidates
/// 4) Selecting best proposed station locations
/// 5) Returning explainable result to main.dart
/// ===============================================================

class PlacementStationInput {
  final String id;
  final String name;
  final String address;
  final LatLng position;

  const PlacementStationInput({
    required this.id,
    required this.name,
    required this.address,
    required this.position,
  });
}

class RouteProjection {
  final int nearestRouteIndex;
  final double distanceToRouteKm;
  final double routeDistanceKm;
  final LatLng snappedPoint;

  const RouteProjection({
    required this.nearestRouteIndex,
    required this.distanceToRouteKm,
    required this.routeDistanceKm,
    required this.snappedPoint,
  });
}

class RouteAnchor {
  final String id;
  final String label;
  final LatLng position;
  final double routeDistanceKm;
  final int nearestRouteIndex;
  final double distanceToRouteKm;
  final bool isExistingStation;

  const RouteAnchor({
    required this.id,
    required this.label,
    required this.position,
    required this.routeDistanceKm,
    required this.nearestRouteIndex,
    required this.distanceToRouteKm,
    required this.isExistingStation,
  });
}

class UncoveredGap {
  final String id;
  final LatLng startPoint;
  final LatLng endPoint;
  final int startRouteIndex;
  final int endRouteIndex;
  final double startRouteDistanceKm;
  final double endRouteDistanceKm;
  final double lengthKm;
  final bool isFeasible;
  final double severityScore;

  const UncoveredGap({
    required this.id,
    required this.startPoint,
    required this.endPoint,
    required this.startRouteIndex,
    required this.endRouteIndex,
    required this.startRouteDistanceKm,
    required this.endRouteDistanceKm,
    required this.lengthKm,
    required this.isFeasible,
    required this.severityScore,
  });

  LatLng get midpoint => LatLng(
    (startPoint.latitude + endPoint.latitude) / 2.0,
    (startPoint.longitude + endPoint.longitude) / 2.0,
  );
}

class CandidateLocation {
  final String id;
  final LatLng position;
  final int nearestRouteIndex;
  final double routeDistanceKm;
  final double distanceToRouteKm;
  final String sourceType;
  final String? nearestGapId;
  final double nearestExistingStationDistanceKm;

  final double detourScore;
  final double coverageScore;
  final double accessibilityScore;
  final double stationDistanceScore;
  final double demandScore;
  final double suitabilityScore;
  final double finalScore;

  final double coveredGapLengthKm;
  final double expectedMaxSubGapKm;
  final List<String> reasonTags;

  const CandidateLocation({
    required this.id,
    required this.position,
    required this.nearestRouteIndex,
    required this.routeDistanceKm,
    required this.distanceToRouteKm,
    required this.sourceType,
    required this.nearestGapId,
    required this.nearestExistingStationDistanceKm,
    required this.detourScore,
    required this.coverageScore,
    required this.accessibilityScore,
    required this.stationDistanceScore,
    required this.demandScore,
    required this.suitabilityScore,
    required this.finalScore,
    required this.coveredGapLengthKm,
    required this.expectedMaxSubGapKm,
    required this.reasonTags,
  });

  CandidateLocation copyWith({List<String>? reasonTags}) {
    return CandidateLocation(
      id: id,
      position: position,
      nearestRouteIndex: nearestRouteIndex,
      routeDistanceKm: routeDistanceKm,
      distanceToRouteKm: distanceToRouteKm,
      sourceType: sourceType,
      nearestGapId: nearestGapId,
      nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
      detourScore: detourScore,
      coverageScore: coverageScore,
      accessibilityScore: accessibilityScore,
      stationDistanceScore: stationDistanceScore,
      demandScore: demandScore,
      suitabilityScore: suitabilityScore,
      finalScore: finalScore,
      coveredGapLengthKm: coveredGapLengthKm,
      expectedMaxSubGapKm: expectedMaxSubGapKm,
      reasonTags: reasonTags ?? this.reasonTags,
    );
  }
}

class ProposedStationPlacement {
  final String id;
  final LatLng position;
  final int rank;
  final double finalScore;
  final double routeDistanceKm;
  final double distanceToRouteKm;
  final double nearestExistingStationDistanceKm;
  final double coveredGapLengthKm;
  final double expectedMaxSubGapKm;
  final String sourceType;
  final String reason;
  final List<String> solvedGapIds;

  const ProposedStationPlacement({
    required this.id,
    required this.position,
    required this.rank,
    required this.finalScore,
    required this.routeDistanceKm,
    required this.distanceToRouteKm,
    required this.nearestExistingStationDistanceKm,
    required this.coveredGapLengthKm,
    required this.expectedMaxSubGapKm,
    required this.sourceType,
    required this.reason,
    required this.solvedGapIds,
  });
}

class PlacementAlgorithmResult {
  final String algorithmName;
  final List<ProposedStationPlacement> stations;
  final double totalFitnessScore;
  final double totalCoverageKm;
  final double avgDetourKm;
  final int gapsSolved;
  final Duration calculationTime;

  const PlacementAlgorithmResult({
    required this.algorithmName,
    required this.stations,
    required this.totalFitnessScore,
    required this.totalCoverageKm,
    required this.avgDetourKm,
    required this.gapsSolved,
    required this.calculationTime,
  });
}

class PlacementResult {
  final List<RouteAnchor> usableExistingStationsOnRoute;
  final List<UncoveredGap> uncoveredGaps;
  final List<CandidateLocation> allCandidates;
  final List<ProposedStationPlacement> selectedStations; // Default (PSO-DS)
  final Map<String, PlacementAlgorithmResult> resultsByAlgorithm;
  final double routeLengthKm;
  final double safeRangeKm;
  final int totalCandidatesGenerated;
  final int totalSelected;

  const PlacementResult({
    required this.usableExistingStationsOnRoute,
    required this.uncoveredGaps,
    required this.allCandidates,
    required this.selectedStations,
    required this.resultsByAlgorithm,
    required this.routeLengthKm,
    required this.safeRangeKm,
    required this.totalCandidatesGenerated,
    required this.totalSelected,
  });
}

class PlacementWeights {
  final double detour;
  final double coverage;
  final double accessibility;
  final double stationDistance;
  final double demand;
  final double suitability;

  const PlacementWeights({
    this.detour = 0.20,
    this.coverage = 0.30,
    this.accessibility = 0.15,
    this.stationDistance = 0.15,
    this.demand = 0.10,
    this.suitability = 0.10,
  });

  double get total =>
      detour +
      coverage +
      accessibility +
      stationDistance +
      demand +
      suitability;
}

class PlacementService {
  final PlacementWeights weights;

  /// Maximum distance from route for an existing station to be considered useful.
  final double usableStationCorridorKm;

  /// Candidate points farther than this from route are heavily penalized.
  final double candidateRouteCorridorKm;

  /// Minimum spacing between selected proposed locations.
  final double redundancyRadiusKm;

  /// How often route-wide candidates are created.
  final double candidateSpacingKm;

  /// Minimum preferred distance from an existing station.
  final double minDistanceFromExistingKm;

  /// If a gap is larger than safe range, it is risky/uncovered.
  final double coverageSlackFactor;

  const PlacementService({
    this.weights = const PlacementWeights(),
    this.usableStationCorridorKm = 8.0,
    this.candidateRouteCorridorKm = 10.0,
    this.redundancyRadiusKm = 18.0,
    this.candidateSpacingKm = 20.0,
    this.minDistanceFromExistingKm = 10.0,
    this.coverageSlackFactor = 1.0,
  });

  PlacementResult runPlacementAnalysis({
    required List<LatLng> routePoints,
    required List<PlacementStationInput> existingStations,
    required double safeRangeKm,
    int maxProposedStations = 3,
  }) {
    if (routePoints.length < 2) {
      return PlacementResult(
        usableExistingStationsOnRoute: const [],
        uncoveredGaps: const [],
        allCandidates: const [],
        selectedStations: const [],
        resultsByAlgorithm: const {},
        routeLengthKm: 0,
        safeRangeKm: safeRangeKm,
        totalCandidatesGenerated: 0,
        totalSelected: 0,
      );
    }

    final cumulativeKm = _buildCumulativeRouteDistances(routePoints);
    final routeLengthKm = cumulativeKm.last;

    final usableAnchors = _projectExistingStationsToRoute(
      routePoints: routePoints,
      cumulativeKm: cumulativeKm,
      existingStations: existingStations,
    );

    final gaps = _detectUncoveredGaps(
      routePoints: routePoints,
      cumulativeKm: cumulativeKm,
      usableAnchors: usableAnchors,
      safeRangeKm: safeRangeKm,
    );

    final rawCandidates = _generateCandidates(
      routePoints: routePoints,
      cumulativeKm: cumulativeKm,
      gaps: gaps,
      routeLengthKm: routeLengthKm,
      safeRangeKm: safeRangeKm,
    );

    final candidates = _scoreCandidates(
      rawCandidates: rawCandidates,
      gaps: gaps,
      existingStations: existingStations,
      routeLengthKm: routeLengthKm,
      safeRangeKm: safeRangeKm,
    );

    final selectedGreedy = _selectBestCandidates(
      scoredCandidates: candidates,
      gaps: gaps,
      maxSelections: maxProposedStations,
      safeRangeKm: safeRangeKm,
    );

    final results = <String, PlacementAlgorithmResult>{};

    // 1. Greedy
    final watchGreedy = Stopwatch()..start();
    final greedySelection = _selectBestCandidates(
      scoredCandidates: candidates,
      gaps: gaps,
      maxSelections: maxProposedStations,
      safeRangeKm: safeRangeKm,
    );
    watchGreedy.stop();
    results['Greedy'] = _buildAlgorithmResult(
      'Greedy',
      greedySelection,
      candidates,
      gaps,
      safeRangeKm,
      watchGreedy.elapsed,
    );

    // 2. PSO-DS (Optimal algorithm for this case study)
    final watchPSO = Stopwatch()..start();
    final psoSelection = _selectBestCandidatesPSO(
      allCandidates: candidates,
      gaps: gaps,
      maxSelections: maxProposedStations,
      safeRangeKm: safeRangeKm,
    );
    watchPSO.stop();
    results['PSO-DS'] = _buildAlgorithmResult(
      'PSO-DS',
      psoSelection,
      candidates,
      gaps,
      safeRangeKm,
      watchPSO.elapsed,
    );

    // 3. Genetic Algorithm (Comparison)
    final watchGA = Stopwatch()..start();
    final gaSelection = _selectBestCandidatesGA(
      allCandidates: candidates,
      gaps: gaps,
      maxSelections: maxProposedStations,
      safeRangeKm: safeRangeKm,
    );
    watchGA.stop();
    results['GA'] = _buildAlgorithmResult(
      'GA',
      gaSelection,
      candidates,
      gaps,
      safeRangeKm,
      watchGA.elapsed,
    );

    // 4. Simulated Annealing (Comparison)
    final watchSA = Stopwatch()..start();
    final saSelection = _selectBestCandidatesSA(
      allCandidates: candidates,
      gaps: gaps,
      maxSelections: maxProposedStations,
      safeRangeKm: safeRangeKm,
    );
    watchSA.stop();
    results['SA'] = _buildAlgorithmResult(
      'SA',
      saSelection,
      candidates,
      gaps,
      safeRangeKm,
      watchSA.elapsed,
    );

    // Primary selection is PSO-DS
    final primary = psoSelection.isNotEmpty ? psoSelection : greedySelection;

    return PlacementResult(
      usableExistingStationsOnRoute: usableAnchors,
      uncoveredGaps: gaps,
      allCandidates: candidates,
      selectedStations: primary,
      resultsByAlgorithm: results,
      routeLengthKm: routeLengthKm,
      safeRangeKm: safeRangeKm,
      totalCandidatesGenerated: candidates.length,
      totalSelected: primary.length,
    );
  }

  PlacementAlgorithmResult _buildAlgorithmResult(
    String name,
    List<ProposedStationPlacement> selection,
    List<CandidateLocation> allCandidates,
    List<UncoveredGap> gaps,
    double safeRangeKm,
    Duration time,
  ) {
    double totalCoverage = 0;
    double totalDetour = 0;
    int gapsSolved = 0;

    final solvedIds = <String>{};
    for (final s in selection) {
      totalDetour += s.distanceToRouteKm;
      for (final gid in s.solvedGapIds) {
        if (solvedIds.add(gid)) {
          final gap = gaps.where((g) => g.id == gid).firstOrNull;
          if (gap != null) {
            totalCoverage += gap.lengthKm;
            gapsSolved++;
          }
        }
      }
    }

    // Heuristic fitness for summary
    double fitness = (totalCoverage * 1.5) - (totalDetour * 0.5);
    
    // Safety Baseline: if no gaps were solved (sufficient network), 
    // we give a small positive score based on station quality and redundancy.
    if (gapsSolved == 0 && gaps.isEmpty) {
      fitness = 5.0 + (selection.length * 2.0) - (totalDetour * 0.1);
    }

    return PlacementAlgorithmResult(
      algorithmName: name,
      stations: selection,
      totalFitnessScore: math.max(0.1, fitness),
      totalCoverageKm: totalCoverage,
      avgDetourKm: selection.isEmpty ? 0 : totalDetour / selection.length,
      gapsSolved: gapsSolved,
      calculationTime: time,
    );
  }

  List<double> _buildCumulativeRouteDistances(List<LatLng> routePoints) {
    final cumulative = <double>[0.0];
    for (int i = 1; i < routePoints.length; i++) {
      cumulative.add(
        cumulative.last + _haversineKm(routePoints[i - 1], routePoints[i]),
      );
    }
    return cumulative;
  }

  List<RouteAnchor> _projectExistingStationsToRoute({
    required List<LatLng> routePoints,
    required List<double> cumulativeKm,
    required List<PlacementStationInput> existingStations,
  }) {
    final anchors = <RouteAnchor>[];

    for (final station in existingStations) {
      final proj = _projectPointToRoute(
        point: station.position,
        routePoints: routePoints,
        cumulativeKm: cumulativeKm,
      );

      if (proj.distanceToRouteKm <= usableStationCorridorKm) {
        anchors.add(
          RouteAnchor(
            id: station.id,
            label: station.name,
            position: station.position,
            routeDistanceKm: proj.routeDistanceKm,
            nearestRouteIndex: proj.nearestRouteIndex,
            distanceToRouteKm: proj.distanceToRouteKm,
            isExistingStation: true,
          ),
        );
      }
    }

    anchors.sort((a, b) => a.routeDistanceKm.compareTo(b.routeDistanceKm));
    return anchors;
  }

  List<UncoveredGap> _detectUncoveredGaps({
    required List<LatLng> routePoints,
    required List<double> cumulativeKm,
    required List<RouteAnchor> usableAnchors,
    required double safeRangeKm,
  }) {
    final anchors = <RouteAnchor>[
      RouteAnchor(
        id: 'source_anchor',
        label: 'Source',
        position: routePoints.first,
        routeDistanceKm: 0.0,
        nearestRouteIndex: 0,
        distanceToRouteKm: 0.0,
        isExistingStation: false,
      ),
      ...usableAnchors,
      RouteAnchor(
        id: 'destination_anchor',
        label: 'Destination',
        position: routePoints.last,
        routeDistanceKm: cumulativeKm.last,
        nearestRouteIndex: routePoints.length - 1,
        distanceToRouteKm: 0.0,
        isExistingStation: false,
      ),
    ];

    anchors.sort((a, b) => a.routeDistanceKm.compareTo(b.routeDistanceKm));

    final gaps = <UncoveredGap>[];
    for (int i = 0; i < anchors.length - 1; i++) {
      final a = anchors[i];
      final b = anchors[i + 1];
      final gapLengthKm = (b.routeDistanceKm - a.routeDistanceKm).abs();

      final threshold = safeRangeKm * coverageSlackFactor;
      final isFeasible = gapLengthKm <= threshold;

      if (!isFeasible) {
        final severity =
            ((gapLengthKm - threshold) / math.max(threshold, 1.0))
                .clamp(0.0, 1.0)
                .toDouble();

        gaps.add(
          UncoveredGap(
            id: 'gap_$i',
            startPoint: routePoints[a.nearestRouteIndex],
            endPoint: routePoints[b.nearestRouteIndex],
            startRouteIndex: a.nearestRouteIndex,
            endRouteIndex: b.nearestRouteIndex,
            startRouteDistanceKm: a.routeDistanceKm,
            endRouteDistanceKm: b.routeDistanceKm,
            lengthKm: gapLengthKm,
            isFeasible: isFeasible,
            severityScore: severity,
          ),
        );
      }
    }

    return gaps;
  }

  List<_RawCandidate> _generateCandidates({
    required List<LatLng> routePoints,
    required List<double> cumulativeKm,
    required List<UncoveredGap> gaps,
    required double routeLengthKm,
    required double safeRangeKm,
  }) {
    final result = <_RawCandidate>[];
    final seen = <String>{};

    void addCandidate({
      required LatLng point,
      required int nearestRouteIndex,
      required double routeDistanceKm,
      required String sourceType,
      String? gapId,
    }) {
      final key =
          '${point.latitude.toStringAsFixed(5)}_${point.longitude.toStringAsFixed(5)}_$sourceType';
      if (seen.contains(key)) return;
      seen.add(key);

      result.add(
        _RawCandidate(
          id: 'cand_${result.length + 1}',
          position: point,
          nearestRouteIndex: nearestRouteIndex,
          routeDistanceKm: routeDistanceKm,
          sourceType: sourceType,
          nearestGapId: gapId,
        ),
      );
    }

    // A) Candidates focused on uncovered gaps.
    for (final gap in gaps) {
      final midRouteKm =
          (gap.startRouteDistanceKm + gap.endRouteDistanceKm) / 2.0;
      final midIdx = _routeIndexForDistance(cumulativeKm, midRouteKm);
      addCandidate(
        point: routePoints[midIdx],
        nearestRouteIndex: midIdx,
        routeDistanceKm: cumulativeKm[midIdx],
        sourceType: 'gap_midpoint',
        gapId: gap.id,
      );

      final q1Km = gap.startRouteDistanceKm + gap.lengthKm * 0.25;
      final q3Km = gap.startRouteDistanceKm + gap.lengthKm * 0.75;
      final q1Idx = _routeIndexForDistance(cumulativeKm, q1Km);
      final q3Idx = _routeIndexForDistance(cumulativeKm, q3Km);

      addCandidate(
        point: routePoints[q1Idx],
        nearestRouteIndex: q1Idx,
        routeDistanceKm: cumulativeKm[q1Idx],
        sourceType: 'gap_quarter',
        gapId: gap.id,
      );

      addCandidate(
        point: routePoints[q3Idx],
        nearestRouteIndex: q3Idx,
        routeDistanceKm: cumulativeKm[q3Idx],
        sourceType: 'gap_three_quarter',
        gapId: gap.id,
      );

      // Dense candidates inside extra-long gaps
      final denseSpacing = math.max(10.0, safeRangeKm / 3.0);
      double d = gap.startRouteDistanceKm + denseSpacing;
      while (d < gap.endRouteDistanceKm) {
        final idx = _routeIndexForDistance(cumulativeKm, d);
        addCandidate(
          point: routePoints[idx],
          nearestRouteIndex: idx,
          routeDistanceKm: cumulativeKm[idx],
          sourceType: 'gap_interval',
          gapId: gap.id,
        );
        d += denseSpacing;
      }
    }

    // B) Route-wide candidates every fixed interval.
    double d = candidateSpacingKm;
    while (d < routeLengthKm) {
      final idx = _routeIndexForDistance(cumulativeKm, d);
      addCandidate(
        point: routePoints[idx],
        nearestRouteIndex: idx,
        routeDistanceKm: cumulativeKm[idx],
        sourceType: 'route_interval',
      );
      d += candidateSpacingKm;
    }

    return result;
  }

  List<CandidateLocation> _scoreCandidates({
    required List<_RawCandidate> rawCandidates,
    required List<UncoveredGap> gaps,
    required List<PlacementStationInput> existingStations,
    required double routeLengthKm,
    required double safeRangeKm,
  }) {
    final scored = <CandidateLocation>[];

    for (final raw in rawCandidates) {
      final nearestGap = _findNearestGapByRouteDistance(
        raw.routeDistanceKm,
        gaps,
      );

      final nearestExistingStationDistanceKm =
          existingStations.isEmpty
              ? 9999.0
              : existingStations
                  .map((s) => _haversineKm(raw.position, s.position))
                  .reduce((a, b) => math.min(a, b));

      final distanceToRouteKm = 0.0; // all generated candidates lie on route

      final detourScore = _scoreDetour(distanceToRouteKm);
      final coverageInfo = _coverageImprovementForCandidate(
        routeDistanceKm: raw.routeDistanceKm,
        nearestGap: nearestGap,
        safeRangeKm: safeRangeKm,
      );

      final coverageScore = coverageInfo.coverageScore;
      final coveredGapLengthKm = coverageInfo.coveredGapLengthKm;
      final expectedMaxSubGapKm = coverageInfo.expectedMaxSubGapKm;

      final accessibilityScore = _scoreAccessibility(
        distanceToRouteKm: distanceToRouteKm,
        routeProgressRatio:
            routeLengthKm == 0 ? 0 : raw.routeDistanceKm / routeLengthKm,
      );

      final stationDistanceScore = _scoreExistingStationDistance(
        nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
      );

      final demandScore = _scoreDemandPotential(
        nearestGap: nearestGap,
        routeDistanceKm: raw.routeDistanceKm,
        routeLengthKm: routeLengthKm,
      );

      final suitabilityScore = _scoreSuitability(
        distanceToRouteKm: distanceToRouteKm,
        nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
        nearestGap: nearestGap,
      );

      final finalScore = _weightedScore(
        detourScore: detourScore,
        coverageScore: coverageScore,
        accessibilityScore: accessibilityScore,
        stationDistanceScore: stationDistanceScore,
        demandScore: demandScore,
        suitabilityScore: suitabilityScore,
      );

      final reasonTags = _buildReasonTags(
        detourScore: detourScore,
        coverageScore: coverageScore,
        accessibilityScore: accessibilityScore,
        stationDistanceScore: stationDistanceScore,
        demandScore: demandScore,
        suitabilityScore: suitabilityScore,
        nearestGap: nearestGap,
        nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
        distanceToRouteKm: distanceToRouteKm,
      );

      scored.add(
        CandidateLocation(
          id: raw.id,
          position: raw.position,
          nearestRouteIndex: raw.nearestRouteIndex,
          routeDistanceKm: raw.routeDistanceKm,
          distanceToRouteKm: distanceToRouteKm,
          sourceType: raw.sourceType,
          nearestGapId: nearestGap?.id ?? raw.nearestGapId,
          nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
          detourScore: detourScore,
          coverageScore: coverageScore,
          accessibilityScore: accessibilityScore,
          stationDistanceScore: stationDistanceScore,
          demandScore: demandScore,
          suitabilityScore: suitabilityScore,
          finalScore: finalScore,
          coveredGapLengthKm: coveredGapLengthKm,
          expectedMaxSubGapKm: expectedMaxSubGapKm,
          reasonTags: reasonTags,
        ),
      );
    }

    scored.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return _dedupeNearbyCandidates(scored);
  }

  List<ProposedStationPlacement> _selectBestCandidates({
    required List<CandidateLocation> scoredCandidates,
    required List<UncoveredGap> gaps,
    required int maxSelections,
    required double safeRangeKm,
  }) {
    final selected = <ProposedStationPlacement>[];
    final coveredGapIds = <String>{};

    for (final candidate in scoredCandidates) {
      if (selected.length >= maxSelections) break;

      final tooCloseToSelected = selected.any(
        (s) =>
            _haversineKm(s.position, candidate.position) < redundancyRadiusKm,
      );
      if (tooCloseToSelected) continue;

      final solvedGapIds = <String>[];
      if (candidate.nearestGapId != null) {
        final gap =
            gaps.where((g) => g.id == candidate.nearestGapId).firstOrNull;
        if (gap != null) {
          final improved =
              candidate.expectedMaxSubGapKm <= safeRangeKm &&
              !coveredGapIds.contains(gap.id);
          if (improved) {
            solvedGapIds.add(gap.id);
          }
        }
      }

      // Prefer candidates that actually solve uncovered gaps.
      if (gaps.isNotEmpty && solvedGapIds.isEmpty && selected.isNotEmpty) {
        continue;
      }

      for (final id in solvedGapIds) {
        coveredGapIds.add(id);
      }

      selected.add(
        ProposedStationPlacement(
          id: candidate.id,
          position: candidate.position,
          rank: selected.length + 1,
          finalScore: candidate.finalScore,
          routeDistanceKm: candidate.routeDistanceKm,
          distanceToRouteKm: candidate.distanceToRouteKm,
          nearestExistingStationDistanceKm:
              candidate.nearestExistingStationDistanceKm,
          coveredGapLengthKm: candidate.coveredGapLengthKm,
          expectedMaxSubGapKm: candidate.expectedMaxSubGapKm,
          sourceType: candidate.sourceType,
          reason: _buildReasonText(candidate),
          solvedGapIds: solvedGapIds,
        ),
      );
    }

    // Fallback: if nothing was selected but candidates exist, pick the best one.
    if (selected.isEmpty && scoredCandidates.isNotEmpty) {
      final candidate = scoredCandidates.first;
      selected.add(
        ProposedStationPlacement(
          id: candidate.id,
          position: candidate.position,
          rank: 1,
          finalScore: candidate.finalScore,
          routeDistanceKm: candidate.routeDistanceKm,
          distanceToRouteKm: candidate.distanceToRouteKm,
          nearestExistingStationDistanceKm:
              candidate.nearestExistingStationDistanceKm,
          coveredGapLengthKm: candidate.coveredGapLengthKm,
          expectedMaxSubGapKm: candidate.expectedMaxSubGapKm,
          sourceType: candidate.sourceType,
          reason: _buildReasonText(candidate),
          solvedGapIds:
              candidate.nearestGapId == null
                  ? const []
                  : <String>[candidate.nearestGapId!],
        ),
      );
    }

    return selected;
  }

  double _scoreDetour(double distanceToRouteKm) {
    if (distanceToRouteKm <= 2) return 1.0;
    if (distanceToRouteKm <= 5) return 0.75;
    if (distanceToRouteKm <= 10) return 0.40;
    return 0.10;
  }

  _CoverageInfo _coverageImprovementForCandidate({
    required double routeDistanceKm,
    required UncoveredGap? nearestGap,
    required double safeRangeKm,
  }) {
    if (nearestGap == null) {
      return const _CoverageInfo(
        coverageScore: 0.10,
        coveredGapLengthKm: 0.0,
        expectedMaxSubGapKm: 0.0,
      );
    }

    final left = (routeDistanceKm - nearestGap.startRouteDistanceKm).abs();
    final right = (nearestGap.endRouteDistanceKm - routeDistanceKm).abs();
    final newMaxSubGap = math.max(left, right);

    final oldGap = nearestGap.lengthKm;
    final improvement = math.max(0.0, oldGap - newMaxSubGap);
    final improvementRatio = oldGap == 0 ? 0.0 : improvement / oldGap;

    final double feasibilityBonus = newMaxSubGap <= safeRangeKm ? 1.0 : 0.0;

    final double score =
        (0.65 * improvementRatio + 0.35 * feasibilityBonus)
            .clamp(0.0, 1.0)
            .toDouble();

    return _CoverageInfo(
      coverageScore: score,
      coveredGapLengthKm: oldGap,
      expectedMaxSubGapKm: newMaxSubGap,
    );
  }

  double _scoreAccessibility({
    required double distanceToRouteKm,
    required double routeProgressRatio,
  }) {
    final double routeProximity =
        (1.0 - (distanceToRouteKm / candidateRouteCorridorKm))
            .clamp(0.0, 1.0)
            .toDouble();

    final double centerPreference =
        (1.0 - ((routeProgressRatio - 0.5).abs() * 1.2))
            .clamp(0.0, 1.0)
            .toDouble();

    return (0.7 * routeProximity + 0.3 * centerPreference)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _scoreExistingStationDistance({
    required double nearestExistingStationDistanceKm,
  }) {
    if (nearestExistingStationDistanceKm < minDistanceFromExistingKm)
      return 0.10;
    if (nearestExistingStationDistanceKm < 20) return 0.40;
    if (nearestExistingStationDistanceKm < 40) return 0.75;
    return 1.0;
  }

  double _scoreDemandPotential({
    required UncoveredGap? nearestGap,
    required double routeDistanceKm,
    required double routeLengthKm,
  }) {
    final double gapBonus =
        nearestGap == null ? 0.15 : 0.75 + nearestGap.severityScore * 0.25;
    final double routeRatio =
        routeLengthKm == 0 ? 0.0 : routeDistanceKm / routeLengthKm;
    final double centerFactor =
        (1.0 - ((routeRatio - 0.5).abs() * 1.1)).clamp(0.0, 1.0).toDouble();

    return (0.7 * gapBonus + 0.3 * centerFactor).clamp(0.0, 1.0).toDouble();
  }

  double _scoreSuitability({
    required double distanceToRouteKm,
    required double nearestExistingStationDistanceKm,
    required UncoveredGap? nearestGap,
  }) {
    final double routeFactor =
        (1.0 - (distanceToRouteKm / candidateRouteCorridorKm))
            .clamp(0.0, 1.0)
            .toDouble();
    final double scarcityFactor = _scoreExistingStationDistance(
      nearestExistingStationDistanceKm: nearestExistingStationDistanceKm,
    );
    final double gapFactor = nearestGap == null ? 0.25 : 0.85;

    return (0.4 * routeFactor + 0.35 * scarcityFactor + 0.25 * gapFactor)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _weightedScore({
    required double detourScore,
    required double coverageScore,
    required double accessibilityScore,
    required double stationDistanceScore,
    required double demandScore,
    required double suitabilityScore,
  }) {
    final total = weights.total == 0 ? 1.0 : weights.total;

    final score =
        (weights.detour * detourScore) +
        (weights.coverage * coverageScore) +
        (weights.accessibility * accessibilityScore) +
        (weights.stationDistance * stationDistanceScore) +
        (weights.demand * demandScore) +
        (weights.suitability * suitabilityScore);

    return (score / total).clamp(0.0, 1.0).toDouble();
  }

  List<String> _buildReasonTags({
    required double detourScore,
    required double coverageScore,
    required double accessibilityScore,
    required double stationDistanceScore,
    required double demandScore,
    required double suitabilityScore,
    required UncoveredGap? nearestGap,
    required double nearestExistingStationDistanceKm,
    required double distanceToRouteKm,
  }) {
    final tags = <String>[];

    if (nearestGap != null) {
      tags.add(
        'Fills uncovered gap of ${nearestGap.lengthKm.toStringAsFixed(1)} km',
      );
    }

    if (distanceToRouteKm <= 2) {
      tags.add('Very low detour from main route');
    } else if (detourScore >= 0.7) {
      tags.add('Low detour from route');
    }

    if (nearestExistingStationDistanceKm >= 40) {
      tags.add(
        'Underserved area; nearest existing station is ${nearestExistingStationDistanceKm.toStringAsFixed(1)} km away',
      );
    } else if (stationDistanceScore >= 0.75) {
      tags.add('Good spacing from existing stations');
    }

    if (coverageScore >= 0.75) {
      tags.add('Strong coverage improvement');
    }

    if (accessibilityScore >= 0.75) {
      tags.add('High route accessibility');
    }

    if (demandScore >= 0.75) {
      tags.add('High operational demand potential');
    }

    if (suitabilityScore >= 0.75) {
      tags.add('Good installation suitability');
    }

    if (tags.isEmpty) {
      tags.add('Balanced location based on route efficiency');
    }

    return tags;
  }

  String _buildReasonText(CandidateLocation cand) {
    final parts = <String>[];

    // Priority 1: Gap Closure
    if (cand.nearestGapId != null && cand.coveredGapLengthKm > 0) {
      if (cand.expectedMaxSubGapKm <= 40) {
        parts.add(
          "Strategic Gap Solver: This location was selected to split a critical ${cand.coveredGapLengthKm.toStringAsFixed(1)}km stretch of uncovered route. By placing a station here, the largest remaining gap is reduced to a safe ${cand.expectedMaxSubGapKm.toStringAsFixed(1)}km.",
        );
      } else {
        parts.add(
          "Gap Reduction: Essential placement within a long ${cand.coveredGapLengthKm.toStringAsFixed(1)}km gap to improve overall route feasibility.",
        );
      }
    }

    // Priority 2: Network Redundancy/Safety
    if (parts.isEmpty && cand.nearestExistingStationDistanceKm >= 20) {
      parts.add(
        "Network Redundancy: Added to provide a safety buffer in an underserved area where the nearest alternative charger is ${cand.nearestExistingStationDistanceKm.toStringAsFixed(1)}km away.",
      );
    }

    // High Suitability Note
    if (cand.suitabilityScore >= 0.8 && parts.isNotEmpty) {
      parts.add("This site also shows high physical suitability for installation.");
    }

    // Low Detour Note
    if (cand.distanceToRouteKm <= 1.0) {
      parts.add("Conveniently located almost directly on the main route (under 1km detour).");
    } else if (cand.distanceToRouteKm <= 3.5) {
      parts.add("Provides excellent coverage with a minimal ${cand.distanceToRouteKm.toStringAsFixed(1)}km detour.");
    }

    if (parts.isEmpty) {
      return cand.reasonTags.join(', ');
    }

    return parts.join(' ');
  }

  List<CandidateLocation> _dedupeNearbyCandidates(
    List<CandidateLocation> candidates,
  ) {
    final selected = <CandidateLocation>[];

    for (final candidate in candidates) {
      final duplicate = selected.any(
        (s) => _haversineKm(s.position, candidate.position) < 3.0,
      );
      if (!duplicate) {
        selected.add(candidate);
      }
    }

    return selected;
  }

  RouteProjection _projectPointToRoute({
    required LatLng point,
    required List<LatLng> routePoints,
    required List<double> cumulativeKm,
  }) {
    int bestIndex = 0;
    double bestDistanceKm = double.infinity;

    for (int i = 0; i < routePoints.length; i++) {
      final d = _haversineKm(point, routePoints[i]);
      if (d < bestDistanceKm) {
        bestDistanceKm = d;
        bestIndex = i;
      }
    }

    return RouteProjection(
      nearestRouteIndex: bestIndex,
      distanceToRouteKm: bestDistanceKm,
      routeDistanceKm: cumulativeKm[bestIndex],
      snappedPoint: routePoints[bestIndex],
    );
  }

  UncoveredGap? _findNearestGapByRouteDistance(
    double routeDistanceKm,
    List<UncoveredGap> gaps,
  ) {
    if (gaps.isEmpty) return null;

    UncoveredGap? best;
    double bestMetric = double.infinity;

    for (final gap in gaps) {
      if (routeDistanceKm >= gap.startRouteDistanceKm &&
          routeDistanceKm <= gap.endRouteDistanceKm) {
        return gap;
      }

      final metric = math.min(
        (routeDistanceKm - gap.startRouteDistanceKm).abs(),
        (routeDistanceKm - gap.endRouteDistanceKm).abs(),
      );

      if (metric < bestMetric) {
        bestMetric = metric;
        best = gap;
      }
    }
    return best;
  }

  int _routeIndexForDistance(List<double> cumulativeKm, double targetKm) {
    if (targetKm <= 0) return 0;
    if (targetKm >= cumulativeKm.last) return cumulativeKm.length - 1;

    int bestIndex = 0;
    double bestDiff = double.infinity;

    for (int i = 0; i < cumulativeKm.length; i++) {
      final diff = (cumulativeKm[i] - targetKm).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  double _evaluatePlacementSet({
    required List<int> candidateIndices,
    required List<CandidateLocation> allCandidates,
    required List<UncoveredGap> gaps,
    required double safeRangeKm,
  }) {
    if (candidateIndices.isEmpty) return 0.0;

    double coverageScore = 0.0;
    double detourScore = 0.0;
    double redundancyPenalty = 0.0;

    final selected = candidateIndices.map((i) => allCandidates[i]).toList();
    final solvedGapIds = <String>{};

    for (int i = 0; i < selected.length; i++) {
      final cand = selected[i];
      detourScore += _scoreDetour(cand.distanceToRouteKm);

      // Coverage part
      if (cand.nearestGapId != null) {
        final gap = gaps.where((g) => g.id == cand.nearestGapId).firstOrNull;
        if (gap != null && !solvedGapIds.contains(gap.id)) {
          final info = _coverageImprovementForCandidate(
            routeDistanceKm: cand.routeDistanceKm,
            nearestGap: gap,
            safeRangeKm: safeRangeKm,
          );
          if (info.expectedMaxSubGapKm <= safeRangeKm) {
            coverageScore += 1.0; // Fully solves gap
            solvedGapIds.add(gap.id);
          } else {
            coverageScore += info.coverageScore * 0.5; // Partially solves
          }
        }
      }

      // Redundancy check
      for (int j = i + 1; j < selected.length; j++) {
        final d = _haversineKm(selected[i].position, selected[j].position);
        if (d < redundancyRadiusKm) {
          redundancyPenalty += (1.0 - (d / redundancyRadiusKm));
        }
      }
    }

    // Final fitness components
    // Base fitness from detour and accessibility (always > 0 for valid candidates)
    double baseScore = (detourScore * 10.0);
    
    // Safety/Redundancy Bonus: even if no gaps exist, we prefer stations 
    // that are well-spaced along the route for redundancy.
    double safetyBonus = 0.0;
    if (gaps.isEmpty) {
      // Calculate how well-spread the selected stations are
      double totalSpread = 0.0;
      for (final s in selected) {
        totalSpread += s.routeDistanceKm;
      }
      safetyBonus = (totalSpread / (allCandidates.length * 10.0)).clamp(0.0, 50.0);
    }

    return (coverageScore * 100.0) + baseScore + safetyBonus - (redundancyPenalty * 25.0);
  }

  List<ProposedStationPlacement> _selectBestCandidatesPSO({
    required List<CandidateLocation> allCandidates,
    required List<UncoveredGap> gaps,
    required int maxSelections,
    required double safeRangeKm,
    int swarmSize = 30,
    int iterations = 40,
  }) {
    if (allCandidates.isEmpty) return [];
    final n = allCandidates.length;
    final k = math.min(maxSelections, n);
    final random = math.Random();

    // Each particle is a set of k indices
    List<List<int>> particles = List.generate(swarmSize, (_) {
      final set = <int>{};
      while (set.length < k) {
        set.add(random.nextInt(n));
      }
      return set.toList();
    });

    List<double> pBestScore = List.generate(swarmSize, (i) => _evaluatePlacementSet(
          candidateIndices: particles[i],
          allCandidates: allCandidates,
          gaps: gaps,
          safeRangeKm: safeRangeKm,
        ));

    List<List<int>> pBestPos = List.generate(swarmSize, (i) => List.from(particles[i]));

    int gBestIdx = 0;
    for (int i = 1; i < swarmSize; i++) {
      if (pBestScore[i] > pBestScore[gBestIdx]) gBestIdx = i;
    }

    List<int> gBestPos = List.from(pBestPos[gBestIdx]);
    double gBestScore = pBestScore[gBestIdx];

    // PSO Iterations
    for (int iter = 0; iter < iterations; iter++) {
      for (int i = 0; i < swarmSize; i++) {
        // Discrete PSO: With some probability, swap an element with one from PBest or GBest
        for (int j = 0; j < k; j++) {
          double r = random.nextDouble();
          if (r < 0.3) {
            // Social component: learn from GBest
            particles[i][j] = gBestPos[random.nextInt(k)];
          } else if (r < 0.6) {
            // Cognitive component: learn from PBest
            particles[i][j] = pBestPos[i][random.nextInt(k)];
          } else if (r < 0.1) {
            // Random mutation
            particles[i][j] = random.nextInt(n);
          }
        }

        // Evaluate
        double score = _evaluatePlacementSet(
          candidateIndices: particles[i],
          allCandidates: allCandidates,
          gaps: gaps,
          safeRangeKm: safeRangeKm,
        );

        if (score > pBestScore[i]) {
          pBestScore[i] = score;
          pBestPos[i] = List.from(particles[i]);
        }
        if (score > gBestScore) {
          gBestScore = score;
          gBestPos = List.from(particles[i]);
        }
      }
    }

    return _convertIndicesToProposed(gBestPos, allCandidates, gaps, safeRangeKm);
  }

  List<ProposedStationPlacement> _selectBestCandidatesGA({
    required List<CandidateLocation> allCandidates,
    required List<UncoveredGap> gaps,
    required int maxSelections,
    required double safeRangeKm,
    int popSize = 30,
    int generations = 40,
  }) {
    if (allCandidates.isEmpty) return [];
    final n = allCandidates.length;
    final k = math.min(maxSelections, n);
    final random = math.Random();

    List<List<int>> population = List.generate(popSize, (_) {
      final set = <int>{};
      while (set.length < k) {
        set.add(random.nextInt(n));
      }
      return set.toList();
    });

    for (int gen = 0; gen < generations; gen++) {
      // Evaluate fitness
      final fitness = population.map((p) => _evaluatePlacementSet(
            candidateIndices: p,
            allCandidates: allCandidates,
            gaps: gaps,
            safeRangeKm: safeRangeKm,
          )).toList();

      // Selection (Tournament)
      List<List<int>> nextPop = [];
      while (nextPop.length < popSize) {
        int i1 = random.nextInt(popSize);
        int i2 = random.nextInt(popSize);
        List<int> parent = fitness[i1] > fitness[i2] ? population[i1] : population[i2];

        // Mutation & Crossover (simplified)
        List<int> child = List.from(parent);
        if (random.nextDouble() < 0.2) {
          child[random.nextInt(k)] = random.nextInt(n);
        }
        nextPop.add(child);
      }
      population = nextPop;
    }

    // Pick best from final pop
    final finalFitness = population.map((p) => _evaluatePlacementSet(
          candidateIndices: p,
          allCandidates: allCandidates,
          gaps: gaps,
          safeRangeKm: safeRangeKm,
        )).toList();

    int bestIdx = 0;
    for (int i = 1; i < popSize; i++) {
      if (finalFitness[i] > finalFitness[bestIdx]) bestIdx = i;
    }

    return _convertIndicesToProposed(population[bestIdx], allCandidates, gaps, safeRangeKm);
  }

  List<ProposedStationPlacement> _selectBestCandidatesSA({
    required List<CandidateLocation> allCandidates,
    required List<UncoveredGap> gaps,
    required int maxSelections,
    required double safeRangeKm,
    int iterations = 200,
  }) {
    if (allCandidates.isEmpty) return [];
    final n = allCandidates.length;
    final k = math.min(maxSelections, n);
    final random = math.Random();

    List<int> current = [];
    final set = <int>{};
    while (set.length < k) {
      set.add(random.nextInt(n));
    }
    current = set.toList();

    double curFit = _evaluatePlacementSet(
      candidateIndices: current,
      allCandidates: allCandidates,
      gaps: gaps,
      safeRangeKm: safeRangeKm,
    );

    List<int> best = List.from(current);
    double bestFit = curFit;

    double temp = 100.0;
    double cooling = 0.98;

    for (int i = 0; i < iterations; i++) {
      List<int> neighbor = List.from(current);
      neighbor[random.nextInt(k)] = random.nextInt(n);

      double nextFit = _evaluatePlacementSet(
        candidateIndices: neighbor,
        allCandidates: allCandidates,
        gaps: gaps,
        safeRangeKm: safeRangeKm,
      );

      double diff = nextFit - curFit;
      if (diff > 0 || random.nextDouble() < math.exp(diff / temp)) {
        current = neighbor;
        curFit = nextFit;
        if (curFit > bestFit) {
          bestFit = curFit;
          best = List.from(current);
        }
      }
      temp *= cooling;
    }

    return _convertIndicesToProposed(best, allCandidates, gaps, safeRangeKm);
  }

  List<ProposedStationPlacement> _convertIndicesToProposed(
    List<int> indices,
    List<CandidateLocation> allCandidates,
    List<UncoveredGap> gaps,
    double safeRangeKm,
  ) {
    // Unique indices only
    final uniqueIdx = indices.toSet().toList();
    final selected = uniqueIdx.map((i) => allCandidates[i]).toList();

    // Sort by route distance
    selected.sort((a, b) => a.routeDistanceKm.compareTo(b.routeDistanceKm));

    final result = <ProposedStationPlacement>[];
    final coveredGaps = <String>{};

    for (int i = 0; i < selected.length; i++) {
      final cand = selected[i];
      final solvedGapIds = <String>[];

      if (cand.nearestGapId != null) {
        final gap = gaps.where((g) => g.id == cand.nearestGapId).firstOrNull;
        if (gap != null) {
          final info = _coverageImprovementForCandidate(
            routeDistanceKm: cand.routeDistanceKm,
            nearestGap: gap,
            safeRangeKm: safeRangeKm,
          );
          if (info.expectedMaxSubGapKm <= safeRangeKm) {
            solvedGapIds.add(gap.id);
            coveredGaps.add(gap.id);
          }
        }
      }

      result.add(ProposedStationPlacement(
        id: cand.id,
        position: cand.position,
        rank: i + 1,
        finalScore: cand.finalScore,
        routeDistanceKm: cand.routeDistanceKm,
        distanceToRouteKm: cand.distanceToRouteKm,
        nearestExistingStationDistanceKm: cand.nearestExistingStationDistanceKm,
        coveredGapLengthKm: cand.coveredGapLengthKm,
        expectedMaxSubGapKm: cand.expectedMaxSubGapKm,
        sourceType: cand.sourceType,
        reason: _buildReasonText(cand),
        solvedGapIds: solvedGapIds,
      ));
    }

    return result;
  }

  double _haversineKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;

    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);

    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);

    final aa = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;

    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;
}

class _RawCandidate {
  final String id;
  final LatLng position;
  final int nearestRouteIndex;
  final double routeDistanceKm;
  final String sourceType;
  final String? nearestGapId;

  const _RawCandidate({
    required this.id,
    required this.position,
    required this.nearestRouteIndex,
    required this.routeDistanceKm,
    required this.sourceType,
    this.nearestGapId,
  });
}

class _CoverageInfo {
  final double coverageScore;
  final double coveredGapLengthKm;
  final double expectedMaxSubGapKm;

  const _CoverageInfo({
    required this.coverageScore,
    required this.coveredGapLengthKm,
    required this.expectedMaxSubGapKm,
  });
}

extension _FirstWhereOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}