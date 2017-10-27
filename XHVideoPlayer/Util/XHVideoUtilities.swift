//
//  XHVideoUtilities.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/12.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol XHLockProtocol {
    func synchronized(_ lock: Any, closure:()->())
}

extension XHLockProtocol {
    func synchronized(_ lock: Any, closure:()->()) {
        objc_sync_enter(lock)
        closure()
        objc_sync_exit(lock)
    }
}

protocol XHErrorProtocol {
    var  domain: String {get}
    func XHError(with code: Int, msg: String) -> NSError
}

extension XHErrorProtocol {
    func XHError(with code: Int, msg: String) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey : msg])
    }
}

public extension DispatchQueue {
    private static var onceTracker = [String]()
    public class func once(token: String, block: ()->Void) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if onceTracker.contains(token) {
            return
        }
        onceTracker.append(token)
        block()
    }
}

class XHDebug {
    static var  enable  = false
    static func log(_ items: Any...) {
        if enable {
            NSLog("", items)
        }
    }
}

struct XHScreenSize {
    static var kScreenSize: CGSize {
        get {
            if .zero == XHScreenSize.screenSize {
                var size = UIScreen.main.bounds.size
                if size.height < size.width {
                    let tmp = size.height
                    size.height = size.width
                    size.width  = tmp
                }
                XHScreenSize.screenSize = size
            }
            return XHScreenSize.screenSize
        }
    }
    
    static var width: CGFloat {
        return XHScreenSize.kScreenSize.width
    }
    
    static var height: CGFloat {
        return XHScreenSize.kScreenSize.height
    }
    
    static var center: CGPoint {
        return CGPoint(x: XHScreenSize.width / 2, y: XHScreenSize.height / 2)
    }
    
    static var pixelScale: CGFloat {
        return (XHScreenSize.width / 375)
    }
    private static var screenSize = CGSize.zero
}

extension CGPoint {
    func pixelScale() -> CGPoint {
        return CGPoint(x: self.x * XHScreenSize.pixelScale, y: self.y * XHScreenSize.pixelScale)
    }
}

extension CGSize {
    func pixelScale() -> CGSize {
        return CGSize(width: self.width * XHScreenSize.pixelScale, height: self.height * XHScreenSize.pixelScale)
    }
}

extension CGRect {
    func pixelScale() -> CGRect {
        return CGRect(x: self.minX * XHScreenSize.pixelScale, y: self.minY * XHScreenSize.pixelScale, width: self.width * XHScreenSize.pixelScale, height: self.height * XHScreenSize.pixelScale)
    }
}

extension CGFloat {
    func pixelScale() -> CGFloat {
        return self * XHScreenSize.pixelScale
    }
}


extension CGRect {
    func zoom(_ x: CGFloat) -> CGRect? {
        return CGRect(x: self.minX * x, y: self.minY * x, width: self.width * x, height: self.height * x)
    }
}

class XHVideoUtilities: NSObject {
    static var isSimulator: Bool {
        return TARGET_IPHONE_SIMULATOR != 0
    }
    
    static var systemVersion: Float {
        return Float(UIDevice.current.systemVersion)!
    }

    // MARK: Camera device and input.
    static func cameraDeviceInputWith(position: AVCaptureDevicePosition) -> AVCaptureDeviceInput? {
        var deviceInput: AVCaptureDeviceInput?
        if let device = XHVideoUtilities.cameraDeviceWith(position: position) {
            do {
                deviceInput = try AVCaptureDeviceInput(device: device)
            } catch let error as NSError {
                XHDebug.log("init capture camera device input error code:\(error.code) domain:\(error.domain)")
            }
        }
        return deviceInput
    }
    
    static func cameraDeviceWith(position: AVCaptureDevicePosition!) -> AVCaptureDevice? {
        var expectedDevice: AVCaptureDevice? = nil
        var devices: [AVCaptureDevice]? = nil
        
        if #available(iOS 10.0, *) {
            devices = AVCaptureDeviceDiscoverySession(deviceTypes: [AVCaptureDeviceType.builtInWideAngleCamera], mediaType: AVMediaTypeVideo, position: position)!.devices;
        } else {
            devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as? [AVCaptureDevice]
        }
        
        if nil != devices {
            for device in devices! {
                let dev: AVCaptureDevice = device
                if position == dev.position {
                    expectedDevice = dev
                    break
                }
            }
        }
        return expectedDevice
    }
    
    // MARK: Microphone
    static func microphoneDeviceInput() -> AVCaptureDeviceInput? {
        var deviceInput: AVCaptureDeviceInput?
        if let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio) {
            do {
                deviceInput = try AVCaptureDeviceInput(device: device)
            } catch let error as NSError {
                XHDebug.log("init capture audio device input error code:\(error.code) domain:\(error.domain)")
            }
        }
        return deviceInput
    }
    
    // MARK: helper
    // if date == nil, return format time stampe of current date
    static var dateFormatter: DateFormatter?
    static func formattedTimestampStringFrom(date: Date?) -> String? {
        if nil == dateFormatter {
            dateFormatter = DateFormatter()
            dateFormatter!.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'"
            dateFormatter!.locale = NSLocale.autoupdatingCurrent
        }
        return dateFormatter!.string(from: (nil == date) ? Date() : date!)
    }
    
    // file manager
    static func isFileExistedAt(path: String!)-> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    static func cleanFileAt(path: String!)-> URL? {
        let url = URL.init(fileURLWithPath: path)
        if XHVideoUtilities.isFileExistedAt(path: path) {
            do {
                try FileManager.default.removeItem(at: url)
                XHDebug.log("remove file at path \(path) successed")
                return url
            } catch let error as NSError {
                XHDebug.log("remove file at path \(path) failed, code \(error.code) msg \(error.localizedDescription)")
            }
        } else {
            XHDebug.log("file at path \(path) is not existed")
            return url
        }
        return nil
    }
        
    // device authorization
    static func cameraAuthorizationStatus() -> Bool {
        if AVCaptureDevice.responds(to: #selector(AVCaptureDevice.authorizationStatus(forMediaType:))) {
            let cameraStatus = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo)
            if AVAuthorizationStatus.restricted == cameraStatus || AVAuthorizationStatus.denied == cameraStatus {
                return false
            }
            return true
        }
        return false
    }
    
    static func microphoneAuthorizationStatus() -> Bool {
        if AVCaptureDevice.responds(to: #selector(AVCaptureDevice.authorizationStatus(forMediaType:))) {
            let audioStatus = AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeAudio)
            if AVAuthorizationStatus.restricted == audioStatus || AVAuthorizationStatus.denied == audioStatus {
                return false
            }
            return true
        }
        return false
    }
}

extension UIAlertView : UIAlertViewDelegate {
    typealias XHAlertViewClickedHandler = (UIAlertView, Int)->Void
    private static var XHAlertClickHandlerKey: UInt8 = 0
    var clickedHandler: XHAlertViewClickedHandler? {
        get {return objc_getAssociatedObject(self, &UIAlertView.XHAlertClickHandlerKey) as? XHAlertViewClickedHandler}
        set {objc_setAssociatedObject(self, &UIAlertView.XHAlertClickHandlerKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)}
    }

    convenience init(title: String, message: String, cancelButtonTitle: String?, otherButtonTitles firstButtonTitle: String, _ moreButtonTitles: String..., clickedHandler: XHAlertViewClickedHandler?) {
        self.init(title: title, message: message, delegate: nil, cancelButtonTitle: cancelButtonTitle, otherButtonTitles: firstButtonTitle)
        moreButtonTitles.forEach { (title) in
            addButton(withTitle: title)
        }
        self.delegate = self
        self.clickedHandler = clickedHandler
    }
    
    public func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        clickedHandler?(alertView, buttonIndex)
    }
}
