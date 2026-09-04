import SwiftUI

struct ContentView: View {
  @State private var model: PhotoFeedViewModel
  private let detailService: any PhotoPostDetailServing

  init(service: any PhotoFeedServing, detailService: any PhotoPostDetailServing) {
    _model = State(initialValue: PhotoFeedViewModel(service: service))
    self.detailService = detailService
  }

  var body: some View {
    NavigationStack {
      Group {
        switch model.state {
        case .idle, .loading:
          ProgressView("사진을 불러오는 중…")
        case .empty:
          ContentUnavailableView(
            "아직 사진이 없어요",
            systemImage: "photo.on.rectangle.angled",
            description: Text("첫 번째 사진을 기다리고 있어요.")
          )
        case .failed(let message):
          ContentUnavailableView {
            Label("사진을 불러오지 못했어요", systemImage: "wifi.exclamationmark")
          } description: {
            Text(message)
          } actions: {
            Button("다시 시도") {
              Task { await model.retry() }
            }
            .buttonStyle(.borderedProminent)
          }
        case .loaded(let posts):
          PhotoFeedList(posts: posts, detailService: detailService) {
            await model.refresh()
          }
          .toolbar(.hidden, for: .navigationBar)
        }
      }
      .navigationTitle("SENSTA")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Image(systemName: "camera.aperture")
            .accessibilityHidden(true)
        }
      }
    }
    .task {
      await model.loadIfNeeded()
    }
  }
}

private struct PhotoFeedList: View {
  let posts: [PhotoPost]
  let detailService: any PhotoPostDetailServing
  let onRefresh: @MainActor @Sendable () async -> Void
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { geometry in
      let viewportSize = CGSize(
        width: geometry.size.width
          + geometry.safeAreaInsets.leading
          + geometry.safeAreaInsets.trailing,
        height: geometry.size.height
          + geometry.safeAreaInsets.top
          + geometry.safeAreaInsets.bottom
      )

      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
            NavigationLink {
              PhotoPostDetailView(postID: post.id, service: detailService)
            } label: {
              PhotoFeedCard(
                post: post,
                size: viewportSize,
                safeAreaInsets: geometry.safeAreaInsets
              )
            }
            .buttonStyle(.plain)
            .frame(width: viewportSize.width, height: viewportSize.height)
            .accessibilityIdentifier("photo-feed-card")
            .task(id: post.id, priority: .utility) {
              await prefetchNextCover(after: index, targetSize: viewportSize)
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.paging)
      .refreshable {
        await onRefresh()
      }
      .ignoresSafeArea()
    }
    .background(Color.black.ignoresSafeArea())
  }

  private func prefetchNextCover(after index: Int, targetSize: CGSize) async {
    let nextIndex = posts.index(after: index)
    guard posts.indices.contains(nextIndex) else { return }
    await PhotoImagePipeline.shared.prefetch(
      posts[nextIndex].coverURL,
      targetSize: targetSize,
      displayScale: displayScale
    )
  }
}

private struct PhotoFeedCard: View {
  let post: PhotoPost
  let size: CGSize
  let safeAreaInsets: EdgeInsets

  var body: some View {
    ZStack(alignment: .topLeading) {
      cover

      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black.opacity(0.12), location: 0.28),
          .init(color: .black.opacity(0.9), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: max(size.height * 0.5, 300))
      .frame(maxHeight: .infinity, alignment: .bottom)
      .allowsHitTesting(false)

      Text("SENSTA")
        .font(.custom("SnellRoundhand-Bold", fixedSize: 25))
        .foregroundStyle(.white.opacity(0.68))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .padding(.leading, 18)
        .padding(.top, safeAreaInsets.top + 14)
        .accessibilityIdentifier("sensta-feed-wordmark")

      VStack(alignment: .leading, spacing: 12) {
        writerHeader

        Text(post.title)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 16) {
          counts
          Spacer(minLength: 12)
          submittedDate
        }
        .font(.caption)
      }
      .padding(.horizontal, 18)
      .padding(.bottom, safeAreaInsets.bottom + 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    .frame(width: size.width, height: size.height)
    .background(Color.black)
    .clipped()
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
  }

  private var writerHeader: some View {
    HStack(spacing: 10) {
      profileImage

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(post.writer.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
          if post.writer.badgeKeys.contains("sensta-app") {
            Image(systemName: "camera.aperture")
              .font(.caption)
              .foregroundStyle(.white.opacity(0.9))
              .accessibilityLabel("SENSTA 앱 포토그래퍼")
          }
        }
        Text("PHOTOGRAPHER")
          .font(.caption2)
          .tracking(1)
          .foregroundStyle(.white.opacity(0.72))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var profileImage: some View {
    if let url = post.writer.profileURL {
      CachedAsyncPhotoImage(url: url, targetSize: CGSize(width: 38, height: 38)) { phase in
        if case .success(let image) = phase {
          image.resizable().scaledToFill()
        } else {
          Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.white.opacity(0.72))
        }
      }
      .frame(width: 38, height: 38)
      .clipShape(Circle())
      .accessibilityLabel("\(post.writer.name) 프로필 사진")
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .foregroundStyle(.white.opacity(0.72))
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }
  }

  private var counts: some View {
    HStack(spacing: 16) {
      countLabel("heart", count: post.likeCount, name: "좋아요")
      countLabel("bubble.right", count: post.commentCount, name: "댓글")
      countLabel("eye", count: post.viewCount, name: "조회")
    }
  }

  private var submittedDate: some View {
    Text(post.submitted, format: .dateTime.year().month().day())
      .foregroundStyle(.white.opacity(0.72))
  }

  private var cover: some View {
    ZStack {
      Color.secondary.opacity(0.12)

      if post.coverURL != nil {
        CachedAsyncPhotoImage(url: post.coverURL, targetSize: size) { phase in
          switch phase {
          case .empty:
            missingPhoto.opacity(0.35)
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
              .frame(width: size.width, height: size.height)
          case .failure:
            missingPhoto
          }
        }
      } else {
        missingPhoto
      }
    }
    .frame(width: size.width, height: size.height)
    .clipped()
    .accessibilityLabel(post.title)
  }

  private var missingPhoto: some View {
    Image(systemName: "photo")
      .font(.largeTitle)
      .foregroundStyle(.secondary)
  }

  private func countLabel(_ systemImage: String, count: Int, name: String) -> some View {
    Label(count.formatted(.number.notation(.compactName)), systemImage: systemImage)
      .foregroundStyle(.white.opacity(0.86))
      .accessibilityLabel("\(name) \(count)개")
  }
}

#Preview {
  ContentView(
    service: PreviewPhotoFeedService(),
    detailService: PreviewPhotoPostDetailService()
  )
}

private struct PreviewPhotoPostDetailService: PhotoPostDetailServing {
  func fetchPost(id: Int) async throws -> PhotoPostDetail {
    PhotoPostDetail(
      post: PhotoPost(
        id: id,
        title: "사진으로 이어지는 커뮤니티",
        content: "SENSTA에서 사진과 이야기를 함께 만나보세요.",
        submitted: .now,
        viewCount: 24,
        coverURL: nil,
        commentCount: 3,
        likeCount: 12,
        isLiked: false,
        writer: PhotoPostWriter(
          id: 1,
          name: "SENSTA",
          profileURL: nil,
          badgeKeys: ["sensta-app"]
        )
      ),
      images: [],
      tags: [PhotoPostTag(id: 1, name: "사진")],
      attachments: [],
      previousPostID: nil,
      nextPostID: nil,
      shareURL: nil
    )
  }
}

private struct PreviewPhotoFeedService: PhotoFeedServing {
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    PhotoFeedPage(
      totalPostCount: 1,
      posts: [
        PhotoPost(
          id: 1,
          title: "사진으로 이어지는 커뮤니티",
          content: "",
          submitted: .now,
          viewCount: 24,
          coverURL: nil,
          commentCount: 3,
          likeCount: 12,
          isLiked: false,
          writer: PhotoPostWriter(
            id: 1,
            name: "SENSTA",
            profileURL: nil,
            badgeKeys: ["sensta-app"]
          )
        )
      ]
    )
  }
}
