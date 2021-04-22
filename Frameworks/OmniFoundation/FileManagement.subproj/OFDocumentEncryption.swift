// Copyright 2016-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation
import Dispatch

/// Encapsulates the encryption settings of a document
@objc public
class OFDocumentEncryptionSettings : NSObject {
    
    /// Decrypts an encrypted document file, if necessary.
    ///
    /// If the file is encrypted, it is unwrapped and a new file wrapper is returned, and information about the encryption settings is stored in `info`. Otherwise the original file wrapper is returned. If the file is encrypted but cannot be decrypted, an error is thrown, but `info` may still be filled in with whatever information is publicly visible on the encryption wrapper.
    ///
    /// - Parameter wrapper: The possibly-encrypted document.
    /// - Parameter info: (out) May be filled in with a new instance of `OFDocumentEncryptionSettings`.
    /// - Parameter keys: Will be used to resolve password/key queries.
    @objc(decryptFileWrapper:info:keys:error:)
    public class func unwrapIfEncrypted(_ wrapper: FileWrapper, info: AutoreleasingUnsafeMutablePointer<OFDocumentEncryptionSettings?>, keys: OFCMSKeySource?) throws -> FileWrapper {
        if (OFCMSFileWrapper.mightBeEncrypted(wrapper)) {
            let helper = OFCMSFileWrapper()
            helper.delegate = keys
            let unwrapped : FileWrapper
            do {
                unwrapped = try helper.unwrap(input: wrapper)
            } catch let e as NSError {
                if e.domain == OFErrorDomain && (e.code == OFError.OFKeyNotAvailable.rawValue || e.code == OFError.OFKeyNotApplicable.rawValue) {
                    info.pointee = OFDocumentEncryptionSettings(from: helper)
                }
                throw e
            }
            info.pointee = OFDocumentEncryptionSettings(from: helper)
            return unwrapped
        } else {
            info.pointee = nil
            return wrapper
        }
    }
    
    /** Tests whether a given filewrapper looks like an encrypted document.
     *
     * May return false positives for other CMS-formatted objects, such as PKCS#7 or PKCS#12 objects, iTunes store receipts, etc.
     */
    @objc(fileWrapperMayBeEncrypted:)
    public class func mayBeEncrypted(wrapper: FileWrapper) -> Bool {
        if (OFCMSFileWrapper.mightBeEncrypted(wrapper)) {
            return true
        } else {
            return false
        }
    }
    
    /** Encrypts a file wrapper using the receiver's settings. */
    @objc(encryptFileWrapper:schema:error:)
    public func wrap(_ wrapper: FileWrapper, schema: [String:Any]?) throws -> FileWrapper {
        let helper = OFCMSFileWrapper()
        helper.passwordHint = self.passwordHint
        
        // Make sure that anyone who can read the file has the recipients' certificates.
        var certificates = [Data]()
        var mustEmbed = false
        for recipient in recipients {
            if let pkrecipient = recipient as? CMSPKRecipient,
               let cert = pkrecipient.cert {
                if !certificates.isEmpty {
                    mustEmbed = true
                }
                certificates.append(SecCertificateCopyData(cert) as Data)
            } else {
                mustEmbed = true
            }
        }
        if mustEmbed {
            helper.embeddedCertificates.append(contentsOf: certificates)
        }
        
        return try helper.wrap(input: wrapper, previous:nil, schema: schema, recipients: self.recipients, options: self.cmsOptions)
    }
    
    @objc
    public var cmsOptions : OFCMSOptions
    
    /// The unencrypted, outer identifier for this document.
    ///
    /// This is used to match the document with a password keychain item.
    @objc
    public var documentIdentifier : Data?
    
    /// The unencrypted password hint text for this document.
    @objc
    public var passwordHint : String?
    
    // Information about recipients. These are only non-private so that they can be used by the -Inspection category.
    @nonobjc internal var recipients : [CMSRecipient]
    @nonobjc internal var unreadableRecipientCount : UInt
    
    private
    init(from wrapper: OFCMSFileWrapper) {
        cmsOptions = []
        // TODO: copy stuff from helper into savedSettings
        recipients = wrapper.recipientsFoo
        unreadableRecipientCount = 0
        passwordHint = wrapper.passwordHint
        
        let embeddedCertificates = wrapper.embeddedCertificates.lazy.compactMap { SecCertificateCreateWithData(kCFAllocatorDefault, $0 as CFData) }
        
        for recipient_ in recipients {
            resolveRecipient:
            if let recipient = recipient_ as? CMSPKRecipient, !recipient.canWrap() {
                
                // First try the embedded certificates
                for cert in embeddedCertificates {
                    if recipient.resolve(certificate: cert) {
                        break resolveRecipient
                    }
                }
                
                // Next see if we can resolve from our auxiliary keys
                for auxiliaryKey in wrapper.auxiliaryAsymmetricKeys {
                    do {
                        if let cert = try auxiliaryKey.certificate() {
                            if recipient.resolve(certificate: cert) {
                                break resolveRecipient
                            }
                        }
                    } catch let e {
                        debugPrint(e)
                        // Ignore exceptions from here
                    }
                }
                
                // Or from the keychains
                if recipient.resolveWithKeychain() {
                    break resolveRecipient
                }
                
                // Not much else we can do here?
            }
        }

    }
    
    @objc public
    override init() {
        cmsOptions = []
        recipients = []
        unreadableRecipientCount = 0
    }
    
    @objc public
    init(settings other_: OFDocumentEncryptionSettings?) {
        if let other = other_ {
            cmsOptions = other.cmsOptions
            recipients = other.recipients
            unreadableRecipientCount = other.unreadableRecipientCount
            passwordHint = other.passwordHint
        } else {
            cmsOptions = []
            recipients = []
            unreadableRecipientCount = 0
            passwordHint = nil
        }
    }
    
    @objc public override
    var debugDictionary: NSMutableDictionary {
        let debugDictionary : NSMutableDictionary = super.debugDictionary

        debugDictionary.setUnsignedIntegerValue(self.cmsOptions.rawValue, forKey: "cmsOptions")
        if let docId = self.documentIdentifier as NSData? {
            debugDictionary.setObject(docId, forKey: "documentIdentifier" as NSString)
        }
        if let pwHint = self.passwordHint as NSString? {
            debugDictionary.setObject(pwHint, forKey: "passwordHint" as NSString)
        }
        debugDictionary.setUnsignedIntegerValue(self.unreadableRecipientCount, forKey: "unreadableRecipientCount")
        debugDictionary.setObject(self.recipients.map({ $0.debugDictionary() }), forKey: "recipients" as NSString)
        
        return debugDictionary
    }
}

internal
class OFCMSFileWrapper {
    
    fileprivate static let indexFileName = "contents.cms"
    fileprivate static let encryptedContentIndexNamespaceURI = "http://www.omnigroup.com/namespace/DocumentEncryption/v1"
    fileprivate static let xLinkNamespaceURI = "http://www.w3.org/1999/xlink"
    fileprivate static let hintFileName = ".iwph" // iWork compatibilish
    fileprivate static let hintFileXattr = "com.omnigroup.DocumentEncryption.Hint"
    
    var recipientsFoo : [CMSRecipient] = []
    var usedRecipient : CMSRecipient? = nil
    var embeddedCertificates : [Data] = []
    var outermostIdentifier: Data? = nil
    var passwordHint : String? = nil
    var shouldSupportLegacyHints: Bool = true
    public var delegate : OFCMSKeySource? = nil
    public var auxiliaryAsymmetricKeys : [Keypair] = []
    
    /** Checks whether an NSFileWrapper looks like an encrypted document we produced. */
    public class func mightBeEncrypted(_ wrapper: FileWrapper) -> Bool {
        
        if wrapper.isRegularFile {
            if let contentData = wrapper.regularFileContents {
                return OFCMSFileWrapper.mightBeCMS(contentData)
            } else {
                return false
            }
        } else if wrapper.isDirectory {
            if let indexFile = wrapper.fileWrappers?[OFCMSFileWrapper.indexFileName], indexFile.isRegularFile,
               let indexFileContents = indexFile.regularFileContents {
                return OFCMSFileWrapper.mightBeCMS(indexFileContents)
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    /** Checks whether an NSData looks like it could be a CMS message */
    static fileprivate func mightBeCMS(_ data: Data) -> Bool {
        var ct : OFCMSContentType = OFCMSContentType_Unknown
        let rc = OFASN1ParseCMSContent(data, &ct, nil)
        if rc == 0 && ct != OFCMSContentType_Unknown {
            return true
        } else {
            return false
        }
    }
    
    private typealias partWrapSpec = (identifier: Data?, contents: dataSrc, type: OFCMSContentType, options: OFCMSOptions)
    
    /// Encrypts a FileWrapper and returns the encrypted version.
    ///
    /// - parameter input: The FileWrapper (either a file or directory) to encrypt.
    /// - parameter previous: (Currently unused pass nil) a previous version of the file wrapper, for efficient save-in-place of file packages.
    /// - parameter schema: Options to apply to individual elements of the document.
    /// - parameter recipients: Password and public-key recipients.
    /// - parameter docID: Optional outer document identifier to attach to the envelope of the encrypted document.
    func wrap(input: FileWrapper, previous: FileWrapper?, schema: [String: Any]?, recipients: [CMSRecipient], docID: Data? = nil, options: OFCMSOptions) throws -> FileWrapper {
        
        var toplevelFileAttributes = input.fileAttributes

        if input.isRegularFile {
            /* For flat files, we can simply encrypt the flat file and write it out. */
            let wrapped = FileWrapper(regularFileWithContents: try self.wrap(data: input.regularFileContents!, recipients: recipients, embeddedCertificates: embeddedCertificates, options: options, outerIdentifier: docID))
            if let fname = input.preferredFilename {
                wrapped.preferredFilename = fname
            }
            if shouldSupportLegacyHints, let hintData = passwordHint?.data(using: String.Encoding.utf8) {
                var xattrs : [String : Any] = ( toplevelFileAttributes[NSFileExtendedAttributes] as? [String : Any] ) ?? [:]
                xattrs[OFCMSFileWrapper.hintFileXattr] = hintData
                toplevelFileAttributes[NSFileExtendedAttributes] = xattrs
            }
            wrapped.fileAttributes = toplevelFileAttributes
            return wrapped
        } else if input.isDirectory {
            /* For file packages, we encrypt all the files under random names, and write an index file indicating the real names of each file member. */

            let nameCount = input.countRegularFiles()
            let nlen = nameCount < 125 ? 6 : nameCount < 600 ? 8 : 15
            var ns = Set<String>()
            let sides = CMSKEKRecipient()

            var sideFiles : [ (String, FileWrapper, OFCMSOptions) ] = []
            var insideFiles : [ partWrapSpec ] = []
            var nextPartNumber = 1

            /** Helper function, used for recursively descending the plantext file wrapper and collecting items to encrypt. */
            func wrapWrapperHierarchy(_ w: FileWrapper, settings: [String:Any]?) -> (files: [PackageIndex.FileEntry], directories: [PackageIndex.DirectoryEntry]) {
                guard let items = w.fileWrappers else {
                    return ([], []) // what to do here? when can this happen?
                }
                var files : [PackageIndex.FileEntry] = []
                var directories : [PackageIndex.DirectoryEntry] = []
                for (realName, wrapper) in items {
                    let setting = settings?[realName] as! [String : Any]?
                    if wrapper.isRegularFile {
                        var obscuredName : String
                        var fileOptions : OFCMSOptions = []

                        if let specifiedOptions = setting?[OFDocEncryptionFileOptions] {
                            if let asOpts = specifiedOptions as? OFCMSOptions {
                                fileOptions.formUnion(asOpts)
                            } else if let asNum = specifiedOptions as? UInt {
                                fileOptions.formUnion(OFCMSOptions(rawValue: asNum))
                            } else {
                                // Shouldn't happen.
                                assert(false, "invalid type in CMSFileWrapper schema")
                            }
                        }

                        let contentType = (fileOptions.contains(OFCMSOptions.contentIsXML)) ? OFCMSContentType_XML : OFCMSContentType_data

                        if fileOptions.contains(OFCMSOptions.storeInMain) {

                            let cid = "part\(nextPartNumber)"
                            nextPartNumber += 1

                            insideFiles.append( (cid.data(using: String.Encoding.ascii)!, dataSrc.fileWrapper(wrapper), contentType, fileOptions) )

                            obscuredName = "#" + cid
                        } else {

                            if let exposed = setting?[OFDocEncryptionExposeName] {
                                obscuredName = exposed as! String
                            } else {
                                obscuredName = OFCMSFileWrapper.generateCrypticFilename(ofLength: nlen)
                            }

                            while ns.contains(obscuredName) {
                                obscuredName = OFCMSFileWrapper.generateCrypticFilename(ofLength: nlen)
                            }
                            ns.insert(obscuredName)

                            sideFiles.append( (obscuredName, wrapper, fileOptions) )
                        }

                        files.append(PackageIndex.FileEntry(realName: realName, storedName: obscuredName, options: fileOptions))
                    } else if wrapper.isDirectory {
                        let subSettings : [String : Any]? = setting?[OFDocEncryptionChildren] as! [String : Any]?
                        let (subFiles, subDirectories) = wrapWrapperHierarchy(wrapper, settings: subSettings)
                        directories.append(PackageIndex.DirectoryEntry(realName: realName, files: subFiles, directories: subDirectories))
                    }
                }

                return (files: files, directories: directories)
            }

            // Traverse the plaintext file wrapper, extracting a list of file contents and where they should go.
            var packageIndex = PackageIndex()
            packageIndex.keys[sides.keyIdentifier] = sides.kek
            (packageIndex.files, packageIndex.directories) = wrapWrapperHierarchy(input, settings: schema)

            // Include the table-of-contents item in the list of things to encrypt.
            try insideFiles.insert( (nil, dataSrc.data(packageIndex.serialize()), OFCMSContentType_XML, options), at: 0)

            // Embed recipients' certificates.
            if !embeddedCertificates.isEmpty {
                let certBundle = OFCMSCreateSignedData(OFCMSContentType_data.asDER(), nil, embeddedCertificates, [Data]())
                insideFiles.insert( (nil, dataSrc.data(OFNSDataFromDispatchData(certBundle)), OFCMSContentType_signedData, [OFCMSOptions.storeInMain, OFCMSOptions.compress] ),
                                    at: 1)
            }

            // Wrap the main object, containing the table-of-contents and any files we've decided to store with it.
            let wrappedIndex = try self.wrap(parts: insideFiles,
                                             recipients: recipients,
                                             options: options,
                                             outerIdentifier: docID)
            var resultItems : [String:FileWrapper] = [:]
            resultItems[OFCMSFileWrapper.indexFileName] = FileWrapper(regularFileWithContents: wrappedIndex)

            // Wrap any side files.
            for (obscuredName, wrapper, fileOptions) in sideFiles {
                let wrappedData = try self.wrap(data: wrapper.regularFileContents!, recipients: [sides], options: fileOptions)
                let sideFile = FileWrapper(regularFileWithContents: wrappedData)
                sideFile.preferredFilename = obscuredName
                resultItems[obscuredName] = sideFile
            }

            // Insert the password hint if we have one
            if shouldSupportLegacyHints, let hintData = passwordHint?.data(using: String.Encoding.utf8) {
                let addition = FileWrapper(regularFileWithContents: hintData)
                addition.preferredFilename = OFCMSFileWrapper.hintFileName
                resultItems[OFCMSFileWrapper.hintFileName] = addition
            }

            let result = FileWrapper(directoryWithFileWrappers: resultItems)
            result.fileAttributes = toplevelFileAttributes
            return result
        } else {
            // We can't store symlinks
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil /* TODO: Better error for this should-never-happen case? */)
        }
    }
    
    /** Generates a random filename of a given length. */
    private static 
    func generateCrypticFilename(ofLength nlen: Int) -> String {
        var r : UInt32 = 0
        var cs = Array(repeating: UInt8(0), count: nlen)
        let ch : [UInt8] = [ 0x49, 0x6C, 0x4F, 0x30, 0x31 ]
        for i in 0 ..< nlen {
            if i % 12 == 0 {
                r = OFRandomNext32()
            }
            
            var v : Int
            if i == 0 || i == (nlen - 1) {
                v = Int(r & 0x01)
                r = r >> 1
            } else {
                v = Int(r % 5)
                r = r / 5
            }
            
            cs[i] = ch[v]
        }
        
        return String(bytes: cs, encoding: String.Encoding.ascii)!
    }
    
    /** Decrypts a FileWrapper and returns the plaintext version */
    func unwrap(input: FileWrapper) throws -> FileWrapper {
        
        if input.isRegularFile {
            // Extract the password hint, if any
            let fileAttributes = input.fileAttributes
            if shouldSupportLegacyHints && passwordHint == nil, let xattrs = fileAttributes[NSFileExtendedAttributes] as? [String:Any],
               let pwhint = xattrs[OFCMSFileWrapper.hintFileXattr] {
                if let pwhint_data = pwhint as? Data {
                    passwordHint = String(data: pwhint_data, encoding: String.Encoding.utf8)
                }
            }

            // Read and decrypt the file
            guard let encryptedData = input.regularFileContents else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
            }
            let decryptedData = try self.unwrap(data: encryptedData)
            guard let unwrappedData = decryptedData.primaryContent else {
                throw miscFormatError()
            }
            
            recipientsFoo = decryptedData.allRecipients
            usedRecipient = decryptedData.usedRecipient
            embeddedCertificates += decryptedData.embeddedCertificates
            outermostIdentifier = decryptedData.outerIdentifier
            let unwrapped = FileWrapper(regularFileWithContents: unwrappedData)
            if let fname = input.preferredFilename {
                unwrapped.preferredFilename = fname
            }
            unwrapped.fileAttributes = fileAttributes
            return unwrapped
        } else if input.isDirectory {
            
            // Open the main index file and read the index, which should be its primary content.
            
            guard let encryptedFiles = input.fileWrappers else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
            }
            
            guard let indexFile = encryptedFiles[OFCMSFileWrapper.indexFileName],
                  indexFile.isRegularFile,
                  let indexFileContents = indexFile.regularFileContents else {
                throw missingFileError(filename: OFCMSFileWrapper.indexFileName)
            }
            
            // Extract the password hint, if any
            if shouldSupportLegacyHints && passwordHint == nil,
                let hintFile = encryptedFiles[OFCMSFileWrapper.hintFileName],
                hintFile.isRegularFile,
                let hintData = hintFile.regularFileContents {
                passwordHint = String(data: hintData, encoding: String.Encoding.utf8)
            }
            
            // Decrypt the main object to get the index / table-of-contents
            let decryptedIndexFile = try self.unwrap(data: indexFileContents)
            recipientsFoo = decryptedIndexFile.allRecipients
            usedRecipient = decryptedIndexFile.usedRecipient
            embeddedCertificates += decryptedIndexFile.embeddedCertificates
            outermostIdentifier = decryptedIndexFile.outerIdentifier
            guard let indexData = decryptedIndexFile.primaryContent else {
                throw miscFormatError(reason: "Missing table of contents")
            }
            
            // Parse the index to get a list of plaintext files and where they live in the final file wrapper
            let indexEntries : PackageIndex
            do {
                indexEntries = try PackageIndex.unserialize(indexData)
            } catch let e as NSError {
                throw miscFormatError(reason: "Malformed table of contents", underlying: e)
            }
            
            // Recreate the structure of directory wrappers. Don't decrypt the leaf files yet, but build a list of which side file contains data which goes into which directory wrapper.
            
            typealias unwrapQueue = Array<(Data?, OFCMSOptions, String, FileWrapper)>
            
            var leafFiles : [ String : unwrapQueue ] = [:]
            
            func recreateWrapperHierarchy(files: [PackageIndex.FileEntry], directories: [PackageIndex.DirectoryEntry]) -> FileWrapper {
                var resultItems : [String : FileWrapper] = [:]
                for dent in directories {
                    resultItems[dent.realName] = recreateWrapperHierarchy(files: dent.files, directories: dent.directories)
                }
                let directoryWrapper = FileWrapper(directoryWithFileWrappers: resultItems)
                
                for fent in files {
                    let (basename, cid) = fent.splitStoredName()
                    if leafFiles[basename] == nil {
                        leafFiles[basename] = []
                    }
                    leafFiles[basename]!.append( (cid, fent.options, fent.realName, directoryWrapper) )
                }
                
                return directoryWrapper
            }
            let resultWrapper = recreateWrapperHierarchy(files: indexEntries.files, directories: indexEntries.directories)
            
            // Now repopulate the file wrapper hierarchy's regular file data.
            
            func readSideFileEntries(sideFileNameForDebugging: String, sideFile: OFCMSFileWrapper.ExpandedContent, entries: unwrapQueue) throws {
                for (cid_, options, realName, dstWrapper) in entries {
                    var fentData : Data?
                    var fentId : String
                    if let cid = cid_ {
                        // One entry in a multipart file.
                        fentData = sideFile.identifiedContent[cid]
                        fentId = "#" + uglyHexify(cid)
                    } else {
                        // File entry refers to the side file's primary content.
                        fentData = sideFile.primaryContent
                        fentId = ""
                    }
                    guard let fentDataBang = fentData else {
                        if options.contains(OFCMSOptions.fileIsOptional) {
                            continue
                        } else {
                            throw missingFileError(filename: sideFileNameForDebugging + fentId)
                        }
                    }
                    dstWrapper.addRegularFile(withContents: fentDataBang, preferredFilename: realName)
                }
            }
            
            // Extract any files contained in the main CMS object --- do this first so we can go ahead and deallocate it.
            if let indexFilePackedEntries = leafFiles.removeValue(forKey: "") {
                try readSideFileEntries(sideFileNameForDebugging: OFCMSFileWrapper.indexFileName, sideFile: decryptedIndexFile, entries: indexFilePackedEntries)
            }
            // Then any files contained in auxiliary CMS objects. We do it this way so that we only decrypt/decompress a given file once even if it contains multiple contents.
            for (sideFileName, entries) in leafFiles {
                guard let dataFile = encryptedFiles[sideFileName] else {
                    // This file was missing, make sure that's OK.
                    for (_, opts, _, _) in entries {
                        if !opts.contains(OFCMSOptions.fileIsOptional) {
                            throw missingFileError(filename: sideFileName)
                        }
                    }
                    // All the entries in this file were optional, so I guess this is OK.
                    continue
                }
                
                try autoreleasepool(invoking: { () -> () in
                    guard dataFile.isRegularFile,
                          let fileData = dataFile.regularFileContents else {
                            throw missingFileError(filename: sideFileName)
                    }
                    
                    try readSideFileEntries(sideFileNameForDebugging: sideFileName, sideFile: self.unwrap(data: fileData, auxiliaryKeys: indexEntries.keys), entries: entries)
                })
            }
            
            
            // We're done recreating the original wrapper hierarchy and all its content files return it.
            return resultWrapper
        } else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
        }
    }
    
    private func compressPart(data input: Data, contentType: OFCMSContentType) throws -> (Data, OFCMSContentType) {
        #if true
        return (input, contentType)  // TODO
        #else
        if input.count < 200 {
            return (input, contentType)
        }
        
        var error : NSError? = nil
        guard let compressed = OFCMSCreateCompressedData(contentType.asDER(), input, &error) else {
            throw error!
        }
        let compressed_ = (compressed as AnyObject) as! Data
        
        // Unless we save at least 2% of our size, don't bother storing it compressed.
        if (compressed_.count + (compressed_.count / 50)) < input.count {
            return (compressed_, OFCMSContentType_compressedData)
        } else {
            return (input, contentType)
        }
        #endif
    }
    
    /// Wrap some input data (which may itself already be a CMS object).
    private func wrap(data input_: Data, type type_: OFCMSContentType = OFCMSContentType_Unknown, recipients: [CMSRecipient], embeddedCertificates certs: [Data]? = nil, options: OFCMSOptions, outerIdentifier: Data? = nil) throws -> Data {
        
        var input = input_
        var contentType = type_
        
        // Determine the content type if it wasn't specified
        if contentType == OFCMSContentType_Unknown {
            contentType = (options.contains(.contentIsXML) ? OFCMSContentType_XML : OFCMSContentType_data)
        }
        
        // Optionally compress
        if options.contains(.compress) {
            (input, contentType) = try compressPart(data: input, contentType: contentType)
        }
        
        // If there are embedded certificates, embed them using a signature-less SignedData content
        if let certs = certs, !certs.isEmpty {
            input = OFNSDataFromDispatchData(OFCMSCreateSignedData(contentType.asDER(), input, certs, [Data]()))
            contentType = OFCMSContentType_signedData
        }
        
        // Generate the session key (CEK), and produce a wrapped CEK for each recipient
        let cek = NSData.cryptographicRandomData(ofLength: 32)
        let rinfos = try recipients.map( { (recip) -> Data in try recip.recipientInfo(wrapping: cek) } )
        
        var envelope : Data
        var envelopeType : OFCMSContentType
        
        // Perform the actual bulk encryption
        let hintAttributes : [Data]?
        if let hintData = passwordHint?.data(using: String.Encoding.utf8) {
            hintAttributes = [ OFCMSHintAttribute(hintData) ]
        } else {
            hintAttributes = nil
        }

        if !options.contains(.withoutAEAD) {
            let authAttributes : [Data]?
            if let cid = outerIdentifier {
                authAttributes = [ OFCMSIdentifierAttribute(cid) ]
            } else {
                authAttributes = nil
            }

            var error : NSError? = nil
            guard let enveloped_ = OFCMSCreateAuthenticatedEnvelopedData(cek, rinfos, options, contentType.asDER(), input, authAttributes, hintAttributes, &error) else {
                throw error!
            }
            envelope = OFNSDataFromDispatchData(enveloped_)
            envelopeType = OFCMSContentType_authenticatedEnvelopedData
        } else {
            var error : NSError? = nil
            guard let enveloped_ = OFCMSCreateEnvelopedData(cek, rinfos, contentType.asDER(), input, hintAttributes, &error) else {
                throw error!
            }
            envelope = OFNSDataFromDispatchData(enveloped_)
            envelopeType = OFCMSContentType_envelopedData
        }
        
        return OFNSDataFromDispatchData(OFCMSWrapContent(envelopeType, envelope))
    }
    
    // Wrap multiple plaintext items into one ciphertext file
    private func wrap(parts: [partWrapSpec], recipients: [CMSRecipient], options: OFCMSOptions, outerIdentifier: Data?) throws -> Data {

        // If we only have one part, we don't need to use a ContentCollection
        if parts.count == 1 {
            let partContents = try parts[0].contents.get()
            let partOptions = options.union(parts[0].options)
            if let partIdentifier = parts[0].identifier {
                return try wrap(data: OFNSDataFromDispatchData(OFCMSWrapIdentifiedContent(parts[0].type, partContents, partIdentifier)),
                                type: OFCMSContentType_contentWithAttributes,
                                recipients: recipients,
                                options: partOptions,
                                outerIdentifier: outerIdentifier)
            } else {
                return try wrap(data: partContents,
                                type: parts[0].type,
                                recipients: recipients,
                                options: partOptions,
                                outerIdentifier: outerIdentifier)
            }
        }
        
        // If we have multiple parts (or zero, though that's a silly case), put everything in a ContentCollection
        
        let anyUncompressedParts = parts.contains { !$0.options.contains(OFCMSOptions.compress) }
        
        let encodedParts = try parts.map { (part: partWrapSpec) -> Data in
            var partContents = try part.contents.get()
            var partType = part.type
            if anyUncompressedParts && part.options.contains(OFCMSOptions.compress) {
                (partContents, partType) = try compressPart(data: partContents, contentType: partType)
            }
            if let partIdentifier = part.identifier {
                return OFNSDataFromDispatchData(OFCMSWrapIdentifiedContent(partType, partContents, partIdentifier))
            } else {
                return OFNSDataFromDispatchData(OFCMSWrapContent(partType, partContents))
            }
        }
        
        var outerOptions = options
        if anyUncompressedParts {
            outerOptions.remove(OFCMSOptions.compress)
        } else {
            outerOptions.insert(OFCMSOptions.compress)
        }
        
        return try wrap(data: OFNSDataFromDispatchData(OFCMSCreateMultipart(encodedParts)), type: OFCMSContentType_contentCollection, recipients: recipients, options: outerOptions, outerIdentifier: outerIdentifier)
    }
    
    /// Represents the results of recursively unpacking one disk file.
    private struct ExpandedContent {
        /// The outermost content-identifier
        // (stored in plaintext and possibly unauthenticated).
        let outerIdentifier: Data?
        /// Primary (or only, in the common case) content data.
        var primaryContent: Data?
        /// Other contents, stored by their content-identifiers.
        var identifiedContent: [Data : Data]
        /// Any certificates found while traversing the message.
        var embeddedCertificates: [Data]
        
        /// All CMSRecipients found on the outermost (typically only) envelope.
        let allRecipients: [CMSRecipient]
        /// The recipient we actually used for decryption.
        let usedRecipient: CMSRecipient?
    }

    /// Unwrap a component, returning its decrypted and assorted contents.
    ///
    /// See the comments on `ExpandedContent` for details.
    private func unwrap(data input_: Data, auxiliaryKeys: [Data: Data] = [:]) throws -> ExpandedContent {
        
        let decr = try OFCMSUnwrapper(data: input_, keySource: delegate)
        
        if !auxiliaryKeys.isEmpty {
            decr.addSymmetricKeys(auxiliaryKeys)
        }
        if !auxiliaryAsymmetricKeys.isEmpty {
            decr.addAsymmetricKeys(auxiliaryAsymmetricKeys)
        }
        decr.passwordHint = passwordHint
        
        try decr.peelMeLikeAnOnion()
        var result = ExpandedContent(outerIdentifier: decr.contentIdentifier,
                                     primaryContent: nil,
                                     identifiedContent: [:],
                                     embeddedCertificates: decr.embeddedCertificates,
                                     allRecipients: decr.allRecipients,
                                     usedRecipient: decr.usedRecipient)

        switch decr.contentType {
        case OFCMSContentType_data, OFCMSContentType_XML:
            result.primaryContent = try decr.content()
            
        case OFCMSContentType_contentCollection:
            var parts = try decr.splitParts().makeIterator()
            while true {
                guard let part = parts.next() else {
                    break
                }
                
                try part.peelMeLikeAnOnion()
                result.embeddedCertificates += part.embeddedCertificates
                if part.hasNullContent /* && ! part.embeddedCertificates.isEmpty */ {
                    // It's OK for a signedData to have null content --- it's how CMS/PKCS#7/PKCS#12 objects contain certificate lists.
                    continue
                }
                
                switch part.contentType {
                case OFCMSContentType_contentCollection:
                    var subParts = try part.splitParts()
                    subParts.append(contentsOf: parts)
                    parts = subParts.makeIterator()

                case OFCMSContentType_data, OFCMSContentType_XML:
                    let partContents = try part.content()
                    if let identifier = part.contentIdentifier {
                        result.identifiedContent[identifier] = partContents
                    } else if result.primaryContent == nil {
                        result.primaryContent = partContents
                    }
                    // We're dropping any identifier-less content other than the first on the floor.
                    
                default:
                    if result.primaryContent == nil && part.contentIdentifier == nil {
                        // This could be the primary content, if we knew what it was. Throw an error.
                        throw unexpectedContentTypeError(part.contentType)
                    }
                    // Else, ignore it. If it's referenced by something, we'll get the appropriate error when we try to find it.
                }
            }
            
        default:
            throw unexpectedContentTypeError(decr.contentType)
        }
        
        return result
    }
    
    /// Convenience for generating an error when we don't recognize or expect a given content-type.
    private func unexpectedContentTypeError(_ ct: OFCMSContentType) -> Error {
        return OFError(.OFUnsupportedCMSFeature,
                       userInfo: [NSLocalizedFailureReasonErrorKey: NSLocalizedString("Unexpected CMS content-type", tableName: "OmniFoundation", bundle: OFBundle, comment: "Document decryption error - unexpected content-type found while unwrapping a Cryptographic Message Syntax object")])
    }
    
    /// PackageIndex represents the table-of-contents object of an encrypted file wrapper.
    private struct PackageIndex {
        
        // A single file in the plaintext wrapper
        struct FileEntry {
            let realName: String
            let storedName: String
            let options: OFCMSOptions
            
            func serialize(into elt: OFXMLMakerElement) {
                let felt = elt.openElement("file")
                              .addAttribute("name", value: realName)
                              .addAttribute("href", xmlns: xLinkNamespaceURI, value: storedName)
                if options.contains(OFCMSOptions.fileIsOptional) {
                    felt.addAttribute("optional", value: "1")
                }
                felt.close()
            }
            
            func splitStoredName() -> (String, Data?) {
                if let sep = storedName.range(of: "#") {
                    let first = String(storedName[..<sep.lowerBound])
                    let second = String(storedName[sep.upperBound...])
                    return (first, second.data(using: String.Encoding.ascii))
                } else {
                    return (storedName, nil)
                }
            }
        }
        
        // A directory in the plaintext wrapper
        struct DirectoryEntry {
            let realName: String
            let files : [FileEntry]
            let directories : [DirectoryEntry]
            
            func serialize(into elt: OFXMLMakerElement) {
                let dirElt = elt.openElement("directory").addAttribute("name", value: realName)
                for fileEntry in files {
                    fileEntry.serialize(into: dirElt)
                }
                for subDirectory in directories {
                    subDirectory.serialize(into: dirElt)
                }
                dirElt.close()
            }
        }
        
        var files : [FileEntry] = []
        var keys : [Data : Data] = [:]
        var directories : [DirectoryEntry] = []
        
        /// Produce an XML representation of the PackageIndex
        func serialize() throws -> Data {
            let strm = OutputStream(toMemory: ())
            let sink = OFXMLTextWriterSink(stream: strm)!
            let doc = sink.openElement("index", xmlns: encryptedContentIndexNamespaceURI, defaultNamespace: encryptedContentIndexNamespaceURI)
            doc.prefix(forNamespace:xLinkNamespaceURI, hint: "xl")
            
            for (keyIdentifier, keyMaterial) in self.keys {
                doc.openElement("key")
                    .addAttribute("id", value: (keyIdentifier as NSData).unadornedLowercaseHexString())
                    .add(string: (keyMaterial as NSData).unadornedLowercaseHexString())
                    .close()
            }
            
            for d in self.directories {
                d.serialize(into: doc)
            }
            
            for entry in self.files {
                entry.serialize(into: doc)
            }
            
            doc.close()
            sink.close()
            
            if let bufferError = strm.streamError {
                throw bufferError
            }
            
            let v = strm.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey)
            
            return (v as? Data) ?? Data()  // RADAR 6160521
        }
        
        /// Parse a PackageIndex from its XML representation
        static func unserialize(_ input: Data) throws -> PackageIndex {
            let reader = try OFXMLReader(data: input)
            guard let rtelt = reader.elementQName() else {
                throw OFError(.OFXMLDocumentNoRootElementError)
            }
            guard rtelt.name == "index", rtelt.namespace == encryptedContentIndexNamespaceURI else {
                throw miscFormatError(reason: "Incorrect root element: \(rtelt.shortDescription)")
            }
            
            var files : [PackageIndex.FileEntry] = []
            var keys : [Data:Data] = [:]
            var directories : [DirectoryEntry] = []
            
            let fileNameAttr = OFXMLQName(namespace: nil, name: "name")!
            let fileLocationAttr = OFXMLQName(namespace: xLinkNamespaceURI, name: "href")!
            let fileOptionalAttr = OFXMLQName(namespace: nil, name: "optional")!
            let keyIdAttr = OFXMLQName(namespace: nil, name: "id")!
            
            try reader.openElement()
            var currentElementName = reader.elementQName()
            var directoryStack : [DirectoryEntry] = []
            
            while true {
                try reader.findNextElement(&currentElementName)
                guard let elementName = currentElementName else {
                    // Nil indicates end of enclosing element. In theory the only elements we should be entering are the toplevel element and any <directory/> elements.
                    if let dent = directoryStack.popLast() {
                        // We abuse the DirectoryEntry type slightly here: its name field contains the name of the dierctory we were just scanning, but its other fields are the saved state from its own containing directry.
                        let newSubdirectory = DirectoryEntry(realName: dent.realName, files: files, directories: directories)
                        files = dent.files
                        directories = dent.directories
                        directories.append(newSubdirectory)
                        try reader.closeElement()
                        continue
                    } else {
                        // Done with the index.
                        break
                    }
                }
                
                if elementName.name == "file" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    guard let memberName = try reader.getAttributeValue(fileNameAttr),
                          let memberLocation = try reader.getAttributeValue(fileLocationAttr) else {
                            throw OFError(.OFEncryptedDocumentFormatError, userInfo: [
                                NSLocalizedFailureReasonErrorKey: "Missing <file> attribute"
                                ])
                    }
                    var memberOptions : OFCMSOptions = []
                    if let optionality = try reader.getAttributeValue(fileOptionalAttr), (optionality as NSString).boolValue() {
                        memberOptions.formUnion(OFCMSOptions.fileIsOptional)
                    }
                    files.append(PackageIndex.FileEntry(realName: memberName, storedName: memberLocation, options: memberOptions))
                    try reader.skipCurrentElement()
                } else if elementName.name == "key" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    guard let keyName = try reader.getAttributeValue(keyIdAttr) else {
                        throw OFError(.OFEncryptedDocumentFormatError, userInfo: [
                            NSLocalizedFailureReasonErrorKey: "Missing <key> attribute"
                        ])
                    }
                    do {
                        try reader.openElement()
                        var keyValue = nil as NSString?
                        try reader.copyStringContents(toEndOfElement: &keyValue)
                        let keyValueData = try NSData(hexString: keyValue! as String)

                        keys[ try NSData(hexString:keyName) as Data ] = keyValueData as Data
                    } catch let e as NSError {
                        throw OFError(.OFEncryptedDocumentFormatError, userInfo: [NSUnderlyingErrorKey: e])
                    }
                } else if elementName.name == "directory" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    guard let dirName = try reader.getAttributeValue(fileNameAttr) else {
                        throw OFError(.OFEncryptedDocumentFormatError, userInfo: [
                            NSLocalizedFailureReasonErrorKey: "Missing <directory> attribute"
                            ])
                    }
                    
                    directoryStack.append(DirectoryEntry(realName: dirName, files: files, directories: directories))
                    files = []
                    directories = []
                    try reader.openElement()
                } else {
                    // Ignore unknown tags.
                    try reader.skipCurrentElement()
                }
            }
            
            return PackageIndex(files: files, keys: keys, directories: directories)
        }
    }
}

private let NSFileExtendedAttributes = "NSFileExtendedAttributes"

private
func missingFileError(filename: String) -> Error {
    let msg = NSString(format: NSLocalizedString("The encrypted item \"%@\" is missing or unreadable.", tableName: "OmniFoundation", bundle: OFBundle, comment: "Document decryption error message - a file within the encrypted file wrapper can't be read") as NSString,
                       filename) as String
    return miscFormatError(reason: msg)
}

private
func uglyHexify(_ cid: Data) -> String {
    var buf : String = ""
    for byte in cid {
        if byte > 0x20 && byte < 0x7F {
            buf.append(String(UnicodeScalar(byte)))
        } else {
            buf.append(String(format: "%%%02X", UInt(byte)))
        }
    }
    return buf
}

private
func miscFormatError(reason: String? = nil, underlying: NSError? = nil) -> Error {
    var userInfo: [String: AnyObject] = [:]
    
    if let underlyingError = underlying {
        if underlyingError.domain == OFErrorDomain && underlyingError.code == OFError.OFEncryptedDocumentFormatError.rawValue && reason == nil {
            return underlyingError
        }
        userInfo[NSUnderlyingErrorKey] = underlyingError
    }
    
    if let message = reason {
        userInfo[NSLocalizedFailureReasonErrorKey] = message as NSString
    }
    
    return OFError(.OFEncryptedDocumentFormatError, userInfo: userInfo)
}

private extension OFXMLReader {
    /// Swifty cover on -copyValueOfAttribute:named:error:
    func getAttributeValue(_ qualifiedName: OFXMLQName) throws -> String? {
        var attributeValue : NSString?
        attributeValue = nil
        try self.copyValue(ofAttribute: &attributeValue, named: qualifiedName)
        return attributeValue as String?
    }
}

/// A tiny Either class containing either raw Data or a (potentially lazily-mapped) NSFileWrapper
fileprivate enum dataSrc {
    case data(_: Data)
    case fileWrapper(_: FileWrapper)
    
    func get() throws -> Data {
        switch self {
        case .data(let d):
            return d
        case .fileWrapper(let w):
            guard let contents = w.regularFileContents else {
                throw CocoaError(.fileReadUnknown)
            }
            return contents
        }
    }
}

private extension FileWrapper {
    
    /// Count the number of regular files in a file wrapper hierarchy
    func countRegularFiles() -> UInt {
        
        if self.isRegularFile {
            return 1
        }
        
        var nameCount : UInt = 0
        var wrappersToCount : [FileWrapper] = [self]
        
        repeat {
            if let entries = wrappersToCount.popLast()?.fileWrappers {
                for (_, w) in entries {
                    if w.isRegularFile {
                        nameCount += 1
                    } else if w.isDirectory {
                        wrappersToCount.append(w)
                    }
                }
            }
        } while !wrappersToCount.isEmpty
        
        return nameCount
    }
}

