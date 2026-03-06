import { createRemoteJWKSet, jwtVerify } from "jose";

const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export class AuthorizationError extends Error {
  readonly statusCode: number;

  constructor(message: string, statusCode = 401) {
    super(message);
    this.name = "AuthorizationError";
    this.statusCode = statusCode;
  }
}

function extractBearerToken(request: Request): string | null {
  const raw = request.headers.get("authorization");
  if (!raw) {
    return null;
  }

  const parts = raw.trim().split(/\s+/);
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    return null;
  }

  return parts[1];
}

function expectedAudiences(): string[] {
  return [
    process.env.APPLE_BUNDLE_ID,
    process.env.APPLE_SERVICE_ID,
    process.env.APPLE_CLIENT_ID
  ]
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
}

export async function authenticateUploadRequest(request: Request): Promise<{ subject: string } | null> {
  const authRequired = process.env.REQUIRE_APPLE_AUTH !== "false";
  if (!authRequired) {
    return null;
  }

  const token = extractBearerToken(request);
  if (!token) {
    throw new AuthorizationError("Missing Apple identity token.");
  }

  const audiences = expectedAudiences();
  const verificationOptions: Parameters<typeof jwtVerify>[2] = {
    issuer: "https://appleid.apple.com"
  };

  if (audiences.length > 0) {
    verificationOptions.audience = audiences;
  }

  let payloadSubject: string | undefined;

  try {
    const { payload } = await jwtVerify(token, appleJWKS, verificationOptions);
    payloadSubject = payload.sub;
  } catch {
    throw new AuthorizationError("Apple token verification failed.");
  }

  if (!payloadSubject || payloadSubject.length === 0) {
    throw new AuthorizationError("Apple token subject is missing.");
  }

  const declaredUserID = request.headers.get("x-apple-user-id")?.trim();
  if (declaredUserID && declaredUserID != payloadSubject) {
    throw new AuthorizationError("Apple user ID mismatch.");
  }

  return { subject: payloadSubject };
}
