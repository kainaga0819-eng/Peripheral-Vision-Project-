//  ContentView.swift
//  Retina Detachment Project
//
//  Main app coordinator that manages navigation between different screens
//  and the immersive peripheral vision testing experience.

import SwiftUI
import RealityKit
import simd
import UIKit

struct ContentView: View {
    @State private var gameState: GameState = .mainMenu
    @StateObject private var dataManager = TestDataManager()
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            switch gameState {
            case .mainMenu:
                MainMenuView(gameState: $gameState)
                    .environmentObject(dataManager)
                
            case .settings:
                SettingsView(gameState: $gameState)
                
            case .testing:
                TestPrepView(gameState: $gameState)
                    .environmentObject(dataManager)
                
            case .results:
                ResultsView(gameState: $gameState)
                    .environmentObject(dataManager)
            }
        }
    }
}

struct TestPrepView: View {
    @Binding var gameState: GameState
    @EnvironmentObject var dataManager: TestDataManager
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showingImmersive = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.green.opacity(0.8), Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("Ready to Test?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("This will open an immersive testing environment")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 20) {
                    Button("Start Immersive Test") {
                        startImmersiveTest()
                    }
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                    .shadow(radius: 5)
                    
                    Button("Back to Menu") {
                        gameState = .mainMenu
                    }
                    .font(.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func startImmersiveTest() {
        Task {
            let result = await openImmersiveSpace(id: "ImmersiveSpace")
            if case .opened = result {
                showingImmersive = true
                dismissWindow(id: "MainWindow")
            }
        }
    }
}


#Preview(windowStyle: .automatic) { ContentView() }
