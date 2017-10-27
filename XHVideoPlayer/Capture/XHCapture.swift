//
//  XHVideoCatcher.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/10.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

enum RecordingStatus: String {
    case Idle = "Idle"
    case Recording = "Recording"
    case Finished = "Finished"
}

@objc enum CaptureType: Int {
    case Unknown
    case Video
    case Photo
    case Audio
    var isVideo:  Bool {return .Video == self}
    var isPhoto:  Bool {return .Photo == self}
    var isAudio:  Bool {return .Audio == self}
    var hasAudio: Bool {return (.Video == self) || (.Audio == self)}
}

class CaptureJarvis {
    var videoConfiguration = XHVideoConfiguration()
    var audioConfiguration = XHAudioConfiguration()
    var status = RecordingStatus.Idle
    var inPreview = false
    var interrupted = false
    var startTimestamp = kCMTimeInvalid
    var maximumCaptureDuration = kCMTimeInvalid
    var type = CaptureType.Video
}

@objc protocol XHWriteSessionDelegate: class {
    @objc optional func capture(_ capture: XHCapture, writer: XHWriteSession, startWriting segment: XHWriteSegment?)
    @objc optional func capture(_ capture: XHCapture, writer: XHWriteSession, writing segment: XHWriteSegment?)
    @objc optional func capture(_ capture: XHCapture, writer: XHWriteSession, finishedWriting segment:XHWriteSegment?)
}

class XHCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, XHLockProtocol {
    private var jarvis: CaptureJarvis
    private let writeSession: XHWriteSession
    private let captureSession: XHCaptureSession
    private let previewLayer: AVCaptureVideoPreviewLayer
    
    deinit {
        NSLog("dealloc")
    }
    
    // Readonly
    var recording: Bool {return .Recording == jarvis.status}
    var layer: AVCaptureVideoPreviewLayer {return previewLayer}
    var videoConfiguration: XHVideoConfiguration {return jarvis.videoConfiguration}
    var audioConfiguration: XHAudioConfiguration {return jarvis.audioConfiguration}
    var segments: XHWriteSegments {return writeSession.segments}

    // Property
    weak var writeSessionDelegate: XHWriteSessionDelegate?
    var maximumDuration: CMTime {
        get {return jarvis.maximumCaptureDuration}
        set {jarvis.maximumCaptureDuration = newValue}
    }
    var captureSessionPreset: String {
        get {return captureSession.preset}
        set {
            captureSession.reconfigureSession(jarvis.videoConfiguration.enable, jarvis.audioConfiguration.enable)
            captureSession.preset = newValue
        }
    }
    
    override init() {
        jarvis = CaptureJarvis()
        captureSession = XHCaptureSession()
        writeSession = XHWriteSession()
        previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        super.init()
        guard XHVideoUtilities.cameraAuthorizationStatus() && XHVideoUtilities.microphoneAuthorizationStatus() else {
            XHDebug.log("用户不允许使用设备")
            return
        }
    }
    
    func startCapture() {
        self.setupCaptureSession()
        if !self.captureSession.isRunning {
            self.captureSession.startRunning()
        }
        self.jarvis.inPreview = true
        self.recordingStatus = .Idle
    }
    
    func stopCapture() {
        self.jarvis.inPreview = false
        self.captureSession.stopRunning()
    }
    
    func startRecording() {
        guard !XHVideoUtilities.isSimulator else {return}
        guard !isRecordTimeOut() else {return}
        guard captureSession.isReady else {return}
        guard (.Idle == self.recordingStatus) else {
            XHDebug.log("Already recording")
            return
        }
        NSLog("start")
        recordingStatus = .Recording;
    }
    
    func stopRecording() {
        guard .Recording == recordingStatus else {
            return
        }
        recordingStatus = .Finished
        self.writeSession.endSegment(completion: {[weak self] (session, error) in
            guard let strongself = self else {return}
            strongself.writeSessionDelegate?.capture?(strongself, writer: strongself.writeSession, finishedWriting: strongself.writeSession.segments.lastSegment)
            strongself.recordingStatus = .Idle
        })
    }
    
    // MARK: Capture
    // 设置点击焦点
    func focus(at point: CGPoint, continuous: Bool) {
        captureSession.focus(at: previewLayer.captureDevicePointOfInterest(for: point), continuous: continuous)
    }
    
    // 切换前后摄像头
    func swapVideoCaptureDevice(completion: ((Bool)->Void)?) {
        XHDispatchQueues.capture.async {
            self.captureSession.stopRunning()
            self.captureSession.swapCamera()
            DispatchQueue.main.safeSync {
                completion?(true)
            }
            self.captureSession.startRunning()
        }
    }
    
    // 设置闪光灯模式
    var flashModel: CaptureFlashMode? {
        get {return captureSession.flashModel}
        set {captureSession.flashModel = newValue}
    }
    
    // 设置缩放
    var zoomFactor: CGFloat {
        get {return captureSession.zoomFactor}
        set {captureSession.zoomFactor = newValue}
    }
    
    // 设置输出尺寸
    func export(screenRect: CGRect?, to size: CMVideoDimensions?) {
        recordingStatus = .Idle
        videoConfiguration.export(screenRect: screenRect, to: size)
        writeSession.reset()
    }
    
    // MARK: Delegate
    // 当前有一个新的视频帧写入时该方法就会被调用，数据会基于视频输出的 videoSettings 属性进行解码或重新编码。
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {return}
        if captureOutput == captureSession.videoOutput {
            if !writeSession.videoInputPrepared {
                writeSession.initVideoInput(with: CMSampleBufferGetFormatDescription(sampleBuffer), and: jarvis.videoConfiguration, completion: nil)
            }
            guard .Recording == recordingStatus else {
                return
            }
            
            if !writeSession.writerPrepared {
                writeSession.beginSegment(completion: nil)
            }
            
            var appendBuffer: CVPixelBuffer?
            if let cropFrame = jarvis.videoConfiguration.customResizeFrame {
                appendBuffer = sampleBuffer.resize(cropFrame)
            } else {
                appendBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            }
            guard nil != appendBuffer else {
                return
            }
            let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writeSession.appendVideoPixel(buffer: appendBuffer, at: presentationTimeStamp, completion: {[weak self] (session, succ) in
                guard let strongself = self else {return}
                strongself.writeSessionDelegate?.capture?(strongself, writer: strongself.writeSession, writing: strongself.writeSession.segments.writingSegment)
                strongself.checkRecordDuration()
            })
        } else if captureOutput == captureSession.audioOutput {
            if !writeSession.audioInputPrepared {
                writeSession.initAudioInput(with: CMSampleBufferGetFormatDescription(sampleBuffer), and: jarvis.audioConfiguration, completion: nil)
            }
            guard .Recording == recordingStatus else {
                return
            }
            writeSession.appendAudioPixel(buffer: sampleBuffer, completion: nil)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput!, didDrop sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        NSLog("drop")
    }
    
    // MARK: Private
    private func checkRecordDuration() {
        if isRecordTimeOut() {
            stopRecording()
        }
    }
    
    private func isRecordTimeOut() -> Bool {
        let duration = writeSession.segments.duration
        let expectedDuration = jarvis.maximumCaptureDuration
        if duration.isValid && expectedDuration.isValid && (-1 != CMTimeCompare(duration, expectedDuration)) {
            return true
        }
        return false
    }
    
    // MARK: Setup capture/write session
    private func setupCaptureSession() {
        if jarvis.videoConfiguration.enable {
            jarvis.type = .Video
        } else if jarvis.audioConfiguration.enable {
            jarvis.type = .Audio
        }
        captureSession.stopRunning()
        captureSession.type = jarvis.type
        captureSession.videoConfiguration = jarvis.videoConfiguration
        captureSession.audioConfiguration = jarvis.audioConfiguration
        captureSession.videoOutput.setSampleBufferDelegate(self, queue: jarvis.videoConfiguration.sampleBufferQueue)
        captureSession.audioOutput.setSampleBufferDelegate(self, queue: jarvis.audioConfiguration.sampleBufferQueue)
        captureSession.reconfigureSession(jarvis.videoConfiguration.enable, jarvis.audioConfiguration.enable)
        if previewLayer.session != captureSession.session {
            previewLayer.session = captureSession.session
            previewLayer.connection.setOrientationIfSupported(jarvis.videoConfiguration.orientation)
        }
    }
    
    private var recordingStatus: RecordingStatus {
        get {
            return jarvis.status;
        }
        set {
            synchronized(jarvis.status) {
                jarvis.status = newValue
            }
        }
    }
}

// MARK: Help extension
extension AVCaptureConnection {
    func setOrientationIfSupported(_ orientation: AVCaptureVideoOrientation) {
        guard isVideoOrientationSupported else {
            return
        }
        guard self.videoOrientation != orientation else {
            return
        }
        videoOrientation = orientation
    }
}

extension CMSampleBuffer {
    func resize(_ rect: CGRect?) -> CVPixelBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else {
            return nil
        }
        
        guard let bufferRect = rect else {
            return imageBuffer
        }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
        }
        
        let formatType  = CVPixelBufferGetPixelFormatType(imageBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)! 
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let bytesPrePixel = bytesPerRow / CVPixelBufferGetWidth(imageBuffer)
        let options = [kCVPixelBufferCGImageCompatibilityKey : true, kCVPixelBufferCGBitmapContextCompatibilityKey : true] as CFDictionary
        let baseAddressStart = bytesPerRow * Int(bufferRect.minY) + bytesPrePixel * Int(bufferRect.minX)
        let addressPoint = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        let status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, Int(bufferRect.width), Int(bufferRect.height), formatType, &addressPoint[baseAddressStart], bytesPerRow, nil, nil, options, &pixelBuffer)
        
        if (status != 0) {
            print(status)
            return nil;
        }
        return pixelBuffer;
    }
    
    // The following function is from http://www.gdcl.co.uk/2013/02/20/iPhone-Pause.html
    func adjustTimeStamp(_ withOffset:CMTime!, _ duration:CMTime = kCMTimeInvalid) -> CMSampleBuffer? {
        var itemCount = 0
        guard 0 == CMSampleBufferGetSampleTimingInfoArray(self, 0, nil, &itemCount) else {
            return nil
        }
        
        var timingInfos = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTimeMake(0, 0),
                                                                             presentationTimeStamp: CMTimeMake(0, 0),
                                                                             decodeTimeStamp: CMTimeMake(0, 0)),
                                               count: itemCount)
        // The timingArrayOut must be allocated by the caller
        guard 0 == CMSampleBufferGetSampleTimingInfoArray(self, itemCount, &timingInfos, &itemCount) else {
            free(&timingInfos)
            return nil
        }
        
        // CMSampleTimingInfo 是 struct，值类型，var a = b 的时候，会新建一个全新的 CMSampleTimingInfo
        for i in 0..<itemCount {
            timingInfos[i].presentationTimeStamp = CMTimeSubtract(timingInfos[i].presentationTimeStamp, withOffset)
            timingInfos[i].decodeTimeStamp = CMTimeSubtract(timingInfos[i].decodeTimeStamp, withOffset)
            if duration.isValid {
                timingInfos[i].duration = duration
            }
        }
        
        var offsetSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, self, itemCount, &timingInfos, &offsetSampleBuffer)
        return offsetSampleBuffer
    }
}
