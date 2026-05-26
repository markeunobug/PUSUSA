from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle


BASE_DIR = Path(__file__).resolve().parent
FIG_DIR = BASE_DIR / "figures_academic"
DOCX_PATH = BASE_DIR / "2.3.1 数字处理设计_学术框图版.docx"

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Microsoft YaHei", "SimHei", "Arial Unicode MS", "DejaVu Sans", "sans-serif"],
    "axes.unicode_minus": False,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
    "font.size": 9,
})

INK = "#111827"
MUTED = "#4B5563"
LINE = "#374151"
SOFT = "#9CA3AF"
PANEL = "#F7F8FA"
PANEL2 = "#F2F4F7"
HEADER = "#E5E7EB"
WHITE = "#FFFFFF"

RBW_ROWS = [
    ("1 kHz", 13000, 5, 256, 256, 128),
    ("10 kHz", 1300, 5, 256, 256, 128),
    ("30 kHz", 433, 5, 256, 256, 128),
    ("100 kHz", 130, 5, 128, 384, 64),
    ("300 kHz", 43, 4, 128, 384, 64),
    ("1 MHz", 13, 4, 64, 384, 32),
]


def setup_canvas(width=12.0, height=7.0):
    fig, ax = plt.subplots(figsize=(width, height))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    return fig, ax


def title(ax, main, sub):
    ax.text(0.035, 0.955, main, ha="left", va="top", fontsize=16, color=INK, fontweight="bold")
    ax.text(0.035, 0.905, sub, ha="left", va="top", fontsize=9.5, color=MUTED)


def box(ax, x, y, w, h, text, fc=WHITE, ec=LINE, fs=10, bold=False):
    patch = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.01,rounding_size=0.012",
        linewidth=1.25,
        edgecolor=ec,
        facecolor=fc,
    )
    ax.add_patch(patch)
    ax.text(
        x + w / 2,
        y + h / 2,
        text,
        ha="center",
        va="center",
        fontsize=fs,
        color=INK,
        fontweight="bold" if bold else "normal",
        linespacing=1.22,
    )


def group(ax, x, y, w, h, label):
    ax.add_patch(Rectangle((x, y), w, h, facecolor=PANEL, edgecolor=SOFT, linewidth=1.0, linestyle=(0, (5, 4))))
    ax.text(x + 0.012, y + h - 0.028, label, ha="left", va="top", fontsize=8.5, color=MUTED)


def arrow(ax, start, end, color=LINE, lw=1.4, dashed=False, rad=0.0):
    arr = FancyArrowPatch(
        start,
        end,
        arrowstyle="-|>",
        mutation_scale=12,
        linewidth=lw,
        color=color,
        linestyle=(0, (5, 4)) if dashed else "solid",
        connectionstyle=f"arc3,rad={rad}",
    )
    ax.add_patch(arr)


def save(fig, stem):
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    out = FIG_DIR / stem
    fig.savefig(out.with_suffix(".png"), dpi=300, bbox_inches="tight", facecolor="white")
    fig.savefig(out.with_suffix(".svg"), bbox_inches="tight", facecolor="white")
    fig.savefig(out.with_suffix(".pdf"), bbox_inches="tight", facecolor="white")
    fig.savefig(out.with_suffix(".tiff"), dpi=600, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def fig_overall():
    fig, ax = setup_canvas()
    title(ax, "Zynq 数字中频处理总体流程", "固定 40 MHz 中频经数字基带处理后形成可定量显示的频谱点。")
    labels = [
        "LTC2208\nADC采样\n130 MSPS",
        "AXI DMA\n4096点帧\nPS缓存",
        "DDC\n40 MHz IF\nI/Q基带",
        "CIC抽取\n按RBW降采样",
        "补偿FIR\nRBW低通\n去瞬态",
        "功率估计\nmean(I²+Q²)\ndBFS/dBm",
        "幅度校正\nUART流式\n频谱点",
    ]
    x0, y, w, h, gap = 0.035, 0.54, 0.118, 0.13, 0.022
    for i, label in enumerate(labels):
        x = x0 + i * (w + gap)
        box(ax, x, y, w, h, label, WHITE, LINE, 8.8, True)
        if i < len(labels) - 1:
            arrow(ax, (x + w + 0.003, y + h / 2), (x + w + gap - 0.004, y + h / 2))
    group(ax, 0.06, 0.28, 0.26, 0.14, "频率规划")
    box(ax, 0.085, 0.315, 0.21, 0.055, "LO1 = RF + 2.180 GHz\nLO2 = 2.220 GHz，IF2 = 40 MHz", WHITE, LINE, 8.4)
    group(ax, 0.37, 0.28, 0.26, 0.14, "扫频密度")
    box(ax, 0.395, 0.315, 0.21, 0.055, "内部步进约为 RBW / 2\n最大扫频点数 4096", WHITE, LINE, 8.4)
    group(ax, 0.68, 0.28, 0.26, 0.14, "输出方式")
    box(ax, 0.705, 0.315, 0.21, 0.055, "每个频点独立发送\n上位机实时拼接曲线", WHITE, LINE, 8.4)
    ax.text(0.06, 0.18, "主测量路径：逐频点扫频功率测量，而不是一次性上传 FFT bin。", fontsize=11.5, color=INK, fontweight="bold")
    save(fig, "fig_231_1_overall_flow")


def fig_arch():
    fig, ax = setup_canvas()
    title(ax, "Zynq 侧软件模块与数据流", "扫频状态机负责调度，本振控制、DMA、信号处理和协议输出保持清晰分层。")
    box(ax, 0.42, 0.66, 0.16, 0.10, "sweep_engine\n扫频状态机\n调度每个频点", PANEL2, LINE, 9.2, True)
    box(ax, 0.08, 0.66, 0.17, 0.09, "lo_control\n设置 LO1\n等待 PLL 锁定", WHITE, LINE, 8.8)
    box(ax, 0.08, 0.40, 0.17, 0.09, "dma_capture\nAXI DMA S2MM\n采集中频帧", WHITE, LINE, 8.8)
    box(ax, 0.41, 0.40, 0.18, 0.09, "signal_processing\nDDC + CIC + FIR\n功率估计", WHITE, LINE, 8.8)
    box(ax, 0.73, 0.40, 0.19, 0.09, "amplitude_correction\n衰减 / LNA / VGA / 频率\n输入端幅度修正", WHITE, LINE, 8.2)
    box(ax, 0.73, 0.66, 0.19, 0.09, "device_protocol\nACK / STATUS / 0x82频谱点\n流式发送", WHITE, LINE, 8.2)
    arrow(ax, (0.42, 0.71), (0.25, 0.71), dashed=True)
    arrow(ax, (0.25, 0.67), (0.42, 0.67), dashed=True)
    arrow(ax, (0.47, 0.66), (0.18, 0.49), rad=0.12)
    arrow(ax, (0.25, 0.445), (0.41, 0.445))
    arrow(ax, (0.59, 0.445), (0.73, 0.445))
    arrow(ax, (0.83, 0.49), (0.83, 0.66))
    arrow(ax, (0.73, 0.71), (0.58, 0.71), dashed=True)
    box(ax, 0.22, 0.20, 0.56, 0.075, "主循环轮询 device_protocol 与 sweep_engine；扫频活跃时以当前测量点为核心，采样、处理、发送各模块职责清晰。", PANEL, SOFT, 9.1)
    save(fig, "fig_231_2_software_arch")


def fig_state():
    fig, ax = setup_canvas()
    title(ax, "逐点扫频状态机", "每个频点独立经历锁相、采样、积累、测量、发送，适合实时显示和故障定位。")
    coords = [
        ("Prepare\n配置RBW/DDC", 0.06, 0.66),
        ("Set LO1\n切到RF频点", 0.23, 0.66),
        ("Wait Lock\n等待PLL锁定", 0.40, 0.66),
        ("Arm DMA\n启动采样", 0.57, 0.66),
        ("Accumulate\nDDC+CIC累积", 0.57, 0.40),
        ("Measure\nFIR+功率估计\n幅度校正", 0.40, 0.40),
        ("Emit Point\n发送0x82", 0.23, 0.40),
        ("Next Point\n或Done", 0.06, 0.40),
    ]
    w, h = 0.13, 0.10
    for text, x, y in coords:
        box(ax, x, y, w, h, text, WHITE, LINE, 8.7, True)
    centers = [(x + w / 2, y + h / 2) for _, x, y in coords]
    for i in range(3):
        arrow(ax, (centers[i][0] + w / 2, centers[i][1]), (centers[i + 1][0] - w / 2, centers[i + 1][1]))
    arrow(ax, (centers[3][0], centers[3][1] - h / 2), (centers[4][0], centers[4][1] + h / 2))
    arrow(ax, (centers[4][0] - w / 2, centers[4][1]), (centers[5][0] + w / 2, centers[5][1]))
    arrow(ax, (centers[5][0] - w / 2, centers[5][1]), (centers[6][0] + w / 2, centers[6][1]))
    arrow(ax, (centers[6][0] - w / 2, centers[6][1]), (centers[7][0] + w / 2, centers[7][1]))
    arrow(ax, (centers[7][0], centers[7][1] + h / 2), (centers[1][0] - w / 2, centers[1][1] - 0.01), rad=-0.33)
    box(ax, 0.78, 0.51, 0.15, 0.13, "异常保护\nLO锁定超时\nDMA超时\n功率测量失败", PANEL2, LINE, 8.5, True)
    arrow(ax, (0.64, 0.66), (0.78, 0.60), SOFT, dashed=True)
    arrow(ax, (0.64, 0.44), (0.78, 0.55), SOFT, dashed=True)
    ax.text(0.06, 0.23, "设计收益：每个频点都有完整测量闭环，可实时显示，也便于定位 DMA、锁相或信号处理瓶颈。", fontsize=10.5, color=INK, fontweight="bold")
    save(fig, "fig_231_3_sweep_state")


def fig_rbw():
    fig, ax = setup_canvas()
    title(ax, "多档 RBW 数字滤波处理链", "RBW 档位真实改变抽取比、FIR 长度和观测窗口，而不仅是显示参数。")
    labels = ["DDC后 I/Q\n基带样本", "CIC抽取\nR/N按RBW配置\n降低数据率", "补偿FIR\nRBW低通\n修正通带", "有效观测窗\n跳过瞬态\n积累功率"]
    xs = [0.08, 0.31, 0.54, 0.77]
    for i, (x, label) in enumerate(zip(xs, labels)):
        box(ax, x, 0.64, 0.15, 0.10, label, WHITE, LINE, 8.8, True)
        if i < 3:
            arrow(ax, (x + 0.15, 0.69), (xs[i + 1], 0.69))
    group(ax, 0.08, 0.28, 0.84, 0.27, "RBW 档位参数趋势")
    rbws = ["1 kHz", "10 kHz", "30 kHz", "100 kHz", "300 kHz", "1 MHz"]
    rs = [13000, 1300, 433, 130, 43, 13]
    taps = [256, 256, 256, 128, 128, 64]
    max_log = math.log10(max(rs))
    for i, (rbw, r, tap) in enumerate(zip(rbws, rs, taps)):
        y = 0.49 - i * 0.035
        ax.text(0.12, y + 0.012, rbw, ha="right", va="center", fontsize=8, color=INK, fontweight="bold")
        ax.add_patch(Rectangle((0.14, y), 0.08 + 0.18 * math.log10(r) / max_log, 0.022, facecolor="#D1D5DB", edgecolor="none"))
        ax.add_patch(Rectangle((0.49, y), 0.07 + 0.12 * tap / 256, 0.022, facecolor="#E5E7EB", edgecolor=SOFT, linewidth=0.4))
        ax.text(0.37, y + 0.012, f"R={r}, N={5 if r >= 130 else 4}", fontsize=7.5, va="center", color=MUTED)
        ax.text(0.68, y + 0.012, f"FIR={tap} taps", fontsize=7.5, va="center", color=MUTED)
    ax.text(0.14, 0.225, "窄 RBW：更大抽取比、更长观测时间；宽 RBW：更高扫速、更短处理链。", fontsize=9.5, color=INK, fontweight="bold")
    save(fig, "fig_231_4_rbw_chain")


def fig_power():
    fig, ax = setup_canvas()
    title(ax, "功率计算与输入端幅度校正", "把 RBW 滤波后的基带能量换算为 RF 输入端 dBm。")
    labels = ["RBW滤波后\nI/Q样本", "均方功率\nP = mean(I²+Q²)", "dBFS换算\n10log10(P/PFS)", "ADC输入功率\n+8.02 dBm参考"]
    xs = [0.07, 0.30, 0.53, 0.76]
    for i, (x, label) in enumerate(zip(xs, labels)):
        box(ax, x, 0.64, 0.15, 0.095, label, WHITE, LINE, 8.6, True)
        if i < 3:
            arrow(ax, (x + 0.15, 0.688), (xs[i + 1], 0.688))
    box(ax, 0.24, 0.39, 0.52, 0.09, "幅度校正项 = 衰减器 - LNA增益 - VGA增益 + 路径校准 + 频率分段校准", PANEL2, LINE, 10.0, True)
    arrow(ax, (0.835, 0.64), (0.65, 0.48), dashed=True, rad=0.16)
    arrow(ax, (0.50, 0.39), (0.50, 0.27))
    box(ax, 0.37, 0.17, 0.26, 0.08, "RF输入端幅度\n用于上位机频谱显示", WHITE, LINE, 10.5, True)
    ax.text(0.07, 0.53, "固件保留 raw power 与 correction dB，便于后续标定、误差分析和校准表迭代。", fontsize=9.3, color=MUTED)
    save(fig, "fig_231_5_power_calibration")


def fig_table():
    fig, ax = setup_canvas(width=11.8, height=6.4)
    title(ax, "当前固件 RBW 档位参数", "参数来自 app_config.h，用于 signal_processing.c 的 sweep-path 配置。")
    columns = ["RBW", "CIC R", "CIC N", "FIR taps", "Observe pts", "Skip pts", "Accum target"]
    rows = [[rbw, str(r), str(n), str(taps), str(obs), str(skip), str(obs + skip + taps)] for rbw, r, n, taps, obs, skip in RBW_ROWS]
    table = ax.table(cellText=rows, colLabels=columns, cellLoc="center", colLoc="center", bbox=[0.06, 0.20, 0.88, 0.62])
    table.auto_set_font_size(False)
    table.set_fontsize(9.2)
    for (row, col), cell in table.get_celld().items():
        cell.set_edgecolor(SOFT)
        cell.set_linewidth(0.7)
        if row == 0:
            cell.set_facecolor(HEADER)
            cell.get_text().set_color(INK)
            cell.get_text().set_fontweight("bold")
        else:
            cell.set_facecolor("#FFFFFF" if row % 2 else PANEL)
            if col == 0:
                cell.get_text().set_fontweight("bold")
    ax.text(0.06, 0.12, "注：Accum target = Observe points + Skip points + FIR taps；实际累积受 ACCUM_BUFFER_SIZE = 768 约束。", fontsize=8.7, color=MUTED)
    save(fig, "table_231_1_rbw_params")


def generate_images():
    fig_overall()
    fig_arch()
    fig_state()
    fig_rbw()
    fig_power()
    fig_table()


def generate_word():
    source = BASE_DIR / "make_231_digital_processing_figures.py"
    spec = importlib.util.spec_from_file_location("original_231", source)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load original Word generator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.FIG_DIR = FIG_DIR
    module.DOCX_PATH = DOCX_PATH
    module.generate_word()


def main():
    generate_images()
    generate_word()
    print(f"Generated academic figures: {FIG_DIR}")
    print(f"Generated Word: {DOCX_PATH}")


if __name__ == "__main__":
    main()
