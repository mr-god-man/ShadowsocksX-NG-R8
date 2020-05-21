//
//  SubscribeManager.swift
//  ShadowsocksX-NG
//
//  Created by 秦宇航 on 2017/6/19.
//  Copyright © 2017年 qiuyuzhou. All rights reserved.
//

import Foundation

class SubscribeManager:NSObject{
    static let instance:SubscribeManager = SubscribeManager()
    
    var subscribes:[Subscribe]
    var subscribesDefault : [[String: AnyObject]]
    let defaults = UserDefaults.standard
    
    fileprivate override init() {
        subscribes = []
        subscribesDefault = [[:]]
        if let subscribesDefault = defaults.array(forKey: USERDEFAULTS_SUBSCRIBES) {
            for value in subscribesDefault{
                subscribes.append(Subscribe.fromDictionary(value as! [String : AnyObject]))
            }
        }
    }
    func addSubscribe(oneSubscribe: Subscribe) -> Bool {
        for (index, value) in subscribes.enumerated() {
            if Subscribe.isSame(source: oneSubscribe, target: value) {
                return true
            }
            if value.isExist(oneSubscribe) {
                subscribes.replaceSubrange((index..<index + 1), with: [oneSubscribe])
                return true
            }
        }
        subscribes.append(oneSubscribe)
        return true
    }
    func deleteSubscribe(atIndex: Int) -> Subscribe {
        return subscribes.remove(at: atIndex)
    }
    func save() {
        defaults.set(subscribesToDefaults(data: subscribes), forKey: USERDEFAULTS_SUBSCRIBES)
        defaults.synchronize()
    }
    fileprivate func subscribesToDefaults(data: [Subscribe]) -> [[String: AnyObject]]{
        var ret : [[String: AnyObject]] = []
        for value in data {
            ret.append(Subscribe.toDictionary(value))
        }
        return ret
    }
    fileprivate func DefaultsToSubscribes(data:[[String: AnyObject]]) -> [Subscribe] {
        var ret : [Subscribe] = []
        for value in data{
            ret.append(Subscribe.fromDictionary(value))
        }
        return ret
    }
    func updateAllServerFromSubscribe(auto: Bool, useProxy: Bool = true, finish:@escaping ()->()) {
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: DispatchQoS.QoSClass.userInteractive)
        for item in subscribes {
            if item.isActive {
                group.enter()
                queue.async(group: group) {
                    if !auto {
                        item.updateServerFromFeed(useProxy: useProxy) {
                            group.leave()
                        }
                    } else {
                        if item.getAutoUpdateEnable() {
                            item.updateServerFromFeed(useProxy: useProxy) {
                                group.leave()
                            }
                        } else {
                            group.leave()
                        }
                    }
                }
            }
        }
        //每次更新订阅后自动测试延时
        group.notify(queue: DispatchQueue.main) {
            //更新订阅后存一下组名
            self.save()
            if UserDefaults.standard.bool(forKey: USERDEFAULTS_SPEED_TEST_AFTER_SUBSCRIPTION) {
                ConnectTestigManager.shared.start {
                    finish()
                }
            } else {
                finish()
            }
        }
    }
}
