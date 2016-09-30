// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

#if os(iOS)
    import MobileCoreServices
#endif
#if os(OSX)
    import CoreServices
#endif

// Swift struct wrapper around the OFUTI functions.
// Not conforming to CustomStringConvertible before checking that this wouldn't allow naive conversion to a string

public struct UTI {
    public let rawFileType:String

    // Common UTIs
    public static let Directory = UTI(kUTTypeDirectory as String) // "file system directory (includes packages AND folders)"

    public static let Folder = UTI(kUTTypeFolder as String) // "a user-browsable directory (i.e., not a package)"
    public static let Data = UTI(kUTTypeData as String) // "base type for any sort of simple byte stream including files and in-memory data"

    public static let Zip = UTI("com.pkware.zip-archive") // This is the base type for public.zip-archive, but the latter defines a 'zip' extension, while this is usable for zip-formatted files that don't use that extension.

    public static func fileType(forFileURL fileURL:URL, preferringNative:Bool = true) throws -> UTI {
        var error:NSError?
        if let rawFileType = OFUTIForFileURLPreferringNative(fileURL, &error) {
            return UTI(rawFileType)
        }
        throw error!
    }

    public static func fileType(forPathExtension pathExtension:String, isDirectory:Bool?, preferringNative:Bool = true) throws -> UTI {

        guard let isDirectory = isDirectory else {
            return UTI.fileType(forTagClass:kUTTagClassFilenameExtension as String, tagValue: pathExtension, conformingToUTI: nil, preferringNative:preferringNative)
        }

        if isDirectory && pathExtension == OFDirectoryPathExtension {
            return Folder
        }

        let conformingType = (isDirectory ? kUTTypeDirectory : kUTTypeData) as String
        return UTI.fileType(forTagClass:kUTTagClassFilenameExtension as String, tagValue: pathExtension, conformingToUTI: conformingType, preferringNative:preferringNative)
    }

    // Our ObjC version asserts a non-nil return for the preferringNative case, so we use '!', but we might want to switch to an optional return or throws.
    public static func fileType(forTagClass tagClass:String, tagValue:String, conformingToUTI:String?, preferringNative:Bool = true) -> UTI {
        let rawFileType:String

        if preferringNative {
            rawFileType = OFUTIForTagPreferringNative(tagClass as CFString, tagValue, conformingToUTI as CFString?)
        } else {
            rawFileType = UTTypeCreatePreferredIdentifierForTag(tagClass as CFString, tagValue as CFString, conformingToUTI as CFString?)!.takeUnretainedValue() as String
        }
        return UTI(rawFileType)
    }

    public init(_ fileType:String) {
        self.rawFileType = fileType
    }

    // NOTE: We could define the typical '~=' pattern comparison operator, but have chosen not to, since the two types passed in are the same. This would make it too easy to swap the order of the arguments to the operator and not be checking the desire condition.


    /// Checks if the receiver conforms to, or is equal to, the passed in type.
    public func conformsTo(_ otherUTI:UTI) -> Bool {
        return UTTypeConformsTo(self.rawFileType as CFString, otherUTI.rawFileType as CFString)
    }

    public func conformsToAny<T>(_ otherUTIs:T) -> Bool where T : Sequence, T.Iterator.Element == UTI {
        for e in otherUTIs {
            if self.conformsTo(e) {
                return true
            }
        }
        return false
    }
    
    public var preferredPathExtension: String? {
        guard let unmanaged = UTTypeCopyPreferredTagWithClass(self.rawFileType as CFString, kUTTagClassFilenameExtension) else {
            return nil
        }
        return String(unmanaged.takeRetainedValue())
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

extension UTI: Equatable {
    public static func ==(type1:UTI, type2:UTI) -> Bool {
        return UTTypeEqual(type1.rawFileType as CFString, type2.rawFileType as CFString)
    }
}
