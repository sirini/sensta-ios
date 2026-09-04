import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "camera.aperture")
        .font(.system(size: 48))
        .accessibilityHidden(true)

      Text("SENSTA")
        .font(.largeTitle.bold())

      Text("사진으로 이어지는 커뮤니티")
        .foregroundStyle(.secondary)
    }
    .padding()
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  ContentView()
}
