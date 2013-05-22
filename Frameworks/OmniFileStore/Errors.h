// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/NSError-OBExtensions.h>

enum {
    // skip zero since it means 'no error' to AppleScript (actually the first 10-ish are defined in NSScriptCommand)

    // General
    OFSNoFileManagerForScheme = 1,
    OFSBaseURLIsNotAbsolute,
    OFSCannotCreateDirectory,
    OFSCannotMove,
    OFSCannotWriteFile,
    OFSNoSuchDirectory,
    OFSCannotDelete,
    OFSFilenameAlreadyInUse,
    OFSNoSuchFile,
    OFSCertificateNotTrusted,
    
    OFSCannotMoveItemFromInbox,
    OFSInvalidZipArchive,
    OFSUnrecognizedFileType,
    
    // DAV
    OFSDAVFileManagerCannotAuthenticate,
    OFSDAVFileManagerConformanceFailed,
    OFSDAVOperationInvalidMultiStatusResponse,
};

extern NSString * const OFSErrorDomain;
extern BOOL OFSShouldOfferToReportError(NSError *error);

#define OFSErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, OFSErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define OFSError(error, code, description, reason) OFSErrorWithInfo((error), (code), (description), (reason), nil)

#define OFSResponseLocationErrorKey (@"Location")

extern NSString * const OFSURLErrorFailingURLErrorKey;          // > 4.0 use NSURLErrorFailingURLErrorKey
extern NSString * const OFSURLErrorFailingURLStringErrorKey;    // > 4.0 use NSURLErrorFailingURLStringErrorKey


// Codes are HTTP error codes.  You'd think Foundation would define such a domain...
extern NSString * const OFSDAVHTTPErrorDomain;

extern NSString * const OFSDAVHTTPErrorDataKey;
extern NSString * const OFSDAVHTTPErrorDataContentTypeKey;
extern NSString * const OFSDAVHTTPErrorStringKey;

typedef enum {
    // Based on <apache2/httpd.h>
    OFS_HTTP_CONTINUE = 100,
    OFS_HTTP_SWITCHING_PROTOCOLS = 101,
    OFS_HTTP_PROCESSING = 102,
    OFS_HTTP_OK = 200,
    OFS_HTTP_CREATED = 201,
    OFS_HTTP_ACCEPTED = 202,
    OFS_HTTP_NON_AUTHORITATIVE = 203,
    OFS_HTTP_NO_CONTENT = 204,
    OFS_HTTP_RESET_CONTENT = 205,
    OFS_HTTP_PARTIAL_CONTENT = 206,
    OFS_HTTP_MULTI_STATUS = 207,
    OFS_HTTP_MULTIPLE_CHOICES = 300,
    OFS_HTTP_MOVED_PERMANENTLY = 301,
    OFS_HTTP_MOVED_TEMPORARILY = 302,
    OFS_HTTP_SEE_OTHER = 303,
    OFS_HTTP_NOT_MODIFIED = 304,
    OFS_HTTP_USE_PROXY = 305,
    OFS_HTTP_TEMPORARY_REDIRECT = 307,
    OFS_HTTP_BAD_REQUEST = 400,
    OFS_HTTP_UNAUTHORIZED = 401,
    OFS_HTTP_PAYMENT_REQUIRED = 402,
    OFS_HTTP_FORBIDDEN = 403,
    OFS_HTTP_NOT_FOUND = 404,
    OFS_HTTP_METHOD_NOT_ALLOWED = 405,
    OFS_HTTP_NOT_ACCEPTABLE = 406,
    OFS_HTTP_PROXY_AUTHENTICATION_REQUIRED = 407,
    OFS_HTTP_REQUEST_TIME_OUT = 408,
    OFS_HTTP_CONFLICT = 409,
    OFS_HTTP_GONE = 410,
    OFS_HTTP_LENGTH_REQUIRED = 411,
    OFS_HTTP_PRECONDITION_FAILED = 412,
    OFS_HTTP_REQUEST_ENTITY_TOO_LARGE = 413,
    OFS_HTTP_REQUEST_URI_TOO_LARGE = 414,
    OFS_HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    OFS_HTTP_RANGE_NOT_SATISFIABLE = 416,
    OFS_HTTP_EXPECTATION_FAILED = 417,
    OFS_HTTP_UNPROCESSABLE_ENTITY = 422,
    OFS_HTTP_LOCKED = 423,
    OFS_HTTP_FAILED_DEPENDENCY = 424,
    OFS_HTTP_UPGRADE_REQUIRED = 426,
    OFS_HTTP_INTERNAL_SERVER_ERROR = 500,
    OFS_HTTP_NOT_IMPLEMENTED = 501,
    OFS_HTTP_BAD_GATEWAY = 502,
    OFS_HTTP_SERVICE_UNAVAILABLE = 503,
    OFS_HTTP_GATEWAY_TIME_OUT = 504,
    OFS_HTTP_VERSION_NOT_SUPPORTED = 505,
    OFS_HTTP_VARIANT_ALSO_VARIES = 506,
    OFS_HTTP_INSUFFICIENT_STORAGE = 507,
    OFS_HTTP_NOT_EXTENDED = 510,
} OFSDAVHTTPErrorCode;

@interface NSError (OFSExtensions)
+ (NSError *)certificateTrustErrorForChallenge:(NSURLAuthenticationChallenge *)challenge;
- (BOOL)causedByPermissionFailure;
@end

// User info key that contains the NSURLAuthenticationChallenge passed when a certificate trust issue was encountered
#define OFSCertificateTrustChallengeErrorKey (@"Challenge")
