import { neon } from "@neondatabase/serverless";
import type { MarketplacePreviewKind, MarketplaceSort, WallpaperKind, WallpaperRow } from "./models";

let schemaReady = false;
let queryClient: ReturnType<typeof neon> | null = null;

export type WallpaperStatus = "draft" | "published" | "hidden";

export interface InsertWallpaperInput {
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
  tags: string[];
  status: WallpaperStatus;
  createdBy: string | null;
}

export interface MarketplaceListFilters {
  q?: string | null;
  kind?: WallpaperKind | null;
  tag?: string | null;
  featured?: boolean | null;
  sort: MarketplaceSort;
  page: number;
  perPage: number;
  includeHidden?: boolean;
}

export interface MarketplaceListResult {
  rows: WallpaperRow[];
  total: number;
  page: number;
  perPage: number;
}

function query() {
  if (queryClient) {
    return queryClient;
  }

  const connectionString = process.env.POSTGRES_URL;
  if (!connectionString || connectionString.trim().length === 0) {
    throw new Error("POSTGRES_URL is not configured.");
  }

  queryClient = neon(connectionString);
  return queryClient;
}

function normalizePagination(page: number, perPage: number): { page: number; perPage: number; offset: number } {
  const safePerPage = Math.min(Math.max(Math.floor(perPage || 24), 1), 100);
  const safePage = Math.max(Math.floor(page || 1), 1);
  const offset = (safePage - 1) * safePerPage;

  return { page: safePage, perPage: safePerPage, offset };
}

function normalizeSearch(raw: string | null | undefined): string | null {
  const value = (raw ?? "").trim();
  return value.length > 0 ? `%${value}%` : null;
}

export async function ensureSchema(): Promise<void> {
  if (schemaReady) {
    return;
  }

  const sql = query();

  await sql`
    CREATE TABLE IF NOT EXISTS wallpapers (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT NOT NULL,
      summary TEXT,
      kind TEXT NOT NULL CHECK (kind IN ('web', 'video', 'gradient', 'shader')),
      source_value TEXT,
      download_url TEXT,
      preview_url TEXT,
      preview_kind TEXT NOT NULL DEFAULT 'image' CHECK (preview_kind IN ('image', 'video', 'web', 'none')),
      accent_color TEXT,
      thumbnail_url TEXT,
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,
      featured BOOLEAN NOT NULL DEFAULT FALSE,
      installs INTEGER NOT NULL DEFAULT 0,
      downloads INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('draft', 'published', 'hidden')),
      created_by TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `;

  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS preview_url TEXT;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS preview_kind TEXT;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS accent_color TEXT;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS featured BOOLEAN;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS installs INTEGER;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS downloads INTEGER;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS status TEXT;`;
  await sql`ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;`;

  await sql`UPDATE wallpapers SET featured = COALESCE(featured, FALSE);`;
  await sql`UPDATE wallpapers SET installs = COALESCE(installs, 0);`;
  await sql`UPDATE wallpapers SET downloads = COALESCE(downloads, 0);`;
  await sql`UPDATE wallpapers SET status = COALESCE(status, 'published');`;
  await sql`UPDATE wallpapers SET updated_at = COALESCE(updated_at, created_at, NOW());`;
  await sql`UPDATE wallpapers SET preview_kind = COALESCE(preview_kind, 'image');`;
  await sql`UPDATE wallpapers SET preview_url = COALESCE(preview_url, thumbnail_url);`;

  await sql`
    CREATE INDEX IF NOT EXISTS wallpapers_created_at_idx
      ON wallpapers (created_at DESC);
  `;

  await sql`
    CREATE INDEX IF NOT EXISTS wallpapers_featured_created_idx
      ON wallpapers (featured DESC, created_at DESC);
  `;

  await sql`
    CREATE INDEX IF NOT EXISTS wallpapers_kind_created_idx
      ON wallpapers (kind, created_at DESC);
  `;

  await sql`
    CREATE INDEX IF NOT EXISTS wallpapers_installs_idx
      ON wallpapers (installs DESC, created_at DESC);
  `;

  schemaReady = true;
}

function baseSelect() {
  return `
    SELECT
      id,
      title,
      author,
      summary,
      kind,
      source_value,
      download_url,
      preview_url,
      preview_kind,
      accent_color,
      thumbnail_url,
      featured,
      installs,
      downloads,
      status,
      tags,
      created_at,
      updated_at
    FROM wallpapers
  `;
}

function whereClause(
  searchLike: string | null,
  kind: WallpaperKind | null | undefined,
  tag: string | null | undefined,
  featured: boolean | null | undefined,
  includeHidden: boolean
): { clause: string; values: unknown[] } {
  const conditions: string[] = [];
  const values: unknown[] = [];

  if (!includeHidden) {
    conditions.push(`status = 'published'`);
  }

  if (searchLike) {
    values.push(searchLike);
    const idx = values.length;
    conditions.push(`(title ILIKE $${idx} OR author ILIKE $${idx} OR summary ILIKE $${idx})`);
  }

  if (kind) {
    values.push(kind);
    conditions.push(`kind = $${values.length}`);
  }

  if (tag) {
    values.push(tag);
    conditions.push(`tags ? $${values.length}`);
  }

  if (typeof featured === "boolean") {
    values.push(featured);
    conditions.push(`featured = $${values.length}`);
  }

  const clause = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
  return { clause, values };
}

function orderBy(sort: MarketplaceSort): string {
  switch (sort) {
    case "latest":
      return "ORDER BY created_at DESC";
    case "popular":
      return "ORDER BY installs DESC, downloads DESC, created_at DESC";
    case "featured":
    default:
      return "ORDER BY featured DESC, installs DESC, created_at DESC";
  }
}

async function executeQuery<T>(text: string, values: unknown[]): Promise<T[]> {
  const sql = query();
  const result = (await sql.query(text, values)) as { rows: T[] };
  return result.rows;
}

export async function listMarketplaceWallpapers(filters: MarketplaceListFilters): Promise<MarketplaceListResult> {
  const { page, perPage, offset } = normalizePagination(filters.page, filters.perPage);
  const searchLike = normalizeSearch(filters.q);
  const includeHidden = Boolean(filters.includeHidden);

  const where = whereClause(searchLike, filters.kind, filters.tag, filters.featured, includeHidden);

  const rowsQuery = `
    ${baseSelect()}
    ${where.clause}
    ${orderBy(filters.sort)}
    LIMIT $${where.values.length + 1}
    OFFSET $${where.values.length + 2};
  `;

  const countQuery = `
    SELECT COUNT(*)::INT AS total
    FROM wallpapers
    ${where.clause};
  `;

  const rows = await executeQuery<WallpaperRow>(rowsQuery, [...where.values, perPage, offset]);
  const totalRows = await executeQuery<{ total: number }>(countQuery, where.values);
  const total = Number(totalRows[0]?.total ?? 0);

  return {
    rows,
    total,
    page,
    perPage
  };
}

export async function listWallpapers(limit: number): Promise<WallpaperRow[]> {
  const result = await listMarketplaceWallpapers({
    sort: "featured",
    page: 1,
    perPage: Math.min(Math.max(limit, 1), 500)
  });
  return result.rows;
}

export async function getWallpaperByID(id: string): Promise<WallpaperRow | null> {
  const sql = query();
  const rows = (await sql`
    SELECT
      id,
      title,
      author,
      summary,
      kind,
      source_value,
      download_url,
      preview_url,
      preview_kind,
      accent_color,
      thumbnail_url,
      featured,
      installs,
      downloads,
      status,
      tags,
      created_at,
      updated_at
    FROM wallpapers
    WHERE id = ${id}
    LIMIT 1;
  `) as WallpaperRow[];

  return rows[0] ?? null;
}

export async function incrementWallpaperInstalls(id: string): Promise<WallpaperRow | null> {
  const sql = query();
  const rows = (await sql`
    UPDATE wallpapers
    SET installs = COALESCE(installs, 0) + 1,
        updated_at = NOW()
    WHERE id = ${id}
      AND COALESCE(status, 'published') = 'published'
    RETURNING
      id,
      title,
      author,
      summary,
      kind,
      source_value,
      download_url,
      preview_url,
      preview_kind,
      accent_color,
      thumbnail_url,
      featured,
      installs,
      downloads,
      status,
      tags,
      created_at,
      updated_at;
  `) as WallpaperRow[];

  return rows[0] ?? null;
}

export async function insertWallpaper(input: InsertWallpaperInput): Promise<WallpaperRow> {
  const id = crypto.randomUUID();
  const sql = query();

  const rows = (await sql`
    INSERT INTO wallpapers (
      id,
      title,
      author,
      summary,
      kind,
      source_value,
      download_url,
      preview_url,
      preview_kind,
      accent_color,
      thumbnail_url,
      featured,
      tags,
      installs,
      downloads,
      status,
      created_by,
      updated_at
    ) VALUES (
      ${id},
      ${input.title},
      ${input.author},
      ${input.summary},
      ${input.kind},
      ${input.sourceValue},
      ${input.downloadURL},
      ${input.previewURL},
      ${input.previewKind},
      ${input.accentColor},
      ${input.thumbnailURL},
      ${input.featured},
      ${JSON.stringify(input.tags)},
      0,
      0,
      ${input.status},
      ${input.createdBy},
      NOW()
    )
    RETURNING
      id,
      title,
      author,
      summary,
      kind,
      source_value,
      download_url,
      preview_url,
      preview_kind,
      accent_color,
      thumbnail_url,
      featured,
      installs,
      downloads,
      status,
      tags,
      created_at,
      updated_at;
  `) as WallpaperRow[];

  return rows[0];
}

export async function dbPing(): Promise<boolean> {
  try {
    const sql = query();
    await sql`SELECT 1;`;
    return true;
  } catch {
    return false;
  }
}
