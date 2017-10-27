//
//  XHVideoWriter.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/11.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

extension AVAssetWriter {
    func tryToAdd(_ input: AVAssetWriterInput?) {
        guard let writerInput = input else {
            XHDebug.log("can not add input nil to AVAssetWriter \(self)")
            return
        }
        guard canAdd(writerInput) else {
            XHDebug.log("can not add input \(writerInput) to AVAssetWriter \(self)")
            return
        }
        add(writerInput)
    }
}

class XHWriteSegment: NSObject {
    var finished = false
    var url: URL?
    var duration: CMTime {
        return asset?.duration ?? kCMTimeZero
    }
    
    var asset: AVAsset? {
        get {
            guard finished && nil != url else {
                return nil
            }
            if nil == localAsset {
                localAsset = AVAsset(url: url!)
            }
            return localAsset
        }
    }
    
    init(with url: URL) {
        super.init()
        self.url = url
    }
    
    private var localAsset: AVAsset?
}

class XHWriteSegments {
    private var _segments = [XHWriteSegment]()
    private var _count: Int = 0

    // writing segment properties
    var writingSegment: XHWriteSegment?
    var writingOffset = kCMTimeInvalid // time offset in group
    var writingDuration = kCMTimeZero
    
    // get
    var array: [XHWriteSegment] {return _segments}
    var count: Int {return _segments.count}
    var duration: CMTime {
        get {
            var dur = writingDuration
            for segment in array {
                dur = CMTimeAdd(segment.duration, dur)
            }
            return dur
        }
    }
    var lastSegment: XHWriteSegment? {
        return array.last ?? nil
    }
    
    func removeSegment(at index: Int, andDisk: Bool) {
        guard nil == writingSegment else {
            XHDebug.log("can not remove when capture is writing")
            return
        }
        
        guard (index >= 0) && (index < count) else  {
            return
        }
        
        if andDisk {
            let segment = _segments[index]
            do {
                try FileManager.default.removeItem(at: segment.url!)
            } catch {
                XHDebug.log("remove file failed")
            }
        }
        _segments.remove(at: index)
    }
    
    func removeAll(andDisk: Bool) {
        finishWriting()
        _segments.removeAll()
        
        if andDisk {
            do  {
                try FileManager.default.removeItem(atPath: directory())
                _count = 0
            } catch {
                XHDebug.log("remove temp directory failed")
            }
        }
    }
    
    func startNewSegment() -> XHWriteSegment? {
        guard let filePath = filePath() else {
            return nil
        }
        let segment = XHWriteSegment(with: filePath)
        writingOffset   = kCMTimeInvalid
        writingDuration = kCMTimeZero
        writingSegment  = segment
        return segment
    }
    
    func finishWriting() {
        guard let segment = writingSegment else {
            return
        }
        segment.finished = true
        _segments.append(segment)
        _count += 1
        writingDuration = kCMTimeZero
        writingSegment = nil
    }
    
    private func directory() -> String {
        return NSTemporaryDirectory() + "xhVideo/"
    }
    
    private func filePath() -> URL? {
        let tempdirectory = directory()
        do {
            try FileManager.default.createDirectory(atPath: tempdirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            XHDebug.log("create directory failed: " + error.localizedDescription)
            return nil
        }
        let segmentPath = tempdirectory + "xhcapture_temp_\(_count).mp4"
        return XHVideoUtilities.cleanFileAt(path: segmentPath)
    }
}

typealias XHWriteSessionCompletion = (XHWriteSession, NSError?)->Void
class XHWriteSession: NSObject, XHErrorProtocol {
    private let XHWriteSessionDomain = "XHWriteSession"
    private var callBackQueue: DispatchQueue
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoSegments: XHWriteSegments

    var domain: String {return "XHWriteSession"}
    var type = CaptureType.Unknown
    var videoInputPrepared: Bool {return (nil != videoInput)}
    var audioInputPrepared: Bool {return (nil != audioInput)}
    var writerPrepared:     Bool {return (nil != assetWriter)}
    var segments: XHWriteSegments{return videoSegments}

    deinit {
        videoSegments.removeAll(andDisk: true)
        NSLog("dealloc")
    }
    
    func reset() {
        if let writer = assetWriter {
            writer.endSession(atSourceTime: kCMTimeZero)
            writer.cancelWriting()
        }
        videoSegments.removeAll(andDisk: true)
        videoPixelBufferAdaptor = nil
        videoInput = nil
        audioInput = nil
    }

    override init() {
        callBackQueue = XHDispatchQueues.capture
        videoSegments = XHWriteSegments()
        super.init()
    }
    
    convenience init(with callBackQueue: DispatchQueue!) {
        self.init()
        self.callBackQueue = callBackQueue
    }

    // XHDispatchQueues.video or .audio
    func beginSegment(completion: XHWriteSessionCompletion?) {
        guard audioInputPrepared && videoInputPrepared else {
            self.callBackQueue.async {
                completion?(self, self.XHError(with: 1, msg: "audio/video input is not ready"))
            }
            return
        }
        
        XHDispatchQueues.write.async {
            guard nil == self.assetWriter else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 2, msg: "begin segment error, segment already existed"))
                }
                return
            }
            
            guard let writer = self.initWriter() else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 3, msg: "begin segment error, can not init segment"))
                }
                return
            }
            guard writer.startWriting() else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 4, msg: "can not start writing"))
                }
                return
            }
            self.assetWriter = writer
            self.assetWriter?.startSession(atSourceTime: kCMTimeZero)
            self.callBackQueue.async {
                completion?(self, nil)
            }
        }
    }
    
    // XHDispatchQueues.capture
    func endSegment(completion: XHWriteSessionCompletion?) {
        XHDispatchQueues.write.async {
            guard let writer = self.assetWriter else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 11, msg: "end segment error, writer is nil"))
                }
                return
            }
            writer.endSession(atSourceTime: self.videoSegments.writingDuration)
            writer.finishWriting {
                self.videoSegments.finishWriting()
                self.destoryWriter()
                self.callBackQueue.async {
                    completion?(self, nil)
                }
            }
        }
    }
    
    // XHDispatchQueues.video
    func appendVideoPixel(buffer: CVPixelBuffer!, at time: CMTime!, completion: XHWriteSessionCompletion?) {
        XHDispatchQueues.write.async {
            guard let input = self.videoInput else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 5, msg: "video input is not ready"))
                }
                return
            }
            guard let adaptor = self.videoPixelBufferAdaptor else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 6, msg: "video pixel buffer adaptor is not ready"))
                }
                return
            }
            
            if !self.segments.writingOffset.isValid {
                self.segments.writingOffset = CMTimeSubtract(time, self.segments.writingDuration)
            }
            let presentationTime = CMTimeSubtract(time, self.segments.writingOffset)
            if input.isReadyForMoreMediaData {
                self.segments.writingDuration = presentationTime
                self.callBackQueue.async {
                    completion?(self, nil)
                }
                adaptor.append(buffer, withPresentationTime: presentationTime)
            } else {
                self.callBackQueue.async {
                    completion?(self, self.XHError(with: 7, msg: "video input is not ready for data"))
                }
            }
        }
    }
    
    // XHDispatchQueues.audio
    func appendAudioPixel(buffer: CMSampleBuffer!, completion: XHWriteSessionCompletion?) {
        XHDispatchQueues.write.async {
            var error: NSError?
            defer {
                self.callBackQueue.async {
                    completion?(self, error)
                }
            }
            
            guard let input = self.audioInput else {return}
            guard self.segments.writingOffset.isValid else {return}
            guard let sampleBuffer = buffer.adjustTimeStamp(self.segments.writingOffset) else {
                error = self.XHError(with: 8, msg: "adjust time stamp failed")
                return
            }
            
            let newTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard -1 != CMTimeCompare(newTimeStamp, kCMTimeZero) else { // presentationTime >= kCMTimeZero
                error = self.XHError(with: 9, msg: "presetation time invalid")
                return
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            } else {
                error = self.XHError(with: 10, msg: "audio input is not ready for data")
            }
        }
    }
    
    // MARK: setup audio/video settings
    // XHDispatchQueues.video
    func initVideoInput(with descrption: CMFormatDescription!, and configuration: XHVideoConfiguration!, completion: XHWriteSessionCompletion?) {
        XHDispatchQueues.capture.safeSync {
            var error: NSError?
            defer {
                self.callBackQueue.async {
                    completion?(self, error)
                }
            }
            let settings = configuration.assetWriterSettings(with: descrption)
            if nil == self.videoInput {
                let input = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: settings, sourceFormatHint: descrption)
                input.expectsMediaDataInRealTime = true
                self.videoInput = input
                if let transform = configuration.additionalProperties[AdditionalProperty.Rotation.rawValue] as? CGAffineTransform {
                    input.transform = transform
                }
                let attributes: [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                  kCVPixelBufferWidthKey as String: settings[AVVideoWidthKey]!,
                                                  kCVPixelBufferHeightKey as String: settings[AVVideoHeightKey]!]
                self.videoPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
            } else {
                error = self.XHError(with: 11, msg: "video input already existed")
            }
        }
    }
    
    // XHDispatchQueues.audio
    func initAudioInput(with descrption: CMFormatDescription!, and configuration: XHAudioConfiguration!, completion: XHWriteSessionCompletion?) {
        XHDispatchQueues.capture.safeSync {
            var error: NSError?
            defer {
                self.callBackQueue.async {
                    completion?(self, error)
                }
            }
            
            let setting = configuration.assertWirterSettings(with: descrption)
            if nil == self.audioInput {
                let input = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: setting, sourceFormatHint: descrption)
                input.expectsMediaDataInRealTime = true
                self.audioInput = input
            } else {
                error = self.XHError(with: 12, msg: "audio input already existed")
            }
        }
    }
    
    // MAKE: Private
    private func initWriter() -> AVAssetWriter? {
        guard let segment = videoSegments.startNewSegment() else {
            return nil
        }
        
        do {
            let writer = try AVAssetWriter(url: segment.url!, fileType: AVFileTypeMPEG4)
            writer.metadata = metadate()
            writer.tryToAdd(videoInput)
            writer.tryToAdd(audioInput)
            return writer
        } catch {
            XHDebug.log(error)
        }
        return nil
    }
    
    private func destoryWriter() {
        assetWriter = nil
    }
    
    private func metadate() -> [AVMutableMetadataItem]! {
        let currentDevice = UIDevice.current
        
        // device model
        let modelItem = AVMutableMetadataItem()
        modelItem.keySpace = AVMetadataKeySpaceCommon
        modelItem.key = AVMetadataCommonKeyModel as NSCopying & NSObjectProtocol
        modelItem.value = currentDevice.localizedModel as NSCopying & NSObjectProtocol
        
        // software
        let softwareItem = AVMutableMetadataItem()
        softwareItem.keySpace = AVMetadataKeySpaceCommon
        softwareItem.key = AVMetadataCommonKeySoftware as NSCopying & NSObjectProtocol
        softwareItem.value = "XHVideoCatcher" as NSCopying & NSObjectProtocol
        
        // creation date
        let creationDateImte = AVMutableMetadataItem()
        creationDateImte.keySpace = AVMetadataKeySpaceCommon
        creationDateImte.key = AVMetadataCommonKeyCreationDate as NSCopying & NSObjectProtocol
        creationDateImte.value = XHVideoUtilities.formattedTimestampStringFrom(date: nil)! as NSCopying & NSObjectProtocol
        
        return [modelItem, softwareItem, creationDateImte]
    }
}
