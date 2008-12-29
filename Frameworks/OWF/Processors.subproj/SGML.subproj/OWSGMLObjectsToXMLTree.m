// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSGMLObjectsToXMLTree.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWSGMLTag.h>
#import <OWF/OWSGMLTagType.h>
#import <OWF/OWObjectTree.h>
#import <OWF/OWObjectTreeNode.h>
#import <OWF/OWObjectStreamCursor.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$")

@implementation OWSGMLObjectsToXMLTree

- (void)dealloc;
{
    [root release];
    [super dealloc];
}

- (void)process
{
    id <OWSGMLToken> sgmlToken;

    while ((sgmlToken = [objectCursor readObject])) {
        switch ([sgmlToken tokenType]) {
            case OWSGMLTokenTypeStartTag:
                if (!currentNode) {
                    root = [[OWObjectTree alloc] initWithRepresentedObject:sgmlToken];
                    // should set the content type
                    [pipeline addContent:root];
                    currentNode = root;
                    break;
                }
                // fall through
            case OWSGMLTokenTypeCData:
                // TODO: Is this cast valid, i.e. is sgmlToken a valid node?
                [currentNode addChild:(id)sgmlToken];
                break;
            case OWSGMLTokenTypeEndTag:
            {
                OWSGMLTag *tag = (OWSGMLTag *)[currentNode representedObject];

                if (sgmlTagType(tag) != sgmlTagType((OWSGMLTag *)sgmlToken)) {
                    // should abort here
                } else {
                    [currentNode childrenEnd];
                    currentNode = [currentNode parent];
                }
                break;
            }
            default:
                break;
        }
    }
}

@end
