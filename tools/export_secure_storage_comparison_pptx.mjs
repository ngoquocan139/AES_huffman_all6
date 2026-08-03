import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const artifactToolPath =
  "C:/Users/htk19/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const { Presentation, PresentationFile } = await import(
  pathToFileURL(artifactToolPath).href
);

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

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = path.join(root, "docs", "generated_figures");
const imagePath = path.join(outDir, "secure_storage_ecg_paper_comparison_slide.png");
const pptxPath = path.join(outDir, "secure_storage_ecg_paper_comparison_slide.pptx");
const previewDir = path.join(outDir, "secure_storage_ecg_paper_comparison_slide_preview");

await fs.mkdir(previewDir, { recursive: true });

const presentation = Presentation.create({
  slideSize: { width: 1920, height: 1080 },
});

const slide = presentation.slides.add();
slide.background.fill = "#F7FAFF";

slide.images.add({
  blob: await readImageBlob(imagePath),
  contentType: "image/png",
  alt: "Secure-storage ECG paper comparison slide",
  fit: "contain",
  position: { left: 0, top: 0, width: 1920, height: 1080 },
});

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
