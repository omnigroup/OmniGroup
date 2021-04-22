// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import OmniFoundation

// Support for looking at the defined types in the main bundle
@objc(OADocumentFileTypes) public class DocumentFileTypes : NSObject {

    public enum Role : String {
        case viewer = "Viewer"
        case editor = "Editor"
        case none =  "None"
    }

    private let fileTypeToRole: [UTI:Role]
    public let editableFileTypes: Set<UTI>

    @objc public static var main: DocumentFileTypes = DocumentFileTypes(bundle: Bundle.main)

    public init(bundle: Bundle) {
        var editableFileTypes = Set<UTI>()
        var fileTypeToRole = [UTI:Role]()

        guard let documentTypes = bundle.infoDictionary?["CFBundleDocumentTypes"] as? [[String:Any]] else {
            assert(OFIsRunningUnitTests(), "CFBundleDocumentTypes missing or has unexpected type")
            self.fileTypeToRole = [:]
            self.editableFileTypes = []
            return
        }
        documentTypes.forEach { typeDescription in
            let role: Role

            if let roleString = typeDescription["CFBundleTypeRole"] as? String {
                if let role_ = Role(rawValue: roleString) {
                    role = role_
                } else {
                    assertionFailure("Unknown rolw \(roleString) for document type \(typeDescription)")
                    role = .none
                }
            } else {
                assertionFailure("CFBundleTypeRole missing or wrong type for document type \(typeDescription)")
                role = .none
            }

            // Uppercase is allowed in type identifiers, but UTTypeEqual is compared to use case-insenstive comparison.
            let contentTypes: [UTI]
            if let contentTypeStrings = typeDescription["LSItemContentTypes"] as? [String] {
                contentTypes = contentTypeStrings.map { UTI($0.lowercased()) }
            } else {
                assertionFailure("LSItemContentTypes missing or wrong type for document type \(typeDescription)")
                contentTypes = []
            }

            switch role {
            case .editor:
                editableFileTypes.formUnion(contentTypes)
            case .none:
                return
            default:
                break
            }

            for contentType in contentTypes {
                assert(fileTypeToRole[contentType] == nil)
                fileTypeToRole[contentType] = role
            }
        }

        self.fileTypeToRole = fileTypeToRole
        self.editableFileTypes = editableFileTypes
    }

    // For application with dynamic file types.
    public init(readableTypes: Set<UTI>, writableTypes: Set<UTI>, editableTypes: Set<UTI>) {
        // Can have non-native types that can be imported and exported, but aren't considered native (in editableTypes). But editable types must be readable and writable.
        assert(editableTypes.isSubset(of: readableTypes))
        assert(editableTypes.isSubset(of: writableTypes))

        var fileTypeToRole = [UTI:Role]()

        let allTypes = readableTypes.union(writableTypes).union(editableTypes)
        for type in allTypes {
            if editableTypes.contains(type) {
                fileTypeToRole[type] = .editor
            } else if writableTypes.contains(type) {
                fileTypeToRole[type] = Role.none // Export only
            } else {
                fileTypeToRole[type] = .viewer
            }
        }

        self.fileTypeToRole = fileTypeToRole
        self.editableFileTypes = editableTypes
    }

    public var readableTypes: [UTI] {
        return fileTypeToRole.compactMap { type, role in
            switch role {
            case .none:
                return nil
            default:
                return type
            }
        }
    }

    // TODO: This is wrong (and not necessarily useful). Some 'none' types may be export-only. Really, an individual document should be consulted for its writable types.

    public var writableTypes: [UTI] {
        return fileTypeToRole.compactMap { type, role in
            switch role {
            case .editor:
                return type
            default:
                return nil
            }
        }
    }

    // ObjC helpers

    @objc public var readableTypeIdentifiers: [String] {
        return readableTypes.map { $0.rawFileType }
    }
    @objc public var writableTypeIdentifiers: [String] {
        return writableTypes.map { $0.rawFileType }
    }
}
