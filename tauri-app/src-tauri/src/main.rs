#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::process::Command;
use tauri::{ActivationPolicy, CustomMenuItem, Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, SystemTrayMenuItem, SystemTraySubmenu};

fn main() {
    let _ = Command::new("pkill").arg("-f").arg("uvicorn").output();

    let _ = Command::new("zsh")
        .arg("-c")
        .arg("cd ~/odysseus-pewdiepie && ./venv/bin/uvicorn app:app --host 127.0.0.1 --port 7860 > logs/tauri-backend.log 2>&1 &")
        .spawn()
        .expect("Failed to start backend");

    let open_item = CustomMenuItem::new("open".to_string(), "Open Odysseus").accelerator("CmdOrCtrl+O");
    let quit_item = CustomMenuItem::new("quit".to_string(), "Quit").accelerator("CmdOrCtrl+Q");

    let features_menu = SystemTrayMenu::new()
        .add_item(CustomMenuItem::new("new_chat", "New Chat").accelerator("CmdOrCtrl+N"))
        .add_item(CustomMenuItem::new("search", "Search").accelerator("CmdOrCtrl+S"))
        .add_item(CustomMenuItem::new("chats", "Chats").accelerator("CmdOrCtrl+Shift+C"))
        .add_item(CustomMenuItem::new("email", "Email").accelerator("CmdOrCtrl+Shift+E"));
    let features = SystemTraySubmenu::new("Features", features_menu);

    let tools_menu = SystemTrayMenu::new()
        .add_item(CustomMenuItem::new("brain", "Brain").accelerator("CmdOrCtrl+Shift+B"))
        .add_item(CustomMenuItem::new("calendar", "Calendar").accelerator("CmdOrCtrl+Shift+A"))
        .add_item(CustomMenuItem::new("compare", "Compare").accelerator("CmdOrCtrl+Shift+P"))
        .add_item(CustomMenuItem::new("cookbook", "Cookbook").accelerator("CmdOrCtrl+Shift+K"))
        .add_item(CustomMenuItem::new("deep_research", "Deep Research").accelerator("CmdOrCtrl+Shift+D"))
        .add_item(CustomMenuItem::new("gallery", "Gallery").accelerator("CmdOrCtrl+Shift+G"))
        .add_item(CustomMenuItem::new("library", "Library").accelerator("CmdOrCtrl+Shift+L"))
        .add_item(CustomMenuItem::new("notes", "Notes").accelerator("CmdOrCtrl+Shift+N"))
        .add_item(CustomMenuItem::new("tasks", "Tasks").accelerator("CmdOrCtrl+Shift+T"))
        .add_item(CustomMenuItem::new("theme", "Theme").accelerator("CmdOrCtrl+Shift+H"));
    let tools = SystemTraySubmenu::new("Tools", tools_menu);

    let mgmt_menu = SystemTrayMenu::new()
        .add_item(CustomMenuItem::new("data", "Data Folder").accelerator("CmdOrCtrl+D"))
        .add_item(CustomMenuItem::new("logs", "View Logs").accelerator("CmdOrCtrl+L"))
        .add_item(CustomMenuItem::new("restart", "Restart Server").accelerator("CmdOrCtrl+R"));
    let mgmt = SystemTraySubmenu::new("Management", mgmt_menu);

    let tray_menu = SystemTrayMenu::new()
        .add_item(open_item)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_submenu(features)
        .add_submenu(tools)
        .add_submenu(mgmt)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(quit_item);

    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(ActivationPolicy::Accessory);
            Ok(())
        })
        .system_tray(SystemTray::new().with_menu(tray_menu))
        .on_system_tray_event(|app, event| {
            if let SystemTrayEvent::MenuItemClick { id, .. } = event {
                let win = app.get_window("main").unwrap();
                match id.as_str() {
                    "open" => { win.show().unwrap(); win.set_focus().unwrap(); }
                    "quit" => { std::process::exit(0); }
                    "data" => { let _ = Command::new("open").arg("../data").spawn(); }
                    "logs" => { let _ = Command::new("open").arg("../logs/tauri-backend.log").spawn(); }
                    "restart" => {
                        let _ = Command::new("pkill").arg("-f").arg("uvicorn").output();
                        let _ = Command::new("zsh").arg("-c").arg("cd ~/odysseus-pewdiepie && ./venv/bin/uvicorn app:app --host 127.0.0.1 --port 7860 > logs/tauri-backend.log 2>&1 &").spawn();
                        win.eval("window.location.reload()").unwrap();
                    }
                    "new_chat" => {
                        win.show().unwrap(); win.set_focus().unwrap();
                        let js = r#"
                        (function() {
                            let buttons = Array.from(document.querySelectorAll('button, a, div[role="button"], li'));
                            let newBtn = buttons.find(b => {
                                let text = (b.innerText || b.textContent || b.title || b.getAttribute('aria-label') || '').toLowerCase();
                                return (text.includes('new chat') || text === 'new' || text.includes('new conversation')) && text.length < 50;
                            });
                            if (newBtn) { newBtn.click(); } else { window.location.href = '/'; }
                        })();
                        "#;
                        win.eval(js).unwrap();
                    }
                    "search" => {
                        win.show().unwrap(); win.set_focus().unwrap();
                        let js = r#"
                        (function() {
                            let searchInput = document.querySelector('input[type="search"], input[placeholder*="earch" i], [class*="search" i] input, input[id*="search" i]');
                            if (searchInput && searchInput.offsetParent !== null) { searchInput.focus(); return; }
                            let clickables = Array.from(document.querySelectorAll('button, a, [role="button"], li'));
                            let btn = clickables.find(el => {
                                let text = (el.innerText || el.textContent || el.getAttribute('aria-label') || el.title || '').toLowerCase().trim();
                                return text === 'search' || text.includes('search');
                            });
                            if (btn) { btn.click(); return; }
                            let kOpts = { key: 'k', code: 'KeyK', keyCode: 75, which: 75, metaKey: true, bubbles: true, composed: true, cancelable: true };
                            document.dispatchEvent(new KeyboardEvent('keydown', kOpts)); window.dispatchEvent(new KeyboardEvent('keydown', kOpts));
                        })();
                        "#;
                        win.eval(js).unwrap();
                    }
                    "chats" => {
                        win.show().unwrap(); win.set_focus().unwrap();
                        let js = r#"
                        (function() {
                            const getCleanText = (el) => (el.innerText || el.textContent || '').toLowerCase().trim();
                            let libraryBtn = null;
                            let innerSpans = Array.from(document.querySelectorAll('span, div, p')).filter(el => { let t = getCleanText(el); return t === 'library' || t === 'library +'; });
                            if (innerSpans.length > 0) { libraryBtn = innerSpans[0].closest('a, button, li, [role="button"], .sidebar-item, .nav-item') || innerSpans[0]; }
                            else {
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
                                    if (innerTabs.length > 0) chatsTab = innerTabs[0].closest('a, button, [role="tab"]') || innerTabs[0];
                                    if (chatsTab) chatsTab.click(); else window.location.href = '/';
                                }, 400); 
                            } else { window.location.href = '/'; }
                        })();
                        "#;
                        win.eval(js).unwrap();
                    }
                    feature @ "email" | feature @ "brain" | feature @ "calendar" | feature @ "compare" | feature @ "cookbook" | feature @ "deep_research" | feature @ "gallery" | feature @ "library" | feature @ "notes" | feature @ "tasks" | feature @ "theme" => {
                        win.show().unwrap(); win.set_focus().unwrap();
                        let keyword = feature.replace("_", " ");
                        let js = [
                            &format!("let kw = '{}';", keyword),
                            r#"
                            (function() {
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
                            "#
                        ].concat();
                        win.eval(&js).unwrap();
                    }
                    _ => {}
                }
            }
        })
        .on_window_event(|event| if let tauri::WindowEvent::CloseRequested { api, .. } = event.event() {
            event.window().hide().unwrap();
            api.prevent_close();
        })
        .run(tauri::generate_context!())
        .expect("error");
}
