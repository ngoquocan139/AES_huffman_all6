#!/usr/bin/env python3
"""Generate the thesis comparison chart for Figure 4.11."""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.patches import Patch
import numpy as np


OUT_PATH = Path("/mnt/h/Academic/senior_project/DATN/docs/figure_4_11_evaluation_performance_comparison.png")


def annotate_bars(ax, bars, fmt: str, y_offset: float = 0.8) -> None:
    for rect in bars:
        value = rect.get_height()
        ax.annotate(
            fmt.format(value),
            (rect.get_x() + rect.get_width() / 2, value),
            xytext=(0, y_offset),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=8,
        )


def style_axis(ax) -> None:
    ax.grid(axis="y", color="#e5e7eb", linewidth=0.9)
    ax.set_axisbelow(True)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def main() -> None:
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "axes.titlesize": 11,
            "axes.labelsize": 10,
            "xtick.labelsize": 9,
            "ytick.labelsize": 9,
        }
    )

    fig = plt.figure(figsize=(16.8, 9.4), constrained_layout=False)
    fig.patch.set_facecolor("white")
    gs = GridSpec(2, 6, figure=fig, hspace=0.62, wspace=0.55)

    color_our = "#f28c28"
    color_github_sw = "#9aa6bd"
    color_github_rtl = "#3f7fcd"
    color_stdlib = "#2a9d8f"
    color_official = "#7b61ff"
    color_paper = "#d9534f"

    fig.suptitle(
        "Evaluation and Performance Comparison",
        fontsize=19,
        fontweight="bold",
        y=0.985,
    )
    fig.text(0.5, 0.925, "Hardware Baselines", ha="center", fontsize=14, fontweight="bold")
    fig.text(0.5, 0.46, "Software and Paper Baselines", ha="center", fontsize=14, fontweight="bold")

    # Hardware chart A: AES block efficiency.
    ax = fig.add_subplot(gs[0, 0:3])
    labels = [
        "Our Design",
        "secworks/\naes",
        "Rex1110/\nAES-128",
        "yeshvanth-m/\nAES-128",
        "OpenTitan\nAES",
    ]
    values = [
        16.0 / 11.0,
        16.0 / 46.0,
        16.0 / 10.0,
        16.0 / 10.0,
        16.0 / 12.0,
    ]
    colors = [color_our, color_github_rtl, color_github_rtl, color_github_rtl, color_official]
    bars = ax.bar(np.arange(len(values)), values, color=colors, edgecolor="white")
    ax.set_title("AES Block Efficiency", fontweight="bold")
    ax.set_ylabel("Effective bytes per cycle")
    ax.set_xticks(np.arange(len(values)), labels)
    ax.set_ylim(0, 1.8)
    style_axis(ax)
    annotate_bars(ax, bars, "{:.3f}")

    # Hardware chart B: throughput at normalized 100 MHz.
    ax = fig.add_subplot(gs[0, 3:6])
    labels = [
        "Our Design",
        "secworks/\naes",
        "Rex1110/\nAES-128",
        "yeshvanth-m/\nAES-128",
        "OpenTitan\nAES",
    ]
    values = [
        (16.0 / 11.0) * 100.0,
        (16.0 / 46.0) * 100.0,
        (16.0 / 10.0) * 100.0,
        (16.0 / 10.0) * 100.0,
        (16.0 / 12.0) * 100.0,
    ]
    colors = [color_our, color_github_rtl, color_github_rtl, color_github_rtl, color_official]
    bars = ax.bar(np.arange(len(values)), values, color=colors, edgecolor="white")
    ax.set_title("AES Throughput at 100 MHz (16-byte blocks)", fontweight="bold")
    ax.set_ylabel("Throughput (MB/s)")
    ax.set_xticks(np.arange(len(values)), labels)
    ax.set_ylim(0, 180)
    style_axis(ax)
    annotate_bars(ax, bars, "{:.1f}")

    # Software chart A: secure-storage TX efficiency against RV32I AES software.
    ax = fig.add_subplot(gs[1, 0:2])
    labels = [
        "Our Design\nTX",
        "aadomn\nsemi-fix",
        "aadomn\nfull-fix",
        "aadomn\nbarrel-128",
        "aadomn\nbarrel-256",
    ]
    values = [
        2551.0 / 32633.0,
        1.0 / 93.4,
        1.0 / 89.3,
        1.0 / 78.9,
        1.0 / 105.7,
    ]
    colors = [color_our, color_github_sw, color_github_sw, color_github_sw, color_github_sw]
    bars = ax.bar(np.arange(len(values)), values, color=colors, edgecolor="white")
    ax.set_title("2551-byte Secure-Storage TX Efficiency", fontweight="bold")
    ax.set_ylabel("Effective bytes per cycle")
    ax.set_xticks(np.arange(len(values)), labels)
    ax.set_ylim(0, 0.09)
    style_axis(ax)
    annotate_bars(ax, bars, "{:.3f}")

    # Software chart B: Huffman-only payload saving on the ECG set.
    ax = fig.add_subplot(gs[1, 2:4])
    labels = [
        "Our Design",
        "drichardson",
        "zlib-9",
        "bz2-9",
        "lzma-6",
    ]
    values = [
        100.0 - 55.72,
        100.0 - 58.53,
        41.16210666518675,
        42.88806260058827,
        44.991397968810695,
    ]
    colors = [color_our, color_github_sw, color_stdlib, color_stdlib, color_stdlib]
    bars = ax.bar(np.arange(len(values)), values, color=colors, edgecolor="white")
    ax.set_title("Payload Saving on 18,019 Preprocessed ECG Bytes", fontweight="bold")
    ax.set_ylabel("Saving (%)")
    ax.set_xticks(np.arange(len(values)), labels)
    ax.set_ylim(38, 46.5)
    style_axis(ax)
    annotate_bars(ax, bars, "{:.2f}%")

    # Software chart C: compressed/stored size against the raw ECG reference size.
    ax = fig.add_subplot(gs[1, 4:6])
    labels = [
        "Our Design",
        "ECG paper",
        "drichardson",
        "zlib-9",
        "bz2-9",
        "lzma-6",
    ]
    values = [
        70.13,
        64.985,
        (1.0 - (0.5853 * 18019.0) / 36000.0) * 100.0,
        (1.0 - 10602.0 / 36000.0) * 100.0,
        (1.0 - 10291.0 / 36000.0) * 100.0,
        (1.0 - 9912.0 / 36000.0) * 100.0,
    ]
    colors = [color_our, color_paper, color_github_sw, color_stdlib, color_stdlib, color_stdlib]
    bars = ax.bar(np.arange(len(values)), values, color=colors, edgecolor="white")
    ax.set_title("Saved vs 36,000 Raw ECG Bytes", fontweight="bold")
    ax.set_ylabel("Saving (%)")
    ax.set_xticks(np.arange(len(values)), labels)
    ax.set_ylim(62, 74)
    style_axis(ax)
    annotate_bars(ax, bars, "{:.2f}%")

    legend_handles = [
        Patch(facecolor=color_our, label="Our Design"),
        Patch(facecolor=color_github_rtl, label="GitHub RTL: secworks/aes, Rex1110/AES-128, yeshvanth-m/AES-128"),
        Patch(facecolor=color_official, label="Official docs: OpenTitan AES"),
        Patch(facecolor=color_github_sw, label="GitHub software: aadomn/aes, drichardson/huffman"),
        Patch(facecolor=color_stdlib, label="Python stdlib: zlib, bz2, lzma"),
        Patch(facecolor=color_paper, label="Research paper: ECG Huffman + CBC-AES (FGCS 2019)"),
    ]
    fig.legend(
        handles=legend_handles,
        ncol=2,
        loc="lower center",
        bbox_to_anchor=(0.5, 0.01),
        frameon=False,
        fontsize=9,
    )

    fig.subplots_adjust(left=0.05, right=0.985, top=0.88, bottom=0.14, hspace=0.68, wspace=0.55)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_PATH, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(OUT_PATH)


if __name__ == "__main__":
    main()
