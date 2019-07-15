// Copyright 1998-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObjCRuntime.h>

@class NSString;

extern NSString *OFCopyNumericBacktraceString(int framesToSkip) NS_RETURNS_RETAINED;
extern NSString *OFCopySymbolicBacktrace(void) NS_RETURNS_RETAINED;
extern NSString *OFCopySymbolicBacktraceForNumericBacktrace(NSString *numericTrace) NS_RETURNS_RETAINED;

extern void OFLogBacktrace(void);
