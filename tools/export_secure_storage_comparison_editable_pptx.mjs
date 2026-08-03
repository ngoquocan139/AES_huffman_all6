import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const artifactToolPath =
  "C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const { Presentation, PresentationFile } = await import(
  pathToFileURL(artifactToolPath).href
);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = path.join(root, "docs", "generated_figures");
const sourceSlidePng = path.join(
  outDir,
  "secure_storage_ecg_paper_comparison_slide.png",
);
const logCropPng = path.join(outDir, "secure_storage_fpga_log_crop.png");
const pptxPath = path.join(
  outDir,
  "secure_storage_ecg_paper_comparison_slide_editable.pptx",
);
const previewDir = path.join(
  outDir,
  "secure_storage_ecg_paper_comparison_slide_editable_preview",
);

const W = 1920;
const H = 1080;
const C = {
  bg: "#F7FAFF",
  blue: "#0068D9",
  blueDark: "#003B91",
  cyan: "#C9FAFF",
  cyanLine: "#10A6C8",
  text: "#132033",
  muted: "#66758A",
  grid: "#B9C9E6",
  lightBlue: "#EAF2FF",
  white: "#FFFFFF",
  black: "#151A20",
  green: "#099A82",
  red: "#F22D3A",
};

async function readImageBlob(imagePath) {
  const bytes = await fs.readFile(imagePath);
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  );
}

async function writeBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function rect(slide, name, position, fill, line = C.grid, radius = 0) {
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
    fontSize: options.fontSize ?? 20,
    bold: options.bold ?? false,
    color: options.color ?? C.text,
    typeface: options.typeface ?? "Arial",
    alignment: options.alignment ?? "left",
    verticalAlignment: options.verticalAlignment ?? "top",
    wrap: "square",
    insets: options.insets ?? { left: 0, right: 0, top: 0, bottom: 0 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function filledText(slide, name, value, position, fill, options = {}) {
  const box = rect(
    slide,
    `${name}-surface`,
    position,
    fill,
    options.line ?? C.grid,
    options.radius ?? 0,
  );
  box.text = value;
  box.text.style = {
    fontSize: options.fontSize ?? 18,
    bold: options.bold ?? false,
    color: options.color ?? C.text,
    typeface: options.typeface ?? "Arial",
    alignment: options.alignment ?? "center",
    verticalAlignment: options.verticalAlignment ?? "middle",
    wrap: "square",
    insets: options.insets ?? { left: 6, right: 6, top: 4, bottom: 4 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function addHeader(slide) {
  rect(slide, "logo-circle", { left: 67, top: 35, width: 76, height: 76 }, C.white, C.blue, 40);
  text(slide, "logo-mark", "C", { left: 84, top: 43, width: 42, height: 42 }, {
    fontSize: 42,
    bold: true,
    color: C.blue,
    alignment: "center",
    verticalAlignment: "middle",
  });
  text(slide, "logo-caption", "HCMUTE", { left: 64, top: 114, width: 85, height: 22 }, {
    fontSize: 14,
    bold: true,
    color: C.blueDark,
    alignment: "center",
  });
  text(
    slide,
    "university-name",
    "HO CHI MINH CITY UNIVERSITY OF TECHNOLOGY\nAND EDUCATION",
    { left: 165, top: 38, width: 620, height: 64 },
    { fontSize: 22, bold: true, color: C.blueDark, lineSpacing: 0.92 },
  );
  text(
    slide,
    "university-subtitle",
    "HCMC University of Technology and Education",
    { left: 165, top: 102, width: 520, height: 26 },
    { fontSize: 16, color: C.muted },
  );

  const band = slide.shapes.add({
    geometry: "rightArrow",
    name: "section-band",
    position: { left: 45, top: 155, width: 945, height: 70 },
    fill: C.cyan,
    line: { style: "solid", fill: C.cyanLine, width: 3 },
  });
  band.text = "DESIGN QUALITY EVALUATION";
  band.text.style = {
    fontSize: 36,
    bold: true,
    color: C.blueDark,
    typeface: "Arial",
    alignment: "left",
    verticalAlignment: "middle",
    insets: { left: 25, right: 12, top: 0, bottom: 0 },
  };
}

function addLogSection(slide, logBlob) {
  text(slide, "performance-title", "Performance Evaluation", {
    left: 85,
    top: 265,
    width: 640,
    height: 50,
  }, { fontSize: 38, bold: true });
  text(
    slide,
    "performance-subtitle",
    "Direct RTL/FPGA verification on ECG secure-storage workload",
    { left: 85, top: 330, width: 720, height: 34 },
    { fontSize: 25 },
  );

  slide.images.add({
    blob: logBlob,
    contentType: "image/png",
    alt: "FPGA secure-storage run log",
    fit: "contain",
    position: { left: 85, top: 395, width: 675, height: 310 },
    geometry: "roundRect",
    borderRadius: "rounded-lg",
  });

  const cards = [
    ["29.87%", "final ratio"],
    ["70.13%", "raw ECG saving"],
    ["100%", "byte match"],
  ];
  for (const [i, [value, label]] of cards.entries()) {
    const left = 85 + i * 235;
    rect(slide, `metric-card-${i}`, { left, top: 745, width: 205, height: 90 }, C.white, C.grid, 10);
    text(slide, `metric-value-${i}`, value, { left, top: 758, width: 205, height: 36 }, {
      fontSize: 31,
      bold: true,
      color: C.blueDark,
      alignment: "center",
      verticalAlignment: "middle",
    });
    text(slide, `metric-label-${i}`, label, { left, top: 795, width: 205, height: 26 }, {
      fontSize: 18,
      bold: true,
      color: C.muted,
      alignment: "center",
      verticalAlignment: "middle",
    });
  }

  rect(slide, "input-box", { left: 85, top: 850, width: 675, height: 122 }, C.white, C.grid, 8);
  text(slide, "input-title", "Comparison input set:", { left: 105, top: 864, width: 230, height: 24 }, {
    fontSize: 18,
    bold: true,
    color: C.blueDark,
  });
  text(
    slide,
    "input-details",
    "MIT-BIH records: 100, 106, 112, 117, 213\nRaw reference: 7200 B/record = 3600 samples x 2 B\nSoC input avg 3603.8 B; stored avg 2150.4 B\nPaper platform: MATLAB 2018a, Win7 64-bit, i5 2nd Gen, 8 GB RAM",
    { left: 105, top: 892, width: 635, height: 72 },
    { fontSize: 16, color: C.text, lineSpacing: 0.88 },
  );
}

function addComparisonTable(slide) {
  text(
    slide,
    "comparison-title",
    "Comparison with ECG Huffman + CBC-AES Paper",
    { left: 820, top: 300, width: 780, height: 36 },
    { fontSize: 25, bold: true },
  );

  const x0 = 820;
  const y0 = 342;
  const colW = [230, 275, 250, 130, 210];
  const rowH = [48, ...Array(10).fill(42)];
  const heads = [
    "Metric",
    "ECG CBC-AES Paper [1]",
    "This Work",
    "Correctness",
    "Improvement (%)",
  ];
  const rows = [
    ["Compression\nratio", "35.015%", "29.87%", "100%", "+14.69%"],
    ["Space\nsaving", "64.985%", "70.13%", "100%", "+7.92%"],
    ["PRD / byte\nmatch", "0.411", "0 mismatch\nbyte-exact RX", "100%", "0%"],
    ["Compression\ntime", "~3.8641 s", "1.056 ms\nTX comp-only", "100%", "+99.97%"],
    ["Decompression\ntime", "~0.5818 s", "0.483 ms\nRX Huffman", "100%", "+99.92%"],
    ["Encryption\ntime", "~2.7106 s", "29.6 us\nTX AES", "100%", "+99.999%"],
    ["Decryption\ntime", "~3.0449 s", "69.2 us\nRX AES", "100%", "+99.998%"],
    ["Compression +\nencryption", "~6.5747 s", "1.065 ms\nTX path", "100%", "+99.98%"],
    ["TX/RX cycles", "N/R", "53233 TX\n24222 RX", "100%", "0%"],
    ["TX/RX throughput", "N/R", "6.828 MB/s TX-in\n15.072 MB/s RX-out", "100%", "0%"],
  ];

  let x = x0;
  for (let i = 0; i < heads.length; i += 1) {
    filledText(
      slide,
      `table-head-${i}`,
      heads[i],
      { left: x, top: y0, width: colW[i], height: rowH[0] },
      C.lightBlue,
      {
        fontSize: 18,
        bold: true,
        color: C.blueDark,
        line: C.grid,
      },
    );
    x += colW[i];
  }

  let y = y0 + rowH[0];
  for (let r = 0; r < rows.length; r += 1) {
    x = x0;
    const fill = r % 2 === 0 ? C.white : "#F3F7FF";
    for (let c = 0; c < rows[r].length; c += 1) {
      const isGood = c === 3 || (c === 4 && rows[r][c] !== "0%");
      filledText(
        slide,
        `table-r${r}-c${c}`,
        rows[r][c],
        { left: x, top: y, width: colW[c], height: rowH[r + 1] },
        fill,
        {
          fontSize: c === 0 || c === 2 ? 15 : 16,
          bold: c === 3 || c === 4,
          color: isGood ? C.green : C.text,
          line: C.grid,
          lineSpacing: 0.84,
        },
      );
      x += colW[c];
    }
    y += rowH[r + 1];
  }

  const tableW = colW.reduce((a, b) => a + b, 0);
  rect(slide, "source-box", { left: x0, top: y + 14, width: tableW, height: 128 }, C.white, C.grid, 8);
  text(slide, "source-label", "Source:", { left: x0 + 25, top: y + 32, width: 90, height: 26 }, {
    fontSize: 18,
    bold: true,
    color: C.blueDark,
  });
  text(
    slide,
    "source-note",
    "[1] A lossless compression and encryption mechanism for remote monitoring of ECG data\nusing Huffman coding and CBC-AES, FGCS 2019; simulated in MATLAB 2018a on Windows 7,\ni5 2nd Gen, 8 GB RAM. N/R = not reported.\nNote: ML precision is TP/(TP+FP); this slide uses byte-match correctness = matched bytes/total bytes.\nRTL timing is measured from perf counters at 50 MHz on the five MIT-BIH records.",
    { left: x0 + 125, top: y + 28, width: tableW - 150, height: 96 },
    { fontSize: 15, lineSpacing: 0.82 },
  );
}

function addFooter(slide) {
  rect(slide, "footer-blue", { left: 50, top: 1000, width: 1730, height: 60 }, C.blue, C.blueDark, 14);
  rect(slide, "footer-red", { left: 1780, top: 1000, width: 90, height: 60 }, C.red, C.red);
  text(
    slide,
    "footer-text",
    "Application target: embedded secure data storage with compression, encryption, and byte-exact readback.",
    { left: 75, top: 1015, width: 1665, height: 32 },
    { fontSize: 25, bold: true, color: C.white, verticalAlignment: "middle" },
  );
}

await fs.mkdir(previewDir, { recursive: true });

await fs.access(sourceSlidePng);
const logBlob = await readImageBlob(logCropPng);
const presentation = Presentation.create({
  slideSize: { width: W, height: H },
});

const slide = presentation.slides.add();
slide.background.fill = C.bg;

addHeader(slide);
addLogSection(slide, logBlob);
addComparisonTable(slide);
addFooter(slide);

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

console.log(pptxPath);
