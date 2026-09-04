import SwiftUI

struct ContentView: View {
  @State private var model: PhotoFeedViewModel

  init(service: any PhotoFeedServing) {
    _model = State(initialValue: PhotoFeedViewModel(service: service))
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
          PhotoFeedList(posts: posts) {
            await model.refresh()
          }
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
  let onRefresh: @MainActor @Sendable () async -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 20) {
        ForEach(posts) { post in
          PhotoFeedCard(post: post)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 16)
    }
    .background(Color.secondary.opacity(0.06))
    .refreshable {
      await onRefresh()
    }
  }
}

private struct PhotoFeedCard: View {
  let post: PhotoPost

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      writerHeader
        .padding(14)

      cover

      VStack(alignment: .leading, spacing: 10) {
        Text(post.title)
          .font(.headline)
          .lineLimit(2)

        ViewThatFits(in: .horizontal) {
          HStack(spacing: 16) {
            counts
            Spacer()
            submittedDate
          }

          VStack(alignment: .leading, spacing: 8) {
            counts
            submittedDate
          }
        }
        .font(.caption)
      }
      .padding(14)
    }
    .background(.background)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(.quaternary, lineWidth: 0.5)
    }
    .accessibilityElement(children: .contain)
  }

  private var writerHeader: some View {
    HStack(spacing: 10) {
      profileImage

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(post.writer.name)
            .font(.subheadline.weight(.semibold))
          if post.writer.badgeKeys.contains("sensta-app") {
            Image(systemName: "camera.aperture")
              .font(.caption)
              .foregroundStyle(.tint)
              .accessibilityLabel("SENSTA 앱 포토그래퍼")
          }
        }
        Text("PHOTOGRAPHER")
          .font(.caption2)
          .tracking(1)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }

  @ViewBuilder
  private var profileImage: some View {
    if let url = post.writer.profileURL {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.tertiary)
        }
      }
      .frame(width: 38, height: 38)
      .clipShape(Circle())
      .accessibilityLabel("\(post.writer.name) 프로필 사진")
    } else {
      Image(systemName: "person.crop.circle.fill")
        .resizable()
        .foregroundStyle(.tertiary)
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
      .foregroundStyle(.secondary)
  }

  private var cover: some View {
    ZStack {
      Color.secondary.opacity(0.12)

      if let coverURL = post.coverURL {
        AsyncImage(url: coverURL) { phase in
          switch phase {
          case .empty:
            ProgressView()
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          case .failure:
            missingPhoto
          @unknown default:
            EmptyView()
          }
        }
      } else {
        missingPhoto
      }
    }
    .aspectRatio(4 / 5, contentMode: .fit)
    .clipped()
    .accessibilityLabel(post.title)
  }

  private var missingPhoto: some View {
    Image(systemName: "photo")
      .font(.largeTitle)
      .foregroundStyle(.secondary)
  }

  private func countLabel(_ systemImage: String, count: Int, name: String) -> some View {
    Label(String(count), systemImage: systemImage)
      .foregroundStyle(.secondary)
      .accessibilityLabel("\(name) \(count)개")
  }
}

#Preview {
  ContentView(service: PreviewPhotoFeedService())
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
