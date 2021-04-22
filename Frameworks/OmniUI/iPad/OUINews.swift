// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

@objc public final class OUINewsManager: NSObject {
    @objc public static var shared = OUINewsManager()

    var providers: [OUINewsProvider] = []

    @objc public func register(_ provider: OUINewsProvider) {
        providers.append(provider)
    }

    @objc public func showNews(in window: UIWindow, for context: String? = nil) -> Bool {
        let nowTime = NSDate.timeIntervalSinceReferenceDate
        guard showNews(in: window, for: context, delayFromLastNews: nowTime - lastNewsTime) else { return false }
        lastNewsTime = nowTime
        return true
    }

    fileprivate func showNews(in window: UIWindow, for context: String? = nil, delayFromLastNews: TimeInterval = 0.0) -> Bool {
        let sortedProviders = providers.sorted { (a, b) -> Bool in
            if a.priority != b.priority {
                return a.priority > b.priority
            } else {
                return a.index < b.index
            }
        }

        for provider in sortedProviders {
            guard provider.isAppropriateForContext(context) else { continue }
            guard delayFromLastNews >= provider.delayFromLastNews else { continue }
            if provider.showNewsInWindow(window) {
                return true
            }
        }

        return false
    }

    fileprivate var lastNewsTimePreference = OFPreference(forKey: "OUINewsItemLastNewsTime", defaultValue: 0.0)
    fileprivate var lastNewsTime: TimeInterval {
        get {
            return lastNewsTimePreference.doubleValue
        }
        set {
            lastNewsTimePreference.doubleValue = newValue
        }
    }
}

@objc open class OUINewsProvider: NSObject {
    @objc open var priority = 0
    @objc open var delayFromLastNews: TimeInterval = 0.0
    @objc open var isAppropriateForContext = { (context: String?) -> Bool in
        return true
    }
    @objc open var showNewsInWindow = { (window: UIWindow) -> Bool in
        return false
    }

    fileprivate var index = OUINewsProvider.nextIndex
    fileprivate static var _nextIndex = 0
    fileprivate static var nextIndex: Int {
        _nextIndex += 1
        return _nextIndex
    }
}

@available(iOSApplicationExtension, unavailable)
extension OUIAppController {
    @discardableResult @objc(showNewsInWindow:) public func showNews(in window: UIWindow) -> Bool {
        registerNewsProvidersIfNeeded()
        return OUINewsManager.shared.showNews(in: window)
    }

    @objc open func registerNewsProviders() {
        Self.registerSoftwareUpdateProvider()
        Self.registerMessageOfTheDayProvider()
    }

    @objc public func skipMessageOfTheDay() {
        OUIMessageOfTheDayNewsProvider.skipMessageOfTheDay()
    }

    fileprivate static var needToRegisterDefaultProviders = true
    fileprivate func registerNewsProvidersIfNeeded() {
        if Self.needToRegisterDefaultProviders {
            Self.needToRegisterDefaultProviders = false
            registerNewsProviders()
        }
    }

    fileprivate static func registerSoftwareUpdateProvider() {
        let provider = OUINewsProvider()
        provider.priority = 100
        provider.delayFromLastNews = 3600.0 // one hour
        provider.showNewsInWindow = { (window) -> Bool in
            guard let newsURLString = OUIAppController.sharedController().mostRecentNewsURLString else { return false }
            let sceneHelper = OUIAppControllerSceneHelper()
            sceneHelper.window = window
            return sceneHelper.showNewsURLString(newsURLString, evenIfShownAlready: false) != nil
        }
        OUINewsManager.shared.register(provider)
    }

    fileprivate static func registerMessageOfTheDayProvider() {
        let provider = OUIMessageOfTheDayNewsProvider()
        provider.delayFromLastNews = 0.0 // no delay
        OUINewsManager.shared.register(provider)
    }

    fileprivate class OUIMessageOfTheDayNewsProvider: OUINewsProvider {
        static func skipMessageOfTheDay() {
            lastSeenSignature = latestSignature
        }

        override init() {
            super.init()
            showNewsInWindow = { (window: UIWindow) -> Bool in
                let latestSignature = OUIMessageOfTheDayNewsProvider.latestSignature
                guard OUIMessageOfTheDayNewsProvider.lastSeenSignature != latestSignature else { return false }
                let sceneHelper = OUIAppControllerSceneHelper()
                sceneHelper.window = window
                sceneHelper.showReleaseNotes(nil)
                OUIMessageOfTheDayNewsProvider.lastSeenSignature = latestSignature
                return true
            }
        }

        static let signaturePreference = OFPreference(forKey: "OUIMessageOfTheDaySignature", defaultValue: "")
        static var lastSeenSignature: String? {
            get {
                return signaturePreference.stringValue
            }
            set {
                signaturePreference.stringValue = newValue
            }
        }

        static let latestSignature = calculateLatestSignature()
        static let url = Bundle.main.url(forResource: "MessageOfTheDay", withExtension: "html")
        static fileprivate func calculateLatestSignature() -> String? {
            guard let url = self.url else { return nil }
            guard let motdData = NSData(contentsOf: url) else { return nil }
            let latestSignature = OFDataCreateSHA1Digest(kCFAllocatorDefault, motdData)! as Data
            return latestSignature.base64EncodedString()
        }
    }
}

