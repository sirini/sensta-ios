import SwiftUI

struct ContentView: View {
  @State private var model: PhotoFeedViewModel
  @State private var notificationCenter = PhotoNotificationCenter()
  @State private var showAccount = false
  @State private var showUpload = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.scenePhase) private var scenePhase
  var account: AccountSession? = nil
  private let detailService: any PhotoPostDetailServing
  private let feedService: any PhotoFeedServing

  init(service: any PhotoFeedServing, detailService: any PhotoPostDetailServing) {
    _model = State(initialValue: PhotoFeedViewModel(service: service))
    self.detailService = detailService
    self.feedService = service
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
          PhotoFeedList(
            posts: posts,
            detailService: detailService,
            isLoadingMore: model.isLoadingMore,
            loadMoreError: model.loadMoreError,
            onRefresh: {
              await model.refresh()
              if let account, account.user != nil {
                await notificationCenter.load(using: account, force: true)
              }
            },
            onLoadMore: { await model.loadMoreIfNeeded(currentPostID: $0) },
            onRetryLoadMore: { await model.loadMore() }
          )
          .overlay(alignment: .top) {
            if let message = model.refreshError {
              VStack(spacing: 8) {
                Text(message)
                Button("새로고침 재시도") { Task { await model.refresh() } }
              }
              .font(.subheadline)
              .padding()
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
              .padding()
              .accessibilityIdentifier("photo-feed-refresh-error")
            }
          }
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
              if let account {
                Button {
                  showAccount = true
                } label: {
                  if account.user != nil {
                    if account.profileURL != nil {
                      AccountAvatar(url: account.profileURL, size: 36)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.25), in: Circle())
                    } else {
                      Image(systemName: "person.crop.circle")
                        .font(.title2.weight(.regular))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.25), in: Circle())
                        .accessibilityIdentifier("photo-feed-account-without-profile")
                    }
                  } else {
                    Image(systemName: "ipad.and.arrow.forward")
                      .environment(\.layoutDirection, .leftToRight)
                      .font(.body.weight(.medium)).foregroundStyle(.white)
                      .frame(width: 44, height: 44).background(.black.opacity(0.25), in: Circle())
                  }
                }.accessibilityLabel(account.user == nil ? "로그인" : "내 계정")
                  .accessibilityValue(account.user == nil ? "로그아웃 상태" : "로그인 상태")
                  .accessibilityIdentifier("photo-feed-account")
              }
              NavigationLink {
                PhotoSearchView(service: feedService, detailService: detailService)
              } label: {
                Image(systemName: "magnifyingglass")
                  .font(.body.weight(.medium))
                  .foregroundStyle(.white)
                  .frame(width: 44, height: 44)
                  .background(.black.opacity(0.25), in: Circle())
              }
              .accessibilityLabel("탐색")
              .accessibilityIdentifier("photo-feed-search")
              if let account, account.user != nil {
                NavigationLink {
                  PhotoNotificationsView(
                    center: notificationCenter, account: account, detailService: detailService)
                } label: {
                  PhotoNotificationBell(hasUnread: notificationCenter.hasUnread)
                }
                .accessibilityLabel(notificationCenter.hasUnread ? "읽지 않은 알림" : "알림")
                .accessibilityValue(notificationCenter.hasUnread ? "새 알림 있음" : "새 알림 없음")
                .accessibilityIdentifier("photo-feed-notifications")
              }
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
          }
          .overlay(alignment: .bottom) {
            Button {
              if account?.user == nil {
                showAccount = true
              } else {
                showUpload = true
              }
            } label: {
              Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(account?.user == nil ? "로그인하고 사진 올리기" : "사진 올리기")
            .accessibilityIdentifier("photo-feed-upload")
            .padding(.bottom, 12)
          }
          .toolbar(.hidden, for: .navigationBar)
        }
      }
      .navigationTitle("SENSTA")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if account != nil {
            Button("내 계정", systemImage: "person.crop.circle") { showAccount = true }
          }
        }
        ToolbarItem(placement: .topBarLeading) {
          Image(systemName: "camera.aperture")
            .accessibilityHidden(true)
        }
      }
    }
    .sheet(isPresented: $showAccount) {
      if let account {
        AccountView(session: account, detailService: detailService)
          .environment(\.dynamicTypeSize, dynamicTypeSize)
          .presentationDragIndicator(.visible)
      }
    }
    .fullScreenCover(isPresented: $showUpload) {
      if let account, account.user != nil {
        PhotoUploadView(account: account) {
          showUpload = false
          Task { await model.refresh() }
        }
      }
    }
    .task {
      await model.loadIfNeeded()
    }
    .task(id: account?.sessionIdentity) {
      guard let account, account.user != nil else {
        notificationCenter.reset()
        return
      }
      await notificationCenter.load(using: account)
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, let account, account.user != nil else { return }
      Task { await notificationCenter.load(using: account, force: true) }
    }
  }
}

private struct PhotoFeedList: View {
  let posts: [PhotoPost]
  let detailService: any PhotoPostDetailServing
  let isLoadingMore: Bool
  let loadMoreError: String?
  let onRefresh: @MainActor @Sendable () async -> Void
  let onLoadMore: @MainActor @Sendable (Int) async -> Void
  let onRetryLoadMore: @MainActor @Sendable () async -> Void
  @State private var visiblePostID: Int?
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
            .id(post.id)
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
      .scrollPosition(id: $visiblePostID)
      .onChange(of: visiblePostID) { _, currentID in
        if let currentID { Task { await onLoadMore(currentID) } }
      }
      .onChange(of: posts.last?.id, initial: true) { _, _ in
        if let currentID = visiblePostID ?? posts.first?.id {
          Task { await onLoadMore(currentID) }
        }
      }
      .overlay(alignment: .top) {
        if visiblePostID == posts.last?.id {
          VStack(spacing: 8) {
            if isLoadingMore {
              ProgressView("다음 사진을 불러오는 중…")
            } else if let loadMoreError {
              Text(loadMoreError)
              Button("다음 사진 다시 불러오기") { Task { await onRetryLoadMore() } }
                .accessibilityIdentifier("photo-feed-load-more-retry")
            }
          }
          .font(.subheadline)
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
          .padding(.top, geometry.safeAreaInsets.top + 44)
          .padding(.horizontal)
          .opacity(isLoadingMore || loadMoreError != nil ? 1 : 0)
        }
      }
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
  @Environment(\.accountSession) private var account
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

      Image("SenstaWordmark")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 61, height: 14)
        .foregroundStyle(.white.opacity(0.6))
        .padding(.leading, 18)
        .padding(.top, safeAreaInsets.top + 14)
        .accessibilityLabel("SENSTA")
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
      .padding(.bottom, safeAreaInsets.bottom + 92)
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
      if post.writer.profileURL != nil { profileImage }

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
      EmptyView()
    }
  }

  private var counts: some View {
    HStack(spacing: 16) {
      countLabel(
        account?.postLikes.states[post.id]?.isLiked == true ? "heart.fill" : "heart",
        count: account?.postLikes.counts[post.id] ?? post.likeCount, name: "좋아요"
      )
      .accessibilityIdentifier("photo-feed-like-\(post.id)")
      countLabel(
        "bubble.right", count: account?.commentCounts[post.id] ?? post.commentCount, name: "댓글"
      )
      .accessibilityIdentifier("photo-feed-comments-\(post.id)")
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
