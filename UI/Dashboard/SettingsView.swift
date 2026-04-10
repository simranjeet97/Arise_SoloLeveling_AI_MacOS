import SwiftUI

struct SettingsView: View {
    
    // Auth State
    @State private var googleKey: String = ""
    @State private var showSaveSuccess = false
    
    // Preferences
    // Preferences
    @AppStorage("voiceEngine") private var voiceEngine = "AVSpeech"
    @AppStorage("isVoiceEnabled") private var isVoiceEnabled = true
    @AppStorage("morningNotification") private var morningNotification = true
    @AppStorage("eveningNotification") private var eveningNotification = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @State private var showResetConfirmation = false
    
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            VisualEffectView.hudDark.ignoresSafeArea()
            Color.black.opacity(0.4).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SYSTEM SETTINGS")
                        .font(Theme.mono(16, weight: .black))
                        .foregroundColor(Theme.textDisabled)
                        .tracking(4)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textDisabled)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        
                        // API Configuration
                        VStack(alignment: .leading, spacing: 16) {
                            Text("API CONFIGURATION")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundColor(Theme.accentPurple)
                            
                            VStack(spacing: 12) {
                            customSecureField(title: "Google API Key (Gemini)", text: $googleKey)
                                
                                Button(action: saveKeys) {
                                    HStack(spacing: 8) {
                                        if showSaveSuccess {
                                            Image(systemName: "checkmark")
                                            Text("Keys Safely Stored")
                                        } else {
                                            Text("Save to Keychain")
                                        }
                                    }
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundColor(showSaveSuccess ? Theme.accentGreen : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgCard))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(showSaveSuccess ? Theme.accentGreen : Theme.borderDim))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Voice Engine
                        VStack(alignment: .leading, spacing: 16) {
                            Text("VOICE ENGINE")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundColor(Theme.accentPurple)
                            
                            Toggle("Voice Responses Enabled", isOn: $isVoiceEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Theme.accentPurple))
                            
                            Picker("", selection: $voiceEngine) {
                                Text("AVSpeechSynthesizer (Free)").tag("AVSpeech")
                                Text("ElevenLabs (Premium)").tag("ElevenLabs")
                            }
                            .pickerStyle(.radioGroup)
                            .font(Theme.label(13))
                            .disabled(!isVoiceEnabled)
                            .opacity(isVoiceEnabled ? 1.0 : 0.5)
                        }
                        
                        // App Automation
                        VStack(alignment: .leading, spacing: 16) {
                            Text("AUTOMATION")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundColor(Theme.accentPurple)
                            
                            Toggle("Morning Awakening Alert (7:30 AM)", isOn: $morningNotification)
                                .toggleStyle(SwitchToggleStyle(tint: Theme.accentPurple))
                            
                            Toggle("Evening Wind-down Alert (10:00 PM)", isOn: $eveningNotification)
                                .toggleStyle(SwitchToggleStyle(tint: Theme.accentPurple))
                        }
                        
                        // Data Operations
                        VStack(alignment: .leading, spacing: 16) {
                            Text("DATA OPERATIONS")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundColor(Theme.accentRed)
                            
                            Button(action: exportData) {
                                Label("Export System Data (JSON)", systemImage: "square.and.arrow.up")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgCard))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderDim))
                            }
                            .buttonStyle(.plain)

                            Button(action: { showResetConfirmation = true }) {
                                Label("System Reawakening (Factory Reset)", systemImage: "flame.fill")
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundColor(Theme.accentRed)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bgCard))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accentRed.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .alert("System Reawakening", isPresented: $showResetConfirmation) {
                                Button("Cancel", role: .cancel) { }
                                Button("Confirm Wipe", role: .destructive) { factoryReset() }
                            } message: {
                                Text("This will permanently delete all your stats, quests, and journal entries. You will return to Level 1 and re-enter Onboarding.")
                            }
                        }
                        
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            googleKey = KeychainService.shared.load(key: KeychainService.googleKey) ?? ""
        }
    }
    
    // MARK: - Subviews
    
    private func customSecureField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label(11))
                .foregroundColor(Theme.textDisabled)
            
            SecureField("sk-...", text: text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(Theme.mono(13))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderDim))
        }
    }
    
    // MARK: - Actions
    
    private func saveKeys() {
        if !googleKey.isEmpty { KeychainService.shared.save(key: KeychainService.googleKey, value: googleKey) }
        
        withAnimation { showSaveSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaveSuccess = false }
        }
    }
    
    private func factoryReset() {
        do {
            try DatabaseService.shared.resetSystem()
            hasCompletedOnboarding = false
            onDismiss()
        } catch {
            print("[Settings] Failed to factory reset: \(error)")
        }
    }
    
    private func exportData() {
        let db = DatabaseService.shared
        do {
            let stats = try db.fetchStats()
            let quests = try db.fetchAllQuests()
            let journals = try db.fetchJournalEntries(limit: 1000)
            let masteries = try db.fetchAllMasteries()
            let streaks = try db.fetchAllStreaks()
            
            struct ExportPayload: Encodable {
                let stats: PlayerStats?
                let quests: [Quest]
                let journals: [JournalEntry]
                let masteries: [DungeonMastery]
                let streaks: [QuestStreak]
            }
            
            let payload = ExportPayload(stats: stats, quests: quests, journals: journals, masteries: masteries, streaks: streaks)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let data = try encoder.encode(payload)
            
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "arise_system_export.json"
            
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            print("[Settings] Failed to export data: \(error)")
        }
    }
}
