import SwiftUI
import UIKit

struct PhotoViewer: View {
  let images: [PhotoPostImage]
  @Binding var selectedImageID: Int?
  let title: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      TabView(selection: $selectedImageID) {
        ForEach(images) { image in
          PhotoViewerPage(image: image, title: title, isActive: selectedImageID == image.id)
            .tag(Optional(image.id))
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(.black)
      .navigationTitle("\(selectedIndex + 1) / \(images.count)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("닫기", systemImage: "xmark") { dismiss() }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("photo-viewer-close")
        }
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 24) {
            Button("이전 사진", systemImage: "chevron.left") { select(offset: -1) }
              .disabled(selectedIndex == 0)
            Button("다음 사진", systemImage: "chevron.right") { select(offset: 1) }
              .disabled(selectedIndex >= images.count - 1)
          }
          .labelStyle(.iconOnly)
        }
      }
    }
    .preferredColorScheme(.dark)
    .accessibilityIdentifier("photo-viewer")
  }

  private var selectedIndex: Int {
    images.firstIndex { $0.id == selectedImageID } ?? 0
  }

  private func select(offset: Int) {
    let index = selectedIndex + offset
    guard images.indices.contains(index) else { return }
    selectedImageID = images[index].id
  }
}

private struct PhotoViewerPage: View {
  let image: PhotoPostImage
  let title: String
  let isActive: Bool
  @State private var decodedImage: UIImage?
  @State private var failed = false
  @State private var attempt = 0
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { geometry in
      Group {
        if let decodedImage {
          ZoomablePhoto(
            image: decodedImage, label: image.description.isEmpty ? title : image.description,
            isActive: isActive)
        } else if failed {
          ContentUnavailableView {
            Label("사진을 불러오지 못했어요", systemImage: "photo")
          } actions: {
            Button("다시 시도") { attempt += 1 }
          }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .task(id: attempt) {
        failed = false
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--ui-test-viewer") {
            decodedImage = PhotoViewerTestImage.make()
            return
          }
        #endif
        guard let url = image.largeURL ?? image.smallURL else {
          failed = true
          return
        }
        do {
          let decoded = try await PhotoImagePipeline.shared.image(
            for: url, targetSize: geometry.size, displayScale: displayScale)
          try Task.checkCancellation()
          decodedImage = decoded.image
        } catch is CancellationError {
          return
        } catch {
          failed = true
        }
      }
    }
  }
}

struct ZoomablePhoto: UIViewRepresentable {
  let image: UIImage
  let label: String
  let isActive: Bool

  func makeUIView(context: Context) -> PhotoZoomScrollView {
    let view = PhotoZoomScrollView()
    view.setImage(image)
    return view
  }

  func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
    view.accessibilityLabel = label
    view.setImage(image)
    if !isActive { view.setZoomScale(1, animated: false) }
  }
}

final class PhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
  private let photo = UIImageView()
  private var viewportSize = CGSize.zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
    minimumZoomScale = 1
    maximumZoomScale = 4
    showsHorizontalScrollIndicator = false
    showsVerticalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    backgroundColor = .black
    photo.contentMode = .scaleAspectFit
    addSubview(photo)
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
    doubleTap.numberOfTapsRequired = 2
    addGestureRecognizer(doubleTap)
    isAccessibilityElement = true
    accessibilityTraits = .image
    accessibilityIdentifier = "photo-zoom-view"
    accessibilityHint = "두 번 탭하거나 두 손가락으로 확대할 수 있습니다."
    accessibilityCustomActions = [
      UIAccessibilityCustomAction(
        name: "사진 확대", target: self, selector: #selector(accessibleZoomIn)),
      UIAccessibilityCustomAction(
        name: "전체 사진 보기", target: self, selector: #selector(accessibleZoomOut)),
    ]
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setImage(_ image: UIImage) {
    guard photo.image !== image else { return }
    setZoomScale(1, animated: false)
    photo.image = image
    viewportSize = .zero
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != viewportSize, bounds.width > 0, bounds.height > 0 {
      viewportSize = bounds.size
      setZoomScale(1, animated: false)
      let size = photo.image?.size ?? bounds.size
      let scale = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
      photo.frame = CGRect(
        origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
      contentSize = photo.frame.size
    }
    centerPhoto()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

  private func centerPhoto() {
    contentInset = UIEdgeInsets(
      top: max((bounds.height - photo.frame.height) / 2, 0),
      left: max((bounds.width - photo.frame.width) / 2, 0),
      bottom: max((bounds.height - photo.frame.height) / 2, 0),
      right: max((bounds.width - photo.frame.width) / 2, 0))
    accessibilityValue = "\(Int(zoomScale * 100))%"
  }

  @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
    if zoomScale > 1.01 {
      setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled)
    } else {
      let point = gesture.location(in: photo)
      let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
      zoom(
        to: CGRect(
          x: point.x - size.width / 2, y: point.y - size.height / 2,
          width: size.width, height: size.height), animated: !UIAccessibility.isReduceMotionEnabled)
    }
  }

  @objc private func accessibleZoomIn() -> Bool {
    setZoomScale(2.5, animated: !UIAccessibility.isReduceMotionEnabled)
    return true
  }

  @objc private func accessibleZoomOut() -> Bool {
    setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled)
    return true
  }
}

#if DEBUG
  enum PhotoViewerTestImage {
    static func make() -> UIImage {
      UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        UIColor.white.setStroke()
        context.cgContext.setLineWidth(10)
        context.stroke(CGRect(x: 10, y: 10, width: 880, height: 580))
      }
    }
  }
#endif
