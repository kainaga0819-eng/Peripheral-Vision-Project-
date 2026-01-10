import SwiftUI

struct SimpleContentView: View {
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Peripheral Vision Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Welcome to the peripheral vision testing app!")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Start test button
            Button("Start Test") {
                handleTap()
            }
            .font(.title)
            .fontWeight(.bold)
            .padding(.horizontal, 50)
            .padding(.vertical, 25)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(20)
            
            VStack(spacing: 15) {
                Button("Settings") {
                    showAlert("Settings feature coming soon!")
                }
                .padding()
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Results") {
                    showAlert("Results feature coming soon!")
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .alert("Info", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func handleTap() {
        print("Starting peripheral vision test...")

        // Open immersive space
        Task {
            print("Opening immersive space...")
            let result = await openImmersiveSpace(id: "ImmersiveSpace")
            print("Immersive space result: \(result)")

            // Dismiss the main window if immersive space opened successfully
            if case .opened = result {
                dismissWindow(id: "MainWindow")
                print("Main window dismissed")
            }
        }
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    SimpleContentView()
}