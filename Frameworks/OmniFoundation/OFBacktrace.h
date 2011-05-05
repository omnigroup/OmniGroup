// Copyright 1998-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSString;

extern NSString *OFCopyNumericBacktraceString(int framesToSkip);
extern NSString *OFCopySymbolicBacktrace(void);
extern NSString *OFCopySymbolicBacktraceForNumericBacktrace(NSString *numericTrace);

