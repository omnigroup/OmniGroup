// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A class that wraps a UTI struct and caches some other values computable from the underlying UTI.
@objc(OFTypeIdentifier) open class TypeIdentifier : NSObject {

    public let typeIdentifier: UTI

    @objc public let pathExtensions: [String]
    @objc public let displayName: String

    public init(_ typeIdentifier: UTI) {
        self.typeIdentifier = typeIdentifier
        self.pathExtensions = OFUTIPathExtensions(typeIdentifier.rawFileType) ?? []
        self.displayName = OFUTIDescription(typeIdentifier.rawFileType) ?? typeIdentifier.rawFileType
    }

    @objc public convenience init(rawType: String) {
        self.init(UTI(rawType))
    }
    
    public override var hash: Int {
        return typeIdentifier.hashValue
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherType = object as? TypeIdentifier else { return false }
        return typeIdentifier == otherType.typeIdentifier
    }

    // Well known types

    @objc public static var plainText: TypeIdentifier {
        if #available(macOS 11, *) {
            return TypeIdentifier(UTI(withUTType: UTType.plainText))
        } else {
            return TypeIdentifier(UTI(kUTTypePlainText as String))
        }
    }

}
