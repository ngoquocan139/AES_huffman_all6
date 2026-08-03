import fs from "node:fs/promises";
import path from "node:path";
import {
  Presentation,
  PresentationFile,
} from "file:///C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const ROOT = "H:/Academic/senior_project/DATN/docs";
const MEDIA = `${ROOT}/poster_a1_canva/thesis_an_tan_direct_media`;
const OUT_DIR = `${ROOT}/poster_a1_canva`;
const FINAL = `${OUT_DIR}/rv32i_huffman_aes_a1_canva_layout_v2_from_thesis.pptx`;
const PREVIEW = `${OUT_DIR}/rv32i_huffman_aes_a1_canva_layout_v2_from_thesis_preview.png`;

const W = 3179;
const H = 2245;
const BLUE = "#003B95";
const DARK = "#001B5B";
const MID = "#0F66C2";
const LIGHT = "#EAF2FF";
const LINE = "#1C6FDB";
const TEXT = "#111827";
const MUTED = "#4B5563";
const ORANGE = "#F28C28";
const GREEN = "#159A85";

await fs.mkdir(OUT_DIR, { recursive: true });

async function blobFor(file) {
  const bytes = await fs.readFile(file);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function contentType(file) {
  const ext = path.extname(file).toLowerCase();
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".webp") return "image/webp";
  return "image/png";
}

const presentation = Presentation.create({ slideSize: { width: W, height: H } });
const slide = presentation.slides.add();
slide.background.fill = "white";

function shape(geometry, x, y, w, h, fill, line = "none", width = 0, name = undefined) {
  return slide.shapes.add({
    geometry,
    name,
    position: { left: x, top: y, width: w, height: h },
    fill,
    line: { style: "solid", fill: line, width },
  });
}

function text(value, x, y, w, h, opts = {}) {
  const box = shape("textbox", x, y, w, h, "none", "none", 0, opts.name);
  box.text = value;
  box.text.style = {
    fontSize: opts.size ?? 32,
    bold: opts.bold ?? false,
    color: opts.color ?? TEXT,
    alignment: opts.align ?? "left",
  };
  return box;
}

function header(title, x, y, w, num) {
  shape("roundRect", x, y, w, 70, BLUE, BLUE, 0);
  text(`${num}. ${title}`, x + 28, y + 14, w - 56, 44, {
    size: 34,
    bold: true,
    color: "white",
  });
}

function panel(num, title, x, y, w, h, headerW = undefined) {
  shape("roundRect", x, y, w, h, "white", LINE, 3);
  header(title, x, y, headerW ?? Math.min(w * 0.76, w - 20), num);
  return { x, y, w, h, bx: x + 24, by: y + 92, bw: w - 48, bh: h - 116 };
}

async function image(fileName, x, y, w, h, alt, opts = {}) {
  const file = `${MEDIA}/${fileName}`;
  if (opts.frame !== false) {
    shape("roundRect", x, y, w, h, opts.fill ?? "white", opts.line ?? "#C9D7EF", opts.lineWidth ?? 2);
  }
  const pad = opts.pad ?? 8;
  slide.images.add({
    blob: await blobFor(file),
    contentType: contentType(file),
    alt,
    fit: opts.fit ?? "contain",
    position: { left: x + pad, top: y + pad, width: w - 2 * pad, height: h - 2 * pad },
  });
}

function bullet(items, x, y, w, opts = {}) {
  let cy = y;
  for (const item of items) {
    text(`• ${item}`, x, cy, w, opts.itemH ?? 42, {
      size: opts.size ?? 32,
      color: opts.color ?? TEXT,
    });
    cy += opts.lineH ?? 48;
  }
}

function card(title, value, x, y, w, h, color = BLUE) {
  shape("roundRect", x, y, w, h, "#F8FBFF", "#B7C9EA", 2);
  text(title, x + 18, y + 16, w - 36, 34, { size: 30, bold: true, color: DARK, align: "center" });
  text(value, x + 18, y + 58, w - 36, h - 68, { size: 36, bold: true, color, align: "center" });
}

function simpleTable(x, y, w, h, columns, rows, opts = {}) {
  const colWidths = opts.colWidths ?? columns.map(() => 1 / columns.length);
  const headerH = opts.headerH ?? 58;
  const rowH = (h - headerH) / rows.length;
  let cx = x;
  columns.forEach((col, i) => {
    const cw = w * colWidths[i];
    shape("rect", cx, y, cw, headerH, BLUE, "white", 1);
    text(col, cx + 8, y + 11, cw - 16, headerH - 18, {
      size: opts.headerSize ?? 30,
      bold: true,
      color: "white",
      align: "center",
    });
    cx += cw;
  });
  rows.forEach((row, r) => {
    cx = x;
    const fill = r % 2 === 0 ? "#F6FAFF" : "#EDF4FF";
    row.forEach((cell, i) => {
      const cw = w * colWidths[i];
      shape("rect", cx, y + headerH + r * rowH, cw, rowH, fill, "white", 1);
      text(String(cell), cx + 8, y + headerH + r * rowH + 8, cw - 16, rowH - 14, {
        size: opts.bodySize ?? 28,
        bold: opts.boldFirstCol && i === 0,
        color: i === 0 ? DARK : TEXT,
        align: opts.alignCenter?.includes(i) ? "center" : "left",
      });
      cx += cw;
    });
  });
}

// Header
shape("rect", 0, 0, W, 245, "white");
shape("rect", 0, 238, W, 10, BLUE);
await image("image1.jpeg", 38, 22, 150, 174, "HCMUTE logo", { frame: false, pad: 0 });
text("HCMC UNIVERSITY OF TECHNOLOGY AND ENGINEERING\nFACULTY OF ADVANCED EDUCATION", 210, 45, 610, 105, {
  size: 32,
  bold: true,
  color: DARK,
  align: "center",
});
shape("rect", 850, 28, 4, 170, BLUE, BLUE, 0);
text("DESIGN OF A RISC-V RV32I SYSTEM INTEGRATING\nHUFFMAN COMPRESSION AND AES-128\nFOR SECURE DATA STORAGE", 900, 18, 1430, 190, {
  size: 36,
  bold: true,
  color: DARK,
  align: "center",
});
text("Advisor: Dr. Tan Do-Duy\nNgo Quoc An - 21161226\nBui Ngoc Duy Tan - 21161266", 2390, 47, 720, 145, {
  size: 32,
  bold: true,
  color: DARK,
});

const infoY = 275;
const topY = 595;
const sideW = 840;
const centerW = 1380;
const gap = 28;
const leftX = 34;
const centerX = leftX + sideW + gap;
const rightX = centerX + centerW + gap;

// Short introduction row
let p = panel(1, "SUMMARY / PROBLEM", leftX, infoY, 980, 280, 560);
bullet(
  [
    "Embedded storage needs security and compact data size.",
    "Compress before encryption to remove redundancy.",
    "Target: secure storage on constrained SoCs.",
  ],
  p.bx + 4,
  p.by,
  p.bw - 8,
  { size: 32, lineH: 48, itemH: 42 },
);

p = panel(2, "OBJECTIVES", leftX + 1010, infoY, 980, 280, 480);
bullet(
  [
    "Build an RV32I secure-storage SoC.",
    "Integrate Huffman compression and AES-128-CBC.",
    "Verify loopback, metadata, and FPGA operation.",
  ],
  p.bx + 4,
  p.by,
  p.bw - 8,
  { size: 32, lineH: 48, itemH: 42 },
);

p = panel(3, "BASIS", leftX + 2020, infoY, 1090, 280, 380);
bullet(
  [
    "Dynamic Huffman: lossless compression.",
    "AES-128-CBC: IV and feedback chaining.",
    "RV32I/APB/DMA: control and data movement.",
  ],
  p.bx + 4,
  p.by,
  p.bw - 8,
  { size: 32, lineH: 48, itemH: 42 },
);

// Main architecture row
p = panel(4, "TX ACCELERATOR", leftX, topY, sideW, 500, 480);
await image("image16.png", p.bx, p.by, p.bw, 275, "TX accelerator architecture from thesis", { pad: 6 });
bullet(["Plaintext -> Huffman", "Bit packing -> 128-bit words", "AES-128-CBC -> ciphertext"], p.bx + 8, p.by + 292, p.bw - 16, {
  size: 30,
  lineH: 38,
  itemH: 34,
});

p = panel(5, "OVERALL ARCHITECTURE", centerX, topY, centerW, 500, 720);
await image("image9.png", p.bx, p.by, p.bw, 292, "Overall RV32I secure-storage SoC architecture", { pad: 6 });
card("Control plane", "RV32I + APB/MMIO", p.bx, p.by + 310, 410, 88, BLUE);
card("Data movement", "TX/RX DMA + DMEM", p.bx + 450, p.by + 310, 410, 88, ORANGE);
card("Accelerators", "Huffman + AES-CBC", p.bx + 900, p.by + 310, 410, 88, GREEN);

p = panel(6, "RX ACCELERATOR", rightX, topY, sideW, 500, 480);
await image("image26.png", p.bx, p.by, p.bw, 275, "RX accelerator architecture from thesis", { pad: 6 });
bullet(["Ciphertext -> AES-CBC decrypt", "Bit depacker reconstructs stream", "Huffman decode -> plaintext"], p.bx + 8, p.by + 292, p.bw - 16, {
  size: 30,
  lineH: 38,
  itemH: 34,
});

// Results row
const row2Y = 1120;
p = panel(7, "FUNCTIONAL VERIFICATION", leftX, row2Y, 1010, 420, 590);
simpleTable(
  p.bx,
  p.by,
  p.bw,
  p.bh - 8,
  ["Group", "Tests", "Result"],
  [
    ["End-to-end loopback", "5", "PASS"],
    ["TX compression / packing", "8", "PASS"],
    ["MMIO / APB / DMA", "8", "PASS"],
    ["TX / RX direct modules", "9", "PASS"],
    ["CPU + raw DUT stress", "4", "PASS"],
    ["Total regression", "34", "PASS"],
  ],
  { colWidths: [0.62, 0.16, 0.22], bodySize: 29, headerSize: 30, boldFirstCol: true, alignCenter: [1, 2] },
);

p = panel(8, "DATASET STORAGE RESULTS", leftX + 1040, row2Y, 1110, 420, 660);
simpleTable(
  p.bx,
  p.by,
  p.bw,
  p.bh - 8,
  ["Dataset", "Plain", "Stored", "Saving", "Throughput"],
  [
    ["SpO2 / heart-rate", "2,551 B", "880 B", "65.50%", "TX 7.817 / RX 16.858 MB/s"],
    ["ECG", "3,603.8 B", "2,150.4 B", "70.13%", "TX 6.771 / RX 14.918 MB/s"],
    ["Log-event", "2,839 B", "1,856 B", "34.62%", "TX 6.597 / RX 14.458 MB/s"],
  ],
  { colWidths: [0.24, 0.16, 0.16, 0.15, 0.29], bodySize: 27, headerSize: 30, boldFirstCol: true, alignCenter: [1, 2, 3] },
);

p = panel(9, "FPGA IMPLEMENTATION", rightX, row2Y, sideW, 420, 520);
simpleTable(
  p.bx,
  p.by,
  p.bw,
  p.bh - 8,
  ["Design", "LUTs", "FF", "BRAM", "Power"],
  [
    ["RV32I CPU", "2,400", "1,639", "0", "~0.002 W"],
    ["TX accelerator", "10,734", "2,806", "0", "0.042 W"],
    ["RX accelerator", "21,253", "13,163", "1", "0.082 W"],
    ["Full FPGA SoC", "36,649", "20,017", "11", "0.788 W"],
  ],
  { colWidths: [0.34, 0.16, 0.15, 0.14, 0.21], bodySize: 26, headerSize: 29, boldFirstCol: true, alignCenter: [1, 2, 3, 4] },
);

// Bottom row
const row3Y = 1565;
p = panel(10, "PERFORMANCE COMPARISON", leftX, row3Y, 1565, 615, 680);
await image("image59.png", p.bx, p.by, p.bw, 370, "Performance comparison chart from thesis", { pad: 6 });
card("AES throughput", "145.5 MB/s", p.bx, p.by + 386, 350, 88, BLUE);
card("Secure TX", "0.078 B/cycle", p.bx + 390, p.by + 386, 350, 88, ORANGE);
card("ECG storage saving", "70.13%", p.bx + 780, p.by + 386, 350, 88, GREEN);
card("Full regression", "34 / 34 PASS", p.bx + 1170, p.by + 386, 350, 88, BLUE);

p = panel(11, "RELATED-WORK COMPARISON", leftX + 1595, row3Y, 920, 615, 610);
simpleTable(
  p.bx,
  p.by,
  p.bw,
  380,
  ["Reference / scope", "This work", "Conclusion"],
  [
    ["secworks/aes", "11 cycles/block", "Lower AES latency for this embedded scope"],
    ["ECG Huffman + CBC-AES", "70.13% saving", "Better final stored-size result"],
    ["Vitis GZip", "Full RV32I secure-storage SoC", "Integrates CPU, DMA, metadata, AES, and recovery"],
  ],
  { colWidths: [0.28, 0.27, 0.45], bodySize: 26, headerSize: 29, boldFirstCol: true },
);

p = panel(12, "REFERENCES", leftX + 2545, row3Y, 566, 615, 360);
bullet(
  [
    "[18] Salomon, Data Compression: The Complete Reference, 2007.",
    "[19] NIST, Advanced Encryption Standard, FIPS 197, 2023.",
    "[20] NIST SP 800-38A, CBC mode recommendation, 2001.",
    "[21] Huffman, minimum-redundancy codes, 1952.",
    "[22] Arm AMBA APB protocol specification, 2021.",
  ],
  p.bx + 4,
  p.by,
  p.bw - 8,
  { size: 29, lineH: 74, itemH: 64 },
);

shape("rect", 0, H - 35, W, 10, BLUE);
text("Source: Graduation_Thesis_an_tan.docx | figures and tables rebuilt from thesis content", 46, H - 82, 1500, 42, {
  size: 32,
  color: MUTED,
});
text("A1 editable Canva poster", W - 720, H - 82, 670, 42, {
  size: 32,
  color: MUTED,
  align: "right",
});

const preview = await presentation.export({ slide, format: "png", scale: 0.35 });
await fs.writeFile(PREVIEW, new Uint8Array(await preview.arrayBuffer()));
const layout = await slide.export({ format: "layout" });
await fs.writeFile(`${OUT_DIR}/rv32i_huffman_aes_a1_canva_layout_v2_from_thesis.layout.json`, await layout.text(), "utf8");
const inspect = await presentation.inspect({ kind: "slide,textbox,shape,image", maxChars: 12000 });
await fs.writeFile(`${OUT_DIR}/rv32i_huffman_aes_a1_canva_layout_v2_from_thesis.inspect.ndjson`, inspect.ndjson, "utf8");
const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(FINAL);
console.log(JSON.stringify({ final: FINAL, preview: PREVIEW }, null, 2));
