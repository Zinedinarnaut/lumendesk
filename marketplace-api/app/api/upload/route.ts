import { put } from "@vercel/blob";
import { NextResponse } from "next/server";
import { AuthorizationError, authenticateUploadRequest } from "../../../lib/auth";
import { ensureSchema, insertWallpaper } from "../../../lib/db";
import { mapRowToWallpaper, normalizeKind, parseTags, sanitizeText } from "../../../lib/models";

export const runtime = "nodejs";
export const maxDuration = 60;

function sanitizeFileName(value: string): string {
  const cleaned = value
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^-+|-+$/g, "");
  return cleaned.length > 0 ? cleaned : "wallpaper-file";
}

function extensionForFile(file: File): string {
  const nameParts = file.name.split(".");
  if (nameParts.length > 1) {
    const ext = nameParts[nameParts.length - 1].trim().toLowerCase();
    if (ext.length > 0) {
      return ext;
    }
  }

  if (file.type.includes("mp4")) return "mp4";
  if (file.type.includes("quicktime")) return "mov";
  if (file.type.includes("webm")) return "webm";

  return "bin";
}

export async function POST(request: Request) {
  try {
    const auth = await authenticateUploadRequest(request);
    await ensureSchema();

    const form = await request.formData();

    const title = sanitizeText(form.get("title"));
    const author = sanitizeText(form.get("author"));
    const summary = sanitizeText(form.get("summary"));
    const kind = normalizeKind(form.get("kind"));
    const tags = parseTags(form.get("tags"));
    const thumbnailURL = sanitizeText(form.get("thumbnailURL"));

    let sourceValue = sanitizeText(form.get("sourceValue"));
    let downloadURL: string | null = null;

    if (!title || !author || !kind) {
      return NextResponse.json(
        { error: "title, author, and kind are required." },
        { status: 400 }
      );
    }

    if (kind === "video") {
      const uploaded = form.get("file");
      if (uploaded instanceof File && uploaded.size > 0) {
        const ext = extensionForFile(uploaded);
        const blobName = sanitizeFileName(`${title}-${Date.now()}.${ext}`);
        const blob = await put(`wallpapers/${blobName}`, uploaded, {
          access: "public",
          addRandomSuffix: true
        });

        downloadURL = blob.url;
        if (!sourceValue) {
          sourceValue = blob.url;
        }
      } else if (sourceValue) {
        downloadURL = sourceValue;
      } else {
        return NextResponse.json(
          { error: "Video upload requires either file or sourceValue." },
          { status: 400 }
        );
      }
    }

    if (kind === "web" && !sourceValue) {
      return NextResponse.json(
        { error: "Web wallpapers require sourceValue." },
        { status: 400 }
      );
    }

    if ((kind === "gradient" || kind === "shader") && !sourceValue) {
      return NextResponse.json(
        { error: "Preset wallpapers require sourceValue preset ID." },
        { status: 400 }
      );
    }

    const row = await insertWallpaper({
      title,
      author,
      summary,
      kind,
      sourceValue,
      downloadURL,
      thumbnailURL,
      tags,
      createdBy: auth?.subject ?? null
    });

    return NextResponse.json(
      {
        wallpaper: mapRowToWallpaper(row)
      },
      { status: 201 }
    );
  } catch (error) {
    if (error instanceof AuthorizationError) {
      return NextResponse.json({ error: error.message }, { status: error.statusCode });
    }

    console.error("[marketplace-api] Upload failed", error);
    return NextResponse.json(
      { error: "Upload failed due to a server error." },
      { status: 500 }
    );
  }
}
