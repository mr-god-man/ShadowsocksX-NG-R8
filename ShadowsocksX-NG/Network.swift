//
//  Network.swift
//  ShadowsocksX-NG
//
//  Created by ParadiseDuo on 2020/4/27.
//  Copyright © 2020 qiuyuzhou. All rights reserved.
//

import Cocoa
import Alamofire

class Network {
    private static let requestQueue = DispatchQueue(label: "Network")
    private static var sharedProxySession = Session(configuration: Network.getProxyConfiguration(), rootQueue: DispatchQueue.main, startRequestsImmediately: true, requestQueue: Network.requestQueue)
    private static let sharedSession = Session(configuration: Network.getConfiguration(), rootQueue: DispatchQueue.main, startRequestsImmediately: true, requestQueue: Network.requestQueue)
    
    static func refreshProxySession() {
        Network.sharedProxySession = Session(configuration: Network.getProxyConfiguration(), rootQueue: DispatchQueue.main, startRequestsImmediately: true, requestQueue: Network.requestQueue)
        print("&&& Network refreshProxySession &&&")
    }
    
    static func getProxyConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        if let a = UserDefaults.standard.string(forKey: USERDEFAULTS_LOCAL_SOCKS5_LISTEN_ADDRESS),
            let p = UserDefaults.standard.value(forKey: USERDEFAULTS_LOCAL_SOCKS5_LISTEN_PORT) as? NSNumber {
            let proxyConfiguration: [AnyHashable : Any] = [kCFNetworkProxiesSOCKSEnable : true,
                                                           kCFNetworkProxiesSOCKSProxy: a,
                                                           kCFNetworkProxiesSOCKSPort: p.intValue]
            configuration.connectionProxyDictionary = proxyConfiguration
        }
        return configuration
    }
    
    static func getConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        let proxyConfiguration: [AnyHashable : Any] = [kCFNetworkProxiesSOCKSEnable : false]
        configuration.connectionProxyDictionary = proxyConfiguration
        return configuration
    }
    
    static func session(useProxy: Bool) -> Session {
        if UserDefaults.standard.bool(forKey: USERDEFAULTS_SHADOWSOCKS_ON) {
            if useProxy {
                return sharedProxySession
            } else {
                return sharedSession
            }
        } else {
            return sharedSession
        }
    }
}

//webServer For SSR command
extension Network {
    private static var webServer: GCDWebServer? = nil
    static func startWebServer() {
        if let w = webServer, w.isRunning {
            return
        }
        webServer = GCDWebServer()
        webServer?.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { (request, completionBlock) in
            switch request.path {
            case Mode.PAC.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_PAC_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            case Mode.GLOBAL.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_GLOBAL_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            case Mode.ACLAUTO.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_ACL_AUTO_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            case Mode.WHITELIST.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_WHITELIST_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            case Mode.MANUAL.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_MANUAL_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            case Mode.CHINA.rawValue:
                NotificationCenter.default.post(name: NOTIFY_SWITCH_CHINA_MODE_SHORTCUT, object: nil)
                completionBlock(GCDWebServerResponse(statusCode: 200))
            default :
                handlePath(request.path) { response in
                    completionBlock(response)
                }
            }
        }
        do {
            let port = UserDefaults.standard.integer(forKey: USERDEFAULTS_WEBSERVERS_LISTEN_PORT)
            try webServer?.start(options: ["BindToLocalhost":NSNumber(value: true), "Port":NSNumber(value: port)])
            print("Visit \(webServer?.serverURL?.absoluteString ?? "") in your web browser")
        } catch let e {
            print("\(e.localizedDescription)")
        }
    }
    
    static func stopWebServer() {
        if let w = webServer, w.isRunning {
            w.stop()
        }
        webServer = nil
    }
    
    static func restart() {
        Network.stopWebServer()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+1) {
            Network.startWebServer()
        }
    }
    
    private static func handlePath(_ path: String, finish: @escaping (GCDWebServerResponse)->()) {
        if path == "/UpdateSubscribersWithProxy" {
            SubscribeManager.instance.updateAllServerFromSubscribe(auto: false, useProxy: true) {
                finish(GCDWebServerResponse(statusCode: 200))
            }
        } else if path == "/UpdateSubscribersWithoutProxy" {
            SubscribeManager.instance.updateAllServerFromSubscribe(auto: false, useProxy: false) {
                finish(GCDWebServerResponse(statusCode: 200))
            }
            finish(GCDWebServerResponse(statusCode: 200))
        } else if path == "/TestDelay" {
            ConnectTestigManager.shared.start {
                var speed = ""
                for (i, p) in ServerProfileManager.instance.profiles.enumerated() {
                    let latency = p.latency
                    let nf = NumberFormatter.three(latency)
                    speed += "\(i) : \(p.title())-\(nf)ms\n"
                }
                finish(GCDWebServerDataResponse(text: speed) ?? GCDWebServerResponse(statusCode: 500))
            }
        } else if path == "/Servers" {
            var speed = ""
            if neverSpeedTestBefore {
                for (i, p) in ServerProfileManager.instance.profiles.enumerated() {
                    speed += "\(i) : \(p.title())\n"
                }
                finish(GCDWebServerDataResponse(text: speed) ?? GCDWebServerResponse(statusCode: 500))
            } else {
                for (i, p) in ServerProfileManager.instance.profiles.enumerated() {
                    let latency = p.latency
                    let nf = NumberFormatter.three(latency)
                    speed += "\(i) : \(p.title())-\(nf)ms\n"
                }
                finish(GCDWebServerDataResponse(text: speed) ?? GCDWebServerResponse(statusCode: 500))
            }
        } else {
            let p = path.dropFirst()
            //切换服务器请求
            if let n = Int(p) {
                if 0 <= n && n < ServerProfileManager.instance.profiles.count {
                    NotificationCenter.default.post(name: NOTIFY_UPDATE_SERVER, object: nil, userInfo: ["index":NSNumber(value: n)])
                    finish(GCDWebServerResponse(statusCode: 200))
                } else {
                    finish(GCDWebServerResponse(statusCode: 404))
                }
            } else {
                finish(GCDWebServerResponse(statusCode: 404))
            }
        }
    }
}
