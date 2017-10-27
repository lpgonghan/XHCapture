//
//  ViewController.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/10.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    open override var prefersStatusBarHidden: Bool { return true }
    open override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { return .slide }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "presentCapture" {
            let nav = segue.destination as! UINavigationController
            let vc  = nav.topViewController as! CaptureViewController
            let capture = XHCapture()
            vc.capture = capture
        }
    }
}

