#!/bin/bash
set -e

echo "🚀 Bootstrapping Cross-Platform Tauri App..."

# 1. Clean slate
rm -rf tauri-app
mkdir -p tauri-app/ui
cd tauri-app

# 2. Setup Node environment
echo "📦 Installing Tauri CLI..."
cat > package.json << 'JSON'
{
  "name": "odysseus-desktop",
  "scripts": {
    "dev": "tauri dev",
    "build": "tauri build"
  },
  "devDependencies": {
    "@tauri-apps/cli": "^1.5.0"
  }
}
JSON
npm install >/dev/null 2>&1

# 3. Create the Local Loading Screen
echo "🖥️ Building local intercept UI..."
cat > ui/index.html << 'HTML'
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Odysseus</title>
    <style>
      body { background-color: #131313; color: white; display: flex; justify-content: center; align-items: center; height: 100vh; font-family: -apple-system, sans-serif; margin: 0; }
      h2 { font-weight: 500; letter-spacing: 0.5px; opacity: 0.8; }
    </style>
  </head>
  <body>
    <h2>Waking up Odysseus...</h2>
    <script>
      // Instantly redirect to the Python backend once it boots
      let check = setInterval(() => {
        fetch('http://127.0.0.1:7860/', { mode: 'no-cors' })
          .then(() => { 
            clearInterval(check);
            window.location.href = 'http://127.0.0.1:7860/'; 
          })
          .catch(() => {});
      }, 150);
    </script>
  </body>
</html>
HTML

# 4. Initialize the Rust Backend
echo "🦀 Initializing Rust backend..."
npx tauri init \
    --app-name "Odysseus" \
    --window-title "Odysseus" \
    --dist-dir "../ui" \
    --dev-path "../ui" \
    --before-dev-command "" \
    --before-build-command ""

# 5. Generate Icons
if [ -f "../docs/odysseus.jpg" ]; then
    echo "🎨 Generating Windows, Linux, and Mac icons..."
    npx tauri icon ../docs/odysseus.jpg >/dev/null 2>&1
fi

# 6. Write the Rust code to manage the Python Server
echo "⚙️ Injecting Server Lifecycle logic into Rust..."
cat > src-tauri/src/main.rs << 'RUST'
#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::process::Command;

fn main() {
    // 1. Kill any ghost instances on port 7860
    let _ = Command::new("bash")
        .arg("-c")
        .arg("lsof -ti:7860 | xargs kill -9 2>/dev/null")
        .output();

    // 2. Boot the Python FastAPI server in the background
    let mut server = Command::new("bash")
        .arg("-c")
        .arg("cd ../.. && ./venv/bin/uvicorn app:app --host 127.0.0.1 --port 7860")
        .spawn()
        .expect("Failed to start Odysseus backend");

    // 3. Launch the App Window
    tauri::Builder::default()
        .on_window_event(move |event| match event.event() {
            tauri::WindowEvent::Destroyed => {
                // 4. Kill the server instantly when the user closes the app
                let _ = server.kill();
                let _ = Command::new("bash")
                    .arg("-c")
                    .arg("lsof -ti:7860 | xargs kill -9 2>/dev/null")
                    .output();
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
RUST

echo "✅ Tauri Architecture built successfully!"
