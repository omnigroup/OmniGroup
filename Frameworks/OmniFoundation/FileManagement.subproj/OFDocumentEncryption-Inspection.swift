// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation

extension OFDocumentEncryptionSettings {

    /// Returns a short, localized description of a document's encryption state.
    @objc(describeEncryptionSettings:)
    public static func describe(encryptionSettings settings: OFDocumentEncryptionSettings?) -> String {
        if let settings = settings {
            if (settings.hasPassword()) {
                return NSLocalizedString("<Encryption: A password is set>", tableName: "OmniFoundation", bundle: OFBundle, value: "Password Set", comment: "summary text - document is encrypted using a password");
            } else {
                let formatted = NSString(format:NSLocalizedString("<Encryption: using %u key(s)>", tableName: "OmniFoundation", bundle: OFBundle, value: "%u Keys", comment: "summary text - document is encrypted using one or more public keys") as NSString,
                            settings.countOfRecipients() as UInt);
                return formatted as String;
            }
        } else {
            return NSLocalizedString("<Encryption: None>", tableName: "OmniFoundation", bundle: OFBundle, value: "Not Encrypted", comment: "summary text - document is not encrypted");
        }
    }
    
    #if true
    // Work in progress: allow spotlight to index the envelope of an encrypted document (recipients and document-key-UUID)
    @objc(addMetadata:)
    public func addMetadata(to into: NSMutableDictionary) -> () {
    
        if let pwid = self.documentIdentifier {
            into[OFMDItemEncryptionPassphraseIdentifier] = pwid;
        }
        
        var passwords = false;
        var pki = false;
        var emails = [String]();
        var dns = [String]();
        
        func addCertInfo(_ cert: SecCertificate) {
            if let description = SecCertificateCopyLongDescription(kCFAllocatorDefault, cert, nil) {
                dns.append(description as String);
            }
            
            var certEmails : CFArray? = nil;
            if SecCertificateCopyEmailAddresses(cert, &certEmails) == 0 {
                emails.append(contentsOf: certEmails as! [String]);
            }
        }

        for recip in recipients {
            switch recip {
            case _ as CMSPasswordRecipient:
                passwords = true;
            case let pkr as CMSPKRecipient:
                pki = true;
                if let cert = pkr.cert {
                    addCertInfo(cert);
                } else {
                    // rids.add(pkr.rid);
                    break;
                }
            default:
                break;
            }
        }
        
        if (passwords) {
            into[kMDItemSecurityMethod] = "Password Encrypted"; // Magic string from MDItem.h
        } else if (pki) {
            into[kMDItemSecurityMethod] = "Public-Key Encrypted";
        } else {
            into[kMDItemSecurityMethod] = "Encrypted";
        }

        into[OFMDItemEncryptionRecipientCount] = UInt(recipients.count) + unreadableRecipientCount;
    }
    #endif
    
    /// Returns the total number of recipients.
    @objc public
    func countOfRecipients() -> UInt {
        return recipients.count as! UInt;
    }
    
    /// Returns YES if the receiver allows decryption using a password.
    @objc public
    func hasPassword() -> Bool {
        return recipients.contains(where: { $0 is CMSPasswordRecipient });
    }
    
    /// Removes any existing password recipients, and adds one given a plaintext passphrase.
    /// - parameter: The password to set. Pass nil to remove the passphrase.
    @objc public
    func setPassword(_ password: String?) {
        recipients = recipients.filter({ (recip: CMSRecipient) -> Bool in !(recip is CMSPasswordRecipient) });
        if let newPassword = password {
            recipients.insert(CMSPasswordRecipient(password: newPassword), at: 0);
        }
    }
    
    /// Returns YES if the receiver allows decryption using asymmetric cryptography.
    @objc public
    func hasPublicKeyRecipients() -> Bool {
        return recipients.contains(where: { $0 is CMSPKRecipient });
    }
    
    @objc public
    func publicKeyRecipients() -> [CMSRecipient] {
        return recipients.flatMap({ $0 as? CMSPKRecipient });
    }
    
    /// Adds a PK recipient for the supplied certificate. Returns the new recipient, or an existing recipient if there already is one for this certificate.
    @objc public
    func addRecipient(certificate: SecCertificate) -> CMSRecipient? {
        for v in recipients {
            if let pk = v as? CMSPKRecipient {
                if pk.rid.matchesCertificate(certificate) && pk.resolve(certificate: certificate) {
                    return v;
                }
            }
        }

        do {
            let recip = try CMSPKRecipient(certificate: certificate);
            recipients.append(recip);
            return recip;
        } catch {
            debugPrint("Cannot create a recipient for ", certificate);
            return nil;
        }
    }
    
    /// Removes a recipient, returning true if the recipient was found and removed.
    @objc public
    func removeRecipient(_ recip: CMSRecipient) -> Bool {
        var result : Bool = false;
        var ix = recipients.count;
        while ix > 0 {
            ix -= 1;
            if recipients[ix] === recip {
                result = true;
                recipients.remove(at: ix);
            }
        }
        return result;
    }
}

