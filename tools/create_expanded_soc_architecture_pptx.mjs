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
const pptxPath = path.join(outDir, "soc_architecture_tx_rx_expanded.pptx");
const pngPath = path.join(outDir, "soc_architecture_tx_rx_expanded.png");
const previewDir = path.join(outDir, "soc_architecture_tx_rx_expanded_preview");

const W = 1920;
const H = 1080;
const C = {
  bg: "#F7FAFF",
  ink: "#122033",
  muted: "#64748B",
  grid: "#B7C7E8",
  blue: "#0B63CE",
  blueDark: "#073B8E",
  blueSoft: "#E8F1FF",
  red: "#E41D2D",
  redSoft: "#FFF1F2",
  orange: "#F28C28",
  orangeSoft: "#FFF4E6",
  green: "#059669",
  greenSoft: "#EAFBF4",
  purple: "#6D3BD1",
  purpleSoft: "#F3EEFF",
  grey: "#EEF2F7",
  white: "#FFFFFF",
};

async function writeBlob(filePath, blob) {
  await fs.writeFile(filePath, new Uint8Array(await blob.arrayBuffer()));
}

function shape(slide, name, geometry, position, fill, line = C.grid, width = 2) {
  return slide.shapes.add({
    geometry,
    name,
    position,
    fill,
    line:
      line === "none"
        ? { style: "solid", fill: "none", width: 0 }
        : { style: "solid", fill: line, width },
  });
}

function addText(slide, name, value, position, options = {}) {
  const box = shape(slide, name, "textbox", position, "none", "none", 0);
  box.text = value;
  box.text.style = {
    fontSize: options.fontSize ?? 20,
    bold: options.bold ?? false,
    color: options.color ?? C.ink,
    typeface: options.typeface ?? "Arial",
    alignment: options.alignment ?? "left",
    verticalAlignment: options.verticalAlignment ?? "top",
    wrap: "square",
    insets: options.insets ?? { left: 0, right: 0, top: 0, bottom: 0 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function addBox(slide, name, value, position, options = {}) {
  const box = shape(
    slide,
    name,
    options.geometry ?? "roundRect",
    position,
    options.fill ?? C.white,
    options.line ?? C.grid,
    options.lineWidth ?? 2,
  );
  box.text = value;
  box.text.style = {
    fontSize: options.fontSize ?? 19,
    bold: options.bold ?? false,
    color: options.color ?? C.ink,
    typeface: options.typeface ?? "Arial",
    alignment: options.alignment ?? "center",
    verticalAlignment: options.verticalAlignment ?? "middle",
    wrap: "square",
    insets: options.insets ?? { left: 8, right: 8, top: 4, bottom: 4 },
    ...(options.lineSpacing ? { lineSpacing: options.lineSpacing } : {}),
  };
  return box;
}

function arrow(slide, name, left, top, width, height, color = C.blue) {
  return shape(slide, name, "rightArrow", { left, top, width, height }, color, color, 1);
}

function downArrow(slide, name, left, top, width, height, color = C.blue) {
  return shape(slide, name, "downArrow", { left, top, width, height }, color, color, 1);
}

function section(slide, name, title, position, colors) {
  const outer = shape(slide, `${name}-outer`, "roundRect", position, colors.fill, colors.line, 3);
  const header = shape(
    slide,
    `${name}-header`,
    "roundRect",
    { left: position.left, top: position.top, width: position.width, height: 46 },
    colors.line,
    colors.line,
    2,
  );
  header.text = title;
  header.text.style = {
    fontSize: 23,
    bold: true,
    color: C.white,
    typeface: "Arial",
    alignment: "left",
    verticalAlignment: "middle",
    insets: { left: 18, right: 8, top: 0, bottom: 0 },
  };
  return outer;
}

function smallStage(slide, name, title, subtitle, x, y, w, h, colors) {
  const box = addBox(slide, name, title, { left: x, top: y, width: w, height: h }, {
    fill: colors.fill,
    line: colors.line,
    fontSize: 18,
    bold: true,
    lineSpacing: 0.9,
  });
  if (subtitle) {
    addText(slide, `${name}-sub`, subtitle, { left: x + 12, top: y + h - 34, width: w - 24, height: 28 }, {
      fontSize: 13,
      color: C.muted,
      alignment: "center",
    });
  }
  return box;
}

function pipelineArrow(slide, name, x1, y, x2, color) {
  const width = Math.max(26, x2 - x1);
  arrow(slide, name, x1, y - 10, width, 20, color);
}

function addSocOverview(slide) {
  addText(slide, "title", "Expanded RV32I SoC Architecture for Secure Storage", {
    left: 55,
    top: 32,
    width: 1250,
    height: 50,
  }, { fontSize: 36, bold: true, color: C.blueDark });
  addText(slide, "subtitle", "CPU controls the accelerator through APB/MMIO; TX and RX data movement is handled by dedicated DMA datapaths.", {
    left: 55,
    top: 80,
    width: 1500,
    height: 30,
  }, { fontSize: 19, color: C.muted });

  addBox(slide, "pl-boundary", "", { left: 45, top: 124, width: 1830, height: 875 }, {
    fill: "none",
    line: "#7D8EA8",
    lineWidth: 2,
  });
  addText(slide, "pl-label", "Zynq UltraScale+ PL: custom RV32I SoC + secure-storage accelerator", {
    left: 70,
    top: 134,
    width: 680,
    height: 28,
  }, { fontSize: 16, bold: true, color: C.muted });

  addBox(slide, "input", "INPUT\nclk\nrst_n\nuart_rx_i", { left: 65, top: 412, width: 155, height: 175 }, {
    fill: C.white,
    line: C.blue,
    lineWidth: 3,
    fontSize: 18,
    bold: true,
    lineSpacing: 0.9,
  });
  addBox(slide, "cpu", "CPU Core\nRV32I", { left: 270, top: 365, width: 180, height: 230 }, {
    fill: C.blueSoft,
    line: C.blueDark,
    fontSize: 24,
    bold: true,
  });
  pipelineArrow(slide, "input-to-cpu", 220, 495, 270, C.blue);

  addBox(slide, "apb-interface", "APB\nInterface", { left: 520, top: 410, width: 140, height: 140 }, {
    fill: C.white,
    line: C.blueDark,
    fontSize: 21,
    bold: true,
  });
  pipelineArrow(slide, "cpu-to-apb", 450, 473, 520, C.blueDark);
  addText(slide, "cpu-apb-notes", "rs2 / alu_result\nDMEM write enable", {
    left: 463,
    top: 425,
    width: 126,
    height: 50,
  }, { fontSize: 14, color: C.muted, alignment: "center" });

  addBox(slide, "dma-register", "DMA Register File\nMMIO registers\nsrc / dst / len / mode\nstatus / bytes / error", {
    left: 735,
    top: 345,
    width: 200,
    height: 280,
  }, {
    fill: C.purpleSoft,
    line: C.purple,
    fontSize: 20,
    bold: true,
    lineSpacing: 0.92,
  });
  pipelineArrow(slide, "apb-to-regfile", 660, 473, 735, C.purple);
  addText(slide, "apb-label", "APB bus", { left: 670, top: 445, width: 70, height: 22 }, {
    fontSize: 14,
    bold: true,
    color: C.purple,
    alignment: "center",
  });

  addBox(slide, "dmem", "DMEM / BRAM\n2-port access\n\nPort A: CPU/MMIO\nPort B: DMA", {
    left: 1650,
    top: 348,
    width: 170,
    height: 310,
  }, {
    fill: C.grey,
    line: "#475569",
    fontSize: 19,
    bold: true,
    lineSpacing: 0.92,
  });

  addBox(slide, "uart", "UART\nloader / debug output", { left: 330, top: 808, width: 200, height: 84 }, {
    fill: C.white,
    line: "#475569",
    fontSize: 18,
    bold: true,
  });
  arrow(slide, "uart-out", 530, 834, 90, 24, "#475569");
  addText(slide, "uart-aux", "aux_data_i", { left: 557, top: 862, width: 92, height: 22 }, {
    fontSize: 13,
    color: C.muted,
    alignment: "center",
  });

  addBox(slide, "output", "OUTPUT\nuart_tx_o\nbusy_o\ndone_o\nerror_o", { left: 1738, top: 700, width: 125, height: 180 }, {
    fill: C.white,
    line: C.blue,
    lineWidth: 3,
    fontSize: 17,
    bold: true,
    lineSpacing: 0.9,
  });
}

function addTx(slide) {
  section(slide, "tx-section", "TX expanded datapath: plaintext -> compressed ciphertext", {
    left: 975,
    top: 175,
    width: 825,
    height: 270,
  }, { fill: C.redSoft, line: C.red });

  const y = 265;
  const h = 70;
  const gap = 15;
  let x = 1005;
  smallStage(slide, "tx-dma", "TX DMA\nEngine", "read source DMEM", x, y, 95, h, { fill: C.white, line: C.red });
  x += 95 + gap;
  smallStage(slide, "tx-huff", "Huffman\ncompressor", "freq + codebook + emit", x, y, 135, h, { fill: C.white, line: C.orange });
  x += 135 + gap;
  smallStage(slide, "tx-pack", "Bit packer\n128-bit word", "final + valid bits", x, y, 125, h, { fill: C.white, line: C.orange });
  x += 125 + gap;
  smallStage(slide, "tx-aes", "AES-128-CBC\nencrypt", "XOR IV/Ci-1 + AES rounds", x, y, 145, h, { fill: C.white, line: C.red });
  x += 145 + gap;
  smallStage(slide, "tx-emit", "AES emit\nblock", "write ciphertext", x, y, 115, h, { fill: C.white, line: C.red });

  pipelineArrow(slide, "tx-a0", 1100, 300, 1115, C.red);
  pipelineArrow(slide, "tx-a1", 1250, 300, 1265, C.red);
  pipelineArrow(slide, "tx-a2", 1390, 300, 1405, C.red);
  pipelineArrow(slide, "tx-a3", 1550, 300, 1565, C.red);
  pipelineArrow(slide, "tx-to-dmem", 1695, 300, 1648, C.red);
  addText(slide, "tx-writeback", "ciphertext + metadata writeback", {
    left: 1405,
    top: 358,
    width: 290,
    height: 24,
  }, { fontSize: 14, color: C.red, alignment: "center" });

  addBox(slide, "tx-status", "TX status\nbusy / done / error\nbytes produced", {
    left: 1010,
    top: 360,
    width: 230,
    height: 55,
  }, { fill: C.white, line: C.red, fontSize: 15, bold: true, lineSpacing: 0.8 });
  pipelineArrow(slide, "reg-to-tx", 935, 285, 975, C.purple);
  addText(slide, "reg-to-tx-label", "cfg / start\nstatus poll", {
    left: 925,
    top: 234,
    width: 75,
    height: 45,
  }, { fontSize: 13, color: C.purple, alignment: "center" });
}

function addRx(slide) {
  section(slide, "rx-section", "RX expanded datapath: ciphertext -> recovered plaintext", {
    left: 975,
    top: 505,
    width: 825,
    height: 305,
  }, { fill: C.greenSoft, line: C.green });

  const y = 595;
  const h = 70;
  const gap = 13;
  let x = 1005;
  smallStage(slide, "rx-dma", "RX DMA\nEngine", "read metadata + ciphertext", x, y, 95, h, { fill: C.white, line: C.green });
  x += 95 + gap;
  smallStage(slide, "rx-aes", "AES-128-CBC\ndecrypt", "AES inv rounds + XOR", x, y, 145, h, { fill: C.white, line: C.green });
  x += 145 + gap;
  smallStage(slide, "rx-depack", "Bit depacker\n128-bit word", "remove padding", x, y, 125, h, { fill: C.white, line: C.green });
  x += 125 + gap;
  smallStage(slide, "rx-header", "Header parser\n+ table rebuild", "symbol + code_len", x, y, 145, h, { fill: C.white, line: C.purple });
  x += 145 + gap;
  smallStage(slide, "rx-decode", "Prefix decoder", "match canonical codes", x, y, 120, h, { fill: C.white, line: C.purple });
  x += 120 + gap;
  smallStage(slide, "rx-pack", "Byte / word\npacker", "DMEM plaintext words", x, y, 110, h, { fill: C.white, line: C.green });

  pipelineArrow(slide, "rx-a0", 1100, 630, 1113, C.green);
  pipelineArrow(slide, "rx-a1", 1253, 630, 1266, C.green);
  pipelineArrow(slide, "rx-a2", 1391, 630, 1404, C.green);
  pipelineArrow(slide, "rx-a3", 1549, 630, 1562, C.green);
  pipelineArrow(slide, "rx-a4", 1682, 630, 1695, C.green);

  addBox(slide, "rx-status", "RX status\nbusy / done / error\nbytes recovered", {
    left: 1010,
    top: 700,
    width: 245,
    height: 58,
  }, { fill: C.white, line: C.green, fontSize: 15, bold: true, lineSpacing: 0.8 });

  pipelineArrow(slide, "reg-to-rx", 935, 615, 975, C.purple);
  addText(slide, "reg-to-rx-label", "selected file\nRX start", {
    left: 925,
    top: 560,
    width: 75,
    height: 45,
  }, { fontSize: 13, color: C.purple, alignment: "center" });

  pipelineArrow(slide, "rx-to-dmem", 1718, 630, 1648, C.green);
  addText(slide, "rx-writeback", "plaintext writeback", {
    left: 1505,
    top: 686,
    width: 205,
    height: 24,
  }, { fontSize: 14, color: C.green, alignment: "center" });
}

function addMemoryAndControlFlows(slide) {
  addBox(slide, "accelerator-boundary", "", { left: 955, top: 150, width: 870, height: 685 }, {
    fill: "none",
    line: C.red,
    lineWidth: 4,
  });
  addText(slide, "accelerator-label", "Secure-storage accelerator + DMA memory subsystem", {
    left: 1185,
    top: 154,
    width: 420,
    height: 25,
  }, { fontSize: 14, bold: true, color: C.red, alignment: "center" });

  downArrow(slide, "mem-access-down", 1603, 205, 24, 142, "#475569");
  addText(slide, "mem-access-text", "Memory access", { left: 1506, top: 190, width: 150, height: 24 }, {
    fontSize: 13,
    color: "#475569",
    alignment: "center",
  });

  arrow(slide, "dmem-to-output", 1820, 773, 45, 20, C.blue);
  addText(slide, "output-note", "status + UART", { left: 1710, top: 888, width: 140, height: 22 }, {
    fontSize: 13,
    color: C.muted,
    alignment: "center",
  });

  const legendX = 70;
  const legendY = 940;
  addText(slide, "legend-title", "Legend:", { left: legendX, top: legendY, width: 70, height: 22 }, {
    fontSize: 15,
    bold: true,
  });
  arrow(slide, "legend-data", legendX + 78, legendY + 2, 55, 16, C.blue);
  addText(slide, "legend-data-text", "data path", { left: legendX + 140, top: legendY - 1, width: 90, height: 22 }, {
    fontSize: 14,
  });
  arrow(slide, "legend-ctrl", legendX + 225, legendY + 2, 55, 16, C.purple);
  addText(slide, "legend-ctrl-text", "APB/control", { left: legendX + 287, top: legendY - 1, width: 105, height: 22 }, {
    fontSize: 14,
  });
  arrow(slide, "legend-tx", legendX + 400, legendY + 2, 55, 16, C.red);
  addText(slide, "legend-tx-text", "TX writeback", { left: legendX + 462, top: legendY - 1, width: 115, height: 22 }, {
    fontSize: 14,
  });
  arrow(slide, "legend-rx", legendX + 585, legendY + 2, 55, 16, C.green);
  addText(slide, "legend-rx-text", "RX readback", { left: legendX + 647, top: legendY - 1, width: 115, height: 22 }, {
    fontSize: 14,
  });
}

await fs.mkdir(previewDir, { recursive: true });
const presentation = Presentation.create({ slideSize: { width: W, height: H } });
const slide = presentation.slides.add();
slide.background.fill = C.bg;

addSocOverview(slide);
addTx(slide);
addRx(slide);
addMemoryAndControlFlows(slide);

await writeBlob(pngPath, await presentation.export({ slide, format: "png", scale: 1 }));
await writeBlob(path.join(previewDir, "slide-1.png"), await presentation.export({ slide, format: "png", scale: 1 }));
await fs.writeFile(
  path.join(previewDir, "slide-1.layout.json"),
  await (await slide.export({ format: "layout" })).text(),
);
const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(pptxPath);

console.log(pptxPath);
console.log(pngPath);
