// Services/CachingResourceLoaderDelegate.swift
import AVFoundation
import UniformTypeIdentifiers

/// Streams a song through AVFoundation while writing it to `AudioCache`.
///
/// Design (see the plan): a single sequential "cache-fill" download from byte 0
/// to EOF is the *only* writer of the cache file — so a partially played or
/// skipped track is never cached. Loading requests for bytes we haven't reached
/// yet (seeks, and the trailing `moov` atom in m4a/ALAC files) are answered by
/// one-off ranged "far-request" downloads whose bytes are handed straight to the
/// player and never persisted. That keeps first-play start and seeking instant
/// without weakening the never-cache-partials rule.
///
/// All AVAssetResourceLoader and URLSession callbacks are serialised onto
/// `loaderQueue`, so the mutable state below needs no additional locking. The
/// class is `nonisolated` because those callbacks arrive off the main actor.
nonisolated final class CachingResourceLoaderDelegate: NSObject,
    AVAssetResourceLoaderDelegate, URLSessionDataDelegate {

    /// Serial queue the resource loader is attached to (see `AudioPlayerService`).
    let loaderQueue = DispatchQueue(label: "earsonics.audioloader")

    private let realURL: URL
    private let songId: String
    private let quality: StreamQuality
    private let seedContentType: String?
    private let seedSuffix: String?
    private let seedSize: Int64?

    /// Anything past `downloadedLength + farMargin` is served by a far-request
    /// task rather than waiting for the sequential download to reach it.
    private let farMargin: Int64 = 512 * 1024

    private let tempURL: URL
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?
    private var downloadedLength: Int64 = 0
    private var expectedLength: Int64?

    private var cacheFillTask: URLSessionDataTask?
    private var cacheFillStarted = false
    private var stored = false
    private var invalidated = false

    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private var farRequestByTask: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private var farTaskByRequest: [ObjectIdentifier: URLSessionDataTask] = [:]

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = nil                                   // never double-cache large audio
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let opQueue = OperationQueue()
        opQueue.underlyingQueue = loaderQueue
        opQueue.maxConcurrentOperationCount = 1
        return URLSession(configuration: cfg, delegate: self, delegateQueue: opQueue)
    }()

    init(realURL: URL, songId: String, quality: StreamQuality,
         contentType: String?, suffix: String?, size: Int64?) {
        self.realURL = realURL
        self.songId = songId
        self.quality = quality
        self.seedContentType = contentType
        self.seedSuffix = suffix
        self.seedSize = size
        self.expectedLength = quality.knownLength ? size : nil
        // Temp file lives in the cache directory so the final move is a same-volume
        // (atomic) rename.
        self.tempURL = AudioCache.directoryURL()
            .appendingPathComponent("dl-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        super.init()
        writeHandle = try? FileHandle(forWritingTo: tempURL)
        readHandle = try? FileHandle(forReadingFrom: tempURL)
    }

    /// Cancels all work and cleans up. Must be called by the owner when the
    /// associated player item is discarded — URLSession retains its delegate
    /// until invalidated, so this also breaks that retain cycle.
    func invalidate() {
        loaderQueue.async { [self] in
            guard !invalidated else { return }
            invalidated = true
            cacheFillTask?.cancel()
            for (_, task) in farTaskByRequest { task.cancel() }
            let error = NSError(domain: "earsonics.audioloader", code: -999)
            for request in pendingRequests where !request.isFinished {
                request.finishLoading(with: error)
            }
            pendingRequests.removeAll()
            try? writeHandle?.close()
            try? readHandle?.close()
            // Only the sequential task owns the cache file; if it never stored,
            // discard the temp. (Safe even if the player still holds a read fd:
            // on APFS the inode survives until the descriptor closes.)
            if !stored { try? FileManager.default.removeItem(at: tempURL) }
            session.invalidateAndCancel()
        }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        startCacheFillIfNeeded()
        pendingRequests.append(loadingRequest)
        serviceRequests()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        pendingRequests.removeAll { $0 === loadingRequest }
        if let task = farTaskByRequest.removeValue(forKey: ObjectIdentifier(loadingRequest)) {
            farRequestByTask.removeValue(forKey: ObjectIdentifier(task))
            task.cancel()
        }
    }

    // MARK: - Request servicing

    private func serviceRequests() {
        for request in pendingRequests {
            if request.isCancelled {
                pendingRequests.removeAll { $0 === request }
                continue
            }
            if let info = request.contentInformationRequest, !fillContentInfo(info) {
                continue    // length not known yet — wait for the response
            }
            guard let data = request.dataRequest else {
                request.finishLoading()
                pendingRequests.removeAll { $0 === request }
                continue
            }
            // A request whose bytes are far beyond what we've downloaded (a seek
            // or the trailing moov atom) is served out of band so playback isn't
            // blocked on the sequential download. Only possible for range-capable
            // originals; transcoded streams advertise no range support.
            if quality.knownLength, data.currentOffset > downloadedLength + farMargin {
                pendingRequests.removeAll { $0 === request }
                startFarTask(for: request, from: data.currentOffset)
                continue
            }
            serveFromTemp(data)
            if isSatisfied(data) {
                request.finishLoading()
                pendingRequests.removeAll { $0 === request }
            }
        }
    }

    private func fillContentInfo(_ info: AVAssetResourceLoadingContentInformationRequest) -> Bool {
        info.contentType = contentTypeIdentifier
        info.isByteRangeAccessSupported = quality.knownLength
        if let length = expectedLength {
            info.contentLength = length
            return true
        }
        return false
    }

    private func serveFromTemp(_ data: AVAssetResourceLoadingDataRequest) {
        let start = data.currentOffset
        guard start < downloadedLength, let readHandle else { return }
        let end = min(downloadedLength, logicalEnd(of: data))
        let length = end - start
        guard length > 0 else { return }
        do {
            try readHandle.seek(toOffset: UInt64(start))
            if let chunk = try readHandle.read(upToCount: Int(length)), !chunk.isEmpty {
                data.respond(with: chunk)
            }
        } catch { }
    }

    /// The absolute byte offset a data request needs to reach to be complete.
    private func logicalEnd(of data: AVAssetResourceLoadingDataRequest) -> Int64 {
        if data.requestsAllDataToEndOfResource {
            return expectedLength ?? Int64.max
        }
        return data.requestedOffset + Int64(data.requestedLength)
    }

    private func isSatisfied(_ data: AVAssetResourceLoadingDataRequest) -> Bool {
        data.currentOffset >= logicalEnd(of: data)
    }

    private var contentTypeIdentifier: String? {
        let mime = quality == .original ? seedContentType : "audio/mpeg"
        if let mime, let type = UTType(mimeType: mime) { return type.identifier }
        let suffix = quality.fileSuffix ?? seedSuffix
        if let suffix, let type = UTType(filenameExtension: suffix) { return type.identifier }
        return nil
    }

    // MARK: - Downloads

    private func startCacheFillIfNeeded() {
        guard !cacheFillStarted else { return }
        cacheFillStarted = true
        let task = session.dataTask(with: URLRequest(url: realURL))
        cacheFillTask = task
        task.resume()
    }

    private func startFarTask(for request: AVAssetResourceLoadingRequest, from offset: Int64) {
        var urlRequest = URLRequest(url: realURL)
        urlRequest.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: urlRequest)
        farRequestByTask[ObjectIdentifier(task)] = request
        farTaskByRequest[ObjectIdentifier(request)] = task
        task.resume()
    }

    private func finishFarTask(_ task: URLSessionTask) {
        if let request = farRequestByTask.removeValue(forKey: ObjectIdentifier(task)) {
            farTaskByRequest.removeValue(forKey: ObjectIdentifier(request))
        }
        task.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if dataTask === cacheFillTask, expectedLength == nil {
            let length = response.expectedContentLength
            if length > 0 { expectedLength = length }
            serviceRequests()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if dataTask === cacheFillTask {
            try? writeHandle?.write(contentsOf: data)
            downloadedLength += Int64(data.count)
            serviceRequests()
        } else if let request = farRequestByTask[ObjectIdentifier(dataTask)] {
            guard !request.isCancelled, let dataRequest = request.dataRequest else { return }
            dataRequest.respond(with: data)
            if isSatisfied(dataRequest) {
                request.finishLoading()
                finishFarTask(dataTask)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if task === cacheFillTask {
            handleCacheFillCompletion(error: error)
        } else if let request = farRequestByTask[ObjectIdentifier(task)] {
            if let error, !request.isFinished { request.finishLoading(with: error as NSError) }
            finishFarTask(task)
        }
    }

    private func handleCacheFillCompletion(error: Error?) {
        try? writeHandle?.close()
        writeHandle = nil

        if error == nil && !invalidated && downloadedLength > 0 {
            // Truncation guard: for a known-length original, only cache if the
            // full file arrived. Transcoded streams have only an estimated
            // length, so a clean completion is the best signal available.
            let complete: Bool
            if quality == .original, let expected = seedSize {
                complete = downloadedLength == expected
            } else {
                complete = true
            }
            if complete {
                stored = true
                let temp = tempURL, sid = songId, q = quality
                Task.detached { await AudioCache.shared.store(tempFile: temp, songId: sid, quality: q) }
            }
            // Resolve any request still waiting for the tail / total length.
            if expectedLength == nil { expectedLength = downloadedLength }
            serviceRequests()
        } else if let error {
            for request in pendingRequests where !request.isFinished {
                request.finishLoading(with: error as NSError)
            }
            pendingRequests.removeAll()
        }
    }
}
