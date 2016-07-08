// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSImage-ColorSyncExtensions.h>
#import <OmniAppKit/OAColorProfile.h>

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

- (void)_convertUsingColorWorld:(ColorSyncTransformRef)world;
{
    for (NSImageRep *rep in [self representations]) {
        if (![rep isKindOfClass:[NSBitmapImageRep class]])
            continue;

        NSBitmapImageRep *bitmap = (NSBitmapImageRep *)rep;
        if ([bitmap valueForProperty:NSImageColorSyncProfileData] != nil)
            return;

        OBASSERT(![bitmap isPlanar]);


        //FIXME: this is an ugly hack to make it work similar to the old ColorSync APIs.
        ColorSyncDataDepth aDepth;
        ColorSyncDataLayout layout = kColorSyncAlphaLast | kColorSyncByteOrderDefault;
        if (![bitmap hasAlpha]) {
            layout = kColorSyncAlphaNone | kColorSyncByteOrderDefault;
            switch([bitmap bitsPerSample]) {
                case 5:
                    aDepth = kColorSync16BitInteger; break;
                case 8:
                    aDepth = kColorSync32BitInteger;
                    if ([bitmap bitsPerPixel] == 24) {
                        layout = kColorSyncAlphaNone | kColorSyncByteOrderDefault;
                    } else {
                        layout = kColorSyncAlphaNoneSkipLast | kColorSyncByteOrderDefault;
                    }
                    break;
                default:
                    OBASSERT_NOT_REACHED("don't know how to support this sample size");
                    continue;
            }
        } else {
            OBASSERT([bitmap bitsPerSample] == 8);
            layout = kColorSyncAlphaLast | kColorSyncByteOrderDefault;
            aDepth = kColorSync32BitInteger;
        }

        ColorSyncTransformConvert(world, [bitmap pixelsWide], [bitmap pixelsHigh], [bitmap bitmapData], aDepth, layout, [bitmap bytesPerRow], [bitmap bitmapData], aDepth, layout, [bitmap bytesPerRow], nil);
        break;
    }
}

- (void)convertFromProfile:(OAColorProfile *)inProfile toProfile:(OAColorProfile *)outProfile;
{
    ColorSyncTransformRef world = [inProfile _rgbConversionWorldForOutput:outProfile];
    
    if (!world)
        return;
    [self _convertUsingColorWorld:world];
}

@end

