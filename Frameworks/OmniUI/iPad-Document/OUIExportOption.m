// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportOption.h"

RCS_ID("$Id$");

@implementation OUIExportOption

- initWithFileType:(NSString *)fileType label:(NSString *)label image:(UIImage *)image requiresPurchase:(BOOL)requiresPurchase;
{
    self = [super init];

    _fileType = [fileType copy];
    _label = [label copy];
    _image = image;
    _requiresPurchase = requiresPurchase;
    
    return self;
}

@end
