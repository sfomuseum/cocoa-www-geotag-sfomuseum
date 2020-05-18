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

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    
  let app = NSApplication.shared.delegate as! AppDelegate
    
    @IBOutlet var webView: WKWebView!
    
    var oauth2: OAuthSwift?
    
    let oauth2_callback_url = "geotag://oauth2"
    var oauth2_access_token: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.frame.size.width = 800
        self.view.frame.size.height = 1000
        
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
        
        print("LOAD APPLICATION")
        
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
    
    func webView(_ webView: WKWebView,
      didFinish navigation: WKNavigation!) {
      print("FINISHED LOADING WEBPAGE")

        self.getAccessToken()
    }
    
    func getAccessToken(){
        
        print("GET ACCESS TOKEN")
        // check for locally stored token
        // ensure token validity
        
        self.getNewAccessToken()
    }
    
    func getNewAccessToken(){
        
        let oauth2_auth_url = Bundle.main.object(forInfoDictionaryKey: "OAuth2AuthURL") as? String
        
        let oauth2_token_url = Bundle.main.object(forInfoDictionaryKey: "OAuth2TokenURL") as? String
        
        let oauth2_client_id = Bundle.main.object(forInfoDictionaryKey: "OAuth2ClientID") as? String
        
        let oauth2_client_secret = Bundle.main.object(forInfoDictionaryKey: "OAuth2ClientSecret") as? String
        
        let oauth2_scope = Bundle.main.object(forInfoDictionaryKey: "OAuth2Scope") as? String
        
        if oauth2_auth_url == nil || oauth2_auth_url == "" {
            showAlert(message: "OAuth2AuthURL")
            return
        }
        
        if oauth2_token_url == nil || oauth2_token_url == "" {
            showAlert(message: "OAuth2TokenURL")
            return
        }
        
        if oauth2_client_id == nil || oauth2_client_id == "" {
            showAlert(message: "OAuth2ClientID")
            return
        }
        
        if oauth2_client_secret == nil || oauth2_client_secret == "" {
            showAlert(message: "OAuth2ClientSecret")
            return
        }
        
        if oauth2_scope == nil || oauth2_scope == "" {
            showAlert(message: "OAuth2AuthURL")
            return
        }
        
        let oauth2_state = UUID().uuidString
        
        let oauth2 = OAuth2Swift(
            consumerKey:    oauth2_client_id!,
            consumerSecret: oauth2_client_secret!,
            authorizeUrl:   oauth2_auth_url!,
            accessTokenUrl: oauth2_token_url!,
            responseType:   "token"
        )
        
        self.oauth2 = oauth2
        
        oauth2.authorize(
            withCallbackURL: self.oauth2_callback_url,
            scope: oauth2_scope!,
            state:oauth2_state) { result in
                                
                switch result {
                case .success(let (credential, _, _)):
                    print("GOT ACCESS TOKEN")
                    self.oauth2_access_token = credential.oauthToken
                    self.executeJS(target: "sfomuseum.webkit.setAccessToken", body: credential.oauthToken)

                case .failure(let error):
                    self.showAlert(message:error.localizedDescription)
                    return
                }
        }
        
    }
    
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
        
        print("FEATURES", features)
    }
    
    func showAlert(message: String){
        
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
                print("JS failure: \(target), \(error)")
            }
        }
        
        let js_func = String(format: "%@('%@')",target, body)
        self.webView.evaluateJavaScript(js_func, completionHandler: jsCompletionHandler)
    }
}

