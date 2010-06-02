// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSAttributedString;
@class OAFontDescriptor;

#import <OmniFoundation/OFDataBuffer.h>

@interface OUIRTFWriter : OFObject
{
@private
    NSAttributedString *_attributedString;
    NSMutableDictionary *_registeredColors;
    NSMutableDictionary *_registeredFonts;
    OFDataBuffer *_dataBuffer;

    struct {
        struct {
            unsigned int bold:1;
            unsigned int italic:1;
        } flags;
        int fontSize;
        int fontIndex;
        int colorIndex;
        unsigned int underline;
        OAFontDescriptor *fontDescriptor;
        int alignment;
        int firstLineIndent;
        int leftIndent;
        int rightIndent;
    } _state;
}

+ (NSData *)rtfDataForAttributedString:(NSAttributedString *)attributedString;

@end
