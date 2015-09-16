// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

typedef enum {
    OUIInspectorUpdateReasonDefault,
    OUIInspectorUpdateReasonObjectsEdited, // Due to -[OUIInspector didEndChangingInspectedObjects]. Most commonly we want to check this to avoid reloading a table view when code following -didEndChangingInspectedObjects will fix the table view.
    OUIInspectorUpdateReasonDismissed,
} OUIInspectorUpdateReason;

