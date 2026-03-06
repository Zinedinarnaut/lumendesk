import { neon } from "@neondatabase/serverless";
import type { WallpaperKind, WallpaperRow } from "./models";

let schemaReady = false;
let queryClient: ReturnType<typeof neon> | null = null;

export interface InsertWallpaperInput {
  title: string;
  author: string;
  summary: string | null;
  kind: WallpaperKind;
  sourceValue: string | null;
  downloadURL: string | null;
  thumbnailURL: string | null;
  tags: string[];
  createdBy: string | null;
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
      thumbnail_url TEXT,
      tags JSONB NOT NULL DEFAULT '[]'::jsonb,
      created_by TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `;

  await sql`
    CREATE INDEX IF NOT EXISTS wallpapers_created_at_idx
      ON wallpapers (created_at DESC);
  `;

  schemaReady = true;
}

export async function listWallpapers(limit: number): Promise<WallpaperRow[]> {
  const safeLimit = Math.min(Math.max(limit, 1), 500);
  const sql = query();
  const rows = (await sql`
    SELECT id, title, author, summary, kind, source_value, download_url, thumbnail_url, tags
    FROM wallpapers
    ORDER BY created_at DESC
    LIMIT ${safeLimit};
  `) as WallpaperRow[];

  return rows;
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
      thumbnail_url,
      tags,
      created_by
    ) VALUES (
      ${id},
      ${input.title},
      ${input.author},
      ${input.summary},
      ${input.kind},
      ${input.sourceValue},
      ${input.downloadURL},
      ${input.thumbnailURL},
      ${JSON.stringify(input.tags)},
      ${input.createdBy}
    )
    RETURNING id, title, author, summary, kind, source_value, download_url, thumbnail_url, tags;
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
