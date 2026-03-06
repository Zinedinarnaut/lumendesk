export type WallpaperKind = "web" | "video" | "gradient" | "shader";
export type MarketplacePreviewKind = "image" | "video" | "web" | "none";
export type MarketplaceSort = "latest" | "popular" | "featured";

export interface MarketplaceWallpaper {
  id: string;
  title: string;
  author: string;
  summary: string | null;
  kind: WallpaperKind;
  sourceValue: string | null;
  downloadURL: string | null;
  previewURL: string | null;
  previewKind: MarketplacePreviewKind;
  accentColor: string | null;
  thumbnailURL: string | null;
  featured: boolean;
  installs: number;
  downloads: number;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

export interface WallpaperRow {
  id: string;
  title: string;
  author: string;
  summary: string | null;
  kind: string;
  source_value: string | null;
  download_url: string | null;
  preview_url: string | null;
  preview_kind: string | null;
  accent_color: string | null;
  thumbnail_url: string | null;
  featured: boolean | null;
  installs: number | null;
  downloads: number | null;
  status: string | null;
  tags: unknown;
  created_at: string;
  updated_at: string;
}

const VALID_KINDS: WallpaperKind[] = ["web", "video", "gradient", "shader"];
const VALID_PREVIEW_KINDS: MarketplacePreviewKind[] = ["image", "video", "web", "none"];
const VALID_SORTS: MarketplaceSort[] = ["latest", "popular", "featured"];
const HEX_COLOR_PATTERN = /^#?[0-9a-fA-F]{6}$/;

export function normalizeKind(raw: FormDataEntryValue | null): WallpaperKind | null {
  const value = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  return VALID_KINDS.includes(value as WallpaperKind) ? (value as WallpaperKind) : null;
}

export function normalizeSort(raw: string | null): MarketplaceSort {
  const value = (raw ?? "").trim().toLowerCase();
  return VALID_SORTS.includes(value as MarketplaceSort) ? (value as MarketplaceSort) : "featured";
}

export function normalizePreviewKind(raw: FormDataEntryValue | null): MarketplacePreviewKind {
  const value = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  return VALID_PREVIEW_KINDS.includes(value as MarketplacePreviewKind)
    ? (value as MarketplacePreviewKind)
    : "image";
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

  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return [];
  }

  if (trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed
          .filter((item): item is string => typeof item === "string")
          .map((item) => item.trim())
          .filter((item) => item.length > 0);
      }
    } catch {
      // Fall through to CSV parser.
    }
  }

  return trimmed
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
}

export function parseBoolean(raw: FormDataEntryValue | null): boolean | null {
  if (typeof raw !== "string") {
    return null;
  }

  const value = raw.trim().toLowerCase();
  if (value === "true" || value === "1" || value === "yes") {
    return true;
  }
  if (value === "false" || value === "0" || value === "no") {
    return false;
  }
  return null;
}

export function sanitizeHexColor(raw: FormDataEntryValue | null): string | null {
  const value = sanitizeText(raw);
  if (!value || !HEX_COLOR_PATTERN.test(value)) {
    return null;
  }

  return value.startsWith("#") ? value.toUpperCase() : `#${value.toUpperCase()}`;
}

export function sanitizeURL(raw: FormDataEntryValue | null): string | null {
  const value = sanitizeText(raw);
  if (!value) {
    return null;
  }

  try {
    const parsed = new URL(value);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
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

function normalizeRowPreviewKind(rawKind: string | null): MarketplacePreviewKind {
  if (!rawKind) {
    return "image";
  }
  const lower = rawKind.toLowerCase();
  if (VALID_PREVIEW_KINDS.includes(lower as MarketplacePreviewKind)) {
    return lower as MarketplacePreviewKind;
  }
  return "image";
}

export function mapRowToWallpaper(row: WallpaperRow): MarketplaceWallpaper {
  const previewURL = row.preview_url ?? row.thumbnail_url ?? null;

  return {
    id: row.id,
    title: row.title,
    author: row.author,
    summary: row.summary,
    kind: normalizeRowKind(row.kind),
    sourceValue: row.source_value,
    downloadURL: row.download_url,
    previewURL,
    previewKind: normalizeRowPreviewKind(row.preview_kind),
    accentColor: row.accent_color ?? null,
    thumbnailURL: row.thumbnail_url ?? previewURL,
    featured: Boolean(row.featured),
    installs: Number(row.installs ?? 0),
    downloads: Number(row.downloads ?? 0),
    tags: normalizeTags(row.tags),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}
