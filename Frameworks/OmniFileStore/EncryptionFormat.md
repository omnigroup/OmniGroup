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
* Document key management. Allows a device to obtain a file's keys given
  a password or other authenticator for its document.
* Group membership. A non-password-based authentication method for
  document keys. (Future work.)


Threat model
------------

An attacker is assumed to be able to read the stored files repeatedly at any time.
This may leak activity information (frequency and size of changes) but shouldn't leak any contents.

(Concern: Some content information can be leaked by traffic analysis *a la* CRIME, because we compress stuff.
Combined with Mail Drop, this could allow an all-observing attacker to probe for specific text in a user's database.)

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

Concern: Depending on our implementation of a future 'write-only'
access feature (for e.g. MailDrop), an attacker may be able to add
arbitrary files, in which case they are probably able to *replace*
arbitrary files with content of their choosing; if so this makes our
file integrity fairly weak (but still prevents an attacker from
replacing part of a file while leaving the rest unchanged).

Concern: We don't authenticate (or encrypt) filenames at all, currently. Perhaps we should: They are significant for both OF and OP. See 'Filename Integrity Check', below.

Document Key Management
-----------------------

Document key management provides the following functions:

* Given a key index (a small integer), provide a file key (128 or 256 bits of AES key and MAC key).
* Create new file keys as needed, rotate them into use, and garbage-collect old ones when no longer used. This will require hooks into the application which is using OmniFileStore.
* Maintain policy for which files within the document need to be encrypted (see Unencrypted Files, below).
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

Implemented by `OFSSegmentedEncryption.{h,m}`

This format was designed for on-disk encryption of local content,
which requires the ability to efficiently read subranges of the encrypted data
and to write the file out-of-order.
It might be overkill for encryption of server-stored data; see 'Non-Segmented File Encryption' below.

A file consists of:

* Fixed-length header containing magic number and key index
    * File magic (currently "OmniFileStore Encryption\0STRAWMAN-6", will change repeatedly until finalized)
    * Key information length (2 bytes, size of next section not including padding)
* File keys, encrypted using document key
    * Key index (2 bytes). Selects a document key for unwrapping the file key.
    * Remaining contents of this section depend on the type of the key selected by the key index.
        * For AES\_CTR\_HMAC keys, this is empty (zero bytes). The file key (AES and HMAC) comes from the keyslot.
        * For AESWRAP keys, this is the file key, wrapped using RFC3394 AESWRAP:
            * AES key ( kCCKeySizeAES128 = 16 bytes)
            * HMAC key ( SEGMENTED\_MAC\_KEY\_LEN = 16 bytes )
            * Zero-padding to boundary as needed by AESWRAP (zero bytes)
    * Padding to a 16-byte boundary. Must be zero; must be checked by reader.
* Variable-length array of encrypted segments, which may be empty
    * Segment IV (12 bytes = block size minus the 32-bit AES-CTR counter)
    * Segment MAC (20 bytes)
    * Segment data (SEGMENTED\_PAGE\_SIZE = 64k bytes, except possibly for the last segment)
* Trailer
    * File HMAC: (SEGMENTED\_FILE\_MAC\_LEN = 32 bytes) computed over a version identifier and the segment MACs.

All multibyte integers are in big-endian (network) byte order.

The file MAC is the HMAC-SHA256 of  ( SEGMENTED\_INNER\_VERSION || segment\_mac\_0 || segment\_mac\_1 ... ) (all of the segment MACs in sequence). SEGMENTED\_INNER\_VERSION is the single byte 0x01

The data is AES-CTR encrypted with initial IV of ( IV || zeroes ) as is normal for CTR mode.

The segment MAC is the truncated HMAC-SHA256 of ( IV || segment number || encrypted data ) where the segment number is a 32-bit number, starting at 0.

The length of the plaintext is determined by the length of the encrypted file. The file HMAC protects against truncation/lengthening.

### Motivations ###

The segment IV and MAC add to a multiple of 16 bytes for alignment purposes.

Most files are quite short (less than 1kB), so the format should be reasonably compact in that case. But some files are large (~ 1GB).

It's assumed that in the normal case, all files will be encrypted with the same document key (will have the same key index). During a key rollover, new files will have a new index and the old key will be retained only for reading pre-rollover files until they are deleted or reëncrypted.

A similar mechanism is used when a document is first encrypted, with a special temporary key indicating that old files may be plaintext.

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

### Other Notes

Algorithm choice: AES+HMAC is easy to implement using the primitives
available on OSX and iOS. If Apple provided an AES-GCM implementation
we could use that instead of AES+HMAC, but AES+HMAC is probably
preferable to bundling our own GCM implementation. If we were to
bundle our own, would a completely different choice like ChaCha+Poly
be even better?  AES has the advantage of being boring. How well-regarded
are chacha/salsa/poly1305 outside of the djb fan club, anyway?

The IV is constructed from 8 random bytes (via CommonCrypto's CSPRNG) and a 32-bit per-AES-key counter to eliminate the possibility of nonce reuse, but that's an implementation detail. Clients cannot communicate their counter values, so the random portion has to be enough to prevent client/client collisions.
(Concern: We currently generate IVs as a combination of random data and a monotonic counter; this means that the order of blocks written is visible in the encrypted file. This probably reveals no useful information, but we could pass the counter through a guaranteed-1:1 transformation, [see][ro1])

The segment MAC prevents many modifications of the ciphertext,
but it is possible to truncate the file to a segment boundary without
detection. For that, the file MAC is used: it is simply the
HMAC-SHA256 of all the segments' MACs.

### Questions ###

Concern: Since we have variable-length segments, should we include the segment length in the segment HMAC? I don't think this protects us from anything that the HMAC construction itself doesn't protect us from, but adding more fields here is cheap, so why not?

Concern: To prevent an attacker from renaming encrypted files, which might cause OmniFocus to put its database in a bad state, should we include the file's name in the file? See 'Filename Integrity Check', below.

Concern: An attacker can tell how long the plaintexts are, which could
potentially leak information especially about the sizes of attachments
which are being added to an OF database. Is there a way to pad files
that doesn't inflate the data usage too much but still provides an
actual benefit?

Concern: Should we include e.g. the file header in the file MAC? It
may be desirable to be able to rewrite the wrapped file key with one
wrapped with a different key (e.g., rewriting a downloaded file to be
encrypted with a local key; or rewriting a file written with a special
write-only key to use the normal key.)

Question: We have two encryption formats in this file: AES-CTR-HMAC, and AESWRAP. AESWRAP was designed for the exact purpose we're using it for, but is an old design. Should we use CTR-HMAC for everything instead for simplicity? (On the other hand, AESWRAP is available in CommonCrypto on both OSX and iOS.)

Non-Segmented File Encryption
-----------------------------

This is probably not worth doing:

If we don't require random read access, it might be possible to use a
standard encryption container like PBE (PKCS#5) CMS (PKCS#7), or PGP's
symmetric mode. (Are there more modern options than CMS?)

CMS does support AES-CGM and -CCM, which allow random read access but
not incremental integrity checks. But it's not unreasonable to do a
full integrity check on any file downloaded during a sync, and we can
either store it decrypted locally (relying on Data Protection or
FileVault), or re-encrypt into a random-access format.

A non-segmented format might be worthwile if it allows us to use a well-defined industry standard format, but otherwise the advantage seems small.

Unencrypted Files
-----------------

Several types of files in an OmniFocus database remain unencrypted
(see the discussion of key management records 5 and 6, below).

`.client` files are unencrypted in order for the account-management
website and for customer support to get some information about a
database's usage.

(Opportunity: We could still HMAC them, even if we don't encrypt them.)

`.inbox` files contain incoming transactions generated by Mail Drop or
perhaps other machinery which should not have access to a user's full
database; they exist temporarily until they are consumed by a client.

(Opportunity: We can put an asymmetric keypair in the file management
plist, and allow Mail Drop to encrypt its droppings. This works great
against a passive attacker; is there a way to make it effective
against an active attacker who can modify the key management plist? I
don't think so, unless we can somehow provide Mail Drop with a trust
path to verify the contents of the management plist, and clients with
a trust path to identify a "genuine" maildrop instance.)


Document Key Management
-----------------------

For the initial, password-based version of this feature, the document
key management file provides the connection from a user's passphrase
to a document key.

The key management file is named "encrypted" and is a plist containing
a dictionary. (An earlier version contained an array of dictionaries,
with each dictionary corresponding to one method for deriving a key;
some code still expects or handles 1-element arrays.) The dictionary
contains an encrypted list of *key slots*, plus information needed to
derive the unwrapping key for that list.

There are two derivation methods:

"method = static": For testing, the key slot data can simply be stored in plaintext as a `data` under the key "key".

"method = password": The document key is wrapped using a PBKDF2-derived key. The other dictionary keys are "algorithm" (always "PBKDF2; aes128-wrap"); "rounds", "salt", "prf" (the PBKDF2 parameters); and "key" (the AES128-wrapped key information).

### Key information

Once unwrapped, the key information consists of a sequence of records. Each record has a type (one byte), an identifier (two bytes), and a length byte (in 4-byte units, allowing up to 2^10 bytes of data in a record).

The current version uses types 3 (ActiveAES\_CTR\_HMAC) and 4 (RetiredAES\_CTR\_HMAC).
They are identical except that new files should only be encrypted with an active key.
Retired keys are retained as long as there are files encrypted with them; they are then deleted.

The data of an AES\_CTR\_HMAC key slot consists of 16 bytes of AES128 key, followed by 16 bytes of HMAC-SHA256 key.

The previous version (ActiveAESWRAP) contained a single AES key, which was
used to unwrap the CTR and HMAC keys stored in each file's header.

Two non-key record types also exist, which define encryption policy
based on file names:

Type 5 (Plaintext Mask) indicates that files
matching its pattern are to be both written and read unencrypted.

Type 6 (Retired Plaintext Mask) allows files to be read unencrypted,
but they are still written encrypted; this is used when converting a
database from unencrypted to encrypted to indicate that the conversion
is in progress. Once all files are encrypted, the type-6 record is
removed, and clients will no longer allow reading of unencrypted
files.

These "policy" records contain in their data section a string (padded
with NULs if necessary); if this string matches a suffix of a
filename, the policy of the record applies to that file. By default,
if a file matches no policy record, it is written encrypted, and OFS
will refuse to read files which are not encrypted.

### Key rollover

Rollover should be triggered by any password change, and if group
management is implemented, should be triggered whenever anyone leaves
the group. A new unused key index is chosen at random and a key is generated.
The existing key is changed to its corresponding Retired key type.

(Concern: People don't change their passwords all that often. Should
we silently start a key rollover whenever enough time has passed?
Should we try to measure the amount of data encrypted under a key and
trigger a rollover when it exceeds a threshold?)

Whenever a client deletes files (currently this happens only during compaction)
it checks to see whether there are any retired keys, and then whether there are any remaining files encrypted under those retired keys. If not, the retired keys are removed from the key information.
This means that a password change requires two updates to the document key information file: one to create a new active key and wrap it with the new passphrase; and some time later, one to remove the old key once it is no longer in use.

### Notes

One motivation of this design is to avoid having any secrets with an
infinite lifetime. Assuming the user changes their password once in a
while, all keys will eventually be rotated out of use and
deleted. This limits the amount of time forwards/backwards that a
compromised passphrase (or group authenticator) will be useful.

Safely rewriting files is difficult/time-expensive because clients
can't communicate directly, so data files are written once, read many
times, and deleted; the key-management/metadata file is unique in that
it will need to be updated over time, but we want to minimize the
frequency with which we have to do that.

Work to do
==========

'Write-only' keys
-----------------

Both Quick Entry and MailDrop would benefit from being able to encrypt
a file and add it to a document without having decryption access. The
obvious solution would be for some key slots to contain a
public/private keypair, with the public half also stored unencrypted
in the plist. EC-IEC over something like Curve25519 seems like the
obvious choice there.

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

Filename integrity check
------------------------

Our main concern is passive attackers, but if we can prevent some
kinds of active attacks, we might as well. An attacker who can rename
files can alter the way they are incorporated into an OmniFocus
database, conceivably causing subtle corruption. So perhaps we should
have an integrity check on files' names.

Option 1: Prepend a record containing the file's name (and other
metadata?) to the plaintext before encrypting. (Implementation of this
could be combined with adding obfuscatory padding, if we decide to do
that.)

Option 2: Add an "additional authenticated (but unencrypted) data"
field to the file header, and include this field in the file HMAC.

[ro1]: https://www.voltage.com/wp-content/uploads/UCSD_Rogaway_Synopsis_Format_Preserving_Encyption-1.pdf
