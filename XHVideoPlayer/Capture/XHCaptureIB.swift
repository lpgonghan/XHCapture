//
//  XHCaptureIB.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/14.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

// MARK: capture button
typealias CaptureButtonTouchesHanlder = (CaptureButton, UIGestureRecognizerState) -> Void
@IBDesignable
class CaptureButton: UIButton {
    private var _defaultImage: UIImage?
    private var _highlightImage: UIImage?
    var touches: CaptureButtonTouchesHanlder?
    
    @IBInspectable var borderColor: UIColor = UIColor() {
        didSet {
            layer.borderColor = borderColor.cgColor
        }
    }
    
    @IBInspectable var borderWidth:  CGFloat = CGFloat() {
        didSet {
            layer.borderWidth = borderWidth
        }
    }
    
    @IBInspectable var cornerRadius: CGFloat = CGFloat() {
        didSet {
            layer.cornerRadius = cornerRadius
        }
    }
    
    @IBInspectable var highlightImageName: String = String() {
        didSet {
            _highlightImage = UIImage(named: highlightImageName)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        highlighted(true)
        self.touches?(self, .began)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        self.touches?(self, .changed)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        highlighted(false)
        self.touches?(self, .ended)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        highlighted(false)
        self.touches?(self, .cancelled)
    }
    
    func highlighted(_ highlight: Bool) {
        guard nil != _highlightImage else {
            return
        }
        
        if nil == _defaultImage {
            _defaultImage = image(for: UIControlState.normal)
        }
        
        if highlight {
            setImage(_highlightImage, for: UIControlState.normal)
        } else {
            setImage(_defaultImage, for: UIControlState.normal)
        }
    }
}

// MARK: slider view
class SliderView: UIView {
    @IBOutlet weak var lineView: UIView!
    @IBOutlet weak var slider: UIImageView!
    @IBOutlet weak var sliderMinX: NSLayoutConstraint!
    lazy var range: (minX: CGFloat, maxX: CGFloat) = (self.lineView.frame.minX, self.lineView.frame.maxX)
    var available = false
    var percentage: CGFloat {
        set {
            var percentage = newValue
            percentage = CGFloat.minimum(1, newValue)
            percentage = CGFloat.maximum(0, percentage)
            move(to: lineView.frame.width * percentage + range.minX)
            hide(with: true)
        }
        get {
            return percentageValue
        }
    }
    var percentageHandler: ((CGFloat)->Void)?
    
    override func awakeFromNib() {
        alpha = 0
        lineView.layer.cornerRadius = 2
        lineView.layer.masksToBounds = true
        slider.isUserInteractionEnabled = true
        slider.addGestureRecognizer(UIPanGestureRecognizer.init(target: self, action: #selector(SliderView.panGesture(_:))))
    }
    
    static func xibInstance() -> SliderView {
        let nibs = Bundle.main.loadNibNamed("XHCaptureIB", owner: nil, options: nil)!
        return nibs[1] as! SliderView
    }
    
    @objc private func panGesture(_ gesture: UIPanGestureRecognizer) {
        let offset = gesture.translation(in: self)
        let point  = gesture.location(in: self)
        if gesture.state == .began {
            available = slider.frame.contains(point)
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideAfterDelay), object: nil)
        } else if .changed == gesture.state {
            
        } else {
            available = false
            hide(with: true)
        }
        
        if available {
            move(to: slider.center.x + offset.x)
            if let hander = percentageHandler {
                hander(percentageValue)
            }
        }
        gesture.setTranslation(.zero, in: self)
    }
    
    private func move(to centerX: CGFloat) {
        alpha = 1
        var x = centerX
        x = CGFloat.maximum(x, range.minX)
        x = CGFloat.minimum(x, range.maxX)
        percentageValue = (x - range.minX) / (range.maxX - range.minX)
        sliderMinX.constant = (x - slider.frame.width / 2)
        layoutIfNeeded()
    }
    private var percentageValue: CGFloat = 0
    
    private func hide(with animation: Bool) {
        guard animation else {
            alpha = 0
            return
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideAfterDelay), object: nil)
        perform(#selector(self.hideAfterDelay), with: nil, afterDelay: 3)
    }
    
    @objc private func hideAfterDelay() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0
        }
    }
}

// MARK: capture segments preview
extension XHWriteSegment {
    var thumbnail: UIImage? {
        get {
            var image: UIImage?
            guard let avasset = asset else {
                return image
            }
            let imageGenerator = AVAssetImageGenerator(asset: avasset)
            imageGenerator.maximumSize = CGSize(width: 100, height: 100).pixelScale()
            imageGenerator.appliesPreferredTrackTransform = true
            do {
                let cgimage = try imageGenerator.copyCGImage(at: kCMTimeZero, actualTime: nil)
                image = UIImage(cgImage: cgimage)
            } catch {
                XHDebug.log(error.localizedDescription)
            }
            return image
        }
    }
}

protocol QueueView {
    var qInset: UIEdgeInsets {get}
    var qSize : CGSize {get}
}

class SegmentTile: UIView, QueueView {
    private let _margin = CGFloat(10).pixelScale()
    var qInset: UIEdgeInsets {
        return UIEdgeInsetsMake(_margin, _margin, 0, _margin)
    }
    var qSize: CGSize {
        return CGSize(width: 100, height: 130).pixelScale()
    }
    
    private var _segment: XHWriteSegment?
    private var _index = 0

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var gestureView: UIImageView!
    
    var removeSegment: ((SegmentTile)->Void)?
    var segment: XHWriteSegment? {
        get {return _segment}
        set {
            guard let sgm = newValue else {
                return
            }
            _segment = sgm
            imageView.image = sgm.thumbnail
            label.text = String(format: "%.1f", CMTimeGetSeconds(sgm.duration))
        }
    }
    var index: Int {
        get {return _index}
        set {
            _index = newValue
            let left = qInset.left + (qInset.left + qSize.width) * CGFloat(index)
            frame = CGRect(origin: CGPoint(x: left, y: qInset.top), size: qSize)
        }
    }
    
    static func initXIB(with segment: XHWriteSegment, at index: Int) -> SegmentTile {
        let nibs = Bundle.main.loadNibNamed("XHCaptureIB", owner: nil, options: nil)!
        let tile = nibs[3] as! SegmentTile
        tile.segment = segment
        tile.index = index
        return tile
    }
    
    override func awakeFromNib() {
        layer.cornerRadius = 3
        gestureView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tap(gesture:))))
        gestureView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.long(gesture:))))
    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }) { (finished) in
            self.removeFromSuperview()
        }
    }
    
    func tap(gesture: UITapGestureRecognizer) {
        
    }
    
    func long(gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            UIAlertView(title: "提示", message: "确定要删除片段吗？", cancelButtonTitle: "取消", otherButtonTitles: "确定", clickedHandler: { (alertView, index) in
                if index == 1 {
                    self.removeSegment?(self)
                }
            }).show()
        }
    }
}

class SegmentPreviewView: UIView {
    @IBOutlet weak var scrollView: UIScrollView!
    private var _timer:  SwiftCountDownTimer?
    private var _segmentTiles = [SegmentTile]()

    var closeHandler: (() -> Void)?
    var removeSegmentComplete: (() -> Void)?
    var segments: XHWriteSegments?
    
    static func xibInstance() -> SegmentPreviewView {
        let nibs = Bundle.main.loadNibNamed("XHCaptureIB", owner: nil, options: nil)!
        return nibs[2] as! SegmentPreviewView
    }
    
    func layoutSegments() {
        _segmentTiles.forEach { (tile) in
            tile.removeFromSuperview()
        }
        _segmentTiles.removeAll()
        
        guard let sgms = segments else {
            return
        }
        
        for index in 0..<sgms.count {
            let tile = SegmentTile.initXIB(with: sgms.array[index], at: index)
            _segmentTiles.append(tile)
            _registerHandler(tile)
            scrollView.addSubview(tile)
        }
        _resetScrollViewContentSize()
    }
    
    @IBAction func closeButtonClicked(_ button: UIButton) {
        closeHandler?()
        self._resetScrollViewContentSize()
    }
    
    private func _resetScrollViewContentSize() {
        guard let last = _segmentTiles.last else {
            return
        }
        scrollView.contentSize = CGSize(width: last.frame.maxX + last.qInset.left, height: scrollView.frame.height)
    }
    
    private func _registerHandler(_ tile: SegmentTile!) {
        tile.removeSegment = {[weak self] (segmentTile) in
            self?._removeSegment(segmentTile)
        }
    }
    
    private func _removeSegment(_ tile: SegmentTile) {
        segments?.removeSegment(at: tile.index, andDisk: true)
        _segmentTiles.remove(at: tile.index)
        tile.dismiss()
        removeSegmentComplete?()
        
        let times = _segmentTiles.count - tile.index
        if times > 0 {
            _timer = SwiftCountDownTimer(interval: .fromSeconds(0.1), times: times, handler: {(timer, leftTimes, consumeTimes) in
                UIView.animate(withDuration: 0.3, animations: {
                    let index = tile.index + consumeTimes - 1
                    self._segmentTiles[index].index = index
                })
            })
            _timer?.start()
        }
    }
}
