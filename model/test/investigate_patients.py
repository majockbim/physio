"""
Investigate why Stroke5 and Stroke9 are systematically misclassified as healthy.

Outputs:
- Console: statistical fingerprints per stroke patient + ND cohort
- Console: ranking of stroke patients by how "healthy-like" their signals are
- model/test/signal_comparison.png: visual comparison of raw IMU signals

Run from anywhere: python model/test/investigate_patients.py
"""
import os
import sys
import glob
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt

# Make src importable
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(SCRIPT_DIR, "..", "src")
sys.path.insert(0, SRC_DIR)

from data_loader import JUIMUDataset  # for get_patient_data side-aware sensor selection

DATA_BASE = "/home/ethan/projects/LAHacks2026/data/"
ROM_DIR = DATA_BASE + "ROM/"
ADL_DIR = DATA_BASE + "ADL/"
ROM_INFO = DATA_BASE + "ROM_participants.csv"
ADL_INFO = DATA_BASE + "ADL_participants.csv"

ROM_MOVEMENTS = ["ElbFlex", "ShFlex90", "ShHorAdd", "FrontSupPro"]
ADL_MOVEMENTS = ["TakePill", "PourWater", "BrushTeeth"]


def load_patient_signal(file_path, info_path):
    """Load a single CSV, extract the 12 hemiparesis-aware channels, return (T, 12) numpy."""
    df = pd.read_csv(file_path)
    # Reuse JUIMUDataset's side-aware logic without instantiating full dataset
    dummy = JUIMUDataset([file_path], info_path, [0])
    cols = dummy.get_patient_data(df, file_path, info_path)
    return df[cols].values.astype(np.float32)


def compute_features(signal):
    """
    Return per-signal statistical fingerprint.
    signal: (T, 12) array. First 6 = accel, last 6 = gyro.
    """
    T = signal.shape[0]
    accel = signal[:, 0:6]   # 2 sensors x 3 axes
    gyro = signal[:, 6:12]

    # Per-channel stats then averaged
    feats = {}
    feats["seq_length"] = T
    feats["accel_magnitude"] = float(np.mean(np.linalg.norm(accel.reshape(T, 2, 3), axis=2)))
    feats["gyro_magnitude"] = float(np.mean(np.linalg.norm(gyro.reshape(T, 2, 3), axis=2)))
    feats["accel_std"] = float(np.std(accel))
    feats["gyro_std"] = float(np.std(gyro))
    # Range (peak-to-peak) per channel, averaged
    feats["accel_range"] = float(np.mean(accel.max(axis=0) - accel.min(axis=0)))
    feats["gyro_range"] = float(np.mean(gyro.max(axis=0) - gyro.min(axis=0)))
    # Jerk = third derivative magnitude (smoothness inverse)
    if T >= 4:
        jerk = np.diff(accel, n=3, axis=0)
        feats["jerk"] = float(np.mean(np.abs(jerk)))
    else:
        feats["jerk"] = 0.0
    # Smoothness via spectral arc length proxy: ratio of high-freq to total energy
    fft_mag = np.abs(np.fft.rfft(accel, axis=0))
    total_energy = fft_mag.sum() + 1e-9
    half = fft_mag.shape[0] // 2
    feats["high_freq_ratio"] = float(fft_mag[half:].sum() / total_energy)
    return feats


def gather_files_for_patient(patient_id):
    """Return list of (file_path, info_path) tuples for ALL movements of a single patient."""
    out = []
    for mov in ROM_MOVEMENTS:
        for f in glob.glob(os.path.join(ROM_DIR, f"*_{patient_id}_{mov}.csv")):
            out.append((f, ROM_INFO))
    for mov in ADL_MOVEMENTS:
        for f in glob.glob(os.path.join(ADL_DIR, f"*_{patient_id}_{mov}.csv")):
            out.append((f, ADL_INFO))
    return out


def get_all_patient_ids():
    """Scan filenames to find every unique patient ID across all directories."""
    ids = set()
    for d in [ROM_DIR, ADL_DIR]:
        for f in glob.glob(os.path.join(d, "*.csv")):
            pid = os.path.basename(f).split("_")[1]
            ids.add(pid)
    nd = sorted([p for p in ids if p.startswith("ND")], key=lambda x: int(x[2:]))
    stroke = sorted([p for p in ids if p.startswith("Stroke")], key=lambda x: int(x[6:]))
    return nd, stroke


def patient_fingerprint(patient_id):
    """Average feature dict across all of a patient's movements."""
    files = gather_files_for_patient(patient_id)
    if not files:
        return None
    all_feats = []
    for fpath, info in files:
        try:
            sig = load_patient_signal(fpath, info)
            all_feats.append(compute_features(sig))
        except Exception as e:
            print(f"  WARN: failed to load {os.path.basename(fpath)}: {e}")
    if not all_feats:
        return None
    keys = all_feats[0].keys()
    return {k: float(np.mean([f[k] for f in all_feats])) for k in keys}


def print_table(rows, title):
    print(f"\n{'='*90}")
    print(title)
    print('='*90)
    if not rows:
        return
    keys = list(rows[0][1].keys())
    header = f"{'Patient':<10}" + "".join(f"{k:>14}" for k in keys)
    print(header)
    print("-" * len(header))
    for pid, feats in rows:
        line = f"{pid:<10}" + "".join(f"{feats[k]:>14.2f}" for k in keys)
        print(line)


def cohort_summary(rows, label):
    """Mean ± std across a cohort."""
    if not rows:
        return {}
    keys = list(rows[0][1].keys())
    summary = {}
    for k in keys:
        vals = [r[1][k] for r in rows]
        summary[k] = (float(np.mean(vals)), float(np.std(vals)))
    print(f"\n[{label}] cohort mean ± std (n={len(rows)}):")
    for k, (m, s) in summary.items():
        print(f"  {k:<22} {m:>10.2f} ± {s:.2f}")
    return summary


def zscore_vs_cohort(target_feats, cohort_summary_dict):
    """How many std-devs is the target patient from the cohort mean?"""
    z = {}
    for k, val in target_feats.items():
        m, s = cohort_summary_dict.get(k, (0, 1))
        if s < 1e-6:
            z[k] = 0.0
        else:
            z[k] = (val - m) / s
    return z


def plot_signal_comparison(patients_to_plot, movement, save_path):
    """Plot 6-axis IMU signal for one movement across selected patients."""
    fig, axes = plt.subplots(len(patients_to_plot), 2, figsize=(14, 2.4 * len(patients_to_plot)))
    if len(patients_to_plot) == 1:
        axes = axes.reshape(1, 2)

    for row, (pid, label_color) in enumerate(patients_to_plot):
        files = gather_files_for_patient(pid)
        match = [f for f in files if movement in f[0]]
        if not match:
            axes[row, 0].set_title(f"{pid} — no {movement} data")
            continue
        fpath, info = match[0]
        sig = load_patient_signal(fpath, info)
        T = sig.shape[0]
        t = np.arange(T)

        # Left: accelerometer (channels 0-5)
        ax = axes[row, 0]
        for c in range(6):
            ax.plot(t, sig[:, c], linewidth=0.7, alpha=0.8)
        ax.set_title(f"{pid} - {movement} - Accel (T={T})", color=label_color)
        ax.set_xlabel("timestep")
        ax.grid(alpha=0.3)

        # Right: gyroscope (channels 6-11)
        ax = axes[row, 1]
        for c in range(6, 12):
            ax.plot(t, sig[:, c], linewidth=0.7, alpha=0.8)
        ax.set_title(f"{pid} - {movement} - Gyro", color=label_color)
        ax.set_xlabel("timestep")
        ax.grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(save_path, dpi=110, bbox_inches="tight")
    plt.close(fig)
    print(f"\nSaved plot to: {save_path}")


def main():
    print("="*90)
    print("PATIENT INVESTIGATION: why are Stroke5 / Stroke9 misclassified?")
    print("="*90)

    nd_ids, stroke_ids = get_all_patient_ids()
    print(f"\nFound {len(nd_ids)} ND patients, {len(stroke_ids)} Stroke patients")
    print(f"ND: {nd_ids}")
    print(f"Stroke: {stroke_ids}")

    print("\nComputing fingerprints for all ND patients...")
    nd_rows = []
    for pid in nd_ids:
        fp = patient_fingerprint(pid)
        if fp is not None:
            nd_rows.append((pid, fp))

    print("Computing fingerprints for all Stroke patients...")
    stroke_rows = []
    for pid in stroke_ids:
        fp = patient_fingerprint(pid)
        if fp is not None:
            stroke_rows.append((pid, fp))

    # Cohort summaries
    nd_summary = cohort_summary(nd_rows, "ND (healthy)")
    stroke_summary = cohort_summary(stroke_rows, "Stroke (all)")

    # Per-stroke-patient table
    print_table(stroke_rows, "Per-stroke-patient fingerprints (averaged across all their movements)")

    # Z-scores vs ND for each stroke patient: how "ND-like" do they look?
    print("\n" + "="*90)
    print("Z-SCORE OF EACH STROKE PATIENT vs ND COHORT")
    print("(values close to 0 mean the patient's signals look like a healthy person)")
    print("="*90)
    keys_to_show = ["seq_length", "accel_magnitude", "gyro_magnitude",
                    "accel_range", "gyro_range", "jerk", "high_freq_ratio"]
    header = f"{'Patient':<10}" + "".join(f"{k:>16}" for k in keys_to_show) + f"{'|abs_z|_avg':>14}"
    print(header)
    print("-" * len(header))
    nd_likeness = []
    for pid, feats in stroke_rows:
        z = zscore_vs_cohort(feats, nd_summary)
        avg_abs = float(np.mean([abs(z[k]) for k in keys_to_show]))
        nd_likeness.append((pid, avg_abs, z))
        line = f"{pid:<10}" + "".join(f"{z[k]:>16.2f}" for k in keys_to_show) + f"{avg_abs:>14.2f}"
        print(line)

    # Rank stroke patients by how ND-like they are
    nd_likeness.sort(key=lambda x: x[1])
    print("\n" + "="*90)
    print("STROKE PATIENTS RANKED BY ND-LIKENESS (most healthy-looking first)")
    print("='*90 - lower |abs_z|_avg means more similar to healthy cohort")
    print("="*90)
    for pid, avg_abs, _ in nd_likeness:
        bar = "#" * max(1, int(avg_abs * 5))
        print(f"  {pid:<10} avg|z|={avg_abs:.2f}  {bar}")

    # Visual comparison
    print("\nGenerating signal comparison plot for ElbFlex...")
    patients_to_plot = [
        ("ND25", "green"),
        ("ND30", "green"),
        ("Stroke6", "red"),     # severely impaired - model gets right
        ("Stroke10", "red"),    # severely impaired
        ("Stroke5", "orange"),  # mild - model misclassifies
        ("Stroke9", "orange"),  # mild - model misclassifies
    ]
    save_path = os.path.join(SCRIPT_DIR, "signal_comparison.png")
    plot_signal_comparison(patients_to_plot, "ElbFlex", save_path)

    # Final verdict
    print("\n" + "="*90)
    print("INTERPRETATION HINTS")
    print("="*90)
    s5 = next((x for x in nd_likeness if x[0] == "Stroke5"), None)
    s9 = next((x for x in nd_likeness if x[0] == "Stroke9"), None)
    s6 = next((x for x in nd_likeness if x[0] == "Stroke6"), None)
    if s5 and s6:
        print(f"  Stroke5 avg|z|={s5[1]:.2f}, Stroke6 avg|z|={s6[1]:.2f}")
        if s5[1] < s6[1] * 0.7:
            print("  -> Stroke5 statistically much closer to ND than Stroke6: likely MILD CASE.")
        elif s5[1] > 3:
            print("  -> Stroke5 is far from ND; misclassification is a MODEL issue, not data.")
        else:
            print("  -> Stroke5 is moderately ND-like; both data and model factors at play.")
    if s9:
        print(f"  Stroke9 avg|z|={s9[1]:.2f}")


if __name__ == "__main__":
    main()
