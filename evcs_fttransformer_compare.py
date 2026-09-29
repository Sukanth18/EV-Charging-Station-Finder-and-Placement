import os
import json
import time
import math
import random
import warnings
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from pytorch_tabular import TabularModel
from pytorch_tabular.config import DataConfig, OptimizerConfig, TrainerConfig
from pytorch_tabular.models.ft_transformer.config import FTTransformerConfig

warnings.filterwarnings("ignore")

# ============================================================
# CONFIG
# ============================================================
CSV_PATH = "assets/EVCS.csv"
RESULTS_DIR = "saved_results_fttransformer"

N_SELECT = 10
SERVICE_RADIUS_KM = 25.0
N_RUNS = 5
SEED = 42

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


def minmax_series(s):
    s = pd.to_numeric(s, errors="coerce").fillna(0.0)
    mn, mx = s.min(), s.max()
    if abs(mx - mn) < 1e-12:
        return pd.Series(np.zeros(len(s)), index=s.index)
    return (s - mn) / (mx - mn)


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

    station_df = df.drop_duplicates(subset=["Charging Station ID"]).copy().reset_index(drop=True)

    # Fill optional columns
    if "Charger Type" not in station_df.columns:
        station_df["Charger Type"] = "Unknown"

    if "Charging Cost (USD)" not in station_df.columns:
        station_df["Charging Cost (USD)"] = 0.0

    station_df["Power_kW"] = station_df["Charger Type"].apply(infer_power_kw)

    # Capacity
    possible_capacity_cols = ["Network Capacity", "network_capacity", "Capacity", "capacity"]
    capacity_col = next((c for c in possible_capacity_cols if c in station_df.columns), None)
    if capacity_col:
        station_df["CapacityScore"] = pd.to_numeric(station_df[capacity_col], errors="coerce")
    else:
        station_df["CapacityScore"] = station_df["Power_kW"] * 2.0

    # Loss
    possible_loss_cols = ["Power Loss", "power_loss", "Loss", "loss"]
    loss_col = next((c for c in possible_loss_cols if c in station_df.columns), None)
    if loss_col:
        station_df["LossScore"] = pd.to_numeric(station_df[loss_col], errors="coerce")
    else:
        station_df["LossScore"] = 0.0

    # Voltage
    possible_voltage_cols = [
        "Voltage Regulation", "voltage_regulation",
        "Voltage Deviation", "voltage_deviation",
        "Voltage", "voltage"
    ]
    voltage_col = next((c for c in possible_voltage_cols if c in station_df.columns), None)
    if voltage_col:
        station_df["VoltageScore"] = pd.to_numeric(station_df[voltage_col], errors="coerce")
    else:
        station_df["VoltageScore"] = 0.0

    # Charging cost numeric
    station_df["Charging Cost (USD)"] = pd.to_numeric(
        station_df["Charging Cost (USD)"], errors="coerce"
    )

    # Fill numeric missing values by mean
    num_cols = station_df.select_dtypes(include=[np.number]).columns.tolist()
    for col in num_cols:
        station_df[col] = pd.to_numeric(station_df[col], errors="coerce")
        station_df[col] = station_df[col].fillna(station_df[col].mean())

    # Fill categorical missing
    cat_cols = station_df.select_dtypes(include=["object"]).columns.tolist()
    for col in cat_cols:
        station_df[col] = station_df[col].fillna("Unknown").astype(str)

    demand_df = station_df[["Latitude", "Longitude"]].copy().reset_index(drop=True)
    return station_df, demand_df

# ============================================================
# TARGET CREATION FOR TRAINING
# ============================================================
def create_suitability_target(station_df):
    cap_n = minmax_series(station_df["CapacityScore"])
    power_n = minmax_series(station_df["Power_kW"])
    voltage_n = minmax_series(station_df["VoltageScore"])
    loss_n = minmax_series(station_df["LossScore"])
    cost_n = minmax_series(station_df["Charging Cost (USD)"])

    # Higher is better
    suitability = (
        0.35 * cap_n
        + 0.25 * power_n
        + 0.20 * voltage_n
        - 0.10 * loss_n
        - 0.10 * cost_n
    )

    station_df = station_df.copy()
    station_df["SuitabilityScore"] = suitability.astype(float)
    return station_df

# ============================================================
# FT-TRANSFORMER TRAINING
# ============================================================
def train_fttransformer_model(station_df):
    df = station_df.copy()

    # Choose features
    ignore_cols = ["SuitabilityScore"]
    target_col = "SuitabilityScore"

    # Keep ID separately, not as feature
    feature_df = df.drop(columns=[], errors="ignore").copy()

    # Identify categorical and continuous columns
    categorical_cols = []
    continuous_cols = []

    for col in feature_df.columns:
        if col == target_col:
            continue
        if col == "Charging Station ID":
            continue  # not using raw ID as feature
        if feature_df[col].dtype == "object":
            categorical_cols.append(col)
        else:
            continuous_cols.append(col)

    model_df = feature_df[
        categorical_cols + continuous_cols + [target_col, "Charging Station ID"]
    ].copy()

    train_df, test_df = train_test_split(model_df, test_size=0.2, random_state=SEED)

    train_model_df = train_df.drop(columns=["Charging Station ID"]).copy()
    test_model_df = test_df.drop(columns=["Charging Station ID"]).copy()

    data_config = DataConfig(
        target=[target_col],
        continuous_cols=continuous_cols,
        categorical_cols=categorical_cols,
    )

    trainer_config = TrainerConfig(
        auto_lr_find=False,
        batch_size=64,
        max_epochs=50,
        accelerator="auto",
    )

    optimizer_config = OptimizerConfig()

    model_config = FTTransformerConfig(
        task="regression",
        learning_rate=1e-3,
        input_embed_dim=32,
        num_heads=4,
        num_attn_blocks=4,
        ff_hidden_multiplier=2,
    )

    tabular_model = TabularModel(
        data_config=data_config,
        model_config=model_config,
        optimizer_config=optimizer_config,
        trainer_config=trainer_config,
    )

    start = time.time()
    tabular_model.fit(train=train_model_df, validation=test_model_df)
    train_time = time.time() - start

    preds = tabular_model.predict(test_model_df)
    pred_col = "SuitabilityScore_prediction"
    if pred_col not in preds.columns:
        # fallback for library naming differences
        pred_candidates = [c for c in preds.columns if "prediction" in c.lower()]
        if not pred_candidates:
            raise ValueError("Prediction column not found in FT-Transformer output.")
        pred_col = pred_candidates[0]

    y_true = test_model_df[target_col].values
    y_pred = preds[pred_col].values

    metrics = {
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "r2": float(r2_score(y_true, y_pred)),
        "train_time_sec": float(train_time),
    }

    # Predict full dataset
    full_model_df = model_df.drop(columns=["Charging Station ID"]).copy()
    full_preds = tabular_model.predict(full_model_df)
    if pred_col not in full_preds.columns:
        pred_candidates = [c for c in full_preds.columns if "prediction" in c.lower()]
        pred_col = pred_candidates[0]

    station_df = station_df.copy()
    station_df["PredictedSuitability"] = full_preds[pred_col].values.astype(float)

    # Save model
    model_path = os.path.join(RESULTS_DIR, "ft_transformer_model")
    tabular_model.save_model(model_path)

    return tabular_model, station_df, metrics

# ============================================================
# BASELINE TRAINED-ONLY SELECTION
# ============================================================
def trained_model_topk_selection(problem):
    scores = problem.station_df["PredictedSuitability"].values
    idx = np.argsort(scores)[::-1][:problem.n_select]
    x = np.zeros(problem.n_sites, dtype=int)
    x[idx] = 1

    fit, metrics = problem.evaluate(x)
    metrics["avg_predicted_suitability"] = float(problem.station_df.iloc[idx]["PredictedSuitability"].mean())
    return x, fit, metrics

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
        self.max_pred_score = self.station_df["PredictedSuitability"].max() + 1e-9

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
            voltage_term = voltage_term / (self.station_df["VoltageScore"].max() + 1e-9 + 1e-9)
        else:
            util_arr = np.array(utilization_list, dtype=float)
            voltage_term = float(np.mean(np.square(util_arr)))

        avg_cost = float(pd.to_numeric(chosen["Charging Cost (USD)"], errors="coerce").fillna(0.0).mean())

        pred_score = float(chosen["PredictedSuitability"].mean())
        pred_term = pred_score / self.max_pred_score

        # lower is better
        obj = (
            0.30 * (1.0 - coverage)
            + 0.20 * loss_term
            + 0.20 * capacity_penalty
            + 0.10 * voltage_term
            + 0.20 * (1.0 - pred_term)
        )

        metrics = {
            "coverage": float(coverage),
            "loss_term": float(loss_term),
            "capacity_penalty": float(capacity_penalty),
            "voltage_term": float(voltage_term),
            "avg_cost": float(avg_cost),
            "avg_predicted_suitability": float(pred_score),
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

def mutate_binary(x, mutation_rate=0.08):
    y = x.copy()
    for i in range(len(y)):
        if np.random.rand() < mutation_rate:
            y[i] = 1 - y[i]
    return y

def hgamssa(problem, pop_size=30, ga_generations=30, ssa_iterations=40, mutation_rate=0.08):
    n = problem.n_sites
    k = problem.n_select

    population = [exact_k_binary(np.random.rand(n), k) for _ in range(pop_size)]
    fitness = [problem.evaluate(p)[0] for p in population]

    best_curve = []
    best_idx = int(np.argmin(fitness))
    best_sol = population[best_idx].copy()
    best_fit, best_metrics = problem.evaluate(best_sol)

    # GA phase
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
        fitness = [problem.evaluate(p)[0] for p in population]

        gen_best_idx = int(np.argmin(fitness))
        if fitness[gen_best_idx] < best_fit:
            best_sol = population[gen_best_idx].copy()
            best_fit, best_metrics = problem.evaluate(best_sol)

        best_curve.append(best_fit)

    # SSA phase
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
# REPORTING
# ============================================================
def save_json(obj, path):
    with open(path, "w") as f:
        json.dump(obj, f, indent=4)

def plot_convergence(curves, names, save_path):
    plt.figure(figsize=(9, 5))
    for curve, name in zip(curves, names):
        if curve is not None:
            plt.plot(curve, linewidth=2, label=name)
    plt.xlabel("Iteration / Generation")
    plt.ylabel("Best Objective")
    plt.title("Convergence Comparison")
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(save_path, dpi=300)
    plt.show()

def plot_bar(labels, values, title, ylabel, save_path):
    plt.figure(figsize=(8, 5))
    plt.bar(labels, values)
    plt.title(title)
    plt.ylabel(ylabel)
    plt.tight_layout()
    plt.savefig(save_path, dpi=300)
    plt.show()

# ============================================================
# MAIN
# ============================================================
def main():
    print("Loading dataset...")
    station_df, demand_df = load_evcs_data(CSV_PATH)

    print("Creating suitability target...")
    station_df = create_suitability_target(station_df)

    print("Training FT-Transformer...")
    model, station_df, train_metrics = train_fttransformer_model(station_df)

    print("\nFT-Transformer Training Metrics")
    print("-" * 40)
    print(f"MAE            : {train_metrics['mae']:.6f}")
    print(f"RMSE           : {train_metrics['rmse']:.6f}")
    print(f"R2             : {train_metrics['r2']:.6f}")
    print(f"Train Time(sec): {train_metrics['train_time_sec']:.4f}")

    problem = EVCSPlacementProblem(
        station_df=station_df,
        demand_df=demand_df,
        n_select=N_SELECT,
        service_radius_km=SERVICE_RADIUS_KM,
    )

    # ---------------------------
    # Baseline: trained-only
    # ---------------------------
    start = time.time()
    base_sol, base_fit, base_metrics = trained_model_topk_selection(problem)
    base_time = time.time() - start

    # ---------------------------
    # Optimized models
    # ---------------------------
    hg_runs = []
    ps_runs = []

    best_hg_curve = None
    best_ps_curve = None
    best_hg_obj = float("inf")
    best_ps_obj = float("inf")

    for run in range(N_RUNS):
        print(f"\nOptimization Run {run + 1}/{N_RUNS}")

        start = time.time()
        hg_sol, hg_fit, hg_metrics, hg_curve = hgamssa(problem)
        hg_time = time.time() - start

        hg_runs.append({
            "best_obj": hg_fit,
            "runtime_sec": hg_time,
            **hg_metrics
        })

        if hg_fit < best_hg_obj:
            best_hg_obj = hg_fit
            best_hg_curve = hg_curve
            best_hg_metrics = hg_metrics
            best_hg_time = hg_time

        start = time.time()
        ps_sol, ps_fit, ps_metrics, ps_curve = psods(problem)
        ps_time = time.time() - start

        ps_runs.append({
            "best_obj": ps_fit,
            "runtime_sec": ps_time,
            **ps_metrics
        })

        if ps_fit < best_ps_obj:
            best_ps_obj = ps_fit
            best_ps_curve = ps_curve
            best_ps_metrics = ps_metrics
            best_ps_time = ps_time

        print(f"  HGAMSSA objective : {hg_fit:.6f}")
        print(f"  PSO-DS objective  : {ps_fit:.6f}")

    hg_df = pd.DataFrame(hg_runs)
    ps_df = pd.DataFrame(ps_runs)

    comparison = pd.DataFrame([
        {
            "Model": "FT-Transformer Only",
            "Objective": base_fit,
            "Coverage": base_metrics["coverage"],
            "LossTerm": base_metrics["loss_term"],
            "CapacityPenalty": base_metrics["capacity_penalty"],
            "VoltageTerm": base_metrics["voltage_term"],
            "AvgPredictedSuitability": base_metrics["avg_predicted_suitability"],
            "AvgCost": base_metrics["avg_cost"],
            "RuntimeSec": base_time,
            "SelectedIDs": base_metrics["selected_ids"],
        },
        {
            "Model": "FT-Transformer + HGAMSSA",
            "Objective": float(hg_df["best_obj"].mean()),
            "Coverage": float(hg_df["coverage"].mean()),
            "LossTerm": float(hg_df["loss_term"].mean()),
            "CapacityPenalty": float(hg_df["capacity_penalty"].mean()),
            "VoltageTerm": float(hg_df["voltage_term"].mean()),
            "AvgPredictedSuitability": float(hg_df["avg_predicted_suitability"].mean()),
            "AvgCost": float(hg_df["avg_cost"].mean()),
            "RuntimeSec": float(hg_df["runtime_sec"].mean()),
            "SelectedIDs": best_hg_metrics["selected_ids"],
        },
        {
            "Model": "FT-Transformer + PSO-DS",
            "Objective": float(ps_df["best_obj"].mean()),
            "Coverage": float(ps_df["coverage"].mean()),
            "LossTerm": float(ps_df["loss_term"].mean()),
            "CapacityPenalty": float(ps_df["capacity_penalty"].mean()),
            "VoltageTerm": float(ps_df["voltage_term"].mean()),
            "AvgPredictedSuitability": float(ps_df["avg_predicted_suitability"].mean()),
            "AvgCost": float(ps_df["avg_cost"].mean()),
            "RuntimeSec": float(ps_df["runtime_sec"].mean()),
            "SelectedIDs": best_ps_metrics["selected_ids"],
        },
    ])

    print("\n" + "=" * 80)
    print("FINAL COMPARISON")
    print("=" * 80)
    print(comparison[[
        "Model", "Objective", "Coverage", "AvgPredictedSuitability", "AvgCost", "RuntimeSec"
    ]])

    # Save files
    station_df.to_csv(os.path.join(RESULTS_DIR, "station_predictions.csv"), index=False)
    hg_df.to_csv(os.path.join(RESULTS_DIR, "hgamssa_results.csv"), index=False)
    ps_df.to_csv(os.path.join(RESULTS_DIR, "psods_results.csv"), index=False)
    comparison.to_csv(os.path.join(RESULTS_DIR, "comparison_results.csv"), index=False)

    save_json(train_metrics, os.path.join(RESULTS_DIR, "ft_transformer_train_metrics.json"))

    best_answers = {
        "FT_Transformer_Only": {
            "objective": float(base_fit),
            "runtime_sec": float(base_time),
            **base_metrics
        },
        "FT_Transformer_HGAMSSA_Best": {
            "objective": float(best_hg_obj),
            "runtime_sec": float(best_hg_time),
            **best_hg_metrics
        },
        "FT_Transformer_PSO_DS_Best": {
            "objective": float(best_ps_obj),
            "runtime_sec": float(best_ps_time),
            **best_ps_metrics
        }
    }
    save_json(best_answers, os.path.join(RESULTS_DIR, "best_model_answers.json"))

    # Plots
    plot_convergence(
        [best_hg_curve, best_ps_curve],
        ["FT-Transformer + HGAMSSA", "FT-Transformer + PSO-DS"],
        os.path.join(RESULTS_DIR, "convergence_comparison.png")
    )

    plot_bar(
        comparison["Model"].tolist(),
        comparison["Objective"].tolist(),
        "Objective Comparison",
        "Objective Value",
        os.path.join(RESULTS_DIR, "objective_comparison.png")
    )

    plot_bar(
        comparison["Model"].tolist(),
        comparison["Coverage"].tolist(),
        "Coverage Comparison",
        "Coverage",
        os.path.join(RESULTS_DIR, "coverage_comparison.png")
    )

    plot_bar(
        comparison["Model"].tolist(),
        comparison["RuntimeSec"].tolist(),
        "Runtime Comparison",
        "Runtime (sec)",
        os.path.join(RESULTS_DIR, "runtime_comparison.png")
    )

    print(f"\nAll outputs saved in: {RESULTS_DIR}")

if __name__ == "__main__":
    main()
