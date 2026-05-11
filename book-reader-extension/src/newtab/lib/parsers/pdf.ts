import type { TocNode } from "./epub";

export interface ParsedPdf {
  title: string;
  author: string;
  totalPages: number;
  /**
   * Embedded PDF outline (a.k.a. bookmarks / chapter tree). `undefined`
   * when the PDF has no outline OR the outline could not be decoded — the
   * TOC panel falls back to a flat page list in that case.
   *
   * spineIndex on each node is the 0-based page index the outline entry
   * targets, or -1 if the destination could not be resolved.
   */
  outline?: TocNode[];
}

/**
 * Shape of a single pdf.js outline item. We only model the fields we read;
 * pdf.js attaches extras (bold/italic/color/url/...) that we ignore.
 */
interface PdfjsOutlineItem {
  title: unknown;
  dest: string | unknown[] | null | undefined;
  items?: PdfjsOutlineItem[];
}

function cleanOutlineLabel(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw.replace(/\s+/g, " ").trim();
}

/**
 * Resolves a pdf.js outline `dest` to a 0-based page index. The destination
 * can be either a name string (needs an extra lookup) or an array whose
 * first element is a page ref. Returns -1 when the destination is missing,
 * external, or unresolvable.
 */
async function resolveOutlineDestination(
  pdf: any,
  dest: string | unknown[] | null | undefined,
): Promise<number> {
  try {
    if (!dest) return -1;
    let destArray: unknown[] | null = null;
    if (typeof dest === "string") {
      const resolved = await pdf.getDestination(dest);
      destArray = Array.isArray(resolved) ? resolved : null;
    } else if (Array.isArray(dest)) {
      destArray = dest;
    }
    if (!destArray || destArray.length === 0) return -1;
    const pageRef = destArray[0];
    if (pageRef == null) return -1;
    const pageIndex = await pdf.getPageIndex(pageRef);
    return typeof pageIndex === "number" && pageIndex >= 0 ? pageIndex : -1;
  } catch {
    return -1;
  }
}

async function convertOutlineItems(
  pdf: any,
  items: PdfjsOutlineItem[],
  idPrefix: string,
): Promise<TocNode[]> {
  const result: TocNode[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const childIdPath = idPrefix === "" ? String(i) : `${idPrefix}.${i}`;
    const label = cleanOutlineLabel(item.title) || `Section ${childIdPath}`;
    const spineIndex = await resolveOutlineDestination(pdf, item.dest ?? null);
    const children = Array.isArray(item.items) && item.items.length > 0
      ? await convertOutlineItems(pdf, item.items, childIdPath)
      : [];
    result.push({
      id: childIdPath,
      label,
      href: "",
      spineIndex,
      fragment: null,
      children,
    });
  }
  return result;
}

async function extractOutline(pdf: any): Promise<TocNode[] | undefined> {
  try {
    const raw = await pdf.getOutline();
    if (!Array.isArray(raw) || raw.length === 0) return undefined;
    const converted = await convertOutlineItems(pdf, raw as PdfjsOutlineItem[], "");
    return converted.length > 0 ? converted : undefined;
  } catch {
    // A malformed outline must never break PDF loading entirely — fall back
    // to the flat page list that TocPanel synthesises when outline is absent.
    return undefined;
  }
}

export async function parsePdf(arrayBuffer: ArrayBuffer): Promise<ParsedPdf> {
  if (typeof pdfjsLib !== "undefined") {
    try {
      const pdf = await pdfjsLib.getDocument({
        data: arrayBuffer.slice(0),
        isEvalSupported: false,
      }).promise;
      const meta = await pdf.getMetadata().catch(() => null);
      const info = meta?.info ?? {};
      const totalPages = pdf.numPages;
      const outline = await extractOutline(pdf);
      pdf.destroy();
      return {
        title: info.Title || "PDF Document",
        author: info.Author || "Unknown Author",
        totalPages,
        outline,
      };
    } catch {
      // Fall through to binary parsing
    }
  }

  const raw = new TextDecoder("latin1").decode(arrayBuffer.slice(0));
  return {
    title: extractField(raw, "Title") || "PDF Document",
    author: extractField(raw, "Author") || "Unknown Author",
    totalPages: extractPageCount(raw),
  };
}

function extractPageCount(raw: string): number {
  const countRegex = /\/Count\s+(\d+)/g;
  let max = 0;
  let m: RegExpExecArray | null;
  while ((m = countRegex.exec(raw)) !== null) {
    const n = parseInt(m[1], 10);
    if (n > max) max = n;
  }
  if (max > 0) return max;

  let count = 0;
  const pageRegex = /\/Type\s*\/Page\b(?!s)/g;
  while (pageRegex.exec(raw) !== null) count++;
  return Math.max(1, count);
}

function extractField(raw: string, field: string): string {
  const re = new RegExp(`\\/${field}\\s*\\(([^)]{0,200})\\)`, "i");
  const m = raw.match(re);
  if (m) return m[1].trim();
  return "";
}

export function revokePdfUrl(url: string) {
  try { URL.revokeObjectURL(url); } catch { /* noop */ }
}
