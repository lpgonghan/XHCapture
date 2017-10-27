//
//  XHCaptureSession.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/14.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import AVFoundation

enum CaptureFlashMode: Int {
    case Off = 0
    case On = 1
    case Auto = 2
}

class XHCaptureSession: NSObject, XHErrorProtocol {
    private class Devices {
        let front = XHVideoUtilities.cameraDeviceInputWith(position: AVCaptureDevicePosition.front)
        let back  = XHVideoUtilities.cameraDeviceInputWith(position: AVCaptureDevicePosition.back)
        let audio = XHVideoUtilities.microphoneDeviceInput()
    }
    
    private let devices: Devices
    private let captureSession: AVCaptureSession
    private let captureVideoOutput: AVCaptureVideoDataOutput
    private let captureAudioOutput: AVCaptureAudioDataOutput
    
    var domain: String {return "XHCaptureSession"}
    var type = CaptureType.Unknown
    var videoConfiguration: XHVideoConfiguration?
    var videoOutput: AVCaptureVideoDataOutput {return captureVideoOutput}
    var audioConfiguration: XHAudioConfiguration?
    var audioOutput: AVCaptureAudioDataOutput {return captureAudioOutput}
    var session: AVCaptureSession {return captureSession}
    var isRunning: Bool {return captureSession.isRunning}
    var preset: String {
        get {return captureSession.sessionPreset}
        set {captureSession.sessionPreset = newValue}
    }
    var isReady: Bool {
        if type.hasAudio && !captureSession.outputs.contains {(captureAudioOutput.isEqual($0))} {
            return false
        }
        if type.isVideo && !captureSession.outputs.contains {(captureVideoOutput.isEqual($0))} {
            return false
        }
        return true
    }
    
    deinit {
        NSLog("dealloc")
    }

    override init() {
        devices = Devices()
        captureSession = AVCaptureSession()
        captureAudioOutput = AVCaptureAudioDataOutput()
        captureVideoOutput = {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = false
            output.videoSettings =  [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA]
            return output
        }()
        super.init()
    }
    
    // MARK: Capture Running State
    func startRunning() {captureSession.startRunning()}
    func stopRunning()  {captureSession.stopRunning()}
    
    // MARK: Action
    func swapCamera() { //back->front->back
        let device = (currentDeviceInput(mediaType: AVMediaTypeVideo) ?? devices.front)!.device
        videoConfiguration?.position = (.back == (device?.position ?? .front)) ? .front : .back
        reconfigureSession(true, false)
    }
    
    func focus(at point: CGPoint, continuous: Bool) {
        setupFocus(at: point, continuous: continuous)
    }
    
    var flashModel: CaptureFlashMode? {
        get {return getFlashMode()}
        set {setFlashMode(mode: newValue)}
    }
    
    var zoomFactor: CGFloat {
        get {return getZoomFactor()}
        set {setZoomFactor(newValue)}
    }
    
    func reconfigureSession(_ video: Bool = false, _ audio: Bool = false) {
        var error: NSError?
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }
        
        if preset != captureSession.sessionPreset {
            if captureSession.canSetSessionPreset(preset) {
                captureSession.sessionPreset = preset
            } else {
                error = XHError(with: 1, msg: "cannot set session preset:" + preset)
            }
        }
        
        // video
        if videoConfiguration?.enable ?? false {
            if video {
                if !captureSession.outputs.contains(where: {captureVideoOutput.isEqual($0)}) {
                    if captureSession.canAddOutput(captureVideoOutput) {
                        captureSession.addOutput(captureVideoOutput)
                    } else {
                        error = XHError(with: 2, msg: "cannot add video output to session")
                    }
                }
                error = setupVideoInputWith(position: videoConfiguration?.position ?? .back)
                captureVideoOutput.connection(withMediaType: AVMediaTypeVideo).setOrientationIfSupported(videoConfiguration?.orientation ?? .portrait)
            }
        } else {
            captureSession.removeOutput(captureVideoOutput)
            if let currentInput = currentDeviceInput(mediaType: AVMediaTypeVideo) {
                captureSession.removeInput(currentInput)
                removeVideoObervers(currentInput.device)
            }
        }
        
        // audio
        if audioConfiguration?.enable ?? false {
            if audio {
                if !captureSession.outputs.contains(where: {captureAudioOutput.isEqual($0)}) {
                    if captureSession.canAddOutput(captureAudioOutput) {
                        captureSession.addOutput(captureAudioOutput)
                    } else {
                        error = XHError(with: 3, msg: "cannot add audio output to session")
                    }
                }
                if nil == currentDeviceInput(mediaType: AVMediaTypeAudio) {
                    if captureSession.canAddInput(devices.audio) {
                        captureSession.addInput(devices.audio)
                    }
                }
            }
        } else {
            captureSession.removeOutput(captureAudioOutput)
            if let currentInput = currentDeviceInput(mediaType: AVMediaTypeAudio) {
                captureSession.removeInput(currentInput)
            }
        }
    }
    
    // MARK: Oberver
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //guard let newValue = change else {
        //    return
        //}
        //
        //if "adjustingFocus" == keyPath {
        //    let adjustingFocus = newValue[NSKeyValueChangeKey.newKey] as! Bool
        //} else if "adjustingExposure" == keyPath {
        //    let adjustingExposure = newValue[NSKeyValueChangeKey.newKey] as! Bool
        //}
    }
    
    private func addVideoObervers(_ device: AVCaptureDevice) {
        //device.addObserver(self, forKeyPath: "adjustingFocus", options: .new, context: nil)
        //device.addObserver(self, forKeyPath: "adjustingExposure", options: .new, context: nil)
    }
    private func removeVideoObervers(_ device: AVCaptureDevice) {
        //device.removeObserver(self, forKeyPath: "adjustingFocus")
        //device.removeObserver(self, forKeyPath: "adjustingExposure")
    }
    
    // MARK: Focus/Exposure/WhiteBalance
    private func setupFocus(at point: CGPoint, continuous: Bool) {
        guard let device = currentDeviceInput(mediaType: AVMediaTypeVideo)?.device else {
            return
        }
        let focusModel: AVCaptureFocusMode = {
            var model = AVCaptureFocusMode.autoFocus
            if continuous && device.isFocusModeSupported(AVCaptureFocusMode.continuousAutoFocus) {
                model = AVCaptureFocusMode.continuousAutoFocus
            }
            return model
        }()
        let exposureModel: AVCaptureExposureMode = {
            var model = AVCaptureExposureMode.autoExpose
            if continuous && device.isExposureModeSupported(AVCaptureExposureMode.continuousAutoExposure) {
                model = AVCaptureExposureMode.continuousAutoExposure
            }
            return model
        }()
        let whiteBalanceModel: AVCaptureWhiteBalanceMode = {
            var balance = AVCaptureWhiteBalanceMode.autoWhiteBalance
            if continuous && device.isWhiteBalanceModeSupported(AVCaptureWhiteBalanceMode.continuousAutoWhiteBalance) {
                balance = AVCaptureWhiteBalanceMode.continuousAutoWhiteBalance
            }
            return balance
        }()
        
        do {
            try device.lockForConfiguration()
            
            // focus
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(focusModel) {
                device.focusMode = focusModel
            }
            
            // exposure
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(exposureModel) {
                device.exposureMode = exposureModel
            }
            
            // white balance
            if device.isWhiteBalanceModeSupported(whiteBalanceModel) {
                device.whiteBalanceMode = whiteBalanceModel
            }
            device.unlockForConfiguration()
        } catch {
            XHDebug.log(error)
        }
    }
    
    // MARK: Device Input
    private func setupVideoInputWith(position: AVCaptureDevicePosition!) -> NSError? {
        var verror: NSError?
        let currentVideoInput = currentDeviceInput(mediaType: AVMediaTypeVideo)
        let newVideoInput = deviceInput(with: position)
        
        if currentVideoInput != newVideoInput {
            if let currentInput = currentVideoInput {
                captureSession.removeInput(currentInput)
                removeVideoObervers(currentInput.device)
            }
            
            if let newInput = newVideoInput {
                do {
                    try newInput.device.lockForConfiguration()
                    if newInput.device.isSmoothAutoFocusSupported {
                        newInput.device.isSmoothAutoFocusEnabled = true
                    }
                    if newInput.device.isLowLightBoostSupported {
                        newInput.device.automaticallyEnablesLowLightBoostWhenAvailable = true
                    }
                    newInput.device.unlockForConfiguration()
                    
                    if captureSession.canAddInput(newInput) {
                        captureSession.addInput(newInput)
                        addVideoObervers(newInput.device)
                        let videoConnection = captureVideoOutput.connection(withMediaType: AVMediaTypeVideo)
                        if (videoConnection?.isVideoStabilizationSupported)! {
                            if #available(iOS 8.0, *) {
                                videoConnection?.preferredVideoStabilizationMode = .auto
                            } else {
                                videoConnection?.enablesVideoStabilizationWhenAvailable = true
                            }
                        }
                    } else {
                        verror = XHError(with: 11, msg: "cannot add video device input")
                    }
                } catch {
                    verror = XHError(with: 12, msg: "failed to configure device" + error.localizedDescription)
                }
            }
        }
        return verror
    }
    
    private func deviceInput(with position: AVCaptureDevicePosition!) -> AVCaptureDeviceInput? {
        return (.front == position) ? devices.front : devices.back
    }
    
    private func currentDeviceInput(mediaType: String!) -> AVCaptureDeviceInput? {
        let inputs = captureSession.inputs as! [AVCaptureDeviceInput]
        for input in inputs {
            let device = input.device!
            if device.hasMediaType(mediaType) {
                return input
            }
        }
        return nil
    }
    
    // MARK: Flash
    private func getFlashMode() -> CaptureFlashMode? {
        guard let device = currentDeviceInput(mediaType: AVMediaTypeVideo)?.device else {
            return nil
        }
        
        if type.isVideo {
            return CaptureFlashMode(rawValue: device.torchMode.rawValue)
        }
        return CaptureFlashMode(rawValue: device.flashMode.rawValue)
    }
    
    private func setFlashMode(mode: CaptureFlashMode?) {
        guard let device = currentDeviceInput(mediaType: AVMediaTypeVideo)?.device else {
            return
        }
        guard device.hasFlash else {
            return
        }
        guard let newMode = mode else {
            return
        }
        do {
            func setTorchModelIfSupported(mode: AVCaptureTorchMode) {
                if device.isTorchModeSupported(mode) {
                    device.torchMode = mode
                }
            }
            func setFlashModelIfSupported(mode: AVCaptureFlashMode) {
                if device.isFlashModeSupported(mode) {
                    device.flashMode = mode
                }
            }
            
            try device.lockForConfiguration()
            if type.isVideo {
                setTorchModelIfSupported(mode: AVCaptureTorchMode(rawValue: newMode.rawValue)!)
            } else {
                setFlashModelIfSupported(mode: AVCaptureFlashMode(rawValue: newMode.rawValue)!)
            }
            device.unlockForConfiguration()
        } catch {
            XHDebug.log("set flash model failed")
        }
    }
    
    // MARK: Zoom Factor
    private func getZoomFactor() -> CGFloat {
        if let device = currentDeviceInput(mediaType: AVMediaTypeVideo)?.device {
            if device.responds(to: #selector(getter: AVCaptureDevice.videoZoomFactor)) {
                return device.videoZoomFactor
            }
        }
        return 1
    }
    
    private func setZoomFactor(_ v: CGFloat) {
        guard let device = currentDeviceInput(mediaType: AVMediaTypeVideo)?.device else {
            return
        }
        guard device.responds(to: #selector(setter: AVCaptureDevice.videoZoomFactor)) else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            if v <= device.activeFormat.videoMaxZoomFactor {
                device.videoZoomFactor = v
            } else {
                XHDebug.log("fail to set video zoom: \(v), max: \(device.activeFormat.videoMaxZoomFactor)")
            }
            device.unlockForConfiguration()
        } catch {
            XHDebug.log("fail to set video zoom: \(error.localizedDescription)")
        }
    }
}
