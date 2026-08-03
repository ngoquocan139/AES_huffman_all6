import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = path.join(root, "docs", "generated_figures");
const xlsxPath = path.join(
  outDir,
  "paper_based_evaluation_performance_comparison_data_colored.xlsx",
);
const docsCopyPath = path.resolve(
  root,
  "..",
  "..",
  "..",
  "docs",
  "figure_4_11_evaluation_performance_comparison_paper_based_data_colored.xlsx",
);
const previewDir = path.join(
  outDir,
  "paper_based_evaluation_performance_comparison_data_preview",
);

const C = {
  blue: "#1F4E79",
  header: "#EAF2FF",
  border: "#B7C9E2",
  our: "#F28C28",
  paper: "#3F7FCD",
  official: "#7B61FF",
  std: "#2A9D8F",
  warn: "#D9534F",
  text: "#111827",
  muted: "#4B5563",
};

const chartBlocks = [
  {
    key: "aes_throughput",
    title: "AES Throughput at 100 MHz",
    unit: "MB/s",
    section: "Hardware Baselines",
    axisMax: 180,
    axisFormat: "0.0",
    rows: [
      ["Ours", 145.5, "Our Design", C.our, "Normalized from local AES block efficiency at 100 MHz"],
      ["Good low", 0.4, "Research paper / cited hardware design", C.paper, "Good & Benaissa low-area AES reference"],
      ["C&G", 34.6, "Research paper / cited hardware design", C.paper, "Chodowiec & Gaj AES reference"],
      ["Rouv.", 36.6, "Research paper / cited hardware design", C.paper, "Rouvroy et al. AES reference"],
      ["OT", 133.3, "Official hardware IP/spec", C.official, "OpenTitan AES HWIP reference"],
    ],
  },
  {
    key: "aes_efficiency",
    title: "AES Efficiency",
    unit: "bytes/cycle",
    section: "Hardware Baselines",
    axisMax: 1.75,
    axisFormat: "0.000",
    rows: [
      ["Ours", 1.455, "Our Design", C.our, "16-byte AES block divided by local cycle count"],
      ["Good low", 0.004, "Research paper / cited hardware design", C.paper, "Good & Benaissa low-area AES reference"],
      ["C&G", 0.346, "Research paper / cited hardware design", C.paper, "Chodowiec & Gaj AES reference"],
      ["Rouv.", 0.366, "Research paper / cited hardware design", C.paper, "Rouvroy et al. AES reference"],
      ["OT", 1.333, "Official hardware IP/spec", C.official, "OpenTitan AES HWIP reference"],
    ],
  },
  {
    key: "huffman_throughput",
    title: "Huffman Throughput",
    unit: "input MB/s",
    section: "Hardware Baselines",
    axisMax: 150000,
    axisFormat: "0.0",
    rows: [
      ["Ours", 9.4, "Our Design", C.our, "Local TX Huffman test normalized to 100 MHz"],
      ["ASAP14-L", 2.1, "Research paper / cited hardware design", C.paper, "Matai et al. ASAP 2014 latency-optimized canonical Huffman"],
      ["ASAP14-T", 22.1, "Research paper / cited hardware design", C.paper, "Matai et al. ASAP 2014 throughput-optimized canonical Huffman"],
      ["Gug25", 144000.0, "Research paper / cited hardware design", C.paper, "Guguloth et al. 2025 high-throughput canonical Huffman machine"],
    ],
  },
  {
    key: "huffman_efficiency",
    title: "Huffman Efficiency",
    unit: "bytes/cycle",
    section: "Hardware Baselines",
    axisMax: 0.25,
    axisFormat: "0.000",
    rows: [
      ["Ours", 0.094, "Our Design", C.our, "2551 bytes / 27107 cycles"],
      ["ASAP14-L", 0.021, "Research paper / cited hardware design", C.paper, "Matai et al. ASAP 2014 latency-optimized canonical Huffman"],
      ["ASAP14-T", 0.221, "Research paper / cited hardware design", C.paper, "Matai et al. ASAP 2014 throughput-optimized canonical Huffman"],
    ],
  },
  {
    key: "ce_input_throughput",
    title: "Compression + Encryption Input Throughput",
    unit: "input MB/s",
    section: "Software and Paper Baselines",
    axisMax: 5,
    axisFormat: "0.0000",
    rows: [
      ["Our Design TX", 4.5310, "Our Design", C.our, "Secure-storage TX input throughput"],
      ["FGCS20 C+E", 0.0055, "ECG/application paper baselines", C.warn, "36000 bytes / 6.5747 s from Hameed et al."],
    ],
  },
  {
    key: "payload_saving",
    title: "Payload Saving on 18,019 Preprocessed ECG Bytes",
    unit: "saving %",
    section: "Software and Paper Baselines",
    axisMin: 38,
    axisMax: 46.5,
    axisFormat: "0.00",
    rows: [
      ["Ours", 44.28, "Our Design", C.our, "Local secure-storage compression result"],
      ["IJETT24 ECG", 42.00, "ECG/application paper baselines", C.warn, "Zarate Segura et al. IJETT 2024 ECG compression reference"],
      ["zlib-9", 41.16, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
      ["bz2-9", 42.89, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
      ["lzma-6", 44.99, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
    ],
  },
  {
    key: "raw_ecg_saving",
    title: "Saved vs 36,000 Raw ECG Bytes",
    unit: "saving %",
    section: "Software and Paper Baselines",
    axisMin: 62,
    axisMax: 74,
    axisFormat: "0.00",
    rows: [
      ["Ours", 70.13, "Our Design", C.our, "Local pipeline result vs 36,000-byte raw ECG reference"],
      ["FGCS20 paper", 64.98, "ECG/application paper baselines", C.warn, "Hameed et al. FGCS 2020 ECG Huffman + CBC-AES"],
      ["zlib-9", 70.55, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
      ["bz2-9", 71.41, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
      ["lzma-6", 72.47, "Standard-library compressors", C.std, "Local Python standard-library compressor baseline"],
    ],
  },
];

await fs.mkdir(outDir, { recursive: true });
await fs.mkdir(previewDir, { recursive: true });

const wb = Workbook.create();
const data = wb.worksheets.add("Chart Data");
const dash = wb.worksheets.add("Dashboard");
const src = wb.worksheets.add("Sources");

const seriesDefs = [
  ["Our Design (local)", C.our],
  ["Hardware papers [1][3][4]", C.paper],
  ["Official AES IP [2]", C.official],
  ["Standard compressors (local)", C.std],
  ["ECG papers [5][6]", C.warn],
];

for (const sheet of [data, dash, src]) {
  sheet.showGridLines = false;
}

function styleTitle(range) {
  range.format = {
    fill: C.blue,
    font: { bold: true, color: "#FFFFFF", size: 14 },
    borders: { preset: "outside", style: "medium", color: C.blue },
  };
}

function styleHeader(range) {
  range.format = {
    fill: C.header,
    font: { bold: true, color: C.text },
    borders: { preset: "all", style: "thin", color: C.border },
  };
}

function styleBody(range) {
  range.format = {
    borders: { preset: "all", style: "thin", color: "#D9E2EF" },
    font: { color: C.text },
  };
}

src.getRange("A1:D1").merge();
src.getRange("A1").values = [["Sources and Notes"]];
styleTitle(src.getRange("A1:D1"));
src.getRange("A3:D3").values = [["Source", "Used for", "URL / citation", "Notes"]];
styleHeader(src.getRange("A3:D3"));
src.getRange("A4:D10").values = [
  ["[1] Good & Benaissa, CHES 2005", "AES hardware throughput and efficiency", "https://class.ece.iastate.edu/tyagi/cpre681/papers/AESCHES05.pdf", "High-throughput AES reference; different design target from integrated secure-storage SoC."],
  ["[2] OpenTitan AES HWIP documentation", "Official AES hardware IP/spec baseline", "https://opentitan.org/book/hw/ip/aes/", "Used as official hardware IP/spec comparison."],
  ["[3] Matai et al., ASAP 2014", "Canonical Huffman hardware throughput/cycle", "https://kastner.ucsd.edu/wp-content/uploads/2014/05/admin/asap14-canonical_huffman.pdf", "Canonical Huffman hardware baseline."],
  ["[4] Guguloth et al., Results in Engineering 2025", "High-throughput canonical Huffman encoder/decoder", "https://www.sciencedirect.com/science/article/pii/S2590123025011120", "Different FPGA/platform; included as paper-based hardware reference."],
  ["[5] Hameed et al., FGCS 2020", "ECG Huffman + CBC-AES application baseline", "https://doi.org/10.1016/j.future.2019.10.010", "Used for CR/saving/time comparison."],
  ["[6] Zarate Segura et al., IJETT 2024", "ECG compression payload-saving reference", "https://ijettjournal.org/Volume-72/Issue-2/IJETT-V72I2P121.pdf", "Additional ECG payload-saving comparison."],
  ["Local project measurements", "Our design values", root, "Values from local simulation/performance counters and local compressor tests."],
];
styleBody(src.getRange("A4:D10"));
src.getRange("A:D").format.wrapText = true;
src.getRange("A:A").format.columnWidth = 28;
src.getRange("B:B").format.columnWidth = 34;
src.getRange("C:C").format.columnWidth = 72;
src.getRange("D:D").format.columnWidth = 58;
src.freezePanes.freezeRows(3);

let row = 1;
const blockRanges = {};
for (const block of chartBlocks) {
  const titleRange = data.getRange(`A${row}:H${row}`);
  titleRange.merge();
  data.getRange(`A${row}`).values = [[`${block.section} - ${block.title}`]];
  styleTitle(titleRange);
  row += 1;

  const header = data.getRange(`A${row}:H${row}`);
  header.values = [[
    "Label",
    "Our Design (local)",
    "Hardware papers [1][3][4]",
    "Official AES IP [2]",
    "Standard compressors (local)",
    "ECG papers [5][6]",
    "Unit",
    "Note",
  ]];
  styleHeader(header);
  data.getRange(`B${row}`).format = { fill: C.our, font: { bold: true, color: "#FFFFFF" } };
  data.getRange(`C${row}`).format = { fill: C.paper, font: { bold: true, color: "#FFFFFF" } };
  data.getRange(`D${row}`).format = { fill: C.official, font: { bold: true, color: "#FFFFFF" } };
  data.getRange(`E${row}`).format = { fill: C.std, font: { bold: true, color: "#FFFFFF" } };
  data.getRange(`F${row}`).format = { fill: C.warn, font: { bold: true, color: "#FFFFFF" } };

  const start = row + 1;
  const values = block.rows.map(([label, value, sourceType, color, note]) => [
    label,
    sourceType === "Our Design" ? value : null,
    sourceType === "Research paper / cited hardware design" ? value : null,
    sourceType === "Official hardware IP/spec" ? value : null,
    sourceType === "Standard-library compressors" ? value : null,
    sourceType === "ECG/application paper baselines" ? value : null,
    block.unit,
    note,
  ]);
  data.getRange(`A${start}:H${start + values.length - 1}`).values = values;
  styleBody(data.getRange(`A${start}:H${start + values.length - 1}`));
  data.getRange(`B${start}:F${start + values.length - 1}`).format.numberFormat = block.axisFormat;
  data.getRange(`A${start}:H${start + values.length - 1}`).format.wrapText = true;
  blockRanges[block.key] = { start, end: start + values.length - 1, block };
  row = start + values.length + 2;
}
data.getRange("A:A").format.columnWidth = 20;
data.getRange("B:F").format.columnWidth = 22;
data.getRange("G:G").format.columnWidth = 16;
data.getRange("H:H").format.columnWidth = 70;
data.freezePanes.freezeRows(1);

dash.getRange("A1:T1").merge();
dash.getRange("A1").values = [["Evaluation and Performance Comparison"]];
styleTitle(dash.getRange("A1:T1"));
dash.getRange("A2:T2").merge();
dash.getRange("A2").values = [[
  "Editable Excel version: charts are linked to the Chart Data sheet. Edit values there to update the charts.",
]];
dash.getRange("A2:T2").format = {
  fill: "#F3F8FF",
  font: { color: C.muted },
  borders: { preset: "outside", style: "thin", color: C.border },
};

function addDashboardChart(key, title, topLeft, bottomRight) {
  const { start, end, block } = blockRanges[key];
  const chart = dash.charts.add("bar", {
    chartType: "bar",
    title,
    hasLegend: true,
  });
  seriesDefs.forEach(([name, color], index) => {
    const col = String.fromCharCode("B".charCodeAt(0) + index);
    const series = chart.series.add(name);
    series.categoryFormula = `'Chart Data'!$A$${start}:$A$${end}`;
    series.formula = `'Chart Data'!$${col}$${start}:$${col}$${end}`;
    series.fill = color;
  });
  chart.title = title;
  chart.titleTextStyle.fontSize = 12;
  chart.hasLegend = true;
  chart.xAxis = { axisType: "textAxis", textStyle: { fontSize: 9 } };
  chart.yAxis = {
    numberFormatCode: block.axisFormat,
    min: block.axisMin ?? 0,
    max: block.axisMax,
    title: { text: block.unit },
  };
  chart.setPosition(topLeft, bottomRight);
}

addDashboardChart("aes_throughput", "AES Throughput at 100 MHz", "A4", "E20");
addDashboardChart("aes_efficiency", "AES Efficiency", "F4", "J20");
addDashboardChart("huffman_throughput", "Huffman Throughput", "K4", "O20");
addDashboardChart("huffman_efficiency", "Huffman Efficiency", "P4", "T20");
addDashboardChart("ce_input_throughput", "Compression + Encryption Input Throughput", "A22", "G40");
addDashboardChart("payload_saving", "Payload Saving on 18,019 Preprocessed ECG Bytes", "H22", "N40");
addDashboardChart("raw_ecg_saving", "Saved vs 36,000 Raw ECG Bytes", "O22", "T40");

for (const col of "ABCDEFGHIJKLMNOPQRST") {
  dash.getRange(`${col}:${col}`).format.columnWidth = 12;
}
dash.freezePanes.freezeRows(2);

const inspectData = await wb.inspect({
  kind: "region",
  sheetId: "Chart Data",
  range: "A1:H60",
  maxChars: 8000,
});
await fs.writeFile(
  path.join(previewDir, "chart_data_inspect.ndjson"),
  inspectData.ndjson ?? String(inspectData),
);
const errors = await wb.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "formula error scan",
});
await fs.writeFile(
  path.join(previewDir, "formula_error_scan.ndjson"),
  errors.ndjson ?? String(errors),
);
const preview = await wb.render({
  sheetName: "Dashboard",
  autoCrop: "all",
  scale: 1,
  format: "png",
});
await fs.writeFile(
  path.join(previewDir, "dashboard.png"),
  new Uint8Array(await preview.arrayBuffer()),
);

const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(xlsxPath);
await fs.mkdir(path.dirname(docsCopyPath), { recursive: true });
await fs.copyFile(xlsxPath, docsCopyPath);

console.log(xlsxPath);
console.log(docsCopyPath);
