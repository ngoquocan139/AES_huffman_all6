import fs from "node:fs/promises";
import {
  Presentation,
  PresentationFile,
} from "file:///C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const OUT_DIR =
  "H:/Academic/senior_project/DATN/work/luc/AES_huffman_all6/docs/generated_figures";
const FINAL = `${OUT_DIR}/huffman_repetition_decode_slide.pptx`;
const PREVIEW = `${OUT_DIR}/huffman_repetition_decode_slide.png`;
const LAYOUT = `${OUT_DIR}/huffman_repetition_decode_slide.layout.json`;

const W = 1280;
const H = 720;
const BLUE = "#0B3292";
const BLUE2 = "#123FA8";
const LIGHT = "#EAF2FF";
const TEXT = "#111827";
const MUTED = "#4B5563";
const LINE = "#B8C7E6";
const ORANGE = "#F28C28";
const GREEN = "#168A5B";
const PURPLE = "#6D3AD6";

await fs.mkdir(OUT_DIR, { recursive: true });

async function writeBlob(path, blob) {
  await fs.writeFile(path, new Uint8Array(await blob.arrayBuffer()));
}

const presentation = Presentation.create({
  slideSize: { width: W, height: H },
});

const slide = presentation.slides.add();
slide.background.fill = "white";

function shape(geometry, x, y, w, h, fill, line = "none", width = 0, name) {
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
    fontSize: opts.size ?? 22,
    bold: opts.bold ?? false,
    color: opts.color ?? TEXT,
    alignment: opts.align ?? "left",
  };
  return box;
}

function panel(x, y, w, h, title, color = BLUE) {
  shape("roundRect", x, y, w, h, "white", LINE, 1.4);
  shape("rect", x, y, w, 42, color, color, 0);
  text(title, x + 18, y + 9, w - 36, 24, {
    size: 20,
    bold: true,
    color: "white",
  });
}

function field(x, y, w, h, label, fill, line, sub = undefined) {
  shape("roundRect", x, y, w, h, fill, line, 1.5);
  text(label, x + 8, y + 10, w - 16, sub ? 22 : 32, {
    size: sub ? 18 : 21,
    bold: true,
    color: TEXT,
    align: "center",
  });
  if (sub) {
    text(sub, x + 8, y + 38, w - 16, 20, {
      size: 15,
      color: MUTED,
      align: "center",
    });
  }
}

function token(x, y, label, color) {
  shape("roundRect", x, y, 58, 42, color, color, 1);
  text(label, x, y + 8, 58, 22, {
    size: 21,
    bold: true,
    color: "white",
    align: "center",
  });
}

function arrow(x, y, w = 50, h = 22) {
  shape("rightArrow", x, y, w, h, BLUE2, BLUE2, 0);
}

// Top banner
shape("rect", 0, 0, 390, 92, BLUE, BLUE, 0);
text("3. System design", 28, 24, 340, 42, {
  size: 34,
  bold: true,
  color: "white",
});
text("How repeated symbols are recovered in Huffman decoding", 435, 28, 780, 40, {
  size: 29,
  bold: true,
  color: BLUE,
  align: "center",
});

// Core strip: header vs payload
panel(50, 120, 1180, 190, "Compressed block contains a codebook header followed by payload bits");

field(80, 182, 110, 66, "mode", "#DBEAFE", "#2563EB", "2b");
field(190, 182, 150, 66, "block_size", "#DCFCE7", "#16A34A", "7 bytes");
field(340, 182, 165, 66, "symbol_count", "#FEF3C7", "#D97706", "3 entries");
field(505, 182, 150, 66, "E : len 1", "#F3E8FF", PURPLE);
field(655, 182, 150, 66, "D : len 2", "#F3E8FF", PURPLE);
field(805, 182, 150, 66, "L : len 2", "#F3E8FF", PURPLE);
field(955, 182, 240, 66, "payload bits", "#FFEDD5", "#EA580C", "0001010110");

text("Header stores each symbol once. It does not store how many times each symbol repeats.", 82, 262, 720, 28, {
  size: 18,
  color: MUTED,
});
text("Repetitions are represented by repeated codewords in the payload.", 822, 262, 370, 28, {
  size: 18,
  color: MUTED,
  align: "center",
});

// Decoder reconstruction
panel(50, 340, 360, 290, "1. RX rebuilds the canonical table", GREEN);
text("From header entries:", 78, 395, 280, 25, {
  size: 20,
  bold: true,
  color: TEXT,
});
text("E len=1\nD len=2\nL len=2", 95, 428, 140, 95, {
  size: 22,
  color: TEXT,
});
arrow(214, 452, 48, 26);
text("Canonical table:", 78, 538, 280, 24, {
  size: 20,
  bold: true,
  color: TEXT,
});
text("E = 0\nD = 10\nL = 11", 95, 568, 160, 80, {
  size: 22,
  color: TEXT,
});

// Payload scan
panel(460, 340, 385, 290, "2. Payload is decoded sequentially", ORANGE);
text("Payload bits:", 488, 395, 180, 24, {
  size: 20,
  bold: true,
});
text("0 0 0 10 10 11 0", 488, 432, 310, 34, {
  size: 27,
  bold: true,
  color: TEXT,
});
text("Each matched codeword emits one byte:", 488, 490, 330, 24, {
  size: 19,
  color: MUTED,
});
token(500, 532, "E", BLUE);
token(568, 532, "E", BLUE);
token(636, 532, "E", BLUE);
token(704, 532, "D", PURPLE);
token(772, 532, "D", PURPLE);
token(568, 585, "L", GREEN);
token(636, 585, "E", BLUE);

// Stop condition
panel(895, 340, 335, 290, "3. Stop after block_size outputs", BLUE);
text("The decoder does not need per-symbol repetition counts.", 923, 398, 280, 58, {
  size: 21,
  bold: true,
  color: TEXT,
});
text("It counts recovered bytes:", 923, 478, 255, 28, {
  size: 20,
  color: MUTED,
});
text("E E E D D L E", 923, 516, 250, 34, {
  size: 27,
  bold: true,
  color: TEXT,
});
text("output_count = 7\nblock_size = 7\nDONE", 923, 565, 250, 78, {
  size: 22,
  bold: true,
  color: BLUE,
});

// Footer takeaway
shape("rect", 0, 678, W, 6, BLUE, BLUE, 0);
text("Key idea: the header is the dictionary; repeated occurrences are encoded as repeated codewords in the payload.", 66, 646, 1120, 28, {
  size: 21,
  bold: true,
  color: BLUE,
  align: "center",
});

const slidePng = await presentation.export({ slide, format: "png", scale: 1 });
await writeBlob(PREVIEW, slidePng);
const layout = await slide.export({ format: "layout" });
await fs.writeFile(LAYOUT, await layout.text());
const pptx = await PresentationFile.exportPptx(presentation);
await pptx.save(FINAL);

console.log(FINAL);
console.log(PREVIEW);
