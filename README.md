# Project Technical Documentation: EV Routing & Optimization

## 1. Dataset Features & Characteristics
The system utilizes a comprehensive EV Infrastructure dataset (`EVCS_INDIA_NEW.csv`) with the following feature set:

| Feature Category | Specific Attributes |
| :--- | :--- |
| **Location Data** | Charging Station Name, Address, City, State, Latitude, Longitude |
| **Infrastructure** | Charging Station ID, Charger Type (AC/DC), Charging Rate (kW) |
| **Operational Data** | Charging Start/End Time, Energy Consumed (kWh), Charging Duration |
| **Vehicle Metrics** | Vehicle Model, Battery Capacity (kWh), Vehicle Type (Bike/Car) |
| **Performance Data** | State of Charge (Start/End %), Distance Driven, Temperature |

---

## 2. Metaheuristic Model Parameters
The project compares three advanced optimization algorithms to solve the multi-objective routing problem.

### A. PSO-DS (Particle Swarm Optimization for Dynamic Stations)
*   **Swarm Size**: 20 particles (representing candidate solution vectors).
*   **Max Iterations**: 35.
*   **Inertia Weight ($w$):** 0.7 (Balances exploration of the map vs. exploitation of known good stations).
*   **Cognitive Constant ($c1$):** 1.5 (Weight given to the particle's own best-found station).
*   **Social Constant ($c2$):** 1.5 (Weight given to the swarm's global best station).

### B. Genetic Algorithm (GA)
*   **Population Size**: 20.
*   **Generations**: 40.
*   **Mutation Rate**: 0.15 (15% chance to "jump" to a new random station to avoid local optima).
*   **Selection Method**: Tournament Selection (Ensures the fittest routes survive).

### C. Simulated Annealing (SA)
*   **Initial Temperature**: 10.0.
*   **Cooling Rate**: 0.95 (Exponential decay).
*   **Iterations**: 120 (More iterations for finer local search).

---

## 3. Critical VIVA Points (Technical Justification)

### Q: Why use Metaheuristics over standard A* or Dijkstra?
**A:** Standard routing algorithms only optimize for **distance**. Our project requires multi-objective optimization: **Trip Time + Energy Consumption + Detour Distance + Charger Speed**. Metaheuristics like PSO-DS can find a "near-optimal" solution in a high-dimensional search space much faster than exhaustive search.

### Q: What is the Fitness Function?
**A:** The fitness function is the "brain" of the optimization. It weights:
*   **30%** Source-to-Station Distance.
*   **25%** Station-to-Destination Distance.
*   **20%** Detour Overhead.
*   **10%** Charging Time Required.
*   **15%** Energy consumed.
*   **Penalty**: A massive penalty (+10.0) is added if the station cannot sustain the mission (Reachability check).

### Q: What is the "DS" in PSO-DS?
**A:** It stands for **Direct-Search**. Unlike static models, our implementation dynamically captures the real-time "Reachability" and "Power Level" of stations based on the vehicle's specific state-of-charge (SoC).

### Q: Explain the Confusion Matrix in this context.
**A:** It measures the **Reliability of the Selection Logic**. 
*   **True Positive (TP)**: The algorithm predicted a reachable station, and it was actually reachable.
*   **False Positive (FP)**: The algorithm suggested an unreachable station (Failure).
*   Our goal is to maximize TP and minimize FP to ensure the user never gets stranded.

### Q: Key Contribution?
**A:** Transitioning EV routing from a simple "nearest charger" search to a **Total Mission Time** optimizer that accounts for fast-charging infrastructure availability.
