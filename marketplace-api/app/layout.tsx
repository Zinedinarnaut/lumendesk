import type { ReactNode } from "react";

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          color: "#e7ecf3",
          background:
            "radial-gradient(1200px 550px at 10% -10%, rgba(74,145,255,0.35), transparent), radial-gradient(1200px 700px at 110% 10%, rgba(34,197,94,0.22), transparent), #090b10",
          fontFamily:
            "\"SF Pro Text\", \"SF Pro Display\", -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif"
        }}
      >
        {children}
      </body>
    </html>
  );
}
