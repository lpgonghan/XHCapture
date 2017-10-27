//
//  CatcherViewController.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/14.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

enum CaptureFormat {
    case Preset
    case Square
    
    var exportSize: CMVideoDimensions {
        return (.Square == self) ? CaptureFormat.squareVideoSize : CaptureFormat.fullVideoSize
    }
    
    var screenRect: CGRect {
        return (.Square == self) ? CaptureFormat.squareScreen : CaptureFormat.fullScreen
    }
    
    var captureButtonImage: UIImage {
        return UIImage(named: "record_" + ((.Square == self) ? "a" : "b"))!
    }
    
    var settingButtonImage: UIImage {
        return UIImage(named: "setting_" + ((.Square == self) ? "a" : "b"))!
    }

    var nextButtonImage: UIImage {
        return UIImage(named: "right_" + ((.Square == self) ? "a" : "b"))!
    }

    var closeButtonImage: UIImage {
        return UIImage(named: "close_" + ((.Square == self) ? "a" : "b"))!
    }
    
    func exchange() -> CaptureFormat! {
        return (.Square == self) ? .Preset : .Square
    }
    
    static let squareScreen = CGRect(x: 0, y: 64, width: XHScreenSize.width, height: XHScreenSize.width)
    static let fullScreen   = CGRect(origin: .zero, size: XHScreenSize.kScreenSize)
    static let squareVideoSize = CMVideoDimensions(width: 540, height: 540)
    static let fullVideoSize   = CMVideoDimensions(width: 540, height: 960)
}

extension CaptureFlashMode {
    func nextState() -> CaptureFlashMode {
        switch self {
        case .Off:
            return .Auto
        case .Auto:
            return .On
        case .On:
            return .Off
        }
    }
    
    func icon() -> String {
        switch self {
        case .Off:
            return "flash_off"
        case .Auto:
            return "flash_auto"
        case .On:
            return "flash_on"
        }
    }
}

extension UIView {
    func xiblayout(_ block: ()->Void) {
        layoutIfNeeded()
        defer {
            layoutIfNeeded()
        }
        block()
    }
}

class CaptureViewController: UIViewController, XHWriteSessionDelegate {
    var capture: XHCapture!
    @IBOutlet var captureButton: CaptureButton!
    @IBOutlet var settingButton: CaptureButton!
    @IBOutlet var nextButton: CaptureButton!
    @IBOutlet var closeButton: UIButton!
    @IBOutlet var flashButton: UIButton!
    @IBOutlet var segmentButton: UIButton!
    @IBOutlet var captureView: XHCaptureToolView!
    @IBOutlet var topViewHeight: NSLayoutConstraint! //navigation bar height
    @IBOutlet var bottomViewHeight: NSLayoutConstraint! //bottom view height
    @IBOutlet var toolViewHeight: NSLayoutConstraint!
    @IBOutlet var settingViewTopMargin: NSLayoutConstraint!
    @IBOutlet var segmentButtonWidth: NSLayoutConstraint!
    lazy var zoomSlider: SliderView = {
        let slider = SliderView.xibInstance()
        let sliderHeight = CGFloat(40).pixelScale()
        slider.frame = CGRect(origin: CGPoint(x: 0, y: CaptureFormat.squareScreen.maxY - sliderHeight),
                              size: CGSize(width: XHScreenSize.width, height: sliderHeight))
        return slider
    }()
    lazy var segmentsPreview: SegmentPreviewView = {
        let preview = SegmentPreviewView.xibInstance()
        let height  = XHScreenSize.height - CaptureFormat.squareScreen.maxY
        preview.frame = CGRect(x: 0, y: XHScreenSize.height, width: XHScreenSize.width, height: height)
        return preview
    }()
    
    class Setting {
        var state = false
        var animating = false
        let hideConstant = XHScreenSize.height - CaptureFormat.squareScreen.maxY
        let showConstant = CGFloat(0)
        var constant: CGFloat {
            return self.state ? showConstant : hideConstant
        }
    }
    var setting = Setting()
    var segment: (state: Bool, animating: Bool) = (false, false)
    var format:  (state: CaptureFormat, animating: Bool) = (.Square, false)
    var flashModel = CaptureFlashMode.Off
    var zoomFactor: (start: CGFloat, min: CGFloat, max: CGFloat) = (1, 1, 4)
    // Duration
    private let maxCaptureDuration: Float = 9
    private var captureDuration: Float = 0
    
    deinit {
        XHDebug.log("dealloc")
    }
    
    open override var prefersStatusBarHidden: Bool { return true }
    open override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { return .slide }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.view.xiblayout {
            topViewHeight.constant = format.state.screenRect.midY
            bottomViewHeight.constant = XHScreenSize.height - format.state.screenRect.midY
            toolViewHeight.constant = XHScreenSize.height - CaptureFormat.squareScreen.maxY
            settingViewTopMargin.constant = setting.hideConstant
        }
        self.setupUserinterface()
        self.setupCatcher()
        self.setupActions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        capture.stopCapture()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    func setupUserinterface() {
        view.addSubview(zoomSlider)
        segmentButton.layer.cornerRadius = 3
        view.addSubview(segmentsPreview)
    }
    
    func setupCatcher() {
        capture.layer.frame = captureView.bounds
        capture.captureSessionPreset = AVCaptureSessionPresetHigh
        capture.maximumDuration = CMTimeMake(Int64(30 * maxCaptureDuration), 30) // duration = 30 sec (900/30)
        capture.writeSessionDelegate = self
        captureView.layer.addSublayer(capture.layer)
        flashButton.setImage(UIImage(named: flashModel.icon()), for: .normal)
        captureExport(with: format.state)
        
        XHDispatchQueues.capture.async {
            self.capture.startCapture()
            DispatchQueue.main.safeSync {
                self.changeCaptureFormatAnimation(self.format.state, completion: nil)
            }
        }
    }
    
    func setupActions () {
        settingButton.touches = {[weak self] (_, state) in
            self?.captureSetting(true)
        }
        
        segmentsPreview.closeHandler = { [weak self] in
            self?.captureSegment(false)
        }
        
        segmentsPreview.removeSegmentComplete = { [weak self] in
            guard let strongself = self else {
                return
            }
            let duration = CMTimeGetSeconds(strongself.capture.segments.duration)
            let count = strongself.capture.segments.count
            strongself.layoutSegments(count, duration)
        }
        
        captureButton.touches = {[weak self] (_, state) in
            switch state {
            case .began:
                self?.startRecording()
            case .cancelled, .ended:
                self?.stopRecording()
            default:
                break
            }
        }
        
        zoomSlider.percentageHandler = {[weak self] (percentage: CGFloat) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.capture.zoomFactor = (percentage * (strongSelf.zoomFactor.max - strongSelf.zoomFactor.min)) + strongSelf.zoomFactor.min
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapAndFocus(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(self.pinchAndZoom(_:))))
    }
    
    // MARK: Record
    private func startRecording() {
        capture.startRecording()
    }
    
    private func stopRecording() {
        capture.stopRecording()
    }
    
    // MARK: Write session delegate
    private func layoutSegments(_ count: Int, _ duration: Float64) {
        if duration > 0 {
            segmentButtonWidth.constant = CGFloat(60).pixelScale()
            let countString = " x" + String(count) + " "
            let durationString = String(format: " %.1f", duration)
            let mstr = NSMutableAttributedString(string: countString + durationString)
            mstr.addAttribute(NSFontAttributeName, value: UIFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: countString.count))
            mstr.addAttribute(NSForegroundColorAttributeName, value: UIColor.orange, range: NSRange(location: 0, length: countString.count))
            mstr.addAttribute(NSFontAttributeName, value: UIFont.boldSystemFont(ofSize: 14), range: NSRange(location: countString.count, length: durationString.count))
            mstr.addAttribute(NSForegroundColorAttributeName, value: UIColor.white, range: NSRange(location: countString.count, length: durationString.count))
            self.segmentButton.setAttributedTitle(mstr, for: .normal)
        } else {
            self.segmentButton.setAttributedTitle(nil, for: .normal)
            segmentButtonWidth.constant = segmentButton.frame.height.pixelScale()
        }
        segmentButton.isEnabled = count > 0
    }
    
    func capture(_ capture: XHCapture, writer: XHWriteSession, writing segment: XHWriteSegment?) {
        let duration = CMTimeGetSeconds(writer.segments.duration)
        let count = writer.segments.count + 1
        DispatchQueue.main.async {
            self.layoutSegments(count, duration)
        }
    }
    
    func capture(_ capture: XHCapture, writer: XHWriteSession, finishedWriting segment: XHWriteSegment?) {
        let duration = CMTimeGetSeconds(writer.segments.duration)
        let count = writer.segments.count
        DispatchQueue.main.async {
            self.layoutSegments(count, duration)
        }
    }
    
    // MARK: Action
    @IBAction func closeSettingView(button: UIButton) {
        captureSetting(false)
    }
    
    @IBAction func close(button: UIButton) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func changeFormat(button: UIButton) {
        changeCaptureFormatAnimation(format.state.exchange()) { (format) in
            self.captureExport(with: format!)
        }
    }
    
    @IBAction func swapVideoCaptureDevice(button: UIButton) {
        capture.swapVideoCaptureDevice(completion: nil)
    }
    
    @IBAction func exchangeFlashState(button: UIButton) {
        flashModel = flashModel.nextState()
        button.setImage(UIImage(named:flashModel.icon()), for: .normal)
        capture.flashModel = flashModel
    }
    
    @IBAction func previewAssets(_ sender: Any) {
        segmentsPreview.segments = capture.segments
        segmentsPreview.layoutSegments()
        captureSegment(true)
    }
    
    private func changeCaptureFormatAnimation(_ fmt: CaptureFormat!, completion:((CaptureFormat?)->())?) {
        if !format.animating {
            format.animating = true
            format.state = fmt
            UIView.animate(withDuration: 0.15, animations: {
                self.view.xiblayout {
                    self.topViewHeight.constant = self.format.state.screenRect.minY
                    self.bottomViewHeight.constant = XHScreenSize.height - self.format.state.screenRect.maxY
                }
            }, completion: { (finished) in
                self.captureButton.setImage(self.format.state.captureButtonImage, for: UIControlState.normal)
                self.settingButton.setImage(self.format.state.settingButtonImage, for: UIControlState.normal)
                self.nextButton.setImage(self.format.state.nextButtonImage, for: UIControlState.normal)
                self.closeButton.setImage(self.format.state.closeButtonImage, for: UIControlState.normal)
                completion?(self.format.state)
                self.format.animating = false
            })
        }
    }
    
    private func captureExport(with format: CaptureFormat!) {
        capture.export(screenRect: (.Square == format) ? format.screenRect : nil, to: format.exportSize)
        let duration = CMTimeGetSeconds(capture.segments.duration)
        let count = capture.segments.count
        layoutSegments(count, duration)
    }
    
    private func captureSetting(_ show: Bool!) {
        if !setting.animating {
            setting.animating = true
            setting.state = show
            UIView.animate(withDuration: 0.15, animations: {
                self.view.xiblayout {
                    self.settingViewTopMargin.constant = self.setting.constant
                }
            }, completion: { (finished) in
                self.setting.animating = false
            })
        }
    }
    
    private func captureSegment(_ show: Bool) {
        if !segment.animating {
            segment.animating = true
            segment.state = show
            UIView.animate(withDuration: 0.15, animations: {
                let rect = CGRect(origin: CGPoint(x: 0, y: XHScreenSize.height - (show ? self.segmentsPreview.frame.height : 0)),
                                  size: self.segmentsPreview.frame.size)
                self.segmentsPreview.frame = rect
            }, completion: { (finished) in
                self.segment.animating = false
            })
        }
    }
    
    @objc private func tapAndFocus(_ gesture: UIGestureRecognizer) {
        if .ended == gesture.state {
            let point = gesture.location(in: view)
            if format.state.screenRect.contains(point) {
                captureView.focus(at: point)
                capture.focus(at: point, continuous: true)
            }
        }
    }
    
    @objc private func pinchAndZoom(_ gesture: UIPinchGestureRecognizer) {
        if .began == gesture.state {
            zoomFactor.start = capture.zoomFactor
        }
        var newZoom = gesture.scale * zoomFactor.start
        newZoom = CGFloat.minimum(newZoom, zoomFactor.max)
        newZoom = CGFloat.maximum(newZoom, zoomFactor.min)
        capture.zoomFactor = newZoom
        zoomSlider.percentage = (newZoom - zoomFactor.min) / (zoomFactor.max - zoomFactor.min)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
