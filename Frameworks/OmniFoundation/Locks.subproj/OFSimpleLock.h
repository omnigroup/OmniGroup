// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#ifdef __ppc__
#import <OmniFoundation/OFSimpleLock-ppc.h>
#endif

#if defined(__i386__) || defined(__x86_64__) || defined(__amd64__)
#import <OmniFoundation/OFSimpleLock-i386.h>
#endif

#ifdef __sparc__
#import <OmniFoundation/OFSimpleLock-sparc.h>
#endif

#ifdef __hppa__
#import <OmniFoundation/OFSimpleLock-hppa.h>
#endif


#ifndef OFSimpleLockDefined
#import <OmniFoundation/OFSimpleLock-pthreads.h>
#endif
