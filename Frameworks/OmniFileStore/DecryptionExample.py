
'''This will take an OmniFileStore encrypted file and decrypt it.  It
is intended more as an unambiguous, executable summary of the
specification than as production code.

Requires Python 3.4 (mostly for the plistlib module) and
the cryptography module ("pip install cryptography").

'''

import argparse, collections, getpass, os.path, plistlib, posix, struct, sys
import cryptography.hazmat.primitives.hashes
import cryptography.hazmat.primitives.keywrap
import cryptography.hazmat.primitives.kdf.pbkdf2
from cryptography.hazmat import primitives
from cryptography.hazmat.primitives.hmac import HMAC
from cryptography.hazmat.primitives.ciphers import algorithms, modes, Cipher

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

# The name of the filename containing the encryption metadata.
metadata_filename = 'encrypted'

# Bytes identifying an encrypted file.
file_magic = b"OmniFileEncryption\x00\x00"

backend = cryptography.hazmat.backends.default_backend()

def hexify(b):
    return ':'.join(('%02X' % (v,)) for v in b)
def trim_0padding(b):
    while len(b) > 0 and b[-1] == 0:
        b = b[:-1]
    return b

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

    def __init__(self, metadata_blob):
        metadata = plistlib.loads(metadata_blob)
        # The current version has a 1-element array at toplevel.
        # Future versions will have a dictionary at toplevel.
        if isinstance(metadata, list) and len(metadata) == 1:
            metadata = metadata[0]
        assert isinstance(metadata, dict)
        self.metadata = metadata
        self.secrets = None

    def use_password(self, passphrase):
        '''Use a password to unwrap the file keys, and store those in self.secrets.'''
        # Assert the set of parameters currently used. Other methods
        # (e.g. key agreement rather than passwords) or algorithms
        # (e.g. other KDFs or wrapping algs) may exist in the future.
        assert self.metadata.get('method') == 'password'
        assert self.metadata.get('algorithm') == 'PBKDF2; aes128-wrap'

        # Use PBKDF2 to derive the wrapping key from the password
        print('Deriving wrapping key...')
        rounds = self.metadata.get('rounds')
        salt = self.metadata.get('salt')
        prf = self.metadata.get('prf', 'sha1')
        deriver = primitives.kdf.pbkdf2.PBKDF2HMAC(
            algorithm  = self.prfs[prf](),
            length     = 16, # 16 bytes = 128 bits = AES128-wrap
            salt       = salt,
            iterations = rounds,
            backend    = backend
        )
        derived_key = deriver.derive(passphrase)

        # Decrypt the secrets using the wrapping key
        print('Unwrapping file secrets...')
        unwrapped = primitives.keywrap.aes_key_unwrap(derived_key,
                                                      self.metadata.get('key'),
                                                      backend)

        # Parse out the list of secrets for easier manipulation later
        print('Parsing file secrets...')
        secrets = list()
        idx = 0
        while idx != len(unwrapped):
            slottype = unwrapped[idx]
            if slottype == 0:
                break  # End-of-data padding pseudo-slot
            slotlength = 4 * unwrapped[idx+1]
            (slotid,) = struct.unpack('>H', unwrapped[idx+2 : idx+4])
            slotdata = unwrapped[idx+4 : idx+4+slotlength]
            secrets.append( Slot( slottype, slotid, slotdata ) )
            print("  Slot: %2d Type: %2d" % (slotid, slottype), end='')
            if slottype in SlotTypeName:
                sys.stdout.write(" (" + SlotTypeName[slottype] + ")")
            sys.stdout.write(" (%d bytes of data)\n" % (len(slotdata),))
            if slottype in ( SlotType['ActiveAESWRAP'], SlotType['RetiredAESWRAP'] ):
                print("\tAESWRAP key:", hexify(slotdata))
            elif slottype in ( SlotType['ActiveAES_CTR_HMAC'], SlotType['RetiredAES_CTR_HMAC'] ):
                print("\t   AES key:", hexify(slotdata[ : len(slotdata)//2 ]))
                print("\t  HMAC key:", hexify(slotdata[ len(slotdata)//2 : ]))
            elif slottype in ( SlotType['PlaintextMask'], SlotType['RetiredPlaintextMask'] ):
                print("\t    Suffix:", repr(trim_0padding(slotdata).decode('utf8')))
            idx = idx + 4 + slotlength
        self.secrets = secrets

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
            return CTRDecryptor(slot.contents)
        elif slot.tp in ( SlotType['ActiveAESWRAP'], SlotType['RetiredAESWRAP'] ):
            wrappedkey = info[2:]
            assert len(wrappedkey) % 8 == 0 # AESWRAPped info
            unwrapped = primitives.keywrap.aes_key_unwrap(slot.contents, wrappedkey, backend)
            return CTRDecryptor(unwrapped)
        else:
            raise ValueError('Unknown keyslot type: %r' % (slot.tp,))

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
        seg_N_end = infp.seek(-( decryptor.FileMACLen ), 2) # Last 32 bytes are file HMAC
        fileHMAC = infp.read(decryptor.FileMACLen)

        # Check the MACs
        print('    Verifying')
        decryptor.checkHMAC(infp, seg_0_start, seg_N_end, fileHMAC)
        if outfp is not None:
            # Decrypt the file
            print('    Decrypting')
            decryptor.decrypt(infp, outfp, seg_0_start, seg_N_end)

class CTRDecryptor (object):
    '''A helper class used by DocumentKey.'''

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

def decrypt_directory(indir, outdir):
    '''Decrypt the OmniFocus data in indir, writing the result to outdir. Prompts for a passphrase.'''
    files = posix.listdir(indir)
    if metadata_filename not in files:
        raise EnvironmentError('Expected to find %r in %r' %
                               ( metadata_filename, indir))
    docKey = DocumentKey( open(os.path.join(indir, metadata_filename), 'rb').read() )
    docKey.use_password(bytes(getpass.getpass(prompt="Passphrase: "), encoding="latin1"))
    if outdir is not None:
        posix.mkdir(outdir)
    for datafile in files:
        if datafile == metadata_filename:
            continue
        if outdir is not None:
            print('Decrypting %r' % (datafile,))
            with open(os.path.join(indir, datafile), "rb") as infp, \
                 open(os.path.join(outdir, datafile), "wb") as outfp:
                docKey.decrypt_file(datafile, infp, outfp)
        else:
            print('Reading %r' % (datafile,))
            with open(os.path.join(indir, datafile), "rb") as infp:
                docKey.decrypt_file(datafile, infp, None)

if __name__ == '__main__':
    optp = argparse.ArgumentParser()
    optp.add_argument('input', metavar='input.ofocus',
                      help='The encryted OmniFocus database to read')
    optp.add_argument('-o', '--output',
                      help='Write decrypted contents to this directory')
    args = optp.parse_args()
    decrypt_directory(args.input, args.output)
