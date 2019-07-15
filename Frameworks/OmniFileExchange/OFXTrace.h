// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@class NSString;

// Terrible system for letting test cases check on the progress of expected work (since NSFileCoordination poking presenters can be delayed).

extern void OFXTraceReset(void);

// Counters
extern void OFXTraceSignal(NSString *name);
extern void OFXTraceWait(NSString *name);
extern NSUInteger OFXTraceSignalCount(NSString *name);
extern BOOL OFXTraceHasSignal(NSString *name);

// Accumulating arrays -- namespace is distinct from counters
extern void OFXTraceAppend(NSString *name, id object);
extern NSArray *OFXTraceCopy(NSString *name);

extern BOOL OFXTraceEnabled;

#define TRACE_SIGNAL(tag) do { \
    if (OFXTraceEnabled) \
        OFXTraceSignal(@#tag); \
} while(0)

#define TRACE_WAIT(tag) do { \
    if (OFXTraceEnabled) \
        OFXTraceWait(@#tag); \
} while(0)

#define TRACE_APPEND(tag, object) do { \
    if (OFXTraceEnabled) \
        OFXTraceAppend(@#tag, (object)); \
} while(0)
