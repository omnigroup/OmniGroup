// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

enum {
    OMNI_PAGE_UP_TAG, OMNI_PAGE_DOWN_TAG
};

@protocol OAPageSelectableDocument
- (void)pageUp;
- (void)pageDown;
- (void)displayPageNumber:(int)pageNumber;
@end
