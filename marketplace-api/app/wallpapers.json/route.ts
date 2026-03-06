import { GET as getWallpapers } from "../api/wallpapers/route";

export const runtime = "nodejs";

export async function GET(request: Request) {
  return getWallpapers(request);
}
