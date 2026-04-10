import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("playerName") private var playerName = ""
    @AppStorage("playerGoal") private var playerGoal = "Career Edge"
    @AppStorage("playerExperience") private var playerExperience = "Novice"

    @State private var appear = false
    
    private let goals = ["Career Edge", "Health & Physique", "Equilibrium (Both)"]
    private let experiences = ["Novice", "Intermediate", "Senior Hunter"]
    
    var body: some View {
        ZStack {
            ARISEWindowBackground()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Welcome Title
                VStack(spacing: 8) {
                    Text("THE SYSTEM HAS CHOSEN YOU")
                        .font(Theme.rounded(28, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: Theme.accentPurple.opacity(0.8), radius: 10)
                        .tracking(2)
                    
                    Text("Initialize your profile to unlock daily growth dungeons.")
                        .font(Theme.mono(12))
                        .foregroundColor(Theme.accentPurple.opacity(0.8))
                }
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 20)
                
                // Form
                VStack(alignment: .leading, spacing: 20) {
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("HUNTER ALIAS")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundColor(Theme.textDisabled)
                        
                        TextField("Enter your name", text: $playerName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(Theme.label(16))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Theme.bgCard)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderDim))
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PRIMARY GOAL")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundColor(Theme.textDisabled)
                        
                        Picker("", selection: $playerGoal) {
                            ForEach(goals, id: \.self) { goal in
                                Text(goal).tag(goal)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CURRENT REAL-WORLD RANK")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundColor(Theme.textDisabled)
                        
                        Picker("", selection: $playerExperience) {
                            ForEach(experiences, id: \.self) { exp in
                                Text(exp).tag(exp)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                .frame(maxWidth: 400)
                .padding(30)
                .background(ARISECardBackground(radius: 16))
                .opacity(appear ? 1.0 : 0.0)
                .offset(y: appear ? 0 : 20)
                
                Spacer()
                
                Button {
                    withAnimation(.easeOut) {
                        if playerName.isEmpty { playerName = "Hunter" }
                        hasCompletedOnboarding = true
                    }
                    VoiceOutputService.shared.speak("Welcome to the System, \(playerName).")
                } label: {
                    Text("INITIALIZE SYSTEM")
                        .font(Theme.mono(14, weight: .black))
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .frame(maxWidth: 400)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AnyShapeStyle(Theme.gradientPurpleBlue))
                                .shadow(color: Theme.accentPurple.opacity(0.4), radius: 10, y: 3)
                        )
                }
                .buttonStyle(.plain)
                .opacity(appear ? 1.0 : 0.0)
                
                Spacer().frame(height: 20)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                appear = true
            }
            VoiceOutputService.shared.speak("The System has chosen you.")
        }
    }
}
