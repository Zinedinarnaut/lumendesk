import { NextResponse } from "next/server";
import { ensureSchema, listMarketplaceWallpapers } from "../../../lib/db";
import { mapRowToWallpaper, normalizeSort, type WallpaperKind } from "../../../lib/models";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const requestedPerPage = Number(url.searchParams.get("perPage") ?? "24");
  const perPage = Number.isFinite(requestedPerPage)
    ? Math.min(Math.max(Math.floor(requestedPerPage), 1), 100)
    : 24;

  const requestedPage = Number(url.searchParams.get("page") ?? "1");
  const page = Number.isFinite(requestedPage) ? Math.max(Math.floor(requestedPage), 1) : 1;

  const q = url.searchParams.get("q");
  const tag = url.searchParams.get("tag");
  const sort = normalizeSort(url.searchParams.get("sort"));
  const featuredParam = url.searchParams.get("featured");
  const featured = featuredParam == null ? null : featuredParam === "true" || featuredParam === "1";
  const kindParam = (url.searchParams.get("kind") ?? "").trim().toLowerCase();
  const kind = (["web", "video", "gradient", "shader"] as const).includes(kindParam as WallpaperKind)
    ? (kindParam as WallpaperKind)
    : null;

  try {
    await ensureSchema();

    const result = await listMarketplaceWallpapers({
      q,
      kind,
      tag,
      featured,
      sort,
      page,
      perPage
    });

    const items = result.rows.map(mapRowToWallpaper);
    return NextResponse.json(
      {
        items,
        page: result.page,
        perPage: result.perPage,
        total: result.total,
        hasMore: result.page * result.perPage < result.total
      },
      { status: 200 }
    );
  } catch (error) {
    console.error("[marketplace-api] Failed to list marketplace items", error);
    return NextResponse.json(
      { error: "Could not fetch marketplace items." },
      { status: 500 }
    );
  }
}
