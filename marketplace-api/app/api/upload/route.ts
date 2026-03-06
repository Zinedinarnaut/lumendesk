import { put } from "@vercel/blob";
import { NextResponse } from "next/server";
import { AuthorizationError, authenticateUploadRequest } from "../../../lib/auth";
import { ensureSchema, insertWallpaper } from "../../../lib/db";
import {
  mapRowToWallpaper,
  normalizeKind,
  normalizePreviewKind,
  parseBoolean,
  parseTags,
  sanitizeHexColor,
  sanitizeText,
  sanitizeURL
} from "../../../lib/models";

export const runtime = "nodejs";
export const maxDuration = 60;

const VALID_STATUSES = new Set(["draft", "published", "hidden"]);

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

function isAdminRequest(request: Request): boolean {
  const expected = process.env.MARKETPLACE_ADMIN_TOKEN?.trim();
  if (!expected || expected.length === 0) {
    return false;
  }

  const provided = request.headers.get("x-marketplace-admin")?.trim();
  return provided === expected;
}

function normalizeStatus(raw: string | null, admin: boolean): "draft" | "published" | "hidden" {
  if (!admin || !raw) {
    return "published";
  }

  const value = raw.trim().toLowerCase();
  if (VALID_STATUSES.has(value)) {
    return value as "draft" | "published" | "hidden";
  }

  return "published";
}

export async function POST(request: Request) {
  try {
    const isAdmin = isAdminRequest(request);
    const auth = await authenticateUploadRequest(request);
    await ensureSchema();

    const form = await request.formData();

    const title = sanitizeText(form.get("title"));
    const author = sanitizeText(form.get("author"));
    const summary = sanitizeText(form.get("summary"));
    const kind = normalizeKind(form.get("kind"));
    const tags = parseTags(form.get("tags"));
    const thumbnailURL = sanitizeURL(form.get("thumbnailURL")) ?? sanitizeURL(form.get("thumbnail"));
    const accentColor = sanitizeHexColor(form.get("accentColor"));
    const featuredFlag = parseBoolean(form.get("featured"));
    const featured = isAdmin && featuredFlag === true;
    const status = normalizeStatus(sanitizeText(form.get("status")), isAdmin);

    let sourceValue = sanitizeText(form.get("sourceValue"));
    let downloadURL: string | null = null;
    let previewURL = sanitizeURL(form.get("previewURL")) ?? thumbnailURL;
    let previewKind = normalizePreviewKind(form.get("previewKind"));

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
        if (!previewURL) {
          previewURL = blob.url;
        }
        if (previewKind === "image" || previewKind === "none") {
          previewKind = "video";
        }
      } else if (sourceValue) {
        const remote = sanitizeURL(sourceValue);
        if (!remote) {
          return NextResponse.json(
            { error: "Video sourceValue must be a valid http(s) URL." },
            { status: 400 }
          );
        }
        sourceValue = remote;
        downloadURL = remote;
        if (!previewURL) {
          previewURL = remote;
        }
      } else {
        return NextResponse.json(
          { error: "Video upload requires either file or sourceValue." },
          { status: 400 }
        );
      }
    }

    if (kind === "web") {
      const webURL = sanitizeURL(sourceValue);
      if (!webURL) {
        return NextResponse.json(
          { error: "Web wallpapers require a valid sourceValue URL." },
          { status: 400 }
        );
      }
      sourceValue = webURL;
      if (!previewURL) {
        previewURL = webURL;
      }
      if (previewKind === "image" || previewKind === "none") {
        previewKind = "web";
      }
    }

    if ((kind === "gradient" || kind === "shader") && !sourceValue) {
      return NextResponse.json(
        { error: "Preset wallpapers require sourceValue preset ID." },
        { status: 400 }
      );
    }

    if ((kind === "gradient" || kind === "shader") && !previewURL) {
      previewKind = "image";
    }

    const row = await insertWallpaper({
      title,
      author,
      summary,
      kind,
      sourceValue,
      downloadURL,
      previewURL,
      previewKind,
      accentColor,
      thumbnailURL,
      featured,
      tags,
      status,
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
