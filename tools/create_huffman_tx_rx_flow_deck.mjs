import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const artifactToolEntry =
  process.env.ARTIFACT_TOOL_ENTRYPOINT ||
  "C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const { Presentation, PresentationFile } = await import(
  pathToFileURL(artifactToolEntry).href
);

const outDir =
  "H:/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/generated_figures";
const finalPptx = path.join(outDir, "huffman_tx_rx_flow_4slides.pptx");

const W = 1280;
const H = 720;
const BLUE = "#0b3f98";
const GREEN = "#15915c";
const ORANGE = "#f28c22";
const PURPLE = "#7137d8";
const TEXT = "#111827";
const MUTED = "#5f6f89";
const LIGHT_BLUE = "#eaf2ff";
const LIGHT_GREEN = "#ecfff5";
const LIGHT_ORANGE = "#fff4df";
const LIGHT_PURPLE = "#f0e8ff";
const YELLOW = "#f6a817";
const BORDER = "#c7d3e6";
const BG = "#f7f9fd";

async function writeBlob(file, blob) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, Buffer.from(await blob.arrayBuffer()));
}

function addShape(slide, geometry, position, fill = "white", lineFill = BORDER, width = 1) {
  return slide.shapes.add({
    geometry,
    position,
    fill,
    line: { style: "solid", fill: lineFill, width },
  });
}

function addText(slide, text, position, opts = {}) {
  const box = slide.shapes.add({
    geometry: "textbox",
    position,
    fill: "none",
    line: { style: "solid", fill: "none", width: 0 },
  });
  box.text = text;
  box.text.style = {
    fontSize: opts.size ?? 18,
    bold: opts.bold ?? false,
    color: opts.color ?? TEXT,
    fontFamily: opts.fontFamily ?? "Arial",
    alignment: opts.align ?? "left",
  };
  return box;
}

function addTitle(slide, title, subtitle) {
  addText(slide, title, { left: 38, top: 24, width: 1140, height: 44 }, {
    size: 36,
    bold: true,
    color: BLUE,
  });
  addText(slide, subtitle, { left: 40, top: 68, width: 1140, height: 26 }, {
    size: 17,
    color: TEXT,
  });
  addShape(slide, "rect", { left: 0, top: 100, width: W, height: 5 }, BLUE, BLUE, 0);
}

function addPanel(slide, x, y, w, h, title, color) {
  addShape(slide, "rect", { left: x, top: y, width: w, height: h }, "white", BORDER, 1.2);
  addShape(slide, "rect", { left: x, top: y, width: w, height: 42 }, color, color, 0);
  addText(slide, title, { left: x + 16, top: y + 9, width: w - 32, height: 25 }, {
    size: 21,
    bold: true,
    color: "white",
  });
}

function addArrow(slide, x, y, w = 42) {
  addShape(slide, "rightArrow", { left: x, top: y, width: w, height: 26 }, BLUE, BLUE, 0);
}

function addCodeCell(slide, x, y, w, h, text, fill, line, opts = {}) {
  const shape = addShape(slide, "rect", { left: x, top: y, width: w, height: h }, fill, line, 1.4);
  shape.text = text;
  shape.text.style = {
    fontSize: opts.size ?? 16,
    bold: opts.bold ?? false,
    color: opts.color ?? TEXT,
    fontFamily: opts.fontFamily ?? "Consolas",
    alignment: opts.align ?? "center",
  };
  return shape;
}

function addLine(slide, x1, y1, x2, y2, color = TEXT, width = 2) {
  return slide.shapes.add({
    geometry: "line",
    position: { left: x1, top: y1, width: x2 - x1, height: y2 - y1 },
    fill: "none",
    line: { style: "solid", fill: color, width },
  });
}

function addLeaf(slide, x, y, weight, symbol, len, scale = 1) {
  const w = 52 * scale;
  const h = 46 * scale;
  const shape = addShape(
    slide,
    "rect",
    { left: x - w / 2, top: y - h / 2, width: w, height: h },
    YELLOW,
    TEXT,
    1.2,
  );
  shape.text = `${weight}\n${symbol}`;
  shape.text.style = {
    fontSize: 13 * scale,
    bold: true,
    color: TEXT,
    fontFamily: "Arial",
    alignment: "center",
  };
  if (len) {
    addText(slide, `len=${len}`, { left: x - 33, top: y + h / 2 + 4, width: 66, height: 17 }, {
      size: 11,
      bold: true,
      color: BLUE,
      align: "center",
    });
  }
}

function addInternal(slide, x, y, weight, r = 23) {
  addShape(
    slide,
    "ellipse",
    { left: x - r, top: y - r, width: 2 * r, height: 2 * r },
    "white",
    TEXT,
    1.2,
  );
  addText(slide, String(weight), { left: x - 27, top: y - 10, width: 54, height: 22 }, {
    size: 15,
    color: TEXT,
    align: "center",
  });
}

function addKeyIdea(slide, text) {
  addShape(slide, "rect", { left: 38, top: 626, width: 1140, height: 36 }, "#eef5ff", "#3b7cff", 1.2);
  addText(slide, text, { left: 55, top: 634, width: 1105, height: 23 }, {
    size: 17,
    bold: true,
    color: BLUE,
  });
}

function addTxTreeSlide(presentation) {
  const slide = presentation.slides.add();
  slide.background.fill = BG;
  addTitle(
    slide,
    "TX Huffman Tree to Code Length",
    "TX builds a Huffman tree by repeatedly merging the two lowest-weight nodes, then uses leaf depth as code_len.",
  );

  addPanel(slide, 38, 122, 335, 485, "1. Initial partial trees", BLUE);
  addText(slide, "Start with one leaf per symbol", { left: 65, top: 176, width: 270, height: 25 }, { size: 17 });
  const items = [[2, "Z"], [7, "K"], [24, "M"], [32, "C"], [37, "U"], [42, "D"], [42, "L"], [120, "E"]];
  const xs = [88, 164, 240, 316];
  const ys = [252, 346];
  items.forEach(([weight, symbol], i) => addLeaf(slide, xs[i % 4], ys[Math.floor(i / 4)], weight, symbol, null, 1.12));
  addShape(slide, "rect", { left: 67, top: 445, width: 267, height: 120 }, LIGHT_BLUE, "#4b83e6", 1.2);
  addText(slide, "Priority queue rule", { left: 88, top: 462, width: 225, height: 25 }, {
    size: 19,
    bold: true,
    color: BLUE,
  });
  addText(slide, "Merge two lowest weights.\nParent weight = sum.", { left: 88, top: 500, width: 225, height: 45 }, {
    size: 16,
  });
  addText(slide, "parent = w1 + w2", { left: 88, top: 540, width: 225, height: 26 }, {
    size: 15,
    bold: true,
    fontFamily: "Consolas",
  });

  addPanel(slide, 405, 122, 295, 485, "2. Merge until root", GREEN);
  addText(slide, "Each row is one merge:", { left: 430, top: 176, width: 230, height: 25 }, { size: 17 });
  const rows = [
    ["1", "Z2 + K7", "9"],
    ["2", "9 + M24", "33"],
    ["3", "C32 + 33", "65"],
    ["4", "U37 + D42", "79"],
    ["5", "L42 + 65", "107"],
    ["6", "79 + 107", "186"],
    ["7", "E120 + 186", "306"],
  ];
  let y = 218;
  for (const [n, lhs, rhs] of rows) {
    addCodeCell(slide, 430, y, 34, 27, n, LIGHT_GREEN, "#20b36d", { size: 14, bold: true, fontFamily: "Arial" });
    addCodeCell(slide, 480, y, 105, 27, lhs, "#f8fbff", BORDER, { size: 12, bold: true });
    addArrow(slide, 592, y + 4, 25);
    addCodeCell(slide, 625, y, 52, 27, rhs, LIGHT_ORANGE, ORANGE, { size: 14, bold: true });
    y += 43;
  }
  addCodeCell(slide, 430, 546, 247, 37, "Stop: one root = 306", LIGHT_GREEN, "#20b36d", {
    size: 16,
    bold: true,
    fontFamily: "Arial",
  });

  addPanel(slide, 732, 122, 510, 485, "3. Final tree and code_len", ORANGE);
  const p = {
    root: [980, 190],
    E: [845, 250],
    n186: [1075, 250],
    n79: [960, 313],
    n107: [1138, 313],
    U: [900, 375],
    D: [985, 375],
    L: [1080, 375],
    n65: [1188, 375],
    C: [1138, 438],
    n33: [1210, 438],
    n9: [1166, 500],
    M: [1220, 500],
    Z: [1132, 560],
    K: [1192, 560],
  };
  const gy = [190, 250, 313, 375, 438, 500, 560];
  gy.forEach((lineY, d) => {
    addLine(slide, 770, lineY, 1220, lineY, "#d9e3f2", 1);
    addText(slide, `d${d}`, { left: 775, top: lineY - 12, width: 30, height: 17 }, {
      size: 11,
      color: "#7891b9",
    });
  });
  const edges = [
    ["root", "E"],
    ["root", "n186"],
    ["n186", "n79"],
    ["n186", "n107"],
    ["n79", "U"],
    ["n79", "D"],
    ["n107", "L"],
    ["n107", "n65"],
    ["n65", "C"],
    ["n65", "n33"],
    ["n33", "n9"],
    ["n33", "M"],
    ["n9", "Z"],
    ["n9", "K"],
  ];
  edges.forEach(([a, b]) => addLine(slide, p[a][0], p[a][1], p[b][0], p[b][1], TEXT, 1.4));
  addInternal(slide, ...p.root, 306);
  addInternal(slide, ...p.n186, 186);
  addInternal(slide, ...p.n79, 79);
  addInternal(slide, ...p.n107, 107);
  addInternal(slide, ...p.n65, 65);
  addInternal(slide, ...p.n33, 33);
  addInternal(slide, ...p.n9, 9);
  addLeaf(slide, ...p.E, 120, "E", 1, 0.82);
  addLeaf(slide, ...p.U, 37, "U", 3, 0.72);
  addLeaf(slide, ...p.D, 42, "D", 3, 0.72);
  addLeaf(slide, ...p.L, 42, "L", 3, 0.72);
  addLeaf(slide, ...p.C, 32, "C", 4, 0.68);
  addLeaf(slide, ...p.M, 24, "M", 5, 0.64);
  addLeaf(slide, ...p.Z, 2, "Z", 6, 0.6);
  addLeaf(slide, ...p.K, 7, "K", 6, 0.6);
  addCodeCell(
    slide,
    765,
    580,
    440,
    34,
    "code_len = leaf depth: E=1, U/D/L=3, C=4, M=5, Z/K=6",
    "#fff9f0",
    ORANGE,
    { size: 13, bold: true, fontFamily: "Arial" },
  );

  addKeyIdea(
    slide,
    "TX output from this stage is code_len for each symbol; the tree shape itself is not stored in the compressed block.",
  );
}

function addCanonicalFlowSlide(presentation, mode) {
  const isTx = mode === "tx";
  const slide = presentation.slides.add();
  slide.background.fill = BG;
  addTitle(
    slide,
    isTx ? "TX Canonical Huffman Encoding" : "RX Canonical Huffman Reconstruction",
    isTx
      ? "Tree depth gives code_len. TX sorts symbols and assigns deterministic canonical codes."
      : "RX reads only symbol + code length from the header, then rebuilds the same canonical code table as TX.",
  );
  const y = 122;
  const h = 485;
  const widths = [285, 210, 265, 285];
  const xs = [38, 355, 598, 895];

  addPanel(slide, xs[0], y, widths[0], h, isTx ? "1. Read tree depth" : "1. Read header entries", BLUE);
  addText(
    slide,
    isTx ? "code_len = tree depth" : "Header carries codebook\ninformation:",
    { left: xs[0] + 25, top: y + 58, width: 230, height: 50 },
    { size: 16, bold: isTx },
  );
  addCodeCell(
    slide,
    xs[0] + 30,
    y + 100,
    isTx ? 220 : 218,
    isTx ? 260 : 270,
    isTx
      ? "symbol   depth   len\n\nE        1       1\nU        3       3\nD        3       3\nL        3       3\nC        4       4\nM        5       5\nZ        6       6\nK        6       6"
      : "symbol   code_len\n\nE    1\nD    3\nL    3\nU    3\nC    4\nM    5\nK    6\nZ    6",
    "#f8fbff",
    BORDER,
    { size: isTx ? 15 : 17, align: "left" },
  );
  addCodeCell(
    slide,
    xs[0] + 30,
    y + 395,
    isTx ? 220 : 218,
    isTx ? 44 : 46,
    isTx ? "code_len" : "No original tree stored",
    LIGHT_BLUE,
    "#4b83e6",
    { size: isTx ? 17 : 16, bold: true, fontFamily: "Arial" },
  );
  addArrow(slide, 321, 335);

  addPanel(slide, xs[1], y, widths[1], h, isTx ? "2. Sort" : "2. Sort entries", GREEN);
  addText(slide, "Canonical order:", { left: xs[1] + 18, top: y + 62, width: widths[1] - 36, height: 25 }, {
    size: 17,
    bold: true,
  });
  addText(
    slide,
    "shorter code_len first\nsame length: ASCII first",
    { left: xs[1] + 18, top: y + 94, width: widths[1] - 36, height: 64 },
    { size: 15 },
  );
  addCodeCell(slide, xs[1] + 49, y + 175, 112, 240, "Order\n\nE\nD\nL\nU\nC\nM\nK\nZ", LIGHT_GREEN, "#20b36d", {
    size: 18,
    bold: true,
    fontFamily: "Arial",
  });
  addCodeCell(slide, xs[1] + 30, y + 430, 150, 34, "len=3: D < L < U", "#f8fbff", BORDER, {
    size: 13,
    fontFamily: "Arial",
  });
  addArrow(slide, 564, 335);

  addPanel(slide, xs[2], y, widths[2], h, isTx ? "3. Assign code" : "3. Recreate codes", ORANGE);
  addText(
    slide,
    isTx ? "Start: current_code = 0" : "Start with current_code = 0.",
    { left: xs[2] + 18, top: y + 58, width: widths[2] - 36, height: 27 },
    { size: 16, bold: true },
  );
  const rows = [
    ["len", isTx ? "assigned code" : "generated code"],
    ["1", "E = 0"],
    ["2", isTx ? "no symbol; shift left" : "no symbol, shift left"],
    ["3", "D = 100\nL = 101\nU = 110"],
    ["4", "C = 1110"],
    ["5", "M = 11110"],
    ["6", "K = 111110\nZ = 111111"],
  ];
  let rowY = y + 100;
  const rowHeights = [30, 42, 48, 78, 42, 42, 62];
  rows.forEach((row, i) => {
    const fill = i === 0 ? "#ffd29b" : i % 2 ? "#eef6ff" : "#f7fbff";
    addCodeCell(slide, xs[2] + 22, rowY, 52, rowHeights[i], row[0], fill, "#d6e1ef", {
      size: i === 0 ? 15 : 14,
      bold: i === 0,
      fontFamily: i === 0 ? "Arial" : "Consolas",
    });
    addCodeCell(slide, xs[2] + 74, rowY, 168, rowHeights[i], row[1], fill, "#d6e1ef", {
      size: i === 0 ? 15 : 14,
      bold: i === 0,
      align: "left",
      fontFamily: i === 0 ? "Arial" : "Consolas",
    });
    rowY += rowHeights[i];
  });
  addArrow(slide, 862, 335);

  addPanel(slide, xs[3], y, widths[3], h, isTx ? "4. TX tables" : "4. RX lookup table", PURPLE);
  if (isTx) {
    addText(slide, "Header: codebook info", { left: xs[3] + 25, top: y + 58, width: 230, height: 25 }, {
      size: 17,
      bold: true,
    });
    addCodeCell(
      slide,
      xs[3] + 28,
      y + 92,
      222,
      90,
      "E:1    D:3    L:3    U:3\nC:4    M:5    K:6    Z:6",
      LIGHT_PURPLE,
      "#8a55f0",
      { size: 15 },
    );
    addText(slide, "Payload: canonical codes", { left: xs[3] + 25, top: y + 205, width: 230, height: 25 }, {
      size: 17,
      bold: true,
    });
    addCodeCell(
      slide,
      xs[3] + 28,
      y + 240,
      222,
      180,
      "E = 0\nD = 100\nL = 101\nU = 110\nC = 1110\nM = 11110\nK = 111110\nZ = 111111",
      LIGHT_BLUE,
      "#3b7cff",
      { size: 15, align: "left" },
    );
  } else {
    addText(slide, "The decoder stores prefix rules:", { left: xs[3] + 18, top: y + 58, width: widths[3] - 36, height: 28 }, {
      size: 16,
    });
    addCodeCell(
      slide,
      xs[3] + 28,
      y + 100,
      222,
      250,
      "code    symbol\n\n0      E\n100    D\n101    L\n110    U\n1110   C\n11110  M\n111110 K\n111111 Z",
      LIGHT_PURPLE,
      "#8a55f0",
      { size: 16, align: "left" },
    );
    addText(
      slide,
      "Same table as TX because the canonical rule is deterministic.",
      { left: xs[3] + 20, top: y + 372, width: widths[3] - 40, height: 72 },
      { size: 16 },
    );
  }

  addKeyIdea(
    slide,
    isTx
      ? "TX output: header carries codebook information; payload carries compressed bits encoded with canonical codes."
      : "Key idea: RX reconstructs the codebook from code_len; it does not transmit or rebuild the original Huffman tree.",
  );
}

function addRxPayloadSlide(presentation) {
  const slide = presentation.slides.add();
  slide.background.fill = BG;
  addTitle(
    slide,
    "RX Huffman Payload Decoding",
    "After the table is rebuilt, payload bits are consumed by prefix match until block_size output bytes are recovered.",
  );
  addPanel(slide, 42, 123, 1145, 148, "Compressed block seen by RX", BLUE);
  const cells = [
    ["mode\n2b", 90, "#e6f0ff", "#3b7cff"],
    ["block_size\n7 bytes", 150, "#dbfae8", "#1eb96f"],
    ["symbol_count\n8 entries", 170, "#fff2c7", "#f4a621"],
    ["entries\nE:1 D:3 L:3 U:3 ...", 320, LIGHT_PURPLE, "#8a55f0"],
    ["payload bits\n0 0 0 100 100 101 0", 360, LIGHT_ORANGE, ORANGE],
  ];
  let x = 70;
  for (const [text, width, fill, line] of cells) {
    addCodeCell(slide, x, 175, width, 62, text, fill, line, { size: 15, bold: true, fontFamily: "Arial" });
    x += width;
  }
  addText(
    slide,
    "Header = dictionary information. Payload = actual compressed data encoded using that dictionary.",
    { left: 73, top: 242, width: 1040, height: 24 },
    { size: 15, color: MUTED },
  );

  addPanel(slide, 42, 295, 335, 315, "1. Match prefix", GREEN);
  addText(slide, "Input window:", { left: 70, top: 352, width: 140, height: 24 }, { size: 17, bold: true });
  addCodeCell(slide, 72, 382, 245, 44, "1001010...", "#f8fbff", BORDER, { size: 22 });
  addShape(slide, "downArrow", { left: 168, top: 433, width: 36, height: 42 }, MUTED, MUTED, 0);
  addCodeCell(slide, 78, 482, 235, 58, "first match: 100 = D", LIGHT_GREEN, "#20b36d", {
    size: 20,
    bold: true,
    fontFamily: "Arial",
  });
  addText(slide, "Consume 3 bits, then continue with the next prefix.", { left: 72, top: 552, width: 250, height: 42 }, {
    size: 15,
  });

  addPanel(slide, 407, 295, 430, 315, "2. Decode sequentially", ORANGE);
  addText(slide, "Example payload segmentation:", { left: 435, top: 352, width: 330, height: 24 }, {
    size: 17,
    bold: true,
  });
  const segments = [
    ["0", "E", "#eaf2ff", "#3b7cff"],
    ["0", "E", "#eaf2ff", "#3b7cff"],
    ["0", "E", "#eaf2ff", "#3b7cff"],
    ["100", "D", "#ecfff5", "#20b36d"],
    ["100", "D", "#ecfff5", "#20b36d"],
    ["101", "L", "#fff4df", "#f28c22"],
    ["0", "E", "#eaf2ff", "#3b7cff"],
  ];
  let sx = 436;
  for (const [code, symbol, fill, line] of segments) {
    const width = code.length === 1 ? 45 : 62;
    addCodeCell(slide, sx, 390, width, 42, code, fill, line, { size: 18 });
    addShape(slide, "downArrow", { left: sx + width / 2 - 11, top: 436, width: 22, height: 29 }, MUTED, MUTED, 0);
    addCodeCell(slide, sx, 472, width, 40, symbol, line, line, {
      size: 18,
      bold: true,
      color: "white",
      fontFamily: "Arial",
    });
    sx += width + 10;
  }
  addText(
    slide,
    "Repeated symbols come from repeated codewords in the payload, not from per-symbol counts in the header.",
    { left: 435, top: 550, width: 360, height: 42 },
    { size: 15 },
  );

  addPanel(slide, 867, 295, 320, 315, "3. Stop by block_size", PURPLE);
  addText(slide, "Recovered bytes:", { left: 895, top: 356, width: 248, height: 28 }, { size: 17, bold: true });
  addCodeCell(slide, 905, 408, 220, 57, "E E E D D L E", "#f8fbff", BORDER, { size: 20, bold: true });
  addText(slide, "output_count = 7\nblock_size = 7", { left: 908, top: 491, width: 255, height: 64 }, {
    size: 19,
    bold: true,
    color: BLUE,
    fontFamily: "Consolas",
  });
  addCodeCell(slide, 935, 562, 150, 42, "DONE", LIGHT_PURPLE, "#8a55f0", {
    size: 20,
    bold: true,
    fontFamily: "Arial",
  });
  addKeyIdea(
    slide,
    "Key idea: the payload carries the repeated occurrences; block_size tells RX when the original block is fully recovered.",
  );
}

async function main() {
  await fs.mkdir(outDir, { recursive: true });
  const presentation = Presentation.create({ slideSize: { width: W, height: H } });
  addTxTreeSlide(presentation);
  addCanonicalFlowSlide(presentation, "tx");
  addCanonicalFlowSlide(presentation, "rx");
  addRxPayloadSlide(presentation);

  for (const [index, slide] of presentation.slides.items.entries()) {
    const number = index + 1;
    await writeBlob(
      path.join(outDir, `huffman_tx_rx_flow_4slides_slide${number}.png`),
      await presentation.export({ slide, format: "png", scale: 1 }),
    );
    await fs.writeFile(
      path.join(outDir, `huffman_tx_rx_flow_4slides_slide${number}.layout.json`),
      await (await slide.export({ format: "layout" })).text(),
    );
  }

  await writeBlob(
    path.join(outDir, "huffman_tx_rx_flow_4slides_montage.webp"),
    await presentation.export({ format: "webp", montage: true, scale: 1 }),
  );

  const pptx = await PresentationFile.exportPptx(presentation);
  await pptx.save(finalPptx);
  console.log(finalPptx);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
