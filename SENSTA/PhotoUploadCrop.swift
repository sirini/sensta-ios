import SwiftUI
import UIKit

struct PhotoUploadCrop: Equatable, Hashable, Sendable {
  static let full = PhotoUploadCrop(x: 0, y: 0, width: 1, height: 1)

  let x: Double
  let y: Double
  let width: Double
  let height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    let minimumX = min(max(x, 0), 1)
    let minimumY = min(max(y, 0), 1)
    self.x = minimumX
    self.y = minimumY
    self.width = min(max(width, 0), 1 - minimumX)
    self.height = min(max(height, 0), 1 - minimumY)
  }

  init(normalizedRect: CGRect) {
    self.init(
      x: Double(normalizedRect.minX), y: Double(normalizedRect.minY),
      width: Double(normalizedRect.width), height: Double(normalizedRect.height))
  }

  var normalizedRect: CGRect {
    CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
  }

  var isFull: Bool {
    let tolerance = 0.000_001
    return abs(x) < tolerance && abs(y) < tolerance
      && abs(width - 1) < tolerance && abs(height - 1) < tolerance
  }

  static func centered(
    for aspect: PhotoUploadCropAspect, sourceSize: CGSize
  ) -> PhotoUploadCrop {
    guard let ratio = aspect.normalizedRatio(for: sourceSize), ratio > 0 else {
      return PhotoUploadCrop(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    }
    if ratio >= 1 {
      let height = 1 / ratio
      return PhotoUploadCrop(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }
    let width = ratio
    return PhotoUploadCrop(x: (1 - width) / 2, y: 0, width: width, height: 1)
  }

  func moved(byX deltaX: Double, y deltaY: Double) -> PhotoUploadCrop {
    PhotoUploadCrop(
      x: min(max(x + deltaX, 0), 1 - width),
      y: min(max(y + deltaY, 0), 1 - height),
      width: width, height: height)
  }

  func resized(
    from corner: PhotoUploadCropCorner, to point: CGPoint,
    aspect: PhotoUploadCropAspect, sourceSize: CGSize
  ) -> PhotoUploadCrop {
    let normalizedX = min(max(Double(point.x), 0), 1)
    let normalizedY = min(max(Double(point.y), 0), 1)
    let anchorX = corner.isLeading ? x + width : x
    let anchorY = corner.isTop ? y + height : y
    let horizontalDirection = corner.isLeading ? -1.0 : 1.0
    let verticalDirection = corner.isTop ? -1.0 : 1.0
    let availableWidth = horizontalDirection < 0 ? anchorX : 1 - anchorX
    let availableHeight = verticalDirection < 0 ? anchorY : 1 - anchorY
    let requestedWidth = min(abs(normalizedX - anchorX), availableWidth)
    let requestedHeight = min(abs(normalizedY - anchorY), availableHeight)
    let minimumLength = 0.08

    let newWidth: Double
    let newHeight: Double
    if let ratio = aspect.normalizedRatio(for: sourceSize), ratio > 0 {
      let maximumWidth = min(availableWidth, availableHeight * ratio)
      let minimumWidth = min(max(minimumLength, minimumLength * ratio), maximumWidth)
      newWidth = min(max(max(requestedWidth, requestedHeight * ratio), minimumWidth), maximumWidth)
      newHeight = newWidth / ratio
    } else {
      newWidth = min(max(requestedWidth, minimumLength), availableWidth)
      newHeight = min(max(requestedHeight, minimumLength), availableHeight)
    }

    return PhotoUploadCrop(
      x: horizontalDirection < 0 ? anchorX - newWidth : anchorX,
      y: verticalDirection < 0 ? anchorY - newHeight : anchorY,
      width: newWidth, height: newHeight)
  }
}

enum PhotoUploadCropCorner: Sendable {
  case topLeading
  case topTrailing
  case bottomLeading
  case bottomTrailing

  var isLeading: Bool {
    self == .topLeading || self == .bottomLeading
  }

  var isTop: Bool {
    self == .topLeading || self == .topTrailing
  }

  var label: String {
    switch self {
    case .topLeading: "왼쪽 위"
    case .topTrailing: "오른쪽 위"
    case .bottomLeading: "왼쪽 아래"
    case .bottomTrailing: "오른쪽 아래"
    }
  }
}

enum PhotoUploadCropAspect: String, CaseIterable, Identifiable, Sendable {
  case original
  case portrait45
  case portrait34
  case free

  var id: String { rawValue }

  var label: String {
    switch self {
    case .original: "원본"
    case .portrait45: "4:5"
    case .portrait34: "3:4"
    case .free: "자유"
    }
  }

  func normalizedRatio(for sourceSize: CGSize) -> Double? {
    guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
    let sourceRatio = Double(sourceSize.width / sourceSize.height)
    let outputRatio: Double
    switch self {
    case .original:
      outputRatio = sourceRatio
    case .portrait45:
      outputRatio = 4 / 5
    case .portrait34:
      outputRatio = 3 / 4
    case .free:
      return nil
    }
    return outputRatio / sourceRatio
  }
}

struct PhotoUploadCropView: View {
  let image: UIImage
  let onApply: @MainActor (PhotoUploadCrop?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var crop: PhotoUploadCrop
  @State private var aspect: PhotoUploadCropAspect

  init(
    image: UIImage, initialCrop: PhotoUploadCrop?,
    onApply: @escaping @MainActor (PhotoUploadCrop?) -> Void
  ) {
    self.image = image
    self.onApply = onApply
    _crop = State(initialValue: initialCrop ?? .full)
    _aspect = State(initialValue: initialCrop == nil ? .original : .free)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        PhotoUploadCropCanvas(image: image, crop: $crop, aspect: aspect)
          .aspectRatio(0.82, contentMode: .fit)
          .accessibilityIdentifier("photo-crop-canvas")
          .accessibilityValue(cropAccessibilityValue)

        aspectSelector

        Text("프레임을 옮기거나 네 모서리를 끌어 자를 영역을 정하세요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .navigationTitle("사진 자르기")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("적용") {
            onApply(crop.isFull ? nil : crop)
            dismiss()
          }
          .accessibilityIdentifier("photo-crop-apply")
        }
      }
    }
  }

  private var aspectSelector: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("비율").font(.headline)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(PhotoUploadCropAspect.allCases) { option in
            Button(option.label) { selectAspect(option) }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
              .tint(aspect == option ? .accentColor : .secondary)
              .accessibilityAddTraits(aspect == option ? .isSelected : [])
              .accessibilityIdentifier("photo-crop-aspect-\(option.rawValue)")
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var cropAccessibilityValue: String {
    let width = Int((crop.width * 100).rounded())
    let height = Int((crop.height * 100).rounded())
    return "원본의 가로 \(width)퍼센트, 세로 \(height)퍼센트"
  }

  private func selectAspect(_ option: PhotoUploadCropAspect) {
    aspect = option
    if option == .free, !crop.isFull { return }
    crop = PhotoUploadCrop.centered(for: option, sourceSize: image.size)
  }
}

private struct PhotoUploadCropCanvas: View {
  let image: UIImage
  @Binding var crop: PhotoUploadCrop
  let aspect: PhotoUploadCropAspect
  @State private var moveStart: PhotoUploadCrop?
  @State private var resizeStart: PhotoUploadCrop?

  var body: some View {
    GeometryReader { proxy in
      let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 16, dy: 16)
      let imageFrame = fittedFrame(imageSize: image.size, in: bounds)
      let cropFrame = displayedCropFrame(in: imageFrame)

      ZStack {
        Color.black
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: imageFrame.width, height: imageFrame.height)
          .position(x: imageFrame.midX, y: imageFrame.midY)

        cropMask(imageFrame: imageFrame, cropFrame: cropFrame)
        cropGrid(cropFrame)

        Color.clear
          .contentShape(Rectangle())
          .frame(width: cropFrame.width, height: cropFrame.height)
          .position(x: cropFrame.midX, y: cropFrame.midY)
          .gesture(moveGesture(in: imageFrame))
          .accessibilityHidden(true)

        Rectangle()
          .stroke(.white, lineWidth: 2)
          .frame(width: cropFrame.width, height: cropFrame.height)
          .position(x: cropFrame.midX, y: cropFrame.midY)
          .allowsHitTesting(false)

        cropHandle(.topLeading, at: CGPoint(x: cropFrame.minX, y: cropFrame.minY), in: imageFrame)
        cropHandle(.topTrailing, at: CGPoint(x: cropFrame.maxX, y: cropFrame.minY), in: imageFrame)
        cropHandle(
          .bottomLeading, at: CGPoint(x: cropFrame.minX, y: cropFrame.maxY), in: imageFrame)
        cropHandle(
          .bottomTrailing, at: CGPoint(x: cropFrame.maxX, y: cropFrame.maxY), in: imageFrame)
      }
      .coordinateSpace(name: "photoCropCanvas")
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
  }

  private func fittedFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
  }

  private func displayedCropFrame(in imageFrame: CGRect) -> CGRect {
    CGRect(
      x: imageFrame.minX + CGFloat(crop.x) * imageFrame.width,
      y: imageFrame.minY + CGFloat(crop.y) * imageFrame.height,
      width: CGFloat(crop.width) * imageFrame.width,
      height: CGFloat(crop.height) * imageFrame.height)
  }

  private func cropMask(imageFrame: CGRect, cropFrame: CGRect) -> some View {
    Path { path in
      path.addRect(imageFrame)
      path.addRect(cropFrame)
    }
    .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
    .allowsHitTesting(false)
  }

  private func cropGrid(_ cropFrame: CGRect) -> some View {
    Path { path in
      for part in 1...2 {
        let fraction = CGFloat(part) / 3
        let x = cropFrame.minX + cropFrame.width * fraction
        let y = cropFrame.minY + cropFrame.height * fraction
        path.move(to: CGPoint(x: x, y: cropFrame.minY))
        path.addLine(to: CGPoint(x: x, y: cropFrame.maxY))
        path.move(to: CGPoint(x: cropFrame.minX, y: y))
        path.addLine(to: CGPoint(x: cropFrame.maxX, y: y))
      }
    }
    .stroke(.white.opacity(0.7), lineWidth: 0.7)
    .allowsHitTesting(false)
  }

  private func cropHandle(
    _ corner: PhotoUploadCropCorner, at position: CGPoint, in imageFrame: CGRect
  ) -> some View {
    ZStack {
      Circle().fill(.black.opacity(0.45)).frame(width: 22, height: 22)
      Circle().stroke(.white, lineWidth: 3).frame(width: 16, height: 16)
    }
    .frame(width: 44, height: 44)
    .contentShape(Rectangle())
    .position(position)
    .gesture(resizeGesture(from: corner, in: imageFrame))
    .accessibilityLabel("\(corner.label) 자르기 조절점")
  }

  private func moveGesture(in imageFrame: CGRect) -> some Gesture {
    DragGesture(coordinateSpace: .named("photoCropCanvas"))
      .onChanged { value in
        if moveStart == nil { moveStart = crop }
        guard let moveStart, imageFrame.width > 0, imageFrame.height > 0 else { return }
        crop = moveStart.moved(
          byX: Double(value.translation.width / imageFrame.width),
          y: Double(value.translation.height / imageFrame.height))
      }
      .onEnded { _ in moveStart = nil }
  }

  private func resizeGesture(
    from corner: PhotoUploadCropCorner, in imageFrame: CGRect
  ) -> some Gesture {
    DragGesture(coordinateSpace: .named("photoCropCanvas"))
      .onChanged { value in
        if resizeStart == nil { resizeStart = crop }
        guard let resizeStart, imageFrame.width > 0, imageFrame.height > 0 else { return }
        let point = CGPoint(
          x: (value.location.x - imageFrame.minX) / imageFrame.width,
          y: (value.location.y - imageFrame.minY) / imageFrame.height)
        crop = resizeStart.resized(
          from: corner, to: point, aspect: aspect, sourceSize: image.size)
      }
      .onEnded { _ in resizeStart = nil }
  }
}
