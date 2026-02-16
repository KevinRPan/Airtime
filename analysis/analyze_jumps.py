#!/usr/bin/env python3
"""
Airtime - Phase 2: Offline Jump Analysis

Ingests Phase 1 CSV data from the WatchOS black box logger.
Visualizes sensor signals and helps determine optimal thresholds
for takeoff detection, landing detection, and noise filtering.

Usage:
    python analyze_jumps.py <session_directory>
    python analyze_jumps.py data/2025-03-15_143022/

The session directory should contain:
    - sensor_data.csv: Raw sensor samples at 50Hz
    - jump_events.csv: Detected jump events
    - ground_truth_marks.csv: Manual event markers
"""

import sys
import os
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from scipy.signal import butter, filtfilt, find_peaks


# ── Data Loading ──────────────────────────────────────────────────────────────

def load_session(session_dir: str) -> dict:
    """Load all CSV files from a session directory."""
    session_path = Path(session_dir)

    data = {}

    sensor_file = session_path / "sensor_data.csv"
    if sensor_file.exists():
        df = pd.read_csv(sensor_file)
        # Compute derived columns
        df["UserAccel_Mag"] = np.sqrt(
            df["UserAccel_X"]**2 + df["UserAccel_Y"]**2 + df["UserAccel_Z"]**2
        )
        df["Gravity_Mag"] = np.sqrt(
            df["Gravity_X"]**2 + df["Gravity_Y"]**2 + df["Gravity_Z"]**2
        )
        df["Time_s"] = df["Timestamp"] - df["Timestamp"].iloc[0]
        data["sensors"] = df
    else:
        print(f"Warning: {sensor_file} not found")
        data["sensors"] = pd.DataFrame()

    events_file = session_path / "jump_events.csv"
    if events_file.exists():
        data["events"] = pd.read_csv(events_file)
    else:
        data["events"] = pd.DataFrame()

    marks_file = session_path / "ground_truth_marks.csv"
    if marks_file.exists():
        data["marks"] = pd.read_csv(marks_file)
    else:
        data["marks"] = pd.DataFrame()

    return data


# ── Signal Processing ─────────────────────────────────────────────────────────

def low_pass_filter(signal: np.ndarray, cutoff_hz: float = 5.0,
                    sample_rate: float = 50.0, order: int = 4) -> np.ndarray:
    """Apply a Butterworth low-pass filter to remove high-frequency noise."""
    nyquist = sample_rate / 2.0
    normalized_cutoff = cutoff_hz / nyquist
    b, a = butter(order, normalized_cutoff, btype="low")
    return filtfilt(b, a, signal)


def detect_jumps_offline(df: pd.DataFrame,
                         takeoff_threshold: float = 1.5,
                         landing_threshold: float = 2.5,
                         min_airtime_s: float = 0.2,
                         freefall_ceiling: float = 0.4,
                         sample_rate: float = 50.0) -> list[dict]:
    """
    Offline jump detection using the same state machine as the watch app.

    Returns a list of detected jump dicts with:
        start_idx, end_idx, duration_s, yaw_degrees, peak_accel
    """
    accel_mag = df["UserAccel_Mag"].values
    rotation_z = df["RotationRate_Z"].values
    timestamps = df["Time_s"].values

    jumps = []
    state = "ground"  # ground | potential_takeoff | airborne
    jump_start_idx = 0
    accumulated_yaw = 0.0

    for i in range(len(accel_mag)):
        if state == "ground":
            if accel_mag[i] > takeoff_threshold:
                state = "potential_takeoff"
                jump_start_idx = i
                accumulated_yaw = 0.0

        elif state == "potential_takeoff":
            dt = timestamps[i] - timestamps[i - 1] if i > 0 else 1.0 / sample_rate
            accumulated_yaw += rotation_z[i] * dt

            if accel_mag[i] < freefall_ceiling:
                state = "airborne"

            elapsed = timestamps[i] - timestamps[jump_start_idx]
            if elapsed > 0.5 and accel_mag[i] > takeoff_threshold:
                state = "ground"

        elif state == "airborne":
            dt = timestamps[i] - timestamps[i - 1] if i > 0 else 1.0 / sample_rate
            accumulated_yaw += rotation_z[i] * dt

            elapsed = timestamps[i] - timestamps[jump_start_idx]

            if accel_mag[i] > landing_threshold and elapsed > min_airtime_s * 0.5:
                if elapsed >= min_airtime_s:
                    yaw_deg = np.degrees(accumulated_yaw)
                    peak = accel_mag[jump_start_idx:i + 1].max()
                    jumps.append({
                        "start_idx": jump_start_idx,
                        "end_idx": i,
                        "start_time": timestamps[jump_start_idx],
                        "end_time": timestamps[i],
                        "duration_s": elapsed,
                        "yaw_degrees": yaw_deg,
                        "peak_accel": peak,
                        "landing_impact": accel_mag[i],
                    })
                state = "ground"

            if elapsed > 5.0:
                state = "ground"

    return jumps


# ── Visualization ─────────────────────────────────────────────────────────────

def plot_session_overview(df: pd.DataFrame, jumps: list[dict],
                          takeoff_threshold: float = 1.5,
                          landing_threshold: float = 2.5):
    """Plot full session overview with detected jumps highlighted."""
    fig, axes = plt.subplots(3, 1, figsize=(16, 10), sharex=True)

    time = df["Time_s"].values

    # Plot 1: User Acceleration Magnitude
    ax = axes[0]
    ax.plot(time, df["UserAccel_Mag"], linewidth=0.5, color="steelblue",
            label="UserAccel Magnitude")
    ax.axhline(y=takeoff_threshold, color="green", linestyle="--", alpha=0.7,
               label=f"Takeoff Threshold ({takeoff_threshold}G)")
    ax.axhline(y=landing_threshold, color="red", linestyle="--", alpha=0.7,
               label=f"Landing Threshold ({landing_threshold}G)")

    for j in jumps:
        t0 = j["start_time"]
        t1 = j["end_time"]
        ax.axvspan(t0, t1, alpha=0.2, color="gold")

    ax.set_ylabel("Acceleration (G)")
    ax.set_title("User Acceleration Magnitude")
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(True, alpha=0.3)

    # Plot 2: Individual Acceleration Axes
    ax = axes[1]
    ax.plot(time, df["UserAccel_X"], linewidth=0.5, alpha=0.7, label="X")
    ax.plot(time, df["UserAccel_Y"], linewidth=0.5, alpha=0.7, label="Y")
    ax.plot(time, df["UserAccel_Z"], linewidth=0.5, alpha=0.7, label="Z")
    ax.set_ylabel("Acceleration (G)")
    ax.set_title("User Acceleration Components")
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(True, alpha=0.3)

    # Plot 3: Rotation Rate (Yaw = Z-axis)
    ax = axes[2]
    ax.plot(time, df["RotationRate_Z"], linewidth=0.5, color="purple",
            label="Yaw (Z-axis)")
    ax.plot(time, df["RotationRate_X"], linewidth=0.3, alpha=0.4, label="Roll (X)")
    ax.plot(time, df["RotationRate_Y"], linewidth=0.3, alpha=0.4, label="Pitch (Y)")

    for j in jumps:
        t0 = j["start_time"]
        t1 = j["end_time"]
        ax.axvspan(t0, t1, alpha=0.2, color="gold")

    ax.set_ylabel("Rotation Rate (rad/s)")
    ax.set_xlabel("Time (s)")
    ax.set_title("Gyroscope Rotation Rates")
    ax.legend(loc="upper right", fontsize=8)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    return fig


def plot_jump_detail(df: pd.DataFrame, jump: dict, context_s: float = 1.0,
                     sample_rate: float = 50.0):
    """Plot detailed view of a single jump with surrounding context."""
    context_samples = int(context_s * sample_rate)
    start = max(0, jump["start_idx"] - context_samples)
    end = min(len(df), jump["end_idx"] + context_samples)
    segment = df.iloc[start:end]
    time = segment["Time_s"].values

    fig, axes = plt.subplots(2, 1, figsize=(12, 6), sharex=True)

    # Acceleration
    ax = axes[0]
    ax.plot(time, segment["UserAccel_Mag"], linewidth=1, color="steelblue",
            label="Magnitude")
    ax.axvline(x=jump["start_time"], color="green", linestyle="-", alpha=0.8,
               label="Takeoff")
    ax.axvline(x=jump["end_time"], color="red", linestyle="-", alpha=0.8,
               label="Landing")
    ax.axvspan(jump["start_time"], jump["end_time"], alpha=0.15, color="gold")
    ax.set_ylabel("Acceleration (G)")
    ax.set_title(
        f"Jump: {jump['duration_s']:.2f}s | "
        f"Yaw: {jump['yaw_degrees']:.0f}° | "
        f"Peak: {jump['peak_accel']:.1f}G | "
        f"Impact: {jump['landing_impact']:.1f}G"
    )
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)

    # Rotation
    ax = axes[1]
    ax.plot(time, segment["RotationRate_Z"], linewidth=1, color="purple",
            label="Yaw (Z)")
    ax.axvline(x=jump["start_time"], color="green", linestyle="-", alpha=0.8)
    ax.axvline(x=jump["end_time"], color="red", linestyle="-", alpha=0.8)
    ax.axvspan(jump["start_time"], jump["end_time"], alpha=0.15, color="gold")
    ax.set_ylabel("Rotation (rad/s)")
    ax.set_xlabel("Time (s)")
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    return fig


def plot_threshold_sweep(df: pd.DataFrame,
                         takeoff_range: np.ndarray = None,
                         landing_range: np.ndarray = None):
    """Sweep through threshold values to visualize detection sensitivity."""
    if takeoff_range is None:
        takeoff_range = np.arange(0.5, 3.1, 0.25)
    if landing_range is None:
        landing_range = np.arange(1.0, 5.1, 0.5)

    results = []
    for to_thresh in takeoff_range:
        for ld_thresh in landing_range:
            jumps = detect_jumps_offline(df,
                                         takeoff_threshold=to_thresh,
                                         landing_threshold=ld_thresh)
            avg_duration = np.mean([j["duration_s"] for j in jumps]) if jumps else 0
            results.append({
                "takeoff_threshold": to_thresh,
                "landing_threshold": ld_thresh,
                "num_jumps": len(jumps),
                "avg_duration": avg_duration,
            })

    results_df = pd.DataFrame(results)
    pivot = results_df.pivot(index="landing_threshold",
                              columns="takeoff_threshold",
                              values="num_jumps")

    fig, ax = plt.subplots(figsize=(10, 6))
    im = ax.imshow(pivot.values, aspect="auto", cmap="YlOrRd",
                   extent=[takeoff_range[0], takeoff_range[-1],
                           landing_range[-1], landing_range[0]])
    ax.set_xlabel("Takeoff Threshold (G)")
    ax.set_ylabel("Landing Threshold (G)")
    ax.set_title("Jump Count by Threshold Combination")
    plt.colorbar(im, label="Number of Jumps Detected")
    plt.tight_layout()
    return fig


def plot_filtered_vs_raw(df: pd.DataFrame, cutoff_hz: float = 5.0):
    """Compare raw vs low-pass filtered acceleration signals."""
    fig, axes = plt.subplots(2, 1, figsize=(14, 6), sharex=True)
    time = df["Time_s"].values

    raw = df["UserAccel_Mag"].values
    filtered = low_pass_filter(raw, cutoff_hz=cutoff_hz)

    ax = axes[0]
    ax.plot(time, raw, linewidth=0.5, alpha=0.7, label="Raw")
    ax.plot(time, filtered, linewidth=1.5, color="red", label=f"LP Filter ({cutoff_hz}Hz)")
    ax.set_ylabel("Acceleration (G)")
    ax.set_title("User Acceleration Magnitude: Raw vs Filtered")
    ax.legend()
    ax.grid(True, alpha=0.3)

    ax = axes[1]
    ax.plot(time, raw - filtered, linewidth=0.5, color="gray")
    ax.set_ylabel("Residual (G)")
    ax.set_xlabel("Time (s)")
    ax.set_title("High-Frequency Noise (Raw - Filtered)")
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    return fig


def print_jump_summary(jumps: list[dict]):
    """Print a summary table of detected jumps."""
    if not jumps:
        print("No jumps detected.")
        return

    print(f"\n{'='*70}")
    print(f"{'Jump':>4}  {'Start(s)':>8}  {'Duration':>8}  {'Yaw(°)':>7}  "
          f"{'Peak(G)':>7}  {'Impact(G)':>9}")
    print(f"{'-'*70}")

    for i, j in enumerate(jumps):
        yaw_label = f"{j['yaw_degrees']:+.0f}"
        abs_yaw = abs(j["yaw_degrees"])
        if abs_yaw >= 45:
            nearest = round(abs_yaw / 90) * 90
            direction = "R" if j["yaw_degrees"] >= 0 else "L"
            yaw_label += f" ({nearest}{direction})"

        print(f"{i+1:>4}  {j['start_time']:>8.2f}  {j['duration_s']:>7.2f}s  "
              f"{yaw_label:>7}  {j['peak_accel']:>7.1f}  {j['landing_impact']:>9.1f}")

    durations = [j["duration_s"] for j in jumps]
    yaws = [abs(j["yaw_degrees"]) for j in jumps]
    print(f"{'-'*70}")
    print(f"Total: {len(jumps)} jumps | "
          f"Avg airtime: {np.mean(durations):.2f}s | "
          f"Max airtime: {np.max(durations):.2f}s | "
          f"Max rotation: {np.max(yaws):.0f}°")
    print(f"{'='*70}\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    session_dir = sys.argv[1]
    if not os.path.isdir(session_dir):
        print(f"Error: Directory not found: {session_dir}")
        sys.exit(1)

    print(f"Loading session from: {session_dir}")
    data = load_session(session_dir)
    df = data["sensors"]

    if df.empty:
        print("No sensor data found.")
        sys.exit(1)

    duration = df["Time_s"].iloc[-1]
    sample_count = len(df)
    effective_rate = sample_count / duration if duration > 0 else 0
    print(f"Session: {duration:.1f}s | {sample_count} samples | ~{effective_rate:.0f}Hz")

    # Detect jumps with default thresholds
    jumps = detect_jumps_offline(df)
    print_jump_summary(jumps)

    # Generate plots
    output_dir = Path(session_dir) / "plots"
    output_dir.mkdir(exist_ok=True)

    print("Generating plots...")

    fig = plot_session_overview(df, jumps)
    fig.savefig(output_dir / "session_overview.png", dpi=150)
    plt.close(fig)

    fig = plot_filtered_vs_raw(df)
    fig.savefig(output_dir / "filtered_vs_raw.png", dpi=150)
    plt.close(fig)

    fig = plot_threshold_sweep(df)
    fig.savefig(output_dir / "threshold_sweep.png", dpi=150)
    plt.close(fig)

    for i, jump in enumerate(jumps):
        fig = plot_jump_detail(df, jump)
        fig.savefig(output_dir / f"jump_{i+1:02d}_detail.png", dpi=150)
        plt.close(fig)

    print(f"Plots saved to: {output_dir}")


if __name__ == "__main__":
    main()
