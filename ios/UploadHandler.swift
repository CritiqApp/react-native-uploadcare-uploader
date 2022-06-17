//
//  UploadHandler.swift
//  react-native-uploadcare-uploader
//
//  Created by Nicho Mercier on 2022-06-16.
//

import Foundation

let DirectUploadThreshold: Int = 10485760
let ChunkSize: Int = 5242880

class UploadHandler: NSObject {
    
    // MARK - API endpoints
    static let StartEndpoint = URL(string: "https://upload.uploadcare.com/multipart/start/")!
    static let CompleteEndpoint = URL(string: "https://upload.uploadcare.com/multipart/complete/")!
    static let DirectEndpoint = URL(string: "https://upload.uploadcare.com/base/")!
    
    // MARK - File related fields
    private var size: Int = 0
    private let mimeType: String
    private let url: URL
    private let sessionId: String = UUID().uuidString
    private var chunks: [URL] = []
    
    // MARK - Uploadcare client fields
    private let key: String
    
    // MARK - Task queue fields
    private let dispatchGroup = DispatchGroup()
    private var tasks: [Int:TaskInfo] = [:]
    private var uploadFailed = false
    private var uploadTotal: Int64 = 0

    // MARK - Callbacks
    public var errorCallback: ((_ type: String, _ description: String, _ error: Error) -> Void)?
    public var successCallback: ((_ uuid: String) -> Void)?
    
    init(_ key: String, path: String, mimeType: String) {
        self.key = key
        self.url = URL(fileURLWithPath: path)
        self.mimeType = mimeType
    }
    
    func upload() {
        
        // Get the file size
        guard let size = try? getFileSize() else {
            errorCallback?("file", "could not get file size", UploadError.file)
            return
        }
        self.size = size
        
        if size >= DirectUploadThreshold {
            uploadMultipart()
        } else {
            uploadDirect(url)
        }
        
    }
    
    // Logic to handle multipart uploading
    private func uploadMultipart() {
        guard let chunks = try? self.chunkFile() else {
            errorCallback?("file", "failed to chunk file", UploadError.file)
            return
        }
        
        // Start the upload
        startMultipart() { response in
            
            if chunks.count != response.parts.count {
                self.errorCallback?("chunk", "chunk mismatch from upload paths", UploadError.parse)
                return
            }
            
            // Pair up the upload parts with the file chunks and upload them
            let session = self.backgroundSession(self.sessionId)
            for (url, file) in zip(response.parts, chunks) {
                let fileUrl = URL(string: url)!
                let task = self.uploadBackground(session, url: fileUrl, file: file)
                self.dispatchGroup.enter()
                self.tasks[task.taskIdentifier] = TaskInfo(task: task, url: fileUrl, file: file)
            }
            self.dispatchGroup.notify(queue: .main) {
                // Check to see if something went wrong
                print (self.uploadFailed)
                if self.uploadFailed {
                    self.errorCallback?("upload", "upload failed", UploadError.network)
                    return
                }
                
                // Complete the upload and return the UUID
                self.completeMultipart(response.uuid) {
                    self.successCallback?(response.uuid)
                }
            }
            
        }
                
    }
    
    // Create a background session for uploading
    private func backgroundSession(_ id: String) -> URLSession {
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // Start a background upload task
    private func uploadBackground(_ session: URLSession, url: URL, file: URL) -> URLSessionTask {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: file)
        task.resume()
        return task
    }
    
    // Build the chunks for multipart upload
    private func chunkFile() throws -> [URL] {
        var chunks: [URL] = []
        let reader = try FileHandle(forReadingFrom: self.url)
        var remaining = size
        
        // Loop through the file bytes and save the chunk
        // data to files
        while remaining > 0 {
            if #available(iOS 13.4, *) {
                let chunkSize = min(remaining, ChunkSize)
                let data = try reader.read(upToCount: chunkSize)
                if let data = data {
                    let url = try self.saveDataToFile("\(sessionId)_\(chunks.count)", data: data)
                    chunks.append(url)
                    remaining -= chunkSize
                } else {
                    throw UploadError.file
                }
            } else {
                throw UploadError.unsupportedIosVersion
            }
        }
        try reader.close()
        
        return chunks
    }
    
    // Get the file size to help determine what upload mode
    // we should use
    private func getFileSize() throws -> Int {
        let resources = try url.resourceValues(forKeys:[.fileSizeKey])
        let fileSize = resources.fileSize!
        return fileSize
    }
    
    // Save a chunk of data to a file
    private func saveDataToFile(_ name: String, data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension("chunk")
        try data.write(to: url)
        return url
    }
    
    // Logic to handle direct uploading
    private func uploadDirect(_ file: URL) {
        let filename = "\(sessionId).\(url.pathExtension)"
        let builder = MultipartRequestBuilder(boundary: sessionId, request:  URLRequest(url: UploadHandler.DirectEndpoint))
        builder.addMultiformValue(key, forName: "UPLOADCARE_PUB_KEY")
        builder.addMultiformValue("auto", forName: "UPLOADCARE_STORE")
        builder.addMultiformValue(filename, forName: "filename")
        builder.addMultiformValue("\(size)", forName: "size")
        builder.addMultiformValue(mimeType, forName: "content_type")
        var request = builder.finalize()
        request.httpMethod = "POST"
        
        let session = URLSession.shared
        let task = session.uploadTask(with: request, fromFile: file) { data, response, error in
            DispatchQueue.main.async {
                guard let response = response as? HTTPURLResponse else {
                    self.errorCallback?("direct", "direct request failed", UploadError.network)
                    return
                }
                
                if let error = error {
                    self.errorCallback?("direct", "direct request failed", error)
                    return
                }
                
                if response.statusCode < 200 || response.statusCode >= 300 {
                    self.errorCallback?("direct", "server responded with a bad status code", UploadError.network)
                    return
                }
    
                let decoder = JSONDecoder()
                guard let json = try? decoder.decode([String:String].self, from: data!) else {
                    self.errorCallback?("direct", "decoding response failed", UploadError.parse)
                    return
                }
                
                guard let uuid = json[filename] else {
                    self.errorCallback?("direct upload", "uuid not found", UploadError.parse)
                    return
                }
                self.successCallback?(uuid)
            }
        }
        task.resume()
        
    }
    
    // Create a multipart upload session with Uploadcare
    private func startMultipart(_ callback: @escaping (_ response: StartResponse) -> Void) {

        let builder = MultipartRequestBuilder(boundary: sessionId, request: URLRequest(url: UploadHandler.StartEndpoint))
        builder.addMultiformValue(key, forName: "UPLOADCARE_PUB_KEY")
        builder.addMultiformValue("auto", forName: "UPLOADCARE_STORE")
        builder.addMultiformValue("\(sessionId).\(url.pathExtension)", forName: "filename")
        builder.addMultiformValue("\(size)", forName: "size")
        builder.addMultiformValue(mimeType, forName: "content_type")
        builder.addMultiformValue("\(ChunkSize)", forName: "part_size")
        var request = builder.finalize()
        request.httpMethod = "POST"
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let response = response as? HTTPURLResponse else {
                    self.errorCallback?("start multipart", "multipart start request failed", UploadError.network)
                    return
                }
                
                if let error = error {
                    self.errorCallback?("start multipart", "multipart start request failed", error)
                    return
                }
                
                if response.statusCode < 200 || response.statusCode >= 300 {
                    self.errorCallback?("complete multipart", "server responded with a bad status code", UploadError.network)
                    return
                }
                
    
                let decoder = JSONDecoder()
                guard let json = try? decoder.decode(StartResponse.self, from: data!) else {
                    self.errorCallback?("start multipart", "decoding response failed", UploadError.parse)
                    return
                }
                
                callback(json)
            }
        }
        task.resume()
    }
    
    // Create a multipart upload session with Uploadcare
    private func completeMultipart(_ uuid: String, _ callback: @escaping () -> Void) {

        let builder = MultipartRequestBuilder(boundary: sessionId, request:  URLRequest(url: UploadHandler.CompleteEndpoint))
        builder.addMultiformValue(key, forName: "UPLOADCARE_PUB_KEY")
        builder.addMultiformValue(uuid, forName: "uuid")
        var request = builder.finalize()
        request.httpMethod = "POST"
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let response = response as? HTTPURLResponse else {
                    self.errorCallback?("complete multipart", "multipart complete request failed", UploadError.network)
                    return
                }
                
                if let error = error {
                    self.errorCallback?("complete multipart", "multipart complete request failed", error)
                    return
                }
                
                if response.statusCode < 200 || response.statusCode >= 300 {
                    self.errorCallback?("complete multipart", "server responded with bad status code", UploadError.network)
                    return
                }
                callback()
            }
        }
        task.resume()
    }
    
}

// Handle the URL session delegates
extension UploadHandler: URLSessionDelegate, URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Needs this delegate
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                
        // If upload is already marked as failed, leave the
        // dispatch group
        if uploadFailed {
            dispatchGroup.leave()
            return
        }
        
        // If the task is not mapped, something went wrong
        // fail the upload and leave the dispatch group
        guard let taskMapping = self.tasks[task.taskIdentifier] else {
            self.uploadFailed = true
            dispatchGroup.leave()
            return
        }
        
        // Check for a valid response
        if let response = task.response as? HTTPURLResponse {
            if response.statusCode < 200 || response.statusCode >= 300 {
                self.uploadFailed = true
                dispatchGroup.leave()
                return
            }
        }
        
        // If we caught an error or response indicates a server error
        // retry a few times. After 5 retries, fail the upload and
        // leave the dispatch group
        if error != nil {
            if taskMapping.retries < 5 {
                // Attempt to retry this upload
                let url = taskMapping.url
                let file = taskMapping.file
                let newTask = self.uploadBackground(session, url: url, file: file)
                self.tasks[newTask.taskIdentifier] = TaskInfo(task: newTask, url: url, file: file, retries: taskMapping.retries + 1)
                self.tasks.removeValue(forKey: task.taskIdentifier)
            } else {
                self.uploadFailed = true
                dispatchGroup.leave()
            }
        } else {
            // Everything is okay! Leave the dispatch group
            dispatchGroup.leave()
        }
    }
        
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        self.uploadTotal += bytesSent
        print(Float(uploadTotal) / Float(size))
    }
        
}

enum UploadError: Error {
    case file
    case unsupportedIosVersion
    case network
    case parse
}

// Structure to represent the response from
// Uploadcare's Multipart Start request
struct StartResponse: Codable {
    var uuid: String
    var parts: [String]
}

// Store some basic information about tasks
struct TaskInfo {
    var task: URLSessionTask
    var url: URL
    var file: URL
    var error = false
    var retries = 0
}
