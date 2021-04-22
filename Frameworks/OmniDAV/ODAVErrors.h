// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSError-OBExtensions.h>

extern NSErrorDomain const ODAVErrorDomain;

typedef NS_ERROR_ENUM(ODAVErrorDomain, ODAVError) {
    // skip zero since it means 'no error' to AppleScript (actually the first 10-ish are defined in NSScriptCommand)

    // General
    ODAVNoFileManagerForScheme = 1,
    ODAVBaseURLIsNotAbsolute,
    ODAVCannotCreateDirectory,
    ODAVCannotMove,
    ODAVNoSuchDirectory,
    ODAVCannotDelete,
    ODAVNoSuchFile,
    ODAVCertificateNotTrusted,
    
    // DAV
    ODAVServerConformanceFailed,
    ODAVOperationInvalidMultiStatusResponse,
    ODAVOperationInvalidPath,
    ODAVInvalidPartialResponse,
};

extern BOOL ODAVShouldOfferToReportError(NSError *error);

#define ODAVErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, ODAVErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define ODAVError(error, code, description, reason) ODAVErrorWithInfo((error), (code), (description), (reason), nil)

#define ODAVResponseLocationErrorKey (@"Location")
#define ODAVPreviousRedirectsErrorKey (@"Redirects")

extern NSString * const ODAVURLErrorFailingURLErrorKey __attribute__((deprecated("use NSURLErrorFailingURLErrorKey")));          // > 4.0 use NSURLErrorFailingURLErrorKey

// Codes are HTTP error codes.  You'd think Foundation would define such a domain...
extern NSErrorDomain const ODAVHTTPErrorDomain;

extern NSString * const ODAVHTTPErrorDataKey;
extern NSString * const ODAVHTTPErrorDataContentTypeKey;
extern NSString * const ODAVHTTPErrorStringKey;

typedef NS_ERROR_ENUM(ODAVHTTPErrorDomain, ODAVHTTPError) {
    // Based on <apache2/httpd.h>
    ODAV_HTTP_CONTINUE = 100,
    ODAV_HTTP_SWITCHING_PROTOCOLS = 101,
    ODAV_HTTP_PROCESSING = 102,
    ODAV_HTTP_OK = 200,
    ODAV_HTTP_CREATED = 201,
    ODAV_HTTP_ACCEPTED = 202,
    ODAV_HTTP_NON_AUTHORITATIVE = 203,
    ODAV_HTTP_NO_CONTENT = 204,
    ODAV_HTTP_RESET_CONTENT = 205,
    ODAV_HTTP_PARTIAL_CONTENT = 206,
    ODAV_HTTP_MULTI_STATUS = 207,
    ODAV_HTTP_MULTIPLE_CHOICES = 300,
    ODAV_HTTP_MOVED_PERMANENTLY = 301,
    ODAV_HTTP_MOVED_TEMPORARILY = 302,
    ODAV_HTTP_SEE_OTHER = 303,
    ODAV_HTTP_NOT_MODIFIED = 304,
    ODAV_HTTP_USE_PROXY = 305,
    ODAV_HTTP_TEMPORARY_REDIRECT = 307,
    ODAV_HTTP_BAD_REQUEST = 400,
    ODAV_HTTP_UNAUTHORIZED = 401,
    ODAV_HTTP_PAYMENT_REQUIRED = 402,
    ODAV_HTTP_FORBIDDEN = 403,
    ODAV_HTTP_NOT_FOUND = 404,
    ODAV_HTTP_METHOD_NOT_ALLOWED = 405,
    ODAV_HTTP_NOT_ACCEPTABLE = 406,
    ODAV_HTTP_PROXY_AUTHENTICATION_REQUIRED = 407,
    ODAV_HTTP_REQUEST_TIME_OUT = 408,
    ODAV_HTTP_CONFLICT = 409,
    ODAV_HTTP_GONE = 410,
    ODAV_HTTP_LENGTH_REQUIRED = 411,
    ODAV_HTTP_PRECONDITION_FAILED = 412,
    ODAV_HTTP_REQUEST_ENTITY_TOO_LARGE = 413,
    ODAV_HTTP_REQUEST_URI_TOO_LARGE = 414,
    ODAV_HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    ODAV_HTTP_RANGE_NOT_SATISFIABLE = 416,
    ODAV_HTTP_EXPECTATION_FAILED = 417,
    ODAV_HTTP_UNPROCESSABLE_ENTITY = 422,
    ODAV_HTTP_LOCKED = 423,
    ODAV_HTTP_FAILED_DEPENDENCY = 424,
    ODAV_HTTP_UPGRADE_REQUIRED = 426,
    ODAV_HTTP_INTERNAL_SERVER_ERROR = 500,
    ODAV_HTTP_NOT_IMPLEMENTED = 501,
    ODAV_HTTP_BAD_GATEWAY = 502,
    ODAV_HTTP_SERVICE_UNAVAILABLE = 503,
    ODAV_HTTP_GATEWAY_TIME_OUT = 504,
    ODAV_HTTP_VERSION_NOT_SUPPORTED = 505,
    ODAV_HTTP_VARIANT_ALSO_VARIES = 506,
    ODAV_HTTP_INSUFFICIENT_STORAGE = 507,
    ODAV_HTTP_NOT_EXTENDED = 510,
};

@interface NSError (ODAVExtensions)

/// Returns an error indicating a certificate trust problem with the given challenge. This error has no localized strings in its userInfo dictionary, since it is intended to be caught at the app level. Errors of this kind should cause localized UI to be presented to the user to evaluate trust and possibly restart the operation.
+ (NSError *)certificateTrustErrorForChallenge:(NSURLAuthenticationChallenge *)challenge;

- (BOOL)causedByDAVPermissionFailure;
- (BOOL)causedByMissingDAVResource;

@end

// User info key that contains the NSURLAuthenticationChallenge passed when a certificate trust issue was encountered
#define ODAVCertificateTrustChallengeErrorKey (@"Challenge")
