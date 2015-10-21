OmniFileStore Encryption Design
===============================

File version: $Id$

This file documents the formats and motivations for the encryption
formats used by OmniFileStore.

The purpose of this encryption mechanism is to provide confidentiality
and integrity (but not necessarily authentication) for some number of
*documents*, each of which is manipulated by possibly many
*devices*. A document contains a number of *files*. For example, an
OmniFocus database is one document, with each transaction being a
file. Each instance of OmniFocus that syncs with that database is a distinct
device. Most of the time, a given file is written once and read many
times but not modified after writing.

The design is broken into three parts:

* Individual file encryption. Encrypts an individual file, given a
  key provided by the document key management system.
* Document key management. Allows a device to obtain a files' keys given
  a password or other authenticator.
* Group membership. A non-password-based authentication method for
  document keys.


Threat model
------------

An attacker is assumed to be able to read the stored files repeatedly over time. This may leak activity information (frequency and size of changes) but shouldn't leak any contents.

(Concern: Some content information can be leaked by traffic analysis *a la* CRIME, because we compress stuff.)

An attacker may gain access to a device and/or old password after that
device has been removed from access (eg via a password change). In
that case, the attacker should have no access to changes made after
the password change, but may have access to *some* (how many?) changes
made before the password change (e.g. as if there were a decrypted
snapshot on the device- which in fact there is anyway, so we're not
losing anything here). An attacker should not have unlimited ability
to decrypt data snapshots from the distant past if a current password
is compromised, or current/future snapshots if a password from the
distant past is compromised.

We provide only weak protection against an attacker who can modify the files:

Administrators should be able to roll a document back to a previous
state without having access to any document keys.

We do not currently have any integrity checks on the *set of files*
available, although individual files' integrity is checked.

Concern: Depending on our implementation of 'write-only' access, an attacker
may be able to add arbitrary files, in which case they are probably
able to *replace* arbitrary files with content of their choosing; if
so this makes our file integrity fairly weak (but still prevents an
attacker from replacing part of a file while leaving the rest
unchanged).

Concern: We don't authenticate (or encrypt) filenames at all, currently. Should we? They are significant for both OF and OP.

Document Key Management
-----------------------

This is only partly fleshed out. Document key management must provide
the following functions:

* Given a key index, provide a file key.
* Create new file keys as needed, and garbage-collect old ones when no longer used.
* The information needed to do the above will be protected using a passphrase.

Group Membership
----------------

This is future work. I envision each client having an asymmetric
keypair, and engaging in some very simple group membership protocol
with other devices in order to produce key(s) which are accessible
only to members of the group. Those keys would then be used to unlock
document key management blobs as needed, instead of using a shared
passphrase.

Concrete File Formats
=====================

Segmented (Random-Access) File Encryption
-----------------------------------------

Implemented by OFSSegmentedEncryption.{h,m}

This format was designed for on-disk encryption of local content,
which requires the ability to efficiently read subranges of the encrypted data
and to write the file out-of-order.
It might be overkill for encryption of server-stored data; see 'Non-Segmented File Encryption' below.

A file consists of:

* Fixed-length header containing magic number and key index
    * File magic (currently "OmniFileStore Encryption STRAWMAN-4\\n", will change repeatedly until finalized)
    * Key information length (2 bytes, size of next section not including padding)
* File keys, encrypted using document key
    * Key index (2 bytes). Selects a document key for unwrapping the file key.
    * Encrypted file key, wrapped using RFC3394 AESWRAP. Contains:
        * AES key ( kCCKeySizeAES128 = 16 bytes)
        * HMAC key ( SEGMENTED\_MAC\_KEY\_LEN = 16 bytes )
        * Zero-padding to boundary as needed by AESWRAP
    * Padding to a 16-byte boundary. Must be zero; must be checked by reader.
* Variable-length array of encrypted segments
    * Segment IV (12 bytes = block size minus the 32-bit AES-CTR counter)
    * Segment MAC (20 bytes)
    * Segment data (SEGMENTED\_PAGE\_SIZE = 64k bytes, except possibly for the last segment)
* Trailer
    * File HMAC: (SEGMENTED\_FILE\_MAC\_LEN = 32 bytes) computed over a version identifier and the segment MACs.

The file MAC is the HMAC-SHA256 of  ( SEGMENTED\_INNER\_VERSION || segment\_mac\_0 || segment\_mac\_1 ... ) (all of the segment MACs in sequence)

The data is AES-CTR encrypted with initial IV of ( IV || zeroes ) as is normal for CTR mode.

The segment MAC is the truncated HMAC-SHA256 of ( IV || segment number || encrypted data ) where the segment number is a 32-bit number.

### Motivations ###

The segment IV and MAC add to a multiple of 16 bytes for alignment purposes.

Most files are quite short (less than 1kB), so the format should be reasonably compact in that case. But some files are large (~ 1GB).

It's assumed that in the normal case, all files will be encrypted with the same document key (will have the same key index). During a key rollover, new files will have a new index and the old key will be retained only for reading pre-rollover files until they are deleted or reëncrypted.

(Concern: This requires us to garbage-collect old document keys. This is okay for OmniFocus, since a compaction happens regularly and we touch and re-encrypt all files when that happens. This might not be practical for OmniPresence however.)

A file is "random access" in two ways:

One, it must be possible to read only a subrange of a large file. This
allows OmniFocus to read only the XML transaction data from a
transaction without loading the attachments into memory on a
memory-constrained iDevice (or to read only one of potentially many
large attachments). AES-CTR allows this, and the segmenting allows the
integrity of the portions being read to be checked without pulling the
whole thing into memory.
(Concern: Would a Merkle tree buy us anything here? It would complicate the logic that computes the location of a file segment for a given plaintext offset.)
(Concern: Would a mode like XTS be better? The main motivation for such modes is to avoid any ciphertext expansion, but a small amount of expansion is OK for us.)

Two, when a transaction is being written to local disk, the format of the .ZIP
archive requires that each item header be written after the item
itself; this means we have to seek back and fill in holes in the file.
(This is the main reason for having a per-segment IV; otherwise updating a segment would imply reusing an IV.)
However, this isn't necessary for encrypting remote databases since we always write out the file to be uploaded before uploading it; we could use one-pass encryption.

Algorithm choice: AES+HMAC is easy to implement using the primitives
available on OSX and iOS. If Apple provided an AES-GCM implementation
we could use that instead of AES+HMAC, but AES+HMAC is probably
preferable to bundling our own GCM implementation. If we were to
bundle our own, would a completely different choice like ChaCha+Poly
be even better?  AES has the advantage of being boring. How well-regarded
are chacha/salsa/poly1305 outside of the djb fan club, anyway?

The IV is constructed from some random bytes and a per-AES-key counter to eliminate the possibility of nonce reuse, but that's an implementation detail.
(Concern: We currently generate IVs as a combination of random data and a monotonic counter; this means that the order of blocks written is visible in the encrypted file. This probably reveals no useful information, but we could pass the counter through a guaranteed-1:1 transformation, [see][ro1])
 
NOTE: The segment MAC prevents many modifications of the ciphertext,
but it is possible to truncate the file to a segment boundary without
detection. For that, the file MAC is used: it is simply the
HMAC-SHA256 of all the segments' MACs.


### Questions ###

Concern: Since we have variable-length segments, should we include the segment length in the segment HMAC? I don't think this protects us from anything that the HMAC construction itself doesn't protect us from, but adding more fields here is cheap, so why not?

Concern: Should we include e.g. the file header in the file MAC? It
may be desirable to be able to rewrite the wrapped file key with one
wrapped with a different key (e.g., rewriting a downloaded file to be
encrypted with a local key; or rewriting a file written with a special
write-only key to use the normal key.)

Concern: Is the version number in the wrapped blob needed? Should we
just produce a new file magic for any version changes, or tie the version information to a key slot?

Question: We have two encryption formats in this file: AES-CTR-HMAC, and AESWRAP. AESWRAP was designed for the exact purpose we're using it for, but is an old design. Should we use CTR-HMAC for everything instead for simplicity? (On the other hand, AESWRAP is available in CommonCrypto on both OSX and iOS.)

Non-Segmented File Encryption
-----------------------------

If we don't require random read access, it might be possible to use a
standard encryption container like PBE (PKCS#5) CMS (PKCS#7), or PGP's
symmetric mode. (Are there more modern options than CMS?)

CMS does support AES-CGM and -CCM, which allow random read access but
not incremental integrity checks. But it's not unreasonable to do a
full integrity check on any file downloaded during a sync, and we can
either store it decrypted locally (relying on Data Protection or
FileVault), or re-encrypt into a random-access format.

A non-segmented format might be worthwile if it allows us to use a well-defined industry standard format, but otherwise the advantage seems small.

Document Key Management
-----------------------

For the initial, password-based version of this feature, the document
key management file provides the connection from a user's passphrase
to a document key.

The key management file is named "encrypted" and is a plist containing
an array of dictionaries. Each dictionary represents a means for
deriving a key.

In the current implementation we can't do key rollover, so there is
only one key, the key with index 0. In the future, we plan for there
to be a single "current key", with possibly oter keys available (see
under Work to do).

There are three derivation methods:

"method = static": For testing, the key can simply be stored in plaintext as a data under the key "key".

"method = password": The document key is wrapped using a PBKDF2-derived key. The other dictionary keys are "algorithm" (always "PBKDF2; aes128-wrap"); "rounds", "salt", "prf" (the PBKDF2 parameters); and "key" (the AES128-wrapped document key).

"method = keychain": For local storage, and not useful for networked stores. The "item" key contains the persistent identifier for a keychain item which should be the document key.


Work to do
==========

Multiple key slots
------------------

For rollover and multiple key-type support (see below), we'll want to
be able to have more than one key active at once.

Rollover should be triggered by any password change, and if group
management is implemented, should be triggered whenever anyone leaves
the group.

Approach 1: Old keys can simply be stored in the key management blob
encrypted using the current key. However an attacker with
regular snapshots would be able to walk backwards in time and decrypt
arbitrarily far back if a current passphrase / group membership is
compromised.

Approach 2: All keys are encrypted using the current authentication
mechanism (and are re-wrapped with new keys after a password change);
senescent keys contain some marker or other. This makes unlocking a
document more expensive.

Approach 3: Introduce yet another layer of key indirection (a document
master key) which only wraps lists of document sub-keys, which are
then accessed by index to unwrap individual files' file keys.

'Write-only' keys
-----------------

Both Quick Entry and MailDrop would benefit from being able to encrypt
a file and add it to a document without having decryption access. The
obvious solution would be for some key slots to contain a
public/private keypair, with the public half unencrypted.

On the other hand, allowing unauthenticated writers to add files to
the document might be dangerous, in which case QE and MD would need to
contain some less-capable key which can encrypt and authenticate new
data, but not decrypt existing data. This depends on our threat model.

Any specialized keys for these purposes can simply live in their own
key slots.

Key escrow
----------

Some users may want to be able to encrypt a document key to a keypair
they do not have online access to, for recovery, business continuity,
auditing, etc. This presents a problem: the rollover scheme is
supposed to ensure that there is no secret information with unlimited
lifetime (that is, all keys are eventually rotated out of use) which
means that escrow can't be done by simply encrypting something and
filing the result. Escrow may have to be performed by including an
escrow public key in the document key management blob, along with an
authenticator (HMAC using the current document key?) and encrypted
copies of all current document keys.

Password (and other authenticator) changes
------------------------------------------

The format allows the document to have multiple access methods (password, keychain, group membership) and for it to be usable by a device which can use *any* of them. But key rollover and special-purpose (eg write-only) keys would require a device to be able to write new keys to new key slots, which they can't do unless they can use *all* access methods defined in the document management blob. Does this mean we should drop the multiple-access-method feature? It's mostly there for development and testing, really.

Concern: If an attacker can append a new, weak access method, a client could give the attacker access at the next key rollover. So unless we can cross-authenticate access methods we should have only one. Maybe this means that any multiple-access-method support logically belongs in the group management layer (which already has to be able to do cross authentication & authorization among group members).

[ro1]: https://www.voltage.com/wp-content/uploads/UCSD_Rogaway_Synopsis_Format_Preserving_Encyption-1.pdf
