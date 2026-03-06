import { NextResponse } from "next/server";
import { dbPing, ensureSchema } from "../../../lib/db";

export const runtime = "nodejs";

export async function GET() {
  try {
    await ensureSchema();
    const database = await dbPing();
    return NextResponse.json(
      {
        ok: true,
        database
      },
      { status: 200 }
    );
  } catch (error) {
    console.error("[marketplace-api] Health check failed", error);
    return NextResponse.json(
      {
        ok: false,
        database: false
      },
      { status: 500 }
    );
  }
}
