from __future__ import annotations

import html
import time
import xml.etree.ElementTree as ET
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
OUT_PATH = BASE_DIR / "2.3.1 数字处理设计.drawio"

COLORS = {
    "ink": "#263238",
    "muted": "#667085",
    "line": "#9AA7B2",
    "blue": "#DCE9FF",
    "blue_stroke": "#5B8DEF",
    "teal": "#DDF3F1",
    "teal_stroke": "#52B6B0",
    "green": "#E3F2E7",
    "green_stroke": "#5BAE6B",
    "amber": "#F8EBD7",
    "amber_stroke": "#D99A3D",
    "rose": "#F6DFE3",
    "rose_stroke": "#D8737F",
    "violet": "#E9E5FA",
    "violet_stroke": "#8B7BD3",
    "gray": "#F3F5F7",
    "gray_stroke": "#B7C0C8",
}


class Diagram:
    def __init__(self, name: str, width: int = 1600, height: int = 950):
        self.name = name
        self.width = width
        self.height = height
        self.next_id = 2
        self.root = ET.Element(
            "mxGraphModel",
            {
                "dx": str(width),
                "dy": str(height),
                "grid": "1",
                "gridSize": "10",
                "guides": "1",
                "tooltips": "1",
                "connect": "1",
                "arrows": "1",
                "fold": "1",
                "page": "1",
                "pageScale": "1",
                "pageWidth": str(width),
                "pageHeight": str(height),
                "math": "0",
                "shadow": "0",
            },
        )
        self.mxroot = ET.SubElement(self.root, "root")
        ET.SubElement(self.mxroot, "mxCell", {"id": "0"})
        ET.SubElement(self.mxroot, "mxCell", {"id": "1", "parent": "0"})

    def _id(self) -> str:
        value = str(self.next_id)
        self.next_id += 1
        return value

    @staticmethod
    def text(value: str) -> str:
        return html.escape(value).replace("\n", "<br>")

    def title(self, title: str, subtitle: str):
        self.label(
            70,
            42,
            1180,
            44,
            title,
            size=28,
            bold=True,
            align="left",
            color=COLORS["ink"],
        )
        self.label(
            70,
            90,
            1220,
            34,
            subtitle,
            size=16,
            align="left",
            color=COLORS["muted"],
        )

    def label(self, x, y, w, h, text, size=16, bold=False, align="center", color=None):
        color = color or COLORS["ink"]
        style = (
            "text;html=1;strokeColor=none;fillColor=none;"
            f"align={align};verticalAlign=middle;whiteSpace=wrap;rounded=0;"
            f"fontSize={size};fontColor={color};"
        )
        if bold:
            style += "fontStyle=1;"
        return self.vertex(x, y, w, h, text, style)

    def box(self, x, y, w, h, text, fill, stroke, size=16, bold=False, rounded=True):
        style = (
            f"rounded={1 if rounded else 0};whiteSpace=wrap;html=1;"
            f"fillColor={fill};strokeColor={stroke};strokeWidth=2;"
            "arcSize=14;spacing=12;align=center;verticalAlign=middle;"
            f"fontSize={size};fontColor={COLORS['ink']};"
        )
        if bold:
            style += "fontStyle=1;"
        return self.vertex(x, y, w, h, text, style)

    def group_box(self, x, y, w, h, text, fill="#FFFFFF", stroke=None):
        stroke = stroke or COLORS["gray_stroke"]
        style = (
            f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
            "strokeWidth=2;arcSize=8;dashed=1;dashPattern=8 6;"
            f"fontSize=15;fontColor={COLORS['muted']};align=left;verticalAlign=top;spacing=12;"
        )
        return self.vertex(x, y, w, h, text, style)

    def vertex(self, x, y, w, h, text, style):
        cell = ET.SubElement(
            self.mxroot,
            "mxCell",
            {
                "id": self._id(),
                "value": self.text(text),
                "style": style,
                "vertex": "1",
                "parent": "1",
            },
        )
        ET.SubElement(
            cell,
            "mxGeometry",
            {"x": str(x), "y": str(y), "width": str(w), "height": str(h), "as": "geometry"},
        )
        return cell.attrib["id"]

    def edge(self, source, target, label="", stroke=None, dashed=False):
        stroke = stroke or COLORS["line"]
        style = (
            f"edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;"
            f"html=1;endArrow=block;endFill=1;strokeColor={stroke};strokeWidth=2;"
            "fontSize=13;fontColor=#667085;"
        )
        if dashed:
            style += "dashed=1;dashPattern=8 6;"
        cell = ET.SubElement(
            self.mxroot,
            "mxCell",
            {
                "id": self._id(),
                "value": self.text(label),
                "style": style,
                "edge": "1",
                "parent": "1",
                "source": source,
                "target": target,
            },
        )
        ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
        return cell.attrib["id"]

    def edge_points(self, source, target, points, label="", stroke=None, dashed=False):
        stroke = stroke or COLORS["line"]
        style = (
            f"edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;"
            f"html=1;endArrow=block;endFill=1;strokeColor={stroke};strokeWidth=2;"
            "fontSize=13;fontColor=#667085;"
        )
        if dashed:
            style += "dashed=1;dashPattern=8 6;"
        cell = ET.SubElement(
            self.mxroot,
            "mxCell",
            {
                "id": self._id(),
                "value": self.text(label),
                "style": style,
                "edge": "1",
                "parent": "1",
                "source": source,
                "target": target,
            },
        )
        geo = ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
        arr = ET.SubElement(geo, "Array", {"as": "points"})
        for x, y in points:
            ET.SubElement(arr, "mxPoint", {"x": str(x), "y": str(y)})
        return cell.attrib["id"]

    def table_cell(self, x, y, w, h, text, fill="#FFFFFF", bold=False):
        stroke = "#D0D5DD"
        style = (
            f"rounded=0;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
            "strokeWidth=1;align=center;verticalAlign=middle;spacing=6;"
            f"fontSize=15;fontColor={COLORS['ink']};"
        )
        if bold:
            style += "fontStyle=1;"
        return self.vertex(x, y, w, h, text, style)


def page_overall_flow() -> Diagram:
    d = Diagram("图2.3.1-1 总体流程", 1700, 1000)
    d.title("Zynq 数字中频处理总体流程", "从固定 40 MHz 中频到可定量显示的频谱点。版式按报告阅读优化，减少交叉和拥挤。")
    y = 305
    w = 170
    h = 118
    gap = 42
    labels = [
        ("LTC2208\nADC采样\n130 MSPS", COLORS["blue"], COLORS["blue_stroke"]),
        ("AXI DMA\n4096点帧\nPS缓存", COLORS["blue"], COLORS["blue_stroke"]),
        ("DDC\n40 MHz IF\nI/Q基带", COLORS["teal"], COLORS["teal_stroke"]),
        ("CIC抽取\n按RBW降采样", COLORS["teal"], COLORS["teal_stroke"]),
        ("补偿FIR\nRBW低通\n去瞬态", COLORS["green"], COLORS["green_stroke"]),
        ("功率估计\nmean(I²+Q²)\ndBFS/dBm", COLORS["amber"], COLORS["amber_stroke"]),
        ("幅度校正\nUART流式\n频谱点", COLORS["rose"], COLORS["rose_stroke"]),
    ]
    ids = []
    x = 80
    for text, fill, stroke in labels:
        ids.append(d.box(x, y, w, h, text, fill, stroke, size=17, bold=True))
        x += w + gap
    for a, b in zip(ids, ids[1:]):
        d.edge(a, b)
    d.group_box(86, 555, 430, 150, "频率规划", "#FFFFFF", COLORS["blue_stroke"])
    d.box(130, 615, 340, 58, "LO1 = RF + 2.180 GHz\nLO2 = 2.220 GHz，IF2 = 40 MHz", COLORS["gray"], COLORS["gray_stroke"], size=16)
    d.group_box(635, 555, 430, 150, "扫频密度", "#FFFFFF", COLORS["teal_stroke"])
    d.box(682, 615, 335, 58, "内部步进约为 RBW / 2\n最大扫频点数 4096", COLORS["gray"], COLORS["gray_stroke"], size=16)
    d.group_box(1180, 555, 430, 150, "输出方式", "#FFFFFF", COLORS["rose_stroke"])
    d.box(1224, 615, 340, 58, "每个频点独立发送\n上位机实时拼接频谱曲线", COLORS["gray"], COLORS["gray_stroke"], size=16)
    d.label(80, 800, 1260, 42, "主测量路径：逐频点扫频功率测量，而不是一次性上传 FFT bin。", size=22, bold=True, align="left")
    return d


def page_software_arch() -> Diagram:
    d = Diagram("图2.3.1-2 软件架构", 1700, 1000)
    d.title("Zynq 侧软件模块与数据流", "扫频状态机负责调度，本振控制、DMA、信号处理和协议输出保持清晰分层。")
    core = d.box(720, 210, 260, 115, "sweep_engine\n扫频状态机\n调度每个频点", COLORS["violet"], COLORS["violet_stroke"], size=18, bold=True)
    lo = d.box(170, 220, 250, 100, "lo_control\n设置 LO1\n等待 PLL 锁定", COLORS["blue"], COLORS["blue_stroke"], size=17)
    dma = d.box(170, 500, 250, 105, "dma_capture\nAXI DMA S2MM\n采集中频帧", COLORS["teal"], COLORS["teal_stroke"], size=17)
    sp = d.box(700, 500, 300, 105, "signal_processing\nDDC + CIC + FIR\n功率估计", COLORS["green"], COLORS["green_stroke"], size=17)
    cal = d.box(1230, 500, 300, 105, "amplitude_correction\n衰减 / LNA / VGA / 频率\n输入端幅度修正", COLORS["amber"], COLORS["amber_stroke"], size=16)
    proto = d.box(1230, 220, 300, 105, "device_protocol\nACK / STATUS / 0x82频谱点\n流式发送", COLORS["rose"], COLORS["rose_stroke"], size=16)
    d.edge(core, lo, "设频")
    d.edge(lo, core, "锁定反馈", dashed=True)
    d.edge(core, dma, "启动/重装载DMA")
    d.edge(dma, sp, "4096点帧")
    d.edge(sp, cal, "raw power")
    d.edge(cal, proto, "校正后dBm")
    d.edge(proto, core, "命令触发", dashed=True)
    d.box(420, 735, 860, 92, "主循环轮询 device_protocol 与 sweep_engine；扫频活跃时以当前测量点为核心，采样、处理、发送各模块职责清晰，便于调试和扩展。", COLORS["gray"], COLORS["gray_stroke"], size=18)
    return d


def page_sweep_state() -> Diagram:
    d = Diagram("图2.3.1-3 扫频状态机", 1700, 1000)
    d.title("逐点扫频状态机", "每个频点独立经历锁相、采样、积累、测量、发送，适合实时显示和故障定位。")
    coords = [
        ("Prepare\n配置RBW/DDC", 110, 245, COLORS["gray"], COLORS["gray_stroke"]),
        ("Set LO1\n切到RF频点", 390, 245, COLORS["blue"], COLORS["blue_stroke"]),
        ("Wait Lock\n等待PLL锁定", 670, 245, COLORS["blue"], COLORS["blue_stroke"]),
        ("Arm DMA\n启动采样", 950, 245, COLORS["teal"], COLORS["teal_stroke"]),
        ("Accumulate\nDDC + CIC\n累积样本", 950, 520, COLORS["teal"], COLORS["teal_stroke"]),
        ("Measure\nFIR + 功率估计\n幅度校正", 670, 520, COLORS["green"], COLORS["green_stroke"]),
        ("Emit Point\n发送0x82", 390, 520, COLORS["rose"], COLORS["rose_stroke"]),
        ("Next Point\n或 Done", 110, 520, COLORS["amber"], COLORS["amber_stroke"]),
    ]
    ids = []
    for text, x, y, fill, stroke in coords:
        ids.append(d.box(x, y, 205, 112, text, fill, stroke, size=17, bold=True))
    for a, b in zip(ids[:4], ids[1:4]):
        d.edge(a, b)
    d.edge(ids[3], ids[4])
    d.edge(ids[4], ids[5])
    d.edge(ids[5], ids[6])
    d.edge(ids[6], ids[7])
    d.edge_points(ids[7], ids[1], [(212, 450), (492, 450)], "下一频点", COLORS["amber_stroke"])
    err = d.box(1300, 375, 250, 150, "异常保护\nLO锁定超时\nDMA超时\n功率测量失败", COLORS["rose"], COLORS["rose_stroke"], size=17, bold=True)
    d.edge(ids[2], err, dashed=True, stroke=COLORS["rose_stroke"])
    d.edge(ids[3], err, dashed=True, stroke=COLORS["rose_stroke"])
    d.edge(ids[5], err, dashed=True, stroke=COLORS["rose_stroke"])
    d.label(110, 795, 1250, 40, "设计收益：每个频点都有完整测量闭环，可实时显示，也便于定位 DMA、锁相或信号处理瓶颈。", size=20, bold=True, align="left")
    return d


def page_rbw_chain() -> Diagram:
    d = Diagram("图2.3.1-4 RBW处理链", 1700, 1000)
    d.title("多档 RBW 数字滤波处理链", "RBW 档位真实改变抽取比、FIR 长度和观测窗口，而不仅是显示参数。")
    ids = [
        d.box(130, 245, 240, 105, "DDC后 I/Q\n基带样本", COLORS["blue"], COLORS["blue_stroke"], size=18, bold=True),
        d.box(520, 245, 240, 105, "CIC抽取\nR/N按RBW配置\n降低数据率", COLORS["teal"], COLORS["teal_stroke"], size=18, bold=True),
        d.box(910, 245, 240, 105, "补偿FIR\nRBW低通\n修正通带", COLORS["green"], COLORS["green_stroke"], size=18, bold=True),
        d.box(1300, 245, 240, 105, "有效观测窗\n跳过瞬态\n积累功率", COLORS["amber"], COLORS["amber_stroke"], size=18, bold=True),
    ]
    for a, b in zip(ids, ids[1:]):
        d.edge(a, b)
    d.group_box(120, 465, 1430, 300, "RBW 档位参数趋势", "#FFFFFF", COLORS["gray_stroke"])
    rows = [
        ("1 kHz", "R=13000, N=5", "FIR=256 taps", "Observe=256, Skip=128"),
        ("10 kHz", "R=1300, N=5", "FIR=256 taps", "Observe=256, Skip=128"),
        ("30 kHz", "R=433, N=5", "FIR=256 taps", "Observe=256, Skip=128"),
        ("100 kHz", "R=130, N=5", "FIR=128 taps", "Observe=384, Skip=64"),
        ("300 kHz", "R=43, N=4", "FIR=128 taps", "Observe=384, Skip=64"),
        ("1 MHz", "R=13, N=4", "FIR=64 taps", "Observe=384, Skip=32"),
    ]
    x0, y0 = 185, 535
    for i, row in enumerate(rows):
        y = y0 + i * 34
        d.table_cell(x0, y, 160, 34, row[0], COLORS["gray"], True)
        d.table_cell(x0 + 160, y, 300, 34, row[1])
        d.table_cell(x0 + 460, y, 260, 34, row[2])
        d.table_cell(x0 + 720, y, 380, 34, row[3])
    d.label(185, 785, 980, 34, "窄 RBW：更大抽取比、更长观测时间；宽 RBW：更高扫速、更短处理链。", size=18, bold=True, align="left")
    return d


def page_power_calibration() -> Diagram:
    d = Diagram("图2.3.1-5 功率校正", 1700, 1000)
    d.title("功率计算与输入端幅度校正", "把 RBW 滤波后的基带能量换算为 RF 输入端 dBm。")
    ids = [
        d.box(110, 270, 230, 105, "RBW滤波后\nI/Q样本", COLORS["green"], COLORS["green_stroke"], size=18, bold=True),
        d.box(450, 270, 250, 105, "均方功率\nP = mean(I² + Q²)", COLORS["green"], COLORS["green_stroke"], size=18, bold=True),
        d.box(810, 270, 250, 105, "dBFS换算\n10log10(P/PFS)", COLORS["amber"], COLORS["amber_stroke"], size=18, bold=True),
        d.box(1170, 270, 300, 105, "ADC输入功率\n+8.02 dBm 满量程参考", COLORS["amber"], COLORS["amber_stroke"], size=18, bold=True),
    ]
    for a, b in zip(ids, ids[1:]):
        d.edge(a, b)
    cal = d.box(380, 555, 920, 105, "幅度校正项 = 衰减器 - LNA增益 - VGA增益 + 路径校准 + 频率分段校准", COLORS["rose"], COLORS["rose_stroke"], size=20, bold=True)
    d.edge(ids[3], cal, "raw ADC dBm")
    out = d.box(640, 760, 410, 92, "RF输入端幅度\n用于上位机频谱显示", COLORS["blue"], COLORS["blue_stroke"], size=22, bold=True)
    d.edge(cal, out, "corrected dBm")
    d.label(110, 455, 900, 36, "固件保留 raw power 与 correction dB，便于后续标定、误差分析和校准表迭代。", size=18, align="left")
    return d


def page_rbw_table() -> Diagram:
    d = Diagram("表2.3.1-1 RBW参数", 1700, 1000)
    d.title("当前固件 RBW 档位参数", "参数来自 app_config.h，用于 signal_processing.c 的 sweep-path 配置。")
    headers = ["RBW", "CIC R", "CIC N", "FIR taps", "Observe pts", "Skip pts", "Accum target"]
    rows = [
        ["1 kHz", "13000", "5", "256", "256", "128", "640"],
        ["10 kHz", "1300", "5", "256", "256", "128", "640"],
        ["30 kHz", "433", "5", "256", "256", "128", "640"],
        ["100 kHz", "130", "5", "128", "384", "64", "576"],
        ["300 kHz", "43", "4", "128", "384", "64", "576"],
        ["1 MHz", "13", "4", "64", "384", "32", "480"],
    ]
    col_w = [190, 190, 160, 190, 220, 190, 230]
    x0, y0 = 125, 220
    h = 58
    x = x0
    for header, w in zip(headers, col_w):
        d.table_cell(x, y0, w, h, header, COLORS["blue"], True)
        x += w
    for r, row in enumerate(rows):
        y = y0 + h * (r + 1)
        x = x0
        fill = "#FFFFFF" if r % 2 == 0 else "#F8FAFC"
        for value, w in zip(row, col_w):
            d.table_cell(x, y, w, h, value, fill, value.endswith("kHz") or value.endswith("MHz"))
            x += w
    d.label(125, 640, 1120, 36, "Accum target = Observe points + Skip points + FIR taps；实际累积受 ACCUM_BUFFER_SIZE = 768 约束。", size=18, align="left", color=COLORS["muted"])
    d.label(125, 715, 1020, 40, "用途：写报告时可直接把本页作为表图，也可在 Word 中保留普通表格以便排版。", size=18, bold=True, align="left")
    return d


def build_drawio():
    mxfile = ET.Element(
        "mxfile",
        {
            "host": "app.diagrams.net",
            "modified": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "agent": "Codex",
            "version": "24.7.17",
            "type": "device",
        },
    )
    pages = [
        page_overall_flow(),
        page_software_arch(),
        page_sweep_state(),
        page_rbw_chain(),
        page_power_calibration(),
        page_rbw_table(),
    ]
    for page in pages:
        diagram = ET.SubElement(mxfile, "diagram", {"name": page.name, "id": page.name})
        diagram.append(page.root)
    ET.indent(mxfile, space="  ")
    tree = ET.ElementTree(mxfile)
    tree.write(OUT_PATH, encoding="utf-8", xml_declaration=True)
    print(f"Generated {OUT_PATH}")


if __name__ == "__main__":
    build_drawio()
