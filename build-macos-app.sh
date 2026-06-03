#!/bin/bash
# Build a native macOS Swift Menu Bar App + Standalone Web Wrapper for Odysseus.
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Odysseus"
INSTALL_DIR="$REPO_DIR"
PORT="${ODYSSEUS_PORT:-7860}"
DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"

echo "Building Professional Native Swift App..."

# 1. Kill existing instances
lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
pkill -f "$APP_NAME" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$DIST"

# 2. Build the Info.plist (BUNDLE ID LOCKED FOR PERSISTENT CACHE & LOGINS)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>com.odysseus.native</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>        <string>applet</string>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# 3. Process the Custom Sailboat Logo (APPLE-STANDARD PADDING)
LOGO_FILE=""
if [ -f "$REPO_DIR/docs/odysseus.png" ]; then
  LOGO_FILE="$REPO_DIR/docs/odysseus.png"
elif [ -f "$REPO_DIR/docs/odysseus.jpg" ]; then
  LOGO_FILE="$REPO_DIR/docs/odysseus.jpg"
fi

if [ -n "$LOGO_FILE" ]; then
  TMPIMG="$(mktemp -d)"
  
  cat > "$TMPIMG/pad.swift" << 'SWIFT'
  import Cocoa
  let args = CommandLine.arguments
  guard args.count >= 3, let img = NSImage(contentsOfFile: args[1]) else { exit(1) }
  let target = NSSize(width: 512, height: 512)
  let newImg = NSImage(size: target)
  newImg.lockFocus()
  NSColor.clear.set()
  NSRect(origin: .zero, size: target).fill()
  img.draw(in: NSRect(x: 56, y: 56, width: 400, height: 400), from: NSRect(origin: .zero, size: img.size), operation: .sourceOver, fraction: 1.0)
  newImg.unlockFocus()
  if let tiff = newImg.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
      try? png.write(to: URL(fileURLWithPath: args[2]))
  }
SWIFT
  
  swift "$TMPIMG/pad.swift" "$LOGO_FILE" "$TMPIMG/padded_icon.png" 2>/dev/null || cp "$LOGO_FILE" "$TMPIMG/padded_icon.png"
  sips -s format icns "$TMPIMG/padded_icon.png" --out "$APP/Contents/Resources/applet.icns" >/dev/null 2>&1
  sips -z 64 64 "$LOGO_FILE" --out "$APP/Contents/Resources/menubar_icon.png" >/dev/null 2>&1
  
  echo "  icon:        Custom Sailboat Icons generated with perfect Apple padding."
  rm -rf "$TMPIMG"
else
  echo "  icon:        (skipped — no docs/odysseus.png found)"
fi

# 4. Generate the standalone Server Script
cat > "$APP/Contents/Resources/start_server.sh" << 'EOF'
#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
INSTALL_DIR="$1"
PORT="$2"

cd "$INSTALL_DIR"
UVICORN="./venv/bin/uvicorn"

mkdir -p logs
if [ "$(uname -m)" = "arm64" ]; then
    arch -arm64 "$UVICORN" app:app --host 0.0.0.0 --port "$PORT" > logs/odysseus-app.log 2>&1
else
    "$UVICORN" app:app --host 0.0.0.0 --port "$PORT" > logs/odysseus-app.log 2>&1
fi
EOF
chmod +x "$APP/Contents/Resources/start_server.sh"

# 5. Write the Native Swift Application Code
TMP_SWIFT="$(mktemp).swift"
cat > "$TMP_SWIFT" << 'EOF'
import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var serverTask: Process!
    var mainWindow: NSWindow?
    var webView: WKWebView?
    let installDir = "__INSTALL_DIR__"
    let port = "__PORT__"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "menubar_icon", ofType: "png"),
               let img = NSImage(contentsOfFile: iconPath) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🌊"
            }
        }

        let menu = NSMenu()

        // ── Open ────────────────────────────────────────────────────────
        let openItem = NSMenuItem(title: "Open", action: #selector(openWindow), keyEquivalent: "o")
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        // ── Features ▶ ──────────────────────────────────────────────────
        let featuresItem = NSMenuItem(title: "Features", action: nil, keyEquivalent: "")
        featuresItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        let featuresMenu = NSMenu()
        
        let miNewChat = NSMenuItem(title: "New Chat", action: #selector(newChat), keyEquivalent: "n")
        miNewChat.image = NSImage(systemSymbolName: "plus.message", accessibilityDescription: nil)
        featuresMenu.addItem(miNewChat)
        
        let miSearch = NSMenuItem(title: "Search", action: #selector(openSearch), keyEquivalent: "s")
        miSearch.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        featuresMenu.addItem(miSearch)
        
        let miChats = NSMenuItem(title: "Chats", action: #selector(openChats), keyEquivalent: "C")
        miChats.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)
        featuresMenu.addItem(miChats)
        
        let miEmail = NSMenuItem(title: "Email", action: #selector(openFeature(_:)), keyEquivalent: "E")
        miEmail.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        featuresMenu.addItem(miEmail)
        
        featuresItem.submenu = featuresMenu
        menu.addItem(featuresItem)

        // ── Tools ▶ ─────────────────────────────────────────────────────
        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: nil)
        let toolsMenu = NSMenu()
        
        let toolEntries: [(String, String, String)] = [
            ("Brain",         "B", "brain.head.profile"),
            ("Calendar",      "A", "calendar"),
            ("Compare",       "P", "arrow.left.and.right.righttriangle.left.righttriangle.right"),
            ("Cookbook",      "K", "book.closed"),
            ("Deep Research", "D", "network"),
            ("Gallery",       "G", "photo.on.rectangle.angled"),
            ("Library",       "L", "books.vertical"),
            ("Notes",         "N", "note.text"),
            ("Tasks",         "T", "checklist"),
            ("Theme",         "H", "paintbrush.pointed")
        ]
        
        for (name, key, iconName) in toolEntries {
            let item = NSMenuItem(title: name, action: #selector(openFeature(_:)), keyEquivalent: key)
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            toolsMenu.addItem(item)
        }
        toolsItem.submenu = toolsMenu
        menu.addItem(toolsItem)

        // ── Management ▶ ────────────────────────────────────────────────
        let manageItem = NSMenuItem(title: "Management", action: nil, keyEquivalent: "")
        manageItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        let manageMenu = NSMenu()
        
        let miData = NSMenuItem(title: "Data", action: #selector(openDataFolder), keyEquivalent: "d")
        miData.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        manageMenu.addItem(miData)
        
        let miLogs = NSMenuItem(title: "Logs", action: #selector(viewLogs), keyEquivalent: "l")
        miLogs.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        manageMenu.addItem(miLogs)
        
        let miRestart = NSMenuItem(title: "Restart", action: #selector(restartServer), keyEquivalent: "r")
        miRestart.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        manageMenu.addItem(miRestart)
        
        manageItem.submenu = manageMenu
        menu.addItem(manageItem)
        menu.addItem(NSMenuItem.separator())

        // ── App control ─────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        startServer()
    }

    func startServer() {
        guard let scriptPath = Bundle.main.path(forResource: "start_server", ofType: "sh") else { return }
        serverTask = Process()
        serverTask.launchPath = "/bin/bash"
        serverTask.arguments = [scriptPath, installDir, port]
        serverTask.launch()
    }

    func createOrShowWindow() {
        if mainWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 1280, height: 850)
            let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Odysseus"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self

            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            
            webView = WKWebView(frame: rect, configuration: config)
            webView?.setValue(false, forKey: "drawsBackground") 
            
            window.contentView = webView
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // --- NEW SILENT, ULTRA-FAST LOADING SCREEN ---
    func showLoadingScreen() {
        let loadingHTML = """
        <html><body style="background:#131313;height:100vh;margin:0;overflow:hidden;">
        <script>
        // Poll every 150ms instead of 1.5 seconds for instant loading
        let check = setInterval(() => {
            fetch('http://127.0.0.1:\(port)/', { mode: 'no-cors' })
            .then(() => { 
                clearInterval(check);
                window.location.href = 'http://127.0.0.1:\(port)/'; 
            })
            .catch(() => {});
        }, 150);
        </script>
        </body></html>
        """
        webView?.loadHTMLString(loadingHTML, baseURL: nil)
    }

    @objc func openWindow() {
        createOrShowWindow()
        if webView?.url == nil || webView?.url?.host == nil { showLoadingScreen() }
    }

    @objc func openFeature(_ sender: NSMenuItem) {
        createOrShowWindow()
        if webView?.url == nil || webView?.url?.host == nil { showLoadingScreen(); return }
        
        let featureKeyword = sender.title.lowercased() 
        if let webView = webView {
            let js = """
            (function() {
                let kw = '\(featureKeyword)';
                let clickables = Array.from(document.querySelectorAll('a, button, [role="tab"], [role="button"], .sidebar-item, .nav-item, li'));
                
                let getCleanText = (el) => (el.innerText || el.textContent || el.getAttribute('aria-label') || el.title || '').toLowerCase().trim();

                let target = clickables.find(el => getCleanText(el) === kw);
                if (!target) {
                    target = clickables.find(el => {
                        let text = getCleanText(el);
                        return text.includes(kw) && text.length > 0 && text.length < 50;
                    });
                }
                if (!target && kw.includes(' ')) {
                    let rootWord = kw.split(' ')[0];
                    target = clickables.find(el => {
                        let text = getCleanText(el);
                        return text.includes(rootWord) && text.length > 0 && text.length < 50;
                    });
                }
                if (!target) {
                    let leafs = Array.from(document.querySelectorAll('span, i, svg, div'));
                    let leaf = leafs.find(el => {
                        let text = getCleanText(el);
                        if (el.tagName === 'DIV' && el.children.length > 0) return false; 
                        return text.includes(kw) && text.length > 0 && text.length < 50;
                    });
                    if (leaf && leaf.closest('button, a, [role="tab"], li')) {
                        target = leaf.closest('button, a, [role="tab"], li');
                    }
                }
                if (target) target.click(); 
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    @objc func newChat() {
        createOrShowWindow()
        if webView?.url == nil || webView?.url?.host == nil { showLoadingScreen(); return }
        let js = """
        (function() {
            let buttons = Array.from(document.querySelectorAll('button, a, div[role="button"], li'));
            let newBtn = buttons.find(b => {
                let text = (b.innerText || b.textContent || b.title || b.getAttribute('aria-label') || '').toLowerCase();
                return (text.includes('new chat') || text === 'new' || text.includes('new conversation')) && text.length < 50;
            });
            if (newBtn) { newBtn.click(); } else { window.location.href = 'http://127.0.0.1:\(port)/'; }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func openSearch() {
        createOrShowWindow()
        if webView?.url == nil || webView?.url?.host == nil { showLoadingScreen(); return }
        let js = """
        (function() {
            let searchInput = document.querySelector('input[type="search"], input[placeholder*="earch" i], [class*="search" i] input, input[id*="search" i]');
            if (searchInput && searchInput.offsetParent !== null) { 
                searchInput.focus(); 
                return; 
            }

            let clickables = Array.from(document.querySelectorAll('button, a, [role="button"], li'));
            let btn = clickables.find(el => {
                let text = (el.innerText || el.textContent || el.getAttribute('aria-label') || el.title || '').toLowerCase().trim();
                return text === 'search' || text.includes('search');
            });
            
            if (btn) { 
                btn.click(); 
                return; 
            }

            let kOpts = {
                key: 'k', code: 'KeyK', keyCode: 75, which: 75,
                metaKey: true, bubbles: true, composed: true, cancelable: true
            };
            document.dispatchEvent(new KeyboardEvent('keydown', kOpts));
            window.dispatchEvent(new KeyboardEvent('keydown', kOpts));
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func openChats() {
        createOrShowWindow()
        if webView?.url == nil || webView?.url?.host == nil { showLoadingScreen(); return }
        
        let js = """
        (function() {
            const getCleanText = (el) => (el.innerText || el.textContent || '').toLowerCase().trim();

            let libraryBtn = null;
            let innerSpans = Array.from(document.querySelectorAll('span, div, p')).filter(el => {
                let text = getCleanText(el);
                return text === 'library' || text === 'library +';
            });
            
            if (innerSpans.length > 0) {
                libraryBtn = innerSpans[0].closest('a, button, li, [role="button"], .sidebar-item, .nav-item') || innerSpans[0];
            } else {
                let clickables = Array.from(document.querySelectorAll('a, button, li, [role="button"]'));
                libraryBtn = clickables.find(el => getCleanText(el).includes('library'));
            }

            if (libraryBtn) {
                libraryBtn.click();
                setTimeout(() => {
                    let chatsTab = null;
                    let innerTabs = Array.from(document.querySelectorAll('span, div, p, button, a')).filter(el => {
                        let text = getCleanText(el);
                        let isInsideModal = el.closest('dialog, [role="dialog"], .modal, [class*="modal"], [class*="window"]') !== null;
                        return (text === 'chats' || text === 'chat') && isInsideModal;
                    });

                    if (innerTabs.length > 0) {
                        chatsTab = innerTabs[0].closest('a, button, [role="tab"]') || innerTabs[0];
                    }

                    if (chatsTab) {
                        chatsTab.click();
                    } else {
                        window.location.href = 'http://127.0.0.1:\\(port)/';
                    }
                }, 400); 
            } else {
                window.location.href = 'http://127.0.0.1:\\(port)/';
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func openDataFolder() { NSWorkspace.shared.open(URL(fileURLWithPath: "\(installDir)/data")) }
    @objc func viewLogs() { NSWorkspace.shared.open(URL(fileURLWithPath: "\(installDir)/logs/odysseus-app.log")) }

    @objc func restartServer() {
        serverTask?.terminate()
        cleanPort()
        webView?.reload()
        startServer()
    }

    @objc func quitApp() { NSApplication.shared.terminate(self) }

    func applicationWillTerminate(_ aNotification: Notification) {
        serverTask?.terminate()
        cleanPort()
    }
    
    func cleanPort() {
        let cleanup = Process()
        cleanup.launchPath = "/bin/bash"
        cleanup.arguments = ["-c", "lsof -ti:\(port) | xargs kill -9 2>/dev/null"]
        cleanup.launch()
        cleanup.waitUntilExit()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
EOF

sed -i '' -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" -e "s|__PORT__|$PORT|g" "$TMP_SWIFT"

echo "Compiling native Swift binary..."
swiftc "$TMP_SWIFT" -o "$APP/Contents/MacOS/$APP_NAME" -framework Cocoa -framework WebKit
rm -f "$TMP_SWIFT"

xattr -cr "$APP" 2>/dev/null || true
touch "$APP"

echo "Packaging dist/$APP_NAME.dmg..."
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo -e "\n✓ App compiled successfully!"