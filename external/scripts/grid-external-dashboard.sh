#!/usr/bin/env bash
# ==============================================================================
# fusionAIze Grid - External Status Dashboard Generator
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd || exit 1)"

WWW_ROOT="/var/www/faigrid"
OUTPUT_FILE="${WWW_ROOT}/index.html"
JSON_DATA="${WWW_ROOT}/grid-status.json"

mkdir -p "${WWW_ROOT}"

# Generate aesthetic HTML
cat <<EOF > "${OUTPUT_FILE}"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>fusionAIze Grid | Global Grid Status</title>
    <style>
        :root {
            --bg: #0f172a;
            --card-bg: #1e293b;
            --text: #f8fafc;
            --accent: #38bdf8;
            --success: #22c55e;
            --warning: #f59e0b;
        }
        body {
            background: var(--bg);
            color: var(--text);
            font-family: 'Inter', system-ui, sans-serif;
            margin: 0;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
        }
        header {
            padding: 2rem;
            text-align: center;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            width: 90%;
            max-width: 1200px;
        }
        .card {
            background: var(--card-bg);
            padding: 1.5rem;
            border-radius: 12px;
            border-left: 4px solid var(--accent);
            box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);
        }
        .card.error { border-left-color: #ef4444; }
        .node-name { font-weight: bold; font-size: 1.2rem; margin-bottom: 0.5rem; }
        .status { font-family: monospace; }
        .timestamp { font-size: 0.8rem; color: #94a3b8; margin-top: 1rem; }
    </style>
</head>
<body>
    <header>
        <h1>🛰️ Grid Global Grid</h1>
        <p>Public Status Dashboard (External Extension)</p>
    </header>
    <div class="grid" id="status-grid">
        <!-- Injected by watchdog push -->
        <div class="card">
            <div class="node-name">grid-external</div>
            <div class="status">System OK</div>
            <div class="timestamp">Last local check: $(date)</div>
        </div>
    </div>
</body>
</html>
EOF

echo "[grid-external] Dashboard generated at ${OUTPUT_FILE}"
