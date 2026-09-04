import SwiftUI

struct PhotoPostDetailView: View {
  @State private var model: PhotoPostDetailViewModel
  @State private var selectedImageIndex = 0

  init(postID: Int, service: any PhotoPostDetailServing) {
    _model = State(initialValue: PhotoPostDetailViewModel(postID: postID, service: service))
  }

  var body: some View {
    Group {
      switch model.state {
      case .idle, .loading:
        ProgressView("사진을 불러오는 중…")
      case .failed(let message):
        ContentUnavailableView {
          Label("사진을 불러오지 못했어요", systemImage: "wifi.exclamationmark")
        } description: {
          Text(message)
        } actions: {
          Button("다시 시도") { Task { await model.retry() } }
            .buttonStyle(.borderedProminent)
        }
      case .loaded(let detail):
        loadedContent(detail)
      }
    }
    .navigationTitle("사진")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if case .loaded(let detail) = model.state, let shareURL = detail.shareURL {
        ShareLink(item: shareURL) {
          Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("게시물 공유")
      }
    }
    .task { await model.loadIfNeeded() }
  }

  private func loadedContent(_ detail: PhotoPostDetail) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        titleSection(detail.post)

        PhotoDetailImagePager(
          images: detail.images,
          selectedIndex: $selectedImageIndex,
          fallbackTitle: detail.post.title
        )

        if let image = selectedImage(in: detail.images) {
          PhotoMetadataSection(image: image)
        }

        let bodyText = detail.post.content.nuboPlainText
        if !bodyText.isEmpty {
          Text(bodyText)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        }

        if !detail.tags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(detail.tags) { tag in
                Text("#\(tag.name)")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.tint)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 7)
                  .background(.tint.opacity(0.1), in: Capsule())
              }
            }
          }
        }

        footer(detail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
    }
    .background(Color.secondary.opacity(0.04))
  }

  private func titleSection(_ post: PhotoPost) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(post.title)
        .font(.title2.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("photo-detail-title")

      HStack(spacing: 10) {
        profileImage(for: post.writer)

        VStack(alignment: .leading, spacing: 2) {
          Text(post.writer.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          Text(post.submitted, format: .dateTime.year().month().day())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private func profileImage(for writer: PhotoPostWriter) -> some View {
    if let profileURL = writer.profileURL {
      AsyncImage(url: profileURL) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.tertiary)
        }
      }
      .frame(width: 42, height: 42)
      .clipShape(Circle())
      .accessibilityLabel("\(writer.name) 프로필 사진")
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .foregroundStyle(.tertiary)
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
  }

  private func footer(_ detail: PhotoPostDetail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 18) {
        metric("heart", value: detail.post.likeCount, name: "좋아요")
        metric("bubble.right", value: detail.post.commentCount, name: "댓글")
        metric("eye", value: detail.post.viewCount, name: "조회")
      }

      if let attachment = detail.attachments.first {
        Label {
          Text("첨부 파일 \(attachment.name)")
            .lineLimit(1)
            .truncationMode(.middle)
        } icon: {
          Image(systemName: "paperclip")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 4)
  }

  private func metric(_ systemImage: String, value: Int, name: String) -> some View {
    Label(value.formatted(.number.notation(.compactName)), systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityLabel("\(name) \(value)개")
  }

  private func selectedImage(in images: [PhotoPostImage]) -> PhotoPostImage? {
    guard images.indices.contains(selectedImageIndex) else { return nil }
    return images[selectedImageIndex]
  }
}

private struct PhotoDetailImagePager: View {
  let images: [PhotoPostImage]
  @Binding var selectedIndex: Int
  let fallbackTitle: String

  var body: some View {
    GeometryReader { geometry in
      Group {
        if images.isEmpty {
          missingPhoto
        } else {
          TabView(selection: $selectedIndex) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
              detailImage(image, index: index, size: geometry.size)
                .tag(index)
            }
          }
          .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .background(Color.secondary.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .aspectRatio(4 / 5, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("photo-detail-image-pager")
  }

  @ViewBuilder
  private func detailImage(_ image: PhotoPostImage, index: Int, size: CGSize) -> some View {
    if let url = image.largeURL ?? image.smallURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .empty:
          ProgressView().frame(width: size.width, height: size.height)
        case .success(let loadedImage):
          loadedImage
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
        case .failure:
          missingPhoto
        @unknown default:
          EmptyView()
        }
      }
      .accessibilityLabel(image.description.isEmpty ? fallbackTitle : image.description)
      .accessibilityValue("\(index + 1)/\(images.count)")
    } else {
      missingPhoto
    }
  }

  private var missingPhoto: some View {
    Image(systemName: "photo")
      .font(.largeTitle)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityLabel("사진을 표시할 수 없음")
  }
}

private struct PhotoMetadataSection: View {
  let image: PhotoPostImage

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !facts.isEmpty {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), alignment: .leading)], spacing: 10) {
          ForEach(facts) { fact in
            VStack(alignment: .leading, spacing: 2) {
              Text(fact.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
              Text(fact.value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
          }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
      }

      if !image.description.isEmpty {
        Label {
          Text(image.description).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "sparkles").foregroundStyle(.tint)
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("사진 설명: \(image.description)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var facts: [PhotoFact] {
    let exif = image.exif
    var values: [PhotoFact] = []
    let camera = [exif.make, exif.model].filter { !$0.isEmpty }.joined(separator: " ")
    if !camera.isEmpty {
      values.append(PhotoFact(label: "카메라", value: camera))
    }
    if let focalLength = exif.focalLength {
      values.append(PhotoFact(label: "초점 거리", value: "\(focalLength)mm"))
    }
    if let aperture = exif.aperture {
      let value = Double(aperture) / 100
      values.append(
        PhotoFact(
          label: "조리개",
          value: "f/\(value.formatted(.number.precision(.fractionLength(0...2))))"
        )
      )
    }
    if let exposure = exif.exposure {
      let value = Double(exposure) / 1_000
      values.append(
        PhotoFact(
          label: "노출",
          value: "\(value.formatted(.number.precision(.fractionLength(0...3))))ms"
        )
      )
    }
    if let iso = exif.iso {
      values.append(PhotoFact(label: "감도", value: "ISO \(iso)"))
    }
    if let width = exif.width, let height = exif.height {
      values.append(PhotoFact(label: "크기", value: "\(width) × \(height)"))
    }
    return values
  }
}

private struct PhotoFact: Identifiable {
  let label: String
  let value: String
  var id: String { label }
}

extension String {
  fileprivate var nuboPlainText: String {
    replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"(?i)</(?:p|div)>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
