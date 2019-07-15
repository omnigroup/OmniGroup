// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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
