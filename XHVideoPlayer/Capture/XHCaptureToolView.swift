//
//  XHCaptureToolView.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/10/13.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Foundation
import UIKit

class XHCaptureToolView: UIView {
    let focusView = FocusView(frame: CGRect(x: 100, y: 100, width: 60, height: 60).pixelScale())
    override func awakeFromNib() {
        addSubview(focusView)
    }
    
    func focus(at point: CGPoint) {
        focusView.center = point
        focusView.startFocus()
        bringSubview(toFront: focusView)
    }
}

class FocusView: UIImageView, CAAnimationDelegate {
    private let kFocusScaleAnimationKey = "kFocusScaleAnimationKey"
    private let kFocusFlashAnimationKey = "kFocusFlashAnimationKey"
    private let kFocusAnimationKey = "kFocusAnimationKey"
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.alpha = 0
        self.image = UIImage(named: "focus")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func isAnimationExisted(key: String!) -> Bool {
        if let keys = layer.animationKeys() {
            guard !(keys.contains(key)) else {
                return true
            }
        }
        return false
    }
    
    func startFocus() {
        if isAnimationExisted(key: kFocusScaleAnimationKey) || isAnimationExisted(key: kFocusFlashAnimationKey) {
            stopFocus()
        }
        
        alpha = 1
        let scaleAnimation: CABasicAnimation = {
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.duration = 0.15
            animation.fromValue = 1.5
            animation.toValue = 1
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
            return animation
        }()
        
        let blinkAnimation: CAKeyframeAnimation = {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.beginTime = CACurrentMediaTime() + 0.25
            animation.duration = 1.5
            animation.values = [1, 0, 1, 0, 1, 0]
            animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            animation.isRemovedOnCompletion = false
            animation.fillMode = kCAFillModeForwards
            animation.delegate = self
            animation.setValue(kFocusFlashAnimationKey, forKey: kFocusAnimationKey)
            return animation
        }()
        
        layer.add(scaleAnimation, forKey: kFocusScaleAnimationKey)
        layer.add(blinkAnimation, forKey: kFocusFlashAnimationKey)
    }
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else {
            return
        }
        
        if anim.value(forKey: kFocusAnimationKey) as! String == kFocusFlashAnimationKey {
            stopFocus()
        }
    }
    
    func stopFocus() {
        alpha = 0
        layer.removeAnimation(forKey: kFocusScaleAnimationKey)
        layer.removeAnimation(forKey: kFocusFlashAnimationKey)
    }
}
