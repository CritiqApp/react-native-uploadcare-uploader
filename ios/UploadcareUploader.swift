import Foundation

@objc(UploadcareUploader)
class UploadcareUploader: RCTEventEmitter {

    // MARK - Event handler configuration
    
    @objc open override func supportedEvents() -> [String] {
        return [
            "new_upload_session",
            "upload_session_progress",
            "media_uuid_created",
        ]
    }
    
    // MARK - Upload methods

    @objc(upload:filePath:mimeType:metaData:withResolver:withRejecter:)
    func upload(key: String, filePath path: String, mimeType type: String, metaData data:Dictionary<String, Any>, resolve:@escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        
        let handler = UploadHandler(key, path: path, mimeType: type, metaData: data)
        handler.successCallback = { uuid in resolve(uuid) }
        handler.progressCallback = { current, total in
            self.sendEvent(withName: "upload_session_progress", body: [
                "current": current,
                "total": total,
                "session_id": handler.sessionId,
            ])
        }
        handler.uuidCallback = { uuid in
            self.sendEvent(withName: "media_uuid_created", body: [ "session_id": handler.sessionId, "uuid": uuid ])
        }
        handler.errorCallback = { type, description, error in
            reject(type, description, error)
        }
        sendEvent(withName: "new_upload_session", body: handler.sessionId)
        handler.upload()
    }
}


