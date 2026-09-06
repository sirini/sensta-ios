import Foundation
import Testing

@testable import SENSTA

private let managementBaseURL = URL(string: "https://example.com/goapi/")!

@MainActor private final class ManagementTokenStore: AccountTokenStoring {
  var tokens: AccountTokens? = AccountTokens(token: "manage-access", refresh: "manage-refresh")
  func read() throws -> AccountTokens? { tokens }
  func save(_ tokens: AccountTokens) throws { self.tokens = tokens }
  func clear() throws { tokens = nil }
}

private actor ManagementAccountStub: AccountServing {
  private(set) var requests: [URLRequest] = []

  func data(for request: URLRequest) async throws -> Data {
    requests.append(request)
    if request.url?.path == "/goapi/editor/suggestion/tag" {
      return Data(
        #"{"success":true,"code":0,"error":"","result":[{"uid":1,"name":"여름빛","count":8}]}"#
          .utf8)
    }
    return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
  }

  func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
    (try await load(token: ""), AccountTokens(token: "manage-access", refresh: "manage-refresh"))
  }
  func load(token: String) async throws -> AccountUser {
    AccountUser(uid: 7, name: "나", id: "me@example.com", blocked: false)
  }
  func refresh(_ refresh: String) async throws -> AccountTokens {
    AccountTokens(token: "manage-access-2", refresh: "manage-refresh-2")
  }
  func logout(token: String) async throws {}
}

@MainActor
struct PhotoPostManagementTests {
  @Test
  func endpointsPreservePhotosAndPrivacyWhileMatchingAndroidContract() throws {
    let detail = makeManagementDetail()
    let request = try PhotoPostManagementEndpoint.modify(
      baseURL: managementBaseURL, detail: detail, title: "  바뀐 제목  ",
      content: "  바뀐 설명  ", tags: ["여름", "빛"], boundary: "test-boundary")
    let body = String(data: request.httpBody!, encoding: .utf8)!

    #expect(request.url?.path == "/goapi/editor/modify")
    #expect(request.httpMethod == "PATCH")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Nubo-Client") == "sensta-ios")
    #expect(body.contains("name=\"boardUid\"\r\n\r\n2\r\n"))
    #expect(body.contains("name=\"postUid\"\r\n\r\n101\r\n"))
    #expect(body.contains("name=\"categoryUid\"\r\n\r\n5\r\n"))
    #expect(body.contains("name=\"isSecret\"\r\n\r\ntrue\r\n"))
    #expect(body.contains("name=\"title\"\r\n\r\n바뀐 제목\r\n"))
    #expect(body.contains("name=\"content\"\r\n\r\n바뀐 설명\r\n"))
    #expect(body.contains("name=\"tags\"\r\n\r\n여름,빛\r\n"))
    #expect(!body.contains("attachments[]"))

    let deletion = try PhotoPostManagementEndpoint.delete(
      baseURL: managementBaseURL, boardID: 2, postID: 101)
    let deletionBody = try JSONSerialization.jsonObject(with: deletion.httpBody!) as! [String: Int]
    #expect(deletion.url?.path == "/goapi/board/remove/post")
    #expect(deletion.httpMethod == "DELETE")
    #expect(deletionBody == ["boardUid": 2, "postUid": 101])
  }

  @Test
  func editModelUsesChipsSuggestionsAndAuthenticatedSave() async throws {
    let service = ManagementAccountStub()
    let account = AccountSession(
      service: service, store: ManagementTokenStore(), apiBaseURL: managementBaseURL)
    await account.restore()
    let detail = makeManagementDetail()
    let model = PhotoPostEditModel(detail: detail)

    #expect(model.title == "원래 제목")
    #expect(model.content == "원래 설명")
    #expect(model.tags == ["기존태그"])
    model.updateTagDraft("여름빛")
    await model.loadSuggestions(using: account)
    #expect(model.suggestions.map(\.name) == ["여름빛"])
    model.selectSuggestion(model.suggestions[0])
    model.updateTagDraft("night, 야경 ")
    #expect(model.tags == ["기존태그", "여름빛", "night", "야경"])
    model.removeTag("기존태그")
    model.title = "수정한 제목"
    model.content = "수정한 설명"

    #expect(await model.save(detail: detail, using: account))
    let requests = await service.requests
    let modify = requests.last { $0.url?.path == "/goapi/editor/modify" }
    #expect(modify?.value(forHTTPHeaderField: "Authorization") == "Bearer manage-access")
    let body = String(data: modify!.httpBody!, encoding: .utf8)!
    #expect(body.contains("여름빛,night,야경"))
  }

  @Test
  func ownerCanDeleteThroughAuthenticatedRequest() async throws {
    let service = ManagementAccountStub()
    let account = AccountSession(
      service: service, store: ManagementTokenStore(), apiBaseURL: managementBaseURL)
    await account.restore()

    try await makeManagementDetail().delete(using: account)
    let request = await service.requests.last
    #expect(request?.url?.path == "/goapi/board/remove/post")
    #expect(request?.httpMethod == "DELETE")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer manage-access")
  }

  @Test
  func studioRemovesDeletedPostAndUpdatesSummaryImmediately() async {
    let model = PhotoStudioModel(service: ManagementStudioStub())
    await model.loadIfNeeded()
    model.apply(.deleted(101))
    #expect(model.posts.isEmpty)
    #expect(model.summary?.postCount == 0)
    #expect(model.summary?.photoCount == 0)
    #expect(model.summary?.viewCount == 0)
    #expect(model.summary?.likeCount == 0)
    #expect(model.summary?.commentCount == 0)
  }

  private func makeManagementDetail() -> PhotoPostDetail {
    PhotoPostDetail(
      post: PhotoPost(
        id: 101, title: "원래 제목", content: "<p>원래 설명</p>", submitted: .now,
        viewCount: 4, coverURL: nil, commentCount: 2, likeCount: 3, isLiked: false,
        writer: PhotoPostWriter(id: 7, name: "나", profileURL: nil, badgeKeys: [])),
      images: [], tags: [PhotoPostTag(id: 1, name: "기존태그")], attachments: [],
      previousPostID: nil, nextPostID: nil, shareURL: nil, boardID: 2, categoryID: 5,
      status: 2)
  }
}

private actor ManagementStudioStub: PhotoStudioServing {
  func fetchPage(_ page: Int, sort: PhotoStudioSort) async throws -> PhotoStudioPage {
    PhotoStudioPage(
      summary: PhotoStudioSummary(
        postCount: 1, photoCount: 3, viewCount: 4, likeCount: 3, commentCount: 2),
      page: 1, totalCount: 1, hasNext: false,
      posts: [
        PhotoStudioPost(
          id: 101, title: "원래 제목", coverURL: nil, submitted: .now, modified: .now,
          isPrivate: true, imageCount: 3, viewCount: 4, likeCount: 3, commentCount: 2)
      ])
  }
}
