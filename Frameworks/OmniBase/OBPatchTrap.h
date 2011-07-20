// Copyright 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <objc/objc.h>

/* This whole file is #ifdef DEBUG because you really shouldn't be putting this kind of stuff into shipping code */
#ifdef DEBUG

/* This is a set of utilities for trapping code paths that we don't want to ever be followed.
 
 OBPatchStretToNil() will patch the portion of objc_msgSend_stret() which handles a nil receiver. If the arg is NULL, an illegal operation trap will be inserted. Otherwise the arg is called to handle the message. OBLogStretToNil can be used to log the event and the place it was called from.
 
 OBPatchCode() is a utility used by OBPatchStretToNil() to alter executable code; it diddles the protections temporarily to allow the code to be modified. As a side effect, it COW-faults the big shared map, which I assume will have a performance impact --- I haven't measured it.
 
*/

BOOL OBPatchCode(void *address, size_t size, const void *newvalue);
extern BOOL OBPatchStretToNil(void (*callme)(void *, id, SEL, ...));
void OBLogStretToNil(void *hidden_structptr_arg, id rcvr_always_nil, SEL _cmd, ...);

#endif
