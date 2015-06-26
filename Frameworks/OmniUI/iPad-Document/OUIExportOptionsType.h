// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

typedef NS_ENUM(NSInteger, OUIExportOptionsType) {
    OUIExportOptionsNone, /* not used for exporting. used for getting a rough idea of how many export types are available */
    OUIExportOptionsExport,
    OUIExportOptionsEmail,
    OUIExportOptionsSendToApp,
    OUIExportOptionsSendToService,
};
