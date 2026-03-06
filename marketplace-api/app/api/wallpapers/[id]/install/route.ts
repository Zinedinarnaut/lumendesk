import { NextResponse } from "next/server";
import { ensureSchema, incrementWallpaperInstalls } from "../../../../../lib/db";
import { mapRowToWallpaper } from "../../../../../lib/models";

export const runtime = "nodejs";

interface RouteParams {
  params: Promise<{ id: string }>;
}

export async function POST(_: Request, context: RouteParams) {
  const { id } = await context.params;
  const normalizedID = id.trim();

  if (normalizedID.length == 0) {
    return NextResponse.json({ error: "Wallpaper ID is required." }, { status: 400 });
  }

  try {
    await ensureSchema();
    const row = await incrementWallpaperInstalls(normalizedID);

    if (!row) {
      return NextResponse.json({ error: "Wallpaper not found." }, { status: 404 });
    }

    return NextResponse.json({ wallpaper: mapRowToWallpaper(row) }, { status: 200 });
  } catch (error) {
    console.error("[marketplace-api] Failed to increment installs", error);
    return NextResponse.json({ error: "Could not update install counter." }, { status: 500 });
  }
}
