import SwiftUI

struct PhotoSearchView: View {
  let service: any PhotoFeedServing
  let detailService: any PhotoPostDetailServing
  @State private var draft = ""
  @State private var query = ""

  var body: some View {
    Group {
      if query.isEmpty {
        ContentUnavailableView(
          "사진을 찾아보세요", systemImage: "magnifyingglass",
          description: Text("사진 제목에 담긴 단어로 검색할 수 있어요."))
      } else {
        PhotoSearchResults(query: query, service: service, detailService: detailService)
          .id(query)
      }
    }
    .navigationTitle("사진 찾기")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .searchable(
      text: $draft, placement: .navigationBarDrawer(displayMode: .always), prompt: "사진 제목 검색"
    )
    .onSubmit(of: .search) { query = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    .onChange(of: draft) { _, value in
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { query = "" }
    }
  }
}

struct PhotoSearchResultsService: PhotoFeedServing {
  let source: any PhotoFeedServing
  let keyword: String
  func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
    try await source.search(keyword, page: page)
  }
}

private struct PhotoSearchResults: View {
  let query: String
  let detailService: any PhotoPostDetailServing
  @State private var model: PhotoFeedViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(query: String, service: any PhotoFeedServing, detailService: any PhotoPostDetailServing) {
    self.query = query
    self.detailService = detailService
    _model = State(
      initialValue: PhotoFeedViewModel(
        service: PhotoSearchResultsService(source: service, keyword: query)))
  }

  var body: some View {
    Group {
      switch model.state {
      case .idle, .loading:
        ProgressView("사진을 찾는 중…")
      case .empty:
        ContentUnavailableView.search(text: query)
      case .failed(let message):
        ContentUnavailableView {
          Label("검색 결과를 불러오지 못했어요", systemImage: "wifi.exclamationmark")
        } description: {
          Text(message)
        } actions: {
          Button("다시 시도") { Task { await model.retry() } }
        }
      case .loaded(let posts):
        GeometryReader { geometry in
          let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
          let width = max(
            (geometry.size.width - 32 - CGFloat(columnCount - 1) * 12) / CGFloat(columnCount), 1)
          ScrollView {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount),
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
            .padding(16)
            if model.isLoadingMore {
              ProgressView().padding()
            } else if let message = model.loadMoreError {
              Text(message).font(.subheadline).foregroundStyle(.secondary)
              Button("다시 시도") { Task { await model.loadMore() } }.padding()
            } else if model.hasMorePages {
              Button("사진 더 보기") { Task { await model.loadMore() } }.padding()
            }
            if let message = model.refreshError {
              Text(message).font(.subheadline).foregroundStyle(.secondary)
              Button("새로고침 재시도") { Task { await model.refresh() } }.padding()
            }
          }
          .refreshable { await model.refresh() }
        }
      }
    }
    .task { await model.loadIfNeeded() }
  }
}
