// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPurchaseURLCommand.h>

RCS_ID("$Id$");

@implementation OUIPurchaseURLCommand

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super initWithURL:url])) {
        return nil;
    }
    
    NSString *queryString = [url query];
    _inAppPurchaseIdentifier = queryString;
    
    return self;
}

- (BOOL)skipsConfirmation;
{
    return YES;
}

- (void)invoke;
{
    OBRequestConcreteImplementation(self, _cmd); // We override this in a category
}

@end
