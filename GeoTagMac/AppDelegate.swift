//
//  AppDelegate.swift
//  GeoTagMac
//
//  Created by asc on 4/8/20.
//  Copyright © 2020 SFO Museum. All rights reserved.
//

import Cocoa
import WebKit
import OAuthSwift

enum ServerError: Error {
    case startupError
    case missingServerURI
    case missingNextzenAPIKey
    case missingPlaceholderEndpoint
    case missingOEmbedEndpoints
    case missingApplicationSupportDirectory
    case missingOAuth2ClientID
    case missingOAuth2ClientSecret
    case missingOAuth2Scopes
    case missingWriterURI
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // https://developer.apple.com/documentation/foundation/process
    // https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW1
    
    let server_task = Process()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupApp()
    }
    
    // note that in order for this work the default Info.plist will
    // need to be updated
    // https://developer.apple.com/documentation/bundleresources/information_property_list/nssupportssuddentermination
    
    func applicationWillTerminate(_ aNotification: Notification) {
        
        if server_task.isRunning {
            server_task.terminate()
        }
        
    }
    
    func setupApp() {
        startServerApp()
    }
    
    func startServerApp() {
        
        guard let server_uri = Bundle.main.object(forInfoDictionaryKey: "ServerURI") as? String else {
            NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingServerURI)
            return
        }
                
        let server_url = server_uri
        let url = URL (string: server_url)
        
        let use_local_server = Bundle.main.object(forInfoDictionaryKey: "UseLocalServer") as? String
        
        if use_local_server == nil || use_local_server != "YES" {
            NotificationCenter.default.post(name: Notification.Name("serverListening"), object: url!)
            return
        }
        
        var server_args = [String:String]()
        
        server_args["server-uri"] = server_uri        
        server_args["enable-wk-webview"] = "true"
        
        // this is necessary until I finesse how the crumb handler works
        // with writer/api.go (20200513/thisisaaronland)
        
        server_args["disable-writer-crumb"] = "true"
        
        guard let nextzen_apikey = Bundle.main.object(forInfoDictionaryKey: "NextzenAPIKey") as? String else {
            
            NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingNextzenAPIKey)
            return
        }
        
        server_args["nextzen-apikey"] = nextzen_apikey
        
        let enable_placeholder = Bundle.main.object(forInfoDictionaryKey: "EnablePlaceholder") as? String
        
        if enable_placeholder != nil && enable_placeholder == "YES" {
            
            guard let placeholder_endpoint = Bundle.main.object(forInfoDictionaryKey: "PlaceholderEndpoint") as? String else {
                
                NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingPlaceholderEndpoint)
                return
            }
            
            server_args["enable-placeholder"] = "true"
            server_args["placeholder-endpoint"] = placeholder_endpoint
        }
        
        let enable_oembed = Bundle.main.object(forInfoDictionaryKey: "EnableOEmbed") as? String
        
        if enable_oembed != nil && enable_oembed == "YES" {
            
            guard let oembed_endpoints = Bundle.main.object(forInfoDictionaryKey: "OEmbedEndpoints") as? String else {
                
                NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingOEmbedEndpoints)
                return
            }
            
            server_args["enable-oembed"] = "true"
            server_args["oembed-endpoints"] = oembed_endpoints
        }
        
        let enable_proxy_tiles = Bundle.main.object(forInfoDictionaryKey: "EnableProxyTiles") as? String
        
        if enable_proxy_tiles != nil && enable_proxy_tiles == "YES" {
            
            guard let application_support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                
                NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingApplicationSupportDirectory)
                return
            }
            
            let tile_cache = application_support.appendingPathComponent("tiles")
            let path_cache = tile_cache.path
            
            if !FileManager.default.fileExists(atPath: path_cache){
                
                do {
                    try FileManager.default.createDirectory(at: tile_cache, withIntermediateDirectories: true, attributes: nil)
                } catch let error {
                    NotificationCenter.default.post(name: Notification.Name("serverError"), object: error)
                    return
                }
            }
            
            let cache_uri = String(format: "fs://%@", path_cache)
            
            server_args["enable-proxy-tiles"] = "true"
            server_args["proxy-tiles-cache-uri"] = cache_uri
        }
        
        
        let writer_uri = Bundle.main.object(forInfoDictionaryKey: "WriterURI") as? String
        
        if writer_uri == nil {
            
            NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.missingWriterURI)
            return
        }
        
        server_args["enable-writer"] = "true"
        server_args["writer-uri"] = writer_uri
        
        let wof_writer_uri = Bundle.main.object(forInfoDictionaryKey: "WhosOnFirstWriterURI") as? String
        
        if wof_writer_uri != nil {
            server_args["whosonfirst-writer-uri"] = wof_writer_uri
        }
        
        let wof_reader_uri = Bundle.main.object(forInfoDictionaryKey: "WhosOnFirstReaderURI") as? String
        
        if wof_reader_uri != nil {
            server_args["whosonfirst-reader-uri"] = wof_reader_uri
        }
        
        var environment =  ProcessInfo.processInfo.environment
        
        let task_args = [
            "&"
        ]
        
        for (k,v) in server_args {
            
            var env = k.replacingOccurrences(of: "-", with: "_")
            env = env.uppercased()
            env = String(format: "GEOTAG_%@", env)
            
            print(env, v)
            environment[env] = v
        }
        
        let server_app = Bundle.main.resourcePath! + "/server.bundle/server"
        
        server_task.executableURL = URL(fileURLWithPath: server_app)
        server_task.environment = environment
        
        server_task.arguments = task_args
        
        server_task.terminationHandler = { (process) in
            
            // print("TERMINATION", process.terminationStatus, process.terminationReason)
            
            if process.terminationStatus == 0 {
                return
            }
            
            NotificationCenter.default.post(name: Notification.Name("serverError"), object: ServerError.startupError)
        }
        
        do {
            try server_task.run()
        } catch let error {
            NotificationCenter.default.post(name: Notification.Name("serverError"), object: error)
            return
        }
        
        // please poll until server_url responds with 200
        print("SLEEPING")
        sleep(2)
        
        NotificationCenter.default.post(name: Notification.Name("serverListening"), object: url!)
    }
    
    // https://medium.com/@floschliep/url-routing-on-macos-c53a06f0a984
    // https://stackoverflow.com/questions/1991072/how-to-handle-with-a-default-url-scheme
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager
            .shared()
            .setEventHandler(
                self,
                andSelector: #selector(handleURL(event:reply:)),
                forEventClass: AEEventClass(kInternetEventClass),
                andEventID: AEEventID(kAEGetURL)
        )
        
    }
    
    @objc func handleURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        if let path = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue?.removingPercentEncoding {
            
            guard let url = URL(string: path) else {
                // print("WHAT IS ", path)
                return
            }
                 
            switch url.host {
            case "oauth2":
                OAuthSwift.handle(url: url)
            case "oembed":
                
                let params = url.queryParameters
                let oembed_url = params?["url"] as String?
                
                if oembed_url != nil {
                    NotificationCenter.default.post(name: Notification.Name("oembedURL"), object: oembed_url!)
                }
                
            default:
                print("Unhandled protocol request", url)
            }
        }
    }
    
}

extension URL {
    public var queryParameters: [String: String]? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems else { return nil }
        return queryItems.reduce(into: [String: String]()) { (result, item) in
            result[item.name] = item.value
        }
    }
}
