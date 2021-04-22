// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import OmniUI
import SwiftUI

extension OUIDocumentAppController {
    override open func registerNewsProviders() {
        super.registerNewsProviders()
        registerDocumentBrowserWelcomeNewsProvider()
    }

    fileprivate func registerDocumentBrowserWelcomeNewsProvider() {
        let provider = DocumentBrowserWelcomeNewsProvider()
        provider.priority = 200
        provider.delayFromLastNews = 300.0 // five minutes
        OUINewsManager.shared.register(provider)
    }

    fileprivate class DocumentBrowserWelcomeNewsProvider: OUINewsProvider {
        override init() {
            super.init()
            showNewsInWindow = { (window: UIWindow) -> Bool in
                guard Self.hasOpenedDocumentsInOldBrowser else { return false }
                let latestVersion = Self.latestVersion
                guard Self.lastSeenVersion < latestVersion else { return false }
                Self.lastSeenVersion = latestVersion

                var pages = [OUIDocumentBrowserWelcome.WelcomePage]()

                let page1 = OUIDocumentBrowserWelcome.WelcomePage()
                page1.wantsSplash = true
                page1.localizedTitleText = NSLocalizedString("New in iOS 13:\nFull Adoption of Apple's Document Browser", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: title")
                page1.localizedDescriptionText = NSLocalizedString("We've retired our custom document browser in favor of using Apple's built-in browser, making it easier than ever for you to choose where you want to keep your documents.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: description")
                page1.learnMoreBlock = {
                    let url = URL(string: "https://www.omnigroup.com/forward/ios-13-file-browser")!
                    UIApplication.shared.open(url)
                }
                pages.append(page1)

                let hasOmniPresenceAccount = Self.hasOmniPresenceAccount
                if hasOmniPresenceAccount {
                    let page2 = OUIDocumentBrowserWelcome.WelcomePage()
                    page2.wantsIllustration = true
                    page2.localizedTitleText = NSLocalizedString("OmniPresence Documents", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: title")
                    page2.localizedDescriptionText = NSLocalizedString("Your OmniPresence documents will only be visible in the new browser when they’ve been downloaded to this device.\n\nOmniPresence does not download larger synced files automatically. You can manually download larger files to this device now, or access the download manager later from the OmniPresence icon in the toolbar.", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: description")
                    page2.learnMoreBlock = {
                        let url = URL(string: "https://www.omnigroup.com/forward/ios-13-omnipresence")!
                        UIApplication.shared.open(url)
                    }
                    pages.append(page2)
                }

                OUIDocumentBrowserWelcome.bundle = OmniUIDocumentBundle
                let environment = OUIDocumentBrowserWelcome.WelcomeEnvironment(appName: OUIAppController.applicationName(), pages: pages)
                environment.localizedLearnMoreText = NSLocalizedString("Learn More", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: button title")
                environment.localizedContinueText = NSLocalizedString("Continue", tableName: "OmniUIDocument", bundle: OmniUIDocumentBundle, comment: "Update news: button title")
                environment.closeBlock = {
                    self.close {
                        if hasOmniPresenceAccount {
                            guard let sceneDelegate = window.sceneDelegate else { return }
                            sceneDelegate.showSyncAccounts()
                        }
                    }
                }
                let welcomeView = OUIDocumentBrowserWelcome().environmentObject(environment)
                let welcomeController = UIHostingController(rootView: welcomeView)
                welcomeController.isModalInPresentation = true
                self.viewController = welcomeController
                window.rootViewController!.present(welcomeController, animated: true, completion: nil)

                if let sceneDelegate = window.sceneDelegate {
                    sceneDelegate.openLocalDocumentsFolder()
                }

                return true
            }
        }

        var viewController: UIViewController?

        func close(completion: (() -> Void)? = nil) {
            guard let viewController = self.viewController else {
                Self.handleCompletion(completion)
                return
            }

            viewController.dismiss(animated: true) { [weak self] in
                self?.viewController = nil
                Self.handleCompletion(completion)
            }
        }

        static func handleCompletion(_ completion: (() -> Void)?) {
            if let completion = completion {
                completion()
            }
        }

        static var hasOpenedDocumentsInOldBrowser: Bool {
            let preference = OFPreference(forKey: "OUIRecentlyOpenedDocuments", defaultValue: [])
            return preference.arrayValue?.count != 0
        }
        static let versionPreference = OFPreference(forKey: "OUIDocumentBrowserWelcomeVersion", defaultValue: 0)
        static var lastSeenVersion: Int {
            get {
                return versionPreference.integerValue
            }
            set {
                versionPreference.integerValue = newValue
            }
        }

        static let latestVersion = 1

        static var hasOmniPresenceAccount: Bool {
            guard let agent = OUIDocumentAppController.shared().agentActivity?.agent else { return false }
            let accounts = agent.accountRegistry.allAccounts
            return accounts.count != 0
        }
    }
}
