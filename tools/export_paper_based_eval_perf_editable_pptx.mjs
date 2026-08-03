import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const artifactToolPath =
  "C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const { Presentation, PresentationFile } = await import(
  pathToFileURL(artifactToolPath).href,
);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = path.join(root, "docs", "generated_figures");
const previewDir = path.join(
  outDir,
  "paper_based_evaluation_performance_comparison_editable_preview",
);
const pptxPath = path.join(
  outDir,
  "paper_based_evaluation_performance_comparison_editable_refs.pptx",
);
const docsCopyPath = path.resolve(
  root,
  "..",
  "..",
  "..",
  "docs",
  "figure_4_11_evaluation_performance_comparison_paper_based_editable_refs.pptx",
);

const W = 2400;
const H = 1500;
const C = {
  bg: "#FFFFFF",
  text: "#111827",
  muted: "#4B5563",
  grid: "#D9DEE8",
  border: "#E5E7EB",
  noteBg: "#EAF2FF",
  noteLine: "#7AA7FF",
  our: "#F28C28",
  paper: "#3F7FCD",
  official: "#7B61FF",
  std: "#2A9D8F",
  warn: "#D9534F",
};

async function writeBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function text(slide, name, value, position, options = {}) {
  const box = slide.shapes.add({
    geometry: "textbox",
    name,
    position,
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  box.text = value;
  box.text.style = {
    typeface: "Arial",
    fontSize: options.fontSize ?? 20,
    bold: options.bold ?? false,
    color: options.color ?? C.text,
    alignment: options.alignment ?? "left",
    verticalAlignment: options.verticalAlignment ?? "top",
    wrap: "square",
    insets: options.insets ?? { left: 0, right: 0, top: 0, bottom: 0 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function rect(slide, name, position, fill, line = C.border, radius = 0) {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    name,
    position,
    fill,
    line:
      line === "none"
        ? { style: "solid", fill: "none", width: 0 }
        : { style: "solid", fill: line, width: 2 },
    ...(radius ? { borderRadius: radius } : {}),
  });
}

function addChart(slide, cfg) {
  const points = cfg.colors.map((fill, idx) => ({
    idx,
    fill,
    line: { style: "solid", fill: "#FFFFFF", width: 1 },
  }));

  return slide.charts.add("bar", {
    position: cfg.position,
    title: cfg.title,
    titleTextStyle: { fontSize: 24, fill: C.text, bold: false },
    titlePlacement: "aboveChart",
    categories: cfg.labels,
    series: [
      {
        name: cfg.seriesName ?? cfg.title,
        values: cfg.values,
        fill: cfg.colors[0],
        points,
        valuesFormatCode: cfg.valueFormat ?? "0.00",
      },
    ],
    hasLegend: false,
    barOptions: {
      direction: "column",
      grouping: "clustered",
      varyColors: true,
      gapWidth: cfg.gapWidth ?? 72,
    },
    xAxis: {
      textStyle: { fill: C.text, fontSize: cfg.xFontSize ?? 16 },
      line: { style: "solid", fill: "#333333", width: 1 },
      majorGridlines: null,
    },
    yAxis: {
      title: { text: cfg.ylabel, textStyle: { fill: C.text, fontSize: 18 } },
      min: cfg.min ?? 0,
      max: cfg.max,
      majorUnit: cfg.majorUnit,
      numberFormatCode: cfg.axisFormat ?? "0.0",
      textStyle: { fill: "#333333", fontSize: 16 },
      line: { style: "solid", fill: "#333333", width: 1 },
      majorGridlines: { style: "solid", fill: C.grid, width: 1 },
      minorGridlines: null,
    },
    dataLabels: {
      showValue: true,
      position: "outEnd",
      textStyle: {
        fill: C.text,
        fontSize: cfg.labelFontSize ?? 17,
        bold: true,
      },
    },
    chartFill: "#FFFFFF",
    chartLine: { style: "solid", fill: "#FFFFFF", width: 0 },
    plotAreaFill: "#FFFFFF",
    plotAreaLine: { style: "solid", fill: "#FFFFFF", width: 0 },
  });
}

function addLegend(slide) {
  const rows = [
    [
      ["Our Design (local)", C.our, 310],
      ["Hardware papers [1][3][4]", C.paper, 520],
      ["Official AES IP [2]", C.official, 370],
    ],
    [
      ["Standard compressors (local)", C.std, 500],
      ["ECG papers [5][6]", C.warn, 360],
    ],
  ];
  const y0 = 1270;
  rows.forEach((items, rowIdx) => {
    const totalWidth = items.reduce((sum, item) => sum + item[2], 0);
    let x = (W - totalWidth) / 2;
    const y = y0 + rowIdx * 36;
    items.forEach(([label, color, width], itemIdx) => {
      const idx = `${rowIdx}-${itemIdx}`;
      rect(slide, `legend-swatch-${idx}`, { left: x, top: y + 9, width: 34, height: 24 }, color, color);
      text(
        slide,
        `legend-label-${idx}`,
        label,
        { left: x + 46, top: y, width: width - 48, height: 34 },
        { fontSize: 23, color: C.text },
      );
      x += width;
    });
  });
}

await fs.mkdir(outDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

const presentation = Presentation.create({ slideSize: { width: W, height: H } });
const slide = presentation.slides.add();
slide.background.fill = C.bg;

text(
  slide,
  "deck-title",
  "Evaluation and Performance Comparison",
  { left: 0, top: 22, width: W, height: 58 },
  { fontSize: 48, bold: true, alignment: "center" },
);
text(
  slide,
  "hardware-section",
  "Hardware Baselines",
  { left: 0, top: 92, width: W, height: 46 },
  { fontSize: 34, bold: true, alignment: "center" },
);
text(
  slide,
  "software-section",
  "Software and Paper Baselines",
  { left: 0, top: 658, width: W, height: 46 },
  { fontSize: 34, bold: true, alignment: "center" },
);

const aesLabels = ["Ours", "Good\nlow", "C&G", "Rouv.", "OT"];
const aesEff = [1.455, 0.004, 0.346, 0.366, 1.333];
const aesThroughput = [145.5, 0.4, 34.6, 36.6, 133.3];
const aesColors = [C.our, C.paper, C.paper, C.paper, C.official];

addChart(slide, {
  title: "AES Throughput at 100 MHz",
  position: { left: 45, top: 150, width: 560, height: 460 },
  labels: aesLabels,
  values: aesThroughput,
  colors: aesColors,
  ylabel: "Throughput (MB/s)",
  max: 180,
  majorUnit: 36,
  valueFormat: "0.0",
  axisFormat: "0.0",
});

addChart(slide, {
  title: "AES Efficiency",
  position: { left: 635, top: 150, width: 560, height: 460 },
  labels: aesLabels,
  values: aesEff,
  colors: aesColors,
  ylabel: "Bytes/cycle",
  max: 1.75,
  majorUnit: 0.35,
  valueFormat: "0.000",
  axisFormat: "0.00",
});

addChart(slide, {
  title: "Huffman Throughput",
  position: { left: 1225, top: 150, width: 560, height: 460 },
  labels: ["Ours", "ASAP14-L", "ASAP14-T", "Gug25"],
  values: [9.4, 2.1, 22.1, 144000.0],
  colors: [C.our, C.paper, C.paper, C.paper],
  ylabel: "Input MB/s",
  max: 150000,
  majorUnit: 30000,
  valueFormat: "0.0",
  axisFormat: "0",
  labelFontSize: 15,
  xFontSize: 15,
});

addChart(slide, {
  title: "Huffman Efficiency",
  position: { left: 1815, top: 150, width: 535, height: 460 },
  labels: ["Ours", "ASAP14-L", "ASAP14-T"],
  values: [0.094, 0.021, 0.221],
  colors: [C.our, C.paper, C.paper],
  ylabel: "Bytes/cycle",
  max: 0.25,
  majorUnit: 0.05,
  valueFormat: "0.000",
  axisFormat: "0.00",
});

addChart(slide, {
  title: "Compression + Encryption Input Throughput",
  position: { left: 70, top: 712, width: 680, height: 490 },
  labels: ["Our Design\nTX", "FGCS20\nC+E"],
  values: [4.531, 0.0055],
  colors: [C.our, C.warn],
  ylabel: "Input MB/s",
  max: 5,
  majorUnit: 1,
  valueFormat: "0.0000",
  axisFormat: "0.0",
});

addChart(slide, {
  title: "Payload Saving on 18,019 Preprocessed ECG Bytes",
  position: { left: 790, top: 712, width: 700, height: 490 },
  labels: ["Ours", "IJETT24\nECG", "zlib-9", "bz2-9", "lzma-6"],
  values: [44.28, 42.0, 41.16, 42.89, 44.99],
  colors: [C.our, C.warn, C.std, C.std, C.std],
  ylabel: "Saving (%)",
  min: 38,
  max: 46.5,
  majorUnit: 1.7,
  valueFormat: "0.00",
  axisFormat: "0.0",
  xFontSize: 15,
});

addChart(slide, {
  title: "Saved vs 36,000 Raw ECG Bytes",
  position: { left: 1530, top: 712, width: 770, height: 490 },
  labels: ["Ours", "FGCS20\npaper", "zlib-9", "bz2-9", "lzma-6"],
  values: [70.13, 64.98, 70.55, 71.41, 72.47],
  colors: [C.our, C.warn, C.std, C.std, C.std],
  ylabel: "Saving (%)",
  min: 62,
  max: 74,
  majorUnit: 2.4,
  valueFormat: "0.00",
  axisFormat: "0.0",
  xFontSize: 15,
});

addLegend(slide);

text(
  slide,
  "source-note",
  "References: [1] Good & Benaissa, CHES 2005. [2] OpenTitan AES HWIP. [3] Matai et al., ASAP 2014. [4] Guguloth et al., Results in Engineering, 2025. [5] Hameed et al., FGCS 2020. [6] Zarate Segura et al., IJETT 2024. Note: Throughput is normalized to 100 MHz where possible; efficiency is reported as bytes/cycle. FPGA/platform and input size differ across references.",
  { left: 95, top: 1375, width: 2210, height: 86 },
  { fontSize: 19, color: C.muted, lineSpacing: 0.9 },
);

await writeBlob(
  path.join(previewDir, "slide-1.png"),
  await presentation.export({ slide, format: "png", scale: 1 }),
);
await fs.writeFile(
  path.join(previewDir, "slide-1.layout.json"),
  await (await slide.export({ format: "layout" })).text(),
);

const inspect = await presentation.inspect({
  kind: "slide,textbox,shape,image,table,chart,layout",
  maxChars: 12000,
});
await fs.writeFile(
  path.join(previewDir, "inspect.ndjson"),
  inspect.ndjson ?? String(inspect),
);

const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(pptxPath);

await fs.mkdir(path.dirname(docsCopyPath), { recursive: true });
await fs.copyFile(pptxPath, docsCopyPath);

console.log(pptxPath);
console.log(docsCopyPath);
