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
const logImage = path.join(outDir, "secure_storage_fpga_log_crop.png");
const pptxPath = path.join(
  outDir,
  "secure_storage_ecg_paper_comparison_summary_32.pptx",
);
const previewDir = path.join(
  outDir,
  "secure_storage_ecg_paper_comparison_summary_32_preview",
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
  green: "#099A82",
  red: "#F22D3A",
  paleGreen: "#EBFFF6",
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

function shape(slide, name, geometry, position, fill, line = C.grid, radius = 0) {
  return slide.shapes.add({
    geometry,
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

function rect(slide, name, position, fill, line = C.grid, radius = 0) {
  return shape(slide, name, radius ? "roundRect" : "rect", position, fill, line, radius);
}

function text(slide, name, value, position, options = {}) {
  const box = shape(slide, name, "textbox", position, "none", "none");
  box.text = value;
  box.text.style = {
    fontSize: options.fontSize ?? 32,
    bold: options.bold ?? false,
    color: options.color ?? C.text,
    typeface: "Arial",
    alignment: options.alignment ?? "left",
    verticalAlignment: options.verticalAlignment ?? "top",
    wrap: "square",
    insets: options.insets ?? { left: 0, right: 0, top: 0, bottom: 0 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function cell(slide, name, value, position, fill, options = {}) {
  const box = rect(slide, `${name}-box`, position, fill, options.line ?? C.grid, options.radius ?? 0);
  box.text = value;
  box.text.style = {
    fontSize: options.fontSize ?? 32,
    bold: options.bold ?? false,
    color: options.color ?? C.text,
    typeface: "Arial",
    alignment: options.alignment ?? "center",
    verticalAlignment: "middle",
    wrap: "square",
    insets: options.insets ?? { left: 10, right: 10, top: 6, bottom: 6 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function addHeader(slide) {
  rect(slide, "logo-circle", { left: 66, top: 34, width: 78, height: 78 }, C.white, C.blue, 39);
  text(slide, "logo-c", "C", { left: 84, top: 43, width: 42, height: 42 }, {
    fontSize: 42,
    bold: true,
    color: C.blue,
    alignment: "center",
    verticalAlignment: "middle",
  });
  text(slide, "uni", "HO CHI MINH CITY UNIVERSITY OF TECHNOLOGY\nAND EDUCATION", {
    left: 165,
    top: 38,
    width: 650,
    height: 62,
  }, { fontSize: 22, bold: true, color: C.blueDark, lineSpacing: 0.9 });
  text(slide, "uni-sub", "HCMC University of Technology and Education", {
    left: 165,
    top: 100,
    width: 560,
    height: 24,
  }, { fontSize: 16, color: C.muted });

  const band = shape(slide, "section-band", "rightArrow", {
    left: 45,
    top: 150,
    width: 930,
    height: 74,
  }, C.cyan, C.cyanLine);
  band.text = "DESIGN QUALITY EVALUATION";
  band.text.style = {
    fontSize: 42,
    bold: true,
    color: C.blueDark,
    typeface: "Arial",
    alignment: "left",
    verticalAlignment: "middle",
    insets: { left: 25, right: 12, top: 0, bottom: 0 },
  };
}

function addLeft(slide, logBlob) {
  text(slide, "left-title", "RTL/FPGA Run Evidence", {
    left: 70,
    top: 260,
    width: 690,
    height: 46,
  }, { fontSize: 40, bold: true });
  text(slide, "left-sub", "Secure-storage workload on MIT-BIH ECG records", {
    left: 70,
    top: 312,
    width: 760,
    height: 36,
  }, { fontSize: 32 });

  slide.images.add({
    blob: logBlob,
    contentType: "image/png",
    alt: "Secure-storage FPGA run log",
    fit: "contain",
    position: { left: 70, top: 372, width: 780, height: 360 },
    geometry: "roundRect",
    borderRadius: "rounded-xl",
  });

  const cards = [
    ["29.87%", "final ratio"],
    ["70.13%", "space saving"],
    ["100%", "byte match"],
  ];
  for (const [idx, [value, label]] of cards.entries()) {
    const left = 70 + idx * 265;
    rect(slide, `kpi-${idx}`, { left, top: 760, width: 235, height: 126 }, C.white, C.grid, 12);
    text(slide, `kpi-value-${idx}`, value, { left, top: 778, width: 235, height: 56 }, {
      fontSize: 46,
      bold: true,
      color: C.blueDark,
      alignment: "center",
      verticalAlignment: "middle",
    });
    text(slide, `kpi-label-${idx}`, label, { left, top: 834, width: 235, height: 36 }, {
      fontSize: 32,
      bold: true,
      color: C.muted,
      alignment: "center",
      verticalAlignment: "middle",
    });
  }
}

function addSummaryTable(slide) {
  text(slide, "right-title", "Comparison Summary", {
    left: 900,
    top: 260,
    width: 760,
    height: 48,
  }, { fontSize: 40, bold: true });
  text(slide, "right-sub", "Paper baseline: ECG Huffman + CBC-AES [1]", {
    left: 900,
    top: 312,
    width: 800,
    height: 36,
  }, { fontSize: 32 });

  const x0 = 900;
  const y0 = 372;
  const colW = [280, 220, 220, 250];
  const rowH = [64, 74, 74, 74, 74, 74, 74, 74];
  const headers = ["Metric", "Paper [1]", "This Work", "Evaluation"];
  const rows = [
    ["Final ratio", "35.015%", "29.87%", "+14.69%"],
    ["Space saving", "64.985%", "70.13%", "+7.92%"],
    ["Huff. comp.", "~3.8641 s", "1.056 ms", "+99.97%"],
    ["Huff. decomp.", "~0.5818 s", "0.483 ms", "+99.92%"],
    ["AES encrypt", "~2.7106 s", "29.6 us", "+99.999%"],
    ["AES decrypt", "~3.0449 s", "69.2 us", "+99.998%"],
    ["Readback", "PRD 0.411", "0 mismatch", "100% match"],
  ];

  let x = x0;
  for (let i = 0; i < headers.length; i += 1) {
    cell(slide, `head-${i}`, headers[i], {
      left: x,
      top: y0,
      width: colW[i],
      height: rowH[0],
    }, C.lightBlue, { fontSize: 32, bold: true, color: C.blueDark });
    x += colW[i];
  }

  let y = y0 + rowH[0];
  for (let r = 0; r < rows.length; r += 1) {
    x = x0;
    for (let c = 0; c < rows[r].length; c += 1) {
      const good = c === 3;
      cell(slide, `row-${r}-${c}`, rows[r][c], {
        left: x,
        top: y,
        width: colW[c],
        height: rowH[r + 1],
      }, r % 2 ? "#F3F7FF" : C.white, {
        fontSize: 32,
        bold: c === 0 || c === 3,
        color: good ? C.green : C.text,
        lineSpacing: 0.82,
        insets: { left: 6, right: 6, top: 2, bottom: 2 },
      });
      x += colW[c];
    }
    y += rowH[r + 1];
  }
}

function addFooter(slide) {
  rect(slide, "footer-blue", { left: 50, top: 992, width: 1730, height: 66 }, C.blue, C.blueDark, 14);
  rect(slide, "footer-red", { left: 1780, top: 992, width: 90, height: 66 }, C.red, C.red);
  text(slide, "footer-text", "Input type: MIT-BIH ECG records | Avg input: 3603.8 bytes/record | Raw reference: 7200 bytes/record", {
    left: 75,
    top: 1009,
    width: 1660,
    height: 38,
  }, { fontSize: 32, bold: true, color: C.white, verticalAlignment: "middle" });
  text(slide, "source", "[1] FGCS 2019 ECG Huffman + CBC-AES paper. Paper platform: MATLAB 2018a, Windows 7 64-bit, i5 2nd Gen, 8 GB RAM.", {
    left: 70,
    top: 930,
    width: 800,
    height: 48,
  }, { fontSize: 20, color: C.muted, lineSpacing: 0.9 });
}

await fs.mkdir(previewDir, { recursive: true });

const presentation = Presentation.create({ slideSize: { width: W, height: H } });
const slide = presentation.slides.add();
slide.background.fill = C.bg;

const logBlob = await readImageBlob(logImage);
addHeader(slide);
addLeft(slide, logBlob);
addSummaryTable(slide);
addFooter(slide);

await writeBlob(
  path.join(previewDir, "slide-1.png"),
  await presentation.export({ slide, format: "png", scale: 1 }),
);
await fs.writeFile(
  path.join(previewDir, "slide-1.layout.json"),
  await (await slide.export({ format: "layout" })).text(),
);

const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(pptxPath);

console.log(pptxPath);
