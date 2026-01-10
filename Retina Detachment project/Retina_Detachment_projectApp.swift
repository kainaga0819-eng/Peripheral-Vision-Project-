import SwiftUI
import RealityKit

@main
struct Retina_Detachment_projectApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup(id: "MainWindow") {
            SimpleContentView()
        }
        .windowStyle(.automatic)

        ImmersiveSpace(id: "ImmersiveSpace") {
            SimpleImmersiveView()
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
