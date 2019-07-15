// Copyright 1999-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectTreeNode.h>
#import <OWF/OWContentProtocol.h>
#import <os/lock.h>

@interface OWObjectTree : OWObjectTreeNode <OWContent>
{
    OWContentType *nonretainedContentType;
    OWContentInfo *contentInfo;
    os_unfair_lock mutex;
}

- initWithRepresentedObject:(id <NSObject>)object;

- (void)setContentType:(OWContentType *)aType;
- (void)setContentTypeString:(NSString *)aString;

@end

// Only for use by OWObjectTreeNode
@interface OWObjectTree (lockAccess)
- (os_unfair_lock *)mutex;
@end
