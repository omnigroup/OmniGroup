// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

#import <Foundation/Foundation.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFileExchange/OFXErrors.h>

extern NSInteger OFXSyncDebug;

#define DEBUG_SYNC(level, format, ...) do { \
    if (OFXSyncDebug >= (level)) \
        NSLog(@"SYNC %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

extern NSInteger OFXLocalRelativePathDebug;

#define DEBUG_LOCAL_RELATIVE_PATH(level, format, ...) do { \
    if (OFXLocalRelativePathDebug >= (level)) \
        NSLog(@"PATH %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

extern NSInteger OFXTransferDebug;
#define DEBUG_TRANSFER(level, format, ...) do { \
    if (OFXTransferDebug >= (level)) \
        NSLog(@"TRANSFER %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

extern NSInteger OFXMetadataDebug;
#define DEBUG_METADATA(level, format, ...) do { \
    if (OFXMetadataDebug >= (level)) \
        NSLog(@"METADATA %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

#import "OFXTrace.h"
