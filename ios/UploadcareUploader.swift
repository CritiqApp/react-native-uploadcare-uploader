import Foundation

@objc(UploadcareUploader)
class UploadcareUploader: NSObject {

    @objc(upload:filePath:mimeType:withResolver:withRejecter:)
    func upload(key: String, filePath path: String, mimeType type: String, resolve:@escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        
        let handler = UploadHandler(key, path: path, mimeType: type)
        handler.successCallback = { uuid in resolve(uuid) }
        handler.errorCallback = { type, description, error in
            print(type, description, error)
            reject(type, description, error)
        }
        handler.upload()
    }
}


