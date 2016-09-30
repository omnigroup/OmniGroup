// Copyright 2016 Omni Development, Inc. All rights reserved.
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
    
    /** Decrypts an encrypted document file, if necessary.
     
     If the file is encrypted, it is unwrapped and a new file wrapper is returned, and information about the encryption settings is stored in `info`. Otherwise the original file wrapper is returned.
     
     - Parameter info: Will be filled in with a new instance of `OFDocumentEncryptionSettings` iff the file wrapper was encrypted.
     - Parameter delegate: Will be used to resolve password/key queries.
     
     */
    @objc(decryptFileWrapper:info:keys:error:)
    public class func unwrapIfEncrypted(_ wrapper: FileWrapper, info: AutoreleasingUnsafeMutablePointer<OFDocumentEncryptionSettings?>, keys: OFCMSKeySource?) throws -> FileWrapper {
        if (OFCMSFileWrapper.mightBeEncrypted(wrapper)) {
            let helper = OFCMSFileWrapper();
            helper.delegate = keys;
            let unwrapped = try helper.unwrap(input: wrapper);
            info.pointee = OFDocumentEncryptionSettings(from: helper);
            return unwrapped;
        } else {
            info.pointee = nil;
            return wrapper;
        }
    }
    
    /** Tests whether a given filewrapper looks like an encrypted document.
     *
     * May return false positives for other CMS objects, such as PKCS#7 or PKCS#12 objects.
     */
    @objc(fileWrapperMayBeEncrypted:)
    public class func mayBeEncrypted(wrapper: FileWrapper) -> ObjCBool {
        if (OFCMSFileWrapper.mightBeEncrypted(wrapper)) {
            return true;
        } else {
            return false;
        }
    }
    
    /** Encrypts a file wrapper using the receiver's settings. */
    @objc(encryptFileWrapper:schema:error:)
    public func wrap(_ wrapper: FileWrapper, schema: [String:AnyObject]?) throws -> FileWrapper {
        let helper = OFCMSFileWrapper();
        return try helper.wrap(input: wrapper, previous:nil, schema: schema, recipients: self.recipients, options: self.cmsOptions);
    }
    
    @objc
    public var cmsOptions : OFCMSOptions;
    
    private var recipients : [CMSRecipient];
    private var unreadableRecipientCount : UInt;
    private var haveResolvedRecipients : Bool;
    
    private
    init(from wrapper: OFCMSFileWrapper) {
        cmsOptions = [];
        // TODO: copy stuff from helper into savedSettings
        recipients = wrapper.recipientsFoo;
        unreadableRecipientCount = 0;
        haveResolvedRecipients = true;
    }
    
    @objc public
    override init() {
        cmsOptions = [];
        recipients = [];
        unreadableRecipientCount = 0;
        haveResolvedRecipients = true;
    }
    
    @objc public
    init(settings other: OFDocumentEncryptionSettings) {
        cmsOptions = other.cmsOptions;
        recipients = other.recipients;
        unreadableRecipientCount = other.unreadableRecipientCount;
        haveResolvedRecipients = other.haveResolvedRecipients;
    }
    
    /// Removes any existing password recipients, and adds one given a plaintext passphrase.
    // - parameter: The password to set.
    @objc public
    func setPassword(_ password: String) {
        recipients = recipients.filter({ (recip: CMSRecipient) -> Bool in !(recip is CMSPasswordRecipient) });
        recipients.insert(CMSPasswordRecipient(password: password), at: 0);
    }
    
    /// Returns YES if the receiver allows decryption using a password.
    @objc public
    func hasPassword() -> ObjCBool {
        for recip in recipients {
            if recip is CMSPasswordRecipient {
                return true;
            }
        }
        return false;
    }
        
    @objc
    public func unusableRecipientCount() -> Int {
        if !haveResolvedRecipients {

        }
        return 0;
    }
};

internal
class OFCMSFileWrapper {
    
    fileprivate static let indexFileName = "index.cms";
    fileprivate static let encryptedContentIndexNamespaceURI = "urn:uuid:82E4237D-AB10-4D59-9688-76AEC71E4E1C"; // TODO: better namespace.
    fileprivate static let xLinkNamespaceURI = "http://www.w3.org/1999/xlink";
    
    var recipientsFoo : [CMSRecipient] = [];
    var usedRecipient : CMSRecipient? = nil;
    public var delegate : OFCMSKeySource? = nil;
    public var auxiliaryAsymmetricKeys : [Keypair] = [];
    
    /** Checks whether an NSFileWrapper looks like an encrypted document we produced. */
    public class func mightBeEncrypted(_ wrapper: FileWrapper) -> Bool {
        
        if wrapper.isRegularFile {
            if let contentData = wrapper.regularFileContents {
                return OFCMSFileWrapper.mightBeCMS(contentData);
            } else {
                return false;
            }
        } else if wrapper.isDirectory {
            if let indexFile = wrapper.fileWrappers?[OFCMSFileWrapper.indexFileName], indexFile.isRegularFile,
               let indexFileContents = indexFile.regularFileContents {
                return OFCMSFileWrapper.mightBeCMS(indexFileContents);
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
    
    /** Checks whether an NSData looks like it could be a CMS message */
    static fileprivate func mightBeCMS(_ data: Data) -> Bool {
        var ct : OFCMSContentType = OFCMSContentType_Unknown;
        let rc = OFASN1ParseCMSContent(data, &ct, nil);
        if rc == 0 && ct != OFCMSContentType_Unknown {
            return true;
        } else {
            return false;
        }
    }
    
    /** Encrypts a FileWrapper and returns the encrypted version. */
    func wrap(input: FileWrapper, previous: FileWrapper?, schema: [String: AnyObject]?, recipients: [CMSRecipient], options: OFCMSOptions) throws -> FileWrapper {
        
        if input.isRegularFile {
            /* For flat files, we can simply encrypt the flat file and write it out. */
            let wrapped = FileWrapper(regularFileWithContents: try self.wrap(data: input.regularFileContents!, recipients: recipients, options: options));
            if let fname = input.preferredFilename {
                wrapped.preferredFilename = fname;
            }
            wrapped.fileAttributes = input.fileAttributes;
            return wrapped;
        } else if input.isDirectory {
            /* For file packages, we encrypt all the files under random names, and write an index file indicating the real names of each file member. */
            
            let nameCount = input.countRegularFiles();
            let nlen = nameCount < 125 ? 6 : nameCount < 600 ? 8 : 15;
            var ns = Set<String>();
            let sides = CMSKEKRecipient();
            
            var sideFiles : [ (String, FileWrapper) ] = [];
            
            func wrapWrapperHierarchy(_ w: FileWrapper, settings: [String:AnyObject]?, files: inout [PackageIndex.FileEntry], directories: inout [PackageIndex.DirectoryEntry]) {
                guard let items = w.fileWrappers else {
                    return; // what to do here? when can this happen?
                }
                for (realName, wrapper) in items {
                    let setting = settings?[realName] as! [String : AnyObject]?;
                    if wrapper.isRegularFile {
                        var obscuredName : String;
                        var fileOptions : OFCMSOptions = [];
                        
                        if let specifiedOptions = setting?[OFDocEncryptionFileOptions] {
                            fileOptions.formUnion(OFCMSOptions(rawValue: specifiedOptions.unsignedIntegerValue));
                        }
                        
                        if let exposed = setting?[OFDocEncryptionExposeName] {
                            obscuredName = exposed as! String;
                        } else {
                            obscuredName = OFCMSFileWrapper.generateCrypticFilename(ofLength: nlen);
                        }
                        
                        while ns.contains(obscuredName) {
                            obscuredName = OFCMSFileWrapper.generateCrypticFilename(ofLength: nlen);
                        }
                        ns.insert(obscuredName);
                        
                        sideFiles.append( (obscuredName, wrapper) );
                        
                        files.append(PackageIndex.FileEntry(realName: realName, storedName: obscuredName, options: fileOptions))
                    } else if wrapper.isDirectory {
                        var subFiles: [PackageIndex.FileEntry] = [];
                        var subDirectories: [PackageIndex.DirectoryEntry] = [];
                        let subSettings : [String : AnyObject]? = setting?[OFDocEncryptionChildren] as! [String : AnyObject]?;
                        wrapWrapperHierarchy(wrapper, settings: subSettings, files: &subFiles, directories: &subDirectories);
                        directories.append(PackageIndex.DirectoryEntry(realName: realName, files: subFiles, directories: subDirectories));
                    }
                }
            }
            
            var packageIndex = PackageIndex();
            packageIndex.keys[sides.keyIdentifier] = sides.kek;
            wrapWrapperHierarchy(input, settings: schema, files: &packageIndex.files, directories: &packageIndex.directories);
            
            let wrappedIndex = try self.wrap(data: packageIndex.serialize(),
                                             recipients: recipients,
                                             options: [options, .contentIsXML]);
            var resultItems : [String:FileWrapper] = [:];
            resultItems[OFCMSFileWrapper.indexFileName] = FileWrapper(regularFileWithContents: wrappedIndex);
            
            for (obscuredName, wrapper) in sideFiles {
                let wrappedData = try self.wrap(data: wrapper.regularFileContents!, recipients: [sides], options: options);
                let sideFile = FileWrapper(regularFileWithContents: wrappedData);
                sideFile.preferredFilename = obscuredName;
                resultItems[obscuredName] = sideFile;
            }
            
            let result = FileWrapper(directoryWithFileWrappers: resultItems);
            result.fileAttributes = input.fileAttributes;
            return result;
        } else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil /* TODO: Better error for this should-never-happen case? */)
        }
    }
    
    /** Generates a random filename of a given length. */
    private static 
    func generateCrypticFilename(ofLength nlen: Int) -> String {
        var r : UInt32 = 0;
        var cs = Array(repeating: UInt8(0), count: nlen);
        let ch : [UInt8] = [ 0x49, 0x6C, 0x4F, 0x30, 0x31 ];
        for i in 0 ..< nlen {
            if i % 12 == 0 {
                r = OFRandomNext32();
            }
            
            var v : Int;
            if i == 0 || i == (nlen - 1) {
                v = Int(r & 0x01);
                r = r >> 1;
            } else {
                v = Int(r % 5);
                r = r / 5;
            }
            
            cs[i] = ch[v];
        }
        
        return String(bytes: cs, encoding: String.Encoding.ascii)!;
    }
    
    private func missingFileError(filename: String) -> NSError {
        let msg = NSString(format: NSLocalizedString("The encrypted item \"%@\" is missing or unreadable.", tableName: "OmniFoundation", bundle: OFBundle, comment: "Document decryption error message - a file within the encrypted file wrapper can't be read") as NSString,
                           filename) as String;
        return NSError(domain: OFErrorDomain,
                       code: OFEncryptedDocumentFormatError,
                       userInfo: [ NSLocalizedFailureReasonErrorKey: msg ]);
    }
    
    func unwrap(input: FileWrapper) throws -> FileWrapper {
        
        if input.isRegularFile {
            guard let encryptedData = input.regularFileContents else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
            }
            let decryptedData = try self.unwrap(data: encryptedData);
            recipientsFoo = decryptedData.allRecipients;
            usedRecipient = decryptedData.usedRecipient;
            let unwrapped = FileWrapper(regularFileWithContents: decryptedData.content());
            if let fname = input.preferredFilename {
                unwrapped.preferredFilename = fname;
            }
            unwrapped.fileAttributes = input.fileAttributes;
            return unwrapped;
        } else if input.isDirectory {
            guard let encryptedFiles = input.fileWrappers else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
            }
            
            guard let indexFile = encryptedFiles[OFCMSFileWrapper.indexFileName],
                  indexFile.isRegularFile,
                  let indexFileContents = indexFile.regularFileContents else {
                throw missingFileError(filename: OFCMSFileWrapper.indexFileName);
            }
            
            let decryptedIndexFile = try self.unwrap(data: indexFileContents);
            recipientsFoo = decryptedIndexFile.allRecipients;
            usedRecipient = decryptedIndexFile.usedRecipient;
            let indexEntries = try PackageIndex.unserialize(decryptedIndexFile.content());
            
            var resultItems : [String : FileWrapper] = [:];

            func recreateWrapperHierarchy(files: [PackageIndex.FileEntry], directories: [PackageIndex.DirectoryEntry]) throws -> FileWrapper {
                var resultItems : [String : FileWrapper] = [:];
                for dent in directories {
                    resultItems[dent.realName] = try recreateWrapperHierarchy(files: dent.files, directories: dent.directories);
                }
                for fent in files {
                    guard let dataFile = encryptedFiles[fent.storedName] else {
                        if fent.options.contains(OFCMSOptions.fileIsOptional) {
                            continue;
                        } else {
                            throw missingFileError(filename: fent.storedName);
                        }
                    }
                    
                    guard dataFile.isRegularFile,
                          let fileData = dataFile.regularFileContents else {
                            throw missingFileError(filename: fent.storedName);
                    }
                    let unwrappedFileData = try self.unwrap(data: fileData, auxiliaryKeys: indexEntries.keys).content();
                    resultItems[fent.realName] = FileWrapper(regularFileWithContents: unwrappedFileData);
                }
                return FileWrapper(directoryWithFileWrappers: resultItems);
            }
            
            return try recreateWrapperHierarchy(files: indexEntries.files, directories: indexEntries.directories);
        } else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
        }
    }
    
    private func wrap(data input_: Data, recipients: [CMSRecipient], options: OFCMSOptions) throws -> Data {
        
        let input = input_;
        let contentType = (options.contains(.contentIsXML) ? OFCMSContentType_XML : OFCMSContentType_data);
        
        //        if options.contains(Options.Compress) {
        //            input = OFCMSCompressContent(input) as! NSData;
        //            contentType = OFCMSContentType_compressedData;
        //        }
        
        let cek = NSData.cryptographicRandomData(ofLength: 32);
        let rinfos = try recipients.map( { (recip) -> Data in try recip.recipientInfo(wrapping: cek) } );
        
        var envelope : Data;
        var envelopeType : OFCMSContentType;
        
        if !options.contains(.withoutAEAD) {
            var error : NSError? = nil;
            guard let enveloped_ = OFCMSCreateAuthenticatedEnvelopedData(cek, rinfos, [], contentType.asDER(), input, nil, &error) else {
                throw error!;
            }
            envelope = OFNSDataFromDispatchData(enveloped_);
            envelopeType = OFCMSContentType_authenticatedEnvelopedData;
        } else {
            var error : NSError? = nil;
            guard let enveloped_ = OFCMSCreateEnvelopedData(cek, rinfos, contentType.asDER(), input, &error) else {
                throw error!;
            }
            envelope = OFNSDataFromDispatchData(enveloped_);
            envelopeType = OFCMSContentType_envelopedData;
        }
        
        return OFNSDataFromDispatchData(OFCMSWrapContent(envelopeType.asDER(), envelope));
    }
    
    private func unwrap(data input_: Data, auxiliaryKeys: [Data: Data] = [:]) throws -> OFCMSUnwrapper {
        
        let decr = try OFCMSUnwrapper(data: input_, keySource: delegate);
        
        if !auxiliaryKeys.isEmpty {
            decr.addSymmetricKeys(auxiliaryKeys);
        }
        if !auxiliaryAsymmetricKeys.isEmpty {
            decr.addAsymmetricKeys(auxiliaryAsymmetricKeys);
        }
        
        try decr.peelMeLikeAnOnion();
        switch decr.contentType {
        case OFCMSContentType_data, OFCMSContentType_XML:
            return decr;
        default:
            throw NSError(domain: OFErrorDomain,
                          code: OFUnsupportedCMSFeature,
                          userInfo: [NSLocalizedFailureReasonErrorKey: NSLocalizedString("Unexpected content-type", tableName: "OmniFoundation", bundle: OFBundle, comment: "Document decryption error - unexpected CMS content-type found while unwrapping")]);
        }
    }
    
    private struct PackageIndex {
        
        struct FileEntry {
            let realName: String;
            let storedName: String;
            let options: OFCMSOptions;
            
            func serialize(into elt: OFXMLMakerElement) {
                let felt = elt.openElement("file")
                              .addAttribute("name", value: realName)
                              .addAttribute("href", xmlns: xLinkNamespaceURI, value: storedName);
                if options.contains(OFCMSOptions.fileIsOptional) {
                    felt.addAttribute("optional", value: "1");
                }
                felt.close();
            }
        }
        
        struct DirectoryEntry {
            let realName: String;
            let files : [FileEntry];
            let directories : [DirectoryEntry];
            
            func serialize(into elt: OFXMLMakerElement) {
                let dirElt = elt.openElement("directory").addAttribute("name", value: realName);
                for fileEntry in files {
                    fileEntry.serialize(into: dirElt);
                }
                for subDirectory in directories {
                    subDirectory.serialize(into: dirElt);
                }
                dirElt.close();
            }
        }
        
        var files : [FileEntry] = [];
        var keys : [Data : Data] = [:];
        var directories : [DirectoryEntry] = [];
        
        func serialize() throws -> Data {
            let strm = OutputStream(toMemory: ());
            let sink = OFXMLTextWriterSink(stream: strm)!;
            let doc = sink.openElement("index", xmlns: encryptedContentIndexNamespaceURI, defaultNamespace: encryptedContentIndexNamespaceURI);
            doc.prefix(forNamespace:xLinkNamespaceURI, hint: "xl");
            
            for (keyIdentifier, keyMaterial) in self.keys {
                doc.openElement("key")
                    .addAttribute("id", value: (keyIdentifier as NSData).unadornedLowercaseHexString())
                    .add(string: (keyMaterial as NSData).unadornedLowercaseHexString())
                    .close();
            }
            
            for d in self.directories {
                d.serialize(into: doc);
            }
            
            for entry in self.files {
                entry.serialize(into: doc);
            }
            
            doc.close();
            sink.close();
            
            if let bufferError = strm.streamError {
                throw bufferError;
            }
            
            let v = strm.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey);
            
            return (v as? Data) ?? Data();  // RADAR 6160521
        }
        
        static func unserialize(_ input: Data) throws -> PackageIndex {
            let reader = try OFXMLReader(data: input);
            guard let rtelt = reader.elementQName() else {
                throw NSError(domain: OFErrorDomain, code: OFXMLDocumentNoRootElementError, userInfo: nil);
            }
            guard rtelt.name == "index", rtelt.namespace == encryptedContentIndexNamespaceURI else {
                throw NSError(domain: OFErrorDomain, code: OFEncryptedDocumentFormatError, userInfo: [
                    NSLocalizedFailureReasonErrorKey: "Incorrect root element: \(rtelt.shortDescription())"
                    ]);
            }
            
            var files : [PackageIndex.FileEntry] = [];
            var keys : [Data:Data] = [:];
            var directories : [DirectoryEntry] = [];
            
            let fileNameAttr = OFXMLQName(namespace: nil, name: "name");
            let fileLocationAttr = OFXMLQName(namespace: xLinkNamespaceURI, name: "href");
            let fileOptionalAttr = OFXMLQName(namespace: nil, name: "optional");
            let keyIdAttr = OFXMLQName(namespace: nil, name: "id");
            
            try reader.openElement();
            var currentElementName = reader.elementQName();
            var directoryStack : [DirectoryEntry] = [];
            
            while true {
                try reader.findNextElement(&currentElementName);
                guard let elementName = currentElementName else {
                    // Nil indicates end of enclosing element. In theory the only elements we should be entering are the toplevel element and any <directory/> elements.
                    if let dent = directoryStack.popLast() {
                        // We abuse the DirectoryEntry type slightly here: its name field contains the name of the dierctory we were just scanning, but its other fields are the saved state from its own containing directry.
                        let newSubdirectory = DirectoryEntry(realName: dent.realName, files: files, directories: directories);
                        files = dent.files;
                        directories = dent.directories;
                        directories.append(newSubdirectory);
                        try reader.closeElement();
                        continue;
                    } else {
                        // Done with the index.
                        break;
                    }
                }
                
                if elementName.name == "file" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    var memberName : NSString?;
                    var memberLocation : NSString?;
                    var memberOptionality: NSString?;
                    memberName = nil;
                    try reader.copyValue(ofAttribute: &memberName, named: fileNameAttr);
                    memberLocation = nil;
                    try reader.copyValue(ofAttribute: &memberLocation, named: fileLocationAttr);
                    memberOptionality = nil;
                    try reader.copyValue(ofAttribute: &memberOptionality, named: fileOptionalAttr);
                    guard let memName = memberName as String?,
                          let memLoc = memberLocation as String? else {
                            throw NSError(domain: OFErrorDomain, code: OFEncryptedDocumentFormatError, userInfo: [
                                NSLocalizedFailureReasonErrorKey: "Missing <file> attribute"
                                ]);
                    }
                    var memberOptions : OFCMSOptions = [];
                    if let optionality = memberOptionality, optionality.boolValue {
                        memberOptions.formUnion(OFCMSOptions.fileIsOptional);
                    }
                    files.append(PackageIndex.FileEntry(realName: memName, storedName: memLoc, options: memberOptions));
                    try reader.skipCurrentElement();
                } else if elementName.name == "key" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    var keyName : NSString? = nil;
                    var keyValue = nil as NSString?;
                    try reader.copyValue(ofAttribute: &keyName, named: keyIdAttr);
                    try reader.openElement();
                    try reader.copyStringContents(toEndOfElement: &keyValue);
                    guard let keyNm = keyName as String?, let keyVl = keyValue as String? else {
                        throw NSError(domain: OFErrorDomain, code: OFEncryptedDocumentFormatError, userInfo: [
                            NSLocalizedFailureReasonErrorKey: "Missing <key> attribute"
                            ]);
                    }
                    do {
                        keys[ try NSData(hexString:keyNm) as Data ] = try NSData(hexString: keyVl) as Data;
                    } catch let e as NSError {
                        throw NSError(domain: OFErrorDomain, code: OFEncryptedDocumentFormatError, userInfo: [NSUnderlyingErrorKey: e]);
                    }
                } else if elementName.name == "directory" && elementName.namespace == encryptedContentIndexNamespaceURI {
                    var memberName : NSString?;
                    memberName = nil;
                    try reader.copyValue(ofAttribute: &memberName, named: fileNameAttr);
                    guard let dirName = memberName as String? else {
                        throw NSError(domain: OFErrorDomain, code: OFEncryptedDocumentFormatError, userInfo: [
                            NSLocalizedFailureReasonErrorKey: "Missing <directory> attribute"
                            ]);
                    }
                    
                    directoryStack.append(DirectoryEntry(realName: dirName, files: files, directories: directories));
                    files = [];
                    directories = [];
                    try reader.openElement();
                } else {
                    // Ignore unknown tags.
                    try reader.skipCurrentElement();
                }
            }
            
            return PackageIndex(files: files, keys: keys, directories: directories);
        }
    }
}

private extension FileWrapper {
    func countRegularFiles() -> UInt {
        var nameCount : UInt = 0;
        
        do {
            var wrappersToCount : [FileWrapper] = [self];
            
            repeat {
                if let entries = wrappersToCount.popLast()?.fileWrappers {
                    for (_, w) in entries {
                        if w.isRegularFile {
                            nameCount += 1;
                        } else if w.isDirectory {
                            wrappersToCount.append(w);
                        }
                    }
                }
            } while !wrappersToCount.isEmpty;
        };

        return nameCount;
    }
}

