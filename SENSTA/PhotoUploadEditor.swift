import CoreImage
import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PhotoUploadFilter: String, CaseIterable, Identifiable, Sendable {
  case original
  case vivid
  case warm
  case cool
  case film
  case mono

  var id: String { rawValue }

  var label: String {
    switch self {
    case .original: "원본"
    case .vivid: "선명"
    case .warm: "따뜻함"
    case .cool: "차가움"
    case .film: "필름"
    case .mono: "흑백"
    }
  }
}

struct PhotoUploadEdits: Equatable, Hashable, Sendable {
  var crop: PhotoUploadCrop?
  var rotationQuarterTurns = 0
  var isMirrored = false
  var filter: PhotoUploadFilter = .original
  var filterIntensity = 1.0

  var rotationDegrees: Double { Double(rotationQuarterTurns * 90) }

  var needsRendering: Bool {
    crop != nil || rotationQuarterTurns != 0 || isMirrored
      || (filter != .original && filterIntensity > 0)
  }

  mutating func setCrop(_ crop: PhotoUploadCrop?) {
    self.crop = crop?.isFull == true ? nil : crop
  }

  mutating func rotateClockwise() {
    rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
  }

  mutating func toggleMirror() { isMirrored.toggle() }

  mutating func selectFilter(_ filter: PhotoUploadFilter) { self.filter = filter }

  mutating func setFilterIntensity(_ intensity: Double) {
    filterIntensity = min(max(intensity, 0), 1)
  }

  mutating func reset() { self = PhotoUploadEdits() }
}

enum PhotoUploadRenderer {
  static func render(_ photo: PreparedUploadPhoto, edits: PhotoUploadEdits) throws
    -> PreparedUploadPhoto
  {
    try Task.checkCancellation()
    guard edits.needsRendering else {
      return PreparedUploadPhoto(
        id: photo.id, fileURL: photo.sourceFileURL, previewData: photo.sourcePreviewData,
        byteCount: photo.sourceByteCount, sourceFileURL: photo.sourceFileURL,
        sourcePreviewData: photo.sourcePreviewData, sourceByteCount: photo.sourceByteCount,
        edits: edits)
    }

    let image = try makeImage(fileURL: photo.sourceFileURL, edits: edits, maximumPixelSize: nil)
    try Task.checkCancellation()
    let outputURL = FileManager.default.temporaryDirectory
      .appending(path: "sensta-edit-\(photo.id.uuidString)-\(UUID().uuidString).jpg")
    do {
      try writeJPEG(image, to: outputURL, copyingMetadataFrom: photo.sourceFileURL)
      let previewData = try makePreviewData(
        fileURL: outputURL, edits: PhotoUploadEdits(), maximumPixelSize: 360)
      let byteCount = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      return PreparedUploadPhoto(
        id: photo.id, fileURL: outputURL, previewData: previewData, byteCount: byteCount,
        sourceFileURL: photo.sourceFileURL, sourcePreviewData: photo.sourcePreviewData,
        sourceByteCount: photo.sourceByteCount, edits: edits)
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      throw error
    }
  }

  static func makePreviewData(
    fileURL: URL, edits: PhotoUploadEdits, maximumPixelSize: Int
  ) throws -> Data {
    let image = try makeImage(
      fileURL: fileURL, edits: edits, maximumPixelSize: maximumPixelSize)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw PhotoUploadPreparationError.cannotWriteImage }
    CGImageDestinationAddImage(
      destination, image,
      [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw PhotoUploadPreparationError.cannotWriteImage
    }
    return data as Data
  }

  private static func makeImage(
    fileURL: URL, edits: PhotoUploadEdits, maximumPixelSize: Int?
  ) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
      throw PhotoUploadPreparationError.unreadableImage
    }
    let image: CGImage?
    if let maximumPixelSize {
      image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary)
    } else {
      image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    guard let image else { throw PhotoUploadPreparationError.unreadableImage }
    let cropped = try crop(image, to: edits.crop)
    let transformed = try transform(cropped, edits: edits)
    return try applyFilter(to: transformed, edits: edits)
  }

  private static func crop(_ source: CGImage, to crop: PhotoUploadCrop?) throws -> CGImage {
    guard let crop else { return source }
    let minimumX = floor(crop.x * Double(source.width))
    let minimumY = floor(crop.y * Double(source.height))
    let maximumX = ceil((crop.x + crop.width) * Double(source.width))
    let maximumY = ceil((crop.y + crop.height) * Double(source.height))
    let pixelRect = CGRect(
      x: CGFloat(max(0, minimumX)), y: CGFloat(max(0, minimumY)),
      width: CGFloat(min(Double(source.width), maximumX) - max(0, minimumX)),
      height: CGFloat(min(Double(source.height), maximumY) - max(0, minimumY)))
    guard pixelRect.width >= 1, pixelRect.height >= 1,
      let cropped = source.cropping(to: pixelRect.integral)
    else { throw PhotoUploadPreparationError.unreadableImage }
    return cropped
  }

  private static func transform(_ source: CGImage, edits: PhotoUploadEdits) throws -> CGImage {
    guard edits.rotationQuarterTurns != 0 || edits.isMirrored else { return source }
    let turns = edits.rotationQuarterTurns % 4
    let outputSize =
      turns.isMultiple(of: 2)
      ? CGSize(width: source.width, height: source.height)
      : CGSize(width: source.height, height: source.width)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
      let graphics = context.cgContext
      graphics.setFillColor(UIColor.white.cgColor)
      graphics.fill(CGRect(origin: .zero, size: outputSize))
      graphics.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
      graphics.rotate(by: CGFloat(turns) * .pi / 2)
      if edits.isMirrored { graphics.scaleBy(x: -1, y: 1) }
      UIImage(cgImage: source).draw(
        in: CGRect(
          x: -CGFloat(source.width) / 2, y: -CGFloat(source.height) / 2,
          width: CGFloat(source.width), height: CGFloat(source.height)))
    }
    guard let image = rendered.cgImage else { throw PhotoUploadPreparationError.unreadableImage }
    return image
  }

  private static func applyFilter(to source: CGImage, edits: PhotoUploadEdits) throws -> CGImage {
    guard edits.filter != .original, edits.filterIntensity > 0 else { return source }
    let matrix = colorMatrix(for: edits.filter, intensity: edits.filterIntensity)
    guard let filter = CIFilter(name: "CIColorMatrix") else {
      throw PhotoUploadPreparationError.unreadableImage
    }
    filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
    filter.setValue(CIVector(values: matrix[0], count: 4), forKey: "inputRVector")
    filter.setValue(CIVector(values: matrix[1], count: 4), forKey: "inputGVector")
    filter.setValue(CIVector(values: matrix[2], count: 4), forKey: "inputBVector")
    filter.setValue(CIVector(values: matrix[3], count: 4), forKey: "inputAVector")
    filter.setValue(
      CIVector(x: matrix[4][0], y: matrix[4][1], z: matrix[4][2], w: 0),
      forKey: "inputBiasVector")
    guard let output = filter.outputImage,
      let image = CIContext(options: [.cacheIntermediates: false])
        .createCGImage(output, from: output.extent)
    else { throw PhotoUploadPreparationError.unreadableImage }
    return image
  }

  private static func colorMatrix(
    for filter: PhotoUploadFilter, intensity: Double
  ) -> [[CGFloat]] {
    let identity: [[CGFloat]] = [
      [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1], [0, 0, 0, 0],
    ]
    let target: [[CGFloat]]
    switch filter {
    case .original:
      target = identity
    case .vivid:
      target = [
        [1.20, -0.05, -0.05, 0], [-0.05, 1.15, -0.05, 0], [-0.05, -0.05, 1.20, 0],
        [0, 0, 0, 1], [-5 / 255, -3 / 255, -5 / 255, 0],
      ]
    case .warm:
      target = [
        [1.08, 0.03, 0, 0], [0.01, 1.02, 0, 0], [0, 0, 0.90, 0], [0, 0, 0, 1],
        [3 / 255, 1 / 255, -2 / 255, 0],
      ]
    case .cool:
      target = [
        [0.92, 0, 0, 0], [0, 1.01, 0.02, 0], [0, 0.03, 1.10, 0], [0, 0, 0, 1],
        [-2 / 255, 0, 3 / 255, 0],
      ]
    case .film:
      target = [
        [0.92, 0.08, 0.03, 0], [0.04, 0.94, 0.07, 0], [0.02, 0.10, 0.84, 0],
        [0, 0, 0, 1], [5 / 255, 2 / 255, -3 / 255, 0],
      ]
    case .mono:
      target = [
        [0.213, 0.715, 0.072, 0], [0.213, 0.715, 0.072, 0],
        [0.213, 0.715, 0.072, 0], [0, 0, 0, 1], [0, 0, 0, 0],
      ]
    }
    let amount = CGFloat(min(max(intensity, 0), 1))
    return zip(identity, target).map { original, filtered in
      zip(original, filtered).map { base, value in base + (value - base) * amount }
    }
  }

  private static func writeJPEG(
    _ image: CGImage, to outputURL: URL, copyingMetadataFrom sourceURL: URL
  ) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw PhotoUploadPreparationError.cannotWriteImage }
    var properties: [CFString: Any] = [:]
    if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) {
      properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
    // 편집 출력에서도 촬영 정보는 유지하지만 공개할 수 없는 위치와 이전 방향값은 제거한다.
    properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
    properties[kCGImagePropertyOrientation] = 1
    properties[kCGImagePropertyPixelWidth] = image.width
    properties[kCGImagePropertyPixelHeight] = image.height
    properties[kCGImageDestinationLossyCompressionQuality] = 0.92
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw PhotoUploadPreparationError.cannotWriteImage
    }
  }
}

struct PhotoUploadEditorView: View {
  let photo: PreparedUploadPhoto
  let position: Int
  let totalCount: Int
  let onSave: @MainActor (PhotoUploadEdits) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var edits: PhotoUploadEdits
  @State private var isSaving = false
  @State private var isCropping = false
  @State private var cropPreviewImage: UIImage?

  init(
    photo: PreparedUploadPhoto, position: Int, totalCount: Int,
    onSave: @escaping @MainActor (PhotoUploadEdits) async -> Bool
  ) {
    self.photo = photo
    self.position = position
    self.totalCount = totalCount
    self.onSave = onSave
    _edits = State(initialValue: photo.edits)
    _cropPreviewImage = State(initialValue: UIImage(data: photo.sourcePreviewData))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          PhotoUploadRenderedPreview(
            fileURL: photo.sourceFileURL, edits: edits, maximumPixelSize: 1_200
          )
          .frame(maxWidth: .infinity)
          .aspectRatio(1, contentMode: .fit)
          .background(.black, in: RoundedRectangle(cornerRadius: 18))
          .clipShape(RoundedRectangle(cornerRadius: 18))
          .accessibilityLabel("편집 사진 미리보기")
          .accessibilityIdentifier("photo-editor-preview")

          editActions
          filterSelector
          intensitySlider
        }
        .padding(20)
      }
      .navigationTitle("사진 편집")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소") { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("완료") {
            isSaving = true
            Task {
              if await onSave(edits) { dismiss() }
              isSaving = false
            }
          }
          .disabled(isSaving)
          .accessibilityIdentifier("photo-editor-save")
        }
      }
      .overlay { if isSaving { ProgressView("편집 내용을 저장하는 중…") } }
      .interactiveDismissDisabled(isSaving)
      .task(id: photo.id) { await loadCropPreview() }
      .senstaScreenStyle()
      .fullScreenCover(isPresented: $isCropping) {
        if let image = cropPreviewImage {
          PhotoUploadCropView(image: image, initialCrop: edits.crop) { crop in
            edits.setCrop(crop)
          }
        }
      }
    }
  }

  private var editActions: some View {
    VStack(spacing: 10) {
      Text("\(position) / \(totalCount)").font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 8) {
        editorButton("자르기", systemImage: "crop", identifier: "photo-editor-crop") {
          isCropping = true
        }
        .disabled(cropPreviewImage == nil)
        .accessibilityValue(edits.crop == nil ? "원본 영역" : "자른 영역")
        editorButton("회전", systemImage: "rotate.right", identifier: "photo-editor-rotate") {
          edits.rotateClockwise()
        }
        editorButton(
          "좌우 반전", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
          identifier: "photo-editor-mirror"
        ) { edits.toggleMirror() }
        editorButton(
          "초기화", systemImage: "arrow.counterclockwise", identifier: "photo-editor-reset"
        ) { edits.reset() }
      }
    }
  }

  private func editorButton(
    _ title: String, systemImage: String, identifier: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: systemImage).font(.body)
        Text(title).font(.caption)
      }
      .frame(maxWidth: .infinity, minHeight: 48)
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier(identifier)
  }

  private func loadCropPreview() async {
    let data = try? await Task.detached(priority: .userInitiated) {
      try PhotoUploadRenderer.makePreviewData(
        fileURL: photo.sourceFileURL, edits: PhotoUploadEdits(), maximumPixelSize: 1_600)
    }.value
    guard !Task.isCancelled, let data, let image = UIImage(data: data) else { return }
    cropPreviewImage = image
  }

  private var filterSelector: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("필터").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(PhotoUploadFilter.allCases) { filter in
            Button {
              edits.selectFilter(filter)
            } label: {
              VStack(spacing: 6) {
                PhotoUploadRenderedPreview(
                  fileURL: photo.sourceFileURL,
                  edits: filterPreviewEdits(filter), maximumPixelSize: 150
                )
                .frame(width: 64, height: 64)
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(edits.filter == filter ? Color.accentColor : .clear, lineWidth: 3))
                Text(filter.label)
                  .font(.caption)
                  .fontWeight(edits.filter == filter ? .semibold : .regular)
              }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(edits.filter == filter ? .isSelected : [])
            .accessibilityIdentifier("photo-editor-filter-\(filter.rawValue)")
          }
        }
      }
    }
  }

  private var intensitySlider: some View {
    HStack {
      Text("강도").font(.subheadline)
      Slider(
        value: Binding(
          get: { edits.filterIntensity },
          set: { edits.setFilterIntensity($0) }), in: 0...1
      )
      .disabled(edits.filter == .original)
      .accessibilityIdentifier("photo-editor-intensity")
      Text(edits.filter == .original ? "0%" : "\(Int(edits.filterIntensity * 100))%")
        .font(.caption.monospacedDigit())
        .frame(width: 42, alignment: .trailing)
    }
  }

  private func filterPreviewEdits(_ filter: PhotoUploadFilter) -> PhotoUploadEdits {
    var preview = edits
    preview.filter = filter
    preview.filterIntensity = filter == .original ? 0 : 1
    return preview
  }
}

private struct PhotoUploadRenderedPreview: View {
  let fileURL: URL
  let edits: PhotoUploadEdits
  let maximumPixelSize: Int
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Color.clear
      if let image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        ProgressView().tint(.white)
      }
    }
    .task(id: edits) {
      let data = try? await Task.detached(priority: .userInitiated) {
        try PhotoUploadRenderer.makePreviewData(
          fileURL: fileURL, edits: edits, maximumPixelSize: maximumPixelSize)
      }.value
      guard !Task.isCancelled, let data, let rendered = UIImage(data: data) else { return }
      image = rendered
    }
  }
}
