// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

import Foundation
import XCTest
@testable import OmniFoundation

class blah : OFCMSUnwrapDelegate {
    @objc(promptForPassword:) func promptForPassword() throws -> String {
        var buf = Array(repeating: Int8(0), count: 128);
        let rv = readpassphrase("foo", &buf, buf.count, 0);
        if rv == nil {
            throw NSError(domain: OFErrorDomain, code: OFKeyNotAvailable, userInfo: nil);
        } else {
            guard let str = NSString(bytes: buf, length: Int(strlen(buf)), encoding: String.Encoding.utf8.rawValue) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownStringEncodingError, userInfo: nil);
            }
            guard str.length > 0 else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil);
            }
            return str as String;
        }
    }
}

class OFCMSTest : XCTestCase {
    
    // This is the encoded message from RFC 4134 [5.1]/[5.3].
    let rfc4134_5_3 = "MIIBHgYJKoZIhvcNAQcDoIIBDzCCAQsCAQAxgcAwgb0CAQAwJjASMRAwDgYDVQQDEwdDYXJsUlNBAhBGNGvHgABWvBHTbi7NXXHQMA0GCSqGSIb3DQEBAQUABIGAC3EN5nGIiJi2lsGPcP2iJ97a4e8kbKQz36zg6Z2i0yx6zYC4mZ7mX7FBs3IWg+f6KgCLx3M1eCbWx8+MDFbbpXadCDgO8/nUkUNYeNxJtuzubGgzoyEd8Ch4H/dd9gdzTd+taTEgS0ipdSJuNnkVY4/M652jKKHRLFf02hosdR8wQwYJKoZIhvcNAQcBMBQGCCqGSIb3DQMHBAgtaMXpRwZRNYAgDsiSf8Z9P43LrY4OxUk660cu1lXeCSFOSOpOJ7FuVyU=";
    
    // This is the corresponding certificate for Bob (issuer=carl, sn=46:34:...) certificate from RFC 4134.
    let rfc4134_carl_issued_to_bob = "MIICJzCCAZCgAwIBAgIQRjRrx4AAVrwR024uzV1x0DANBgkqhkiG9w0BAQUFADASMRAwDgYDVQQDEwdDYXJsUlNBMB4XDTk5MDkxOTAxMDkwMloXDTM5MTIzMTIzNTk1OVowETEPMA0GA1UEAxMGQm9iUlNBMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCp4WeYPznVX/Kgk0FepnmJhcg1XZqRW/sdAdoZcCYXD72lItA1hW16mGYUQVzPt7cIOwnJkbgZaTdt+WUee9mpMySjfzu7r0YBhjY0MssHA1lS/IWLMQS4zBgIFEjmTxz7XWDE4FwfU9N/U9hpAfEF+Hpw0b6Dxl84zxwsqmqn6wIDAQABo38wfTAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIFIDAfBgNVHSMEGDAWgBTp4JAnrHggeprTTPJCN04irp44uzAdBgNVHQ4EFgQU6PS4Z9izlqQq8xGqKdOVWoYWtCQwHQYDVR0RBBYwFIESQm9iUlNBQGV4YW1wbGUuY29tMA0GCSqGSIb3DQEBBQUAA4GBAHuOZsXxED8QIEyIcat7QGshM/pKld6dDltrlCEFwPLhfirNnJOIh/uLt359QWHh5NZt+eIEVWFFvGQnRMChvVl52R1kPCHWRbBdaDOS6qzxV+WBfZjmNZGjOd539OgcOyncf1EHl/M28FAK3Zvetl44ESv7V+qJba3JiNiPzyvT";

    // And Bob's private key
    let rfc4134_bob_private = "MIICXAIBAAKBgQCp4WeYPznVX/Kgk0FepnmJhcg1XZqRW/sdAdoZcCYXD72lItA1hW16mGYUQVzPt7cIOwnJkbgZaTdt+WUee9mpMySjfzu7r0YBhjY0MssHA1lS/IWLMQS4zBgIFEjmTxz7XWDE4FwfU9N/U9hpAfEF+Hpw0b6Dxl84zxwsqmqn6wIDAQABAoGAZ81ITJoNj5jCG2X/IoOcbfCmBh287acDiJTyHGsPizXeDoJ4MMvnumpWrXfG61F5cHkKoPT+ReCpsvQZ2oeY1jCEdOT8WWzBxnfcqZHQfDCgosUIXiFxQ/wNBz3w+m0Unk5j8BdYeRxLmBw9PbAb3/olO6PALJgF9hAJ2IfbAxkCQQDQwyLG3qKZGHaPjbymddZmP9SNRVKMdvVyxOvwRprxPlyqVQub2t1rbfj8OzwIQ5O1W/7O6v1ohCNir/MxwrnlAkEA0FH8HiK3W+21jgHI16vyWNT3gpTzU6gZRctmyigZX+IQK/OP7GowdPhNEfSnxCC1RyHcSQH5CiAp8CQIhGB9jwJANLpkyUgoV3TXVVDeakjvGypaHEh7HiFZw2A7m5epwO8YZqlOYlI4hM7lCYhIlGnFIBSZWlf+I2zkpyN70IC3hQJBAJ4vszea+wsGXVfhCQakXdmQlgYFXyQGQHKcOoiFnIcPnWISiBZoqDUaG0PoOMCYaa8DCkgyBE7pD493fTQwJQcCQFcYZ9YK0rWrwrp651TanAVPgdTvAYkeMj1pyzHEUshUVSUAOxwqfCZQ1emm13fLzxX17gvVje6zr0yhfGNGQfY=";
    
    func testPasswordRecipients() throws {
        
        let test_password : NSString = "hello";
        
        let cek = NSData.cryptographicRandomData(ofLength: 32);
        let ri = CMSPasswordRecipient(password: test_password);
        let rinfo = try ri.recipientInfo(withCEK: cek);
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFASN1RecipientType = OFCMSRUnknown;
        let err = OFASN1ParseCMSRecipient(rinfo, &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRPassword);

        let ri_out = CMSPasswordRecipient(info: who! as Data);
        let cek_out = try ri_out.unwrap(password: test_password, data: what! as Data);
        
        XCTAssertEqual(cek, cek_out);
    }
    
    func testPKRecipient4134() throws {
        let message = NSData(base64Encoded: rfc4134_5_3, options: []);
        let ri = message?.subdata(with: NSRange(location: 29, length: 192));
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFASN1RecipientType = OFCMSRUnknown;
        let err = OFASN1ParseCMSRecipient(ri, &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRKeyTransport);
        
        let rid = try CMSRecipientIdentifier.fromDER(who! as Data);
        guard case CMSRecipientIdentifier.issuerSerial(let issu, let sn) = rid else {
            XCTAssert(false, "Parsed rid is not an issuerAndSerial");
            return;
        }
        
        try XCTAssertEqual(sn, NSData(hexString:"46346BC7800056BC11D36E2ECD5D71D0"));
        
        let parsable = OFASN1EnumerateAVAsInName(issu, { (attr, val, rdnseq, _) -> ()
            in
            XCTAssertEqual(attr, try! NSData(hexString:"550403"));
            XCTAssertEqual(OFASN1UnDERString(val), "CarlRSA");
            XCTAssertEqual(rdnseq, 0);
        });
        XCTAssertTrue(parsable, "OFASN1EnumerateAVAsInName");
        
        guard let cert = SecCertificateCreateWithData(kCFAllocatorDefault, NSData(base64Encoded: rfc4134_carl_issued_to_bob, options: [])!) else {
            XCTAssert(false, "SecCertificateCreateWithData");
            return;
        }
        XCTAssertTrue(rid.matchesCertificate(cert));
        
        let bobpriv = NSData(base64Encoded: rfc4134_bob_private, options: [])! as Data;
        guard let foo = OFSecCopyPrivateKeyFromPKCS1Data(bobpriv) else {
            XCTAssertTrue(false, "OFSecCopyPrivateKeyFromPKCS1Data");
        }
        
        let cek = try CMSPKRecipient(rid: rid).unwrap(privateKey: foo, data: what!);
        debugPrint(cek);
    }
    
    #if DEBUG_wiml || DEBUG_wimlocal
    func testRFC3211Recipients() throws {
        
        // Test data from RFC3211, with two changes:
        // - The outer tag's length has been corrected from 96 to 111 (and then to 114, because of the below)
        // - The implicit PBKDF2 output length has been replaced with an explicit one (we don't support the implicit length)
        let example_page11 : [UInt8] = [
            0xA3,  114,
            0x02,    1, 0x00,
            0xA0,   30,
            0x06,    9, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C,
            0x30,   17,
            0x04,    8, 0x12, 0x34, 0x56, 0x78, 0x78, 0x56, 0x34, 0x12,
            0x02,    2, 0x01, 0xF4,
            0x02,    1, 0x18,
            0x30,   35,
            0x06,   11, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x03, 0x09,
            0x30,   20,
            0x06,    8, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x07,
            0x04,    8, 0xBA, 0xF1, 0xCA, 0x79, 0x31, 0x21, 0x3C, 0x4E,
            0x04,   40,
                        0xC0, 0x3C, 0x51, 0x4A, 0xBD, 0xB9, 0xE2, 0xC5,
                        0xAA, 0xC0, 0x38, 0x57, 0x2B, 0x5E, 0x24, 0x55,
                        0x38, 0x76, 0xB3, 0x77, 0xAA, 0xFB, 0x82, 0xEC,
                        0xA5, 0xA9, 0xD7, 0x3F, 0x8A, 0xB1, 0x43, 0xD9,
                        0xEC, 0x74, 0xE6, 0xCA, 0xD7, 0xDB, 0x26, 0x0C
        ];
        let cek_page11 : [UInt8] = [
            0x8C, 0x63, 0x7D, 0x88, 0x72, 0x23, 0xA2, 0xF9,
            0x65, 0xB5, 0x66, 0xEB, 0x01, 0x4B, 0x0F, 0xA5,
            0xD5, 0x23, 0x00, 0xA3, 0xF7, 0xEA, 0x40, 0xFF,
            0xFC, 0x57, 0x72, 0x03, 0xC7, 0x1B, 0xAF, 0x3B
        ];
        
        var who : NSData? = nil;
        var what : NSData? = nil;
        var recipientType : OFASN1RecipientType = OFCMSRUnknown;
        let err = OFASN1ParseCMSRecipient(Data(bytes: example_page11), &recipientType, &who, &what);
        if let err = err {
            throw err;
        }
        XCTAssertEqual(recipientType, OFCMSRPassword);
        
        let ri_out = CMSPasswordRecipient(info: who!);
        let cek_out = try ri_out.unwrap("All n-entities must communicate with other n-entities via n-1 entiteeheehees", data: what!);
        
        XCTAssertEqual(Data(bytes: cek_page11), cek_out);
    }
    #endif
    
    #if false
    // This test requires some way to supply the RFC4134 certificates and private keys to OFCMSUnwrapper.
    // We may want to add that to the delegate protocol.
    func testRFC4134() throws {
        let message = NSData(base64EncodedString: rfc4134_5_3, options: NSDataBase64DecodingOptions(rawValue: 0));
        let delegate = blah();
        
        let decr = try OFCMSUnwrapper(data: message!, delegate: delegate);
        XCTAssertEqual(decr.contentType, OFCMSContentType_envelopedData);
        
    }
    #endif
    
}

