// Copyright 2007-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSError.h> // NSLocalizedDescriptionKey

@class NSString;

enum {
    // Zero typically means no error
    OFCacheFileUnableToWriteError = 1,
    OFFilterDataCommandReturnedErrorCodeError,
    OFUnableToCreatePathError,
    OFUnableToSerializeLockFileDictionaryError,
    OFUnableToCreateLockFileError,
    OFCannotFindTemporaryDirectoryError,
    OFCannotExchangeFileError,
    OFCannotUniqueFileNameError,
    
    OFXMLLibraryError, // An error from libxml; might be a warning, might be fatal.
    OFXMLDocumentNoRootElementError,
    OFXMLCannotCreateStringFromUnparsedData,
    
    OFInvalidHexDigit,
    
    OFXMLReaderCannotCreateInputStream,
    OFXMLReaderCannotCreateXMLInputBuffer,
    OFXMLReaderCannotCreateXMLReader,
    OFXMLReaderUnexpectedNodeType,
    
    OFUnableToCompressData,
    OFUnableToDecompressData,
    
    OFXMLSignatureValidationError,    // Signature information could not be parsed
    OFXMLSignatureValidationFailure,  // Signature information could be parsed, but did not validate
    OFASN1Error,                      // Problem parsing an ASN.1 BER or DER encoded value
    OFKeyNotAvailable,
    
    OFNetStateRegistrationCannotCreateSocket,
    
    OFSyncClientStateInvalidPropertyList,
    
    // OFLockFile
    OFLockInvalidated,
    OFLockUnavailable,
    OFCannotCreateLock,
};


// This key holds the exit status of a process which has exited
#define OFProcessExitStatusErrorKey (@"OFExitStatus")
#define OFProcessExitSignalErrorKey (@"OFExitSignal")

extern NSString * const OFErrorDomain;

#define OFErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFError(error, code, description, reason) OFErrorWithInfo((error), (code), (description), (reason), nil)
