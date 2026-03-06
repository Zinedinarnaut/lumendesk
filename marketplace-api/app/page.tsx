export default function HomePage() {
  return (
    <main>
      <h1>LumenDesk Marketplace API</h1>
      <p>This service powers marketplace feeds and uploads for LumenDesk.</p>
      <ul>
        <li>
          <code>GET /api/health</code>
        </li>
        <li>
          <code>GET /api/wallpapers</code>
        </li>
        <li>
          <code>POST /api/upload</code>
        </li>
      </ul>
    </main>
  );
}
