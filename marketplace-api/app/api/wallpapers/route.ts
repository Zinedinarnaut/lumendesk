import { NextResponse } from "next/server";
import { ensureSchema, listWallpapers } from "../../../lib/db";
import { mapRowToWallpaper } from "../../../lib/models";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const requestedLimit = Number(url.searchParams.get("limit") ?? "120");
  const limit = Number.isFinite(requestedLimit)
    ? Math.min(Math.max(Math.floor(requestedLimit), 1), 500)
    : 120;

  try {
    await ensureSchema();
    const rows = await listWallpapers(limit);
    const wallpapers = rows.map(mapRowToWallpaper);
    return NextResponse.json({ wallpapers }, { status: 200 });
  } catch (error) {
    console.error("[marketplace-api] Failed to fetch wallpapers", error);
    return NextResponse.json(
      { error: "Could not fetch marketplace wallpapers." },
      { status: 500 }
    );
  }
}
