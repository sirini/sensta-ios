import Foundation
import Observation
import SwiftUI

struct PhotographerProfile: Sendable {
  let writer: PhotoPostWriter
  let signature: String
  let posts: [PhotoPost]
  let unavailableCount: Int
  var badges: [BoardBadgeDTO] = []
  var summary: PhotographerSummary? = nil
}

struct PhotographerSummary: Decodable, Sendable {
  let postCount: Int
  let photoCount: Int
  let likeCount: Int
}

struct PhotographerSummaryDTO: Decodable {
  let success: Bool
  let code: Int
  let error: String
  let result: PhotographerSummary?
  func checked() throws -> PhotographerSummary {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result, result.postCount >= 0, result.photoCount >= 0, result.likeCount >= 0 else {
      throw NuboAPIError.malformedResponse
    }
    return result
  }
}

enum PhotographerEndpoint {
  static func summaryRequest(baseURL: URL, userID: Int) throws -> URLRequest {
    guard userID > 0 else { throw NuboAPIError.invalidRequest }
    var components = URLComponents(
      url: baseURL.appending(path: "board/user/summary"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "id", value: "photo"),
      URLQueryItem(name: "targetUserUid", value: String(userID)),
    ]
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  static func request(baseURL: URL, userID: Int, latest: Bool = false) throws -> URLRequest {
    guard userID > 0 else { throw NuboAPIError.invalidRequest }
    var components = URLComponents(
      url: baseURL.appending(path: latest ? "board/user/latest" : "auth/user/info"),
      resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "targetUserUid", value: String(userID))]
    if latest { components.queryItems?.append(URLQueryItem(name: "limit", value: "12")) }
    guard let url = components.url else { throw NuboAPIError.invalidRequest }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

struct PhotographerInfoDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: Info?
  struct Info: Decodable {
    let uid: Int
    let name: String
    let profile: String
    let signature: String
    let blocked: Bool
    let badges: [BoardBadgeDTO]?
  }
  func checked(userID: Int) throws -> Info {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result, result.uid == userID, !result.blocked else {
      throw NuboAPIError.invalidResponse
    }
    return result
  }
}

struct PhotographerLatestDTO: Decodable {
  let success: Bool
  let error: String
  let code: Int
  let result: Latest?
  struct Latest: Decodable { let posts: [Post] }
  struct Post: Decodable {
    let postUid: Int
    let board: Board
    struct Board: Decodable { let id: String }
  }
  func photoIDs() throws -> [Int] {
    guard success, code == 0 else { throw NuboAPIError.server(code: code, message: error) }
    guard let result else { throw NuboAPIError.malformedResponse }
    var seen = Set<Int>()
    return result.posts.filter {
      $0.board.id == "photo" && $0.postUid > 0 && seen.insert($0.postUid).inserted
    }.prefix(12).map(\.postUid)
  }
}

@MainActor @Observable
final class PhotographerModel {
  private(set) var profile: PhotographerProfile?
  private(set) var isLoading = false
  private(set) var error: String?
  func load(userID: Int, service: any PhotoPostDetailServing) async {
    guard !isLoading else { return }
    isLoading = true
    error = nil
    defer { isLoading = false }
    do {
      let profile = try await service.fetchPhotographer(id: userID)
      try Task.checkCancellation()
      self.profile = profile
    } catch is CancellationError { return } catch {
      self.error = "사진가 정보를 불러오지 못했어요. 잠시 뒤 다시 시도해 주세요."
    }
  }
}

struct PhotographerView: View {
  let writer: PhotoPostWriter
  let service: any PhotoPostDetailServing
  @State private var model = PhotographerModel()
  @State private var selectedBadge: BoardBadgeDTO?
  @ScaledMetric(relativeTo: .title2) private var badgeIconHeight = 28
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    GeometryReader { geometry in
      let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
      let width = max(1, (geometry.size.width - 32 - CGFloat(count - 1) * 12) / CGFloat(count))
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if let profile = model.profile {
            header(profile)
            communitySummary(profile)
            achievements(profile.badges)
            Text("최근 작품").font(.headline).accessibilityAddTraits(.isHeader)
            if profile.posts.isEmpty && profile.unavailableCount == 0 {
              ContentUnavailableView("아직 공개된 사진이 없어요", systemImage: "photo.on.rectangle")
            }
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count),
              spacing: 24
            ) {
              ForEach(profile.posts) { post in
                NavigationLink {
                  PhotoPostDetailView(postID: post.id, service: service)
                } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    CachedAsyncPhotoImage(
                      url: post.coverURL, targetSize: CGSize(width: width, height: width * 1.25)
                    ) { phase in
                      if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                      } else {
                        Rectangle().fill(Color(.secondarySystemBackground)).overlay {
                          Image(systemName: "photo").foregroundStyle(.tertiary)
                        }
                      }
                    }.frame(width: width, height: width * 1.25).clipped()
                    Text(post.title).font(.subheadline).lineLimit(2)
                  }.frame(width: width, alignment: .leading).foregroundStyle(.primary)
                }.buttonStyle(.plain).accessibilityIdentifier("photographer-photo")
              }
            }
            if profile.unavailableCount > 0 {
              Text("일부 작품을 불러오지 못했어요.").font(.caption).foregroundStyle(.secondary)
              retry
            }
          }
          if model.isLoading { ProgressView("사진가의 작품을 불러오는 중…").frame(maxWidth: .infinity) }
          if let error = model.error {
            Text(error).foregroundStyle(.secondary)
            retry
          }
        }.padding(16)
      }.refreshable { await model.load(userID: writer.id, service: service) }
    }
    .sheet(item: $selectedBadge) { badge in
      VStack(spacing: 20) {
        Image(systemName: badge.symbol).font(.system(size: 38, weight: .light)).padding(.top, 24)
        Text(badge.name).font(.title2.weight(.semibold))
        Text(badge.description.nuboPlainText).font(.body).multilineTextAlignment(.center)
        if badge.earnedAt > 0 {
          Text(
            Date(timeIntervalSince1970: Double(badge.earnedAt) / 1000),
            format: .dateTime.year().month().day()
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Button("닫기") { selectedBadge = nil }.padding(.top, 8)
      }.padding(24).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    .navigationTitle("사진가")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .task { if model.profile == nil { await model.load(userID: writer.id, service: service) } }
  }

  private func communitySummary(_ profile: PhotographerProfile) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 3
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), alignment: .center), count: columns),
        alignment: .leading, spacing: 16
      ) {
        metric("작품", value: profile.summary?.postCount)
        metric("사진", value: profile.summary?.photoCount)
        metric("받은 좋아요", value: profile.summary?.likeCount)
      }
      if profile.summary == nil {
        HStack {
          Text("통계를 불러오지 못했어요.").font(.caption).foregroundStyle(.secondary)
          Button("재시도") { Task { await model.load(userID: writer.id, service: service) } }.font(
            .caption)
        }
      }
    }.padding(16).background(
      Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
  }

  private func metric(_ name: String, value: Int?) -> some View {
    VStack(alignment: .center, spacing: 6) {
      Text(value.map { $0.formatted() } ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
      Text(name).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(name).accessibilityValue(value.map(String.init) ?? "불러오지 못함")
      .accessibilityIdentifier("photographer-stat-\(name)")
  }

  @ViewBuilder
  private func achievements(_ badges: [BoardBadgeDTO]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("업적").font(.headline).accessibilityAddTraits(.isHeader)
        Text("\(badges.count)").font(.subheadline).foregroundStyle(.secondary)
      }
      if badges.isEmpty {
        Text("사진과 이야기를 나누며 업적을 쌓아가고 있어요.").font(.subheadline).foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 12) {
            ForEach(badges) { badge in
              Button {
                selectedBadge = badge
              } label: {
                VStack(alignment: .leading, spacing: 10) {
                  Image(systemName: badge.symbol).font(.title2.weight(.light))
                    .frame(height: badgeIconHeight)
                  Text(badge.name).font(.subheadline.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                }.frame(width: dynamicTypeSize.isAccessibilitySize ? 220 : 140, alignment: .leading)
                  .padding(16).background(
                    Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)
                  )
                  .contentShape(Rectangle())
              }.buttonStyle(.plain).accessibilityIdentifier("photographer-badge-\(badge.key)")
                .accessibilityLabel(badge.name).accessibilityHint("업적 설명 보기")
            }
          }
        }
      }
    }
  }

  private var retry: some View {
    Button("다시 시도") { Task { await model.load(userID: writer.id, service: service) } }
      .accessibilityIdentifier("photographer-retry")
  }

  private func header(_ profile: PhotographerProfile) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      CachedAsyncPhotoImage(
        url: profile.writer.profileURL, targetSize: CGSize(width: 64, height: 64)
      ) { phase in
        if case .success(let image) = phase {
          image.resizable().scaledToFill()
        } else {
          Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary)
        }
      }.frame(width: 64, height: 64).clipShape(Circle()).accessibilityHidden(true)
      Text(profile.writer.name).font(.title2.weight(.semibold)).accessibilityIdentifier(
        "photographer-name")
      if !profile.signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(profile.signature).font(.subheadline).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
    }.padding(.vertical, 12)
  }
}

extension BoardBadgeDTO: Identifiable {
  var id: String { key }
  var symbol: String {
    switch iconKey {
    case "notebook-pen": "square.and.pencil"
    case "message-circle": "bubble.left"
    case "aperture": "camera.aperture"
    default: "rosette"
    }
  }
}
