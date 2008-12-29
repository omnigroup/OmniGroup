// Copyright 2002-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUCheckTool.h 93428 2007-10-25 16:36:11Z kc $


#define OSUTool_Success	0
#define OSUTool_Failure	1

#define OSUToolErrorDomain @"com.omnigroup.framework.OmniSoftwareUpdate.CheckTool"

enum {
    OSUToolRemoteNetworkFailure = 1, // 0 is no error
    OSUToolLocalNetworkFailure,
    OSUToolExceptionRaised,
    OSUToolServerError,
    OSUToolUnableToParseSoftwareUpdateData,
}; 

#define OSUTool_ResultsURLKey @"url"  // The URL that was actually fetched, as an NSString
#define OSUTool_ResultsDataKey @"data"  // The response from the server, NSData (XML)
#define OSUTool_ResultsErrorKey @"error" // Any error that occured, NSError
#define OSUTool_ResultsMIMETypeKey @"mime-type" // NSString
#define OSUTool_ResultsTextEncodingNameKey @"text-encoding" // NSString

#define OSUTool_ResultsHeadersKey @"headers" // Any HTTP headers, NSDictionary
#define OSUTool_ResultsStatusCodeKey @"status" // Any HTTP status, NSNumber

extern CFDictionaryRef OSUCheckToolCollectHardwareInfo(const char *applicationIdentifier, bool collectHardwareInformation, const char *licenseType, bool reportMode);
