// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

enum OBBacktraceBufferType {
    OBBacktraceBuffer_Unused = 0,      /* Indicates an unused slot */
    OBBacktraceBuffer_Allocated = 1,   /* Allocated but not filled slot */
    
    /* Remaining integers represent different reasons for recording a backtrace */
    OBBacktraceBuffer_OBAssertionFailure = 2,
    OBBacktraceBuffer_NSAssertionFailure = 3,
    OBBacktraceBuffer_NSException = 4,
    OBBacktraceBuffer_Generic = 5,
};

extern void OBRecordBacktrace(const char *ctxt, unsigned int optype);
/*.doc.
 Records a backtrace for possible debugging use in the future. ctxt and optype are free for the caller to use for their own purposes, but optype must be greater than one.
 */

