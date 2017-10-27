//
//  XHCaptureConfiguration.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/20.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

enum ExportPresetQuality: Int {
    case Low
    case Medium
    case Highest
    
    func videoPrePixels() -> Float {
        switch self {
        case .Low:
            return 2.1
        case .Medium:
            return 6
        case .Highest:
            return 10.1
        }
    }
    
    // channels 1 bitRate 64Kbps=增加话音（手机铃声最佳比特率设定值、手机单声道MP3播放器最佳设定值）
    // channels 2 bitRate 128Kbps=磁带（手机立体声MP3播放器最佳设定值、低档MP3播放器最佳设定值）
    func audioBitRate() -> (channels: UInt32, bitRate: Int32, sampleRate: Float64) {
        switch self {
        case .Low:
            return (1, 64000,  44100)
        case .Medium:
            return (2, 128000, 44100)
        case .Highest:
            return (2, 320000, 44100)
        }
    }
}

enum AdditionalProperty: String {
    case Key = "kXHAdditationKey"
    case Rotation = "kXHVideoRotationKey"
}

class XHVideoConfiguration: XHMediaConfiguration {
    private var _CMVideoFormatDimensions:  CMVideoDimensions?
    private var _CVPixelBufferResizeFrame: CGRect?
    private var _ScreenRect: CGRect?
    private var _ExportDimensions: CMVideoDimensions?
    
    var affineTransform: CGAffineTransform! = CGAffineTransform.identity
    var codec: String! = AVVideoCodecH264
    var maxFrameRate: Int32! = 30 //1 means key frames only, default is 30.
    var scalingModel: String! = AVVideoScalingModeResizeAspectFill
    var profileLevel: String! = AVVideoProfileLevelH264BaselineAutoLevel
    var position = AVCaptureDevicePosition.back
    var orientation = AVCaptureVideoOrientation.portrait
    
    override init() {
        super.init()
        sampleBufferQueue = XHDispatchQueues.video
    }
    
    /// - Parameters:
    ///   - screenRect: if this value is nil, UIScreen.main.bounds will be used.
    ///   - size: if this vale is nil, the input video size received from camera will be used.
    ///
    ///                                             CMSampleBuffer Dimensions
    ///                      UIScreen.bounds        (1080, 1080)
    ///                      (375 * 667)            ┌──────────────────┐
    ///                      ┌──────────────┐       │                  │
    ///                      │              │       │ ┌──────────────┐ │
    ///                      │  ┌────────┐  │       │ │             <------ _CVPixelBufferResizeFrame
    /// ScreenRect  ------------->       │  │       │ │              │ │
    /// (0, 64, 300, 300)    │  │        │  │       │ │              │ │
    ///                      │  │        ---- scale --->             │ │             ┌────┐
    ///                      │  └────────┘  │       │ │             ------ export -> │    │ size (540, 540)
    ///                      │              │       │ └──────────────┘ │             └────┘
    ///                      │              │       │                  │
    ///                      │              │       │                  │
    ///                      └──────────────┘       │                  │
    ///                                             └──────────────────┘
    ///  _CVPixelBufferResizeFrame = (0, 64 * _CMVideoFormatDimensions.width / screenRect.width, _CMVideoFormatDimensions.width, _CMVideoFormatDimensions.width)
    func export(screenRect: CGRect?, to size: CMVideoDimensions?) {
        _ExportDimensions = size
        _ScreenRect = screenRect
    }
    
    var customResizeFrame: CGRect? {
        return _CVPixelBufferResizeFrame
    }
    
    var additionalProperties: [String : Any] {
        get {
            return [AdditionalProperty.Rotation.rawValue : affineTransform]
        }
    }
    
    
    /// This method must be called after 'export(screenRect:, to size:)' if you want to custom export region and size.
    func assetWriterSettings(with descrption: CMFormatDescription!) -> [String : Any] {
        
        var dimensions = CMVideoFormatDescriptionGetDimensions(descrption)
        _CMVideoFormatDimensions = dimensions
        
        let width = dimensions.width
        let height = dimensions.height
        dimensions = _ExportDimensions ?? dimensions
        
        _CVPixelBufferResizeFrame = nil
        if let rect = _ScreenRect {
            if rect.width * rect.height > 0 {
                let scale = CGFloat.minimum(CGFloat(width) / rect.width, CGFloat(height) / rect.height)
                _CVPixelBufferResizeFrame = rect.zoom(scale)
            }
        }

        if 0 == bitRate {
            bitRate = Int32(Float(dimensions.width) * Float(dimensions.height) * quality.videoPrePixels())
        }
        
        let compressionProperties: [String : Any] = [AVVideoAverageBitRateKey : bitRate,
                                                     AVVideoMaxKeyFrameIntervalKey : maxFrameRate,
                                                     AVVideoAllowFrameReorderingKey : false,
                                                     AVVideoExpectedSourceFrameRateKey : 30,
                                                     AVVideoProfileLevelKey : profileLevel]
        
        let settings: [String : Any] = [AVVideoWidthKey : dimensions.width,
                                        AVVideoHeightKey: dimensions.height,
                                        AVVideoCodecKey : codec,
                                        AVVideoScalingModeKey: scalingModel,
                                        AVVideoCompressionPropertiesKey: compressionProperties]
        return settings
    }
}

class XHAudioConfiguration: XHMediaConfiguration {
    var sampleRate: Float64 = 44100 //采样率 单位是HZ 通常设置成44100 44.1k
    var channels: UInt32 = 0 //1 单声道，2 双声道，0 默认值
    var ignore = true //ignore sampleRate and channels,
    var format = kAudioFormatMPEG4AAC
    
    override init() {
        super.init()
        sampleBufferQueue = XHDispatchQueues.audio
    }
    
    func assertWirterSettings(with descrption: CMFormatDescription!) -> [String : Any] {
        if nil != descrption && ignore {
            if let audioStreamBasicDescrption = CMAudioFormatDescriptionGetStreamBasicDescription(descrption)?.pointee {
                channels = audioStreamBasicDescrption.mChannelsPerFrame
                sampleRate = audioStreamBasicDescrption.mSampleRate
            }
        }
        
        if 0 == channels {
            channels = quality.audioBitRate().channels
        }
        
        if 0 == sampleRate {
            sampleRate = quality.audioBitRate().sampleRate
        }
        
        if 0 == bitRate {
            bitRate = quality.audioBitRate().bitRate
        }
        
        let settings: [String : Any] = [AVFormatIDKey : format,
                                        AVEncoderBitRateKey : bitRate,
                                        AVNumberOfChannelsKey : channels,
                                        AVSampleRateKey : sampleRate]
        return settings
    }
}

class XHMediaConfiguration: NSObject {
    var enable: Bool! = true
    var quality = ExportPresetQuality.Low
    var bitRate: Int32 = 0 // if this property is 0, bitRate = quality.videoBitRate()
    var sampleBufferQueue: DispatchQueue?
    var sessionPreset = AVCaptureSessionPresetHigh
}
