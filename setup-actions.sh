#!/bin/bash

echo "1. Cleaning up accidentally nested folders..."
rm -rf tauri-app/.git tauri-app/.github

echo "2. Setting up GitHub workflow..."
mkdir -p .github/workflows

cat > .github/workflows/build-odysseus.yml << 'YAML'
name: "Build Odysseus for All OS"

on:
  workflow_dispatch:

jobs:
  build-tauri:
    permissions:
      contents: write
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-latest
          - os: windows-latest
          - os: ubuntu-22.04

    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Install Linux Dependencies
        if: matrix.os == 'ubuntu-22.04'
        run: |
          sudo apt-get update
          sudo apt-get install -y libwebkit2gtk-4.0-dev libwebkit2gtk-4.1-dev build-essential curl wget file libssl-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev

      - name: Build Tauri App
        uses: tauri-apps/tauri-action@v0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          projectPath: tauri-app
          tagName: v0.1.0
          releaseName: "Odysseus v0.1.0"
          releaseDraft: true
          prerelease: false
YAML

echo "3. Linking to GitHub and pushing..."
git remote add origin https://github.com/Jonathan-cpu-bit/odysseus-pewdiepie.git 2>/dev/null || git remote set-url origin https://github.com/Jonathan-cpu-bit/odysseus-pewdiepie.git
git add .
git commit -m "Add GitHub Actions for Windows, Mac, and Linux builds"
git push -u origin main
echo "✅ All done! Code pushed to GitHub."
