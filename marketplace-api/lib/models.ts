export type WallpaperKind = "web" | "video" | "gradient" | "shader";

export interface MarketplaceWallpaper {
  id: string;
  title: string;
  author: string;
  summary: string | null;
  kind: WallpaperKind;
  sourceValue: string | null;
  downloadURL: string | null;
  thumbnailURL: string | null;
  tags: string[];
}

export interface WallpaperRow {
  id: string;
  title: string;
  author: string;
  summary: string | null;
  kind: string;
  source_value: string | null;
  download_url: string | null;
  thumbnail_url: string | null;
  tags: unknown;
}

const VALID_KINDS: WallpaperKind[] = ["web", "video", "gradient", "shader"];

export function normalizeKind(raw: FormDataEntryValue | null): WallpaperKind | null {
  const value = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  return VALID_KINDS.includes(value as WallpaperKind) ? (value as WallpaperKind) : null;
}

export function sanitizeText(raw: FormDataEntryValue | null): string | null {
  if (typeof raw !== "string") {
    return null;
  }

  const value = raw.trim();
  return value.length > 0 ? value : null;
}

export function parseTags(raw: FormDataEntryValue | null): string[] {
  if (typeof raw !== "string") {
    return [];
  }

  return raw
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
}

function normalizeTags(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.filter((item): item is string => typeof item === "string");
  }

  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw);
      return normalizeTags(parsed);
    } catch {
      return [];
    }
  }

  return [];
}

function normalizeRowKind(rawKind: string): WallpaperKind {
  const lower = rawKind.toLowerCase();
  if (VALID_KINDS.includes(lower as WallpaperKind)) {
    return lower as WallpaperKind;
  }
  return "web";
}

export function mapRowToWallpaper(row: WallpaperRow): MarketplaceWallpaper {
  return {
    id: row.id,
    title: row.title,
    author: row.author,
    summary: row.summary,
    kind: normalizeRowKind(row.kind),
    sourceValue: row.source_value,
    downloadURL: row.download_url,
    thumbnailURL: row.thumbnail_url,
    tags: normalizeTags(row.tags)
  };
}
