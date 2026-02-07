import Foundation

// MARK: - Upload Manager

actor UploadManager {
    // MARK: - Types
    
    struct UploadProgress {
        let bytesUploaded: Int64
        let totalBytes: Int64
        
        var fractionCompleted: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesUploaded) / Double(totalBytes)
        }
        
        var percentComplete: Int {
            Int(fractionCompleted * 100)
        }
    }
    
    enum UploadState {
        case idle
        case uploading(UploadProgress)
        case completed(String)  // storage key
        case failed(Error)
    }
    
    // MARK: - Properties
    
    private let supabaseClient: SupabaseClient
    private var activeTasks: [String: URLSessionUploadTask] = [:]
    
    // MARK: - Initialization
    
    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient
    }
    
    // MARK: - Upload Methods
    
    func uploadAudio(
        handoffId: String,
        fileURL: URL,
        progressHandler: @escaping (UploadProgress) async -> Void
    ) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        
        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()
        
        // Add handoff_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"handoff_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(handoffId)\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Call transcribe function
        let (responseData, _) = try await supabaseClient.request(
            path: "functions/v1/transcribe-handoff",
            method: "POST",
            body: body,
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ]
        )
        
        // Parse response
        struct TranscribeResponse: Decodable {
            let success: Bool
            let jobId: String?
            let error: ErrorDetail?
            
            struct ErrorDetail: Decodable {
                let code: String
                let message: String
            }
        }
        
        let result = try JSONDecoder.supabase.decode(TranscribeResponse.self, from: responseData)
        
        if result.success, let jobId = result.jobId {
            return jobId
        } else {
            throw UploadError.serverError(result.error?.message ?? "Upload failed")
        }
    }
    
    func uploadAttachment(
        circleId: String,
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> String {
        let path = "\(circleId)/\(UUID().uuidString)/\(filename)"
        
        return try await supabaseClient
            .storage("attachments")
            .upload(path: path, data: data, contentType: mimeType)
    }
    
    // MARK: - Poll Transcription Job
    
    func pollTranscriptionJob(
        jobId: String,
        maxAttempts: Int = 60,
        intervalSeconds: TimeInterval = 2
    ) async throws -> String {
        for _ in 0..<maxAttempts {
            let status = try await checkTranscriptionStatus(jobId: jobId)
            
            switch status {
            case .completed(let transcript):
                return transcript
            case .failed(let error):
                throw error
            case .pending:
                try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
        
        throw UploadError.timeout
    }
    
    enum TranscriptionStatus {
        case pending
        case completed(String)
        case failed(Error)
    }
    
    private func checkTranscriptionStatus(jobId: String) async throws -> TranscriptionStatus {
        struct StatusResponse: Decodable {
            let success: Bool
            let status: String
            let transcript: String?
            let error: ErrorDetail?
            
            struct ErrorDetail: Decodable {
                let code: String
                let message: String
            }
        }
        
        let (data, _) = try await supabaseClient.request(
            path: "functions/v1/transcribe-handoff/\(jobId)",
            method: "GET"
        )
        
        let result = try JSONDecoder.supabase.decode(StatusResponse.self, from: data)
        
        if result.status == "COMPLETED", let transcript = result.transcript {
            return .completed(transcript)
        } else if result.status == "FAILED" {
            return .failed(UploadError.serverError(result.error?.message ?? "Transcription failed"))
        } else {
            return .pending
        }
    }
    
    // MARK: - Cancel
    
    func cancelUpload(id: String) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }
}

// MARK: - Upload Error

enum UploadError: Error, LocalizedError {
    case fileNotFound
    case serverError(String)
    case timeout
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Recording file not found"
        case .serverError(let message):
            return message
        case .timeout:
            return "Upload timed out"
        case .cancelled:
            return "Upload was cancelled"
        }
    }
}
