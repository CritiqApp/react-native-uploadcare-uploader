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
    public let sessionId: String = UUID().uuidString
    private var chunks: [URL] = []
    
    // MARK - Uploadcare client fields
    private let key: String
    private var uuid: String?
    private let metaData: Dictionary<String, Any>
    
    // MARK - Task queue fields
    private var uploadMode: UploadMode = .direct
    private var tasks: [Int:TaskInfo] = [:]
    private var uploadFailed = false
    private var uploadTotal: Int64 = 0
    private var _cachedUploadSession: URLSession?

    // MARK - Callbacks
    public var errorCallback: ((_ type: String, _ description: String, _ error: Error) -> Void)?
    public var successCallback: ((_ uuid: String) -> Void)?
    public var progressCallback: ((_ current: Int64, _ total: Int64) -> Void)?
    public var uuidCallback: ((_ uuid: String) -> Void)?
    
    init(_ key: String, path: String, mimeType: String, metaData: Dictionary<String, Any>) {
        self.key = key
        self.url = URL(fileURLWithPath: path)
        self.mimeType = mimeType
        self.metaData = metaData
        super.init()
    }
    
    func upload() {

        // Get the file size
        guard let size = try? getFileSize() else {
            errorCallback?("file", "could not get file size", UploadError.file)
            return
        }
        self.size = size
        
        if size >= DirectUploadThreshold {
            uploadMode = .multipart
            uploadMultipart()
        } else {
            uploadMode = .direct
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
            
            self.uuidCallback?(response.uuid)
            
            self.uuid = response.uuid
            let session = self.backgroundSession(self.sessionId)
            
            if chunks.count != response.parts.count {
                self.errorCallback?("chunk", "chunk mismatch from upload paths", UploadError.parse)
                return
            }
            
            // Pair up the upload parts with the file chunks and upload the
            for (url, file) in zip(response.parts, chunks) {
                let fileUrl = URL(string: url)!
                let task = self.uploadBackground(session, url: fileUrl, file: file)
                self.tasks[task.taskIdentifier] = TaskInfo(task: task, url: fileUrl, file: file)
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
        guard let fileSize = resources.fileSize else {
            throw UploadError.file
        }
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
        
        guard let fileData = try? Data(contentsOf: file) else {
            errorCallback?("file", "failed to read contents of file", UploadError.file)
            return
        }
        
        let filename = "\(sessionId).\(url.pathExtension)"
        var request = URLRequest(url: UploadHandler.DirectEndpoint)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let builder = MultipartRequestBuilder(boundary: sessionId, request: request )
        builder.addMultiformValue(key, forName: "UPLOADCARE_PUB_KEY")
        builder.addMultiformValue("auto", forName: "UPLOADCARE_STORE")
        builder.addMultiformValue(filename, forName: "filename")
        builder.addMultiformValue("\(size)", forName: "size")
        builder.addMultiformValue(mimeType, forName: "content_type")
        builder.addMultiformData(fileData, forName: filename, mimeType: mimeType)
                
        for (key, value) in self.metaData {
            builder.addMultiformValue("\(value)", forName: "metadata[\(key)]")
        }
        
        request = builder.finalize()
        
        // Get the body data and create a file to upload
        guard let bodyData = request.httpBody else {
            errorCallback?("direct", "body data was not set", UploadError.file)
            return
        }
        
        // Change the upload size
        self.size = bodyData.count
        
        // Save the body data into a file
        guard let bodyFile = try? saveDataToFile(self.sessionId + ".data", data: bodyData) else {
            errorCallback?("direct", "failed to save body data to file", UploadError.file)
            return
        }
        
        // Create a background task session to upload the file
        let task = backgroundSession(sessionId).uploadTask(with: request, fromFile: bodyFile)
        task.resume()
        
        // Add the task and enter the dispatch group (even if there's only one task)
        let taskInfo = TaskInfo(task: task, url: UploadHandler.DirectEndpoint, file: bodyFile)
        self.tasks[task.taskIdentifier] = taskInfo
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
        
        for (key, value) in self.metaData {
            builder.addMultiformValue("\(value)", forName: "metadata[\(key)]")
        }
        
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
    private func completeMultipart(_ session: URLSession, uuid: String) -> URLSessionTask {
                
        let builder = MultipartRequestBuilder(boundary: sessionId, request:  URLRequest(url: UploadHandler.CompleteEndpoint))
        builder.addMultiformValue(key, forName: "UPLOADCARE_PUB_KEY")
        builder.addMultiformValue(uuid, forName: "uuid")
        var request = builder.finalize()
        request.httpMethod = "POST"
    
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
                
                self.successCallback?(uuid)
            }
            
        }
        return task
    }

    // Handle updates to the progress
    private func updateProgress() {
        let current = tasks.values.reduce(0 as Int64) { $0 + $1.uploaded.value }
        progressCallback?(current, Int64(size))
    }
    
}

// Handle the URL session delegates
extension UploadHandler: URLSessionDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Needs this delegate
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        // If upload is already marked as failed, leave the
        // dispatch group
        if uploadFailed {
            return
        }
        
        // If the task is not mapped, something went wrong
        // fail the upload and leave the dispatch group
        guard let taskMapping = self.tasks[task.taskIdentifier] else {
            self.uploadFailed = true
            return
        }
        
        // Check for a valid response
        if let response = task.response as? HTTPURLResponse {
            if response.statusCode < 200 || response.statusCode >= 300 {
                self.uploadFailed = true
                return
            }
        }
        
        // If we caught an error or response indicates a server error
        // retry a few times. After 5 retries, fail the upload and
        // leave the dispatch group
        if error != nil {
            if taskMapping.retries.value < 5 {
                // Attempt to retry this upload
                let url = taskMapping.url
                let file = taskMapping.file
                let newTask = self.uploadBackground(session, url: url, file: file)
                self.tasks[newTask.taskIdentifier] = TaskInfo(task: newTask, url: url, file: file, retries: MutableValue(taskMapping.retries.value + 1))
                self.tasks.removeValue(forKey: task.taskIdentifier)
            } else {
                uploadFailed = true
            }
        } else {
            
            // Indicate this task done
            taskMapping.done.value = true
            
            // See if all the tasks finished
            let done = self.tasks.values.reduce(true, { $0 && $1.done.value })
            if (done) {
                
                // If session is multipart, tell complete the upload
                if self.uploadMode == .multipart {
                    let session = URLSession.shared
                    self.completeMultipart(session, uuid: self.uuid!).resume()
                }
                
            }
            
            // Update the progress
            taskMapping.uploaded.value = task.countOfBytesSent
            updateProgress()
        }
    }
        
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let info = tasks[task.taskIdentifier] {
            info.uploaded.value = totalBytesSent
            updateProgress()
        }
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if uploadMode == .direct {
            
            guard let response = dataTask.response as? HTTPURLResponse else {
                errorCallback?("direct", "response object is not HTTP", UploadError.network)
                return
            }
            
            if response.statusCode < 200 || response.statusCode >= 300 {
                errorCallback?("direct", "response has error status code", UploadError.network)
                return
            }
            
            let decoder = JSONDecoder()
            guard let json = try? decoder.decode([String:String].self, from: data) else {
                errorCallback?("parse", "unable to parse direct upload response", UploadError.parse)
                return
            }
            
            guard let uuid = json.values.first else {
                errorCallback?("parse", "unable to find uuid in response", UploadError.parse)
                return
            }
            
            uuidCallback?(uuid)
            successCallback?(uuid)
            
        }
    }
                
}

enum UploadError: Error {
    case file
    case unsupportedIosVersion
    case network
    case parse
}

enum UploadMode {
    case direct
    case multipart
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
    var error = MutableValue(false)
    var retries = MutableValue<Int>(0)
    var uploaded = MutableValue<Int64>(0)
    var done = MutableValue(false)
}

// Makes a mutable object in a struct
class MutableValue<T> {
    
    public var value: T
    
    init(_ value: T) {
        self.value = value
    }
    
}
