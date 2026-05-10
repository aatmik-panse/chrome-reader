import { parseEpub } from "./parsers/epub";
import { BookMetadata, getBook, getThumbnail, saveThumbnail } from "./storage";

const TARGET_WIDTH_PX = 256;
const TARGET_HEIGHT_PX = 340;
const JPEG_QUALITY = 0.85;

/**
 * Render a thumbnail Blob for the given book, or return null when the format
 * has no natural cover (TXT) and synthesizing one isn't worth the bytes.
 *
 * The function is best-effort: any failure (corrupt cover, render error) is
 * swallowed and reported as null so the caller can fall back to a placeholder.
 */
export async function generateThumbnail(
  meta: BookMetadata,
  data: ArrayBuffer,
): Promise<Blob | null> {
  try {
    if (meta.format === "pdf") return await generatePdfThumbnail(data);
    if (meta.format === "epub") return await generateEpubThumbnail(data);
    return null;
  } catch {
    return null;
  }
}

async function generatePdfThumbnail(data: ArrayBuffer): Promise<Blob | null> {
  if (typeof pdfjsLib === "undefined") return null;
  if (typeof chrome !== "undefined" && chrome.runtime) {
    pdfjsLib.GlobalWorkerOptions.workerSrc = chrome.runtime.getURL("pdf.worker.min.js");
  }
  const pdf = await pdfjsLib.getDocument({ data: data.slice(0), isEvalSupported: false }).promise;
  try {
    const page = await pdf.getPage(1);
    const baseViewport = page.getViewport({ scale: 1 });
    const scale = Math.min(
      TARGET_WIDTH_PX / baseViewport.width,
      TARGET_HEIGHT_PX / baseViewport.height,
    );
    const viewport = page.getViewport({ scale });
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(viewport.width);
    canvas.height = Math.ceil(viewport.height);
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    await page.render({ canvasContext: ctx, viewport }).promise;
    return await canvasToJpeg(canvas);
  } finally {
    try { await pdf.destroy(); } catch { /* ignore */ }
  }
}

async function generateEpubThumbnail(data: ArrayBuffer): Promise<Blob | null> {
  // Reuse the full epub parser so blob URLs (cover included) are produced via
  // the same path the reader uses. We only need the cover — discard the rest.
  const parsed = await parseEpub(data);
  try {
    const coverUrl = await parsed.book.coverUrl();
    if (!coverUrl) return null;
    const sourceBlob = await fetch(coverUrl).then((response) => response.blob());
    return await downscaleImageBlob(sourceBlob);
  } finally {
    parsed.dispose();
  }
}

async function downscaleImageBlob(blob: Blob): Promise<Blob | null> {
  const objectUrl = URL.createObjectURL(blob);
  try {
    const image = await loadImageElement(objectUrl);
    const scale = Math.min(
      TARGET_WIDTH_PX / image.naturalWidth,
      TARGET_HEIGHT_PX / image.naturalHeight,
      1,
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    return await canvasToJpeg(canvas);
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

function loadImageElement(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("Cover image failed to decode"));
    image.src = src;
  });
}

function canvasToJpeg(canvas: HTMLCanvasElement): Promise<Blob | null> {
  return new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob), "image/jpeg", JPEG_QUALITY);
  });
}

/**
 * Make sure a thumbnail exists for the given book; generate and store one if
 * not. Returns the cached or freshly-generated blob, or null when generation
 * is impossible (TXT, errors).
 *
 * Callers should treat null as "use a placeholder" — never as an error.
 */
export async function ensureThumbnail(meta: BookMetadata): Promise<Blob | null> {
  const cached = await getThumbnail(meta.hash);
  if (cached) return cached;
  const data = await getBook(meta.hash);
  if (!data) return null;
  const generated = await generateThumbnail(meta, data);
  if (generated) await saveThumbnail(meta.hash, generated);
  return generated;
}
