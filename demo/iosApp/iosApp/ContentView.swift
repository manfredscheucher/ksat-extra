import SwiftUI
import Demo

// The ksat demo is plain Kotlin that returns a String; show it in a monospaced, scrollable view.
struct ContentView: View {
    var body: some View {
        ScrollView {
            Text(DemoKt.iosDemoReport())
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
