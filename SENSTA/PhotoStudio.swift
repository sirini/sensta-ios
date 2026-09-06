import Foundation
import Observation
import SwiftUI

enum PhotoStudioSort: String, CaseIterable, Identifiable, Sendable {
  case recent
  case views
  case likes
  case comments

  var id: String { rawValue }

  var label: String {
    switch self {
    case .recent: "최신순"
    case .views: "조회순"
    case .likes: "좋아요순"
    case .comments: "댓글순"
    }
  }
}

struct PhotoStudioSummary: Equatable, Sendable {
  let postCount: Int
  let photoCount: Int
  let viewCount: Int
  let likeCount: Int
  let commentCount: Int
}

struct PhotoStudioPost: Identifiable, Equatable, Sendable {
  let id: Int
  let title: String
  let coverURL: URL?
  let submitted: Date
  let modified: Date
  let isPrivate: Bool
  let imageCount: Int
  let viewCount: Int
  let likeCount: Int
  let commentCount: Int
}

struct PhotoStudioPage: Equatable, Sendable {
  let summary: PhotoStudioSummary
  let page: Int
  let totalCount: Int
  let hasNext: Bool
  let posts: [PhotoStudioPost]
}

struct PhotoStudioResponseDTO: Decodable, Sendable {
  let success: Bool
  let error: String
  let code: Int
  let result: ResultDTO?

  struct ResultDTO: Decodable, Sendable {
    let summary: SummaryDTO
    let posts: PostsDTO
  }

  struct SummaryDTO: Decodable, Sendable {
    let postCount: Int
    let photoCount: Int
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
  }

  struct PostsDTO: Decodable, Sendable {
    let page: Int
    let limit: Int
    let totalCount: Int
    let hasNext: Bool
    let items: [PostDTO]
  }

  struct PostDTO: Decodable, Sendable {
    let uid: Int
    let title: String
    let cover: String
    let submitted: Int64
    let modified: Int64
    let status: Int
    let imageCount: Int
    let hit: Int
    let like: Int
    let comment: Int
  }

  func makePage(apiBaseURL: URL, requestedPage: Int, requestedLimit: Int) throws
    -> PhotoStudioPage
  {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result else { throw NuboAPIError.malformedResponse }
    let summary = result.summary
    let posts = result.posts
    let summaryCounts = [
      summary.postCount, summary.photoCount, summary.viewCount, summary.likeCount,
      summary.commentCount,
    ]
    let pageBoundary = posts.page.multipliedReportingOverflow(by: posts.limit)
    var seen = Set<Int>()
    guard summaryCounts.allSatisfy({ $0 >= 0 }), posts.page == requestedPage,
      posts.limit == requestedLimit, posts.totalCount >= 0, posts.items.count <= posts.limit,
      posts.totalCount >= posts.items.count, !pageBoundary.overflow,
      posts.hasNext == (pageBoundary.partialValue < posts.totalCount),
      posts.items.allSatisfy({ item in
        item.uid > 0 && [0, 2].contains(item.status) && item.submitted >= 0 && item.modified >= 0
          && item.imageCount >= 0 && item.hit >= 0 && item.like >= 0 && item.comment >= 0
          && seen.insert(item.uid).inserted
      })
    else { throw NuboAPIError.malformedResponse }

    return PhotoStudioPage(
      summary: PhotoStudioSummary(
        postCount: summary.postCount, photoCount: summary.photoCount,
        viewCount: summary.viewCount, likeCount: summary.likeCount,
        commentCount: summary.commentCount),
      page: posts.page, totalCount: posts.totalCount, hasNext: posts.hasNext,
      posts: posts.items.map { item in
        PhotoStudioPost(
          id: item.uid, title: item.title,
          coverURL: Self.coverURL(path: item.cover, apiBaseURL: apiBaseURL),
          submitted: Date(timeIntervalSince1970: Double(item.submitted) / 1_000),
          modified: Date(timeIntervalSince1970: Double(item.modified) / 1_000),
          isPrivate: item.status == 2, imageCount: item.imageCount, viewCount: item.hit,
          likeCount: item.like, commentCount: item.comment)
      })
  }

  private static func coverURL(path: String, apiBaseURL: URL) -> URL? {
    var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard path.hasPrefix("/upload/thumbnails/") || path.hasPrefix("./upload/thumbnails/") else {
      return nil
    }
    if path.hasPrefix("./") { path.removeFirst() }
    return MediaURLResolver.url(for: path, apiBaseURL: apiBaseURL)
  }
}

enum PhotoStudioEndpoint {
  static let pageSize = 20

  static func request(
    baseURL: URL, page: Int, limit: Int = pageSize, sort: PhotoStudioSort
  ) throws -> URLRequest {
    guard page > 0, (1...50).contains(limit),
      var components = URLComponents(
        url: baseURL.appending(path: "board/my/studio"), resolvingAgainstBaseURL: false)
    else { throw NuboAPIError.invalidRequest }
    components.queryItems = [
      URLQueryItem(name: "id", value: "photo"),
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "sort", value: sort.rawValue),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = try AccountEndpoint.request(baseURL: baseURL, path: "board/my/studio")
    request.url = url
    return request
  }
}

protocol PhotoStudioServing: Sendable {
  func fetchPage(_ page: Int, sort: PhotoStudioSort) async throws -> PhotoStudioPage
}

struct AccountPhotoStudioService: PhotoStudioServing {
  let account: AccountSession
  let baseURL: URL?

  @MainActor
  init(account: AccountSession) {
    self.account = account
    baseURL = account.apiBaseURL
  }

  func fetchPage(_ page: Int, sort: PhotoStudioSort) async throws -> PhotoStudioPage {
    guard let baseURL else { throw NuboAPIError.configuration }
    let request = try PhotoStudioEndpoint.request(baseURL: baseURL, page: page, sort: sort)
    let data = try await account.sendAuthenticated(request)
    do {
      return try JSONDecoder().decode(PhotoStudioResponseDTO.self, from: data).makePage(
        apiBaseURL: baseURL, requestedPage: page, requestedLimit: PhotoStudioEndpoint.pageSize)
    } catch let error as NuboAPIError {
      throw error
    } catch {
      throw NuboAPIError.malformedResponse
    }
  }
}

struct AuthenticatedPhotoPostDetailService: PhotoPostDetailServing {
  let account: AccountSession
  let baseURL: URL?
  let publicService: any PhotoPostDetailServing

  @MainActor
  init(account: AccountSession, publicService: any PhotoPostDetailServing) {
    self.account = account
    baseURL = account.apiBaseURL
    self.publicService = publicService
  }

  func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
    try await publicService.fetchPhotographer(id: id)
  }

  func fetchPost(id: Int) async throws -> PhotoPostDetail {
    guard let baseURL else { throw NuboAPIError.configuration }
    let request = try PhotoPostDetailEndpoint.makeRequest(apiBaseURL: baseURL, postID: id)
    let data = try await account.sendAuthenticated(request)
    let envelope: BoardViewResponseDTO
    do { envelope = try JSONDecoder().decode(BoardViewResponseDTO.self, from: data) } catch {
      throw NuboAPIError.malformedResponse
    }
    let detail = try envelope.makePhotoPostDetail(apiBaseURL: baseURL)
    guard detail.post.id == id else { throw NuboAPIError.malformedResponse }
    return detail
  }

  func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
    guard let baseURL else { throw NuboAPIError.configuration }
    let request = try PhotoCommentsEndpoint.makeRequest(
      apiBaseURL: baseURL, boardID: boardID, postID: postID, page: page)
    let data = try await account.sendAuthenticated(request)
    let envelope: PhotoCommentsResponseDTO
    do { envelope = try JSONDecoder().decode(PhotoCommentsResponseDTO.self, from: data) } catch {
      throw NuboAPIError.malformedResponse
    }
    return try envelope.makePage(boardID: boardID, postID: postID, page: page)
  }
}

@MainActor @Observable
final class PhotoStudioModel {
  private let service: any PhotoStudioServing
  private var requestID: UUID?
  private var fetchTask: Task<PhotoStudioPage, Error>?
  private(set) var summary: PhotoStudioSummary?
  private(set) var posts: [PhotoStudioPost] = []
  private(set) var selectedSort: PhotoStudioSort = .recent
  private(set) var isLoading = false
  private(set) var isLoadingMore = false
  private(set) var hasLoaded = false
  private(set) var hasNext = false
  private(set) var error: String?
  private(set) var loadMoreError: String?
  private var nextPage = 1

  init(service: any PhotoStudioServing) { self.service = service }

  func reset() {
    fetchTask?.cancel()
    fetchTask = nil
    requestID = nil
    summary = nil
    posts = []
    selectedSort = .recent
    isLoading = false
    isLoadingMore = false
    hasLoaded = false
    hasNext = false
    error = nil
    loadMoreError = nil
    nextPage = 1
  }

  func loadIfNeeded() async {
    guard !hasLoaded, !isLoading else { return }
    await loadFirstPage(preservesExisting: false)
  }

  func refresh() async { await loadFirstPage(preservesExisting: true) }

  func apply(_ change: PhotoPostChange) {
    guard case .deleted(let postID) = change,
      let index = posts.firstIndex(where: { $0.id == postID })
    else { return }
    let post = posts.remove(at: index)
    if let summary {
      self.summary = PhotoStudioSummary(
        postCount: max(0, summary.postCount - 1),
        photoCount: max(0, summary.photoCount - post.imageCount),
        viewCount: max(0, summary.viewCount - post.viewCount),
        likeCount: max(0, summary.likeCount - post.likeCount),
        commentCount: max(0, summary.commentCount - post.commentCount))
    }
  }

  func selectSort(_ sort: PhotoStudioSort) async {
    guard selectedSort != sort else { return }
    selectedSort = sort
    posts = []
    hasLoaded = false
    hasNext = false
    nextPage = 1
    await loadFirstPage(preservesExisting: false)
  }

  func loadMoreIfNeeded(currentPostID: Int) async {
    guard let index = posts.firstIndex(where: { $0.id == currentPostID }),
      index >= posts.count - 3, loadMoreError == nil
    else { return }
    await loadMore()
  }

  func loadMore() async {
    guard requestID == nil, hasNext, !posts.isEmpty else { return }
    let id = beginRequest()
    isLoadingMore = true
    loadMoreError = nil
    defer { finishRequest(id) }
    do {
      let page = try await fetch(page: nextPage, sort: selectedSort)
      guard requestID == id else { return }
      var seen = Set(posts.map(\.id))
      posts += page.posts.filter { seen.insert($0.id).inserted }
      summary = page.summary
      nextPage = page.page + 1
      hasNext = page.hasNext
    } catch is CancellationError {
    } catch {
      guard requestID == id else { return }
      loadMoreError = Self.message(for: error)
    }
  }

  private func loadFirstPage(preservesExisting: Bool) async {
    let previousSummary = summary
    let previousPosts = posts
    let previousHasLoaded = hasLoaded
    let previousHasNext = hasNext
    let previousNextPage = nextPage
    let id = beginRequest()
    isLoading = true
    error = nil
    loadMoreError = nil
    if !preservesExisting { posts = [] }
    defer { finishRequest(id) }
    do {
      let page = try await fetch(page: 1, sort: selectedSort)
      guard requestID == id else { return }
      summary = page.summary
      var seen = Set<Int>()
      posts = page.posts.filter { seen.insert($0.id).inserted }
      hasLoaded = true
      hasNext = page.hasNext
      nextPage = page.page + 1
    } catch is CancellationError {
      guard requestID == id else { return }
      summary = previousSummary
      posts = previousPosts
      hasLoaded = previousHasLoaded
      hasNext = previousHasNext
      nextPage = previousNextPage
    } catch {
      guard requestID == id else { return }
      if preservesExisting, previousHasLoaded {
        summary = previousSummary
        posts = previousPosts
        hasLoaded = true
        hasNext = previousHasNext
        nextPage = previousNextPage
      } else {
        hasLoaded = false
        hasNext = false
        nextPage = 1
      }
      self.error = Self.message(for: error)
    }
  }

  private func beginRequest() -> UUID {
    fetchTask?.cancel()
    let id = UUID()
    requestID = id
    isLoading = false
    isLoadingMore = false
    return id
  }

  private func finishRequest(_ id: UUID) {
    guard requestID == id else { return }
    requestID = nil
    fetchTask = nil
    isLoading = false
    isLoadingMore = false
  }

  private func fetch(page: Int, sort: PhotoStudioSort) async throws -> PhotoStudioPage {
    try Task.checkCancellation()
    let task = Task { try await service.fetchPage(page, sort: sort) }
    fetchTask = task
    return try await withTaskCancellationHandler {
      let page = try await task.value
      try Task.checkCancellation()
      return page
    } onCancel: {
      task.cancel()
    }
  }

  private static func message(for error: Error) -> String {
    if let error = error as? NuboAPIError, let description = error.errorDescription {
      return description
    }
    return "작품 정보를 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
  }
}

struct PhotoStudioView: View {
  let account: AccountSession
  private let detailService: any PhotoPostDetailServing
  @State private var model: PhotoStudioModel
  @State private var showUpload = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.dismiss) private var dismiss

  @MainActor
  init(account: AccountSession, publicDetailService: any PhotoPostDetailServing) {
    self.account = account
    let service = AccountPhotoStudioService(account: account)
    _model = State(initialValue: PhotoStudioModel(service: service))
    detailService = AuthenticatedPhotoPostDetailService(
      account: account, publicService: publicDetailService)
  }

  var body: some View {
    List {
      summarySection

      if !model.posts.isEmpty {
        Section { sortPicker }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }

      if model.isLoading && model.posts.isEmpty {
        Section { ProgressView("내 작품을 불러오는 중…").frame(maxWidth: .infinity) }
      } else if let error = model.error, model.posts.isEmpty {
        Section {
          ContentUnavailableView {
            Label("작품을 불러오지 못했어요", systemImage: "wifi.exclamationmark")
          } description: {
            Text(error)
          } actions: {
            Button("다시 시도") { Task { await model.loadIfNeeded() } }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("photo-studio-retry")
          }
        }
      } else if model.hasLoaded && model.posts.isEmpty {
        Section {
          ContentUnavailableView {
            Label("아직 업로드한 작품이 없어요", systemImage: "photo.on.rectangle.angled")
          } description: {
            Text("첫 사진을 올리고 나만의 스튜디오를 시작해 보세요.")
          } actions: {
            Button("첫 사진 업로드") { showUpload = true }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("photo-studio-empty-upload")
          }
        }
      } else {
        Section("작품") {
          ForEach(model.posts) { post in
            NavigationLink {
              PhotoPostDetailView(postID: post.id, service: detailService) { change in
                model.apply(change)
                Task { await model.refresh() }
              }
            } label: {
              PhotoStudioPostRow(post: post)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
              SenstaTheme.surface,
              in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("photo-studio-post-\(post.id)")
            .task { await model.loadMoreIfNeeded(currentPostID: post.id) }
          }

          if model.isLoadingMore {
            ProgressView("다음 작품을 불러오는 중…").frame(maxWidth: .infinity)
          } else if let error = model.loadMoreError {
            VStack(spacing: 8) {
              Text(error).font(.footnote).foregroundStyle(.secondary)
              Button("다음 작품 다시 불러오기") { Task { await model.loadMore() } }
                .accessibilityIdentifier("photo-studio-load-more-retry")
            }
            .frame(maxWidth: .infinity)
          }
        }
      }

      if model.error != nil && !model.posts.isEmpty {
        Section {
          HStack {
            Text("새로고침하지 못했어요. 기존 작품을 유지했어요.")
              .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("재시도") { Task { await model.refresh() } }
          }
          .accessibilityIdentifier("photo-studio-refresh-error")
        }
      }
    }
    .listStyle(.insetGrouped)
    .refreshable { await model.refresh() }
    .navigationTitle("내 작품")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("사진 올리기", systemImage: "plus") { showUpload = true }
          .accessibilityIdentifier("photo-studio-upload")
      }
    }
    .fullScreenCover(isPresented: $showUpload) {
      PhotoUploadView(account: account) {
        showUpload = false
        Task {
          await model.refresh()
          await account.achievements.check(using: account)
        }
      }
    }
    .task(id: account.sessionIdentity) {
      model.reset()
      guard account.user != nil else { return }
      await model.loadIfNeeded()
    }
    .onChange(of: account.user?.uid) { _, userID in
      if userID == nil { dismiss() }
    }
    .senstaScreenStyle()
  }

  private var summarySection: some View {
    Section {
      let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 3
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), alignment: .center), count: columns),
        spacing: 16
      ) {
        summaryMetric("작품", value: model.summary?.postCount)
        summaryMetric("사진", value: model.summary?.photoCount)
        summaryMetric("받은 좋아요", value: model.summary?.likeCount)
      }
      .padding(.vertical, 8)
      .accessibilityIdentifier("photo-studio-summary")
    }
  }

  private func summaryMetric(_ label: String, value: Int?) -> some View {
    VStack(spacing: 5) {
      Text(value?.formatted() ?? "—")
        .font(.title2.weight(.semibold))
        .monospacedDigit()
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(value.map(String.init) ?? "불러오는 중")
  }

  private var sortPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(PhotoStudioSort.allCases) { sort in
          Button {
            Task { await model.selectSort(sort) }
          } label: {
            Text(sort.label)
              .font(.subheadline.weight(model.selectedSort == sort ? .semibold : .regular))
              .foregroundStyle(
                model.selectedSort == sort ? SenstaTheme.onPrimary : SenstaTheme.foreground
              )
              .padding(.horizontal, 14)
              .frame(minHeight: 38)
              .background(
                model.selectedSort == sort ? SenstaTheme.primary : SenstaTheme.container,
                in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(model.isLoading || model.isLoadingMore)
          .accessibilityAddTraits(model.selectedSort == sort ? .isSelected : [])
          .accessibilityIdentifier("photo-studio-sort-\(sort.rawValue)")
        }
      }
      .padding(.horizontal, 16)
    }
  }
}

private struct PhotoStudioPostRow: View {
  let post: PhotoStudioPost
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          GeometryReader { geometry in
            cover(side: geometry.size.width)
          }
          .aspectRatio(1, contentMode: .fit)
          details
        }
      } else {
        HStack(spacing: 12) {
          cover(side: 96)
          details
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(post.title.nuboPlainText)
    .accessibilityValue(accessibilityValue)
  }

  private func cover(side: CGFloat) -> some View {
    let pixelSide = max(384, ceil(side * displayScale))
    return CachedAsyncPhotoImage(
      url: post.coverURL, targetSize: CGSize(width: pixelSide, height: pixelSide)
    ) { phase in
      if case .success(let image) = phase {
        image.resizable().scaledToFill()
      } else {
        Rectangle().fill(SenstaTheme.container).overlay {
          Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
        }
      }
    }
    .frame(width: side, height: side)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
    }
    .overlay(alignment: .bottomTrailing) {
      if post.imageCount > 1 {
        Label("\(post.imageCount)", systemImage: "photo.stack")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(.black.opacity(0.68), in: Capsule())
          .padding(6)
          .accessibilityHidden(true)
      }
    }
    .accessibilityHidden(true)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(post.title.nuboPlainText)
          .font(.headline)
          .lineLimit(2)
        Spacer(minLength: 0)
        if post.isPrivate {
          Label("비공개", systemImage: "lock.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
        }
      }
      Text("\(post.submitted.formatted(.dateTime.year().month().day())) 업로드")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 12) {
        metric("eye", value: post.viewCount, label: "조회")
        metric("heart", value: post.likeCount, label: "좋아요")
        metric("bubble.right", value: post.commentCount, label: "댓글")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metric(_ symbol: String, value: Int, label: String) -> some View {
    Label(value.formatted(.number.notation(.compactName)), systemImage: symbol)
      .font(.caption2)
      .foregroundStyle(.secondary)
      .accessibilityLabel("\(label) \(value)개")
  }

  private var accessibilityValue: String {
    let privacy = post.isPrivate ? "비공개, " : ""
    return "\(privacy)사진 \(post.imageCount)장, 조회 \(post.viewCount), "
      + "좋아요 \(post.likeCount), 댓글 \(post.commentCount)"
  }
}
