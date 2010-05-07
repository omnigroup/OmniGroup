// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSMutableArray, NSMutableAttributedString;
@class OFStringScanner;
@class OUIRTFReaderState;

@interface OUIRTFReader : OFObject
{
@private
    NSMutableAttributedString *_attributedString;
    OFStringScanner *_scanner;
    OUIRTFReaderState *_currentState;
    NSMutableArray *_pushedStates;
    NSMutableArray *_colorTable;
    NSMutableArray *_fontTable;
    short int _colorTableRedComponent, _colorTableGreenComponent, _colorTableBlueComponent;
}

+ (NSAttributedString *)parseRTFString:(NSString *)rtfString;

@end
