import SwiftUI

struct PhotoPostDetailView: View {
  @Environment(\.accountSession) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var model: PhotoPostDetailViewModel
  @State private var selectedImageID: PhotoPostImage.ID?
  @State private var showsPhotoViewer = false
  @State private var showsReport = false
  @State private var showsEdit = false
  @State private var showsDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var deleteError: String?
  @State private var commentsScrollRequest = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let detailService: any PhotoPostDetailServing
  private let commentsService: any PhotoCommentsServing
  private let onChanged: @MainActor (PhotoPostChange) -> Void

  init(
    postID: Int, service: any PhotoPostDetailServing,
    onChanged: @escaping @MainActor (PhotoPostChange) -> Void = { _ in }
  ) {
    detailService = service
    commentsService = service
    self.onChanged = onChanged
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
        if account?.userSafety.states[detail.post.writer.id]?.isBlocked == true {
          ContentUnavailableView(
            "차단한 사용자의 사진입니다", systemImage: "photo.badge.exclamationmark",
            description: Text("차단을 해제하면 사진을 다시 볼 수 있습니다.")
          )
          .accessibilityIdentifier("photo-detail-blocked")
        } else {
          loadedContent(detail)
        }
      }
    }
    .navigationTitle("사진")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      if case .loaded(let detail) = model.state {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if detail.boardID != nil {
            Button("댓글로 이동", systemImage: "bubble.right") { commentsScrollRequest += 1 }
              .accessibilityIdentifier("photo-detail-comments")
          }
          if let shareURL = detail.shareURL {
            ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
              .accessibilityLabel("게시물 공유")
          }
          if canReport(detail.post) {
            Button {
              showsReport = true
            } label: {
              Image(
                systemName: account?.userSafety.states[detail.post.writer.id]?.isReported == true
                  ? "checkmark.circle" : "exclamationmark.bubble")
            }
            .disabled(
              account?.userSafety.states[detail.post.writer.id]?.isReported == true
                || account?.userSafety.states[detail.post.writer.id]?.isLoading == true
                || account?.userSafety.states[detail.post.writer.id]?.isMutating == true
            )
            .accessibilityLabel(
              account?.userSafety.states[detail.post.writer.id]?.isReported == true
                ? "신고 접수됨" : "사진 신고"
            )
            .accessibilityIdentifier("photo-detail-report")
          }
          if canManage(detail) {
            Menu {
              Button("사진 정보 수정", systemImage: "pencil") { showsEdit = true }
                .accessibilityIdentifier("photo-detail-edit")
              Button("사진 삭제", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
              }
              .accessibilityIdentifier("photo-detail-delete")
            } label: {
              if isDeleting {
                ProgressView()
              } else {
                Image(systemName: "ellipsis.circle")
              }
            }
            .disabled(isDeleting)
            .accessibilityLabel("내 사진 관리")
            .accessibilityIdentifier("photo-detail-owner-menu")
          }
        }
      }
    }
    .fullScreenCover(isPresented: $showsPhotoViewer) {
      if case .loaded(let detail) = model.state {
        PhotoViewer(
          images: detail.images, selectedImageID: $selectedImageID, title: detail.post.title)
      }
    }
    .sheet(isPresented: $showsReport) {
      if let account, let detail = loadedDetail {
        UserReportSheet(
          targetUserID: detail.post.writer.id, targetName: detail.post.writer.name,
          context: .photo(postID: detail.post.id), account: account)
      }
    }
    .sheet(isPresented: $showsEdit) {
      if let account, let detail = loadedDetail {
        PhotoPostEditSheet(detail: detail, account: account) {
          Task {
            await model.refresh()
            onChanged(.edited(detail.post.id))
          }
        }
      }
    }
    .confirmationDialog(
      "이 사진을 삭제할까요?", isPresented: $showsDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("사진 삭제", role: .destructive) {
        guard let detail = loadedDetail else { return }
        Task { await delete(detail) }
      }
      Button("취소", role: .cancel) {}
    } message: {
      Text("사진과 댓글, 좋아요 정보가 함께 삭제되며 되돌릴 수 없습니다.")
    }
    .alert(
      "사진을 삭제하지 못했어요",
      isPresented: Binding(
        get: { deleteError != nil },
        set: { if !$0 { deleteError = nil } })
    ) {
      Button("확인") { deleteError = nil }
    } message: {
      Text(deleteError ?? "잠시 뒤 다시 시도해 주세요.")
    }
    .task { await model.loadIfNeeded() }
    .task(id: safetyLoadID) {
      guard let account, let detail = loadedDetail, canReport(detail.post) else { return }
      await account.userSafety.load(targetUserID: detail.post.writer.id, using: account)
    }
    .senstaScreenStyle()
  }

  private var loadedDetail: PhotoPostDetail? {
    guard case .loaded(let detail) = model.state else { return nil }
    return detail
  }

  private var safetyLoadID: String {
    "\(account?.sessionIdentity.uuidString ?? "signed-out"):\(loadedDetail?.post.writer.id ?? 0)"
  }

  private func canReport(_ post: PhotoPost) -> Bool {
    guard let user = account?.user else { return false }
    return post.writer.id > 0 && post.writer.id != user.uid
  }

  private func canManage(_ detail: PhotoPostDetail) -> Bool {
    guard let user = account?.user else { return false }
    return detail.post.writer.id == user.uid && detail.boardID != nil
      && detail.categoryID != nil && [0, 2].contains(detail.status)
  }

  @MainActor
  private func delete(_ detail: PhotoPostDetail) async {
    guard let account, !isDeleting else { return }
    isDeleting = true
    deleteError = nil
    defer { isDeleting = false }
    do {
      try await detail.delete(using: account)
      try Task.checkCancellation()
      onChanged(.deleted(detail.post.id))
      dismiss()
    } catch is CancellationError {
    } catch {
      deleteError = "연결을 확인한 뒤 다시 시도해 주세요."
    }
  }

  private func loadedContent(_ detail: PhotoPostDetail) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          titleSection(detail.post)

          VStack(alignment: .leading, spacing: 10) {
            PhotoDetailImagePager(
              images: detail.images,
              selectedImageID: $selectedImageID,
              fallbackTitle: detail.post.title,
              onOpen: { imageID in
                selectedImageID = imageID
                showsPhotoViewer = true
              }
            )

            if let image = selectedImage(in: detail.images) {
              PhotoMetadataSection(image: image)
            }
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

          if let boardID = detail.boardID {
            Divider()
            PhotoCommentsSection(
              boardID: boardID, postID: detail.post.id, service: commentsService,
              initialCount: detail.post.commentCount
            )
            .id("photo-comments")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
      }
      .onChange(of: commentsScrollRequest) { _, _ in
        if reduceMotion {
          proxy.scrollTo("photo-comments", anchor: .top)
        } else {
          withAnimation { proxy.scrollTo("photo-comments", anchor: .top) }
        }
      }
    }
    .background(SenstaTheme.background)
  }

  private func titleSection(_ post: PhotoPost) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(post.title)
        .font(.title2.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("photo-detail-title")

      NavigationLink {
        PhotographerView(writer: post.writer, service: detailService)
      } label: {
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
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("photo-detail-photographer")
        .disabled(post.writer.id <= 0)
    }
  }

  @ViewBuilder
  private func profileImage(for writer: PhotoPostWriter) -> some View {
    if let profileURL = writer.profileURL {
      CachedAsyncPhotoImage(url: profileURL, targetSize: CGSize(width: 42, height: 42)) { phase in
        if case .success(let image) = phase {
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
        if let account, let boardID = detail.boardID {
          PhotoLikeButton(
            post: detail.post, boardID: boardID, account: account, detailService: detailService)
        } else {
          metric("heart", value: detail.post.likeCount, name: "좋아요")
        }
        metric(
          "bubble.right", value: account?.commentCounts[detail.post.id] ?? detail.post.commentCount,
          name: "댓글")
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
    guard let selectedImageID else { return images.first }
    return images.first { $0.id == selectedImageID } ?? images.first
  }
}

private struct PhotoDetailImagePager: View {
  let images: [PhotoPostImage]
  @Binding var selectedImageID: PhotoPostImage.ID?
  let fallbackTitle: String
  let onOpen: (Int) -> Void
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        if images.isEmpty {
          missingPhoto
        } else {
          ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
              ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                Button {
                  onOpen(image.id)
                } label: {
                  detailImage(image, index: index, size: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .buttonStyle(.plain)
                .accessibilityHint("사진을 전체 화면으로 감상합니다.")
                .accessibilityIdentifier("photo-detail-open-viewer")
                .id(image.id)
              }
            }
            .scrollTargetLayout()
          }
          .scrollIndicators(.hidden)
          .scrollTargetBehavior(.paging)
          .scrollPosition(id: $selectedImageID, anchor: .center)

          if images.count > 1 {
            HStack(spacing: 6) {
              ForEach(images) { image in
                Circle()
                  .fill(isSelected(image) ? Color.white : Color.white.opacity(0.45))
                  .frame(width: isSelected(image) ? 7 : 6, height: isSelected(image) ? 7 : 6)
                  .accessibilityHidden(true)
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.28), in: Capsule())
            .padding(.bottom, 14)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("사진 페이지")
            .accessibilityValue("\(selectedIndex + 1)/\(images.count)")
          }
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .background(Color.secondary.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      .task(id: selectedImageID ?? images.first?.id, priority: .utility) {
        if selectedImageID == nil {
          selectedImageID = images.first?.id
        }
        await prefetchAdjacentImages(size: geometry.size)
      }
    }
    .aspectRatio(4 / 5, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("photo-detail-image-pager")
  }

  @ViewBuilder
  private func detailImage(_ image: PhotoPostImage, index: Int, size: CGSize) -> some View {
    if let url = image.largeURL ?? image.smallURL {
      CachedAsyncPhotoImage(url: url, targetSize: size) { phase in
        switch phase {
        case .empty:
          missingPhoto.opacity(0.35)
        case .success(let loadedImage):
          loadedImage
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .clipped()
        case .failure:
          missingPhoto
        }
      }
      .accessibilityLabel(image.description.isEmpty ? fallbackTitle : image.description)
      .accessibilityValue("\(index + 1)/\(images.count)")
    } else {
      missingPhoto
    }
  }

  private var selectedIndex: Int {
    guard let selectedImageID,
      let index = images.firstIndex(where: { $0.id == selectedImageID })
    else {
      return 0
    }
    return index
  }

  private func isSelected(_ image: PhotoPostImage) -> Bool {
    (selectedImageID ?? images.first?.id) == image.id
  }

  private func prefetchAdjacentImages(size: CGSize) async {
    guard !images.isEmpty else { return }
    let currentIndex = selectedIndex
    let adjacentIndices = [currentIndex - 1, currentIndex + 1]
      .filter { images.indices.contains($0) }

    await withTaskGroup(of: Void.self) { group in
      for index in adjacentIndices {
        let url = images[index].largeURL ?? images[index].smallURL
        group.addTask {
          await PhotoImagePipeline.shared.prefetch(
            url,
            targetSize: size,
            displayScale: displayScale
          )
        }
      }
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
    if !facts.isEmpty || !image.description.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        if !facts.isEmpty {
          Text(facts.map(\.value).joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .accessibilityLabel(facts.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
            .accessibilityIdentifier("photo-metadata-exif")
        }
        if !facts.isEmpty && !image.description.isEmpty {
          Divider().padding(.horizontal, 14)
        }
        if !image.description.isEmpty {
          Text(image.description)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .accessibilityLabel("AI 사진 설명: \(image.description)")
            .accessibilityIdentifier("photo-metadata-description")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(SenstaTheme.container, in: RoundedRectangle(cornerRadius: 10))
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("photo-metadata-panel")
    }
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
    return values
  }
}

private struct PhotoFact: Identifiable {
  let label: String
  let value: String
  var id: String { label }
}

extension String {
  var nuboPlainText: String {
    replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"(?i)</(?:p|div)>"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
