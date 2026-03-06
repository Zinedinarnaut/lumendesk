import { POST as uploadPOST } from "../api/upload/route";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(request: Request) {
  return uploadPOST(request);
}
