Title:  Omni Document File Encryption  
Revision: $Id: OFDocumentEncryption.md 276695 2017-01-05 00:24:40Z wiml $

# Document File Encryption

File encryption for Omni document-based applications is based on the [RFC5652][rfc5652] Cryptographic Message Syntax (also sometimes called [PKCS#7][wp-pkcs]).

For documents which would be stored as a simple file on disk, the file is simply encapsulated in CMS, and stored as a single file.

For documents which would be stored as a file package, a file package containing an index file (`index.cms`) and some number of data files is created. The index file contains information about the layout of the (notional) unencrypted file package, as well as temporary subkeys used to encrypt attachment files and which attachments can be found in which encrypted files.

TODO items:
1. Where is a password hint stored? (For packages, we can use .iwph like iWork. For flat files, we may need to define a CMS attribute, or ...?)
2. Where is a document keychain UUID stored? (We can probably use a content-identifier attribute on the outermost item?)

## CMS Profile

The following algorithms and formats are supported:

* CMS Content Types
    * ct-data, [ct-authenticatedEnvelopedData][rfc5083], [ct-XML][rfc5485]: both written and read
    * ct-signedData, ct-envelopedData: can be read, but are not generated. Signatures are not checked on signedData. Empty signedData structures are used to convey certificates.
    * [ct-contentCollection][rfc4073], and ct-contentWithAttributes are used when saving encrypted file packages.
    * [ct-compressedData][rfc3274] may be used in the future but is not currently written.
* CMS Recipient Types
    * [Password recipients][rfc3211] using PBKDF2 with a SHA1, SHA256, or SHA512 PRF and a *non-omitted `keyLength` parameter* (note that the standard [allows omission of this parameter][rfc2898] but we currently require it to be present). The key wrapping algorithm must be [AESWRAP][rfc3565] (PWRI-KEK-AES-CBC is supported in some debug configurations but is not written).
    * Key Transport recipients using RSA keys and PKCS #1 v1.5 padding. RSA-OAEP may be supported in the future. The recipient identifier may be either `IssuerAndSerial` or `SubjectKeyIdentifier`.
    * KEK recipients are used for attachment files in file packages; again, the key wrapping algorithm is AESWRAP.
    * Key Agreement recipients for elliptic-curve keys may be supported in the future but are not currently.
* Symmetric Encryption Algorithms
    * For key wrapping in password or KEK recipients, AESWRAP (128, 192, or 256-bit keys) is used.
        * If PWRI-KEK is supported for reading, the inner algorithm may be AES (128, 192, or 256), or 3DES, all in CBC mode.
    * For authenticated enveloped data:
        * Currently AES-CCM is used both for reading and writing.
        * AES-GCM is not currently supported for reading or writing, but will be once it is supported by Apple.
        * [RFC6476][rfc6476] MAC-based authenticated encryption may be supported in the future.
    * For unauthenticated encrypted data (which is read, but not written), either AES (128, 192, or 256 bit keys) or 3DES (192 bit keys) can be used, in CBC mode.
* Message structure restrictions
    * Cryptographic transforms (e.g. authenticated-enveloped-data) must only appear "outside" of non-cryptographic transforms (such as compression, contentCollection, or contentWithAttributes).
      (When an empty signedData is used to hold a certificate set, it can be inside non-cryptographic transforms; it's treated as a data type in that case.)
    * Indefinite-length encodings are supported for elements that (directly or indirectly) contain message content, but not for many of the other structures, even if not forbidden by the spec.
      Currently, files are always written using definite-length encodings, but that may change.

[wp-pkcs]: https://en.wikipedia.org/wiki/PKCS
[rfc2898]: https://tools.ietf.org/html/rfc2898
[rfc3211]: https://tools.ietf.org/html/rfc3211
[rfc3274]: https://tools.ietf.org/html/rfc3274
[rfc3565]: https://tools.ietf.org/html/rfc3565
[rfc4073]: https://tools.ietf.org/html/rfc4073
[rfc5083]: https://tools.ietf.org/html/rfc5083
[rfc5485]: https://tools.ietf.org/html/rfc5485
[rfc5652]: https://tools.ietf.org/html/rfc5652
[rfc5911]: https://tools.ietf.org/html/rfc5911
[rfc6476]: https://tools.ietf.org/html/rfc6476

## Flat files

Flat files may have some number of password recipients and some number of public-key recipients. When an encrypted file is modified and saved, at most one password recipient will be used (corresponding to whichever password was used to decrypt it).
Likewise, public-key recipients whose public keys we don't have a copy of will be lost on save.

The CMS content-type may be ct-data or ct-XML depending on the underlying document format.

## File packages

An encrypted document which is a file package contains a main file, `contents.cms`, encrypted according to the same rules as a flat file.
It contains an XML document describing the structure of the file package that would have been written if it were not encrypted.

### Package index

The index XML document is in the namespace <`http://www.omnigroup.com/namespace/DocumentEncryption/v1`>. The [XLink][xlink] namespace, <`http://www.w3.org/1999/xlink`>, is also used.

The root element must be `<index>`. It contains the following elements (order is insignificant):

* `<key>` represents a subkey used for an attachment.
    * The `id` attribute is the hexadecimal representation of the `KEKIdentifier.keyIdentifier` octets.
    * The element content is the hexadecimal representation of the KEK.
* `<file>` represents an encrypted file. It has the following attributes:
    * `name`: the plaintext name of the file.
    * `href` (in the XLink namespace): the encrypted file containing this plaintext.
    * `optional`: If present, contains the value `1`, indicating that the file may be deleted from the encrypted document. Without this attribute, if any encrypted files are missing, the document is considered corrupted and unreadable.
* `<directory>`: Represents a subdirectory in the plaintext. The `name` attribute holds the directory's name, and any directory contents are represented as nested `<file>` and/or `<directory>` elements. Empty directories are allowed.

In the future, URL fragment syntax may be used in the `href` attribute to refer to individual documents bundled into one disk file using the ct-contentCollection format. If the `contents.cms` file contains a content collection, the first subdocument is the XML document, and any other subdocuments are referenced to by the index document.

[xlink]: https://www.w3.org/TR/xlink11/
