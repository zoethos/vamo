#!/usr/bin/env node
//
// Build the architecture document exports from their canonical sources.
//
//   docs/architecture/DATA_ACQUISITION_STRATEGY.md   ->  Vamo_Data_Acquisition_Strategy.docx
//   docs/architecture/DATA_ACQUISITION_FUNNEL.svg    ->  DATA_ACQUISITION_FUNNEL.png
//
// The Markdown and the SVG are the sources of truth. The .docx and .png are
// disposable exports for people who want something to hand round; never edit
// them directly, because the next run overwrites them.
//
// Dependencies are deliberately NOT declared in a package.json. This script
// runs by hand, a few times a year, when an architecture document changes.
// Adding a second npm package to the repo would buy a lockfile, a dependabot
// surface and CI weight for no benefit at that cadence.
//
//   node >= 20
//   npm install --no-save docx @resvg/resvg-js
//   node tool/docs/build_architecture_docx.mjs
//
// The Markdown subset understood here is exactly what the source documents
// use: ATX headings, paragraphs, `-` bullets, ordered lists, pipe tables,
// blockquotes, images, fenced code, and inline `code` / **bold** / *italic*.
// Anything else raises rather than being silently dropped -- these documents
// state load-bearing rules, so quiet content loss is the failure that matters.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, BorderStyle, ImageRun,
  PageOrientation, ShadingType,
} = await import("docx");
const { Resvg } = await import("@resvg/resvg-js");

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ARCH = join(REPO, "docs", "architecture");

const DOCS = [{
  markdown: join(ARCH, "DATA_ACQUISITION_STRATEGY.md"),
  svg: join(ARCH, "DATA_ACQUISITION_FUNNEL.svg"),
  png: join(ARCH, "DATA_ACQUISITION_FUNNEL.png"),
  docx: join(ARCH, "Vamo_Data_Acquisition_Strategy.docx"),
  title: "Place Data Acquisition Strategy",
  description: "How Vamo builds an owned place graph, and where Confluendo fits.",
}];

const ACCENT = "1D5334";
const MUTED = "5B6472";
const DANGER = "B3261E";
const BODY = 21; // half-points

// ---------------------------------------------------------------- markdown

// Split a line into inline runs. Handles **bold**, *italic* and `code`.
function inlineRuns(text, base = {}) {
  const runs = [];
  const pattern = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g;
  let last = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > last) {
      runs.push({ text: text.slice(last, match.index), ...base });
    }
    const token = match[0];
    if (token.startsWith("**")) {
      runs.push({ text: token.slice(2, -2), ...base, bold: true });
    } else if (token.startsWith("`")) {
      runs.push({ text: token.slice(1, -1), ...base, bold: true });
    } else {
      runs.push({ text: token.slice(1, -1), ...base, italics: true });
    }
    last = match.index + token.length;
  }
  if (last < text.length) runs.push({ text: text.slice(last), ...base });
  return runs.length > 0 ? runs : [{ text, ...base }];
}

function parseMarkdown(source) {
  const lines = source.split(/\r?\n/);
  const blocks = [];
  let i = 0;

  const isTableRow = (line) => /^\s*\|.*\|\s*$/.test(line);
  const cells = (line) =>
    line.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());

  while (i < lines.length) {
    const line = lines[i];

    if (line.trim() === "") { i++; continue; }

    if (line.startsWith("```")) {
      const body = [];
      i++;
      while (i < lines.length && !lines[i].startsWith("```")) body.push(lines[i++]);
      if (i >= lines.length) throw new Error("unterminated fenced code block");
      i++;
      blocks.push({ kind: "code", lines: body });
      continue;
    }

    const heading = /^(#{1,4})\s+(.*)$/.exec(line);
    if (heading) {
      blocks.push({ kind: "heading", level: heading[1].length, text: heading[2].trim() });
      i++;
      continue;
    }

    const image = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/.exec(line);
    if (image) {
      blocks.push({ kind: "image", alt: image[1], src: image[2] });
      i++;
      continue;
    }

    if (isTableRow(line)) {
      const rows = [];
      while (i < lines.length && isTableRow(lines[i])) rows.push(cells(lines[i++]));
      // Drop the --- separator row if present.
      const body = rows.filter((r) => !r.every((c) => /^:?-{2,}:?$/.test(c) || c === ""));
      blocks.push({ kind: "table", header: rows[0], rows: body.slice(1), headerIsData: body[0] !== rows[0] ? false : true });
      continue;
    }

    if (/^>\s?/.test(line)) {
      const body = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) body.push(lines[i++].replace(/^>\s?/, ""));
      blocks.push({ kind: "quote", text: body.join(" ").trim() });
      continue;
    }

    if (/^[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^[-*]\s+/.test(lines[i])) {
        let text = lines[i++].replace(/^[-*]\s+/, "");
        while (i < lines.length && /^\s{2,}\S/.test(lines[i])) text += " " + lines[i++].trim();
        items.push(text);
      }
      blocks.push({ kind: "bullets", items });
      continue;
    }

    if (/^\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\d+\.\s+/.test(lines[i])) {
        let text = lines[i++].replace(/^\d+\.\s+/, "");
        while (i < lines.length && /^\s{2,}\S/.test(lines[i])) text += " " + lines[i++].trim();
        items.push(text);
      }
      blocks.push({ kind: "ordered", items });
      continue;
    }

    const body = [];
    while (i < lines.length && lines[i].trim() !== "" &&
      !/^(#{1,4}\s|[-*]\s|\d+\.\s|>|!\[|```)/.test(lines[i]) && !isTableRow(lines[i])) {
      body.push(lines[i++].trim());
    }
    if (body.length === 0) {
      throw new Error(`unrecognised markdown at line ${i + 1}: ${JSON.stringify(line)}`);
    }
    blocks.push({ kind: "paragraph", text: body.join(" ") });
  }

  return blocks;
}

// ---------------------------------------------------------------- docx

const runs = (specs) => specs.map((s) =>
  new TextRun({ text: s.text, size: s.size ?? BODY, bold: s.bold, italics: s.italics, color: s.color }));

const heading = (level, text) => {
  const sizes = { 1: 30, 2: 24, 3: 22, 4: 21 };
  const colors = { 1: "12171F", 2: ACCENT, 3: ACCENT, 4: MUTED };
  return new Paragraph({
    heading: level === 1 ? HeadingLevel.HEADING_1
      : level === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_3,
    spacing: { before: level === 1 ? 340 : 240, after: level === 1 ? 160 : 120 },
    children: [new TextRun({ text, size: sizes[level], bold: true, color: colors[level] })],
  });
};

const tableCell = (text, opts = {}) =>
  new TableCell({
    width: { size: opts.width, type: WidthType.PERCENTAGE },
    margins: { top: 90, bottom: 90, left: 130, right: 130 },
    shading: opts.head ? { type: ShadingType.CLEAR, fill: "EDF1F5" } : undefined,
    children: [new Paragraph({
      children: runs(inlineRuns(text, { size: 19, bold: opts.head || undefined })),
    })],
  });

function blockToDocx(block, ctx) {
  switch (block.kind) {
    case "heading":
      // The document's H1 is the cover title; render it larger and skip the rule styling.
      if (block.level === 1 && !ctx.sawTitle) {
        ctx.sawTitle = true;
        return [new Paragraph({
          spacing: { after: 60 },
          children: [new TextRun({ text: block.text, size: 42, bold: true, color: "12171F" })],
        })];
      }
      return [heading(block.level, block.text)];

    case "paragraph":
      return [new Paragraph({
        spacing: { after: 140, line: 276 },
        children: runs(inlineRuns(block.text)),
      })];

    case "quote":
      return [new Paragraph({
        spacing: { before: 140, after: 160, line: 276 },
        indent: { left: 420 },
        border: { left: { style: BorderStyle.SINGLE, size: 18, color: ACCENT, space: 12 } },
        children: runs(inlineRuns(block.text, { italics: true, color: "1D2A35" })),
      })];

    case "bullets":
      return block.items.map((item) => new Paragraph({
        bullet: { level: 0 },
        spacing: { after: 90, line: 276 },
        children: runs(inlineRuns(item)),
      }));

    case "ordered":
      return block.items.map((item, index) => new Paragraph({
        spacing: { after: 100, line: 276 },
        indent: { left: 420, hanging: 300 },
        children: [
          new TextRun({ text: `${index + 1}.  `, size: BODY, bold: true, color: DANGER }),
          ...runs(inlineRuns(item)),
        ],
      }));

    case "code":
      return block.lines.map((line) => new Paragraph({
        spacing: { after: 0, line: 240 },
        indent: { left: 300 },
        children: [new TextRun({ text: line, size: 18, color: "1D2A35" })],
      }));

    case "table": {
      const width = Math.floor(100 / block.header.length);
      return [new Table({
        width: { size: 100, type: WidthType.PERCENTAGE },
        rows: [
          new TableRow({
            tableHeader: true,
            children: block.header.map((c) => tableCell(c, { head: true, width })),
          }),
          ...block.rows.map((row) => new TableRow({
            children: row.map((c) => tableCell(c, { width })),
          })),
        ],
      }), new Paragraph({ spacing: { after: 120 }, children: [] })];
    }

    case "image":
      // Handled by the section splitter -- images get their own landscape page.
      throw new Error("image block should be handled by buildSections");

    default:
      throw new Error(`unhandled block kind: ${block.kind}`);
  }
}

// Images go on their own landscape page so diagram text stays legible in print.
function buildSections(blocks, pngBytes) {
  const portrait = { page: { margin: { top: 1000, bottom: 1000, left: 1000, right: 1000 } } };
  const landscape = {
    page: {
      size: { orientation: PageOrientation.LANDSCAPE },
      margin: { top: 700, bottom: 700, left: 700, right: 700 },
    },
  };

  const sections = [];
  const ctx = { sawTitle: false };
  let buffer = [];
  let pendingHeading = null;

  const flush = () => {
    if (buffer.length > 0) {
      sections.push({ properties: portrait, children: buffer });
      buffer = [];
    }
  };

  for (const block of blocks) {
    if (block.kind === "image") {
      // Move the immediately preceding heading onto the landscape page with it.
      const children = [];
      if (pendingHeading) {
        buffer.pop();
        children.push(pendingHeading);
      }
      flush();
      children.push(new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [new ImageRun({
          type: "png",
          data: pngBytes,
          transformation: { width: 980, height: 613 },
        })],
      }));
      sections.push({ properties: landscape, children });
      pendingHeading = null;
      continue;
    }

    const rendered = blockToDocx(block, ctx);
    buffer.push(...rendered);
    pendingHeading = block.kind === "heading" && rendered.length === 1 ? rendered[0] : null;
  }

  flush();
  return sections;
}

// ---------------------------------------------------------------- build

function renderPng(svgPath, pngPath) {
  const svg = readFileSync(svgPath, "utf8");
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: 2880 },
    font: { loadSystemFonts: true },
  });
  const png = resvg.render().asPng();
  writeFileSync(pngPath, png);
  return png;
}

for (const spec of DOCS) {
  const png = renderPng(spec.svg, spec.png);
  const blocks = parseMarkdown(readFileSync(spec.markdown, "utf8"));

  const doc = new Document({
    creator: "Vamo",
    title: spec.title,
    description: spec.description,
    styles: { default: { document: { run: { font: "Calibri", size: BODY } } } },
    sections: buildSections(blocks, png),
  });

  const buffer = await Packer.toBuffer(doc);
  writeFileSync(spec.docx, buffer);

  console.log(
    `built ${spec.docx.replace(REPO, ".")} ` +
    `(${blocks.length} blocks, ${buffer.length} bytes) and ` +
    `${spec.png.replace(REPO, ".")} (${png.length} bytes)`,
  );
}
