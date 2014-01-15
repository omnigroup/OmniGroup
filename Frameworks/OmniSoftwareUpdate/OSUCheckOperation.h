// Copyright 2001-2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniBase/macros.h>

@class OFVersionNumber;

typedef enum {
    OSUCheckOperationHasNotRun,
    OSUCheckOperationRunSynchronously,
    OSUCheckOperationRunAsynchronously,
} OSUCheckOperationRunType;

// This represents a single check operation to the software update server, invoked by OSUChecker.
@interface OSUCheckOperation : NSObject

- initForQuery:(BOOL)doQuery url:(NSURL *)url licenseType:(NSString *)licenseType;

- (NSURL *)url;

- (void)runAsynchronously;
- (NSDictionary *)runSynchronously;

@property(nonatomic,readonly) OSUCheckOperationRunType runType;
@property(nonatomic) BOOL initiatedByUser;

@property(nonatomic,readonly,retain) NSDictionary *output; // KVO observable; will fire on the main thread
@property(nonatomic,readonly,retain) NSError *error; // KVO observable; will fire on the main thread

@end

extern NSString * const OSUCheckOperationCompletedNotification;

extern NSDictionary *OSUPerformCheck(NSURL *url);

#if !OB_ARC // Should convert this struct to an object
typedef struct {
    NSString *firstHopHost;
    NSString *baseURLString;
    NSString *appIdentifier;
    NSString *appVersionString;
    NSString *track;
    BOOL includeHardwareInfo;
    BOOL reportMode;
    NSString *licenseType;
    NSString *osuVersionString;
} OSURunOperationParameters;

extern NSDictionary *OSURunOperation(const OSURunOperationParameters *params, NSError **outError);
#endif // !OB_ARC

// Keys for 'query' mode results (reportMode == NO)
#define OSUCheckResultsURLKey @"url"  // The URL that was actually fetched, as an NSString
#define OSUCheckResultsDataKey @"data"  // The response from the server, NSData (XML)
#define OSUCheckResultsErrorKey @"error" // Any error that occured, NSError
#define OSUCheckResultsMIMETypeKey @"mime-type" // NSString
#define OSUCheckResultsTextEncodingNameKey @"text-encoding" // NSString
#define OSUCheckResultsHeadersKey @"headers" // Any HTTP headers, NSDictionary
#define OSUCheckResultsStatusCodeKey @"status" // Any HTTP status, NSNumber

// Keys for 'report' mode results
#define OSUReportResultsURLKey @"url" // the URL that would have been queried
#define OSUReportResultsInfoKey @"info" // the hardware info
