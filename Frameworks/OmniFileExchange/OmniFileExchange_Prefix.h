// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniFileExchange/OFXErrors.h>

OB_HIDDEN extern NSInteger OFXFileCoordinatonDebug;
#define DEBUG_FILE_COORDINATION(level, format, ...) do { \
    if (OFXFileCoordinatonDebug >= (level)) \
        NSLog(@"FILE COORD %@ <%llu>: " format, [self shortDescription], _filePresenterNotifications, ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXSyncDebug;
#define DEBUG_SYNC(level, format, ...) do { \
    if (OFXSyncDebug >= (level)) \
        NSLog(@"SYNC %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXScanDebug;
#define DEBUG_SCAN(level, format, ...) do { \
    if (OFXScanDebug >= (level)) \
        NSLog(@"SCAN %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXLocalRelativePathDebug;
#define DEBUG_LOCAL_RELATIVE_PATH(level, format, ...) do { \
    if (OFXLocalRelativePathDebug >= (level)) \
        NSLog(@"PATH %@: " format, [self debugName], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXTransferDebug;
#define DEBUG_TRANSFER(level, format, ...) do { \
    if (OFXTransferDebug >= (level)) \
        NSLog(@"TRANSFER %@ %@: " format, [self debugName], [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXConflictDebug;
#define DEBUG_CONFLICT(level, format, ...) do { \
    if (OFXConflictDebug >= (level)) \
        NSLog(@"CONFLICT %@ %@: " format, [self debugName], [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXMetadataDebug;
#define DEBUG_METADATA(level, format, ...) do { \
    if (OFXMetadataDebug >= (level)) \
        NSLog(@"METADATA %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXContentDebug;
#define DEBUG_CONTENT(level, format, ...) do { \
    if (OFXContentDebug >= (level)) \
        NSLog(@"CONTENT %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXActivityDebug;
#define DEBUG_ACTIVITY(level, format, ...) do { \
    if (OFXActivityDebug >= (level)) \
        NSLog(@"ACTIVITY %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OFXAccountRemovalDebug;
#define DEBUG_ACCOUNT_REMOVAL(level, format, ...) do { \
    if (OFXAccountRemovalDebug >= (level)) \
        NSLog(@"ACCOUNT REMOVAL %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

#import "OFXTrace.h"
