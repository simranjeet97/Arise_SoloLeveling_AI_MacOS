import AppKit
import SwiftUI

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem:      NSStatusItem?
    private var popover:         NSPopover?
    private var dashboardWindow: NSWindow?
    private var voiceHUDWindow:  NSWindow?
    private var dungeonWindow:   NSWindow?
    private var journalWindow:   NSWindow?

    // MARK: - Services

    private let db      = DatabaseService.shared
    private let engine  = QuestEngine.shared
    private let gemini  = GeminiService.shared
    private let voice   = VoiceOutputService.shared
    private let whisper = WhisperService.shared

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        bootstrapAPIKeys()   // Migrate env-var keys → Keychain on first launch
        setupStatusBarItem()
        setupPopover()

        do {
            try db.setupDatabase()
        } catch {
            print("[ARISE] DB setup failed: \(error)")
        }

        // Only request auth if we are a bundled app (avoids crash during `swift run` in terminal)
        if Bundle.main.bundleIdentifier != nil {
            NotificationService.shared.requestAuthorization()
        }

        NotificationCenter.default.addObserver(forName: .ariseNotificationTapped, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let route = notification.object as? String else { return }
                if route == "voiceHUD" {
                    self?.startVoiceSession()
                } else if route == "journalView" {
                    self?.openJournalWindow()
                } else if route == "settingsView" {
                    self?.openSettingsWindow()
                }
            }
        }

        greetUserIfNeeded()
        runPipelineTest()    // Simulate voice pipeline — logs to console
        runDungeonTest()     // Simulate Learning Dungeon — logs full JSON to console
        runJournalTest()     // Simulate Shadow Journal — logs Claude's emotional extraction
    }

    func applicationWillTerminate(_ notification: Notification) {
        whisper.stopRecording()
    }

    // MARK: - Status Bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // "waveform" SF Symbol in accentPurple-ish tint —
        // NSStatusBarButton supports template images only; colour via appearance.
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ARISE")?
            .withSymbolConfiguration(cfg)
        button.image?.isTemplate = true          // auto light/dark menu bar adaptation
        button.toolTip  = "ARISE — Shadow System"
        button.action   = #selector(togglePopover)
        button.target   = self
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 490)
        popover.behavior    = .transient
        popover.animates    = true

        let view = MenuBarView(
            onOpenDashboard: { [weak self] in
                DispatchQueue.main.async { self?.openDashboard() }
            },
            onStartVoice: { [weak self] in
                DispatchQueue.main.async { self?.startVoiceSession() }
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Dashboard Window (transparent + frosted glass)

    func openDashboard() {
        popover?.performClose(nil)

        if let w = dashboardWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeTransparentWindow(
            size:   NSSize(width: 920, height: 640),
            minSize: NSSize(width: 880, height: 620)
        )
        window.setFrameAutosaveName("ARISEDashboard")
        window.title = "ARISE"

        // Use an NSVisualEffectView as the root so system blur
        // composites correctly behind the SwiftUI stack.
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material     = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state        = .active
        effectView.wantsLayer   = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true

        let host = NSHostingView(rootView: DashboardView())
        host.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        window.contentView = effectView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = window
    }

    // MARK: - Voice HUD Window (floating pill)

    func startVoiceSession() {
        popover?.performClose(nil)

        if let hud = voiceHUDWindow, hud.isVisible {
            // HUD already visible — bring it to front and start listening
            hud.makeKeyAndOrderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }
        let hudW: CGFloat = 400
        let hudH: CGFloat = 220
        let frame = NSRect(
            x: screen.visibleFrame.midX - hudW / 2,
            y: screen.visibleFrame.minY  + 60,
            width:  hudW,
            height: hudH
        )

        let window = NSPanel(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel, .utilityWindow],
            backing:     .buffered,
            defer:       false
        )
        window.level              = .floating
        window.isOpaque           = false
        window.backgroundColor    = .clear
        window.hasShadow          = true
        window.animationBehavior  = .utilityWindow
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Pass autoStart: true so the HUD immediately begins recording
        // when opened via the menu bar — no extra button press needed.
        window.contentView = NSHostingView(
            rootView: VoiceHUDView(
                autoStart: true,
                onDismiss: { [weak self] in self?.dismissVoiceHUD() }
            )
        )
        window.makeKeyAndOrderFront(nil)
        voiceHUDWindow = window
        // NOTE: Recording is started by VoiceHUDView itself on appear.
        // Do NOT call whisper.startRecording() here — it would double-start.
    }

    private func dismissVoiceHUD() {
        whisper.stopRecording()
        voiceHUDWindow?.orderOut(nil)
        voiceHUDWindow = nil
    }

    // MARK: - Learning Dungeon Window

    func openLearningDungeon(topic: String) {
        popover?.performClose(nil)

        // Close any existing dungeon window before opening a new topic.
        dungeonWindow?.close()
        dungeonWindow = nil

        let window = makeTransparentWindow(
            size:    NSSize(width: 840, height: 620),
            minSize: NSSize(width: 760, height: 520)
        )
        window.setFrameAutosaveName("ARISEDungeon")
        window.title = "Learning Dungeon: \(topic)"

        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material     = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state        = .active
        effectView.wantsLayer   = true
        effectView.layer?.cornerRadius  = 16
        effectView.layer?.masksToBounds = true

        let host = NSHostingView(
            rootView: LearningDungeonView(
                topic: topic,
                onDismiss: { [weak self] in
                    self?.dungeonWindow?.close()
                    self?.dungeonWindow = nil
                }
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo:      effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo:   effectView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo:  effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        window.contentView = effectView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dungeonWindow = window
        print("[ARISE] 📚 Opening Learning Dungeon: \(topic)")
    }

    // MARK: - Journal Window
    
    func openJournalWindow() {
        popover?.performClose(nil)
        
        journalWindow?.close()
        journalWindow = nil
        
        let window = makeTransparentWindow(
            size:    NSSize(width: 800, height: 600),
            minSize: NSSize(width: 700, height: 500)
        )
        window.setFrameAutosaveName("ARISEJournal")
        window.title = "Shadow Dungeon"
        
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material     = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state        = .active
        effectView.wantsLayer   = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        
        let host = NSHostingView(
            rootView: JournalView(
                onDismiss: { [weak self] in
                    self?.journalWindow?.close()
                    self?.journalWindow = nil
                }
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        window.contentView = effectView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        journalWindow = window
    }

    // MARK: - Settings Window
    
    private var settingsWindow: NSWindow?
    
    func openSettingsWindow() {
        popover?.performClose(nil)
        
        settingsWindow?.close()
        settingsWindow = nil
        
        let window = makeTransparentWindow(
            size:    NSSize(width: 600, height: 750),
            minSize: NSSize(width: 500, height: 600)
        )
        window.setFrameAutosaveName("ARISESettings")
        window.title = "System Settings"
        
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material     = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state        = .active
        effectView.wantsLayer   = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        
        let host = NSHostingView(
            rootView: SettingsView(
                onDismiss: { [weak self] in
                    self?.settingsWindow?.close()
                    self?.settingsWindow = nil
                }
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        window.contentView = effectView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Window Factory

    /// Creates a frameless, transparent, rounded-corner window.
    private func makeTransparentWindow(
        size:    NSSize,
        minSize: NSSize? = nil
    ) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   [.titled, .closable, .miniaturizable, .resizable,
                          .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        // ── Transparent chrome
        w.isOpaque                         = false
        w.backgroundColor                  = .clear
        w.titlebarAppearsTransparent       = true
        w.titleVisibility                  = .hidden
        w.isMovableByWindowBackground      = true
        w.hasShadow                        = true
        w.minSize                          = minSize ?? size

        // ── Corner radius on the backing layer
        w.contentView?.wantsLayer          = true
        w.contentView?.layer?.cornerRadius = 16
        w.contentView?.layer?.masksToBounds = true

        // ── Hide the standard traffic-light buttons (they reappear on hover via standard macOS)
        w.standardWindowButton(.zoomButton)?.isHidden  = false
        w.standardWindowButton(.closeButton)?.isHidden = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = false

        return w
    }

    // MARK: - Daily Greeting

    private func greetUserIfNeeded() {
        let key   = "ARISE_LastGreetDate"
        let today = Calendar.current.startOfDay(for: Date())

        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) { return }

        UserDefaults.standard.set(today, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.voice.speak("Arise, Hunter. Your shadow awaits. Let us review your quests.")
        }
    }

    // MARK: - API Key Bootstrap

    /// On first launch, promote any environment-variable API keys into the Keychain
    /// so they persist across app restarts without being hard-coded in source.
    private func bootstrapAPIKeys() {
        let keychain = KeychainService.shared
        let env      = ProcessInfo.processInfo.environment

        // Bootstrap Google Gemini API key (primary AI service).
        if keychain.load(key: KeychainService.googleKey) == nil,
           let key = env["GOOGLE_API_KEY"], !key.isEmpty {
            keychain.save(key: KeychainService.googleKey, value: key)
            print("[ARISE] ✅ Google API key bootstrapped into Keychain.")
        }
    }

    // MARK: - Pipeline Test

    /// Simulates the full text-mode voice pipeline:
    ///   Input: "Hey ARISE, what quest should I do today?"
    ///   Measures time from request → first token (latency target: < 1.5 s)
    ///   Streams and logs every token, then speaks the full response via TTS.
    private func runPipelineTest() {
        Task {
            print("")
            print("[ARISE TEST] ══════════════════════════════════════════")
            print("[ARISE TEST] 🔊 Simulating voice pipeline (text mode)")
            print("[ARISE TEST] Input: \"Hey ARISE, what quest should I do today?\"")
            print("[ARISE TEST] ══════════════════════════════════════════")

            let stats  = try? db.fetchPlayerStats()
            let quests = (try? db.fetchActiveQuests()) ?? []

            // Log player context that will be injected into the system prompt.
            if let s = stats {
                print("[ARISE TEST] 👤 Player: Level \(s.level) \(s.title) | STR:\(s.strength) AGI:\(s.agility) STA:\(s.stamina) INT:\(s.intelligence) SENSE:\(s.sense)")
            } else {
                print("[ARISE TEST] 👤 Player: no DB record (using uncontextualised prompt)")
            }
            print("[ARISE TEST] 📋 Active quests: \(quests.filter { $0.status == .active }.count)")

            let requestStart = Date()
            var firstTokenLatency: Double? = nil
            var fullResponse = ""
            var tokenCount   = 0

            let stream = GeminiService.shared.streamMessage(
                "Hey ARISE, what quest should I do today?",
                stats:  stats,
                quests: quests
            )

            do {
                print("[ARISE TEST] ⏱  Streaming started at \(requestStart)")
                print("[ARISE STREAM] ", terminator: "")

                for try await token in stream {
                    if firstTokenLatency == nil {
                        firstTokenLatency = Date().timeIntervalSince(requestStart)
                        print("")  // newline before first token log
                        print("[ARISE TEST] ⚡ First token latency: \(String(format: "%.2f", firstTokenLatency!))s " +
                              (firstTokenLatency! < 1.5 ? "✅ (< 1.5 s target)" : "⚠️ (> 1.5 s target)"))
                        print("[ARISE STREAM] ", terminator: "")
                    }
                    fullResponse += token
                    tokenCount   += 1
                    print(token, terminator: "")
                    fflush(stdout)

                    // Speak each token chunk as it arrives (sentence-by-sentence).
                    await MainActor.run {
                        VoiceOutputService.shared.feedStreamToken(token)
                    }
                }

                // Flush any remaining partial sentence.
                await MainActor.run {
                    VoiceOutputService.shared.flushStreamBuffer()
                }

                let totalTime = Date().timeIntervalSince(requestStart)
                print("")  // newline after inline stream
                print("")
                print("[ARISE TEST] ══════════════════════════════════════════")
                print("[ARISE TEST] ✅ Stream complete")
                print("[ARISE TEST]    Total time:    \(String(format: "%.2f", totalTime))s")
                print("[ARISE TEST] ──────────────────────────────────────────")
                print("[ARISE TEST] Full response:")
                print(fullResponse)
                print("[ARISE TEST] ══════════════════════════════════════════")

            } catch {
                print("")
                print("[ARISE TEST] ❌ Pipeline error: \(error.localizedDescription)")
                print("[ARISE TEST] ══════════════════════════════════════════")
            }
        }
    }
    // MARK: - Dungeon Test

    /// Simulates a full Learning Dungeon on "React Server Components".
    /// Calls Claude with web_search enabled, prints the raw JSON response
    /// (including web sources) to the console, and parses the result.
    ///
    /// CLI equivalent: swift run ARISECLITest --dungeon "React Server Components"
    private func runDungeonTest() {
        Task {
            // Delay so it doesn't interleave with the pipeline test output.
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            let topic = "React Server Components"
            print("")
            print("[DUNGEON TEST] ══════════════════════════════════════════")
            print("[DUNGEON TEST] 📚 Entering Learning Dungeon: \(topic)")
            print("[DUNGEON TEST] ══════════════════════════════════════════")

            let start = Date()

            guard let dungeon = await DungeonService.shared.enterLearningDungeon(topic: topic) else {
                let err = await DungeonService.shared.lastError ?? "unknown"
                print("[DUNGEON TEST] ❌ Failed to enter dungeon")
                print("[DUNGEON TEST] Error: \(err)")
                return
            }

            let elapsed = Date().timeIntervalSince(start)

            print("[DUNGEON TEST] ══════════════════════════════════════════")
            print("[DUNGEON TEST] ✅ Dungeon parsed successfully (\(String(format: "%.1f", elapsed))s)")
            print("")
            print("[DUNGEON TEST] 🔍 SUMMARY:")
            print(dungeon.summary)
            print("")
            print("[DUNGEON TEST] 🔗 SOURCES (\(dungeon.sources.count)):")
            for (i, s) in dungeon.sources.enumerated() {
                print("  \(i+1). \(s.title)")
                print("     \(s.url)")
            }
            print("")
            print("[DUNGEON TEST] ❓ QUIZ QUESTIONS (\(dungeon.questions.count)):")
            for (i, q) in dungeon.questions.enumerated() {
                print("  Q\(i+1): \(q.prompt)")
                for opt in q.options { print("         \(opt)") }
                print("         ✓ Answer: \(q.answer)")
            }
            print("[DUNGEON TEST] ══════════════════════════════════════════")
        }
    }

    // MARK: - Journal Test

    private func runJournalTest() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)

            let testInput = "I'm feeling overwhelmed with work today."
            print("")
            print("[JOURNAL TEST] ══════════════════════════════════════════")
            print("[JOURNAL TEST] 🌑 Entering Shadow Dungeon: '\(testInput)'")
            print("[JOURNAL TEST] ══════════════════════════════════════════")

            let start = Date()

            do {
                let entry = try await EmotionalAnalysisService.shared.analyzeAndSaveJournal(transcript: testInput)
                let elapsed = Date().timeIntervalSince(start)

                print("[JOURNAL TEST] ══════════════════════════════════════════")
                print("[JOURNAL TEST] ✅ Journal parsed successfully (\(String(format: "%.1f", elapsed))s)")
                print("")
                print("[JOURNAL TEST] 🧠 EMOTION:   \(entry.emotion.uppercased()) (\(entry.intensity)/10)")
                print("[JOURNAL TEST] 💭 SUMMARY:\n\(entry.claudeSummary)")
                print("[JOURNAL TEST] ══════════════════════════════════════════")
            } catch {
                print("[JOURNAL TEST] ❌ Failed to analyze journal: \(error)")
            }
        }
    }
}
