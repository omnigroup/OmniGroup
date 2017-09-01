// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

@objc(OFDiagnostics) public class Diagnostics: NSObject, OFBundleRegistryTarget {

    public enum Target {
        case controller
        case firstResponder
    }

    public struct Item {
        public let action: Selector
        public let target: Target
        public let title: String
    }

    public private(set) static var items = [Item]()

    public static func registerItemName(_ itemName: String, bundle: Bundle, description: Any) {

        guard itemName == "items" else {
            assertionFailure("Registration entry \(itemName) in \(bundle) is not recognized by \(self).")
            return
        }

        guard let itemArray: [Any] = description as? [Any] else {
            assertionFailure("Registration entry \(itemName) in \(bundle) is not an array.")
            return
        }

        for itemEntry in itemArray {
            guard let itemDictionary: [String: Any] = itemEntry as? [String: Any] else {
                assertionFailure("Registration entry \(itemName) in \(bundle) has non-dictionary item \(itemEntry)")
                continue
            }

            guard let actionString: String = itemDictionary["action"] as? String else {
                assertionFailure("Registration entry \(itemName) in \(bundle) has missing action, or it is not a string.")
                continue
            }
            
            guard let title: String = itemDictionary["title"] as? String else {
                assertionFailure("Registration entry \(itemName) in \(bundle) has missing title, or it is not a string.")
                continue
            }
            
            let target: Target
            if let targetEntry = itemDictionary["target"] {
                guard let targetString = targetEntry as? String else {
                    assertionFailure("Registration entry \(itemName) in \(bundle) has target entry that is not a string.")
                    continue
                }
                if targetString == "OFController" {
                    target = .controller
                } else {
                    assertionFailure("Registration entry \(itemName) in \(bundle) has target entry with unrecognized value \"\(targetString)\".")
                    continue
                }
            } else {
                target = .firstResponder
            }

            let item = Item(action: NSSelectorFromString(actionString), target: target, title: title)
            items.append(item)
        }
    }

    // Only the class is used.
    private override init () { }
}
