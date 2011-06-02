// Copyright 2003-2005, 2007, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSImage-ColorSyncExtensions.h"
#import "OAColorProfile.h"

#import <OmniAppKit/OAFeatures.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation NSImage (ColorSyncExtensions)

- (BOOL)containsProfile;
{
    for (NSImageRep *rep in [self representations]) {
        if ([rep isKindOfClass:[NSPDFImageRep class]])
            return YES;
            
        if (![rep isKindOfClass:[NSBitmapImageRep class]])
            continue;
        return [(NSBitmapImageRep *)rep valueForProperty:NSImageColorSyncProfileData] != nil;
    }
    return NO;
}

#if OA_USE_COLOR_MANAGER
- (void)_convertUsingColorWorld:(CMWorldRef)world;
{
    for (NSImageRep *rep in [self representations]) {
        if (![rep isKindOfClass:[NSBitmapImageRep class]])
            continue;

        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)rep;
        if ([bitmap valueForProperty:NSImageColorSyncProfileData] != nil)
            return;

        OBASSERT(![bitmap isPlanar]);
        
        CMBitmap cmBitmap;
        cmBitmap.image = (void *)[bitmap bitmapData];
        cmBitmap.width = [bitmap pixelsWide];
        cmBitmap.height = [bitmap pixelsHigh];
        cmBitmap.rowBytes = [bitmap bytesPerRow];
        cmBitmap.pixelSize = [bitmap bitsPerPixel];
        if (![bitmap hasAlpha]) {
            switch([bitmap bitsPerSample]) {
            case 5:
                cmBitmap.space = cmRGB16Space; break;
            case 8:
                cmBitmap.space = [bitmap bitsPerPixel] == 24 ? cmRGB24Space : cmRGB32Space; break;
            default:
                OBASSERT_NOT_REACHED("don't know how to support this sample size");
            }
        } else {
            OBASSERT([bitmap bitsPerSample] == 8);
            cmBitmap.space = cmRGBA32PmulSpace;
        }
        cmBitmap.user1 = 0;
        cmBitmap.user2 = 0;

        CWMatchBitmap(world, &cmBitmap, NULL, NULL, NULL);//&cmNewBitmap);
        break;
    }
}
#endif

- (void)convertFromProfile:(OAColorProfile *)inProfile toProfile:(OAColorProfile *)outProfile;
{
#if OA_USE_COLOR_MANAGER
    CMWorldRef world = [inProfile _rgbConversionWorldForOutput:outProfile];
    
    if (!world)
        return;
    [self _convertUsingColorWorld:world];
#else
    OBFinishPorting;
#endif
}

@end

