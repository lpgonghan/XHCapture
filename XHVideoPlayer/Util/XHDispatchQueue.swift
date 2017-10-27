//
//  XHDispatchQueue.swift
//  XHVideoPlayer
//
//  Created by Xuehan Gong on 2017/9/24.
//  Copyright © 2017年 Xuehan Gong. All rights reserved.
//

import Dispatch

struct QueueIdentity {
    var label: String?
}

enum XHQueueLabel: String {
    case Video
    case Audio
    case Capture
    case Write
    case Common
    
    static func specific(_ label: XHQueueLabel) -> String {
        return "com.xh.\(label).queue"
    }
}

class XHDispatchQueues {
    // In a multi-threaded producer consumer system it's generally a good idea to make sure that producers do not get starved of CPU time by their consumers.
    // In this app we start with VideoDataOutput frames on a high priority queue, and downstream consumers use default priority queues.
    // Audio uses a default priority queue because we aren't monitoring it live and just want to get it into the movie.
    // AudioDataOutput can tolerate more latency than VideoDataOutput as its buffers aren't allocated out of a fixed size pool.
    public static var video: DispatchQueue = {
        return DispatchQueue.createQueue(with: XHQueueLabel.specific(.Video), qos: .userInitiated)
    }()
    public static var audio: DispatchQueue = {
        return DispatchQueue.createQueue(with: XHQueueLabel.specific(.Audio))
    }()
    public static var capture: DispatchQueue = {
        return DispatchQueue.createQueue(with: XHQueueLabel.specific(.Capture))
    }()
    public static var write: DispatchQueue = {
        return DispatchQueue.createQueue(with: XHQueueLabel.specific(.Write))
    }()
}

private var XHDispatchQueueSpecificKey: UInt8 = 0
extension DispatchQueue {
    var specific: DispatchSpecificKey<QueueIdentity>? {
        get {
            return objc_getAssociatedObject(self, &XHDispatchQueueSpecificKey) as? DispatchSpecificKey<QueueIdentity>
        }
        set {
            objc_setAssociatedObject(self, &XHDispatchQueueSpecificKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private static var mainKey: DispatchSpecificKey<QueueIdentity> = {
        let key = DispatchSpecificKey<QueueIdentity>()
        DispatchQueue.main.specific = key
        DispatchQueue.main.setSpecific(key: key, value: QueueIdentity(label: "dispatch.main"))
        return key
    }()
    
    static var isMain: Bool {
        return DispatchQueue.getSpecific(key: mainKey) != nil
    }
    
    func safeSync(_ block: @escaping () -> Void) {
        let _ = DispatchQueue.mainKey
        
        guard let spe = self.specific else {
            sync {
                block()
            }
            return
        }
        
        if let _ = DispatchQueue.getSpecific(key: spe) {
            block()
        } else {
            sync {
                block()
            }
        }
    }
    
    static func createQueue(with specific: String!, qos: DispatchQoS = .default) -> DispatchQueue {
        let queue = DispatchQueue(label: specific, qos: qos)
        let specific = DispatchSpecificKey<QueueIdentity>()
        queue.specific = specific
        queue.setSpecific(key: specific, value: QueueIdentity(label: queue.label))
        return queue
    }
}

