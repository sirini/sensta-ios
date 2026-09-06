import Foundation
import Testing

@testable import SENSTA

struct PushNotificationsTests {
  @Test
  func deviceRequestsUseAuthenticatedIOSContract() throws {
    let baseURL = try #require(URL(string: "https://sensta.me/goapi/"))
    let installationID = "abcdefghijklmnopqrstuvwxyz123456"

    for request in [
      try PushDeviceEndpoint.register(baseURL: baseURL, installationID: installationID),
      try PushDeviceEndpoint.unregister(baseURL: baseURL, installationID: installationID),
    ] {
      #expect(request.url?.path == "/goapi/push/device")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
      let bodyData = try #require(request.httpBody)
      let body = try #require(
        JSONSerialization.jsonObject(with: bodyData) as? [String: String])
      #expect(body == ["token": installationID, "platform": "ios"])
    }

    #expect(
      try PushDeviceEndpoint.register(baseURL: baseURL, installationID: installationID).httpMethod
        == "POST")
    #expect(
      try PushDeviceEndpoint.unregister(baseURL: baseURL, installationID: installationID)
        .httpMethod == "DELETE")
    #expect(throws: NuboAPIError.invalidRequest) {
      try PushDeviceEndpoint.register(baseURL: baseURL, installationID: "short")
    }
  }

  @Test
  func remotePayloadRoutesMessagesAndPhotoActivity() {
    #expect(
      RemoteNotificationDestination.make(from: [
        "type": "4", "fromUserUid": "27", "postUid": "0",
      ]) == .directMessage(27))
    #expect(
      RemoteNotificationDestination.make(from: [
        "type": NSNumber(value: 2), "fromUserUid": NSNumber(value: 9),
        "postUid": NSNumber(value: 101),
      ]) == .post(101))
    #expect(RemoteNotificationDestination.make(from: ["type": "4"]) == nil)
    #expect(
      RemoteNotificationDestination.make(from: ["type": "2", "postUid": "0"]) == nil)
  }

  @Test
  func pushResponseRejectsServerFailure() throws {
    let success = try JSONDecoder().decode(
      PushDeviceResponseDTO.self,
      from: Data(#"{"success":true,"error":"","code":0,"result":null}"#.utf8))
    try success.checked()

    let failure = try JSONDecoder().decode(
      PushDeviceResponseDTO.self,
      from: Data(#"{"success":false,"error":"invalid push device","code":2}"#.utf8))
    #expect(throws: NuboAPIError.self) { try failure.checked() }
  }
}
