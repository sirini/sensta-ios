import Foundation
import Observation
import SwiftUI

enum PhotoSearchOption: Int, CaseIterable, Identifiable, Sendable {
  case aiDescription = 12
  case title = 0
  case content = 1
  case writer = 2
  case hashtag = 3

  var id: Int { rawValue }
  var label: String {
    switch self {
    case .aiDescription: "AI 설명"
    case .title: "제목"
    case .content: "본문"
    case .writer: "닉네임"
    case .hashtag: "해시태그"
    }
  }
  var prompt: String {
    switch self {
    case .aiDescription: "사진 속 장면이나 사물 검색"
    case .title: "사진 제목 검색"
    case .content: "사진에 담긴 이야기 검색"
    case .writer: "사진가 닉네임 검색"
    case .hashtag: "해시태그 검색"
    }
  }
  var hint: String {
    switch self {
    case .aiDescription: "사진에 저장된 AI 설명에서 장면과 사물을 찾아요."
    case .title: "사진 제목에 담긴 단어를 찾아요."
    case .content: "사진과 함께 쓴 본문에서 찾아요."
    case .writer: "사진가의 닉네임으로 작품을 찾아요."
    case .hashtag: "태그를 입력하거나 아래의 최근 태그를 선택하세요."
    }
  }
}

struct PhotoSearchRequest: Hashable {
  let keyword: String
  let option: PhotoSearchOption

  init(keyword: String, option: PhotoSearchOption) {
    self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    self.option = option
  }
}

struct PhotoSearchView: View {
  let service: any PhotoFeedServing
  let detailService: any PhotoPostDetailServing
  @State private var draft = ""
  @State private var option: PhotoSearchOption = .aiDescription
  @State private var request = PhotoSearchRequest(keyword: "", option: .aiDescription)
  @State private var recentTags: PhotoRecentTagsModel

  init(
    service: any PhotoFeedServing, detailService: any PhotoPostDetailServing,
    initialRequest: PhotoSearchRequest = PhotoSearchRequest(keyword: "", option: .aiDescription)
  ) {
    self.service = service
    self.detailService = detailService
    _draft = State(initialValue: initialRequest.keyword)
    _option = State(initialValue: initialRequest.option)
    _request = State(initialValue: initialRequest)
    _recentTags = State(initialValue: PhotoRecentTagsModel(service: service))
  }

  var body: some View {
    PhotoSearchResults(
      request: request, service: service, detailService: detailService,
      recentTags: recentTags, onSelectTag: selectTag
    ) {
      VStack(alignment: .leading, spacing: 10) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(PhotoSearchOption.allCases) { choice in
              Button {
                option = choice
              } label: {
                Text(choice.label)
                  .font(.subheadline.weight(option == choice ? .semibold : .regular))
                  .padding(.horizontal, 16)
                  .frame(minHeight: 44)
                  .background(
                    option == choice ? Color.primary : Color(.secondarySystemBackground),
                    in: Capsule()
                  )
                  .foregroundStyle(option == choice ? Color(.systemBackground) : .primary)
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(option == choice ? .isSelected : [])
              .accessibilityIdentifier("explore-option-\(choice.rawValue)")
            }
          }
          .padding(.horizontal, 16)
        }
        Text(option.hint)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)
      }
      .padding(.top, 12)
    }
    .id(request)
    .navigationTitle("탐색")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .searchable(
      text: $draft, placement: .navigationBarDrawer(displayMode: .always), prompt: option.prompt
    )
    .onSubmit(of: .search) { submit() }
    .onChange(of: option) { _, _ in submit() }
    .onChange(of: draft) { _, value in
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submit() }
    }
  }

  private func submit() { request = PhotoSearchRequest(keyword: draft, option: option) }

  private func selectTag(_ tag: PhotoPostTag) {
    draft = tag.name
    option = .hashtag
    submit()
  }
}

struct PhotoSearchResultsService: PhotoFeedServing {
  let source: any PhotoFeedServing
  let keyword: String
  let option: PhotoSearchOption

  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    if keyword.isEmpty { return try await source.fetchPage(page) }
    return try await source.search(keyword, page: page, option: option)
  }
}

@MainActor
@Observable
final class PhotoRecentTagsModel {
  private let service: any PhotoFeedServing
  private var loadedBoardID: Int?
  private var generation = 0
  private(set) var tags: [PhotoPostTag] = []
  private(set) var isLoading = false
  private(set) var error: String?

  init(service: any PhotoFeedServing) { self.service = service }

  func load(boardID: Int?, force: Bool = false) async {
    guard let boardID, boardID > 0,
      force || loadedBoardID != boardID
    else { return }
    generation += 1
    let currentGeneration = generation
    isLoading = true
    error = nil
    defer { if generation == currentGeneration { isLoading = false } }
    do {
      let tags = try await service.recentTags(boardID: boardID)
      try Task.checkCancellation()
      guard generation == currentGeneration else { return }
      self.tags = tags
      loadedBoardID = boardID
    } catch is CancellationError {
      return
    } catch {
      guard generation == currentGeneration else { return }
      self.error = "최근 태그를 불러오지 못했어요."
    }
  }
}

private struct PhotoSearchResults<Header: View>: View {
  let request: PhotoSearchRequest
  let detailService: any PhotoPostDetailServing
  let recentTags: PhotoRecentTagsModel
  let onSelectTag: (PhotoPostTag) -> Void
  let header: Header
  @State private var model: PhotoFeedViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    request: PhotoSearchRequest, service: any PhotoFeedServing,
    detailService: any PhotoPostDetailServing, recentTags: PhotoRecentTagsModel,
    onSelectTag: @escaping (PhotoPostTag) -> Void, @ViewBuilder header: () -> Header
  ) {
    self.request = request
    self.detailService = detailService
    self.recentTags = recentTags
    self.onSelectTag = onSelectTag
    self.header = header()
    _model = State(
      initialValue: PhotoFeedViewModel(
        service:
          PhotoSearchResultsService(
            source: service, keyword: request.keyword, option: request.option)))
  }

  var body: some View {
    GeometryReader { geometry in
      let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
      let width = max((geometry.size.width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns), 1)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          tagsSection
          Text(request.keyword.isEmpty ? "최근 사진" : "\(request.option.label) 검색 결과")
            .font(.headline)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("explore-results-heading")
            .accessibilityAddTraits(.isHeader)
          results(columns: columns, width: width)
        }
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        await model.refresh()
        await recentTags.load(boardID: model.boardID, force: true)
      }
    }
    .task { await model.loadIfNeeded() }
    .task(id: model.boardID) { await recentTags.load(boardID: model.boardID) }
  }

  @ViewBuilder
  private var tagsSection: some View {
    if !recentTags.tags.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("최근 태그").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(recentTags.tags) { tag in
              Button {
                onSelectTag(tag)
              } label: {
                Text("#\(tag.name)")
                  .font(.subheadline)
                  .padding(.horizontal, 14)
                  .frame(minHeight: 44)
                  .background(Color(.secondarySystemBackground), in: Capsule())
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("explore-tag-\(tag.id)")
            }
          }
          .padding(.horizontal, 16)
        }
      }
    } else if recentTags.isLoading {
      ProgressView("최근 태그를 불러오는 중…").font(.caption).padding(.horizontal, 16)
    }
    if let error = recentTags.error {
      HStack {
        Text(error).font(.caption).foregroundStyle(.secondary)
        Button("재시도") { Task { await recentTags.load(boardID: model.boardID, force: true) } }
          .font(.caption)
          .accessibilityIdentifier("explore-tags-retry")
      }
      .padding(.horizontal, 16)
    }
  }

  @ViewBuilder
  private func results(columns: Int, width: CGFloat) -> some View {
    switch model.state {
    case .idle, .loading:
      ProgressView("사진을 불러오는 중…").frame(maxWidth: .infinity).padding(32)
    case .empty:
      if request.keyword.isEmpty {
        ContentUnavailableView("아직 사진이 없어요", systemImage: "photo.on.rectangle")
      } else {
        ContentUnavailableView.search(text: request.keyword)
      }
    case .failed(let message):
      ContentUnavailableView {
        Label("사진을 불러오지 못했어요", systemImage: "wifi.exclamationmark")
      } description: {
        Text(message)
      } actions: {
        Button("다시 시도") { Task { await model.retry() } }
      }
    case .loaded(let posts):
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
        alignment: .leading, spacing: 24
      ) {
        ForEach(posts) { post in
          NavigationLink {
            PhotoPostDetailView(postID: post.id, service: detailService)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              CachedAsyncPhotoImage(
                url: post.coverURL, targetSize: CGSize(width: width, height: width * 1.25)
              ) { phase in
                if case .success(let image) = phase {
                  image.resizable().scaledToFill()
                } else {
                  Rectangle().fill(Color(.secondarySystemBackground))
                    .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                }
              }
              .frame(width: width, height: width * 1.25)
              .clipped()
              Text(post.title).font(.subheadline).lineLimit(2)
              Text(post.writer.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("photo-search-result")
        }
      }
      .padding(.horizontal, 16)
      if model.isLoadingMore {
        ProgressView().frame(maxWidth: .infinity)
      } else if let message = model.loadMoreError {
        Text(message).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
        Button("다시 시도") { Task { await model.loadMore() } }.frame(maxWidth: .infinity)
      } else if model.hasMorePages {
        Button("사진 더 보기") { Task { await model.loadMore() } }.frame(maxWidth: .infinity).padding()
      }
      if let message = model.refreshError {
        Text(message).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
        Button("새로고침 재시도") { Task { await model.refresh() } }.frame(maxWidth: .infinity)
      }
    }
  }
}
