interface MarketplaceItem {
  id: string;
  title: string;
  author: string;
  summary: string | null;
  kind: string;
  previewURL: string | null;
  thumbnailURL: string | null;
  tags: string[];
  featured: boolean;
  installs: number;
}

interface MarketplaceResponse {
  items: MarketplaceItem[];
  total: number;
}

async function fetchMarketplaceItems(): Promise<MarketplaceResponse> {
  const base = process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "http://localhost:3000";
  const response = await fetch(`${base}/api/marketplace?perPage=12&sort=featured`, {
    cache: "no-store"
  });

  if (!response.ok) {
    return { items: [], total: 0 };
  }

  const data = (await response.json()) as Partial<MarketplaceResponse>;
  return {
    items: Array.isArray(data.items) ? data.items : [],
    total: typeof data.total === "number" ? data.total : 0
  };
}

function previewFor(item: MarketplaceItem): string | null {
  return item.previewURL ?? item.thumbnailURL;
}

function kindLabel(kind: string): string {
  switch (kind) {
    case "video":
      return "Video";
    case "web":
      return "Web";
    case "gradient":
      return "Gradient";
    case "shader":
      return "Metal";
    default:
      return "Wallpaper";
  }
}

export default async function HomePage() {
  const feed = await fetchMarketplaceItems();

  return (
    <main
      style={{
        maxWidth: 1160,
        margin: "0 auto",
        padding: "42px 24px 68px"
      }}
    >
      <section
        style={{
          border: "1px solid rgba(255,255,255,0.08)",
          borderRadius: 22,
          padding: 24,
          background: "rgba(9, 13, 21, 0.68)",
          backdropFilter: "blur(10px)"
        }}
      >
        <p style={{ margin: 0, fontSize: 13, letterSpacing: 1.2, textTransform: "uppercase", color: "#9fb2cf" }}>
          LumenDesk Marketplace API
        </p>
        <h1 style={{ margin: "8px 0 10px", fontSize: 34 }}>Discover animated wallpapers</h1>
        <p style={{ margin: 0, color: "#b6c3d8", maxWidth: 740, lineHeight: 1.55 }}>
          Upload, browse, and install web canvases, live videos, gradients, and Metal shader scenes for LumenDesk.
          This page shows live marketplace content served by the public API.
        </p>

        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 16 }}>
          <Badge label={`Items: ${feed.total}`} />
          <Badge label="POST /api/upload" />
          <Badge label="GET /api/marketplace" />
          <Badge label="GET /api/wallpapers/:id" />
          <Badge label="POST /api/wallpapers/:id/install" />
        </div>
      </section>

      <section style={{ marginTop: 22 }}>
        <h2 style={{ margin: "0 0 12px", fontSize: 24 }}>Featured Marketplace Items</h2>

        {feed.items.length === 0 ? (
          <div
            style={{
              border: "1px dashed rgba(255,255,255,0.18)",
              borderRadius: 18,
              padding: 18,
              color: "#b7c5db"
            }}
          >
            No items published yet. Upload with <code>POST /api/upload</code>.
          </div>
        ) : (
          <div
            style={{
              display: "grid",
              gap: 14,
              gridTemplateColumns: "repeat(auto-fill, minmax(250px, 1fr))"
            }}
          >
            {feed.items.map((item) => {
              const preview = previewFor(item);
              return (
                <article
                  key={item.id}
                  style={{
                    border: "1px solid rgba(255,255,255,0.12)",
                    borderRadius: 16,
                    overflow: "hidden",
                    background: "rgba(16, 21, 31, 0.74)"
                  }}
                >
                  <div
                    style={{
                      height: 144,
                      background:
                        "linear-gradient(135deg, rgba(59,130,246,0.42), rgba(20,184,166,0.42), rgba(250,204,21,0.26))",
                      position: "relative"
                    }}
                  >
                    {preview ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={preview}
                        alt={`${item.title} preview`}
                        style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
                      />
                    ) : null}

                    <span
                      style={{
                        position: "absolute",
                        top: 10,
                        left: 10,
                        background: "rgba(5,8,14,0.75)",
                        border: "1px solid rgba(255,255,255,0.17)",
                        borderRadius: 999,
                        fontSize: 12,
                        padding: "4px 9px"
                      }}
                    >
                      {kindLabel(item.kind)}
                    </span>
                  </div>

                  <div style={{ padding: 13 }}>
                    <div style={{ display: "flex", alignItems: "start", gap: 8 }}>
                      <div style={{ flex: 1 }}>
                        <h3 style={{ margin: 0, fontSize: 16, lineHeight: 1.2 }}>{item.title}</h3>
                        <p style={{ margin: "5px 0 0", color: "#a8b7d0", fontSize: 13 }}>by {item.author}</p>
                      </div>
                      {item.featured ? <Badge label="Featured" /> : null}
                    </div>

                    {item.summary ? (
                      <p style={{ margin: "10px 0 0", color: "#c2cfdf", fontSize: 13.5, lineHeight: 1.4 }}>{item.summary}</p>
                    ) : null}

                    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 10 }}>
                      <Badge label={`Installs ${item.installs}`} />
                      {item.tags.slice(0, 3).map((tag) => (
                        <Badge key={`${item.id}-${tag}`} label={`#${tag}`} />
                      ))}
                    </div>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>
    </main>
  );
}

function Badge({ label }: { label: string }) {
  return (
    <span
      style={{
        border: "1px solid rgba(255,255,255,0.18)",
        borderRadius: 999,
        padding: "5px 10px",
        fontSize: 12,
        color: "#c4d0e1",
        background: "rgba(4,7,13,0.58)"
      }}
    >
      {label}
    </span>
  );
}
