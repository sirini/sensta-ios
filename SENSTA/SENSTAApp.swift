import Foundation
import SwiftUI

@main
struct SENSTAApp: App {
  @UIApplicationDelegateAdaptor(SENSTAAppDelegate.self) private var appDelegate
  @State private var account: AccountSession
  @State private var pushNotifications = PushNotificationManager.shared
  private let photoFeedService: any PhotoFeedServing
  private let photoPostDetailService: any PhotoPostDetailServing

  init() {
    let baseURL =
      (try? AppConfiguration.load(from: Bundle.main.infoDictionary ?? [:]))?.apiBaseURL
      ?? URL(string: "about:blank")!
    _account = State(
      initialValue: AccountSession(
        service: AccountService(baseURL: baseURL),
        store: KeychainAccountStore(
          service: (Bundle.main.bundleIdentifier ?? "me.sensta.ios") + ".account."
            + baseURL.absoluteString), apiBaseURL: baseURL))
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
        _account = State(
          initialValue: AccountSession(
            service: AccountUITestService(), store: AccountUITestStore(), apiBaseURL: baseURL)
        )
      }
      if ProcessInfo.processInfo.arguments.contains("--ui-test-viewer") {
        photoFeedService = PaginationUITestService()
        photoPostDetailService = PhotoViewerUITestService()
        return
      }
      if ProcessInfo.processInfo.arguments.contains("--ui-test-pagination") {
        photoFeedService = PaginationUITestService()
        photoPostDetailService = UnavailablePhotoPostDetailService()
        return
      }
    #endif
    if let configuration = try? AppConfiguration.load(
      from: Bundle.main.infoDictionary ?? [:]
    ) {
      photoFeedService = PhotoFeedService(apiBaseURL: configuration.apiBaseURL)
      photoPostDetailService = PhotoPostDetailService(apiBaseURL: configuration.apiBaseURL)
    } else {
      photoFeedService = UnavailablePhotoFeedService()
      photoPostDetailService = UnavailablePhotoPostDetailService()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(
        service: photoFeedService, detailService: photoPostDetailService,
        pushNotifications: pushNotifications)
        .accountSession(account)
        .environment(\.accountSession, account)
        .task { await account.restore() }
        .task(id: account.sessionIdentity) {
          await pushNotifications.synchronize(with: account)
        }
        .onOpenURL { _ = GoogleSignInClient.handle($0) }
        #if DEBUG
          .preferredColorScheme(
            ProcessInfo.processInfo.arguments.contains("--ui-test-dark")
              ? .dark : ProcessInfo.processInfo.arguments.contains("--ui-test-light") ? .light : nil
          )
          .transformEnvironment(\.dynamicTypeSize) { size in
            if ProcessInfo.processInfo.arguments.contains("--ui-test-large-text") {
              size = .accessibility3
            }
          }
        #endif
    }
  }
}

#if DEBUG
  // 운영 데이터에 의존하지 않고 페이지 경계와 재시도 UI를 검증하는 전용 시나리오다.
  private actor PaginationUITestService: PhotoFeedServing {
    private var failedSecondPage = false
    func recentTags(boardID: Int) async throws -> [PhotoPostTag] {
      [PhotoPostTag(id: 10, name: "풍경"), PhotoPostTag(id: 11, name: "빛")]
    }

    func search(_ keyword: String, page: Int, option: PhotoSearchOption) async throws
      -> PhotoFeedPage
    {
      if keyword == "empty" { return PhotoFeedPage(totalPostCount: 0, posts: []) }
      let result = try await fetchPage(1)
      return PhotoFeedPage(totalPostCount: result.posts.count, posts: result.posts, boardID: 2)
    }

    func fetchPage(_ page: Int) async throws -> PhotoFeedPage {
      if page == 2 && !failedSecondPage {
        failedSecondPage = true
        throw NuboAPIError.networkUnavailable
      }
      let ids = page == 1 ? Array(1...4) : page == 2 ? Array(5...6) : []
      return PhotoFeedPage(
        totalPostCount: 6,
        posts: ids.map { id in
          PhotoPost(
            id: id, title: "테스트 사진 \(id)", content: "", submitted: .now,
            viewCount: 0, coverURL: nil, commentCount: 0, likeCount: 0, isLiked: false,
            writer: PhotoPostWriter(id: 1, name: "테스트 사진가", profileURL: nil, badgeKeys: [])
          )
        },
        hasMorePages: page == 1, boardID: 2
      )
    }
  }
#endif

#if DEBUG
  private actor PhotoViewerUITestService: PhotoPostDetailServing {
    private var commentAttempts = 0

    private var photographerAttempts = 0
    func fetchPhotographer(id: Int) async throws -> PhotographerProfile {
      photographerAttempts += 1
      if photographerAttempts == 1
        && !ProcessInfo.processInfo.arguments.contains("--ui-test-achievements")
        && !ProcessInfo.processInfo.arguments.contains("--ui-test-messages")
        && !ProcessInfo.processInfo.arguments.contains("--ui-test-safety")
      {
        throw NuboAPIError.networkUnavailable
      }
      let post = try await fetchPost(id: 1).post
      return PhotographerProfile(
        writer: post.writer, signature: "빛과 여백, 일상 속 작은 순간을 기록합니다.", posts: [post],
        unavailableCount: 0,
        badges: [
          BoardBadgeDTO(
            key: "sensta-app", name: "SENSTA 앱 포토그래퍼", description: "SENSTA 앱으로 사진을 공유한 사용자입니다.",
            iconKey: "aperture", earnedAt: 1_788_410_731_496),
          BoardBadgeDTO(
            key: "first-post", name: "첫 발자국", description: "첫 게시글을 작성했습니다.",
            iconKey: "notebook-pen", earnedAt: 1_788_410_731_496),
        ], summary: PhotographerSummary(postCount: 24, photoCount: 58, likeCount: 132))
    }
    func fetchComments(boardID: Int, postID: Int, page: Int) async throws -> PhotoCommentsPage {
      commentAttempts += 1
      if commentAttempts == 1 { throw NuboAPIError.networkUnavailable }
      return PhotoCommentsPage(
        comments: [
          PhotoComment(
            id: page, replyID: 1, writer: "사진가", content: "여백이 아름다운 사진입니다. \(page)",
            submitted: .now, likeCount: 2)
        ], hasMore: page == 1)
    }
    func fetchPost(id: Int) async throws -> PhotoPostDetail {
      let otherUserTest = ProcessInfo.processInfo.arguments.contains("--ui-test-messages")
        || ProcessInfo.processInfo.arguments.contains("--ui-test-safety")
      let post = PhotoPost(
        id: id, title: "빛과 여백", content: "사진의 전체 구도를 감상하세요.",
        submitted: .now, viewCount: 3, coverURL: nil, commentCount: 0, likeCount: 1,
        isLiked: false,
        writer: PhotoPostWriter(
          id: otherUserTest ? 2 : 1, name: otherUserTest ? "알림 사진가" : "사진가",
          profileURL: nil, badgeKeys: []))
      let exif = PhotoExif(
        make: "Panasonic", model: "DC-G100", aperture: 400, iso: 250, focalLength: 40,
        exposure: 16666, width: 900, height: 600, date: nil)
      return PhotoPostDetail(
        post: post,
        images: [1, 2].map {
          PhotoPostImage(
            id: $0, largeURL: nil, smallURL: nil,
            description: "나무 사이로 스며드는 빛과 차분한 여백이 어우러진 풍경입니다. 사진 \($0)", exif: exif)
        },
        tags: [], attachments: [], previousPostID: nil, nextPostID: nil, shareURL: nil, boardID: 2)
    }
  }
#endif

extension ContentView {
  func accountSession(_ account: AccountSession) -> Self {
    var view = self
    view.account = account
    return view
  }
}

#if DEBUG
  private actor AccountUITestService: AccountServing {
    private var liked = false
    private var commentLiked = false
    private var commentID = 100
    private var appleLinked = false
    private var notificationRead = false
    private var userReported = false
    private var userBlocked = false
    private var acknowledgedAchievementKeys = Set<String>()
    private var directMessageID = 102
    func data(for request: URLRequest) async throws -> Data {
      if request.url?.path.hasSuffix("/board/list") == true {
        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
        else { throw NuboAPIError.httpStatus(401) }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        let page = Int(query?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
        let ids = page == 1 ? Array(1...4) : page == 2 ? Array(5...6) : []
        let otherUser = ProcessInfo.processInfo.arguments.contains("--ui-test-safety")
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": [
            "totalPostCount": 6,
            "config": ["uid": 2, "id": "photo", "name": "사진", "rowCount": 4],
            "notices": [],
            "posts": ids.map { boardListItem(uid: $0, writerID: otherUser ? 2 : 1) },
            "blackList": userBlocked ? [2] : [], "isAdmin": false,
          ],
        ])
      }
      if request.url?.path.hasSuffix("/auth/user/report") == true {
        if request.httpMethod == "POST" {
          let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
          guard body["targetUserUid"] as? Int == 2,
            body["checkedBlackList"] as? Bool == false,
            (body["content"] as? String)?.contains("신고:") == true
          else { throw NuboAPIError.invalidRequest }
          userReported = true
          return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
        }
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": ["isReported": userReported, "isBannedByMe": userBlocked],
        ])
      }
      if request.url?.path.hasSuffix("/auth/user/block") == true {
        let body = try JSONDecoder().decode([String: Int].self, from: request.httpBody!)
        guard body["targetUserUid"] == 2 else { throw NuboAPIError.invalidRequest }
        userBlocked = request.httpMethod == "PUT"
        return Data(#"{"success":true,"code":0,"error":"","result":null}"#.utf8)
      }
      if request.url?.path.hasSuffix("/auth/apple/status") == true {
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "result": ["linked": appleLinked],
        ])
      }
      if request.url?.path.hasSuffix("/auth/apple/link/nonce") == true {
        return Data(
          #"{"success":true,"code":0,"result":{"nonce":"ui-test-apple-link-nonce"}}"#.utf8)
      }
      if request.url?.path.hasSuffix("/auth/apple/link") == true {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        guard body["identityToken"] as? String == "ui-test-apple-id-token",
          body["nonce"] as? String == "ui-test-apple-link-nonce"
        else { throw NuboAPIError.httpStatus(401) }
        appleLinked = true
        return Data(#"{"success":true,"code":0,"result":{"linked":true}}"#.utf8)
      }
      if request.url?.path.hasSuffix("/auth/user/achievements") == true {
        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
        else { throw NuboAPIError.httpStatus(401) }
        if request.httpMethod == "PATCH" {
          let body = try JSONDecoder().decode([String: [String]].self, from: request.httpBody!)
          acknowledgedAchievementKeys.formUnion(body["keys"] ?? [])
          return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
        }
        let enabled = ProcessInfo.processInfo.arguments.contains("--ui-test-achievements")
        let badges: [[String: Any]] =
          enabled
          ? [
            [
              "key": "sensta-app", "name": "SENSTA 앱 포토그래퍼",
              "description": "SENSTA 앱으로 사진을 공유한 사용자입니다.",
              "iconKey": "aperture", "earnedAt": 1_788_410_731_496 as Int64,
            ],
            [
              "key": "first-post", "name": "첫 발자국",
              "description": "첫 게시글을 작성했습니다.",
              "iconKey": "notebook-pen", "earnedAt": 1_788_410_731_497 as Int64,
            ],
          ].filter { !acknowledgedAchievementKeys.contains($0["key"] as! String) }
          : []
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "", "result": badges,
        ])
      }
      if request.url?.path.hasSuffix("/chat/list") == true {
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": [
            [
              "sender": ["uid": 2, "name": "알림 사진가", "profile": ""],
              "uid": 102, "message": "다음 사진도 기대할게요.",
              "timestamp": 1_788_600_060_000 as Int64,
            ]
          ],
        ])
      }
      if request.url?.path.hasSuffix("/chat/history") == true {
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": [
            [
              "uid": 101, "userUid": 2, "message": "#여름사진 빛이 참 좋네요.",
              "timestamp": 1_788_600_000_000 as Int64, "readAt": 0,
            ],
            [
              "uid": 102, "userUid": 1, "message": "고맙습니다.",
              "timestamp": 1_788_600_030_000 as Int64,
              "readAt": 1_788_600_040_000 as Int64,
            ],
          ],
        ])
      }
      if request.url?.path.hasSuffix("/chat/read") == true {
        let body = try JSONDecoder().decode([String: Int].self, from: request.httpBody!)
        guard body["targetUserUid"] == 2, body["throughUid"] == 101
        else { throw NuboAPIError.invalidRequest }
        return Data(
          #"{"success":true,"error":"","code":0,"result":{"throughUid":101,"readAt":1788600065000,"updatedCount":1}}"#
            .utf8)
      }
      if request.url?.path.hasSuffix("/chat/save") == true {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        guard body["targetUserUid"] as? Int == 2,
          let message = body["message"] as? String, !message.isEmpty
        else { throw NuboAPIError.invalidRequest }
        if message.contains("reject") {
          return Data(#"{"success":false,"error":"blocked","code":4,"result":null}"#.utf8)
        }
        directMessageID += 1
        return Data(
          "{\"success\":true,\"error\":\"\",\"code\":0,\"result\":\(directMessageID)}".utf8)
      }
      if request.url?.path.hasSuffix("/board/my/studio") == true {
        guard
          request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
        else {
          throw NuboAPIError.httpStatus(401)
        }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        let page = Int(query?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
        let sort = query?.first(where: { $0.name == "sort" })?.value ?? "recent"
        let items: [[String: Any]]
        let totalCount: Int
        let hasNext: Bool
        if sort == "views" {
          items = [studioItem(uid: 201, title: "가장 많이 본 비공개 사진", status: 2, hit: 81)]
          totalCount = 1
          hasNext = false
        } else if page == 2 {
          items = [studioItem(uid: 103, title: "세 번째 작품", status: 0, hit: 9)]
          totalCount = 21
          hasNext = false
        } else {
          items = [
            studioItem(uid: 101, title: "비밀의 빛", status: 2, hit: 41),
            studioItem(uid: 102, title: "푸른 여백", status: 0, hit: 20),
          ]
          totalCount = 21
          hasNext = true
        }
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": [
            "summary": [
              "postCount": totalCount, "photoCount": totalCount + 2, "viewCount": 110,
              "likeCount": 12, "commentCount": 7,
            ],
            "posts": [
              "page": page, "limit": 20, "totalCount": totalCount, "hasNext": hasNext,
              "items": items,
            ],
          ],
        ])
      }
      if request.url?.path.hasSuffix("/home/noti/load") == true {
        let messageTest = ProcessInfo.processInfo.arguments.contains("--ui-test-messages")
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": [
            [
              "uid": 77,
              "fromUser": ["uid": 2, "name": "알림 사진가", "profile": ""],
              "type": messageTest ? 4 : 2, "id": "photo", "boardType": 1,
              "postUid": messageTest ? 0 : 1,
              "checked": notificationRead, "timestamp": 1_788_600_000_000 as Int64,
            ]
          ],
        ])
      }
      if request.httpMethod == "PATCH", request.url?.path.contains("/home/noti/checked") == true {
        notificationRead = true
        return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
      }
      if request.url?.path.hasSuffix("/editor/config") == true {
        return Data(
          #"{"success":true,"code":0,"error":"","result":{"config":{"uid":2,"useCategory":false},"categories":[{"uid":5,"name":"lounge"}]}}"#
            .utf8)
      }
      if request.url?.path.hasSuffix("/editor/suggestion/tag") == true {
        return Data(
          #"{"success":true,"code":0,"error":"","result":[{"uid":31,"name":"여름사진","count":12},{"uid":32,"name":"여름빛","count":7}]}"#
            .utf8)
      }
      if request.httpMethod == "POST", request.url?.path.contains("/comment/") == true {
        if String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("reject") == true {
          return Data(#"{"success":false,"code":3,"result":null}"#.utf8)
        }
        commentID += 1
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "result": commentID,
        ])
      }
      if request.httpMethod == "PATCH" {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        if request.url?.path.hasSuffix("/comment/like") == true {
          commentLiked = body["liked"] as! Bool
        } else if request.url?.path.hasSuffix("/comment/modify") == true {
          if (body["content"] as? String)?.contains("reject") == true {
            return Data(#"{"success":false,"code":3,"result":null}"#.utf8)
          }
        } else {
          liked = body["liked"] as! Bool
        }
        return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
      }
      if request.httpMethod == "DELETE", request.url?.path.hasSuffix("/comment/remove") == true {
        return Data(#"{"success":true,"code":0,"result":null}"#.utf8)
      }
      if request.url?.path.hasSuffix("/comment/list") == true {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        let postID = Int(query?.first(where: { $0.name == "postUid" })?.value ?? "1") ?? 1
        let comment: [String: Any] = [
          "uid": 1, "replyUid": 1, "postUid": postID,
          "writer": ["uid": 2, "name": "사진가", "profile": "", "signature": ""],
          "like": commentLiked ? 3 : 2, "liked": commentLiked,
          "submitted": 1_788_600_000_000 as Int64, "modified": 0, "status": 0,
          "content": "여백이 아름다운 사진입니다.",
        ]
        return try JSONSerialization.data(withJSONObject: [
          "success": true, "code": 0, "error": "",
          "result": ["boardUid": 2, "totalCommentCount": 1, "comments": [comment]],
        ])
      }
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      let postID = Int(query?.first(where: { $0.name == "postUid" })?.value ?? "1") ?? 1
      let studioTitle = postID == 201 ? "가장 많이 본 비공개 사진" : "빛과 여백"
      let result: [String: Any] = [
        "config": ["uid": 2, "id": "photo", "name": "사진", "rowCount": 32],
        "post": [
          "uid": postID, "title": studioTitle, "content": "",
          "submitted": 1_788_600_000_000 as Int64, "modified": 0,
          "hit": 3, "status": postID == 201 ? 2 : 0,
          "category": ["uid": 1, "name": "사진"], "cover": "", "comment": 0,
          "like": liked ? 2 : 1, "liked": liked,
          "writer": ["uid": 1, "name": "사진가", "profile": "", "signature": ""],
        ],
        "images": [], "files": [], "tags": [], "prevPostUid": 0, "nextPostUid": 0,
        "writerPosts": [], "writerComments": [],
      ]
      return try JSONSerialization.data(withJSONObject: [
        "success": true, "code": 0, "error": "", "result": result,
      ])
    }
    func signin(email: String, password: String) async throws -> (AccountUser, AccountTokens) {
      guard password == "test-password" else { throw NuboAPIError.httpStatus(401) }
      return (
        AccountUser(uid: 1, name: "테스트 사진가", id: email, blocked: false),
        AccountTokens(token: "ui-access", refresh: "ui-refresh")
      )
    }
    func signupStatus() async throws -> SignupStatus {
      SignupStatus(
        mode: "verified_email", mailConfigured: true, oauthRegistrationAllowed: true)
    }
    func requestPasswordReset(email: String) async throws {
      guard email == "photo@example.com" else { throw NuboAPIError.invalidRequest }
    }
    func signup(email: String, password: String, name: String, invite: String) async throws
      -> SignupResult
    {
      guard email == "new@example.com", password == "Password!1", name == "새 사진가" else {
        throw NuboAPIError.server(code: 3, message: "")
      }
      return SignupResult(target: 42, requiresVerification: true, completed: false)
    }
    func verifySignup(target: Int, code: String, email: String, password: String, name: String)
      async throws -> Bool
    {
      target == 42 && code == "123456" && email == "new@example.com"
        && password == "Password!1" && name == "새 사진가"
    }
    func signinWithGoogle(idToken: String) async throws -> (AccountUser, AccountTokens) {
      guard idToken == "ui-test-google-id-token" else { throw NuboAPIError.httpStatus(401) }
      return (
        AccountUser(uid: 1, name: "Google 사진가", id: "google@example.com", blocked: false),
        AccountTokens(token: "ui-google-access", refresh: "ui-google-refresh")
      )
    }
    func appleNonce() async throws -> String { "ui-test-apple-nonce" }
    func signinWithApple(identityToken: String, nonce: String, name: String) async throws
      -> (AccountUser, AccountTokens)
    {
      guard identityToken == "ui-test-apple-id-token", nonce == "ui-test-apple-nonce" else {
        throw NuboAPIError.httpStatus(401)
      }
      if ProcessInfo.processInfo.arguments.contains("--ui-test-apple-link-required") {
        throw NuboAPIError.server(
          code: 13, message: "sign in to the existing account and link Apple ID")
      }
      appleLinked = true
      return (
        AccountUser(uid: 1, name: name, id: "apple@example.com", blocked: false),
        AccountTokens(token: "ui-apple-access", refresh: "ui-apple-refresh")
      )
    }
    func load(token: String) async throws -> AccountUser { throw NuboAPIError.httpStatus(401) }
    func refresh(_ refresh: String) async throws -> AccountTokens {
      throw NuboAPIError.httpStatus(401)
    }
    func logout(token: String) async throws {}

    private func studioItem(uid: Int, title: String, status: Int, hit: Int) -> [String: Any] {
      [
        "uid": uid, "title": title, "cover": "",
        "submitted": 1_788_600_000_000 as Int64,
        "modified": 1_788_600_001_000 as Int64,
        "status": status, "imageCount": uid == 101 ? 3 : 1,
        "hit": hit, "like": 4, "comment": 2,
      ]
    }

    private func boardListItem(uid: Int, writerID: Int) -> [String: Any] {
      [
        "uid": uid, "title": "테스트 사진 \(uid)", "content": "",
        "submitted": 1_788_600_000_000 as Int64, "modified": 0, "hit": 0, "status": 0,
        "category": ["uid": 1, "name": "사진"], "cover": "", "comment": 0, "like": 0,
        "liked": false,
        "writer": [
          "uid": writerID, "name": writerID == 2 ? "알림 사진가" : "테스트 사진가",
          "profile": "", "signature": "", "badges": [],
        ],
      ]
    }
  }

  @MainActor private final class AccountUITestStore: AccountTokenStoring {
    private var tokens: AccountTokens?
    func read() throws -> AccountTokens? { tokens }
    func save(_ tokens: AccountTokens) throws { self.tokens = tokens }
    func clear() throws { tokens = nil }
  }
#endif
