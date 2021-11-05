// Copyright 2021 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


import Foundation
import SwiftUI

// Debugging helper that can be used in @ViewBuilders. The repeated interface with @inlinable attribute is a bit more wordy, but it should mean that in Debug builds we can turn logging on/off w/o rebuilding the world.

public enum OUIViewDebugging {
#if DEBUG
    public static var loggingEnabled: Bool {
        return false
    }
    public static var considerAllPropertiesInteresting: Bool {
        return true
    }
#else
    @inlinable
    public static var loggingEnabled: Bool {
        return false
    }
#endif
}

extension View {
#if DEBUG
    public func Print(_ vars: Any...) -> some View {
        for v in vars { print(v) }
        return EmptyView()
    }
#else
    @inlinable
    public func Print(_ vars: Any...) -> some View {
        EmptyView()
    }
#endif
}

#if DEBUG
public var _OUIViewDebuggingRandomGenerator = SystemRandomNumberGenerator()
#endif

public protocol OUIViewDebuggingDescription {
    var viewDebuggingDescription: String { get }
}

extension View {
#if DEBUG
    public func printValues(_ vars: Any...) -> some View {
        if OUIViewDebugging.loggingEnabled {
            for v in vars { Swift.print(v) }
        }
        let strings = vars.map { String(describing: $0) }
        return self
            .background(
                Text(verbatim: strings.joined(separator: ","))
                    .foregroundColor(.clear)
            )
    }
#else
    @inlinable
    public func printValues(_ vars: Any...) -> some View {
        self
    }
#endif


#if DEBUG
    public func randomColorBorder() -> some View {
        self
            .border(Color(hue: Double(_OUIViewDebuggingRandomGenerator.next() % 1000) / 1000, saturation: 0.5, brightness: 1.0))
    }
#else
    @inlinable
    public func randomColorBorder() -> some View {
        self
    }
#endif
}

#if DEBUG
public func OUIViewDebugLog(_ message: @autoclosure () -> String) {
    if OUIViewDebugging.loggingEnabled {
        print("🟪 " + message())
    }
}
#else
@inlinable
public func OUIViewDebugLog(_ message: @autoclosure () -> String) {
}
#endif

extension View {
#if DEBUG_bungi
    public static var changedProperties: [String] {
        if #available(iOS 15, *), OUIViewDebugging.loggingEnabled {
            return ["???"]
            //return _changedProperties
        }
        return ["unknown"]
    }
#else
    @inlinable
    public static var changedProperties: [String] {
        return ["unknown"]
    }
#endif

#if DEBUG
    public static var interestingPropertyChanges: [String]? {
        if #available(iOS 15, *), OUIViewDebugging.loggingEnabled {
            let properties = changedProperties
            if !OUIViewDebugging.considerAllPropertiesInteresting && (properties.isEmpty || properties.contains("@self")) {
                return nil // filter out non-useful change lists
            }
            return properties
        }
        return nil
    }
#else
    @inlinable
    public static var interestingPropertyChanges: [String]? {
        return nil
    }
#endif

#if DEBUG
    public static func printChanges(_ item: Self, _ description: @autoclosure () -> String = "") {
#if true
        if #available(iOS 15, *) {
            let itemDescription: String
            if let item = item as? OUIViewDebuggingDescription {
                itemDescription = "\(type(of: self)) \(item.viewDebuggingDescription)"
            } else {
                itemDescription = "\(type(of: self))"
            }
            print("🟪 \(itemDescription) \(description()) ", terminator: "")
            Self._printChanges()
        }
#else
        if let properties = interestingPropertyChanges {
            let itemDescription: String
            if let item = item as? OUIViewDebuggingDescription {
                itemDescription = "\(type(of: self)) \(item.viewDebuggingDescription)"
            } else {
                itemDescription = "\(type(of: self))"
            }
            print("🟪 \(itemDescription) \(description()) \(properties)")
        }
#endif
    }
#else
    @inlinable
    public static func printChanges(_ item: Self, _ description: @autoclosure () -> String = "") {
    }
#endif
}

extension ViewModifier {

#if DEBUG_bungi
    public static var changedProperties: [String] {
        if #available(iOS 15, *), OUIViewDebugging.loggingEnabled {
            return ["???"]
            //return _changedProperties
        }
        return ["unknown"]
    }
#else
    @inlinable
    public static var changedProperties: [String] {
        return ["unknown"]
    }
#endif

#if DEBUG
    public static var interestingPropertyChanges: [String]? {
        if #available(iOS 15, *), OUIViewDebugging.loggingEnabled {
            let properties = changedProperties
            if !OUIViewDebugging.considerAllPropertiesInteresting && (properties.isEmpty || properties.contains("@self")) {
                return nil // filter out non-useful change lists
            }
            return properties
        }
        return nil
    }
#else
    @inlinable
    public static var interestingPropertyChanges: [String]? {
        return nil
    }
#endif

#if DEBUG
    public static func printChanges(_ item: Self, _ description: @autoclosure () -> String = "") {
#if true
        if #available(iOS 15, *) {
            let itemDescription: String
            if let item = item as? OUIViewDebuggingDescription {
                itemDescription = "\(type(of: self)) \(item.viewDebuggingDescription)"
            } else {
                itemDescription = "\(type(of: self))"
            }
            print("🟪 \(itemDescription) \(description()) ", terminator: "")
            Self._printChanges()
        }
#else
        if let properties = interestingPropertyChanges {
            let itemDescription: String
            if let item = item as? OUIViewDebuggingDescription {
                itemDescription = "\(type(of: self)) \(item.viewDebuggingDescription)"
            } else {
                itemDescription = "\(type(of: self))"
            }
            print("🟪 \(itemDescription) \(description()) \(properties)")
        }
#endif
    }
#else
    @inlinable
    public static func printChanges(_ item: Self, _ description: @autoclosure () -> String = "") {
    }
#endif
}

public protocol OUIView : View {
    associatedtype _OUIBody : View

    @ViewBuilder var oui_body : _OUIBody { get }
}

extension OUIView where Body == _OUIBody {
#if DEBUG
    public var body: Body {
        Self.printChanges(self)
        return oui_body
    }
#else
    @inlinable
    public var body: Body {
        oui_body
    }
#endif
}

public protocol OUIViewModifier : ViewModifier {
    associatedtype _OUIBody : View

    @ViewBuilder func oui_body(content: Content) -> _OUIBody
}

extension OUIViewModifier where Body == _OUIBody {
    public func body(content: Content) -> Body {
        Self.printChanges(self)
        return oui_body(content: content)
    }
}
