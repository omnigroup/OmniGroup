// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <objc/objc.h>

/* Most of this file is #ifdef DEBUG because you really shouldn't be putting this kind of stuff into shipping code */

/* This is a set of utilities for trapping code paths that we don't want to ever be followed.
 
 OBPatchCxxThrow() works around Radar 20746379 (libdispatch loses important information needed to fix crashes due to unhandled C++ exceptions). This is enabled in shipping code since we want to be able to fix these crashes that are otherwise nearly impossible to track down w/o reproducible steps from a user.
 
 OBPatchStretToNil() will patch the portion of objc_msgSend_stret() which handles a nil receiver. If the arg is NULL, an illegal operation trap will be inserted. Otherwise the arg is called to handle the message. OBLogStretToNil can be used to log the event and the place it was called from.
 
 OBPatchCode() is a utility used by OBPatchStretToNil() to alter executable code; it diddles the protections temporarily to allow the code to be modified. As a side effect, it COW-faults the big shared map, which I assume will have a performance impact --- I haven't measured it.
 
*/

extern BOOL OBPatchCode(void *address, size_t size, const void *newvalue);

extern BOOL OBPatchCxxThrow(void);

#ifdef DEBUG

extern BOOL OBPatchStretToNil(void (*callme)(void *, id, SEL, ...));
extern void OBLogStretToNil(void *hidden_structptr_arg, id rcvr_always_nil, SEL _cmd, ...);

#endif
