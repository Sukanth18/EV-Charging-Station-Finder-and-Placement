import os
import json
import time
import math
import random
import itertools
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# ============================================================
# CONFIG
# ============================================================
CSV_PATH = "EVCS.csv"
RESULTS_DIR = "saved_results"

N_SELECT = 10
SERVICE_RADIUS_KM = 25.0
N_RUNS = 10
SEED = 42

# Fine-tuning search space for PSO-DS
PSO_TUNE_SWARM_SIZES = [20, 30]
PSO_TUNE_ITERATIONS = [40, 60]
PSO_TUNE_W = [0.6, 0.72]
PSO_TUNE_C1 = [1.3, 1.49]
PSO_TUNE_C2 = [1.3, 1.49]

os.makedirs(RESULTS_DIR, exist_ok=True)

random.seed(SEED)
np.random.seed(SEED)

# ============================================================
# HELPERS
# ============================================================
def haversine(lat1, lon1, lat2, lon2):
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def exact_k_binary(vec, k):
    vec = np.asarray(vec, dtype=float)
    idx = np.argsort(vec)[::-1]
    out = np.zeros(len(vec), dtype=int)
    out[idx[:k]] = 1
    return out


def infer_power_kw(charger_type):
    s = str(charger_type).lower()
    if "dc" in s or "rapid" in s or "supercharger" in s:
        return 50.0
    if "level 2" in s or "ac" in s:
        return 7.4
    return 3.3


# ============================================================
# DATA PREP
# ============================================================
def load_evcs_data(csv_path):
    df = pd.read_csv(csv_path)
    df.columns = [str(c).strip() for c in df.columns]

    required = ["Charging Station ID", "Charging Station Location", "Latitude", "Longitude"]
    for col in required:
        if col not in df.columns:
            raise ValueError(f"Missing required column: {col}")

    station_df = df.drop_duplicates(subset=["Charging Station ID"]).copy()

    if "Charger Type" not in station_df.columns:
        station_df["Charger Type"] = "Unknown"

    if "Charging Cost (USD)" not in station_df.columns:
        station_df["Charging Cost (USD)"] = 0.0

    station_df["Power_kW"] = station_df["Charger Type"].apply(infer_power_kw)

    possible_capacity_cols = ["Network Capacity", "network_capacity", "Capacity", "capacity"]
    capacity_col = None
    for c in possible_capacity_cols:
        if c in station_df.columns:
            capacity_col = c
            break

    if capacity_col:
        station_df["CapacityScore"] = pd.to_numeric(
            station_df[capacity_col], errors="coerce"
        ).fillna(0.0)
    else:
        station_df["CapacityScore"] = station_df["Power_kW"] * 2.0

    possible_loss_cols = ["Power Loss", "power_loss", "Loss", "loss"]
    loss_col = None
    for c in possible_loss_cols:
        if c in station_df.columns:
            loss_col = c
            break

    if loss_col:
        station_df["LossScore"] = pd.to_numeric(
            station_df[loss_col], errors="coerce"
        ).fillna(0.0)
    else:
        station_df["LossScore"] = 0.0

    possible_voltage_cols = [
        "Voltage Regulation",
        "voltage_regulation",
        "Voltage Deviation",
        "voltage_deviation",
        "Voltage",
        "voltage",
    ]
    voltage_col = None
    for c in possible_voltage_cols:
        if c in station_df.columns:
            voltage_col = c
            break

    if voltage_col:
        station_df["VoltageScore"] = pd.to_numeric(
            station_df[voltage_col], errors="coerce"
        ).fillna(0.0)
    else:
        station_df["VoltageScore"] = np.nan

    demand_df = station_df[["Latitude", "Longitude"]].copy().reset_index(drop=True)

    return station_df.reset_index(drop=True), demand_df


# ============================================================
# OBJECTIVE FUNCTION
# ============================================================
class EVCSPlacementProblem:
    def __init__(self, station_df, demand_df, n_select=10, service_radius_km=25.0):
        self.station_df = station_df.reset_index(drop=True)
        self.demand_df = demand_df.reset_index(drop=True)
        self.n_sites = len(station_df)
        self.n_select = n_select
        self.service_radius_km = service_radius_km

        self.dist_matrix = np.zeros((len(self.demand_df), len(self.station_df)), dtype=float)
        for i, d in self.demand_df.iterrows():
            for j, s in self.station_df.iterrows():
                self.dist_matrix[i, j] = haversine(
                    d["Latitude"], d["Longitude"], s["Latitude"], s["Longitude"]
                )

        self.max_mean_dist = np.mean(self.dist_matrix.max(axis=1)) + 1e-9
        self.max_capacity = self.station_df["CapacityScore"].max() + 1e-9

    def evaluate(self, x):
        x = exact_k_binary(x, self.n_select)
        selected_idx = np.where(x == 1)[0]

        if len(selected_idx) == 0:
            return 1e9, {}

        chosen = self.station_df.iloc[selected_idx]

        selected_dists = self.dist_matrix[:, selected_idx]
        min_dists = selected_dists.min(axis=1)
        covered = (min_dists <= self.service_radius_km).sum()
        coverage = covered / len(self.demand_df)

        if self.station_df["LossScore"].sum() > 0:
            loss_term = chosen["LossScore"].mean()
            loss_term = loss_term / (self.station_df["LossScore"].max() + 1e-9)
        else:
            loss_term = float(np.mean(min_dists) / self.max_mean_dist)

        nearest_local_idx = np.argmin(selected_dists, axis=1)
        assigned_site_indices = selected_idx[nearest_local_idx]
        assigned_counts = pd.Series(assigned_site_indices).value_counts().to_dict()

        capacity_penalty = 0.0
        utilization_list = []
        for site_i in selected_idx:
            assigned = assigned_counts.get(site_i, 0)
            capacity = float(self.station_df.loc[site_i, "CapacityScore"])
            util = assigned / max(capacity, 1e-9)
            utilization_list.append(util)
            if util > 1.0:
                capacity_penalty += (util - 1.0)

        capacity_penalty = capacity_penalty / max(len(selected_idx), 1)

        if self.station_df["VoltageScore"].notna().sum() > 0:
            voltage_term = chosen["VoltageScore"].mean()
            voltage_term = voltage_term / (self.station_df["VoltageScore"].max() + 1e-9)
        else:
            util_arr = np.array(utilization_list, dtype=float)
            voltage_term = float(np.mean(np.square(util_arr)))

        if "Charging Cost (USD)" in chosen.columns:
            avg_cost = float(
                pd.to_numeric(chosen["Charging Cost (USD)"], errors="coerce").fillna(0.0).mean()
            )
        else:
            avg_cost = 0.0

        obj = (
            0.40 * (1.0 - coverage)
            + 0.25 * loss_term
            + 0.20 * capacity_penalty
            + 0.15 * voltage_term
        )

        metrics = {
            "coverage": float(coverage),
            "loss_term": float(loss_term),
            "capacity_penalty": float(capacity_penalty),
            "voltage_term": float(voltage_term),
            "avg_cost": float(avg_cost),
            "selected_ids": chosen["Charging Station ID"].astype(str).tolist(),
        }
        return float(obj), metrics


# ============================================================
# HGAMSSA
# ============================================================
def tournament_select(pop, fits, k=3):
    idx = np.random.choice(len(pop), size=k, replace=False)
    best = idx[np.argmin([fits[i] for i in idx])]
    return pop[best].copy()


def crossover_exact_k(p1, p2, k):
    alpha = np.random.rand(len(p1))
    child = alpha * p1 + (1 - alpha) * p2
    return exact_k_binary(child, k)


def mutate_binary(x, mutation_rate=0.1):
    y = x.copy()
    for i in range(len(y)):
        if np.random.rand() < mutation_rate:
            y[i] = 1 - y[i]
    return y


def hgamssa(problem, pop_size=30, ga_generations=30, ssa_iterations=40, mutation_rate=0.08):
    n = problem.n_sites
    k = problem.n_select

    population = [exact_k_binary(np.random.rand(n), k) for _ in range(pop_size)]
    fitness = []
    for p in population:
        f, _ = problem.evaluate(p)
        fitness.append(f)

    best_curve = []
    best_idx = int(np.argmin(fitness))
    best_sol = population[best_idx].copy()
    best_fit, best_metrics = problem.evaluate(best_sol)

    for _ in range(ga_generations):
        new_pop = []
        elite_idx = np.argsort(fitness)[:2]
        for ei in elite_idx:
            new_pop.append(population[ei].copy())

        while len(new_pop) < pop_size:
            p1 = tournament_select(population, fitness)
            p2 = tournament_select(population, fitness)
            child = crossover_exact_k(p1, p2, k)
            child = mutate_binary(child, mutation_rate)
            child = exact_k_binary(child, k)
            new_pop.append(child)

        population = new_pop
        fitness = []
        for p in population:
            f, _ = problem.evaluate(p)
            fitness.append(f)

        gen_best_idx = int(np.argmin(fitness))
        if fitness[gen_best_idx] < best_fit:
            best_sol = population[gen_best_idx].copy()
            best_fit, best_metrics = problem.evaluate(best_sol)

        best_curve.append(best_fit)

    salps = [np.random.rand(n) for _ in range(pop_size)]
    salps[0] = best_sol.astype(float)

    leader = salps[0].copy()
    leader_fit, leader_metrics = problem.evaluate(exact_k_binary(leader, k))

    for t in range(ssa_iterations):
        c1 = 2 * math.exp(-((4 * t / max(ssa_iterations, 1)) ** 2))

        for i in range(pop_size):
            if i == 0:
                c2 = np.random.rand(n)
                c3 = np.random.rand(n)
                new_pos = leader.copy()
                plus_mask = c3 >= 0.5
                minus_mask = ~plus_mask
                new_pos[plus_mask] = leader[plus_mask] + c1 * c2[plus_mask]
                new_pos[minus_mask] = leader[minus_mask] - c1 * c2[minus_mask]
                salps[i] = np.clip(new_pos, 0, 1)
            else:
                salps[i] = np.clip((salps[i] + salps[i - 1]) / 2.0, 0, 1)

            candidate = exact_k_binary(salps[i], k)
            cand_fit, cand_metrics = problem.evaluate(candidate)
            if cand_fit < leader_fit:
                leader = salps[i].copy()
                leader_fit = cand_fit
                leader_metrics = cand_metrics

        if leader_fit < best_fit:
            best_fit = leader_fit
            best_metrics = leader_metrics
            best_sol = exact_k_binary(leader, k)

        best_curve.append(best_fit)

    return best_sol, best_fit, best_metrics, best_curve


# ============================================================
# PSO-DS
# ============================================================
def direct_search_local(problem, gbest, max_swaps=8):
    current = gbest.copy()
    current_fit, current_metrics = problem.evaluate(current)

    selected = list(np.where(current == 1)[0])
    unselected = list(np.where(current == 0)[0])

    np.random.shuffle(selected)
    np.random.shuffle(unselected)

    tried = 0
    for s in selected:
        for u in unselected:
            candidate = current.copy()
            candidate[s] = 0
            candidate[u] = 1
            cand_fit, cand_metrics = problem.evaluate(candidate)
            tried += 1
            if cand_fit < current_fit:
                return candidate, cand_fit, cand_metrics
            if tried >= max_swaps:
                return current, current_fit, current_metrics

    return current, current_fit, current_metrics


def psods(problem, swarm_size=30, iterations=60, w=0.72, c1=1.49, c2=1.49):
    n = problem.n_sites
    k = problem.n_select

    pos = np.random.rand(swarm_size, n)
    vel = np.random.uniform(-1, 1, size=(swarm_size, n))

    pbest = np.array([exact_k_binary(p, k) for p in pos])
    pbest_fit = np.zeros(swarm_size)
    pbest_metrics = []

    for i in range(swarm_size):
        pbest_fit[i], m = problem.evaluate(pbest[i])
        pbest_metrics.append(m)

    g_idx = int(np.argmin(pbest_fit))
    gbest = pbest[g_idx].copy()
    gbest_fit = float(pbest_fit[g_idx])
    gbest_metrics = pbest_metrics[g_idx]

    curve = [gbest_fit]

    for _ in range(iterations):
        for i in range(swarm_size):
            r1 = np.random.rand(n)
            r2 = np.random.rand(n)

            vel[i] = (
                w * vel[i]
                + c1 * r1 * (pbest[i] - pos[i])
                + c2 * r2 * (gbest - pos[i])
            )

            pos[i] = np.clip(pos[i] + vel[i], 0, 1)
            candidate = exact_k_binary(pos[i], k)
            cand_fit, cand_metrics = problem.evaluate(candidate)

            if cand_fit < pbest_fit[i]:
                pbest[i] = candidate.copy()
                pbest_fit[i] = cand_fit
                pbest_metrics[i] = cand_metrics

                if cand_fit < gbest_fit:
                    gbest = candidate.copy()
                    gbest_fit = cand_fit
                    gbest_metrics = cand_metrics

        refined, refined_fit, refined_metrics = direct_search_local(problem, gbest)
        if refined_fit < gbest_fit:
            gbest = refined.copy()
            gbest_fit = refined_fit
            gbest_metrics = refined_metrics

        curve.append(gbest_fit)

    return gbest, gbest_fit, gbest_metrics, curve


# ============================================================
# FINE TUNING
# ============================================================
def tune_psods(problem):
    tuning_results = []
    best_config = None
    best_score = float("inf")

    configs = list(itertools.product(
        PSO_TUNE_SWARM_SIZES,
        PSO_TUNE_ITERATIONS,
        PSO_TUNE_W,
        PSO_TUNE_C1,
        PSO_TUNE_C2
    ))

    print("\nStarting PSO-DS fine-tuning...")
    print(f"Total parameter combinations: {len(configs)}")

    for idx, (swarm_size, iterations, w, c1, c2) in enumerate(configs, start=1):
        scores = []
        runtimes = []

        for _ in range(3):
            start = time.time()
            _, fit, metrics, _ = psods(
                problem,
                swarm_size=swarm_size,
                iterations=iterations,
                w=w,
                c1=c1,
                c2=c2,
            )
            elapsed = time.time() - start
            scores.append(fit)
            runtimes.append(elapsed)

        mean_score = float(np.mean(scores))
        std_score = float(np.std(scores))
        mean_runtime = float(np.mean(runtimes))

        row = {
            "swarm_size": swarm_size,
            "iterations": iterations,
            "w": w,
            "c1": c1,
            "c2": c2,
            "mean_obj": mean_score,
            "std_obj": std_score,
            "mean_runtime_sec": mean_runtime,
        }
        tuning_results.append(row)

        print(
            f"[{idx}/{len(configs)}] "
            f"swarm={swarm_size}, iter={iterations}, w={w}, c1={c1}, c2={c2} "
            f"=> mean_obj={mean_score:.6f}"
        )

        if mean_score < best_score:
            best_score = mean_score
            best_config = row.copy()

    tuning_df = pd.DataFrame(tuning_results)
    tuning_df.to_csv(os.path.join(RESULTS_DIR, "psods_tuning_results.csv"), index=False)

    with open(os.path.join(RESULTS_DIR, "best_psods_config.json"), "w") as f:
        json.dump(best_config, f, indent=4)

    return best_config, tuning_df


# ============================================================
# REPORTING / SAVING
# ============================================================
def summarize_results(results, algo_name):
    df = pd.DataFrame(results)
    print("\n" + "=" * 70)
    print(algo_name)
    print("=" * 70)
    print(df[
        [
            "best_obj",
            "coverage",
            "loss_term",
            "capacity_penalty",
            "voltage_term",
            "runtime_sec",
        ]
    ].agg(["mean", "std", "min", "max"]).round(4))
    return df


def save_best_answers(hg_df, ps_df, tuned_ps_df, best_psods_config):
    best_hg_run = hg_df.loc[hg_df["best_obj"].idxmin()]
    best_ps_run = ps_df.loc[ps_df["best_obj"].idxmin()]
    best_tuned_ps_run = tuned_ps_df.loc[tuned_ps_df["best_obj"].idxmin()]

    best_answers = {
        "HGAMSSA": {
            "best_objective": float(best_hg_run["best_obj"]),
            "coverage": float(best_hg_run["coverage"]),
            "loss_term": float(best_hg_run["loss_term"]),
            "capacity_penalty": float(best_hg_run["capacity_penalty"]),
            "voltage_term": float(best_hg_run["voltage_term"]),
            "avg_cost": float(best_hg_run["avg_cost"]),
            "runtime_sec": float(best_hg_run["runtime_sec"]),
            "selected_ids": list(best_hg_run["selected_ids"]),
        },
        "PSO_DS_Default": {
            "best_objective": float(best_ps_run["best_obj"]),
            "coverage": float(best_ps_run["coverage"]),
            "loss_term": float(best_ps_run["loss_term"]),
            "capacity_penalty": float(best_ps_run["capacity_penalty"]),
            "voltage_term": float(best_ps_run["voltage_term"]),
            "avg_cost": float(best_ps_run["avg_cost"]),
            "runtime_sec": float(best_ps_run["runtime_sec"]),
            "selected_ids": list(best_ps_run["selected_ids"]),
        },
        "PSO_DS_FineTuned": {
            "best_objective": float(best_tuned_ps_run["best_obj"]),
            "coverage": float(best_tuned_ps_run["coverage"]),
            "loss_term": float(best_tuned_ps_run["loss_term"]),
            "capacity_penalty": float(best_tuned_ps_run["capacity_penalty"]),
            "voltage_term": float(best_tuned_ps_run["voltage_term"]),
            "avg_cost": float(best_tuned_ps_run["avg_cost"]),
            "runtime_sec": float(best_tuned_ps_run["runtime_sec"]),
            "selected_ids": list(best_tuned_ps_run["selected_ids"]),
            "best_parameters": best_psods_config,
        },
    }

    with open(os.path.join(RESULTS_DIR, "best_model_answers.json"), "w") as f:
        json.dump(best_answers, f, indent=4)

    return best_hg_run, best_ps_run, best_tuned_ps_run


def save_summary(hg_df, ps_df, tuned_ps_df):
    with open(os.path.join(RESULTS_DIR, "summary.txt"), "w") as f:
        f.write("HGAMSSA vs PSO-DS Comparison Summary\n")
        f.write("=" * 60 + "\n\n")

        f.write("HGAMSSA (Base Model)\n")
        f.write(f"Mean Objective: {hg_df['best_obj'].mean():.6f}\n")
        f.write(f"Mean Coverage: {hg_df['coverage'].mean():.6f}\n")
        f.write(f"Std Objective: {hg_df['best_obj'].std():.6f}\n")
        f.write(f"Mean Runtime: {hg_df['runtime_sec'].mean():.6f} sec\n\n")

        f.write("PSO-DS (Default)\n")
        f.write(f"Mean Objective: {ps_df['best_obj'].mean():.6f}\n")
        f.write(f"Mean Coverage: {ps_df['coverage'].mean():.6f}\n")
        f.write(f"Std Objective: {ps_df['best_obj'].std():.6f}\n")
        f.write(f"Mean Runtime: {ps_df['runtime_sec'].mean():.6f} sec\n\n")

        f.write("PSO-DS (Fine-Tuned)\n")
        f.write(f"Mean Objective: {tuned_ps_df['best_obj'].mean():.6f}\n")
        f.write(f"Mean Coverage: {tuned_ps_df['coverage'].mean():.6f}\n")
        f.write(f"Std Objective: {tuned_ps_df['best_obj'].std():.6f}\n")
        f.write(f"Mean Runtime: {tuned_ps_df['runtime_sec'].mean():.6f} sec\n\n")


def plot_convergence(best_hg_curve, best_ps_curve, best_tuned_curve):
    plt.figure(figsize=(8, 5))
    if best_hg_curve is not None:
        plt.plot(best_hg_curve, label="HGAMSSA", linewidth=2)
    if best_ps_curve is not None:
        plt.plot(best_ps_curve, label="PSO-DS Default", linewidth=2)
    if best_tuned_curve is not None:
        plt.plot(best_tuned_curve, label="PSO-DS Fine-Tuned", linewidth=2)

    plt.xlabel("Iteration / Generation")
    plt.ylabel("Best Objective Value")
    plt.title("Convergence Comparison")
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "convergence_comparison.png"), dpi=300)
    plt.show()


def plot_metric_comparison(hg_df, ps_df, tuned_ps_df):
    metric_names = [
        "best_obj",
        "coverage",
        "loss_term",
        "capacity_penalty",
        "voltage_term",
        "runtime_sec",
    ]

    hg_means = [hg_df[m].mean() for m in metric_names]
    ps_means = [ps_df[m].mean() for m in metric_names]
    tuned_means = [tuned_ps_df[m].mean() for m in metric_names]

    x = np.arange(len(metric_names))
    width = 0.25

    plt.figure(figsize=(11, 5))
    plt.bar(x - width, hg_means, width, label="HGAMSSA")
    plt.bar(x, ps_means, width, label="PSO-DS Default")
    plt.bar(x + width, tuned_means, width, label="PSO-DS Fine-Tuned")
    plt.xticks(x, metric_names, rotation=20)
    plt.title("Mean Performance Comparison")
    plt.legend()
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "metric_comparison.png"), dpi=300)
    plt.show()


def plot_runtime_comparison(hg_df, ps_df, tuned_ps_df):
    labels = ["HGAMSSA", "PSO-DS Default", "PSO-DS Fine-Tuned"]
    values = [
        hg_df["runtime_sec"].mean(),
        ps_df["runtime_sec"].mean(),
        tuned_ps_df["runtime_sec"].mean(),
    ]

    plt.figure(figsize=(7, 5))
    plt.bar(labels, values)
    plt.ylabel("Average Runtime (sec)")
    plt.title("Runtime Comparison")
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "runtime_comparison.png"), dpi=300)
    plt.show()


# ============================================================
# MAIN
# ============================================================
def main():
    station_df, demand_df = load_evcs_data(CSV_PATH)
    problem = EVCSPlacementProblem(
        station_df=station_df,
        demand_df=demand_df,
        n_select=N_SELECT,
        service_radius_km=SERVICE_RADIUS_KM,
    )

    best_psods_config, tuning_df = tune_psods(problem)

    hgamssa_runs = []
    psods_runs = []
    tuned_psods_runs = []

    best_hg_curve = None
    best_ps_curve = None
    best_tuned_curve = None

    best_hg_obj = float("inf")
    best_ps_obj = float("inf")
    best_tuned_obj = float("inf")

    for run in range(N_RUNS):
        print(f"\nRun {run + 1}/{N_RUNS}")

        start = time.time()
        hg_sol, hg_fit, hg_metrics, hg_curve = hgamssa(problem)
        hg_time = time.time() - start

        hgamssa_runs.append({
            "best_obj": hg_fit,
            "coverage": hg_metrics["coverage"],
            "loss_term": hg_metrics["loss_term"],
            "capacity_penalty": hg_metrics["capacity_penalty"],
            "voltage_term": hg_metrics["voltage_term"],
            "avg_cost": hg_metrics["avg_cost"],
            "runtime_sec": hg_time,
            "selected_ids": hg_metrics["selected_ids"],
        })

        if hg_fit < best_hg_obj:
            best_hg_obj = hg_fit
            best_hg_curve = hg_curve

        start = time.time()
        ps_sol, ps_fit, ps_metrics, ps_curve = psods(problem)
        ps_time = time.time() - start

        psods_runs.append({
            "best_obj": ps_fit,
            "coverage": ps_metrics["coverage"],
            "loss_term": ps_metrics["loss_term"],
            "capacity_penalty": ps_metrics["capacity_penalty"],
            "voltage_term": ps_metrics["voltage_term"],
            "avg_cost": ps_metrics["avg_cost"],
            "runtime_sec": ps_time,
            "selected_ids": ps_metrics["selected_ids"],
        })

        if ps_fit < best_ps_obj:
            best_ps_obj = ps_fit
            best_ps_curve = ps_curve

        start = time.time()
        tuned_sol, tuned_fit, tuned_metrics, tuned_curve = psods(
            problem,
            swarm_size=int(best_psods_config["swarm_size"]),
            iterations=int(best_psods_config["iterations"]),
            w=float(best_psods_config["w"]),
            c1=float(best_psods_config["c1"]),
            c2=float(best_psods_config["c2"]),
        )
        tuned_time = time.time() - start

        tuned_psods_runs.append({
            "best_obj": tuned_fit,
            "coverage": tuned_metrics["coverage"],
            "loss_term": tuned_metrics["loss_term"],
            "capacity_penalty": tuned_metrics["capacity_penalty"],
            "voltage_term": tuned_metrics["voltage_term"],
            "avg_cost": tuned_metrics["avg_cost"],
            "runtime_sec": tuned_time,
            "selected_ids": tuned_metrics["selected_ids"],
        })

        if tuned_fit < best_tuned_obj:
            best_tuned_obj = tuned_fit
            best_tuned_curve = tuned_curve

        print("  HGAMSSA best objective       :", round(hg_fit, 6))
        print("  PSO-DS default objective    :", round(ps_fit, 6))
        print("  PSO-DS tuned objective      :", round(tuned_fit, 6))

    hg_df = summarize_results(hgamssa_runs, "HGAMSSA (Base Model)")
    ps_df = summarize_results(psods_runs, "PSO-DS (Default)")
    tuned_ps_df = summarize_results(tuned_psods_runs, "PSO-DS (Fine-Tuned)")

    print("\n" + "=" * 70)
    print("FINAL COMPARISON")
    print("=" * 70)
    print("Lower objective is better.")
    print("Higher coverage is better.\n")

    print("HGAMSSA mean objective        :", round(hg_df["best_obj"].mean(), 6))
    print("PSO-DS default mean objective :", round(ps_df["best_obj"].mean(), 6))
    print("PSO-DS tuned mean objective   :", round(tuned_ps_df["best_obj"].mean(), 6))
    print()
    print("HGAMSSA mean coverage         :", round(hg_df["coverage"].mean(), 6))
    print("PSO-DS default mean coverage  :", round(ps_df["coverage"].mean(), 6))
    print("PSO-DS tuned mean coverage    :", round(tuned_ps_df["coverage"].mean(), 6))
    print()
    print("HGAMSSA mean runtime          :", round(hg_df["runtime_sec"].mean(), 6), "sec")
    print("PSO-DS default mean runtime   :", round(ps_df["runtime_sec"].mean(), 6), "sec")
    print("PSO-DS tuned mean runtime     :", round(tuned_ps_df["runtime_sec"].mean(), 6), "sec")

    hg_df.to_csv(os.path.join(RESULTS_DIR, "hgamssa_results.csv"), index=False)
    ps_df.to_csv(os.path.join(RESULTS_DIR, "psods_results.csv"), index=False)
    tuned_ps_df.to_csv(os.path.join(RESULTS_DIR, "psods_tuned_results.csv"), index=False)

    best_hg_run, best_ps_run, best_tuned_ps_run = save_best_answers(
        hg_df, ps_df, tuned_ps_df, best_psods_config
    )

    save_summary(hg_df, ps_df, tuned_ps_df)
    plot_convergence(best_hg_curve, best_ps_curve, best_tuned_curve)
    plot_metric_comparison(hg_df, ps_df, tuned_ps_df)
    plot_runtime_comparison(hg_df, ps_df, tuned_ps_df)

    print("\nBest HGAMSSA station IDs:")
    print(best_hg_run["selected_ids"])

    print("\nBest PSO-DS Default station IDs:")
    print(best_ps_run["selected_ids"])

    print("\nBest PSO-DS Fine-Tuned station IDs:")
    print(best_tuned_ps_run["selected_ids"])

    print("\nBest PSO-DS parameters:")
    print(best_psods_config)

    print(f"\nAll results saved inside folder: {RESULTS_DIR}")


if __name__ == "__main__":
    main()