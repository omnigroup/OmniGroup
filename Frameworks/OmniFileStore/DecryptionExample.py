
'''This will take an OmniFileStore encrypted file and decrypt it.  It
is intended more as an unambiguous, executable summary of the
specification than as production code.

Requires Python 2.7 or 3.4, and the cryptography module ("pip install cryptography").

'''

from __future__ import print_function
import argparse, collections, getpass, os.path, plistlib, posix, random, struct, sys, tempfile
import cryptography.hazmat.primitives.hashes
import cryptography.hazmat.primitives.keywrap
from cryptography.hazmat.primitives.keywrap import InvalidUnwrap
import cryptography.hazmat.primitives.kdf.pbkdf2
from cryptography.hazmat import primitives
from cryptography.hazmat.primitives.hmac import HMAC
from cryptography.hazmat.primitives.ciphers import algorithms, modes, Cipher

try:
    import __builtin__
except ImportError:
    # Python 3
    import builtins as __builtin__

def print(*args, **kwargs):
    """Custom print that is silent if this is loaded as a module"""
    if __name__ != '__main__':
        return None
    return __builtin__.print(*args, **kwargs)

# Key type name constants
ActiveAES_CTR_HMAC  = 'ActiveAES_CTR_HMAC'  # Currently-active CTR+HMAC key
RetiredAES_CTR_HMAC = 'RetiredAES_CTR_HMAC' # Old key used after rollover

# The kinds of information found in the encrypted document metadata.
Slot = collections.namedtuple('Slot', ('tp', 'id', 'contents'))
SlotType = {
    'None'                : 0, # Trailing padding
    'ActiveAESWRAP'       : 1, # (Obsolete) Currently-active AESWRAP key
    'RetiredAESWRAP'      : 2, # (Obsolete) Old AESWRAP key used after rollover
    'ActiveAES_CTR_HMAC'  : 3, # Currently-active CTR+HMAC key
    'RetiredAES_CTR_HMAC' : 4, # Old key used after rollover
    'PlaintextMask'       : 5, # Filename patterns which should not be encrypted
    'RetiredPlaintextMask': 6, # Filename patterns which have legacy unencrypted entries
    }
SlotTypeName = dict( (v, k) for (k, v) in SlotType.items() )

RetireMap = [
    ( 'ActiveAES_CTR_HMAC', 'RetiredAES_CTR_HMAC' ),
    ( 'ActiveAESWRAP',      'RetiredAESWRAP' )
]

# The name of the filename containing the encryption metadata.
metadata_filename = 'encrypted'

# Bytes identifying an encrypted file.
file_magic = b"OmniFileEncryption\x00\x00"

backend = cryptography.hazmat.backends.default_backend()

# Py2 / Py3 compatibility shims.
if sys.version_info.major < 3:
    def index_u8(b, ix):
        return ord(b[ix])
    def hexify(b):
        return ':'.join(('%02X' % (ord(v),)) for v in b)
    def trim_0padding(b):
        while len(b) > 0 and b[-1] == b'\x00':
            b = b[:-1]
        return b
    from cStringIO import StringIO as BytesIO
else:
    def index_u8(b, ix):
        return b[ix]
    def hexify(b):
        return ':'.join(('%02X' % (v,)) for v in b)
    def trim_0padding(b):
        while len(b) > 0 and b[-1] == 0:
            b = b[:-1]
        return b
    from io import BytesIO

def print_slot(slot):
    print("  Slot: %2d Type: %2d" % (slot.id, slot.tp), end='')
    if slot.tp in SlotTypeName:
        sys.stdout.write(" (" + SlotTypeName[slot.tp] + ")")
    sys.stdout.write(" (%d bytes of data)\n" % (len(slot.contents),))
    if slot.tp in ( SlotType['ActiveAESWRAP'], SlotType['RetiredAESWRAP'] ):
        print("\tAESWRAP key:", hexify(slot.contents))
    elif slot.tp in ( SlotType['ActiveAES_CTR_HMAC'], SlotType['RetiredAES_CTR_HMAC'] ):
        print("\t   AES key:", hexify(slot.contents[ : len(slot.contents)//2 ]))
        print("\t  HMAC key:", hexify(slot.contents[ len(slot.contents)//2 : ]))
    elif slot.tp in ( SlotType['PlaintextMask'], SlotType['RetiredPlaintextMask'] ):
        print("\t    Suffix:", repr(trim_0padding(slot.contents).decode('utf8')))
Slot.print = print_slot

class DocumentKey (object):
    '''Holds the key information for an OmniFocus database.
This class knows how to unwrap the document keys using a user's passphrase,
and how to create a decryptor for a file using the unwrapped document keys.
'''

    # The PRFs for PBKDF2.
    prfs = {
        'sha1':   primitives.hashes.SHA1,   # Historical.
        'sha256': primitives.hashes.SHA256,
        'sha512': primitives.hashes.SHA512
    }

    @classmethod
    def parse_metadata(cls, metadata_blob_or_fp):
        if hasattr(metadata_blob_or_fp, 'read'):
            if hasattr(plistlib, 'load'): # Py3
                metadata = plistlib.load(metadata_blob_or_fp, use_builtin_types=False)
            else:
                metadata = plistlib.readPlist(metadata_blob_or_fp)
        else:
            if hasattr(plistlib, 'loads'): # Py3
                metadata = plistlib.loads(metadata_blob_or_fp, use_builtin_types=False)
            else:
                metadata = plistlib.readPlistFromString(metadata_blob_or_fp)

        # The current version has a 1-element array at toplevel.
        # Future versions will have a dictionary at toplevel.
        if isinstance(metadata, list) and len(metadata) == 1:
            metadata = metadata[0]
        assert isinstance(metadata, dict)
        return metadata
        
    @classmethod
    def use_passphrase(self, metadata, passphrase):
        '''Use a passphrase to derive the key which unwraps the blob of file keys.'''
        # Assert the set of parameters currently used. Other methods
        # (e.g. key agreement rather than passwords) or algorithms
        # (e.g. other KDFs or wrapping algs) may exist in the future.
        assert metadata.get('method') == 'password'
        assert metadata.get('algorithm') == 'PBKDF2; aes128-wrap'

        # Ideally, we should also normalize (NFC) and stringprep the passphrase before converting it to utf-8
        passphrase_bytes = passphrase.encode('utf8')

        # Use PBKDF2 to derive the wrapping key from the password
        print('Deriving wrapping key...')
        rounds = metadata.get('rounds')
        salt = metadata.get('salt').data
        prf = metadata.get('prf', 'sha1')
        deriver = primitives.kdf.pbkdf2.PBKDF2HMAC(
            algorithm  = self.prfs[prf](),
            length     = 16, # 16 bytes = 128 bits = AES128-wrap
            salt       = salt,
            iterations = rounds,
            backend    = backend
        )
        return deriver.derive(passphrase_bytes)
        
    def __init__(self, secrets=None, unwrapping_key=None):
        self.secrets = None
        if secrets:
            if unwrapping_key is None:
                unwrapped = secrets
            else:
                unwrapped = primitives.keywrap.aes_key_unwrap(unwrapping_key,
                                                              secrets,
                                                              backend)
            self.parse_secrets(unwrapped)

    def parse_secrets(self, unwrapped, verbose=True):
        '''Parse out the secrets from an unwrapped blob and store them in self.secrets'''
        secrets = list()
        idx = 0
        while idx != len(unwrapped):
            slottype = index_u8(unwrapped, idx)
            if slottype == 0:
                break  # End-of-data padding pseudo-slot
            slotlength = 4 * index_u8(unwrapped, idx+1)
            (slotid,) = struct.unpack('>H', unwrapped[idx+2 : idx+4])
            slotdata = unwrapped[idx+4 : idx+4+slotlength]
            secrets.append( Slot( slottype, slotid, slotdata ) )
            idx = idx + 4 + slotlength
        self.secrets = secrets

    def wrapped_secrets(self, wrapping_key):
        '''Marshal the secrets into their stored format, optionally wrapping them with the supplied key.'''
        buf = BytesIO()
        for secret in self.secrets:
            slotdata = secret.contents
            assert (len(slotdata) % 4) == 0
            buf.write(struct.pack('>BBH', secret.tp, len(slotdata)//4, secret.id))
            buf.write(slotdata)
        # Apply padding as necessary for AESWRAP
        fragment = buf.tell() % 8
        if fragment > 0:
            buf.write( b'\x00' * (8 - fragment) )
        marshalled = buf.getvalue()
            
        if wrapping_key is None:
            return marshalled
        else:
            return primitives.keywrap.aes_key_wrap(wrapping_key,
                                                   marshalled,
                                                   backend)
    
    def get_decryptor(self, info):
        '''Return an object which decrypts a file, given that file's key information. Used by decrypt_file().'''
        # The beginning of the key information is the key identifier.
        (keyid,) = struct.unpack('>H', info[0:2])
        # Find matching key identifier(s).
        slots = [ s for s in self.secrets if s.id == keyid ]
        assert len(slots) == 1  # Should have exactly one matching entry
        slot = slots[0]
        print("        Key %d: type=%s, %d bytes in doc metadata, %d bytes in file header" %
              (keyid, slot.tp, len(slot.contents), len(info) - 2))
        if slot.tp in ( SlotType['ActiveAES_CTR_HMAC'], SlotType['RetiredAES_CTR_HMAC'] ):
            assert len(info) == 2 # No per-file info for these key types
            return EncryptedFileHelper(slot.contents)
        elif slot.tp in ( SlotType['ActiveAESWRAP'], SlotType['RetiredAESWRAP'] ):
            wrappedkey = info[2:]
            assert len(wrappedkey) % 8 == 0 # AESWRAPped info
            unwrapped = primitives.keywrap.aes_key_unwrap(slot.contents, wrappedkey, backend)
            return EncryptedFileHelper(unwrapped)
        else:
            raise ValueError('Unknown keyslot type: %r' % (slot.tp,))

    def _available_slot(self):
        used_slots = set( int(s.id) for s in self.secrets )
        while True:
            slotnum = random.randint(0, 2 + (2 * len(used_slots)))
            if slotnum not in used_slots:
                return slotnum
        
    def get_key_of_type(self, keytype, create=False):
        tp = SlotType[keytype]
        for slot in self.secrets:
            if slot.tp == tp:
                return slot
        if create:
            if keytype == ActiveAES_CTR_HMAC:
                content = os.urandom(32)
                newkey = Slot(id=self._available_slot(),
                              tp=tp,
                              contents=content)
                self.secrets.append(newkey)
                return newkey
            else:
                raise ValueError('Do not know how to create a key of type %r' % (keytype,))
        return None

    def with_retired_keys(self, predicate=None):
        retirable_types = dict( (SlotType[a], SlotType[b]) for (a,b) in RetireMap )
        new_secrets = list()
        for slot in self.secrets:
            if slot.tp in retirable_types and (predicate is None or predicate(slot)):
                newslot = Slot(id = slot.id,
                               tp = retirable_types[slot.tp],
                               contents = slot.contents)
                new_secrets.append(newslot)
            else:
                new_secrets.append(slot)
        newDocKey = DocumentKey()
        newDocKey.secrets = new_secrets
        return newDocKey
        
    def applicable_policy_slots(self, filename):
        '''Return any filename-based-policy slots which apply to this filename.'''
        fnbytes = filename.encode('utf8')
        for slot in self.secrets:
            if slot.tp in ( SlotType['PlaintextMask'], SlotType['RetiredPlaintextMask'] ):
                if fnbytes.endswith(trim_0padding(slot.contents)):
                    yield slot

    def decrypt_file(self, filename, infp, outfp):
        '''Read an encrypted file from infp (which must be seekable) and write its decrypted contents to outfp.'''
        canReadPlaintext = None
        for slot in self.applicable_policy_slots(filename):
            if slot.tp == SlotType['PlaintextMask']:
                canReadPlaintext = 'expected'
            elif slot.tp == SlotType['RetiredPlaintextMask']:
                canReadPlaintext = 'temporarily allowed'
        print('    Reading file header')
        # Check the file magic.
        magic = infp.read(len(file_magic))
        if magic != file_magic:
            if canReadPlaintext and ( b'crypt' not in magic ):
                print('        File is not encrypted, but this is ' + canReadPlaintext + ' for this filename.')
                if outfp is not None:
                    infp.seek(0)
                    outfp.write(infp.read())
                return
            else:
                raise ValueError('Incorrect file magic, or unencrypted file.')

        # Read the key information.
        (info_length,) = struct.unpack('>H', infp.read(2))
        info = infp.read(info_length)

        # Skip & check padding.
        offset = len(magic) + 2 + info_length
        padding_length = (16 - (offset % 16)) % 16
        padding = infp.read(padding_length)
        assert padding == ( b'\0' * padding_length ) # Padding must be zero.

        print('    Looking up file key')
        decryptor = self.get_decryptor(info) # Find decryptor for this keyslot.

        # The rest of the file is the encrypted segments followed by the file HMAC.
        seg_0_start = infp.tell()
        infp.seek(-( decryptor.FileMACLen ), 2) # Last 32 bytes are file HMAC
        seg_N_end = infp.tell()
        fileHMAC = infp.read(decryptor.FileMACLen)

        # Check the MACs
        print('    Verifying')
        decryptor.checkHMAC(infp, seg_0_start, seg_N_end, fileHMAC)
        if outfp is not None:
            # Decrypt the file
            print('    Decrypting')
            decryptor.decrypt(infp, outfp, seg_0_start, seg_N_end)

    def encrypt_file(self, filename, infp, outfp):
        '''Read a plaintext file from infp and write it to outfp, encrypted depending on policy mask.'''

        # Check whether this file should be encrypted at all
        writePlaintext = False
        for slot in self.applicable_policy_slots(filename):
            if slot.tp == SlotType['PlaintextMask']:
                writePlaintext = True
        if writePlaintext:
            outfp.write(infp.read())
            return

        # Find an active CTR-HMAC key
        encryption_key = self.get_key_of_type(ActiveAES_CTR_HMAC)
        if encryption_key is None:
            raise ValueError('No keys of type %r' % (ActiveAES_CTR_HMAC,))
        file_header = file_magic + struct.pack('>HH', 2, encryption_key.id)
        outfp.write(file_header)
        padding_length = (16 - (len(file_header)%16)) % 16
        outfp.write( b'\0' * padding_length )

        encryptor = EncryptedFileHelper(encryption_key.contents)
        encryptor.encrypt(infp, outfp)

class EncryptedFileHelper (object):
    '''A helper class used by DocumentKey.'''

    # File format constants.
    AESKeySize = 16    # AES128
    HMACKeySize = 16   # Arbitrary, but fixed
    SegIVLen = 12      # Four bytes less than blocksize (see CTR mode for why)
    SegMACLen = 20     # Arbitrary, but fixed
    SegPageSize = 65536
    FileMACPrefix = b'\x01' # Fixed prefix for file HMAC
    FileMACLen = 32    # Full SHA256

    def __init__(self, key_material):
        assert len(key_material) == ( 16 + 16 )
        self.aeskey = key_material[0:16]    # AES key for file.
        self.hmackey = key_material[16:32]  # HMAC-SHA256 key for file.

    def segment_ranges(self, seg_0_start, seg_N_end):
        '''Yield a sequence of tuples describing the locations of the encrypted segments.'''
        encrypted_hdr_size = self.SegIVLen + self.SegMACLen
        idx = 0
        position = seg_0_start
        while True:
            assert position + encrypted_hdr_size <= seg_N_end
            if position + encrypted_hdr_size + self.SegPageSize > seg_N_end:
                # Partial trailing page.
                yield ( idx, position, seg_N_end - (position+encrypted_hdr_size) )
                break
            else:
                # Full page.
                yield ( idx, position, self.SegPageSize )
                position += encrypted_hdr_size + self.SegPageSize
                idx += 1

    def checkHMAC(self, fp, segments_start, segments_end, fileHMAC):
        '''Check the file's integrity'''
        filehash = HMAC(self.hmackey, primitives.hashes.SHA256(), backend)
        filehash.update(self.FileMACPrefix)
        for segmentIndex, startpos, datalen in self.segment_ranges(segments_start, segments_end):

            print("        Segment %d" % (segmentIndex))
            fp.seek(startpos)
            segmentIV = fp.read(self.SegIVLen)
            segmentMAC = fp.read(self.SegMACLen)

            # Verify the segment's own MAC against the segment data
            segmenthash = HMAC(self.hmackey, primitives.hashes.SHA256(), backend)
            segmenthash.update(segmentIV)
            segmenthash.update(struct.pack('>I', segmentIndex))
            segmenthash.update(fp.read(datalen))

            # The cryptography module doesn't handle truncated HMACs directly
            computed = segmenthash.finalize()
            assert primitives.constant_time.bytes_eq(computed[:self.SegMACLen], segmentMAC)

            # Add the segment's MAC to the file-MAC context
            filehash.update(segmentMAC)

        # Finally, verify the file MAC
        print("        File hash")
        filehash.verify(fileHMAC) # Raises on mismatch.

    def decrypt(self, fp, outfp, segments_start, segments_end):
        '''Decrypt the file, write it to outfp'''
        aes = algorithms.AES(self.aeskey)
        for _, startpos, datalen in self.segment_ranges(segments_start, segments_end):
            # Read the segment's IV and set up the decryption context
            fp.seek(startpos)
            segmentIV = fp.read(self.SegIVLen)
            mode = modes.CTR(segmentIV + b'\x00\x00\x00\x00')
            decryptor = Cipher(aes, mode, backend=backend).decryptor()

            # Decrypt the segment
            fp.seek(startpos + self.SegIVLen + self.SegMACLen)
            outfp.write(decryptor.update(fp.read(datalen)))
            trailing = decryptor.finalize() # Should be none for CTR mode
            if trailing:
                outfp.write(trailing)

    def encrypt(self, fp, outfp):
        '''Encrypt the file, write it to outfp. Outfp should already be positioned after the file header, info field, and any padding.'''
        aes = algorithms.AES(self.aeskey)
        filehash = HMAC(self.hmackey, primitives.hashes.SHA256(), backend)
        filehash.update(self.FileMACPrefix)

        # Encrypt each segment
        lastSegmentWasPartial = False
        segmentIndex = 0
        while True:
            segment_plaintext = fp.read(self.SegPageSize)
            if not segment_plaintext and segmentIndex > 0:
                break
            assert not lastSegmentWasPartial
            lastSegmentWasPartial = len(segment_plaintext) < self.SegPageSize

            # Set up this segment's IV, cryptor, and per-segment HMAC context
            segmentIV = os.urandom(self.SegIVLen)
            mode = modes.CTR(segmentIV + b'\x00\x00\x00\x00')
            encryptor = Cipher(aes, mode, backend=backend).encryptor()
            seghash = HMAC(self.hmackey, primitives.hashes.SHA256(), backend)
            
            seghash.update(segmentIV)
            outfp.write(segmentIV)

            seghash.update(struct.pack('>I', segmentIndex))

            # Encrypt the segment's data
            encryptedData = encryptor.update(segment_plaintext)
            encryptedData += encryptor.finalize()
            assert len(encryptedData) == len(segment_plaintext)

            # Per-segment and whole-file hash updates
            seghash.update(encryptedData)
            segmentMAC = seghash.finalize()[:self.SegMACLen]
            outfp.write(segmentMAC)
            filehash.update(segmentMAC)
            
            outfp.write(encryptedData)

            segmentIndex += 1

        outfp.write(filehash.finalize()[:self.FileMACLen])
                

def decrypt_directory(indir, outdir, re_encrypt=False):
    '''Decrypt the OmniFocus data in indir, writing the result to outdir. Prompts for a passphrase.'''
    files = posix.listdir(indir)
    if metadata_filename not in files:
        raise EnvironmentError('Expected to find %r in %r' %
                               ( metadata_filename, indir))
    encryptionMetadata = DocumentKey.parse_metadata( open(os.path.join(indir, metadata_filename), 'rb') )
    metadataKey = DocumentKey.use_passphrase( encryptionMetadata,
                                              getpass.getpass(prompt="Passphrase: ") )
    docKey = DocumentKey( encryptionMetadata.get('key').data, unwrapping_key=metadataKey )
    for secret in docKey.secrets:
        secret.print()
    
    workdir = outdir
    if outdir is not None:
        posix.mkdir(outdir)
    if re_encrypt:
        workdir = tempfile.mkdtemp()

    basename = os.path.basename(indir)
    for dirpath, dirnames, filenames in os.walk(indir):
        for datafile in filenames:
            inpath = os.path.join(dirpath, datafile)
            if workdir is not None:
                outpath = inpath.replace(indir, workdir)
            if datafile == metadata_filename:
                continue
            display = "%s/%s" % (os.path.basename(dirpath), datafile) if os.path.basename(dirpath) != basename else datafile
            if outdir is not None:
                print('Decrypting %r' % (display,))
                if not os.path.exists(os.path.split(outpath)[0]):
                    os.makedirs(os.path.split(outpath)[0])
                with open(os.path.join(indir, inpath), "rb") as infp, \
                     open(os.path.join(workdir, outpath), "wb") as outfp:
                    docKey.decrypt_file(datafile, infp, outfp)
            else:
                print('Reading %r' % (display,))
                with open(os.path.join(indir, inpath), "rb") as infp:
                    docKey.decrypt_file(datafile, infp, None)

    if re_encrypt and outdir is not None:
        print()
        print("Re-Encrypt the database\n")
        newKey = docKey.get_key_of_type(ActiveAES_CTR_HMAC, True)
        encryptionMetadata['key'] = plistlib.Data(docKey.wrapped_secrets(metadataKey))
        encrypt_directory(encryptionMetadata, docKey, workdir, outdir)
        
        # We've created a tempdirectory lets clean it up
        import shutil
        shutil.rmtree(workdir)

def encrypt_directory(metadata, docKey, indir, outdir):
    '''Encrypt all individual files in indir, writing them to outdir.'''
    files = posix.listdir(indir)
    assert metadata_filename not in files  # A non-encrypted directory must not have an encryption metadata file

    if not os.path.exists(outdir):
        posix.mkdir(outdir)

    print('Writing encryption metadata')
    if isinstance(metadata, dict):

        metadata = [ metadata ]  # Current OmniFileStore expects a 1-element list of dictionaries.
    with open(os.path.join(outdir, metadata_filename), "wb") as outfp:
        if hasattr(plistlib, 'dump'):
            plistlib.dump(metadata, outfp)
        else:
            plistlib.writePlist(metadata, outfp)

    basename = os.path.basename(indir)
    for dirpath, dirnames, filenames in os.walk(indir):
        for datafile in filenames:
            inpath = os.path.join(dirpath, datafile)
            outpath = inpath.replace(indir, outdir)
            display = "%s/%s" % (os.path.basename(dirpath), datafile) if os.path.basename(dirpath) != basename else datafile
            print('Encrypting %r' % (display,))

            if not os.path.exists(os.path.split(outpath)[0]):
                os.makedirs(os.path.split(outpath)[0])

            with open(os.path.join(indir, inpath), "rb") as infp, \
                 open(outpath, "wb") as outfp:

                docKey.encrypt_file(datafile, infp, outfp)
    
                
if __name__ == '__main__':
    optp = argparse.ArgumentParser()
    optp.add_argument('input', metavar='input.ofocus',
                      help='The encryted OmniFocus database to read')
    optp.add_argument('-o', '--output',
                      help='Write decrypted contents to this directory')
    optp.add_argument('-e', '--encrypt', action='store_true',
                      help='Also re-encrypt the resulting directory')    
    args = optp.parse_args()
    decrypt_directory(args.input, args.output, args.encrypt)

