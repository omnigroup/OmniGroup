// Copyright 2015-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation
import UniformTypeIdentifiers
import CoreServices

// Swift struct wrapper around the OFUTI functions.
// Not conforming to CustomStringConvertible before checking that this wouldn't allow naive conversion to a string

public struct UTI {
    public let fileType: UTType
    private let lowercaseRawFileType: String

    // This struct ends up getting used for legacy NSPasteboard types too on macOS. This should return false for those types.
    public let isUTI: Bool
    public let rawFileType: String

    // Common UTIs
    /// "file system directory (includes packages AND folders)"
    public static var Directory: UTI {
        if #available(macOS 11, *) {
            return UTI(withUTType: .directory)
        } else {
            return UTI(kUTTypeDirectory as String)
        }
    }
    
    /// "a user-browsable directory (i.e., not a package)"
    public static var Folder: UTI {
        if #available(macOS 11, *) {
            return UTI(withUTType: .folder)
        } else {
            return UTI(kUTTypeFolder as String)
        }
    }
    
    /// "base type for any sort of simple byte stream including files and in-memory data"
    public static var Data: UTI {
        if #available(macOS 11, *) {
            return UTI(withUTType: .data)
        } else {
            return UTI(kUTTypeData as String)
        }
    }

    public static var UTF8PlainText: UTI {
        if #available(macOS 11, *) {
            return UTI(withUTType: .utf8PlainText)
        } else {
            return UTI(kUTTypeUTF8PlainText as String)
        }
    }
    
    public static var PlainText: UTI {
        if #available(macOS 11, *) {
            return UTI(withUTType: .plainText)
        } else {
            return UTI(kUTTypePlainText as String)
        }
    }

    public static let Zip = UTI("com.pkware.zip-archive") // This is the base type for public.zip-archive, but the latter defines a 'zip' extension, while this is usable for zip-formatted files that don't use that extension.

    public static func fileType(forFileURL fileURL:URL, preferringNative:Bool = true) throws -> UTI {
        var error:NSError?
        if let rawFileType = OFUTIForFileURLPreferringNative(fileURL, &error) {
            return UTI(rawFileType)
        }
        if let error_ = error {
            throw error_
        } else {
            assertionFailure("Should fill out the error")
            throw NSError(domain: "UTI", code: 0) // some unknown error
        }
    }

    public static func fileType(forPathExtension pathExtension:String, isDirectory:Bool?, preferringNative:Bool = true) throws -> UTI {
        guard let isDirectory = isDirectory else {
            if #available(macOS 11, *) {
                return UTI.fileType(forTagClass:UTTagClass.filenameExtension, tagValue: pathExtension, conformingToUTI: nil, preferringNative:preferringNative)
            } else {
                return UTI.fileType(forTagClass:kUTTagClassFilenameExtension as String, tagValue: pathExtension, conformingToUTI: nil, preferringNative:preferringNative)
            }
        }

        if isDirectory && pathExtension == OFDirectoryPathExtension {
            return Folder
        }

        if #available(macOS 11, *) {
            let conformingType = isDirectory ? UTType.directory : UTType.data
            return UTI.fileType(forTagClass:UTTagClass.filenameExtension, tagValue: pathExtension, conformingToUTI: conformingType, preferringNative:preferringNative)

        } else {
            let conformingType = (isDirectory ? kUTTypeDirectory : kUTTypeData) as String
            return UTI.fileType(forTagClass:kUTTagClassFilenameExtension as String, tagValue: pathExtension, conformingToUTI: conformingType, preferringNative:preferringNative)
        }
    }

    // Our ObjC version asserts a non-nil return for the preferringNative case, so we use '!', but we might want to switch to an optional return or throws.
    @available(macOS, deprecated: 12)
    @available(iOS, deprecated: 15)
    public static func fileType(forTagClass tagClass: String, tagValue: String, conformingToUTI: String?, preferringNative: Bool = true) -> UTI {
        let rawFileType:String

        if preferringNative {
            rawFileType = OFUTIForTagPreferringNative(tagClass as CFString, tagValue, conformingToUTI as CFString?)
        } else {
            rawFileType = UTTypeCreatePreferredIdentifierForTag(tagClass as CFString, tagValue as CFString, conformingToUTI as CFString?)!.takeUnretainedValue() as String
        }
        return UTI(rawFileType)
    }
    
    @available(macOS 11, *) public static func fileType(forTagClass tagClass: UTTagClass, tagValue: String, conformingToUTI type: UTType?, preferringNative: Bool = true) -> UTI {
        let rawFileType:String
        
        if preferringNative {
            rawFileType = OFUTIForTagPreferringNative(tagClass.rawValue as CFString, tagValue, type?.identifier as CFString?)
            return UTI(rawFileType)

        } else {
            // this has the potential to crash, the right answer is probably to make this method failable, or throw, but for now this will at least surface bad inputs.
            return UTI(withUTType: UTType(tag: tagValue, tagClass: tagClass, conformingTo: type)!)
        }
    }

    @available(macOS 11, *) public init(withUTType: UTType) {
        self.fileType = withUTType
        self.isUTI = withUTType.isDynamic || withUTType.isDeclared
        self.rawFileType = withUTType.identifier
        self.lowercaseRawFileType = rawFileType.lowercased()
    }
    
    @available(macOS, deprecated: 12)
    @available(iOS, deprecated: 15)
    private init(withIdentifier fileType: String) {
        self.rawFileType = fileType
        self.lowercaseRawFileType = fileType.lowercased() // See our Equatable conformance
        self.isUTI = UTTypeIsDeclared(fileType as CFString) || UTTypeIsDynamic(fileType as CFString) // `dyn.*`. This should be false for things like "NeXT Rich Text Format v1.0 pasteboard type"
        self.fileType = UTType.plainText // not paid attention to, but need to initialize it.
    }
    
    public init(_ fileType: String) {
        if #available(macOS 11, *) {
            self.init(withUTType: UTType(fileType) ?? UTType.plainText)
        } else {
            self.init(withIdentifier: fileType)
        }
    }

    public static func fileTypePreferringNative(_ fileExtension: String) -> String? {
        if let uti = try? fileType(forPathExtension: fileExtension, isDirectory: nil, preferringNative: true) {
            return uti.rawFileType
        }

        return nil
    }

    @available(macOS, deprecated: 12)
    @available(iOS, deprecated: 15)
    public static func conforms(_ fileType: String?, to uti: String) -> Bool {
        guard let fileType = fileType else { return false }

        return UTTypeConformsTo(fileType as NSString, uti as NSString)
    }
    
    @available(macOS 11, *) public static func conforms(_ fileType: UTType?, to uti: UTType) -> Bool { // or just use the api directly?
        guard let fileType = fileType else { return false }
        return fileType.conforms(to: uti)
    }

    @available(macOS, deprecated: 12)
    @available(iOS, deprecated: 15)
    public static func conforms(_ fileType: String?, toAnyOf types: [String]) -> Bool {
        guard let fileType = fileType else { return false }

        if types.contains(fileType) {
            return true // Avoid eventually calling UTTypeConformsTo when possible.
        }
        for uti in types {
            if conforms(fileType, to: uti) {
                return true
            }
        }
        return false
    }
    // NOTE: We could define the typical '~=' pattern comparison operator, but have chosen not to, since the two types passed in are the same. This would make it too easy to swap the order of the arguments to the operator and not be checking the desire condition.

    @available(macOS 11, *) public static func conforms(_ fileType: UTType?, toAnyOf types: [UTType]) -> Bool {
        guard let fileType = fileType else { return false }
        
        if types.contains(fileType) {
            return true // Avoid eventually calling UTTypeConformsTo when possible.
        }
        for uti in types {
            if conforms(fileType, to: uti) {
                return true
            }
        }
        return false
    }

    /// Checks if the receiver conforms to, or is equal to, the passed in type.
    public func conformsTo(_ otherUTI:UTI) -> Bool {
        if #available(macOS 11, *) {
            return self.fileType.conforms(to: otherUTI.fileType)
        } else {
            return UTTypeConformsTo(self.rawFileType as CFString, otherUTI.rawFileType as CFString)
        }
    }

    public func conformsToAny<T>(_ otherUTIs:T) -> Bool where T : Sequence, T.Element == UTI {
        for e in otherUTIs {
            if self.conformsTo(e) {
                return true
            }
        }
        return false
    }
    
    public var preferredPathExtension: String? {
        if #available(macOS 11, *) {
            return fileType.preferredFilenameExtension
        } else {
            guard let unmanaged = UTTypeCopyPreferredTagWithClass(self.rawFileType as CFString, kUTTagClassFilenameExtension) else {
                return nil
            }
            return String(unmanaged.takeRetainedValue())
        }
    }
}

extension UTI: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "<UTI: \(rawFileType)>"
    }
}

extension UTI: ExpressibleByStringLiteral {
    public init(stringLiteral value:String) {
        self.init(value)
    }
    public init(extendedGraphemeClusterLiteral value:ExtendedGraphemeClusterType) {
        self.init(value)
    }
    public init(unicodeScalarLiteral value:UnicodeScalar) {
        self.init("\(value)")
    }
}

extension UTI: Equatable, Hashable {
    public static func ==(type1: UTI, type2: UTI) -> Bool {
        if #available(macOS 11, *) {
            return type1.fileType == type2.fileType
        } else {
            if type1.isUTI != type2.isUTI {
                return false
            }
            if type1.isUTI {
                return UTTypeEqual(type1.rawFileType as CFString, type2.rawFileType as CFString)
            } else {
                return type1.rawFileType == type2.rawFileType
            }
        }
    }
    public func hash(into hasher: inout Hasher) {
        // UTTypeEqual which is used in `==` above, but only for actual UTI types, compares with case-insensitivity. Avoid breaking hashing invariants.
        if isUTI {
            hasher.combine(lowercaseRawFileType)
        } else {
            hasher.combine(rawFileType)
        }
    }
}
