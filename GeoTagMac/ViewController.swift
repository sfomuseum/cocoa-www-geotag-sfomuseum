//
//  ViewController.swift
//  GeoTagMac
//
//  Created by asc on 4/8/20.
//  Copyright © 2020 SFO Museum. All rights reserved.
//

import Cocoa
import WebKit
import MapKit

import OAuthSwift
import OAuth2Wrapper

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    
  let app = NSApplication.shared.delegate as! AppDelegate
    
    @IBOutlet var webView: WKWebView!
    
    var oauth2: OAuthSwift?
    var oauth2_wrapper: OAuth2Wrapper?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let result = NewOAuth2WrapperConfigFromBundle(bundle: Bundle.main, prefix: "GitHub")
        
        if case .failure(let error) = result {
            print("SAD", error)
            return
        }
        
        guard case .success(var config) = result else {
            print("MISSING CONFIG")
            return
        }

        config.ResponseType = "code"
        
        let wrapper = OAuth2Wrapper(config: config)
        wrapper.logger.logLevel = .debug
        self.oauth2_wrapper = wrapper
        
        self.view.frame.size.width = 1024
        self.view.frame.size.height = 800
        
        let wk_conf = WKWebViewConfiguration()

        wk_conf.processPool = WKProcessPool()
        wk_conf.websiteDataStore = WKWebsiteDataStore.nonPersistent() // .default()
                
        let wk_controller = WKUserContentController()
        
        // https://stackoverflow.com/questions/50229935/wkwebview-get-javascript-errors
        
        wk_controller.add(
            self,
            name: "publishData"
        )
        
        wk_conf.userContentController = wk_controller
                
        let wvFrame = CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: self.view.frame.size.height);
        
        webView = WKWebView(frame: wvFrame, configuration: wk_conf)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        view = webView
    }
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String

        if (name != nil) {
            self.view.window?.title = name!
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue:"serverListening"),
                                               object: nil,
                                               queue: .main) { (notification) in
                                                
            let server_url = notification.object as! URL
            self.loadApplication(url:server_url)
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue:"serverError"),
                                               object: nil,
                                               queue: .main) { (notification) in
                                                
            let server_error = notification.object as! Error
                                                self.showAlert(message: server_error.localizedDescription)
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue:"oembedURL"),
                                               object: nil,
                                               queue: .main) { (notification) in
                                     
            let oembed_url = notification.object as! String
            self.executeJS(target: "sfomuseum.webkit.loadOEmbedURL", body: oembed_url)
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
   
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        // print("CONTENT", message.name)
        
        if  message.name == "publishData" {
            
            let body = message.body as! String
            self.publishData(body: body)
        }

    }
    
    func loadApplication(url:URL) {
        
        self.app.logger.debug("Load application.")
        
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            records.forEach { record in
                
                if record.displayName == "localhost" || record.displayName == "127.0.0.1" {
                WKWebsiteDataStore.default().removeData(ofTypes: record.dataTypes, for: [record], completionHandler: {})
                print("[WebCacheCleaner] Record \(record) deleted")
                }
            }
        }
        
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {

        self.app.logger.debug("Finished loading webpage.")
        
        func gotAccessToken(rsp: Result<OAuthSwiftCredential, Error>) {
            
            switch rsp {
            case .failure(let error):
                print("SAD", error)
                self.showAlert(message:error.localizedDescription)
            case .success(let credential):
                self.executeJS(target: "sfomuseum.webkit.setAccessToken", body: credential.oauthToken)
            }
        }
        
        self.oauth2_wrapper!.GetAccessToken(completion: gotAccessToken)
    }
    
    
    // This is left here as a reference - it is currently not being used
    // Also there doesn't appear to be any way to make `MKGeoJSONFeature` Encodable
    // because... computers? (20200519/thisisaaronland)
    
    func publishData(body: String) -> Void {
        
        let decoder = MKGeoJSONDecoder()
        var features: [MKGeoJSONFeature]
        
        do  {
            let object = try decoder.decode(body.data(using: .utf8)!)
            features = object as! [MKGeoJSONFeature]
        } catch (let error) {
            self.showAlert(message: error.localizedDescription)
            return
        }

        if features.count == 0 {
            self.showAlert(message: "Invalid GeoJSON, no features")
            return
        }
        
    }
    
    func showAlert(message: String){
        
        self.app.logger.info("\(message)")
        
        let alert = NSAlert()
        alert.messageText = "Error. There was a problem launching the application."
        alert.informativeText = message
        alert.addButton(withTitle: "Okay")
        alert.beginSheetModal(for: self.view.window!) { (returnCode: NSApplication.ModalResponse) -> Void in
            print ("returnCode: ", returnCode)
        }
    }
    
    func executeJS(target: String, body: String){
        
        let jsCompletionHandler: (Any?, Error?) -> Void = {
            (data, error) in
            
            if let error = error {
                self.app.logger.error("JS failure: \(target), \(error)")
            }
        }
        
        let js_func = String(format: "%@('%@')",target, body)
        self.webView.evaluateJavaScript(js_func, completionHandler: jsCompletionHandler)
    }
}

