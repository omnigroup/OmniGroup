// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPreference.h>

extern NSInteger OUIScalingTileViewDebugLayout;
#define DEBUG_TILE_LAYOUT(level, format, ...) do { \
    if (OUIScalingTileViewDebugLayout >= (level)) \
        NSLog(@"TILE LAYOUT %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

extern NSInteger OUIScalingTileViewDebugDrawing;
#define DEBUG_TILE_DRAW(level, format, ...) do { \
    if (OUIScalingTileViewDebugDrawing >= (level)) \
        NSLog(@"TILE DRAW %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)
